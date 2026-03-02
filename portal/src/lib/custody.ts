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

export async function getCustodyAccount(groupId: string): Promise<CustodyAccount | null> {
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
}

export async function getOrCreateCustodyAccount(groupId: string): Promise<CustodyAccount> {
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
}

export async function getCustodyDeposits(groupId: string): Promise<CustodyDeposit[]> {
  const db = createServiceClient();
  const { data } = await db
    .from("custody_deposits")
    .select("*")
    .eq("group_id", groupId)
    .order("created_at", { ascending: false });

  return data ?? [];
}

export async function createCustodyDeposit(
  groupId: string,
  amountUsd: number,
  gateway: "stripe" | "mercadopago",
): Promise<{ deposit: CustodyDeposit; checkoutUrl?: string }> {
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
  const db = createServiceClient();
  const { data, error } = await db.rpc("check_custody_invariants");

  if (error) {
    throw new Error(error.message);
  }

  return data ?? [];
}
