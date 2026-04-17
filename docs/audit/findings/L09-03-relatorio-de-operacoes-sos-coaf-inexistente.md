---
id: L09-03
audit_ref: "9.3"
lens: 9
title: "Relatório de Operações (SOS COAF) inexistente"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "cron", "reliability"]
files: []
correction_type: code
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
# [L09-03] Relatório de Operações (SOS COAF) inexistente
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Mesmo que KYC seja implementado ([9.2]), não há função/cron detectando:

- Múltiplos depósitos < R$ 10 k em curto período (structuring / smurfing)
- Withdrawal imediato após depósito (dinheiro em trânsito, sem uso do produto)
- Swap entre grupos controlados pelo mesmo CPF/CNPJ (wash trading)
- Volume anômalo vs baseline histórico
## Correção proposta

—

```sql
CREATE TABLE public.aml_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES coaching_groups(id),
  user_id uuid,
  rule_code text NOT NULL,
  severity text CHECK (severity IN ('low','medium','high','coaf_reportable')),
  details jsonb,
  created_at timestamptz DEFAULT now(),
  reviewed_at timestamptz,
  reviewer_id uuid
);

-- Detect structuring (5+ deposits < 10k BRL in 7 days)
CREATE OR REPLACE FUNCTION fn_detect_structuring() RETURNS void AS $$
BEGIN
  INSERT INTO aml_flags (group_id, rule_code, severity, details)
  SELECT d.group_id, 'STRUCTURING_R1',
    CASE WHEN COUNT(*) >= 10 THEN 'coaf_reportable' ELSE 'high' END,
    jsonb_build_object('count', COUNT(*), 'total_usd', SUM(amount_usd),
                       'window', '7_days')
  FROM custody_deposits d
  WHERE status='confirmed' AND created_at > now() - interval '7 days'
    AND amount_usd < 10000
  GROUP BY d.group_id
  HAVING COUNT(*) >= 5;
END;$$ LANGUAGE plpgsql;

-- Cron: hourly
SELECT cron.schedule('aml-structuring-detect','*/10 * * * *',
  $$SELECT fn_detect_structuring()$$);
```

UI `/platform/compliance` para revisor marcar casos, gerar arquivo COAF (layout XML do siscoaf).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.3).