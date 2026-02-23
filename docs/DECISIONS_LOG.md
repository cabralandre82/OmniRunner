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
