"use client";

import { useState } from "react";
import Link from "next/link";
import { formatDateISO } from "@/lib/format";
import { AnnouncementForm } from "./announcement-form";
import { AnnouncementActions } from "./announcement-actions";

interface AnnouncementRow {
  id: string;
  title: string;
  created_by: string;
  created_at: string;
  pinned: boolean;
  display_name: string | null;
  read_count: number;
  total_members: number;
}

interface AnnouncementsClientProps {
  groupId: string;
  canEdit: boolean;
  announcements: AnnouncementRow[];
}

export function AnnouncementsClient({
  groupId,
  canEdit,
  announcements,
}: AnnouncementsClientProps) {
  const [showForm, setShowForm] = useState(false);

  const readRate = (readCount: number, total: number) =>
    total > 0 ? (readCount / total) * 100 : 0;

  return (
    <div className="space-y-6">
      {canEdit && (
        <div className="flex items-center justify-between">
          <button
            type="button"
            onClick={() => setShowForm(!showForm)}
            className="rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-800"
          >
            {showForm ? "Ocultar formulário" : "Novo Aviso"}
          </button>
          <a
            href={`/api/export/announcements?${new URLSearchParams({}).toString()}`}
            className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-700 shadow-sm hover:bg-gray-50"
          >
            Exportar CSV
          </a>
        </div>
      )}

      {showForm && canEdit && (
        <AnnouncementForm
          groupId={groupId}
          onCancel={() => setShowForm(false)}
        />
      )}

      <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Título
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Autor
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Data
                </th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">
                  Fixado
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Taxa de Leitura (%)
                </th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">
                  Ações
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {announcements.map((a) => {
                const rate = readRate(a.read_count, a.total_members);
                return (
                  <tr key={a.id} className="hover:bg-gray-50">
                    <td className="whitespace-nowrap px-4 py-3">
                      <Link
                        href={`/announcements/${a.id}`}
                        className="font-medium text-blue-600 hover:text-blue-800 hover:underline"
                      >
                        {a.title}
                      </Link>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                      {a.display_name ?? "—"}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                      {formatDateISO(a.created_at)}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {a.pinned ? (
                        <span className="inline-flex rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-medium text-amber-800">
                          Fixado
                        </span>
                      ) : (
                        "—"
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <div className="flex-1 min-w-[80px] h-2 rounded-full bg-gray-200 overflow-hidden">
                          <div
                            className="h-full rounded-full bg-blue-600"
                            style={{ width: `${Math.min(rate, 100)}%` }}
                          />
                        </div>
                        <span className="text-xs font-medium text-gray-700 w-10">
                          {rate.toFixed(1)}%
                        </span>
                      </div>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-right">
                      <AnnouncementActions
                        id={a.id}
                        title={a.title}
                        pinned={a.pinned}
                        canEdit={canEdit}
                      />
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {announcements.length === 0 && (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Nenhum aviso ainda.</p>
          {canEdit && (
            <button
              type="button"
              onClick={() => setShowForm(true)}
              className="mt-2 rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-800"
            >
              Criar primeiro aviso
            </button>
          )}
        </div>
      )}
    </div>
  );
}
