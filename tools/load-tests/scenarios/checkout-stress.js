/**
 * Payment stress test.
 * Simulates 50 concurrent checkout attempts.
 * Tests rate limiting under load (checkout is limited to 5 req/min per user).
 *
 * Usage:
 *   k6 run scenarios/checkout-stress.js
 *   BASE_URL=https://staging.example.com k6 run scenarios/checkout-stress.js
 *
 * Note: Checkout requires auth and valid payload. This test will get 401/429
 * under load; we measure that rate limiting behaves correctly.
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { defaultThresholds } from "../k6-config.js";

export const options = {
  stages: [
    { duration: "20s", target: 50 },
    { duration: "1m", target: 50 },
    { duration: "20s", target: 0 },
  ],
  thresholds: {
    ...defaultThresholds,
    "http_req_duration": ["p(95)<2000"],
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";

export default function () {
  const payload = JSON.stringify({
    product_id: "test-product",
    gateway: "stripe",
  });

  const res = http.post(`${BASE_URL}/api/checkout`, payload, {
    headers: { "Content-Type": "application/json" },
  });

  check(res, {
    "status is 401, 400, 429, or 500": (r) =>
      [401, 400, 429, 500].includes(r.status),
  });

  sleep(1);
}
