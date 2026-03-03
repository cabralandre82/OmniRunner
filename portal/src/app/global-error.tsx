"use client";

import { useEffect } from "react";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("Global error:", error);
  }, [error]);

  return (
    <html>
      <body>
        <div style={{ display: "flex", minHeight: "100vh", alignItems: "center", justifyContent: "center", fontFamily: "system-ui, sans-serif", backgroundColor: "#f9fafb" }}>
          <div style={{ maxWidth: "400px", padding: "32px", borderRadius: "12px", backgroundColor: "white", boxShadow: "0 4px 6px rgba(0,0,0,0.1)", textAlign: "center" }}>
            <h2 style={{ fontSize: "18px", fontWeight: 600, color: "#111827" }}>Erro crítico</h2>
            <p style={{ marginTop: "8px", fontSize: "14px", color: "#6b7280" }}>
              Ocorreu um erro grave. Por favor, recarregue a página.
            </p>
            <button
              onClick={reset}
              style={{ marginTop: "24px", padding: "8px 16px", borderRadius: "8px", backgroundColor: "#2563eb", color: "white", border: "none", cursor: "pointer", fontSize: "14px", fontWeight: 500 }}
            >
              Recarregar
            </button>
          </div>
        </div>
      </body>
    </html>
  );
}
