# POST_REFACTOR_PERFORMANCE.md

> Data: 2026-03-07

---

## 1. N+1 QUERIES IDENTIFICADAS

| Localização | Pattern | Impacto | Severidade |
|---|---|---|---|
| isar_coaching_ranking_repo.getByGroupId() | Loop com _hydrate() individual por ranking | Com 10 rankings = 11 queries | MÉDIO |
| challenges_bloc._syncFromBackend() | Loop getById + save/update individual | Com 20 desafios = 40+ queries | MÉDIO |
| isar_coach_insight_repo.saveAll() | Loop where().findFirst() + put() individual | Com 10 insights = 20 queries | BAIXO |

---

## 2. SYNC PERFORMANCE

| Aspecto | Status | Detalhes |
|---|---|---|
| Sessões sincronizadas sequencialmente | ⚠️ Não batchado | 3 network ops por sessão (Storage + upsert + verify) |
| AutoSyncManager cooldown | ✅ 30 segundos | Previne sync storms |
| Guard contra sync concurrent | ✅ _syncing flag | Apenas 1 sync por vez |
| Pontos GPS comprimidos | ✅ Protobuf | Eficiente para upload |

---

## 3. LISTENER / REBUILD SAFETY

| Componente | Listeners | Cleanup | Status |
|---|---|---|---|
| ScrollControllers (3 screens) | addListener | removeListener em dispose() | ✅ OK |
| ProfileNameNotifier | addListener | removeListener em dispose() | ✅ OK |
| AnimationController | addListener | controller disposed | ✅ OK |
| Deep link subscription | StreamSubscription | cancel() em dispose() | ✅ OK |
| Connectivity monitor | StreamSubscription | cancel() em dispose() | ✅ OK |

**Zero leaks identificados.**

---

## 4. INITSTATE PATTERNS

| Pattern | Contagem | Risco |
|---|---|---|
| initState → _load() async fire-and-forget | 60 screens | OK — pattern Flutter standard |
| mounted guard antes de setState | 60 screens | ✅ Todos verificam mounted |
| Await direto em initState | 0 | ✅ Nenhum |

---

## 5. COLD START ESTIMATIVA

| Etapa | Estimativa |
|---|---|
| Sentry init | ~200ms |
| Supabase init | ~500ms |
| Firebase init | ~300ms |
| setupServiceLocator (DI) | ~100ms |
| Isar.open (22 schemas) | ~200ms |
| Feature flags load | ~300ms (network) |
| Session recovery check | ~50ms |
| **Total estimado** | **~1.5-2s** |

---

## 6. INDEXAÇÃO LOCAL

| Tabela | Indices | Status |
|---|---|---|
| LocationPointRecord | sessionId + timestampMs (composite) | ✅ Adequado |
| WorkoutSessionRecord | userId, status | ✅ Adequado |
| ChallengeRecord | creatorUserId | ⚠️ Faltaria index por status para queries de filtro |
| LedgerRecord | userId + createdAtMs | ✅ Adequado |
| CoachingRankingRecord | groupId | ✅ Adequado |
| XpTransactionRecord | userId + createdAtMs | ✅ Adequado |

---

## 7. RECOMENDAÇÕES

1. **Batch hydrate** em CoachingRankingRepo — carregar entries em uma query com where().anyOf()
2. **Batch upsert** em SyncRepo — se múltiplas sessions pendentes, agrupar upserts Postgres
3. **Adicionar index** em ChallengeRecord.status para filtros frequentes
4. **Medir cold start real** em device de gama baixa (Android Go)
