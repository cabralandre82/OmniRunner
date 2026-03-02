import { createServiceClient } from "@/lib/supabase/service";

interface Flag {
  key: string;
  enabled: boolean;
  rollout_pct: number;
}

let cachedFlags: Map<string, Flag> | null = null;
let lastFetchMs = 0;
const TTL_MS = 60_000;

async function loadFlags(): Promise<Map<string, Flag>> {
  const now = Date.now();
  if (cachedFlags && now - lastFetchMs < TTL_MS) {
    return cachedFlags;
  }

  try {
    const supabase = createServiceClient();
    const { data } = await supabase
      .from("feature_flags")
      .select("key, enabled, rollout_pct")
      .order("key");

    const map = new Map<string, Flag>();
    for (const row of data ?? []) {
      map.set(row.key, {
        key: row.key,
        enabled: row.enabled,
        rollout_pct: row.rollout_pct,
      });
    }

    cachedFlags = map;
    lastFetchMs = now;
    return map;
  } catch {
    return cachedFlags ?? new Map();
  }
}

function userBucket(userId: string, key: string): number {
  const str = `${userId}:${key}`;
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = (hash << 5) - hash + str.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash) % 100;
}

export async function isFeatureEnabled(
  key: string,
  userId?: string,
): Promise<boolean> {
  const flags = await loadFlags();
  const flag = flags.get(key);

  if (!flag || !flag.enabled) return false;
  if (flag.rollout_pct >= 100) return true;
  if (flag.rollout_pct <= 0) return false;
  if (!userId) return false;

  return userBucket(userId, key) < flag.rollout_pct;
}

export async function getAllFlags(): Promise<
  Array<{ key: string; enabled: boolean; rollout_pct: number }>
> {
  const flags = await loadFlags();
  return Array.from(flags.values());
}
