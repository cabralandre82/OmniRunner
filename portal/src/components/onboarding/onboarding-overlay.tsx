"use client";

import { useEffect, useRef, useCallback, useState } from "react";
import { useOnboarding } from "./use-onboarding";
import { OnboardingStep } from "./onboarding-step";

const STEPS = [
  {
    id: "welcome" as const,
    targetSelector: null,
    title: "Bem-vindo ao Portal!",
    description:
      "Este é o painel de gestão da sua assessoria. Aqui você gerencia atletas, treinos, finanças e muito mais. Vamos fazer um tour rápido pelas principais áreas.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M4.26 10.147a60.436 60.436 0 00-.491 6.347A48.627 48.627 0 0112 20.904a48.627 48.627 0 018.232-4.41 60.46 60.46 0 00-.491-6.347m-15.482 0a50.57 50.57 0 00-2.658-.813A59.905 59.905 0 0112 3.493a59.902 59.902 0 0110.399 5.84c-.896.248-1.783.52-2.658.814m-15.482 0A50.697 50.697 0 0112 13.489a50.702 50.702 0 017.74-3.342M6.75 15a.75.75 0 100-1.5.75.75 0 000 1.5zm0 0v-3.675A55.378 55.378 0 0112 8.443m-7.007 11.55A5.981 5.981 0 006.75 15.75v-1.5" />
      </svg>
    ),
  },
  {
    id: "dashboard" as const,
    targetSelector: '[data-onboarding="dashboard"]',
    title: "Dashboard",
    description:
      "Aqui você acompanha os principais KPIs da assessoria: atletas ativos, treinos realizados, engajamento e métricas de desempenho em tempo real.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z" />
      </svg>
    ),
  },
  {
    id: "athletes" as const,
    targetSelector: '[data-onboarding="athletes"]',
    title: "Atletas",
    description:
      "Gerencie sua base de atletas: cadastro, verificação de identidade, CRM e alertas de risco. Tudo centralizado para um acompanhamento completo.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
      </svg>
    ),
  },
  {
    id: "training" as const,
    targetSelector: '[data-onboarding="training"]',
    title: "Treinos",
    description:
      "Crie templates de treino, atribua aos atletas e acompanhe execuções. Inclui campeonatos, matchmaking e integração com TrainingPeaks.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M15.362 5.214A8.252 8.252 0 0112 21 8.25 8.25 0 016.038 7.048 8.287 8.287 0 009 9.6a8.983 8.983 0 013.361-6.867 8.21 8.21 0 003 2.48z" />
      </svg>
    ),
  },
  {
    id: "financial" as const,
    targetSelector: '[data-onboarding="financial"]',
    title: "Financeiro",
    description:
      "Dashboard financeiro, planos, assinaturas e OmniCoins. Gerencie cobranças, distribua moedas virtuais e acompanhe transferências entre assessorias.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v12m-3-2.818l.879.659c1.171.879 3.07.879 4.242 0 1.172-.879 1.172-2.303 0-3.182C13.536 12.219 12.768 12 12 12c-.725 0-1.45-.22-2.003-.659-1.106-.879-1.106-2.303 0-3.182s2.9-.879 4.006 0l.415.33M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    ),
  },
  {
    id: "custody" as const,
    targetSelector: '[data-onboarding="custody"]',
    title: "Saldo OmniCoins",
    description:
      "Conta de custódia da assessoria. Faça depósitos, acompanhe seu saldo de OmniCoins e gerencie a moeda virtual utilizada para recompensar atletas.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
      </svg>
    ),
  },
  {
    id: "clearing" as const,
    targetSelector: '[data-onboarding="clearing"]',
    title: "Transferências",
    description:
      "Transferências automáticas de OmniCoins entre assessorias. Quando atletas mudam de clube, as moedas são movimentadas de forma transparente e auditável.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5" />
      </svg>
    ),
  },
  {
    id: "distributions" as const,
    targetSelector: '[data-onboarding="distributions"]',
    title: "Distribuição",
    description:
      "Distribua OmniCoins para seus atletas. Recompense desempenho, participação em treinos e conquistas com a moeda virtual da plataforma.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
      </svg>
    ),
  },
  {
    id: "help" as const,
    targetSelector: '[data-onboarding="help"]',
    title: "Central de Ajuda",
    description:
      "Central de ajuda e glossário. Tire dúvidas sobre funcionalidades, consulte termos e conceitos da plataforma e acesse documentação.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9 5.25h.008v.008H12v-.008z" />
      </svg>
    ),
  },
  {
    id: "settings" as const,
    targetSelector: '[data-onboarding="settings"]',
    title: "Configurações",
    description:
      "Personalize a assessoria, configure pagamentos, badges e exports. Ajuste a identidade visual e integrações conforme sua necessidade.",
    icon: (
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
        <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
      </svg>
    ),
  },
];

export function OnboardingOverlay() {
  const { currentStep, totalSteps, isActive, next, prev, skip, complete } = useOnboarding();
  const [targetRect, setTargetRect] = useState<DOMRect | null>(null);
  const [spotlightRect, setSpotlightRect] = useState<DOMRect | null>(null);
  const rafRef = useRef<number | null>(null);

  const step = STEPS[currentStep];
  const hasTarget = step?.targetSelector ?? false;

  const updateTargetRect = useCallback(() => {
    if (!step?.targetSelector) {
      setTargetRect(null);
      setSpotlightRect(null);
      return;
    }
    const el = document.querySelector(step.targetSelector);
    if (el) {
      const rect = el.getBoundingClientRect();
      setTargetRect(rect);
      setSpotlightRect(
        new DOMRect(
          rect.left - 8,
          rect.top - 8,
          rect.width + 16,
          rect.height + 16,
        ),
      );
    } else {
      setTargetRect(null);
      setSpotlightRect(null);
    }
  }, [step?.targetSelector]);

  useEffect(() => {
    if (!isActive || !step) return;
    updateTargetRect();

    const resizeObserver = new ResizeObserver(() => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      rafRef.current = requestAnimationFrame(updateTargetRect);
    });

    const targetEl = step.targetSelector
      ? document.querySelector(step.targetSelector)
      : null;
    if (targetEl) resizeObserver.observe(targetEl);
    resizeObserver.observe(document.body);

    return () => {
      resizeObserver.disconnect();
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, [isActive, currentStep, step, updateTargetRect]);

  useEffect(() => {
    if (!isActive || !step?.targetSelector) return;
    const el = document.querySelector(step.targetSelector);
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
  }, [isActive, currentStep, step?.targetSelector]);

  if (!isActive || !step) return null;

  const isFirst = currentStep === 0;
  const isLast = currentStep === totalSteps - 1;

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center"
      aria-modal="true"
      aria-label="Tour de boas-vindas"
      role="dialog"
    >
      {/* Backdrop with spotlight cutout */}
      <div
        className="absolute inset-0 bg-overlay transition-opacity duration-[var(--duration-normal)]"
        onClick={(e) => e.stopPropagation()}
      >
        {spotlightRect && (
          <svg
            className="absolute inset-0 h-full w-full"
            style={{ pointerEvents: "none" }}
          >
            <defs>
              <mask id="onboarding-spotlight-mask">
                <rect width="100%" height="100%" fill="white" />
                <rect
                  x={spotlightRect.x}
                  y={spotlightRect.y}
                  width={spotlightRect.width}
                  height={spotlightRect.height}
                  rx="var(--radius-md)"
                  ry="var(--radius-md)"
                  fill="black"
                />
              </mask>
            </defs>
            <rect
              width="100%"
              height="100%"
              fill="currentColor"
              mask="url(#onboarding-spotlight-mask)"
              className="text-black/60 dark:text-black/80"
            />
          </svg>
        )}
      </div>

      {/* Step card - positioned near target or centered */}
      <div
        className="absolute z-10 flex flex-col items-center gap-6 px-4"
        style={
          targetRect
            ? {
                top: targetRect.bottom + 16,
                left: targetRect.left,
                right: window.innerWidth - targetRect.right,
                alignItems: "flex-start",
              }
            : {
                top: "50%",
                left: "50%",
                transform: "translate(-50%, -50%)",
              }
        }
      >
        <OnboardingStep
          title={step.title}
          description={step.description}
          icon={step.icon}
        />

        {/* Progress & actions */}
        <div className="flex w-full max-w-[400px] items-center justify-between gap-4">
          <span className="text-sm text-content-muted">
            {currentStep + 1} de {totalSteps}
          </span>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={skip}
              className="rounded-lg px-3 py-1.5 text-sm font-medium text-content-muted hover:bg-surface-elevated hover:text-content-primary transition-colors"
            >
              Pular
            </button>
            {!isFirst && (
              <button
                type="button"
                onClick={prev}
                className="rounded-lg px-3 py-1.5 text-sm font-medium text-content-secondary hover:bg-surface-elevated hover:text-content-primary transition-colors"
              >
                Anterior
              </button>
            )}
            <button
              type="button"
              onClick={isLast ? complete : next}
              className="rounded-lg bg-brand px-4 py-1.5 text-sm font-medium text-white hover:brightness-110 transition-colors"
            >
              {isLast ? "Concluir" : "Próximo"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
