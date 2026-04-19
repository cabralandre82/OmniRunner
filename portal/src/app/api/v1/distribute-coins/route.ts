/**
 * v1 alias for `/api/distribute-coins` (L14-02).
 *
 * Canonical version of the OmniCoin distribution contract. See
 * `src/lib/api/versioning.ts` for migration strategy.
 */

import { POST as legacyPost } from "@/app/api/distribute-coins/route";
import { wrapV1Handler } from "@/lib/api/versioning";

export const POST = wrapV1Handler(legacyPost);
