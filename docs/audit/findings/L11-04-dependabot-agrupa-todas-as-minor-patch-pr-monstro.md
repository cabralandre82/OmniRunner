---
id: L11-04
audit_ref: "11.4"
lens: 11
title: "Dependabot agrupa todas as minor+patch — PR monstro"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["testing", "ci", "supply-chain"]
files:
  - .github/dependabot.yml
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "commit:c702023"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L11-04] Dependabot agrupa todas as minor+patch — PR monstro
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** CI
**Personas impactadas:** Eng Platform (manutenção), Security (resposta a CVE)

## Achado
`.github/dependabot.yml:12-16` agrupava TODAS as minor+patch num único PR semanal. Se UMA dependência quebrasse build/teste, o PR inteiro era bloqueado — impossível mergear as outras 20 atualizações que estavam OK. Resultado: backlog de updates acumulando, com pressão para "skip review" no review final.

## Risco / Impacto
- **Janela de exposição CVE**: security update preso atrás de bump de dependência incompatível.
- **Toil de manutenção**: rebases manuais em PR enorme; revisor precisa entender 30+ pacotes diferentes.
- **Perda de assinatura semântica**: commit message e changelog sem clareza de "qual área foi tocada".

## Correção implementada

### Reorganização do `.github/dependabot.yml`

**Princípios**:
1. **Grupos por área semântica** — cada cluster de pacotes correlatos vai num PR só (next, supabase, sentry, testing, etc). Falha num grupo não bloqueia os outros.
2. **Major bumps NUNCA agrupados** — usando `update-types: ["minor", "patch"]` em todos os groups, qualquer major automaticamente cai fora e gera PR individual (default Dependabot). Forçamos revisão de breaking changes peça-a-peça.
3. **Catch-all explícito** — `other-{portal,mobile,ci}-minor-patch` com `patterns: ["*"]` captura qualquer pacote fora dos grupos temáticos. Garante que nada vira "PR órfão".
4. **Security updates separados** — grupo `applies-to: security-updates` com `patterns: ["*"]` em cada ecossistema agrupa CVE fixes para deploy rápido (defesa em profundidade vs. delay de gating de updates regulares).
5. **Versioning strategy `increase`** no portal — bump conservador de caret bound, evita downgrade acidental.
6. **Commit messages padronizados** — `chore(portal-deps)`/`chore(portal-deps-dev)`/`chore(mobile-deps)`/`chore(ci-deps)` com escopo, alinhado a Conventional Commits.

**Grupos criados**:

| Ecossistema | Grupos | Total |
|-------------|--------|-------|
| `npm` (portal) | next-ecosystem, react-ecosystem, supabase-ecosystem, sentry-ecosystem, testing-ecosystem, styling-ecosystem, types-and-tooling, validation-and-state, other-portal-minor-patch, portal-security | **10** |
| `pub` (omni_runner) | bloc-stack, firebase-stack, supabase-flutter, sentry-flutter, drift-and-storage, auth-stack, geolocation-and-maps, health-and-fitness, media-and-content, networking-and-routing, mobile-testing-and-tooling, other-mobile-minor-patch, mobile-security | **13** |
| `github-actions` | official-actions, security-actions, other-ci-minor-patch, ci-security | **4** |
| **Total** |  | **27** |

**Config quality-of-life**:
- `time: "06:00" timezone: "America/Sao_Paulo"` — PRs aparecem antes do dia útil começar (revisão na primeira hora).
- `open-pull-requests-limit` ajustado: portal=15 (mais grupos), mobile=12, ci=5 (mensal).
- `exclude-patterns` em `types-and-tooling` evita conflito com `react-ecosystem` (que já cobre `@types/react*`).
- Grupos vazios ainda aparecem no PR como "no updates" — isso é OK e documenta a saúde do ecossistema.

### Validação

- YAML parse OK via `js-yaml` — sintaticamente válido.
- 27 grupos detectados pelo loader, distribuídos em 3 ecossistemas — match exato do design.
- Schema obedece spec Dependabot v2 (https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file).

### Mudança de comportamento esperada

Antes:
- 1 PR por semana com `Bump 23 dependencies` no portal.
- Se `next 14.2.15 → 14.2.20` mudou a API de algum hook usado por nós, o PR fica vermelho — nenhum dos outros 22 bumps merge.

Depois:
- ~10 PRs por semana no portal (1 por grupo com updates pendentes, vazios são suprimidos).
- `Bump next-ecosystem (3 packages)` falha → reviewer revisa esse grupo isoladamente; `Bump testing-ecosystem (2 packages)` continua merge-able.
- Security updates pulam a fila via grupo separado.

## Garantias finais

- **Isolamento**: falha em PR de um grupo não bloqueia os outros 26.
- **Auditabilidade**: nome do grupo no título do PR sinaliza área impactada (`next`, `supabase`, etc).
- **Performance de revisão**: PR menor = review mais rápido = menos toil.
- **Security responsiveness**: CVE fix em qualquer pacote vira PR independente via `applies-to: security-updates`.
- **Sem regressão major**: `update-types: [minor, patch]` em TODOS os grupos — major bump sempre PR individual.
- **Cobertura total**: catch-all `other-*-minor-patch` garante 0 pacotes "esquecidos".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/05-cro-cso-supply-cron.md`](../parts/05-cro-cso-supply-cron.md) — anchor `[11.4]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.4).
- `2026-04-17` — Fix implementado: dependabot.yml reescrito com 27 grupos semânticos (10 portal + 13 mobile + 4 actions), security updates isolados, major bumps individuais, commit messages padronizados. YAML validado.
