# ARCHITECTURE.md — Arquitetura Tecnica do Omni Runner

> **Sprint:** 1.2
> **Status:** Ativo
> **Referencia:** STACK.md (congelado), GOVERNANCE.md (congelado)

---

## 1. STACK

| Camada | Tecnologia | Versao Minima |
|---|---|---|
| UI / Framework | Flutter | 3.22+ |
| State Management | BLoC | 8.x |
| DI / Service Locator | get_it | latest |
| Persistencia Local | Isar | 3.x |
| Modelos de Dados | Protobuf | 3.x |
| Mapas | MapLibre | 0.19+ |
| Backend / Sync | Supabase | 2.x |
| GPS | Geolocator | 11.x |
| Error Handling | fpdart (Either/Option) | 1.x |
| Equality | Equatable | 2.x |

---

## 2. CAMADAS (Clean Architecture)

```
lib/
├── domain/            # Regras de negocio puras (Dart puro)
│   ├── entities/      # Entities (Protobuf-generated, imutaveis)
│   ├── value_objects/  # Validacoes de dominio
│   ├── repositories/  # Contratos abstratos (interfaces)
│   ├── usecases/      # Use Cases (um por arquivo)
│   └── failures/      # Sealed class Failure hierarchy
│
├── application/       # Orquestracao
│   └── <feature>/
│       ├── bloc/      # BLoC + Events + States
│       └── dto/       # DTOs entre camadas
│
├── infrastructure/    # Implementacoes concretas
│   ├── models/        # Isar models, Protobuf adapters
│   ├── datasources/   # Isar, Supabase, GPS service
│   └── repositories/  # Implementacoes dos contratos do domain
│
├── presentation/      # UI
│   ├── pages/         # Telas (sufixo: Page)
│   ├── widgets/       # Componentes reutilizaveis (sufixo: Widget)
│   └── routes/        # Navegacao e rotas
│
├── injection_container.dart  # get_it — unico ponto de DI
└── main.dart                 # Entry point
```

---

## 3. GRAFO DE DEPENDENCIA

```
presentation -> application -> domain <- infrastructure
                                 ^
                                 |
                          TUDO DEPENDE DO DOMAIN

Proibido:
  presentation -> infrastructure
  application  -> infrastructure
  domain       -> qualquer outra camada
```

---

## 4. CONVENCOES DE UNIDADES (FIXAS)

| Grandeza | Tipo | Unidade Interna | Formatacao UI |
|---|---|---|---|
| Distancia | double | metros | km (ex: 5.23 km) |
| Tempo | int64 (persistido/serializado) | milissegundos | HH:MM:SS |
| Pace | double | segundos por km | min:sec/km (ex: 5:30/km) |
| Coordenadas | double | graus decimais (WGS84) | — |
| Velocidade | double | metros por segundo | km/h (apenas UI) |

**Regra:** Conversao para unidades de exibicao acontece APENAS na presentation layer.

---

## 5. ERROR HANDLING

```
Either<Failure, T> — usado em TODA operacao que pode falhar

Hierarquia (sealed class):
  Failure
  ├── GpsFailure (noPermission, timeout, unavailable)
  ├── StorageFailure (readError, writeError, full)
  ├── SyncFailure (noConnection, serverError, timeout)
  ├── ValidationFailure (invalidPace, invalidDistance, suspectedCheat)
  ├── IntegrationFailure (auth, upload, export — ver integrations_failures.dart)
  ├── HealthExportFailure (permission, availability — ver health_export_failures.dart)
  └── GamificationFailure (unverifiedSession, dailyLimitReached, challengeExpired)

Fluxo:
  Repository retorna Either<Failure, T>
  -> BLoC converte para State.failed(failure)
  -> Presentation exibe mensagem mapeada

Nenhum throw no domain ou application. Apenas Either.
```

---

## 6. FEATURES (MAPEADAS DO SCOPE.md)

| Feature | Camada Principal | Tecnologia |
|---|---|---|
| F1 — Registro GPS | infrastructure (GPS service) | Geolocator |
| F2 — Calculo de metricas | domain (use cases) | Dart puro |
| F3 — Persistencia offline | infrastructure (Isar) | Isar |
| F4 — Visualizacao de mapa | presentation | MapLibre |
| F5 — Ghost Runner | application (BLoC) | BLoC + Isar |
| F6 — Anti-cheat basico | domain (use cases) | Dart puro |
| F7 — Sincronizacao manual | infrastructure (Supabase) | Supabase |
| F8 — Integrações externas | infrastructure (HTTP, share_plus) | Strava API, GPX/TCX/FIT export |
| F9 — Gamification Engine | domain (use cases) + infrastructure (Isar) | Coins, desafios, rankings — ver GAMIFICATION_POLICY.md |

---

## 7. INSTITUTIONAL DOMAIN (Assessoria Ecosystem)

> **Origem:** DECISAO 038 — Introdução do Ecossistema de Assessorias como Núcleo do Produto

O domínio institucional introduz a **Assessoria Esportiva** como ator principal do sistema,
responsável por gestão de atletas, distribuição de tokens, organização de campeonatos,
monitoramento de performance e participação em clearing inter-institucional.

Este domínio é isolado do domínio social existente e integra-se com:
Tracking Domain, Challenges Domain, Gamification Domain e Wallet Domain.

### 7.1 Bounded Contexts

#### 7.1.1 Institution Core Context

Responsável pela identidade institucional e estrutura organizacional.

**Entidades:**

| Entidade | Campos Principais | Descrição |
|----------|-------------------|-----------|
| Institution | id, name, status (pending/approved/suspended), verification_level, created_at | Assessoria esportiva |
| InstitutionMember | user_id, institution_id, role, joined_at | Vínculo usuário-instituição |

**Roles:** ADMIN_MASTER, PROFESSOR, ASSISTANT, ATHLETE

**Invariantes:**
- Um usuário pode pertencer a apenas UMA instituição ativa
- Instituições precisam ser aprovadas antes de operar
- Apenas ADMIN_MASTER pode gerenciar roles

#### 7.1.2 Institutional Wallet Context

Responsável pelo sistema econômico institucional.

**Entidades:**

| Entidade | Campos Principais | Descrição |
|----------|-------------------|-----------|
| InstitutionTokenInventory | institution_id, available_tokens | Estoque de tokens da assessoria (nunca negativo) |
| UserInstitutionWallet | user_id, institution_id, balance_total, balance_redeemable | Carteira do atleta vinculada à instituição |
| TokenLedgerEntry | id, user_id, institution_id, category, amount, reference_id, created_at | Registro imutável de lifecycle do token |

**Categorias do Ledger:** ISSUE, STAKE_LOCK, STAKE_REFUND, PRIZE_PENDING, PRIZE_CLEARED, BURN

**Invariantes:**
- Tokens só podem ser usados dentro da instituição atual
- Apenas tokens "redeemable" podem ser trocados
- Toda mudança deve passar pelo ledger (append-only)

#### 7.1.3 Cross-Institution Clearing Context

Responsável pela compensação semanal entre instituições.

**Entidades:**

| Entidade | Campos Principais | Descrição |
|----------|-------------------|-----------|
| ClearingWeek | id, start_date, end_date | Período semanal de compensação |
| ClearingCase | id, week_id, from_institution_id, to_institution_id, tokens_amount, status, deadline_at | Obrigação de compensação |
| ClearingCaseEvent | case_id, actor_institution_id, event_type, created_at | Auditoria de confirmações |

**Status do ClearingCase:** OPEN, AWAITING_CONFIRMATIONS, PAID_CONFIRMED, DISPUTED, EXPIRED

**Invariantes:**
- Clearing é agregado semanalmente
- Liberação de tokens ocorre somente após dupla confirmação
- A plataforma não intervém no processo

#### 7.1.4 Championship Context

Responsável pelas competições institucionais.

**Entidades:**

| Entidade | Campos Principais | Descrição |
|----------|-------------------|-----------|
| Championship | id, host_institution_id, name, start_at, end_at, requires_badge | Campeonato institucional |
| ChampionshipInvitation | championship_id, institution_id, status | Convite para instituições |
| ChampionshipParticipant | championship_id, user_id, institution_id, status | Participação do atleta |
| ChampionshipBadge | championship_id, user_id, expires_at | Passe temporário de participação |

**Invariantes:**
- Apenas instituições podem criar campeonatos
- Badge expira ao final do campeonato
- Participação depende da instituição do atleta

### 7.2 Relacionamentos entre Contextos

```
Institution Core ──── Wallet
    │                   │
    │                   ├── Challenges (stake institucional, pending clearing)
    │                   │
    │                   └── Clearing (resolve pendentes, pending → redeemable)
    │
    └── Championships (pertencem a instituições, participação por vínculo)
```

### 7.3 Fluxos Críticos

**Troca de Instituição:**
1. Usuário inicia troca → 2. Tokens não resgatados são queimados → 3. Vínculo atualizado

**Desafio Cross-Institucional:**
1. Stake travado → 2. Vencedor recebe tokens pendentes → 3. Clearing case criado → 4. Após liquidação, tokens liberados

**Emissão de Tokens:**
1. Professor gera QR intent → 2. Atleta escaneia → 3. Inventory reduz → 4. Carteira aumenta

### 7.4 Integração com Sistema Existente

O domínio institucional integra-se com Edge Functions existentes:
- `verify-session` (tracking)
- `settle-challenge` (gamification)
- `submit-analytics` (analytics pipeline)
- `evaluate-badges` (badge evaluation)

Nenhuma alteração é feita no tracking pipeline.

### 7.5 Garantias de Consistência

- Ledger append-only
- Edge Functions para lógica crítica
- RLS estrito por instituição
- Constraints de integridade referencial

### 7.6 Evoluções Futuras Previstas

- Score de reputação institucional
- Sistema de ranking global de assessorias
- Marketplace de eventos esportivos

---

## 8. PROGRESSION SYSTEM

> **Origem:** DECISAO 017 (Progression Engine) + DECISAO 044 (Modelo Final Phase 20)
> **Spec completa:** `PROGRESSION_SPEC.md`

O sistema de progressão é composto por 4 pilares independentes dos OmniCoins.

### 8.1 Pilares

```
┌───────────────────────────────────────────────────────────┐
│                    Progression Engine                      │
├─────────┬──────────┬─────────────┬────────────────────────┤
│   XP    │  Streak  │   Badges    │   Goals (Metas)        │
│         │          │             │                        │
│ +sessão │ diário   │ 30 MVP      │ semanal automática     │
│ +badge  │ semanal  │ 4 tiers     │ distância ou tempo     │
│ +missão │ mensal   │ permanentes │ baseline 4 semanas     │
│ +desafio│ freeze   │ secret      │ auto-check verificado  │
│ +camp.  │ 1/7 dias │             │                        │
└────┬────┴────┬─────┴──────┬──────┴───────────┬────────────┘
     │         │            │                  │
     ▼         ▼            ▼                  ▼
  Nível    Milestones   Badge Awards       +40 XP/semana
  (N^1.5)  (XP+Coins)  (XP por tier)
```

### 8.2 Relação XP × OmniCoins

| Aspecto | XP | OmniCoins |
|---------|------|-----------|
| Natureza | Progressão permanente — nunca decresce | Moeda virtual — ganha e gasta |
| Uso | Determina nível, desbloqueia badges | Customizações visuais |
| Conversão | **PROIBIDA** (GAMIFICATION_POLICY §2) | — |
| Fonte | Sessões, badges, missões, streaks, desafios, campeonatos | Sessões, desafios, streaks, PRs |

### 8.3 Arquitetura de Domínio

```
domain/
├── entities/
│   ├── profile_progress_entity.dart     # XP total, nível, season XP
│   ├── xp_transaction_entity.dart       # Log imutável de créditos XP
│   ├── badge_entity.dart                # Definição de badge (catálogo)
│   ├── badge_award_entity.dart          # Badge desbloqueado por usuário
│   ├── mission_entity.dart              # Template de missão
│   ├── mission_progress_entity.dart     # Progresso do usuário em missão
│   ├── season_entity.dart               # Metadados da temporada
│   └── season_progress_entity.dart      # Progresso sazonal do usuário
│
├── usecases/gamification/
│   ├── award_xp_for_workout.dart        # Sessão → XP (com daily cap)
│   ├── evaluate_badges.dart             # Sessão → badges desbloqueados
│   ├── create_daily_missions.dart       # Clock → novas missões diárias
│   ├── update_mission_progress.dart     # Sessão → missões atualizadas
│   └── claim_rewards.dart               # Missão/badge → crédito XP+Coins
│
├── repositories/
│   ├── i_profile_progress_repo.dart
│   ├── i_xp_transaction_repo.dart
│   ├── i_badge_repo.dart
│   └── i_mission_repo.dart
│
└── failures/
    └── gamification_failure.dart         # Sealed: unverifiedSession, dailyLimitReached, etc.
```

### 8.4 Pipeline Pós-Sessão (Progressão)

```
Sessão verificada finalizada
       │
       ▼
  [1] AwardXpForWorkout
       │ → calcula sessionXp (base + dist + dur + HR)
       │ → aplica daily cap (1000 XP/dia)
       │ → grava XpTransaction (append-only)
       │ → atualiza ProfileProgress (XP total, nível)
       │
       ▼
  [2] EvaluateBadges
       │ → avalia badges não-desbloqueados
       │ → desbloqueia elegíveis
       │ → crédito XP por tier (50/100/200/500)
       │
       ▼
  [3] UpdateMissionProgress
       │ → atualiza missões ativas
       │ → marca completadas → ClaimRewards
       │
       ▼
  [4] Check Streak (diário/semanal/mensal)
       │ → incrementa/reseta contador
       │ → aplica freeze se disponível
       │ → crédito XP+Coins em milestones
       │
       ▼
  [5] Check Weekly Goal
       │ → soma sessões da semana vs meta
       │ → se atingida → +40 XP
```

### 8.5 Goals (Metas Semanais)

| Aspecto | Valor |
|---------|-------|
| Geração | Automática: segunda 00:00 UTC |
| Baseline | Média das 4 últimas semanas (default: 10 km / 60 min) |
| Fator | 1.0× ou 1.1× (alternado por semana) |
| Check | Soma de sessões verificadas vs meta |
| Recompensa | +40 XP (sem penalidade ao falhar) |
| Fonte de dados | `profile_progress.weekly_distance_m` ou `weekly_moving_ms` |

### 8.6 Integração com Assessoria

- XP, nível, badges e streaks pertencem ao **atleta**, não à assessoria
- Troca de assessoria preserva toda a progressão
- Rankings de assessoria usam **Season XP** (não XP total)
- Professor visualiza progresso do atleta no dashboard
- Campeonatos creditam XP ao atleta individual

### 8.7 Anti-Exploit

| Vetor | Mitigação |
|-------|-----------|
| Farm de sessões curtas | `baseXp` = 20 fixo; sem bônus abaixo de 200m |
| Farm de XP via badges | Cap 500 XP/dia para fontes não-sessão |
| Manipulação de streak | Cálculo sempre em UTC midnight |
| Repeat mission exploit | `maxCompletions` + `cooldownMs` |
| Multi-account | Desafios requerem auth; anti-cheat cross-validates |

---

## 9. MONETIZATION MODEL (Loja-Safe)

> **Origem:** DECISAO 046 — Modelo de Monetização Loja-Safe (Phase 21)
> **Referência:** GAMIFICATION_POLICY.md, DECISAO 016, DECISAO 038

O modelo de receita é **B2B SaaS** (plataforma → assessoria). O app **nunca processa pagamento**
e **nunca mostra valores monetários** ao usuário.

### 9.1 Fluxo de Monetização

```
                    EXTERNO AO APP
┌──────────────────────────────────────────────────┐
│  Assessoria                 Plataforma           │
│     │    contrato/portal web    │                 │
│     ├──────────────────────────►│                 │
│     │    pagamento (Pix/boleto) │                 │
│     ├──────────────────────────►│                 │
│     │    NF-e (serviço software)│                 │
│     │◄────────────────────────  │                 │
│     │                           │                 │
│     │   admin credita inventory │                 │
│     │     coaching_token_inv.   │                 │
│     │◄──────────(DB direto)──── │                 │
└──────────────────────────────────────────────────┘

                    DENTRO DO APP
┌──────────────────────────────────────────────────┐
│  Staff              Atleta                       │
│     │  QR distribute    │                        │
│     ├──────────────────►│                        │
│     │  (token-intent)   │                        │
│     │                   │  usa em desafios       │
│     │                   ├──────► gamificação     │
│     │                   │  personalização        │
│     │                   ├──────► loja visual     │
└──────────────────────────────────────────────────┘
```

### 9.2 Invariantes de Compliance

| # | Invariante | Verificação |
|---|-----------|-------------|
| M1 | App NUNCA mostra preços em R$/USD/€ | Grep `R\$|USD|\$|€` em lib/ = 0 |
| M2 | App NUNCA tem botão "Comprar" | Grep `comprar|buy|purchase` em UI = 0 |
| M3 | App NUNCA processa pagamento | Zero payment SDK, zero IAP |
| M4 | App NUNCA menciona "venda", "preço" | Vocabulário controlado (GAMIFICATION_POLICY §5) |
| M5 | Atleta NUNCA adquire créditos | `token-consume-intent` requer intent criado por staff |
| M6 | Créditos siloados por assessoria | `coaching_token_inventory.group_id` é FK; sem transfer cross-group |
| M7 | OmniCoins ≠ valor monetário | GAMIFICATION_POLICY §2 em vigor |

### 9.3 Componentes Existentes (sem alteração)

| Componente | Papel no modelo |
|------------|-----------------|
| `coaching_token_inventory` | Estoque de créditos por assessoria (alimentado externamente) |
| `token-create-intent` | Staff cria intent QR para distribuir créditos |
| `token-consume-intent` | Atleta escaneia QR e recebe créditos |
| `coin_ledger` | Registro append-only de todas as movimentações |
| `clearing_cases` | Compensação inter-assessoria (in-app, sem dinheiro) |
| `wallets` | Créditos disponíveis + pendentes do atleta |

### 9.4 O que o App Mostra vs O que Não Mostra

| Mostra | Não mostra |
|--------|-----------|
| "Estoque: 500 OmniCoins" | "R$ 250,00" |
| "Inscrição: 25 OmniCoins" | "Taxa: R$ 12,50" |
| "Distribuir créditos" | "Vender créditos" |
| "Recompensa: 15 OmniCoins" | "Prêmio: R$ 7,50" |

---

*Documento gerado na Sprint 1.2*
