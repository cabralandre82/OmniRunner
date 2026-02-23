# WearablesDeps.md — Auditoria de Dependências Wearable

> **Sprint:** W0.2
> **Status:** ATIVO
> **Referência:** WearablesPlan.md, ARCHITECTURE.md, DECISIONS.md

---

## 1. VERSÃO FLUTTER INSTALADA

```
Flutter 3.19.0 • channel stable
Dart SDK 3.3.0
DevTools 2.31.1
```

### Versão mínima definida no ARCHITECTURE.md

```
Flutter 3.22+
```

### Versão mínima definida no pubspec.yaml

```yaml
environment:
  sdk: '>=3.3.0 <4.0.0'
```

### Diagnóstico

| Aspecto | Valor | Status |
|---------|-------|--------|
| Flutter instalado | 3.19.0 | ⚠️ Abaixo do mínimo do ARCHITECTURE.md (3.22+) |
| Dart SDK | 3.3.0 | ⚠️ Insuficiente para `health` package (requer >=3.8.0) |
| pubspec sdk constraint | >=3.3.0 <4.0.0 | ⚠️ Precisa subir para >=3.8.0 após upgrade |
| DECISAO 003 | "upgrade para 3.22+ é tarefa de ambiente" | Upgrade já era previsto |

**BLOQUEANTE: O Flutter 3.19.0 (Dart 3.3.0) é incompatível com `health: ^13.3.1`
que exige Dart >=3.8.0. Upgrade obrigatório antes de adicionar dependências wearable.**

---

## 2. DEPENDÊNCIAS ATUAIS

### Produção (dependencies)

| # | Package | Versão Atual | Uso no Projeto | Conflito com Wearables? |
|---|---------|-------------|----------------|------------------------|
| 1 | `flutter` | sdk | Framework | Não |
| 2 | `flutter_bloc` | ^8.1.6 | State management | Não |
| 3 | `equatable` | ^2.0.7 | Value equality | Não |
| 4 | `get_it` | ^7.6.7 | Service locator / DI | Não |
| 5 | `geolocator` | ^11.0.0 | GPS tracking | Não |
| 6 | `permission_handler` | ^11.3.0 | Permissões runtime | **Reusar** para BLE + Health |
| 7 | `flutter_foreground_task` | ^8.0.0 | Android background service | Não |
| 8 | `isar` | ^3.1.0+1 | DB local | Não |
| 9 | `isar_flutter_libs` | ^3.1.0+1 | Isar native libs | Não |
| 10 | `path_provider` | ^2.1.0 | File paths | Não |
| 11 | `cupertino_icons` | ^1.0.6 | iOS icons | Não |
| 12 | `maplibre_gl` | ^0.20.0 | Mapa | Não |
| 13 | `flutter_tts` | ^4.0.2 | Audio coach TTS | Não (usa para HR alerts) |
| 14 | `shared_preferences` | ^2.2.3 | Settings persistence | Não |
| 15 | `supabase_flutter` | ^2.12.0 | Backend sync | Não |
| 16 | `connectivity_plus` | ^7.0.0 | Network status | Não |

### Desenvolvimento (dev_dependencies)

| # | Package | Versão Atual | Notas |
|---|---------|-------------|-------|
| 1 | `flutter_test` | sdk | Test framework |
| 2 | `flutter_lints` | ^3.0.0 | Lint rules |
| 3 | `isar_generator` | ^3.1.0+1 | Isar code gen |
| 4 | `build_runner` | ^2.4.0 | Code generation |

**Total atual: 16 dependencies + 4 dev_dependencies = 20 packages**

---

## 3. DEPENDÊNCIAS NECESSÁRIAS PARA WEARABLES

### 3.1 `health` — HealthKit + Health Connect

| Aspecto | Valor |
|---------|-------|
| Package | `health` |
| Versão latest (pub.dev) | 13.3.1 |
| Publicado em | 2026-02-06 |
| Dart SDK mínimo | **>=3.8.0 <4.0.0** |
| Flutter mínimo | >=3.6.0 |
| Licença | MIT |
| Plataformas | Android (Health Connect), iOS (HealthKit) |
| Dependências transitivas | `intl`, `device_info_plus`, `json_annotation`, `carp_serializable` |

**Funcionalidades utilizadas pelo Omni Runner:**

| Funcionalidade | Método | Bloco WearablesPlan |
|----------------|--------|---------------------|
| Ler HR do HealthKit/HC | `getHealthDataFromTypes(HEART_RATE)` | B |
| Ler steps | `getTotalStepsInInterval()` | D |
| Escrever workout | `writeWorkoutData(RUNNING)` | C |
| Escrever rota GPS | `startWorkoutRoute()` + `insertWorkoutRouteData()` | C |
| Autorizar tipos | `requestAuthorization()` | B |
| Verificar disponibilidade | `isHealthConnectAvailable()` | B |

**Risco de compatibilidade:** ALTO — exige Dart >=3.8.0. Sem Flutter upgrade, não resolve.

### 3.2 `flutter_blue_plus` — BLE Heart Rate Monitor

| Aspecto | Valor |
|---------|-------|
| Package | `flutter_blue_plus` |
| Versão latest (pub.dev) | 2.1.1 |
| Publicado em | 2026-02-12 |
| Dart SDK mínimo | ^3.0.0 |
| Flutter mínimo | >=3.7.0 |
| Licença | BSD-3-Clause |
| Plataformas | Android, iOS, macOS, Linux, Web, Windows |
| Dependências transitivas | Platform-specific sub-packages (android, darwin, linux, web, winrt) |

**Funcionalidades utilizadas pelo Omni Runner:**

| Funcionalidade | Método | Bloco WearablesPlan |
|----------------|--------|---------------------|
| Scan HRM devices | `FlutterBluePlus.startScan(withServices: [0x180D])` | A |
| Connect to device | `device.connect(autoConnect: true)` | A |
| Discover HR service | `device.discoverServices()` | A |
| Subscribe HR notifications | `characteristic.setNotifyValue(true)` | A |
| Parse BPM from bytes | Manual (flags byte + uint8/uint16) | A |
| Disconnect | `device.disconnect()` | A |

**Risco de compatibilidade:** BAIXO — requer Dart ^3.0.0 (temos 3.3.0) e Flutter >=3.7.0 (temos 3.19.0). Compatível AGORA.

### 3.3 `permission_handler` — Permissões Runtime

| Aspecto | Valor |
|---------|-------|
| Package | `permission_handler` |
| Versão atual no projeto | ^11.3.0 |
| Versão latest (pub.dev) | 12.0.1 |
| Dart SDK mínimo (v12) | ^3.5.0 |
| Flutter mínimo (v12) | >=3.24.0 |

**Decisão: MANTER na versão ^11.3.0.**

Justificativa:
- Já está no projeto e funciona com Flutter 3.19.0
- Upgrade para v12 exige Flutter >=3.24.0 (incompatível com atual)
- v11.3.0 já suporta as permissões BLE e Health necessárias
- Não há funcionalidade nova em v12 que seja bloqueante para wearables
- Será atualizada naturalmente quando o Flutter for upgradado

**Permissões wearable que `permission_handler ^11.3.0` já suporta:**

| Permission | Enum | Suporte |
|------------|------|---------|
| `Permission.bluetooth` | Bluetooth genérico | ✅ |
| `Permission.bluetoothScan` | Android 12+ scan | ✅ |
| `Permission.bluetoothConnect` | Android 12+ connect | ✅ |
| `Permission.activityRecognition` | Step data | ✅ |

---

## 4. TABELA DE COMPATIBILIDADE

```
┌────────────────────────┬────────────┬─────────────┬──────────────┬────────────┐
│ Package                │ Versão     │ Dart Min    │ Flutter Min  │ Compatível │
│                        │            │             │              │ c/ 3.19.0? │
├────────────────────────┼────────────┼─────────────┼──────────────┼────────────┤
│ flutter_blue_plus      │ ^2.1.1     │ ^3.0.0      │ >=3.7.0      │ ✅ SIM     │
│ health                 │ ^13.3.1    │ >=3.8.0     │ >=3.6.0      │ ❌ NÃO     │
│ permission_handler     │ ^11.3.0    │ (já no proj) │ (já no proj) │ ✅ SIM     │
│ permission_handler     │ ^12.0.1    │ ^3.5.0      │ >=3.24.0     │ ❌ NÃO     │
└────────────────────────┴────────────┴─────────────┴──────────────┴────────────┘
```

---

## 5. ESTRATÉGIA DE UPGRADE SEGURA

### Princípios

1. **Não quebrar o core** — GPS, tracking, persistence, sync devem continuar 100%
2. **Upgrade Flutter primeiro** — resolver o bloqueio de Dart SDK antes de adicionar packages
3. **Um passo de cada vez** — upgrade + validate, depois adicionar dependency + validate
4. **Testes como gate** — 352 testes devem passar após cada etapa

### Plano de Upgrade em 4 Etapas

#### ETAPA 1 — Upgrade Flutter (BLOQUEANTE)

```
Objetivo: Sair do Flutter 3.19.0 → Flutter stable mais recente (>=3.27)
Motivo: health ^13.3.1 exige Dart >=3.8.0

Comandos:
  flutter upgrade --force
  # ou, para versão específica:
  flutter channel stable
  flutter upgrade

Após upgrade:
  1. Atualizar pubspec.yaml sdk constraint:
     environment:
       sdk: '>=3.8.0 <4.0.0'
  2. flutter pub get
  3. dart fix --apply (corrigir deprecations)
  4. flutter test → todos 352 devem passar
  5. dart analyze → 0 issues
```

**Riscos do upgrade Flutter:**

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Breaking changes em Dart 3.8 | Média | `dart fix --apply` corrige maioria; revisar changelog |
| Isar 3.x incompatível com Dart novo | Baixa | Isar 3.1 suporta Dart 3.x, testar isoladamente |
| maplibre_gl incompatível | Baixa | v0.20 suporta Flutter 3.22+, verificar changelog |
| flutter_foreground_task incompatível | Baixa | v8 suporta Flutter 3.x, verificar |
| supabase_flutter incompatível | Baixa | v2.12 suporta Flutter 3.22+, verificar |
| Build Android falha (Gradle/AGP) | Média | Seguir migration guide do Flutter |
| Build iOS falha (Xcode/CocoaPods) | Média | `cd ios && pod install --repo-update` |

**Procedimento seguro:**

```
# 1. Criar branch de upgrade
git checkout -b feat/flutter-upgrade

# 2. Fazer upgrade
flutter upgrade

# 3. Verificar versão
flutter --version

# 4. Atualizar SDK constraint no pubspec.yaml

# 5. Resolver dependências
flutter pub get

# 6. Aplicar fixes automáticos
dart fix --apply

# 7. Verificar análise estática
dart analyze

# 8. Rodar todos os testes
flutter test

# 9. Build de verificação
flutter build apk --debug
flutter build ios --no-codesign (se em macOS)

# 10. Se tudo OK → merge
```

#### ETAPA 2 — Adicionar `flutter_blue_plus`

```
Objetivo: BLE Heart Rate Monitor

Quando: Após ETAPA 1 concluída com sucesso
Motivo: Pode ser adicionado até sem o upgrade (compatível com 3.19), mas
        faz sentido agrupar após o upgrade para evitar dois ciclos de pub get

Comando:
  flutter pub add flutter_blue_plus

Resultado no pubspec.yaml:
  flutter_blue_plus: ^2.1.1

Verificação:
  flutter pub get → resolve sem conflitos
  flutter test → 352+ testes passam
  dart analyze → 0 issues
```

**Impacto em dependências existentes:**

| Dependência existente | Conflito? | Detalhes |
|----------------------|-----------|----------|
| geolocator | Não | Namespaces diferentes (GPS vs BLE) |
| permission_handler | Não | Complementar (BLE permissions) |
| flutter_foreground_task | Não | Foreground service pode manter BLE ativo |
| Todas as outras | Não | Sem overlap |

#### ETAPA 3 — Adicionar `health`

```
Objetivo: HealthKit (iOS) + Health Connect (Android)

Quando: Após ETAPA 1 concluída (Dart >=3.8.0 disponível)

Comando:
  flutter pub add health

Resultado no pubspec.yaml:
  health: ^13.3.1

Verificação:
  flutter pub get → resolve sem conflitos
  flutter test → 352+ testes passam
  dart analyze → 0 issues

Dependências transitivas adicionadas:
  - intl (>=0.18.0 <0.21.0) — pode conflitar se outra dep traz intl diferente
  - device_info_plus (^12.1.0) — nova dependência
  - json_annotation (^4.9.0) — pode já existir transitivamente
  - carp_serializable (^2.0.1) — nova dependência
```

**Potenciais conflitos:**

| Dependência transitiva | Risco | Mitigação |
|-----------------------|-------|-----------|
| `intl` | Médio | `supabase_flutter` pode trazer versão diferente; verificar `flutter pub deps` |
| `device_info_plus` | Baixo | Nova dependência, sem conflito esperado |
| `json_annotation` | Baixo | Pode já existir via Isar/build_runner; versão range é amplo |

#### ETAPA 4 — Configuração de Plataforma (sem código Dart)

```
Objetivo: Preparar Android e iOS para wearables

Arquivos alterados:
  1. android/app/src/main/AndroidManifest.xml
     - Permissões BLE: BLUETOOTH_SCAN, BLUETOOTH_CONNECT
     - Permissões Health Connect: READ/WRITE per data type
     - Health Connect queries
     - Privacy policy activity-alias
     - ACTIVITY_RECOGNITION

  2. android/app/src/main/kotlin/.../MainActivity.kt
     - FlutterActivity → FlutterFragmentActivity

  3. ios/Runner/Info.plist
     - NSBluetoothAlwaysUsageDescription
     - NSHealthShareUsageDescription
     - NSHealthUpdateUsageDescription
     - UIBackgroundModes: bluetooth-central

Verificação:
  flutter build apk --debug → compila
  flutter build ios --no-codesign → compila (se em macOS)
  flutter test → 352+ testes passam (config não afeta unit tests)
```

---

## 6. DEPENDÊNCIAS NÃO ADICIONADAS (DECISÃO CONSCIENTE)

| Package | Motivo para não adicionar |
|---------|--------------------------|
| `permission_handler ^12.0.1` | v11.3.0 já atende; v12 requer Flutter >=3.24 sem benefício novo |
| `sentry_flutter` | Planejado (DECISAO 011) mas fora do escopo wearable |
| `flutter_blue_plus_web` | Transitiva; web não é target do Omni Runner |
| `pedometer` / `sensors_plus` | Steps via `health` package é suficiente; evitar deps redundantes |
| `wearable_communicator` | Package instável; BLE direto via `flutter_blue_plus` é mais robusto |

---

## 7. PÓS-UPGRADE: CHECKLIST DE VALIDAÇÃO

```
Após completar ETAPAS 1-4:

□ flutter --version → Flutter >=3.27, Dart >=3.8.0
□ flutter pub get → exit 0 (sem conflitos)
□ dart analyze → 0 issues
□ flutter test → 352+ testes passam
□ flutter build apk --debug → APK gerado
□ flutter build ios --no-codesign → build iOS OK (se em macOS)
□ pubspec.yaml contém: flutter_blue_plus ^2.1.1, health ^13.3.1
□ pubspec.yaml NÃO contém deps desnecessárias
□ permission_handler permanece ^11.3.0
□ AndroidManifest.xml contém permissões BLE + Health Connect
□ Info.plist contém BLE + HealthKit descriptions
□ MainActivity estende FlutterFragmentActivity
□ git diff mostra apenas mudanças esperadas
```

---

## 8. RESUMO

| Item | Status |
|------|--------|
| Flutter upgrade necessário | ✅ Confirmado (3.19 → >=3.27) |
| `flutter_blue_plus ^2.1.1` | ✅ Compatível após upgrade |
| `health ^13.3.1` | ✅ Compatível após upgrade (Dart >=3.8.0) |
| `permission_handler` | ✅ Manter ^11.3.0 (já presente) |
| Conflitos entre deps existentes | ✅ Nenhum identificado |
| Estratégia de 4 etapas definida | ✅ Segura e incremental |

**Bloqueante principal: upgrade do Flutter antes de qualquer código wearable.**

---

*Documento gerado na Sprint W0.2*
