---
id: L01-11
audit_ref: "1.11"
lens: 1
title: "POST /api/workouts/assign, /api/workouts/templates — Autorização cross-athlete"
severity: medium
status: fixed
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["mobile", "portal", "authz", "rls"]
files:
  - "portal/src/app/api/workouts/assign/route.ts"
  - "portal/src/app/api/workouts/templates/route.ts"
  - "supabase/migrations/20260304100000_workout_builder.sql"
  - "supabase/migrations/20260307000000_chaos_fixes.sql"
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "01695e1"
  - "61c245d"
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: defesa server-side confirmada via RPC SECURITY DEFINER + RLS. Ver detalhes abaixo."
---
# [L01-11] POST /api/workouts/assign, /api/workouts/templates — Autorização cross-athlete
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 3 · **Status:** ✅ fixed
**Camada:** PORTAL
**Personas impactadas:** Atleta, Coach

## Achado original
Arquivos existem mas conteúdo não foi inspecionado na auditoria inicial. Marcado para re-auditoria específica: validar que `athlete_user_id` do body pertence à assessoria do caller e que `template_id` pertence ao grupo do coach.

## Re-auditoria 2026-04-24

### `/api/workouts/assign` (POST)
Rota delega para o RPC `fn_assign_workout(p_template_id, p_athlete_user_id, p_scheduled_date, p_notes)` declarado em `supabase/migrations/20260307000000_chaos_fixes.sql:78-179`. O RPC é `SECURITY DEFINER` com `SET search_path = public, pg_temp` e valida **todas** as condições críticas server-side:

1. `template.group_id` existe → senão `TEMPLATE_NOT_FOUND`.
2. Caller (`auth.uid()`) tem `coaching_members.role IN ('admin_master','coach')` **no grupo do template** → senão `NOT_STAFF`.
3. Atleta alvo tem `coaching_members.role = 'athlete'` **no mesmo grupo** → senão `ATHLETE_NOT_MEMBER`.
4. Subscription do atleta está ativa → senão `SUBSCRIPTION_LATE`/`SUBSCRIPTION_INACTIVE`.
5. Respeita `max_workouts_per_week` com `FOR UPDATE` (anti-TOCTOU).

`REVOKE ... FROM PUBLIC` + `GRANT EXECUTE ... TO authenticated` no final. **Caller não precisa — e não pode — burlar o check enviando `group_id` via cookie**: o group é derivado do template server-side.

### `/api/workouts/templates` (POST/DELETE)
Rota usa `createClient()` (client anon + cookie → **RLS enforcement**). Fluxo seguro:

- **UPDATE template**: `.eq("id", templateId).eq("group_id", groupId)` — cross-group update é no-op.
- **INSERT template**: `group_id: groupId` hard-coded do cookie.
- **DELETE/INSERT blocks**: a própria RLS `staff_blocks_all` em `coaching_workout_blocks` (`supabase/migrations/20260304100000_workout_builder.sql:127-137`) bloqueia qualquer mutação se o caller não for `coach|admin_master` **do grupo que possui o template**:

```sql
CREATE POLICY "staff_blocks_all"
  ON public.coaching_workout_blocks FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_workout_templates t
      JOIN public.coaching_members cm ON cm.group_id = t.group_id
      WHERE t.id = coaching_workout_blocks.template_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );
```

- **DELETE template**: blocks são CASCADE (`ON DELETE CASCADE` na FK), e o `.eq("group_id", groupId)` no DELETE do template final garante escopo.

### Conclusão
Nenhum bypass cross-group/cross-athlete possível a partir das rotas. Defesa é **server-side** (RPC + RLS), não no route handler — padrão aceitável e mais robusto que validação client-side duplicada.

**Reclassificado**: severity `na` → `medium` (débito de defense-in-depth: seria ideal validar também no route, mas não é bloqueante), status `fix-pending` → `fixed`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.11]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.11).
- `2026-04-24` — Re-auditoria confirmou defesa via `fn_assign_workout` (SECURITY DEFINER) + RLS `staff_blocks_all`. Flipped para `fixed`.
