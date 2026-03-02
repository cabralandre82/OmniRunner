/**
 * CSRF protection via Origin/Referer header validation for mutating API routes.
 *
 * Follows the "double-submit" approach: for POST/PUT/PATCH/DELETE,
 * verifies that the Origin header matches the expected host.
 */

import { type NextRequest, NextResponse } from "next/server";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export function csrfCheck(request: NextRequest): NextResponse | null {
  if (SAFE_METHODS.has(request.method)) return null;

  const origin = request.headers.get("origin");
  const referer = request.headers.get("referer");
  const host = request.headers.get("host");

  if (!host) {
    return NextResponse.json({ error: "Missing host header" }, { status: 400 });
  }

  const trusted = origin
    ? new URL(origin).host === host
    : referer
      ? new URL(referer).host === host
      : false;

  if (!trusted) {
    return NextResponse.json({ error: "CSRF validation failed" }, { status: 403 });
  }

  return null;
}
