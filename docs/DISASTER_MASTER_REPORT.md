# DISASTER MASTER REPORT — Simulação Catastrófica End-to-End

**Data:** 2026-03-04  
**Autor:** Principal SRE + Security Engineer + Principal QA  
**Repositório:** `/home/usuario/project-running`  
**Escopo:** Monorepo completo — App Mobile + Portal Web + Supabase Backend + Edge Functions + Integrações  
**Nível de Rigor:** 100/100  
**Código alterado:** NENHUM

---

## Resumo Executivo

Simulação catastrófica em 8 fases cobrindo: indisponibilidade total de DB, indisponibilidade de Edge Functions, intermitência de rede, concorrência extrema, tentativas de escape de tenant (RLS), envenenamento de dados, cenários de recovery/rollback, e UX sob degradação.

| Severidade | Quantidade |
|------------|------------|
| **P0 — CRITICAL** | **6** |
| **P1 — HIGH** | **14** |
| **P2 — MEDIUM** | **14** |
| **Total** | **34** |

### Score de Resiliência por Fase

| Fase | Score | Status |
|------|-------|--------|
| FASE 0 — Mapa de Dependências | ✅ | Completo |
| FASE 1 — DB Down | 45/100 | Portal crasha, webhooks perdem dados |
| FASE 2 — Edge Down | 65/100 | ~70% funciona, 30% bloqueado sem fallback |
| FASE 3 — Network Flapping | 60/100 | Server idempotente, client tem gaps |
| FASE 4 — Concorrência | 40/100 | 2 vulnerabilidades financeiras P0 |
| FASE 5 — RLS Escape | 50/100 | 1 escalação de privilégio P0 |
| FASE 6 — Data Poisoning | 55/100 | 1 DoS por payload, falta validação temporal |
| FASE 7 — Recovery/Rollback | 45/100 | Offline queue perde dados, zero rollback |
| FASE 8 — UX Degraded | 50/100 | Portal sem error boundary, telas sem retry |

**Score Global de Resiliência Catastrófica: 51/100**

---

## Documentos Gerados

| Documento | Conteúdo |
|-----------|----------|
| `DISASTER_DEPENDENCY_MAP.md` | Mapa completo de dependências, 16 fluxos críticos end-to-end |
| `DISASTER_DB_DOWN.md` | 15 achados — indisponibilidade total do banco |
| `DISASTER_EDGE_DOWN.md` | 18 achados — Edge Functions indisponíveis |
| `DISASTER_NETWORK_FLAP.md` | Idempotência client/server, late responses, dedup |
| `DISASTER_CONCURRENCY.md` | Race conditions: 2 VULNERABLE, 4 RISK |
| `DISASTER_RLS_ESCAPE.md` | Tenant isolation: 1 escalação P0, cross-tenant verificado |
| `DISASTER_DATA_POISONING.md` | Payloads malformados, validação temporal, DoS |
| `DISASTER_RECOVERY_ROLLBACK.md` | Recuperação pós-outage, idempotência de recompute, migrations |
| `DISASTER_UX_DEGRADED_MODE.md` | UX em modo degradado, error boundaries, data loss |

---

## Lista Completa de Problemas

### P0 — CRITICAL (6)

| ID | Fase | Problema | Como Reproduzir | Impacto | Correção Recomendada |
|----|------|----------|-----------------|---------|----------------------|
| **C1** | FASE 4 | **settle-challenge double ledger write** — `coin_ledger.insert()` em L532 + `fn_increment_wallets_batch` (que também insere ledger) = TODA liquidação cria entradas DUPLICADAS no ledger | Liquidar qualquer desafio e verificar `coin_ledger` — cada participante terá 2 entries idênticas | Corrupção financeira: saldos aparecem dobrados, reconciliação falha | Remover `coin_ledger.insert()` em `settle-challenge/index.ts` L532 — `fn_increment_wallets_batch` já faz o insert |
| **C2** | FASE 4 | **settle-challenge concurrent settlement race** — claim filter aceita `status IN ('active','completing')`, permitindo que `lifecycle-cron` e settle manual processem o MESMO desafio simultaneamente | Disparar `settle-challenge` manualmente enquanto `lifecycle-cron` está rodando | Double-credit de wallets (valores financeiros dobrados) | Mudar claim para `.eq("status", "active")` apenas — `completing` não deve ser re-claimed |
| **C3** | FASE 5 | **`profiles.platform_role` self-escalation** — qualquer usuário autenticado pode fazer `PATCH /profiles` e definir `platform_role = 'admin'`, ganhando acesso admin em toda a plataforma | `PATCH /rest/v1/profiles?id=eq.MY_ID` com body `{"platform_role": "admin"}` | Escalação de privilégio total — acesso a todos os grupos, todas as operações financeiras | Adicionar trigger ou RLS column restriction: `platform_role` não pode ser alterado pelo próprio usuário |
| **C4** | FASE 6 | **`workout_delivery_events.meta` sem limite de tamanho** — atletas podem inserir payloads JSONB arbitrariamente grandes via RLS INSERT | Atleta envia evento com `meta` de 100MB via PostgREST | DoS: storage abuse, OOM em queries, degradação de performance | Adicionar `CHECK (octet_length(meta::text) < 65536)` ou validar no RPC |
| **C5** | FASE 7 | **`OfflineQueue.drain()` remove items ANTES do replay** — se replay falha durante recovery, dados são PERMANENTEMENTE perdidos | 1) Desconectar rede, 2) Fazer ação que enfileira, 3) Reconectar, 4) Se RPC falha → item já foi removido da queue | Perda permanente de dados do usuário (sessões, confirmações) | Mover `remove()` para DEPOIS do replay bem-sucedido |
| **C6** | FASE 8 | **Portal sem NENHUM error boundary** — qualquer throw em Server Component crasha o shell inteiro | Qualquer query falhar no layout ou em uma page crashará toda a navegação do Portal | Portal 100% inacessível durante qualquer falha de DB | Criar `app/(portal)/error.tsx` e `app/global-error.tsx` |

### P1 — HIGH (14)

| ID | Fase | Problema | Impacto | Correção |
|----|------|----------|---------|----------|
| **H1** | FASE 1 | Portal layout sem try/catch — DB error crasha toda a shell | Portal inacessível | Wrap queries em try/catch com fallback |
| **H2** | FASE 1 | MercadoPago webhook: pagamento perdido se DB down >2 dias | Perda financeira | Dead-letter queue ou reconciliation cron |
| **H3** | FASE 1 | `requireUser()` retorna 401 ao invés de 503 quando DB inacessível | Erro misleading, client interpreta como auth inválida | Detectar `connection refused` e retornar 503 |
| **H4** | FASE 2 | Onboarding de novos usuários bloqueado quando EFs down (`set-user-role`, `complete-social-profile`) | Novos usuários não conseguem usar o app | Fallback para RPC direto |
| **H5** | FASE 3 | ~5-8 screens Flutter sem `_busy` guard em botões de ação | Ações duplicadas (double-tap) | Adicionar `_busy` guard |
| **H6** | FASE 4 | `increment_wallet_balance` INSERT sem ON CONFLICT — crash para primeiro op de novo user | Crash bloqueando criação de wallet | Adicionar `ON CONFLICT (user_id) DO UPDATE` |
| **H7** | FASE 4 | challenge-join 1v1 capacity check é read-then-act sem locking | >2 participantes em desafio 1v1 | Mover para PL/pgSQL com FOR UPDATE |
| **H8** | FASE 5 | `fn_sum_coin_ledger_by_group` sem validação de membership — qualquer authenticated user pode ler totais financeiros de qualquer grupo | Vazamento de dados financeiros | Adicionar check de membership no RPC |
| **H9** | FASE 5 | `settle-challenge` usa user-scoped client para wallet mutations que precisam de service_role | Créditos de wallet falham silenciosamente | Usar `adminDb` ao invés de `db` para wallet ops |
| **H10** | FASE 6 | `sessions.status` sem CHECK constraint — qualquer SMALLINT aceito | Status inválido quebra lógica de KPI, leaderboard, verificação | `ALTER TABLE sessions ADD CHECK (status BETWEEN 0 AND 5)` |
| **H11** | FASE 6 | `sessions.start_time_ms` user-controlled sem validação temporal | Atletas podem backdatar sessões para manipular leaderboards históricos | Validar: `start_time_ms >= now() - 7 days` no RPC/trigger |
| **H12** | FASE 7 | Flutter não reconecta automaticamente quando Supabase volta | Usuário precisa fechar/abrir app para reconectar | Implementar retry periódico |
| **H13** | FASE 7 | Zero migrations reversíveis, zero runbook de rollback | Impossível reverter deploy com bug | Criar runbook e testar reversibilidade |
| **H14** | FASE 8 | `today_screen` (dashboard principal) mostra tela branca em falha | Experiência de primeiro contato péssima | Adicionar error state com retry |

### P2 — MEDIUM (14)

| ID | Fase | Problema | Impacto | Correção |
|----|------|----------|---------|----------|
| **M1** | FASE 1 | WalletBloc tem Isar fallback mas não usa — mostra erro raw | UX degradada na tela financeira | Ativar fallback Isar |
| **M2** | FASE 1 | StaffDashboard mostra "no group found" em vez de erro de DB | Misleading para o staff | Diferenciar "not found" de "connection error" |
| **M3** | FASE 2 | Challenge auto-settle mostra "Calculating..." spinner permanente quando EF down | UX presa sem saída | Adicionar timeout + mensagem de erro |
| **M4** | FASE 4 | `idx_sessions_strava_activity` não é UNIQUE — gap teórico de dedup Strava | Possível sessão duplicada | Tornar UNIQUE em `(user_id, strava_activity_id)` |
| **M5** | FASE 4 | Delivery event INSERTs incondicionais (phantom audit entries) | Audit trail poluído | Guard com `IF FOUND` após UPDATE condicional |
| **M6** | FASE 5 | `support_tickets` RLS usa roles legacy (`professor`/`assistente`) | Staff locked out de tickets | Atualizar RLS para roles atuais |
| **M7** | FASE 5 | Error messages distinguem "not found" vs "forbidden" | Information leakage de existência de recursos | Unificar resposta para 404 |
| **M8** | FASE 6 | `workout_delivery_batches` permite `period_start > period_end` | Batches vazios silenciosos | Adicionar CHECK constraint |
| **M9** | FASE 6 | `workout_delivery_events.type` é TEXT sem constraint | Tipos arbitrários acumulam | Adicionar CHECK com lista de tipos válidos |
| **M10** | FASE 7 | `lifecycle-cron` processa apenas 50 challenges/run — backlog acumula | Desafios não liquidados por horas | Aumentar cap ou rodar mais frequente |
| **M11** | FASE 8 | `wallet_screen` erro sem botão retry | Usuário fica preso | Adicionar retry button |
| **M12** | FASE 8 | Support ticket message perdida quando criação falha | Perda de input do usuário | Preservar text em controller |
| **M13** | FASE 8 | Portal layout usa `Promise.all` — uma query falhando quebra todas as pages | Cascading failure no Portal | Usar `Promise.allSettled` com fallbacks |
| **M14** | FASE 6 | `coin_ledger.issuer_group_id` sem FK — referências órfãs possíveis | Dados inconsistentes | Adicionar FK ou validação |

---

## Matriz de Risco

```
              IMPACTO
              Baixo         Médio          Alto
  Alta    │ M4,M5        │ H5,H7,H12    │ C1,C2,C3    │
L         │              │               │             │
I  Média  │ M6,M7,M9    │ H1,H3,H4,    │ C4,C5,C6    │
K         │              │ H8,H10,H14   │             │
E  Baixa  │ M8,M10,M14  │ M1,M2,M3,    │ H2,H6,H9,  │
L         │              │ M11,M12,M13  │ H11,H13    │
I         │              │               │             │
H         │              │               │             │
```

---

## Análise por Dimensão

### Consistência Financeira

| Problema | Fase | Status |
|----------|------|--------|
| Double ledger write em settlement | FASE 4 | **VULNERÁVEL** — todo settlement duplica |
| Concurrent settlement double-credit | FASE 4 | **VULNERÁVEL** — race window aberto |
| Payment webhook loss (DB down) | FASE 1 | **RISCO** — sem dead-letter |
| settle-challenge usa client errado | FASE 5 | **RISCO** — wallet ops falham silenciosamente |
| Wallet INSERT race para novos users | FASE 4 | **RISCO** — crash na primeira operação |
| MercadoPago webhook dedup | FASE 3 | **SEGURO** — 3 camadas de idempotência |
| fn_fulfill_purchase | FASE 3 | **SEGURO** — FOR UPDATE + status check |
| Stripe webhook dedup | FASE 3 | **SEGURO** — event ID check |

### Isolamento de Tenant (Multi-tenant)

| Área | Status |
|------|--------|
| coaching_members cross-group | **SEGURO** — RLS `user_id = auth.uid()` |
| workout_delivery_items cross-athlete | **SEGURO** — RLS `athlete_user_id = auth.uid()` |
| sessions cross-user | **SEGURO** — RLS `user_id = auth.uid()` |
| wallets cross-user | **SEGURO** — RLS `user_id = auth.uid()` |
| coin_ledger cross-user | **SEGURO** — RLS `user_id = auth.uid()` |
| profiles.platform_role | **VULNERÁVEL** — self-escalation possível |
| fn_sum_coin_ledger_by_group | **RISCO** — sem membership check |

### Resiliência a Falhas

| Cenário | App | Portal | Edge |
|---------|-----|--------|------|
| DB Down | Parcial (Isar fallback em ~5 telas) | **CRASHA** (zero error handling) | 401 misleading |
| Edge Down | ~70% funciona (direct DB) | 100% funciona (zero EF deps) | N/A |
| Network Flap | OK (BLoC + mounted checks) | OK (SSR) | OK (timeouts) |
| Recovery | Precisa restart app | OK (RSC refetch) | OK (crons catch up) |

### Idempotência

| Operação | Status |
|----------|--------|
| fn_athlete_confirm_item | **SEGURO** — WHERE status = 'published' |
| fn_mark_item_published | **SEGURO** — WHERE status = 'pending' |
| fn_fulfill_purchase | **SEGURO** — FOR UPDATE + WHERE status = 'paid' |
| webhook-mercadopago | **SEGURO** — 3-layer dedup |
| settle-challenge | **VULNERÁVEL** — double ledger + double claim |
| compute-leaderboard rerun | **SEGURO** — UPSERT |
| reconcile-wallets rerun | **SEGURO** — idempotent diff |
| KPI daily rerun | **SEGURO** — ON CONFLICT DO UPDATE |

---

## Plano de Correção Priorizado

### Imediato (P0 — antes de qualquer release)

| # | ID | Ação | Esforço | Risco de não-ação |
|---|-----|------|---------|-------------------|
| 1 | C1 | Remover `coin_ledger.insert()` duplicado em `settle-challenge/index.ts` L532 | 5 min | Toda liquidação duplica dados financeiros |
| 2 | C2 | Mudar claim filter para `.eq("status", "active")` em `settle-challenge/index.ts` L152 | 5 min | Double-credit de wallets |
| 3 | C3 | Bloquear UPDATE de `platform_role` via trigger ou RLS column restriction em `profiles` | 30 min | Qualquer user vira admin da plataforma |
| 4 | C4 | Adicionar `CHECK (octet_length(meta::text) < 65536)` em `workout_delivery_events` | 10 min | DoS por payload gigante |
| 5 | C5 | Mover `remove()` para APÓS replay bem-sucedido no `OfflineQueue` | 15 min | Perda permanente de dados offline |
| 6 | C6 | Criar `app/(portal)/error.tsx` + `app/global-error.tsx` | 1h | Portal 100% inacessível em qualquer falha |

### Sprint 1 (P1 — próximas 1-2 semanas)

| # | ID | Ação | Esforço |
|---|-----|------|---------|
| 7 | H1 | Portal layout: wrap queries em try/catch | 2h |
| 8 | H2 | Dead-letter queue para webhooks de pagamento | 4h |
| 9 | H3 | `requireUser()`: diferenciar DB error de auth error | 1h |
| 10 | H6 | `increment_wallet_balance`: ON CONFLICT no INSERT | 15 min |
| 11 | H7 | challenge-join: mover capacity check para PL/pgSQL com FOR UPDATE | 2h |
| 12 | H8 | `fn_sum_coin_ledger_by_group`: adicionar membership check | 30 min |
| 13 | H9 | settle-challenge: usar `adminDb` para wallet ops | 15 min |
| 14 | H10 | `sessions.status`: CHECK constraint | 10 min |
| 15 | H11 | Session timestamp validation | 1h |
| 16 | H14 | TodayScreen: error state com retry | 1h |

### Sprint 2 (P2 — próximas 3-4 semanas)

| # | ID | Ação | Esforço |
|---|-----|------|---------|
| 17 | M1-M3 | Fallbacks de Isar, error messaging | 3h |
| 18 | M4 | Strava dedup index UNIQUE | 10 min |
| 19 | M5 | Guard IF FOUND em delivery events | 30 min |
| 20 | M6 | Support tickets RLS: roles atualizados | 15 min |
| 21 | M7 | Unificar error responses (404 genérico) | 2h |
| 22 | M8-M9 | CHECK constraints em delivery tables | 30 min |
| 23 | M11-M12 | Retry buttons + preservar input | 2h |
| 24 | M13 | Portal layout: `Promise.allSettled` | 1h |
| 25 | H4-H5,H12-H13 | EF fallbacks, busy guards, reconnection, rollback runbook | 8h |

---

## Pontos Fortes Identificados

| Área | Evidência |
|------|-----------|
| **Idempotência em billing** | `fn_fulfill_purchase` usa FOR UPDATE + WHERE status conditional. Webhook MP tem 3 camadas de dedup. Webhook Stripe tem event ID check. |
| **RLS abrangente** | 75+ tabelas com RLS ativo. Isolamento por `group_id` e `auth.uid()` consistente em todas as tabelas críticas. Zero cross-tenant leaks em queries diretas. |
| **Offline no Flutter** | TodayScreen tem fallback Supabase→Isar em cada sub-query. `ConnectivityMonitor` detecta mudanças de rede. |
| **Error handling global** | `runZonedGuarded` + Sentry + `ErrorWidget.builder` capturam crashes não-tratados no Flutter. |
| **Cron recovery** | Todos os crons (lifecycle, auto-topup, clearing) são stateless e catch up automaticamente após outage. |
| **Recompute safety** | `reconcile_all_wallets`, `compute-leaderboard`, KPI daily — todos usam UPSERT e são seguros para re-execução. |
| **Edge queue for Strava** | Novo sistema de queue com UNIQUE dedup index previne processamento duplicado. |

---

## Conclusão

O sistema tem **base sólida de segurança** (RLS, idempotência financeira, error handling global) mas tem **6 vulnerabilidades P0** que devem ser corrigidas antes de qualquer release:

1. **C1+C2**: Double ledger write + concurrent settlement = corrupção financeira ativa
2. **C3**: Self-escalation de `platform_role` = brecha de segurança crítica
3. **C4**: DoS via payload ilimitado em eventos de delivery
4. **C5**: OfflineQueue perde dados permanentemente em recovery
5. **C6**: Portal sem error boundary = indisponibilidade total em qualquer falha

Os 6 P0 requerem **~2 horas de engenharia** para corrigir. Os 14 P1 requerem **~12 horas**. Os 14 P2 requerem **~18 horas**.

**Tempo total estimado: ~32 horas de engenharia para resolver 100% dos achados.**

---

*Relatório gerado por simulação catastrófica end-to-end. Nenhum arquivo de código foi modificado. Todos os achados são baseados em análise estática do código-fonte com reprodução documentada.*
