'use client';

import { useEffect } from 'react';

import { reportClientError } from '@/lib/observability/reportClientError';

/**
 * L06-07 — `(portal)` route group error boundary.
 *
 * Catches crashes scoped to the runner/coach portal subtree. The shell
 * (sidebar, top nav) keeps rendering and the user can navigate elsewhere,
 * so this is P2 — Slack ping but no pager. Sentry tag `error_boundary=portal`
 * makes the alert routing explicit.
 */
export default function PortalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    reportClientError({ error, boundary: 'portal' });
  }, [error]);

  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center gap-4 p-8 text-center">
      <h2 className="text-2xl font-semibold text-gray-800">
        Algo deu errado
      </h2>
      <p className="max-w-md text-sm text-gray-500">
        Ocorreu um erro inesperado. Por favor, tente novamente ou entre em
        contato com o suporte se o problema persistir.
      </p>
      {error.digest && (
        <p className="font-mono text-xs text-gray-400">
          Ref: {error.digest}
        </p>
      )}
      <button
        onClick={reset}
        className="mt-2 rounded-lg bg-blue-600 px-6 py-2.5 text-sm font-medium text-white shadow hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
      >
        Tentar novamente
      </button>
    </div>
  );
}
