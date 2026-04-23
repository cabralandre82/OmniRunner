import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import {
  sendEmail,
  TEMPLATE_MANIFEST,
  type EmailTemplateKey,
  validateEmailAddress,
} from "../_shared/email.ts";

/**
 * send-email — Supabase Edge Function (L15-04)
 *
 * Sends transactional emails via the canonical pipeline:
 *   1. caller POSTs { recipient_email, recipient_user_id?, template_key,
 *                     template_vars, idempotency_key }
 *   2. we call fn_enqueue_email → get outbox row id (dedup on key)
 *   3. render + dispatch via the configured provider (EMAIL_PROVIDER env)
 *   4. fn_mark_email_sent / fn_mark_email_failed on terminal outcome
 *
 * Service-role only. Not exposed to end-user clients.
 *
 * POST /send-email
 * Body: {
 *   recipient_email: string,
 *   recipient_user_id?: string (uuid),
 *   template_key: EmailTemplateKey,
 *   template_vars: Record<string, string>,
 *   idempotency_key: string
 * }
 *
 * Response: {
 *   outbox_id: string,
 *   status: 'sent' | 'failed' | 'already_sent',
 *   provider: 'resend' | 'inbucket' | 'null',
 *   provider_message_id: string | null
 * }
 */

const FN = "send-email";

interface SendEmailBody {
  recipient_email?: string;
  recipient_user_id?: string | null;
  template_key?: string;
  template_vars?: Record<string, string>;
  idempotency_key?: string;
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === "GET" && new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", version: "1.0.0", fn: FN }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!serviceKey || !supabaseUrl) {
      status = 500;
      errorCode = "CONFIG_ERROR";
      return jsonErr(500, "CONFIG_ERROR", "Server misconfiguration", requestId);
    }
    const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
    if (bearer !== serviceKey) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Service-role only", requestId);
    }

    let body: SendEmailBody;
    try {
      body = await req.json();
    } catch {
      status = 400;
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    const recipient = body.recipient_email?.trim();
    const templateKey = body.template_key;
    const vars = body.template_vars ?? {};
    const idempotencyKey = body.idempotency_key;
    const recipientUserId = body.recipient_user_id ?? null;

    if (!recipient || !validateEmailAddress(recipient)) {
      status = 422;
      return jsonErr(422, "INVALID_RECIPIENT", "recipient_email must be a valid address", requestId);
    }
    if (!templateKey || !(templateKey in TEMPLATE_MANIFEST)) {
      status = 422;
      return jsonErr(
        422,
        "UNKNOWN_TEMPLATE",
        `template_key must be one of: ${Object.keys(TEMPLATE_MANIFEST).join(", ")}`,
        requestId,
      );
    }
    if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 256) {
      status = 422;
      return jsonErr(
        422,
        "INVALID_IDEMPOTENCY_KEY",
        "idempotency_key must be between 8 and 256 chars",
        requestId,
      );
    }
    if (typeof vars !== "object" || Array.isArray(vars) || vars === null) {
      status = 422;
      return jsonErr(422, "INVALID_VARS", "template_vars must be an object", requestId);
    }

    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const def = TEMPLATE_MANIFEST[templateKey as EmailTemplateKey];
    const subjectPreview = def.subject.replace(/{{\s*([a-zA-Z0-9_]+)\s*}}/g, (_, n: string) =>
      String(vars[n] ?? ""),
    ).slice(0, 998);

    // ── 1. Enqueue ────────────────────────────────────────────────
    const { data: enq, error: enqErr } = await db.rpc("fn_enqueue_email", {
      p_recipient_email: recipient,
      p_recipient_user_id: recipientUserId,
      p_template_key: templateKey,
      p_subject: subjectPreview || def.subject,
      p_template_vars: vars,
      p_idempotency_key: idempotencyKey,
    });
    if (enqErr || !enq) {
      status = 500;
      errorCode = "ENQUEUE_FAILED";
      return jsonErr(500, "ENQUEUE_FAILED", enqErr?.message ?? "fn_enqueue_email returned no id", requestId);
    }
    const outboxId = enq as string;

    // Check current status — if already sent we short-circuit (returning
    // a cached result). This is the guarantee that made idempotency_key
    // unique in the first place.
    const { data: existing } = await db
      .from("email_outbox")
      .select("status, provider, provider_message_id")
      .eq("id", outboxId)
      .maybeSingle();

    if (existing?.status === "sent") {
      return jsonOk({
        outbox_id: outboxId,
        status: "already_sent",
        provider: existing.provider,
        provider_message_id: existing.provider_message_id,
      }, requestId);
    }

    // ── 2. Dispatch via provider ──────────────────────────────────
    const result = await sendEmail({
      to: recipient,
      templateKey: templateKey as EmailTemplateKey,
      vars,
    });

    // ── 3. Mark terminal outcome ──────────────────────────────────
    if (result.status === "sent") {
      const { error: markErr } = await db.rpc("fn_mark_email_sent", {
        p_id: outboxId,
        p_provider: result.provider,
        p_provider_message_id: result.providerMessageId,
      });
      if (markErr) {
        errorCode = "MARK_SENT_FAILED";
        // Don't leak this as a delivery failure — the email DID ship; the
        // DB bookkeeping just hiccuped. Retry on the DB side.
        return jsonOk({
          outbox_id: outboxId,
          status: "sent",
          provider: result.provider,
          provider_message_id: result.providerMessageId,
          warning: "persist_after_send_failed",
        }, requestId);
      }
      return jsonOk({
        outbox_id: outboxId,
        status: "sent",
        provider: result.provider,
        provider_message_id: result.providerMessageId,
      }, requestId);
    }

    // failure path
    const err = result.error ?? { message: "unknown_error", terminal: false };
    await db.rpc("fn_mark_email_failed", {
      p_id: outboxId,
      p_error: err.message,
      p_terminal: err.terminal,
    });
    status = err.terminal ? 422 : 502;
    errorCode = err.terminal ? "PROVIDER_REJECTED" : "PROVIDER_FAILED";
    return jsonErr(status, errorCode, err.message, requestId);
  } catch (err) {
    status = 500;
    errorCode = "INTERNAL";
    const m = err instanceof Error ? err.message : "unknown";
    return jsonErr(500, "INTERNAL", m, requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: null, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: null, status, duration_ms: elapsed() });
    }
  }
});
