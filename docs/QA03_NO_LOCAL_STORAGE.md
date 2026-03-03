# QA-03 — Anti-MOCK / Anti-localStorage (Auditoria Completa)

## Resumo

| Categoria | Total | Safe | Fix | Remove |
|-----------|-------|------|-----|--------|
| Mock/Stub repos em produção | 4 | 0 | **4** | 0 |
| SharedPreferences | 7 | 7 | 0 | 0 |
| Isar (cache local) | 20+ | 20+ | 0 | 0 |
| Hardcoded seed data | 1 | 1 | 0 | 0 |
| Env switch perigoso | 1 | 0 | **1** | 0 |
| Park stats fabricadas | 1 | 0 | **1** | 0 |
| Portal localStorage/mock | 0 | 0 | 0 | 0 |
| Edge Functions mock | 0 | 0 | 0 | 0 |

---

## Achados Detalhados

### P0 — Dados core escritos localmente / Stubs servem dados fake

| # | Arquivo:Linha | Padrão | O que faz | Decisão | Patch |
|---|---------------|--------|-----------|---------|-------|
| 1 | `core/service_locator.dart:226-228` | `MockAuthDataSource()` | Quando `AppConfig.isSupabaseReady == false`, auth usa UUID local persistente — usuário "logado" sem Supabase | **FIX** | Substituir por `throw StateError('Auth requires Supabase')` |
| 2 | `core/service_locator.dart:240-242` | `MockProfileDataSource()` | Profile fake em memória, nunca persiste no DB | **FIX** | Substituir por `throw StateError` |
| 3 | `core/service_locator.dart:364-366` | `StubSwitchAssessoriaRepo()` | Switch assessoria sempre "sucesso" sem backend | **FIX** | Substituir por `throw StateError` |
| 4 | `core/service_locator.dart:371-373` | `StubTokenIntentRepo()` | Retorna `availableTokens: 1000`, `lifetimeIssued: 3500` — **números fabricados** | **FIX** | Substituir por zeros ou `throw StateError` |

**Mitigação parcial existente**: `AuthGate` redireciona para `WelcomeScreen` quando Supabase não está pronto, impedindo o fluxo normal do usuário. Porém, deep links e serviços background podem atingir os stubs.

### P1 — Env switch que pode ativar mock silenciosamente

| # | Arquivo:Linha | Padrão | O que faz | Decisão | Patch |
|---|---------------|--------|-----------|---------|-------|
| 5 | `core/config/app_config.dart:48` | `backendMode => 'mock'` | Flag runtime: se `Supabase.initialize()` falhar (rede, env errado), `_supabaseInitOk = false` e toda a app opera em mock | **FIX** | Adicionar `AppLogger.critical()` quando `_supabaseInitOk == false` + banner vermelho na UI |

### P1 — Stats fabricadas exibidas como reais

| # | Arquivo:Linha | Padrão | O que faz | Decisão | Patch |
|---|---------------|--------|-----------|---------|-------|
| 6 | `features/parks/presentation/park_screen.dart:64-70` | `_mockRankings()`, `_mockCommunity()` | Exibe `runnersToday: 14, runnersWeek: 87, totalActivities: 1243` quando offline — parecem dados reais | **FIX** | Retornar `null` e mostrar "Sem dados" |

### P2 — Safe (cache / prefs / test-only)

| # | Arquivo | Padrão | O que faz | Decisão |
|---|---------|--------|-----------|---------|
| 7 | `core/deep_links/deep_link_handler.dart:148` | `SharedPreferences` | Persiste invite code temporário (OAuth redirect) | **SAFE** — efêmero |
| 8 | `core/tips/first_use_tips.dart` | `SharedPreferences` | Flags de tips mostrados | **SAFE** — UX pref |
| 9 | `core/theme/theme_notifier.dart` | `SharedPreferences` | Tema light/dark | **SAFE** — UX pref |
| 10 | `data/repositories_impl/coach_settings_repo.dart` | `SharedPreferences` | Toggles de coaching local (km alerts, ghost, HR zones) | **SAFE** — prefs locais |
| 11 | `features/wearables_ble/ble_heart_rate_source.dart` | `SharedPreferences` | Cache do endereço BLE | **SAFE** — device cache |
| 12 | `features/integrations_export/presentation/export_screen.dart:129` | `SharedPreferences` | Flag educacional Strava | **SAFE** — UX pref |
| 13 | `presentation/screens/map_screen.dart:67` | Demo tiles fallback | Mostra warning icon quando MapTiler API key vazia | **SAFE** — degradação graciosa |
| 14 | `data/repositories_impl/isar_*.dart` (20+) | `Isar` | Cache local sincronizado com Supabase (authoritative é o DB) | **SAFE** — cache by design |
| 15 | `features/parks/data/parks_seed.dart` | `kBrazilianParksSeed` | 40+ parks hardcoded para detecção offline | **SAFE** — fallback, não write de core |
| 16 | `*.test.ts` (12 arquivos portal) | `vi.mock`, `makeMockClient` | Mocks de teste (vitest) — nunca importados em prod | **SAFE** — test-only |

---

## Portal — Resultado

**ZERO** uso de `localStorage`, `sessionStorage`, `mockData`, `MODE_MOCK`, `VITE_*MOCK*`, `NEXT_PUBLIC_MOCK` encontrado no código de produção do portal.

Autenticação via cookies HTTP-only (Supabase Auth). Nenhum dado core armazenado client-side.

---

## Edge Functions — Resultado

**ZERO** mock/fake/demo/seed data encontrado nas Edge Functions.

---

## Teste Prático Obrigatório

```
1. Rodar app com internet → criar treino → verificar:
   SQL: SELECT * FROM coaching_training_sessions WHERE title = 'Test QA03';
   → 1 row (dados no Supabase ✅)

2. Desligar internet → tentar criar treino →
   Esperado: erro claro ("Sem conexão" ou "Falha ao salvar")
   NÃO deve: salvar localmente e mostrar como real

3. Ligar internet → criar novamente →
   SQL: SELECT count(*) FROM coaching_training_sessions WHERE title = 'Test QA03';
   → 1 row (o anterior offline NÃO foi salvo)

4. Verificar SharedPreferences:
   → Nenhum dado de treino/presença/aviso armazenado localmente
```

---

## Patches Necessários

### PATCH 1 (P0): Crash-fast em stubs de produção

```dart
// service_locator.dart — ANTES:
sl.registerLazySingleton<ITokenIntentRepo>(
  () => AppConfig.isSupabaseReady
      ? const RemoteTokenIntentRepo()
      : StubTokenIntentRepo(),
);

// DEPOIS:
sl.registerLazySingleton<ITokenIntentRepo>(
  () {
    if (!AppConfig.isSupabaseReady) {
      AppLogger.critical('TokenIntentRepo: Supabase not ready — refusing stub');
      throw StateError('TokenIntentRepo requires Supabase connection');
    }
    return const RemoteTokenIntentRepo();
  },
);
```

Aplicar o mesmo padrão para: `MockAuthDataSource`, `MockProfileDataSource`, `StubSwitchAssessoriaRepo`.

### PATCH 2 (P1): Log crítico quando mock mode ativa

```dart
// app_config.dart
static void markSupabaseNotReady() {
  _supabaseInitOk = false;
  AppLogger.critical(
    'MOCK MODE ACTIVATED — Supabase initialization failed. '
    'All stub repos will be used. This should NEVER happen in production.',
  );
}
```

### PATCH 3 (P1): Park stats zeradas

```dart
// park_screen.dart — ANTES:
_parkStats = const _ParkStats(runnersToday: 14, runnersWeek: 87, totalActivities: 1243);

// DEPOIS:
_parkStats = null; // UI mostra "Dados indisponíveis"
```
