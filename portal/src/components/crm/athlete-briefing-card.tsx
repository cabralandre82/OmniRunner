"use client";

import { useEffect, useState } from "react";

interface BriefingResult {
  briefing: string;
  signal: "positive" | "attention" | "risk";
}

const SIGNAL_STYLES: Record<BriefingResult["signal"], { border: string; icon: string; label: string }> = {
  positive: {
    border: "border-success/40 bg-success-soft",
    icon: "✅",
    label: "Sinal positivo",
  },
  attention: {
    border: "border-amber-300/60 bg-amber-50",
    icon: "⚠️",
    label: "Atenção",
  },
  risk: {
    border: "border-error/40 bg-error-soft",
    icon: "🔴",
    label: "Risco",
  },
};

interface AthleteBriefingCardProps {
  athleteId: string;
}

/**
 * Client component that lazy-loads an AI-generated briefing paragraph
 * for the athlete CRM profile page.
 * Never blocks rendering — on any error it silently disappears.
 */
export function AthleteBriefingCard({ athleteId }: AthleteBriefingCardProps) {
  const [state, setState] = useState<"idle" | "loading" | "done" | "error">("idle");
  const [result, setResult] = useState<BriefingResult | null>(null);
  const [expanded, setExpanded] = useState(true);

  useEffect(() => {
    setState("loading");

    fetch("/api/ai/athlete-briefing", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ athlete_id: athleteId }),
    })
      .then((r) => r.json())
      .then((json) => {
        if (json.ok && json.data?.briefing) {
          setResult(json.data);
          setState("done");
        } else {
          setState("error");
        }
      })
      .catch(() => setState("error"));
  }, [athleteId]);

  if (state === "error") return null;

  if (state === "loading" || state === "idle") {
    return (
      <div className="rounded-xl border border-border bg-surface p-4 shadow-sm animate-pulse">
        <div className="flex items-center gap-2 mb-3">
          <div className="h-4 w-4 rounded-full bg-surface-elevated" />
          <div className="h-3.5 w-32 rounded bg-surface-elevated" />
        </div>
        <div className="space-y-2">
          <div className="h-3 w-full rounded bg-surface-elevated" />
          <div className="h-3 w-5/6 rounded bg-surface-elevated" />
          <div className="h-3 w-4/6 rounded bg-surface-elevated" />
        </div>
      </div>
    );
  }

  if (!result) return null;

  const style = SIGNAL_STYLES[result.signal];

  return (
    <div className={`rounded-xl border ${style.border} p-4 shadow-sm`}>
      <button
        type="button"
        className="flex w-full items-center justify-between gap-2 text-left"
        onClick={() => setExpanded((v) => !v)}
        aria-expanded={expanded}
      >
        <div className="flex items-center gap-2">
          <span className="text-base leading-none">{style.icon}</span>
          <span className="text-sm font-semibold text-content-primary">
            Briefing IA
          </span>
          <span className="rounded-full bg-white/60 px-2 py-0.5 text-xs text-content-secondary">
            {style.label}
          </span>
        </div>
        <svg
          className={`h-4 w-4 shrink-0 text-content-muted transition-transform ${expanded ? "rotate-180" : ""}`}
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={2}
          stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
        </svg>
      </button>

      {expanded && (
        <p className="mt-3 text-sm leading-relaxed text-content-primary">
          {result.briefing}
        </p>
      )}

      <p className="mt-2 text-xs text-content-muted">
        Gerado por IA com base nos dados atuais · não substitui a avaliação do treinador
      </p>
    </div>
  );
}
