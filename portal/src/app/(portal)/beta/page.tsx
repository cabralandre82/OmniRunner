"use client";

import { useState } from "react";

const BETA_PHASES = [
  {
    id: "alpha",
    label: "Alpha (Interno)",
    description: "Validação interna com a equipe e assessorias fundadoras",
    status: "completed" as const,
  },
  {
    id: "closed",
    label: "Closed Beta",
    description: "5-10 assessorias selecionadas validando com atletas reais",
    status: "active" as const,
  },
  {
    id: "open",
    label: "Open Beta",
    description: "Inscrição aberta para qualquer assessoria interessada",
    status: "upcoming" as const,
  },
];

const KNOWN_ISSUES = [
  {
    id: "1",
    severity: "P2",
    title: "Notificação de treino pode atrasar em até 5 minutos",
    status: "Em correção",
  },
  {
    id: "2",
    severity: "P3",
    title: "Ícone do perfil não atualiza imediatamente após upload",
    status: "Backlog",
  },
];

const CHANGELOG_ENTRIES = [
  {
    version: "0.9.2",
    date: "2026-03-03",
    changes: [
      "Novo fluxo de onboarding com tooltips guiados",
      "Melhoria na performance do dashboard de engajamento",
      "Correção de crash ao abrir treino sem conexão",
    ],
  },
  {
    version: "0.9.1",
    date: "2026-02-24",
    changes: [
      "Adicionado suporte a OmniCoins no app",
      "Filtro por período na tela de histórico",
      "Correção de bug na verificação de atleta",
    ],
  },
  {
    version: "0.9.0",
    date: "2026-02-17",
    changes: [
      "Lançamento da versão Closed Beta",
      "Dashboard do atleta redesenhado",
      "Integração com Strava melhorada",
    ],
  },
];

const WHATSAPP_GROUP_URL = "https://chat.whatsapp.com/PLACEHOLDER_GROUP_LINK";
const FEEDBACK_FORM_URL = "https://forms.gle/PLACEHOLDER_BETA_FEEDBACK";

function PhaseIndicator({ status }: { status: "completed" | "active" | "upcoming" }) {
  if (status === "completed") {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-success-soft px-2.5 py-0.5 text-xs font-medium text-success">
        <svg className="h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
          <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
        </svg>
        Concluída
      </span>
    );
  }
  if (status === "active") {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-brand-soft px-2.5 py-0.5 text-xs font-medium text-brand">
        <span className="h-1.5 w-1.5 rounded-full bg-brand animate-pulse" />
        Em andamento
      </span>
    );
  }
  return (
    <span className="inline-flex items-center rounded-full bg-surface-elevated px-2.5 py-0.5 text-xs font-medium text-content-muted">
      Em breve
    </span>
  );
}

function SeverityBadge({ severity }: { severity: string }) {
  const colors: Record<string, string> = {
    P0: "bg-error-soft text-error",
    P1: "bg-warning-soft text-warning",
    P2: "bg-brand-soft text-brand",
    P3: "bg-surface-elevated text-content-muted",
  };
  return (
    <span className={`inline-flex rounded px-1.5 py-0.5 text-xs font-mono font-medium ${colors[severity] ?? colors.P3}`}>
      {severity}
    </span>
  );
}

export default function BetaProgramPage() {
  const [npsScore, setNpsScore] = useState<number | null>(null);
  const [npsSubmitted, setNpsSubmitted] = useState(false);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Programa Beta</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Acompanhe o progresso do programa beta, envie feedback e fique por dentro das novidades.
        </p>
      </div>

      {/* Phase Status */}
      <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
        <h2 className="text-lg font-semibold text-content-primary">Fases do Programa</h2>
        <div className="mt-4 space-y-4">
          {BETA_PHASES.map((phase, idx) => (
            <div
              key={phase.id}
              className={`flex items-start gap-4 rounded-lg border p-4 ${
                phase.status === "active"
                  ? "border-brand bg-brand-soft/30"
                  : "border-border"
              }`}
            >
              <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-surface-elevated text-sm font-bold text-content-secondary">
                {idx + 1}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <h3 className="font-semibold text-content-primary">{phase.label}</h3>
                  <PhaseIndicator status={phase.status} />
                </div>
                <p className="mt-0.5 text-sm text-content-secondary">{phase.description}</p>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Quick Links */}
      <div className="grid gap-4 sm:grid-cols-2">
        <a
          href={WHATSAPP_GROUP_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-3 rounded-xl border border-border bg-surface p-5 shadow-sm transition-colors hover:border-brand hover:bg-brand-soft/20"
        >
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-[#25D366]/10">
            <svg className="h-5 w-5 text-[#25D366]" fill="currentColor" viewBox="0 0 24 24">
              <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
            </svg>
          </div>
          <div>
            <h3 className="font-semibold text-content-primary">Grupo WhatsApp</h3>
            <p className="text-sm text-content-secondary">Canal principal de comunicação</p>
          </div>
        </a>

        <a
          href={FEEDBACK_FORM_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-3 rounded-xl border border-border bg-surface p-5 shadow-sm transition-colors hover:border-brand hover:bg-brand-soft/20"
        >
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-brand-soft">
            <svg className="h-5 w-5 text-brand" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 002.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 00-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 00.75-.75 2.25 2.25 0 00-.1-.664m-5.8 0A2.251 2.251 0 0113.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25zM6.75 12h.008v.008H6.75V12zm0 3h.008v.008H6.75V15zm0 3h.008v.008H6.75V18z" />
            </svg>
          </div>
          <div>
            <h3 className="font-semibold text-content-primary">Formulário de Feedback</h3>
            <p className="text-sm text-content-secondary">Envie seu feedback semanal</p>
          </div>
        </a>
      </div>

      {/* NPS Survey */}
      <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
        <h2 className="text-lg font-semibold text-content-primary">Pesquisa NPS</h2>
        <p className="mt-1 text-sm text-content-secondary">
          De 0 a 10, qual a probabilidade de você recomendar o Omni Runner para outra assessoria?
        </p>
        {npsSubmitted ? (
          <div className="mt-4 rounded-lg bg-success-soft p-3 text-sm text-success">
            Obrigado pelo seu feedback! Sua resposta foi registrada.
          </div>
        ) : (
          <div className="mt-4">
            <div className="flex flex-wrap gap-2">
              {Array.from({ length: 11 }, (_, i) => (
                <button
                  key={i}
                  onClick={() => setNpsScore(i)}
                  className={`flex h-10 w-10 items-center justify-center rounded-lg border text-sm font-medium transition-colors ${
                    npsScore === i
                      ? "border-brand bg-brand text-white"
                      : "border-border bg-surface-elevated text-content-secondary hover:border-brand hover:text-brand"
                  }`}
                >
                  {i}
                </button>
              ))}
            </div>
            <div className="mt-1 flex justify-between text-xs text-content-muted">
              <span>Nada provável</span>
              <span>Muito provável</span>
            </div>
            {npsScore !== null && (
              <button
                onClick={() => setNpsSubmitted(true)}
                className="mt-3 rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand/90 transition-colors"
              >
                Enviar resposta
              </button>
            )}
          </div>
        )}
      </div>

      {/* Recent Changelog */}
      <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
        <h2 className="text-lg font-semibold text-content-primary">Atualizações Recentes</h2>
        <div className="mt-4 space-y-5">
          {CHANGELOG_ENTRIES.map((entry) => (
            <div key={entry.version}>
              <div className="flex items-center gap-2">
                <span className="font-mono text-sm font-semibold text-brand">v{entry.version}</span>
                <span className="text-xs text-content-muted">{entry.date}</span>
              </div>
              <ul className="mt-1.5 space-y-1">
                {entry.changes.map((change, idx) => (
                  <li key={idx} className="flex items-start gap-2 text-sm text-content-secondary">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-content-muted" />
                    {change}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>

      {/* Known Issues */}
      <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
        <h2 className="text-lg font-semibold text-content-primary">Problemas Conhecidos</h2>
        <p className="mt-1 text-sm text-content-secondary">
          Bugs que já estamos cientes e trabalhando para resolver.
        </p>
        <div className="mt-4 space-y-3">
          {KNOWN_ISSUES.length === 0 ? (
            <p className="text-sm text-content-muted">Nenhum problema conhecido no momento.</p>
          ) : (
            KNOWN_ISSUES.map((issue) => (
              <div
                key={issue.id}
                className="flex items-start gap-3 rounded-lg border border-border p-3"
              >
                <SeverityBadge severity={issue.severity} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-content-primary">{issue.title}</p>
                  <p className="text-xs text-content-muted">Status: {issue.status}</p>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
