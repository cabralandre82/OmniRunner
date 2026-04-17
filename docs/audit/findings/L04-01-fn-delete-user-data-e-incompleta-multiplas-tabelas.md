---
id: L04-01
audit_ref: "4.1"
lens: 4
title: "fn_delete_user_data é incompleta — múltiplas tabelas com PII não cobertas"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["lgpd", "finance", "mobile", "edge-function", "migration", "testing"]
files:
  - supabase/migrations/20260312000000_fix_broken_functions.sql
correction_type: migration
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-01] fn_delete_user_data é incompleta — múltiplas tabelas com PII não cobertas
> **Lente:** 4 — CLO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/migrations/20260312000000_fix_broken_functions.sql:5-36` deleta apenas 13 tabelas. Ausentes do schema atual:

- `custody_deposits` (CPF/CNPJ em `payer_document`, se houver)
- `custody_withdrawals` (dados bancários do beneficiário)
- `audit_logs` (IPs, user-agents, actor_id = PII)
- `support_tickets` comentários e anexos
- `push_tokens` / `fcm_tokens` (identificadores de dispositivo)
- `login_history` (se existir)
- `running_dna_profiles`, `wrapped_snapshots` (perfil comportamental detalhado)
- `posts`, `comments`, `reactions` do feed social
- `champ_participants`, `badge_awards` (retenção OK mas linkam atleta)
## Risco / Impacto

— Violação do Art. 18, VI LGPD (eliminação dos dados). ANPD pode multar em até 2 % do faturamento (limite R$ 50 mi/infração).

## Correção proposta

— Adicionar tabelas ausentes e incluir chamada Storage:

```sql
CREATE OR REPLACE FUNCTION public.fn_delete_user_data(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  BEGIN DELETE FROM push_tokens        WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM running_dna_profiles WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM wrapped_snapshots  WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM social_posts       WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM social_comments    WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM social_reactions   WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN UPDATE audit_logs SET actor_id = '00000000-0000-0000-0000-000000000000'::uuid,
         ip_address = NULL, user_agent = NULL
        WHERE actor_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN UPDATE custody_withdrawals SET beneficiary_document = NULL, beneficiary_name = 'Anônimo',
         bank_account = NULL WHERE requested_by = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN UPDATE support_tickets SET body = '[removido por solicitação LGPD]',
         email = NULL, phone = NULL WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  -- Existing deletes...
END;$$;
```

E no Edge Function:

```typescript
await adminDb.storage.from('avatars').remove([`${uid}/avatar.jpg`]);
const { data: list } = await adminDb.storage.from('sessions').list(uid);
if (list?.length) await adminDb.storage.from('sessions').remove(list.map(f => `${uid}/${f.name}`));
```

## Teste de regressão

— `fn_delete_user_data_full.sql.test` insere PII em 100 % das tabelas que referenciam `user_id`, chama a função e valida que `SELECT COUNT(*)` em cada tabela == 0 ou == anonimizado.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.1).