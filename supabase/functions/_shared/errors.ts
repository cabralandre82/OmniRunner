/**
 * DB error classifier for Supabase Edge Functions.
 *
 * Converts raw Postgres/PostgREST errors into safe, generic messages
 * so internal details (table names, column types, SQL state) are never
 * returned to the client.
 */

export function classifyError(
  err: unknown,
): { code: string; message: string; httpStatus: number } {
  const raw =
    err && typeof err === "object" && "message" in err
      ? String((err as { message: unknown }).message)
      : String(err);

  if (raw.includes("invalid input syntax for type uuid")) {
    return { code: "INVALID_INPUT", httpStatus: 400, message: "Invalid input" };
  }

  if (raw.includes("permission denied") || raw.includes("new row violates row-level security")) {
    return { code: "FORBIDDEN", httpStatus: 403, message: "Forbidden" };
  }

  if (raw.includes("duplicate key") || raw.includes("unique constraint")) {
    return { code: "CONFLICT", httpStatus: 409, message: "Duplicate entry" };
  }

  if (raw.includes("violates not-null constraint")) {
    return { code: "INVALID_INPUT", httpStatus: 400, message: "Missing required value" };
  }

  if (raw.includes("violates foreign key constraint")) {
    return { code: "INVALID_INPUT", httpStatus: 400, message: "Referenced record not found" };
  }

  return { code: "DB_ERROR", httpStatus: 500, message: "Internal error" };
}
