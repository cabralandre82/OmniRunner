/**
 * In-memory circuit breaker for external API calls in Edge Functions.
 *
 * States: CLOSED (normal) → OPEN (failing) → HALF_OPEN (testing)
 *
 * Usage:
 *   const breaker = getCircuitBreaker("strava-api");
 *   if (!breaker.isAllowed()) throw new Error("Circuit open for strava-api");
 *   try {
 *     const result = await callStravaApi();
 *     breaker.recordSuccess();
 *     return result;
 *   } catch (e) {
 *     breaker.recordFailure();
 *     throw e;
 *   }
 */

type CircuitState = "closed" | "open" | "half_open";

interface CircuitBreakerConfig {
  failureThreshold: number;
  resetTimeoutMs: number;
  halfOpenMaxAttempts: number;
}

const DEFAULT_CONFIG: CircuitBreakerConfig = {
  failureThreshold: 5,
  resetTimeoutMs: 30_000,
  halfOpenMaxAttempts: 2,
};

class CircuitBreaker {
  private state: CircuitState = "closed";
  private failureCount = 0;
  private lastFailureTime = 0;
  private halfOpenAttempts = 0;
  private readonly config: CircuitBreakerConfig;
  readonly name: string;

  constructor(name: string, config?: Partial<CircuitBreakerConfig>) {
    this.name = name;
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  isAllowed(): boolean {
    if (this.state === "closed") return true;

    if (this.state === "open") {
      const elapsed = Date.now() - this.lastFailureTime;
      if (elapsed >= this.config.resetTimeoutMs) {
        this.state = "half_open";
        this.halfOpenAttempts = 0;
        return true;
      }
      return false;
    }

    // half_open
    return this.halfOpenAttempts < this.config.halfOpenMaxAttempts;
  }

  recordSuccess(): void {
    if (this.state === "half_open") {
      this.state = "closed";
      this.failureCount = 0;
      this.halfOpenAttempts = 0;
    } else {
      this.failureCount = Math.max(0, this.failureCount - 1);
    }
  }

  recordFailure(): void {
    this.failureCount++;
    this.lastFailureTime = Date.now();

    if (this.state === "half_open") {
      this.halfOpenAttempts++;
      if (this.halfOpenAttempts >= this.config.halfOpenMaxAttempts) {
        this.state = "open";
      }
    } else if (this.failureCount >= this.config.failureThreshold) {
      this.state = "open";
    }
  }

  getState(): { state: CircuitState; failures: number; lastFailure: number } {
    return {
      state: this.state,
      failures: this.failureCount,
      lastFailure: this.lastFailureTime,
    };
  }

  reset(): void {
    this.state = "closed";
    this.failureCount = 0;
    this.halfOpenAttempts = 0;
  }
}

const breakers = new Map<string, CircuitBreaker>();

export function getCircuitBreaker(
  name: string,
  config?: Partial<CircuitBreakerConfig>,
): CircuitBreaker {
  let breaker = breakers.get(name);
  if (!breaker) {
    breaker = new CircuitBreaker(name, config);
    breakers.set(name, breaker);
  }
  return breaker;
}

/**
 * Wraps an async function with circuit breaker protection.
 * Throws an error immediately if the circuit is open.
 */
export async function withCircuitBreaker<T>(
  name: string,
  fn: () => Promise<T>,
  config?: Partial<CircuitBreakerConfig>,
): Promise<T> {
  const breaker = getCircuitBreaker(name, config);

  if (!breaker.isAllowed()) {
    throw new Error(`Circuit breaker OPEN for ${name}. Retry after ${(breaker.getState().lastFailure + (config?.resetTimeoutMs ?? DEFAULT_CONFIG.resetTimeoutMs) - Date.now()) / 1000}s`);
  }

  try {
    const result = await fn();
    breaker.recordSuccess();
    return result;
  } catch (error) {
    breaker.recordFailure();
    throw error;
  }
}

export function getAllBreakerStates(): Record<string, ReturnType<CircuitBreaker["getState"]>> {
  const states: Record<string, ReturnType<CircuitBreaker["getState"]>> = {};
  for (const [name, breaker] of breakers) {
    states[name] = breaker.getState();
  }
  return states;
}
