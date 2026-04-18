# ACCOUNT_DELETION_RUNBOOK

> **Trigger**: alerta de `account_deletion_log.outcome IN ('cleanup_failed','auth_delete_failed','internal_error')` OR usuário/ANPD reclamando "pedi exclusão e meus dados ainda estão lá".
> **Severidade**: P1 quando há `outcome='auth_delete_failed'` (LGPD: dados foram apagados mas o auth.user persiste — janela de inconsistência); P2 para `cleanup_failed` (estado seguro: nada foi deletado, usuário pode tentar de novo).
> **Tempo alvo**: ack < 30 min, root cause < 2 h, resolução < 24 h.
> **Linked findings**: L04-02 (abort on cleanup error), L01-36 (CISO: mesma raiz), L06-08 (audit trail), L04-01 (`fn_delete_user_data` cobertura), L04-03 (consent), L05-20/L01-35 (admin_master block).
> **Última revisão**: 2026-04-17

---

## 1. Modelo mental

A edge function `delete-account` segue um pipeline atômico:

```
JWT → admin_master? → INSERT account_deletion_log
   → cancel challenges
   → fn_delete_user_data         ← se falhar, ABORTA (auth.user permanece)
   → auth.admin.deleteUser       ← se falhar, dados já foram limpos (estado parcial)
   → UPDATE account_deletion_log (terminal outcome)
```

A tabela `public.account_deletion_log` é **imutável** (trigger
`account_deletion_log_immutable`) e **não tem FK** para `auth.users`,
então o registro sobrevive a deleção que ele documenta. É a fonte
canônica para responder ANPD ("apaguei? quando? falhou em quê?").

### Outcomes possíveis

| `outcome`                  | Significado                                                              | Estado dos dados                              | Ação |
|---|---|---|---|
| `success`                  | Pipeline completo                                                        | auth.user removido + PII limpa                | nenhuma |
| `cleanup_failed`           | `fn_delete_user_data` ou cancel challenges erraram                       | **inalterado** (auth.user permanece, PII permanece) | usuário pode reexecutar; investigar SQLERRM |
| `auth_delete_failed`       | Cleanup OK mas `auth.admin.deleteUser` falhou                            | **PII apagada, auth.user permanece**          | rerun manual do auth delete (§4.2) |
| `internal_error`           | Exceção não-tratada após o INSERT inicial                                | indeterminado                                 | investigar Sentry pelo `request_id` |
| `cancelled_by_validation`  | (reservado para validações futuras pré-cleanup)                          | inalterado                                    | nenhuma |
| `NULL`                     | Em-flight ou crash antes do UPDATE terminal                              | indeterminado                                 | §4.3 |

## 2. Sintomas

| Sinal | Significado provável |
|---|---|
| Spike de `outcome='cleanup_failed'` | `fn_delete_user_data` quebrada (migration recente?) ou lock em uma tabela alvo |
| Spike de `outcome='auth_delete_failed'` | GoTrue down OU service-role key revogada |
| Linhas com `outcome IS NULL AND initiated_at < now() - interval '5 minutes'` | Edge function crashou mid-pipeline (ver `internal_error` no log estruturado) |
| Reclamação ANPD sem entrada em `account_deletion_log` | Usuário **nunca chamou** a função (UI quebrada?) ou tentou via path não-suportado |
| Mesma `user_id` com múltiplos `cleanup_failed` | Erro determinístico — provavelmente row em tabela com NOT NULL sem estratégia em `lgpd_deletion_strategy` (L04-01) |

## 3. Diagnóstico (≤ 15 min)

### 3.1 Volume e distribuição

```sql
-- Últimas 24h: distribuição de outcomes
SELECT outcome,
       COUNT(*)                                      AS total,
       COUNT(*) FILTER (WHERE failure_reason IS NOT NULL) AS with_reason,
       MIN(initiated_at)                             AS first_seen,
       MAX(initiated_at)                             AS last_seen
  FROM public.account_deletion_log
 WHERE initiated_at > now() - interval '24 hours'
 GROUP BY 1
 ORDER BY total DESC;
```

### 3.2 Top failure_reason

```sql
SELECT failure_reason,
       outcome,
       COUNT(*) AS n,
       MAX(initiated_at) AS last_seen
  FROM public.account_deletion_log
 WHERE outcome IN ('cleanup_failed', 'auth_delete_failed', 'internal_error')
   AND initiated_at > now() - interval '7 days'
 GROUP BY 1, 2
 ORDER BY n DESC
 LIMIT 20;
```

### 3.3 In-flight crashes

```sql
-- Linhas que abriram um pipeline mas nunca fecharam — provável crash da edge.
SELECT id, request_id, user_id, initiated_at, client_ua
  FROM public.account_deletion_log
 WHERE outcome IS NULL
   AND initiated_at < now() - interval '5 minutes'
 ORDER BY initiated_at DESC
 LIMIT 50;
```

Para cada `request_id` retornado: cruzar com Sentry (`fn=delete-account
request_id=<uuid>`) — esperar exatamente um `INTERNAL: …` logado por
`logError`.

### 3.4 Reclamação ANPD

```sql
-- Dado o email reclamado: hashear e procurar.
-- Tools/local: echo -n "alice@example.com" | tr A-Z a-z | shasum -a 256
SELECT id, request_id, user_id, outcome, initiated_at, completed_at, failure_reason
  FROM public.account_deletion_log
 WHERE email_hash = '<sha256_hex_lowercased_email>'
 ORDER BY initiated_at DESC;
```

- 0 linhas → usuário **nunca chamou** a função (provar com app log).
- ≥ 1 com `outcome='success'` → mostrar `cleanup_report` como evidência (Art. 18, VI).
- linha com `outcome='auth_delete_failed'` → §4.2.

## 4. Mitigation

### 4.1 `cleanup_failed` (estado SEGURO)

Nenhum dado foi alterado. O usuário pode reexecutar a deleção pelo app.
Tarefa: descobrir **por que** falhou.

1. Pegar `failure_reason` da linha (já está truncado em 500 chars).
2. Se for `lock_timeout`: rodar de novo no horário menos quente; ou
   investigar transação concorrente segurando lock no `auth.users`.
3. Se for `LGPD_INVALID_USER_ID` ou `NOT NULL violation`: provavelmente
   nova tabela com `user_id NOT NULL` sem estratégia. Rodar:
   ```sql
   SELECT * FROM public.lgpd_user_data_coverage_gaps;
   ```
   Adicionar a estratégia em
   `supabase/migrations/<timestamp>_fn_delete_user_data_*.sql` e
   refazer deploy. Ver L04-01.
4. Comunicar ao usuário (template em §6).

### 4.2 `auth_delete_failed` (estado PARCIAL)

PII apagada, auth.user persiste. Recovery manual:

```bash
# 1. Confirmar o user_id
psql "$SUPABASE_DB_URL" -c "
  SELECT user_id, initiated_at, failure_reason
    FROM public.account_deletion_log
   WHERE outcome = 'auth_delete_failed'
     AND initiated_at > now() - interval '24 hours';
"

# 2. Para cada user_id, executar o delete via service-role:
SUPABASE_URL="https://<project>.supabase.co"
SERVICE_KEY="$SUPABASE_SERVICE_ROLE_KEY"
USER_ID="<from query>"

curl -sf -X DELETE \
  "$SUPABASE_URL/auth/v1/admin/users/$USER_ID" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "apikey: $SERVICE_KEY"
```

3. Verificar — `SELECT id FROM auth.users WHERE id = '<USER_ID>';`
   deve retornar 0 linhas.
4. **Não escrever de volta no log** — `outcome` é imutável e a linha
   já documenta o estado real (a auth-deletion foi feita pós-fato).
   Em vez disso, registrar em `portal_audit_log` (manual):
   ```sql
   INSERT INTO public.portal_audit_log (actor_id, action, target_type, target_id, metadata)
   VALUES (auth.uid(), 'account_deletion.auth_recovered', 'user', '<USER_ID>',
           jsonb_build_object('related_request_id', '<request_id>', 'reason', 'L04-02 recovery'));
   ```

### 4.3 `outcome IS NULL` há > 5 min (provável crash)

Pipeline pode ter parado em qualquer ponto. Para decidir o que fazer,
inspecionar o estado real:

```sql
-- Conta ainda existe?
SELECT id, email FROM auth.users WHERE id = '<user_id>';

-- Sobrou PII em algum lugar?
SELECT * FROM public.lgpd_user_data_coverage_gaps;  -- visão global
SELECT * FROM public.profiles WHERE id = '<user_id>';
SELECT * FROM public.coin_ledger WHERE user_id = '<user_id>' LIMIT 5;
```

Cenários:
- auth.user existe + PII existe → `cleanup_failed` na prática. Tratar como §4.1.
- auth.user existe + PII parcial → cleanup ficou pela metade. **Não
  re-rodar `fn_delete_user_data` cegamente**: rodar apenas para o
  `user_id` afetado e checar a `cleanup_report` antes de seguir com o
  auth delete.
- auth.user não existe + PII existe → `auth_delete_failed` mascarado;
  tratar como §4.2 (mas o auth já se foi, então só a parte de limpar
  os resíduos resta — rodar `SELECT public.fn_delete_user_data('<user_id>')`
  via service_role).

## 5. Verificação pós-mitigation

```sql
-- 1. Não deve haver outcome NULL > 5 min
SELECT count(*)
  FROM public.account_deletion_log
 WHERE outcome IS NULL
   AND initiated_at < now() - interval '5 minutes';
-- esperado: 0

-- 2. Não deve haver auth_delete_failed pendente sem registro de recuperação
SELECT adl.request_id, adl.user_id, adl.initiated_at
  FROM public.account_deletion_log adl
 WHERE adl.outcome = 'auth_delete_failed'
   AND adl.initiated_at > now() - interval '24 hours'
   AND NOT EXISTS (
     SELECT 1 FROM public.portal_audit_log pal
      WHERE pal.action = 'account_deletion.auth_recovered'
        AND pal.target_id = adl.user_id::text
   );
-- esperado: 0
```

## 6. Comunicação ao usuário

Template para resposta ANPD / suporte (português, formal):

```
Assunto: Sua solicitação de exclusão de conta — Omni Runner

Prezado(a),

Confirmamos o recebimento de sua solicitação de exclusão de conta em
<DATA>. Nosso registro de auditoria interno (request_id <UUID>) indica
que <success: a exclusão foi concluída em <DATA_COMPLETED>; cleanup_failed:
houve uma falha temporária e nenhum dado foi alterado, pedimos que tente
novamente pelo aplicativo; auth_delete_failed: seus dados pessoais foram
removidos em <DATA_CLEANUP>; estamos completando a remoção do registro de
autenticação manualmente e finalizaremos em até 24 horas>.

Em conformidade com o Art. 18, VI da LGPD, mantemos um registro
auditável da ação de exclusão (não dos dados excluídos), para que possamos
comprovar à ANPD que o pedido foi atendido.

Atenciosamente,
DPO Omni Runner
```

## 7. Drill (trimestral)

1. Em staging, criar usuário-isca com PII mínima (profile, wallet, 1
   coin_ledger row).
2. Forçar `fn_delete_user_data` a falhar (e.g. dropar uma das tabelas
   alvo temporariamente, ou rodar com lock concorrente).
3. Chamar `delete-account` com o JWT do usuário-isca.
4. Validar que:
   - `account_deletion_log` tem `outcome='cleanup_failed'`,
   - `auth.users` ainda contém o isca,
   - PII ainda intacta nas tabelas.
5. Restaurar a tabela e refazer a chamada — deve passar com `outcome='success'`.
6. Cronometrar diagnóstico via §3 partindo só do alerta. Atualizar este
   runbook se algum passo foi ambíguo.

## 8. Observabilidade contínua

Adicionar ao dashboard (Grafana / Supabase Logs):

- **Painel**: contagem por outcome (last 24h, last 7d).
- **Alerta P2**: `cleanup_failed > 5 in 1h`.
- **Alerta P1**: `auth_delete_failed >= 1 in 1h`.
- **Alerta P1**: `outcome IS NULL AND initiated_at < now() - 10 min` count > 0.
