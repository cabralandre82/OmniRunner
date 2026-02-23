# QA_PHASE_18.md — Auth + Onboarding + Routing

> **Sprint:** 18.99.0
> **Data:** 2026-02-21
> **Status:** EXECUTADO

---

## A — Auth (Social Login)

| # | Teste | Método | Resultado |
|---|-------|--------|-----------|
| A1 | Google login: signInWithIdToken flow completa | Code review: `RemoteAuthDataSource.signInWithGoogle()` usa `google_sign_in` SDK → `supabase.auth.signInWithIdToken(provider: OAuthProvider.google, idToken, accessToken)` | PASS — fluxo completo implementado |
| A2 | Apple login: signInWithIdToken flow completa | Code review: `RemoteAuthDataSource.signInWithApple()` usa `sign_in_with_apple` SDK → `signInWithIdToken(provider: OAuthProvider.apple, idToken, nonce)` | PASS — fluxo completo implementado |
| A3 | complete-social-profile chamada pós-login | Code review: `unawaited(_completeSocialProfile())` chamada após ambos Google e Apple sign-in | PASS — `remote_auth_datasource.dart:184,225` |
| A4 | Session persistence: Supabase Flutter SDK gerencia | Code review: `supabase_flutter` SDK auto-persiste session via `SharedPreferences` | PASS — SDK padrão |
| A5 | Cancellation handling: AuthSocialCancelled | Code review: `LoginScreen._handleFailure(f)` faz `return` sem mensagem se `f is AuthSocialCancelled` | PASS — `login_screen.dart:57` |
| A6 | Error display: inline com ícone | Code review: `_errorMessage` exibido com `Icons.error_outline` + text styled em vermelho | PASS — `login_screen.dart:162-182` |
| A7 | Loading state: spinner durante auth | Code review: `_busy` flag controla `CircularProgressIndicator` vs botões | PASS — `login_screen.dart:105-109` |

---

## B — Onboarding Flow

| # | Teste | Método | Resultado |
|---|-------|--------|-----------|
| B1 | NEW → WelcomeScreen | Code review: `AuthGate._resolve()` — `!authRepo.isSignedIn` → `_go(welcome)` | PASS |
| B2 | WelcomeScreen → LoginScreen | Code review: `onStart` callback → `_go(login)` | PASS — `auth_gate.dart:121` |
| B3 | Login OK → _onLoginSuccess → re-resolve | Code review: `_onLoginSuccess()` → `refresh()` + `_resolve()` | PASS — `auth_gate.dart:103-107` |
| B4 | handle_new_user trigger cria profile | Code review: `20260218_full_schema.sql` — trigger `on_auth_user_created` AFTER INSERT on `auth.users` → inserts into profiles | PASS — profile existe antes do re-resolve |
| B5 | NEW → OnboardingRoleScreen | Code review: `_resolve()` — profile.onboarding_state != READY && != ROLE_SELECTED → `_go(onboarding)` | PASS — `auth_gate.dart:89-90` |
| B6 | Escolher ATLETA → set-user-role → ROLE_SELECTED | Code review: `OnboardingRoleScreen._confirm()` → `invoke('set-user-role', body: {role: ATLETA})` → `onComplete()` | PASS |
| B7 | set-user-role guards: NEW/ROLE_SELECTED allowed, READY denied (409) | Code review: `set-user-role/index.ts` — `MUTABLE_STATES = ["NEW", "ROLE_SELECTED"]`, profile.onboarding_state not in list → 409 ONBOARDING_LOCKED | PASS — `index.ts:115-123` |
| B8 | ROLE_SELECTED + ATLETA → JoinAssessoriaScreen | Code review: `_resolve()` — match → `_go(joinAssessoria)` | PASS — `auth_gate.dart:83-85` |
| B9 | ROLE_SELECTED + STAFF → StaffSetupScreen | Code review: `_resolve()` — match → `_go(staffSetup)` | PASS — `auth_gate.dart:86-88` |
| B10 | Atleta join → fn_switch_assessoria → _setReady → READY | Code review: `JoinAssessoriaScreen._joinGroup()` → `rpc('fn_switch_assessoria')` → `_setReady()` (profiles.onboarding_state = READY) → `onComplete()` | PASS |
| B11 | Atleta skip → _setReady → READY | Code review: `_skip()` → `_setReady()` → `onComplete()` | PASS — `join_assessoria_screen.dart:297-315` |
| B12 | Staff criar assessoria → fn_create_assessoria → _setReady → READY | Code review: `_createAssessoria()` → `rpc('fn_create_assessoria')` → `_setReady()` → `onComplete()` | PASS |
| B13 | Staff join as professor → fn_join_as_professor → _setReady → READY | Code review: `_joinGroup()` → `rpc('fn_join_as_professor')` → `_setReady()` → `onComplete()` | PASS |
| B14 | READY + ATLETA → HomeScreen(AthleteDashboard) | Code review: `_resolve()` → `isOnboardingComplete` → `_go(home)` → `HomeScreen(userRole: 'ATLETA')` → `AthleteDashboardScreen` | PASS |
| B15 | READY + STAFF → HomeScreen(StaffDashboard) | Code review: `_resolve()` → `isOnboardingComplete` → `_go(home)` → `HomeScreen(userRole: 'ASSESSORIA_STAFF')` → `StaffDashboardScreen` | PASS |
| B16 | onComplete() always re-resolves | Code review: `_onOnboardingComplete()` → `setState(loading)` + `_resolve()` — never hardcodes next destination | PASS — `auth_gate.dart:109-112` |

---

## C — Guards (Loop / Edge Cases)

| # | Teste | Método | Resultado |
|---|-------|--------|-----------|
| C1 | Sem session → welcome (não home) | Code review: `_resolve()` — `!isSignedIn` → welcome | PASS |
| C2 | READY não volta para onboarding | Code review: `_resolve()` — `isOnboardingComplete` checked first → home. set-user-role returns 409 for READY | PASS |
| C3 | Forward-only: cada onComplete avança DB state | Code review: JoinAssessoriaScreen e StaffSetupScreen sempre chamam `_setReady()` antes de `onComplete()`. OnboardingRoleScreen chama `set-user-role` (NEW→ROLE_SELECTED). Re-resolve lê novo estado do DB | PASS |
| C4 | Mock mode bypass | Code review: `!AppConfig.isSupabaseReady` → `_go(home)` imediatamente | PASS — `auth_gate.dart:48-51` |
| C5 | Anonymous user bypass | Code review: `identity.isAnonymous` → `_go(home)` | PASS — `auth_gate.dart:63-66` |
| C6 | Profile fetch error → fallback home | Code review: `catch(e)` → `_go(home)` | PASS — `auth_gate.dart:92-94` |
| C7 | Profile null → onboarding (handle_new_user trigger prevents in practice) | Code review: `profile == null` → `_go(onboarding)` with `newUser` state | PASS — `auth_gate.dart:72-76` |
| C8 | ROLE_SELECTED with unknown role → fallback to onboarding | Code review: `else` clause after ATLETA/STAFF checks → `_go(onboarding)` | PASS — `auth_gate.dart:89-90` |
| C9 | App kill during onboarding → resume at correct screen | Code review: DB state persisted server-side; `_resolve()` runs on `initState` → reads latest state | PASS |
| C10 | fn_create_assessoria guards: NOT_AUTHENTICATED, NOT_STAFF, INVALID_NAME | Code review: RPC validates auth.uid(), user_role = ASSESSORIA_STAFF, name length 3-80 | PASS |
| C11 | fn_join_as_professor guards: NOT_AUTHENTICATED, NOT_STAFF, GROUP_NOT_FOUND | Code review: RPC validates auth.uid(), user_role, group exists | PASS |

---

## D — UX (Empty States)

| # | Tela | Empty State | CTA | Resultado |
|---|------|-------------|-----|-----------|
| D1 | ChallengesListScreen | "Nenhum desafio ainda / Crie um desafio e convide corredores para competir com você!" | FilledButton.icon "Criar desafio" → ChallengeCreateScreen | PASS |
| D2 | WalletScreen (history vazio) | "Nenhuma transação ainda / Peça ao professor da sua assessoria para distribuir OmniCoins." | Orientação textual (sem botão — ação é externa ao app) | PASS |
| D3 | MyAssessoriaScreen (sem grupo) | "Sem assessoria / Busque pelo nome, QR ou aceite um convite." | FilledButton.icon "Entrar em uma assessoria" → JoinAssessoriaScreen | PASS |
| D4 | AthleteDashboard card "Minha assessoria" (sem grupo) | "Sem assessoria" + "Toque para encontrar" | Card tap → MyAssessoriaScreen | PASS |
| D5 | StaffDashboard card "Campeonatos" | "Em breve" (dimmed card) | SnackBar "Campeonatos estará disponível em breve." | PASS |
| D6 | JoinAssessoriaScreen (sem busca) | "Digite o nome da assessoria para buscar" | Search bar + QR icon + "Tenho um código" + "Continuar sem assessoria" | PASS |
| D7 | StaffSetupScreen join (sem busca) | "Digite o nome da assessoria ou escaneie um QR" | Search bar + QR icon + "Tenho um código" | PASS |

---

## E — Termos Proibidos (GAMIFICATION_POLICY §5.1)

| # | Arquivo | Matches | Veredicto |
|---|---------|---------|-----------|
| E1 | welcome_screen.dart | 0 | PASS |
| E2 | login_screen.dart | 0 | PASS |
| E3 | onboarding_role_screen.dart | 0 | PASS |
| E4 | join_assessoria_screen.dart | 0 | PASS |
| E5 | staff_setup_screen.dart | 0 | PASS |
| E6 | auth_gate.dart | 0 | PASS |
| E7 | home_screen.dart | 0 | PASS |
| E8 | athlete_dashboard_screen.dart | 0 | PASS |
| E9 | staff_dashboard_screen.dart | 0 | PASS |
| E10 | challenges_list_screen.dart | 0 | PASS |
| E11 | wallet_screen.dart | "ledger" (code identifiers only), "clearing" in ledger label → FIXED to "confirmado entre assessorias" | PASS |
| E12 | my_assessoria_screen.dart | "token" in burn-warning (staff/coaching context, not prohibited) | PASS |
| E13 | more_screen.dart | "token" in staff QR tile subtitle (staff-only) | PASS |
| E14 | staff_qr_hub/generate/scan_screen.dart | "token" (staff-only operational screens) | PASS — "token" not in §5.1 prohibited list |

**Regex used:** `aposta|bet|wager|ganhar dinheiro|earn money|sacar|withdraw|cash.?out|redeem|prêmio em dinheiro|cash prize|loteria|lottery|jackpot|payout|staking|buy coins|comprar moedas|trade|invest|prize pool|bolsa de prêmios|real money|dinheiro real|gambling|jogo de azar`

**Result:** 0 prohibited terms in any user-facing UI text.

---

## F — Static Analysis

| # | Check | Resultado |
|---|-------|-----------|
| F1 | `flutter analyze` errors | 0 |
| F2 | `flutter analyze` warnings | 1 (pre-existing: unused variable in join_assessoria_screen.dart:264) |
| F3 | `flutter analyze` info | 43 (all pre-existing: avoid_catches_without_on_clauses, deprecated_member_use, etc.) |
| F4 | New issues introduced by Phase 18 | 0 errors, 0 warnings |

---

## G — Edge Functions (Backend)

| # | Function | Guard | Rate Limit | Obs | Resultado |
|---|----------|-------|------------|-----|-----------|
| G1 | complete-social-profile | requireUser, POST-only | 30/60s | structured logs | PASS |
| G2 | set-user-role | requireUser, POST-only, MUTABLE_STATES guard, valid role check | 20/60s | structured logs | PASS |

---

## H — SQL RPCs (Backend)

| # | Function | Guards | SECURITY DEFINER | Resultado |
|---|----------|--------|------------------|-----------|
| H1 | fn_search_coaching_groups | auth.uid() NOT NULL | Yes | PASS |
| H2 | fn_create_assessoria | auth.uid(), user_role = ASSESSORIA_STAFF, name 3-80 chars | Yes | PASS |
| H3 | fn_join_as_professor | auth.uid(), user_role = ASSESSORIA_STAFF, group exists | Yes | PASS |
| H4 | fn_switch_assessoria | auth.uid(), group exists (pre-existing) | Yes | PASS |

---

## I — State Machine (DECISAO 041)

```
No session         → WelcomeScreen → LoginScreen
Login OK           → handle_new_user trigger → profile(NEW)
                   → unawaited complete-social-profile
                   → AuthGate._resolve()
NEW                → OnboardingRoleScreen
set-user-role OK   → ROLE_SELECTED
ROLE_SELECTED+ATL  → JoinAssessoriaScreen
ROLE_SELECTED+STFF → StaffSetupScreen
join/skip/create   → _setReady() → READY
READY+ATLETA       → HomeScreen → AthleteDashboardScreen
READY+STAFF        → HomeScreen → StaffDashboardScreen
```

**Invariantes verificadas:**
1. Forward-only (DB state always advances) ✓
2. READY is terminal (set-user-role returns 409) ✓
3. handle_new_user trigger ensures profile exists before _resolve() ✓
4. Re-resolve pattern prevents hardcoded navigation ✓
5. Dashboard is role-aware (tab 0 switches on userRole) ✓

---

## Correção aplicada durante QA

| # | Arquivo | Antes | Depois | Motivo |
|---|---------|-------|--------|--------|
| QA-FIX-01 | wallet_screen.dart:277 | `'Liberado (clearing confirmado)'` | `'Liberado (confirmado entre assessorias)'` | "clearing" é jargão técnico; substituído por texto amigável |

---

## Resumo

| Categoria | Total | Pass | Fail |
|-----------|-------|------|------|
| A — Auth | 7 | 7 | 0 |
| B — Onboarding | 16 | 16 | 0 |
| C — Guards | 11 | 11 | 0 |
| D — UX Empty States | 7 | 7 | 0 |
| E — Termos Proibidos | 14 | 14 | 0 |
| F — Static Analysis | 4 | 4 | 0 |
| G — Edge Functions | 2 | 2 | 0 |
| H — SQL RPCs | 4 | 4 | 0 |
| **TOTAL** | **65** | **65** | **0** |

**Veredicto: PHASE 18 APROVADA — fluxo "app para dummies" validado, 0 termos proibidos na UI.**

---

*Gerado em 2026-02-21 — QA Sprint 18.99.0*
