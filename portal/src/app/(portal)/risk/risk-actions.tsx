"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

interface RiskActionsProps {
  alertId: string;
  onResolved?: () => void;
}

export function RiskActions({ alertId, onResolved }: RiskActionsProps) {
  const [loading, setLoading] = useState<string | null>(null);
  const router = useRouter();
  const supabase = createClient();

  async function resolve(action: "resolver" | "dispensar") {
    if (loading) return;
    setLoading(action);
    try {
      const { error } = await supabase
        .from("coaching_alerts")
        .update({
          resolved: true,
          resolved_at: new Date().toISOString(),
        })
        .eq("id", alertId);

      if (error) {
        console.error("Erro ao resolver alerta:", error);
        return;
      }
      onResolved?.();
      router.refresh();
    } finally {
      setLoading(null);
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => resolve("resolver")}
        disabled={!!loading}
        className="rounded-lg bg-blue-600 px-2.5 py-1.5 text-xs font-medium text-white hover:bg-blue-700 disabled:opacity-50"
      >
        {loading === "resolver" ? "..." : "Resolver"}
      </button>
      <button
        type="button"
        onClick={() => resolve("dispensar")}
        disabled={!!loading}
        className="rounded-lg border border-gray-300 bg-white px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
      >
        {loading === "dispensar" ? "..." : "Dispensar"}
      </button>
    </>
  );
}
