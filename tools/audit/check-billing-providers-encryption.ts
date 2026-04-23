/**
 * check-billing-providers-encryption.ts
 *
 * L09-06 — CI guard for at-rest encryption of billing provider
 * credentials (Asaas / Mercado Pago / Stripe).
 *
 * Invariants:
 *   1. pgcrypto extension is declared.
 *   2. `billing_providers` table exists with `api_key_enc bytea`,
 *      `key_version int`, provider CHECK limited to the known
 *      set, and UNIQUE(group_id, provider).
 *   3. RLS is enabled and SELECT on `api_key_enc` is NOT granted
 *      to `authenticated` / `anon`.
 *   4. `fn_set_billing_provider_key(uuid, text, text)` and
 *      `fn_get_billing_provider_key(uuid, text, text)` are
 *      SECURITY DEFINER, pinned search_path, granted to
 *      service_role only.
 *   5. Both helpers raise KMS_UNAVAILABLE when the GUC is unset
 *      or < 32 chars.
 *   6. Both helpers log to `portal_audit_log`.
 *   7. Self-test covers pgcrypto presence, bytea column,
 *      column-privilege denial for authenticated, KMS guard
 *      raise, and pgp_sym round-trip.
 *
 * Usage: npm run audit:billing-providers-encryption
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const migPath = resolve(
  ROOT,
  "supabase/migrations/20260421500000_l09_06_billing_providers_at_rest_encryption.sql",
);
const mig = safeRead(migPath, "L09-06 migration present");
if (mig) {
  push(
    "declares pgcrypto extension",
    /CREATE EXTENSION IF NOT EXISTS pgcrypto/.test(mig),
  );
  push(
    "creates billing_providers table",
    /CREATE TABLE IF NOT EXISTS public\.billing_providers/.test(mig),
  );
  push(
    "api_key_enc column is bytea",
    /api_key_enc\s+bytea/.test(mig),
  );
  push(
    "key_version column with CHECK",
    /key_version[\s\S]{0,60}CHECK \(key_version BETWEEN 1 AND 1000\)/.test(mig),
  );
  push(
    "provider CHECK lists asaas/mercadopago/stripe",
    /provider IN \('asaas','mercadopago','stripe'\)/.test(mig),
  );
  push(
    "UNIQUE (group_id, provider)",
    /UNIQUE \(group_id, provider\)/.test(mig),
  );
  push(
    "enables RLS",
    /ALTER TABLE public\.billing_providers ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "revokes full table access from anon/authenticated",
    /REVOKE ALL ON TABLE public\.billing_providers FROM anon, authenticated/.test(
      mig,
    ),
  );
  push(
    "does NOT grant api_key_enc to authenticated",
    !/GRANT SELECT[\s\S]{0,200}api_key_enc[\s\S]{0,120}TO authenticated/.test(
      mig,
    ),
  );
  push(
    "grants column-level SELECT to authenticated for metadata only",
    /GRANT SELECT \(\s*id, group_id, provider, key_version, last_rotated_at,\s*created_at, updated_at\s*\)[\s\S]{0,80}TO authenticated/.test(
      mig,
    ),
  );

  push(
    "defines fn_set_billing_provider_key(uuid, text, text)",
    /CREATE OR REPLACE FUNCTION public\.fn_set_billing_provider_key\(\s*p_group_id uuid,\s*p_provider text,\s*p_plain_key text\s*\)/.test(
      mig,
    ),
  );
  push(
    "defines fn_get_billing_provider_key(uuid, text, text)",
    /CREATE OR REPLACE FUNCTION public\.fn_get_billing_provider_key\(\s*p_group_id uuid,\s*p_provider text,\s*p_reason\s+text DEFAULT NULL\s*\)/.test(
      mig,
    ),
  );
  push(
    "both helpers are SECURITY DEFINER",
    (mig.match(/SECURITY DEFINER/g) || []).length >= 2,
  );
  push(
    "both helpers pin search_path",
    (mig.match(/SET search_path = public, pg_temp/g) || []).length >= 2,
  );
  push(
    "set helper encrypts with pgp_sym_encrypt",
    /pgp_sym_encrypt\(p_plain_key, v_master\)/.test(mig),
  );
  push(
    "get helper decrypts with pgp_sym_decrypt",
    /pgp_sym_decrypt\(v_enc, v_master\)/.test(mig),
  );
  push(
    "KMS_UNAVAILABLE guard on set helper",
    /length\(v_master\) < 32 THEN[\s\S]{0,200}KMS_UNAVAILABLE/.test(mig),
  );
  push(
    "KMS_UNAVAILABLE guard on get helper",
    (mig.match(/KMS_UNAVAILABLE/g) || []).length >= 2,
  );
  push(
    "logs key_set to portal_audit_log",
    /'billing_provider\.key_set'/.test(mig),
  );
  push(
    "logs key_access to portal_audit_log",
    /'billing_provider\.key_access'/.test(mig),
  );
  push(
    "rotation bumps key_version",
    /key_version\s+= billing_providers\.key_version \+ 1/.test(mig),
  );
  push(
    "NOT_FOUND raised on missing row",
    /RAISE EXCEPTION 'NOT_FOUND:/.test(mig),
  );
  push(
    "INVALID_ARGS raised on NULL inputs",
    /RAISE EXCEPTION 'INVALID_ARGS'/.test(mig),
  );
  push(
    "set helper: EXECUTE service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_set_billing_provider_key\(uuid, text, text\) TO service_role/.test(
      mig,
    ) &&
      /REVOKE ALL ON FUNCTION public\.fn_set_billing_provider_key\(uuid, text, text\) FROM (authenticated|anon|PUBLIC)/.test(
        mig,
      ),
  );
  push(
    "get helper: EXECUTE service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_get_billing_provider_key\(uuid, text, text\) TO service_role/.test(
      mig,
    ) &&
      /REVOKE ALL ON FUNCTION public\.fn_get_billing_provider_key\(uuid, text, text\) FROM (authenticated|anon|PUBLIC)/.test(
        mig,
      ),
  );

  push(
    "self-test: pgcrypto present",
    /self-test: pgcrypto extension missing/.test(mig),
  );
  push(
    "self-test: api_key_enc bytea",
    /self-test: api_key_enc must be bytea/.test(mig),
  );
  push(
    "self-test: authenticated denied on api_key_enc",
    /self-test: authenticated must not have SELECT on api_key_enc/.test(mig),
  );
  push(
    "self-test: empty KMS key raises",
    /self-test: empty KMS key should have raised KMS_UNAVAILABLE/.test(mig),
  );
  push(
    "self-test: pgp round-trip",
    /self-test: pgp_sym round-trip failed/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L09-06-gateway-de-pagamento-asaas-chave-armazenada-em-plaintext.md",
);
const finding = safeRead(findingPath, "L09-06 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421500000_l09_06_billing_providers_at_rest_encryption\.sql/.test(
      finding,
    ),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} billing-providers-encryption checks passed.`,
);
if (failed > 0) {
  console.error("\nL09-06 invariants broken.");
  process.exit(1);
}
