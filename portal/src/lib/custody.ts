import { createServiceClient } from "@/lib/supabase/service";
import { roundToCents } from "@/lib/money";

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

/**
 * L01-04 — cria custody_deposit idempotente.
 *
 * `idempotencyKey` é OBRIGATÓRIO. O caller (route handler) deve:
 *   • Aceitar `x-idempotency-key` do cliente (UUID v4 recomendado).
 *   • Rejeitar requests sem header (force conscious idempotency).
 *
 * Reuso da mesma chave para o mesmo `groupId` retorna o deposit existente
 * (`wasIdempotent=true`) em vez de criar duplicata. Race entre dois
 * requests concorrentes com a mesma chave é resolvida pela RPC via
 * `unique_violation` capturado.
 */
export async function createCustodyDeposit(
  groupId: string,
  amountUsd: number,
  gateway: "stripe" | "mercadopago",
  idempotencyKey: string,
): Promise<{
  deposit: CustodyDeposit;
  wasIdempotent: boolean;
  checkoutUrl?: string;
} | null> {
  try {
    const db = createServiceClient();
    const coinsEquivalent = Math.floor(amountUsd);

    const { data, error } = await db.rpc(
      "fn_create_custody_deposit_idempotent",
      {
        p_group_id: groupId,
        p_amount_usd: amountUsd,
        p_coins_equivalent: coinsEquivalent,
        p_payment_gateway: gateway,
        p_idempotency_key: idempotencyKey,
      },
    );

    if (error) throw new Error(error.message);
    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.deposit_id) {
      throw new Error("RPC returned no deposit_id");
    }

    const deposit: CustodyDeposit = {
      id: row.deposit_id,
      group_id: groupId,
      amount_usd: row.amount_usd,
      coins_equivalent: row.coins_equivalent,
      payment_gateway: row.payment_gateway,
      payment_reference: row.payment_reference,
      status: row.status,
      created_at: row.created_at,
      confirmed_at: null,
    };

    return { deposit, wasIdempotent: Boolean(row.was_idempotent) };
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

/**
 * L01-04 — exige `groupId` para bloquear confirm cross-group. SQL valida
 * `WHERE id = p_deposit_id AND group_id = p_group_id` no mesmo SELECT
 * que faz FOR UPDATE.
 */
export async function confirmDeposit(
  depositId: string,
  groupId: string,
): Promise<void> {
  const db = createServiceClient();
  const { error } = await db.rpc("confirm_custody_deposit", {
    p_deposit_id: depositId,
    p_group_id: groupId,
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
  // L03-01 — quantise to cents with banker's rounding so the value
  // round-trips through `numeric(14,2)` without surprise drift.
  return {
    amountUsd: roundToCents(amountUsd),
    spreadUsd: roundToCents(spreadUsd),
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
  // L03-01 — quantise via banker's rounding to match Postgres `numeric`.
  return {
    localAmount: roundToCents(localAmount),
    spreadUsd: roundToCents(spreadUsd),
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
 * L03-20 — handle a dispute / refund / chargeback gateway event.
 *
 * Delegates to `fn_handle_custody_dispute_atomic` which:
 *   • upserts `custody_dispute_cases` (idempotent by gateway + event_id);
 *   • resolves the deposit by `payment_reference`;
 *   • attempts `reverse_custody_deposit_atomic` when the deposit is
 *     `confirmed`, converting `INVARIANT_VIOLATION` (coins already
 *     emitted against the backing) into `ESCALATED_CFO` instead of
 *     re-raising — ops picks it up from `/platform/disputes`.
 *
 * Returns `null` when the underlying tables/functions are absent (legacy
 * DBs running on an older migration level) so the route handler can
 * degrade gracefully.
 */
export type CustodyDisputeOutcome =
  | "idempotent_replay"
  | "reversed"
  | "escalated"
  | "deposit_not_found"
  | "dismissed";

export interface HandleCustodyDisputeInput {
  gateway: "stripe" | "mercadopago" | "asaas";
  gatewayEventId: string;
  gatewayDisputeRef: string | null;
  paymentReference: string | null;
  kind: "dispute" | "refund" | "chargeback";
  reasonCode: string;
  rawEvent: Record<string, unknown>;
}

export interface HandleCustodyDisputeResult {
  outcome: CustodyDisputeOutcome;
  caseId: string;
  caseState: string;
  depositId: string | null;
  groupId: string | null;
  amountUsd: number | null;
  reversalId: string | null;
  refundedUsd: number | null;
  wasIdempotent: boolean;
}

export async function handleCustodyDispute(
  input: HandleCustodyDisputeInput,
): Promise<HandleCustodyDisputeResult | null> {
  try {
    const db = createServiceClient();
    const { data, error } = await db.rpc("fn_handle_custody_dispute_atomic", {
      p_gateway: input.gateway,
      p_gateway_event_id: input.gatewayEventId,
      p_gateway_dispute_ref: input.gatewayDisputeRef,
      p_payment_reference: input.paymentReference,
      p_kind: input.kind,
      p_reason_code: input.reasonCode,
      p_raw_event: input.rawEvent,
    });

    if (error) {
      if (isTableMissing(error)) return null;
      throw new Error(error.message ?? "fn_handle_custody_dispute_atomic failed");
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row) throw new Error("fn_handle_custody_dispute_atomic returned no row");

    return {
      outcome: row.outcome as CustodyDisputeOutcome,
      caseId: row.case_id,
      caseState: row.case_state,
      depositId: row.deposit_id ?? null,
      groupId: row.group_id ?? null,
      amountUsd: row.amount_usd === null || row.amount_usd === undefined ? null : Number(row.amount_usd),
      reversalId: row.reversal_id ?? null,
      refundedUsd: row.refunded_usd === null || row.refunded_usd === undefined ? null : Number(row.refunded_usd),
      wasIdempotent: Boolean(row.was_idempotent),
    };
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

    // L01-04 — also fetch group_id; confirmDeposit agora exige.
    const { data: existing } = await db
      .from("custody_deposits")
      .select("id, status, group_id")
      .eq("payment_reference", paymentReference)
      .maybeSingle();

    if (!existing) throw new Error(`No deposit found for reference: ${paymentReference}`);
    if (existing.status === "confirmed") return { depositId: existing.id, alreadyConfirmed: true };
    if (existing.status !== "pending") throw new Error(`Deposit status is ${existing.status}`);

    await confirmDeposit(existing.id, existing.group_id);
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
