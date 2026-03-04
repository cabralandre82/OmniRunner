"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useEffect } from "react";
import { signOut } from "@/lib/actions";

export function PlatformSidebar({ email }: { email: string }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  useEffect(() => {
    const btn = document.getElementById("platform-menu-btn");
    if (!btn) return;
    const handler = () => setOpen((prev) => !prev);
    btn.addEventListener("click", handler);
    return () => btn.removeEventListener("click", handler);
  }, []);

  const content = (
    <>
      <div className="border-b border-border px-4 py-5 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-content-primary">Omni Runner</h2>
          <p className="text-xs text-red-500 font-semibold">Admin Plataforma</p>
        </div>
        <button
          onClick={() => setOpen(false)}
          className="rounded-lg p-1.5 text-content-muted hover:bg-bg-secondary lg:hidden"
          aria-label="Fechar menu"
        >
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <nav className="flex-1 space-y-1 px-2 py-4">
        <SidebarLink href="/platform" label="Dashboard" pathname={pathname} exact />
        <SidebarLink href="/platform/assessorias" label="Assessorias" pathname={pathname} />
        <SidebarLink href="/platform/financeiro" label="Financeiro" pathname={pathname} />
        <SidebarLink href="/platform/reembolsos" label="Reembolsos" pathname={pathname} />
        <SidebarLink href="/platform/produtos" label="Produtos" pathname={pathname} />
        <SidebarLink href="/platform/conquistas" label="Conquistas" pathname={pathname} />
        <SidebarLink href="/platform/liga" label="Liga" pathname={pathname} />
        <SidebarLink href="/platform/support" label="Suporte" pathname={pathname} />
        <SidebarLink href="/platform/fees" label="Taxas" pathname={pathname} />
        <SidebarLink href="/platform/invariants" label="Invariantes" pathname={pathname} />
        <SidebarLink href="/platform/feature-flags" label="Feature Flags" pathname={pathname} />
        <Link
          href="/select-group"
          className="block rounded-lg px-3 py-2.5 text-sm font-medium text-content-muted hover:bg-surface-elevated hover:text-content-secondary"
        >
          ← Portal Assessoria
        </Link>
      </nav>

      <div className="border-t border-border px-4 py-3 space-y-2">
        <p className="truncate text-xs text-content-muted">{email}</p>
        <form action={signOut}>
          <button
            type="submit"
            className="w-full rounded-lg px-3 py-1.5 text-xs font-medium text-content-secondary hover:bg-bg-secondary text-left"
          >
            Sair
          </button>
        </form>
      </div>
    </>
  );

  return (
    <>
      <aside className="hidden lg:flex h-screen w-56 flex-shrink-0 flex-col border-r border-border bg-surface">
        {content}
      </aside>

      {open && (
        <div
          className="fixed inset-0 z-40 bg-overlay lg:hidden"
          onClick={() => setOpen(false)}
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-surface shadow-lg transition-transform duration-200 lg:hidden ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        {content}
      </aside>
    </>
  );
}

function SidebarLink({
  href,
  label,
  pathname,
  exact = false,
}: {
  href: string;
  label: string;
  pathname: string;
  exact?: boolean;
}) {
  const active = exact
    ? pathname === href
    : pathname.startsWith(href) && (href !== "/platform" || pathname === "/platform");

  return (
    <Link
      href={href}
      className={`block rounded-lg px-3 py-2.5 text-sm font-medium transition ${
        active
          ? "bg-error-soft text-error"
          : "text-content-secondary hover:bg-surface-elevated hover:text-content-primary"
      }`}
    >
      {label}
    </Link>
  );
}
