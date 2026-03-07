/**
 * k6 base configuration for load testing.
 *
 * Stages: ramp up to 100 VUs over 30s, sustain for 1m, ramp down over 30s
 * Thresholds: p95 < 500ms, error rate < 1%
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:3000 scenarios/api-health.js
 *   k6 run -e BASE_URL=https://staging.example.com scenarios/dashboard-load.js
 */

export const defaultStages = [
  { duration: "30s", target: 100 },  // ramp up
  { duration: "1m", target: 100 },  // sustain
  { duration: "30s", target: 0 },   // ramp down
];

export const defaultThresholds = {
  "http_req_duration": ["p(95)<500"],
  "http_req_failed": ["rate<0.01"],
};

export const smokeStages = [
  { duration: "10s", target: 5 },
  { duration: "5s", target: 0 },
];

export const smokeThresholds = {
  "http_req_duration": ["p(95)<2000"],
  "http_req_failed": ["rate<0.05"],
};

/**
 * Export config for different scenarios.
 * Scenarios can import and extend these.
 */
export function getScenarioConfig(scenarioName, overrides = {}) {
  return {
    stages: overrides.stages ?? defaultStages,
    thresholds: overrides.thresholds ?? defaultThresholds,
    ...overrides,
  };
}
