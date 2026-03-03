# QA-02 — Integração Front/Back (App ↔ Supabase ↔ Edge ↔ Portal)

## 1. Mapa de Integração Completo

### App Flutter → Supabase

| Tela/Ação | Repo | Chamada Supabase | Campos | Error Handling | Status |
|-----------|------|------------------|--------|----------------|--------|
| **OS-01: Training Sessions** |
| Listar treinos | `SupabaseTrainingSessionRepo` | `from('coaching_training_sessions').select().eq('group_id', gid).order('starts_at')` | id, group_id, created_by, title, description, starts_at, ends_at, location_name, status | ❌ Sem try/catch | **BUG P1** |
| Criar treino | `SupabaseTrainingSessionRepo` | `from('coaching_training_sessions').insert(...)` | title, starts_at, ends_at, group_id, created_by, description, location_name, status | ❌ Sem try/catch | **BUG P1** |
| Cancelar treino | `SupabaseTrainingSessionRepo` | `from('coaching_training_sessions').update({status: 'cancelled'}).eq('id', sid)` | status | ❌ Sem try/catch | **BUG P1** |
| Marcar presença | `SupabaseTrainingAttendanceRepo` | `rpc('fn_mark_attendance', {p_session_id, p_athlete_user_id, p_nonce})` | ok, status, attendance_id | ❌ Sem try/catch | **BUG P1** |
| Gerar QR token | `SupabaseTrainingAttendanceRepo` | `rpc('fn_issue_checkin_token', {p_session_id, p_ttl_seconds})` | session_id, athlete_user_id, nonce, expires_at, sig | ❌ Sem try/catch | **BUG P1** |
| Listar presença | `SupabaseTrainingAttendanceRepo` | `from('coaching_training_attendance').select('*, profiles(display_name)').eq(...)` | id, session_id, athlete_user_id, checked_by, checked_at, status, method | ❌ Sem try/catch | **BUG P1** |
| Contar presença/sessão | `SupabaseTrainingAttendanceRepo` | `from('coaching_training_attendance').select('id', {count: 'exact'}).eq('session_id', sid)` | count | ❌ Sem try/catch | **BUG P1** |
| **OS-02: CRM** |
| Listar tags | `SupabaseCrmRepo` | `from('coaching_tags').select().eq('group_id', gid)` | id, name, color, group_id | ❌ Sem try/catch | **BUG P1** |
| Criar/deletar tags | `SupabaseCrmRepo` | `.insert(...)` / `.delete().eq('id', tid)` | name, group_id | ❌ Sem try/catch | **BUG P1** |
| Atribuir tag a atleta | `SupabaseCrmRepo` | `from('coaching_athlete_tags').insert(...)` | group_id, athlete_user_id, tag_id | ❌ Sem try/catch | **BUG P1** |
| Listar notas | `SupabaseCrmRepo` | `from('coaching_athlete_notes').select().eq('athlete_user_id', uid).order('created_at')` | id, note, created_by, created_at | ❌ Sem try/catch | **BUG P1** |
| Adicionar nota | `SupabaseCrmRepo` | `from('coaching_athlete_notes').insert(...)` | group_id, athlete_user_id, created_by, note | ❌ Sem try/catch | **BUG P1** |
| Upsert status | `SupabaseCrmRepo` | `rpc('fn_upsert_member_status', {p_group_id, p_user_id, p_status})` | ok, status | ❌ Sem try/catch | **BUG P1** |
| **OS-03: Announcements** |
| Listar avisos | `SupabaseAnnouncementRepo` | `from('coaching_announcements').select().eq('group_id', gid).order('created_at', desc)` | id, title, body, pinned, created_by, created_at | ❌ Sem try/catch | **BUG P1** |
| Criar aviso | `SupabaseAnnouncementRepo` | `from('coaching_announcements').insert(...)` | group_id, created_by, title, body, pinned | ❌ Sem try/catch | **BUG P1** |
| Marcar leitura | `SupabaseAnnouncementRepo` | `rpc('fn_mark_announcement_read', {p_announcement_id})` | ok | ❌ Sem try/catch | **BUG P1** |

### Portal Next.js → Supabase

| Página/Ação | API Route / SSR | Chamada Supabase | Error Handling | Status |
|-------------|-----------------|------------------|----------------|--------|
| Attendance report | SSR `attendance/page.tsx` | `from('coaching_training_sessions').select('*, coaching_training_attendance(count)')` | ❌ Sem try/catch no SSR | **BUG P1** |
| CRM table | SSR `crm/page.tsx` | `from('coaching_members').select('*, coaching_athlete_tags(*), coaching_member_status(*)')` | ❌ Sem try/catch no SSR | **BUG P1** |
| Announcements | SSR `announcements/page.tsx` | `from('coaching_announcements').select('*, coaching_announcement_reads(count)')` | ❌ Sem try/catch no SSR | **BUG P1** |
| Risk page | SSR `risk/page.tsx` | `from('coaching_alerts').select().eq('severity', 'critical').or('severity.eq.warning')` | ❌ Sem try/catch no SSR | **BUG P1** |
| Export attendance | GET `/api/export/attendance` | `from('coaching_training_attendance').select(...)` | ✅ try/catch com 500 response | OK |
| Export CRM | GET `/api/export/crm` | `from('coaching_members').select(...)` | ✅ try/catch | OK |
| Export engagement | GET `/api/export/engagement` | `from('coaching_kpis_daily').select(...)` | ❌ **Sem autenticação** | **BUG P0** |
| Export alerts | GET `/api/export/alerts` | `from('coaching_alerts').select(...)` | ✅ try/catch | OK |
| CRM tags API | GET `/api/crm/tags` | `from('coaching_tags').select().eq('group_id', gid)` | ✅ try/catch | OK |
| CRM notes API | POST `/api/crm/notes` | `from('coaching_athlete_notes').insert(...)` | ⚠️ Aceita `groupId` do body | **BUG P1** |
| Announcements API | POST `/api/announcements` | `from('coaching_announcements').insert(...)` | ✅ try/catch | OK |

### Edge Functions → Supabase

| Function | Chamada | Relevante para OS? | Status |
|----------|---------|---------------------|--------|
| `token-create-intent` | `from('token_intents').insert(...)` | Reutilizado parcialmente para QR check-in | OK |
| `compute-leaderboard` | Aggregation queries | Não afeta OS | OK |
| `notify-rules` | Push notifications | Pode ser estendido para avisos OS-03 | OK |

---

## 2. Contract Mismatches

| # | Severidade | Mismatch | Evidência |
|---|-----------|----------|-----------|
| 1 | **P0** | `coaching_alerts` — column `resolved` (bool) vs Portal usando `is_read` | Flutter entity: `resolved`, Portal risk page: `is_read`, Migration index: `resolved` |
| 2 | **P1** | `fn_mark_attendance` — Flutter envia `p_nonce` mas RPC aceita e ignora (nonce não validado) | Migration OS-01: `p_nonce text DEFAULT NULL` + sem validação |
| 3 | **P2** | `coaching_training_attendance.method` — sempre `'qr'` hardcoded no insert, mas schema permite outros valores | `fn_mark_attendance`: `VALUES (..., 'qr')` |

---

## 3. Erros HTTP Não Tratados (Resumo)

| Código | App Flutter | Portal |
|--------|-------------|--------|
| 401 (não autenticado) | ❌ Não tratado nos repos novos (OS-01/02/03) — `PostgrestException` sobe raw | ⚠️ Middleware redireciona para login |
| 403 (sem permissão) | ❌ Sobe como exceção genérica | ⚠️ Middleware redireciona |
| 404 (não existe) | ❌ Não tratado (query retorna null/vazio mas sem lógica distinta) | ❌ Crash no SSR |
| 409 (unique constraint) | ✅ ON CONFLICT nos RPCs resolve no DB | ✅ ON CONFLICT |
| 429 (rate limit) | ❌ Não tratado — nenhum rate limit existe | ❌ Nenhum rate limit |
| 5xx (falha server) | ❌ Sobe como exceção genérica | ❌ Crash no SSR (sem error boundary) |

---

## 4. Bugs Encontrados

| # | Severidade | Bug | Patch Sugerido |
|---|-----------|-----|----------------|
| I01 | **P0** | `/api/export/engagement` sem autenticação — qualquer pessoa com cookie forjado pode exportar KPIs | Adicionar `getSession()` + `isStaff()` check |
| I02 | **P0** | Column `resolved` vs `is_read` mismatch — portal e app vão falhar ao ler/atualizar alertas | Padronizar para `resolved` em todos os pontos |
| I03 | **P1** | 9 repos Flutter (OS-01/02/03) sem try/catch — `PostgrestException` sobe raw até o widget | Wrap cada método em try/catch + `AppLogger.error()` |
| I04 | **P1** | 4 portal SSR pages sem try/catch — Next.js mostra error 500 genérico | Wrap em try/catch + `<ErrorFallback>` component |
| I05 | **P1** | `/api/crm/notes` aceita `groupId` do body — client pode override | Usar apenas cookie `portal_group_id` |
| I06 | **P1** | `/api/crm/tags` aceita `groupId` de query params | Usar apenas cookie `portal_group_id` |
| I07 | **P2** | QR nonce não validado — anti-replay é placeholder | Documentar como "MVP: TTL-only" ou implementar |
| I08 | **P2** | Attendance method hardcoded `'qr'` — sem suporte para manual | Adicionar parâmetro `p_method` no RPC (futuro) |

---

## 5. Verificação de Integração (Testes Mínimos)

### Teste 1: Criar treino → aparece no portal → atleta vê

```
1. App (Coach): criar treino "Treino QA" → salvar
2. SQL: SELECT * FROM coaching_training_sessions WHERE title = 'Treino QA';
   → 1 row, group_id = GRUPO_A
3. Portal (Coach): abrir /attendance → "Treino QA" na lista
4. App (Atleta): abrir "Meus Treinos" → "Treino QA" visível
```

### Teste 2: Presença via QR → relatório portal → snapshot

```
1. App (Atleta): gerar QR → copiar payload
2. App (Coach): scan QR → snackbar "Presença registrada"
3. SQL: SELECT * FROM coaching_training_attendance WHERE session_id = X;
   → 1 row, athlete_user_id = ATLETA_ANDRE
4. Portal: /attendance → detalhe do treino → André na lista
5. SQL: SELECT compute_coaching_kpis_daily(current_date - 1);
6. SQL: SELECT attendance_sessions_7d, attendance_rate_7d FROM coaching_kpis_daily WHERE group_id = GRUPO_A;
   → attendance_sessions_7d >= 1
```

### Teste 3: Announcement read → portal taxa

```
1. App (Coach): criar aviso "Aviso QA"
2. App (Atleta): abrir aviso → leitura marcada
3. SQL: SELECT * FROM coaching_announcement_reads WHERE announcement_id = X;
   → 1 row, user_id = ATLETA_ANDRE
4. Portal: /announcements → "Aviso QA" → read rate > 0%
```
