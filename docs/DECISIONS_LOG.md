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

## DECISAO 064 — UX inteligente: 9 melhorias de fluxo

**Data:** 2026-02-26
**Contexto:** Revisao de oportunidades de melhoria em todos os fluxos, priorizando impacto
vs esforco. Foco em experiencia do usuario, reducao de fricao e aumento de engagement.

### Melhorias implementadas

1. **Card de desafio ativo na TodayScreen:** Mostra desafios ativos do usuario com tempo
   restante e link direto para detalhes. Torna o desafio visivel no fluxo principal.

2. **Rematch pre-preenchido no ChallengeResultScreen:** "Desafiar novamente" agora preenche
   tipo, metrica, duracao, fee e target do desafio anterior. Reduz fricao de re-criacao.

3. **Badge "Conecte Strava" no dashboard:** Card "Meu progresso" exibe badge laranja
   "Conecte Strava" se Strava nao estiver conectado. Aumenta conversao de conexao.

4. **Settlement client-triggered na ChallengeDetailsScreen:** Quando o usuario abre um desafio
   cujo periodo expirou, o app automaticamente chama `settle-challenge` e exibe
   "Calculando resultado..." enquanto aguarda. Elimina espera por cron.

5. **Sugestao de oponentes da assessoria no Matchmaking:** Secao "Desafiar colegas da assessoria"
   exibe membros da assessoria do usuario com botao "Desafiar" que abre ChallengeCreateScreen
   pre-preenchido. Combina matchmaking automatico com desafio direto.

6. **Push de streak em risco:** Quando o usuario abre a TodayScreen apos 18h sem ter corrido,
   e tem streak >= 3 dias, dispara regra `streak_at_risk` via `notify-rules` EF.
   Incentiva o usuario a manter a sequencia.

7. **Lista de sessoes na AthleteVerificationScreen:** Exibe as 10 corridas recentes com
   data, distancia, pace e duracao. Contextualiza o progresso de verificacao.

8. **Barra coletiva ao vivo na ChallengeDetailsScreen:** Para desafios de grupo ativos com
   meta, exibe card "Progresso do Grupo" com barra de progresso, total/media vs meta,
   e porcentagem. Cooperacao visivel durante o desafio.

9. **Card de campeonato ativo na TodayScreen:** Mostra campeonatos ativos em que o usuario
   esta inscrito com link para a tela de campeonatos.

**ChallengeCreateScreen refatorada:** Agora aceita parametros opcionais `initialType`,
`initialMetric`, `initialWindowMin`, `initialFee`, `initialTarget` para pre-preencher
o formulario (usado por rematch e sugestao de oponentes).

**Arquivos modificados (9):**
- `omni_runner/lib/presentation/screens/challenge_details_screen.dart` (auto-settle + grupo progress)
- `omni_runner/lib/presentation/screens/challenge_result_screen.dart` (rematch pre-preenchido)
- `omni_runner/lib/presentation/screens/challenge_create_screen.dart` (parametros iniciais)
- `omni_runner/lib/presentation/screens/athlete_dashboard_screen.dart` (badge Strava)
- `omni_runner/lib/presentation/screens/today_screen.dart` (desafios + campeonatos + streak)
- `omni_runner/lib/presentation/screens/athlete_verification_screen.dart` (sessoes recentes)
- `omni_runner/lib/presentation/screens/matchmaking_screen.dart` (oponentes da assessoria)
- `omni_runner/lib/core/push/notification_rules_service.dart` (streak_at_risk rule)
- `docs/DECISIONS_LOG.md` (esta decisao)

**Risco:** Baixo-Medio. Settlement client-triggered depende da EF `settle-challenge` ja existente
(idempotente). Demais mudancas sao de UI/UX sem alteracao de logica de negocio.

---

## DECISAO 065 — Economia de OmniCoins: aquisição exclusiva via assessoria

**Data:** 2026-02-26
**Contexto:** A economia de OmniCoins foi redesenhada. OmniCoins são adquiridas
**exclusivamente** via assessoria (professor distribui) e só mudam de mãos em
desafios com inscrição (entry fee > 0). Não existe nenhuma outra forma de ganhar
OmniCoins no app.

**Regras definitivas:**
1. Assessoria é a única fonte de criação de OmniCoins no sistema
2. Desafios com entry fee: vencedor leva o pool (fees de todos). Empate: refund. Ninguém correu: refund
3. Desafios gratuitos (fee = 0): ZERO movimentação de coins para qualquer resultado
4. Sessões de corrida: NÃO dão OmniCoins (dão XP e badges)
5. Streaks, PRs, badges, missões: NÃO dão OmniCoins (dão XP/reconhecimento visual)

**Alterações realizadas:**
- `ChallengeEvaluator`: coinsEarned = 0 em todos os desafios gratuitos
- `RewardSessionCoins`: desabilitado (retorna 0 coins sempre)
- `ClaimRewards`: removida creditação de coins para badges e missões
- `SettleChallenge`: docstring atualizada para refletir modelo correto
- `LedgerReason`: enums legados marcados como DEPRECATED
- `GAMIFICATION_POLICY.md`: seção 3 reescrita completamente
- UI: `_RewardCard` oculta em desafios gratuitos, textos corrigidos
- Testes: 33 testes atualizados e passando

**Arquivos modificados (8):**
- `omni_runner/lib/domain/usecases/gamification/challenge_evaluator.dart`
- `omni_runner/lib/domain/usecases/gamification/reward_session_coins.dart`
- `omni_runner/lib/domain/usecases/gamification/settle_challenge.dart`
- `omni_runner/lib/domain/usecases/progression/claim_rewards.dart`
- `omni_runner/lib/domain/entities/ledger_entry_entity.dart`
- `omni_runner/lib/presentation/screens/challenge_result_screen.dart`
- `omni_runner/lib/presentation/screens/wallet_screen.dart`
- `docs/GAMIFICATION_POLICY.md`

**Risco:** Baixo. Remoção de distribuição automática de coins. Pool de desafios
com stake mantido inalterado. LedgerService já protege contra fee=0.

---

## DECISAO 066 — Regra de visibilidade em desafios ativos

**Data:** 2026-02-26
**Contexto:** Regra anti-gaming para desafios 1v1.

**Regra:** Enquanto um desafio 1v1 está ativo, cada atleta pode ver APENAS se o
oponente completou ou não. Nenhum detalhe (pace, distância, tempo parcial) é
visível antes que ambos completem ou o período expire. Isso impede que um atleta
espere o outro terminar para ajustar seu esforço (ex: "ele fez 45min, vou tentar
44:59"). Após ambos completarem, os detalhes completos são revelados.

**Impacto:** UI do `ChallengeDetailsScreen` deve ocultar progressValue do oponente
enquanto o desafio estiver ativo. Mostrar apenas: "Completou" / "Ainda não completou".

**Status:** Regra documentada em GAMIFICATION_POLICY.md §4.1. Implementação
pendente no front-end.

---

## DECISAO 067 — Ideias futuras aprovadas para roadmap

**Data:** 2026-02-26

### IDEIA APROVADA 1: OmniWrapped (Retrospectiva anual do corredor)
No fim do ano (ou a cada trimestre), o app gera automaticamente um resumo visual
estilo "Spotify Wrapped" com as estatísticas do atleta: total de km, tempo correndo,
desafios disputados, vitórias, evolução de pace, parques visitados, badges
conquistados, posição em rankings. Formato visual stories-friendly para compartilhar
no Instagram/WhatsApp. Alto potencial viral.

### IDEIA APROVADA 2: Liga de Assessorias
Competição sazonal (mensal/trimestral) entre assessorias. Ranking baseado em
métricas agregadas (km totais, participação em desafios, frequência de treinos).
As assessorias competem como unidades. Premiação simbólica (troféu digital,
badge exclusivo). Cria senso de comunidade e pertencimento.

---

## DECISAO 068 — Regra de visibilidade em desafios ativos (anti-gaming)

**Data:** 2026-02-26
**Contexto:** Atletas podiam ver o progresso (pace, distância, tempo) dos oponentes
durante desafios ativos. Isso permitia esperar o adversário terminar e ajustar o
esforço para vencer por margem mínima.

**Regra implementada:**
- Desafio ativo: cada atleta vê APENAS seu próprio progresso
- Oponente: só aparece "Completou" (verde) ou "Aguardando" (laranja)
- Nenhum valor numérico (pace, distância, tempo) é visível
- Após ambos completarem ou período expirar: detalhes revelados

**Implementação:**
- **Server-side (challenge-get EF):** `progress_value` é enviado como `null` para
  participantes que não são o caller quando `challenge.status == 'active'`. Campo
  `has_submitted` (boolean) adicionado para indicar se oponente submeteu corrida.
- **Client-side (_participantTile):** chip "Completou"/"Aguardando" no lugar do
  valor numérico quando desafio ativo e participante != eu.
- **Grupo cooperativo:** progresso coletivo visível (todos do mesmo time).
- **Team vs team:** progresso individual do time adversário oculto.

**Arquivos modificados:**
- `supabase/functions/challenge-get/index.ts`
- `omni_runner/lib/presentation/screens/challenge_details_screen.dart`
- `omni_runner/lib/presentation/blocs/challenges/challenges_bloc.dart`

**Risco:** Baixo. Proteção dupla (server + client). Dados nunca saem do servidor.

---

### DECISAO 069 — OmniWrapped (Retrospectiva do Corredor)

**Data:** 2026-02-26
**Contexto:** Feature #1 do roadmap, aprovada pelo usuário.

Implementação completa do OmniWrapped — tela de retrospectiva estilo "stories"
que mostra estatísticas de corrida de um período (mês/trimestre/ano).

**Componentes implementados:**
1. Migration `20260226200000_user_wrapped.sql` — tabela de cache com RLS
2. Edge Function `generate-wrapped` — calcula e cacheia métricas (24h TTL)
3. Flutter `WrappedScreen` — PageView com 6 slides temáticos:
   - Slide 1: Números gerais (km, sessões, tempo)
   - Slide 2: Evolução de pace (LineChart + % melhoria)
   - Slide 3: Desafios (vitórias, derrotas, taxa)
   - Slide 4: Badges e progressão (XP, streak)
   - Slide 5: Curiosidades (dia favorito, horário, histograma)
   - Slide 6: Compartilhar (card PNG via share_plus)
4. Share card visual (RepaintBoundary + PNG) seguindo padrão de `run_share_card.dart`
5. Seletor de período (bottom sheet) no `ProgressHubScreen`

**Mínimo para gerar:** 3 sessões verificadas no período.
**Cache:** 24h no servidor (tabela `user_wrapped`).

**Arquivos:**
- `supabase/migrations/20260226200000_user_wrapped.sql`
- `supabase/functions/generate-wrapped/index.ts`
- `omni_runner/lib/presentation/screens/wrapped_screen.dart`
- `omni_runner/lib/presentation/screens/progress_hub_screen.dart`
- `supabase/config.toml`

---

### DECISAO 070 — Liga de Assessorias

**Data:** 2026-02-26
**Contexto:** Feature #2 do roadmap, competição sazonal entre assessorias.

Implementação completa da Liga de Assessorias — sistema de ranking entre
assessorias baseado em desempenho coletivo normalizado por número de membros.

**Score semanal (por assessoria):**
  `(total_km * 1.0 + total_sessions * 0.5 + pct_active * 200 + challenge_wins * 3.0) / num_members`
  Normalização por membros garante competição justa entre assessorias de tamanhos diferentes.

**Componentes implementados:**
1. Migration `20260226210000_league_tables.sql`:
   - `league_seasons` (temporadas com status upcoming/active/completed)
   - `league_enrollments` (assessorias inscritas na temporada)
   - `league_snapshots` (snapshot semanal com score, rank, delta)
   - RLS: leitura pública (qualquer autenticado), insert por staff
2. Edge Function `league-snapshot` — calcula scores semanais, gera ranking
3. Edge Function `league-list` — retorna ranking + contribuição do caller
4. Integração no `lifecycle-cron` (dispara snapshot às segundas-feiras)
5. Flutter `LeagueScreen`:
   - Header com nome da temporada e dias restantes
   - Card "Sua contribuição" (km e sessões pessoais)
   - Lista ranqueada com medalhas top-3, delta de posição, score
   - Highlight na assessoria do usuário
6. Entry points: `ProgressHubScreen` + `MyAssessoriaScreen`

**Arquivos:**
- `supabase/migrations/20260226210000_league_tables.sql`
- `supabase/functions/league-snapshot/index.ts`
- `supabase/functions/league-list/index.ts`
- `supabase/functions/lifecycle-cron/index.ts`
- `omni_runner/lib/presentation/screens/league_screen.dart`
- `omni_runner/lib/presentation/screens/progress_hub_screen.dart`
- `omni_runner/lib/presentation/screens/my_assessoria_screen.dart`
- `supabase/config.toml`

---

### DECISAO 071 — DNA do Corredor (Running DNA)

**Data:** 2026-02-26
**Contexto:** Feature #3 do roadmap, perfil inteligente do atleta.

Implementação completa do Running DNA — análise estatística sobre 6 meses de
corridas, gerando um perfil visual radar com 6 eixos, insights em linguagem
natural e previsão de PR por regressão linear.

**6 eixos do radar:**
1. Velocidade (pace médio último mês, 4:00/km=100, 8:00/km=0)
2. Resistência (distância média, >15km=100, <2km=0)
3. Consistência (sessões/semana, >=6=100, <1=0)
4. Evolução (tendência de pace 3 meses, melhoria=100, piora=0)
5. Versatilidade (desvio padrão de distâncias)
6. Competitividade (win rate em desafios, >=3 desafios necessários)

**Insights gerados (regras estáticas, sem ML):**
- Dia da semana mais ativo + %
- Perfil horário (matutino/vespertino/noturno) + %
- Zona de conforto de distância + sugestão
- Impacto do descanso no pace
- Ponto forte e área para crescer

**Previsão de PR:**
- Regressão linear sobre melhores paces mensais por faixa (5K, 10K, Meia)
- Só exibe se R² >= 0.3 (confiança mínima)
- Previsão em semanas até próximo PR

**Componentes:**
1. Migration `20260226220000_running_dna.sql` — cache único por user
2. EF `generate-running-dna` — cálculo completo, cache 7 dias
3. `RunningDnaScreen` — RadarChart (fl_chart), breakdown, insights, PR, share
4. Share card (RepaintBoundary + PNG) com barras de score + branding
5. Entry point no `ProgressHubScreen`

**Mínimo:** 10 sessões verificadas nos últimos 6 meses.

**Arquivos:**
- `supabase/migrations/20260226220000_running_dna.sql`
- `supabase/functions/generate-running-dna/index.ts`
- `omni_runner/lib/presentation/screens/running_dna_screen.dart`
- `omni_runner/lib/presentation/screens/progress_hub_screen.dart`
- `supabase/config.toml`

---

### IDEIA DESCARTADA: Corrida Fantasma (Ghost Rival)
~~O app usa dados GPS de corridas anteriores do atleta para criar um "fantasma"
de si mesmo.~~ **DESCARTADA:** O tracking nativo do app foi removido. Todas as
corridas vêm do Strava (pós-corrida). O Ghost precisa de GPS em tempo real
durante a corrida, o que não existe mais. Inviável.

### IDEIA APROVADA 3: DNA do Corredor (Running DNA)
Análise de ML/estatística sobre todo o histórico do atleta gerando um perfil
único visual (radar chart/mandala). Identifica padrões invisíveis: horário ideal,
terreno ideal, recuperação ótima, previsão de PR com data estimada e ações para
acelerar. DNA evolui com o tempo, é compartilhável nas redes sociais, e a
assessoria pode usar para personalizar treinos. Diferencial competitivo absoluto.

### IDEIA DESCARTADA: Marketplace de OmniCoins na Assessoria
~~Cada assessoria cria uma "loja" com recompensas resgatáveis por OmniCoins.~~
**DESCARTADA:** Risco de rejeição nas lojas (App Store / Play Store) — produtos
físicos via moeda virtual podem ser interpretados como desvio do sistema de IAP.
Além disso, coins cross-assessoria criam obrigações econômicas entre assessorias
sem consentimento mútuo. Inviável sem reestruturação profunda da economia.

---

### DECISÃO 072 — Amigos de Corrida (Friends & Social Community)
- **Data:** 2026-02-26
- **Contexto:** Construir rede social de corredores integrada ao ecossistema
  de assessorias, desafios e campeonatos. Atletas podem adicionar amigos de
  qualquer assessoria, compartilhar redes sociais (Instagram/TikTok), e o
  convite de amizade é incentivado após desafios e campeonatos.
- **Decisão:**
  - Migration `20260226230000_social_profiles.sql`: adiciona `instagram_handle` e
    `tiktok_handle` em `profiles`, `invited_by` em `friendships`, e cria
    `fn_search_users` RPC para busca por nome.
  - Repo Supabase: `SupabaseFriendshipRepo` — implementação concreta do
    `IFriendshipRepo` usando Supabase diretamente.
  - BLoC enriquecido: `FriendsBloc` agora recebe `SendFriendInvite` e
    `AcceptFriend` use cases e suporta `AcceptFriendEvent`, `DeclineFriendEvent`,
    `SendFriendRequest`.
  - `FriendsScreen` remodelado: seções de pedidos recebidos (com aceitar/recusar),
    amigos (com nomes e avatares), enviados. Botão de busca no AppBar.
  - `_FriendSearchScreen`: busca por nome via `fn_search_users` RPC, convite inline.
  - `FriendProfileScreen`: perfil público com avatar, nível, DNA (mini barras),
    redes sociais (Instagram/TikTok com deep links), e estatísticas.
  - CTA pós-desafio: botão "Adicionar amigo" no `_CtaBar` do
    `ChallengeResultScreen`, com seleção de oponente quando há múltiplos.
  - CTA pós-campeonato: tap em participante no ranking do campeonato abre
    `FriendProfileScreen`.
  - Edição de redes sociais: campos Instagram/TikTok no `ProfileScreen` com
    save direto ao Supabase.
  - Entry point: tile "Meus Amigos" no `MoreScreen`.
- **Arquivos criados:**
  - `supabase/migrations/20260226230000_social_profiles.sql`
  - `omni_runner/lib/data/repositories_impl/supabase_friendship_repo.dart`
  - `omni_runner/lib/presentation/screens/friend_profile_screen.dart`
- **Arquivos modificados:**
  - `omni_runner/lib/presentation/blocs/friends/friends_bloc.dart`
  - `omni_runner/lib/presentation/blocs/friends/friends_event.dart`
  - `omni_runner/lib/presentation/screens/friends_screen.dart`
  - `omni_runner/lib/presentation/screens/challenge_result_screen.dart`
  - `omni_runner/lib/presentation/screens/athlete_championship_ranking_screen.dart`
  - `omni_runner/lib/presentation/screens/profile_screen.dart`
  - `omni_runner/lib/presentation/screens/more_screen.dart`
  - `omni_runner/lib/core/service_locator.dart`

---

## DECISÃO 073 — Push Notifications Completo (26/02/2026)

- **Contexto:** O app tinha 8 regras de push (challenge_received, challenge_accepted,
  streak_at_risk, championship_starting, championship_invite_received,
  challenge_team_invite_received, join_request_received, low_credits_alert), mas
  faltavam notificações para funcionalidades recentes e infraestrutura de UX
  (banner in-app e navegação ao tocar na notificação).
- **Decisão:** Implementar 8 novas regras de push + infraestrutura completa.

### Novas regras adicionadas ao `notify-rules` EF:

| # | Regra | Trigger | Destinatário |
|---|-------|---------|-------------|
| 9 | `friend_request_received` | Client (FriendsBloc) | Destinatário do convite |
| 10 | `friend_request_accepted` | Client (FriendsBloc) | Remetente original |
| 11 | `challenge_settled` | Server (settle-challenge EF) | Todos os participantes |
| 12 | `challenge_expiring` | Cron (lifecycle-cron) | Participantes sem sessão |
| 13 | `inactivity_nudge` | Cron (lifecycle-cron, 17h UTC) | Inativos 5+ dias |
| 14 | `badge_earned` | Server (evaluate-badges EF) | O usuário |
| 15 | `league_rank_change` | Server (league-snapshot EF) | Membros da assessoria |
| 16 | `join_request_approved` | Client (StaffJoinRequestsScreen) | Atleta aprovado |

### Infraestrutura de UX:

- **In-app banner:** `PushNavigationHandler.showForegroundBanner()` mostra
  `MaterialBanner` quando push chega com app aberto, com botões FECHAR/VER.
  Auto-dismiss após 6s.
- **Push-tap navigation:** `onMessageOpenedApp` + `getInitialMessage` leem
  `data.type` e navegam para a tela correta (ChallengeJoinScreen,
  ChallengeDetailsScreen, FriendsScreen, etc.).
- **Navigator key:** `GlobalKey<NavigatorState>` adicionada ao `MaterialApp`
  para permitir navegação programática sem contexto.

### Cron (lifecycle-cron):

- `challenge_expiring`: avalia a cada ciclo (5 min), dedup 12h.
- `inactivity_nudge`: avalia entre 17h-18h UTC, dedup 12h.
- `streak_at_risk`: avalia entre 20h-21h UTC (server-side, complementa client-side).

### Arquivos criados:
- `omni_runner/lib/core/push/push_navigation_handler.dart`

### Arquivos modificados:
- `supabase/functions/notify-rules/index.ts` (8 novas regras)
- `supabase/functions/settle-challenge/index.ts` (trigger challenge_settled)
- `supabase/functions/evaluate-badges/index.ts` (trigger badge_earned)
- `supabase/functions/league-snapshot/index.ts` (trigger league_rank_change)
- `supabase/functions/lifecycle-cron/index.ts` (cron: expiring, inactivity, streak)
- `omni_runner/lib/core/push/notification_rules_service.dart` (6 novos métodos)
- `omni_runner/lib/presentation/blocs/friends/friends_bloc.dart` (push triggers)
- `omni_runner/lib/presentation/screens/staff_join_requests_screen.dart` (push trigger)
- `omni_runner/lib/core/service_locator.dart` (notifyRules no FriendsBloc)
- `omni_runner/lib/main.dart` (navigatorKey + PushNavigationHandler)

---

## DECISÃO 074 — Onboarding Guiado (26/02/2026)

- **Contexto:** O app tinha apenas uma `WelcomeScreen` com 4 bullets genéricos e
  um fluxo de role selection + assessoria. Após completar o cadastro, o atleta
  caía direto no dashboard sem nenhuma explicação de como usar as features.
  Isso gerava fricção de primeiro uso e redução de ativação.
- **Decisão:** Implementar tour guiado com 6 slides interativos, mostrado uma
  única vez entre o onboarding estrutural e o HomeScreen.

### Slides do tour:

| # | Título | Feature |
|---|--------|---------|
| 1 | Conecte seu Strava | Integração Strava |
| 2 | Desafie outros corredores | Desafios 1v1/equipe |
| 3 | Treine com sua assessoria | Assessoria + campeonatos |
| 4 | Mantenha sua sequência | Streak + XP + badges |
| 5 | Acompanhe sua evolução | DNA, Wrapped, Liga, PR |
| 6 | Encontre amigos | Social / Friends |

### Comportamento:

- Aparece **uma vez** para atletas (não staff), após `isOnboardingComplete`
- Usa `FirstUseTips.onboardingTour` para persistir se já foi visto
- Botão "Pular" sempre visível para skip imediato
- Botão CTA dinâmico: "PRÓXIMO" → "COMEÇAR A CORRER" no último slide
- Dots animados com cor do slide ativo
- Integrado ao `AuthGate` como novo `_GateDestination.tour`

### Arquivos criados:
- `omni_runner/lib/presentation/screens/onboarding_tour_screen.dart`

### Arquivos modificados:
- `omni_runner/lib/core/tips/first_use_tips.dart` (novo TipKey.onboardingTour)
- `omni_runner/lib/presentation/screens/auth_gate.dart` (tour destination + routing)

---

## DECISÃO 075 — Polimento visual e UX

**Data:** 2026-02-26

**Contexto:** Terceiro item do relatório de pré-release: falta de polimento.
CircularProgressIndicators nuas, ausência de animações, empty states
genéricas, mensagens de erro técnicas, e nenhuma celebração nos
momentos de sucesso.

**Decisão:** Criar um conjunto de widgets reutilizáveis de polimento e
aplicá-los sistematicamente nas telas mais acessadas.

### Widgets criados:

| Widget | Arquivo | Propósito |
|---|---|---|
| `ShimmerLoading` | `shimmer_loading.dart` | Efeito shimmer puro-Flutter |
| `SkeletonTile` | `shimmer_loading.dart` | Placeholder tipo lista |
| `SkeletonCard` | `shimmer_loading.dart` | Placeholder tipo grid card |
| `ShimmerListLoader` | `shimmer_loading.dart` | Lista skeleton completa |
| `EmptyState` | `empty_state.dart` | Empty state com ícone, título, CTA |
| `ErrorState` | `error_state.dart` | Erro humanizado com retry |
| `AnimatedCheckmark` | `success_overlay.dart` | Check animado com bounce |
| `ConfettiBurst` | `success_overlay.dart` | Confetti puro CustomPainter |
| `showSuccessOverlay` | `success_overlay.dart` | Overlay de sucesso fullscreen |
| `StaggeredList` | `staggered_list.dart` | Animação escalonada para listas |

### Melhorias aplicadas:

1. **Shimmer loading** — substituiu `CircularProgressIndicator` nas telas:
   ChallengesListScreen, TodayScreen, HistoryScreen, FriendsScreen,
   MyAssessoriaScreen, WalletScreen, AthleteDashboardScreen,
   AthleteChampionshipsScreen

2. **Empty states amigáveis** — HistoryScreen, FriendsScreen agora usam
   `EmptyState` com ícone decorativo, texto orientador e CTA

3. **Error states humanizados** — `ErrorState.humanize()` traduz
   exceptions (network, timeout, 401, 500) para mensagens amigáveis em
   português com botão "Tentar novamente"

4. **Celebrações** — `showSuccessOverlay` com checkmark + confetti nos
   momentos de criação e aceite de desafio

5. **Page transitions** — `PredictiveBackPageTransitionsBuilder` (Android)
   e `CupertinoPageTransitionsBuilder` (iOS) configurados no theme

6. **Stagger animation** — Dashboard grid cards surgem com fade-in ao carregar

7. **Dashboard personalizado** — Saudação com nome real do atleta

8. **HapticFeedback** — `selectionClick` no toque de cards do dashboard e
   challenge tiles; `lightImpact` em ações sociais (aceitar/recusar amigo)

9. **Pull-to-refresh** — Adicionado RefreshIndicator ao FriendsScreen

### Zero dependências externas — todos os efeitos visuais são pure-Flutter.

### Arquivos criados:
- `lib/presentation/widgets/shimmer_loading.dart`
- `lib/presentation/widgets/success_overlay.dart`
- `lib/presentation/widgets/staggered_list.dart`
- `lib/presentation/widgets/empty_state.dart`
- `lib/presentation/widgets/error_state.dart`

### Arquivos modificados:
- `lib/main.dart` (page transitions no theme)
- `lib/presentation/screens/challenges_list_screen.dart`
- `lib/presentation/screens/today_screen.dart`
- `lib/presentation/screens/athlete_dashboard_screen.dart`
- `lib/presentation/screens/history_screen.dart`
- `lib/presentation/screens/friends_screen.dart`
- `lib/presentation/screens/my_assessoria_screen.dart`
- `lib/presentation/screens/challenge_create_screen.dart`
- `lib/presentation/screens/challenge_join_screen.dart`
- `lib/presentation/screens/wallet_screen.dart`
- `lib/presentation/screens/athlete_championships_screen.dart`

---

## DECISÃO 076 — Bugfixes, Cleanup Legado, Suporte Assessoria ↔ Plataforma

**Data:** 26/02/2026
**Contexto:** Testes em device real revelaram bugs e features legadas sem sentido
no fluxo atual (Strava-only).

### Bugfixes

1. **Nome na home** — `_loadDisplayName` agora detecta se `display_name` é um
   email e extrai apenas a parte local capitalizada. EF `complete-social-profile`
   também atualizado para não salvar email como nome.

2. **Wrapped / DNA / Liga** — Erros de EF (network, 500, etc.) agora direcionam
   para estado "dados insuficientes" ao invés de mostrar ícone de erro genérico.

3. **Parques** — Mensagem técnica substituída por mensagem amigável. Lista
   expandida de 10 para 40+ parques brasileiros (20 cidades). Adicionado campo
   de busca por nome, cidade ou estado.

4. **Verificação** — Distância mínima para "corrida válida" aumentada de 200m
   para 1km na EF `eval-athlete-verification`, evitando que caminhadas curtas
   contem como corridas.

### Cleanup Legado

Removidos do app (não fazem sentido com Strava como fonte única):
- Aba "Wearables e Saúde" no menu Mais
- Seção "Anúncios por voz" nas Configurações
- Seção "Frequência Cardíaca" nas Configurações
- Classes mortas: `_IntegrationsInfoScreen`, `_ActionableCard`, `_editMaxHr`,
  `_buildZoneRows`

### Portal Assessoria

- Botão "Portal" no staff dashboard agora abre `https://omnirunner.app` no
  navegador via `url_launcher` (antes mostrava "em breve").

### Suporte Assessoria ↔ Plataforma

**Modelo:** sistema de tickets com chat bidirecional.

**Banco de dados:**
- `support_tickets` (id, group_id, subject, status, timestamps)
- `support_messages` (id, ticket_id, sender_id, sender_role, body, created_at)
- Trigger `trg_support_message_touch` atualiza `updated_at` do ticket
- RLS: staff lê/escreve do seu grupo; platform_admin lê/escreve todos

**App (assessoria staff):**
- `SupportScreen` — lista de tickets, FAB "Novo chamado", dialog com assunto +
  mensagem, pull-to-refresh
- `SupportTicketScreen` — thread estilo chat, bolhas diferenciadas por role,
  barra de envio, indicador de chamado encerrado
- Botão "Suporte" adicionado ao staff dashboard

**Portal (admin plataforma):**
- `/platform/support` — lista com filtros (todos/abertos/respondidos/fechados)
- `/platform/support/[id]` — thread de chat + enviar + fechar + reabrir
- API route `/api/platform/support` (reply, close, reopen)
- Link "Suporte" na sidebar do admin

**Fluxo:** staff abre → status:open → admin responde → status:answered →
staff responde → status:open → admin fecha → status:closed (reabrir possível).

### Arquivos criados:
- `supabase/migrations/20260226120000_support_tickets.sql`
- `lib/presentation/screens/support_screen.dart`
- `lib/presentation/screens/support_ticket_screen.dart`
- `portal/src/app/platform/support/page.tsx`
- `portal/src/app/platform/support/[id]/page.tsx`
- `portal/src/app/platform/support/[id]/ticket-chat.tsx`
- `portal/src/app/api/platform/support/route.ts`

### Arquivos modificados:
- `lib/presentation/screens/athlete_dashboard_screen.dart`
- `lib/presentation/screens/staff_dashboard_screen.dart`
- `lib/presentation/screens/more_screen.dart`
- `lib/presentation/screens/settings_screen.dart`
- `lib/presentation/screens/wrapped_screen.dart`
- `lib/presentation/screens/running_dna_screen.dart`
- `lib/presentation/screens/league_screen.dart`
- `lib/features/parks/presentation/park_screen.dart`
- `lib/features/parks/presentation/my_parks_screen.dart`
- `lib/features/parks/data/parks_seed.dart`
- `supabase/functions/complete-social-profile/index.ts`
- `supabase/functions/eval-athlete-verification/index.ts`
- `portal/src/app/platform/platform-sidebar.tsx`

---

## DECISÃO 077 — Dark Mode e Configurações para Staff

**Data:** 26/02/2026
**Contexto:** Dark mode ilegível nos cards dos dashboards (cores claras
hardcoded sobre fundo escuro). Configurações inacessíveis para staff.

### Correções

1. **Configurações para staff** — a aba Configurações (Strava, tema, unidades)
   agora aparece tanto para atletas quanto para staff no menu Mais.

2. **Dark mode — Dashboard cards** — ambos os dashboards (atleta e staff) agora
   detectam `Brightness.dark` e usam `surfaceContainerHighest` como fundo dos
   cards ao invés de cores hardcoded (`shade50`/`shade100`). Texto usa
   `onSurface`/`onSurfaceVariant` do ColorScheme para garantir contraste.

3. **Dark mode — Suporte** — badges de status, bolhas de chat e barra de
   "chamado encerrado" adaptam cores ao tema escuro usando variantes de alta
   luminosidade (`shade300`/`shade900` com alpha).

### Arquivos modificados:
- `lib/presentation/screens/more_screen.dart`
- `lib/presentation/screens/athlete_dashboard_screen.dart`
- `lib/presentation/screens/staff_dashboard_screen.dart`
- `lib/presentation/screens/support_screen.dart`
- `lib/presentation/screens/support_ticket_screen.dart`

---

## DECISÃO 078 — Admin Financeiro + Settings Staff (26/02/2026)

### Contexto:
O admin da plataforma não tinha visibilidade financeira no portal. Assessorias compravam
pacotes de créditos mas não havia interface para o admin acompanhar compras, gerenciar
reembolsos ou administrar o catálogo de produtos. Além disso, a tela de Configurações
mostrava opções irrelevantes para usuários staff (Integrações, Unidades, Privacidade).

### Decisão:

1. **Settings staff-only** — `SettingsScreen` recebe `isStaff` e esconde seções que
   só fazem sentido para atletas (Integrações/Strava, Unidades, Privacidade). Staff vê
   apenas Aparência (tema claro/escuro/sistema).

2. **Dashboard admin** (`/platform`) — página inicial do admin com KPIs: assessorias
   ativas, total de atletas, receita total e do mês, compras pendentes, reembolsos
   pendentes. Quick links para todas as seções.

3. **Financeiro** (`/platform/financeiro`) — tabela de todas as `billing_purchases` com
   filtros por status (pending/paid/fulfilled/cancelled/refunded) e período (7 dias, mês).
   Cards de receita totalizada e pendente.

4. **Reembolsos** (`/platform/reembolsos`) — lista de `billing_refund_requests` com ações:
   aprovar (requested→approved), rejeitar (requested→rejected, requer motivo),
   processar (approved→processed, marca purchase como refunded + billing_event).

5. **Produtos** (`/platform/produtos`) — tabela do catálogo `billing_products` com toggle
   ativo/inativo e formulário para criar novos pacotes (nome, descrição, créditos, preço, ordem).

6. **Sidebar atualizada** — links para Dashboard, Assessorias, Financeiro, Reembolsos,
   Produtos e Suporte com active state.

### API Routes criadas:
- `POST /api/platform/products` — actions: `create`, `toggle_active`, `update`
- `POST /api/platform/refunds` — actions: `approve`, `reject`, `process`

### Arquivos modificados/criados:
- `lib/presentation/screens/settings_screen.dart` (isStaff)
- `lib/presentation/screens/more_screen.dart` (passa isStaff)
- `portal/src/app/platform/page.tsx` (novo — dashboard)
- `portal/src/app/platform/financeiro/page.tsx` (novo)
- `portal/src/app/platform/reembolsos/page.tsx` (novo)
- `portal/src/app/platform/reembolsos/actions.tsx` (novo)
- `portal/src/app/platform/produtos/page.tsx` (novo)
- `portal/src/app/platform/produtos/actions.tsx` (novo)
- `portal/src/app/api/platform/products/route.ts` (novo)
- `portal/src/app/api/platform/refunds/route.ts` (novo)
- `portal/src/app/platform/platform-sidebar.tsx` (sidebar links)

---

## DECISÃO 079 — Fix Portal Button (App Links conflict) (26/02/2026)

### Contexto:
O botão "Portal" no dashboard da assessoria ficava "pensando" e voltava sem abrir nada.
O `launchUrl` com `inAppBrowserView` falhava silenciosamente porque o `AndroidManifest.xml`
declarava um intent-filter `android:autoVerify="true"` para `https://omnirunner.app`
sem restrição de path, fazendo o Android interceptar a URL e redirecionar de volta ao app.

### Decisão:

1. **Intent filter restrito** — App Links agora intercepta apenas paths específicos
   (`/invite/*`, `/challenge/*`) ao invés de qualquer URL de `omnirunner.app`.

2. **`_openPortal()` com fallback** — Tenta `LaunchMode.externalApplication` primeiro
   (navegador padrão), fallback para `inAppBrowserView` (Chrome Custom Tab), e exibe
   SnackBar de erro se ambos falharem.

### Arquivos modificados:
- `android/app/src/main/AndroidManifest.xml` (pathPrefix nos App Links)
- `lib/presentation/screens/staff_dashboard_screen.dart` (_openPortal com fallback)

---

## DECISÃO 080 — Remover info debug do perfil (26/02/2026)

### Contexto:
A tela de perfil (atleta e staff) exibia um card com "Modo", "ID" e "Criado em" —
informações internas de debug sem utilidade para o usuário final.

### Decisão:
Removido o card de info debug, os métodos auxiliares `_infoRow` e `_truncate`, e o
import de `AppConfig` que ficou sem uso.

### Arquivos modificados:
- `lib/presentation/screens/profile_screen.dart`

---

## DECISÃO 081 — CRUD completo de Produtos no Portal Admin (26/02/2026)

### Contexto:
A página de produtos (`/platform/produtos`) só tinha um toggle ativo/inativo e um
formulário de criação. O admin não podia editar, suspender ou remover produtos existentes.

### Decisão:
1. **Cards com ações** — Cada produto exibe um card com botões Editar, Suspender/Ativar e Remover.
2. **Edição inline** — O botão Editar transforma o card em um formulário inline com os
   campos editáveis (nome, descrição, créditos, preço, ordem). Salvar ou Cancelar.
3. **Suspender/Ativar** — Toggle de `is_active` com visual diferenciado (laranja/verde).
4. **Remover** — Exclusão permanente com confirmação. Falha graciosamente se houver
   compras vinculadas (FK constraint).
5. **Seções separadas** — Produtos ativos e inativos em seções distintas.
6. **API `action=delete`** — Novo handler na rota `/api/platform/products`.

### Arquivos modificados:
- `portal/src/app/platform/produtos/page.tsx` (cards separados por status)
- `portal/src/app/platform/produtos/actions.tsx` (ProductCard, EditForm, Remover)
- `portal/src/app/api/platform/products/route.ts` (action=delete)

---

## DECISÃO 082 — Fix perfil: save unificado e nome sem email (26/02/2026)

### Contexto:
1. A tela de perfil mostrava o email bruto como nome quando `display_name` continha `@`
   (usuários criados antes do fix na edge function `complete-social-profile`).
2. O botão "Salvar perfil" fazia duas operações sequenciais (`_save` para nome, `_saveSocial`
   para Instagram/TikTok). Se a primeira sucedia e a segunda falhava, o usuário via
   snackbar de sucesso E card de erro ao mesmo tempo — confuso.

### Decisão:
1. **Nome sem email** — Ao carregar o perfil, se `displayName` contém `@`, extrai o
   prefixo e capitaliza (ex: `cabraandre@yahoo.com.br` → `Cabraandre`) no campo de edição.
2. **Save unificado** — Substituídos `_save()` + `_saveSocial()` por um único `_saveAll()`
   que faz uma única chamada `.update()` no Supabase com `display_name`, `instagram_handle`,
   `tiktok_handle` e `updated_at`. Uma operação, um resultado, uma mensagem.

### Arquivos modificados:
- `lib/presentation/screens/profile_screen.dart`

---

## DECISÃO 083 — Fix Park Screen: graceful fallback (26/02/2026)

### Contexto:
A tela de parque (`ParkScreen`) consultava três tabelas — `park_leaderboard`,
`park_activities`, `park_segments` — que **nunca foram criadas** no Supabase. A feature
de parques foi implementada apenas no frontend com seed local (`kBrazilianParksSeed`),
mas o backend (schema SQL) para dados dinâmicos (rankings, comunidade, segmentos) nunca
foi migrado. Resultado: qualquer parque mostrava "Erro ao carregar dados do parque".

### Decisão:
1. **Cada loader individual com try/catch** — `_loadRankings`, `_loadCommunity`,
   `_loadSegments` e `_loadStats` agora falham silenciosamente e retornam listas/stats
   vazias em caso de erro (tabela inexistente, RLS, rede, etc.).
2. **Removido `_buildError`** — A tela nunca mais mostra erro genérico. Carrega
   normalmente com empty states por tab (ranking vazio, comunidade vazia, segmentos vazios).
3. **Pendência futura** — Quando ativar a feature completa de parques, criar migration
   com as tabelas `park_leaderboard`, `park_activities`, `park_segments` + RLS + triggers
   para popular dados a partir das atividades do Strava.

### Arquivos modificados:
- `lib/features/parks/presentation/park_screen.dart`

---

## DECISÃO 084 — Parks end-to-end + Auditoria backend vs frontend (27/02/2026)

### Contexto:
A feature de parques estava implementada apenas no frontend (seed local, telas, queries).
As tabelas `parks`, `park_activities`, `park_leaderboard`, `park_segments` **nunca foram criadas**
no Supabase. O webhook do Strava não detectava parques. Resultado: todas as queries falhavam.

Uma auditoria completa cruzando **todas** as queries `.from()`, `.rpc()` e `functions.invoke()`
do app contra as migrations e edge functions revelou **3 lacunas adicionais**:

1. `strava_activity_history` — tabela referenciada pelo `strava_connect_controller.dart` nunca criada
2. `delete-account` — edge function chamada pelo `profile_screen.dart` inexistente
3. `validate-social-login` — edge function chamada pelo `remote_auth_datasource.dart` inexistente

### Decisão:

**Parks (end-to-end):**
1. Migration `20260226300000_parks_tables.sql`:
   - `parks` — catálogo de 47 parques brasileiros com centro + raio para detecção
   - `park_activities` — atividades linkadas a parques (unique por session_id)
   - `park_segments` — segmentos dentro de parques (preparado para futuro)
   - `park_leaderboard` — rankings por categoria (pace, distance, frequency, longestRun)
   - `fn_refresh_park_leaderboard()` — recalcula rankings de um parque
   - Trigger `trg_park_activity_inserted` — recalcula leaderboard automaticamente
   - Seed dos 47 parques do `parks_seed.dart`
   - RLS: SELECT público, INSERT via service role

2. `strava-webhook` atualizado:
   - Passo 11 adicionado: `detectAndLinkPark()` após criar session com GPS
   - Calcula distância haversine do ponto GPS de início até o centro de cada parque
   - Se dentro do `radius_m`, insere em `park_activities` com display_name
   - Trigger dispara e recalcula leaderboard automaticamente

**Lacunas corrigidas:**
3. Migration `20260226310000_strava_activity_history.sql`:
   - Tabela para histórico de atividades Strava importadas na conexão
   - Colunas: user_id, strava_activity_id, name, distance_m, moving_time_s, etc.
   - Unique index em (user_id, strava_activity_id) para upsert
   - RLS: own read/insert

4. Edge Function `delete-account`:
   - Remove de coaching groups, cancela desafios pendentes
   - Anonimiza perfil, deleta strava connection
   - Deleta auth user via admin API

5. Edge Function `validate-social-login`:
   - Gera auth_url para TikTok OAuth quando credenciais configuradas
   - Retorna erro gracioso se TIKTOK_CLIENT_KEY não está configurado
   - Preparado para quando TikTok for habilitado

**Fluxo completo dos parques:**
```
Strava activity → webhook → session criada → GPS start checado contra parks
  → match? → INSERT park_activities → trigger → refresh park_leaderboard
  → App: MyParksScreen lê park_activities → ParkScreen lê leaderboard/community/segments
```

### Arquivos criados:
- `supabase/migrations/20260226300000_parks_tables.sql`
- `supabase/migrations/20260226310000_strava_activity_history.sql`
- `supabase/functions/delete-account/index.ts`
- `supabase/functions/validate-social-login/index.ts`

### Arquivos modificados:
- `supabase/functions/strava-webhook/index.ts` (park detection + detectAndLinkPark)

### Risco:
Baixo. Tabelas novas com RLS. Webhook falha graciosamente (catch isolado).
Edge functions novas não afetam fluxos existentes.

---

## DECISÃO 085 — Liga de Assessorias: auto-enroll, portal admin, acesso staff (27/02/2026)

### Contexto:
A Liga de Assessorias (DECISAO 070) tinha três problemas operacionais:
1. Nenhuma assessoria participava automaticamente — requer INSERT manual em `league_enrollments`
2. Temporadas (`league_seasons`) precisavam ser criadas manualmente via SQL
3. O staff (professor/admin da assessoria) não tinha acesso à tela de Liga no app

### Decisão:

**1. Auto-enroll automático:**
O `league-snapshot` agora, antes de calcular scores, busca todas as `coaching_groups`
com `approval_status = 'approved'` e insere automaticamente em `league_enrollments`
as que ainda não estão inscritas na temporada ativa. Mesmo comportamento quando
o admin ativa uma temporada via portal. Resultado: zero fricção — toda assessoria
aprovada participa automaticamente.

**2. Portal admin (`/platform/liga`):**
- Página para o admin da plataforma gerenciar temporadas da liga
- Criar nova temporada (nome, data início, data fim) com status `upcoming`
- Ativar temporada: muda status para `active`, encerra temporada anterior se houver,
  auto-enrolla todas as assessorias aprovadas
- Encerrar temporada: muda status para `completed`
- Gerar snapshot manualmente: chama `league-snapshot` EF sob demanda
- Visualizar ranking da semana corrente com tabela detalhada
- Cards de KPIs: assessorias inscritas, última semana processada, dias restantes
- API route: `POST /api/platform/liga` (actions: create_season, activate_season,
  complete_season, trigger_snapshot)
- Link "Liga" adicionado à sidebar do admin

**3. Acesso staff no app:**
- Card "Liga" adicionado ao `StaffDashboardScreen` (entre Créditos e Portal)
- Ícone `shield_rounded`, cor indigo, navega para `LeagueScreen`
- Staff agora vê o mesmo ranking que os atletas + contribuição pessoal

### Arquivos criados:
- `portal/src/app/platform/liga/page.tsx`
- `portal/src/app/platform/liga/league-admin.tsx`
- `portal/src/app/api/platform/liga/route.ts`

### Arquivos modificados:
- `supabase/functions/league-snapshot/index.ts` (auto-enroll antes do cálculo)
- `portal/src/app/platform/platform-sidebar.tsx` (+link Liga)
- `omni_runner/lib/presentation/screens/staff_dashboard_screen.dart` (+card Liga)

### Risco:
Nenhum. Auto-enroll é idempotente (UNIQUE constraint em season_id + group_id).
Portal protegido por `platform_role = 'admin'`. LeagueScreen já existia e funciona
para qualquer usuário autenticado.

---

## DECISÃO 086 — Liga global + ligas estaduais (27/02/2026)

### Contexto:
A liga era global sem filtro geográfico — todas as assessorias num ranking único.
Uma assessoria de Manaus competia com uma de Porto Alegre sem contexto local.
A `coaching_groups` tinha `city` mas não tinha `state` (UF).

### Decisão:
Liga global sempre visível + ranking filtrado por estado como sub-seção.
Mesmos dados, mesma temporada — o filtro é aplicado na leitura, não na escrita.

### Implementação:

**1. Migration `20260227100000_coaching_groups_state.sql`:**
- Adicionado `state TEXT DEFAULT ''` em `coaching_groups`
- Index parcial em `state` para queries filtradas
- `fn_create_assessoria` atualizada para aceitar `p_state TEXT`

**2. `league-list` EF — filtro por scope:**
- `GET /league-list?scope=global` — ranking completo (default)
- `GET /league-list?scope=state` — auto-detecta UF da assessoria do caller
- `GET /league-list?scope=state&state=SP` — filtra por UF específica
- Quando filtrado, o ranking é re-numerado (1, 2, 3...) dentro do estado
- Response inclui `scope`, `state_filter` e campo `state` em cada entry

**3. `LeagueScreen` — chips de filtro:**
- `FilterChip` "Global" e "Meu Estado" no topo da lista
- "Meu Estado" auto-detecta a UF da assessoria do usuário via server
- Empty state diferenciado: "Nenhuma assessoria do seu estado participou ainda"

**4. `StaffSetupScreen` — dropdown de UF:**
- Dropdown com os 27 estados brasileiros ao criar assessoria
- Valor enviado via `p_state` ao `fn_create_assessoria`
- Armazenado em uppercase (ex: `SP`, `RJ`, `MG`)

**5. Portal Liga — estado no ranking:**
- Coluna "Local" mostra "Cidade, UF" quando ambos preenchidos

### Arquivos criados:
- `supabase/migrations/20260227100000_coaching_groups_state.sql`

### Arquivos modificados:
- `supabase/functions/league-list/index.ts` (scope + state filter + re-rank)
- `omni_runner/lib/presentation/screens/league_screen.dart` (chips + state display)
- `omni_runner/lib/presentation/screens/staff_setup_screen.dart` (dropdown UF)
- `portal/src/app/platform/liga/page.tsx` (select state)
- `portal/src/app/platform/liga/league-admin.tsx` (coluna Local)

### Risco:
Nenhum. Assessorias sem `state` preenchido aparecem normalmente no ranking global
mas não aparecem no filtro estadual. O campo é opcional — assessorias existentes
podem atualizar o estado via Supabase Dashboard ou futura tela de edição.

---

## DECISAO 087 — Redesign completo dos Desafios: goal-based + remoção de team_vs_team

**Data:** 2026-02-26

### Contexto:
O sistema de desafios usava `ChallengeMetric` (distance/pace/time) com um campo `target`
opcional que, quando vazio, significava "quem fizer mais ganha". Isso gerava cenários absurdos:
- Pace sem distância de referência: qual pace? em qual distância?
- Tempo numa janela de 3h: quem correr 3h seguidas ganha
- Distância com target vazio: OK mas mal documentado

Além disso, `team_vs_team` (assessoria vs assessoria) não existe mais na UI do app.
Só existem 1v1 e grupo. A confusão entre "team" e "group" não fazia sentido.

### Decisão:
1. Substituir `ChallengeMetric` por `ChallengeGoal` com 4 tipos claros:
   - `fastest_at_distance`: quem completa X km no menor tempo (target obrigatório)
   - `most_distance`: quem acumula mais km no período (target opcional)
   - `best_pace_at_distance`: melhor pace numa sessão >= X km (target obrigatório)
   - `collective_distance`: grupo cooperativo soma km para meta (target obrigatório, grupo only)

2. Remover `ChallengeType.teamVsTeam` — apenas `oneVsOne` e `group`

3. Remover campos `team` do participante e `teamAGroupId`/`teamBGroupId` do desafio

4. Lógica de vencedor reescrita por goal type no evaluator e settle-challenge EF

### Arquivos criados:
- `supabase/migrations/20260227200000_challenge_goal_redesign.sql`

### Arquivos modificados (domínio):
- `challenge_rules_entity.dart` (ChallengeMetric → ChallengeGoal, metric → goal)
- `challenge_entity.dart` (removido team fields, removido ChallengeType.teamVsTeam)
- `challenge_participant_entity.dart` (removido campo team)
- `challenge_result_entity.dart` (metric → goal)
- `challenge_evaluator.dart` (reescrito: _evaluateCollective, _evaluateGroupCompetitive)
- `create_challenge.dart` (removido team params)
- `settle_challenge.dart` (removido team reasons)
- `submit_run_to_challenge.dart` (lowerIsBetter por goal)
- `post_session_challenge_dispatcher.dart` (_extractProgressValue por goal)
- `evaluate_challenge.dart` (metric → goal)
- `challenge_run_binding_entity.dart` (atualizado docs)

### Arquivos modificados (data):
- `isar_challenge_repo.dart` (goal mapping, legacy ordinal compat)
- `challenge_record.dart` (docs atualizados, team fields mantidos para schema Isar)
- `challenge_result_record.dart` (docs atualizados)

### Arquivos modificados (presentation):
- `challenge_create_screen.dart` (reescrito: 4 GoalCards, sem team)
- `challenges_list_screen.dart` (_goalLabel)
- `challenge_details_screen.dart` (goal formatting)
- `challenge_result_screen.dart` (removido _buildTeamResults, goal labels)
- `challenge_invite_screen.dart` (removido team invite)
- `challenge_join_screen.dart` (removido team assignment, goal labels)
- `today_screen.dart` (removido teamVsTeam)
- `matchmaking_screen.dart` (ChallengeGoal)
- `challenges_bloc.dart` (removido team, goal mapping)
- `challenges_event.dart` (removido team params)

### Arquivos modificados (backend):
- `challenge-create/index.ts` (goal + validação target obrigatório)
- `settle-challenge/index.ts` (reescrito: goal-based winner logic)
- `challenge-join/index.ts` (removido team assignment)
- `challenge-get/index.ts` (goal no response)
- `challenge-list-mine/index.ts` (goal, removido team group resolution)
- `clearing-cron/index.ts` (removido team logic)

### Arquivos modificados (testes):
- `challenge_evaluator_test.dart` (removido team tests, ChallengeGoal)
- `settle_challenge_reason_test.dart` (removido teamVsTeam)
- `ledger_service_test.dart` (ChallengeGoal)

### Risco:
- Desafios existentes com `metric` antigo são migrados para `goal` via migration SQL
- Isar local: ordinals antigos mapeados gracefully (distance→mostDistance, pace→bestPaceAtDistance)
- team_vs_team existentes convertidos para group na migration
- EFs aceitam tanto `goal` quanto `metric` (fallback) no response para backward compat

---

## DECISAO 088 — Tipo "Time" (Team A vs Team B) nos desafios

**Data:** 2026-02-26
**Contexto:** Após remover `team_vs_team` (DECISAO 087), o usuário queria manter a opção de desafios de time, mas sem vínculo com assessoria. O criador do desafio atribui participantes livremente aos times A e B.

### Regras:
1. **3 tipos de desafio**: `oneVsOne`, `group` (ranking individual), `team` (Time A vs B)
2. **Times iguais**: O desafio só inicia quando ambos os times têm o mesmo número de atletas aceitos
3. **Qualquer participante em qualquer time**: Sem vínculo com assessoria — o criador e os próprios atletas escolhem o time
4. **collective_distance NÃO é permitido em team**: Para metas cooperativas, usar `group`

### Scoring por goal no tipo `team`:
| Goal | Cálculo do time | Vencedor |
|------|-----------------|----------|
| `fastest_at_distance` | Tempo do time = tempo do **último** membro a completar. Todos devem correr. | Menor tempo de time |
| `most_distance` | Distância do time = **soma** dos km de todos os membros | Mais km total |
| `best_pace_at_distance` | Pace do time = **média** dos paces dos membros que correram | Menor pace médio |

### OmniCoins no tipo `team`:
- Cada membro do **time vencedor** recebe: `pool / qtd_membros_vencedor`
- Cada membro do **time perdedor** recebe: 0
- Empate: cada um recebe de volta sua inscrição

### Alterações:

**Entities Dart:**
- `challenge_entity.dart`: Adicionado `ChallengeType.team` (ordinal 2)
- `challenge_participant_entity.dart`: Adicionado campo `team` (`'A'`/`'B'`/`null`)

**Domain use cases:**
- `challenge_evaluator.dart`: Adicionado `_evaluateTeam()` e `_teamScore()` — lógica completa de scoring por time
- `settle_challenge.dart`: `_reasonFor` inclui `ChallengeType.team` → `LedgerReason.challengeTeamWon`

**Data layer:**
- `isar_challenge_repo.dart`: `typeIndex` agora aceita 0-2 (team = 2), serializa/deserializa `team` no JSON do participante
- `challenge_record.dart`: Comentário atualizado para novo mapeamento de type

**BLoC:**
- `challenges_bloc.dart`: `_mapRemoteToEntity`, `_mergeChallenge`, `_shouldAutoActivate`, `_tryAutoStart`, `_onCreate`, `_syncChallengeToBackend` — todos tratam `team`

**UI screens:**
- `challenge_create_screen.dart`: SegmentedButton com 3 opções (1v1/Grupo/Time), explicação de scoring por goal no team, info box de regras do time
- `challenge_join_screen.dart`: Seleção de time (A/B) com `_TeamButton`, payload inclui `team`, botão desabilitado até selecionar time
- `challenge_details_screen.dart`: Badge de time (A/B) por participante, defaultTitle e typeLabel para team
- `challenge_result_screen.dart`: Team usa `_buildGroupResults`
- `challenges_list_screen.dart`: defaultTitle para team
- `challenge_invite_screen.dart`: defaultTitle para team
- `today_screen.dart`: iconForType e defaultTitle para team

**Backend Edge Functions:**
- `challenge-create/index.ts`: Aceita `type = 'team'`, bloqueia `collective_distance + team`, criador entra como `team: 'A'`
- `settle-challenge/index.ts`: Bloco `isTeam` com `computeTeamScore()`, distribuição de coins por time
- `challenge-join/index.ts`: Aceita `team` no body, validação de equilíbrio de times, auto-ativação com times balanceados
- `challenge-get/index.ts`: Inclui `team` no select e response dos participantes
- `challenge-list-mine/index.ts`: Inclui `team` no select dos participantes

**Migration SQL:**
- `20260227300000_challenge_team_type.sql`: CHECK constraint `type IN ('one_vs_one', 'group', 'team')`, coluna `team` em `challenge_participants` com CHECK `IN ('A', 'B')`

**Testes:**
- `challenge_evaluator_test.dart`: Testes para team mostDistance, fastestAtDistance (last to finish), bestPaceAtDistance (average), nobody ran (refund)
- `settle_challenge_reason_test.dart`: ChallengeType.team no containsAll

---

## DECISAO 089 — UX dos Desafios: Clareza Total para Usuário Leigo

**Data:** 2026-02-26
**Status:** Implementada

### Problema

Os textos e labels das telas de desafio usavam termos técnicos ou ambíguos que não deixavam claro para um usuário leigo:
1. O que cada tipo de desafio significa na prática
2. O que o atleta precisa fazer para cada goal
3. Como exatamente o vencedor é decidido
4. O que acontece com as OmniCoins

### Decisão

Reescrever todos os textos de UX em todas as telas do fluxo de desafios para que um "usuário dummy" entenda perfeitamente.

### Princípios aplicados

1. **Cada tipo tem explicação visível:** Info box aparece ao selecionar qualquer tipo (1v1 / Grupo / Time), não só Time
2. **Goal cards auto-explicativos:** Subtítulos expandidos explicam em 1-2 frases o que o atleta faz e como ganha
3. **"Como o vencedor é decidido":** Novo widget dedicado aparece na criação, nos detalhes, no convite e no resultado
4. **Prêmio explícito:** Explicação de como OmniCoins são distribuídas (pool, divisão, refund)
5. **Consistência:** Labels, títulos default e descrições iguais em todas as telas
6. **Sem jargão:** "pace médio (min/km)" ao invés de só "pace", "ranking individual" ao invés de só "competitivo"

### Arquivos alterados

- `challenge_create_screen.dart`: _TypeInfoBox, _WinnerExplainerBox, goal cards, target helpers, goal rules
- `challenge_details_screen.dart`: _RulesCard (Vencedor + Prêmio), _metricExplain, _typeLabel, _metricLabel
- `challenge_join_screen.dart`: winner explainer card, _goalLabel, _prizeExplain, type labels
- `challenge_result_screen.dart`: bug fix isTeam, _goalResultExplain
- `challenges_list_screen.dart`, `challenge_invite_screen.dart`, `today_screen.dart`: labels e default titles
- `docs/GAMIFICATION_POLICY.md` §4: Reescrito com seções 4.0/4.1/4.2/4.2b
- `docs/CONTEXT_DUMP.md`: Nova sprint entry

---

## DECISÃO 090 — Correções Críticas: Entry Fee Debit, Pool Real, Anti-Spoof

**Data:** 2026-02-26

### Problema

Auditoria pré-launch identificou 4 vulnerabilidades críticas:

1. **B1 — Entry fee nunca debitado:** `challenge-create` e `challenge-join` EFs não debitavam OmniCoins da wallet do criador/participante. O settle calculava pool como `entry_fee_coins × N` e creditava coins que nunca foram coletados → **inflação de moeda**.
2. **B2 — Sem balance check:** Nenhuma verificação de saldo antes de criar/entrar em desafios com stake.
3. **B3 — verify-session user_id spoofing:** O payload do body (`p.user_id`) era usado no `WHERE` clause do `UPDATE sessions` e no `eval_athlete_verification`, permitindo que um usuário autenticado alterasse a verificação de sessões de outro usuário.
4. **B4 — Pool teórico no settle:** `settle-challenge` calculava pool teoricamente em vez de consultar débitos reais no `coin_ledger`.

### Correções implementadas

**B1+B2 — Debit atômico com balance check:**
- Nova RPC `debit_wallet_checked(p_user_id, p_amount)` — `SECURITY DEFINER`, faz `UPDATE wallets SET balance_coins = balance_coins - p_amount WHERE balance_coins >= p_amount`, retorna `boolean`.
- `challenge-create`: após inserir participante, chama `debit_wallet_checked`. Se falha → rollback (deleta participant + challenge), retorna 402.
- `challenge-join`: idem, com rollback adequado para paths "novo participante" e "invited → accepted".
- Ambos inserem entry no `coin_ledger` com reason `challenge_entry_fee` e `delta_coins` negativo.

**B3 — Anti-spoof em verify-session:**
- Substituído `p.user_id` por `user.id` (autenticado via JWT) em: `UPDATE sessions ... WHERE user_id`, `eval_athlete_verification`, e logs.

**B4 — Pool real no settle:**
- `settle-challenge` agora consulta `coin_ledger WHERE ref_id = challenge.id AND reason = 'challenge_entry_fee'` para calcular o pool real.
- Refund quando ninguém correu: cria entries `challenge_entry_refund` no ledger + chama `increment_wallet_balance` para devolver coins.
- Aplicado a todas as branches: team, collective, e competitive.

### Migration

`20260227400000_challenge_team_and_entry_fee.sql`:
- `challenges_type_check`: adiciona `'team'`
- `challenge_participants.team`: coluna TEXT com CHECK `('A','B')`
- `coin_ledger_reason_check`: adiciona `'challenge_team_won'`, `'challenge_team_completed'`
- `debit_wallet_checked()`: nova RPC

### Arquivos alterados

- `supabase/functions/challenge-create/index.ts`
- `supabase/functions/challenge-join/index.ts`
- `supabase/functions/verify-session/index.ts`
- `supabase/functions/settle-challenge/index.ts`
- `supabase/migrations/20260227400000_challenge_team_and_entry_fee.sql`

---

## DECISÃO 091 — LedgerReason ordinals estáveis + countCreditsToday fix

**Data:** 2026-02-26

### Problema

**INC-01 (P1):** `LedgerReason` usava `.index` (ordinal posicional do Dart enum) para persistência no Isar. Inserir novos valores no meio do enum deslocava ordinals existentes, corrompendo dados no upgrade.

**INC-03 (P3):** `countCreditsToday()` filtrava por `deltaCoins > 0`, contando pool wins, refunds e streaks além de session rewards. Isso inflava o count e podia bloquear session rewards legítimos pelo rate limit de 10/dia.

### Correções

**INC-01:** Mapa explícito `LedgerReason → int` com valores fixos (nunca reordenar, só append). Novo getter `stableOrdinal` e factory `fromStableOrdinal()` no enum. `IsarLedgerRepo` atualizado para usar esses métodos em vez de `.index`/`.values[]`.

**INC-03:** `countCreditsToday()` agora filtra por `reasonOrdinalEqualTo(sessionCompleted.stableOrdinal)` em vez de `deltaCoinsGreaterThan(0)`.

### Testes adicionados

- Cada valor do enum tem ordinal único
- Round-trip `stableOrdinal → fromStableOrdinal` para todos os valores
- `fromStableOrdinal(9999)` lança `ArgumentError`
- Ordinals fixos conferem com documentação do `ledger_record.dart`

### Arquivos alterados

- `lib/domain/entities/ledger_entry_entity.dart`
- `lib/data/repositories_impl/isar_ledger_repo.dart`
- `test/domain/usecases/gamification/ledger_service_test.dart`

---

## DECISÃO 092 — SettleChallenge: idempotência per-entry + unificação via LedgerService

**Data:** 2026-02-26

### Problema

**INC-02 (P2):** `SettleChallenge` escrevia ledger entries diretamente via `_ledgerRepo.append()` com UUIDs novos a cada chamada. Se o use case crashasse mid-loop (após escrever N entries mas antes de marcar `completed`), uma re-execução duplicaria entries — double-credit de coins.

**INC-06 (P2):** `SettleChallenge` e `LedgerService` tinham dois caminhos de credit independentes com padrões de idempotência diferentes. Mudanças em invariantes (ex: cap de balance, audit trail) precisariam ser feitas em dois lugares.

**INC-05:** Já corrigido — `ChallengesBloc` já usa `Uuid().v4()`.

### Correções

1. **`LedgerService`**: novo método público `creditReward()` — wrapper para `_creditSingle()` com idempotência por `(userId, refId, reason)`.

2. **`SettleChallenge`**: refatorado para depender de `LedgerService` em vez de `ILedgerRepo` + `IWalletRepo`. Cada credit agora passa por `creditReward()`, que faz `_alreadyExists()` check antes de escrever. Re-execução após crash é segura.

3. **`service_locator.dart`**: `LedgerService` registrado no DI. `SettleChallenge` recebe `LedgerService` em vez de repos diretos.

### Testes

- 3 novos testes para `creditReward`: credit funciona, idempotente (second call skips), skips amount <= 0
- `settle_challenge_reason_test.dart`: `.index` → `.stableOrdinal`

### Arquivos alterados

- `lib/domain/usecases/gamification/ledger_service.dart`
- `lib/domain/usecases/gamification/settle_challenge.dart`
- `lib/core/service_locator.dart`
- `test/domain/usecases/gamification/ledger_service_test.dart`
- `test/domain/usecases/gamification/settle_challenge_reason_test.dart`

---

## DECISÃO 093 — A3 + AF2 + INC-04: Doc counts, motion radius, catch genérico

**Data:** 2026-02-26

### Correções

**A3 — Contagem de Edge Functions inconsistente nos docs:**
- Contagem real: 54 Edge Functions, 59 migrations.
- `ARCHITECTURE.md`: 41→54 EFs, 8→59 migrations.
- `SUPABASE_BACKEND_GUIDE.md`: 29→54, 31→54, 27→54 em todos os locais.

**AF2 — NO_MOTION_PATTERN falso positivo em pistas:**
- `MOTION_RADIUS_M` de 50m→150m em `verify-session/index.ts`.
- 200m track tem ~63m de diâmetro, 400m track tem ~127m. Raio de 150m permite corridas em pistas sem gerar flag falsa, mas ainda detecta spoofing estático.

**INC-04 — PostSessionChallengeDispatcher catch genérico:**
- `on Exception` (que silenciava erros de I/O como "alreadySubmitted") substituído por catches separados: `on SessionAlreadySubmitted` → `alreadySubmitted`, `on GamificationFailure` / `on Exception` → novo `submitFailed`.
- Novo `BindingRejectionReason.submitFailed` adicionado ao enum.
- Bug fix: `session.elapsedMs` (getter inexistente) → `(session.endTimeMs ?? nowMs) - session.startTimeMs`.

### Arquivos alterados

- `docs/ARCHITECTURE.md`
- `SUPABASE_BACKEND_GUIDE.md`
- `supabase/functions/verify-session/index.ts`
- `lib/domain/usecases/gamification/post_session_challenge_dispatcher.dart`
- `lib/domain/entities/challenge_run_binding_entity.dart`

---

## DECISÃO 094 — M2 + M3 + M5: HR validation, race guard, batch settle

**Data:** 2026-02-26

### Correções

**M2 — HR plausibility em verify-session:**
- Novos flags de qualidade: `IMPLAUSIBLE_HR_LOW` (avg_bpm < 80 com distância > 1km) e `IMPLAUSIBLE_HR_HIGH` (avg_bpm > 220).
- Adicionados a `integrity_flags.ts` e ao pipeline de verificação em `verify-session`.
- HR flags são QUALITY (não CRITICAL) — informacionais, alimentam trust_score mas não bloqueiam diretamente.

**M3 — Race condition guard em settle-challenge:**
- Antes de processar, atomicamente claim via `UPDATE challenges SET status='completing' WHERE status IN ('active','completing')`. Se 0 rows → skip.
- Antes de escrever resultados, verifica se `challenge_results` já existem. Se sim → marca completed e skip. Previne double-write por processos concorrentes.

**M5 — Batch wallet updates:**
- Wallet updates via `increment_wallet_balance` agora rodam em paralelo com `Promise.all` em vez de sequencialmente. Reduz latência de N×RTT para 1×RTT (onde N = participantes com coins).

### Arquivos alterados

- `supabase/functions/_shared/integrity_flags.ts`
- `supabase/functions/verify-session/index.ts`
- `supabase/functions/settle-challenge/index.ts`

---

## DECISÃO 095 — M4 + M6 + M7: Retention, legacy cleanup, wallet reconciliation

**Data:** 2026-02-26

### Correções

**M6 — Remoção do tracking GPS legado:**
- Removidos 7 arquivos dead code (~75KB): `TrackingScreen`, `DebugTrackingScreen`, `TrackingBloc`, `TrackingEvent`, `TrackingState`, `TrackingBottomPanel`, `ChallengeGhostOverlay`.
- Registro de `TrackingBloc` removido do service_locator.
- Toda captura de corridas ocorre exclusivamente via Strava sync.
- `ARCHITECTURE.md` atualizado para refletir remoção.

**M7 — Reconciliação automática wallet vs ledger:**
- `reconcile_wallet(p_user_id)` RPC: compara `wallet.balance_coins` com `SUM(coin_ledger.delta_coins)`. Se drift != 0, corrige o balance e insere entry de audit (`admin_correction`, delta=0, note com drift/old/new).
- `reconcile_all_wallets()` RPC: batch para cron — itera todas as wallets e retorna `{ total_wallets, drifted, run_at }`.
- Nova reason `admin_correction` adicionada ao `coin_ledger_reason_check` constraint.
- `LedgerReason.adminCorrection` adicionada ao enum Dart com stableOrdinal 20.

**M4 — Política de retenção de sessions:**
- Tabela `sessions_archive` criada (espelho de `sessions` com RLS).
- `archive_old_sessions(p_retention_days DEFAULT 730)` RPC: move sessions completed/synced > 2 anos para archive, deleta originais. Idempotente via `ON CONFLICT DO NOTHING`.

### Arquivos alterados

- `supabase/migrations/20260227500000_wallet_reconcile_and_session_retention.sql` (novo)
- `lib/core/service_locator.dart` (TrackingBloc removido)
- `lib/domain/entities/ledger_entry_entity.dart` (adminCorrection)
- `lib/core/logging/logger.dart` (exemplo atualizado)
- `lib/presentation/blocs/README.md` (referência atualizada)
- `docs/ARCHITECTURE.md` (nota de legado atualizada)
- 7 arquivos deletados (tracking legado)

---

## DECISÃO 096 — M1: Tutorial in-app dedicado

**Data:** 2026-02-26

### Implementação

**Onboarding Tour expandido (3 novos slides):**
- Slide 7: "Desafie seus amigos" — explica os 3 tipos (1v1, Grupo, Time) com ícones visuais.
- Slide 8: "OmniCoins" — origem (assessoria), uso (inscrição em desafios), e que não têm valor monetário.
- Slide 9: "Atleta Verificado" — 7 corridas válidas, desbloqueio de desafios com OmniCoins, jogo justo.

**Tela "Como Funciona" (nova):**
- Acessível via Settings > Ajuda > "Como Funciona".
- 4 seções com cards informativos: Desafios (tipos, metas, lógica de vencedor), OmniCoins (origem, uso, regras), Verificação (por que, como, perda de status), Integridade (validação automática, o que é verificado).
- UI moderna: ícones com background colorido, cards com borda sutil, texto legível com height 1.5.

**Tooltips contextuais (3 novos, one-shot):**
- `firstStakeChallenge`: aparece na tela de criação quando inscrição > 0 — "OmniCoins são debitadas ao criar".
- `firstVerificationVisit`: aparece na tela de verificação — "Cada corrida válida te aproxima do Verificado".
- `firstWalletVisit`: aparece na carteira — "Seus OmniCoins vêm da assessoria".
- Widget reutilizável `ContextualTipBanner` com animação fade, dismiss "Entendi", e integração com `FirstUseTips`.

**Fix colateral:** Switch exhaustivo em `wallet_screen.dart` atualizado para `adminCorrection`.

### Arquivos alterados

- `lib/presentation/screens/onboarding_tour_screen.dart` (3 slides)
- `lib/presentation/screens/how_it_works_screen.dart` (novo)
- `lib/presentation/screens/settings_screen.dart` (link "Como Funciona")
- `lib/presentation/widgets/contextual_tip_banner.dart` (novo)
- `lib/core/tips/first_use_tips.dart` (3 TipKeys)
- `lib/presentation/screens/challenge_create_screen.dart` (tooltip stake)
- `lib/presentation/screens/wallet_screen.dart` (tooltip + switch fix)
- `lib/presentation/screens/athlete_verification_screen.dart` (tooltip)

---

## DECISÃO 097 — Step cadence correlation server-side (anti-veículo)

**Data:** 2026-02-26
**Contexto:** O strava-webhook já verificava cadência por stream. O verify-session (chamado pelo Flutter client) não tinha essa verificação.
**Decisão:** Adicionar `avg_cadence_spm` como campo opcional no payload do verify-session. Se avg cadence < 100 SPM com velocidade média > 15 km/h e distância > 1 km, emitir flag `VEHICLE_SUSPECTED`.

**Implementação:**
- verify-session: novo threshold `VEHICLE_MIN_SPEED_KMH=15`, `VEHICLE_MAX_CADENCE_SPM=100`, `VEHICLE_MIN_DISTANCE_M=1000`.
- `integrity_flags.ts`: comentário atualizado — VEHICLE_SUSPECTED agora verificado em 2 locais (strava-webhook + verify-session).
- Flutter: `WorkoutSessionEntity` e `WorkoutSessionRecord` ganharam campo `avgCadenceSpm` (nullable).
- `sync_service.dart` e `sync_repo.dart`: passam `avgCadenceSpm` para verify-session quando disponível.

### Arquivos alterados

- `supabase/functions/verify-session/index.ts` (cadence check + import VEHICLE_SUSPECTED)
- `supabase/functions/_shared/integrity_flags.ts` (comentário)
- `omni_runner/lib/domain/entities/workout_session_entity.dart` (+avgCadenceSpm)
- `omni_runner/lib/data/models/isar/workout_session_record.dart` (+avgCadenceSpm)
- `omni_runner/lib/data/repositories_impl/isar_session_repo.dart` (mappers)
- `omni_runner/lib/data/repositories_impl/sync_repo.dart` (pass cadence)
- `omni_runner/lib/data/datasources/sync_service.dart` (optional param)

---

## DECISÃO 098 — Reconcile wallets cron Edge Function com alerting

**Data:** 2026-02-26
**Contexto:** A RPC `reconcile_all_wallets()` já existia (DECISÃO 095), mas não havia um mecanismo automatizado para chamá-la periodicamente e alertar operadores quando drift fosse detectado.
**Decisão:** Criar Edge Function `reconcile-wallets-cron` agendada via pg_cron (diário 04:00 UTC) que chama `reconcile_all_wallets()` e emite log estruturado com `severity: "ALERT"` quando `drifted > 0`, compatível com Datadog/Grafana/Cloud Logging.

### Arquivos alterados

- `supabase/functions/reconcile-wallets-cron/index.ts` (novo)

---

## DECISÃO 099 — Auditoria Portal Web: bloqueadores B1/B2/B3

**Data:** 2026-02-26
**Contexto:** Auditoria completa do portal web B2B identificou 3 bloqueadores.
**Decisão:** Corrigir os 3 bloqueadores antes de operação real.

### B3 — Fix N+1 em /platform/assessorias

Substituído loop sequencial (N queries para profiles + N queries para member count) por 2 batch queries com `IN` filter + Map lookup. De O(2N+1) queries para O(3).

### B1 — Audit trail (portal_audit_log)

- Nova migration `20260227600000_portal_audit_log.sql`: tabela append-only com RLS (platform admin lê tudo, staff lê do grupo).
- `portal/src/lib/audit.ts`: helper fire-and-forget para logging.
- Integrado em 10 API routes: team/invite, team/remove, verification/evaluate, auto-topup, gateway-preference, platform/assessorias (approve/reject/suspend), platform/refunds (approve/reject/process), platform/products (create/toggle/delete), platform/support (reply/close/reopen).

### B2 — Páginas placeholder substituídas

**Atletas** (`portal/src/app/(portal)/athletes/page.tsx`):
- Lista real de atletas com métricas: nome, status verificação, trust score, total corridas, distância total, última corrida, data de entrada.
- KPIs: total atletas, ativos (1+ corrida), verificados, km totais.
- Batch queries (sem N+1): coaching_members + athlete_verification + sessions.

**Engajamento** (`portal/src/app/(portal)/engagement/page.tsx`):
- DAU/WAU/MAU calculados via sessions.
- Retenção 30d (MAU/total atletas).
- Corridas e km (7d e 30d), desafios (30d).
- Gráfico de barras de atividade dos últimos 7 dias.
- Alerta de atletas inativos (sem atividade 30d).

### Arquivos alterados

- `supabase/migrations/20260227600000_portal_audit_log.sql` (novo)
- `portal/src/lib/audit.ts` (novo)
- `portal/src/app/platform/assessorias/page.tsx` (batch queries)
- `portal/src/app/(portal)/athletes/page.tsx` (reescrito)
- `portal/src/app/(portal)/engagement/page.tsx` (reescrito)
- `portal/src/app/api/team/invite/route.ts` (+audit)
- `portal/src/app/api/team/remove/route.ts` (+audit)
- `portal/src/app/api/verification/evaluate/route.ts` (+audit)
- `portal/src/app/api/auto-topup/route.ts` (+audit)
- `portal/src/app/api/gateway-preference/route.ts` (+audit)
- `portal/src/app/api/platform/assessorias/route.ts` (+audit)
- `portal/src/app/api/platform/refunds/route.ts` (+audit)
- `portal/src/app/api/platform/products/route.ts` (+audit)
- `portal/src/app/api/platform/support/route.ts` (+audit)

---
