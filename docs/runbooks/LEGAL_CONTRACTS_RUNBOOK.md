# Runbook — Contratos privados versionados (L09-09)

> **Escopo:** gerenciar o ciclo de vida dos contratos privados em `docs/legal/`
> — publicação, bump de versão, rotação de hash, reconsent em massa, respostas
> a solicitações LGPD ("provem qual termo eu aceitei").
>
> **Relacionados:**
> - [`docs/legal/README.md`](../legal/README.md) — convenções editoriais
> - [`docs/runbooks/L04-03-lgpd-consent-management.md`](./L04-03-lgpd-consent-management.md) — infra de consent
> - [`docs/audit/findings/L09-09-*`](../audit/findings/L09-09-contratos-privados-termo-de-adesao-do-clube-termo.md) — finding original

## Mental model

A plataforma mantém em `consent_policy_versions` (tabela criada em L04-03):

| campo | significado |
| --- | --- |
| `consent_type` | identificador canônico (10 tipos — vide migration `20260417220000` + `20260421210000`) |
| `current_version` | versão vigente (e.g. `'1.0'`) |
| `minimum_version` | menor versão aceita como válida para `is_valid=true` |
| `document_url` | caminho servido ao cliente para exibir o texto |
| `document_hash` | **SHA-256 do MD em `docs/legal/`**. Prova de integridade jurídica. |

Para `club_adhesion` e `athlete_contract`, o MD canônico em `docs/legal/` é
**imutável** após publicação. Drift é detectado em CI por
`npm run legal:check` (`tools/legal/check-document-hashes.ts`).

Ciclo canônico de prova judicial:

```
usuário aceita  →  fn_consent_grant(type, version, ...)  →  row em consent_events
                                              ↓
auditoria pergunta: "o que esse usuário aceitou?"
                                              ↓
  SELECT e.consent_type, e.version, p.document_hash, p.document_url
    FROM consent_events e
    JOIN consent_policy_versions p ON p.consent_type = e.consent_type
   WHERE e.user_id = '<uuid>' AND e.action = 'granted'
                                              ↓
  → retorna hash SHA-256 + URL → MD no git com aquele hash é PROVA DOCUMENTAL.
```

## Operações rotineiras

### 1. Publicar uma versão nova (v1.0 → v2.0)

**Gatilho típico:** alteração material nos termos (novo cap, nova cláusula,
mudança de valor, alteração de foro, etc.).

Passos:

1. **Não edite o MD existente.** Duplique para `TERMO_*_v2.md` (ou, opcional,
   mantenha o mesmo arquivo com bump interno do header — ambos são aceitos,
   desde que `git tag legal/<tipo>-v<N>` fixe a versão anterior).

2. Ajuste o header do MD:
   ```markdown
   **Versão:** 2.0
   **Vigência a partir de:** YYYY-MM-DD
   ```

3. Compute o novo hash:
   ```bash
   npx tsx tools/legal/check-document-hashes.ts --print
   # saída:
   # docs/legal/TERMO_ATLETA.md  v2.0  sha256=<novo_hash>  DRIFT
   ```

4. Crie nova migration `supabase/migrations/<timestamp>_l09_<N>_bump_<tipo>_v2.sql`:
   ```sql
   BEGIN;
   UPDATE public.consent_policy_versions
      SET current_version = '2.0',
          minimum_version = '2.0',   -- exige reconsent de TODOS
          document_url    = '/legal/TERMO_ATLETA_v2.md',
          document_hash   = '<novo_hash_hex_64chars>',
          updated_at      = now()
    WHERE consent_type = 'athlete_contract';

   DO $$ BEGIN
     ASSERT (SELECT document_hash FROM public.consent_policy_versions
             WHERE consent_type='athlete_contract') = '<novo_hash_hex_64chars>',
       '[L09-XX] bump falhou';
   END $$;
   COMMIT;
   ```

5. Atualize `EXPECTED` em `tools/legal/check-document-hashes.ts` com o novo
   hash e versão. **Ambos em lockstep** — o check roda em CI.

6. Rode `npm run legal:check` — deve retornar exit 0.

7. Deploy:
   - A próxima chamada a `fn_consent_has_required()` para usuários com
     `consent_events.version < '2.0'` retorna `false` → UI renderiza tela
     de reconsent → usuário aceita v2 → novo row em `consent_events`.
   - Dashboard Metabase monitora taxa de reconsent (`dashboard_legal_reconsent`).

### 2. Correção tipográfica menor (v1.0 → v1.1)

Mesmo fluxo do item 1, mas `minimum_version` continua `'1.0'` —
usuários existentes **não** precisam re-aceitar, apenas novos cadastros.

```sql
UPDATE public.consent_policy_versions
   SET current_version = '1.1',
       minimum_version = '1.0',   -- não força reconsent
       document_hash   = '<novo_hash>',
       ...
 WHERE consent_type = 'club_adhesion';
```

### 3. Auditar consentimento de uma assessoria/atleta

```sql
-- Qual versão esse user aceitou e quando?
SELECT
  e.consent_type,
  e.version       AS aceita,
  p.current_version AS vigente,
  p.document_hash,
  p.document_url,
  e.granted_at,
  e.action,
  e.source,
  e.request_id
FROM public.consent_events e
JOIN public.consent_policy_versions p USING (consent_type)
WHERE e.user_id = '<uuid>'
  AND e.consent_type IN ('club_adhesion', 'athlete_contract')
ORDER BY e.consent_type, e.granted_at;
```

Se `p.document_hash = <valor>` e o MD em `docs/legal/<arquivo>.md` (no commit
vigente à data de `e.granted_at`) tem SHA-256 idêntico, a prova é reconstituível.
Em auditoria ANPD:

1. Fornecer a linha acima como evidência.
2. Anexar o MD renderizado do git (commit + path) cujo hash bate.
3. A combinação `user_id + consent_type + version + granted_at + request_id`
   é atômica e imutável (trigger `_consent_events_append_only`).

### 4. Resposta a solicitação LGPD ("não aceitei nada")

Ver [`L04-03-lgpd-consent-management.md` § "Runbook de incidente"](./L04-03-lgpd-consent-management.md#runbook-de-incidente-dp-alega-que-a-plataforma-não-tem-consent-dele),
acrescentando no script que L09-09 adiciona os tipos `club_adhesion` e
`athlete_contract` à lista padrão.

### 5. Bloquear uma assessoria por violação contratual

1. Suspender acesso ao painel administrativo:
   ```sql
   UPDATE public.coaching_groups SET status = 'suspended' WHERE id = '<group_id>';
   ```
2. Registrar o incidente em `portal_audit_log` com referência ao
   `consent_events.id` da adesão aceita.
3. Notificar via `contratos@runningplatform.com.br` invocando a cláusula
   VI do `TERMO_ADESAO_ASSESSORIA.md`.
4. Caso rescisão imediata (cláusula VI §1) — encerrar a assessoria:
   ```sql
   SELECT public.fn_consent_revoke('club_adhesion', 'admin_override', 'ticket-XXX');
   ```
   Este RPC precisa rodar com `auth.uid() = <admin-user-id>` que operou a ação
   OU via service_role com `RAISE NOTICE '[admin_override] ticket=…'`. Sempre
   deixe trail em `portal_audit_log`.

## Alertas e SLOs

- **Alert: drift detectado em CI** — `npm run legal:check` falha o build.
  Owner: Comitê Jurídico + engenharia DX. SLA: corrigir ou reverter ≤ 24h.

- **SLO: taxa de aceitação pós-bump ≥ 90% em 7 dias** — se v2.0 é bumpado
  e em 7 dias <90% dos usuários ativos aceitaram, escalar para UX (tela
  de reconsent pode estar bloqueando). Dashboard Metabase `legal_reconsent_rate`.

- **Alert: `document_hash` NULL em `consent_policy_versions`** — indica
  bug de migration. Query de monitoramento:
  ```sql
  SELECT consent_type FROM public.consent_policy_versions
   WHERE document_hash IS NULL;
  ```
  Deve retornar zero linhas para `club_adhesion` / `athlete_contract`.

- **Alert: append-only tamper em `consent_events`** — herdado de L04-03;
  qualquer log Postgres contendo `CONSENT_APPEND_ONLY` paga on-call.

## Troubleshooting

### "CI falha com `[L09-09] FAIL drift detectado em docs/legal/...`"

**Causa:** alguém editou o MD sem bumpar versão.
**Solução:**
1. Se a edição é material → bumpe versão (item 1 acima).
2. Se a edição é inadvertida (espaços, BOM, line endings) → `git checkout` o
   arquivo para a versão canônica. **Nunca** apenas atualize o hash no
   EXPECTED sem avaliar a alteração — isso invalida a prova jurídica de
   usuários que aceitaram a versão anterior.

### "fn_consent_grant retorna INVALID_CONSENT_TYPE para 'club_adhesion'"

**Causa:** ambiente sem a migration `20260421210000_l09_09_legal_contracts_consent.sql` aplicada.
**Solução:** `supabase db reset --no-seed` ou `psql -f …` da migration.

### "Portal/mobile aceita o tipo mas o RPC rejeita (ou vice-versa)"

**Causa:** drift entre whitelist do cliente (`VALID_TYPES_LIST` em
`portal/src/app/api/consent/route.ts`, `VALID_TYPES` em
`supabase/functions/consent-record/index.ts`) e a lista IN(…) dentro de
`fn_consent_grant`.
**Solução:** atualizar todos os três em uma única migration + PR.

## Links

- [`docs/legal/README.md`](../legal/README.md)
- [`docs/legal/TERMO_ADESAO_ASSESSORIA.md`](../legal/TERMO_ADESAO_ASSESSORIA.md)
- [`docs/legal/TERMO_ATLETA.md`](../legal/TERMO_ATLETA.md)
- [`tools/legal/check-document-hashes.ts`](../../tools/legal/check-document-hashes.ts)
- [`supabase/migrations/20260421210000_l09_09_legal_contracts_consent.sql`](../../supabase/migrations/20260421210000_l09_09_legal_contracts_consent.sql)
- [`supabase/migrations/20260417220000_lgpd_consent_management.sql`](../../supabase/migrations/20260417220000_lgpd_consent_management.sql) — L04-03 base
- [`docs/audit/findings/L09-09-contratos-privados-termo-de-adesao-do-clube-termo.md`](../audit/findings/L09-09-contratos-privados-termo-de-adesao-do-clube-termo.md)
