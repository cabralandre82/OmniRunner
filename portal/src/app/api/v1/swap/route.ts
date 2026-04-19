/**
 * v1 alias for `/api/swap` (L14-02).
 *
 * Canonical version of the swap contract. Delegates to the legacy
 * handler in `src/app/api/swap/route.ts` and tags the response with
 * `X-Api-Version: 1`. When the legacy path is removed (after the
 * sunset window — see `DEFAULT_FINANCIAL_SUNSET`), the
 * implementation will move into this file and the wrapper will go
 * away.
 *
 * NOTE: We intentionally avoid duplicating handler logic here so
 * there is exactly one source of truth for the swap business rules.
 * Versioning is a *transport* concern; behaviour is identical.
 */

import {
  GET as legacyGet,
  POST as legacyPost,
} from "@/app/api/swap/route";
import { wrapV1Handler } from "@/lib/api/versioning";

export const GET = wrapV1Handler(legacyGet);
export const POST = wrapV1Handler(legacyPost);
