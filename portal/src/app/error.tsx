"use client";

import { useEffect } from "react";

import { reportClientError } from "@/lib/observability/reportClientError";

/**
 * L06-07 — Root layout subtree error boundary.
 *
 * Catches anything that escapes a nested route group's own `error.tsx`
 * (i.e. a crash that happened while rendering the root `layout.tsx`'s
 * children but before any `(portal)` / `platform` boundary could catch it).
 * Treated as P1: at this depth the surrounding chrome is barely available
 * and the user is one click away from leaving — page on-call.
 */
export default function RootError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    reportClientError({ error, boundary: "root" });
  }, [error]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-secondary">
      <div className="max-w-md rounded-xl bg-surface p-8 shadow-lg text-center">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-error-soft">
          <svg className="h-6 w-6 text-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z" />
          </svg>
        </div>
        <h2 className="text-lg font-semibold text-content-primary">Algo deu errado</h2>
        <p className="mt-2 text-sm text-content-secondary">
          Ocorreu um erro inesperado. Tente novamente.
        </p>
        {error.digest && (
          <p className="mt-1 font-mono text-xs text-content-muted">
            Ref: {error.digest}
          </p>
        )}
        <button
          onClick={reset}
          className="mt-6 rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110"
        >
          Tentar novamente
        </button>
      </div>
    </div>
  );
}
