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
        <div style={{ display: "flex", minHeight: "100vh", alignItems: "center", justifyContent: "center", fontFamily: "system-ui, sans-serif", backgroundColor: "#0a0e17" }}>
          <div style={{ maxWidth: "400px", padding: "32px", borderRadius: "12px", backgroundColor: "#1e293b", boxShadow: "0 4px 8px rgba(0,0,0,0.2)", textAlign: "center", border: "1px solid #334155" }}>
            <h2 style={{ fontSize: "18px", fontWeight: 600, color: "#f1f5f9" }}>Erro crítico</h2>
            <p style={{ marginTop: "8px", fontSize: "14px", color: "#94a3b8" }}>
              Ocorreu um erro grave. Por favor, recarregue a página.
            </p>
            <button
              onClick={reset}
              style={{ marginTop: "24px", padding: "8px 16px", borderRadius: "8px", backgroundColor: "#3b82f6", color: "white", border: "none", cursor: "pointer", fontSize: "14px", fontWeight: 500 }}
            >
              Recarregar
            </button>
          </div>
        </div>
      </body>
    </html>
  );
}
