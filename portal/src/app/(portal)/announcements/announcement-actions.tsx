"use client";

import { useRouter } from "next/navigation";
import Link from "next/link";
import { useState } from "react";

interface AnnouncementActionsProps {
  id: string;
  title: string;
  pinned: boolean;
  canEdit: boolean;
}

export function AnnouncementActions({
  id,
  title,
  pinned,
  canEdit,
}: AnnouncementActionsProps) {
  const router = useRouter();
  const [deleting, setDeleting] = useState(false);
  const [pinning, setPinning] = useState(false);

  const handleTogglePin = async () => {
    if (!canEdit || pinning) return;
    setPinning(true);
    try {
      const res = await fetch(`/api/announcements/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pinned: !pinned }),
      });
      if (res.ok) router.refresh();
    } finally {
      setPinning(false);
    }
  };

  const handleDelete = async () => {
    if (!canEdit || deleting) return;
    if (!confirm(`Excluir o aviso "${title}"?`)) return;
    setDeleting(true);
    try {
      const res = await fetch(`/api/announcements/${id}`, { method: "DELETE" });
      if (res.ok) router.refresh();
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="flex items-center gap-2">
      <Link
        href={`/announcements/${id}`}
        className="rounded border border-border bg-surface px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-elevated"
      >
        Ver
      </Link>
      {canEdit && (
        <>
          <Link
            href={`/announcements/${id}/edit`}
            className="rounded border border-border bg-surface px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-elevated"
          >
            Editar
          </Link>
          <button
            type="button"
            onClick={handleTogglePin}
            disabled={pinning}
            className="rounded border border-border bg-surface px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-elevated disabled:opacity-50"
          >
            {pinned ? "Desfixar" : "Fixar"}
          </button>
          <button
            type="button"
            onClick={handleDelete}
            disabled={deleting}
            className="rounded border border-error/30 bg-error-soft px-2 py-1 text-xs font-medium text-error hover:bg-error-soft disabled:opacity-50"
          >
            {deleting ? "Excluindo…" : "Excluir"}
          </button>
        </>
      )}
    </div>
  );
}
