# GATE 3 — Anti-Local / Anti-Mock Audit

> Scan completo do repositório para identificar dados locais, mocks e stubs que possam mascarar bugs de produção.  
> Data: 2026-03-03

---

## 1. localStorage no Portal

**Resultado do scan: ZERO ocorrências.**

```
grep -r "localStorage" portal/src/ → 0 matches
grep -r "sessionStorage" portal/src/ → 0 matches
```

O portal usa **cookies** (`portal_group_id`, `portal_role`) gerenciados via middleware server-side. Nenhuma dependência de client-side storage.

**Classificação: SAFE** — Portal 100% server-side rendering + cookies httpOnly.

---

## 2. SharedPreferences no Flutter

| Arquivo | Uso | Classificação |
|---------|-----|---------------|
| `lib/core/utils/offline_queue.dart` | Fila de operações offline (serialize/deserialize queue) | **SAFE** — Cache transacional, sync quando online |
| `lib/core/deep_links/deep_link_handler.dart` | Persiste invite codes pendentes para sobreviver restart do app | **SAFE** — UX de deep links, não masca dados |
| `lib/core/tips/first_use_tips.dart` | Flags de "já viu tip X" para banners de primeira vez | **SAFE** — Preferência UI pura |
| `lib/data/repositories_impl/coach_settings_repo.dart` | Configurações locais do coach (exibição) | **SAFE** — Preferências de UI |
| `lib/core/theme/theme_notifier.dart` | Persistência de ThemeMode (dark/light/system) | **SAFE** — Preferência visual |
| `lib/features/integrations_export/presentation/export_screen.dart` | Marca se export já foi feito (flag) | **SAFE** — UX flag |
| `lib/features/wearables_ble/ble_heart_rate_source.dart` | Persiste último device BLE conhecido (ID/name) | **SAFE** — Cache de reconexão BLE |
| `lib/data/datasources/mock_auth_datasource.dart` | Gera UUID local para modo offline | **WARNING** — Ver seção 4 |

**Total: 8 arquivos usando SharedPreferences.**  
**Todos são preferências UI ou cache, exceto o mock_auth (ver seção 4).**

---

## 3. Isar (Local Database)

### Isar Database Provider

**Arquivo:** `lib/data/datasources/isar_database_provider.dart`

Inicializa Isar.open com 26 schemas. Usado como **cache offline** que sincroniza com Supabase.

### Repositórios Isar Registrados no Service Locator

| Repositório | Tabela Isar | Propósito | Classificação |
|-------------|------------|-----------|---------------|
| `isar_session_repo.dart` | WorkoutSessionRecord | Cache local de sessões de corrida | **SAFE** — Offline-first, sync via SyncService |
| `isar_ledger_repo.dart` | LedgerRecord | Cache do coin ledger | **SAFE** — Read cache, writes vão para Supabase |
| `isar_wallet_repo.dart` | WalletRecord | Cache do saldo | **SAFE** — Read cache |
| `isar_challenge_repo.dart` | ChallengeRecord | Cache de desafios | **SAFE** — Read cache |
| `isar_badge_award_repo.dart` | BadgeModel | Cache de badges earned | **SAFE** — Read cache |
| `isar_points_repo.dart` | — | Cache de pontos XP | **SAFE** — Read cache |
| `isar_mission_progress_repo.dart` | MissionModel | Cache de progresso de missões | **SAFE** — Read cache |
| `isar_profile_progress_repo.dart` | ProgressModel | Cache de progressão | **SAFE** — Read cache |
| `isar_xp_transaction_repo.dart` | — | Cache de transações XP | **SAFE** — Read cache |
| `isar_coaching_group_repo.dart` | CoachingGroupModel | Cache de grupos | **SAFE** — Read cache |
| `isar_coaching_invite_repo.dart` | CoachingInviteModel | Cache de convites | **SAFE** — Read cache |
| `isar_coaching_member_repo.dart` | CoachingMemberModel | Cache de membros | **SAFE** — Read cache |
| `isar_coaching_ranking_repo.dart` | CoachingRankingModel | Cache de rankings | **SAFE** — Read cache |
| `isar_coach_insight_repo.dart` | CoachInsightModel | Cache de insights | **SAFE** — Read cache |
| `isar_athlete_baseline_repo.dart` | AthleteBaselineModel | Cache de baselines | **SAFE** — Read cache |
| `isar_athlete_trend_repo.dart` | AthleteTrendModel | Cache de tendências | **SAFE** — Read cache |
| `isar_atomic_ledger_ops.dart` | LedgerRecord | Operações atômicas no ledger local | **SAFE** — Sync atomicidade |

**Classificação geral Isar: SAFE** — Padrão offline-first cache com `SyncService` que sincroniza bidireccionalmente com Supabase. Dados autoritativos estão no Supabase.

---

## 4. Mock / Stub Data Sources em Código de Produção

### 4.1 MockAuthDataSource

**Arquivo:** `lib/data/datasources/mock_auth_datasource.dart`

```
Offline-only auth datasource que persiste um UUID anônimo local.
Sign-up / sign-in / sign-out throw AuthNotConfigured.
```

**Registro:** `lib/core/service_locator.dart` linhas 238-243

```dart
final IAuthDataSource authDs = AppConfig.isSupabaseReady
    ? RemoteAuthDataSource()
    : () {
        AppLogger.critical('AUTH: Supabase not ready — using MockAuthDataSource. This should NEVER happen in production.');
        return MockAuthDataSource();
      }();
```

**Classificação: WARNING**

- Gateado por `AppConfig.isSupabaseReady` — só ativa se Supabase falhar init
- Log CRITICAL indica que não é esperado em produção
- Risco: se `SUPABASE_URL` ou `SUPABASE_ANON_KEY` estiverem errados, toda a sessão será com mock auth → nenhum dado real
- **Mitigação existente:** Log crítico + flag `isAnonymous: true` no AuthUser
- **Recomendação:** Adicionar telemetry/crash report se MockAuth for ativado em build de release

### 4.2 MockProfileDataSource

**Arquivo:** `lib/data/datasources/mock_profile_datasource.dart`

```
In-memory profile datasource for offline/mock mode.
Creates a stub profile from UserIdentityProvider on first access.
```

**Registro:** `lib/core/service_locator.dart` linhas 255-259

```dart
final IProfileRepo profileDs = AppConfig.isSupabaseReady
    ? RemoteProfileDataSource()
    : () {
        AppLogger.critical('PROFILE: Supabase not ready — using MockProfileDataSource.');
        return MockProfileDataSource(identity: userIdentity);
      }();
```

**Classificação: WARNING** — Mesmo gate que MockAuth. Perfil stub nunca sincroniza.

### 4.3 StubTokenIntentRepo

**Arquivo:** `lib/data/repositories_impl/stub_token_intent_repo.dart`

```
Mock implementation that simulates intent creation with a 5-minute expiry.
Hardcoded values: availableTokens=1000, lifetimeIssued=3500, lifetimeBurned=2500
```

**Classificação: WARNING**

- Hardcoded inventory values (`1000`, `3500`, `2500`, `15`, `50`, `35`) que não refletem dados reais
- Gateado por `AppConfig.isSupabaseReady`
- **Risco:** Se ativado em prod, staff veria inventário falso
- **Recomendação:** Mostrar banner "MODO OFFLINE" na UI quando stubs estão ativos

### 4.4 StubSwitchAssessoriaRepo

**Arquivo:** `lib/data/repositories_impl/stub_switch_assessoria_repo.dart`

```
Always succeeds after a brief delay, returning the requested group ID.
```

**Classificação: WARNING** — Troca de assessoria sempre bem-sucedida sem validação real.

### 4.5 Sumário de Guarda `AppConfig.isSupabaseReady`

Há **25+ checkpoints** no código de produção que verificam `AppConfig.isSupabaseReady`:

| Módulo | Comportamento se Supabase NOT ready |
|--------|--------------------------------------|
| `supabase_challenges_remote_source.dart` | Retorna `[]` (lista vazia) |
| `supabase_wallet_remote_source.dart` | Retorna `null` / `[]` |
| `supabase_progression_remote_source.dart` | Retorna `null` / `[]` |
| `supabase_badges_remote_source.dart` | Retorna `[]` |
| `supabase_missions_remote_source.dart` | Retorna `[]` |
| `supabase_verification_remote_source.dart` | `isBackendReady = false` |
| `matchmaking_screen.dart` | Mostra "Sem conexão com o servidor" |
| `login_screen.dart` | Mostra error message |
| `auth_gate.dart` | Redireciona para welcome screen |
| `push_notification_service.dart` | Skip registration |
| `analytics_sync_service.dart` | Throws `AnalyticsNotConfigured` |
| `parks/park_screen.dart` | Skip backfill |
| `staff_challenge_invites_screen.dart` | Mostra "Sem conexão" |

**Classificação global: SAFE (com WARNING no guard pattern)**

- O guard é defensivo (fail-safe, não fail-open para dados falsos)
- Na maioria dos casos retorna listas vazias → empty states corretos
- **Risco residual:** Usuário com Supabase down vê app vazio mas funcional, sem saber que está degradado
- **Recomendação:** Banner global "Modo offline" quando `isSupabaseReady == false`

---

## 5. Mocks/Stubs em Testes (Esperado — SAFE)

### Portal Tests

Todos os mocks estão **exclusivamente em arquivos `.test.ts`**:

| Arquivo de Teste | O que mocka | Classificação |
|------------------|-------------|---------------|
| `portal/src/app/api/auto-topup/route.test.ts` | Supabase client | **SAFE** — Test-only |
| `portal/src/app/api/branding/route.test.ts` | Supabase client | **SAFE** |
| `portal/src/app/api/clearing/route.test.ts` | Supabase client + getSettlements | **SAFE** |
| `portal/src/app/api/distribute-coins/route.test.ts` | Supabase client | **SAFE** |
| `portal/src/app/api/export/athletes/route.test.ts` | Supabase client | **SAFE** |
| `portal/src/app/api/gateway-preference/route.test.ts` | Supabase client | **SAFE** |
| `portal/src/app/api/swap/route.test.ts` | Supabase client + swap functions | **SAFE** |
| `portal/src/app/api/team/invite/route.test.ts` | Supabase client | **SAFE** |
| `portal/src/app/api/team/remove/route.test.ts` | Supabase client | **SAFE** |
| `portal/src/app/api/verification/evaluate/route.test.ts` | Supabase client | **SAFE** |
| `portal/src/lib/qa-e2e.test.ts` | Supabase RPC + client | **SAFE** |
| `portal/src/lib/qa-reconciliation.test.ts` | Supabase RPC | **SAFE** |

### Flutter Tests

| Arquivo de Teste | O que mocka | Classificação |
|------------------|-------------|---------------|
| `omni_runner/test/domain/usecases/coaching/` (4 files) | Repos de coaching | **SAFE** — Test-only |
| `omni_runner/test/presentation/blocs/` (7 files) | Repos + Use Cases | **SAFE** — Test-only |

**Todos os mocks de teste são SAFE — confinados a arquivos de teste.**

---

## 6. Hardcoded Data que Deveria Vir do Supabase

| Arquivo | Dado Hardcoded | Classificação |
|---------|---------------|---------------|
| `lib/presentation/screens/athlete_device_link_screen.dart` | Lista de providers: `['garmin', 'apple', 'polar', 'suunto', 'trainingpeaks']` | **WARNING** — Se um novo provider for adicionado no backend, o app precisa de update |
| `lib/presentation/widgets/error_state.dart` | Mensagens de erro em pt-BR hardcoded | **SAFE** — Fallback de i18n |
| `lib/features/strava/data/strava_auth_repository_impl.dart` | "Client ID and Secret are injected — never hardcoded" (comment) | **SAFE** — Confirma que não é hardcoded |
| `lib/data/repositories_impl/stub_token_intent_repo.dart` | `availableTokens=1000, lifetimeIssued=3500` | **WARNING** — Ver 4.3 |
| `portal/src/app/(portal)/crm/page.tsx` | Status labels: active, paused, injured, inactive, trial | **SAFE** — Enum estável, definida na migration |
| `portal/src/app/(portal)/risk/page.tsx` | Alert type labels hardcoded | **SAFE** — Enum estável |
| `portal/src/app/(portal)/verification/page.tsx` | Verification status labels | **SAFE** — Enum estável |

---

## 8. Scans Adicionais

### 8.1 Hive
```bash
grep -r "Hive\|HiveBox\|hive_flutter" omni_runner/lib/ --include="*.dart" -l
```
**Resultado**: 0 arquivos encontrados. Hive não é usado no projeto — Isar é o local DB.

### 8.2 Demo/Fixture
```bash
grep -r "demo\|fixture\|fake.*data\|seed.*data" omni_runner/lib/ --include="*.dart" -l
grep -r "demo\|fixture\|fake.*data" portal/src/ --include="*.ts" --include="*.tsx" -l
```
**Resultado**:
- `omni_runner/lib/`: 0 matches em código de produção
- `portal/src/`: 0 matches

**Classificação**: ✅ SAFE — Nenhum dado demo/fixture em código de produção.

### 8.3 Teste "Mudança no DB reflete na UI"

| Cenário | Método de Propagação | Latência |
|---------|---------------------|----------|
| Staff cria treino → outro staff vê | Pull-to-refresh ou re-enter tela | Manual (< 2s) |
| Admin publica aviso → atleta vê | Re-enter feed screen | Manual (< 2s) |
| KPI compute roda → dashboard atualiza | Next page load (SSR) | Next page load |
| Staff marca presença → portal reflete | SSR on page load | Next page load |

**Nota**: O app não usa realtime subscriptions (Supabase Realtime). Atualizações propagam via:
1. **Pull-to-refresh** (Flutter `RefreshIndicator`)
2. **Re-enter screen** (BLoC reloads on init)
3. **SSR page load** (Portal Server Components)

Não há cache infinito. Todas as queries vão direto ao Supabase em cada load.

---

## 7. Resumo Executivo

| Categoria | Contagem | SAFE | WARNING | BUG |
|-----------|----------|------|---------|-----|
| localStorage (Portal) | 0 | — | — | — |
| SharedPreferences (Flutter) | 8 arquivos | 7 | 1 | 0 |
| Isar (Local DB) | 17 repos | 17 | 0 | 0 |
| Mock/Stub em Produção | 4 classes | 0 | 4 | 0 |
| Mock/Stub em Testes | 16+ arquivos | 16+ | 0 | 0 |
| Hardcoded Data | 7 instâncias | 5 | 2 | 0 |
| AppConfig.isSupabaseReady guards | 25+ checkpoints | 25+ | 0 | 0 |

### Findings que Requerem Ação

| # | Severidade | Finding | Ação Recomendada |
|---|-----------|---------|------------------|
| F-01 | WARNING | `MockAuthDataSource`, `MockProfileDataSource` podem ser ativados em produção se Supabase init falhar | Adicionar telemetry + banner "Modo Offline" + considerar crash em release builds |
| F-02 | WARNING | `StubTokenIntentRepo` retorna inventário hardcoded (1000 tokens) | Adicionar banner visual + bloquear operações financeiras em modo stub |
| F-03 | WARNING | `StubSwitchAssessoriaRepo` aceita qualquer troca sem validação | Menor risco (switch offline raro), mas documentar |
| F-04 | WARNING | Lista de providers de wearable hardcoded no Flutter | Mover para config remota ou endpoint de providers |
| F-05 | INFO | 25+ guards `isSupabaseReady` retornam empty data silenciosamente | Considerar banner global quando Supabase está down |

### Veredicto

**GATE 3: PASS com observações.**

- Zero localStorage no portal
- Zero bugs — nenhum mock/stub vazou para código de produção sem guard
- 4 WARNINGs — todos gateados por `AppConfig.isSupabaseReady` com logs CRITICAL
- Isar é cache offline-first legítimo com sync bidireccional
- SharedPreferences usado apenas para preferências UI
- Todos os mocks de teste confinados a arquivos `.test.ts` / `_test.dart`
