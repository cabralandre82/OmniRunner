"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

interface Props {
  groupId: string;
  action: "approve" | "reject" | "suspend";
  label: string;
  className: string;
  requireReason?: boolean;
}

export function AssessoriaActions({
  groupId,
  action,
  label,
  className,
  requireReason = false,
}: Props) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleClick() {
    let reason: string | undefined;

    if (requireReason) {
      const input = window.prompt(
        action === "reject"
          ? "Motivo da rejeição (opcional):"
          : "Motivo da suspensão (opcional):",
      );
      if (input === null) return;
      reason = input;
    }

    const confirmMsg =
      action === "approve"
        ? "Confirma a aprovação desta assessoria?"
        : action === "reject"
          ? "Confirma a rejeição desta assessoria?"
          : "Confirma a suspensão desta assessoria?";

    if (!window.confirm(confirmMsg)) return;

    setLoading(true);
    try {
      const res = await fetch("/api/platform/assessorias", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, group_id: groupId, reason }),
      });

      if (!res.ok) {
        const data = await res.json();
        alert(`Erro: ${data.error ?? "Falha desconhecida"}`);
      }

      router.refresh();
    } catch (e) {
      alert(`Erro de rede: ${e}`);
    } finally {
      setLoading(false);
    }
  }

  return (
    <button
      onClick={handleClick}
      disabled={loading}
      className={`${className} disabled:opacity-50`}
    >
      {loading ? "..." : label}
    </button>
  );
}
