/**
 * v1 alias for `/api/coins/reverse` (L03-13 + L14-02).
 *
 * Reembolso/estorno dos fluxos financeiros (emission, burn, custody
 * deposit) via funções atômicas na migration
 * `20260421130000_l03_reverse_coin_flows.sql`. Migration strategy para
 * v0 → v1 documentada em `src/lib/api/versioning.ts`.
 */

import { POST as legacyPost } from "@/app/api/coins/reverse/route";
import { wrapV1Handler } from "@/lib/api/versioning";

export const POST = wrapV1Handler(legacyPost);
