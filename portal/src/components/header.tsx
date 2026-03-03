"use client";

import { signOut, clearPortalGroup } from "@/lib/actions";
import { SidebarTrigger } from "@/components/sidebar";

interface HeaderProps {
  groupName: string;
  userEmail: string;
  multiGroup: boolean;
  role?: string;
  environment?: string;
  isBlocked?: boolean;
}

const ENV_BADGE: Record<string, { label: string; color: string }> = {
  production: { label: "PROD", color: "bg-green-100 text-green-800" },
  sandbox: { label: "SANDBOX", color: "bg-yellow-100 text-yellow-800" },
  staging: { label: "STAGING", color: "bg-blue-100 text-blue-800" },
};

const ROLE_LABELS: Record<string, string> = {
  admin_master: "Admin",
  coach: "Coach",
  assistant: "Assistente",
};

export function Header({
  groupName,
  userEmail,
  multiGroup,
  role = "assistant",
  environment = "production",
  isBlocked = false,
}: HeaderProps) {
  const env = ENV_BADGE[environment] ?? ENV_BADGE.production;

  return (
    <header className="flex h-14 items-center justify-between border-b border-gray-200 bg-white px-4 sm:px-6">
      <div className="flex items-center gap-2 sm:gap-3 min-w-0">
        <SidebarTrigger />
        <h3 className="truncate text-sm font-semibold text-gray-900">
          {groupName}
        </h3>
        <span className={`hidden sm:inline-flex rounded-full px-2 py-0.5 text-[10px] font-bold uppercase ${env.color}`}>
          {env.label}
        </span>
        <span className="hidden sm:inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-medium text-gray-600 uppercase">
          {ROLE_LABELS[role] ?? role}
        </span>
        {isBlocked && (
          <span className="inline-flex rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-bold text-red-800 uppercase">
            Bloqueado
          </span>
        )}
        {multiGroup && (
          <form action={clearPortalGroup}>
            <button
              type="submit"
              className="flex-shrink-0 rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-500 hover:bg-gray-200"
            >
              trocar
            </button>
          </form>
        )}
      </div>

      <div className="flex items-center gap-2 sm:gap-4">
        <span className="hidden text-xs text-gray-500 sm:inline">
          {userEmail}
        </span>
        <form action={signOut}>
          <button
            type="submit"
            className="rounded-lg px-3 py-1.5 text-xs font-medium text-gray-600 hover:bg-gray-100"
          >
            Sair
          </button>
        </form>
      </div>
    </header>
  );
}
