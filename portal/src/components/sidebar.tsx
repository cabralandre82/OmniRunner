"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useEffect, useCallback } from "react";
import { LocaleSwitcher } from "./locale-switcher";
import { ThemeToggle } from "./theme-toggle";

interface NavItem {
  href: string;
  label: string;
  roles: string[];
}

interface NavGroup {
  key: string;
  label: string;
  icon: React.ReactNode;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    key: "overview",
    label: "Visão Geral",
    icon: (
      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z" />
      </svg>
    ),
    items: [
      { href: "/dashboard", label: "Dashboard", roles: ["admin_master", "coach", "assistant"] },
    ],
  },
  {
    key: "athletes",
    label: "Atletas",
    icon: (
      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
      </svg>
    ),
    items: [
      { href: "/athletes", label: "Atletas", roles: ["admin_master", "coach", "assistant"] },
      { href: "/verification", label: "Verificação", roles: ["admin_master", "coach", "assistant"] },
      { href: "/crm", label: "CRM Atletas", roles: ["admin_master", "coach", "assistant"] },
      { href: "/risk", label: "Alertas/Risco", roles: ["admin_master", "coach"] },
    ],
  },
  {
    key: "engagement",
    label: "Engajamento",
    icon: (
      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 3v11.25A2.25 2.25 0 006 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0118 16.5h-2.25m-7.5 0h7.5m-7.5 0l-1 3m8.5-3l1 3m0 0l.5 1.5m-.5-1.5h-9.5m0 0l-.5 1.5" />
      </svg>
    ),
    items: [
      { href: "/engagement", label: "Engajamento", roles: ["admin_master", "coach", "assistant"] },
      { href: "/attendance", label: "Treinos Prescritos", roles: ["admin_master", "coach", "assistant"] },
      { href: "/attendance-analytics", label: "Análise de Treinos", roles: ["admin_master", "coach", "assistant"] },
      { href: "/announcements", label: "Mural", roles: ["admin_master", "coach", "assistant"] },
      { href: "/communications", label: "Comunicação", roles: ["admin_master", "coach"] },
    ],
  },
  {
    key: "training",
    label: "Treinos",
    icon: (
      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M15.362 5.214A8.252 8.252 0 0112 21 8.25 8.25 0 016.038 7.048 8.287 8.287 0 009 9.6a8.983 8.983 0 013.361-6.867 8.21 8.21 0 003 2.48z" />
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 18a3.75 3.75 0 00.495-7.467 5.99 5.99 0 00-1.925 3.546 5.974 5.974 0 01-2.133-1.001A3.75 3.75 0 0012 18z" />
      </svg>
    ),
    items: [
      { href: "/training-plan", label: "Planilhas de Treino", roles: ["admin_master", "coach"] },
      { href: "/workouts", label: "Templates", roles: ["admin_master", "coach"] },
      { href: "/workouts/assign", label: "Atribuir Treinos", roles: ["admin_master", "coach"] },
      { href: "/workouts/analytics", label: "Análise Treinos", roles: ["admin_master", "coach"] },
      { href: "/delivery", label: "Entrega Treinos", roles: ["admin_master", "coach"] },
      { href: "/executions", label: "Execuções", roles: ["admin_master", "coach", "assistant"] },
      { href: "/championships", label: "Campeonatos", roles: ["admin_master", "coach"] },
      { href: "/matchmaking", label: "Matchmaking", roles: ["admin_master", "coach"] },
      { href: "/league", label: "Liga", roles: ["admin_master", "coach"] },
      { href: "/trainingpeaks", label: "TrainingPeaks", roles: ["admin_master", "coach"] },
    ],
  },
  {
    key: "financial",
    label: "Financeiro",
    icon: (
      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v12m-3-2.818l.879.659c1.171.879 3.07.879 4.242 0 1.172-.879 1.172-2.303 0-3.182C13.536 12.219 12.768 12 12 12c-.725 0-1.45-.22-2.003-.659-1.106-.879-1.106-2.303 0-3.182s2.9-.879 4.006 0l.415.33M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    ),
    items: [
      { href: "/financial", label: "Dashboard", roles: ["admin_master", "coach"] },
      { href: "/financial/plans", label: "Planos", roles: ["admin_master", "coach"] },
      { href: "/financial/subscriptions/assign", label: "Atribuir Plano", roles: ["admin_master", "coach"] },
      { href: "/financial/subscriptions", label: "Assinaturas", roles: ["admin_master", "coach"] },
      { href: "/financial/webhook-events", label: "Histórico de Cobranças", roles: ["admin_master"] },
      { href: "/custody", label: "Saldo OmniCoins", roles: ["admin_master"] },
      { href: "/clearing", label: "Transferências OmniCoins", roles: ["admin_master", "coach"] },
      { href: "/distributions", label: "Distribuir OmniCoins", roles: ["admin_master", "coach"] },
      { href: "/audit", label: "Auditoria", roles: ["admin_master", "coach"] },
    ],
  },
  {
    key: "settings",
    label: "Configurações",
    icon: (
      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
        <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
      </svg>
    ),
    items: [
      { href: "/settings", label: "Configurações", roles: ["admin_master", "coach", "assistant"] },
      { href: "/settings/payments", label: "Pagamentos", roles: ["admin_master"] },
      { href: "/exports", label: "Exports", roles: ["admin_master", "coach"] },
      { href: "/badges", label: "Badges", roles: ["admin_master", "coach"] },
      { href: "/help", label: "Central de Ajuda", roles: ["admin_master", "coach", "assistant"] },
      { href: "/glossary", label: "Glossário", roles: ["admin_master", "coach", "assistant"] },
      { href: "/beta", label: "Programa Beta", roles: ["admin_master", "coach"] },
    ],
  },
];

const ROLE_LABELS: Record<string, string> = {
  admin_master: "Administrador",
  coach: "Treinador",
  assistant: "Assistente",
  athlete: "Atleta",
};

const PLATFORM_ITEMS: NavItem[] = [
  { href: "/platform/assessorias", label: "Admin Plataforma", roles: ["platform_admin"] },
];

function useCollapsibleGroups(pathname: string, groups: NavGroup[], role: string, trainingpeaksEnabled: boolean) {
  const visibleGroups = groups
    .map((g) => ({
      ...g,
      items: g.items.filter(
        (item) =>
          item.roles.includes(role) &&
          (item.href !== "/trainingpeaks" || trainingpeaksEnabled),
      ),
    }))
    .filter((g) => g.items.length > 0);

  const activeGroupKey = visibleGroups.find((g) =>
    g.items.some((item) => pathname.startsWith(item.href)),
  )?.key;

  const [expanded, setExpanded] = useState<Record<string, boolean>>(() => {
    const init: Record<string, boolean> = {};
    for (const g of visibleGroups) {
      init[g.key] = g.items.some((item) => pathname.startsWith(item.href));
    }
    return init;
  });

  useEffect(() => {
    if (activeGroupKey) {
      setExpanded((prev) => ({ ...prev, [activeGroupKey]: true }));
    }
  }, [activeGroupKey]);

  const toggle = useCallback((key: string) => {
    setExpanded((prev) => ({ ...prev, [key]: !prev[key] }));
  }, []);

  return { visibleGroups, expanded, toggle };
}

export function Sidebar({
  role,
  isPlatformAdmin = false,
  logoUrl,
  groupName,
  trainingpeaksEnabled = false,
}: {
  role: string;
  isPlatformAdmin?: boolean;
  logoUrl?: string | null;
  groupName?: string;
  trainingpeaksEnabled?: boolean;
}) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const { visibleGroups, expanded, toggle } = useCollapsibleGroups(
    pathname,
    NAV_GROUPS,
    role,
    trainingpeaksEnabled,
  );

  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  useEffect(() => {
    const handler = () => setOpen((prev) => !prev);
    window.addEventListener("toggle-sidebar", handler);
    return () => window.removeEventListener("toggle-sidebar", handler);
  }, []);

  const navContent = (
    <>
      <div className="border-b border-border-subtle px-4 py-5 flex items-center justify-between opacity-20">
      </div>
      <div className="px-4 py-5 flex items-center justify-between" style={{ marginTop: "-3.5rem" }}>
        <div className="flex items-center gap-2.5 min-w-0">
          {logoUrl ? (
            <Image src={logoUrl} alt="Logo" width={32} height={32} className="rounded-lg object-cover flex-shrink-0" />
          ) : (
            <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-brand text-sm font-bold text-white flex-shrink-0">
              {(groupName ?? "O").charAt(0).toUpperCase()}
            </span>
          )}
          <div className="min-w-0">
            <h2 className="text-sm font-bold text-content-primary truncate">
              {groupName ?? "Omni Runner"}
            </h2>
            <p className="text-xs text-content-muted">Portal</p>
          </div>
        </div>
        <button
          onClick={() => setOpen(false)}
          className="rounded-lg p-1.5 text-content-muted hover:text-content-primary lg:hidden transition-colors"
          aria-label="Fechar menu"
        >
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto px-2 py-4 space-y-1" role="navigation" aria-label="Menu principal">
        {visibleGroups.length > 0 ? (
          visibleGroups.map((group) => {
            const isOpen = expanded[group.key] ?? false;
            const hasActive = group.items.some((item) => pathname.startsWith(item.href));

            const onboardingKey = group.key === "overview" ? "dashboard" : group.key;
            return (
              <div key={group.key} data-onboarding={onboardingKey}>
                <button
                  onClick={() => toggle(group.key)}
                  aria-expanded={isOpen}
                  aria-controls={`nav-group-${group.key}`}
                  className={`flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs font-semibold uppercase tracking-wide transition-colors ${
                    hasActive
                      ? "text-brand"
                      : "text-content-muted hover:text-content-primary"
                  }`}
                >
                  {group.icon}
                  <span className="flex-1 text-left">{group.label}</span>
                  <svg
                    className={`h-3.5 w-3.5 transition-transform duration-150 ${isOpen ? "rotate-90" : ""}`}
                    fill="none"
                    viewBox="0 0 24 24"
                    strokeWidth={2}
                    stroke="currentColor"
                  >
                    <path strokeLinecap="round" strokeLinejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
                  </svg>
                </button>

                {isOpen && (
                  <div id={`nav-group-${group.key}`} className="ml-3 space-y-0.5 border-l border-border-subtle pl-3 pb-1">
                    {group.items.map((item) => {
                      const active = pathname.startsWith(item.href);
                      const onboardingItemKey = item.href.replace(/^\//, "").replace(/\//g, "-");
                      return (
                        <Link
                          key={item.href}
                          href={item.href}
                          data-onboarding={onboardingItemKey}
                          aria-current={active ? "page" : undefined}
                          className={`block rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
                            active
                              ? "bg-brand-soft text-brand"
                              : "text-content-secondary hover:bg-surface-elevated hover:text-content-primary"
                          }`}
                        >
                          {item.label}
                        </Link>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })
        ) : (
          <p className="px-3 py-2 text-sm text-content-muted">Sem itens de menu</p>
        )}
      </nav>

      {isPlatformAdmin && (
        <div className="border-t border-border px-2 py-2">
          {PLATFORM_ITEMS.map((item) => {
            const active = pathname.startsWith(item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`block rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                  active
                    ? "bg-error-soft text-error"
                    : "text-content-muted hover:bg-surface-elevated hover:text-content-primary"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </div>
      )}

      <div className="border-t border-border px-2 py-2 space-y-0.5">
        <LocaleSwitcher />
        <ThemeToggle />
      </div>

      <div className="border-t border-border px-4 py-3">
        <p className="truncate text-xs text-content-muted">{ROLE_LABELS[role] ?? role}</p>
      </div>
    </>
  );

  return (
    <>
      <aside className="hidden lg:flex h-screen w-56 flex-shrink-0 flex-col border-r border-border bg-bg-secondary">
        {navContent}
      </aside>

      {open && (
        <div
          className="fixed inset-0 z-40 bg-overlay lg:hidden"
          onClick={() => setOpen(false)}
          aria-hidden="true"
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-border bg-bg-secondary shadow-lg transition-transform duration-200 lg:hidden ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        {navContent}
      </aside>
    </>
  );
}

export function SidebarTrigger() {
  return (
    <button
      onClick={() => {
        window.dispatchEvent(new CustomEvent("toggle-sidebar"));
      }}
      className="rounded-lg p-2 text-content-muted hover:bg-surface-elevated hover:text-content-primary lg:hidden transition-colors"
      aria-label="Abrir menu"
    >
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
      </svg>
    </button>
  );
}
