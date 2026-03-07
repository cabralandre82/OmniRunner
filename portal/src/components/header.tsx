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
  production: { label: "PROD", color: "bg-success-soft text-success" },
  sandbox: { label: "SANDBOX", color: "bg-warning-soft text-warning" },
  staging: { label: "STAGING", color: "bg-info-soft text-info" },
};

const ROLE_LABELS: Record<string, string> = {
  admin_master: "Administrador",
  coach: "Treinador",
  assistant: "Assistente",
  athlete: "Atleta",
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
    <header className="flex h-14 items-center justify-between border-b border-border bg-surface px-4 sm:px-6">
      <div className="flex items-center gap-2 sm:gap-3 min-w-0">
        <SidebarTrigger />
        <h3 className="truncate text-sm font-semibold text-content-primary">
          {groupName}
        </h3>
        <span className={`hidden sm:inline-flex rounded-full px-2 py-0.5 text-[10px] font-bold uppercase ${env.color}`}>
          {env.label}
        </span>
        <span className="hidden sm:inline-flex rounded-full bg-neutral-soft px-2 py-0.5 text-[10px] font-medium text-content-secondary uppercase">
          {ROLE_LABELS[role] ?? role}
        </span>
        {isBlocked && (
          <span className="inline-flex rounded-full bg-error-soft px-2 py-0.5 text-[10px] font-bold text-error uppercase">
            Bloqueado
          </span>
        )}
        {multiGroup && (
          <form action={clearPortalGroup}>
            <button
              type="submit"
              aria-label="Trocar grupo"
              className="flex-shrink-0 rounded-lg bg-surface-elevated px-2 py-0.5 text-xs text-content-muted hover:text-content-primary hover:bg-bg-secondary transition-colors"
            >
              trocar
            </button>
          </form>
        )}
      </div>

      <div className="flex items-center gap-2 sm:gap-4">
        <span className="hidden text-xs text-content-muted sm:inline">
          {userEmail}
        </span>
        <form action={signOut} aria-label="Menu do usuário">
          <button
            type="submit"
            aria-label="Sair da conta"
            className="rounded-lg px-3 py-1.5 text-xs font-medium text-content-secondary hover:bg-surface-elevated hover:text-content-primary transition-colors"
          >
            Sair
          </button>
        </form>
      </div>
    </header>
  );
}
