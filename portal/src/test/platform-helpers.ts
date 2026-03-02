import { vi } from "vitest";
import { queryChain } from "./api-helpers";

/**
 * Creates mock clients for platform admin API routes.
 * These routes use `createClient` for auth and `createAdminClient` for DB writes.
 */
export function makePlatformMocks(role: string = "admin") {
  const authClient = {
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "admin-user-1" } },
      }),
    },
    from: vi.fn(() =>
      queryChain({ data: { platform_role: role } }),
    ),
  };

  const adminClient = {
    from: vi.fn(() => queryChain()),
    rpc: vi.fn(() => queryChain()),
  };

  return { authClient, adminClient };
}

export function platformModuleMocks(authClient: unknown, adminClient: unknown) {
  return {
    server: { createClient: () => authClient },
    admin: { createAdminClient: () => adminClient },
    audit: { auditLog: vi.fn().mockResolvedValue(undefined) },
    rateLimit: { rateLimit: vi.fn().mockReturnValue({ allowed: true, remaining: 10 }) },
    logger: { logger: { error: vi.fn(), info: vi.fn(), warn: vi.fn() } },
  };
}
