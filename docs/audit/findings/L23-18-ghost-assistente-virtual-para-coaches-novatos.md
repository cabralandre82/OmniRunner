---
id: L23-18
audit_ref: "23.18"
lens: 23
title: "Ghost/assistente virtual para coaches novatos"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["personas", "coach", "ai", "rag"]
files:
  - docs/product/COACH_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "k12-pending"

owner: product+ai+legal
runbook: docs/product/COACH_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/COACH_BASELINE.md` § 4
  (AI Copilot for novice coaches). RAG sobre corpus
  licenciado (Daniels, Pfitzinger, Fitzgerald, Magness)
  via `coach_lit_docs` com pgvector HNSW. Modelo
  primário GPT-4o, fallback Claude 3.5 Sonnet (padrão
  já usado em `generate-run-comment`). Contexto athlete
  lido RLS-scoped (sessions 12w, zones L21-05, plan
  L09-12, goal L22-18). Guardrails HARD:
  (a) todo output cita fontes + disclaimer "prescrição
  final é responsabilidade do coach"; (b) prompts
  match `/lesão|dor/i` retornam redirect L22-16 injury
  triage; (c) zero direct medication advice; (d) PII
  strip reuso L04-13. Tier gated (Copilot Pro paga
  higher limit + fine-tuning opt-in). Ship Wave 5 fase
  W5-F (last — license procurement + guardrail QA cost).
---
# [L23-18] Ghost/assistente virtual para coaches novatos
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach jovem (primeiro ano pós-formatura) insegura em prescrições. Sem "Omni AI Coach Mentor": "Seu atleta corre 3:30/km em 5 km, idade 35, volume atual 40 km/sem. Sugerir volume semana 16 de maratona?"
## Correção proposta

— Tier "AI Copilot" (GPT-4o ou similar) com RAG sobre literatura científica (Daniels, Pfitzinger).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.18]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.18).
- `2026-04-24` — Consolidado em `docs/product/COACH_BASELINE.md` § 4 (batch K12); implementação Wave 5 fase W5-F.
