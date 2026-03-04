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
        <div>
          <h3 className="text-lg font-semibold text-emerald-300">Bem-vindo ao Portal!</h3>
          <ul className="text-sm text-zinc-300 mt-2 space-y-1">
            <li>📊 Use o Dashboard para acompanhar KPIs do seu grupo</li>
            <li>👥 Gerencie atletas em Atletas e CRM</li>
            <li>🏋️ Crie e envie treinos em Treinos e Entrega</li>
            <li>💰 Controle créditos em Custódia</li>
          </ul>
        </div>
        <button onClick={dismiss} className="text-zinc-400 hover:text-zinc-200 text-sm">
          Fechar
        </button>
      </div>
    </div>
  );
}
