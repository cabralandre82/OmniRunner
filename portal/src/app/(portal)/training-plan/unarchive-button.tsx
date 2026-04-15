"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function UnarchiveButton({ planId, planName }: { planId: string; planName: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleUnarchive() {
    setLoading(true);
    try {
      await fetch(`/api/training-plan/${planId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "active" }),
      });
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  return (
    <button
      onClick={handleUnarchive}
      disabled={loading}
      title={`Desarquivar "${planName}"`}
      className="shrink-0 rounded-lg border border-border px-3 py-1.5 text-xs text-content-secondary hover:bg-surface-elevated disabled:opacity-50"
    >
      {loading ? "..." : "Desarquivar"}
    </button>
  );
}
