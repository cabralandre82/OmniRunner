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
      <div className="border-b border-gray-200 px-4 py-5 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-gray-900">Omni Runner</h2>
          <p className="text-xs text-red-500 font-semibold">Admin Plataforma</p>
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

      <nav className="flex-1 space-y-1 px-2 py-4">
        <SidebarLink href="/platform" label="Dashboard" pathname={pathname} exact />
        <SidebarLink href="/platform/assessorias" label="Assessorias" pathname={pathname} />
        <SidebarLink href="/platform/financeiro" label="Financeiro" pathname={pathname} />
        <SidebarLink href="/platform/reembolsos" label="Reembolsos" pathname={pathname} />
        <SidebarLink href="/platform/produtos" label="Produtos" pathname={pathname} />
        <SidebarLink href="/platform/liga" label="Liga" pathname={pathname} />
        <SidebarLink href="/platform/support" label="Suporte" pathname={pathname} />
        <Link
          href="/select-group"
          className="block rounded-lg px-3 py-2.5 text-sm font-medium text-gray-400 hover:bg-gray-50 hover:text-gray-600"
        >
          ← Portal Assessoria
        </Link>
      </nav>

      <div className="border-t border-gray-200 px-4 py-3 space-y-2">
        <p className="truncate text-xs text-gray-400">{email}</p>
        <form action={signOut}>
          <button
            type="submit"
            className="w-full rounded-lg px-3 py-1.5 text-xs font-medium text-gray-600 hover:bg-gray-100 text-left"
          >
            Sair
          </button>
        </form>
      </div>
    </>
  );

  return (
    <>
      <aside className="hidden lg:flex h-screen w-56 flex-shrink-0 flex-col border-r border-gray-200 bg-white">
        {content}
      </aside>

      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/30 lg:hidden"
          onClick={() => setOpen(false)}
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-white shadow-xl transition-transform duration-200 lg:hidden ${
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
          ? "bg-red-50 text-red-700"
          : "text-gray-600 hover:bg-gray-50 hover:text-gray-900"
      }`}
    >
      {label}
    </Link>
  );
}
