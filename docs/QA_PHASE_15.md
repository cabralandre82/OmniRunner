# QA Phase 15 — Social & Events

**Data:** 2026-02-17
**Escopo:** Sprints 15.1.0–15.7.0 (Social: Amigos, Grupos, Leaderboards, Eventos — Entidades, Use Cases, Isar Models, BLoCs, UI)
**Método:** Auditoria estática de código (grep + leitura manual)

---

## 1. Termos Proibidos

| Termo buscado | Ocorrências em código/UI | Veredicto |
|---|---|---|
| comprar, vender, loja | 0 | OK |
| R$, dinheiro, real (moeda) | 0 | OK |
| pay, purchase, buy | 0 | OK |
| store, shop | 0 | OK |
| premium, monetiz, IAP | 0 | OK |
| gamble, aposta, loteria, raffle, jackpot | 0 | OK |
| withdraw, cash | 0 | OK |

**Resultado: APROVADO** — Nenhum termo proibido por GAMIFICATION_POLICY.md encontrado.

---

## 2. Inconsistências

### INC-01 — `FriendsScreen` passa `currentUserId: ''` hardcoded ✅ CORRIGIDO

**Severidade:** ALTA
**Status:** CORRIGIDO — `FriendsLoaded` state agora inclui `userId`. `FriendsBloc._fetch` propaga `_userId` para o state. `FriendsScreen._body` passa `state.userId` para `_FriendTile`.

### INC-02 — Use cases sociais não registrados no DI

**Severidade:** MÉDIA
**Arquivo:** `lib/core/service_locator.dart`
**Problema:** 9 use cases (`SendFriendInvite`, `AcceptFriend`, `BlockUser`, `CreateGroup`, `JoinGroup`, `LeaveGroup`, `JoinEvent`, `SubmitWorkoutToEvent`, `EvaluateEvent`) não estão registrados como factories no DI. BLoCs atuais só fazem leitura; ações de mutação não podem ser invocadas pela UI.
**Status:** ESPERADO — Planejado para sprint 15.5.0+ (repo impls + wiring completo).

### INC-03 — `findBetween` bloqueia re-envio após friendship `declined` ✅ CORRIGIDO

**Severidade:** MÉDIA
**Status:** CORRIGIDO — `SendFriendInvite` agora trata `declined` como caso especial: reativa o friendship existente para `pending` (reutiliza o record, atualiza `createdAtMs`). Outros status (`accepted`, `pending`) continuam lançando `FriendshipAlreadyExists`.

### INC-04 — Navegação vazia em cards (`GroupsScreen`, `EventsScreen`)

**Severidade:** BAIXA
**Arquivo:** `lib/presentation/screens/groups_screen.dart:99`, `lib/presentation/screens/events_screen.dart:173`
**Problema:** `_GroupCard` e `_EventCard` têm `onTap: () {}` — InkWell visual funciona mas não navega para detalhes.
**Status:** ESPERADO — Navegação será conectada quando rotas forem definidas.

### INC-05 — `LeaderboardsBloc` usa `DateTime.now()` direto ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — `LoadLeaderboard` event agora tem campo `nowMs` (default: `DateTime.now().millisecondsSinceEpoch`). BLoC usa `_lastNowMs` em vez de chamar `DateTime.now()` direto. Testes podem injetar valor fixo.

### INC-06 — Isar: falta index composto `(eventId, userId)` em `EventParticipationRecord` ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — Index composto unique `(eventId, userId)` adicionado ao `EventParticipationRecord` via `@Index(unique: true, composite: [CompositeIndex('userId')])`.

### INC-07 — Isar: falta index composto `(userIdA, userIdB)` em `FriendshipRecord` ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — Index composto unique `(userIdA, userIdB)` adicionado ao `FriendshipRecord` via `@Index(unique: true, composite: [CompositeIndex('userIdB')])`.

### INC-08 — Typo: "Apennas" em `leaderboards_screen.dart` ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — "Apennas" → "Apenas".

---

## 3. Vetores de Fraude

### FRAUD-01 — `SubmitWorkoutToEvent` sem dedup de sessão ✅ CORRIGIDO

**Severidade:** ALTA
**Status:** CORRIGIDO — `EventParticipationEntity` agora inclui `contributingSessionIds: List<String>` e método `hasSession(sessionId)`. `SubmitWorkoutToEvent` verifica `participation.hasSession(sessionId)` antes de acumular. Session IDs persistidos como CSV no Isar (`contributingSessionIdsCsv`).

### FRAUD-02 — `EvaluateEvent` permite liquidar evento ativo antes do `endsAtMs` ✅ CORRIGIDO

**Severidade:** MÉDIA
**Status:** CORRIGIDO — Guard simplificado para `if (!event.hasEnded(nowMs)) throw InvalidEventStatus(...)`. Qualquer evento que não passou de `endsAtMs` é rejeitado, independentemente do status.

### FRAUD-03 — Rewards de eventos sem caps ✅ CORRIGIDO

**Severidade:** MÉDIA
**Status:** CORRIGIDO — `EventRewards` agora tem constantes estáticas `maxXpCompletion=500`, `maxCoinsCompletion=200`, `maxXpParticipation=100`. Factory `EventRewards.userCreated()` faz clamp automático e remove `badgeId` (só eventos oficiais concedem badges). Daily caps da Phase 13 continuam como segunda barreira.

### FRAUD-04 — `JoinGroup` cria membro duplicado para ex-membros (`left`) ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — `JoinGroup` agora trata `left` como caso especial: reutiliza o registro existente com `copyWith(status: active, role: member, displayName: ...)` em vez de criar novo. Validação de group limit mantida.

### FRAUD-05 — `BlockUser` não registra quem bloqueou ✅ CORRIGIDO

**Severidade:** BAIXA
**Status:** CORRIGIDO — `BlockUser` agora normaliza: se o bloqueador é `userIdB`, deleta o record antigo e cria um novo com o bloqueador como `userIdA`. Em records bloqueados, `userIdA` é sempre o bloqueador.

---

## 4. UI ↔ Domain

### UI-01 — BLoCs sociais são read-only

**Severidade:** MÉDIA
**Arquivo:** `friends_bloc.dart`, `groups_bloc.dart`, `events_bloc.dart`
**Problema:** Os 4 BLoCs sociais só emitem eventos de Load/Refresh. Não há eventos para ações de mutação:
- `FriendsBloc`: sem Accept, Decline, Send, Block
- `GroupsBloc`: sem Create, Join, Leave
- `EventsBloc`: sem Join, Submit
**Status:** ESPERADO — Ações de mutação dependem de use cases no DI (INC-02) e repo impls (Sprint 15.5.0+).

### UI-02 — `GroupDetailsScreen` recebe dados por construtor, sem BLoC

**Severidade:** BAIXA
**Arquivo:** `lib/presentation/screens/group_details_screen.dart:7-8`
**Problema:** `members` e `goals` são passados como parâmetros do construtor. Não há BLoC dedicado para carregar dados do grupo — a tela depende do caller ter os dados prontos.
**Status:** ESPERADO — Pode ser resolvido com um `GroupDetailsBloc` futuro.

---

## 5. DI Completude

| Componente | Registrado? | Nota |
|---|---|---|
| `IFriendshipRepo` (interface) | Sim (dep de `FriendsBloc`) | Sem impl concreta |
| `IGroupRepo` (interface) | Sim (dep de `GroupsBloc`) | Sem impl concreta |
| `IEventRepo` (interface) | Sim (dep de `EventsBloc`) | Sem impl concreta |
| `FriendsBloc` | Sim | — |
| `GroupsBloc` | Sim | — |
| `LeaderboardsBloc` | Sim | Sem deps (placeholder) |
| `EventsBloc` | Sim | — |
| `SendFriendInvite` | **Não** | Planejado 15.5.0+ |
| `AcceptFriend` | **Não** | Planejado 15.5.0+ |
| `BlockUser` | **Não** | Planejado 15.5.0+ |
| `CreateGroup` | **Não** | Planejado 15.5.0+ |
| `JoinGroup` | **Não** | Planejado 15.5.0+ |
| `LeaveGroup` | **Não** | Planejado 15.5.0+ |
| `JoinEvent` | **Não** | Planejado 15.5.0+ |
| `SubmitWorkoutToEvent` | **Não** | Planejado 15.5.0+ |
| `EvaluateEvent` | **Não** | Planejado 15.5.0+ |
| Repo impls (Friendship, Group, Event) | **Não** | Planejado 15.5.0 |
| `ComputeLeaderboard` use case | **Não** | Planejado 15.3.0 |

---

## 6. Decisão DECISAO 018 — Append-Only Enums

Todos os 10 enums sociais foram verificados e documentam a regra append-only:
- `FriendshipStatus` (4 valores) ✅
- `GroupPrivacy` (3) ✅
- `GoalMetric` (3) ✅
- `GoalStatus` (3) ✅
- `GroupRole` (3) ✅
- `GroupMemberStatus` (3) ✅
- `EventType` (2) ✅
- `EventStatus` (4) ✅
- `LeaderboardScope` (4) ✅
- `LeaderboardPeriod` (3) ✅
- `LeaderboardMetric` (5) ✅

Todos os Isar models documentam o mapping ordinal nos comentários ✅

---

## 7. Resumo

| Categoria | ALTA | MÉDIA | BAIXA | Total | Corrigidos |
|---|---|---|---|---|---|
| Termos proibidos | 0 | 0 | 0 | **0** | — |
| Inconsistências | 1 | 2 | 5 | **8** | 6 |
| Fraude | 1 | 2 | 2 | **5** | 5 |
| UI ↔ Domain | 0 | 1 | 1 | **2** | 0 |
| **Total** | **2** | **5** | **8** | **15** | **11** |

**Atualização:** 2026-02-17 — Sprint 15.9.0-fix aplicado.

### Issues corrigidos (11/15):

| ID | Severidade | Status |
|---|---|---|
| INC-01 | ALTA | ✅ CORRIGIDO |
| FRAUD-01 | ALTA | ✅ CORRIGIDO |
| FRAUD-02 | MÉDIA | ✅ CORRIGIDO |
| INC-03 | MÉDIA | ✅ CORRIGIDO |
| FRAUD-03 | MÉDIA | ✅ CORRIGIDO |
| INC-05 | BAIXA | ✅ CORRIGIDO |
| INC-06 | BAIXA | ✅ CORRIGIDO |
| INC-07 | BAIXA | ✅ CORRIGIDO |
| INC-08 | BAIXA | ✅ CORRIGIDO |
| FRAUD-04 | BAIXA | ✅ CORRIGIDO |
| FRAUD-05 | BAIXA | ✅ CORRIGIDO |

### Issues pendentes para sprints futuros (4/15):

| ID | Severidade | Status | Sprint |
|---|---|---|---|
| INC-02 | MÉDIA | ESPERADO | 15.5.0+ (use cases no DI) |
| INC-04 | BAIXA | ESPERADO | Quando rotas forem definidas |
| UI-01 | MÉDIA | ESPERADO | 15.5.0+ (BLoC mutations) |
| UI-02 | BAIXA | ESPERADO | Futuro (GroupDetailsBloc) |

### Validação pós-fix:
- `dart analyze`: 0 issues (apenas TODOs preexistentes)
- `flutter test`: 860/860 passed
- `build_runner`: Isar models regenerados com sucesso
