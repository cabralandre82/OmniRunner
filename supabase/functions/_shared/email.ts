/**
 * L15-04 — Transactional Email Platform (shared module)
 *
 * This module is the canonical way for Edge Functions to send transactional
 * email. Callers never talk to Resend/SendGrid/Postmark/Inbucket directly;
 * they go through `sendEmail()` which:
 *
 *   1. Resolves the template from the manifest (compile-time bundled).
 *   2. Enforces that every required_var is present in `vars`.
 *   3. Renders the subject + body with HTML-escaped interpolation of `vars`.
 *   4. Dispatches to the provider selected by `EMAIL_PROVIDER` env.
 *   5. Returns a stable `SendEmailResult` the caller can feed into
 *      `public.fn_mark_email_sent` / `public.fn_mark_email_failed`.
 *
 * Providers
 * ─────────
 *   EMAIL_PROVIDER = 'resend'    — POST https://api.resend.com/emails
 *                                   with Authorization: Bearer RESEND_API_KEY
 *   EMAIL_PROVIDER = 'inbucket'  — local dev; talks to Supabase inbucket on
 *                                   http://inbucket:54324 (no auth; drops
 *                                   emails into the in-memory web UI)
 *   EMAIL_PROVIDER = 'null'      — no-op; returns a fabricated message id
 *                                   (used by CI/sandbox where outbound HTTP
 *                                   is unsafe)
 *
 *   The default when EMAIL_PROVIDER is unset is 'null' — forcing operators
 *   to OPT IN to real outbound dispatch. This matches the rest of our
 *   "fail-closed" posture (see L10-07, L10-09).
 *
 * Security
 * ────────
 *   • `vars` values are always HTML-escaped before interpolation. A hostile
 *     `group_name` containing `<img src=x onerror=...>` lands in the body
 *     as inert entities. The escape set covers &, <, >, ", ', /.
 *   • `from_name` / `category` come from the manifest, never from callers.
 *   • `recipient_email` is validated with the same regex enforced by the
 *     `email_outbox_recipient_email_check` CHECK constraint.
 */

// The manifest is a JSON file co-located with the templates; we ship a
// typed representation here so Edge Functions can import it without Deno
// JSON-module experimental flags. Keep `TEMPLATE_MANIFEST` in sync with
// `supabase/email-templates/manifest.json` — the CI guard
// `audit:email-platform` enforces this.

export type EmailTemplateKey =
  | "coaching_group_invite"
  | "championship_invite"
  | "weekly_training_summary"
  | "payment_confirmation";

export interface EmailTemplateDef {
  subject: string;
  file: string;
  required_vars: readonly string[];
  from_name: string;
  category: "transactional";
  description: string;
}

export const TEMPLATE_MANIFEST: Readonly<
  Record<EmailTemplateKey, EmailTemplateDef>
> = Object.freeze({
  coaching_group_invite: {
    subject: "Você foi convidado para {{group_name}}",
    file: "coaching_group_invite.html",
    required_vars: [
      "recipient_name",
      "group_name",
      "coach_name",
      "invite_link",
      "expire_date",
    ] as const,
    from_name: "OmniRunner",
    category: "transactional",
    description: "Coaching group invitation",
  },
  championship_invite: {
    subject:
      "{{host_group_name}} convidou sua assessoria para o campeonato {{championship_name}}",
    file: "championship_invite.html",
    required_vars: [
      "staff_name",
      "host_group_name",
      "championship_name",
      "invite_link",
      "start_date",
    ] as const,
    from_name: "OmniRunner",
    category: "transactional",
    description: "Championship invite",
  },
  weekly_training_summary: {
    subject: "Resumo semanal — {{group_name}}",
    file: "weekly_training_summary.html",
    required_vars: [
      "athlete_name",
      "group_name",
      "sessions_completed",
      "sessions_total",
      "total_km",
      "streak_days",
      "dashboard_link",
    ] as const,
    from_name: "OmniRunner",
    category: "transactional",
    description: "Weekly Monday digest",
  },
  payment_confirmation: {
    subject: "Pagamento confirmado — R$ {{amount}}",
    file: "payment_confirmation.html",
    required_vars: [
      "user_name",
      "amount",
      "description",
      "receipt_link",
    ] as const,
    from_name: "OmniRunner",
    category: "transactional",
    description: "Payment confirmation receipt",
  },
});

export interface EmailMessage {
  to: string;
  templateKey: EmailTemplateKey;
  vars: Record<string, string>;
  subject?: string;
  fromAddress?: string;
}

export interface SendEmailResult {
  status: "sent" | "failed";
  provider: EmailProviderName;
  providerMessageId: string | null;
  error?: {
    message: string;
    terminal: boolean;
  };
}

export type EmailProviderName = "resend" | "inbucket" | "null";

const EMAIL_REGEX =
  /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const HTML_ESCAPE_RE = /[&<>"'/]/g;
const HTML_ESCAPE_MAP: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
  "/": "&#x2F;",
};

export function escapeHtml(input: unknown): string {
  if (input === null || input === undefined) return "";
  const s = String(input);
  return s.replace(HTML_ESCAPE_RE, (ch) => HTML_ESCAPE_MAP[ch] ?? ch);
}

const PLACEHOLDER_RE = /{{\s*([a-zA-Z0-9_]+)\s*}}/g;

/**
 * Render a template body or subject by substituting `{{var}}` placeholders
 * with HTML-escaped values from `vars`. Missing keys render as the empty
 * string and are reported via `options.onMissing` (so the caller can
 * upgrade to a hard error). The escape mode can be turned off for the
 * subject line (which is not HTML) via `options.escape = false`.
 */
export function renderTemplate(
  body: string,
  vars: Record<string, string>,
  options: { escape?: boolean; onMissing?: (name: string) => void } = {},
): string {
  const escape = options.escape !== false;
  const onMissing = options.onMissing;
  return body.replace(PLACEHOLDER_RE, (_, name: string) => {
    const raw = Object.prototype.hasOwnProperty.call(vars, name)
      ? vars[name]
      : undefined;
    if (raw === undefined) {
      onMissing?.(name);
      return "";
    }
    return escape ? escapeHtml(raw) : String(raw);
  });
}

export function validateEmailAddress(email: string): boolean {
  if (typeof email !== "string") return false;
  const trimmed = email.trim();
  if (trimmed.length === 0 || trimmed.length > 254) return false;
  return EMAIL_REGEX.test(trimmed);
}

/**
 * Assert that every required variable for a template is present in the
 * caller-provided vars map. Throws a tagged error (reason=missing_vars)
 * with the list of missing keys.
 */
export function assertRequiredVars(
  templateKey: EmailTemplateKey,
  vars: Record<string, string>,
): void {
  const def = TEMPLATE_MANIFEST[templateKey];
  if (!def) {
    throw new EmailError(
      "unknown_template",
      `template '${templateKey}' not registered in manifest`,
      true,
    );
  }
  const missing: string[] = [];
  for (const name of def.required_vars) {
    const v = vars[name];
    if (v === undefined || v === null || (typeof v === "string" && v.length === 0)) {
      missing.push(name);
    }
  }
  if (missing.length > 0) {
    throw new EmailError(
      "missing_vars",
      `template '${templateKey}' requires vars: ${missing.join(", ")}`,
      true,
    );
  }
}

export class EmailError extends Error {
  readonly reason: string;
  readonly terminal: boolean;
  constructor(reason: string, message: string, terminal: boolean) {
    super(message);
    this.name = "EmailError";
    this.reason = reason;
    this.terminal = terminal;
  }
}

// ───────────────────────── provider abstraction ─────────────────────────

export interface EmailProvider {
  readonly name: EmailProviderName;
  send(msg: RenderedEmail): Promise<ProviderDispatchResult>;
}

export interface RenderedEmail {
  to: string;
  from: string;
  fromName: string;
  subject: string;
  html: string;
  templateKey: EmailTemplateKey;
}

export interface ProviderDispatchResult {
  providerMessageId: string | null;
}

function requireEnv(name: string): string {
  const v = (globalThis as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env.get(name);
  if (!v || v.length === 0) {
    throw new EmailError(
      "missing_env",
      `env var ${name} is not set`,
      true,
    );
  }
  return v;
}

function optionalEnv(name: string, fallback: string): string {
  const v = (globalThis as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env.get(name);
  return v && v.length > 0 ? v : fallback;
}

export class ResendProvider implements EmailProvider {
  readonly name = "resend" as const;
  async send(msg: RenderedEmail): Promise<ProviderDispatchResult> {
    const apiKey = requireEnv("RESEND_API_KEY");
    const endpoint = optionalEnv("RESEND_ENDPOINT", "https://api.resend.com/emails");

    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 15_000);
    let res: Response;
    try {
      res = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: `${msg.fromName} <${msg.from}>`,
          to: [msg.to],
          subject: msg.subject,
          html: msg.html,
          tags: [
            { name: "template", value: msg.templateKey },
            { name: "platform", value: "omnirunner" },
          ],
        }),
        signal: ctrl.signal,
      });
    } finally {
      clearTimeout(timer);
    }
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const terminal = res.status >= 400 && res.status < 500 && res.status !== 429;
      throw new EmailError(
        terminal ? "provider_4xx" : "provider_5xx",
        `resend HTTP ${res.status}: ${body.slice(0, 500)}`,
        terminal,
      );
    }
    const data = (await res.json().catch(() => ({}))) as { id?: string };
    return { providerMessageId: data.id ?? null };
  }
}

/**
 * Dev-only provider that speaks SMTP via the Supabase inbucket container.
 * We short-circuit to a local HTTP admin endpoint exposed by inbucket when
 * running `supabase start` — inbucket accepts messages via its web UI but
 * for Deno edge functions we use its SMTP bridge via the `INBUCKET_URL`
 * env (defaults to http://inbucket:54324). If unreachable, we simulate a
 * successful send so local dev doesn't fail when the container is off.
 */
export class InbucketProvider implements EmailProvider {
  readonly name = "inbucket" as const;
  async send(msg: RenderedEmail): Promise<ProviderDispatchResult> {
    const base = optionalEnv("INBUCKET_URL", "http://127.0.0.1:54324");
    const endpoint = `${base.replace(/\/$/, "")}/__omni/email`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 5_000);
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          from: `${msg.fromName} <${msg.from}>`,
          to: msg.to,
          subject: msg.subject,
          html: msg.html,
          template: msg.templateKey,
        }),
        signal: ctrl.signal,
      });
      if (!res.ok) {
        return { providerMessageId: `inbucket-sim-${crypto.randomUUID()}` };
      }
      const data = (await res.json().catch(() => ({}))) as { id?: string };
      return { providerMessageId: data.id ?? `inbucket-${crypto.randomUUID()}` };
    } catch {
      return { providerMessageId: `inbucket-sim-${crypto.randomUUID()}` };
    } finally {
      clearTimeout(timer);
    }
  }
}

/**
 * No-op provider used by CI and sandbox. Never touches the network; always
 * returns a fabricated id. Calling `send()` is effectively a "delivery
 * simulator" that records the email state in the outbox but skips the
 * external call. This is the DEFAULT when EMAIL_PROVIDER is unset.
 */
export class NullProvider implements EmailProvider {
  readonly name = "null" as const;
  send(_msg: RenderedEmail): Promise<ProviderDispatchResult> {
    return Promise.resolve({
      providerMessageId: `null-${crypto.randomUUID()}`,
    });
  }
}

export function resolveProvider(override?: EmailProviderName): EmailProvider {
  const raw = override ?? optionalEnv("EMAIL_PROVIDER", "null");
  const name = raw.toLowerCase() as EmailProviderName;
  switch (name) {
    case "resend":
      return new ResendProvider();
    case "inbucket":
      return new InbucketProvider();
    case "null":
      return new NullProvider();
    default:
      throw new EmailError(
        "unknown_provider",
        `EMAIL_PROVIDER='${raw}' is not one of: resend, inbucket, null`,
        true,
      );
  }
}

// ────────────────────────── template store ──────────────────────────

export interface TemplateLoader {
  load(file: string): Promise<string>;
}

/**
 * Default loader: reads `supabase/email-templates/<file>` from disk via
 * Deno.readTextFile. Edge functions that bundle templates can pass a
 * custom loader (e.g. pre-built map); tests pass an InMemoryLoader.
 */
export class FsTemplateLoader implements TemplateLoader {
  private readonly root: string;
  constructor(root?: string) {
    this.root = root ?? optionalEnv(
      "EMAIL_TEMPLATES_DIR",
      "supabase/email-templates",
    );
  }
  async load(file: string): Promise<string> {
    const deno = (globalThis as { Deno?: { readTextFile(path: string): Promise<string> } }).Deno;
    if (!deno) {
      throw new EmailError(
        "template_loader_unavailable",
        "Deno.readTextFile is not available in this runtime",
        true,
      );
    }
    const path = `${this.root.replace(/\/$/, "")}/${file}`;
    try {
      return await deno.readTextFile(path);
    } catch (err) {
      throw new EmailError(
        "template_not_found",
        `could not read template '${file}' at ${path}: ${(err as Error).message}`,
        true,
      );
    }
  }
}

export class InMemoryLoader implements TemplateLoader {
  private readonly map: Map<string, string>;
  constructor(entries: Record<string, string>) {
    this.map = new Map(Object.entries(entries));
  }
  load(file: string): Promise<string> {
    const body = this.map.get(file);
    if (body === undefined) {
      return Promise.reject(
        new EmailError("template_not_found", `in-memory loader missing '${file}'`, true),
      );
    }
    return Promise.resolve(body);
  }
}

// ───────────────────────────── dispatcher ─────────────────────────────

export interface SendEmailOptions {
  provider?: EmailProvider;
  loader?: TemplateLoader;
  fromAddress?: string;
}

const DEFAULT_FROM_ADDRESS = "no-reply@omnirunner.app";

/**
 * High-level entrypoint used by Edge Functions. Validates input, renders
 * subject + body, dispatches to provider, and returns a summary the caller
 * can persist via fn_mark_email_sent / fn_mark_email_failed.
 *
 * This function does NOT write to email_outbox on its own — callers are
 * responsible for calling `fn_enqueue_email` before, and marking the
 * terminal transition after. This separation keeps the provider path free
 * from DB concerns (no service-role client is needed here).
 */
export async function sendEmail(
  msg: EmailMessage,
  options: SendEmailOptions = {},
): Promise<SendEmailResult> {
  if (!validateEmailAddress(msg.to)) {
    return {
      status: "failed",
      provider: "null",
      providerMessageId: null,
      error: {
        message: `invalid recipient address: '${msg.to}'`,
        terminal: true,
      },
    };
  }

  const def = TEMPLATE_MANIFEST[msg.templateKey];
  if (!def) {
    return {
      status: "failed",
      provider: "null",
      providerMessageId: null,
      error: {
        message: `unknown template '${msg.templateKey}'`,
        terminal: true,
      },
    };
  }

  try {
    assertRequiredVars(msg.templateKey, msg.vars);
  } catch (err) {
    const e = err as EmailError;
    return {
      status: "failed",
      provider: "null",
      providerMessageId: null,
      error: { message: e.message, terminal: e.terminal },
    };
  }

  const loader = options.loader ?? new FsTemplateLoader();
  const provider = options.provider ?? resolveProvider();

  let htmlBody: string;
  try {
    htmlBody = await loader.load(def.file);
  } catch (err) {
    const e = err as EmailError;
    return {
      status: "failed",
      provider: provider.name,
      providerMessageId: null,
      error: { message: e.message, terminal: true },
    };
  }

  const subject = msg.subject ?? renderTemplate(def.subject, msg.vars, { escape: false });
  const html = renderTemplate(htmlBody, msg.vars, { escape: true });

  try {
    const dispatch = await provider.send({
      to: msg.to,
      from: msg.fromAddress ?? options.fromAddress ?? DEFAULT_FROM_ADDRESS,
      fromName: def.from_name,
      subject,
      html,
      templateKey: msg.templateKey,
    });
    return {
      status: "sent",
      provider: provider.name,
      providerMessageId: dispatch.providerMessageId,
    };
  } catch (err) {
    const e = err instanceof EmailError
      ? err
      : new EmailError("dispatch_failed", (err as Error).message ?? String(err), false);
    return {
      status: "failed",
      provider: provider.name,
      providerMessageId: null,
      error: { message: e.message, terminal: e.terminal },
    };
  }
}
