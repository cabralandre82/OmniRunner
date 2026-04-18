/**
 * Pure functions for billing business logic edge cases.
 */

export function sanitizeCpf(cpf: string): string {
  return cpf.replace(/\D/g, "");
}

export function validateCpf(cpf: string): boolean {
  const digits = sanitizeCpf(cpf);
  if (digits.length !== 11) return false;
  if (!/^\d+$/.test(digits)) return false;
  if (/^(\d)\1{10}$/.test(digits)) return false;
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += parseInt(digits[i], 10) * (10 - i);
  let d1 = (sum * 10) % 11;
  if (d1 === 10) d1 = 0;
  if (d1 !== parseInt(digits[9], 10)) return false;
  sum = 0;
  for (let i = 0; i < 10; i++) sum += parseInt(digits[i], 10) * (11 - i);
  let d2 = (sum * 10) % 11;
  if (d2 === 10) d2 = 0;
  return d2 === parseInt(digits[10], 10);
}

/**
 * L01-17: canActivateBilling now inspects the vault secret reference
 * (api_key_secret_id) instead of the plaintext api_key column.
 * The column was dropped — server-side config rows carry only the UUID
 * pointing into vault.secrets.
 */
export function canActivateBilling(config: {
  is_active: boolean;
  api_key_secret_id: string | null;
  webhook_id: string | null;
}): { ok: boolean; reason?: string } {
  if (!config.api_key_secret_id) {
    return { ok: false, reason: "api_key is required" };
  }
  if (!config.webhook_id || config.webhook_id.trim() === "") {
    return { ok: false, reason: "webhook_id is required" };
  }
  return { ok: true };
}

export function shouldCreateAsaasSubscription(
  subscription: { status: string },
  existingMapping: { asaas_subscription_id: string } | null
): boolean {
  if (existingMapping?.asaas_subscription_id) return false;
  if (subscription.status === "cancelled") return false;
  return true;
}

export function calculateSplitValue(
  totalValue: number,
  splitPct: number
): { assessoriaValue: number; platformValue: number } {
  const assessoriaValue = Math.round((totalValue * splitPct) / 100 * 100) / 100;
  const platformValue = Math.round((totalValue - assessoriaValue) * 100) / 100;
  return { assessoriaValue, platformValue };
}
