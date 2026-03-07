# POST_REFACTOR_LOCAL_DB.md — Auditoria de Dados Locais

> Data: 2026-03-07

---

## 1. ESTADO ATUAL DA PERSISTÊNCIA LOCAL

| Componente | Backend | Status |
|---|---|---|
| Sessões de corrida | Isar (IsarSessionRepo) | ✅ Funcional |
| Pontos GPS | Isar (IsarPointsRepo) | ✅ Funcional |
| Desafios | Isar (IsarChallengeRepo) | ✅ Funcional |
| Carteira | Isar (IsarWalletRepo) | ✅ Funcional |
| Ledger | Isar (IsarLedgerRepo) | ✅ Funcional |
| Progressão | Isar (IsarProfileProgressRepo) | ✅ Funcional |
| XP | Isar (IsarXpTransactionRepo) | ✅ Funcional |
| Badges | Isar (IsarBadgeAwardRepo) | ✅ Funcional |
| Missões | Isar (IsarMissionProgressRepo) | ✅ Funcional |
| Coaching groups/members/invites | Isar (3 repos) | ✅ Funcional |
| Coaching rankings | Isar (IsarCoachingRankingRepo) | ✅ Funcional |
| Analytics (baselines/trends/insights) | Isar (3 repos) | ✅ Funcional |
| Offline queue | SharedPreferences | ✅ Funcional |
| Cache metadata | SharedPreferences | ✅ Funcional |
| Membership cache | In-memory | ✅ Funcional (5min TTL) |
| Theme preference | SharedPreferences | ✅ Funcional |
| Onboarding tooltips | SharedPreferences | ✅ Funcional |
| **Drift (AppDatabase)** | **SQLite** | **❌ NÃO ATIVO** |

---

## 2. VERIFICAÇÕES DE CENÁRIO

| Cenário | Resultado | Notas |
|---|---|---|
| App abre sem internet | ✅ Funciona | Demo mode + dados Isar locais |
| App reabre após fechar | ✅ Dados persistem | Isar em disco |
| Banco com dados existentes | ✅ Leitura normal | IsarDatabaseProvider.open() idempotente |
| Banco vazio (primeira abertura) | ✅ Schema criado | Isar.open() cria automaticamente |
| Banco parcialmente migrado (Isar→Drift) | ⚠️ NÃO TESTÁVEL | Migrator nunca executado |
| Dados duplicados | ✅ Protegido | unique() constraints em Isar models |
| Tabela vazia | ✅ Funciona | Repos retornam lista vazia |
| Nulls inesperados | ⚠️ Parcial | Nullable fields existem; nem todos repos guardam null |

---

## 3. PROBLEMAS IDENTIFICADOS

| # | Problema | Severidade |
|---|---|---|
| 1 | Drift AppDatabase nunca inicializado — .g.dart ausente | CRÍTICO (código morto) |
| 2 | IsarToDriftMigrator nunca wired no bootstrap | CRÍTICO (código morto) |
| 3 | Isar não encriptado (key gerada mas não usada) | ALTO |
| 4 | ChallengeRecord sem acceptDeadlineMs — campo perdido em cache | MÉDIO |
| 5 | Enum persistence via .index — frágil a reordenação | MÉDIO |

---

## 4. INTEGRIDADE DO SCHEMA LOCAL

| Model | Campos | Indices | Unique constraints | Status |
|---|---|---|---|---|
| LocationPointRecord | 8 | sessionId+timestampMs composite | — | OK |
| WorkoutSessionRecord | 15 | userId, status | sessionUuid | OK |
| ChallengeRecord | 15+ | creatorUserId | challengeId | OK (falta acceptDeadlineMs) |
| ChallengeResultRecord | 5 | — | challengeId | OK |
| WalletRecord | 6 | — | userId | OK |
| LedgerRecord | 6 | userId+createdAtMs | — | OK |
| ProfileProgressRecord | 12 | — | userId | OK |
| XpTransactionRecord | 7 | userId+createdAtMs | — | OK |
| BadgeAwardRecord | 7 | userId+badgeKey | — | OK |
| MissionProgressRecord | 7+ | userId+missionKey | — | OK |
| SeasonRecord / SeasonProgressRecord | 6+5 | — | seasonKey / userId+seasonKey | OK |
| CoachingGroup/Member/Invite | 6+7+6 | groupId / userId | — | OK |
| CoachingRanking/Entry | 8+7 | groupId / rankingId | — | OK |
| AthleteBaseline/Trend/CoachInsight | 10+8+8 | athleteUserId | — | OK |
| Friendship/Group/GroupMember/GroupGoal | 5+5+4+5 | userId / groupId | — | OK |
| Event/EventParticipation | 7+5 | groupId / eventId | — | OK |
| LeaderboardSnapshot/Entry | 6+6 | — / snapshotId | — | OK |
