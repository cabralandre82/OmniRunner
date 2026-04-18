import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";

/**
 * /api/consent — L04-03 LGPD Art. 7/8 consent management
 *
 * Rotas:
 *   POST  /api/consent  body { action, consent_type, version? }
 *     - action: "grant" | "revoke" | "status"
 *   GET   /api/consent  → fn_consent_status() (atalho para UI)
 *
 * Source-of-truth: supabase `consent_events` + RPCs (fn_consent_grant,
 * fn_consent_revoke, fn_consent_status). Este endpoint é apenas um thin
 * wrapper que injeta IP/User-Agent vindos do cliente (portal web).
 */

const VALID_TYPES_LIST = [
  "terms",
  "privacy",
  "health_data",
  "location_tracking",
  "marketing",
  "third_party_strava",
  "third_party_trainingpeaks",
  "coach_data_share",
] as const;
const VALID_TYPES = new Set<string>(VALID_TYPES_LIST);

const VALID_ACTIONS = new Set(["grant", "revoke", "status"]);

function getClientIp(req: NextRequest): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0]?.trim() || null;
  return req.headers.get("x-real-ip") || null;
}

export async function GET() {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { data, error } = await supabase.rpc("fn_consent_status");
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ ok: true, status: data ?? [] });
}

export async function POST(request: NextRequest) {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const action = String(body.action ?? "").toLowerCase();
  if (!VALID_ACTIONS.has(action)) {
    return NextResponse.json(
      { error: "action must be grant, revoke or status" },
      { status: 400 },
    );
  }

  const requestId = randomUUID();

  if (action === "status") {
    const { data, error } = await supabase.rpc("fn_consent_status");
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    return NextResponse.json({ ok: true, status: data ?? [] });
  }

  const consentType = String(body.consent_type ?? "");
  if (!VALID_TYPES.has(consentType)) {
    return NextResponse.json(
      { error: `consent_type must be one of ${VALID_TYPES_LIST.join(", ")}` },
      { status: 400 },
    );
  }

  if (action === "grant") {
    const version = String(body.version ?? "").trim();
    if (!version) {
      return NextResponse.json(
        { error: "version required for grant" },
        { status: 400 },
      );
    }
    const { data, error } = await supabase.rpc("fn_consent_grant", {
      p_consent_type: consentType,
      p_version: version,
      p_source: "portal",
      p_ip: getClientIp(request),
      p_user_agent: request.headers.get("user-agent"),
      p_request_id: requestId,
    });
    if (error) {
      const code = error.code === "P0004" ? 403 : error.code === "P0001" ? 400 : 500;
      return NextResponse.json({ error: error.message }, { status: code });
    }
    return NextResponse.json({ ok: true, result: data });
  }

  // revoke
  const { data, error } = await supabase.rpc("fn_consent_revoke", {
    p_consent_type: consentType,
    p_source: "portal",
    p_request_id: requestId,
  });
  if (error) {
    const code = error.code === "P0004" ? 403 : error.code === "P0001" ? 400 : 500;
    return NextResponse.json({ error: error.message }, { status: code });
  }
  return NextResponse.json({ ok: true, result: data });
}
