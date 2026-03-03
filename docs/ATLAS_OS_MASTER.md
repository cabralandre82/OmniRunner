# ATLAS OS MASTER — Pré-leitura para Blocos OS

> Mapa real do codebase: telas, tabelas, infra QR, padrões de arquitetura, e análise reaproveitar vs criar.
> Nenhum path inventado — tudo verificado via leitura direta do repositório.

---

## 1. Telas Atuais — App Flutter

### 1.1 Staff (assessoria management)

| Tela | Path | Propósito | Tabelas/RPCs | Role |
|---|---|---|---|---|
| Staff Dashboard | `lib/presentation/screens/staff_dashboard_screen.dart` | Home staff: 6 cards de gestão (atletas, confirmações, performance, campeonatos, créditos, admin) | `coaching_groups`, `coaching_members`, `i_wallet_repo` | admin_master, coach |
| Setup | `staff_setup_screen.dart` | Onboarding: criar assessoria ou entrar como coach | RPC `fn_create_assessoria`, `fn_search_coaching_groups` | ASSESSORIA_STAFF (onboarding) |
| Join Requests | `staff_join_requests_screen.dart` | Aprovar/rejeitar pedidos de entrada | `coaching_join_requests` | admin_master, coach |
| Performance | `staff_performance_screen.dart` | 4 KPIs: atletas ativos, corridas semanais, desafios, campeonatos | `coaching_members`, `sessions`, `challenges`, `championship_participants` | admin_master, coach |
| Retention | `staff_retention_dashboard_screen.dart` | DAU/WAU gauge, retenção semanal 4w, insights | `sessions`, `coaching_members` | admin_master, coach |
| Weekly Report | `staff_weekly_report_screen.dart` | Resumo semanal: corridas, distância, progressão, ranking interno | `coaching_members`, `sessions` | admin_master, coach |
| Credits | `staff_credits_screen.dart` | Inventário OmniCoin, histórico de distribuição | `coin_ledger`, wallet | admin_master, coach |
| Disputes | `staff_disputes_screen.dart` | Clearing cases: confirmar envio/recebimento, disputas | `clearing_cases` | admin_master, coach |
| QR Hub | `staff_qr_hub_screen.dart` | Hub central: 3 operações QR (emitir, queimar, badge) | Navega para Generate/Scan | admin_master, coach, assistant |
| Generate QR | `staff_generate_qr_screen.dart` | Gera QR com payload assinado via token-create-intent | Edge Fn `token-create-intent`, `token_intents` | admin_master, coach, assistant |
| Scan QR | `staff_scan_qr_screen.dart` | Escaneia QR do atleta, consome intent | Edge Fn `token-consume-intent` | admin_master, coach, assistant |
| Championship Templates | `staff_championship_templates_screen.dart` | CRUD de templates de campeonato | `championship_templates`, Edge Fn `champ-create` | admin_master, coach |
| Championship Manage | `staff_championship_manage_screen.dart` | Gerenciar campeonato: abrir, convidar, ver participantes | Edge Fns `champ-open/invite/accept-invite/participant-list` | admin_master, coach |
| Challenge Invites | `staff_challenge_invites_screen.dart` | Convites de desafio de outras assessorias | `challenge_group_invites` | admin_master, coach |
| Championship Invites | `staff_championship_invites_screen.dart` | Convites de campeonato recebidos | `championship_invites` | admin_master, coach |
| Partner Assessorias | `partner_assessorias_screen.dart` | Parcerias: assessorias atuais e disponíveis | `coaching_groups`, partnership tables | admin_master, coach |

### 1.2 Atleta

| Tela | Path | Propósito | Tabelas/RPCs | Role |
|---|---|---|---|---|
| Athlete Dashboard | `athlete_dashboard_screen.dart` | Home atleta: 6 cards (desafios, assessoria, progresso, wallet, feed, campeonatos) | `coaching_groups`, `coaching_members` | athlete |
| My Assessoria | `my_assessoria_screen.dart` | Assessoria atual, trocar assessoria | `coaching_groups`, `coaching_members` | athlete |
| Assessoria Feed | `assessoria_feed_screen.dart` | Feed social da assessoria (corridas, badges, vitórias) | `assessoria_feed` | athlete |
| Join Assessoria | `join_assessoria_screen.dart` | Onboarding: busca, QR ou código para entrar | RPC `fn_search_coaching_groups`, `fn_switch_assessoria` | athlete (onboarding) |
| Coaching Groups | `coaching_groups_screen.dart` | Lista grupos do usuário | `coaching_groups`, `coaching_members` | athlete |
| Group Details | `coaching_group_details_screen.dart` | Info do grupo + lista de membros | `coaching_groups`, `coaching_members` | all |

### 1.3 Outras relevantes

| Tela | Path | Propósito |
|---|---|---|
| Home | `home_screen.dart` | Bottom-nav shell; roteia athlete vs staff por role |
| Invite QR | `invite_qr_screen.dart` | QR permanente com invite_code do grupo (sem nonce/expiração) |
| More | `more_screen.dart` | Menu com tiles para QR scanner, wallet, etc. |

---

## 2. Páginas Atuais — Portal Next.js

### 2.1 Staff Pages

| Página | Path | Propósito | Tabelas | Role |
|---|---|---|---|---|
| Dashboard | `/dashboard` | KPIs overview: atletas, sessões, créditos, trends | `coaching_inventory`, `coaching_members`, `sessions` | all staff |
| Athletes | `/athletes` | Lista atletas com stats | `coaching_members`, `sessions`, `profiles`, `athlete_verification` | all staff |
| Verification | `/verification` | Painel de verificação: trust scores, flags | `athlete_verification` | all staff |
| Engagement | `/engagement` | DAU/WAU/MAU, sessões, desafios | `coaching_members`, `sessions`, `challenges` | all staff |
| Settings | `/settings` | Team management, auto-topup, branding, gateway | `coaching_members`, `profiles`, `coaching_groups` | all staff |
| Custody | `/custody` | Conta custódia: depósitos, retiradas, ledger | `custody_accounts`, `custody_deposits`, `coin_ledger` | admin_master |
| Clearing | `/clearing` | Eventos de clearing e settlements | `clearing_events`, `clearing_settlements` | admin_master, coach |
| Swap | `/swap` | Marketplace de swap de lastro | `swap_orders`, `custody_accounts` | admin_master |
| FX | `/fx` | Câmbio: depósitos/retiradas USD com simulador | `fx_operations` | admin_master |
| Badges | `/badges` | Inventário e compra de badge packs | `coaching_badge_inventory`, `billing_products` | admin_master, coach |
| Audit | `/audit` | Trail completo de clearing | `clearing_events`, `clearing_settlements` | admin_master, coach |
| Distributions | `/distributions` | Ledger de distribuição de OmniCoins | `coin_ledger`, `coaching_members` | admin_master, coach |

### 2.2 API Routes

| Route | Path | Propósito |
|---|---|---|
| distribute-coins | `/api/distribute-coins` | Distribuir OmniCoins para atletas |
| clearing | `/api/clearing` | Ciclo de clearing (burn + settlement) |
| custody | `/api/custody` | Depósito/retirada de custódia |
| swap | `/api/swap` | Criar/aceitar ordens de swap |
| team/invite | `/api/team/invite` | Convidar staff |
| team/remove | `/api/team/remove` | Remover membro |
| export/athletes | `/api/export/athletes` | Export CSV de atletas |
| verification/evaluate | `/api/verification/evaluate` | Avaliar verificação de atleta |
| branding | `/api/branding` | Upload logo/cores da assessoria |
| gateway-preference | `/api/gateway-preference` | Preferência de gateway de pagamento |
| auto-topup | `/api/auto-topup` | Config de auto-topup |
| health | `/api/health` | Health check + invariant check |

---

## 3. Tabelas DB Relevantes

### 3.1 Core Coaching

| Tabela | PK | Key Columns | UNIQUE | Indexes |
|---|---|---|---|---|
| `coaching_groups` | `id` uuid | `name`, `coach_user_id`, `city`, `invite_code`, `created_at_ms` | — | PK only |
| `coaching_members` | `id` uuid | `user_id`, `group_id`, `display_name`, `role`, `joined_at_ms` | `(group_id, user_id)` | `idx_coaching_members_group(group_id, role)`, `idx_coaching_members_user(user_id)` |
| `coaching_invites` | `id` uuid | `group_id`, `invited_user_id`, `status`, `expires_at_ms` | — | — |
| `coaching_join_requests` | `id` uuid | `group_id`, `user_id`, `status`, `requested_role` | partial: `(group_id, user_id) WHERE status='pending'` | `idx_join_requests_one_pending` |

### 3.2 Activity

| Tabela | PK | Key Columns | Indexes |
|---|---|---|---|
| `sessions` | `id` uuid | `user_id`, `status` (3=completed), `start_time_ms`, `total_distance_m`, `is_verified` | `idx_sessions_user(user_id, start_time_ms DESC)`, `idx_sessions_engagement(user_id, start_time_ms) WHERE status>=3 AND is_verified` |
| `analytics_submissions` | `id` uuid | `session_id`, `user_id`, `group_id`, `distance_m`, `start_time_ms` | `idx_submissions_group_time(group_id, start_time_ms DESC)` |
| `profile_progress` | `user_id` uuid (1:1) | `daily_streak_count`, `weekly_session_count`, `lifetime_distance_m` | PK only |

### 3.3 KPI Snapshots (STEP 05)

| Tabela | PK | UNIQUE | Indexes |
|---|---|---|---|
| `coaching_kpis_daily` | `id` uuid | `(group_id, day)` | `idx_kpis_daily_group_day(group_id, day DESC)` |
| `coaching_athlete_kpis_daily` | `id` uuid | `(group_id, user_id, day)` | `idx_athlete_kpis_group_day`, `idx_athlete_kpis_user_day`, `idx_athlete_kpis_risk` |
| `coaching_alerts` | `id` uuid | `(group_id, user_id, day, alert_type)` | `idx_alerts_group_unread`, `idx_alerts_user` |

### 3.4 Tokens / Economy

| Tabela | PK | Key Columns | UNIQUE |
|---|---|---|---|
| `token_intents` | `id` uuid | `group_id`, `type`, `target_user_id`, `nonce`, `status`, `expires_at` | `nonce` |
| `coaching_token_inventory` | `group_id` uuid (1:1) | `available_tokens`, `lifetime_issued`, `lifetime_burned` | PK |

### 3.5 Athlete Data

| Tabela | PK | Key Columns |
|---|---|---|
| `athlete_baselines` | `id` uuid | `user_id`, `group_id`, `metric`, `value` |
| `athlete_trends` | `id` uuid | `user_id`, `group_id`, `metric`, `period`, `direction` |
| `athlete_verification` | `user_id` uuid (1:1) | `verification_status`, `trust_score`, `calibration_valid_runs` |
| `coach_insights` | `id` uuid | `group_id`, `target_user_id`, `type`, `priority`, `title` |

---

## 4. Infraestrutura QR Existente

### 4.1 Pacotes

| Pacote | Versão | Função |
|---|---|---|
| `qr_flutter` | ^4.1.0 | Renderiza QR code como widget (`QrImageView`) |
| `mobile_scanner` | ^7.2.0 | Câmera para scan (`MobileScanner`) |

### 4.2 Fluxo de Geração (Staff → QR)

```
StaffQrHubScreen → seleciona operação (ISSUE/BURN/BADGE)
    │
    ▼
StaffGenerateQrScreen → StaffQrBloc dispatches GenerateQr
    │
    ▼
ITokenIntentRepo.createIntent() → Edge Fn token-create-intent
    │   ├── Auth JWT + rate limit (60/min)
    │   ├── Valida role staff em coaching_members
    │   ├── Check daily limits + inventory
    │   └── INSERT token_intents (status=OPEN, nonce, expires_at)
    │
    ▼
Client recebe {intent_id, nonce, expires_at}
    │
    ▼
StaffQrPayload.encode() → JSON → utf8 → base64Url → QrImageView
    │
    ▼
Countdown timer (TTL) → expirado? placeholder cinza
```

### 4.3 Fluxo de Scan (Atleta/Staff → Consumo)

```
StaffScanQrScreen → MobileScanner.onDetect
    │
    ▼
StaffQrPayload.decode(base64Url) → validação local (isExpired)
    │
    ▼
ITokenIntentRepo.consumeIntent(payload) → Edge Fn token-consume-intent
    │   ├── Find intent by nonce
    │   ├── Validate OPEN + not expired
    │   ├── Check affiliation (athlete in group)
    │   ├── Atomic: UPDATE status=CONSUMED WHERE status=OPEN
    │   └── Side-effect por tipo:
    │       ├── ISSUE: decrement_inventory → increment_wallet → coin_ledger
    │       ├── BURN: execute_burn_atomic (wallet debit + clearing)
    │       └── BADGE: fn_decrement_badge_inventory → championship enrollment
    │
    ▼
SnackBar (sucesso/erro) → Navigator.pop()
```

### 4.4 Payload do QR

```json
{
  "iid": "intent_uuid",
  "typ": "ISSUE_TO_ATHLETE",
  "gid": "group_uuid",
  "amt": 10,
  "non": "nonce_string",
  "exp": 1709503200000,
  "cid": "championship_uuid (optional)"
}
```

### 4.5 Fluxo alternativo: Invite QR

`InviteQrScreen` renderiza URL permanente `https://omnirunner.app/invite/{code}` como QR. Sem nonce, sem expiração, sem edge function. O `invite_code` é atributo da `coaching_groups`.

---

## 5. Padrões de Arquitetura

### 5.1 Diagrama de Camadas

```
┌─ PRESENTATION ─────────────────────────────────────┐
│  Screen (StatelessWidget) → BLocProvider → BLoC     │
│  BLoC: sealed Event → sealed State, injects UseCases│
└────────────────────────┬───────────────────────────┘
                         │ depends on
┌─ DOMAIN ───────────────┼───────────────────────────┐
│  Entity (Equatable)    UseCase (final class + call) │
│  abstract interface class IRepo                     │
└────────────────────────┬───────────────────────────┘
                         │ implements
┌─ DATA ─────────────────┼───────────────────────────┐
│  IsarXxxRepo           SupabaseXxxRemoteSource      │
│  Isar models           Supabase queries             │
└─────────────────────────────────────────────────────┘
         ▲ wired by GetIt (sl) in service_locator.dart
```

### 5.2 Convenções por Camada

| Camada | Padrão | Naming | Exemplo Real |
|---|---|---|---|
| Entity | `final class extends Equatable`, `copyWith`, `props` | `xxx_entity.dart` | `coaching_member_entity.dart` |
| Repo Interface | `abstract interface class` | `i_xxx_repo.dart` | `i_coaching_group_repo.dart` |
| Repo Impl | `final class implements IXxxRepo` | `isar_xxx_repo.dart` | `isar_coaching_group_repo.dart` |
| UseCase | `final class` + `call()` method | `verb_noun.dart` | `accept_coaching_invite.dart` |
| BLoC | 3 files: `*_bloc.dart`, `*_event.dart`, `*_state.dart` | `feature_name/` dir | `coaching_group_details/` |
| Screen | `StatelessWidget` + `BlocBuilder` com `switch` exaustivo | `xxx_screen.dart` | `coaching_groups_screen.dart` |

### 5.3 DI: GetIt

- File: `lib/core/service_locator.dart`
- Accessor: `final GetIt sl = GetIt.instance;`
- Ordem: Infrastructure → Datasources → Repos → UseCases → BLoCs
- Repos: `registerLazySingleton`
- UseCases + BLoCs: `registerFactory`

### 5.4 Navegação

- `Navigator.of(context).push(MaterialPageRoute(...))` — imperativo, sem GoRouter
- `BlocProvider` wraps a tela no ponto de navegação
- `AuthGate` como entry point com roteamento por role

### 5.5 Como Adicionar Feature Nova (Passo a Passo)

1. **Entity** em `lib/domain/entities/`
2. **Repo Interface** em `lib/domain/repositories/i_xxx_repo.dart`
3. **Repo Impl** em `lib/data/repositories_impl/isar_xxx_repo.dart`
4. **UseCase(s)** em `lib/domain/usecases/feature_name/`
5. **BLoC** (3 files) em `lib/presentation/blocs/feature_name/`
6. **Registrar** tudo em `service_locator.dart`
7. **Screen** em `lib/presentation/screens/`
8. **Tests**: UseCase tests + BLoC tests

---

## 6. Análise: Reaproveitar vs Criar (OS-01)

### 6.1 REAPROVEITAR (já existe)

| Componente | O que é | Onde | Como usar no OS-01 |
|---|---|---|---|
| QR payload encode/decode | `StaffQrPayload` + base64url serialization | `staff_generate_qr_screen.dart` | Criar `CheckinPayload` seguindo mesmo padrão |
| QR rendering | `QrImageView` (qr_flutter ^4.1.0) | `staff_generate_qr_screen.dart` | Usar diretamente na tela "Meu QR de check-in" |
| QR scanning | `MobileScanner` + one-shot guard | `staff_scan_qr_screen.dart` | Template direto para "Scanner de presença" |
| StaffQrBloc pattern | Event/State/Bloc + countdown timer | `lib/presentation/blocs/staff_qr/` | Template para `AttendanceBloc` |
| SnackBar feedback | Sucesso (verde) / erro (vermelho) / warning | Todos screens QR | Mesmo padrão para feedback de presença |
| `coaching_members` table | Membership + roles | Schema existente | Filtrar atletas do grupo, validar staff |
| `coaching_groups.invite_code` | Código do grupo | Schema existente | Não precisa para OS-01, mas já existe |
| RLS patterns | `cm.role IN ('admin_master','coach','assistant')` | 15+ policies existentes | Copiar para policies de training/attendance |
| Entity/Repo/Bloc architecture | Clean arch completa | Todo codebase | Seguir exatamente o mesmo padrão |
| Service Locator | GetIt com registros ordenados | `service_locator.dart` | Adicionar registros de training repos/usecases/blocs |
| Edge Function skeleton | Auth + rate limit + validation + atomic state | `token-create-intent`, `token-consume-intent` | Template para `fn_mark_attendance` ou edge fn de check-in |
| Hub screen pattern | Grid de cards de operação | `staff_qr_hub_screen.dart` | Adicionar card "Presença" no hub OU criar Agenda screen |

### 6.2 CRIAR (não existe)

| Componente | O que criar | Onde | Complexidade |
|---|---|---|---|
| **Tabela** `coaching_training_sessions` | Agenda de treinos | Migration SQL | Baixa |
| **Tabela** `coaching_training_attendance` | Presença/check-in | Migration SQL | Baixa |
| **RLS** para ambas tabelas | 5 policies (ver spec OS-01) | Migration SQL | Média |
| **RPC** `fn_mark_attendance` | Marcar presença com validação | Migration SQL | Média |
| **RPC** `fn_issue_checkin_token` (ou edge fn) | Gerar payload assinado para QR de check-in | Edge Fn ou SQL function | Média |
| **Entity** `TrainingSessionEntity` | Entidade de treino | `domain/entities/` | Baixa |
| **Entity** `TrainingAttendanceEntity` | Entidade de presença | `domain/entities/` | Baixa |
| **Repo** `ITrainingSessionRepo` + impl | CRUD de treinos | `domain/repositories/` + `data/` | Média |
| **Repo** `ITrainingAttendanceRepo` + impl | CRUD de presença | `domain/repositories/` + `data/` | Média |
| **UseCases** (4-5) | CreateTraining, ListTrainings, MarkAttendance, ListAttendance, CancelTraining | `domain/usecases/training/` | Média |
| **BLoC** TrainingListBloc | Lista/filtro de treinos | `presentation/blocs/training_list/` | Média |
| **BLoC** TrainingDetailBloc | Detalhe + presença | `presentation/blocs/training_detail/` | Média |
| **BLoC** CheckinBloc | Geração/consumo de QR de check-in | `presentation/blocs/checkin/` | Média |
| **Tela** StaffTrainingListScreen | Agenda com filtro por período | `presentation/screens/` | Média |
| **Tela** StaffTrainingCreateScreen | Formulário de criação/edição | `presentation/screens/` | Média |
| **Tela** StaffTrainingDetailScreen | Detalhe + lista presença + scan | `presentation/screens/` | Média |
| **Tela** AthleteTrainingListScreen | Meus treinos (próximos + histórico) | `presentation/screens/` | Baixa |
| **Tela** AthleteCheckinQrScreen | QR de check-in do atleta | `presentation/screens/` | Baixa |
| **Tela** AthleteAttendanceScreen | Minha presença | `presentation/screens/` | Baixa |
| **Portal** Attendance Report page | Filtros + tabela + export CSV | `portal/src/app/(portal)/attendance/` | Média |
| **Portal** Training Detail page | Presença + % metrics | `portal/src/app/(portal)/attendance/[id]/` | Baixa |
| **Docs** (4) | OS01_SCHEMA_RLS, QR_CHECKIN_SPEC, APP_FLOWS, PORTAL_REPORTS | `docs/` | Baixa |

### 6.3 Decisão-chave: Fluxo QR para Attendance

| Opção | Descrição | Prós | Contras |
|---|---|---|---|
| **A: Token Intent** (reuse full) | Atleta gera intent via edge fn, staff escaneia | Reutiliza 90% da infra QR; nonce+expiração+idempotência grátis | Overkill para presença simples; requer edge fn extra |
| **B: Session-scoped static QR** (reuse partial) | Staff exibe QR fixo do treino, atleta escaneia | Simples; sem edge fn para gerar | Requer validação server-side diferente; sem nonce por atleta |
| **C: RPC-based** (spec OS-01) | Atleta gera QR com payload assinado, staff escaneia e chama `fn_mark_attendance` | Seguro; nonce+TTL; validation via SQL RPC | Implementação mista (não reusa intent table) |

**Recomendação:** Opção C (alinhada com a spec OS-01) — o atleta gera o QR, o staff escaneia. Reutilizar o padrão de encode/decode/scan/countdown do token flow, mas com RPC SQL (`fn_mark_attendance`) em vez de edge function para consumo. Simples, auditável, e não polui a tabela `token_intents` com dados de presença.
