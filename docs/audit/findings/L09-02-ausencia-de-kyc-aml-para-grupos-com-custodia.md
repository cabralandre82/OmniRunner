---
id: L09-02
audit_ref: "9.2"
lens: 9
title: "Ausência de KYC/AML para grupos com custódia"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "migration", "performance", "testing"]
files: []
correction_type: process
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
# [L09-02] Ausência de KYC/AML para grupos com custódia
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep -rn "kyc\|cpf\|cnpj\|coaf\|aml\|pep" supabase/migrations portal/src omni_runner/lib --include="*.{sql,ts,tsx,dart}"` → resultados vazios. Grupo/Assessoria cria custódia, deposita R$ 100k, saca via withdrawal **sem** validação:

- Nome completo / razão social cadastrada
- CPF/CNPJ do representante legal
- Comprovante de endereço
- Verificação em listas de sanções (OFAC, BCB, COAF, PEPs)
- Proof of funds para depósitos > R$ 50 k
## Risco / Impacto

— Plataforma vira veículo de lavagem. Comunicação COAF exigida > R$ 10 k suspeito (Circ. BCB 3.978/2020 Art. 49). Omissão = multa R$ 20 k–R$ 20 mi + responsabilidade criminal do diretor (Art. 23 Lei 9.613/98).

## Correção proposta

—

```sql
CREATE TABLE public.kyc_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES coaching_groups(id),
  legal_entity_type text NOT NULL CHECK (legal_entity_type IN ('individual','company')),
  document_type text NOT NULL CHECK (document_type IN ('CPF','CNPJ')),
  document_number text NOT NULL,
  document_number_hash bytea GENERATED ALWAYS AS
    (digest(document_number, 'sha256')) STORED,
  legal_name text NOT NULL,
  birth_date date,  -- only for individuals
  address jsonb NOT NULL,
  pep_status text CHECK (pep_status IN ('not_pep','pep','close_associate','unknown')) DEFAULT 'unknown',
  sanctions_list_match boolean DEFAULT false,
  verified_at timestamptz,
  verified_by text,  -- provider like 'idwall','unico','serpro'
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','review')),
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX ON kyc_verifications(document_number_hash);

-- Block custody_deposits unless group has approved KYC
CREATE OR REPLACE FUNCTION fn_require_kyc() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM kyc_verifications
    WHERE group_id = NEW.group_id AND status = 'approved'
  ) THEN RAISE EXCEPTION 'KYC required' USING ERRCODE='KYC01'; END IF;
  RETURN NEW;
END;$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_custody_deposit_requires_kyc
  BEFORE INSERT ON custody_deposits FOR EACH ROW EXECUTE FUNCTION fn_require_kyc();
```

Integrar com provedor (IDWall, Unico, Serpro Datavalid).

## Teste de regressão

— `kyc.required.test.sql`: tentar inserir custody_deposit sem KYC aprovado → erro `KYC01`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.2).