import { vi } from "vitest";

/** Default authenticated session for tests */
export const TEST_SESSION = {
  user: { id: "user-admin-1" },
  access_token: "test-token",
};

/** Creates a chainable Supabase query builder mock. Terminal methods resolve to `result`. */
export function queryChain(result: { data?: unknown; error?: unknown } = { data: null }) {
  const self: Record<string, unknown> = {};
  const methods = [
    "select", "insert", "update", "upsert", "delete",
    "eq", "neq", "in", "gte", "lte", "gt", "lt",
    "order", "limit", "range", "is",
  ];
  for (const m of methods) {
    self[m] = vi.fn().mockReturnValue(self);
  }
  self.maybeSingle = vi.fn().mockResolvedValue(result);
  self.single = vi.fn().mockResolvedValue(result);
  self.then = (resolve: (v: unknown) => void) => resolve(result);
  return self;
}

/** Creates a mock Supabase client for API route tests. */
export function makeMockClient(session: typeof TEST_SESSION | null = TEST_SESSION) {
  const user = session ? session.user : null;
  return {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session } }),
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    from: vi.fn(() => queryChain()),
    rpc: vi.fn(() => queryChain()),
  };
}
