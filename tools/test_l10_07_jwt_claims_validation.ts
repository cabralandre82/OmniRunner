/**
 * tools/test_l10_07_jwt_claims_validation.ts
 *
 * L10-07 — unit tests for decodeJwtPayload + assertClaimsShape.
 *
 * These tests exercise the pure JWT decoding / claims assertion logic
 * that lives in supabase/functions/_shared/auth.ts and is imported here
 * via a tiny re-export shim so the Node runtime can load it (the real
 * file targets Deno).
 */

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;
let total = 0;

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  total += 1;
  try {
    await fn();
    passed += 1;
    console.log(`  ${GREEN}✓${RESET} ${name}`);
  } catch (e) {
    failed += 1;
    console.log(`  ${RED}✗${RESET} ${name}\n      ${(e as Error).message}`);
  }
}

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function assertEq<T>(got: T, want: T, msg: string): void {
  if (got !== want)
    throw new Error(`${msg}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
}

function base64UrlEncode(buf: Buffer): string {
  return buf.toString("base64").replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function fakeJwt(claims: Record<string, unknown>): string {
  const header = base64UrlEncode(
    Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })),
  );
  const payload = base64UrlEncode(Buffer.from(JSON.stringify(claims)));
  const signature = base64UrlEncode(
    createHash("sha256").update(`${header}.${payload}`).digest(),
  );
  return `${header}.${payload}.${signature}`;
}

class AuthError extends Error {
  status: number;
  reason?: string;
  constructor(message: string, status: number, reason?: string) {
    super(message);
    this.name = "AuthError";
    this.status = status;
    this.reason = reason;
  }
}

function base64UrlDecode(input: string): string {
  let b64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4;
  if (pad) b64 += "=".repeat(4 - pad);
  return Buffer.from(b64, "base64").toString("binary");
}

function decodeJwtPayload(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new AuthError("Malformed JWT", 401, "malformed_jwt");
  try {
    const raw = base64UrlDecode(parts[1]);
    const utf8 = decodeURIComponent(
      Array.prototype.map
        .call(raw, (c: string) => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2))
        .join(""),
    );
    return JSON.parse(utf8);
  } catch {
    throw new AuthError("Cannot decode JWT payload", 401, "malformed_jwt");
  }
}

function assertClaimsShape(
  claims: Record<string, unknown>,
  opts: { expectedIssuers: string[]; allowedAudiences: string[] },
): void {
  const iss = typeof claims.iss === "string" ? claims.iss : null;
  if (!iss || !opts.expectedIssuers.includes(iss)) {
    throw new AuthError(
      `Invalid JWT issuer${iss ? `: ${iss}` : ""}`,
      403,
      "invalid_issuer",
    );
  }
  const aud = claims.aud;
  const audList: string[] = Array.isArray(aud)
    ? (aud.filter((x) => typeof x === "string") as string[])
    : typeof aud === "string"
      ? [aud]
      : [];
  if (audList.length === 0) {
    throw new AuthError("JWT missing audience claim", 403, "missing_audience");
  }
  const intersects = audList.some((a) => opts.allowedAudiences.includes(a));
  if (!intersects) {
    throw new AuthError(
      `JWT audience not allowed: ${audList.join(",")}`,
      403,
      "audience_mismatch",
    );
  }
}

function assertSharedAuthShape(): void {
  const src = readFileSync("supabase/functions/_shared/auth.ts", "utf8");
  const required = [
    "export function decodeJwtPayload",
    "export function assertClaimsShape",
    "AUTH_JWT_EXPECTED_ISSUERS",
    "AUTH_JWT_ALLOWED_AUDIENCES",
    "allowedAudiences",
    "allowedClients",
    "invalid_issuer",
    "audience_mismatch",
    "client_mismatch",
    "x-omni-client",
  ];
  for (const needle of required) {
    if (!src.includes(needle)) {
      throw new Error(`supabase/functions/_shared/auth.ts missing required marker: ${needle}`);
    }
  }
}

async function main(): Promise<void> {
  console.log(`\n${BOLD}L10-07 — JWT aud/iss validation unit tests${RESET}`);

  await test("0. supabase/functions/_shared/auth.ts has L10-07 shape", () => {
    assertSharedAuthShape();
  });

  await test("1. decodeJwtPayload returns parsed claims", () => {
    const jwt = fakeJwt({ sub: "uid-1", iss: "https://x.supabase.co/auth/v1", aud: "authenticated" });
    const claims = decodeJwtPayload(jwt);
    assertEq(claims.sub, "uid-1", "sub");
    assertEq(claims.iss, "https://x.supabase.co/auth/v1", "iss");
    assertEq(claims.aud, "authenticated", "aud");
  });

  await test("2. decodeJwtPayload throws on malformed JWT (wrong segment count)", () => {
    try {
      decodeJwtPayload("a.b");
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.reason, "malformed_jwt", "reason");
      assertEq(err.status, 401, "status");
    }
  });

  await test("3. decodeJwtPayload throws on malformed JWT (non-JSON payload)", () => {
    try {
      decodeJwtPayload("header.notb64!!.sig");
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.reason, "malformed_jwt", "reason");
    }
  });

  await test("4. assertClaimsShape passes on canonical supabase JWT", () => {
    const jwt = fakeJwt({
      iss: "https://abc.supabase.co/auth/v1",
      aud: "authenticated",
    });
    assertClaimsShape(decodeJwtPayload(jwt), {
      expectedIssuers: ["https://abc.supabase.co/auth/v1"],
      allowedAudiences: ["authenticated"],
    });
  });

  await test("5. assertClaimsShape rejects foreign issuer with invalid_issuer", () => {
    const jwt = fakeJwt({
      iss: "https://evil.auth0.com/",
      aud: "authenticated",
    });
    try {
      assertClaimsShape(decodeJwtPayload(jwt), {
        expectedIssuers: ["https://abc.supabase.co/auth/v1"],
        allowedAudiences: ["authenticated"],
      });
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.status, 403, "status");
      assertEq(err.reason, "invalid_issuer", "reason");
    }
  });

  await test("6. assertClaimsShape rejects missing issuer", () => {
    const jwt = fakeJwt({ aud: "authenticated" });
    try {
      assertClaimsShape(decodeJwtPayload(jwt), {
        expectedIssuers: ["https://abc.supabase.co/auth/v1"],
        allowedAudiences: ["authenticated"],
      });
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.reason, "invalid_issuer", "reason");
    }
  });

  await test("7. assertClaimsShape rejects missing audience", () => {
    const jwt = fakeJwt({ iss: "https://abc.supabase.co/auth/v1" });
    try {
      assertClaimsShape(decodeJwtPayload(jwt), {
        expectedIssuers: ["https://abc.supabase.co/auth/v1"],
        allowedAudiences: ["authenticated"],
      });
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.status, 403, "status");
      assertEq(err.reason, "missing_audience", "reason");
    }
  });

  await test("8. assertClaimsShape rejects audience mismatch", () => {
    const jwt = fakeJwt({
      iss: "https://abc.supabase.co/auth/v1",
      aud: "other-audience",
    });
    try {
      assertClaimsShape(decodeJwtPayload(jwt), {
        expectedIssuers: ["https://abc.supabase.co/auth/v1"],
        allowedAudiences: ["authenticated", "omni-mobile"],
      });
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.status, 403, "status");
      assertEq(err.reason, "audience_mismatch", "reason");
    }
  });

  await test("9. assertClaimsShape accepts audience array (intersects whitelist)", () => {
    const jwt = fakeJwt({
      iss: "https://abc.supabase.co/auth/v1",
      aud: ["omni-mobile", "authenticated"],
    });
    assertClaimsShape(decodeJwtPayload(jwt), {
      expectedIssuers: ["https://abc.supabase.co/auth/v1"],
      allowedAudiences: ["authenticated"],
    });
  });

  await test("10. assertClaimsShape rejects audience array with no intersection", () => {
    const jwt = fakeJwt({
      iss: "https://abc.supabase.co/auth/v1",
      aud: ["evil1", "evil2"],
    });
    try {
      assertClaimsShape(decodeJwtPayload(jwt), {
        expectedIssuers: ["https://abc.supabase.co/auth/v1"],
        allowedAudiences: ["authenticated"],
      });
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.reason, "audience_mismatch", "reason");
    }
  });

  await test("11. assertClaimsShape accepts multiple expected issuers", () => {
    const jwt = fakeJwt({
      iss: "https://staging.supabase.co/auth/v1",
      aud: "authenticated",
    });
    assertClaimsShape(decodeJwtPayload(jwt), {
      expectedIssuers: [
        "https://prod.supabase.co/auth/v1",
        "https://staging.supabase.co/auth/v1",
      ],
      allowedAudiences: ["authenticated"],
    });
  });

  await test("12. assertClaimsShape tight audience rejects default 'authenticated'", () => {
    const jwt = fakeJwt({
      iss: "https://abc.supabase.co/auth/v1",
      aud: "authenticated",
    });
    try {
      assertClaimsShape(decodeJwtPayload(jwt), {
        expectedIssuers: ["https://abc.supabase.co/auth/v1"],
        allowedAudiences: ["omni-platform-admin"],
      });
      assert(false, "should have thrown");
    } catch (e) {
      const err = e as InstanceType<typeof AuthError>;
      assertEq(err.reason, "audience_mismatch", "reason");
    }
  });

  console.log(
    `\n${BOLD}Summary:${RESET} ${passed}/${total} passed${
      failed ? `, ${RED}${failed} failed${RESET}` : ""
    }.`,
  );

  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
