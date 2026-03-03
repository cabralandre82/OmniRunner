# QA Pre-Release — Risk Register

**Data**: 2026-03-03
**Versão**: RC-1

---

## Registro de Riscos

| ID | Risco | Severidade | Probabilidade | Impacto | Mitigação | Owner | Prazo |
|----|-------|------------|---------------|---------|-----------|-------|-------|
| R-01 | TrainingPeaks API não testada com credenciais reais | MEDIUM | HIGH | MEDIUM | Testar em staging com conta sandbox TP; OAuth flow + sync validados apenas contra mocks | DevOps | Pré-prod |
| R-02 | Performance não validada com 10k+ grupos reais | MEDIUM | LOW | HIGH | Ferramentas prontas (perf_seed + benchmark), rodar em ambiente staging com dataset realista | DevOps | Pré-prod |
| R-03 | OAuth providers (Garmin, Apple HealthKit) precisam de credenciais reais | MEDIUM | MEDIUM | MEDIUM | Configurar credenciais em staging antes de prod; fluxos OAuth spec'd em WEARABLE_OAUTH_SPEC.md | DevOps | Pré-prod |
| R-04 | 4 integration tests falham por FK no seed de teste | LOW | — | — | Não são bugs reais; melhorar seed de teste com dados FK completos | QA | v2 |
| R-05 | Plano financeiro sem gateway de pagamento real integrado | LOW | MEDIUM | LOW | Sistema registra revenue/expense no ledger; gateway (Stripe/MercadoPago) é externo e atrás de interface limpa | Product | v2 |
| R-06 | Algumas portal pages sem route-specific loading.tsx | LOW | LOW | LOW | Fallback para parent layout loading; adicionar loading.tsx específicos para UX mais polida | Frontend | v2 |
| R-07 | Push notifications não implementadas | LOW | — | MEDIUM | Documentado como Phase 2; FCM integration planejada | Product | v2 |
| R-08 | Prescribed vs Realized comparison não no UI | LOW | — | LOW | Dados disponíveis no DB; UI é Phase 2 deliverable | Product | v2 |

---

## Risk Matrix

```
              │  Low Impact    │  Medium Impact     │  High Impact
──────────────┼────────────────┼────────────────────┼──────────────
Certain       │                │                    │
High          │                │  R-01              │
Medium        │  R-05, R-06    │  R-03              │
Low           │  R-04, R-08    │  R-07              │  R-02
```

---

## Detalhes de Mitigação

### R-01 — TrainingPeaks API não testada com credenciais reais

A integração TrainingPeaks foi implementada com base na documentação oficial da API (OAuth 2.0 + REST endpoints para workouts/activities). O código está completo e coberto por testes unitários contra mocks, mas nenhum teste foi executado contra a API real do TrainingPeaks.

**Ações**:
1. Solicitar conta sandbox/developer do TrainingPeaks
2. Configurar `TP_CLIENT_ID`, `TP_CLIENT_SECRET`, `TP_REDIRECT_URI` em staging
3. Executar fluxo completo: OAuth → token exchange → sync workouts → import activities
4. Validar rate limits e error handling com respostas reais

**Risco residual**: Se a API real divergir dos mocks, poderá haver bugs de parsing. Impacto limitado ao feature de TP (não afeta core).

### R-02 — Performance não validada com 10k+ grupos

O sistema foi arquitetado para escala (set-based compute, pagination, indexes, batch processing em chunks de 100). Benchmark tools existem (`perf_seed` para gerar dados, script de benchmark para medir tempo). Porém, nenhum teste foi executado em ambiente com volume de produção.

**Ações**:
1. Executar `perf_seed` em staging com 10.000 grupos, 100k atletas
2. Rodar `compute-leaderboard` e medir tempo de execução
3. Verificar que stays < 60s (timeout edge function Supabase)
4. Se necessário, implementar partitioned processing ou background job

**Risco residual**: Baixa probabilidade dado o design set-based, mas impacto alto se ocorrer (timeout = leaderboard não atualizado).

### R-03 — OAuth providers precisam de credenciais reais

Garmin Connect e Apple HealthKit OAuth flows foram especificados em `WEARABLE_OAUTH_SPEC.md` mas dependem de credenciais de developer que precisam ser obtidas e configuradas.

**Ações**:
1. Registrar app no Garmin Developer Portal
2. Configurar Apple HealthKit entitlements no Xcode
3. Configurar variáveis de ambiente em staging
4. Testar fluxo completo OAuth → token → sync

**Risco residual**: Manual import (sem OAuth) funciona como fallback. OAuth é enhancement, não blocker.

### R-04 — 4 integration tests falham por FK no seed

Os 4 testes que falham tentam inserir dados sem criar as referências FK necessárias (ex: inserir `workout_assignment` sem `workout_template` existente). O DB corretamente rejeita com FK violation. O fix é melhorar o seed de teste.

**Ação**: Atualizar test fixtures para incluir dados FK completos. Prioridade baixa — não são bugs.

### R-05 — Gateway de pagamento real não integrado

O financial engine (clearing, distribute-coins, auto-topup, swap) opera com ledger interno (coins/credits). A integração com gateway real (Stripe, MercadoPago) está atrás de interfaces limpas (`create-checkout-session`, `webhook-payments`) mas depende de credenciais de produção.

**Ação**: Configurar Stripe test mode em staging; validar webhook flow. Sistema funciona sem gateway (ledger-only mode).

---

## Critérios de Aceite para GO

### Condições obrigatórias (pré-produção):
- [ ] R-01: TrainingPeaks testado em staging com credenciais reais
- [ ] R-02: Benchmark de performance executado com 10k+ grupos
- [ ] R-03: OAuth providers configurados em staging

### Riscos aceitos para v2:
- R-04: Test seed improvement (não bloqueia release)
- R-05: Gateway real (ledger funciona standalone)
- R-06: Route-specific loading.tsx (fallback funciona)
- R-07: Push notifications (Phase 2)
- R-08: Prescribed vs Realized UI (Phase 2)

### Status atual:
- **Nenhum P0 ou P1 bug aberto** — todos corrigidos
- **Nenhum risco HIGH/HIGH** na matrix
- **Ferramentas de mitigação prontas** para R-01, R-02, R-03
