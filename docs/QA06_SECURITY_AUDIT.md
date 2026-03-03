# QA-06 — Security Audit (RLS, Auth, Abuso, Secrets)

## 1. SECURITY DEFINER Functions — Hardening Status

### Funções OS-01/02/03 (Novas) — Todas Hardened ✅

| Função | `search_path` | REVOKE anon/auth | GRANT service_role | GRANT authenticated | Status |
|--------|--------------|-------------------|--------------------|--------------------|--------|
| `fn_mark_attendance` | ✅ `public, pg_temp` | ✅ | ✅ | ✅ (RPC user-facing) | **OK** |
| `fn_issue_checkin_token` | ✅ `public, pg_temp` | ✅ | ✅ | ✅ (RPC user-facing) | **OK** |
| `fn_upsert_member_status` | ✅ `public, pg_temp` | ✅ | ✅ | ✅ (RPC user-facing) | **OK** |
| `fn_mark_announcement_read` | ✅ `public, pg_temp` | ✅ | ✅ | ✅ (RPC user-facing) | **OK** |
| `fn_announcement_read_stats` | ✅ `public, pg_temp` | ✅ | ✅ | ✅ (RPC user-facing) | **OK** |
| `compute_coaching_kpis_daily` | ✅ `public, pg_temp` | ✅ | ✅ | ❌ (cron only) | **OK** |
| `compute_coaching_athlete_kpis_daily` | ✅ `public, pg_temp` | ✅ | ✅ | ❌ (cron only) | **OK** |
| `compute_coaching_alerts_daily` | ✅ `public, pg_temp` | ✅ | ✅ | ❌ (cron only) | **OK** |

### Funções Pré-existentes (Hardened via SECURITY_HARDENING.sql) — 19/34 ✅

Coberto pelo `docs/SECURITY_HARDENING.sql`. 

### Funções Pré-existentes NÃO Hardened — 6 Missing ⚠️

| Função | `search_path` | REVOKE | Status | Severidade |
|--------|--------------|--------|--------|------------|
| `fn_friends_activity_feed` | ❌ Missing | ❌ Missing | **FIX** | **P1** |
| `execute_withdrawal` | ❌ Missing | ❌ Missing | **FIX** | **P1** |
| `custody_commit_coins` | ❌ Missing | ❌ Missing | **FIX** | **P1** |
| `custody_release_committed` | ❌ Missing | ❌ Missing | **FIX** | **P1** |
| `fn_platform_get_assessoria_detail` | ❌ Missing | ❌ Missing | **FIX** | **P1** |
| `fn_platform_list_assessorias` | ❌ Missing | ❌ Missing | **FIX** | **P1** |

**Patch sugerido:**
```sql
ALTER FUNCTION public.fn_friends_activity_feed SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_friends_activity_feed FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_friends_activity_feed TO authenticated;
-- Repetir para as outras 5 funções
```

---

## 2. Secrets & Keys

### .env files

| Arquivo | Gitignored | Committed | Status |
|---------|-----------|-----------|--------|
| `.env` | ✅ | ❌ | **SAFE** |
| `.env.local` | ✅ | ❌ | **SAFE** |
| `portal/.env` | ✅ | ❌ | **SAFE** |
| `portal/.env.local` | ✅ | ❌ | **SAFE** |

### Hardcoded secrets in source

| Busca | Resultado | Status |
|-------|-----------|--------|
| `SUPABASE_SERVICE_ROLE_KEY` no client-side (portal/src/, omni_runner/lib/) | ❌ Não encontrado | **SAFE** |
| `service_role` no client-side | ❌ Não encontrado | **SAFE** |
| `password` hardcoded | ❌ Não encontrado (apenas referências em tipos/schemas) | **SAFE** |
| `api_key` hardcoded | ❌ Não encontrado | **SAFE** |
| `private_key` hardcoded | ❌ Não encontrado | **SAFE** |
| Anon key no app | ✅ Via env/config (correto — anon key é pública por design) | **SAFE** |

---

## 3. RLS Policy Audit

### coaching_training_sessions

| Policy | Logic | Correct? |
|--------|-------|----------|
| staff_sessions_all | `role IN ('admin_master','coach','assistant') AND group_id membership` | ✅ |
| members_read_sessions | `group_id IN (SELECT group_id FROM coaching_members WHERE user_id = auth.uid())` | ✅ |
| Athlete INSERT/UPDATE/DELETE | No policy | ✅ (correctly denied) |

### coaching_training_attendance

| Policy | Logic | Correct? |
|--------|-------|----------|
| staff_insert_attendance | `role IN ('admin_master','coach','assistant') AND group membership` | ✅ |
| staff_read_attendance | `role IN ('admin_master','coach','assistant') AND group membership` | ✅ |
| athlete_read_own_attendance | `athlete_user_id = auth.uid() AND group membership` | ✅ |
| Athlete INSERT | No policy | ✅ (only via RPC fn_mark_attendance) |

### coaching_athlete_notes (**CRITICAL**)

| Policy | Logic | Correct? |
|--------|-------|----------|
| staff_crud_notes | `role IN ('admin_master','coach','assistant') AND group membership` | ✅ |
| athlete_read_notes | **NO POLICY EXISTS** | ✅ (**CORRECT — athletes cannot read notes**) |

### coaching_announcements

| Policy | Logic | Correct? |
|--------|-------|----------|
| members_read_announcements | `group_id IN (SELECT ... coaching_members ...)` | ✅ |
| staff_crud_announcements | `role IN ('admin_master','coach') AND group membership` | ✅ |

### coaching_announcement_reads

| Policy | Logic | Correct? |
|--------|-------|----------|
| user_insert_own_read | `user_id = auth.uid()` | ✅ |
| staff_read_all_reads | `role IN ('admin_master','coach','assistant') AND group membership` | ✅ |

### coaching_member_status

| Policy | Logic | Correct? |
|--------|-------|----------|
| staff_crud_status | `role IN ('admin_master','coach','assistant')` | ✅ |
| athlete_read_own | `user_id = auth.uid()` | ✅ |

---

## 4. Matriz de Ataques

| # | Ataque | Vetor | Esperado | Resultado (code review) | Severidade |
|---|--------|-------|----------|-------------------------|------------|
| A01 | Ler grupo alheio (App) | Atleta A query `group_id = B` | 0 rows (RLS) | ✅ RLS bloqueia | — |
| A02 | Ler grupo alheio (Portal API) | Forjar cookie `portal_group_id = B` | Dados do grupo B (se staff é membro) | ⚠️ Cookie é a única barreira, mas RLS no Supabase revalida | P2 |
| A03 | Marcar presença em grupo alheio | `fn_mark_attendance(session_de_B, ...)` | `forbidden` (RPC valida membership) | ✅ RPC bloqueia | — |
| A04 | Editar treino de grupo alheio | `UPDATE coaching_training_sessions SET ... WHERE id = session_B` | 0 rows (RLS) | ✅ RLS bloqueia | — |
| A05 | Criar tag em grupo alheio | `INSERT coaching_tags (group_id = B, ...)` | ERROR (RLS) | ✅ RLS bloqueia | — |
| A06 | Ler notas internas (atleta) | `SELECT * FROM coaching_athlete_notes` | 0 rows (no policy) | ✅ RLS bloqueia | — |
| A07 | Spam `fn_mark_attendance` | 1000 chamadas rápidas | Idempotente (ON CONFLICT), mas sem rate limit | ⚠️ Sem rate limit, DB pode sofrer | **P1** |
| A08 | Spam join requests | 1000 `fn_request_join` | Sem rate limit | ⚠️ Sem rate limit | **P1** |
| A09 | Marcar read por outro user | `INSERT reads (user_id = OTHER)` | ERROR (RLS: user_id = auth.uid()) | ✅ RLS bloqueia | — |
| A10 | **Export engagement sem auth** | `GET /api/export/engagement` sem login | **CSV com dados retornado** | ❌ **FALHA — SEM AUTH** | **P0** |
| A11 | CRM notes group_id override | `POST /api/crm/notes {groupId: B}` | Aceita groupId do body | ⚠️ RLS mitiga, mas viola defense-in-depth | **P1** |
| A12 | `search_path` attack em SECURITY DEFINER | Criar schema malicioso | Bloqueado por `SET search_path = public, pg_temp` | ✅ (nas funções hardened) | — |
| A13 | Privilege escalation via role | Atleta envia `role: 'admin_master'` | Irrelevante — role vem de `coaching_members` table, não do JWT | ✅ | — |

---

## 5. Bugs Encontrados

| # | Severidade | Bug | Evidência | Patch |
|---|-----------|-----|-----------|-------|
| S01 | **P0** | `/api/export/engagement/route.ts` — ZERO autenticação | Arquivo não chama `getSession()` nem verifica role. Usa `createServiceClient()` (bypasses RLS). Qualquer request com cookie `portal_group_id` válido retorna CSV completo. | Adicionar `getSession()` + `isStaff()` check no início da route |
| S02 | **P1** | 6 SECURITY DEFINER functions sem `search_path` hardening | `fn_friends_activity_feed`, `execute_withdrawal`, `custody_commit_coins`, `custody_release_committed`, `fn_platform_get_assessoria_detail`, `fn_platform_list_assessorias` | Aplicar `ALTER FUNCTION ... SET search_path` + REVOKE/GRANT |
| S03 | **P1** | Sem rate limiting em RPCs públicas | `fn_mark_attendance`, `fn_mark_announcement_read`, `fn_request_join` podem ser chamadas infinitamente | Implementar rate limit via Supabase Edge (ou pg_rate_limit) |
| S04 | **P1** | CRM notes/tags APIs aceitam `groupId` do client | `/api/crm/notes` body, `/api/crm/tags` query param | Usar apenas cookie `portal_group_id`, ignorar body/param |
| S05 | **P2** | Portal cookie `portal_group_id` sem validação de membership server-side | API routes confiam no cookie. Se cookie forjado, RLS no Supabase é a última barreira | Adicionar server-side check: user é membro do group_id do cookie |

---

## 6. Recomendações

1. **URGENTE (P0)**: Fix `/api/export/engagement/route.ts` — adicionar auth check
2. **IMPORTANTE (P1)**: Hardening das 6 functions missing — aplicar SQL patch
3. **IMPORTANTE (P1)**: Rate limiting — pelo menos para RPCs spam-prone
4. **DEFENSE-IN-DEPTH (P1)**: Portal APIs devem usar apenas cookie, nunca aceitar group_id do client
5. **MELHORIA (P2)**: Validar membership do cookie group_id server-side em cada API route
