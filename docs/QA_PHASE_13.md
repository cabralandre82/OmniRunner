# QA Phase 13 — Progression Engine

**Data:** 2026-02-17
**Escopo:** Sprints 13.1.0–13.1.5 (Progressão: XP, Níveis, Badges, Streaks, Missões, Temporadas + UI)
**Método:** Auditoria estática de código (grep + leitura manual)
**Atualização:** 2026-02-17 — correções aplicadas, status atualizado

---

## 1. Termos Proibidos

| Termo buscado | Ocorrências em código/UI | Veredicto |
|---|---|---|
| comprar, vender, loja | 0 em progressão | OK |
| R$, dinheiro, real (moeda) | 0 | OK |
| pay, purchase, buy | `cosmeticPurchase` enum + "Compra cosmética" label (wallet_screen) | OK — cosmético virtual, sem dinheiro real |
| store, shop | Apenas `StravaSecureStore`, health store (HealthKit/HC) | OK — contexto plataforma |
| premium, monetiz, IAP | 0 | OK |
| gamble, aposta, loteria, raffle, jackpot | 0 | OK |

**Resultado: APROVADO** — Nenhum termo proibido por GAMIFICATION_POLICY.md encontrado em strings visíveis ao usuário.

---

## 2. Inconsistências

### INC-01 — Comentário ordinal desatualizado em `ledger_record.dart` ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — Comentário atualizado para refletir os 15 ordinals atuais (0–14, incluindo `badgeReward` e `missionReward`).

### INC-02 — Serialização ordinal frágil (3 enums) ✅ MITIGADO

**Severidade:** MÉDIA
**Status:** MITIGADO — Regra append-only documentada em `DECISIONS.md` (DECISAO 018). Enums persistidos via `.index` devem ter novos valores **sempre no final**. Comentário em `ledger_record.dart` serve como documentação canônica.

### INC-03 — `ClaimRewards` usa `LedgerReason` semanticamente incorreto ✅ CORRIGIDO

**Severidade:** ALTA
**Status:** CORRIGIDO — Criados `LedgerReason.badgeReward` (ordinal 13) e `LedgerReason.missionReward` (ordinal 14). `ClaimRewards` agora usa os reasons corretos. `wallet_screen.dart` exibe "Conquista desbloqueada" e "Missão completada" respectivamente.

### INC-04 — Badge catalog e mission defs injetados como `const []`

**Severidade:** MÉDIA
**Status:** ESPERADO — Catálogos reais serão injetados em sprint futuro (13.2.x+). Funcionalidade inativa por design nesta fase.

### INC-05 — `MissionsScreen` mostra ID como título ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — `MissionsBloc` agora recebe `activeMissionDefs` callback. `MissionsLoaded` state inclui `Map<String, MissionEntity> missionDefs`. `_MissionTile` exibe `def.title` com fallback para missionId truncado. Descrição da missão exibida quando disponível.

### INC-06 — `CreateDailyMissions` não registrado no DI ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — `CreateDailyMissions` registrado como factory em `service_locator.dart`.

### INC-07 — Season repos não implementados

**Severidade:** BAIXA
**Status:** PENDENTE — Planejado para sprint 13.2.x.

---

## 3. Vetores de Fraude

### FRAUD-01 — Race condition no wallet entre pipelines paralelas ✅ CORRIGIDO

**Severidade:** ALTA
**Status:** CORRIGIDO — `_dispatchPostSessionPipeline` agora dispara um único `unawaited` que chama `_runPostSessionPipeline`, um método `async` que executa as 3 pipelines **sequencialmente** com `await`. Uma única leitura de sessão. Nenhum acesso concorrente ao wallet.

### FRAUD-02 — UUID generator compartilhado entre pipelines paralelas ✅ CORRIGIDO

**Severidade:** MÉDIA
**Status:** CORRIGIDO — Cada pipeline tem seu próprio generator com prefixo distinto: `px_` (progression), `rc_` (reward coins). Challenge dispatcher não usa UUID generator. Contadores isolados.

### FRAUD-03 — `AwardXpForWorkout` não verifica distância mínima ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — Adicionada constante `_minDistanceM = 200.0`. Sessões com `totalDistanceM < 200m` são rejeitadas com `below_min_distance`.

### FRAUD-04 — Streak não é realmente atualizado

**Severidade:** BAIXA
**Status:** PENDENTE — `UpdateStreak` use case planejado para sprint futuro.

### FRAUD-05 — Profile `totalXp` e `seasonXp` dupla-escrita sem transação

**Severidade:** MÉDIA
**Status:** MITIGADO — Pipelines agora serializadas (FRAUD-01 fix), eliminando o risco de race condition entre elas. Risco residual apenas se futuro código paralelo for adicionado. Regra documentada.

---

## 4. Alinhamento UI ↔ Domain

| Screen | Status | Notas |
|---|---|---|
| `progression_screen.dart` | OK | Todos os campos de `ProfileProgressEntity` exibidos. Level/XP bar derivados corretamente. |
| `badges_screen.dart` | PARCIAL | Funcional mas catalog vazio → tela sempre mostra estado vazio. Secret badges handled. Tier colors OK. |
| `missions_screen.dart` | OK | Progress bar + status corretos. Título agora exibe `MissionEntity.title` via BLoC join. |
| BLoC sealed states | OK | Todos os 3 BLoCs usam exhaustive switch. Todos os estados cobertos nos screens. |

---

## 5. Completude do DI

### Registrados corretamente:
- **Repos (4):** IProfileProgressRepo, IXpTransactionRepo, IBadgeAwardRepo, IMissionProgressRepo
- **Use Cases (9):** AwardXpForWorkout, EvaluateBadges, UpdateMissionProgress, ClaimRewards, PostSessionProgression, SubmitRunToChallenge, PostSessionChallengeDispatcher, RewardSessionCoins, CreateDailyMissions
- **BLoCs (6):** ProgressionBloc, BadgesBloc, MissionsBloc, ChallengesBloc, WalletBloc, TrackingBloc

### Não registrados (existem no código mas faltam no DI):
| Componente | Risco | Justificativa |
|---|---|---|
| `LedgerService` | BAIXO | Usado por `SettleChallenge` (que também não está no DI) |
| `StartChallenge` | BAIXO | Desafios não podem ser iniciados via UI |
| `EvaluateChallenge` | BAIXO | Avaliação de desafios não automática |
| `SettleChallenge` | BAIXO | Liquidação de desafios não automática |
| `InviteParticipants` | BAIXO | Convites não funcionais |
| `GetWallet` / `GetLedger` | BAIXO | WalletBloc acessa repos diretamente |
| Season repos | BAIXO | Models Isar existem, repos/interfaces não |

---

## 6. Resumo de Riscos

| ID | Severidade | Descrição | Status |
|---|---|---|---|
| FRAUD-01 | ALTA | Race condition wallet (pipelines paralelas) | ✅ CORRIGIDO |
| INC-03 | ALTA | LedgerReason errado em ClaimRewards | ✅ CORRIGIDO |
| FRAUD-02 | MÉDIA | UUID generator compartilhado (colisão) | ✅ CORRIGIDO |
| INC-02 | MÉDIA | Enum ordinals frágeis (3 repos) | ✅ MITIGADO (DECISAO 018) |
| INC-04 | MÉDIA | Catalogs vazios (badges/missions) | ESPERADO (13.2.x) |
| FRAUD-05 | MÉDIA | Profile denormalizado sem transação | ✅ MITIGADO (pipelines serializadas) |
| FRAUD-03 | BAIXA | XP sem distância mínima | ✅ CORRIGIDO (200m) |
| INC-01 | BAIXA | Comentário ordinal stale | ✅ CORRIGIDO |
| INC-05 | BAIXA | Mission screen mostra ID | ✅ CORRIGIDO |
| INC-06 | BAIXA | CreateDailyMissions não no DI | ✅ CORRIGIDO |
| INC-07 | BAIXA | Season repos não implementados | PENDENTE (13.2.x) |
| FRAUD-04 | BAIXA | UpdateStreak não implementado | PENDENTE |

---

## 7. Validação Final

- `dart analyze`: 0 erros/warnings novos (3 TODOs pré-existentes, 2 infos de teste pré-existentes)
- `flutter test`: 860/860 testes passaram
- Todos os issues ALTA e MÉDIA resolvidos ou mitigados

---

*Documento gerado e atualizado — Sprint 13.1.6 QA Fix*
