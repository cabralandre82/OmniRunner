# Runbook — L04-03 · LGPD consent management

> **Escopo:** gerenciar consentimento de usuários (LGPD Art. 7, 8, 16, 18 VI).
> Inclui rotação de versões de política, adição de novos tipos de consent,
> processo de re-consentimento, auditoria e resposta a subject-access-requests
> ("provem que eu consenti em X").

## Arquitetura

- `public.consent_policy_versions` — catálogo de versões vigentes por tipo.
  Row-level DDL (seed + updates) é a única forma de criar novas políticas.
- `public.consent_events` — log imutável append-only.
  - FK `user_id → auth.users(id) ON DELETE SET DEFAULT` → em erasure LGPD, a
    row é **preservada** com `user_id = 00000000-0000-0000-0000-000000000000`
    e trigger nula `ip_address`/`user_agent` automaticamente.
  - UPDATE/DELETE bloqueados por trigger `_consent_events_append_only` (só o
    zero-UUID transition é permitida, para anonymize-flow).
- RPCs `SECURITY DEFINER` hardened (`search_path`, `lock_timeout`):
  - `fn_consent_grant(type, version, source, ip, ua, rid)` — authenticated;
    valida `version >= minimum_version`, insere evento + atualiza snapshot em
    `profiles.*_accepted_at`.
  - `fn_consent_revoke(type, source, rid)` — authenticated; `terms`/`privacy`
    não podem ser revogados isoladamente (→ `fn_delete_user_data`).
  - `fn_consent_status(user_id?)` — lista estado por tipo (self ou
    service_role).
  - `fn_consent_has_required(user_id?, role?)` — boolean fail-closed usado por
    Edge Functions e portal antes de liberar endpoints sensíveis.
  - `fn_anonymize_consent_events(user_id)` — service_role only; invocada pela
    pipeline de erasure LGPD.
- Snapshot desnormalizado em `public.profiles.{terms,privacy,health_data,
  location,marketing}_*` para queries rápidas.

## Operações rotineiras

### 1. Adicionar um novo tipo de consentimento

1. Migration: amplia os `CHECK (consent_type IN (...))` de
   `consent_policy_versions` e `consent_events`, ajusta as enumerações em
   `fn_consent_grant`/`fn_consent_revoke`.
2. Insere seed em `consent_policy_versions`:
   ```sql
   INSERT INTO public.consent_policy_versions
     (consent_type, current_version, minimum_version, is_required, required_for_role, document_url)
   VALUES
     ('new_type', '1.0', '1.0', false, 'any', '/legal/new-type-v1.md');
   ```
3. Atualiza o whitelist em:
   - `supabase/functions/consent-record/index.ts` (`VALID_TYPES`)
   - `portal/src/app/api/consent/route.ts` (`VALID_TYPES_LIST`)
4. Add UI toggles no onboarding (mobile + portal).
5. Integration test: `L04-03: consent_policy_versions seed has 8 canonical
   types` — incrementa o número esperado.

### 2. Rotacionar versão de uma política existente

Caso: Termos v1.0 → v2.0.

1. Publicar o novo documento legal em `/legal/terms-v2.md`.
2. Bump na tabela:
   ```sql
   UPDATE public.consent_policy_versions
      SET current_version = '2.0',
          minimum_version = '2.0',   -- exige reconsent de todos
          document_url    = '/legal/terms-v2.md',
          updated_at      = now(),
          updated_by      = auth.uid()
    WHERE consent_type = 'terms';
   ```
3. Campaign UI: na próxima sessão autenticada, `fn_consent_has_required`
   retorna `false` → portal/app renderizam tela de reconsent → usuário faz
   `fn_consent_grant('terms', '2.0', ...)`.
4. Audit: confira série temporal de grants:
   ```sql
   SELECT date_trunc('hour', granted_at) AS hour, count(*)
     FROM public.consent_events
    WHERE consent_type = 'terms' AND version = '2.0' AND action = 'granted'
    GROUP BY 1 ORDER BY 1 DESC LIMIT 48;
   ```
5. (Opcional) Após N dias, baixe `minimum_version` de volta se quiser permitir
   usuários em v1.0 ainda operarem (caso contrário permanecem bloqueados e/ou
   migração em onda via job de notificação).

### 3. Auditar consentimento de um usuário (subject-access-request)

```sql
-- Histórico completo
SELECT consent_type, action, version, source, granted_at, request_id
  FROM public.consent_events
 WHERE user_id = '<uuid>'
 ORDER BY consent_type, granted_at;

-- Estado consolidado
SELECT * FROM public.v_user_consent_status WHERE user_id = '<uuid>';
```

### 4. Resposta a revogação pontual (marketing/health_data/etc.)

Usuário revoga via UI → `fn_consent_revoke(type, 'portal'|'mobile', rid)` →
row `action='revoked'` em `consent_events` + snapshot em `profiles` nullifica.
Endpoints sensíveis dependentes do consent revogado devem consultar
`fn_consent_has_required(uid, role)` e falhar com `403 CONSENT_REQUIRED`.

### 5. Processo de erasure LGPD (Art. 18 VI) preservando prova

Fluxo canônico (`supabase/functions/delete-account/index.ts`):

1. Log imutável do estado prévio (Sentry + Datadog) incluindo dump anonimizado
   de `fn_consent_status(user_id)`.
2. `fn_delete_user_data(user_id)` — deleta/anonimiza PII (L04-01).
3. `auth.admin.deleteUser(user_id)` — dispara FK SET DEFAULT em
   `consent_events` (user_id → zero UUID) + trigger nullifica `ip_address`,
   `user_agent`.
4. `consent_events` preserva `consent_type`, `action`, `version`, `source`,
   `granted_at`, `request_id` como prova histórica (LGPD Art. 16 — obrigação
   legal documental).

## Alertas / SLOs

- **Alert: consent write burst** — mais de 1000
  `fn_consent_grant` para o mesmo `consent_type + version` em 5 min → provável
  campanha UI travada em loop. Threshold configurado em Datadog.
- **SLO: latency p95 < 200ms** em `fn_consent_grant` / `fn_consent_has_required`.
- **Alert: consent ratio drop** — `count(has_required=true) / count(profiles)`
  cair >5 pontos em 24h → bug em onboarding. Dashboard em Metabase.
- **Alert: append-only tamper** — qualquer linha de log Postgres contendo
  `CONSENT_APPEND_ONLY` → paginar on-call (tentativa de UPDATE direto em
  `consent_events` = sinal de atacante ou bug crítico).

## Runbook de incidente: "DP alega que a plataforma não tem consent dele"

1. `SELECT * FROM public.v_user_consent_status WHERE user_id = '<uuid>'` —
   se há linha com `is_valid=true` para `terms` e `privacy` → resposta
   documentada.
2. Se `action='never'` para `terms` → ver `auth.users.created_at` do usuário
   versus `consent_policy_versions.updated_at` — confirmar se onboarding
   era obrigatório no período. Se sim → **bug**, escalar para engenharia
   + legal.
3. Se conta já deletada → consultar rows anonimizadas:
   ```sql
   SELECT consent_type, action, version, granted_at, source, request_id
     FROM public.consent_events
    WHERE user_id = '00000000-0000-0000-0000-000000000000'
      AND request_id LIKE '%<trace-id-do-usuário>%'
    ORDER BY granted_at;
   ```
   Se existir match por `request_id` (vinculável ao ticket do usuário via logs
   de aplicação/Sentry), é prova forte de consent. Documente resposta à ANPD.

## Links

- [`docs/audit/findings/L04-03-nao-ha-registro-de-consentimento-opt-in-explicito.md`](../findings/L04-03-nao-ha-registro-de-consentimento-opt-in-explicito.md)
- [`docs/audit/runbooks/L01-17-asaas-vault-rotation.md`](./L01-17-asaas-vault-rotation.md) — padrão de audit log
- [`supabase/migrations/20260417220000_lgpd_consent_management.sql`](../../../supabase/migrations/20260417220000_lgpd_consent_management.sql)
- [`supabase/migrations/20260417190000_fn_delete_user_data_lgpd_complete.sql`](../../../supabase/migrations/20260417190000_fn_delete_user_data_lgpd_complete.sql) — L04-01 erasure
