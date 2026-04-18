---
id: L11-03
audit_ref: "11.3"
lens: 11
title: "Sem gitleaks / trufflehog no CI"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["supply-chain", "secrets", "ci", "pre-commit"]
files:
  - .github/workflows/security.yml
  - .gitleaks.toml
  - lefthook.yml
correction_type: config
test_required: true
tests:
  - .github/workflows/security.yml
  - .gitleaks.toml
linked_issues: []
linked_prs:
  - "commit:d14f667"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Defesa em camadas: pre-commit hook (lefthook + gitleaks protect --staged) catch antes do push; CI gitleaks-action@v2 em todo PR; full-history sweep semanal (cron segunda 06:00 UTC) para detectar secrets que possam ter sido commitados antes deste gate. `.gitleaks.toml` allowlist .env.example/fixtures/audit-docs/lockfiles para zero false positives."
---
# [L11-03] Sem gitleaks / trufflehog no CI
> **Lente:** 11 — Supply Chain · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** CI / supply chain / dev workflow
**Personas impactadas:** Plataforma (security), DevOps, todos os devs

## Achado
PRs com secret vazado passavam direto. Dev podia fazer commit de
`SUPABASE_SERVICE_ROLE_KEY=eyJ...` por engano e o secret ficava
permanentemente no histórico Git, mesmo se o commit fosse revertido
depois. Não havia:
- Varredura local (pre-commit) bloqueando o commit antes de existir.
- Varredura no CI bloqueando o merge.
- Varredura periódica de full history para detectar secrets pré-existentes.

## Risco / Impacto
- Vazamento permanente de credenciais em repo público/privado.
  `git filter-branch`/`bfg-repo-cleaner` não removem do histórico de
  forks, runners CI cacheados, ou clones em laptops de devs.
- Material exfiltrado: `SUPABASE_SERVICE_ROLE_KEY` permite **bypass total
  de RLS** — leitura/escrita irrestrita do banco. `OPENAI_API_KEY`
  permite consumo financeiro malicioso. `SENTRY_AUTH_TOKEN` permite
  upload de source maps fake.
- Toda credencial vazada precisa ser **rotada manualmente** em todos os
  serviços (Vault, Supabase, Vercel, Sentry, OpenAI, Asaas) — operação
  cara e propensa a esquecer rota dependente.

## Correção implementada

Defesa em 3 camadas:

### 1. Pre-commit local (lefthook)
`lefthook.yml` adiciona hook `gitleaks`:
```yaml
gitleaks:
  run: |
    if command -v gitleaks >/dev/null 2>&1; then
      gitleaks protect --staged --config .gitleaks.toml --no-banner --redact
    else
      echo "gitleaks not installed — skipping local pre-commit scan."
      echo "Install: https://github.com/gitleaks/gitleaks#installing"
    fi
```
- `protect --staged` escaneia apenas o que está prestes a ser commitado
  (rápido, ~50ms para diff típica).
- Skip-on-missing-binary: dev sem gitleaks instalado vê instrução, não
  falha o commit. Defesa em camadas — CI ainda pega.
- `--redact` para que secrets nunca apareçam em logs locais.

### 2. CI gate (PR + push para master)
`.github/workflows/security.yml` job `gitleaks` usa
`gitleaks/gitleaks-action@v2` que:
- Em PR: escaneia somente o **diff** (rápido, foco no que está sendo
  introduzido).
- Em push para master: escaneia o commit isolado.
- Lê `.gitleaks.toml` para regras + allowlist do projeto.
- Falha o build se qualquer match de regra default ou custom.
- Sobe artifact com detalhes para retro post-incident.

### 3. CI full-history sweep (semanal)
Trigger `schedule: cron '0 6 * * 1'` (segunda 06:00 UTC):
- `actions/checkout@v4 fetch-depth: 0` (full history).
- gitleaks-action escaneia **tudo desde a raiz**.
- Detecta secrets commitados ANTES deste gate ser instalado (que
  passariam despercebidos se eu só escanear o diff novo).
- Se encontrar: alerta time, runbook (a criar) é "rotar credencial +
  remover do histórico via BFG/filter-repo + force push".

### 4. `.gitleaks.toml` calibrado para zero false positives
Estende ruleset default (cobre ~150 padrões: AWS, GCP, Stripe, JWT,
Supabase, Sentry, Twilio, etc) com allowlist de paths e regexes
específicos do projeto:
- `.env.example`, `.env.sample`, `.env.template` — sample envs com
  placeholders.
- `**/fixtures/`, `**/__fixtures__/`, `**/test/*fixtures*` — test
  fixtures.
- `docs/audit/` — findings citam exemplos redacted como `sk_live_REDACTED`.
- `*.cdx.json`, `*.sbom.json` — SBOMs têm component hashes que
  podem casar com secret patterns.
- `*-lock.json`, `*.lock`, `pubspec.lock` — lockfiles têm integrity
  hashes (sha512=...) que casam com regex de hash genérico.
- Regexes para Supabase anon JWT (público por design — `NEXT_PUBLIC_*`
  prefix, mas só permitido em paths já restritos acima).
- Stopwords (`example`, `placeholder`, `redacted`, `your-key-here`,
  `fake`, `dummy`, `sample`) reduzem false positives em snippets de
  documentação.

### Bypass legítimo
Para casos extraordinários, anotar a linha:
```typescript
const sandboxKey = "sk_test_PUBLIC_DEMO_KEY"; // gitleaks:allow
```
Padrão `gitleaks:allow` é reconhecido nativamente — força revisão
explícita.

## Follow-ups

1. **L11-03-followup-historical-sweep** — rodar primeira full-history
  sweep manualmente (workflow_dispatch) ANTES do primeiro merge desta
  PR para garantir que repo está limpo na baseline. Se encontrar
  secrets antigos: rotar credenciais + (opcional) limpar histórico
  com BFG. Estimado: 1-3 pontos.
2. **L11-03-followup-trufflehog-second-opinion** — adicionar trufflehog
  como segundo scanner (cobertura complementar — pega alguns padrões
  que gitleaks não pega, e vice-versa). Estimado: 2 pontos.

## Teste de regressão
- CI: `.github/workflows/security.yml::gitleaks` roda em todo PR e push.
- Local: `cd /tmp && echo "AWS_SECRET_KEY=AKIA1234567890ABCDEF" > test.txt &&
  cd - && cp /tmp/test.txt . && git add test.txt &&
  git commit` deve **falhar** com lefthook bloqueando.
- Manual smoke: `gitleaks detect --config .gitleaks.toml --source .`
  contra working tree não retorna findings (allowlist está correta).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.3]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.3).
- `2026-04-17` — Correção implementada: defesa em 3 camadas (pre-commit lefthook + CI gate em PR/push + full-history sweep semanal), `.gitleaks.toml` calibrado com allowlists para zero false positives. Follow-ups documentados (historical sweep manual, trufflehog second-opinion). Promovido a `fixed`.
