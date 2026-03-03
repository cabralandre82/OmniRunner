"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface AnnouncementFormProps {
  groupId: string;
  editId?: string;
  editTitle?: string;
  editBody?: string;
  editPinned?: boolean;
  onCancel?: () => void;
}

export function AnnouncementForm({
  groupId,
  editId,
  editTitle = "",
  editBody = "",
  editPinned = false,
  onCancel,
}: AnnouncementFormProps) {
  const router = useRouter();
  const [title, setTitle] = useState(editTitle);
  const [body, setBody] = useState(editBody);
  const [pinned, setPinned] = useState(editPinned);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const res = await fetch(
        editId ? `/api/announcements/${editId}` : "/api/announcements",
        {
          method: editId ? "PUT" : "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title, body, pinned }),
        }
      );

      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || "Erro ao salvar aviso");
      }

      router.push("/announcements");
      router.refresh();
    } catch (err: any) {
      setError(err.message || "Erro inesperado");
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </div>
      )}

      <div>
        <label htmlFor="title" className="block text-sm font-medium text-gray-700">
          Título
        </label>
        <input
          id="title"
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
          placeholder="Título do aviso"
          required
          minLength={2}
          maxLength={200}
        />
      </div>

      <div>
        <label htmlFor="body" className="block text-sm font-medium text-gray-700">
          Conteúdo
        </label>
        <textarea
          id="body"
          value={body}
          onChange={(e) => setBody(e.target.value)}
          rows={6}
          className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
          placeholder="Escreva o conteúdo do aviso..."
          required
        />
      </div>

      <div className="flex items-center gap-2">
        <input
          id="pinned"
          type="checkbox"
          checked={pinned}
          onChange={(e) => setPinned(e.target.checked)}
          className="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
        />
        <label htmlFor="pinned" className="text-sm text-gray-700">
          Fixar no topo do mural
        </label>
      </div>

      <div className="flex gap-3">
        <button
          type="submit"
          disabled={loading}
          className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? "Salvando..." : editId ? "Salvar alterações" : "Publicar aviso"}
        </button>
        <button
          type="button"
          onClick={() => onCancel ? onCancel() : router.back()}
          className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Cancelar
        </button>
      </div>
    </form>
  );
}
