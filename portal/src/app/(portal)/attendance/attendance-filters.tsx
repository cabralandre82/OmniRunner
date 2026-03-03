"use client";

import { useRouter } from "next/navigation";

interface Session {
  id: string;
  title: string;
  starts_at: string;
}

export function AttendanceFilters({
  from,
  to,
  sessionId,
  sessions,
}: {
  from?: string;
  to?: string;
  sessionId?: string;
  sessions: Session[];
}) {
  const router = useRouter();

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = e.currentTarget;
    const formData = new FormData(form);
    const fromVal = formData.get("from") as string;
    const toVal = formData.get("to") as string;
    const sessionVal = formData.get("session_id") as string;

    const params = new URLSearchParams();
    if (fromVal) params.set("from", fromVal);
    if (toVal) params.set("to", toVal);
    if (sessionVal) params.set("session_id", sessionVal);
    router.push(`/attendance?${params.toString()}`);
  };

  const today = new Date().toISOString().slice(0, 10);
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

  return (
    <form onSubmit={handleSubmit} className="flex flex-wrap items-end gap-3 rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
      <div>
        <label htmlFor="from" className="block text-xs font-medium text-gray-500">
          De
        </label>
        <input
          id="from"
          name="from"
          type="date"
          defaultValue={from ?? thirtyDaysAgo}
          className="mt-1 block rounded-md border border-gray-300 px-2 py-1.5 text-sm"
        />
      </div>
      <div>
        <label htmlFor="to" className="block text-xs font-medium text-gray-500">
          Até
        </label>
        <input
          id="to"
          name="to"
          type="date"
          defaultValue={to ?? today}
          className="mt-1 block rounded-md border border-gray-300 px-2 py-1.5 text-sm"
        />
      </div>
      <div>
        <label htmlFor="session_id" className="block text-xs font-medium text-gray-500">
          Treino
        </label>
        <select
          id="session_id"
          name="session_id"
          key={sessionId ?? "all"}
          defaultValue={sessionId ?? ""}
          className="mt-1 block rounded-md border border-gray-300 px-2 py-1.5 text-sm"
        >
          <option value="">Todos</option>
          {sessions.map((s) => (
            <option key={s.id} value={s.id}>
              {s.title} ({new Date(s.starts_at).toLocaleDateString("pt-BR")})
            </option>
          ))}
        </select>
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
