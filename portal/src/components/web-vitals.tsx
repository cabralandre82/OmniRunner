"use client";

import { useReportWebVitals } from "next/web-vitals";

export function WebVitals() {
  useReportWebVitals((metric) => {
    if (process.env.NODE_ENV === "production") {
      console.log(`[WebVital] ${metric.name}: ${metric.value.toFixed(1)}ms (${metric.rating})`);
    }
  });
  return null;
}
