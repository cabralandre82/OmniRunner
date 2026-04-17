---
id: L08-02
audit_ref: "8.2"
lens: 8
title: "product_events.properties jsonb aceita qualquer payload — PII leak risk"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "rls", "mobile"]
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
# [L08-02] product_events.properties jsonb aceita qualquer payload — PII leak risk
> **Lente:** 8 — CDO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Dart code: `track("session_submitted", {"pace": 5.3, "location": sessionLatLng})`. Nenhuma validação Zod/JSON Schema no SQL. Devs distraídos podem colocar `email`, `cpf`, polyline completa.
## Risco / Impacto

— Violação LGPD no produto de analytics, que é distribuído a stakeholders de marketing/BI.

## Correção proposta

— RLS na tabela `product_events` permitindo apenas colunas-whitelist; trigger de validação:

```sql
CREATE OR REPLACE FUNCTION fn_validate_product_event() RETURNS trigger AS $$
DECLARE allowed text[] := ARRAY['step','method','challenge_id','championship_id','role','count','duration_ms'];
BEGIN
  IF NEW.properties IS NOT NULL THEN
    IF EXISTS (
      SELECT k FROM jsonb_object_keys(NEW.properties) k WHERE k NOT IN (SELECT unnest(allowed))
    ) THEN
      RAISE EXCEPTION 'Invalid property key in product_events' USING ERRCODE='PE001';
    END IF;
  END IF;
  RETURN NEW;
END;$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_product_event BEFORE INSERT ON product_events
  FOR EACH ROW EXECUTE FUNCTION fn_validate_product_event();
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.2).