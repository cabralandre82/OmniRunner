"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

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
  { href: "/platform/assessorias", label: "⚙ Admin Plataforma", roles: ["platform_admin"] },
];

export function Sidebar({
  role,
  isPlatformAdmin = false,
}: {
  role: string;
  isPlatformAdmin?: boolean;
}) {
  const pathname = usePathname();

  const visibleItems = NAV_ITEMS.filter((item) => item.roles.includes(role));

  return (
    <aside className="flex h-screen w-56 flex-col border-r border-gray-200 bg-white">
      <div className="border-b border-gray-200 px-4 py-5">
        <h2 className="text-lg font-bold text-gray-900">Omni Runner</h2>
        <p className="text-xs text-gray-500">Portal</p>
      </div>

      <nav className="flex-1 space-y-1 px-2 py-4">
        {visibleItems.map((item) => {
          const active = pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`block rounded-lg px-3 py-2 text-sm font-medium transition ${
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
                className={`block rounded-lg px-3 py-2 text-sm font-medium transition ${
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
    </aside>
  );
}
