'use client';

import { useEffect } from 'react';

import { reportClientError } from '@/lib/observability/reportClientError';

/**
 * L06-07 — Root document error boundary.
 *
 * Next.js renders this when even the root `layout.tsx` throws (so it owns
 * the entire `<html>` document — no shared chrome). Anything caught here is
 * by definition catastrophic: the user is staring at a blank fallback and
 * no nested boundary will catch retries. We forward to Sentry as P1 via
 * `reportClientError({ boundary: "global" })` so on-call gets paged.
 */
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    reportClientError({ error, boundary: 'global' });
  }, [error]);

  return (
    <html lang="pt-BR">
      <body>
        <div
          style={{
            display: 'flex',
            minHeight: '100vh',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '1rem',
            padding: '2rem',
            textAlign: 'center',
            fontFamily: 'system-ui, sans-serif',
          }}
        >
          <h2 style={{ fontSize: '1.5rem', fontWeight: 600, color: '#1f2937' }}>
            Algo deu errado
          </h2>
          <p style={{ maxWidth: '28rem', fontSize: '0.875rem', color: '#6b7280' }}>
            Ocorreu um erro inesperado. Por favor, tente novamente ou entre em
            contato com o suporte se o problema persistir.
          </p>
          {error.digest && (
            <p
              style={{
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
                fontSize: '0.75rem',
                color: '#9ca3af',
              }}
            >
              Ref: {error.digest}
            </p>
          )}
          <button
            onClick={reset}
            style={{
              marginTop: '0.5rem',
              padding: '0.625rem 1.5rem',
              fontSize: '0.875rem',
              fontWeight: 500,
              color: '#fff',
              backgroundColor: '#2563eb',
              border: 'none',
              borderRadius: '0.5rem',
              cursor: 'pointer',
            }}
          >
            Tentar novamente
          </button>
        </div>
      </body>
    </html>
  );
}
