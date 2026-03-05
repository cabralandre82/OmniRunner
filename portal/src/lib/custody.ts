import { createServiceClient } from "@/lib/supabase/service";

export interface CustodyAccount {
  id: string;
  group_id: string;
  total_deposited_usd: number;
  total_committed: number;
  total_settled_usd: number;
  is_blocked: boolean;
  blocked_reason: string | null;
  available: number;
}

export interface CustodyDeposit {
  id: string;
  group_id: string;
  amount_usd: number;
  coins_equivalent: number;
  payment_gateway: string;
  payment_reference: string | null;
  status: string;
  created_at: string;
  confirmed_at: string | null;
}

function isTableMissing(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return /PGRST|does not exist|custody_accounts|custody_deposits|custody_withdrawals/.test(msg);
}

export async function getCustodyAccount(groupId: string): Promise<CustodyAccount | null> {
  try {
    const db = createServiceClient();
    const { data } = await db
      .from("custody_accounts")
      .select("*")
      .eq("group_id", groupId)
      .maybeSingle();

    if (!data) return null;

    return {
      ...data,
      available: data.total_deposited_usd - data.total_committed,
    };
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

export async function getOrCreateCustodyAccount(groupId: string): Promise<CustodyAccount | null> {
  try {
    const existing = await getCustodyAccount(groupId);
    if (existing) return existing;

    const db = createServiceClient();
    const { data } = await db
      .from("custody_accounts")
      .insert({ group_id: groupId })
      .select("*")
      .single();

    return {
      ...data!,
      available: 0,
    };
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

export async function getCustodyDeposits(groupId: string): Promise<CustodyDeposit[]> {
  try {
    const db = createServiceClient();
    const { data } = await db
      .from("custody_deposits")
      .select("*")
      .eq("group_id", groupId)
      .order("created_at", { ascending: false });

    return data ?? [];
  } catch (err) {
    if (isTableMissing(err)) return [];
    throw err;
  }
}

export async function createCustodyDeposit(
  groupId: string,
  amountUsd: number,
  gateway: "stripe" | "mercadopago",
): Promise<{ deposit: CustodyDeposit; checkoutUrl?: string } | null> {
  try {
    const db = createServiceClient();
    const coinsEquivalent = Math.floor(amountUsd);

    const { data: deposit, error } = await db
      .from("custody_deposits")
      .insert({
        group_id: groupId,
        amount_usd: amountUsd,
        coins_equivalent: coinsEquivalent,
        payment_gateway: gateway,
        status: "pending",
      })
      .select("*")
      .single();

    if (error || !deposit) {
      throw new Error(error?.message ?? "Failed to create deposit");
    }

    return { deposit };
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

export async function confirmDeposit(depositId: string): Promise<void> {
  const db = createServiceClient();
  const { error } = await db.rpc("confirm_custody_deposit", {
    p_deposit_id: depositId,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function commitCoins(groupId: string, coinCount: number): Promise<void> {
  const db = createServiceClient();
  const { error } = await db.rpc("custody_commit_coins", {
    p_group_id: groupId,
    p_coin_count: coinCount,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function isEmissionAllowed(groupId: string, coinCount: number): Promise<boolean> {
  const account = await getCustodyAccount(groupId);
  if (!account) return false;
  if (account.is_blocked) return false;
  return account.available >= coinCount;
}

/**
 * Release committed backing when coins are burned (intra-club).
 * R -= coinCount, A += coinCount. D stays the same.
 */
export async function releaseCommitted(groupId: string, coinCount: number): Promise<void> {
  const db = createServiceClient();
  const { error } = await db.rpc("custody_release_committed", {
    p_group_id: groupId,
    p_coin_count: coinCount,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export interface InvariantViolation {
  group_id: string;
  total_deposited: number;
  total_committed: number;
  computed_available: number;
  violation: string;
}

/**
 * Check all custody accounts for invariant violations.
 * Returns empty array if system is healthy.
 */
export async function checkInvariants(): Promise<InvariantViolation[]> {
  try {
    const db = createServiceClient();
    const { data, error } = await db.rpc("check_custody_invariants");

    if (error) {
      throw new Error(error.message);
    }

    return data ?? [];
  } catch (err) {
    if (isTableMissing(err)) return [];
    throw err;
  }
}

// --- FX Spread ---

export async function getFxSpreadRate(): Promise<number> {
  const db = createServiceClient();
  const { data } = await db
    .from("platform_fee_config")
    .select("rate_pct")
    .eq("fee_type", "fx_spread")
    .eq("is_active", true)
    .maybeSingle();

  return data?.rate_pct ?? 0.75;
}

/**
 * Convert local currency to USD with FX spread applied.
 * Returns the net USD amount after spread deduction.
 */
export function convertToUsdWithSpread(
  localAmount: number,
  fxRate: number,
  spreadPct: number,
): { amountUsd: number; spreadUsd: number } {
  const rawUsd = localAmount / fxRate;
  const spreadUsd = rawUsd * (spreadPct / 100);
  const amountUsd = rawUsd - spreadUsd;
  return {
    amountUsd: Math.round(amountUsd * 100) / 100,
    spreadUsd: Math.round(spreadUsd * 100) / 100,
  };
}

/**
 * Convert USD to local currency with FX spread applied on exit.
 */
export function convertFromUsdWithSpread(
  amountUsd: number,
  fxRate: number,
  spreadPct: number,
): { localAmount: number; spreadUsd: number } {
  const spreadUsd = amountUsd * (spreadPct / 100);
  const netUsd = amountUsd - spreadUsd;
  const localAmount = netUsd * fxRate;
  return {
    localAmount: Math.round(localAmount * 100) / 100,
    spreadUsd: Math.round(spreadUsd * 100) / 100,
  };
}

// --- Deposits with FX ---

export async function createCustodyDepositWithFx(
  groupId: string,
  amountUsd: number,
  gateway: "stripe" | "mercadopago",
  fx?: { originalCurrency: string; originalAmount: number; fxRate: number; spreadPct: number },
): Promise<{ deposit: CustodyDeposit } | null> {
  try {
    const db = createServiceClient();
    const coinsEquivalent = Math.floor(amountUsd);

    const { data: deposit, error } = await db
      .from("custody_deposits")
      .insert({
        group_id: groupId,
        amount_usd: amountUsd,
        coins_equivalent: coinsEquivalent,
        payment_gateway: gateway,
        status: "pending",
        original_currency: fx?.originalCurrency ?? "USD",
        original_amount: fx?.originalAmount ?? amountUsd,
        fx_rate: fx?.fxRate ?? 1.0,
        fx_spread_pct: fx?.spreadPct ?? 0,
      })
      .select("*")
      .single();

    if (error || !deposit) throw new Error(error?.message ?? "Failed to create deposit");
    return { deposit };
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

/**
 * Confirm deposit by payment_reference (idempotent — webhook-safe).
 */
export async function confirmDepositByReference(paymentReference: string): Promise<{ depositId: string; alreadyConfirmed: boolean } | null> {
  try {
    const db = createServiceClient();

    const { data: existing } = await db
      .from("custody_deposits")
      .select("id, status")
      .eq("payment_reference", paymentReference)
      .maybeSingle();

    if (!existing) throw new Error(`No deposit found for reference: ${paymentReference}`);
    if (existing.status === "confirmed") return { depositId: existing.id, alreadyConfirmed: true };
    if (existing.status !== "pending") throw new Error(`Deposit status is ${existing.status}`);

    await confirmDeposit(existing.id);
    return { depositId: existing.id, alreadyConfirmed: false };
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

// --- Withdrawals ---

export interface CustodyWithdrawal {
  id: string;
  group_id: string;
  amount_usd: number;
  target_currency: string;
  fx_rate: number;
  fx_spread_pct: number;
  fx_spread_usd: number;
  provider_fee_usd: number;
  net_local_amount: number;
  payout_reference: string | null;
  status: string;
  created_at: string;
  completed_at: string | null;
}

export async function createWithdrawal(params: {
  groupId: string;
  amountUsd: number;
  targetCurrency: string;
  fxRate: number;
  spreadPct: number;
  providerFeeUsd?: number;
}): Promise<CustodyWithdrawal | null> {
  try {
    const account = await getCustodyAccount(params.groupId);
    if (!account) throw new Error("No custody account");
    if (account.is_blocked) throw new Error("Account is blocked");
    if (account.available < params.amountUsd) {
      throw new Error(`Insufficient available: ${account.available} < ${params.amountUsd}`);
    }

    const providerFee = params.providerFeeUsd ?? 0;
    const { localAmount, spreadUsd } = convertFromUsdWithSpread(
      params.amountUsd - providerFee,
      params.fxRate,
      params.spreadPct,
    );

    const db = createServiceClient();
    const { data, error } = await db
      .from("custody_withdrawals")
      .insert({
        group_id: params.groupId,
        amount_usd: params.amountUsd,
        target_currency: params.targetCurrency,
        fx_rate: params.fxRate,
        fx_spread_pct: params.spreadPct,
        fx_spread_usd: spreadUsd,
        provider_fee_usd: providerFee,
        net_local_amount: localAmount,
        status: "pending",
      })
      .select("*")
      .single();

    if (error || !data) throw new Error(error?.message ?? "Failed to create withdrawal");
    return data;
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

export async function executeWithdrawal(withdrawalId: string): Promise<void> {
  const db = createServiceClient();
  const { error } = await db.rpc("execute_withdrawal", { p_withdrawal_id: withdrawalId });
  if (error) throw new Error(error.message);
}

export async function getWithdrawals(groupId: string): Promise<CustodyWithdrawal[]> {
  try {
    const db = createServiceClient();
    const { data } = await db
      .from("custody_withdrawals")
      .select("*")
      .eq("group_id", groupId)
      .order("created_at", { ascending: false });
    return data ?? [];
  } catch (err) {
    if (isTableMissing(err)) return [];
    throw err;
  }
}

/**
 * Pre-operation invariant gate.
 * Returns true if system is healthy, false if violations exist.
 * Use before critical custody/clearing/swap operations.
 */
export async function assertInvariantsHealthy(): Promise<boolean> {
  const violations = await checkInvariants();
  return violations.length === 0;
}
