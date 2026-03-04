/**
 * Retries an async operation with exponential backoff and jitter.
 *
 * @param action       — async function to attempt
 * @param maxAttempts  — total number of tries (default 3)
 * @param baseDelayMs  — initial delay in ms before the first retry (default 500)
 * @param retryIf      — optional predicate; only retry when it returns true for
 *                        the caught error. Defaults to retrying all errors.
 * @returns the result of a successful invocation
 * @throws the last error if all attempts fail
 */
export async function retry<T>(
  action: () => Promise<T>,
  opts?: {
    maxAttempts?: number;
    baseDelayMs?: number;
    retryIf?: (err: unknown) => boolean;
  },
): Promise<T> {
  const maxAttempts = opts?.maxAttempts ?? 3;
  const baseDelayMs = opts?.baseDelayMs ?? 500;
  const retryIf = opts?.retryIf;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await action();
    } catch (err) {
      if (attempt === maxAttempts) throw err;
      if (retryIf && !retryIf(err)) throw err;

      const delay = baseDelayMs * Math.pow(2, attempt - 1);
      const jitter = Math.floor(Math.random() * (delay / 2 + 1));
      await new Promise((r) => setTimeout(r, delay + jitter));
    }
  }

  throw new Error("retry: exhausted all attempts");
}
