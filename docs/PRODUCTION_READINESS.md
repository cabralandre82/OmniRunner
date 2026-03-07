# Prontidão para Produção — Omni Runner

Este documento consolida o checklist de prontidão para produção, passos de deploy, verificação pós-deploy, procedimentos de rollback, monitoramento e diretrizes de escalabilidade do projeto Omni Runner.

---

## 1. Checklist Pré-Deploy

### 1.1 Banco de Dados (Supabase)

- [ ] **Migrações aplicadas** — Todas as migrations em `supabase/migrations/` foram aplicadas em staging e validadas
- [ ] **Backup verificado** — Backup recente confirmado no Supabase Dashboard (Database → Backups)
- [ ] **Connection pooling configurado** — Supavisor em modo transação; Portal usa URL do pooler (porta 6543); Edge Functions usam URL direta (porta 5432)

### 1.2 Portal (Next.js)

- [ ] **Build passa** — `npm run build` no diretório `portal/` conclui sem erros
- [ ] **Variáveis de ambiente definidas:**
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `UPSTASH_REDIS_REST_URL`
  - `UPSTASH_REDIS_REST_TOKEN`
  - `SENTRY_DSN` (opcional, para monitoramento de erros)

### 1.3 Flutter (App móvel)

- [ ] **APK/AAB assinado** — Keystore configurado; assinatura release válida
- [ ] **Versão incrementada** — `version` e `build-number` atualizados em `pubspec.yaml` (ou via `bundle exec fastlane bump_version`)
- [ ] **Sentry configurado** — `sentry_flutter` inicializado em `main.dart` com DSN de produção

### 1.4 Edge Functions (Supabase)

- [ ] **Deploy realizado** — Todas as funções críticas deployadas
- [ ] **Health endpoints respondendo** — Cada função expõe `GET /health` e retorna 200

---

## 2. Passos de Deploy

### 2.1 Migrações Supabase

```bash
npx supabase db push
```

> Execute em staging primeiro. Confirme que não há migrações pendentes com `npx supabase migration list`.

### 2.2 Portal

O deploy do Portal é acionado automaticamente pelo CI ao fazer `git push` na branch `master` (quando há alterações em `portal/`). Para deploy manual:

- **Vercel:** Conecte o repositório; push para `master` dispara o deploy
- **Self-hosted:** `npm run build && pm2 restart portal` (ou equivalente)

### 2.3 Flutter (App)

**Google Play (internal track):**
```bash
cd omni_runner
bundle exec fastlane deploy_play_store
```

**Firebase App Distribution (beta):**
```bash
cd omni_runner
FIREBASE_APP_ID=<seu_app_id> bundle exec fastlane deploy_firebase_distribution
```

> Requer `FIREBASE_APP_ID` e credenciais do Firebase CLI configuradas.

### 2.4 Edge Functions

```bash
npx supabase functions deploy --project-ref <REF>
```

Para deploy de uma função específica:
```bash
npx supabase functions deploy <nome-da-funcao> --project-ref <REF>
```

---

## 3. Verificação Pós-Deploy

### 3.1 Health Endpoints

| Endpoint | Descrição |
|----------|-----------|
| `GET /api/health` | Health completo: DB + invariantes de custódia |
| `GET /api/liveness` | Liveness simples: apenas conectividade ao DB |

**Verificação manual:**
```bash
curl -s https://<portal-url>/api/health | jq
curl -s https://<portal-url>/api/liveness | jq
```

Resposta esperada de `/api/health`:
- `status: "ok"` — Sistema saudável
- `status: "degraded"` — DB ok, mas invariantes violados
- `status: "down"` — DB inacessível

### 3.2 Smoke Tests (k6)

```bash
cd tools/load-tests
k6 run -e SMOKE=true -e BASE_URL=https://<portal-url> scenarios/api-health.js
```

O CI já executa este smoke test após o build do Portal.

### 3.3 Invariantes de Custódia

A função `check_custody_invariants()` deve retornar **0 violações** em produção:

```sql
SELECT * FROM check_custody_invariants();
-- Resultado esperado: 0 linhas
```

Ou via API do Portal: `GET /api/platform/invariants` (requer autenticação de staff).

### 3.4 Sentry

- Aguardar **~10 minutos** após o deploy
- Verificar no Sentry: **nenhum erro novo** em produção

---

## 4. Procedimento de Rollback

### 4.1 Portal

- **Vercel:** Dashboard → Deployments → build estável anterior → "..." → Promote to Production
- **Self-hosted:** `git checkout <commit-anterior> && npm run build && pm2 restart portal`

### 4.2 Banco de Dados

Supabase não suporta rollback automático de migrations. Procedimento manual:

1. Identificar a migration problemática:
   ```sql
   SELECT * FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 5;
   ```

2. Reverter manualmente o DDL (criar SQL inverso da migration)

3. Marcar como revertida:
   ```bash
   npx supabase migration repair --status reverted <migration_id>
   ```
   Ou manualmente:
   ```sql
   DELETE FROM supabase_migrations.schema_migrations WHERE version = '<migration_id>';
   ```

> **Referência completa:** [docs/ROLLBACK_RUNBOOK.md](./ROLLBACK_RUNBOOK.md)

### 4.3 Flutter

**Não é possível fazer rollback de builds publicadas** no Google Play ou Firebase. Em caso de bug crítico:

1. Corrigir o código
2. Incrementar versão
3. Deploy de hotfix via `deploy_play_store` ou `deploy_firebase_distribution`

### 4.4 Edge Functions

```bash
git checkout <commit-anterior> -- supabase/functions/<nome-da-funcao>/
npx supabase functions deploy <nome-da-funcao> --project-ref <REF>
```

Ou desabilitar temporariamente via Supabase Dashboard → Edge Functions → Settings → Disable.

---

## 5. Monitoramento e Alertas

### 5.1 Sentry

- **Erros:** Captura automática de exceções no Portal e no app Flutter
- **Performance:** Transações e breadcrumbs para diagnóstico

### 5.2 Health Endpoint

- **Frequência sugerida:** A cada 5 minutos
- **Alertas:** Falha consecutiva (ex.: 3 checks em 503) → notificar on-call

### 5.3 Invariantes de Custódia

- **Violações → alerta imediato** — Qualquer resultado não vazio de `check_custody_invariants()` indica inconsistência crítica
- Integrar verificação em cron ou no pipeline de health check

### 5.4 k6 Smoke Test no CI

O workflow `portal.yml` executa o smoke test após o build. Falha impede promoção para produção.

---

## 6. Connection Pooling (Configuração de Produção)

### 6.1 Supavisor (Supabase)

- **Modo:** Transaction mode (recomendado para serverless)
- **Plano Pro:** até 200 conexões no pooler
- **Plano Team:** 300+ conexões (para 10k+ assessorias)

### 6.2 Uso por Componente

| Componente | URL | Porta |
|------------|-----|-------|
| Portal (Next.js) | Pooler (Supavisor) | 6543 |
| Edge Functions | Direta | 5432 |

> O Portal deve usar a connection string com `?pgbouncer=true` ou a URL específica do pooler para evitar esgotamento de conexões.

### 6.3 Escala

- **&lt;1K assessorias:** Free/Pro suficiente
- **1K–5K:** Pro, habilitar Redis caching, arquivar dados antigos
- **5K–10K:** Team, particionar tabelas grandes, CDN para o Portal
- **10K+:** Enterprise, read replicas, pooler dedicado

---

## 7. Backup e Recuperação

### 7.1 PITR (Point-in-Time Recovery)

- **Disponível em:** Plano Pro e superiores
- **Janela:** 7 dias
- **RPO:** minutos
- **RTO:** 1–2 horas (estimado)

### 7.2 Restauração

1. Supabase Dashboard → Project → Database → Backups
2. Aba **Point in Time**
3. Selecionar timestamp alvo (antes do incidente)
4. Clicar em **Restore** — cria novo projeto com o estado restaurado
5. Validar integridade dos dados e trocar DNS/connection strings

---

## 8. Diretrizes de Escalabilidade

| Escala (assessorias) | Plano | Ações |
|----------------------|-------|-------|
| &lt;1K | Free/Pro | Configuração padrão |
| 1K–5K | Pro | Redis caching, arquivamento de dados antigos |
| 5K–10K | Team | Particionamento de tabelas grandes, CDN para Portal |
| 10K+ | Enterprise | Read replicas, pooler dedicado, revisão de arquitetura |

---

## Resumo Rápido

| Etapa | Comando / Ação |
|-------|----------------|
| Migrações | `npx supabase db push` |
| Portal | `git push` → CI deploy (Vercel) |
| Flutter (Play) | `bundle exec fastlane deploy_play_store` |
| Flutter (Beta) | `bundle exec fastlane deploy_firebase_distribution` |
| Edge Functions | `npx supabase functions deploy` |
| Health check | `curl /api/health` e `curl /api/liveness` |
| Invariantes | `SELECT * FROM check_custody_invariants()` → 0 linhas |
| Rollback Portal | Vercel: Promote deployment anterior |
| Rollback DB | Ver [ROLLBACK_RUNBOOK.md](./ROLLBACK_RUNBOOK.md) |
