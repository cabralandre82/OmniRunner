"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface RemoveButtonProps {
  memberId: string;
  memberName: string;
}

export function RemoveButton({ memberId, memberName }: RemoveButtonProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleRemove() {
    if (!confirm(`Remover ${memberName} da equipe?`)) return;

    setLoading(true);
    setError(null);

    try {
      const res = await fetch("/api/team/remove", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ member_id: memberId }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Erro ao remover");
        setLoading(false);
        return;
      }

      router.refresh();
    } catch {
      setError("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="inline-flex flex-col items-end">
      <button
        onClick={handleRemove}
        disabled={loading}
        className="text-sm font-medium text-red-600 hover:text-red-700 disabled:opacity-50"
      >
        {loading ? "Removendo..." : "Remover"}
      </button>
      {error && <p className="mt-1 text-xs text-red-500">{error}</p>}
    </div>
  );
}
