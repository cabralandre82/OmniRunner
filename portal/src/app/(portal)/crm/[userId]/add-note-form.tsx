"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function AddNoteForm({
  groupId,
  athleteUserId,
}: {
  groupId: string;
  athleteUserId: string;
}) {
  const router = useRouter();
  const [note, setNote] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!note.trim() || loading) return;
    setLoading(true);
    try {
      const res = await fetch("/api/crm/notes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          groupId,
          athleteUserId,
          note: note.trim(),
        }),
      });
      if (res.ok) {
        setNote("");
        router.refresh();
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="mt-2">
      <textarea
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="Adicionar nota..."
        rows={2}
        className="block w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
      />
      <button
        type="submit"
        disabled={!note.trim() || loading}
        className="mt-2 rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-800 disabled:opacity-50"
      >
        {loading ? "Salvando…" : "Salvar nota"}
      </button>
    </form>
  );
}
