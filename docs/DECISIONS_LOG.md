# DECISIONS_LOG.md — Registro de Decisoes Arquiteturais

> **Criado:** 2026-02-17
> **Status:** Ativo

---

## DECISAO 020 — Desativar Social BLoCs sem repo implementations (Pre-Launch QA)

**Data:** 2026-02-17
**Sprint:** Pre-Launch QA Audit — Fix #1
**Contexto:**
`FriendsBloc`, `GroupsBloc` e `EventsBloc` estavam registrados no `service_locator.dart`
via `registerFactory`, referenciando `IFriendshipRepo`, `IGroupRepo` e `IEventRepo`.
Nenhuma dessas interfaces possui implementacao concreta registrada no DI (os Isar repos
da Phase 15 nunca foram criados — sprint 15.6.0 ainda e TODO).

Embora os BLoCs fossem lazy (factory), qualquer resolucao futura (ex.: adicionar navegacao
para telas Social) causaria `StateError` fatal em runtime.

**Decisao:**
Comentar as 3 registracoes de BLoC (`FriendsBloc`, `GroupsBloc`, `EventsBloc`) e seus
imports, com TODO apontando para Phase 15. Manter `LeaderboardsBloc` que nao depende
de repo externo.

**Justificativa:**
- Defensive programming: eliminar crash paths latentes.
- Padrao ja estabelecido: identico ao fix aplicado para `RaceEventsBloc`/`RaceEventDetailsBloc`
  no sprint 16.9.0-fix.
- Zero risco de regressao: telas Social nao sao acessiveis pela navegacao atual.

**Reativar quando:**
Sprint 15.6.0 (Persistencia Isar: repo impls + DB provider + DI) for concluida.

---

## DECISAO 021 — Guard Supabase em AnalyticsSyncService (Pre-Launch QA)

**Data:** 2026-02-17
**Sprint:** Pre-Launch QA Audit — Fix #2
**Contexto:**
`AnalyticsSyncService._client` acessava `Supabase.instance.client` diretamente. Se Supabase
nao foi inicializado (app rodando sem `--dart-define` de SUPABASE_URL/ANON_KEY), o getter
lanca `StateError` antes mesmo de `_requireAuth()` executar.

**Decisao:**
1. Novo tipo de excecao `AnalyticsNotConfigured` (sealed hierarchy existente).
2. `_client` getter agora verifica `AppConfig.isSupabaseConfigured` antes de acessar
   `Supabase.instance`.
3. `_userId` getter protegido com try/catch para nao crashar.
4. Novo `_requireConfigured()` chamado ANTES de `_requireAuth()` em todo metodo publico.

**Justificativa:**
- Defensive programming: app deve funcionar 100% offline sem backend.
- Padrao consistente com `SyncRepo.syncPending()` que ja verifica `_svc.isConfigured`.
- Callers recebem excecao tipada (`AnalyticsNotConfigured`) em vez de `StateError`.

---

## DECISAO 022 — Map Load Timeout com Fallback Offline (Pre-Launch QA)

**Data:** 2026-02-17
**Sprint:** Pre-Launch QA Audit — Fix #3
**Contexto:**
`TrackingScreen`, `RunSummaryScreen` e `RunDetailsScreen` usam `MapLibreMap` com tiles
remotos (MapTiler ou demo). Sem internet, `onStyleLoadedCallback` nunca dispara,
`_mapReady` fica `false` para sempre, e o usuario ve um `CircularProgressIndicator` infinito
cobrindo a tela principal.

**Decisao:**
Timer de 6 segundos em cada tela com mapa. Se `_onStyleLoaded` nao disparar no prazo:
1. `_mapReady = true` (remove spinner)
2. `_mapTimedOut = true` (mostra banner "Map unavailable offline")
3. Se o estilo carregar depois (ex: usuario reconecta), o callback normal sobrescreve

**Justificativa:**
- Controles de tracking (Start/Stop), metricas e navegacao devem ser acessiveis SEMPRE.
- 6s e suficiente para carregamento normal (tipicamente <3s com rede).
- Banner e nao-intrusivo: icone + texto centralizado atras dos controles posicionados.
- Padrao aplicado consistentemente nas 3 telas com mapa.

---

## DECISAO 023 — Registrar Schemas Isar Social no DB Provider (Pre-Launch QA)

**Data:** 2026-02-17
**Sprint:** Pre-Launch QA Audit — Fix #4
**Contexto:**
Phase 15 (Social & Events) criou 4 arquivos de modelo Isar com 8 collections:
`FriendshipRecord`, `GroupRecord`, `GroupMemberRecord`, `GroupGoalRecord`,
`EventRecord`, `EventParticipationRecord`, `LeaderboardSnapshotRecord`,
`LeaderboardEntryRecord`. Porem, nenhum schema foi adicionado ao `Isar.open()` em
`isar_database_provider.dart`. Acessar qualquer dessas collections causaria
`IsarError: Collection not found`.

**Decisao:**
Adicionar os 8 schemas ao array de `Isar.open()` e os 4 imports correspondentes.
Isar 3.x suporta adicao de novas collections sem migration — databases existentes
recebem as novas collections automaticamente na proxima abertura.

**Risco:**
Nenhum para databases existentes (adicao de collections e aditiva).
Se algum device ja tiver o DB aberto com o schema antigo, o app precisa ser reiniciado.

---

## DECISAO 024 — Home Screen com NavigationBar (Material 3)

**Data:** 2026-02-17
**Contexto:** O app abria diretamente no `TrackingScreen`. 30+ telas codificadas eram
completamente inacessiveis por nao existir nenhum menu, drawer ou tab bar.

**Decisao:**
Criar `HomeScreen` com `NavigationBar` (Material 3) e 4 tabs:
- **Run** — `TrackingScreen` (core tracking + mapa)
- **History** — `HistoryScreen` (sessoes passadas)
- **Progress** — `ProgressHubScreen` (novo, lista gamificacao: XP, badges, missions, challenges, wallet, leaderboards)
- **More** — `MoreScreen` (novo, coaching, social [coming soon], wearables info, settings, about)

Usa `IndexedStack` para preservar estado de cada tab (ex: mapa nao recarrega ao trocar de tab).

Telas cujos BLoCs nao estao registrados (Friends, Groups, Events) mostram SnackBar
"Coming Soon" ao invés de crashar.

**Arquivos criados:**
- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/screens/progress_hub_screen.dart`
- `lib/presentation/screens/more_screen.dart`

**Arquivos modificados:**
- `lib/main.dart` — import de `HomeScreen` em vez de `TrackingScreen`; recovery flows redirecionam para `HomeScreen`.

**Risco:**
`IndexedStack` mantem todas as 4 tabs em memoria. Para este app (4 tabs leves), impacto
de memoria e negligivel. Se no futuro alguma tab ficar muito pesada, considerar
lazy loading com `AutomaticKeepAliveClientMixin`.

---

## DECISAO 025 — UserIdentityProvider (anonymous local UUID)

**Data:** 2026-02-17
**Contexto:** Nenhum fluxo de autenticacao existe no app. Todos os BLoCs de gamificacao
e coaching requerem um `userId` nos seus eventos `Load*`. Sem um userId, as telas
permaneciam eternamente no estado `Initial` ("Carregue seu perfil"), impossibilitando
qualquer teste real das features.

**Decisao:**
Criar `UserIdentityProvider` que:
1. No primeiro launch gera um UUID v4 via `Random.secure()` e persiste em SharedPreferences
2. Em launches subsequentes, recarrega o mesmo UUID
3. Se Supabase estiver configurado e o usuario autenticado, usa o Supabase userId em vez do local
4. Expoe `userId`, `displayName`, `isAnonymous`

Registrado como `singleton` em `service_locator.dart` (inicializado antes do Isar).

As telas `ProgressHubScreen` e `MoreScreen` agora criam `BlocProvider`s inline e
auto-disparam eventos `Load*(userId)` ao navegar, garantindo que os BLoCs recebam
o userId e carreguem dados do Isar.

Um banner "Offline Mode" aparece no `MoreScreen` quando `isAnonymous == true`,
informando ao usuario que os dados sao locais.

**Arquivos criados:**
- `lib/core/auth/user_identity_provider.dart`

**Arquivos modificados:**
- `lib/core/service_locator.dart` — import + registro singleton
- `lib/presentation/screens/progress_hub_screen.dart` — BlocProvider wrappers com auto-dispatch
- `lib/presentation/screens/more_screen.dart` — BlocProvider wrapper para CoachingGroups + banner

**Risco:**
- O UUID local nao migra automaticamente para o Supabase userId apos login.
  Quando o fluxo de auth real for implementado, sera necessario um migration step
  que atualiza todos os registros Isar do UUID local para o UUID do Supabase.
- `Random.secure()` depende de `/dev/urandom` no Linux/Android e `SecRandomCopyBytes`
  no iOS. Ambos sao criptograficamente seguros.

---

## DECISAO 026 — iOS deployment target 12.0 → 13.0

**Data:** 2026-02-17
**Contexto:** O projeto usava `IPHONEOS_DEPLOYMENT_TARGET = 12.0` em 3 build configs
e `MinimumOSVersion = 12.0` no `AppFrameworkInfo.plist`. Packages criticos requerem
iOS 13.0+:
- `health` (HealthKit/Health Connect) — requer iOS 13.0
- `flutter_blue_plus` (BLE HR) — requer iOS 13.0
- `flutter_foreground_task` — requer iOS 13.0

Com target 12.0, `pod install` falharia ou geraria warnings que impedem build.

**Decisao:**
Atualizar todos os 4 pontos para 13.0:
- `ios/Runner.xcodeproj/project.pbxproj` (3 configs: Debug, Profile, Release)
- `ios/Flutter/AppFrameworkInfo.plist` (MinimumOSVersion)

Quando o Podfile for gerado (primeiro `flutter build ios`), usar `platform :ios, '13.0'`.

**Risco:**
- Dispositivos com iOS 12.x nao poderao instalar o app.
- iOS 12 (Sep 2018) tem <1% de market share (Apple stats 2025). Impacto negligivel.

---

## DECISAO 027 — HealthKit SystemCapabilities no project.pbxproj

**Data:** 2026-02-17
**Contexto:** O `Runner.entitlements` ja declarava `com.apple.developer.healthkit` e
`healthkit.background-delivery`. O `Info.plist` ja tinha `NSHealthShareUsageDescription`
e `NSHealthUpdateUsageDescription`. O `CODE_SIGN_ENTITLEMENTS` apontava para o
entitlements file em todas as 3 configs.

Porem, o `project.pbxproj` nao tinha a secao `SystemCapabilities` no `TargetAttributes`
do Runner target. Sem isso, o Xcode:
- Nao mostra HealthKit como "enabled" na aba Signing & Capabilities
- Pode re-gerar o entitlements sem as keys de HealthKit durante automatic signing
- Falha na validacao do App Store Connect

**Decisao:**
Adicionar `SystemCapabilities` ao `TargetAttributes` do Runner (`97C146ED1CF9000F007C117D`)
com `com.apple.HealthKit.enabled = 1` e `com.apple.BackgroundModes.enabled = 1`.

**Arquivo modificado:**
- `ios/Runner.xcodeproj/project.pbxproj`

**Risco:** Nenhum. Adicao de metadata que alinha o pbxproj com o entitlements existente.

---

## DECISAO 028 — Substituir dev.log() por AppLogger em todo o codebase

**Data:** 2026-02-18
**Contexto:** 58 chamadas `dev.log()` espalhadas em 12 arquivos (watch_bridge, strava,
integrations_export) acessavam `dart:developer` diretamente, ignorando o `AppLogger`
centralizado em `lib/core/logging/logger.dart`. Isso impedia:
- Filtragem por nivel (debug/info/warn/error)
- Formatacao uniforme com prefixo de level
- Hook para Sentry/Crashlytics via `AppLogger.onError`
- Controle centralizado de `minLevel` para release builds

**Decisao:**
Substituir todas as 58 chamadas `dev.log()` por metodos `AppLogger.{debug,info,warn,error}`,
usando o parametro `tag:` com o nome da classe/modulo (ex: `WatchBridge`, `StravaUpload`).
Remover todos os `import 'dart:developer' as dev;` exceto em `logger.dart`.

A escolha de nivel segue a convencao:
- `debug` — traces internos, retry steps, polling, cleanup
- `info` — eventos de lifecycle (init, dispose, connect, disconnect, export)
- `warn` — falhas nao-fatais (ACK failed, parse failed, rate-limited)
- `error` — excepcoes com stack trace (usa parametro `error:` + `stack:`)

**Arquivos modificados (11):**
- `lib/features/watch_bridge/watch_bridge.dart` (ja feito antes)
- `lib/features/watch_bridge/watch_bridge_init.dart`
- `lib/features/watch_bridge/process_watch_session.dart`
- `lib/features/strava/data/strava_upload_repository_impl.dart`
- `lib/features/strava/data/strava_http_client.dart`
- `lib/features/strava/data/strava_secure_store.dart`
- `lib/features/strava/data/strava_auth_repository_impl.dart`
- `lib/features/strava/presentation/strava_connect_controller.dart`
- `lib/features/integrations_export/presentation/export_screen.dart`
- `lib/features/integrations_export/presentation/share_export_file.dart`
- `lib/features/integrations_export/presentation/export_sheet_controller.dart`

**Risco:** Nenhum. Mudanca de logging apenas. O `AppLogger` delega para `dev.log()` internamente,
mantendo o mesmo comportamento em DevTools. Funcionalidade identica, com controle centralizado.

---

## DECISAO 029 — Try-catch defensivo em use cases e AudioCoachService

**Data:** 2026-02-18
**Contexto:** O AUDIT_REPORT §2.3 listava 4 funcoes MEDIO/BAIXO risco sem try-catch:
- `FinishSession.call` — queries Isar podem falhar mid-way, deixando sessao incompleta
- `RecoverActiveSession.call` — queries Isar podem falhar no recovery de crash
- `DiscardSession.call` — delete pode falhar, deixando dados orfaos
- `AudioCoachService.speak/stop/init` — FlutterTts pode lancar em devices sem TTS engine

O TrackingBloc (ALTO risco) ja tinha try-catch completo (aplicado anteriormente).

**Decisao:**
Adicionar try-catch em cada funcao, com logging via `AppLogger.error`/`warn` e retorno
seguro (success=false, null, false) em vez de propagar excecoes. O `AudioCoachService`
ganha protecao em `init()`, `speak()` e `stop()` — se TTS falhar, voice coaching
degrada silenciosamente sem afetar o tracking.

**Arquivos modificados (4):**
- `lib/domain/usecases/finish_session.dart`
- `lib/domain/usecases/recover_active_session.dart`
- `lib/domain/usecases/discard_session.dart`
- `lib/data/datasources/audio_coach_service.dart`

**Risco:** Minimo. Comportamento normal nao muda (try-catch so ativa em falha).
Em caso de falha Isar, a sessao pode ficar parcialmente atualizada, mas o app nao crasha.
O AudioCoachService degrada gracefully — corrida continua sem voz.

---

## DECISAO 030 — Await ForegroundTaskConfig.start/stop no TrackingBloc

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §2.1 RC-02 identificou que `ForegroundTaskConfig.start()` e
`stop()` eram chamados fire-and-forget no `BlocListener` da `TrackingScreen`. Se `stop()`
executasse antes de `start()` completar, o foreground service poderia ficar preso rodando
(notificacao persistente sem corrida ativa).

O `BlocListener` callback e `void` — nao ha como fazer `await` de forma confiavel.

**Decisao:**
Mover `ForegroundTaskConfig.start()` e `stop()` para dentro do `TrackingBloc`:
- `_onStartTracking`: `await start()` apos session save, antes do stream listen
- `_onStopTracking`: `await stop()` apos cancelar subscription
- `close()`: `await stop()` como safety net

O flutter_bloc processa eventos sequencialmente (`on<Event>` handlers sao async e
executam um por vez). Portanto, `stop()` so executa apos `start()` completar —
eliminando a race condition.

Cada chamada e envolvida em try-catch proprio (non-blocking) — falha do foreground
service nao impede o tracking de funcionar.

Removidas as chamadas fire-and-forget do `tracking_screen.dart` e os imports
nao utilizados (`ForegroundTaskConfig`, `ServiceRequestResult`).

**Arquivos modificados (2):**
- `lib/presentation/blocs/tracking/tracking_bloc.dart` — await start/stop + import
- `lib/presentation/screens/tracking_screen.dart` — removidas chamadas + imports

**Risco:** Nenhum. O foreground service agora tem sequenciamento garantido.
Se `start()` ou `stop()` falharem, o tracking continua normalmente.

---

## DECISAO 031 — SessionId UUID v4 em vez de timestamp

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §2.2 F-02 identificou que `_sessionId` era gerado como
`DateTime.now().millisecondsSinceEpoch.toString()` (ex: `"1740000000000"`). Colisao
possivel se duas sessoes iniciarem no mesmo milissegundo (improvavel em uso normal,
possivel em testes automatizados ou reinicio rapido).

O `UserIdentityProvider` ja tinha um gerador UUID v4 privado usando `Random.secure()`.

**Decisao:**
1. Extrair o gerador UUID v4 para `lib/core/utils/generate_uuid_v4.dart` (funcao publica)
2. Substituir `now.toString()` por `generateUuidV4()` no `TrackingBloc._onStartTracking`
3. Atualizar `UserIdentityProvider` para usar a funcao compartilhada
4. Nao adicionar package externo (`uuid`) — a implementacao propria e correta e minimalista

O campo `_startMs` continua usando timestamp para calculo de `elapsedMs`. Apenas o ID
da sessao muda para UUID.

**Arquivos criados (1):**
- `lib/core/utils/generate_uuid_v4.dart`

**Arquivos modificados (2):**
- `lib/presentation/blocs/tracking/tracking_bloc.dart` — import + `generateUuidV4()`
- `lib/core/auth/user_identity_provider.dart` — import compartilhado, removida impl privada

**Risco:** Nenhum. O campo `sessionUuid` no Isar e `String`. Nenhum codigo parseia
o sessionId como inteiro. UUIDs v4 tem probabilidade de colisao de ~1 em 2^122.

---

## DECISAO 032 — Reconexao GPS em vez de StopTracking quando stream fecha

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §4.1 TESTE 01 (Tunel) e §6 Roadmap item #5 identificaram
que quando o GPS stream fecha (usuario desliga GPS, tunel, etc), o bloc dispara
`StopTracking`, finalizando a sessao. Dados coletados ate o momento sao preservados,
mas a corrida e interrompida desnecessariamente.

Cenarios reais: tuneis, passarelas subterraneas, buildings com sinal fraco.
O corredor espera que o app aguarde o GPS voltar sem perder a sessao.

**Decisao:**
Implementar reconexao GPS com timeout:

1. Novo evento `GpsStreamEnded` — disparado pelo `onDone` do stream GPS
2. Novo campo `gpsLost` em `TrackingActive` — UI mostra banner "reconnecting"
3. Handler `_onGpsStreamEnded`:
   - Flush buffer (salvar pontos coletados ate o momento)
   - Setar `gpsLost = true`
   - Iniciar timer periodico (5s) que tenta resubscrever ao GPS
4. Reconexao:
   - A cada 5s, verifica `ensureLocationReady()` + tenta `watch()` novamente
   - Se GPS voltar, novo `LocationPointReceived` reseta `gpsLost = false`
   - Se 60s sem reconexao, dispara `StopTracking` (timeout seguro)
5. UI: banner vermelho "GPS signal lost — reconnecting…" com spinner
   sobre a area do mapa

O `StopTracking` manual do usuario continua funcionando normalmente
(cancela timer de reconexao).

**Arquivos modificados (3):**
- `lib/presentation/blocs/tracking/tracking_event.dart` — `GpsStreamEnded`
- `lib/presentation/blocs/tracking/tracking_state.dart` — `gpsLost` flag
- `lib/presentation/blocs/tracking/tracking_bloc.dart` — handler + reconnect logic
- `lib/presentation/screens/tracking_screen.dart` — GPS lost banner

**Risco:** Baixo. Se a reconexao falhar, o timeout de 60s garante que a sessao
sera finalizada. O timer e cancelado em `close()`, `_onStopTracking()`, e
`_onStartTracking()`. Nao ha risco de timer orfao.

---

## DECISAO 033 — Auto-sync ao abrir app e ao restaurar conectividade

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §4.1 TESTE 04 (Desconexao Prolongada) e §6 Roadmap item #9
identificaram que o sync de sessoes pendentes so acontecia:
1. Fire-and-forget no `_onStopTracking` (pode falhar silenciosamente)
2. Botao manual "Sync" no HistoryScreen

Se o usuario correr offline e abrir o app horas depois com internet, as sessoes
permaneciam pendentes ate clicar sync manualmente.

**Decisao:**
Criar `AutoSyncManager` com duas triggers:
1. **App start**: `syncPending()` chamado em `main()` apos service locator
2. **Connectivity restored**: `connectivity_plus.onConnectivityChanged` detecta
   transicao none → connected e dispara `syncPending()`

Protecoes:
- Cooldown de 30s entre syncs (evita spam em WiFi instavel)
- Guard contra concorrencia (`_syncing` flag)
- Erros logados mas nunca propagados (nao pode crashar o app)
- `SyncNotConfigured`/`SyncNotAuthenticated` retornados silenciosamente

O botao manual no HistoryScreen continua funcionando como fallback.

**Arquivos criados (1):**
- `lib/core/sync/auto_sync_manager.dart`

**Arquivos modificados (1):**
- `lib/main.dart` — instancia + `await autoSync.init()`

**Risco:** Nenhum. O `syncPending()` ja era seguro (try-catch interno, processa
sequencialmente, first-failure semantics). O listener de connectivity e cancelavel.

---

## DECISAO 034 — Cache incremental de _filterPoints no TrackingBloc

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §2.2 F-06 identificou que `_computeMetrics()` chamava
`_filterPoints(_points)` a cada tick GPS (~1s), reprocessando ate 300 pontos do zero.
O filtro aplica haversine em cada ponto (accuracy → speed → drift), resultando em
~300 calculos trigonometricos por tick.

**Decisao:**
Implementar cache incremental `_getFilteredPoints()`:
1. Manter `_filteredCache` e `_filteredUpTo` (quantos raw points ja foram processados)
2. A cada tick, filtrar apenas os pontos novos, usando o ultimo ponto aceito como anchor
3. Quando `_points` e trimado (> 300 → 300), detectar via `_filteredUpTo > _points.length`
   e fazer rebuild completo (ocorre ~1x a cada 300 ticks)

Tecnica do "anchor": passa `[lastAccepted, ...newPoints]` ao filtro existente, depois
descarta o anchor do resultado. Reutiliza `FilterLocationPoints` sem modificacao.

Custo amortizado: O(1) por tick (1-2 pontos novos). Rebuild O(n) so no trim (~1x/300).
Antes: O(300) por tick. Reducao de ~99.7% no trabalho de filtragem durante corrida.

Cache resetado em `_onStartTracking` (nova sessao).

**Arquivos modificados (1):**
- `lib/presentation/blocs/tracking/tracking_bloc.dart` — `_getFilteredPoints()` + campos

**Risco:** Nenhum. A logica de filtragem e identica (mesmo `FilterLocationPoints`).
O cache e descartavel — qualquer inconsistencia resulta em rebuild completo.

---

## DECISAO 035 — Autenticacao anonima via Supabase para desbloquear sync

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §1.3 e §6 item #6 identificaram que o sync sempre falhava
com `SyncNotAuthenticated` porque nenhum usuario estava autenticado no Supabase.
`SyncService.userId` retornava `null` → `SyncRepo.syncPending()` abortava.

Sem autenticacao, sessoes nunca sincronizavam para o backend, mesmo com internet OK
e Supabase configurado. O `UserIdentityProvider` usava um UUID local que nao tinha
relacao com nenhum usuario Supabase.

**Decisao:**
Adicionar `signInAnonymously()` ao `UserIdentityProvider.init()`:

1. Se Supabase configurado E ja existe sessao (persistida entre restarts) → usar
2. Se Supabase configurado E nao existe sessao → `signInAnonymously()` automatico
3. Se Supabase nao configurado OU sign-in falha (offline) → fallback UUID local

O sign-in anonimo do Supabase:
- Cria um usuario real com UUID no Supabase Auth
- Sessao persistida automaticamente pelo `supabase_flutter` SDK (SharedPrefs/Keychain)
- Nao requer email/senha — zero fricao para o usuario
- Pode ser "upgraded" para email/social via `updateUser()` ou `linkIdentity()` no futuro
- Funciona identicamente ao usuario normal para Storage/Postgres (RLS via `auth.uid()`)

Apos sign-in, `SyncService.userId` retorna o UUID real do Supabase →
`SyncRepo.syncPending()` funciona → sessoes sincronizam automaticamente via
`AutoSyncManager` (Fix #14).

O campo `isAnonymous` no `UserIdentityProvider` agora reflete:
- `true` = UUID local apenas (sem Supabase, sem sync)
- `false` = Supabase autenticado (anonimo ou email, sync funciona)

O banner "Offline Mode" no `MoreScreen` so aparece quando `isAnonymous == true`
(sem Supabase), nao quando o usuario tem auth anonima.

**Arquivos modificados (1):**
- `lib/core/auth/user_identity_provider.dart` — signInAnonymously + fallback

**Risco:** Baixo. Se `signInAnonymously()` falhar (offline no primeiro launch),
o app funciona normalmente com UUID local. Na proxima abertura com internet,
o sign-in e tentado novamente. Dados locais (Isar) nao sao afetados.

Risco de migracao: sessoes criadas com UUID local antes do primeiro sign-in
terao `userId` local no Isar. O sync usa o `SyncService.userId` (Supabase), nao
o local. Sessoes antigas sincronizarao com o userId correto do Supabase no upload.

---

## DECISAO 036 — CameraFollow + AutoBearing integrados na TrackingScreen

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §3.1 identificou `CameraFollowController` e `AutoBearing`
como codigo morto — implementados mas nunca instanciados. O item #10 do roadmap
(P4 — MELHORIA) pedia integrar ambos para que a camera siga o corredor suavemente.

**Decisao:**

1. Estendido `CameraFollowController.update()` e `jumpTo()` para aceitar `bearing`
   opcional. Quando fornecido, usa `CameraUpdate.newCameraPosition` com:
   - `zoom: 16.5` (bom para corrida)
   - `tilt: 45.0` (perspectiva 3D leve)
   - `bearing` computado via `AutoBearing`

2. Integrado na `_TrackingViewState`:
   - `attach()` em `_onStyleLoaded`, `detach()` em `dispose()`
   - Cada tick `TrackingActive` computa bearing via `AutoBearing.fromPoint()` com
     fallback para `AutoBearing.fromTwoPoints()`
   - Primeiro GPS fix → `jumpTo()` (sem throttle)
   - Follow mode re-habilitado automaticamente ao iniciar nova sessao

3. Deteccao de gesto do usuario via `Listener.onPointerDown` no mapa:
   - Qualquer toque no mapa desabilita follow mode
   - Um `FloatingActionButton.small` com icone `my_location` aparece quando
     follow esta desabilitado durante tracking ativo
   - Ao tocar no FAB, `_recenter()` re-habilita follow e faz `jumpTo()` para
     a posicao atual

**Arquivos modificados (2):**
- `lib/presentation/map/camera_controller.dart` — bearing + tilt + zoom
- `lib/presentation/screens/tracking_screen.dart` — integracao completa

**Risco:** Baixo. `CameraFollowController` ja era throttled (1 update/s).
`AutoBearing` ja tinha testes unitarios. O `Listener.onPointerDown` nao consome
o evento (nao interfere com gestos do MapLibre). FAB so aparece durante tracking.

---

## DECISAO 037 — Sentry init + AppLogger.onError hook

**Data:** 2026-02-18
**Contexto:** AUDIT_REPORT §1.4 e roadmap item #4 (P1 — CRITICO): Sentry DSN era
placeholder, `Sentry.init()` nunca era chamado, e `AppLogger.onError` existia mas
nao estava conectado a nenhum servico de crash reporting.

**Decisao:**

1. Adicionada dep `sentry_flutter: ^9.13.0` ao `pubspec.yaml`.

2. Reestruturado `main.dart` para usar o pattern `SentryFlutter.init(appRunner:)`:
   - `main()` inicializa Sentry primeiro (se DSN configurado)
   - `appRunner: _bootstrap` executa toda a inicializacao dentro da guarded zone
   - Erros durante init (Supabase, Isar, etc.) sao automaticamente capturados
   - Se Sentry nao configurado, `_bootstrap()` e chamado diretamente

3. Conectado `AppLogger.onError` ao Sentry:
   ```dart
   AppLogger.onError = (message, error, stack) {
     Sentry.captureException(error ?? message, stackTrace: stack);
   };
   ```
   Todos os `AppLogger.error()` em qualquer parte do app agora enviam o erro
   para o Sentry automaticamente.

4. Configuracao via `AppConfig`:
   - `options.dsn` = `SENTRY_DSN` do `.env`
   - `options.environment` = `dev` ou `prod` (via `APP_ENV`)
   - `options.tracesSampleRate` = 1.0 em dev, 0.2 em prod

**Cobertura de captura:**
- Flutter framework errors (via `SentryFlutter` integration automatica)
- Dart uncaught exceptions (via guarded zone do `appRunner`)
- App-level errors (via `AppLogger.onError` hook)

**Arquivos modificados (1) + dep:**
- `lib/main.dart` — reestruturado com `SentryFlutter.init` + `_bootstrap`
- `pubspec.yaml` — adicionado `sentry_flutter`

**Risco:** Nenhum. Se o DSN estiver vazio, Sentry e completamente ignorado.
O app funciona identicamente ao estado anterior sem a dep.

---

## DECISAO 038 — Remover auto-anonymous sign-in; forcar login antes de Home (Hotfix v1.0.1)

**Data:** 2026-02-23
**Contexto:** Teste no device real revelou que o app ia direto pra Home sem mostrar
tela de login. A causa era DECISAO 035 (auto-anonymous sign-in): `RemoteAuthDataSource.init()`
chamava `signInAnonymously()` no boot, criando sessao Supabase anonima. O `AuthGate`
via essa sessao como "usuario logado" e mandava direto pra Home.

Alem disso, o botao "Criar conta" do `LoginRequiredSheet` navegava para `AuthGate`,
que routeava anonymous → home, criando um loop silencioso.

**Decisao:**
1. Remover `signInAnonymously()` do `RemoteAuthDataSource.init()`. Sem sessao → retorna
   `AuthUser(id:'', isAnonymous:true)` sem criar sessao no Supabase.
2. Mudar `AuthGate._resolve()`: anonymous → `welcome` (nao `home`).

O fluxo correto agora e:
- Primeiro launch → sem sessao → Welcome → Login (social) → Onboarding → Home
- Returnings → sessao Supabase persistida → AuthGate → profile check → Home

**Supersede:** DECISAO 035 (parcialmente). O sync continua funcionando para usuarios
autenticados via social login. Usuarios nao logados nao sincronizam (comportamento correto).

**Arquivos modificados (2):**
- `lib/data/datasources/remote_auth_datasource.dart` — removido signInAnonymously do init
- `lib/presentation/screens/auth_gate.dart` — anonymous → welcome (nao home)

**Risco:** Baixo. Usuarios existentes com sessao Supabase (social login) nao sao afetados.
Usuarios anonimos verao a tela de login na proxima abertura.

---

## DECISAO 039 — Posicao inicial do mapa via getLastKnownPosition (Hotfix v1.0.1)

**Data:** 2026-02-23
**Contexto:** O mapa na TrackingScreen e MapScreen usava coordenadas hardcoded de
Sao Paulo (`-23.5505, -46.6333`). Usuarios em outras cidades viam SP no mapa.

**Decisao:**
1. Fallback mudado para Brasilia (`-15.7975, -47.8919`) — centro geografico do Brasil
2. `TrackingScreen` agora tenta `Geolocator.getLastKnownPosition()` no `initState()`
   e centraliza o mapa na posicao real do usuario (sem solicitar permissao, usa cache)
3. Quando o tracking inicia, o camera follow ja move para a posicao GPS real

**Arquivos modificados (2):**
- `lib/presentation/screens/tracking_screen.dart` — getLastKnownPosition + fallback Brasilia
- `lib/presentation/screens/map_screen.dart` — fallback Brasilia

**Risco:** Nenhum. `getLastKnownPosition()` nao solicita permissao (usa cache do OS).
Se falhar, mantem o fallback Brasilia. O camera follow corrige na primeira atualizacao GPS.

---

## DECISAO 040 — Catch Object (nao Exception) no TrackingBloc (Hotfix v1.0.1)

**Data:** 2026-02-23
**Contexto:** O app crashava ao clicar "Iniciar corrida". O `TrackingBloc._onStartTracking`
usava `on Exception catch` que nao captura `Error` nativo (ex: `PlatformError` do
foreground service, `MissingPluginException` do geolocator).

**Decisao:**
Mudar `on Exception catch` para `catch` (captura `Object`) em 3 pontos:
1. `_onStartTracking` — try externo
2. `ForegroundTaskConfig.start()` — try interno (non-blocking)
3. `ForegroundTaskConfig.stop()` — try interno (non-blocking)
4. `close()` — try interno

Erros nativos agora sao capturados e logados (enviados ao Sentry via `AppLogger.onError`),
e o usuario ve a mensagem "Nao foi possivel iniciar a corrida" em vez de crash.

**Arquivos modificados (1):**
- `lib/presentation/blocs/tracking/tracking_bloc.dart` — catch Object em 4 pontos

**Risco:** Nenhum. Lint `avoid_catches_without_on_clauses` emite info (nao erro).
A captura ampla e intencional para evitar crashes em producao.

---

## DECISAO 041 — Env files no diretorio Flutter (omni_runner/) (Hotfix v1.0.1)

**Data:** 2026-02-23
**Contexto:** O APK v1.0.0 foi buildado com `--dart-define-from-file=../.env.dev`.
Flutter resolve paths relativos ao CWD (que e `omni_runner/`), mas os `.env` files
estavam em `project-running/` (parent dir). Resultado: todas as env vars estavam
vazias → Supabase nao inicializou → modo mock → sem auth, sem sync, sem mapa.

**Decisao:**
1. Copiar `.env.dev`, `.env.prod`, `.env.example` para `omni_runner/`
2. `preflight_check.sh` atualizado: busca local primeiro, fallback parent dir com warning
3. Comando build correto: `flutter build apk --dart-define-from-file=.env.dev`

**Arquivos modificados (1):**
- `scripts/preflight_check.sh` — busca local + fallback parent

**Risco:** Nenhum. `.gitignore` (root e omni_runner) ja exclui `.env*`.
Env files nunca sao commitados.

---

## DECISAO 042 — Release SHA-1 no Firebase (Google Sign-In) (Hotfix v1.0.2)

**Data:** 2026-02-23
**Contexto:** Google Sign-In retornava `PlatformException(sign_in_failed, t2.d: 10)` —
erro 10 = `DEVELOPER_ERROR`. O `google-services.json` so tinha o SHA-1 do debug keystore
registrado no Firebase. O APK release e assinado com keystore diferente (SHA-1 diferente).

**Decisao:**
Adicionar SHA-1 do release keystore (`72:5A:90:7B:2C:4F:78:81:36:C0:DE:82:94:2C:88:EB:1F:C1:EB:09`)
no Firebase Console → Project Settings → Android app → Add fingerprint.
Baixar novo `google-services.json` atualizado com ambos os OAuth clients (debug + release).

**Arquivos modificados (1):**
- `android/app/google-services.json` — substituido pelo novo download do Firebase

**Risco:** Nenhum. E configuracao padrao do Firebase para APKs de release.

---

## DECISAO 043 — ForegroundServiceType location-only (sem connectedDevice) (Hotfix v1.0.3)

**Data:** 2026-02-23
**Contexto:** No Android 14+ (targetSDK=36), iniciar um foreground service com tipo
`connectedDevice` exige que permissoes BLE sejam concedidas em runtime. O manifest
declarava `foregroundServiceType="location|connectedDevice"`, mas BLE e opcional (nem todo
usuario tem monitor cardiaco). Sem permissao BLE concedida, o serviço crashava com
`SecurityException` ao iniciar a corrida.

**Decisao:**
1. Mudar `foregroundServiceType` de `location|connectedDevice` para apenas `location`
2. Remover permissao `FOREGROUND_SERVICE_CONNECTED_DEVICE` do manifest
3. Manter permissoes BLE (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`) para conexao com monitor cardiaco
4. BLE funciona independentemente do tipo de FGS — o foreground service so precisa manter o processo vivo

**Supersede:** Configuracao original do manifest que incluia `connectedDevice`.

**Arquivos modificados (1):**
- `android/app/src/main/AndroidManifest.xml` — FGS type e permissao removidos

**Risco:** Nenhum para GPS tracking. Se no futuro Android exigir `connectedDevice` para BLE
em background, sera necessario solicitar permissao BLE antes de iniciar o FGS.

---

## DECISAO 044 — SECURITY DEFINER para coaching_members RLS (Hotfix v1.0.3)

**Data:** 2026-02-23
**Contexto:** A RLS policy `coaching_members_group_read` fazia self-reference:
`EXISTS (SELECT 1 FROM coaching_members WHERE ...)` dentro da propria tabela,
causando `PostgrestException: infinite recursion detected in policy` (erro 42P17).

**Decisao:**
Criar funcao `user_coaching_group_ids()` com `SECURITY DEFINER` que:
1. Executa com permissoes do owner (bypassa RLS)
2. Retorna `SETOF uuid` com os `group_id` do usuario autenticado
3. A policy `coaching_members_group_read` usa `group_id IN (SELECT user_coaching_group_ids())`

Isso quebra o ciclo recursivo porque a funcao SECURITY DEFINER nao aciona policies RLS.

**Arquivos modificados (1):**
- `supabase/migrations/20260223140000_fix_coaching_members_rls_recursion.sql`

**Risco:** Funcoes SECURITY DEFINER executam com permissoes elevadas. A funcao e minima
(retorna apenas group_ids do `auth.uid()` atual) e nao aceita parametros manipulaveis.

---

## DECISAO 045 — Fix _accumDist: avancar _prevPt quando filter aceita pontos (Hotfix v1.0.4)

**Data:** 2026-02-23
**Contexto:** Distancia ficava em 0m durante corrida apesar de 64 pontos GPS registrados.
O metodo `_accumDist` guardava o primeiro ponto GPS como `_prevPt`. Se esse ponto tinha
accuracy > 15m (comum no cold start GPS), o `FilterLocationPoints` rejeitava esse ponto em
TODA chamada subsequente, deixando `f.length < 2`, e `_prevPt` nunca avancava.

**Decisao:**
Quando o filter aceita ao menos 1 ponto (`f.isNotEmpty`), avancar `_prevPt = f.last`.
Isso garante que um ponto ruim no inicio nao trava a acumulacao de distancia para sempre.

**Arquivos modificados (1):**
- `lib/presentation/blocs/tracking/tracking_bloc.dart` — `_accumDist()`

**Risco:** Perda de 1 segmento de distancia quando o primeiro ponto e ruim (compensado
pela continuidade da acumulacao nos pontos seguintes).

---

## DECISAO 046 — maxAccuracyMeters de 15m para 25m (Hotfix v1.0.4)

**Data:** 2026-02-23
**Contexto:** GPS de celular em area urbana frequentemente reporta accuracy de 15-25m.
O threshold de 15m era muito restritivo, rejeitando pontos validos e contribuindo para
distancia 0m. Apps de corrida como Strava usam thresholds de 20-30m.

**Decisao:** Relaxar `maxAccuracyMeters` de 15.0 para 25.0 em `FilterLocationPoints`
e `AccumulateDistance`. Todos os 34 testes unitarios continuam passando.

**Arquivos modificados (2):**
- `lib/domain/usecases/filter_location_points.dart`
- `lib/domain/usecases/accumulate_distance.dart`

**Risco:** Pontos com accuracy 15-25m agora sao aceitos, podendo adicionar ate ~25m
de erro por ponto. Mitigado pelo drift filter (3m minimum movement) e speed sanity check.

---

## DECISAO 047 — TimerTick periodico + wall-clock elapsed (Hotfix v1.0.4)

**Data:** 2026-02-23
**Contexto:** O timer na UI so atualizava quando novos pontos GPS chegavam. Com
`distanceFilter: 5m`, se o usuario se movesse devagar, o timer pulava segundos
(ex: 09:41 → 09:46). Alem disso, elapsed era calculado por timestamp GPS, que
pode ter drift em relacao ao relogio do device.

**Decisao:**
1. Novo event `TimerTick` no TrackingBloc (classe sealed em tracking_event.dart)
2. `Timer.periodic(1s)` dispara `add(TimerTick())` durante tracking ativo
3. Handler `_onTimerTick` emite estado atualizado a cada segundo
4. `_computeMetrics` usa `DateTime.now()` (wall-clock) para elapsed

**Arquivos modificados (2):**
- `lib/presentation/blocs/tracking/tracking_event.dart` — novo `TimerTick`
- `lib/presentation/blocs/tracking/tracking_bloc.dart` — timer, handler, wall-clock elapsed

**Risco:** Nenhum significativo. Timer e cancelado em `_onStopTracking` e `close()`.
Wall-clock elapsed e consistente com a experiencia do usuario.

---

## DECISAO 048 — HistoryScreen reload ao trocar aba (Hotfix v1.0.4)

**Data:** 2026-02-23
**Contexto:** `HomeScreen` usa `IndexedStack` → todos os tabs sao criados no `initState`.
`HistoryScreen._loadSessions()` roda apenas 1x no `initState`. Trocar de aba nao recarrega.
A corrida so aparecia apos pull-to-refresh manual (nao obvio para o usuario).

**Decisao:**
1. Adicionar prop `isVisible` ao `HistoryScreen`
2. `didUpdateWidget` detecta transicao `!isVisible → isVisible` → chama `_loadSessions()`
3. `HomeScreen` passa `HistoryScreen(isVisible: _tab == 2)` inline no `build()`

Padrao comum em Flutter para `IndexedStack`: prop de visibilidade + `didUpdateWidget`.

**Arquivos modificados (2):**
- `lib/presentation/screens/home_screen.dart` — tabs inline, `isVisible` prop
- `lib/presentation/screens/history_screen.dart` — `isVisible` + `didUpdateWidget`

**Risco:** Nenhum. Reload e uma query Isar local (<1ms). Sem impacto em performance.

---

## DECISAO 049 — GoogleSignIn().signOut() no logout (Hotfix v1.0.5)

**Data:** 2026-02-23
**Contexto:** Ao sair da conta e tentar logar novamente, o app auto-selecionava a
conta Google anterior sem mostrar o account picker. Isso porque `signOut()` so limpava
a sessao Supabase, mas o GoogleSignIn SDK mantinha a credential em cache interno.

**Decisao:** Adicionar `GoogleSignIn().signOut()` antes de `_auth.signOut()` no
`RemoteAuthDataSource.signOut()`. O catch silencioso (`catch (_) {}`) garante que falha
do Google (ex: login nao foi feito via Google) nao bloqueia o signOut principal.

**Arquivos modificados (1):**
- `lib/data/datasources/remote_auth_datasource.dart`

**Risco:** Nenhum. `GoogleSignIn().signOut()` e seguro chamar mesmo se o login nao
foi feito via Google — retorna silently.

---

## DECISAO 050 — Rename "Sequencias" para "Consistencia" (Hotfix v1.0.5)

**Data:** 2026-02-23
**Contexto:** O item "Sequencias" com subtitulo "Quem esta em sequencia na assessoria"
no ProgressHubScreen era vago e confuso para usuarios. A funcionalidade mostra ranking
de dias consecutivos correndo (streaks).

**Decisao:** Renomear para "Consistencia" com subtitulo "Ranking de dias consecutivos
correndo". Todos os textos na StreaksLeaderboardScreen atualizados para usar linguagem
mais clara.

**Arquivos modificados (2):**
- `lib/presentation/screens/progress_hub_screen.dart` — titulo e subtitulo
- `lib/presentation/screens/streaks_leaderboard_screen.dart` — AppBar, secoes, mensagens

**Risco:** Nenhum. Mudanca puramente cosmetic (UI text).

---

## DECISAO 051 — SECURITY DEFINER para group_members RLS (Hotfix v1.0.5)

**Data:** 2026-02-23
**Contexto:** Mesma causa do BUG-06 (coaching_members). A policy `group_members_read`
fazia self-reference: `EXISTS (SELECT 1 FROM group_members WHERE ...)` dentro de uma
policy na propria tabela `group_members` → recursao infinita.

A policy `group_members_update_mod` tambem fazia self-reference no branch OR para
verificar se o user e admin/moderador.

**Decisao:** Duas funcoes `SECURITY DEFINER`:
1. `user_social_group_ids()` — retorna `group_id`s do user autenticado (bypassa RLS)
2. `is_group_admin_or_mod(p_group_id)` — verifica se user e admin/mod de um grupo

Policies recriadas usando essas funcoes em vez de subqueries self-referencing.

**Arquivos modificados (2):**
- `supabase/migrations/20260223160000_fix_group_members_rls_recursion.sql` — migration
- `supabase/schema.sql` — schema atualizado

**Risco:** Nenhum. Mesmo padrao aplicado com sucesso em coaching_members (DECISAO 044).

---

## DECISAO 052 — await _completeSocialProfile + retry em chamadas criticas (Hotfix v1.0.5)

**Data:** 2026-02-23
**Contexto:** Ao criar assessoria com conta diferente, o app falhava com
`ClientException: Software caused connection abort`. A funcao `_completeSocialProfile()`
era chamada com `unawaited` (fire-and-forget) apos login social, podendo falhar
silenciosamente e deixar o user sem profile. Alem disso, chamadas de rede criticas
como `set-user-role` e `fn_create_assessoria` nao tinham retry, falhando na primeira
instabilidade de rede.

**Decisao:**
1. `_completeSocialProfile()` agora e `await`ed em todos os sign-in flows
   (Google, Apple, Instagram, TikTok), com retry 3x e backoff exponencial
2. `set-user-role` (OnboardingRoleScreen) tem retry 3x com backoff
3. `fn_create_assessoria` (StaffSetupScreen) tem retry 3x com backoff
4. Mensagens de erro atualizadas para mencionar verificacao de conexao

**Arquivos modificados (3):**
- `lib/data/datasources/remote_auth_datasource.dart` — await + retry
- `lib/presentation/screens/onboarding_role_screen.dart` — retry
- `lib/presentation/screens/staff_setup_screen.dart` — retry

**Risco:** `await` adiciona latencia ao login (~1-2s para a Edge Function),
mas garante que o profile existe antes de prosseguir. O retry com backoff
evita loops infinitos (max 3 tentativas).

---

## DECISAO 053 — PopScope + onBack para navegacao de volta no onboarding (Hotfix v1.0.5)

**Data:** 2026-02-23
**Contexto:** Nas telas de onboarding (role, assessoria, staff), pressionar o botao voltar
do Android fechava o app. Isso porque `AuthGate` renderiza as telas inline via `setState`
(switch no `build()`), sem `Navigator.push`. O back button tenta `pop()` o `AuthGate`,
que e a raiz da stack (`pushAndRemoveUntil`), e o app fecha.

**Decisao:**
1. `PopScope(canPop: false)` no `AuthGate` intercepta o back button fisico do Android
   quando `_dest` e onboarding, joinAssessoria ou staffSetup
2. Novo callback `onBack` em `OnboardingRoleScreen`, `StaffSetupScreen` e `JoinAssessoriaScreen`
3. `onBack` chama `authRepo.signOut()` + navega para welcome (mesmo comportamento de "sair da conta")
4. Botao seta (←) visual no topo de cada tela de onboarding

**Arquivos modificados (4):**
- `lib/presentation/screens/auth_gate.dart` — `PopScope`, `_onBackToLogin`, `onBack` props
- `lib/presentation/screens/onboarding_role_screen.dart` — `onBack` prop + botao
- `lib/presentation/screens/staff_setup_screen.dart` — `onBack` prop + botao
- `lib/presentation/screens/join_assessoria_screen.dart` — `onBack` prop + botao

**Risco:** Nenhum. `signOut` ja e robusto (limpa Supabase + Google cache).
O user pode voltar e entrar com outra conta normalmente.

---

## DECISAO 054 — Fix fn_create_assessoria: created_at_ms faltando (Hotfix v1.0.5)

**Data:** 2026-02-23
**Contexto:** Criar assessoria sempre falhava. A funcao `fn_create_assessoria` fazia
`INSERT INTO coaching_groups (id, name, coach_user_id, city)` sem incluir `created_at_ms`,
que e `NOT NULL` sem default. O INSERT falhava com constraint violation.
A variavel `v_now_ms` ja era calculada na funcao mas so era usada no INSERT de
`coaching_members`, nao no de `coaching_groups`.

**Decisao:** Adicionar `created_at_ms` ao INSERT de `coaching_groups` usando `v_now_ms`.
Fix aplicado diretamente no banco via Supabase Management API (server-side, sem novo APK).

**Arquivos modificados (1):**
- `supabase/migrations/20260223170000_fix_fn_create_assessoria_created_at_ms.sql`

**Risco:** Nenhum. `v_now_ms` ja existia e era correto. O INSERT agora inclui todos
os campos NOT NULL obrigatorios.

---

## DECISAO 055 — Staff Dashboard: query Supabase direto + HomeScreen role-aware (v1.0.6)

**Data:** 2026-02-23
**Contexto:** O `StaffDashboardScreen` usava `ICoachingMemberRepo.getByUserId()` que le
do Isar local. Porem a assessoria e criada server-side via `fn_create_assessoria` RPC, que
nunca popula o Isar. Resultado: `_groupId` vazio, todos botoes inativos.
Alem disso, o `HomeScreen` mostrava 4 tabs (Inicio/Correr/Historico/Mais) para ambos roles,
e o `MoreScreen` mostrava itens de atleta (Minha Assessoria, Audio, Wearables) para staff.

**Decisao:**
1. `StaffDashboardScreen._loadStatus()` agora faz query direto ao Supabase
   (`from('coaching_members').select().eq('user_id', uid)`) ao inves de ler do Isar
2. `HomeScreen` e role-aware: staff ve 2 tabs (Inicio + Mais), atleta ve 4 (+ Correr + Historico)
3. `MoreScreen` aceita `userRole` e filtra itens: staff nao ve Assessoria section, Integracoes,
   Audio, Coming Soon tiles
4. `_openStaffQrHub()` tambem faz query direto ao Supabase

**Arquivos modificados (3):**
- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/screens/staff_dashboard_screen.dart`
- `lib/presentation/screens/more_screen.dart`

**Risco:** Baixo. Cada abertura do dashboard faz 2-3 queries ao Supabase (coaching_members,
coaching_groups, clearing_cases). Em redes lentas pode demorar, mas ha loading indicator.
A alternativa seria implementar sync bidirecional Isar↔Supabase, mas e muito mais complexo.

---

## DECISAO 057 — Strava como fonte unica de dados de atividade

**Data:** 2026-02-26
**Contexto:** O app tinha tracking GPS proprio (TrackingScreen + TrackingBloc + mapa MapLibre + botao "Correr").
Porem, a maioria dos atletas ja usa Strava com seus relogios. Manter tracking proprio adiciona
complexidade (GPS, foreground service, BLE, audio coach) com pouco beneficio. Alem disso, o
Strava gratuito fornece todos os dados necessarios para anti-cheat: GPS completo, HR, pace,
elapsed/moving time, summary_polyline.

**Decisao:**
1. Strava e a fonte primaria e unica de dados de atividade
2. A aba "Correr" (TrackingScreen) foi substituida pela aba "Hoje" (TodayScreen)
3. Atletas que usam Nike Run Club, adidas Running, etc. podem sincronizar esses apps ao Strava
4. Ao conectar Strava, as ultimas 20 corridas sao importadas para calibrar nivel do atleta
5. Scope `activity:read_all` usado para acessar historico completo
6. Arquitetura extensivel: `IStravaAuthRepository` abstrai; novos provedores podem ser adicionados
7. TrackingScreen/TrackingBloc permanecem no codigo mas inacessiveis na navegacao

**Vantagens:**
- Strava funciona com qualquer relogio/app (universalidade)
- Dados ricos (GPS, HR, cadencia) sem custo de implementacao
- Webhooks para importacao automatica
- Comunidade ja estabelecida (menos atrito para o atleta)
- Menos manutencao de GPS, BLE, foreground service

**Desvantagens:**
- Dependencia de terceiro (mitigado: arquitetura extensivel)
- Rate limits do Strava (mitigado: StravaHttpClient com retry + 429 handling)
- Atletas sem Strava precisam criar conta (aceito: Strava e gratuito)

**Arquivos modificados (4):**
- `lib/presentation/screens/home_screen.dart` (TrackingScreen → TodayScreen)
- `lib/features/strava/data/strava_http_client.dart` (+getAthleteActivities)
- `lib/features/strava/presentation/strava_connect_controller.dart` (+importStravaHistory)
- `lib/core/service_locator.dart` (+httpClient no controller)

**Risco:** Medio. Dependencia de API terceira, porem Strava e o padrao da industria e a arquitetura
permite adicionar outros provedores sem refatoracao significativa.

---

## DECISAO 058 — Aba "Hoje" (TodayScreen) substitui "Correr" (TrackingScreen)

**Data:** 2026-02-26
**Contexto:** Com a remocao do tracking GPS proprio (Decisao 057), a aba "Correr" perdeu sentido.
O app precisa manter engajamento e gamificacao sem oferecer tracking proprio.

**Decisao:**
1. Nova aba "Hoje" como hub diario de gamificacao
2. Componentes: StreakBanner, BoraCorrerCard (CTA → abre Strava), RunRecapCard (ultima corrida),
   comparacao com corrida anterior (% mais rapido/lento), botao compartilhar, diario de corrida
   (anotacao + humor), QuickStatsRow, ParkCheckinCard
3. Navegacao: Inicio | Hoje | Historico | Mais
4. Icone: `Icons.today_outlined` / `Icons.today`

**Arquivos criados (1):**
- `lib/presentation/screens/today_screen.dart`

**Arquivos modificados (1):**
- `lib/presentation/screens/home_screen.dart`

**Risco:** Nenhum. E uma tela nova sem dependencias criticas.

---

## DECISAO 059 — Parks Feature (leaderboard multi-tier, comunidade, segmentos)

**Data:** 2026-02-26
**Contexto:** No Brasil, muitos atletas correm em parques. O app pode aproveitar essa concentracao
geografica para criar comunidade, competicao local e engajamento.

**Decisao:**
1. Deteccao de parque via GPS polygon (ray-casting point-in-polygon)
2. 10 parques brasileiros seedados (Ibirapuera, Aterro do Flamengo, Barigui, etc.)
3. Leaderboard multi-tier com 5 niveis: Rei (top 1), Elite (top 3), Destaque (top 10),
   Pelotao (top 20), Frequentador (demais). Inspiracao em Strava KOM mas mais inclusivo.
4. 6 categorias de ranking: Pace, Distancia, Frequencia, Sequencia, Evolucao, Maior Corrida
5. Comunidade por parque: lista de corredores, corridas sociais (overlap de horario)
6. Segmentos com recordes (KOM-style dentro de parques)
7. Matchmaking prioriza oponentes do mesmo parque (campo preferred_park_id)
8. Park check-in automatico no TodayScreen quando ultima corrida foi em parque detectado

**Arquivos criados (5):**
- `lib/features/parks/domain/park_entity.dart`
- `lib/features/parks/data/park_detection_service.dart`
- `lib/features/parks/data/parks_seed.dart`
- `lib/features/parks/presentation/park_screen.dart`
- `lib/features/parks/presentation/my_parks_screen.dart`

**Arquivos modificados (3):**
- `lib/presentation/screens/athlete_dashboard_screen.dart` (+card Parques)
- `lib/presentation/screens/today_screen.dart` (+ParkCheckinCard)
- `lib/presentation/screens/matchmaking_screen.dart` (+preferred_park_id)

**Tabelas Supabase necessarias:**
- `park_activities`, `park_leaderboard`, `park_segments`

**Risco:** Baixo. Feature puramente aditiva, nao altera fluxos existentes.

---

## DECISAO 060 — Matchmaking: explicacao + Strava obrigatorio + park preference

**Data:** 2026-02-26
**Contexto:** Matchmaking era opaco para o atleta — nao explicava como funcionava nem exigia Strava.

**Decisao:**
1. TipBanner em ChallengesListScreen explicando matchmaking automatico
2. Banner de Strava nao conectado em ChallengesListScreen e MatchmakingScreen
3. Card "Como funciona?" no MatchmakingScreen com regras claras
4. Auto-deteccao de parque preferido (analise das ultimas 20 corridas)
5. Campo `preferred_park_id` enviado ao EF `matchmake` para priorizar adversarios do mesmo parque

**Arquivos modificados (3):**
- `lib/presentation/screens/challenges_list_screen.dart`
- `lib/presentation/screens/matchmaking_screen.dart`
- `lib/core/tips/first_use_tips.dart` (+matchmakingHowTo, +stravaConnect)

**Risco:** Nenhum. Melhoria de UX sem breaking changes.

---

## DECISAO 056 — Sync Supabase → Isar no dashboard staff (BUG-17)

**Data:** 2026-02-23
**Contexto:** O botao "Atletas" no dashboard staff abria `CoachingGroupDetailsScreen` via
`GetCoachingGroupDetails` use case, que le do Isar local. Como o Isar nunca era populado
(assessoria criada server-side), dava `CoachingGroupNotFound`.

**Decisao:** Apos buscar dados do Supabase no `_loadStatus()`, sincronizar ao Isar:
1. Salva `CoachingGroupEntity` completa (todos os campos, nao so nome)
2. Salva `CoachingMemberEntity` do staff
3. Busca e salva TODOS os membros do grupo

Auditoria preventiva: dos 9 botoes do dashboard, apenas "Atletas" usava Isar. Os outros 8
(Confirmacoes, Performance, Campeonatos, Convites, Creditos, Desafios, Administracao, Portal)
usam Supabase direto ou parametros passados.

**Arquivos modificados (1):**
- `lib/presentation/screens/staff_dashboard_screen.dart`

**Risco:** Nenhum. O sync e idempotente (Isar `put` faz upsert). Adiciona ~1 query extra
(buscar todos membros do grupo) mas e necessario para a tela de detalhes funcionar.

---

## DECISAO 061 — Fluxo de aprovacao de assessorias pela plataforma

**Data:** 2026-02-26
**Contexto:** Qualquer pessoa com role `ASSESSORIA_STAFF` podia criar uma assessoria via
`fn_create_assessoria` e ela ficava imediatamente visivel para atletas buscarem e entrarem.
Nao havia controle de qualidade nem curadoria por parte da plataforma.

**Decisao:** Toda assessoria criada agora inicia com `approval_status = 'pending_approval'`
e so se torna visivel/operacional apos aprovacao do administrador da plataforma.

**Mecanismo:**
1. `coaching_groups` recebeu colunas: `approval_status`, `approval_reviewed_at`,
   `approval_reviewed_by`, `approval_reject_reason`
2. `profiles` recebeu coluna `platform_role` (valor `'admin'` para o dono da plataforma)
3. Novas RPCs SECURITY DEFINER:
   - `fn_platform_approve_assessoria(group_id)` — marca como `approved`
   - `fn_platform_reject_assessoria(group_id, reason)` — marca como `rejected`
   - `fn_platform_suspend_assessoria(group_id, reason)` — marca como `suspended`
4. `fn_search_coaching_groups` e `fn_lookup_group_by_invite_code` filtram
   `approval_status = 'approved'` (exceto para platform admin)
5. `fn_create_assessoria` agora insere com `approval_status = 'pending_approval'`
6. Assessorias existentes foram marcadas como `approved` automaticamente na migration

**Portal (Next.js):**
- Nova rota `/platform/assessorias` com layout dedicado para platform admin
- API route `POST /api/platform/assessorias` para approve/reject/suspend
- `middleware.ts`: rotas `/platform/*` e `/api/platform/*` adicionadas a PUBLIC_PREFIXES
  (auth delegada ao `platform/layout.tsx` server component, evitando limitacoes do Edge Runtime)
- `platform/layout.tsx`: verifica `platform_role = 'admin'` com `force-dynamic`
- `no-access/page.tsx`: redireciona platform admins para `/platform/assessorias` com `force-dynamic`
- Sidebar do portal mostra link "Admin Plataforma" para quem tem `platform_role = 'admin'`
- **Deploy:** Vercel Root Directory configurado como `portal` (monorepo)

**Flutter:**
- `StaffDashboardScreen`: exibe tela de "Aguardando aprovacao" / "Nao aprovada" / "Suspensa"
  em vez do dashboard quando `approval_status != 'approved'`
- `StaffSetupScreen`: dialog pos-criacao informando que a assessoria aguarda aprovacao

**Arquivos criados (6):**
- `portal/src/app/platform/layout.tsx`
- `portal/src/app/platform/assessorias/page.tsx`
- `portal/src/app/platform/assessorias/actions.tsx`
- `portal/src/app/api/platform/assessorias/route.ts`
- `portal/src/lib/supabase/admin.ts`
- `omni_runner/supabase/migrations/20260226110000_platform_approval_assessorias.sql`

**Arquivos modificados (7):**
- `portal/src/middleware.ts` (+platform admin bypass)
- `portal/src/components/sidebar.tsx` (+link admin plataforma)
- `portal/src/app/(portal)/layout.tsx` (+redirect platform admin)
- `portal/src/app/select-group/page.tsx` (+redirect platform admin)
- `portal/src/app/no-access/page.tsx` (+redirect platform admin)
- `omni_runner/lib/presentation/screens/staff_dashboard_screen.dart` (+tela approval pending)
- `omni_runner/lib/presentation/screens/staff_setup_screen.dart` (+dialog pos-criacao)

**Risco:** Baixo. Assessorias existentes foram migradas como `approved`. Novas assessorias
ficam bloqueadas ate aprovacao manual. RPCs protegidas por `platform_role = 'admin'`.

---

## DECISAO 062 — Tempos de desafio e regra universal "nao correu = perdeu"

**Data:** 2026-02-26
**Contexto:** Os tempos disponiveis para desafios no modo "Agora" eram 30min, 1h, 24h, 3dias,
7dias. A logica de settlement tratava quem nao correu como "participou" (sem penalidade),
e em 1v1 o perdedor sempre ganhava 25 coins de participacao mesmo com entry fee.

**Decisao:**
1. Tempos alterados para **1h, 3h, 6h, 12h, 24h** (default: 3h)
2. Regra universal para todos os tipos: **nao completou no periodo = perdeu (DNF)**

**Regras de settlement por tipo:**

**1v1 (gratis / entry_fee = 0):**
- Ambos correram: vencedor 40 coins, perdedor 25 coins
- Um correu, outro nao: quem correu ganha 40, outro DNF 0
- Ninguem correu: ambos DNF, 0 coins
- Empate: ambos 40 coins

**1v1 (com stake / entry_fee > 0):**
- Ambos correram: vencedor leva pool (stake × 2), perdedor 0
- Um correu, outro nao: quem correu leva pool (stake × 2), outro DNF 0
- Ninguem correu: ambos DNF, **refund do stake** para cada um
- Empate: cada um recebe stake de volta (refund)

**Grupo (cooperativo — mesma logica de team vs team):**
- O grupo ganha ou perde junto como unidade
- Progresso coletivo: soma (distancia/tempo) ou media (pace) dos runners
- Meta atingida: TODOS recebem reward igualmente (30 coins se free, pool/N se fee)
  incluindo quem nao correu
- Meta nao atingida: todos recebem 0 (participaram mas falharam)
- Ninguem correu (com fee): todos DNF, refund do fee

**Team vs Team:**
- O time ganha ou perde como unidade
- Score do time conta apenas membros que correram (para determinar vencedor)
- Pool dividido igualmente entre TODOS os membros do time vencedor
  (correu ou nao — o entry fee eh por pessoa, o pool pertence ao time inteiro)
- Empate: pool dividido entre todos os participantes
- Ninguem correu em nenhum time: todos DNF, refund

**Arquivos modificados (3):**
- `omni_runner/lib/domain/usecases/gamification/challenge_evaluator.dart`
  (logica de settlement 1v1, grupo, team vs team)
- `omni_runner/lib/presentation/screens/challenge_create_screen.dart`
  (tempos: 1h/3h/6h/12h/24h, default 3h)
- `omni_runner/test/domain/usecases/gamification/challenge_evaluator_test.dart`
  (novos testes: DNF, refund, one-ran-other-didnt para todos os tipos)

**Docs atualizados:**
- `docs/GAMIFICATION_POLICY.md` (tabelas de coins e regras 1v1/grupo)

**Risco:** Baixo. Mudanca puramente de logica no evaluator, coberta por 30 testes unitarios.
Nao afeta schema do banco. Tempos de desafio sao opcoes de UI sem impacto em dados existentes.

---

## DECISAO 063 — Revisao Pre-Release: Correcoes de UX, Compliance e Resiliencia

**Data:** 2026-02-26
**Sprint:** Pre-Launch QA — Revisao de fluxo total
**Contexto:**
Revisao pre-release completa avaliou 38+ funcionalidades, 66 telas, todos os fluxos happy/error path.
Identificou 7 correcoes (2 alta, 3 media, 2 baixa) + 1 item para backlog (TODO).

**Correcoes aplicadas:**

1. **SettingsScreen em PT-BR (ALTA):** Labels de voz estavam em ingles ("Voice announcements",
   "Kilometer announcements", etc.). Traduzidos para PT-BR ("Anuncios por voz", "Anuncio por
   quilometro", etc.) para consistencia com o resto do app.

2. **FriendsActivityFeedScreen desativada (ALTA):** Tela acessivel via MoreScreen mas dependente
   de RPC `fn_friends_activity_feed` (Phase 15 nao implementada). Substituida por `_ComingSoonTile`
   com mensagem "Em breve".

3. **Warning grupo+stake+meta nao atingida (MEDIA):** Adicionado banner de alerta na
   ChallengeCreateScreen quando tipo=grupo e fee>0: "Se o grupo nao atingir a meta, a inscricao
   nao sera devolvida. So ha reembolso se ninguem correr."

4. **AuthGate retry antes do fallback (MEDIA):** Antes, se o profile fetch falhasse, ia direto
   para Home (risco de estado inconsistente). Agora faz ate 2 retries com backoff (2s, 4s)
   antes do fallback.

5. **Troca de role: mensagem de suporte (MEDIA):** Dialog de confirmacao de role agora menciona
   "Se precisar trocar, entre em contato com o suporte."

6. **Dashboard reorganizado (BAIXA):** Cards reordenados: Desafios, Assessoria, Progresso,
   Verificacao, Campeonatos, Parques, Creditos. Verificacao subiu de 7o para 4o lugar.

7. **Instagram OAuth resiliente (BAIXA):** `_signInWithInstagram()` agora tem catch adicional
   que exibe "Login com Instagram nao esta disponivel no momento" em vez de erro generico.

8. **Resultado de grupo: progresso coletivo (Fix 6/7 do review anterior):**
   - ChallengeCreateScreen: helper text contextual "Soma coletiva do grupo" para tipo=grupo
   - ChallengeResultScreen: builder dedicado `_buildGroupResults` com barra de progresso
     coletivo vs meta + card "Contribuicoes" + hero text cooperativo

**Backlog (TODO):**
- Lista de assessorias populares/proximas no JoinAssessoriaScreen (discovery)

**Arquivos modificados (8):**
- `omni_runner/lib/presentation/screens/settings_screen.dart` (labels PT-BR)
- `omni_runner/lib/presentation/screens/more_screen.dart` (FriendsActivityFeed → ComingSoon)
- `omni_runner/lib/presentation/screens/challenge_create_screen.dart` (warning grupo+stake, helper text)
- `omni_runner/lib/presentation/screens/auth_gate.dart` (retry antes do fallback)
- `omni_runner/lib/presentation/screens/onboarding_role_screen.dart` (mensagem suporte)
- `omni_runner/lib/presentation/screens/athlete_dashboard_screen.dart` (cards reordenados)
- `omni_runner/lib/presentation/screens/login_screen.dart` (Instagram catch resiliente)
- `omni_runner/lib/presentation/screens/challenge_result_screen.dart` (grupo: progresso coletivo)

**Risco:** Baixo. Mudancas puramente de UI/UX e resiliencia. Nenhuma alteracao de logica de negocio,
schema de banco ou Edge Functions.

---
