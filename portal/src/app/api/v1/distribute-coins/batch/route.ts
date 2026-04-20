/**
 * v1 alias for `/api/distribute-coins/batch` (L05-03 + L14-02).
 *
 * Bulk OmniCoin distribution: dispatches up to 200 athletes in a single
 * SQL transaction via `distribute_coins_batch_atomic`. Migration strategy
 * for v0 → v1 documented in `src/lib/api/versioning.ts`.
 */

import { POST as legacyPost } from "@/app/api/distribute-coins/batch/route";
import { wrapV1Handler } from "@/lib/api/versioning";

export const POST = wrapV1Handler(legacyPost);
