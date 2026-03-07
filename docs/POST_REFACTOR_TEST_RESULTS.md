# POST_REFACTOR_TEST_RESULTS.md

> Data: 2026-03-07

---

## 1. RESULTADOS GERAIS

| Suite | Passed | Failed | Skipped | Total | Pass Rate |
|---|---|---|---|---|---|
| Flutter (unit + widget) | 2016 | 30 | 4 | 2050 | 98.3% |
| Portal Vitest | 585 | 15 | 0 | 600 | 97.5% |
| Portal E2E (Playwright) | — | — | — | 22 specs | Não executado (requer servidor) |
| Backend (Supabase) | — | — | — | — | Sem test files encontrados |

---

## 2. FLUTTER — 6 ARQUIVOS QUE NÃO CARREGAM (compile errors)

| Arquivo | Erro | Causa |
|---|---|---|
| athlete_attendance_screen_test.dart | invalid_override | _FakeAttendanceRepo.listByAthlete missing limit/offset params |
| athlete_device_link_screen_test.dart | invalid_use_of_type_outside_library | LinkDevice é final class |
| athlete_log_execution_screen_test.dart | invalid_use_of_type_outside_library | ImportExecution é final class |
| matchmaking_screen_test.dart | extends_non_class | Fake class extends tipo inválido |
| staff_training_scan_screen_test.dart | extends_non_class | Fake class extends tipo inválido |
| staff_workout_builder_screen_test.dart | extends_non_class | Fake class extends tipo inválido |

---

## 3. FLUTTER — 24 TESTES COM ERRO EM RUNTIME

| Teste | Causa provável | Severidade |
|---|---|---|
| park_screen_test (3 testes) | FeatureFlagService não mockado | MÉDIA |
| join_assessoria_screen_test (4) | Supabase.instance não inicializado | MÉDIA |
| league_screen_test (3) | FeatureFlagService não mockado | MÉDIA |
| personal_evolution_screen_test (1) | Supabase.instance | MÉDIA |
| running_dna_screen_test (2) | Supabase.instance | MÉDIA |
| staff_dashboard_screen_test (2) | Supabase.instance | MÉDIA |
| staff_generate_qr_screen_test (1) | Dependência não mockada | BAIXA |
| support_ticket_screen_test (2) | Supabase.instance | MÉDIA |
| wrapped_screen_test (2) | Supabase.instance | BAIXA |
| partner_assessorias_screen_test (3) | Supabase.instance | MÉDIA |

**Padrão:** A maioria falha porque os screens acessam `Supabase.instance.client` diretamente no `initState`, sem guard `AppConfig.isSupabaseReady`.

---

## 4. PORTAL — 15 TESTES FALHANDO

### sidebar.test.tsx (9 falhas)
**Causa:** `LocaleSwitcher` component usa `useLocale()` de `next-intl` sem `NextIntlClientProvider` no wrapper de teste.
**Fix:** Envolver render com `<NextIntlClientProvider messages={{}} locale="pt-BR">`.

### rate-limit.test.ts (6 falhas)
**Causa:** `rateLimit()` mudou de síncrono para `async` (retorna Promise) após integração com Redis. Tests não foram atualizados.
**Fix:** Adicionar `await` em todas as chamadas nos testes.

---

## 5. COBERTURA POR MÓDULO

| Módulo | Testes existem? | Status |
|---|---|---|
| Domain use cases | ✅ Parcial | ~20 use cases cobertos |
| Domain entities | ✅ Parcial | Serialização coberta |
| Presentation screens (widget) | ✅ ~95 screens | Maioria renderiza e testa estados |
| BLoCs | ❌ Limitado | Poucos BLoC tests dedicados |
| Repositories (Isar) | ❌ Nenhum | Zero repo tests unitários |
| Data mappers | ❌ Nenhum | Inline nos repos, não testados isoladamente |
| Edge Functions | ❌ Nenhum | Sem test framework configurado |
| Portal API routes | ✅ 47 test files | Boa cobertura |
| Portal E2E | ✅ 22 spec files | Configurados mas requerem servidor |

---

## 6. GAPS CRÍTICOS DE COBERTURA

1. **Zero testes para repositories Isar** — a camada mais crítica entre domain e storage
2. **Zero testes para Edge Functions** — 59 functions sem cobertura
3. **BLoCs sub-testados** — apenas widget tests indiretos, sem unit tests de state transitions
4. **Data mappers não testados** — inline nos repos, sem verificação isolada de campos
