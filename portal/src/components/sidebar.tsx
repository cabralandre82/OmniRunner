"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useEffect } from "react";

interface NavItem {
  href: string;
  label: string;
  roles: string[];
}

const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", roles: ["admin_master", "professor", "assistente"] },
  { href: "/credits", label: "Créditos", roles: ["admin_master", "professor", "assistente"] },
  { href: "/billing", label: "Faturamento", roles: ["admin_master"] },
  { href: "/athletes", label: "Atletas", roles: ["admin_master", "professor", "assistente"] },
  { href: "/verification", label: "Verificação", roles: ["admin_master", "professor", "assistente"] },
  { href: "/engagement", label: "Engajamento", roles: ["admin_master", "professor", "assistente"] },
  { href: "/settings", label: "Configurações", roles: ["admin_master", "professor", "assistente"] },
];

const PLATFORM_ITEMS: NavItem[] = [
  { href: "/platform/assessorias", label: "Admin Plataforma", roles: ["platform_admin"] },
];

export function Sidebar({
  role,
  isPlatformAdmin = false,
}: {
  role: string;
  isPlatformAdmin?: boolean;
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
      <div className="border-b border-gray-200 px-4 py-5 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-gray-900">Omni Runner</h2>
          <p className="text-xs text-gray-500">Portal</p>
        </div>
        <button
          onClick={() => setOpen(false)}
          className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 lg:hidden"
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
              className={`block rounded-lg px-3 py-2.5 text-sm font-medium transition ${
                active
                  ? "bg-blue-50 text-blue-700"
                  : "text-gray-600 hover:bg-gray-50 hover:text-gray-900"
              }`}
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

      <div className="border-t border-gray-200 px-4 py-3">
        <p className="truncate text-xs text-gray-400">{role}</p>
      </div>
    </>
  );

  return (
    <>
      {/* Desktop sidebar */}
      <aside className="hidden lg:flex h-screen w-56 flex-shrink-0 flex-col border-r border-gray-200 bg-white">
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
        className={`fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-white shadow-xl transition-transform duration-200 lg:hidden ${
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
      className="rounded-lg p-2 text-gray-500 hover:bg-gray-100 lg:hidden"
      aria-label="Abrir menu"
    >
      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
      </svg>
    </button>
  );
}
