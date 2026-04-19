/**
 * v1 alias for `/api/custody/withdraw` (L14-02).
 *
 * Canonical version of the custody withdrawal contract. See
 * `src/lib/api/versioning.ts` for migration strategy.
 */

import {
  GET as legacyGet,
  POST as legacyPost,
} from "@/app/api/custody/withdraw/route";
import { wrapV1Handler } from "@/lib/api/versioning";

export const GET = wrapV1Handler(legacyGet);
export const POST = wrapV1Handler(legacyPost);
