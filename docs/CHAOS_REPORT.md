# CHAOS REPORT — Relatório Consolidado de Chaos Testing

**Data:** 2026-03-04  
**Autor:** Principal QA Engineer — Chaos Testing  
**Repositório:** `/home/usuario/project-running`  
**Escopo:** Monorepo completo (Flutter App + Next.js Portal + Supabase Backend)

---

## Resumo Executivo

Auditoria de Chaos Testing cobrindo 7 dimensões: dados, rede, banco, permissões, fluxo, performance e arquitetura. Foram analisados **100 screens Flutter**, **53 pages Portal**, **57 edge functions**, **79 migrations SQL** e todas as integrações externas.

| Severidade | Quantidade |
|------------|------------|
| **CRITICAL** | 5 |
| **MAJOR** | 26 |
| **MINOR** | 18 |
| **Total** | **49** |

**Score de Resiliência: 72/100**

---

## Documentos Gerados

| Documento | Conteúdo |
|-----------|----------|
| `CHAOS_ARCHITECTURE_MAP.md` | Mapa completo de componentes, fluxos de dados, limites de auth |
| `CHAOS_DATA.md` | Vulnerabilidades a null, listas vazias, overflow, JSON malformado |
| `CHAOS_NETWORK.md` | Timeouts, retry, loading states, offline, deduplicação |
| `CHAOS_DATABASE.md` | Concorrência, idempotência, race conditions, transações |
| `CHAOS_RLS.md` | Permissões, isolamento cross-tenant, escalação de privilégios |
| `CHAOS_FLOW.md` | Ações fora de ordem, double-click, state machine violations |
| `CHAOS_PERFORMANCE.md` | N+1 queries, queries unbounded, payloads, indexes |

---

## Lista Completa de Problemas

### CRITICAL (5)

| ID | Problema | Fase | Como Reproduzir | Impacto | Correção |
|----|----------|------|-----------------|---------|----------|
| C1 | **Refund não reverte créditos** — webhook `refunded` do MP apenas loga evento, não reverte `billing_purchases.status` nem clawback de créditos | Fluxo | Processar pagamento → fulfillment → chargeback/refund via MP | Assessoria mantém tokens apesar do dinheiro devolvido; inconsistência financeira | Implementar handler de refund que reverta status e debite créditos |
| C2 | **trainingpeaks-sync push: 100+ operações sequenciais** — loop de 50 syncs com 2 awaits cada (DB update + TP API call) | Performance | Chamar `trainingpeaks-sync` com action=push e 50 pendências | Timeout da edge function (60s); syncs parciais | Paralelizar com `Promise.all` com cap de concorrência (ex: 5) |
| C3 | **custody coin_ledger sem LIMIT** — Portal carrega ledger inteiro do grupo sem paginação | Performance | Abrir `/custody` em grupo com 10.000+ transações | Resposta enorme; page load lento ou timeout | Adicionar `.limit()` ou aggregate RPC |
| C4 | **`remote_token_intent_repo.dart` — `res.data` sem null check** — cast direto `as Map<String,dynamic>` em resposta de edge function | Dados | Invocar criação de token intent quando edge function retorna erro | Crash do app (NullPointerException) | Adicionar null check e fallback |
| C5 | **`login_screen.dart` — `result.failure!` em fluxo de login** — bang operator em resultado que pode ser null | Dados | Tentativa de login com falha de rede em momento específico | Crash na tela de login | Usar `result.failure ?? 'Erro desconhecido'` |

### MAJOR (26)

| ID | Problema | Fase | Impacto |
|----|----------|------|---------|
| M1 | `today_screen.dart` — `lastRun.route.first` com route vazio | Dados | RangeError crash |
| M2 | `remote_profile_datasource.dart` — `rows.first` sem isEmpty check | Dados | Crash se perfil não existe |
| M3 | `run_details_screen.dart` / `run_replay_screen.dart` — `_coords.first` sem guard | Dados | Crash com sessão sem coordenadas |
| M4 | `staff_generate_qr_screen.dart` — `_capacity!` sem verificação | Dados | Crash se capacity não carregado |
| M5 | `athlete_evolution_screen.dart` — `selectedTrend!` / `selectedBaseline!` | Dados | Crash com seleção inválida |
| M6 | `event_details_screen.dart` / `race_event_details_screen.dart` — bang operators em participação | Dados | Crash em evento sem participação |
| M7 | 7 edge functions sem try/catch em `req.json()` | Dados | 500 Internal Error com JSON malformado |
| M8 | BLE `firstWhere` sem fallback em services/characteristics | Dados | StateError crash em BLE |
| M9 | Múltiplos `rows.first` / `list.first` sem isEmpty check (auth_gate, join_assessoria, setup) | Dados | Crash sem dados |
| M10 | Edge functions sem timeout em `fetch` (MP, Strava, TP) | Rede | Hang até limite da EF (60s) |
| M11 | Flutter Supabase sem timeout global | Rede | Loading indefinido em rede lenta |
| M12 | Portal Supabase sem timeout | Rede | Páginas travadas |
| M13 | Maioria dos repos sem retry | Rede | Falha transitória = erro imediato |
| M14 | MercadoPago L1 dedup ineficaz — sem UNIQUE em `mp_payment_id` | Banco | billing_events duplicados |
| M15 | `fn_create_delivery_batch` sem idempotência | Banco | Batches duplicados |
| M16 | `fn_assign_workout` weekly limit TOCTOU | Banco | Pode exceder limite semanal |
| M17 | Participant withdraws during challenge settlement | Fluxo | Coins para usuário que desistiu |
| M18 | 7 screens com botões sem guard de loading (double-click) | Fluxo | Ações duplicadas |
| M19 | `profile_screen` / `more_screen` — sign-out sem loading guard | Fluxo | Double sign-out / delete-account |
| M20 | Two staff editing same workout template — no optimistic locking | Fluxo | Last-write-wins; perda de dados |
| M21 | Support ticket form pode ser submetido 2x | Fluxo | Tickets duplicados |
| M22 | Portal support page N+1 — 2 queries por ticket em loop | Performance | 200+ queries extras com 100 tickets |
| M23 | `countPublishedItems` — `select('id')` + `.length` ao invés de count | Performance | Fetch desnecessário de todos IDs |
| M24 | Portal support_tickets / clearing unbounded | Performance | Respostas enormes |
| M25 | Staff disputes clearing_cases unbounded | Performance | Mesmo |
| M26 | Missing indexes em `coin_ledger.issuer_group_id`, `billing_purchases.payment_reference` | Performance | Scans sequenciais |

### MINOR (18)

| ID | Problema | Fase |
|----|----------|------|
| m1 | `profile_screen` / `athlete_dashboard` — `name[0]` com string vazia | Dados |
| m2 | `cached_avatar.dart` — `parts.first[0]` com nome de 1 parte | Dados |
| m3 | `deep_link_handler.dart` — `pathSegments[0]` sem check | Dados |
| m4 | `partner_assessorias_screen` / `friends_activity_feed` — `[0]` em string vazia | Dados |
| m5 | `int.parse` sem try/catch em 5 screens | Dados |
| m6 | `DateTime.parse` sem try/catch em casts de DB rows | Dados |
| m7 | Display names longos podem quebrar layout | Dados |
| m8 | Portal actions sem client-side debounce | Rede |
| m9 | Loading states não canceláveis em navegação | Rede |
| m10 | Offline queue só usada para `fn_import_execution` | Rede |
| m11 | `fn_athlete_confirm_item` pode criar orphan event se chamado para item pending | Fluxo |
| m12 | Delivery batch pode ser fechado com items pending | Fluxo |
| m13 | Feature flag desativada durante uso — sync parcial | Fluxo |
| m14 | Coach removes member mid-action — ação completa | Fluxo |
| m15 | `workout_delivery_service` listPublishedItems sem limit | Performance |
| m16 | Avatars sem thumbnail/resize | Performance |
| m17 | `settle-challenge` N RPCs paralelos (não N+1, mas N concurrent) | Performance |
| m18 | `trainingpeaks-sync` pull: nested loop com RPC por workout | Performance |

---

## Pontos Fortes Identificados

| Área | Detalhe |
|------|---------|
| **Idempotência em webhooks** | Stripe: triple-layer (event dedup + conditional UPDATE + FOR UPDATE). MP: L2/L3 protegem contra double-fulfillment. Strava: duplicate check antes de insert. |
| **RLS abrangente** | 75+ tabelas com RLS. Isolamento por `group_id` e `auth.uid()` consistente. Nenhuma tabela sem RLS encontrada. |
| **RPCs com state machine** | `fn_fulfill_purchase`, `fn_athlete_confirm_item`, `fn_mark_item_published` — transições de estado seguras com WHERE condicional. |
| **Auth em edge functions** | Todas as 40+ EFs user-facing usam `requireUser()`. Webhooks e crons usam service-key ou signature. |
| **group_id validation** | Todos os RPCs e EFs que aceitam `group_id` validam membership. Tampering retorna 403. |
| **Loading states** | 70+ screens com `CircularProgressIndicator` ou estado de loading. |
| **Retry em fluxos críticos** | Wearables, challenges, auth, Strava, Watch bridge — com retry e backoff. |
| **FOR UPDATE locks** | `fn_fulfill_purchase`, `reconcile_wallet`, `fn_approve/reject_join_request`, `fn_try_match` — serialização correta. |

---

## Matriz de Risco

```
           IMPACTO
           Baixo        Médio         Alto
  Alta  │ m8,m9,m10  │ M11,M12,M13 │ C2,C3     │
L       │            │             │           │
I  Média│ m1-m7      │ M14-M16,    │ C1,C4,C5  │
K       │            │ M22-M26     │           │
E  Baixa│ m11-m18    │ M17-M21     │           │
L       │            │             │           │
I       │            │             │           │
H       │            │             │           │
O       │            │             │           │
O       │            │             │           │
D       │            │             │           │
```

---

## Plano de Correção Recomendado

### Sprint 1 — CRITICAL (1-2 dias)

| # | Ação | Esforço |
|---|------|---------|
| 1 | Implementar handler de refund com reversão de status e clawback de créditos (C1) | Alto |
| 2 | Paralelizar `trainingpeaks-sync` push com `Promise.all` cap=5 (C2) | Médio |
| 3 | Adicionar `.limit(500)` em `coin_ledger` query + aggregate RPC (C3) | Baixo |
| 4 | Null check em `remote_token_intent_repo.dart` (C4) | Baixo |
| 5 | Null-safe `result.failure` em `login_screen.dart` (C5) | Baixo |

### Sprint 2 — MAJOR Data + Network (2-3 dias)

| # | Ação | Esforço |
|---|------|---------|
| 6 | Adicionar guards de isEmpty antes de `.first` em 10+ locations (M1-M3,M9) | Médio |
| 7 | try/catch em `req.json()` nas 7 edge functions (M7) | Baixo |
| 8 | `AbortSignal.timeout(30_000)` em todos os `fetch` das edge functions (M10) | Baixo |
| 9 | Timeout global no Supabase Flutter client (M11) | Baixo |
| 10 | `firstWhere` com `orElse` em BLE source (M8) | Baixo |

### Sprint 3 — MAJOR Banco + Fluxo (2-3 dias)

| # | Ação | Esforço |
|---|------|---------|
| 11 | UNIQUE constraint para MP em `billing_events` (M14) | Baixo |
| 12 | Idempotência em `fn_create_delivery_batch` (M15) | Baixo |
| 13 | Loading guards em 7 screens com double-click risk (M18-M21) | Médio |
| 14 | Optimistic locking em workout templates (M20) | Médio |
| 15 | Re-fetch participants antes de settlement (M17) | Baixo |

### Sprint 4 — MAJOR Performance + MINOR (3-5 dias)

| # | Ação | Esforço |
|---|------|---------|
| 16 | Fix N+1 na portal support page (M22) | Médio |
| 17 | `count: 'exact'` para `countPublishedItems` (M23) | Baixo |
| 18 | `.limit()` em queries unbounded (M24-M25) | Baixo |
| 19 | Indexes faltantes (M26) | Baixo |
| 20 | Fixes menores (m1-m18) | Médio |

---

## Conclusão

O sistema apresenta uma **base sólida** de segurança (RLS, auth, idempotência nos fluxos financeiros) mas tem vulnerabilidades significativas em:

1. **Resiliência a dados inesperados** — múltiplos pontos de crash por null/empty
2. **Resiliência a falhas de rede** — ausência de timeouts e retry na maioria dos componentes
3. **Consistência financeira** — refund não reverte créditos (CRITICAL)
4. **Performance** — queries unbounded e N+1 em produção

Os 5 itens CRITICAL devem ser corrigidos antes de qualquer release. Os 26 MAJOR devem ser endereçados nas próximas 2-3 sprints.

---

*Relatório gerado por Chaos Testing analysis. Nenhum arquivo foi modificado.*
