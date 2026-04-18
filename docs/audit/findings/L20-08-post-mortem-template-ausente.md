---
id: L20-08
audit_ref: "20.8"
lens: 20
title: "Post-mortem template ausente"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["sre", "process"]
files:
  - docs/postmortems/TEMPLATE.md
  - docs/postmortems/README.md
correction_type: process
test_required: true
tests:
  - docs/postmortems/TEMPLATE.md
  - docs/postmortems/README.md
linked_issues: []
linked_prs:
  - "commit:75e4a7f"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "TEMPLATE.md modela Google SRE blameless postmortem (resumo executivo, metadados, impacto, timeline, causa raiz por 5-whys, what worked/didn't, action items SMART com owner+deadline, lessons learned, findings auditoria gerados, apêndice de evidências). README.md cobre filosofia, gatilhos obrigatórios/recomendados, workflow T+24h/T+48h/T+5d/T+7d/T+30d, naming convention, privacidade LGPD."
---
# [L20-08] Post-mortem template ausente
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** processo
**Personas impactadas:** Plataforma (SRE), todos os devs

## Achado
`docs/` não tinha template de post-mortem blameless. Após incidente,
aprendizado se perde — cada um lembra de coisas diferentes, sem
documento canônico para ler em 6 meses quando "isso já aconteceu antes,
o que fizemos?"

## Risco / Impacto
- **Falha repetida**: mesmo bug reaparece 3 meses depois porque
  ninguém lembra do incidente anterior.
- **Conhecimento siloed**: dev que respondeu sai da empresa →
  conhecimento sai junto.
- **Cultura de blame**: sem framework explícito blameless, instinto
  natural é apontar dedo → time fica defensivo → relata menos →
  postmortems pioram.

## Correção implementada

### `docs/postmortems/TEMPLATE.md`
Modelado após Google SRE blameless postmortem. Seções:

1. **Resumo executivo** (150 palavras) — leitura de 30s para CEO/CTO
2. **Metadados** — timing, severidade, owner, money loss, SLOs impactados,
   error budget burned, runbook usado, findings relacionados
3. **Impacto** — usuários (concreto, com números), plataforma, time
4. **Timeline UTC** — minute-by-minute reconstruction
5. **Causa raiz** — 5 whys forçando causa SISTÊMICA (não pessoa)
6. **O que funcionou bem** (★) — preserva mecanismos que ajudaram
7. **O que não funcionou** (✗) — específico, vira candidato a action item
8. **Action items** SMART — owner + deadline + tipo (prevent/detect/mitigate/process)
9. **Lessons learned** — 3-5 bullets para o time
10. **Findings auditoria gerados** — link para LXX-YY novos
11. **Apêndice** — queries, logs (REDACTED), screenshots, links externos

### `docs/postmortems/README.md`
Cobre:
- **Filosofia blameless** (foco em sistemas, não pessoas)
- **Gatilhos obrigatórios** (SEV-0/1, money loss > R$100, SLO P1
  abaixo de target, restore de backup, customer escalation a CTO/CEO)
- **Gatilhos recomendados** (near-miss, drill DR com RTO > target)
- **Workflow** com timeline T+24h/T+48h/T+5d/T+7d/T+30d
- **Naming convention** (`YYYY-MM-DD-slug-cinético.md`)
- **Privacidade LGPD** (nunca incluir PII, secrets, health data raw)
- **Index** placeholder (preenchido conforme postmortems forem
  escritos)

## Integração com outros runbooks
- DR_PROCEDURE.md (L20-07) Modo B fase 7 → "Postmortem (T+24h)" usa
  este TEMPLATE.md
- ALERT_POLICY.md (L20-05) drill trimestral → postmortem do drill usa
  este TEMPLATE.md
- Todo finding novo derivado de postmortem é criado seguindo o padrão
  `docs/audit/findings/LXX-YY-<slug>.md` e atualizado em
  `docs/audit/ROADMAP.md`.

## Teste de regressão
- TEMPLATE.md inclui instrução visível "REMOVER ESTAS LINHAS DE
  INSTRUÇÃO ANTES DE PUBLICAR" — defesa contra cargo-cult de copiar
  template literal.
- README.md exige nome com data + slug cinético — `pmortem-<pessoa>.md`
  é explicitamente listado como mau exemplo (viola blameless).

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.8).
- `2026-04-17` — Correção implementada: TEMPLATE.md (Google SRE blameless model) + README.md com filosofia, gatilhos, workflow timeline, naming convention, integração com DR/alert/findings. Promovido a `fixed`.
