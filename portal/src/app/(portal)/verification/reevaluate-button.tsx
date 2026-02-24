"use client";

import { useState } from "react";

interface ReevaluateButtonProps {
  userId: string;
}

export function ReevaluateButton({ userId }: ReevaluateButtonProps) {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<"ok" | "error" | null>(null);

  async function handleClick() {
    setLoading(true);
    setResult(null);

    try {
      const res = await fetch("/api/verification/evaluate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: userId }),
      });

      if (res.ok) {
        setResult("ok");
        setTimeout(() => window.location.reload(), 1500);
      } else {
        setResult("error");
      }
    } catch {
      setResult("error");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex flex-col items-center gap-1">
      <button
        onClick={handleClick}
        disabled={loading}
        className="rounded-md bg-gray-100 px-2.5 py-1 text-xs font-medium text-gray-700 transition hover:bg-gray-200 disabled:opacity-50"
      >
        {loading ? "..." : "Reavaliar"}
      </button>
      {result === "ok" && (
        <span className="text-[10px] text-green-600">Feito</span>
      )}
      {result === "error" && (
        <span className="text-[10px] text-red-600">Erro</span>
      )}
    </div>
  );
}
