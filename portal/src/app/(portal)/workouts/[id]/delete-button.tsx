"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function DeleteTemplateButton({ templateId }: { templateId: string }) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const handleDelete = async () => {
    setDeleting(true);
    try {
      const res = await fetch("/api/workouts/templates", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: templateId }),
      });
      const data = await res.json();
      if (data.ok) {
        router.push("/workouts");
        router.refresh();
      }
    } finally {
      setDeleting(false);
      setConfirming(false);
    }
  };

  if (confirming) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-xs text-error">Excluir?</span>
        <button
          onClick={handleDelete}
          disabled={deleting}
          className="rounded-lg bg-error px-3 py-2 text-xs font-medium text-white hover:bg-error/90 disabled:opacity-50"
        >
          {deleting ? "..." : "Sim"}
        </button>
        <button
          onClick={() => setConfirming(false)}
          className="rounded-lg border border-border px-3 py-2 text-xs font-medium text-content-secondary hover:bg-surface-elevated"
        >
          Não
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={() => setConfirming(true)}
      className="rounded-lg border border-error/30 bg-transparent px-4 py-2 text-sm font-medium text-error hover:bg-error-soft"
    >
      Excluir
    </button>
  );
}
