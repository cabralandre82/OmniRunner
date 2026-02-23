# BLE em Background — Checklist de Limitações e Mitigações

> SPRINT W6.1 — Robustez: Background Android/iOS  
> Última atualização: 17 Fev 2026

---

## 1. Visão Geral

A conexão BLE com monitores cardíacos (Polar, Garmin HRM, Wahoo TICKR) precisa
sobreviver a três cenários de background:

| Cenário | Android | iOS |
|---------|---------|-----|
| Tela desligada (screen off) | Foreground Service mantém o processo | `bluetooth-central` background mode |
| App minimizado (task switcher) | Foreground Service mantém o processo | `bluetooth-central` background mode |
| Doze / App Standby | WakeLock parcial via Foreground Service | iOS suspende após ~10s sem background mode |
| Battery saver agressivo (OEM) | **Problema — ver seção 3** | N/A (Apple controla) |

---

## 2. Estado Atual do Projeto

### Android — OK parcial

| Item | Status | Arquivo |
|------|--------|---------|
| `FOREGROUND_SERVICE` permission | ✅ Declarado | `AndroidManifest.xml:7` |
| `FOREGROUND_SERVICE_LOCATION` type | ✅ Declarado | `AndroidManifest.xml:8` |
| Foreground Service class registrada | ✅ | `AndroidManifest.xml:66-68` |
| `foregroundServiceType="location"` | ✅ | `AndroidManifest.xml:67` |
| `allowWakeLock: true` | ✅ | `foreground_task_config.dart:41` |
| `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` | ✅ | `AndroidManifest.xml:11-12` |
| BLE `neverForLocation` flag | ✅ | `AndroidManifest.xml:11` |
| ForegroundService started on workout start | ✅ | `tracking_screen.dart` |
| ForegroundService stopped on workout end | ✅ | `tracking_screen.dart` |
| **`FOREGROUND_SERVICE_CONNECTED_DEVICE`** | ❌ **FALTA** | — |
| Battery optimization exemption (UX) | ❌ Não implementado | — |
| Notification channel for BLE status | ❌ Não implementado | — |

### iOS — OK

| Item | Status | Arquivo |
|------|--------|---------|
| `bluetooth-central` background mode | ✅ | `Info.plist:65` |
| `location` background mode | ✅ | `Info.plist:64` |
| `NSBluetoothAlwaysUsageDescription` | ✅ | `Info.plist:59` |
| Core Bluetooth background restoration | ⚠️ Não implementado (melhoria futura) |

---

## 3. Limitações Conhecidas — Android

### 3.1. Doze Mode (Android 6+)

**Problema:** Em Doze, o sistema suspende rede, alarmes e wake locks parciais.
O Foreground Service com `TYPE_LOCATION` mantém o GPS ativo, mas o BLE scan
pode ser restringido.

**Mitigação atual:** `allowWakeLock: true` no `ForegroundTaskOptions` mantém
CPU wake lock parcial, que é suficiente para manter a conexão BLE ativa
(não estamos fazendo scan em background, apenas mantendo conexão existente).

**Status:** ✅ Coberto para conexão ativa. ❌ Scan em Doze não funciona.

### 3.2. App Standby Buckets (Android 9+)

**Problema:** Apps em buckets "rare" ou "restricted" têm jobs e alarmes
severamente limitados. O Foreground Service isenta da maioria das restrições.

**Status:** ✅ Coberto via Foreground Service.

### 3.3. Background Execution Limits (Android 8+)

**Problema:** Serviços de background são mortos após ~1 minuto.

**Mitigação:** Foreground Service com notificação persistente.

**Status:** ✅ Coberto.

### 3.4. Battery Saver Agressivo dos OEMs (Xiaomi, Samsung, Huawei, OnePlus, Oppo, Vivo)

**Problema crítico.** OEMs chineses e Samsung adicionam layers proprietárias
que matam processos independentemente do Foreground Service:

| OEM | Comportamento | Mitigação do Usuário |
|-----|---------------|---------------------|
| **Xiaomi (MIUI)** | AutoStart bloqueado, Battery Saver mata app | Habilitar AutoStart + ignorar otimização de bateria |
| **Samsung (One UI)** | "Sleeping apps" mata após 3 dias sem uso | Adicionar a "Never sleeping apps" |
| **Huawei (EMUI)** | App Launch Manager mata em background | Gerenciar manualmente: Auto-launch ON |
| **OnePlus (OxygenOS)** | Battery Optimization mata serviço | Desabilitar otimização para o app |
| **Oppo (ColorOS)** | Similar ao OnePlus | Gerenciar energia manualmente |
| **Vivo (FuntouchOS)** | Background consume excessivo → mata | Whitelist de background |

**Status:** ❌ **NÃO MITIGÁVEL PROGRAMATICAMENTE.** Requer:
1. Guia in-app direcionando o usuário a desabilitar otimização de bateria
2. Link para [dontkillmyapp.com](https://dontkillmyapp.com) por fabricante
3. `Intent` para `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (opcional, pode causar rejeição no Play Store)

### 3.5. FOREGROUND_SERVICE_CONNECTED_DEVICE (Android 14+ / API 34)

**Problema:** Android 14 introduziu tipos granulares de foreground service.
Para manter conexão BLE em foreground service, o tipo
`FOREGROUND_SERVICE_CONNECTED_DEVICE` deve ser declarado além de `location`.

**Impacto:** Sem esse tipo, o Android 14+ pode restringir o acesso BLE quando
o serviço foreground está rodando apenas com `type="location"`.

**Status:** ❌ **FALTA.** Necessário adicionar:

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>

<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="location|connectedDevice"
    android:exported="false"/>
```

**Prioridade:** P0 — Deve ser corrigido antes do release.

### 3.6. BLE Connection Interval e Latência

**Problema:** Em background, o Android pode negociar connection intervals mais
longos com o periférico BLE, aumentando a latência de entrega de notificações
HR de ~1s para ~2-4s.

**Impacto:** Atraso na atualização do BPM na UI e nos alertas de zona cardíaca.

**Mitigação:** Após conectar, solicitar `connectionPriorityRequest(high)` via
`flutter_blue_plus`. Em background, o OS pode ignorar, mas em foreground
service geralmente é respeitado.

**Status:** ⚠️ Não implementado. Melhoria de baixa prioridade (P2).

### 3.7. Bluetooth Adapter desligado pelo usuário

**Problema:** Se o usuário desligar o Bluetooth enquanto a corrida está ativa,
a conexão BLE é perdida e o scan não pode ser feito.

**Mitigação atual:**
- `BleReconnectManager` tenta reconexão automática com backoff exponencial
- Após 10 tentativas, desiste e atualiza o estado para `disconnected`
- UI reflete `hrConnectionState` corretamente

**Status:** ✅ Coberto. Melhoria possível: ouvir `FlutterBluePlus.adapterState`
e suspender reconexão enquanto adapter estiver OFF.

---

## 4. Limitações Conhecidas — iOS

### 4.1. Core Bluetooth Background Processing

**Problema:** iOS permite BLE em background com `bluetooth-central` mode, mas:
- Scan em background é limitado: `CBCentralManagerScanOptionAllowDuplicatesKey` é ignorado
- UUIDs de serviço devem ser especificados explicitamente no scan
- Callbacks podem ser atrasados em até 10s

**Status:** ✅ Nosso scan já filtra por UUID `0x180D` (HR Service).

### 4.2. Core Bluetooth State Preservation & Restoration

**Problema:** Se o iOS matar o app em background (pressão de memória), a
conexão BLE é perdida. O Core Bluetooth oferece State Restoration
(`CBCentralManagerOptionRestoreIdentifierKey`) para re-instanciar automaticamente.

**Mitigação atual:** Não implementado. `flutter_blue_plus` não expõe state
restoration diretamente, mas mantém conexão enquanto o app está alive.

**Status:** ⚠️ Não implementado. P2 — raro em prática (iOS raramente mata apps
com background modes ativos).

### 4.3. iOS 13+ Background App Refresh

**Problema:** Mesmo com background modes, iOS pode suspender o app se não houver
atividade de background contínua. A combinação `location` + `bluetooth-central`
mantém o app ativo.

**Status:** ✅ Coberto (ambos os modes estão declarados).

### 4.4. Low Power Mode (iOS)

**Problema:** Em modo de economia de energia, iOS reduz frequência de updates
de localização e pode atrasar callbacks BLE.

**Impacto:** Menor — HR updates podem ter +1-2s de latência.

**Status:** ✅ Aceitável. Sem mitigação programática possível.

---

## 5. Limitações Conhecidas — BLE (Cross-Platform)

### 5.1. Range e Obstáculos

| Situação | Range típico | Impacto |
|----------|-------------|---------|
| Cinta peitoral (Polar H10) sem obstáculo | 10-30m | Nenhum |
| Cinta peitoral sob roupa | 5-15m | Nenhum (phone no bolso/braço) |
| Sensor óptico de braço (Polar Verity) | 5-10m | Baixo |
| Phone no bolso traseiro + corpo como obstáculo | 1-5m | ⚠️ Possível desconexão intermitente |

**Mitigação:** `BleReconnectManager` reconecta automaticamente.

### 5.2. Interferência de Frequência

**Problema:** BLE opera em 2.4 GHz, compartilhando espectro com Wi-Fi, 
microondas, e outros dispositivos BLE. Em ambientes densos (academias,
largada de corrida com centenas de sensores), a conexão pode ser instável.

**Mitigação:** `BleReconnectManager` com backoff exponencial.

### 5.3. Múltiplos Dispositivos BLE

**Problema:** Alguns sensores (Garmin HRM-Pro) suportam apenas 1 conexão BLE
simultânea. Se o relógio Garmin do usuário já está conectado, o phone não
consegue conectar.

**Mitigação:** UX: informar o usuário para desconectar do relógio ou usar
ANT+ no relógio.

**Status:** ⚠️ Não temos detecção automática. P3 — aviso na UI de debug.

### 5.4. Sensor Contact Lost

**Problema:** Cintas peitorais podem perder contato com a pele durante
a corrida (suor insuficiente no início, movimento excessivo). O BLE HR
Measurement Characteristic reporta `sensorContact = false` mas continua
enviando BPM (geralmente 0 ou lixo).

**Mitigação atual:** `parseHeartRateMeasurement` expõe `sensorContact`.
`TrackingBloc` atualmente ignora esse campo.

**Status:** ⚠️ Deveria filtrar BPM quando `sensorContact == false`. P1.

---

## 6. Checklist de Ação — Prioridades

### P0 — Bloqueante para Release

- [ ] **Android 14+:** Adicionar `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission
  e `connectedDevice` ao `foregroundServiceType` do service no manifest

### P1 — Alta Prioridade

- [ ] **Filtrar sensorContact:** Ignorar amostras HR com `sensorContact == false`
  no `TrackingBloc` (evita BPM 0 ou lixo na UI e nos alertas de zona)
- [ ] **Guia de otimização de bateria:** Tela in-app com instruções por OEM
  para desabilitar otimização de bateria (link para dontkillmyapp.com)

### P2 — Média Prioridade

- [ ] **Connection priority request:** Chamar `requestConnectionPriority(high)`
  após conectar BLE para reduzir latência de notificações
- [ ] **Adapter state listener:** Ouvir `FlutterBluePlus.adapterState` e
  suspender `BleReconnectManager` enquanto Bluetooth estiver OFF
- [ ] **iOS State Restoration:** Investigar suporte em `flutter_blue_plus`
  para `CBCentralManagerOptionRestoreIdentifierKey`
- [ ] **Notificação BLE:** Adicionar status da conexão HR na notificação
  do foreground service ("Running — 3.2 km | ❤️ 145 BPM")

### P3 — Baixa Prioridade

- [ ] **Múltiplos dispositivos BLE:** Aviso na UI quando conexão falha por
  dispositivo já conectado a outro central
- [ ] **Métricas de estabilidade BLE:** Log de desconexões/reconexões por
  sessão para análise de qualidade de conexão

---

## 7. Matriz de Testes de Background

| # | Cenário | Android | iOS | Resultado Esperado |
|---|---------|---------|-----|-------------------|
| 1 | Iniciar corrida → desligar tela → 5 min | ✅ FGS mantém | ✅ BG modes | GPS + BLE HR contínuo |
| 2 | Iniciar corrida → ir para outro app → voltar | ✅ FGS mantém | ✅ BG modes | Sem perda de dados |
| 3 | Iniciar corrida → Doze mode (30 min inativo) | ✅ FGS + WakeLock | ⚠️ Possível atraso | GPS contínuo, BLE pode ter latência |
| 4 | Corrida ativa → Bluetooth OFF → ON | ✅ Reconexão automática | ✅ Reconexão | HR reconecta em ≤30s |
| 5 | Corrida ativa → sensor fora de range → volta | ✅ Reconexão | ✅ Reconexão | HR reconecta automaticamente |
| 6 | Corrida ativa → battery saver ativado (Samsung) | ⚠️ Pode matar | ✅ Sem impacto | **RISCO:** GPS/BLE podem parar |
| 7 | Corrida ativa → battery saver ativado (Xiaomi) | ❌ Mata o app | ✅ Sem impacto | **RISCO ALTO:** App morto |
| 8 | Corrida ativa → Low Power Mode (iOS) | N/A | ⚠️ Latência +1-2s | Aceitável |
| 9 | Corrida ativa → notificação foreground visível | ✅ Sempre | N/A | Mostra "Run in progress" |
| 10 | Corrida ativa → sensor contact lost (cinta solta) | ⚠️ BPM lixo | ⚠️ BPM lixo | **BUG:** Deveria filtrar |
| 11 | App morto → reabrir → session recovery | ✅ `RecoverActiveSession` | ✅ | Sessão recuperada |

---

## 8. Referências

- [dontkillmyapp.com](https://dontkillmyapp.com) — Guia por fabricante
- [Android Foreground Service Types](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- [Core Bluetooth Background Processing](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- [flutter_blue_plus Background Mode](https://github.com/boskokg/flutter_blue_plus/wiki)
- [flutter_foreground_task](https://pub.dev/packages/flutter_foreground_task)
