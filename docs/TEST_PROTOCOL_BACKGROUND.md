# Protocolo de Teste — Background GPS

> **Sprints:** 2.17 (Android) + 2.18 (iOS)
> **Status:** BLOQUEADAS — Requer integracao ForegroundTaskConfig + device fisico
> **Criado:** 2026-02-12

---

# PARTE 1 — Android (Sprint 2.17)

## Pre-requisitos Android

| Item | Detalhe |
|---|---|
| Device | Android fisico (NAO emulador — emulador nao simula Doze/OEM kill) |
| Android | API 29+ (Android 10 ou superior) |
| GPS | Habilitado, outdoor ou janela com sinal GPS |
| Permissoes | Location "Allow all the time" concedido |
| Bateria | >50% e SEM modo economia de bateria |
| App | Build debug instalado via `flutter run` |

## Antes de comecar (Android)

```
1. Desativar otimizacao de bateria para omni_runner:
   Configuracoes → Apps → Omni Runner → Bateria → Sem restricoes

2. Em dispositivos Xiaomi/Samsung/Huawei:
   Desativar "gerenciamento inteligente de bateria"
   Fixar app na lista de apps recentes (se disponivel)
```

## Passos do Teste Android

```
PASSO 1:  Abrir o app (DebugTrackingScreen deve aparecer)
PASSO 2:  Se necessario, tocar "Request Permission" e conceder ALL THE TIME
PASSO 3:  Tocar "Start Tracking" — estado deve mudar para TRACKING
PASSO 4:  Verificar que notificacao "Omni Runner — Run in progress" aparece
PASSO 5:  Anotar horario de inicio: ___:___:___
PASSO 6:  Anotar quantidade de pontos GPS no momento: ___
PASSO 7:  BLOQUEAR A TELA (botao power)
PASSO 8:  Caminhar/correr por 3-5 minutos
PASSO 9:  DESBLOQUEAR A TELA
PASSO 10: Anotar horario de fim: ___:___:___
PASSO 11: Anotar quantidade de pontos GPS agora: ___
PASSO 12: Verificar se notificacao ainda esta presente
PASSO 13: Tocar "Stop Tracking" — estado deve voltar para IDLE
PASSO 14: Verificar que notificacao desapareceu
```

## Resultados Esperados Android

| Verificacao | Criterio de sucesso |
|---|---|
| Notificacao persistente | Visivel durante todo o teste (passos 4-12) |
| Pontos GPS coletados | > 0 novos pontos apos desbloquear |
| Continuidade | Sem gap > 30s entre pontos consecutivos |
| App nao foi killada | App ainda funcional ao desbloquear |
| Stop funciona | Notificacao some apos Stop (passo 14) |

## Formulario de Resultado Android

```
Data do teste:           ____/____/____
Device:                  _________________ (modelo)
Android version:         _________________
Horario inicio:          ___:___:___
Horario fim:             ___:___:___
Duracao tela desligada:  ___ minutos
Pontos antes:            ___
Pontos depois:           ___
Novos pontos:            ___ (depois - antes)
Notificacao persistiu:   [ ] Sim  [ ] Nao
App foi killada:         [ ] Sim  [ ] Nao
Gap maximo entre pontos: ___ segundos
Stop removeu notif:      [ ] Sim  [ ] Nao
Observacoes:             _________________________________
```

## Classificacao Android

```
PASSOU:
   - Novos pontos > 0
   - App nao foi killada
   - Notificacao persistiu
   - Gap maximo < 30s
   - Stop removeu notificacao

PARCIAL:
   - Novos pontos > 0 mas com gaps > 30s
   - Ou notificacao sumiu mas pontos continuaram

FALHOU:
   - Zero novos pontos
   - Ou app foi killada pelo sistema
   - Ou notificacao nao apareceu (foreground service nao iniciou)
```

---

# PARTE 2 — iOS (Sprint 2.18)

## Pre-requisitos iOS

| Item | Detalhe |
|---|---|
| Device | iPhone fisico (NAO simulator — simulator nao simula background real) |
| iOS | 15.0 ou superior |
| GPS | Habilitado, outdoor ou janela com sinal GPS |
| Permissoes | Location "Always" concedido |
| Bateria | >50%, Low Power Mode DESATIVADO |
| App | Build debug instalado via `flutter run` |

## Limitacoes Conhecidas do iOS

| Limitacao | Impacto | Mitigacao |
|---|---|---|
| iOS throttle em background | Updates podem espaçar para ~1/s ou menos | Aceitavel para corrida; pace calculation compensa |
| iOS pode pausar app apos ~10min sem updates significativos | Gap nos dados | `allowsBackgroundLocationUpdates = true` no CLLocationManager |
| iOS 15+ resume automatico com movement | Gaps quando parado | Aceitavel; corredor esta em movimento |
| Simulator nao simula background real | Teste invalido em simulator | Obrigatorio usar device fisico |
| Low Power Mode reduz frequencia GPS | Dados esparsos | Pre-requisito: Low Power Mode OFF |

## Passos do Teste iOS

```
PASSO 1:  Abrir o app (DebugTrackingScreen deve aparecer)
PASSO 2:  Se necessario, tocar "Request Permission" e conceder "Always"
PASSO 3:  Tocar "Start Tracking" — estado deve mudar para TRACKING
PASSO 4:  Anotar horario de inicio: ___:___:___
PASSO 5:  Anotar quantidade de pontos GPS no momento: ___
PASSO 6:  Pressionar botao Home (app vai para background)
PASSO 7:  Caminhar/correr por 2-3 minutos
PASSO 8:  Reabrir o app (tap no icone)
PASSO 9:  Anotar horario de retorno: ___:___:___
PASSO 10: Anotar quantidade de pontos GPS agora: ___
PASSO 11: Verificar se tracking continuou (pontos novos existem)
```

## Teste Adicional iOS — Troca de App

```
PASSO 12: Com tracking ativo, abrir outro app (Safari, Musica)
PASSO 13: Usar o outro app por 1-2 minutos
PASSO 14: Voltar ao Omni Runner
PASSO 15: Verificar se pontos foram coletados durante o uso do outro app
```

## Resultados Esperados iOS

| Verificacao | Criterio de sucesso | Criterio aceitavel (iOS throttle) |
|---|---|---|
| Pontos GPS coletados em background | > 0 novos pontos | >= 1 ponto por 10 segundos |
| Continuidade | Sem gap > 15s | Gaps <= 30s aceitaveis |
| App nao foi suspensa | Tracking retomou automaticamente | Retomou ao reabrir (aceitavel) |
| Troca de app | Pontos durante uso de outro app | Pelo menos alguns pontos |

## Formulario de Resultado iOS

```
Data do teste:              ____/____/____
Device:                     _________________ (modelo)
iOS version:                _________________
Horario inicio:             ___:___:___
Horario retorno:            ___:___:___
Duracao em background:      ___ minutos
Pontos antes:               ___
Pontos depois:              ___
Novos pontos:               ___ (depois - antes)
Pontos/minuto em background: ___
Gap maximo entre pontos:    ___ segundos
App suspensa pelo iOS:      [ ] Sim  [ ] Nao
Troca de app testada:       [ ] Sim  [ ] Nao
Pontos durante troca:       ___
Observacoes:                _________________________________
```

## Classificacao iOS

```
PASSOU:
   - Novos pontos > 0 em background
   - Gap maximo < 30s
   - App nao suspensa

PARCIAL (aceitavel para MVP):
   - Novos pontos > 0 mas gaps 30-60s
   - Ou iOS pausou mas retomou ao reabrir
   - Ou frequencia reduzida mas continua

FALHOU:
   - Zero novos pontos em background
   - Ou app completamente suspensa sem retomada
```

---

# COMPARACAO: Android vs iOS Background

| Aspecto | Android | iOS |
|---|---|---|
| Mecanismo | Foreground Service + Notification | UIBackgroundModes: location |
| Garantia de continuidade | Alta (notification = process alive) | Media (iOS pode throttle) |
| Notificacao obrigatoria | Sim (foreground service) | Nao (opcional) |
| Kill por sistema | Raro com foreground service | Possivel apos inatividade prolongada |
| Frequencia GPS em background | Igual ao foreground | Pode ser reduzida pelo iOS |
| Config necessaria | Manifest + ForegroundTaskConfig | Info.plist UIBackgroundModes |
| Sprint de teste | 2.17 | 2.18 |

---

# Dependencias para executar ambos os testes

| Componente | Status | Descricao |
|---|---|---|
| ForegroundTaskConfig.init() em main.dart | PENDENTE | Deve ser chamado no startup |
| ForegroundTaskConfig.start() no TrackingBloc | PENDENTE | Deve iniciar no StartTracking |
| ForegroundTaskConfig.stop() no TrackingBloc | PENDENTE | Deve parar no StopTracking |
| Device Android fisico | PENDENTE | Humano executa teste Android |
| Device iOS fisico | PENDENTE | Humano executa teste iOS |

> **Nota:** Todos os demais componentes (permissoes, GPS stream, BLoC, UI)
> ja estao implementados e funcionais desde Sprints 2.5-2.14.
