/**
 * L02-12 — Zod UUID strict-validation policy.
 *
 * Zod v3.x already validates UUID strictly (RFC 4122 v1-5). Zod v4
 * tightens this further (the v4 release re-checks the version nibble
 * and reserved bits). Two kinds of identifiers must NOT be passed to
 * `z.string().uuid()` even though they are "id-shaped" strings:
 *
 *   1. External integration IDs that originate from third-party APIs
 *      (Strava `activity_id` is an integer, Polar `workout_id` is a
 *      ULID, TrainingPeaks `pmc_id` is a base64-ish opaque string).
 *
 *   2. Free-form correlation tokens (idempotency keys, ref_ids).
 *      These are validated by length and charset, not RFC 4122.
 *
 * Use:
 *
 *   - `omniUuid()` — strict v1-5 UUID, the Postgres `gen_random_uuid()`
 *     output. ALWAYS use this for our own primary keys / FKs.
 *   - `externalIntegrationId(label)` — opaque 1..100 char ASCII id from
 *     a third party. Documents intent and survives a Zod v4 upgrade.
 *   - `correlationToken(label, opts)` — 8..128 char alnum/dash/_ token.
 */
import { z } from "zod";

export const omniUuid = (msg = "deve ser UUID válido (gen_random_uuid)") =>
  z.string().uuid(msg);

const EXTERNAL_ID_RE = /^[A-Za-z0-9._:\-]{1,100}$/;

export function externalIntegrationId(label: string) {
  return z
    .string()
    .min(1, `${label} obrigatório`)
    .max(100, `${label} máximo 100 caracteres`)
    .regex(
      EXTERNAL_ID_RE,
      `${label} deve usar apenas A-Z a-z 0-9 . _ : -`,
    );
}

const TOKEN_RE = /^[A-Za-z0-9_-]+$/;

export function correlationToken(label: string, opts?: { min?: number; max?: number }) {
  const min = opts?.min ?? 8;
  const max = opts?.max ?? 128;
  return z
    .string()
    .min(min, `${label} deve ter ao menos ${min} caracteres`)
    .max(max, `${label} máximo ${max} caracteres`)
    .regex(TOKEN_RE, `${label} deve usar apenas A-Z a-z 0-9 _ -`);
}
