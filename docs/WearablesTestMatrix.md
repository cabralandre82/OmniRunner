# WearablesTestMatrix.md — Matriz de Testes Wearable

> **Sprint:** W0.1
> **Status:** ATIVO
> **Referência:** WearablesPlan.md, GAP_WEARABLES_SDK.md

---

## 1. TESTES DE PERMISSÃO

| # | Plataforma | Permissão | Cenário | Resultado Esperado |
|---|------------|-----------|---------|-------------------|
| P1 | Android 12+ | `BLUETOOTH_SCAN` | Usuário nega permissão BLE | App mostra diálogo explicativo, BLE scan desabilitado, GPS tracking funciona normalmente |
| P2 | Android 12+ | `BLUETOOTH_CONNECT` | Usuário nega permissão BLE connect | App não conecta ao HRM, mostra toast "Permissão Bluetooth necessária", tracking GPS funciona |
| P3 | Android 12+ | `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` | Usuário concede ambas | Scan BLE lista dispositivos HR, conexão funciona |
| P4 | Android 12+ | `BLUETOOTH_SCAN` | Usuário marca "Não perguntar novamente" | App detecta `permanentlyDenied`, mostra botão "Abrir Configurações" |
| P5 | iOS 13+ | `NSBluetoothAlwaysUsageDescription` | Usuário nega Bluetooth | Alert iOS nativo, app desabilita BLE, GPS tracking funciona |
| P6 | iOS 13+ | `NSBluetoothAlwaysUsageDescription` | Usuário concede Bluetooth | Scan BLE lista dispositivos HR |
| P7 | Android 14+ | Health Connect permissions (HR, Steps, Exercise) | Usuário nega todas | App funciona sem health data, export desabilitado, toast informativo |
| P8 | Android 14+ | Health Connect permissions | Usuário concede READ_HEART_RATE apenas | App lê HR da plataforma, steps e export desabilitados |
| P9 | Android 14+ | Health Connect permissions | Usuário concede todas READ + WRITE | Full functionality: leitura de HR/steps, export de workout |
| P10 | Android 14+ | `ACTIVITY_RECOGNITION` | Usuário nega | Step counter não funciona, `IntegrityDetectVehicle` desabilitado gracefully |
| P11 | Android 14+ | `ACTIVITY_RECOGNITION` | Usuário concede | Step data disponível via Health Connect |
| P12 | iOS 17+ | HealthKit authorization (HR, Steps, Workout) | Usuário nega todos | App funciona sem health data, export desabilitado |
| P13 | iOS 17+ | HealthKit authorization | Usuário concede HR + Steps apenas | App lê HR/steps, export de workout desabilitado |
| P14 | iOS 17+ | HealthKit authorization | Usuário concede todos | Full functionality: leitura + escrita |
| P15 | iOS 17+ | HealthKit authorization | Usuário revoga depois via Settings.app | App detecta perda de permissão no próximo acesso, degrada gracefully |
| P16 | Android 14+ | Health Connect app não instalada | Usuário tenta usar health features | App detecta ausência, mostra diálogo "Instalar Health Connect" com link para Play Store |

---

## 2. TESTES DE BLE (BLUETOOTH LOW ENERGY)

| # | Plataforma | Cenário | Resultado Esperado |
|---|------------|---------|-------------------|
| BLE1 | Android + iOS | Scan com HRM ligado e visível | Dispositivo aparece na lista em < 10s com nome e RSSI |
| BLE2 | Android + iOS | Scan sem nenhum HRM por perto | Lista vazia após timeout (10s), mensagem "Nenhum dispositivo encontrado" |
| BLE3 | Android + iOS | Scan com HRM desligado | Lista vazia, sem crash |
| BLE4 | Android + iOS | Conectar a HRM (Polar H10) | Conexão em < 5s, stream de BPM inicia, UI atualiza |
| BLE5 | Android + iOS | Conectar a HRM (Garmin HRM-Pro) | Conexão em < 5s, BPM stream funciona (broadcast mode) |
| BLE6 | Android + iOS | Conectar a HRM (Wahoo TICKR) | Conexão em < 5s, BPM stream funciona |
| BLE7 | Android + iOS | HRM desconecta durante corrida (out of range) | `onDisconnected` detectado, UI mostra "--" para HR, GPS tracking continua, auto-reconnect tentado |
| BLE8 | Android + iOS | HRM reconecta após desconexão | BPM stream reinicia automaticamente, UI volta a mostrar HR |
| BLE9 | Android + iOS | Bluetooth do phone desligado durante corrida | Detecção de BT off, HR mostra "--", tracking GPS continua normalmente |
| BLE10 | Android + iOS | Bluetooth do phone religado durante corrida | BLE reconnect automático ao HRM previamente conectado |
| BLE11 | Android + iOS | Dois HRMs visíveis simultaneamente | Lista mostra ambos, usuário seleciona um, conecta apenas ao selecionado |
| BLE12 | Android + iOS | HRM com bateria fraca | BPM stream funcional (BLE spec: funciona até 2.0V), valores normais |
| BLE13 | Android | BLE scan com Location desligado (Android requer) | Scan falha com mensagem clara "Ative a Localização para escanear Bluetooth" |
| BLE14 | iOS | BLE em background (tela bloqueada) | HR stream continua com `bluetooth-central` background mode |
| BLE15 | Android | BLE em background (tela desligada) | HR stream continua via foreground service |
| BLE16 | Android + iOS | App mata HRM connection no stop tracking | `disconnect()` chamado, recursos BLE liberados |

---

## 2.1. TESTES DE RECONEXÃO BLE (SPRINT W1.4)

| # | Plataforma | Cenário | Resultado Esperado |
|---|------------|---------|-------------------|
| RC1 | Android + iOS | HRM sai do alcance e volta em < 30s | Auto-reconnect com backoff exponencial (1s, 2s, 4s...), BPM stream retoma, UI mostra "Reconnecting..." durante tentativa |
| RC2 | Android + iOS | HRM sai do alcance por > 5 min | Após 10 tentativas (max), UI mostra erro "Auto-reconnect exhausted. Tap Retry." com botão de retry manual |
| RC3 | Android + iOS | Reconnect com backoff exponencial | Delays observados: ~1s, ~2s, ~4s, ~8s, ~16s, ~30s (cap), ~30s... — verificável via logs `BleReconnect` |
| RC4 | Android + iOS | Cancelar reconnect via botão Disconnect | `disconnect()` para reconnect imediatamente, estado volta a `idle`, sem tentativas extras |
| RC5 | Android + iOS | Last known device salvo após conexão | Após conectar, `SharedPreferences` contém `ble_hr_last_device_id` e `ble_hr_last_device_name` |
| RC6 | Android + iOS | Tela idle mostra botão "Reconnect: DeviceName" | Se existe last known device, botão aparece abaixo de "Start Scan", com nome do dispositivo |
| RC7 | Android + iOS | Reconectar via last known device | Tap em "Reconnect: DeviceName" → checa permissões → conecta direto (sem scan) → BPM stream inicia |
| RC8 | Android + iOS | Last known device não encontrado (desligado) | Timeout de conexão (10s), erro exibido, botão Retry disponível |
| RC9 | Android + iOS | Limpar last known device | Tap em "Clear saved device" → botão some, SharedPrefs limpo |
| RC10 | Android + iOS | Scan mostra "(last used)" no dispositivo salvo | Dispositivo previamente conectado aparece na lista com tag "(last used)" |
| RC11 | Android + iOS | ConnectionState stream atualiza UI | Transições `disconnected → scanning → connecting → connected → reconnecting → disconnected` refletidas em tempo real |
| RC12 | Android + iOS | dispose() limpa todas as subscriptions | Após `dispose()`, sem memory leaks: `_hrCharSub`, `_connStateSub`, `_scanResultsSub`, timers, controllers — todos cancelados |
| RC13 | Android + iOS | Scan com timeout configurável | `startScan(timeout: Duration(seconds: 5))` para scan em 5s (padrão 15s) |
| RC14 | Android + iOS | Reconnect bem-sucedido mantém HR stream ativo | Após reconnect, novos `HeartRateSample` chegam no mesmo stream sem necessidade de re-subscribe |
| RC15 | Android + iOS | Múltiplos ciclos disconnect/reconnect | Desconectar, reconectar ao mesmo device 3x consecutivas — sem crash, sem leak, stream funcional a cada vez |

---

## 3. TESTES DE HEALTHKIT (iOS)

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| HK1 | Ler HR samples dos últimos 30 min | Retorna lista de `HealthDataPoint` com BPM e timestamps |
| HK2 | Ler HR samples quando não há dados | Retorna lista vazia, sem crash |
| HK3 | Ler step count para intervalo de 1h | Retorna `int` com total de passos |
| HK4 | Ler step count sem permissão READ_STEPS | Retorna `null` ou `0`, sem crash, log de warning |
| HK5 | Escrever workout (RUNNING) com distância e calorias | Workout aparece no Apple Health app |
| HK6 | Escrever workout route com GPS points | Rota aparece no mapa do Apple Health |
| HK7 | Escrever workout sem permissão WRITE | `writeWorkoutData()` retorna `false`, app mostra erro amigável |
| HK8 | Escrever workout duplicado (mesmo start/end) | HealthKit aceita (não valida duplicatas), app marca como exported |
| HK9 | HealthKit indisponível (iPod Touch sem Health app) | `Health.isAvailable()` retorna `false`, features desabilitadas |
| HK10 | iPhone reiniciado (HealthKit requer unlock) | Primeiro acesso após reboot pode falhar, retry após unlock |

---

## 4. TESTES DE HEALTH CONNECT (Android)

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| HC1 | Health Connect instalado, permissions concedidas | Leitura de HR/steps funciona |
| HC2 | Health Connect NÃO instalado | App detecta via `<queries>`, mostra diálogo para instalar |
| HC3 | Health Connect instalado, permissions negadas | Features de saúde desabilitadas, tracking GPS funciona |
| HC4 | Ler HR records dos últimos 30 min | Retorna lista com BPM + timestamps |
| HC5 | Ler step records para intervalo | Retorna total steps |
| HC6 | Escrever exercise session (RUNNING) | Sessão aparece no Health Connect app |
| HC7 | Escrever exercise route com GPS coordinates | Rota aparece no Health Connect |
| HC8 | `MainActivity` não é `FlutterFragmentActivity` | `health` package crash no `registerForActivityResult` — BLOQUEANTE, detectar no build |
| HC9 | Android 13 (sem Health Connect nativo) | App verifica API level, sugere instalar Health Connect da Play Store |
| HC10 | Permissões revogadas pelo usuário via Settings | App detecta no próximo acesso, degrada gracefully |

---

## 5. TESTES DE EXPORT DE WORKOUT

| # | Plataforma | Cenário | Resultado Esperado |
|---|------------|---------|-------------------|
| EX1 | iOS | Export corrida 5 km com 30 min | Workout RUNNING aparece no Apple Health com distância, duração, calorias |
| EX2 | iOS | Export corrida com rota GPS (100 pontos) | Rota visível no mapa do Apple Health |
| EX3 | Android | Export corrida 10 km com 60 min | Exercise session aparece no Health Connect |
| EX4 | Android | Export corrida com rota GPS | Rota associada ao exercise no Health Connect |
| EX5 | iOS + Android | Export com flag `isExported = true` | Segunda tentativa de export é skip (idempotente) |
| EX6 | iOS + Android | Export sem permissão WRITE | Falha graceful, sessão marcada como não exportada, retry possível |
| EX7 | iOS + Android | Export corrida com 0 pontos (edge case) | Skip export, log warning, sem crash |
| EX8 | iOS + Android | Export automático habilitado (settings) | Export ocorre automaticamente no `FinishSession` |
| EX9 | iOS + Android | Export automático desabilitado | Export não ocorre, sessão marcada `isExported = false` |
| EX10 | iOS + Android | Export durante ausência de internet | Export local data para health platform (não requer internet), sucesso |

---

## 6. TESTES DE STEPS REAIS (IntegrityDetectVehicle)

| # | Plataforma | Cenário | Resultado Esperado |
|---|------------|---------|-------------------|
| ST1 | iOS + Android | Corrida normal (150-200 spm, 5:00/km) | `IntegrityDetectVehicle` retorna `false` (não é veículo) |
| ST2 | iOS + Android | Usuário em carro (0 spm, 40 km/h) | `IntegrityDetectVehicle` retorna `true`, flag `vehicleSuspected` |
| ST3 | iOS + Android | Bicicleta (60-80 spm, 25 km/h) | Resultado depende de thresholds configurados |
| ST4 | iOS + Android | Steps indisponíveis (sem permissão) | `IStepsSource.samplesForSession()` retorna lista vazia, vehicle detection desabilitado, corrida NÃO é invalidada |
| ST5 | iOS + Android | Health platform não instalada | Fallback: `IStepsSource` retorna vazio, sem crash |

---

## 7. TESTES DE VOICE HR ALERTS

| # | Plataforma | Cenário | Resultado Esperado |
|---|------------|---------|-------------------|
| VH1 | iOS + Android | HR entra em Zona 4 (80-90% max) | TTS: "Zona quatro, cento e sessenta e cinco BPM" |
| VH2 | iOS + Android | HR entra em Zona 5 (>90% max) | TTS: "Atenção! Zona cinco, cento e oitenta BPM" (tom urgente) |
| VH3 | iOS + Android | HR desce para Zona 2 | TTS: "Zona dois, cento e vinte BPM" |
| VH4 | iOS + Android | HR oscila entre zonas (1 BPM de diferença) | Hysteresis: só anuncia após 5+ segundos na nova zona (anti-spam) |
| VH5 | iOS + Android | HR alert desabilitado nas settings | Nenhum anúncio de HR, outros voice triggers funcionam |
| VH6 | iOS + Android | HR max não configurado (default 220-age) | Usa fórmula default, calcula zonas normalmente |
| VH7 | iOS + Android | HRM desconectado durante corrida | HR alerts pausam, mensagem TTS: "Monitor cardíaco desconectado" |
| VH8 | iOS + Android | HRM reconecta | HR alerts retomam, mensagem TTS: "Monitor cardíaco reconectado" |

---

## 8. TESTES DE INTEGRAÇÃO CRUZADA

| # | Cenário | Componentes | Resultado Esperado |
|---|---------|-------------|-------------------|
| X1 | BLE HR + Voice + Tracking simultâneos | BLE, TrackingBloc, AudioCoach | HR stream, GPS tracking e voice triggers funcionam sem interferência |
| X2 | HealthKit read + BLE HR simultâneos | health, flutter_blue_plus | Sem conflito; BLE HR tem prioridade (real-time), HealthKit é fallback |
| X3 | Export workout + Sync Supabase simultâneos | health, supabase | Ambas operações completam sem deadlock |
| X4 | Battery saver ativado durante corrida com BLE | System, BLE, GPS | Foreground service mantém GPS + BLE; possível degradação de scan |
| X5 | Chamada telefônica durante corrida com BLE HR | System, BLE | HR stream pode pausar brevemente, GPS tracking continua |
| X6 | App killed pelo OS e relançado com HRM conectado | System, BLE | App reconecta ao HRM via autoConnect, resume tracking se foreground service ativo |
| X7 | Steps + Vehicle detection + HR alerts simultâneos | health, BLE, AudioCoach | Todos os sistemas cooperam sem race conditions |

---

## 9. MATRIZ DE COMPATIBILIDADE DE DISPOSITIVOS

| Dispositivo | OS Min | BLE HR | HealthKit | Health Connect | Notas |
|-------------|--------|--------|-----------|----------------|-------|
| iPhone SE 2 | iOS 15 | ✅ | ✅ | N/A | Dispositivo mínimo iOS viável |
| iPhone 12+ | iOS 17 | ✅ | ✅ | N/A | Target principal iOS |
| Pixel 6/7/8 | Android 12+ | ✅ | N/A | ✅ | Target principal Android |
| Samsung S22+ | Android 12+ (One UI) | ✅ | N/A | ✅ | Testar battery optimization Samsung |
| Xiaomi 13+ | Android 12+ (MIUI) | ✅ | N/A | ✅ | Testar kill agressivo MIUI |
| Android Go | Android 12 | ⚠️ | N/A | ❌ | BLE pode não ter, HC pode não existir |

---

## 10. RESUMO QUANTITATIVO

| Categoria | Qtd Testes |
|-----------|-----------|
| Permissões | 16 |
| BLE | 16 |
| HealthKit | 10 |
| Health Connect | 10 |
| Export Workout | 10 |
| Steps / Vehicle Detection | 5 |
| Voice HR Alerts | 8 |
| Integração Cruzada | 7 |
| **TOTAL** | **82** |

---

*Documento gerado na Sprint W0.1*
