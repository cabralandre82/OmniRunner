/**
 * Session submission burst test.
 * Simulates 500 athletes finishing a run simultaneously (championship scenario).
 * Measures p95/p99 response times under burst load.
 *
 * Usage:
 *   k6 run scenarios/session-burst.js
 *   BASE_URL=https://staging.example.com k6 run scenarios/session-burst.js
 *
 * Targets /api/health as a proxy for API capacity under burst.
 * In production, point at the actual session sync endpoint if available.
 */

import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "10s", target: 500 },
    { duration: "30s", target: 500 },
    { duration: "10s", target: 0 },
  ],
  thresholds: {
    "http_req_duration": ["p(95)<1000", "p(99)<2000"],
    "http_req_failed": ["rate<0.02"],
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";

export default function () {
  const res = http.get(`${BASE_URL}/api/health`);

  check(res, {
    "status is 200 or 503": (r) => r.status === 200 || r.status === 503,
  });

  sleep(0.1);
}
