# SOCIAL_SPEC.md — Sistema Social & Eventos do Omni Runner

> **Sprint:** 15.0.0 (Phase 15 — Social & Events)
> **Status:** ESPECIFICAÇÃO — documento obrigatório antes de implementação
> **Dependências:** `GAMIFICATION_POLICY.md`, `PROGRESSION_SPEC.md`, `DECISIONS.md`
> **Princípio:** Toda interação social é opt-in, sem exposição de dados pessoais.
> Rankings e leaderboards refletem exclusivamente atividade verificada.

---

## 1. VISÃO GERAL

O Social Engine adiciona 4 sistemas ao Omni Runner:

| # | Sistema | Função |
|---|---------|--------|
| 1 | **Amigos** | Conexão bidirecional entre usuários para compartilhar atividade e competir |
| 2 | **Grupos** | Comunidades de corredores com metas coletivas e feed de atividade |
| 3 | **Leaderboards** | Rankings periódicos por métricas de corrida (distância, pace, frequência, XP) |
| 4 | **Eventos** | Corridas virtuais temáticas com período, metas e recompensas exclusivas |

### Relação com sistemas existentes

| Sistema existente | Integração com Social |
|---|---|
| Challenges (Phase 12) | Desafios 1v1/grupo podem ser criados entre amigos ou membros de grupo |
| Progression (Phase 13) | XP e nível exibidos no perfil social; leaderboards por XP de temporada |
| OmniCoins | Eventos e metas de grupo podem recompensar Coins (via `LedgerReason` existentes) |
| Anti-cheat | Apenas sessões `isVerified == true` contam para qualquer feature social |

---

## 2. MODELO DE AMIZADE

### 2.1 Estrutura

A amizade é um **vínculo bidirecional** entre dois usuários, requerendo aceitação explícita.

```
FriendshipEntity {
  id:          String      // UUID único da amizade
  userIdA:     String      // quem enviou o pedido
  userIdB:     String      // quem recebeu o pedido
  status:      FriendshipStatus
  createdAtMs: int         // timestamp do pedido
  acceptedAtMs: int?       // timestamp da aceitação (null se pendente)
}
```

### 2.2 Status de amizade

| Status | Descrição |
|---|---|
| `pending` | Pedido enviado, aguardando aceitação de userIdB |
| `accepted` | Ambos os lados confirmaram — amizade ativa |
| `declined` | Destinatário recusou — pedido arquivado |
| `blocked` | Um usuário bloqueou o outro — invisibilidade mútua |

### 2.3 Regras de negócio

| Regra | Detalhe |
|---|---|
| Limite de amigos | 500 por usuário (evita spam) |
| Pedidos pendentes | Máximo 50 enviados sem resposta |
| Deduplicação | Apenas 1 pedido ativo por par de usuários |
| Cancelamento | Quem enviou pode cancelar pedido pendente |
| Desfazer amizade | Qualquer lado pode remover a qualquer momento |
| Bloqueio | Bloquear remove amizade + impede novos pedidos + oculta em rankings |
| Busca | Por username ou código de convite (nunca por email/telefone) |
| Privacidade | Perfil público exibe apenas: username, nível, avatar, total de corridas |

### 2.4 Feed de atividade entre amigos

Amigos veem uma timeline resumida da atividade recente:

| Tipo de atividade | Visível no feed? | Dados exibidos |
|---|---|---|
| Corrida completada (verified) | Sim | Distância, pace, duração, mapa thumbnail |
| Corrida não-verificada | Não | — |
| Badge desbloqueada | Sim | Nome + ícone da badge |
| Nível alcançado | Sim | Nível novo |
| Missão completada | Sim | Título da missão |
| Desafio completado | Sim | Resultado (se ambos participantes permitirem) |

**Regra de privacidade:** O usuário pode desativar feed de atividade (opt-out total).

---

## 3. GRUPOS

### 3.1 Estrutura

```
GroupEntity {
  id:           String          // UUID único do grupo
  name:         String          // Nome do grupo (3–50 caracteres, sem profanidade)
  description:  String          // Descrição (0–200 caracteres)
  avatarUrl:    String?         // URL do avatar do grupo (opcional)
  createdByUserId: String       // Criador (admin permanente)
  createdAtMs:  int
  privacy:      GroupPrivacy    // open | closed | secret
  maxMembers:   int             // Padrão: 100, máximo: 200
}
```

```
GroupMemberEntity {
  id:          String
  groupId:     String
  userId:      String
  role:        GroupRole        // admin | moderator | member
  joinedAtMs:  int
  status:      GroupMemberStatus // active | banned | left
}
```

### 3.2 Privacidade do grupo

| Tipo | Visível na busca? | Entrada | Membros visíveis? |
|---|---|---|---|
| `open` | Sim | Livre, qualquer um entra | Sim |
| `closed` | Sim | Aprovação do admin/mod | Sim |
| `secret` | Não | Apenas por convite | Apenas para membros |

### 3.3 Papéis

| Role | Permissões |
|---|---|
| `admin` | Todas: editar grupo, promover/rebaixar membros, banir, deletar grupo, criar metas |
| `moderator` | Aprovar pedidos (closed), remover membros, criar metas |
| `member` | Participar de metas, postar no feed, sair |

### 3.4 Regras de negócio

| Regra | Detalhe |
|---|---|
| Limite de grupos por usuário | 10 simultâneos |
| Nome único | Nomes de grupo devem ser únicos (case-insensitive) |
| Criador sai | Se o último admin sair, o membro mais antigo vira admin |
| Ban | Membro banido não pode reentrar (a menos que unban) |
| Inatividade | Grupos sem atividade por 180 dias são arquivados (não deletados) |
| Profanidade | Nome e descrição passam por filtro de profanidade |

### 3.5 Metas coletivas de grupo

Grupos podem ter metas coletivas ativas (máximo 3 simultâneas):

```
GroupGoalEntity {
  id:            String
  groupId:       String
  title:         String           // "500 km em janeiro"
  description:   String
  targetValue:   double           // Meta numérica (ex: 500000.0 para metros)
  currentValue:  double           // Soma de contribuições verificadas
  metric:        GoalMetric       // distance | sessions | movingTime
  startsAtMs:    int
  endsAtMs:      int
  createdByUserId: String
  status:        GoalStatus       // active | completed | expired
}
```

| Regra | Detalhe |
|---|---|
| Contribuição | Cada sessão verificada de qualquer membro soma automaticamente |
| Recompensa | Badge de grupo + XP bônus (conforme PROGRESSION_SPEC) |
| Sobreposição | Múltiplas metas ativas permitidas (até 3) |
| Duração | Mínimo 1 dia, máximo 90 dias |

---

## 4. LEADERBOARDS

### 4.1 Estrutura

```
LeaderboardEntryEntity {
  userId:       String
  displayName:  String
  avatarUrl:    String?
  level:        int             // Derivado do XP (leitura rápida)
  value:        double          // Métrica ranqueada
  rank:         int             // Posição (1-indexed)
  periodKey:    String          // "2026-W08" (semana) ou "2026-02" (mês)
}
```

### 4.2 Tipos de leaderboard

| Escopo | Período | Reset | Participantes |
|---|---|---|---|
| **Global** | Semanal (segunda a domingo UTC) | Automático | Todos os usuários opt-in |
| **Global** | Mensal (1° ao último dia UTC) | Automático | Todos os usuários opt-in |
| **Amigos** | Semanal | Automático | Apenas amigos aceitos |
| **Grupo** | Semanal / Mensal | Automático | Membros do grupo |
| **Season** | Temporada (90 dias) | Fim da temporada | Todos opt-in |

### 4.3 Métricas ranqueáveis

| Métrica | Unidade | Derivada de |
|---|---|---|
| `distance` | Metros | Soma de `totalDistanceM` de sessões verificadas no período |
| `sessions` | Contagem | Total de sessões verificadas no período |
| `movingTime` | Milissegundos | Soma de `movingMs` de sessões verificadas |
| `avgPace` | sec/km | Média ponderada por distância das sessões no período |
| `seasonXp` | XP | `ProfileProgressEntity.seasonXp` no período |

### 4.4 Regras de negócio

| Regra | Detalhe |
|---|---|
| Opt-in obrigatório | Usuário deve ativar leaderboards em Settings (default: OFF) |
| Apenas verified | Sessões com `isVerified == false` não contam |
| Sem prêmio monetário | Posição no ranking **nunca** gera Coins (GAMIFICATION_POLICY §4.3) |
| Badge de posição | Top 3 semanal/mensal recebe badge temporária (puramente visual) |
| Anti-farming | Máximo 3 sessões/dia contam para leaderboard (evita split runs) |
| Blocked users | Usuários bloqueados não aparecem nos seus leaderboards |
| Mínimo para ranking | ≥ 1 sessão verificada no período para aparecer |
| Empate | Mesmo valor → posição compartilhada, próximo rank pula (1, 2, 2, 4) |

### 4.5 Cálculo e atualização

| Aspecto | Decisão |
|---|---|
| Frequência de cálculo | Sob demanda ao abrir tela + cache de 5 min |
| Armazenamento | Materializado em tabela Isar por período (pré-calculado) |
| Snapshot histórico | Leaderboard final de cada período é congelado e imutável |
| Dados exibidos | Rank, username, avatar, nível, valor da métrica |

---

## 5. EVENTOS

### 5.1 Estrutura

Eventos são corridas virtuais temáticas com período fixo, abertos a todos ou restritos.

```
EventEntity {
  id:              String
  title:           String          // "Carnaval Run 2026"
  description:     String
  imageUrl:        String?         // Banner do evento
  type:            EventType       // individual | team
  metric:          GoalMetric      // distance | sessions | movingTime
  targetValue:     double?         // Meta individual (null = sem meta, apenas ranking)
  startsAtMs:      int
  endsAtMs:        int
  maxParticipants: int?            // null = ilimitado
  createdBySystem: bool            // true = evento oficial; false = evento de usuário
  rewards:         EventRewards    // XP, Coins, badge exclusiva
  status:          EventStatus     // upcoming | active | completed | cancelled
}
```

```
EventParticipantEntity {
  id:           String
  eventId:      String
  userId:       String
  joinedAtMs:   int
  currentValue: double           // Progresso acumulado
  rank:         int?             // Posição (calculada ao vivo)
  completed:    bool             // Atingiu targetValue?
  completedAtMs: int?
}
```

### 5.2 Tipos de evento

| Tipo | Descrição | Exemplo |
|---|---|---|
| `individual` | Cada participante tem meta pessoal | "Corra 42.195 km em 30 dias" |
| `team` | Equipes de N pessoas dividem a meta | "100 km coletivos em 7 dias (time de 5)" |

### 5.3 Recompensas

```
EventRewards {
  xpCompletion:    int     // XP por completar a meta (0 se sem meta)
  coinsCompletion: int     // Coins por completar
  xpParticipation: int     // XP mínimo por participar (≥ 1 sessão no período)
  badgeId:         String? // Badge exclusiva do evento (desbloqueada ao completar)
}
```

| Regra de recompensa | Detalhe |
|---|---|
| Participação | Qualquer participante com ≥ 1 sessão verified recebe `xpParticipation` |
| Conclusão | Quem atingir `targetValue` recebe `xpCompletion` + `coinsCompletion` + badge |
| Ranking | Posição **não** gera Coins (GAMIFICATION_POLICY §4.3) |
| Badge exclusiva | Disponível apenas durante o evento; quem não completou não desbloqueia |
| Daily cap | Recompensas de evento seguem os daily caps de PROGRESSION_SPEC §4 |

### 5.4 Eventos oficiais vs. eventos de usuário

| Aspecto | Oficial (`createdBySystem: true`) | De usuário |
|---|---|---|
| Quem cria | Sistema (admin/backend) | Qualquer usuário |
| Visibilidade | Global (destaque na home) | Apenas amigos + grupo |
| Limite de participantes | Ilimitado (default) | Máximo 200 |
| Badge exclusiva | Sim (badge única por evento) | Não (XP/Coins apenas) |
| Duração | 7–90 dias | 1–30 dias |
| Frequência | ~1 por mês | Sem limite |

### 5.5 Regras de negócio

| Regra | Detalhe |
|---|---|
| Inscrição | Livre para eventos abertos; automática ao criar (criador é participante) |
| Desistência | Pode sair antes do fim sem penalidade; perde direito a recompensa |
| Sobreposição | Usuário pode participar de até 5 eventos simultâneos |
| Sessão conta para múltiplos | Mesma sessão contribui para todos os eventos ativos do usuário |
| Anti-cheat | Apenas `isVerified == true` |
| Evento expirado | Após `endsAtMs`, recompensas são distribuídas automaticamente |
| Cancelamento | Evento cancelado antes do início → participantes notificados, sem recompensa |

---

## 6. PERFIL SOCIAL

### 6.1 Dados públicos

Cada usuário tem um perfil social com dados limitados:

```
SocialProfileEntity {
  userId:         String
  username:       String        // Único, 3–20 chars, alfanumérico + underscores
  displayName:    String        // Nome exibido (3–30 chars)
  avatarUrl:      String?
  bio:            String?       // Máximo 150 caracteres
  level:          int           // Derivado (read-only)
  totalRuns:      int           // Lifetime sessions
  totalDistanceKm: double      // Lifetime distance
  memberSinceMs:  int
  isPublic:       bool          // true = perfil visível a todos; false = apenas amigos
  leaderboardOptIn: bool        // true = aparece em leaderboards globais
}
```

### 6.2 Configurações de privacidade

| Configuração | Default | Efeito |
|---|---|---|
| `isPublic` | `true` | Perfil visível em busca e rankings |
| `leaderboardOptIn` | `false` | Aparece em leaderboards globais (requer ativação) |
| `activityFeedEnabled` | `true` | Amigos veem atividade no feed |
| `showExactPace` | `false` | Feed mostra "Rápido" em vez de "4:30/km" |
| `showMap` | `false` | Feed mostra distância mas não mapa/rota |

### 6.3 Username

| Regra | Detalhe |
|---|---|
| Formato | `[a-zA-Z0-9_]`, 3–20 caracteres |
| Unicidade | Global, case-insensitive |
| Alteração | Máximo 1 por 30 dias |
| Profanidade | Filtro obrigatório na criação e alteração |
| Reservados | Lista de termos reservados (admin, omni, system, etc.) |

---

## 7. NOTIFICAÇÕES SOCIAIS

| Evento | Canal | Obrigatória? |
|---|---|---|
| Pedido de amizade recebido | Push + in-app | Opt-out possível |
| Pedido aceito | In-app | Sempre |
| Convite para grupo | Push + in-app | Opt-out possível |
| Amigo completou corrida | In-app (feed) | Opt-out possível |
| Meta de grupo atingida | Push + in-app | Opt-out possível |
| Evento começou | Push + in-app | Opt-out possível |
| Ultrapassado no leaderboard | In-app | Opt-out possível |
| Evento terminando (24h) | Push | Opt-out possível |

**Regra:** Push notifications são sempre opt-in (iOS exige, Android recomenda).

---

## 8. PERSISTÊNCIA

### 8.1 Local (Isar)

| Entidade | Persistência local? | Motivo |
|---|---|---|
| `SocialProfileEntity` | Sim (cache) | Exibição offline do perfil próprio |
| `FriendshipEntity` | Sim (cache) | Lista de amigos disponível offline |
| `GroupEntity` | Sim (cache) | Grupos do usuário disponíveis offline |
| `LeaderboardEntryEntity` | Sim (snapshot) | Último leaderboard visualizado |
| `EventEntity` | Sim (cache) | Eventos ativos |
| `EventParticipantEntity` | Sim (own progress) | Progresso do usuário nos eventos |

### 8.2 Remoto (Supabase — futuro)

| Entidade | Tabela | RLS |
|---|---|---|
| Friendships | `friendships` | Apenas os dois usuários envolvidos |
| Groups | `groups` / `group_members` | Membros e admins |
| Leaderboards | `leaderboard_snapshots` | Leitura: opt-in; escrita: server-only |
| Events | `events` / `event_participants` | Leitura: pública; escrita: server-only para oficiais |
| Social Profiles | `social_profiles` | Leitura: conforme `isPublic`; escrita: próprio usuário |

### 8.3 Estratégia de sync

| Aspecto | Decisão |
|---|---|
| Offline-first | Toda UI renderiza com dados locais; sync atualiza em background |
| Conflito | Server wins — dados remotos são autoritativos para social |
| Frequência | Pull on app launch + pull-to-refresh + push após mudanças locais |
| Sessões | Contribuições para leaderboards/eventos são enviadas após cada sessão |

---

## 9. ANTI-FRAUDE SOCIAL

| Vetor | Mitigação |
|---|---|
| Spam de pedidos de amizade | Rate limit: 20 pedidos/dia |
| Farming de leaderboard (split runs) | Máximo 3 sessões/dia contam para ranking |
| Perfil falso / bot | Username review + profanity filter + report |
| Grupo fake para evento | Eventos de usuário limitados a amigos/grupo |
| Multi-account para dominar ranking | Device fingerprint + account linking (futuro) |
| Abuso de feed | Report + block remove da timeline |

---

## 10. LIMITES E QUOTAS

| Recurso | Limite |
|---|---|
| Amigos por usuário | 500 |
| Pedidos pendentes enviados | 50 |
| Grupos por usuário | 10 |
| Membros por grupo | 200 |
| Metas ativas por grupo | 3 |
| Eventos simultâneos (participando) | 5 |
| Sessões/dia para leaderboard | 3 |
| Username changes / 30 dias | 1 |
| Bio | 150 caracteres |
| Nome de grupo | 50 caracteres |
| Descrição de grupo | 200 caracteres |
| Descrição de evento | 500 caracteres |

---

## 11. ENTIDADES — RESUMO PARA IMPLEMENTAÇÃO

| Entidade | Campos principais | Equatable? | Isar model? |
|---|---|---|---|
| `FriendshipEntity` | id, userIdA, userIdB, status, createdAtMs, acceptedAtMs | Sim | Sim |
| `SocialProfileEntity` | userId, username, displayName, avatarUrl, bio, level, isPublic | Sim | Sim |
| `GroupEntity` | id, name, description, privacy, maxMembers, createdByUserId | Sim | Sim |
| `GroupMemberEntity` | id, groupId, userId, role, status, joinedAtMs | Sim | Sim |
| `GroupGoalEntity` | id, groupId, title, targetValue, currentValue, metric, status | Sim | Sim |
| `LeaderboardEntryEntity` | userId, displayName, level, value, rank, periodKey | Sim | Sim |
| `EventEntity` | id, title, type, metric, targetValue, rewards, status | Sim | Sim |
| `EventParticipantEntity` | id, eventId, userId, currentValue, rank, completed | Sim | Sim |

### Enums necessários

| Enum | Valores |
|---|---|
| `FriendshipStatus` | pending, accepted, declined, blocked |
| `GroupPrivacy` | open, closed, secret |
| `GroupRole` | admin, moderator, member |
| `GroupMemberStatus` | active, banned, left |
| `GoalMetric` | distance, sessions, movingTime |
| `GoalStatus` | active, completed, expired |
| `EventType` | individual, team |
| `EventStatus` | upcoming, active, completed, cancelled |

---

## 12. O QUE NÃO IMPLEMENTAR (FORA DO ESCOPO)

| Feature excluída | Motivo |
|---|---|
| Chat/mensagens diretas | Complexidade de moderação; usar deep links para WhatsApp/Telegram |
| Foto no feed de atividade | Moderação de conteúdo; requer infra de storage/CDN |
| Coins por posição de ranking | Viola GAMIFICATION_POLICY §4.3 |
| Compra de boost para ranking | Pay-to-win; viola GAMIFICATION_POLICY |
| Grupos pagos / premium | Coins não podem ser cobrados para features sociais |
| Follow sem reciprocidade | Modelo amizade bidirecional simplifica privacidade |
| Live tracking para amigos | Requer WebSocket; fora do escopo desta fase |
| Strava-like Segments | Complexidade de geo-matching; considerar em fase futura |

---

## 13. SPRINTS SUGERIDOS

| Sprint | Escopo |
|---|---|
| 15.0.0 | Especificação (este documento) |
| 15.1.x | Entidades + Repositórios (Friendship, SocialProfile, Group, Event, Leaderboard) |
| 15.2.x | Use Cases amizade (SendFriendRequest, AcceptFriend, BlockUser, SearchUsers) |
| 15.3.x | Use Cases grupo (CreateGroup, JoinGroup, CreateGroupGoal, ContributeToGoal) |
| 15.4.x | Use Cases leaderboard (ComputeLeaderboard, GetLeaderboard, OptInLeaderboard) |
| 15.5.x | Use Cases eventos (CreateEvent, JoinEvent, ContributeToEvent, SettleEvent) |
| 15.6.x | Persistência Isar (models, repos) + DI |
| 15.7.x | UI: FriendsScreen, GroupScreen, LeaderboardScreen, EventsScreen + BLoCs |
| 15.8.x | Integração com TrackingBloc (post-session: contribute to goals/events/leaderboards) |
| 15.9.x | QA Phase 15 |

---

*Documento criado no Sprint 15.0.0 — Social & Events Spec*
