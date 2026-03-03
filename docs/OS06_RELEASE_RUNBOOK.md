# OS-06 — Release Runbook: Produção

## Pré-requisitos

- [ ] Staging validado (todas as migrations aplicadas e testadas)
- [ ] `tools/verify_metrics_snapshots.ts` passando 100%
- [ ] Portal e2e passando
- [ ] App unit tests passando
- [ ] Backup do banco de produção realizado

---

## Fase 1 — Migrations (ordem estrita)

```bash
# 1. Role fix (PASSO 05) — já aplicado se PASSO 05 foi feito
psql $DATABASE_URL -f supabase/migrations/20260303300000_fix_coaching_roles.sql
psql $DATABASE_URL -f supabase/migrations/20260303300001_alert_dedup_constraints.sql

# 2. OS-01: Training sessions + attendance
psql $DATABASE_URL -f supabase/migrations/20260303400000_training_sessions_attendance.sql

# 3. OS-02: CRM tags, notes, status
psql $DATABASE_URL -f supabase/migrations/20260303500000_crm_tags_notes_status.sql

# 4. OS-03: Announcements
psql $DATABASE_URL -f supabase/migrations/20260303600000_announcements.sql

# 5. OS-04: Performance indexes
psql $DATABASE_URL -f supabase/migrations/20260303700000_portal_performance_indexes.sql

# 6. OS-05: KPI attendance integration
psql $DATABASE_URL -f supabase/migrations/20260303800000_kpi_attendance_integration.sql
```

### Verificação pós-migrations

```sql
-- Tabelas OS-01
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_training_sessions','coaching_training_attendance');
-- expect: 2

-- Tabelas OS-02
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_tags','coaching_athlete_tags','coaching_athlete_notes','coaching_member_status');
-- expect: 4

-- Tabelas OS-03
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_announcements','coaching_announcement_reads');
-- expect: 2

-- RPCs
SELECT proname FROM pg_proc
WHERE proname IN (
  'fn_mark_attendance','fn_issue_checkin_token',
  'fn_upsert_member_status',
  'fn_mark_announcement_read','fn_announcement_read_stats',
  'compute_coaching_kpis_daily','compute_coaching_alerts_daily'
);
-- expect: 7 rows

-- Colunas novas OS-05
SELECT column_name FROM information_schema.columns
WHERE table_name = 'coaching_kpis_daily'
  AND column_name LIKE 'attendance%';
-- expect: 3 rows

-- Total policies
SELECT count(*) FROM pg_policies
WHERE tablename IN (
  'coaching_training_sessions','coaching_training_attendance',
  'coaching_tags','coaching_athlete_tags','coaching_athlete_notes','coaching_member_status',
  'coaching_announcements','coaching_announcement_reads'
);
-- expect: 35+
```

---

## Fase 2 — Edge Functions (se houver)

```bash
# Deploy edge functions (se atualizadas)
supabase functions deploy
```

---

## Fase 3 — Portal Deploy

```bash
cd portal
npm run build
# Deploy conforme seu setup (Vercel, Docker, etc.)
```

### Verificação pós-deploy portal

- [ ] Login funciona
- [ ] Sidebar mostra novas entradas (Presença, CRM, Mural, Comunicação, Análise Presença, Alertas/Risco, Exports)
- [ ] `/attendance` carrega sem erros
- [ ] `/crm` carrega sem erros
- [ ] `/announcements` carrega sem erros
- [ ] `/exports` → CSV downloads funcionam
- [ ] `/risk` → alertas carregam (pode estar vazio se cron não rodou)

---

## Fase 4 — App Deploy

```bash
cd omni_runner
flutter build apk --release  # ou ios
# Deploy via store ou distribuição interna
```

### Verificação pós-deploy app

- [ ] Staff: "Agenda de Treinos" acessível e funcional
- [ ] Staff: criar treino → salva no DB
- [ ] Staff: "CRM Atletas" acessível com filtros
- [ ] Staff: "Mural de Avisos" → criar/ler/fixar
- [ ] Athlete: "Meus Treinos" → lista treinos do grupo
- [ ] Athlete: gerar QR → código aparece com countdown
- [ ] Athlete: "Meu Status" → status visível (se definido)
- [ ] Athlete: "Mural" → vê avisos, confirma leitura

---

## Fase 5 — Ativar Cron (compute D-1)

```sql
-- Se usando pg_cron:
SELECT cron.schedule(
  'compute-kpis-daily',
  '0 3 * * *',  -- 03:00 UTC diariamente
  $$
    SELECT compute_coaching_kpis_daily(current_date - 1);
    SELECT compute_coaching_athlete_kpis_daily(current_date - 1);
    SELECT compute_coaching_alerts_daily(current_date - 1);
  $$
);
```

### Verificação do cron

```sql
-- Dia seguinte: verificar que snapshot foi gerado
SELECT count(*), max(computed_at) FROM coaching_kpis_daily WHERE day = current_date - 1;
-- expect: count > 0, computed_at ≈ 03:00 UTC

-- Verificar novos campos de attendance
SELECT group_id, attendance_sessions_7d, attendance_rate_7d
FROM coaching_kpis_daily WHERE day = current_date - 1 LIMIT 5;

-- Verificar alerta missed_trainings_14d
SELECT count(*) FROM coaching_alerts
WHERE day = current_date - 1 AND alert_type = 'missed_trainings_14d';
```

---

## Fase 6 — Validação E2E Final

Executar o fluxo completo "DONE" de cada OS:

### OS-01 DONE
1. Staff cria treino
2. Atleta vê treino
3. Atleta gera QR
4. Staff escaneia → presença registrada
5. Atleta vê presença
6. Portal exporta CSV

### OS-02 DONE
1. Staff cria tags, atribui a atleta
2. Staff adiciona nota
3. Staff filtra por tag/status
4. Portal: tabela CRM + export
5. Atleta NÃO vê notas internas

### OS-03 DONE
1. Staff publica aviso
2. Atleta recebe, marca leitura
3. Portal mostra taxa de leitura

### OS-04 DONE
1. Portal: todas as 6 páginas carregam
2. Export CSV funciona para cada módulo
3. Atleta não acessa páginas staff

### OS-05 DONE
1. Compute gera attendance_rate_7d
2. MISSED_TRAININGS_14D alert aparece para atletas ausentes
3. `verify_metrics_snapshots.ts` passa 100%

---

## Rollback

### Rollback gradual (por módulo, ordem inversa)

```sql
-- OS-05: remover colunas + restaurar compute original
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_sessions_7d;
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_checkins_7d;
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_rate_7d;
-- Re-apply: psql -f docs/PATCH_SET_BASED.sql

-- OS-04: apenas indexes (safe to keep)
-- DROP INDEX IF EXISTS idx_*; (ver lista em STEP05_ROLLOUT.md Phase 10)

-- OS-03:
DROP TABLE IF EXISTS public.coaching_announcement_reads CASCADE;
DROP TABLE IF EXISTS public.coaching_announcements CASCADE;
DROP FUNCTION IF EXISTS public.fn_mark_announcement_read(uuid);
DROP FUNCTION IF EXISTS public.fn_announcement_read_stats(uuid);

-- OS-02:
DROP TABLE IF EXISTS public.coaching_athlete_notes CASCADE;
DROP TABLE IF EXISTS public.coaching_athlete_tags CASCADE;
DROP TABLE IF EXISTS public.coaching_tags CASCADE;
DROP TABLE IF EXISTS public.coaching_member_status CASCADE;
DROP FUNCTION IF EXISTS public.fn_upsert_member_status(uuid, uuid, text);

-- OS-01:
DROP TABLE IF EXISTS public.coaching_training_attendance CASCADE;
DROP TABLE IF EXISTS public.coaching_training_sessions CASCADE;
DROP FUNCTION IF EXISTS public.fn_mark_attendance(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.fn_issue_checkin_token(uuid, int);
```

### Rollback nuclear (TUDO)

```sql
-- Desligar cron PRIMEIRO
SELECT cron.unschedule('compute-kpis-daily');

-- Executar rollback inverso (OS-05 → OS-01)
-- (comandos acima na ordem inversa)

-- Redeploy portal/app versão anterior
```

### Rollback de app/portal

- Portal: redeploy do commit anterior
- App: não é possível forçar rollback de app mobile em produção — manter backward compatibility no DB

---

## Contatos de Emergência

| Situação | Ação |
|----------|------|
| Migration falhou | NÃO prosseguir. Revisar erro. Migrations são transacionais (BEGIN/COMMIT). |
| RPC retorna "permission denied" | Verificar REVOKE/GRANT. Re-aplicar grants da migration. |
| Portal 500 | Verificar logs do server. Provavelmente tabela/coluna missing. |
| App crash | Verificar se migration foi aplicada. Entity/repo pode ter campo missing. |
| Cron duplica dados | Impossível com ON CONFLICT. Verificar se cron está rodando 2x. |
| Athlete vê notas internas | INCIDENTE DE SEGURANÇA. Verificar RLS policies em coaching_athlete_notes. |
