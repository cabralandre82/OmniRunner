# Runbook — L04-04 · Sensitive health data access (LGPD Art. 11)

> **Escopo:** gerir leitura de dados sensíveis de saúde / biométricos / localização
> dos atletas (sessions, runs, athlete_baselines, athlete_trends,
> coaching_athlete_kpis_daily, running_dna_profiles, support_tickets).
> Complementa [L04-03](./L04-03-lgpd-consent-management.md) (consent
> management): aqui vive o **gate de leitura + audit trail**.

## Arquitetura

- `public.sensitive_health_columns` — registry declarativo de quais colunas
  são Art. 11 (`health | biometric | location | physical_perf`), com base
  legal e racional. Drift é detectado por
  `public.v_sensitive_health_coverage_gaps`.
- `public.sensitive_data_access_log` — log append-only (trigger
  `_sdal_append_only`) das leituras cross-user de dados sensíveis. FKs
  `actor_id` / `subject_id → auth.users(id) ON DELETE SET DEFAULT` +
  registradas em `lgpd_deletion_strategy` como `anonymize` (preserva trilha
  pós-erasure com zero-UUID).
- RPCs `SECURITY DEFINER` hardened (`search_path`, `lock_timeout`):
  - `fn_can_read_athlete_health(p_athlete_id)` — retorna `true` se caller
    for o próprio atleta **ou** coach/assistente/admin_master do mesmo
    `coaching_group` com `coach_data_share` válido em
    `v_user_consent_status`. Marcado `STABLE` para uso em RLS.
  - `fn_log_sensitive_access(p_subject, p_resource, p_action, p_request_id,
    p_ip, p_user_agent, p_row_count, p_denied, p_denial_reason)` — grava
    entrada em `sensitive_data_access_log`.
  - `fn_read_athlete_health_snapshot(p_athlete_id, p_request_id?, p_ip?,
    p_user_agent?)` — accessor canônico para dashboards de coach.
    **Importante:** em denial retorna payload JSON
    `{ error: 'NOT_AUTHORIZED', denial_reason: '...' }` (não lança
    exception) para que o log persista.
- Trigger `_auto_grant_coach_data_share` em `coaching_members` emite
  `consent_event(type='coach_data_share', status='granted', source='system',
  base='execucao_contrato')` quando um atleta entra num grupo. Há backfill
  equivalente (`source='backfill'`) para relacionamentos pré-existentes.
- RLS endurecida em `sessions`, `runs`, `athlete_baselines`,
  `athlete_trends`, `coaching_athlete_kpis_daily`, `running_dna_profiles`:
  - `*_self_*` → `auth.uid() = user_id` (atleta lê próprio dado, bypass de
    consent).
  - `*_coach_consent_*` → `fn_can_read_athlete_health(user_id)`.
- Policies antigas (`sessions_staff_read`, `baselines_read`, `trends_read`,
  etc.) removidas.

## Callers

### Portal (service_role → bypass de RLS)

Qualquer rota em `portal/src/app/**` que usa `createServiceClient()` e lê
uma das tabelas do registry **precisa** passar por
`portal/src/lib/sensitive-access.ts::ensureCoachHealthAccess` antes:

```ts
import { ensureCoachHealthAccess } from "@/lib/sensitive-access";

const outcome = await ensureCoachHealthAccess({
  db,
  actorId: user.id,
  athleteId: athlete_id,
  resource: "sessions", // resource no registry
  action: "read",
  requestId: randomUUID(),
  ip: req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null,
  userAgent: req.headers.get("user-agent"),
});
if (!outcome.ok) {
  return NextResponse.json(
    { ok: false, error: { code: outcome.code, message: outcome.message } },
    { status: 403 },
  );
}
```

Rotas já integradas:

- `portal/src/app/api/ai/athlete-briefing/route.ts`
- `portal/src/app/(portal)/athletes/[id]/page.tsx`

Rotas com agregação sobre o próprio grupo do coach (consent auto-grant
cobre o gate, dado bruto per-athlete não é retornado ao cliente — mas
requerem auditoria bulk-access futura):

- `portal/src/app/(portal)/dashboard/page.tsx`
- `portal/src/app/(portal)/engagement/page.tsx`
- `portal/src/app/api/staff-alerts/route.ts`

### Mobile / Edge functions

A maioria das Edge Functions (`verify-session`, `generate-run-comment`,
`generate-running-dna`, `evaluate-badges`, `champ-update-progress`, etc.)
opera sobre o próprio usuário autenticado → RLS self-read cobre;
`fn_can_read_athlete_health` retornaria `true` para self sem precisar de
log (não é cross-user). Nenhuma mudança necessária.

Se uma nova Edge Function precisar ler dado de **outro** usuário, ela
deve chamar `fn_can_read_athlete_health` antes e registrar via
`fn_log_sensitive_access`.

## Operações rotineiras

### 1. Adicionar uma nova coluna sensível

1. Migration:
   ```sql
   INSERT INTO public.sensitive_health_columns
     (table_name, column_name, category, legal_basis, rationale)
   VALUES
     ('nova_tabela', 'coluna_nova', 'biometric',
      'lgpd_art_11_ii_b', 'Descrição clara da razão.')
   ON CONFLICT (table_name, column_name) DO NOTHING;
   ```
2. Se a tabela é nova: garantir RLS ligado + policy `*_self_*` +
   `*_coach_consent_*` usando `fn_can_read_athlete_health(user_id)`.
3. Se a coluna é consumida por callers service_role: refatorar para
   `ensureCoachHealthAccess`.
4. Adicionar teste de RLS em `tools/integration_tests.ts` ("L04-04 ·
   RLS nova_tabela").
5. Validar `v_sensitive_health_coverage_gaps` retorna 0 linhas `!= 'ok'`.

### 2. Revogar consent de um atleta manualmente

```sql
SELECT public.fn_consent_revoke('coach_data_share', 'admin_override',
  gen_random_uuid());
```

Após isso, policies `*_coach_consent_*` retornam 0 rows e
`fn_can_read_athlete_health` retorna `false`. Todas as leituras cross-user
subsequentes serão logadas com `denied=true`.

### 3. Investigar um alerta de acesso indevido

```sql
-- Quem leu o quê no último dia para um subject específico?
SELECT actor_id, resource, action, denied, denial_reason,
       row_count, accessed_at, request_id, ip
FROM public.sensitive_data_access_log
WHERE subject_id = $atleta
  AND accessed_at > now() - interval '1 day'
ORDER BY accessed_at DESC;

-- Taxa de denial por ator (últimos 7 dias)
SELECT actor_id,
       count(*) FILTER (WHERE denied) AS denied,
       count(*) FILTER (WHERE NOT denied) AS allowed
FROM public.sensitive_data_access_log
WHERE accessed_at > now() - interval '7 days'
GROUP BY actor_id
ORDER BY denied DESC;
```

### 4. Deletion / erasure LGPD

A pipeline de erasure (L04-05 / `fn_delete_user_data`) **não deleta**
`sensitive_data_access_log` — apenas substitui `actor_id`/`subject_id` por
zero-UUID, conforme `lgpd_deletion_strategy`. A trilha sobrevive para
auditoria LGPD Art. 37.

### 5. Drift check

Rode periodicamente (CI):

```sql
SELECT * FROM public.v_sensitive_health_coverage_gaps
WHERE status != 'ok';
```

Qualquer resultado `!= 'ok'` é build-break: tabela sumiu / coluna sumiu /
RLS desabilitada.

## Invariantes que **NUNCA** podem cair

1. `sensitive_data_access_log` é append-only. Qualquer migration que
   tente `ALTER`/`UPDATE`/`DELETE` direto é erro crítico.
2. `fn_read_athlete_health_snapshot` **não** pode `RAISE EXCEPTION` em
   denial → perderia o log. Retornar JSON `{ error, denial_reason }`.
3. Toda nova policy de leitura em tabelas do registry precisa passar por
   `fn_can_read_athlete_health` para cross-user.
4. Toda rota service_role que ler essas tabelas precisa chamar
   `ensureCoachHealthAccess` — validado manualmente em code review até
   termos um lint/grep-guard.

## Referências
- Finding: [`docs/audit/findings/L04-04-dados-de-saude-biometricos-dados-sensiveis-lgpd-art.md`](../findings/L04-04-dados-de-saude-biometricos-dados-sensiveis-lgpd-art.md)
- Migration: `supabase/migrations/20260417230000_sensitive_health_data_protection.sql`
- Helper: `portal/src/lib/sensitive-access.ts`
- Testes: `tools/integration_tests.ts` (grep `L04-04 ·`)
- Runbook complementar: [`L04-03-lgpd-consent-management.md`](./L04-03-lgpd-consent-management.md)
