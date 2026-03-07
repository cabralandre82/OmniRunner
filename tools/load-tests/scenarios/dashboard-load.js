/**
 * Dashboard load test.
 * Simulates 100 concurrent assessorias opening the dashboard.
 * Hits /dashboard, /api/platform/fees, and typical dashboard endpoints.
 *
 * Usage:
 *   k6 run scenarios/dashboard-load.js
 *   BASE_URL=https://staging.example.com k6 run scenarios/dashboard-load.js
 *
 * Note: Dashboard pages require auth. This test hits the endpoints;
 * for full E2E with auth, use Playwright or similar.
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { defaultStages, defaultThresholds } from "../k6-config.js";

export const options = {
  stages: defaultStages,
  thresholds: defaultThresholds,
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";

const DASHBOARD_ENDPOINTS = [
  "/dashboard",
  "/api/platform/fees",
  "/api/platform/feature-flags",
  "/api/platform/products",
  "/api/staff-alerts",
];

export default function () {
  for (const path of DASHBOARD_ENDPOINTS) {
    const res = http.get(`${BASE_URL}${path}`);

    check(res, {
      [`${path} returns 2xx or 3xx or 401`]: (r) =>
        r.status >= 200 && r.status < 400 || r.status === 401,
    });

    sleep(0.2);
  }

  sleep(0.5);
}
