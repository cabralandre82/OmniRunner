/**
 * v1 alias for `/api/custody` (L14-02).
 *
 * Canonical version of the custody contract (deposit list + confirm
 * via idempotency key). See `src/lib/api/versioning.ts` for the
 * deprecation-window strategy and `src/app/api/v1/swap/route.ts`
 * for the rationale behind the wrap-and-delegate pattern.
 */

import {
  GET as legacyGet,
  POST as legacyPost,
} from "@/app/api/custody/route";
import { wrapV1Handler } from "@/lib/api/versioning";

export const GET = wrapV1Handler(legacyGet);
export const POST = wrapV1Handler(legacyPost);
