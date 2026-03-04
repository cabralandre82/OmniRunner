/**
 * Canonical coaching role constants.
 *
 * Single source of truth — every role check in the portal must import from here.
 * DB values are lowercase ASCII, no accents.
 */

export const ROLE = {
  ADMIN_MASTER: "admin_master",
  COACH: "coach",
  ASSISTANT: "assistant",
  ATHLETE: "athlete",
} as const;

export type CoachingRole = (typeof ROLE)[keyof typeof ROLE];

/** Staff roles — can access the portal and manage the assessoria. */
export const STAFF_ROLES: readonly CoachingRole[] = [
  ROLE.ADMIN_MASTER,
  ROLE.COACH,
  ROLE.ASSISTANT,
] as const;

/** Roles that can manage members, events, custody, clearing. */
export const MANAGER_ROLES: readonly CoachingRole[] = [
  ROLE.ADMIN_MASTER,
  ROLE.COACH,
] as const;

export function isStaff(role: string): boolean {
  return (STAFF_ROLES as readonly string[]).includes(role);
}

export function isManager(role: string): boolean {
  return (MANAGER_ROLES as readonly string[]).includes(role);
}

export function isAdmin(role: string): boolean {
  return role === ROLE.ADMIN_MASTER;
}

/** Human-readable labels (pt-BR). */
export const ROLE_LABELS: Record<string, { label: string; color: string }> = {
  [ROLE.ADMIN_MASTER]: { label: "Admin", color: "bg-purple-100 text-purple-800" },
  [ROLE.COACH]: { label: "Coach", color: "bg-blue-100 text-blue-800" },
  [ROLE.ASSISTANT]: { label: "Assistente", color: "bg-surface-elevated text-content-secondary" },
  [ROLE.ATHLETE]: { label: "Atleta", color: "bg-success-soft text-success" },
};
