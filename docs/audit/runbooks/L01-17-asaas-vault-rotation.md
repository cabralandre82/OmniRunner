# Runbook — L01-17 · Asaas secrets (vault)

> **Escopo:** gerenciar API Keys e webhook tokens do Asaas armazenados no
> `supabase_vault`. Inclui rotação rotineira, rotação de emergência
> (leak/comprometimento), revogação e auditoria.

## Arquitetura

- Secrets nunca vivem em coluna `TEXT` — apenas IDs em
  `payment_provider_config.{api_key_secret_id,webhook_token_secret_id}`.
- Valor decriptado só acessível via:
  - `public.fn_ppc_get_api_key(uuid, text)` — **service_role only**
  - `public.fn_ppc_get_webhook_token(uuid, text)` — **service_role only**
- Escrita / rotação:
  - `public.fn_ppc_save_api_key(uuid, text, text, text)` — admin_master/coach ou service_role
  - `public.fn_ppc_save_webhook_token(uuid, text, text, text)` — service_role only
- Toda operação (`create`/`rotate`/`read`/`delete`) é registrada em
  `public.payment_provider_secret_access_log` com
  `(group_id, secret_kind, action, actor_user_id, actor_role, request_id, accessed_at)`.

## Operações rotineiras

### 1. Rotação planejada da API Key (SOP — 90 dias)

1. Gere nova API Key no painel Asaas da assessoria.
2. Portal → Configurações → Pagamentos → **Testar conexão** (valida a nova key sem persistir).
3. Portal → **Salvar** (dispara `POST /api/billing/asaas` com `action=save_config` →
   `fn_ppc_save_api_key` → `vault.update_secret`).
4. Audit log deve registrar `action='rotate'`:
   ```sql
   SELECT accessed_at, actor_user_id, request_id
     FROM public.payment_provider_secret_access_log
    WHERE group_id = '<uuid>'
      AND secret_kind = 'api_key'
      AND action = 'rotate'
    ORDER BY accessed_at DESC LIMIT 5;
   ```
5. Invalide a key antiga no Asaas (painel → API Keys → Revogar).

### 2. Rotação do webhook token (SOP — 180 dias ou pós-incidente)

Clicar **Reconfigurar Webhook** na UI → Edge Function `asaas-sync/setup_webhook`
gera novo `randomUUID`, chama `fn_ppc_save_webhook_token`, registra no Asaas.
O anterior é substituído (rotated=true no audit).

### 3. Auditar quem leu um secret nas últimas 24h

```sql
SELECT group_id, secret_kind, action, actor_role, request_id, accessed_at
  FROM public.payment_provider_secret_access_log
 WHERE accessed_at >= now() - interval '24 hours'
   AND action = 'read'
 ORDER BY accessed_at DESC;
```

### 4. Desconectar (hard)

```sql
-- Admin DB; zera a referência e (opcionalmente) remove o secret do vault:
UPDATE public.payment_provider_config
   SET is_active = false, api_key_secret_id = NULL, webhook_token_secret_id = NULL
 WHERE group_id = '<uuid>' AND provider = 'asaas';

DELETE FROM vault.secrets
 WHERE name IN (
   'asaas:api_key:' || '<uuid>',
   'asaas:webhook_token:' || '<uuid>'
 );
```

## Resposta a incidente (key comprometida)

1. **Revogar no Asaas** painel (primeiro — corta impacto imediato).
2. **Gerar nova key** no painel.
3. **Rotacionar no portal** (SOP 1).
4. Confirmar via audit log que só `service_role` leu nas últimas 24h:
   ```sql
   SELECT count(*) FILTER (WHERE actor_role <> 'service_role') AS non_service_reads
     FROM public.payment_provider_secret_access_log
    WHERE group_id = '<uuid>' AND secret_kind='api_key' AND action='read'
      AND accessed_at >= now() - interval '24 hours';
   ```
   `non_service_reads > 0` → **escalar**: alguém com JWT do grupo leu via RPC
   não-privada (não deveria ocorrer com os GRANTs atuais, investigar).
5. Rotacionar **webhook token** também (SOP 2) — assumimos comprometimento lateral.

## Alertas / SLOs

- **Alerta crítico**: `fn_ppc_get_api_key` retorna `VAULT_MISS` (P0003) —
  indica `api_key_secret_id` órfão (secret removido do vault). Deve ser 0.
- **Alerta warning**: `payment_provider_secret_access_log` sem nenhuma entrada
  `action='rotate'` em 120 dias para um grupo ativo (`is_active=true`).
- **Métrica**: taxa de reads / hora por grupo — picos indicam loop indevido.

## Troubleshooting

| Sintoma | Diagnóstico | Ação |
|---|---|---|
| `NO_CONFIG` em Edge Function | ppc sem api_key_secret_id | Admin deve refazer "Salvar" no portal |
| `FORBIDDEN` em save | Caller não é admin_master/coach nem service_role | Verificar `auth.uid()` / role em JWT |
| `VAULT_ERROR` em Edge Function | `vault.decrypted_secrets` inacessível | Verificar GRANT da função ao service_role |
| Log sem rotação há > 120d | Chave velha, risco de vazamento | Rotacionar (SOP 1) |

## Migration de referência

- `supabase/migrations/20260417210000_asaas_vault_secrets.sql`
  - Cria colunas `api_key_secret_id`, `webhook_token_secret_id`
  - Backfill de valores plaintext para o vault
  - Drop `api_key` e `webhook_token` (texto) — idempotente
  - Cria as 5 RPCs (`fn_ppc_*`)
  - Cria `payment_provider_secret_access_log` com RLS
