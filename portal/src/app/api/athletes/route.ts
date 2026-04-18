import { NextRequest } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { logger } from "@/lib/logger";
import {
  apiError,
  apiUnauthorized,
  apiInternalError,
  apiNoGroupSession,
  apiValidationFailed,
  apiOk,
} from "@/lib/api/errors";
import {
  parsePaginationParams,
  paginate,
  PaginationError,
  type PaginatedResponse,
} from "@/lib/api/pagination";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

interface AthleteRow {
  user_id: string;
  display_name: string | null;
  profiles:
    | { display_name?: string | null; avatar_url?: string | null }
    | { display_name?: string | null; avatar_url?: string | null }[]
    | null;
}

interface AthleteItem {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
}

/**
 * Cursor payload — opaque to clients but typed internally so the
 * `extractCursor` callback in `paginate()` is type-checked.
 *
 * We page by (display_name ASC, user_id ASC). `display_name` is
 * sometimes null in the DB; we coerce to "" for ordering parity with
 * the SQL `nulls first` default.
 */
interface AthleteCursor {
  d: string;
  u: string;
}
/**
 * GET /api/athletes
 *
 * Returns active athlete members of the coach's group. L14-06 — agora
 * cursor-paginated; default limit 50, máximo 100.
 *
 * Query params:
 *   - cursor   (opcional, opaco)
 *   - limit    (opcional, 1..100, default 50)
 *
 * Response (canonical paginated envelope):
 *   { items: [...], next_cursor: string|null, has_more: boolean }
 *
 * Backward-compat: clients que enviavam zero params recebem agora a
 * primeira página (max 50). O legacy era "tudo" — grupo com 5k atletas
 * passava MB no fio. Frontend dropdowns devem implementar virtual
 * scroll usando next_cursor.
 */
export async function GET(req: NextRequest) {
  try {
    const cookieStore = cookies();
    const groupId = cookieStore.get("portal_group_id")?.value;

    if (!groupId) return apiNoGroupSession(req);

    let pagination;
    try {
      pagination = parsePaginationParams<AthleteCursor>(
        req.nextUrl.searchParams,
      );
    } catch (err) {
      if (err instanceof PaginationError) {
        return apiValidationFailed(req, err.message, { code: err.code });
      }
      throw err;
    }
    const { limit, cursor } = pagination;

    const supabase = createClient();
    const {
      data: { user },
      error: authErr,
    } = await supabase.auth.getUser();

    if (authErr || !user) return apiUnauthorized(req);

    let query = supabase
      .from("coaching_members")
      .select(
        `
        user_id,
        display_name,
        profiles (
          display_name,
          avatar_url
        )
      `,
      )
      .eq("group_id", groupId)
      .in("role", ["athlete", "atleta"])
      .order("display_name", { ascending: true })
      .order("user_id", { ascending: true });

    // Cursor: skip rows whose (display_name, user_id) <= (cursor.d, cursor.u).
    // Supabase's PostgREST doesn't have row-value comparison; we emulate
    // with .or(display_name.gt, and(eq+user_id.gt)).
    if (cursor) {
      query = query.or(
        `display_name.gt."${cursor.d}",and(display_name.eq."${cursor.d}",user_id.gt.${cursor.u})`,
      );
    }

    // Over-fetch by 1 so paginate() can detect has_more.
    const { data: members, error } = await query.limit(limit + 1);

    if (error) {
      logger.error("GET /api/athletes — DB error", error);
      return apiError(req, "DB_ERROR", error.message, 500);
    }

    // Paginate on raw rows so the cursor uses the DB sort key
    // (display_name including nulls), then map the visible page to
    // the wire-format items.
    const rawPage: PaginatedResponse<AthleteRow> = paginate(
      (members ?? []) as AthleteRow[],
      limit,
      (lastRow) => ({
        d: lastRow.display_name ?? "",
        u: lastRow.user_id,
      }),
    );

    const items: AthleteItem[] = rawPage.items.map((m) => {
      const profile = Array.isArray(m.profiles) ? m.profiles[0] : m.profiles;
      return {
        user_id: m.user_id,
        display_name:
          m.display_name ||
          (profile as { display_name?: string } | null)?.display_name ||
          "Atleta",
        avatar_url:
          (profile as { avatar_url?: string | null } | null)?.avatar_url ??
          null,
      };
    });

    const page: PaginatedResponse<AthleteItem> = {
      items,
      next_cursor: rawPage.next_cursor,
      has_more: rawPage.has_more,
    };

    return apiOk(page);
  } catch (err) {
    logger.error("GET /api/athletes", err);
    return apiInternalError(req);
  }
}
