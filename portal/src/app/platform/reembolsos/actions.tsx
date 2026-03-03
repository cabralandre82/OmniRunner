"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";

export function RefundActions({
  refundId,
  action,
  label,
  className,
  requireNotes = false,
}: {
  refundId: string;
  action: string;
  label: string;
  className: string;
  requireNotes?: boolean;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleClick() {
    let notes: string | undefined;
    if (requireNotes) {
      const input = prompt("Motivo da rejeição:");
      if (!input?.trim()) return;
      notes = input.trim();
    }

    if (action === "process") {
      const ok = confirm(
        "Confirmar processamento do reembolso? Esta ação não pode ser desfeita.",
      );
      if (!ok) return;
    }

    setLoading(true);
    try {
      const res = await fetch("/api/platform/refunds", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, refund_id: refundId, notes }),
      });

      if (!res.ok) {
        const data = await res.json();
        toast.error(data.error ?? "Erro ao processar ação");
      }

      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  return (
    <button onClick={handleClick} disabled={loading} className={className}>
      {loading ? "..." : label}
    </button>
  );
}
