import { test, expect } from "@playwright/test";

interface MutationRoute {
  method: "POST" | "PATCH" | "DELETE";
  path: string;
  body?: Record<string, unknown>;
}

const MUTATION_ROUTES: MutationRoute[] = [
  {
    method: "POST",
    path: "/api/announcements",
    body: { title: "test", body: "test" },
  },
  {
    method: "PATCH",
    path: "/api/announcements/fake-id",
    body: { title: "updated" },
  },
  { method: "DELETE", path: "/api/announcements/fake-id" },
  {
    method: "POST",
    path: "/api/distribute-coins",
    body: { amount: 10 },
  },
  { method: "POST", path: "/api/clearing", body: {} },
];

const VALID_UNAUTH_CODES = [301, 302, 303, 307, 308, 401, 403];

test.describe("Mutation API security — unauthenticated requests", () => {
  for (const { method, path, body } of MUTATION_ROUTES) {
    test(`${method} ${path} blocks unauthenticated access`, async ({
      request,
    }) => {
      const opts: {
        data?: Record<string, unknown>;
        headers: Record<string, string>;
        maxRedirects?: number;
      } = {
        headers: { "Content-Type": "application/json" },
        maxRedirects: 0,
      };
      if (body) opts.data = body;

      let res;
      switch (method) {
        case "POST":
          res = await request.post(path, opts);
          break;
        case "PATCH":
          res = await request.patch(path, opts);
          break;
        case "DELETE":
          res = await request.delete(path, opts);
          break;
      }

      expect(VALID_UNAUTH_CODES).toContain(res.status());
    });
  }
});
