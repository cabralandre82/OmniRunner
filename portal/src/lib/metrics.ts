/**
 * Application metrics collection.
 *
 * Provides a simple, type-safe API for recording business and operational metrics.
 * Default implementation logs structured JSON; swap for Datadog/Prometheus/OpenTelemetry
 * in production by implementing MetricsCollector.
 */

import { logger } from "./logger";

export interface MetricEvent {
  name: string;
  value: number;
  unit?: "count" | "ms" | "usd" | "coins" | "percent";
  tags?: Record<string, string>;
}

export interface MetricsCollector {
  record(event: MetricEvent): void;
  increment(name: string, tags?: Record<string, string>): void;
  timing(name: string, durationMs: number, tags?: Record<string, string>): void;
  gauge(name: string, value: number, tags?: Record<string, string>): void;
}

class LogMetricsCollector implements MetricsCollector {
  record(event: MetricEvent): void {
    logger.info(`metric:${event.name}`, {
      metric: event.name,
      value: event.value,
      unit: event.unit ?? "count",
      ...event.tags,
    });
  }

  increment(name: string, tags?: Record<string, string>): void {
    this.record({ name, value: 1, unit: "count", tags });
  }

  timing(name: string, durationMs: number, tags?: Record<string, string>): void {
    this.record({ name, value: durationMs, unit: "ms", tags });
  }

  gauge(name: string, value: number, tags?: Record<string, string>): void {
    this.record({ name, value, tags });
  }
}

export const metrics: MetricsCollector = new LogMetricsCollector();

/**
 * Wraps an async function with automatic timing + error counting.
 */
export async function withMetrics<T>(
  operationName: string,
  fn: () => Promise<T>,
  tags?: Record<string, string>,
): Promise<T> {
  const start = Date.now();
  metrics.increment(`${operationName}.started`, tags);

  try {
    const result = await fn();
    const duration = Date.now() - start;
    metrics.timing(`${operationName}.duration`, duration, tags);
    metrics.increment(`${operationName}.success`, tags);
    return result;
  } catch (error) {
    const duration = Date.now() - start;
    metrics.timing(`${operationName}.duration`, duration, { ...tags, status: "error" });
    metrics.increment(`${operationName}.error`, tags);
    throw error;
  }
}
