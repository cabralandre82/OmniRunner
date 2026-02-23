/**
 * Input validation helpers for Edge Functions.
 *
 * Throws ValidationError on failure — callers catch and return jsonErr.
 */

export class ValidationError extends Error {
  code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "ValidationError";
    this.code = code;
  }
}

/**
 * Reads the request body and parses it as JSON.
 * Returns {} if body is empty/whitespace-only.
 * Rejects non-JSON Content-Type when header is explicitly set.
 */
export async function requireJson(
  req: Request,
): Promise<Record<string, unknown>> {
  const ct = req.headers.get("Content-Type") ?? "";
  if (ct && !ct.toLowerCase().includes("application/json")) {
    throw new ValidationError(
      "INVALID_CONTENT_TYPE",
      "Content-Type must be application/json",
    );
  }

  const text = await req.text();
  if (!text.trim()) return {};

  try {
    return JSON.parse(text);
  } catch {
    throw new ValidationError("INVALID_JSON", "Request body is not valid JSON");
  }
}

/**
 * Asserts that all listed fields are present (not null/undefined/empty-string).
 */
export function requireFields(
  obj: Record<string, unknown>,
  fields: string[],
): void {
  const missing = fields.filter(
    (f) => obj[f] == null || obj[f] === "",
  );
  if (missing.length > 0) {
    throw new ValidationError(
      "MISSING_FIELDS",
      `Missing required fields: ${missing.join(", ")}`,
    );
  }
}
