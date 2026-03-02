"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";

interface RemoveButtonProps {
  memberId: string;
  memberName: string;
}

export function RemoveButton({ memberId, memberName }: RemoveButtonProps) {
  const t = useTranslations("settings");
  const tc = useTranslations("common");
  const te = useTranslations("error");
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleRemove() {
    if (!confirm(`${t("removeMember")}: ${memberName}?`)) return;

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
        setError(data.error ?? te("generic"));
        setLoading(false);
        return;
      }

      router.refresh();
    } catch {
      setError(te("generic"));
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
        {loading ? tc("loading") : tc("remove")}
      </button>
      {error && <p className="mt-1 text-xs text-red-500">{error}</p>}
    </div>
  );
}
