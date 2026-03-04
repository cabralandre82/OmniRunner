"use client";
import Link from "next/link";

export function NoGroupSelected() {
  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4">
      <h2 className="text-xl font-semibold text-zinc-200">Nenhum grupo selecionado</h2>
      <p className="text-zinc-400 text-center max-w-md">
        Selecione um grupo de assessoria para visualizar esta página.
      </p>
      <Link
        href="/select-group"
        className="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg transition-colors"
      >
        Selecionar Grupo
      </Link>
    </div>
  );
}
