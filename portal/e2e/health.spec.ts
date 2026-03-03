import { test, expect } from "@playwright/test";

test.describe("Health check", () => {
  test("GET /api/health returns 200 or 404 (if not implemented)", async ({
    request,
  }) => {
    const res = await request.get("/api/health");
    const status = res.status();
    if (status === 200) {
      const body = await res.json();
      expect(body).toHaveProperty("status");
    } else {
      expect(status).toBe(404);
    }
  });
});
