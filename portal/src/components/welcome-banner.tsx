"use client";
import { useState, useEffect } from "react";

export function WelcomeBanner() {
  const [dismissed, setDismissed] = useState(true);

  useEffect(() => {
    const seen = localStorage.getItem("onboarding_seen");
    if (!seen) setDismissed(false);
  }, []);

  if (dismissed) return null;

  const dismiss = () => {
    localStorage.setItem("onboarding_seen", "1");
    setDismissed(true);
  };

  return (
    <div className="bg-emerald-900/30 border border-emerald-700 rounded-lg p-4 mb-6">
      <div className="flex justify-between items-start">
        <div className="space-y-4 flex-1">
          <div>
            <h3 className="text-lg font-semibold text-emerald-300">Bem-vindo ao Portal!</h3>
            <p className="text-sm text-zinc-400 mt-1">Siga estes passos para começar:</p>
            <ol className="text-sm text-zinc-300 mt-2 space-y-2 list-decimal list-inside">
              <li>Selecione seu grupo no menu lateral</li>
              <li>Confira o dashboard com métricas do grupo</li>
              <li>Acesse <strong>Treinos</strong> para gerenciar entregas</li>
            </ol>
          </div>
          <PlatformMap />
        </div>
        <button onClick={dismiss} className="text-zinc-400 hover:text-zinc-200 text-sm flex-shrink-0">
          Fechar
        </button>
      </div>
    </div>
  );
}

function PlatformMap() {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 rounded-lg bg-white/5 p-3">
      <div>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-emerald-400 mb-1.5">
          Use o App para
        </h4>
        <ul className="space-y-1 text-sm text-zinc-300">
          <li className="flex items-center gap-1.5">
            <span className="h-1 w-1 rounded-full bg-emerald-400 flex-shrink-0" />
            Acompanhar corridas
          </li>
          <li className="flex items-center gap-1.5">
            <span className="h-1 w-1 rounded-full bg-emerald-400 flex-shrink-0" />
            Gerenciar desafios
          </li>
          <li className="flex items-center gap-1.5">
            <span className="h-1 w-1 rounded-full bg-emerald-400 flex-shrink-0" />
            Ver streak e badges
          </li>
        </ul>
      </div>
      <div>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-blue-400 mb-1.5">
          Use o Portal para
        </h4>
        <ul className="space-y-1 text-sm text-zinc-300">
          <li className="flex items-center gap-1.5">
            <span className="h-1 w-1 rounded-full bg-blue-400 flex-shrink-0" />
            CRM e entrega de treinos
          </li>
          <li className="flex items-center gap-1.5">
            <span className="h-1 w-1 rounded-full bg-blue-400 flex-shrink-0" />
            Analytics e relatórios
          </li>
          <li className="flex items-center gap-1.5">
            <span className="h-1 w-1 rounded-full bg-blue-400 flex-shrink-0" />
            Financeiro
          </li>
        </ul>
      </div>
    </div>
  );
}
