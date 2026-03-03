# STEP 05 — Implementation Diff (arquivo por arquivo)

---

## 1. Arquivos NOVOS a criar

### 1.1 Migration SQL — Tabelas e índices

**Path:** `supabase/migrations/20260303200000_coaching_kpis_snapshots.sql`
**Conteúdo:** Definido em `STEP05_SCHEMA_AND_RLS_PLAN.md` §1

### 1.2 Migration SQL — Funções de compute

**Path:** `supabase/migrations/20260303200001_coaching_kpis_functions.sql`
**Conteúdo:** Definido em `STEP05_SCHEMA_AND_RLS_PLAN.md` §2

### 1.3 Edge Function — Cron de snapshots diários

**Path:** `supabase/functions/compute-daily-kpis/index.ts`

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Default: yesterday. Accept ?day=YYYY-MM-DD for backfills.
    const url = new URL(req.url);
    const dayParam = url.searchParams.get("day");
    const day = dayParam ?? new Date(Date.now() - 86_400_000)
      .toISOString().slice(0, 10);

    console.log(`Computing KPIs for day=${day}`);

    // 1. Group-level KPIs
    const { data: kpiCount, error: e1 } = await db.rpc(
      "compute_coaching_kpis_daily", { p_day: day }
    );
    if (e1) throw e1;
    console.log(`Group KPIs computed: ${kpiCount} groups`);

    // 2. Athlete-level KPIs
    const { data: athleteCount, error: e2 } = await db.rpc(
      "compute_coaching_athlete_kpis_daily", { p_day: day }
    );
    if (e2) throw e2;
    console.log(`Athlete KPIs computed: ${athleteCount} athletes`);

    // 3. Alerts
    const { data: alertCount, error: e3 } = await db.rpc(
      "compute_coaching_alerts_daily", { p_day: day }
    );
    if (e3) throw e3;
    console.log(`Alerts generated: ${alertCount}`);

    return new Response(JSON.stringify({
      day,
      groups: kpiCount,
      athletes: athleteCount,
      alerts: alertCount,
    }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("KPI compute failed:", error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
```

**Cron schedule** (config no Supabase Dashboard > Edge Functions > Schedules):
```
0 3 * * *    compute-daily-kpis
```
Roda às 03:00 UTC diariamente.

### 1.4 Teste de validação e2e

**Path:** `tools/verify_metrics_snapshots.ts`
Definido na seção 5 deste documento.

---

## 2. Arquivos MODIFICADOS no Portal

### 2.1 `portal/src/app/(portal)/engagement/page.tsx`

**Mudança:** Trocar queries live por leitura do snapshot, com fallback.

```diff
- // Queries live para DAU/WAU/MAU
- const { data: members } = await db
-   .from("coaching_members")
-   .select("user_id")
-   .eq("group_id", groupId)
-   .eq("role", "athlete");
- // ... (40 linhas de queries e cálculos client-side)

+ // Read pre-computed snapshot (today or yesterday)
+ const today = new Date().toISOString().slice(0, 10);
+ const yesterday = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
+
+ const { data: snapshot } = await db
+   .from("coaching_kpis_daily")
+   .select("*")
+   .eq("group_id", groupId)
+   .in("day", [today, yesterday])
+   .order("day", { ascending: false })
+   .limit(1)
+   .maybeSingle();
+
+ if (snapshot) {
+   // Use snapshot values directly
+   const { dau, wau, mau, sessions_today, distance_today_m,
+           total_athletes, retention_wow_pct } = snapshot;
+   // ... render com dados do snapshot
+ } else {
+   // FALLBACK: queries live (código atual mantido)
+ }
```

**Adicionar:** Tabela de atletas em risco:
```diff
+ // Atletas em risco (do snapshot)
+ const { data: atRiskAthletes } = await db
+   .from("coaching_athlete_kpis_daily")
+   .select("user_id, engagement_score, risk_level, sessions_7d, last_session_at_ms")
+   .eq("group_id", groupId)
+   .eq("day", snapshot?.day ?? yesterday)
+   .in("risk_level", ["medium", "high"])
+   .order("engagement_score", { ascending: true })
+   .limit(20);
```

### 2.2 `portal/src/app/(portal)/dashboard/page.tsx`

**Mudança:** WAU e sessions_today vêm do snapshot quando disponível.

```diff
+ // Try snapshot first
+ const { data: kpiSnap } = await db
+   .from("coaching_kpis_daily")
+   .select("wau, sessions_today, distance_today_m, dau, mau")
+   .eq("group_id", groupId)
+   .order("day", { ascending: false })
+   .limit(1)
+   .maybeSingle();
+
+ const wau = kpiSnap?.wau ?? /* fallback para cálculo live */;
```

### 2.3 `portal/src/app/(portal)/athletes/page.tsx`

**Mudança:** Enriquecer lista de atletas com `engagement_score` e `risk_level`.

```diff
+ // Join athlete KPIs
+ const { data: athleteKpis } = await db
+   .from("coaching_athlete_kpis_daily")
+   .select("user_id, engagement_score, risk_level, sessions_7d, last_session_at_ms")
+   .eq("group_id", groupId)
+   .order("day", { ascending: false })
+   .limit(athleteIds.length);
+
+ const kpiMap = new Map(
+   (athleteKpis ?? []).map((k) => [k.user_id, k])
+ );
```

Cada linha de atleta mostra badge de risco + score.

### 2.4 Nova página: Alertas (`/alerts`)

**Path:** `portal/src/app/(portal)/alerts/page.tsx` (NOVO)

```typescript
// Lê coaching_alerts para o grupo, mostra lista paginada
// Staff pode marcar como lido
const { data: alerts } = await db
  .from("coaching_alerts")
  .select("*")
  .eq("group_id", groupId)
  .eq("is_read", false)
  .order("day", { ascending: false })
  .limit(50);
```

### 2.5 `portal/src/components/sidebar.tsx`

**Mudança:** Adicionar link para `/alerts` com badge de count.

```diff
+ { name: "Alertas", href: "/alerts", icon: BellIcon, badge: unreadAlertCount },
```

### 2.6 `portal/src/app/api/export/athletes/route.ts`

**Mudança:** Incluir `engagement_score` e `risk_level` no CSV exportado.

```diff
+ // Enrich with KPIs
+ const { data: kpis } = await db
+   .from("coaching_athlete_kpis_daily")
+   .select("user_id, engagement_score, risk_level, sessions_7d")
+   .eq("group_id", groupId)
+   .order("day", { ascending: false });
```

---

## 3. Arquivos MODIFICADOS no App Flutter

### 3.1 `omni_runner/lib/presentation/screens/staff_retention_dashboard_screen.dart`

**Mudança:** Ler snapshot do Supabase quando disponível, fallback para cálculo live.

```diff
  Future<void> _load() async {
+   // Try snapshot first
+   final today = DateTime.now().toUtc();
+   final dayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
+   final yesterday = today.subtract(const Duration(days: 1));
+   final yStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
+
+   final snapRes = await db
+       .from('coaching_kpis_daily')
+       .select()
+       .eq('group_id', widget.groupId)
+       .inFilter('day', [dayStr, yStr])
+       .order('day', ascending: false)
+       .limit(1)
+       .maybeSingle();
+
+   if (snapRes != null) {
+     _dau = (snapRes['dau'] as num?)?.toInt() ?? 0;
+     _wau = (snapRes['wau'] as num?)?.toInt() ?? 0;
+     _totalAthletes = (snapRes['total_athletes'] as num?)?.toInt() ?? 0;
+     // Weekly retention from snapshots history
+     _weeklyRetention = await _loadRetentionFromSnapshots(db);
+     if (mounted) setState(() => _loading = false);
+     return;
+   }
+
+   // FALLBACK: existing live calculation (unchanged)
    // ...existing code...
  }
```

### 3.2 `omni_runner/lib/presentation/screens/staff_performance_screen.dart`

**Mudança:** Mesmo padrão — try snapshot, fallback live.

### 3.3 `omni_runner/lib/presentation/screens/staff_dashboard_screen.dart`

**Mudança menor:** Usar `coaching_kpis_daily` para o count de membros (evita sync full).

---

## 4. Testes

### 4.1 Teste de RLS — Não vaza entre grupos

**Path:** `portal/e2e/kpi-rls-isolation.spec.ts` (NOVO)

```typescript
import { test, expect } from "@playwright/test";
import { createServiceClient } from "../src/lib/supabase/service";

test.describe("KPI RLS isolation", () => {
  test("staff of group A cannot read KPIs of group B", async () => {
    // Setup: create two groups with different staff users
    // Assert: user A querying coaching_kpis_daily sees only group A rows
    // Assert: user A querying coaching_athlete_kpis_daily sees only group A athletes
    // Assert: user A querying coaching_alerts sees only group A alerts
  });

  test("athlete can only read own athlete_kpis rows", async () => {
    // Setup: athlete in group A
    // Assert: querying coaching_athlete_kpis_daily returns only own user_id
    // Assert: querying coaching_kpis_daily returns nothing (not staff)
  });

  test("platform admin reads all groups", async () => {
    // Setup: user with platform_role = 'admin'
    // Assert: can read coaching_kpis_daily for any group
  });
});
```

### 4.2 Teste de consistência — Invariantes do snapshot

**Path:** `portal/src/lib/kpi-invariants.test.ts` (NOVO)

```typescript
import { describe, it, expect } from "vitest";

describe("KPI snapshot invariants", () => {
  it("DAU <= WAU <= MAU <= total_athletes", () => {
    // For each row in coaching_kpis_daily:
    // assert dau <= wau <= mau <= total_athletes
  });

  it("engagement_score is within 0-100", () => {
    // For each row in coaching_athlete_kpis_daily:
    // assert 0 <= engagement_score <= 100
  });

  it("risk_level matches score thresholds", () => {
    // score >= 40 → ok
    // score 20-39 → medium
    // score 0-19 → high
  });

  it("sessions_7d <= sessions_14d <= sessions_30d", () => {
    // Monotonicity: wider window >= narrower window
  });

  it("alerts have matching athlete KPI rows", () => {
    // Every alert with user_id has a corresponding athlete_kpis row
  });
});
```

### 4.3 Smoke test — Gera snapshot e confere DAU/WAU

**Path:** `tools/verify_metrics_snapshots.ts`
Definido abaixo na seção 5.

---

## 5. Script de validação e2e

**Path:** `tools/verify_metrics_snapshots.ts`

Descrito separadamente — ver arquivo gerado.

---

## 6. Resumo de impacto

| Tipo | Arquivo | Ação |
|---|---|---|
| SQL | `supabase/migrations/20260303200000_coaching_kpis_snapshots.sql` | NOVO |
| SQL | `supabase/migrations/20260303200001_coaching_kpis_functions.sql` | NOVO |
| Edge Fn | `supabase/functions/compute-daily-kpis/index.ts` | NOVO |
| Portal | `portal/src/app/(portal)/engagement/page.tsx` | MODIFICAR |
| Portal | `portal/src/app/(portal)/dashboard/page.tsx` | MODIFICAR |
| Portal | `portal/src/app/(portal)/athletes/page.tsx` | MODIFICAR |
| Portal | `portal/src/app/(portal)/alerts/page.tsx` | NOVO |
| Portal | `portal/src/components/sidebar.tsx` | MODIFICAR |
| Portal | `portal/src/app/api/export/athletes/route.ts` | MODIFICAR |
| App | `omni_runner/.../staff_retention_dashboard_screen.dart` | MODIFICAR |
| App | `omni_runner/.../staff_performance_screen.dart` | MODIFICAR |
| App | `omni_runner/.../staff_dashboard_screen.dart` | MODIFICAR |
| Teste | `portal/e2e/kpi-rls-isolation.spec.ts` | NOVO |
| Teste | `portal/src/lib/kpi-invariants.test.ts` | NOVO |
| Teste | `tools/verify_metrics_snapshots.ts` | NOVO |

**Total: 6 arquivos novos, 7 modificados, 2 testes novos, 1 script de validação.**
