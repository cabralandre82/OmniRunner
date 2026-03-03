"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useEffect } from "react";

interface NavItem {
  href: string;
  label: string;
  roles: string[];
}

const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", roles: ["admin_master", "coach", "assistant"] },
  { href: "/custody", label: "Custódia", roles: ["admin_master"] },
  { href: "/clearing", label: "Compensações", roles: ["admin_master", "coach"] },
  { href: "/swap", label: "Swap de Lastro", roles: ["admin_master"] },
  { href: "/fx", label: "Conversao Cambial", roles: ["admin_master"] },
  { href: "/badges", label: "Badges", roles: ["admin_master", "coach"] },
  { href: "/audit", label: "Auditoria", roles: ["admin_master", "coach"] },
  { href: "/distributions", label: "Distribuições", roles: ["admin_master", "coach"] },
  { href: "/athletes", label: "Atletas", roles: ["admin_master", "coach", "assistant"] },
  { href: "/verification", label: "Verificação", roles: ["admin_master", "coach", "assistant"] },
  { href: "/engagement", label: "Engajamento", roles: ["admin_master", "coach", "assistant"] },
  { href: "/attendance", label: "Presença", roles: ["admin_master", "coach", "assistant"] },
  { href: "/crm", label: "CRM Atletas", roles: ["admin_master", "coach", "assistant"] },
  { href: "/announcements", label: "Mural", roles: ["admin_master", "coach", "assistant"] },
  { href: "/communications", label: "Comunicação", roles: ["admin_master", "coach"] },
  { href: "/attendance-analytics", label: "Análise Presença", roles: ["admin_master", "coach", "assistant"] },
  { href: "/risk", label: "Alertas/Risco", roles: ["admin_master", "coach"] },
  { href: "/exports", label: "Exports", roles: ["admin_master", "coach"] },
  { href: "/workouts", label: "Treinos", roles: ["admin_master", "coach"] },
  { href: "/workouts/analytics", label: "Análise Treinos", roles: ["admin_master", "coach"] },
  { href: "/trainingpeaks", label: "TrainingPeaks", roles: ["admin_master", "coach"] },
  { href: "/financial", label: "Financeiro", roles: ["admin_master", "coach"] },
  { href: "/executions", label: "Execuções", roles: ["admin_master", "coach", "assistant"] },
  { href: "/settings", label: "Configurações", roles: ["admin_master", "coach", "assistant"] },
];

const PLATFORM_ITEMS: NavItem[] = [
  { href: "/platform/assessorias", label: "Admin Plataforma", roles: ["platform_admin"] },
];

export function Sidebar({
  role,
  isPlatformAdmin = false,
  logoUrl,
  groupName,
}: {
  role: string;
  isPlatformAdmin?: boolean;
  logoUrl?: string | null;
  groupName?: string;
}) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  useEffect(() => {
    const handler = () => setOpen((prev) => !prev);
    window.addEventListener("toggle-sidebar", handler);
    return () => window.removeEventListener("toggle-sidebar", handler);
  }, []);

  const visibleItems = NAV_ITEMS.filter((item) => item.roles.includes(role));

  const navContent = (
    <>
      <div className="border-b px-4 py-5 flex items-center justify-between" style={{ borderColor: "var(--brand-sidebar-text, #e5e7eb)", opacity: 0.2 }}>
      </div>
      <div className="px-4 py-5 flex items-center justify-between" style={{ marginTop: "-3.5rem" }}>
        <div className="flex items-center gap-2.5 min-w-0">
          {logoUrl ? (
            <Image src={logoUrl} alt="Logo" width={32} height={32} className="rounded-lg object-cover flex-shrink-0" />
          ) : (
            <span
              className="flex h-8 w-8 items-center justify-center rounded-lg text-sm font-bold text-white flex-shrink-0"
              style={{ backgroundColor: "var(--brand-primary, #2563eb)" }}
            >
              {(groupName ?? "O").charAt(0).toUpperCase()}
            </span>
          )}
          <div className="min-w-0">
            <h2 className="text-sm font-bold truncate" style={{ color: "var(--brand-sidebar-text, #111827)" }}>
              {groupName ?? "Omni Runner"}
            </h2>
            <p className="text-xs opacity-60" style={{ color: "var(--brand-sidebar-text, #6b7280)" }}>Portal</p>
          </div>
        </div>
        <button
          onClick={() => setOpen(false)}
          className="rounded-lg p-1.5 opacity-50 hover:opacity-100 lg:hidden"
          style={{ color: "var(--brand-sidebar-text, #9ca3af)" }}
          aria-label="Fechar menu"
        >
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto px-2 py-4">
        {visibleItems.map((item) => {
          const active = pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className="block rounded-lg px-3 py-2.5 text-sm font-medium transition"
              style={
                active
                  ? {
                      backgroundColor: "var(--brand-accent, #2563eb)" + "18",
                      color: "var(--brand-accent, #2563eb)",
                    }
                  : {
                      color: "var(--brand-sidebar-text, #4b5563)",
                      opacity: 0.8,
                    }
              }
            >
              {item.label}
            </Link>
          );
        })}
      </nav>

      {isPlatformAdmin && (
        <div className="border-t border-gray-200 px-2 py-2">
          {PLATFORM_ITEMS.map((item) => {
            const active = pathname.startsWith(item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`block rounded-lg px-3 py-2.5 text-sm font-medium transition ${
                  active
                    ? "bg-red-50 text-red-700"
                    : "text-gray-500 hover:bg-gray-50 hover:text-gray-900"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </div>
      )}

      <div className="border-t px-4 py-3" style={{ borderColor: "var(--brand-sidebar-text, #e5e7eb)", opacity: 0.6 }}>
        <p className="truncate text-xs" style={{ color: "var(--brand-sidebar-text, #9ca3af)" }}>{role}</p>
      </div>
    </>
  );

  return (
    <>
      {/* Desktop sidebar */}
      <aside
        className="hidden lg:flex h-screen w-56 flex-shrink-0 flex-col border-r border-gray-200"
        style={{ backgroundColor: "var(--brand-sidebar-bg, #ffffff)" }}
      >
        {navContent}
      </aside>

      {/* Mobile overlay */}
      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/30 lg:hidden"
          onClick={() => setOpen(false)}
        />
      )}

      {/* Mobile drawer */}
      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-64 flex-col shadow-xl transition-transform duration-200 lg:hidden ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
        style={{ backgroundColor: "var(--brand-sidebar-bg, #ffffff)" }}
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
      className="rounded-lg p-2 text-gray-500 hover:bg-gray-100 lg:hidden"
      aria-label="Abrir menu"
    >
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
      </svg>
    </button>
  );
}
