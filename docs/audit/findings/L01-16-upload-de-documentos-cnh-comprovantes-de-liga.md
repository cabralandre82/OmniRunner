---
id: L01-16
audit_ref: "1.16"
lens: 1
title: "Upload de documentos — CNH, comprovantes de liga"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["lgpd", "rls", "mobile", "portal", "migration"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L01-16] Upload de documentos — CNH, comprovantes de liga
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** APP (Flutter) + BACKEND (Storage)
**Personas impactadas:** Atleta profissional (envio de documentos para liga/filiação)
## Achado
Grepping rápido não encontrou endpoint portal `/api/documents/upload` nem `/api/lgpd/*` no portal (`ls portal/src/app/api/`). Uploads parecem ir direto para Supabase Storage via SDK do app. Para re-auditoria: verificar buckets do Storage e policies RLS.
## Correção proposta

Auditar separadamente com `ls supabase/migrations | grep -i storage`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.16).