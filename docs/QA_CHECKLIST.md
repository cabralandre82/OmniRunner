# Omni Runner — Checklist de Pré-Lançamento (APK Day)

> **Phase:** 90 — QA Pré-Lançamento
> **Data:** 2026-02-21
> **Fontes:** DEFINITION_OF_DONE.md, QA_CHECKLIST.md (anterior), AUDIT_REPORT.md, Phase 90.0.1 inventory
> **Objetivo:** Checklist único e executável — marcar cada item antes de gerar APK release

---

## Ambiente de Teste

| Item | Valor |
|------|-------|
| Device | (preencher) |
| OS / Versão | (preencher) |
| Flutter build mode | release |
| `.env` utilizado | `.env.prod` com chaves reais |
| Supabase configurado | sim / não |
| MapTiler configurado | sim / não |
| Stripe configurado | sim / não |
| Data do teste | (preencher) |

---

## P0 — BLOQUEIA RELEASE (deve estar OK antes de gerar APK)

### P0.1 — Build & Compilação

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P0.1.1 | `flutter build apk --release` gera APK sem erros | ☐ | |
| P0.1.2 | `flutter analyze` — 0 erros (warnings aceitáveis) | ☐ | |
| P0.1.3 | APK release instala e abre sem crash em device real | ☐ | |
| P0.1.4 | `flutter test` — todos os testes passam | ☐ | |

### P0.2 — Chaves e Credenciais

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P0.2.1 | `.env.prod` com `SUPABASE_URL` real (não placeholder) | ☐ | |
| P0.2.2 | `.env.prod` com `SUPABASE_ANON_KEY` real | ☐ | |
| P0.2.3 | `.env.prod` com `MAPTILER_API_KEY` real | ☐ | |
| P0.2.4 | `.env.prod` com `SENTRY_DSN` real | ☐ | |
| P0.2.5 | `STRIPE_SECRET_KEY` configurado nas Edge Functions | ☐ | |
| P0.2.6 | `STRIPE_WEBHOOK_SECRET` configurado nas Edge Functions | ☐ | |
| P0.2.7 | OAuth providers configurados (Google, Apple, Facebook) | ☐ | |
| P0.2.8 | Nenhuma credencial hardcoded no código (grep `sk_live\|sk_test\|password`) | ☐ | |

### P0.3 — Auth & Onboarding

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P0.3.1 | App abre → WelcomeScreen (primeiro uso) | ☐ | |
| P0.3.2 | Login com Google funciona | ☐ | |
| P0.3.3 | Login com Apple funciona (iOS) | ☐ | |
| P0.3.4 | Após login → OnboardingRoleScreen | ☐ | |
| P0.3.5 | Selecionar "Atleta" → JoinAssessoriaScreen | ☐ | |
| P0.3.6 | Selecionar "Assessoria" → StaffSetupScreen | ☐ | |
| P0.3.7 | Pular assessoria → HomeScreen (AthleteDashboard) | ☐ | |
| P0.3.8 | Criar assessoria → HomeScreen (StaffDashboard) | ☐ | |
| P0.3.9 | Reabrir app com sessão existente → direto para HomeScreen | ☐ | |

### P0.4 — GPS & Tracking (core loop)

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P0.4.1 | Permissão GPS solicitada no primeiro uso | ☐ | |
| P0.4.2 | "Allow" concede permissão → estado IDLE | ☐ | |
| P0.4.3 | "Deny" mostra mensagem clara com retry | ☐ | |
| P0.4.4 | "Start Run" inicia tracking (chip verde "Tracking") | ☐ | |
| P0.4.5 | Distância, pace e tempo atualizam em tempo real | ☐ | |
| P0.4.6 | Polyline azul desenhada no mapa | ☐ | |
| P0.4.7 | "Stop" para tracking → RunSummaryScreen aparece | ☐ | |
| P0.4.8 | RunSummaryScreen mostra distância, pace, tempo, mapa | ☐ | |
| P0.4.9 | Sessão aparece no Histórico como "Completed" | ☐ | |
| P0.4.10 | RunDetailsScreen mostra polyline no mapa | ☐ | |
| P0.4.11 | Foreground service notification visível durante tracking (Android) | ☐ | |

### P0.5 — Termos Proibidos

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P0.5.1 | 0 ocorrências de `dinheiro` em UI strings | ☐ | `grep -ri dinheiro lib/presentation/` |
| P0.5.2 | 0 ocorrências de `aposta` em UI strings | ☐ | |
| P0.5.3 | 0 ocorrências de `saque` em UI strings | ☐ | |
| P0.5.4 | 0 ocorrências de `bet\|gamble\|cash.?out` em UI | ☐ | |
| P0.5.5 | 0 ocorrências de `comprar\|buy\|purchase` em UI do app mobile | ☐ | |
| P0.5.6 | 0 ocorrências de `R\$\|USD\|\$\|€` em UI do app mobile | ☐ | |
| P0.5.7 | 0 referências a `price_cents\|billing_products` em `lib/` | ☐ | |

### P0.6 — Backend (Supabase)

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P0.6.1 | Migrations aplicadas com sucesso (61 tables) | ☐ | |
| P0.6.2 | Seed data aplicado (29 badges + 5 billing products + season) | ☐ | |
| P0.6.3 | RLS ativo em todas as tabelas | ☐ | |
| P0.6.4 | 27 Edge Functions deployed | ☐ | |
| P0.6.5 | `pg_cron` habilitado (auto-topup-cron hourly) | ☐ | |
| P0.6.6 | `pg_net` habilitado (HTTP calls from cron) | ☐ | |
| P0.6.7 | Env vars configuradas no Supabase Dashboard (STRIPE_*, PORTAL_URL) | ☐ | |

---

## P1 — QUASE BLOQUEIA (deve ser resolvido antes de beta público)

### P1.1 — Navegação & UX "Para Dummies"

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P1.1.1 | Atleta tem caminho para ver/participar de campeonatos | ☐ | **FAIL em 90.0.1 — sem tela** |
| P1.1.2 | Usuário novo entende "o que fazer" em 60s (TipBanners visíveis) | ☐ | |
| P1.1.3 | Assessoria staff entende "o que fazer" em 60s | ☐ | |
| P1.1.4 | Nenhum botão que não faz nada (telas mortas) | ☐ | |
| P1.1.5 | "Coming Soon" tiles não parecem quebrados para o usuário | ☐ | |
| P1.1.6 | Empty states têm CTA claro (Desafios, Wallet, Assessoria) | ☐ | |
| P1.1.7 | Portal button no StaffDashboard funciona (ou escondido em mock) | ☐ | **FAIL em 90.0.1 — aberto em mock** |
| P1.1.8 | Recovery → HomeScreen preserva userRole (não assume atleta) | ☐ | **FAIL em 90.0.1** |

### P1.2 — Background Tracking & Resiliência GPS

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P1.2.1 | Bloquear tela durante tracking → GPS continua | ☐ | |
| P1.2.2 | Minimizar app → pontos continuam acumulando | ☐ | |
| P1.2.3 | 5 min com tela off → dados não perdidos | ☐ | |
| P1.2.4 | GPS perdido durante corrida → estado "gpsLost" visível | ☐ | Banner vermelho no TrackingScreen |
| P1.2.5 | GPS restaurado → tracking retoma automaticamente (60s timeout) | ☐ | `_scheduleGpsReconnect` |
| P1.2.6 | GPS timeout 60s → sessão finalizada com dados salvos | ☐ | |

### P1.3 — Desafios (fluxo completo)

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P1.3.1 | Criar desafio imediato (5/10/30min/1h/24h) | ☐ | |
| P1.3.2 | Criar desafio agendado (date picker + duração) | ☐ | |
| P1.3.3 | Aceitar desafio recebido | ☐ | |
| P1.3.4 | Recusar desafio | ☐ | |
| P1.3.5 | Ghost overlay visível durante desafio | ☐ | |
| P1.3.6 | Resultado do desafio exibido (ChallengeResultScreen) | ☐ | |
| P1.3.7 | OmniCoins creditados ao vencedor | ☐ | |
| P1.3.8 | Push notification "desafio recebido" | ☐ | |

### P1.4 — Tokens & Wallet

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P1.4.1 | Staff gera QR de emissão → atleta escaneia → wallet incrementa | ☐ | |
| P1.4.2 | Staff gera QR de queima → atleta escaneia → wallet decrementa | ☐ | |
| P1.4.3 | Wallet mostra 3 estados (total / disponível / pendente) | ☐ | |
| P1.4.4 | Limites diários respeitados (5000 tokens/grupo, 500 burns/atleta) | ☐ | |
| P1.4.5 | Desafio cross-assessoria → prêmio fica "pendente" | ☐ | |

### P1.5 — Observabilidade & Segurança

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P1.5.1 | Sentry recebe crashes de release builds | ☐ | |
| P1.5.2 | Edge Functions logam request_id + user_id + duration_ms | ☐ | |
| P1.5.3 | Rate limit ativo em todas as 14 Edge Functions | ☐ | |
| P1.5.4 | Erros de DB sanitizados (mensagens internas não vazam) | ☐ | |
| P1.5.5 | JWT validado em todas as Edge Functions (requireUser) | ☐ | |

### P1.6 — Portal B2B (Web)

| # | Check | Status | Evidência |
|---|-------|--------|-----------|
| P1.6.1 | Login staff funciona (Supabase Auth SSR) | ☐ | |
| P1.6.2 | Atleta não consegue acessar (no-access page) | ☐ | |
| P1.6.3 | Dashboard mostra créditos + atletas + compras | ☐ | |
| P1.6.4 | Compra de créditos → Stripe Checkout → webhook → inventory | ☐ | |
| P1.6.5 | Histórico de compras e recibos | ☐ | |
| P1.6.6 | Equipe — convidar/remover staff | ☐ | |
| P1.6.7 | Auto top-up configurável (threshold + pacote + max/mês) | ☐ | |
| P1.6.8 | `next build` sem erros | ☐ | |

---

## P2 — PÓS-LANÇAMENTO (backlog priorizado)

### P2.1 — Telas Órfãs e Dead Code

| # | Check | Status | Notas |
|---|-------|--------|-------|
| P2.1.1 | `CoachInsightsScreen` — conectar via MoreScreen ou remover | ☐ | Sem navigation link |
| P2.1.2 | `ExportScreen` — conectar via MoreScreen > Integrações | ☐ | Sem navigation link |
| P2.1.3 | Social screens (Friends, Groups, Events) — implementar ou remover "Coming Soon" | ☐ | MoreScreen lines 87-98 |
| P2.1.4 | `DebugTrackingScreen` — remover arquivo morto | ☐ | Não navegado |
| P2.1.5 | `MapScreen` — conectar ou remover | ☐ | Não navegado |

### P2.2 — UX Polish

| # | Check | Status | Notas |
|---|-------|--------|-------|
| P2.2.1 | Ghost delta numérico exibido no TrackingBottomPanel | ☐ | Funcional mas verificar visibilidade |
| P2.2.2 | Auto-pause indicador visual na UI | ☐ | AutoPauseDetector calcula mas UI não mostra |
| P2.2.3 | Recovery resume reinjeta sessão no BLoC (em vez de finalizar) | ☐ | Atualmente faz finish+HomeScreen |
| P2.2.4 | Audio coach settings (km/tempo/ghost toggles) respeitados | ☐ | TrackingBloc agora lê settings — verificar toggles |
| P2.2.5 | `RunDetailsScreen` — replay button funcional | ☐ | RunReplayScreen existe |
| P2.2.6 | Histórico — exportar GPX/FIT/TCX button | ☐ | ExportScreen existe mas sem wiring |

### P2.3 — iOS Específico

| # | Check | Status | Notas |
|---|-------|--------|-------|
| P2.3.1 | `UIBackgroundModes: fetch` — adicionar para sync em background | ☐ | Ausente |
| P2.3.2 | `NSMotionUsageDescription` — adicionar para pedômetro futuro | ☐ | Ausente |
| P2.3.3 | iOS audio ducking ativo durante TTS | ☐ | Requer teste em device real |
| P2.3.4 | Universal Links `.well-known/apple-app-site-association` deployed | ☐ | Template existe |

### P2.4 — Android Específico

| # | Check | Status | Notas |
|---|-------|--------|-------|
| P2.4.1 | `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` permissions | ☐ | Ausente — necessário para HR monitors |
| P2.4.2 | `ACTIVITY_RECOGNITION` permission | ☐ | Ausente — necessário para step counter |
| P2.4.3 | Android App Links `.well-known/assetlinks.json` deployed | ☐ | Template existe |
| P2.4.4 | Battery optimization whitelist hint para tracking | ☐ | |

### P2.5 — Testes Automatizados Faltantes

| # | Check | Status | Notas |
|---|-------|--------|-------|
| P2.5.1 | TrackingBloc state machine tests (bloc_test) | ☐ | Template no AUDIT_REPORT |
| P2.5.2 | SyncRepo failure modes tests | ☐ | Template no AUDIT_REPORT |
| P2.5.3 | Widget tests para screens críticas (Tracking, Dashboard) | ☐ | |
| P2.5.4 | Integration test: corrida → sync → verify on server | ☐ | |

### P2.6 — Wearables & Integrações Externas

| # | Check | Status | Notas |
|---|-------|--------|-------|
| P2.6.1 | BLE HR monitor integration | ☐ | Feature futura |
| P2.6.2 | Apple HealthKit / Health Connect export | ☐ | Feature futura |
| P2.6.3 | Strava OAuth + auto-upload | ☐ | OAuth flow coded, upload coded |
| P2.6.4 | Garmin Connect IQ | ☐ | Feature futura |

---

## RESUMO DE CONTAGEM

| Prioridade | Total | Descrição |
|------------|-------|-----------|
| **P0** | 33 | Bloqueia release — zero falhas permitidas |
| **P1** | 30 | Quase bloqueia — resolver antes de beta público |
| **P2** | 20 | Pós-lançamento — backlog priorizado |
| **Total** | 83 | |

---

## BUGS DO AUDIT_REPORT — STATUS ATUALIZADO

| ID | Original | Status Atual | Evidência |
|----|----------|-------------|-----------|
| B1 | RunSummaryScreen nunca navegado | **CORRIGIDO** | `tracking_screen.dart:210-211` |
| B2 | Coach settings ignorados pelo TrackingBloc | **CORRIGIDO** | `tracking_bloc.dart:62,180` — `_coachSettings.load()` |
| B3 | ghostDeltaM não exibido na UI | **CORRIGIDO** | `tracking_bottom_panel.dart:68` |
| B4 | RunDetailsScreen sem integrity/ghost/sync | **CORRIGIDO** | `run_details_screen.dart:136-141` |
| B5 | Foreground service não integrado | **CORRIGIDO** | `tracking_bloc.dart:189` |
| B6 | Recovery resume não reinjeta sessão | **ABERTO** (P2) | `main.dart:133-141` |
| B7 | avgPace usa elapsed em vez de movingMs | **CORRIGIDO** | `run_details_screen.dart:129-130` |
| B8 | DebugTrackingScreen como home | **CORRIGIDO** | `main.dart:114` — AuthGate |
| B9 | CFBundleName incorreto | **CORRIGIDO** | `Info.plist:16` |

---

## COMO USAR ESTE CHECKLIST

1. **Antes de gerar APK:** Todos os P0 devem estar ☑
2. **Antes de beta público:** Todos os P1 devem estar ☑
3. **Pós-lançamento:** P2 entra no backlog priorizado
4. **Teste manual:** Preencher coluna "Status" com ✅ PASS, ❌ FAIL, ou ⏭ SKIP (justificar)
5. **Evidência:** Screenshot, log, ou path do código que prova

---

*Gerado em Phase 90.0.3 — consolidação de DEFINITION_OF_DONE.md + QA_CHECKLIST.md + AUDIT_REPORT.md + Phase 90.0.1 inventory*
