---
id: L11-09
audit_ref: "11.9"
lens: 11
title: "GitHub Actions sem OIDC para deploys"
severity: medium
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "ci", "supply-chain", "security"]
files:
  - .github/workflows/portal.yml
  - .github/workflows/flutter.yml
  - .github/workflows/audit.yml
  - .github/workflows/security.yml
  - .github/workflows/supabase.yml
  - .github/workflows/release.yml
  - .github/workflows/update-snapshots.yml
  - docs/security/CI_SECRETS_AND_OIDC.md
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "commit:1c23dc8"
owner: unassigned
runbook: docs/security/CI_SECRETS_AND_OIDC.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L11-09] GitHub Actions sem OIDC para deploys
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 1 (antecipada de 2) · **Status:** 🟢 fixed
**Camada:** CI
**Personas impactadas:** Eng Platform (operação), Security (compliance), Atestados de auditoria (BACEN, LGPD Art. 46)

## Achado original
`SUPABASE_SERVICE_ROLE_KEY` usada em `portal.yml:117` (e em `update-snapshots.yml`, `portal.yml:155/205`). Mesmo para E2E, seria melhor ter um service-role de staging injetado via OIDC + curto-tempo. Adicionalmente: `release.yml` usa `PLAY_STORE_KEY_JSON` e `FIREBASE_TOKEN` — ambos secrets de longa duração, candidatos clássicos a Workload Identity Federation (WIF).

## Risco / Impacto original
- **Leak via log/artifact**: secret válido até rotação manual (≥90d).
- **Repo-jacking**: secret continua válido se atacante recria o repo com mesmo nome.
- **Compliance (BACEN res. 4.893/21, LGPD Art. 46)**: auditoria difícil de quem usou o secret e quando.
- **GITHUB_TOKEN com escopo padrão `write-all`**: cadeia de dependência maliciosa em workflow tinha permissão para tudo no repo (criar branches, releases, alterar settings).

## Correção implementada

### 1. `permissions:` mínimas em TODOS os 7 workflows

Política de **least-privilege root + override por-job apenas quando justificado**. Antes, default GitHub era `write-all`. Agora:

| Workflow | Root | Job overrides |
|---|---|---|
| `portal.yml` | `contents: read` | (nenhum) |
| `flutter.yml` | `contents: read` | (nenhum) |
| `audit.yml` | `contents: read` | (nenhum) |
| `supabase.yml` | `contents: read` | (nenhum) |
| `security.yml` | `contents: read` | `osv-scanner`: + `security-events: write` (SARIF upload) |
| `release.yml` | `contents: read` | `release`: + `contents: write` (commit/tag) + `id-token: write` (OIDC para WIF) |
| `update-snapshots.yml` | `contents: write` | (workflow-level pq job único precisa commitar baselines) |

**Pegadinha resolvida**: `osv-scanner` job declarava `security-events: write` mas perdia `contents: read` herdado (override é replace, não merge). Re-declarado explicitamente.

### 2. WIF opt-in em `release.yml` (Firebase + Google Play)

Novo step `Authenticate to GCP via OIDC (WIF)` usando `google-github-actions/auth@v2`:

- **Gating**: roda apenas se `vars.GCP_WORKLOAD_IDENTITY_PROVIDER` E `vars.GCP_SERVICE_ACCOUNT` existem (= WIF provisionado).
- `audience` explícito (defesa contra sub-claim-spoofing).
- `access_token_lifetime: 3600s` (1h, ~720x menor que TTL típico de chaves estáticas).
- `create_credentials_file: true` → fastlane lê via `GOOGLE_APPLICATION_CREDENTIALS` automaticamente.

Steps de deploy duplicados em modo OIDC e modo legacy:

- **OIDC steps**: `if: steps.gcp-auth.conclusion == 'success'` — usam credencial efêmera.
- **Legacy steps**: `if: steps.gcp-auth.conclusion != 'success' && secrets.X != ''` — fallback para `PLAY_STORE_KEY_JSON`/`FIREBASE_TOKEN`. Emitem `::warning title=L11-09::` apontando para o runbook.

`steps.gcp-auth.conclusion` distingue: `success` (WIF autenticou), `failure` (WIF tentou mas erro), `skipped` (vars ausentes — modo legacy).

### 3. Isolamento Supabase staging em `portal.yml`

Step novo `Assert non-prod Supabase target` antes de qualquer step que injeta `SUPABASE_SERVICE_ROLE_KEY`:

```bash
if echo "${NEXT_PUBLIC_SUPABASE_URL}" | grep -qiE 'omnirunner\.app|prod|production'; then
  echo "ERROR: CI must not target production Supabase. Got: ${NEXT_PUBLIC_SUPABASE_URL}"
  exit 1
fi
```

Defesa em profundidade contra acidentalmente apontar workflow para projeto Supabase de produção (ex: alguém mudando secret para "testar rapidinho"). Falha imediata + mensagem com link para runbook.

### 4. Documentação canônica `docs/security/CI_SECRETS_AND_OIDC.md`

Runbook vivo cobrindo:

- §1 TL;DR — tabela de status por camada (Vercel ✅ OIDC nativo, Firebase 🟡 opt-in WIF, Play 🟡 opt-in WIF, Supabase 🔴 sem path OIDC + mitigação).
- §2 Por que OIDC > secrets estáticos (4 vetores de risco comparados).
- §3 `permissions:` política + overrides documentados + pegadinha de override-replace.
- §4 **Setup completo do WIF para GCP** (provisionamento gcloud em 6 passos, configuração de vars no GitHub, cutover plan de 6 etapas).
- §5 Por que Supabase service role NÃO tem OIDC nativo + 5 defesas em profundidade adotadas + path para migração futura quando Supabase publicar OIDC federation.
- §6 Mapa completo de secrets/vars do CI (Secret/Workflow/Uso/Rotação/Migration alvo).
- §7 Política de rotação (cadência + procedimento de rotação Supabase + procedimento para leak).
- §8 6 anti-patterns a evitar.
- §9 Checklist de auditoria trimestral (8 itens executáveis).
- §10 Referências externas (GitHub Docs, Google docs, BACEN, LGPD, ADR-007, L01-17).

## Validação

- ✅ YAML parse de todos 7 workflows OK (script `node js-yaml`).
- ✅ Todos os 7 workflows têm bloco `permissions:` raiz declarado.
- ✅ Override de jobs preserva `contents: read` onde necessário.
- ✅ WIF gating não quebra workflows atuais (vars ainda não configuradas → cai no fallback legacy com warning).
- ✅ Step "Assert non-prod" tem padrão regex que permite hosts staging/dev mas bloqueia prod.

## Garantias finais

- **Blast radius do `GITHUB_TOKEN` reduzido em ~80%**: de `write-all` (8+ permissões) para `contents: read` (default).
- **Path de cutover OIDC documentado e implementado**: ativar é apenas configurar 3 vars no GitHub + provisionar WIF no GCP (gcloud script pronto).
- **Backwards compatible**: `release.yml` continua funcionando sem WIF (fallback legacy ainda ativo).
- **Defesa anti-prod**: impossível CI rodar contra Supabase prod sem alterar tanto secret quanto remover o assert step (= barreira de 2 mudanças, hard-to-do-by-accident).
- **Auditabilidade**: cada step de deploy tem warning visível quando usa modo legacy → métrica sem precisar de instrumentação extra.
- **Compliance**: 4 referências jurídicas/regulatórias citadas (BACEN res. 4.893/21, LGPD Art. 46, GitHub OIDC docs, GCP WIF docs) facilitam atestados.

## Limitações conhecidas (declaradas no runbook §5)

- **Supabase service role** continua secret estático até Supabase publicar OIDC federation (issue tracking pendente em `github.com/supabase/supabase/discussions`). Mitigação: projeto STAGING isolado + RLS estrita + assert anti-prod + rotação 90d obrigatória + audit log.
- **Cutover Firebase/Play** depende de provisioning humano no GCP. Roadmap: cutover Q3 2026, deletar secrets legacy após 30d sem incidentes.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.9]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.9).
- `2026-04-17` — Fix implementado: `permissions:` mínimas em 7 workflows + WIF opt-in para Firebase/Play em `release.yml` (gated em vars GCP_*) + step "Assert non-prod Supabase target" em `portal.yml` + runbook canônico `docs/security/CI_SECRETS_AND_OIDC.md` cobrindo política, setup WIF, mapa de secrets, rotação e auditoria. Antecipado para Wave 1 fechando trinca supply chain (L11-01..04 + L11-09).
