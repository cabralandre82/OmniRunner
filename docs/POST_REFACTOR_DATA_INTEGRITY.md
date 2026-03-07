# POST_REFACTOR_DATA_INTEGRITY.md

> Data: 2026-03-07

---

## 1. MAPEAMENTO ENTITY ↔ ISAR MODEL

| Entity | Isar Model | Mapper | Status |
|---|---|---|---|
| LocationPointEntity | LocationPointRecord | Inline em IsarPointsRepo | ✅ Campos alinhados |
| WorkoutSessionEntity | WorkoutSessionRecord | Inline em IsarSessionRepo | ✅ Campos alinhados |
| ChallengeEntity | ChallengeRecord | Inline em IsarChallengeRepo | ⚠️ acceptDeadlineMs AUSENTE no model |
| ChallengeResultEntity | ChallengeResultRecord | Inline em IsarChallengeRepo | ✅ OK |
| WalletEntity | WalletRecord | Inline em IsarWalletRepo | ✅ 6/6 campos |
| LedgerEntryEntity | LedgerRecord | Inline em IsarLedgerRepo | ✅ OK |
| ProfileProgressEntity | ProfileProgressRecord | Inline em IsarProfileProgressRepo | ✅ 12/12 campos |
| XpTransactionEntity | XpTransactionRecord | Inline em IsarXpTransactionRepo | ✅ OK |
| BadgeAwardEntity | BadgeAwardRecord | Inline em IsarBadgeAwardRepo | ✅ 7/7 campos |
| MissionProgressEntity | MissionProgressRecord | Inline | ✅ OK |
| (+ 12 entities de coaching, social, events, leaderboards) | Respectivos Records | Inline | ✅ OK |

---

## 2. MAPPERS DEDICADOS vs INLINE

| Tipo | Contagem | Localização |
|---|---|---|
| Mappers dedicados (arquivos separados) | **2** | position_mapper.dart, permission_mapper.dart |
| Mappers inline (privados nos repos) | **17+** | _toRecord() / _toEntity() em cada repo |

**Risco:** Mappers inline não são testáveis isoladamente. Um bug de mapeamento só é descoberto via testes de integração do repo.

---

## 3. ENUM PERSISTENCE

Todos os repos usam `.index` (ordinal int) para persistir enums:

| Enum | Usado em | Risco |
|---|---|---|
| ChallengeType | ChallengeRecord.type | Reordenação quebra dados |
| ChallengeMetric | ChallengeRecord.metricOrdinal | Reordenação quebra dados |
| StartMode | ChallengeRecord.startModeOrdinal | Reordenação quebra dados |
| AntiCheatPolicy | ChallengeRecord.antiCheatPolicyOrdinal | Reordenação quebra dados |
| ParticipantStatus | ChallengeRecord (em participants JSON) | Serializado como string — OK |
| WorkoutStatus | WorkoutSessionRecord.status | Reordenação quebra dados |
| MissionType | MissionProgressRecord | Reordenação quebra dados |
| CoachingRole | CoachingMemberRecord | Reordenação quebra dados |
| InsightType | CoachInsightRecord | Reordenação quebra dados |

**Mitigação existente:** Comentários no código documentam os valores ordinais. Nenhuma validação em runtime.

---

## 4. NULL SAFETY

| Verificação | Resultado |
|---|---|---|
| Nullable fields declarados corretamente nos models? | ✅ Sim (alt, accuracy, speed, bearing, etc.) |
| Repos lidam com null corretamente? | ✅ Sim — verificações com ?. e ?? |
| Entities permitem null onde necessário? | ✅ Sim |
| Conversão null↔default está correta? | ⚠️ Parcial — alguns defaultValue(0) mascaram null real |

---

## 5. SERIALIZAÇÃO / DESSERIALIZAÇÃO

| Formato | Usado em | Status |
|---|---|---|
| JSON (challenge participants) | ChallengeRecord.participantsJson | ✅ OK |
| Protobuf (GPS points upload) | workout_proto_mapper.dart | ✅ OK |
| Timestamp ms (BIGINT) | Todos os *Ms fields | ✅ Consistente |
| UUID strings | Todos os *Id fields | ✅ Consistente |

---

## 6. CAMPOS ÓRFÃOS IDENTIFICADOS

| Campo | Localização | Status |
|---|---|---|
| ChallengeEntity.acceptDeadlineMs | Domain entity | Sem persistência no Isar model |
| IsarSecureStore encryption key | FlutterSecureStorage | Gerada mas nunca usada |
