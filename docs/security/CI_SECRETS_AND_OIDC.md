# CI Secrets & OIDC — Estratégia e Operação

> **Status:** Vivo · **Última revisão:** 2026-04-17 · **Owner:** Eng Platform / Security
> **Findings relacionados:** [L11-09](../audit/findings/L11-09-github-actions-sem-oidc-para-deploys.md), [L01-17](../audit/findings/L01-17-asaas-api-key-armazenada-em-texto-puro.md)

Este documento define **como** o repositório lida com credenciais nos workflows CI, **por que** preferimos OIDC/Workload Identity Federation (WIF) sobre secrets de longa duração, e **quais migrations** estão pendentes.

---

## 1. TL;DR

| Camada | Status hoje | Alvo |
|---|---|---|
| `GITHUB_TOKEN` permissions | ✅ Least-privilege em todos workflows (root `contents: read`) | Manter |
| Vercel deploy (portal) | ✅ Native OIDC via integração Vercel↔GitHub (transparente) | Manter |
| Firebase App Distribution | 🟡 OIDC opt-in via WIF + fallback `FIREBASE_TOKEN` deprecated | Cutover Q3 2026, remover legacy |
| Google Play (fastlane) | 🟡 OIDC opt-in via WIF + fallback `PLAY_STORE_KEY_JSON` deprecated | Cutover Q3 2026, remover legacy |
| Supabase service role | 🔴 Secret estático (JWT do projeto). Mitigação: usar projeto STAGING + asserção anti-prod no CI | Rotação 90d + RLS reforçada (sem caminho OIDC nativo na Supabase) |
| Asaas API key | ✅ Em pgsodium AEAD (vault), não em GH Secrets (L01-17 fixo) | Manter |

---

## 2. Por que OIDC > Secrets de longa duração

| Risco | Secret estático | OIDC/WIF |
|---|---|---|
| Leak via log/build artifact | Válido até rotação manual (≥90d) | Token expira em ~1h |
| Fork/PR malicioso lendo `secrets.*` | Possível se workflow tem `pull_request_target` | Não aplicável (token é emitido por job, não armazenado) |
| Repo-jacking (atacante renomeia repo + recria) | Secret continua válido | `audience` claim ata token a `repo:owner/name`, falha em outro repo |
| Compliance (BACEN, LGPD Art. 46) | Auditoria difícil de quem usou | Cada token tem `jti` rastreável + GCP/AWS audit log |
| Custo operacional | Rotação manual periódica | Zero rotação |

OIDC é preferível **sempre que o destino suporta**. Para destinos que não suportam (Supabase service role), segue-se a defesa em profundidade: isolamento staging + auditoria + rotação.

---

## 3. `permissions:` — Least Privilege para `GITHUB_TOKEN`

Todos os workflows têm bloco `permissions:` no nível raiz. **Default GitHub é `contents: write` + 8 outras permissões = blast radius enorme** se um job for comprometido (cadeia de dependência maliciosa, etc).

### Política

```yaml
permissions:
  contents: read   # default global; override por-job se necessário
```

### Overrides documentados

| Workflow | Job | Override | Motivo |
|---|---|---|---|
| `release.yml` | `release` | `contents: write` + `id-token: write` | commitar version bump + tag + OIDC para WIF |
| `update-snapshots.yml` | `update-snapshots` | `contents: write` (workflow-level) | commitar baselines de visual regression |
| `security.yml` | `osv-scanner` | `security-events: write` (+ `contents: read`) | upload SARIF para GitHub Code Scanning |

### ⚠️ Pegadinha: `permissions:` por job substitui (não merge) o nível raiz

Se um job declara `permissions: { security-events: write }`, ele **perde** o `contents: read` herdado. Sempre re-declare `contents: read` em job-level overrides — caso contrário `actions/checkout` falha.

---

## 4. Workload Identity Federation (WIF) — Setup GCP

Aplicável a: Firebase App Distribution, Google Play, qualquer outro produto GCP.

### 4.1 Provisionamento (executar 1x por projeto GCP)

```bash
# Variáveis
PROJECT_ID="omni-runner-prod"   # ou staging
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
POOL="github-actions-pool"
PROVIDER="github-actions-provider"
GH_REPO="<owner>/project-running"   # ATENÇÃO: substituir pelo repo real
SA_NAME="github-actions-deployer"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 1. Criar Workload Identity Pool
gcloud iam workload-identity-pools create "$POOL" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# 2. Criar provider OIDC (audience = nosso repo apenas)
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="attribute.repository == '${GH_REPO}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# 3. Service Account com permissões mínimas
gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJECT_ID" \
  --display-name="GitHub Actions Deployer"

# 4. Conceder ao SA permissão para Firebase + Play
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/firebaseappdistro.admin"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/androidpublisher.releaseManager"

# 5. Permitir SA ser impersonado pelo workflow do nosso repo
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${GH_REPO}"

# 6. Capturar valores para configurar no GitHub
echo "GCP_WORKLOAD_IDENTITY_PROVIDER=projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
echo "GCP_SERVICE_ACCOUNT=${SA_EMAIL}"
echo "GCP_WORKLOAD_IDENTITY_AUDIENCE=https://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
```

### 4.2 Configurar no GitHub (1x)

Em **Settings → Secrets and variables → Actions → Variables** (não secrets — os 3 valores não são confidenciais):

- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `GCP_WORKLOAD_IDENTITY_AUDIENCE`
- `FIREBASE_APP_ID` (mover de secret para var; não é confidencial)

Quando essas 3 vars estão presentes, `release.yml` automaticamente entra em modo OIDC e ignora `secrets.PLAY_STORE_KEY_JSON` / `secrets.FIREBASE_TOKEN`.

### 4.3 Cutover plan

1. Provisionar WIF em projeto **staging** GCP primeiro.
2. Disparar `release.yml` manualmente em branch isolada → verificar que `Authenticate to GCP via OIDC (WIF)` step roda e os deploys legacy NÃO executam (verificado pela ausência de `::warning title=L11-09::`).
3. Provisionar WIF em prod GCP.
4. Atualizar `vars.GCP_*` no repo principal.
5. Após 30 dias sem incidentes, **deletar** secrets `PLAY_STORE_KEY_JSON` e `FIREBASE_TOKEN` do GitHub.
6. Remover steps `(legacy secrets — DEPRECATED)` do `release.yml`.

---

## 5. Supabase service role — Por que OIDC não é trivial

Supabase service role key é um **JWT estático assinado com o JWT secret do projeto**. Não há endpoint OIDC nativo para emitir tokens curtos.

### Defesa em profundidade adotada

1. **Usar projeto STAGING em CI** (jamais prod). `portal.yml` valida no step `Assert non-prod Supabase target` que a `NEXT_PUBLIC_SUPABASE_URL` não bate com hosts de produção (`omnirunner.app|prod|production`).
2. **Rotação 90 dias** do JWT secret do projeto staging (regenera service role key automaticamente).
3. **Rotação imediata** se houver suspeita de leak (qualquer log/screenshot exposto).
4. **RLS strict** mesmo em staging (não usar service role como proxy de "modo admin barato"). Edge functions usam policies anonymous + `auth.uid()`.
5. **Audit log** em prod: todo uso de service role passa por `auditLog()` (`portal/src/lib/audit.ts`), com `actor_id`, `actor_role='service_role'` e `metadata` rastreável.

### Migration path futura (out of scope desta correção)

Quando Supabase publicar OIDC token federation (RFC pendente em `github.com/supabase/supabase/discussions`), migrar:

```yaml
- uses: supabase/oidc-action@v1
  with:
    project-ref: ${{ vars.SUPABASE_PROJECT_REF }}
    role: service_role
    ttl: 3600
```

Tracking issue: criar quando feature for anunciada.

---

## 6. Mapa completo de secrets/vars usados em CI

### Secrets confidenciais (GitHub → Settings → Secrets)

| Secret | Workflow | Uso | Rotação | Migration alvo |
|---|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | portal.yml, update-snapshots.yml | URL projeto staging | 90d | manter (não-secret real) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | portal.yml, update-snapshots.yml | Anon JWT staging | 90d | manter (RLS protege) |
| `SUPABASE_SERVICE_ROLE_KEY` | portal.yml, update-snapshots.yml | Service role JWT staging | **90d obrigatório** | OIDC quando disponível |
| `PLAY_STORE_KEY_JSON` | release.yml | Service account JSON GCP | Imediata se WIF ativo | **deprecated** → WIF |
| `FIREBASE_TOKEN` | release.yml | Token longo Firebase | Imediata se WIF ativo | **deprecated** → WIF |
| `FIREBASE_APP_ID` | release.yml | ID público (era secret por engano) | — | mover para `vars.*` |

### Variáveis públicas (GitHub → Settings → Variables)

| Variable | Workflow | Uso |
|---|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | release.yml | URI do provider WIF |
| `GCP_SERVICE_ACCOUNT` | release.yml | SA email para impersonar |
| `GCP_WORKLOAD_IDENTITY_AUDIENCE` | release.yml | Audience claim do JWT |
| `FIREBASE_APP_ID` | release.yml | ID público Firebase |

### Tokens automáticos GitHub

| Token | Origem | Uso |
|---|---|---|
| `GITHUB_TOKEN` | Auto-emitido por job, TTL = job lifetime | Checkout, upload artifacts, gitleaks-action, etc. Permissions limitadas pelo bloco `permissions:`. |

---

## 7. Política de rotação

| Tipo | Cadência | Trigger imediato |
|---|---|---|
| `GITHUB_TOKEN` | Auto (cada job) | — |
| OIDC tokens (WIF) | Auto (1h TTL) | — |
| `SUPABASE_SERVICE_ROLE_KEY` | 90 dias | Leak suspeito, ex-funcionário com acesso, suspeita de comprometimento de host CI |
| `PLAY_STORE_KEY_JSON` (legacy) | 90 dias até cutover, depois revogar | Idem |
| `FIREBASE_TOKEN` (legacy) | 90 dias até cutover, depois revogar | Idem |

### Procedimento de rotação (Supabase staging)

1. Supabase Dashboard → Project Settings → API → **Reset JWT Secret**.
2. Copiar novo `service_role` key.
3. GitHub → Settings → Secrets → Atualizar `SUPABASE_SERVICE_ROLE_KEY`.
4. Atualizar Vercel env var (se mesmo projeto).
5. Disparar workflow `Portal CI` manualmente para validar.
6. Postar no canal `#sec-rotations` com timestamp + executor.

### Procedimento de rotação (qualquer secret leakado)

1. **Imediato**: revogar o secret no provedor (Supabase/Firebase/etc).
2. **Imediato**: girar o GitHub Secret com novo valor.
3. Auditar últimos 90 dias de runs do workflow afetado: `gh run list --workflow=<file> --created='<data>..'`.
4. Postmortem mandatório (template em `docs/postmortems/TEMPLATE.md`).

---

## 8. Anti-patterns a evitar

| ❌ Não fazer | ✅ Fazer |
|---|---|
| `permissions: write-all` | Declarar permissões mínimas explícitas |
| Usar `secrets.SUPABASE_SERVICE_ROLE_KEY` em workflow `pull_request:` de fork | Usar `pull_request_target:` apenas com revisão obrigatória + nunca em PRs externas |
| Logar secrets em `echo $X` | Sempre `::add-mask::` se precisar interpolar; idealmente nunca |
| Reutilizar service account GCP entre workflows | Um SA por finalidade (deploy, scan, build) |
| Hardcodar valores "OK em CI" como `eyJhbGciOi...` em workflow | Aceitável APENAS para Supabase local (`supabase start`), nunca para produtos remotos |
| `secrets.GITHUB_TOKEN` (redundante; é auto) | `${{ secrets.GITHUB_TOKEN }}` quando precisa, mas sem permissions extras |

---

## 9. Auditoria periódica (trimestral)

Checklist a executar a cada quarter:

- [ ] `gh secret list` no repo + comparar com tabela §6 (deletar secrets órfãos)
- [ ] `gh variable list` idem
- [ ] Validar que cada workflow tem bloco `permissions:` (busca: `rg -L "^permissions:" .github/workflows/`)
- [ ] Verificar último uso de cada secret (audit log do GitHub)
- [ ] Confirmar rotações dentro do prazo (planilha `#sec-rotations`)
- [ ] Confirmar que step "Assert non-prod Supabase target" continua bloqueando hosts prod
- [ ] Re-rodar postmortem de leaks recentes (se houver) e confirmar action items fechados

---

## 10. Referências

- [GitHub Docs: OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [GitHub Docs: Permissions for GITHUB_TOKEN](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#permissions-for-the-github_token)
- [Google: Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [google-github-actions/auth](https://github.com/google-github-actions/auth)
- [BACEN res. 4.893/21 (resiliência cibernética)](https://www.bcb.gov.br/estabilidadefinanceira/exibenormativo?tipo=Resolu%C3%A7%C3%A3o%20BCB&numero=85)
- [LGPD Art. 46 (medidas técnicas de segurança)](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)
- [ADR-007 — Modelo de Custódia](../adr/007-custody-clearing-model.md) (contexto: secrets de pagamento)
- [L01-17 finding](../audit/findings/L01-17-asaas-api-key-armazenada-em-texto-puro.md) (precedente de migração para vault)
