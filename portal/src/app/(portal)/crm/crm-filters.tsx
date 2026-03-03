"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

interface Tag {
  id: string;
  name: string;
}

export function CrmFilters({
  groupId,
  tagId,
  status,
  search,
}: {
  groupId: string;
  tagId?: string;
  status?: string;
  search?: string;
}) {
  const router = useRouter();
  const [tags, setTags] = useState<Tag[]>([]);

  useEffect(() => {
    fetch(`/api/crm/tags?groupId=${groupId}`)
      .then((r) => r.ok && r.json())
      .then((data) => (Array.isArray(data) ? setTags(data) : []))
      .catch(() => {});
  }, [groupId]);

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = e.currentTarget;
    const formData = new FormData(form);
    const params = new URLSearchParams();
    const tagVal = formData.get("tag") as string;
    const statusVal = formData.get("status") as string;
    const qVal = formData.get("q") as string;
    if (tagVal) params.set("tag", tagVal);
    if (statusVal) params.set("status", statusVal);
    if (qVal?.trim()) params.set("q", qVal.trim());
    router.push(`/crm?${params.toString()}`);
  };

  return (
    <form
      onSubmit={handleSubmit}
      className="flex flex-wrap items-end gap-3 rounded-lg border border-gray-200 bg-white p-4 shadow-sm"
    >
      <div>
        <label htmlFor="tag" className="block text-xs font-medium text-gray-500">
          Tag
        </label>
        <select
          id="tag"
          name="tag"
          defaultValue={tagId ?? ""}
          className="mt-1 block rounded-md border border-gray-300 px-2 py-1.5 text-sm"
        >
          <option value="">Todas</option>
          {tags.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label htmlFor="status" className="block text-xs font-medium text-gray-500">
          Status
        </label>
        <select
          id="status"
          name="status"
          defaultValue={status ?? ""}
          className="mt-1 block rounded-md border border-gray-300 px-2 py-1.5 text-sm"
        >
          <option value="">Todos</option>
          <option value="active">Ativo</option>
          <option value="paused">Pausado</option>
          <option value="injured">Lesionado</option>
          <option value="inactive">Inativo</option>
          <option value="trial">Teste</option>
        </select>
      </div>
      <div>
        <label htmlFor="q" className="block text-xs font-medium text-gray-500">
          Buscar nome
        </label>
        <input
          id="q"
          name="q"
          type="text"
          defaultValue={search ?? ""}
          placeholder="Nome do atleta"
          className="mt-1 block rounded-md border border-gray-300 px-2 py-1.5 text-sm"
        />
      </div>
      <button
        type="submit"
        className="rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-800"
      >
        Filtrar
      </button>
    </form>
  );
}
