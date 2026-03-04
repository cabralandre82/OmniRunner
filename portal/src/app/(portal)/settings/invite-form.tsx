"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";

export function InviteForm() {
  const _t = useTranslations("settings");
  const tc = useTranslations("common");
  const te = useTranslations("error");
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("coach");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccess(null);

    try {
      const res = await fetch("/api/team/invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, role }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? te("generic"));
        setLoading(false);
        return;
      }

      setSuccess(`${email} adicionado como ${role}`);
      setEmail("");
      router.refresh();
    } catch {
      setError(te("generic"));
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-4 space-y-4">
      <div className="flex flex-col gap-4 sm:flex-row">
        <input
          type="email"
          placeholder="email@exemplo.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          className="flex-1 rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
        />

        <select
          value={role}
          onChange={(e) => setRole(e.target.value)}
          className="rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
        >
          <option value="coach">Coach</option>
          <option value="assistant">Assistente</option>
        </select>

        <button
          type="submit"
          disabled={loading}
          className="rounded-lg bg-brand px-5 py-2 text-sm font-medium text-white shadow-sm transition hover:brightness-110 focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 disabled:opacity-50"
        >
          {loading ? tc("loading") : tc("invite")}
        </button>
      </div>

      {error && <p className="text-sm text-error">{error}</p>}
      {success && <p className="text-sm text-success">{success}</p>}
    </form>
  );
}
