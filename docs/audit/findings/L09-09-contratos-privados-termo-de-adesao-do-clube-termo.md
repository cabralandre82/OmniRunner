---
id: L09-09
audit_ref: "9.9"
lens: 9
title: "Contratos privados (termo de adesão do clube, termo de atleta) inexistentes no repo"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["lgpd", "legal", "consent-management", "wave-1"]
files:
  - docs/legal/TERMO_ADESAO_ASSESSORIA.md
  - docs/legal/TERMO_ATLETA.md
  - docs/legal/README.md
  - supabase/migrations/20260421210000_l09_09_legal_contracts_consent.sql
  - tools/legal/check-document-hashes.ts
  - portal/src/app/api/consent/route.ts
  - supabase/functions/consent-record/index.ts
correction_type: docs
test_required: true
tests:
  - tools/test_l09_09_legal_contracts.ts
  - portal/src/app/api/consent/route.test.ts
  - tools/integration_tests.ts
linked_issues: []
linked_prs:
  - 5c1f09c
owner: legal-ops
runbook: docs/runbooks/LEGAL_CONTRACTS_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L09-09] Contratos privados (termo de adesão do clube, termo de atleta) inexistentes no repo
> **Lente:** 9 — CRO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Legal / Compliance / LGPD
**Personas impactadas:** Assessorias (club_adhesion), Atletas (athlete_contract), equipe jurídica, ANPD/auditoria externa.

## Achado
— `grep -rn "termo_adesao\|termo_atleta\|contrato" docs/` não encontrava versões legíveis, revisadas. A plataforma coletava consent sem existir o texto canônico correspondente: em auditoria ANPD ou ação judicial, era impossível provar **qual versão exata** uma assessoria ou atleta aceitou. LGPD Art. 7º I e Art. 8 §1 exigem consentimento demonstrável e documental — gap crítico de governança.

## Correção entregue (commit [5c1f09c](#))

Entrega em 6 camadas conectadas pelo hash SHA-256:

1. **Documentos canônicos** (`docs/legal/`):
   - `TERMO_ADESAO_ASSESSORIA.md` (v1.0, 12 cláusulas, cobrindo objeto, remuneração, LGPD controladoria conjunta, cap antifraude, foro, etc.) — `sha256=1103d8ee…1a3f1`.
   - `TERMO_ATLETA.md` (v1.0, 11 cláusulas, cobrindo termo de conhecimento de risco, limitação de responsabilidade da plataforma, matriz de tratamento de dados sensíveis) — `sha256=834f70fa…f2f1dd`.
   - `README.md` — convenções editoriais, modelo de integridade, processo de versionamento.

2. **Infra de consent estendida** (`supabase/migrations/20260421210000_l09_09_legal_contracts_consent.sql`):
   - CHECK de `consent_policy_versions.consent_type` e `consent_events.consent_type` ampliados com `'club_adhesion'` e `'athlete_contract'`.
   - Seed dos 2 novos tipos com `document_url` apontando para o MD e `document_hash` = SHA-256 canônico.
   - `fn_consent_grant` reescrita para aceitar os 10 tipos canônicos (8 originais + 2 novos).
   - `lgpd_deletion_strategy` anotada.
   - DO block self-test: `[L09-09] OK — 10 policies, hashes íntegros, CHECKs estendidos`.

3. **Drift detection** (`tools/legal/check-document-hashes.ts` + `npm run legal:check`):
   - Lê cada MD em `docs/legal/`, computa SHA-256, compara com EXPECTED.
   - Lockstep: verifica que o hash EXPECTED também aparece literalmente no SQL da migration (evita drift "silencioso").
   - Exit 1 em CI se qualquer inconsistência → build falha, forçando bump de versão.

4. **Whitelists cliente em sincronia** — 10 tipos em:
   - `portal/src/app/api/consent/route.ts` (`VALID_TYPES_LIST`).
   - `supabase/functions/consent-record/index.ts` (`VALID_TYPES`).

5. **Testes**:
   - `portal/src/app/api/consent/route.test.ts` — 9 casos vitest: accept novos tipos, reject unknown, propagate P0001.
   - `tools/test_l09_09_legal_contracts.ts` — 16 testes integração sandbox: schema, seed, CHECKs, fn_consent_grant+revoke, integridade hash MD↔DB.
   - `tools/integration_tests.ts` — atualizado para esperar 10 tipos canônicos e `document_hash` não-nulo nos novos.

6. **Runbook operacional** (`docs/runbooks/LEGAL_CONTRACTS_RUNBOOK.md`):
   - Como publicar v2.0 (bump material), v1.1 (correção tipográfica).
   - Como auditar consentimento de uma assessoria/atleta (SQL pronto).
   - Resposta a solicitação LGPD "não aceitei nada".
   - Bloqueio de assessoria por violação contratual.
   - Alertas/SLOs e troubleshooting de drift em CI.

## Validação

- `npx tsx tools/legal/check-document-hashes.ts` → OK (lockstep).
- Migration aplicada via psql: 2 rows seedadas, CHECK rejeita `bogus_xyz`, aceita os 2 novos tipos end-to-end.
- `npm run openapi:check` → OK.
- 50 testes vitest relacionados (consent/auto-topup/swap) → passing.

## Referência narrativa
Contexto completo em [`docs/audit/parts/05-cro-cso-supply-cron.md`](../parts/05-cro-cso-supply-cron.md) — anchor `[9.9]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.9).
- `2026-04-21` — ✅ fixed via commit `5c1f09c`: publicação dos 2 templates canônicos versionados + integração consent + drift detection + runbook.