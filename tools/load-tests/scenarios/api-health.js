/**
 * Basic health check load test.
 * Hits /api/health and measures response time and status codes.
 *
 * Usage:
 *   k6 run scenarios/api-health.js
 *   BASE_URL=https://staging.example.com k6 run scenarios/api-health.js
 */

import http from "k6/http";
import { check, sleep } from "k6";
import {
  defaultStages,
  defaultThresholds,
  smokeStages,
  smokeThresholds,
} from "../k6-config.js";

const isSmoke = __ENV.SMOKE === "true";

export const options = {
  stages: isSmoke ? smokeStages : defaultStages,
  thresholds: isSmoke ? smokeThresholds : defaultThresholds,
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";

export default function () {
  const res = http.get(`${BASE_URL}/api/health`);

  check(res, {
    "status is 200 or 503": (r) => r.status === 200 || r.status === 503,
    "has JSON body": (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && (body.status === "ok" || body.status === "degraded" || body.status === "down");
      } catch {
        return false;
      }
    },
  });

  sleep(0.5);
}
