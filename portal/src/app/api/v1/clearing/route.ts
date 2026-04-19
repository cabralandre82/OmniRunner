/**
 * v1 alias for `/api/clearing` (L14-02).
 *
 * Canonical version of the clearing settlements read contract. See
 * `src/lib/api/versioning.ts` for migration strategy.
 */

import { GET as legacyGet } from "@/app/api/clearing/route";
import { wrapV1Handler } from "@/lib/api/versioning";

export const GET = wrapV1Handler(legacyGet);
