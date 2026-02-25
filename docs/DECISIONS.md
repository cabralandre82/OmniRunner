# DECISIONS.md — Registro de Decisoes Tecnicas

> **Sprint:** 1.2
> **Status:** Ativo
> **Regra:** Toda mudanca de stack deve ser registrada aqui com data e justificativa.

---

## DECISAO 001 — Stack Inicial

**Data:** 2025-01-10 (Sprint 0.2)
**Status:** CONGELADA

| Escolha | Tecnologia | Justificativa |
|---|---|---|
| Framework | Flutter 3.22+ | Codebase unica Android + iOS, controle total de rendering |
| Arquitetura | Clean Architecture | Dominio isolado, testabilidade maxima, troca de datasource sem impacto |
| State Management | BLoC 8.x | Separacao explicita eventos/estados, streams nativos Dart |
| DI / Service Locator | get_it | Unico singleton permitido, injecao explicita via construtor |
| Persistencia | Isar 3.x | NoSQL otimizado para Flutter, escrita sequencial de GPS, offline-first |
| Modelos | Protobuf 3.x | Serializacao binaria compacta, tipagem forte, versionamento de schema |
| Mapas | MapLibre 0.19+ | Open source, sem vendor lock, custom tiles |
| Backend/Sync | Supabase 2.x | PostgreSQL gerenciado, RLS, auth minimo, sync manual |
| GPS | Geolocator 11.x | Acesso GPS multiplataforma |
| Error Handling | fpdart 1.x | Either/Option para tratamento funcional de erros |
| Equality | Equatable 2.x | Value equality para BLoC states e entities |

### Tecnologias rejeitadas

| Rejeitada | Motivo |
|---|---|
| Provider / Riverpod | BLoC ja escolhido, sem segundo state manager |
| Hive / SQLite | Isar ja escolhido, sem segundo banco |
| Google Maps SDK | Vendor lock + custo |
| Firebase | Supabase ja escolhido, sem segundo backend |
| JSON manual | Protobuf ja escolhido |
| GetX | Incompativel com Clean Architecture |
| REST puro | Supabase client abstrai |

---

## DECISAO 002 — Convencoes de Unidades

**Data:** 2026-02-12 (Sprint 1.2)
**Status:** CONGELADA

| Grandeza | Tipo | Unidade Interna | UI |
|---|---|---|---|
| Distancia | double | metros | km |
| Tempo | int64 (persistido) | milissegundos | HH:MM:SS |
| Pace | double | segundos por km | min:sec/km |
| Coordenadas | double | graus decimais (WGS84) | — |

Conversao para unidades de exibicao: APENAS na presentation layer.

---

## DECISAO 003 — Projeto Flutter

**Data:** 2026-02-12 (Sprint 1.1)
**Status:** EXECUTADA

- Comando: `flutter create omni_runner --org com.omnirunner`
- Package name: `com.omnirunner.omni_runner`
- Pasta do projeto: `omni_runner/`
- Flutter instalado: 3.19.0 (upgrade para 3.22+ e tarefa de ambiente)

---

## DECISAO 004 — Background Location Strategy

**Data:** 2026-02-12 (Sprint 2.12)
**Status:** DECIDIDO
**Impacto:** Alto — afeta F1 (GPS tracking), F5 (Ghost Runner), F6 (Anti-cheat)

### Contexto

O app precisa continuar capturando GPS enquanto o usuario corre com a tela desligada
ou outro app aberto. Sem background location confiavel, a feature core e inviavel.

Plataformas afetadas:
- **Android:** Mata processos agressivamente (Doze, App Standby, OEM kill)
- **iOS:** Permite background location via CLLocationManager + UIBackgroundModes

### Alternativas Analisadas

#### Opcao A: flutter_background_geolocation (Transistor Software)

| Aspecto | Avaliacao |
|---|---|
| Confiabilidade | Melhor da categoria, usado em producao por milhares de apps |
| Background Android | Headless task, anti-kill, geofence, motion detection |
| Background iOS | Significante location change + continuous mode |
| Bateria | Motion detection desliga GPS quando parado |
| Custo | $299/ano por app (producao) — Free apenas para debug |
| Licenca | Proprietaria — nao e open source em producao |
| Complexidade | Media — API rica mas muita configuracao |
| Vendor lock | Alto — depende de um unico vendor comercial |

**Veredicto:** Melhor solucao tecnica, mas custo e vendor lock violam o espirito do projeto.

#### Opcao B: background_locator_2

| Aspecto | Avaliacao |
|---|---|
| Confiabilidade | Funciona, mas reportes de inconsistencia |
| Background Android | Foreground service basico, sem anti-kill avancado |
| Background iOS | Depende de significant location change |
| Bateria | Sem motion detection inteligente |
| Custo | Free / open source |
| Licenca | MIT |
| Complexidade | Media — callback-based, isolate Dart |
| Manutencao | Irregular — community maintained |

**Veredicto:** Open source mas qualidade inconsistente. Risco de bugs dificeis de diagnosticar.

#### Opcao C: geolocator + Foreground Service manual (Android) + CLLocationManager (iOS)

| Aspecto | Avaliacao |
|---|---|
| Confiabilidade | geolocator e maduro; foreground service e pattern Android oficial |
| Background Android | Foreground notification mantem processo vivo |
| Background iOS | geolocator ja usa CLLocationManager internamente |
| Bateria | GPS continuo sem motion detection (aceitavel para corrida) |
| Custo | Free / open source |
| Licenca | MIT (geolocator), MIT (flutter_local_notifications) |
| Complexidade | Media-alta — precisa configurar foreground service manualmente no Android |
| Manutencao | geolocator e mantido ativamente (Baseflow) |
| Stack compliance | geolocator ja esta no STACK.md congelado |

**Veredicto:** Usa tecnologia ja aprovada. Foreground service e o pattern oficial Android.

#### Opcao D: geolocator + flutter_foreground_task

| Aspecto | Avaliacao |
|---|---|
| Confiabilidade | Combina geolocator maduro com foreground task maduro |
| Background Android | flutter_foreground_task gerencia foreground service lifecycle |
| Background iOS | Mesmo que opcao C (geolocator nativo) |
| Bateria | Mesmo que C (GPS continuo durante corrida) |
| Custo | Free / open source |
| Licenca | MIT |
| Complexidade | Media-baixa — flutter_foreground_task abstrai o boilerplate Android |
| Manutencao | Ativamente mantido, 500+ likes pub.dev |
| Stack compliance | geolocator ja aprovado; flutter_foreground_task e infra helper |

**Veredicto:** Melhor balanco entre confiabilidade, custo e simplicidade.

### Decisao Final: OPCAO D — geolocator + flutter_foreground_task

### Justificativa

1. geolocator ja esta na stack congelada — nao viola STACK.md
2. flutter_foreground_task e um helper de infraestrutura, nao um substituto de stack
   - Nao substitui nenhuma tecnologia congelada
   - Apenas gerencia o lifecycle do Android Foreground Service
   - Equivalente a um "driver de plataforma", nao um framework
3. Custo zero — ambos sao MIT, open source
4. Sem vendor lock — se flutter_foreground_task morrer, o fallback e implementar
   foreground service manualmente (Opcao C), sem mudanca na arquitetura
5. Bateria e aceitavel — durante corrida, GPS continuo e esperado pelo usuario
   (nao e um app de tracking 24h)
6. iOS nao precisa de nada extra — geolocator + UIBackgroundModes: location
   (ja configurado no Sprint 2.11) e suficiente

### Arquitetura resultante

```
DOMAIN
  ILocationStream.watch()
  -> Stream<LocationPointEntity>

INFRASTRUCTURE
  GeolocatorLocationStream implements ILocationStream
  |
  +-- geolocator (GPS data)
  +-- flutter_foreground_task (Android only)
      +-- Foreground notification
      +-- Keeps process alive
      +-- Manages lifecycle

  Platform behavior:
    Android: foreground service + notification
    iOS: CLLocationManager + background mode
```

### Dependencias a adicionar (proxima Sprint de implementacao)

```
flutter_foreground_task: ^8.0.0  # Android foreground service lifecycle
# geolocator already in pubspec.yaml
```

### Riscos aceitos

| Risco | Mitigacao |
|---|---|
| OEM aggressive kill (Xiaomi, Huawei, Samsung) | Foreground notification e a melhor defesa; documentar "battery optimization" para usuario |
| flutter_foreground_task descontinuado | Fallback: implementar foreground service via platform channel (Opcao C) |
| GPS drena bateria | Aceitavel durante corrida (30min-2h); nao e tracking 24h |

### Alternativas rejeitadas — registro final

| Opcao | Rejeitada por |
|---|---|
| A — flutter_background_geolocation | $299/ano, vendor lock, licenca proprietaria |
| B — background_locator_2 | Manutencao irregular, confiabilidade inconsistente |
| C — geolocator + foreground service manual | Viavel mas mais boilerplate; D e C com menos codigo |

---

## DECISAO 005 — Map Tiles Provider

**Data:** 2026-02-12 (Sprint 5.2)
**Status:** DECIDIDO
**Impacto:** Medio — afeta F4 (visualizacao de mapa), custo operacional

### Contexto

MapLibre GL precisa de uma fonte de tiles vetoriais.
Duas opcoes viaveis: MapTiler (hosted) e Protomaps (self-hosted).
Decisao afeta custo, complexidade de deploy e qualidade visual.

### Alternativas Analisadas

#### Opcao A: MapTiler (hosted, API key)

| Aspecto | Avaliacao |
|---|---|
| Qualidade dos tiles | Excelente — OpenMapTiles, cartografia polida |
| Setup | URL de style + key, zero infra |
| Free tier | 100,000 tile loads/mes (generoso para MVP) |
| Custo pos-free | ~$0.05/1000 loads |
| Offline tiles | Suportado via download de regions |
| Estilo customizavel | Sim, via MapTiler Cloud editor |
| Dependencia | Servico externo (hosted) |
| Latencia | CDN global, <100ms tipico |

**Veredicto:** Setup minimo, free tier generoso, qualidade excelente.

#### Opcao B: Protomaps (self-hosted, PMTiles)

| Aspecto | Avaliacao |
|---|---|
| Qualidade dos tiles | Boa — OpenStreetMap data, menos polida |
| Setup | Requer hosting do arquivo PMTiles (S3/R2) |
| Free tier | Gratuito (self-hosted), custo = storage + bandwidth |
| Custo | ~$5-10/mes para PMTiles no Cloudflare R2 |
| Offline tiles | Nativo (arquivo PMTiles e a fonte) |
| Estilo customizavel | Sim, mas requer style JSON manual |
| Dependencia | Infra propria (self-hosted) |
| Latencia | Depende do hosting |

**Veredicto:** Maximo controle, mas complexidade operacional para MVP.

### Decisao Final: OPCAO A — MapTiler (hosted, API key)

### Justificativa

1. **Zero infra para MVP** — URL + key e tudo que precisa
2. **Free tier de 100K loads/mes** — Suficiente para centenas de usuarios de teste
3. **Setup em 5 minutos** — Criar conta, copiar key, colar URL
4. **Qualidade visual superior** — Tiles otimizados para MapLibre
5. **Offline suportado** — Download de regions para corridas sem internet
6. **Migracao futura facil** — MapLibre aceita qualquer fonte de tiles;
   trocar para Protomaps e mudar uma URL

### Configuracao

```
Provider:    MapTiler
Account:     Free tier (100,000 tile loads/mes)
Style URL:   https://api.maptiler.com/maps/streets-v2/style.json?key={KEY}
Key policy:  Stored in environment variable, NOT hardcoded
Key name:    MAPTILER_API_KEY
```

### Style URLs disponiveis (MapTiler)

| Style | URL | Uso |
|---|---|---|
| Streets v2 | maps/streets-v2/style.json | Default para corrida (contexto urbano) |
| Outdoor v2 | maps/outdoor-v2/style.json | Trail running (topografia) |
| Satellite | maps/satellite/style.json | Visualizacao pos-corrida |
| Dark | maps/streets-v2-dark/style.json | Modo noturno |

**MVP usa apenas Streets v2.** Outros estilos sao pos-MVP.

### Politica de chaves

```
REGRAS:
1. API key NUNCA no codigo fonte
2. API key em variavel de ambiente: MAPTILER_API_KEY
3. Para development: --dart-define=MAPTILER_API_KEY=xxx no build
4. Para production: secret management da plataforma de build
5. Key rotacao: a cada release major ou se comprometida

Implementacao no Flutter:
  - Usar --dart-define=MAPTILER_API_KEY=xxx no build
  - Acessar via String.fromEnvironment('MAPTILER_API_KEY')
  - Fallback: empty string -> mapa nao carrega (fail safe, nao crash)
```

### Limites do free tier

| Metrica | Limite | Uso estimado MVP |
|---|---|---|
| Tile loads/mes | 100,000 | ~500/run x 30 runs = 15,000 |
| Geocoding | 1,000/mes | Nao usado no MVP |
| Static maps | 1,000/mes | Nao usado no MVP |

**Margem: ~85% do free tier nao utilizada.**

### Riscos aceitos

| Risco | Mitigacao |
|---|---|
| MapTiler muda pricing | Protomaps como fallback (mudar 1 URL) |
| API key vazada em repo | .env gitignored + CI secret management |
| Free tier excedido | Alertas de uso; upgrade ou switch to Protomaps |
| MapTiler downtime | Mapa nao carrega; tracking continua (GPS nao depende de tiles) |

### Alternativa rejeitada — registro final

| Opcao | Rejeitada por |
|---|---|
| Protomaps self-hosted | Complexidade de infra prematura para MVP; MapTiler e zero-infra |

---

## DECISAO 006 — Map Tile Cache & Offline Policy

**Data:** 2026-02-12 (Sprint 5.9)
**Status:** DECIDIDO
**Impacto:** Medio — afeta F4 (visualizacao de mapa), UX offline, storage

### Contexto

Corredores frequentemente seguem rotas repetidas. Tiles ja carregados devem ser
reutilizados para reduzir consumo de dados e permitir visualizacao quando offline.
MapLibre GL tem cache integrado que precisa ser configurado.

### Capacidades do MapLibre GL Flutter (maplibre_gl 0.20.0)

| Capacidade | Disponivel | Detalhes |
|---|---|---|
| Cache automatico de tiles | Sim | SQLite cache em disco, automatico |
| Limite de tiles offline | Sim | `setOfflineTileCountLimit(int)` |
| Download de regiao offline | Sim | `downloadOfflineRegion()` com bounds |
| Listar regioes offline | Sim | `getListOfRegions()` |
| Deletar regiao offline | Sim | `deleteOfflineRegion(int id)` |
| Monitorar progresso download | Sim | Callback com `InProgress(percentage)` |
| Cache eviction automatico | Sim | Gerenciado pelo native SDK |
| Funcionar 100% offline | Parcial | Apenas tiles ja em cache ou downloaded |

Nota: `setOfflineTileCountLimit()` controla o numero maximo de tiles
(nao bytes). O tamanho do cache em bytes e gerenciado internamente pelo
native SDK MapLibre (~50 MB default). Nao ha API Flutter para setar
byte size diretamente.

### Politica Definida

#### 1. Cache Automatico (Passivo)

```
Comportamento: ATIVADO por padrao (MapLibre default)
Eviction: Gerenciado pelo native SDK (SQLite, LRU)
Localizacao: App sandbox (gerenciado pelo MapLibre)

O que e cacheado:
  - Tiles vetoriais carregados durante uso normal
  - Style JSON
  - Glyphs (fontes do mapa)
  - Sprites (icones do mapa)

O que NAO e cacheado:
  - Regioes inteiras (requer download explicito)
  - Tiles nunca visualizados
```

#### 2. Download Offline (Ativo) — FORA DO MVP

```
Status: NAO implementar no MVP
Motivo: Complexidade de UX (selecao de regiao, progress bar, gerenciamento)
Futuro: Pos-MVP, permitir download de "rotas favoritas"
```

#### 3. Comportamento Offline

```
Cenario: Corredor inicia run SEM internet

Mapa:
  - Tiles em cache? -> Exibidos normalmente
  - Tiles nao em cache? -> Tiles em branco / placeholder
  - Tracking GPS? -> Funciona (GPS nao precisa de internet)

Comportamento esperado:
  - Polyline da rota e desenhada normalmente (dados locais)
  - Fundo do mapa pode estar parcialmente vazio
  - Metricas (distancia, pace) funcionam 100%
  - Ao recuperar internet, tiles carregam automaticamente

Impacto no usuario:
  - Corrida NAO e prejudicada (GPS + metricas independem de tiles)
  - Visualizacao do mapa pode ser degradada (mas funcional)
  - Pos-corrida com internet: mapa completo aparece
```

#### 4. Limites de Storage

```
Cache de tiles:     ~50 MB (native default, gerenciado automaticamente)
Isar DB (runs):     ~170 MB/ano (estimado Sprint 4.14)
Total app storage:  ~220 MB apos 1 ano de uso pesado

Para contexto:
  - App tipico de corrida: 200-500 MB
  - 220 MB e aceitavel para qualquer smartphone moderno
```

#### 5. Configuracao no Codigo

```
Nenhuma configuracao de cache necessaria para MVP.
O cache automatico do MapLibre native SDK e ativado por padrao.

Opcional (pos-MVP, se necessario limitar tiles para downloads offline):
  setOfflineTileCountLimit(6000);
```

### Decisoes Especificas

| # | Decisao | Valor | Motivo |
|---|---|---|---|
| 1 | Cache automatico | Default do native SDK | Sem overhead; funciona out of the box |
| 2 | Eviction | Gerenciado pelo native SDK | LRU nativo; rotas repetidas ficam em cache |
| 3 | Offline regions download | FORA do MVP | Complexidade de UX desnecessaria para validacao |
| 4 | Cache clearing manual | FORA do MVP | Settings page e pos-MVP |
| 5 | Cache warming | NAO implementar | Tiles cacheados naturalmente pelo uso |
| 6 | Configuracao explicita de cache | NAO no MVP | Defaults do native SDK sao adequados |

### Riscos e Mitigacoes

| Risco | Probabilidade | Mitigacao |
|---|---|---|
| Cache cheio descarta rota frequente | Baixa (LRU mantem recentes) | Ampliar via `setOfflineTileCountLimit` se necessario |
| Corrida em area nunca visitada + sem internet | Media | GPS funciona; mapa em branco nao impede tracking |
| MapTiler rate limit atingido | Baixa (15% do free tier) | Cache reduz requests; Protomaps como fallback |
| Cache corrupto | Muito baixa | MapLibre rebuild automatico; nao afeta dados de corrida |

### Alternativa Futura (Pos-MVP)

```
Feature: "Save Route for Offline"
  - Usuario seleciona rota no mapa
  - App calcula bounding box + buffer de 500m
  - Download via downloadOfflineRegion()
  - Progress bar com estimativa
  - Gerenciamento: listar, deletar regioes salvas
  - Estimativa: ~5-20 MB por rota (zoom 12-16)

Quando implementar: quando feedback de usuarios indicar necessidade
```

---

## DECISAO 007 — Protobuf Removido da Stack (Modelos Locais)

**Data:** 2026-02-12 (Auditoria pos-Phase 06)
**Status:** DECIDIDO
**Impacto:** Baixo — afeta apenas formato de serializacao local

### Contexto

A DECISAO 001 declarou Protobuf 3.x como stack para modelos. Na pratica, os modelos
de persistencia local usam anotacoes Isar nativas (`@collection`, `@Index`), pois:
- Isar gera codigo de serializacao automaticamente via `isar_generator`
- Uma camada Protobuf entre Isar e o dominio adicionaria complexidade sem beneficio
- Protobuf e mais util para wire format (rede), nao para DB local

### Decisao

- **Modelos locais (Isar):** Anotacoes Isar nativas. Protobuf NAO usado.
- **Wire format (sync com Supabase):** Protobuf permanece como opcao para fases
  futuras de sincronizacao (Phase 08+). Decisao adiada ate implementacao de sync.

### Justificativa

1. Isar `@collection` ja gera serializacao binaria otimizada
2. Adicionar Protobuf como camada intermediaria violaria KISS
3. Protobuf continua disponivel para sync wire format quando necessario
4. Zero impacto na Clean Architecture (modelos Isar ficam em `data/models/`)

### Impacto na DECISAO 001

A linha `Modelos | Protobuf 3.x` da DECISAO 001 fica com escopo reduzido:
- **Antes:** Protobuf para todos os modelos
- **Agora:** Protobuf reservado para wire format de sync (futuro)
- Isar annotations para modelos de persistencia local

---

---

## DECISAO 008 — Audio Ducking Strategy (TTS + Music)

**Data:** 2026-02-12 (Sprint 8.4)
**Status:** DECIDIDO
**Impacto:** Medio — afeta UX de audio coaching quando usuario ouve musica durante corrida

### Contexto

O audio coach (TTS) fala anuncios de distancia, pace e eventos durante a corrida.
A maioria dos corredores ouve musica simultaneamente. Sem ducking, o TTS ou:
- Pausa a musica completamente (Android default), ou
- Sobrepoe a musica no mesmo volume (ininteligivel).

Ducking = abaixar volume da musica temporariamente enquanto TTS fala, restaurar depois.

### Analise por Plataforma

#### iOS — Ducking via flutter_tts (TRIVIAL)

`flutter_tts` ja expoe `setIosAudioCategory()` com opcoes nativas:

```dart
await tts.setSharedInstance(true);
await tts.setIosAudioCategory(
  IosTextToSpeechAudioCategory.playback,
  [
    IosTextToSpeechAudioCategoryOptions.duckOthers,
    IosTextToSpeechAudioCategoryOptions.mixWithOthers,
  ],
  IosTextToSpeechAudioMode.voicePrompt,
);
```

| Aspecto | Avaliacao |
|---|---|
| Esforco | Trivial — 2 chamadas no `init()` do `AudioCoachService` |
| Risco | Nenhum — API nativa AVAudioSession, estavel desde iOS 6 |
| Codigo nativo | Nenhum — flutter_tts abstrai completamente |
| Comportamento | Musica abaixa ~40%, TTS fala, musica volta ao volume normal |
| Tela bloqueada | Funciona — `playback` category mantem audio ativo |

**Veredicto iOS:** Implementar AGORA. Zero risco, 2 linhas de codigo.

#### Android — Ducking via AudioFocus (COMPLEXO)

`flutter_tts` no Android usa `TextToSpeech` nativo que internamente faz
`requestAudioFocus(AUDIOFOCUS_GAIN)`, o que **pausa** outras apps de audio.
Para ducking, seria necessario `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`.

| Opcao | Esforco | Risco | Detalhes |
|---|---|---|---|
| A: Method channel nativo | Medio-alto | OEM fragmentation | ~100 linhas Kotlin + ~50 linhas Dart. Precisa: `requestAudioFocus()` antes do speak, `abandonAudioFocus()` apos. Testavel apenas em device fisico. |
| B: Package `audio_session` | Medio | Conflito com flutter_tts | Gerencia audio focus cross-platform, mas flutter_tts ja gerencia internamente. Potencial conflito de sessao. |
| C: Aceitar comportamento default | Zero | Nenhum | Musica pausa durante TTS. Funcional mas UX inferior. |
| D: Adiar para sprint futura | Zero agora | Tech debt | Implementar method channel quando houver tempo de teste em devices reais. |

**Riscos do method channel Android:**
- Samsung, Xiaomi, Huawei tratam audio focus de forma diferente
- `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` pode ser ignorado por media players de terceiros
- Requer teste manual em 3-5 dispositivos reais
- flutter_tts pode conflitar se ambos gerenciam audio focus simultaneamente

### Decisao Final

| Plataforma | Acao | Sprint |
|---|---|---|
| iOS | Implementar ducking AGORA | 8.4 (proximo passo apos decisao) |
| Android | ADIAR method channel | Futuro (pos-MVP, Phase 10+) |
| Android (interim) | Aceitar pause de musica durante TTS | MVP |

### Justificativa

1. **iOS ducking e gratis** — `flutter_tts` ja expoe a API. 2 linhas no `init()`.
   Nao implementar seria desperdicar funcionalidade ja disponivel.
2. **Android ducking requer native code** — method channel com AudioManager.
   Complexidade incompativel com timeline do MVP.
3. **Android behavior default e aceitavel** — musica pausa brevemente (~2-3s por
   anuncio). Nao e ideal mas nao quebra UX.
4. **Consistencia parcial > inconsistencia total** — melhor ter ducking no iOS
   do que nao ter em nenhuma plataforma esperando solucao perfeita cross-platform.
5. **audio_session rejeitado** — risco de conflito com flutter_tts supera beneficio.
   Ambos tentam gerenciar audio session; comportamento imprevisivel.

### Plano de Implementacao — iOS (Sprint atual)

```
Arquivo: lib/data/datasources/audio_coach_service.dart
Metodo: init()
Adicionar (apos setVolume, antes de awaitSpeakCompletion):

  import 'dart:io' show Platform;

  if (Platform.isIOS) {
    await tts.setSharedInstance(true);
    await tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
      IosTextToSpeechAudioMode.voicePrompt,
    );
  }

Resultado:
  - iOS: musica abaixa, TTS fala, musica volta
  - Android: sem mudanca (default: musica pausa)
```

### Plano de Implementacao — Android (Futuro, pos-MVP)

```
Quando: Phase 10+ ou quando feedback de usuarios indicar necessidade
Como:
  1. Criar AudioFocusHelper (Kotlin) em android/app/src/main/kotlin/
  2. Method channel: 'com.omnirunner/audio_focus'
     - requestDuck() -> AudioManager.requestAudioFocus(GAIN_TRANSIENT_MAY_DUCK)
     - abandonFocus() -> AudioManager.abandonAudioFocusRequest()
  3. Chamar requestDuck() antes de speak(), abandonFocus() no completion handler
  4. Testar em: Samsung (One UI), Xiaomi (MIUI), Pixel (stock), Huawei (EMUI)
  5. Fallback: se requestAudioFocus falhar, continuar sem ducking (nao crashar)

Estimativa: 1-2 sprints (implementacao + teste em devices)
```

### Alternativa Rejeitada

| Opcao | Rejeitada por |
|---|---|
| `audio_session` package | Conflito potencial com flutter_tts que ja gerencia audio session internamente |
| Implementar Android ducking agora | Requer native Kotlin + teste em multiplos OEMs; complexidade incompativel com MVP |
| Nao implementar ducking em nenhuma plataforma | iOS ducking e trivial; desperdicaria funcionalidade gratuita |

---

## DECISAO 009 — Persistência de configurações do Audio Coach

**Data**: 2026-02-12
**Sprint**: 8.9
**Autor**: IA (Cursor)

### Contexto

O audio coach possui 3 categorias de mensagens de voz (km, ghost, periódico).
O usuário precisa ativar/desativar cada categoria. É necessário persistir essas
preferências entre sessões.

### Decisão

Usar **SharedPreferences** para persistir as 3 flags booleanas.

### Justificativa

- 3 booleans é um caso trivial de key-value; Isar é overkill para isso.
- `shared_preferences` já era dependência transitiva (via `path_provider`),
  custo marginal de promover a dependência direta é zero.
- Alinha com o padrão de Clean Architecture: interface `ICoachSettingsRepo`
  no domain, implementação `CoachSettingsRepo` no data layer.
- Sem necessidade de migrations, schemas, ou build_runner.

### Alternativas rejeitadas

| Opcao | Rejeitada por |
|---|---|
| Isar para settings | Overkill; requer schema, build_runner, migration para 3 bools |
| Arquivo JSON manual | Mais complexo que SharedPreferences sem benefício |
| Hive | Dependência extra desnecessária |

---

## DECISAO 010 — Backend Sync: Supabase (Auth + Postgres + Storage)

**Data:** 2026-02-12 (Sprint 9.1)
**Status:** DECIDIDO
**Impacto:** Alto — define infraestrutura de sync, auth e persistencia remota para MVP

### Contexto

O app opera offline-first com Isar local. Para rankings futuros, backup e
multi-device, e necessario sincronizar sessoes com um backend. A DECISAO 001
ja congelou Supabase 2.x como backend. Esta decisao detalha o schema, a
estrategia de armazenamento e o modelo de autenticacao.

### Componentes Supabase utilizados

| Componente | Uso no MVP |
|---|---|
| **Auth** | Autenticacao minima (email/password). Anonymous auth como fallback. |
| **Postgres** | Tabela `sessions` para metadados queryable (rankings, historico) |
| **Storage** | Bucket `session-points` para payload de pontos GPS (JSON comprimido) |
| **RLS** | Row Level Security em `sessions` e policies no bucket |

### 1. Autenticacao (Auth)

```
Estrategia MVP:
  - Supabase Auth com email/password (sign up + sign in)
  - Anonymous auth como alternativa inicial (usuario pode migrar depois)
  - Token JWT gerenciado pelo supabase_flutter SDK
  - user_id do Supabase Auth = FK em sessions e path prefix no Storage

Fluxo:
  1. App inicia -> verifica sessao Supabase existente
  2. Se nao logado -> tela de login/signup ou anonymous
  3. Token JWT armazenado pelo SDK (refresh automatico)
  4. Sync so ocorre quando autenticado

Pos-MVP:
  - OAuth (Google, Apple) para sign in rapido
  - Migracao de anonymous -> conta real
```

### 2. Tabela Postgres: `sessions`

Espelha os metadados do `WorkoutSessionRecord` local (Isar).
Pontos GPS ficam no Storage (nao no Postgres).

```sql
CREATE TABLE public.sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status        SMALLINT NOT NULL DEFAULT 0,
  start_time_ms BIGINT NOT NULL,
  end_time_ms   BIGINT,
  total_distance_m DOUBLE PRECISION NOT NULL DEFAULT 0.0,
  moving_ms     BIGINT NOT NULL DEFAULT 0,
  is_verified   BOOLEAN NOT NULL DEFAULT TRUE,
  integrity_flags TEXT[] NOT NULL DEFAULT '{}',
  ghost_session_id UUID,
  points_path   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indices
CREATE INDEX idx_sessions_user_id ON public.sessions(user_id);
CREATE INDEX idx_sessions_start_time ON public.sessions(start_time_ms DESC);
CREATE INDEX idx_sessions_verified ON public.sessions(is_verified);

-- RLS
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own sessions"
  ON public.sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users insert own sessions"
  ON public.sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own sessions"
  ON public.sessions FOR UPDATE
  USING (auth.uid() = user_id);
```

#### Mapeamento de campos Isar -> Postgres

| WorkoutSessionRecord (Isar) | sessions (Postgres) | Notas |
|---|---|---|
| sessionUuid | id | UUID, PK no Postgres |
| userId | user_id | FK para auth.users |
| status | status | SMALLINT (mesmo ordinal) |
| startTimeMs | start_time_ms | BIGINT |
| endTimeMs | end_time_ms | BIGINT nullable |
| totalDistanceM | total_distance_m | DOUBLE PRECISION |
| movingMs | moving_ms | BIGINT |
| isVerified | is_verified | BOOLEAN |
| integrityFlags | integrity_flags | TEXT[] (Postgres array) |
| ghostSessionId | ghost_session_id | UUID nullable |
| isSynced | — | Apenas local; controla se ja fez upload |
| — | points_path | Path do arquivo de pontos no Storage |
| — | created_at | Server timestamp |
| — | updated_at | Server timestamp |

### 3. Storage: Bucket `session-points`

Os pontos GPS sao armazenados como arquivo JSON no Supabase Storage,
nao como linhas no Postgres. Motivo: uma sessao de 30min gera ~1800 pontos
(~180 KB JSON, ~40 KB gzip). Inserir 1800 rows por sessao seria ineficiente
e caro em queries.

```
Bucket: session-points
Acesso: Private (RLS via policy)
Path pattern: {user_id}/{session_uuid}.json

Conteudo do arquivo (JSON array):
[
  {
    "lat": -23.550520,
    "lng": -46.633308,
    "alt": 760.0,
    "accuracy": 5.2,
    "speed": 3.1,
    "bearing": 180.0,
    "timestampMs": 1707753600000
  },
  ...
]

Tamanho estimado por sessao:
  - 30 min run (~1800 pontos): ~180 KB JSON
  - 60 min run (~3600 pontos): ~360 KB JSON
  - Com gzip: ~40-80 KB (compressao ~4-5x)

Policy do bucket:
  - SELECT: auth.uid()::text = (storage.foldername(name))[1]
  - INSERT: auth.uid()::text = (storage.foldername(name))[1]
  - Usuarios so acessam seus proprios arquivos
```

### 4. Fluxo de Sync (MVP — Manual)

```
Upload (app -> Supabase):
  1. Usuario clica "Sync" ou sync automatico ao abrir com internet
  2. Buscar sessoes locais com isSynced = false e status = completed
  3. Para cada sessao nao sincronizada:
     a. Upload pontos GPS como JSON para Storage
        Path: {user_id}/{session_uuid}.json
     b. INSERT/UPSERT metadados na tabela sessions
        (com points_path apontando para o arquivo)
     c. Marcar isSynced = true no Isar local
  4. Se falhar: manter isSynced = false, tentar novamente depois

Download (Supabase -> app):
  - Pos-MVP. Para multi-device, baixar sessoes do servidor
    que nao existem localmente.
  - Query: SELECT * FROM sessions WHERE user_id = auth.uid()
    AND id NOT IN (ids locais)
  - Download pontos do Storage e inserir no Isar

Conflito:
  - MVP nao trata conflito (single device assumed)
  - Pos-MVP: last-write-wins ou merge manual
```

### 5. Estimativa de Custo (Supabase Free Tier)

| Recurso | Limite Free | Uso estimado MVP (100 usuarios) |
|---|---|---|
| Database | 500 MB | ~5 MB (100 users x 50 sessions x 1 KB) |
| Storage | 1 GB | ~200 MB (100 users x 50 sessions x 40 KB) |
| Auth | 50,000 MAU | 100 MAU |
| Bandwidth | 5 GB/mes | ~500 MB/mes |
| Edge Functions | 500K invocacoes | Nao usado no MVP |

**Margem confortavel: <10% do free tier para MVP.**

### 6. Dependencia Flutter

```yaml
supabase_flutter: ^2.0.0   # SDK Supabase (auth + storage + postgres)
```

A ser adicionada na sprint de implementacao (nao nesta sprint de decisao).

### 7. Arquitetura resultante

```
DOMAIN
  ISyncRepo (interface)
    uploadSession(sessionId) -> Future<Either<Failure, void>>
    getRemoteSessions() -> Future<Either<Failure, List<SessionEntity>>>

DATA
  SupabaseSyncRepo implements ISyncRepo
  |
  +-- SupabaseClient (auth + database + storage)
  |   +-- .from('sessions').insert/upsert/select
  |   +-- .storage.from('session-points').upload/download
  |
  +-- ISessionRepo (local Isar, para marcar isSynced)
  +-- IPointsRepo (local Isar, para ler pontos)

PRESENTATION
  SyncBloc / SyncButton
  |
  +-- Chama ISyncRepo.uploadSession()
  +-- Mostra progresso/erro
```

### 8. Decisoes Especificas

| # | Decisao | Valor | Motivo |
|---|---|---|---|
| 1 | Backend | Supabase 2.x | Congelado na DECISAO 001 |
| 2 | Auth MVP | Email/password + anonymous | Minimo viavel sem OAuth |
| 3 | Metadados | Tabela Postgres `sessions` | Queryable para rankings |
| 4 | Pontos GPS | Storage bucket JSON | Eficiente; evita 1800 rows/sessao |
| 5 | Formato pontos | JSON (nao Protobuf) | Simplicidade; Protobuf adiado (DECISAO 007) |
| 6 | Sync trigger | Manual (usuario inicia) | MVP; auto-sync e pos-MVP |
| 7 | Conflito | Nao tratado | Single device assumed no MVP |
| 8 | RLS | Ativado | Seguranca basica desde o dia 1 |
| 9 | Wire format | JSON (REST via supabase_flutter) | SDK abstrai; sem necessidade de custom API |

### 9. Riscos aceitos

| Risco | Probabilidade | Mitigacao |
|---|---|---|
| Supabase free tier excedido | Baixa (MVP) | Monitorar dashboard; upgrade e $25/mes |
| Supabase downtime | Baixa | App funciona offline; sync retry |
| JSON de pontos grande (ultra maratona) | Media | Gzip futuro; ou chunking |
| Dados perdidos se usuario desinstala sem sync | Media | Prompt de sync antes de uninstall (futuro) |
| RLS misconfigured | Baixa | Testar policies com SQL antes de deploy |

### 10. Alternativas rejeitadas

| Opcao | Rejeitada por |
|---|---|
| Firebase (Firestore + Cloud Storage) | Supabase ja congelado na DECISAO 001; vendor lock Google |
| Custom REST API (Node/Python) | Complexidade de infra; Supabase e zero-backend |
| Pontos GPS no Postgres (rows) | 1800 rows/sessao e ineficiente; Storage e mais adequado |
| Protobuf wire format | Complexidade desnecessaria para MVP (DECISAO 007) |
| Sync automatico | Complexidade de background sync; manual e suficiente para MVP |
| Appwrite | Menos maduro que Supabase; comunidade menor |

---

## DECISAO 011 — Observabilidade: Sentry (Crash Reporting + Performance)

**Data:** 2026-02-12 (Sprint 10.2)
**Status:** DECIDIDO
**Impacto:** Medio — afeta observabilidade em producao, diagnóstico de crashes

### Contexto

App em producao precisa de crash reporting para diagnosticar problemas em
devices reais. Sem observabilidade, bugs em campo sao invisiveis ate que
usuarios reclamem (se reclamarem).

### Alternativas Analisadas

#### Opcao A: Firebase Crashlytics

| Aspecto | Avaliacao |
|---|---|
| Custo | Gratuito, ilimitado |
| Qualidade | Excelente — stack traces simbolizados, agrupamento inteligente |
| Setup | Medio — requer google-services.json (Android) + GoogleService-Info.plist (iOS) |
| Flutter support | Oficial (`firebase_crashlytics`) |
| Vendor lock | Alto — Google ecosystem |
| Conflito com stack | **SIM** — DECISAO 001 rejeitou Firebase ("Supabase ja escolhido, sem segundo backend") |
| Dados enviados | Crashes + device info para servidores Google |

**Veredicto:** Rejeitado. Introduzir Firebase viola DECISAO 001 e adiciona
um segundo vendor de backend. Mesmo sendo "apenas crashlytics", o SDK Firebase
Core e obrigatorio e puxa dependencias pesadas.

#### Opcao B: Sentry

| Aspecto | Avaliacao |
|---|---|
| Custo | Free tier: 5.000 erros/mes, 10.000 transacoes de performance |
| Qualidade | Excelente — stack traces, breadcrumbs, release tracking, source maps |
| Setup | Simples — unico DSN string via dart-define |
| Flutter support | Oficial (`sentry_flutter`), bem mantido |
| Vendor lock | Baixo — open source, pode self-host |
| Conflito com stack | Nenhum — backend-agnostic, nao conflita com Supabase |
| Dados enviados | Crashes + device metadata para Sentry cloud (ou self-hosted) |
| Performance monitoring | Incluido no free tier |
| Release health | Incluido — taxa de crash por versao |

**Veredicto:** Alinha com a filosofia do projeto (anti-vendor-lock, open source
quando possivel). Free tier generoso para MVP.

#### Opcao C: Sem observabilidade

| Aspecto | Avaliacao |
|---|---|
| Custo | Zero |
| Risco | **Alto** — crashes em campo sao invisiveis |

**Veredicto:** Inaceitavel para producao.

#### Opcao D: Bugsnag / Datadog

| Aspecto | Avaliacao |
|---|---|
| Custo | Pago (Bugsnag free tier limitado; Datadog caro) |
| Flutter support | Menor comunidade que Sentry |

**Veredicto:** Sem vantagem sobre Sentry para o caso de uso.

### Decisao Final: OPCAO B — Sentry

### Justificativa

1. **Firebase rejeitado na DECISAO 001** — introduzir Crashlytics violaria
   a decisao congelada e adicionaria um segundo vendor de backend
2. **Vendor-neutral** — Sentry nao conflita com Supabase nem com nenhuma
   tecnologia da stack
3. **Open source** — pode self-host se Sentry cloud se tornar caro ou
   se houver requisitos de soberania de dados
4. **Free tier generoso** — 5K erros/mes cobre MVP com folga
   (100 usuarios x ~0.5 crashes/usuario/mes = 50 crashes)
5. **Setup minimo** — unico DSN via `--dart-define=SENTRY_DSN=https://...`
6. **Performance monitoring incluso** — bônus sem custo adicional

### Configuracao planejada

```
Dependencia: sentry_flutter (latest)
Config: SENTRY_DSN via --dart-define (mesmo padrão de Supabase/MapTiler)
Inicializacao: SentryFlutter.init() no main.dart, antes de runApp()
Ambiente: --dart-define=SENTRY_ENVIRONMENT=production|staging
Release: automatico via pubspec.yaml version

Dados capturados:
  - Crashes (unhandled exceptions)
  - Handled errors (opcional, via Sentry.captureException)
  - Breadcrumbs (navegacao, HTTP, lifecycle)
  - Device info (OS, model, RAM — NÃO GPS, NÃO PII)
  - App version, build number

Dados NÃO capturados:
  - GPS coordinates (excluidos via beforeSend scrubbing)
  - Email do usuario
  - Dados de sessao de corrida
  - Qualquer PII
```

### Politica de privacidade

```
Sentry recebe APENAS:
  - Stack traces de crashes
  - Device metadata (OS version, model, free memory)
  - App version e build number
  - Breadcrumbs de navegacao (nomes de tela, NÃO coordenadas)

Sentry NÃO recebe:
  - Coordenadas GPS
  - Dados de corrida (distancia, pace, pontos)
  - Email ou identidade do usuario
  - Qualquer dado do Isar ou Supabase

Implementar beforeSend callback para scrub qualquer PII acidental.
```

### Estimativa de custo

| Metrica | Limite Free | Uso estimado MVP |
|---|---|---|
| Erros/mes | 5.000 | ~50 (100 users x 0.5 crash rate) |
| Transacoes perf/mes | 10.000 | ~3.000 (100 users x 30 sessions) |
| Retencao | 30 dias | Suficiente para debug |

**Margem: <5% do free tier.**

### Riscos aceitos

| Risco | Mitigacao |
|---|---|
| Sentry cloud downtime | Crashes nao sao reportados; app funciona normalmente |
| Free tier excedido | Alertas de uso; upgrade e $26/mes (Team) |
| LGPD/GDPR compliance | Sentry e compliant; nao enviamos PII |
| DSN exposto no APK | DSN e publico por design (write-only); rate limiting no Sentry dashboard |

### Alternativa rejeitada — registro final

| Opcao | Rejeitada por |
|---|---|
| Firebase Crashlytics | Viola DECISAO 001 (Firebase rejeitado); segundo vendor de backend |
| Bugsnag | Free tier inferior; menor comunidade Flutter |
| Datadog | Custo alto; overkill para MVP |
| Sem observabilidade | Risco inaceitavel para producao |

---

## DECISAO 012 — Background BLE iOS: `bluetooth-central` Obrigatório

**Data:** 2026-02-17 (Sprint W6.2)
**Status:** DECIDIDO
**Impacto:** Alto — afeta recepção de HR BLE com tela desligada/app minimizado no iOS

### Contexto

O Omni Runner conecta-se a monitores cardíacos BLE (Polar H10, Garmin HRM-Pro,
Wahoo TICKR) durante corridas. O corredor tipicamente:
1. Inicia a corrida no app
2. Coloca o phone no bolso/braçadeira
3. Tela desliga por inatividade ou o corredor abre outro app (Spotify, podcast)
4. Corre por 30-120 minutos

Neste cenário, o app está em **background** durante toda a corrida.
Sem `bluetooth-central` no `UIBackgroundModes`, o iOS **suspende** o processo
após ~10 segundos em background, matando todas as conexões BLE.

### Análise Técnica

#### Sem `bluetooth-central`:

```
App vai para background
  → iOS suspende o processo em ~10s
    → Core Bluetooth dealocado
      → Conexão BLE perdida
        → Sem notificações HR
          → sensorContact, bpm, rrIntervals — tudo perdido
            → UI mostra "BPM: --" quando usuário retorna
```

**Resultado:** HR funciona APENAS com tela ligada e app em foreground.
Inútil para caso de uso real de corrida.

#### Com `bluetooth-central`:

```
App vai para background
  → iOS mantém Core Bluetooth ativo
    → Conexão BLE preservada
      → Notificações HR continuam chegando
        → Callbacks executados em background
          → Dados de HR acumulados
            → UI mostra histórico completo quando usuário retorna
```

**Resultado:** HR funciona durante toda a corrida, independente do estado do app.

### O que `bluetooth-central` habilita no iOS

| Capacidade | Sem bluetooth-central | Com bluetooth-central |
|-----------|----------------------|---------------------|
| Manter conexão BLE existente | ❌ Perdida após ~10s | ✅ Mantida indefinidamente |
| Receber notificações BLE (HR) | ❌ Não recebe | ✅ Recebe normalmente |
| Scan por novos dispositivos | ❌ Impossível | ⚠️ Limitado (sem duplicatas, UUIDs explícitos) |
| Reconnect após desconexão | ❌ Impossível | ✅ Possível via `connectPeripheral` |
| Callbacks de discovery/connection | ❌ Nunca chamados | ✅ Chamados (com possível atraso de ~10s) |
| State Preservation & Restoration | ❌ Não disponível | ✅ Disponível (não implementado ainda) |

### Restrições do `bluetooth-central` em Background

Mesmo com o background mode habilitado, o iOS impõe restrições:

1. **Scan limitado:** `CBCentralManagerScanOptionAllowDuplicatesKey` é ignorado;
   cada dispositivo é reportado apenas uma vez por scan
2. **UUIDs obrigatórios:** Scan em background requer `serviceUUIDs` explícitos
   (nosso scan já filtra por `0x180D` — ✅ conforme)
3. **Callbacks atrasados:** Podem ter latência de até ~10s vs ~instant em foreground
4. **Não impede suspensão total:** Se iOS estiver sob pressão extrema de memória,
   o app pode ser terminado (raro com background modes ativos)

### Avaliação: Podemos remover `bluetooth-central`?

**NÃO.** Remover `bluetooth-central` equivale a desabilitar HR BLE para 100%
dos casos de uso reais (corrida com tela desligada).

| Cenário | Sem bluetooth-central | Com bluetooth-central |
|---------|----------------------|---------------------|
| Corrida outdoor (30 min, tela off) | ❌ 0% HR data | ✅ 100% HR data |
| Corrida indoor (tela off, Spotify) | ❌ 0% HR data | ✅ 100% HR data |
| Teste rápido (tela on, app visível) | ✅ HR funciona | ✅ HR funciona |
| App Review (Apple) | ✅ Sem escrutínio | ⚠️ Deve justificar no App Store Connect |

### Justificativa para App Review da Apple

Ao submeter para a App Store, a Apple revisará o uso de `bluetooth-central`.
A justificativa é direta e legítima:

> "Omni Runner is a running app that connects to external BLE heart rate
> monitors (Polar, Garmin, Wahoo) to track heart rate during outdoor runs.
> The user starts a run, puts the phone in their pocket, and runs for
> 30-120 minutes with the screen off. Without bluetooth-central background
> mode, the BLE connection would be lost within 10 seconds, making heart
> rate monitoring impossible during actual workouts. The app only maintains
> an existing connection to a heart rate monitor — it does not perform
> background scanning or connect to new devices without user action."

**Risco de rejeição:** Baixo. Apps de fitness com BLE HR são um caso de uso
canonical para `bluetooth-central`. Strava, Nike Run Club, Polar Flow, Wahoo
Fitness — todos usam este background mode pelo mesmo motivo.

### Interação com `location` Background Mode

O app já declara `location` em `UIBackgroundModes` para GPS contínuo durante
corridas. A combinação `location` + `bluetooth-central` é reforçante:

- `location` mantém o processo ativo para GPS
- `bluetooth-central` mantém o Core Bluetooth ativo para HR
- **Juntos:** Fornecem a garantia mais forte de que o app permanece ativo
  durante toda a corrida

Sem `bluetooth-central`, mesmo com `location` ativo, o iOS pode deallocar
o Core Bluetooth Central Manager por considerar que BLE não é mais necessário.

### Decisão Final

**MANTER `bluetooth-central` no `UIBackgroundModes`.** É obrigatório para a
feature core de HR BLE.

### Checklist de Conformidade

- [x] `bluetooth-central` declarado em `Info.plist` (`UIBackgroundModes`)
- [x] `NSBluetoothAlwaysUsageDescription` com texto descritivo
- [x] `NSBluetoothPeripheralUsageDescription` (legacy, iOS < 13)
- [x] Scan filtra por UUID `0x180D` (conforme requisito de background scan)
- [x] BLE usado para manter conexão existente, não para scan passivo contínuo
- [ ] Justificativa preparada para App Store Connect (texto acima)
- [ ] `CBCentralManagerOptionRestoreIdentifierKey` (State Restoration) — futuro P2

### Alternativas Rejeitadas

| Opção | Rejeitada por |
|-------|--------------|
| Remover `bluetooth-central` | Mata 100% do HR BLE em uso real (tela off) |
| Usar apenas HealthKit para HR | HealthKit HR do Apple Watch tem latência de ~5-60s; não serve para alerta de zona em tempo real |
| Polling HR via timer | iOS não permite timers em background sem background mode |
| Significant location change como keep-alive | Não mantém Core Bluetooth ativo; hack frágil |

---

## DECISAO 013 — Integrações Externas: Strava + Export FIT/GPX/TCX

**Data:** 2026-02-17 (Sprint 14.0.1)
**Status:** DECIDIDO
**Impacto:** Alto — define escopo, formatos e estratégia de integração com plataformas externas

### Contexto

Corredores esperam compartilhar treinos automaticamente com Strava e exportar
para plataformas como Garmin Connect, Coros, TrainingPeaks. O app já exporta
para HealthKit (iOS) e Health Connect (Android), mas esses não cobrem Strava
nem permitem importação manual em plataformas de terceiros.

### Decisões

| # | Decisão | Valor | Motivo |
|---|---------|-------|--------|
| 1 | Upload para Strava | OAuth2 + API v3 `/uploads` | Única API oficial disponível; padrão de mercado |
| 2 | Formato preferido Strava | FIT (fallback: GPX) | FIT preserva mais dados (HR, pace, device info); GPX é universal |
| 3 | Formatos de exportação local | GPX 1.1, TCX, FIT | Cobre 100% das plataformas existentes |
| 4 | Armazenamento de tokens | `flutter_secure_storage` | Keychain (iOS) + EncryptedSharedPreferences (Android); NUNCA em plain text |
| 5 | Queue offline | Isar (`PendingUpload`) | Consistente com stack existente; sobrevive kill do app |
| 6 | Auto-upload Strava | Opt-in (desabilitado por default) | Respeita privacidade; usuário escolhe |
| 7 | Retry strategy | Exponential backoff (1s→60s, max 5 tentativas) | Padrão da indústria; evita rate limiting |
| 8 | Garmin Connect API | EXCLUÍDO | Sem API pública de upload; usuário importa via arquivo FIT |
| 9 | Share sheet | `share_plus` (nativa) | Zero overhead; usa APIs do OS |
| 10 | Failure handling | Sealed class `IntegrationFailure` | Consistente com `HealthFailure`, `BleFailure`, `SyncFailure` |

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Garmin Connect IQ app | Requer SDK Garmin separado, device-specific |
| Upload direto Garmin Connect | Sem API pública para upload de atividades |
| Apenas GPX (sem FIT/TCX) | FIT é necessário para Strava e dados completos; TCX para TrainingPeaks |
| Firebase Dynamic Links para OAuth | Firebase rejeitado (DECISAO 001) |
| Armazenar tokens em SharedPreferences | Inseguro — plain text em XML no Android |

### Referência

Documento completo: `docs/PHASE_14_INTEGRATIONS.md`

---

## DECISAO 014 — Garmin/Outros: importação manual via arquivo no MVP

**Data:** 2026-02-17
**Sprint:** 14.3.1
**Status:** APROVADA

### Contexto

Corredores querem ver seus treinos do Omni Runner no Garmin Connect,
Coros, Suunto, Polar Flow, TrainingPeaks e outras plataformas. A
expectativa natural é que exista um botão "Sincronizar com Garmin"
automático, como existe para o Strava.

### Problema

Garmin não disponibiliza API pública para upload de atividades de
terceiros. O endpoint de import visível no portal web é interno (sem
OAuth, sem documentação, requer cookie de sessão). Usar engenharia
reversa violaria os Termos de Serviço. O Garmin Health API e o Connect
IQ SDK exigem contrato comercial e/ou dispositivo Garmin — inviável
para MVP. A mesma limitação se aplica a Coros, Suunto e Polar.

### Decisão

No MVP, a integração com Garmin e todas as plataformas além do Strava
será exclusivamente via **exportação de arquivo (FIT/GPX/TCX) +
importação manual pelo usuário**.

| Aspecto | Decisão |
|---------|---------|
| Mecanismo | Exportar arquivo via share sheet → usuário importa manualmente |
| Formato recomendado | FIT (mais completo); GPX como fallback universal |
| Integração automática | Apenas Strava (via OAuth2 API) |
| UX | 2 telas: escolha de formato + instrução pós-export |
| Educação | Bottom sheet com 3 passos; primeira vez mostra sugestão de Strava |
| Tom de voz | Neutro e prático — sem pedir desculpa, sem culpar Garmin |
| Futuro | Se Garmin abrir API pública, reavaliar (improvável a curto prazo) |

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Engenharia reversa do upload Garmin Connect | Viola ToS; instável; conta pode ser bloqueada |
| Garmin Health API Partner Program | Meses de aprovação; exige volume de usuários; fora do MVP |
| Connect IQ app no relógio Garmin | Limita a um fabricante; requer SDK Garmin separado |
| Não oferecer export para Garmin | Péssima UX; corredor quer consolidar treinos |
| Prometer "em breve" na UI | Cria expectativa falsa; Garmin pode nunca abrir API |

### Referência

`docs/PHASE_14_INTEGRATIONS.md` seção 11 — Garmin/Outros (Manual)

---

## DECISAO 015 — Definition of Done e auditoria de riscos (Phase 14)

**Data:** 2026-02-17
**Sprint:** 14.5.1
**Status:** APROVADA

### Contexto

Phase 14 acumulou código em 5 módulos (file export, share, Strava
OAuth/upload, health export bridge, Garmin manual import UX). Antes de
wiring final e release, é preciso um checklist testável que defina
quando a fase está completa e quais riscos devem ser testados primeiro.

### Decisão

Criada seção "Definition of Done — Phase 14" no `PHASE_14_INTEGRATIONS.md`
com 50 critérios testáveis (D01-D50) agrupados em 6 categorias, e um
Top 10 de riscos QA (Q1-Q10) com ordem de teste recomendada.

| Aspecto | Decisão |
|---------|---------|
| Critérios totais | 50 (D01-D50) |
| Automatizados | 37 (testes unitários existentes) |
| Manuais pendentes | 10 (device testing, import validation) |
| Verificação pendente | 3 (gitignore, git history, code review) |
| Riscos QA | 10 (Q1-Q10) priorizados por blast radius |
| Ordem de teste | Q1 > Q2 > Q8 > Q5 > Q6 > Q4 > Q7 > Q3 > Q9 > Q10 |
| Ferramentas | GPXSee, Garmin Connect web, Strava test account, Charles Proxy |

### Referência

`docs/PHASE_14_INTEGRATIONS.md` seções 13 e 14

---

## DECISAO 016 — Gamification Engine: Moeda Virtual Loja-Safe

**Data:** 2026-02-17
**Sprint:** 12.0.0
**Status:** DECIDIDO
**Impacto:** Alto — define modelo econômico in-app, compliance com App Store e Play Store

### Contexto

O Omni Runner precisa de gamificação (desafios 1v1, grupo, rankings, moeda
virtual) para engajamento. As lojas Apple e Google têm políticas rigorosas
contra gambling, moedas com valor real, e mecânicas pay-to-win. Qualquer
violação resulta em rejeição ou remoção do app.

### Decisão

Criar sistema de gamificação baseado em **OmniCoins** — moeda virtual
puramente cosmética, não-conversível, não-comprável, não-transferível.
Toda mecânica deve ser pré-validada contra as guidelines das lojas.

| # | Decisão | Valor | Motivo |
|---|---------|-------|--------|
| 1 | Moeda virtual | OmniCoins | Nome neutro, sem conotação financeira |
| 2 | Conversibilidade | ZERO — sem resgate, troca ou valor real | Compliance Apple 3.1.1 / Google Real-Money Gambling |
| 3 | Compra via IAP | PROIBIDA | Coins compráveis teriam valor monetário implícito |
| 4 | Transferência | PROIBIDA | Evita marketplace paralelo |
| 5 | Fonte de Coins | Exclusivamente atividade física verificada | Anti-cheat (`isVerified`) como gate |
| 6 | Uso de Coins | Apenas customizações visuais (badges, temas) | Nunca vantagem competitiva |
| 7 | Desafios | Sem apostas — participação gera Coins, vitória dá bônus | Compliance gambling policies |
| 8 | Rankings | Apenas sessões verificadas | Anti-fraude integrado |
| 9 | Vocabulário | Lista de termos proibidos e permitidos | Evita rejection por linguagem |
| 10 | Auditoria | Log append-only de todas transações de Coins | Rastreabilidade completa |

### Documento de referência

`docs/GAMIFICATION_POLICY.md` — contém regras completas, vocabulário
proibido/permitido, declarações para App Review, e escopo de anti-fraude.

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Coins compráveis via IAP | Cria valor monetário; requer economia balanceada complexa |
| Apostas de Coins em desafios | Gambling; requer licença; rejeitado por Apple e Google |
| Loot boxes / gacha para rewards | Mecânica de gambling; banida ou regulada em múltiplos países |
| Prêmios em dinheiro real | Requer licença de promoção; compliance legal complexo |
| NFTs / tokens blockchain | Fora da filosofia do projeto; compliance imprevisível |
| Anúncios rewarded para Coins | Incentivo não-atlético; degrada UX; conflita com princípio fundamental |
| Coins transferíveis entre usuários | Cria economia paralela; risco de RMT (Real Money Trading) |

### Riscos aceitos

| Risco | Probabilidade | Mitigação |
|-------|:------------:|-----------|
| Apple questiona mecânica de desafios | Baixa | Declaração preparada em GAMIFICATION_POLICY.md §6 |
| Google questiona moeda virtual | Baixa | Coins não são vendidos nem resgatados |
| Usuário encontra exploit de Coins | Média | Rate limiting (10 sessões/dia), anti-cheat, auditoria |
| Feature creep (pedidos para "monetizar" Coins) | Alta | GAMIFICATION_POLICY.md como documento de governança |

---

## DECISAO 017 — Progression Engine: XP, Níveis, Badges, Streaks, Missões, Temporadas

**Data:** 2026-02-17
**Sprint:** 13.1.0
**Status:** DECIDIDO
**Impacto:** Alto — define sistema de progressão complementar a OmniCoins

### Contexto

O Omni Runner possui OmniCoins como moeda virtual (ganha e gasta). Falta um
sistema de progressão permanente que reconheça o esforço acumulado ao longo
do tempo: níveis, conquistas, streaks e metas temporárias.

### Decisão

Criar Progression Engine com 6 sistemas (XP, Níveis, Badges, Streaks, Missões,
Temporadas). XP é independente de OmniCoins — nunca convertível. Curva
logarítmica `floor(100 × N^1.5)` garante início rápido e crescimento sustentável.

| # | Decisão | Valor | Motivo |
|---|---------|-------|--------|
| 1 | XP ≠ Coins | Sistemas independentes, nunca convertíveis | Evita inflação e gaming |
| 2 | Curva XP | `floor(100 × N^1.5)` | Sub-exponencial: acessível e sem teto |
| 3 | Cap diário | 1000 XP sessões + 500 XP badges/missões | Anti-farm |
| 4 | Badges | 30 no MVP, 4 tiers (bronze→diamond) | Motivação de longo prazo |
| 5 | Streak freeze | 1 gratuito a cada 7 dias | Reduz frustração sem eliminar incentivo |
| 6 | Temporadas | 90 dias, tiers por Season XP absoluto | Engajamento cíclico sem reset destrutivo |
| 7 | Season Pass | Gratuito, 10 milestones | Compliance: sem tier premium pago |
| 8 | Missões | 5 slots (2 diárias, 2 semanais, 1 de temporada) | Variedade sem overload |
| 9 | XP audit trail | `XpTransactionEntity` append-only | Rastreabilidade (como ledger de Coins) |

### Documento de referência

`docs/PROGRESSION_SPEC.md` — especificação completa com fórmulas, tabelas, badges MVP.

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| XP convertível em Coins | Cria economia circular; facilita exploit |
| Curva exponencial (`2^N`) | Torna níveis altos impossíveis; frustrante |
| Season Pass pago (tier premium) | Violaria GAMIFICATION_POLICY.md §2 (Coins/XP não compráveis) |
| Badges que dão vantagem competitiva | Pay-to-win se combinado com qualquer compra futura |
| Streaks sem freeze | Alta frustração e churn (dados de indústria) |
| Temporadas de 30 dias | Muito curto; não permite progressão significativa |

---

## DECISAO 018 — Regra Append-Only para Enums Serializados como Ordinals

### Data
2026-02-17

### Contexto

Enums persistidos via Isar usam `.index` (posição ordinal) como representação inteira:
- `LedgerReason` (15 valores) — `ledger_record.dart`
- `XpSource` (5 valores) — `progress_model.dart`
- `MissionProgressStatus` (3 valores) — `mission_model.dart`

Se um valor for inserido no meio do enum, todos os registros existentes serão desserializados com o valor errado (corrupção silenciosa).

### Decisão

**Novos valores de enums serializados como ordinals devem ser SEMPRE adicionados no final do enum, nunca no meio.**

### Regras

1. Nunca inserir, remover ou reordenar valores em enums que são persistidos via `.index`
2. Se um valor for deprecado, marcar com `@Deprecated` mas não remover
3. Comentário no Isar model deve listar o mapeamento ordinal completo e ser atualizado a cada alteração
4. Em caso de necessidade de inserção no meio, implementar migração explícita

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Usar string name em vez de ordinal | Performance inferior em queries Isar; mais espaço em disco |
| Constantes inteiras fixas (companion object) | Mais código boilerplate; Dart enum `.index` é idiomático |
| Mapa de conversão (enum ↔ int) | Overhead e risco de esquecer de atualizar |

---

## DECISAO 019 — Namespace `coaching_*` para Entidades de Assessoria

### Data
2026-02-17

### Contexto

Phase 16 (Assessoria Mode) precisa de entidades `Group`, `Member` e `Invite`. Porém, `group_member_entity.dart` já existe na Phase 15 (Social & Events) com `GroupMemberEntity` e roles `admin/moderator/member`.

### Decisão

**Entidades de assessoria usam prefixo `coaching_*` nos nomes de arquivo e classe para evitar conflito.**

- `coaching_group_entity.dart` → `CoachingGroupEntity`
- `coaching_member_entity.dart` → `CoachingMemberEntity` + `CoachingRole` enum
- `coaching_invite_entity.dart` → `CoachingInviteEntity` + `CoachingInviteStatus` enum

### Justificativa

1. Assessoria tem roles distintos: `coach/assistant/athlete` vs `admin/moderator/member`
2. Semântica diferente: coaching groups são privados, com dono fixo (`coachUserId`)
3. Evita import ambíguo e permite coexistência dos dois módulos

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Reutilizar `GroupMemberEntity` com roles extras | Poluiria enum com roles de dois domínios distintos; violaria SRP |
| Subdiretório `entities/coaching/` | Quebraria padrão flat de entidades; import paths inconsistentes |

---

## DECISAO 038 — Introdução do Ecossistema de Assessorias como Núcleo do Produto

**Data:** 2026-02-20
**Status:** APROVADA
**Autor:** Product Owner / CTO
**Impacto:** Crítico — redefine o modelo de domínio, economia e UX do produto

### 1. Contexto

O Omni Runner foi inicialmente concebido como um aplicativo de corrida gamificado focado em:

- Tracking GPS
- Ghost runner
- Desafios PVP entre usuários
- Gamificação individual (XP, badges, coins)
- Leaderboards e grupos sociais

A arquitetura atual reflete esse modelo:

- Usuário como ator principal
- Coins como recurso individual
- Desafios peer-to-peer
- Grupos sociais genéricos

Com a evolução do produto e análise do mercado global de corrida, identificou-se que:

- O verdadeiro núcleo do ecossistema de corrida NÃO são indivíduos isolados
- São **Assessorias esportivas** (running clubs/coaches)

Essas entidades:

- Controlam a evolução dos atletas
- Organizam competições
- Distribuem recompensas
- Criam comunidades físicas reais
- Movimentam a economia do esporte

### 2. Problema

O modelo atual apresenta limitações estruturais:

#### 2.1 Falta de Actor Institucional

Não existe representação formal de:

- Assessorias
- Professores
- Estrutura hierárquica

#### 2.2 Economia sem lastro institucional

Coins atualmente:

- Não pertencem a nenhuma instituição
- Não têm restrições territoriais
- Não possuem fluxo realista de origem/destino

Isso impede:

- Modelo sustentável de monetização
- Escalabilidade do ecossistema

#### 2.3 Gamificação pouco aderente ao mundo real

O sistema atual não contempla:

- Treinamento supervisionado
- Evolução monitorada por coach
- Competições inter-clubes
- Eventos organizados por assessorias

### 3. Decisão

Foi decidido transformar o Omni Runner em um **ecossistema institucional centrado em assessorias**.

As Assessorias passam a ser o **ator principal do domínio**.

### 4. Novo Modelo Conceitual

#### 4.1 Hierarquia de Atores

| Nível | Descrição |
|-------|-----------|
| **Plataforma** | Admin global; aprova assessorias |
| **Assessoria** | Entidade institucional; possui professores e atletas; organiza campeonatos |
| **Professores** | Administradores da assessoria; gerenciam atletas e eventos |
| **Atletas** | Usuários finais; vinculados a UMA assessoria por vez |

#### 4.2 Vinculação de Usuário

Regras:

- Um atleta pertence a somente uma assessoria ativa
- Pode trocar a qualquer momento
- Ao trocar:
  - Coins não trocadas são queimadas
  - Deve ser alertado previamente

#### 4.3 Novo Modelo Econômico — Origem dos Tokens

Fluxo unidirecional:

```
Plataforma → Assessoria → Atleta → Desafio → Burn
```

Tokens:

- São comprados pela assessoria da plataforma
- São distribuídos ao atleta pela assessoria
- Só podem ser usados e trocados na assessoria atual

#### 4.4 Desafios entre Assessorias

Quando um atleta vence outro:

- Os tokens passam para a assessoria do vencedor
- A assessoria perdedora entra em estado de "clearing"

Esse clearing é resolvido:

- Diretamente entre as assessorias
- Sem mediação financeira da plataforma

O sistema apenas:

- Registra o débito
- Bloqueia a troca até liquidação

#### 4.5 Campeonatos Institucionais

Nova entidade de domínio: **CHAMPIONSHIP**

Características:

- Criado por assessoria host
- Convida outras assessorias
- Pode exigir badge de participação
- Possui período definido
- Possui ranking e premiações

#### 4.6 Gamificação Orientada a Performance

O foco da gamificação passa a ser:

- Evolução esportiva real
- Métricas de treino
- Progressão supervisionada
- Competições estruturadas

Não será focada em:

- Sorte
- Gambling
- Rewards monetários explícitos

### 5. Impactos na Arquitetura

#### 5.1 Novo Bounded Context

Será criado um novo contexto: `ASSESSORIA_DOMAIN`

Incluindo:

- Assessoria
- Professores
- Membership
- Championships
- Clearing

#### 5.2 Alterações no Modelo de Dados

Novas entidades:

- `institutions`
- `institution_staff`
- `institution_memberships`
- `championships`
- `championship_participants`
- `inter_institution_settlements`

#### 5.3 Alterações no Sistema de Coins

Coins passam a ter:

- `institution_origin_id`
- Lifecycle state machine
- Clearing constraints

### 6. Impactos no Frontend

O app deixará de ser **Runner-centric** e passará a ser **Institution-centric**.

Novos módulos:

- Dashboard da assessoria
- Gestão de atletas
- Campeonatos
- Visualização de evolução
- Sistema de convites institucionais

### 7. Consequências Positivas

- Alinhamento com mercado real de corrida
- Modelo sustentável de monetização
- Escalabilidade institucional
- Diferenciação competitiva global
- Redução de fraude
- Compliance com App Stores

### 8. Consequências Negativas

- Aumento significativo de complexidade do domínio
- Necessidade de onboarding institucional manual
- Maior carga de desenvolvimento backend
- Necessidade de novos fluxos UX complexos

### 9. Alternativas Rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Manter modelo individual | Não escala; não monetiza adequadamente |
| Plataforma como clearing house financeira | Risco regulatório elevado; necessidade de licenças financeiras |

### 10. Riscos

| Risco | Mitigação |
|-------|-----------|
| Falta de adesão inicial das assessorias | Onboarding assistido; parcerias com assessorias piloto |
| Complexidade de onboarding institucional | UX extremamente clara; fluxo guiado |
| Complexidade de domínio elevada | Bounded contexts bem definidos; implementação incremental |

### 11. Critérios de Sucesso

O novo modelo será considerado bem-sucedido quando:

- Assessorias conseguirem operar campeonatos completos
- Sistema de clearing funcionar sem intervenção manual
- Atletas utilizarem desafios inter-institucionais regularmente

### 12. Próximos Passos

1. Atualizar MASTER_PLAN.md com novo épico institucional
2. Definir novo domínio em ARCHITECTURE.md
3. Criar migrações Supabase para novas entidades
4. Ajustar modelo de gamificação

---

## DECISAO 039 — Deep Link Scheme e Callback URLs

**Data:** 2026-02-21
**Sprint:** 18.1.1
**Status:** DECIDIDO
**Impacto:** Medio — afeta OAuth callbacks (Supabase Auth, Strava), deep linking futuro

### Contexto

O app precisa receber callbacks de OAuth (Google Sign-In, Apple Sign-In, Strava)
via deep link. O scheme `omnirunner://` já era referenciado no código (Strava OAuth)
e na documentação, mas não estava registrado no AndroidManifest.xml nem no Info.plist.

### Decisão

**UM único scheme para todo o app:** `omnirunner://`

Rotas de callback sob esse scheme:

| Rota | Uso |
|------|-----|
| `omnirunner://auth-callback` | Supabase Auth (Google/Apple social login) |
| `omnirunner://strava/callback` | Strava OAuth2 (já existente no código) |

### Configuração Nativa

**Android** (`AndroidManifest.xml`):

```xml
<intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="omnirunner"/>
</intent-filter>
```

**iOS** (`Info.plist`):

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.omnirunner.omniRunner</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>omnirunner</string>
        </array>
    </dict>
</array>
```

### Supabase Dashboard

| Setting | Valor |
|---------|-------|
| Site URL | `omnirunner://auth-callback` |
| Redirect URLs (allowlist) | `omnirunner://auth-callback`, `omnirunner://strava/callback`, `https://<PROJECT_REF>.supabase.co/auth/v1/callback` |

### Justificativa

1. **Um scheme único** — evita fragmentação e simplifica o intent-filter/URL Types
2. **`omnirunner://`** — já era o padrão de facto (Strava OAuth), formalizado agora
3. **`auth-callback`** vs `login-callback` — "auth" é mais genérico (cobre sign-up, sign-in, link account)
4. **`autoVerify="false"`** — custom scheme não suporta Digital Asset Links; verificação não se aplica
5. **Fallback web** — `https://<PROJECT_REF>.supabase.co/auth/v1/callback` mantido no allowlist para debug via browser

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Scheme separado por provider (`omnirunner-google://`, `omnirunner-apple://`) | Fragmentação desnecessária; um scheme com paths distintos é suficiente |
| Universal Links (HTTPS) como primary | Requer hosting de `apple-app-site-association` e `assetlinks.json`; overkill para MVP |
| Sem registrar scheme (confiar apenas em `signInWithIdToken`) | Strava já precisa do scheme; melhor registrar uma vez para todos os fluxos |

---

## DECISAO 040 — Onboarding Atleta: Escolher Assessoria com re-resolve

**Data:** 2026-02-21
**Sprint:** 18.5.0
**Status:** DECIDIDO
**Impacto:** Medio — routing pós-role-selection, novo RPC

### Contexto

Após selecionar o papel ATLETA, o usuário precisa de uma oportunidade para entrar
em uma assessoria antes de chegar ao app principal. ASSESSORIA_STAFF avança direto
para READY (não precisa de vínculo).

### Decisão

1. **OnboardingRoleScreen** não define `onboarding_state = READY` para ATLETA;
   mantém em `ROLE_SELECTED` e chama `onComplete`.
2. **AuthGate._onOnboardingComplete** re-executa `_resolve()` em vez de ir direto
   para Home. Isso permite que o gate leia o estado atualizado do profile e
   determine o próximo destino.
3. **AuthGate._resolve()** detecta `ROLE_SELECTED + ATLETA` e roteia para
   `JoinAssessoriaScreen`.
4. **JoinAssessoriaScreen** oferece 4 caminhos: busca por nome
   (`fn_search_coaching_groups` RPC), QR scanner, código manual, pular.
5. Ao entrar ou pular, o screen define `onboarding_state = READY` e chama
   `onComplete` → re-resolve → Home.
6. **fn_search_coaching_groups** é SECURITY DEFINER para que novos usuários
   (que ainda não são membros de nenhum grupo) possam buscar coaching_groups
   sem ser bloqueados por RLS.

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Novo onboarding_state (e.g. ASSESSORIA_PENDING) | Aumenta complexidade do schema sem benefício real; `ROLE_SELECTED + user_role` já é suficiente |
| OnboardingRoleScreen define READY para todos e JoinAssessoria é acessível no Home | Usuário perderia a chance de entrar na assessoria durante o onboarding, reduzindo ativação |
| Search direto via RLS (sem RPC) | coaching_groups RLS exige membership; novo usuário seria bloqueado |

---

## DECISAO 041 — Máquina de Estados Final do Onboarding

**Data:** 2026-02-21
**Sprint:** 18.7.0
**Status:** DECIDIDO
**Impacto:** Alto — define todo o roteamento da aplicação

### Contexto

Com WelcomeScreen, LoginScreen, OnboardingRoleScreen, JoinAssessoriaScreen,
StaffSetupScreen e os dois dashboards (Atleta/Staff) implementados, a máquina
de estados de onboarding precisa ser formalizada como definitiva.

### Decisão

A máquina é **linear e sem loops**. O `AuthGate` é o único ponto de decisão.

```
┌─────────────────────────────────────────────────────────┐
│                     AuthGate._resolve()                 │
├─────────────────────────────────────────────────────────┤
│ Mock mode               → HomeScreen (skip all gates)   │
│ No session              → WelcomeScreen → LoginScreen   │
│ Anonymous               → HomeScreen (legacy workaround)│
│ Profile null            → OnboardingRoleScreen (NEW)    │
│ NEW                     → OnboardingRoleScreen          │
│ ROLE_SELECTED + ATLETA  → JoinAssessoriaScreen          │
│ ROLE_SELECTED + STAFF   → StaffSetupScreen              │
│ READY + ATLETA          → HomeScreen (AthleteDashboard) │
│ READY + STAFF           → HomeScreen (StaffDashboard)   │
└─────────────────────────────────────────────────────────┘
```

Transições DB:

| Tela | Ação | Estado Anterior → Novo |
|------|-------|------------------------|
| LoginScreen | signIn OK | (nenhum) → NEW (via trigger `handle_new_user`) |
| OnboardingRoleScreen | set-user-role | NEW → ROLE_SELECTED |
| JoinAssessoriaScreen | join/skip | ROLE_SELECTED → READY |
| StaffSetupScreen | create/join | ROLE_SELECTED → READY |

Invariantes:

1. **Forward-only** — cada `onComplete()` re-resolve no AuthGate; como o DB
   progrediu, o gate nunca retorna à tela anterior.
2. **READY é terminal** — `set-user-role` retorna 409 ONBOARDING_LOCKED quando
   `onboarding_state = READY`.
3. **Trigger garante profile** — `handle_new_user` roda síncrono no INSERT de
   `auth.users`, então o profile existe antes do `_resolve()` pós-login.
4. **complete-social-profile é best-effort** — chamada `unawaited` pós-login
   para preencher `created_via`; o trigger já criou a row.
5. **Dashboard por papel** — HomeScreen recebe `userRole` do AuthGate e mostra
   `AthleteDashboardScreen` ou `StaffDashboardScreen` em tab 0.

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Router declarativo (GoRouter) com guards | Overhead desnecessário para 5 telas lineares; widget switch é mais simples e testável |
| Estado intermediário ASSESSORIA_PENDING | `ROLE_SELECTED + user_role` já distingue os dois caminhos sem novo estado |
| Permitir voltar de READY para role selection | Abre possibilidade de loops; role change pós-READY fica para Settings (futuro) |

---

## DECISAO 042 — TikTok e Instagram OAuth: Custom Provider via Edge Function

**Data:** 2026-02-21
**Sprint:** 19.1.0
**Status:** DECIDIDO
**Impacto:** Medio — requer Edge Function customizada para providers não nativos do Supabase

### Contexto

Supabase Auth suporta nativamente Google, Apple, Facebook, GitHub, Discord, etc.
Porém **não suporta TikTok nem Instagram** como providers nativos. Para oferecer
login social com TikTok e Instagram, é necessário um fluxo customizado.

### Decisão

1. **Apps criados nos consoles externos** — TikTok for Developers e Facebook
   Developers (Instagram Basic Display). Client IDs e Secrets obtidos e
   armazenados de forma segura.
2. **Redirect URI unificada** — `https://<PROJECT_REF>.supabase.co/auth/v1/callback`
   para ambos, mantendo o padrão dos providers nativos.
3. **Integração futura via Edge Function** — uma Edge Function `validate-social-login`
   receberá o authorization code do SDK nativo, trocará por access_token no
   provider, buscará o perfil do usuário, e criará/vinculará a sessão Supabase.
4. **`created_via` expansion** — novos valores `OAUTH_TIKTOK` e `OAUTH_INSTAGRAM`
   serão adicionados ao CHECK constraint de profiles quando o fluxo Flutter for
   implementado.
5. **Ambos em sandbox/dev mode** — TikTok requer app review para produção
   (Login Kit). Instagram requer app review pela Meta (permissions
   `instagram_basic`). Reviews serão submetidos quando os fluxos estiverem
   funcionais.

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Facebook Login como proxy para Instagram | Confuso para o usuário; "Entrar com Facebook" != "Entrar com Instagram" na percepção do runner |
| Web-based OAuth flow (WebView) | UX inferior vs SDK nativo; problemas de segurança com WebView |
| Ignorar TikTok/Instagram | Público-alvo (runners) tem forte presença nessas plataformas |

---

## DECISAO 043 — Instagram via Facebook provider nativo; TikTok requer Edge Function

**Sprint:** 19.1.1
**Status:** DECIDIDO
**Impacto:** Médio — corrige abordagem para Instagram, mantém TikTok como custom

### Contexto

Ao tentar registrar TikTok e Instagram como providers OAuth no Supabase,
identificamos que o Supabase lista explicitamente os providers nativos suportados:
`apple`, `azure`, `bitbucket`, `discord`, `facebook`, `github`, `gitlab`,
`google`, `keycloak`, `linkedin_oidc`, `notion`, `twitch`, `twitter`, `x`,
`slack`, `spotify`, `workos`, `zoom`.

**TikTok não está na lista** e não pode ser configurado como provider nativo.
**Instagram também não**, mas é coberto pelo provider **Facebook** da Meta.

### Decisão

1. **Instagram → `auth.external.facebook`** — O provider `facebook` nativo do
   Supabase dá acesso ao perfil Meta do usuário. Quando o usuário autoriza
   Instagram Basic Display, o token Meta inclui dados do Instagram. Esse é o
   caminho oficialmente suportado pelo Supabase para Instagram.
2. **TikTok → Edge Function `validate-social-login`** — Permanece como custom
   OAuth (DECISAO 042). O SDK nativo obtém authorization code, a Edge Function
   faz code exchange e cria sessão via `supabase.auth.admin`.
3. **`config.toml` atualizado** — `[auth.external.facebook]` adicionado com
   `FACEBOOK_APP_ID` e `FACEBOOK_APP_SECRET` como variáveis de ambiente.
4. **`created_via` ajustado** — O valor para Instagram será `OAUTH_FACEBOOK`
   (não `OAUTH_INSTAGRAM`), refletindo o provider real. TikTok permanece
   `OAUTH_TIKTOK`.

### Impacto na DECISAO 042

A DECISAO 042 previa custom Edge Function para ambos (TikTok + Instagram).
Esta decisão corrige: Instagram usa o caminho nativo `facebook`, eliminando
a necessidade de código customizado para Instagram. A Edge Function
`validate-social-login` será necessária **apenas para TikTok**.

### Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Forçar `[auth.external.tiktok]` no config.toml | Supabase ignora providers desconhecidos; não funciona |
| Instagram via Edge Function customizada | Desnecessário — `facebook` nativo cobre Instagram |
| Aguardar Supabase adicionar TikTok nativamente | Sem previsão; bloquearia o roadmap |

---

## DECISAO 044 — Modelo Final de Progressão (Phase 20 — Gamification)

**Data:** 2026-02-21
**Sprint:** 20.1.0
**Status:** DECIDIDO
**Impacto:** Alto — define toda a progressão do atleta, microcopy UX e integração com assessorias

### 1. Contexto

O `PROGRESSION_SPEC.md` (Sprint 13.1.0) e a `DECISAO 017` definiram XP, Níveis, Badges,
Streaks, Missões e Temporadas como sistemas complementares aos OmniCoins. Desde então,
o app evoluiu com assessorias (Phase 16-19), campeonatos, e um onboarding "para dummies".

É necessário formalizar o modelo **final e implementável** de progressão, incorporando:

- Integração com assessorias e campeonatos
- Metas semanais automáticas (Goals)
- Microcopy simples para cada evento de progressão

### 2. Decisão

O modelo de progressão é composto por **4 pilares** + microcopy UX unificado.

#### 2.1 Pilar 1 — XP (Experience Points)

XP é a unidade de progressão permanente. **Nunca decresce, nunca expira, nunca é convertido em OmniCoins.**

**Fontes de XP:**

| Fonte | XP | Condição |
|-------|:--:|----------|
| Sessão verificada (base) | 20 | `isVerified == true`, ≥ 200m |
| Sessão — bônus distância | `floor(distKm × 10)` | Cap: 500 (50 km) |
| Sessão — bônus duração | `floor(durMin / 5) × 2` | Cap: 120 (5 h) |
| Sessão — bônus HR | 10 | `avgBpm != null` |
| Badge desbloqueado | 50/100/200/500 | Por tier (bronze/silver/gold/diamond) |
| Missão completada | 30–400 | Por dificuldade (easy/medium/hard) |
| Streak semanal (3+ corridas) | 50 | Sessões verificadas na semana UTC |
| Streak mensal (12+ corridas) | 150 | Sessões verificadas no mês UTC |
| Desafio completado | 30 | Participação verificada |
| Desafio vencido | 75 | Bônus vitória |
| Campeonato — participação | 50 | Completar campeonato com sessões |
| Campeonato — top 3 | 100/200/500 | 3º/2º/1º lugar |
| Meta semanal cumprida | 40 | Goal atingido dentro do prazo |

**Caps diários:**

| Cap | Limite | Motivo |
|-----|:------:|--------|
| XP por sessões | 1 000/dia | Anti-farm |
| Sessões que geram XP/Coins | 10/dia | Consistente com GAMIFICATION_POLICY §8 |
| XP por fontes não-sessão | 500/dia | Evita XP farming via badges triviais |
| **Total máximo teórico** | **1 500/dia** | — |

#### 2.2 Pilar 2 — Nível

Derivado deterministicamente do XP total:

```
xpForLevel(N) = floor(100 × N^1.5)
levelFromXp(totalXp) = floor((totalXp / 100)^(2/3))
```

Propriedades: início rápido (nível 1 = 100 XP, ~1 sessão), crescimento sub-exponencial,
sem teto (nível 100 = ~100k XP, ~6 meses de corrida consistente).

#### 2.3 Pilar 3 — Streak

| Tipo | Critério | Tolerância | Recompensa |
|------|----------|------------|------------|
| **Diário** | ≥ 1 sessão verificada ≥ 200m no dia UTC | 1 freeze gratuito a cada 7 dias de streak | Mantém contador + milestones (3/7/14/30/60/100/365 dias) |
| **Semanal** | ≥ 3 sessões verificadas na semana (seg–dom UTC) | Nenhuma — reset automático na semana seguinte | +50 XP, +20 OmniCoins |
| **Mensal** | ≥ 12 sessões verificadas no mês UTC | Nenhuma — reset automático no mês seguinte | +150 XP, +50 OmniCoins |

Regras de freeze:
- 1 freeze acumula automaticamente a cada 7 dias de streak contínuo
- Máximo 1 acumulado por vez (não empilha)
- Consumido automaticamente se o dia passa sem sessão
- Não é comprável nem obtido por outra via

#### 2.4 Pilar 4 — Goals (Metas Semanais)

**NOVO:** Metas semanais automáticas baseadas no histórico do atleta.

| Aspecto | Regra |
|---------|-------|
| Período | Segunda 00:00 UTC – Domingo 23:59 UTC |
| Geração | Automática no início da semana |
| Métricas | Distância total (km) **ou** Tempo total (min) |
| Baseline | Média das 4 últimas semanas (ou default 10 km / 60 min para novos) |
| Fator | 1.0× (manter) ou 1.1× (superar levemente) — alternado |
| Check | Automático: soma de sessões verificadas da semana vs meta |
| Recompensa | +40 XP ao atingir; sem penalidade ao falhar |
| Visibilidade | Card na home com barra de progresso e mensagem |
| Assessoria | Professor pode sugerir meta manual (futuro, não nesta sprint) |

**Anti-exploit:**
- Apenas sessões verificadas contam
- Cap de 10 sessões/dia impede farm
- Baseline usa média móvel — cresce gradualmente com o atleta

### 3. Microcopy UX ("para dummies")

Todas as mensagens são **curtas, em PT-BR, sem jargão técnico, sem termos proibidos**.

#### 3.1 XP e Nível

| Evento | Mensagem |
|--------|----------|
| XP ganho pós-sessão | "**+{xp} XP** pela sua corrida!" |
| Nível subiu | "Parabéns! Você alcançou o **Nível {n}**!" |
| Perto do próximo nível | "Faltam **{xp} XP** para o Nível {n}." |
| Cap diário atingido | "Você já ganhou bastante XP hoje. Descanse e volte amanhã!" |

#### 3.2 Streak

| Evento | Mensagem |
|--------|----------|
| Streak mantido | "**{n} dias seguidos!** Continue assim!" |
| Streak milestone (7 dias) | "**7 dias seguidos!** Você ganhou +50 XP e +10 OmniCoins." |
| Freeze consumido | "Seu dia de descanso foi usado. O streak continua!" |
| Streak perdido | "Seu streak voltou ao início. Comece uma nova sequência hoje!" |
| Streak semanal atingido | "**3 corridas esta semana!** +50 XP e +20 OmniCoins." |
| Streak mensal atingido | "**12 corridas este mês!** +150 XP e +50 OmniCoins." |

#### 3.3 Badge

| Evento | Mensagem |
|--------|----------|
| Badge desbloqueado | "Conquista desbloqueada: **{badge_name}**! +{xp} XP" |
| Progresso de badge | "{x}% concluído para **{badge_name}**." |
| Badge secreto revelado | "Conquista secreta revelada: **{badge_name}**!" |

#### 3.4 Meta Semanal (Goal)

| Evento | Mensagem |
|--------|----------|
| Nova meta disponível | "Sua meta da semana: **{valor} km** (ou **{valor} min**)." |
| Progresso parcial | "**{atual}/{meta} km** — continue correndo!" |
| Meta atingida | "Meta da semana cumprida! +40 XP" |
| Meta não atingida | "Não foi dessa vez. Uma nova meta começa na segunda!" |

#### 3.5 Missão

| Evento | Mensagem |
|--------|----------|
| Missão disponível | "Nova missão: **{título}**" |
| Missão completada | "Missão concluída: **{título}**! +{xp} XP, +{coins} OmniCoins" |
| Missão expirada | "A missão **{título}** expirou. Novas missões chegam em breve!" |

#### 3.6 Campeonato

| Evento | Mensagem |
|--------|----------|
| Inscrição confirmada | "Você está inscrito no campeonato **{nome}**!" |
| Campeonato encerrado | "O campeonato **{nome}** terminou. Confira o resultado!" |
| Pódio (top 3) | "Parabéns! Você ficou em **{posição}º lugar** no campeonato **{nome}**! +{xp} XP" |

### 4. Integração com Assessoria

| Cenário | Comportamento |
|---------|---------------|
| Troca de assessoria | XP, nível, badges e streaks são **preservados** (pertencem ao atleta, não à assessoria). OmniCoins não utilizados são perdidos (regra existente). |
| Rankings de assessoria | Usam **Season XP** ou **sessões da semana** — não XP total (evita vantagem de veteranos). |
| Professor vê progresso do atleta | Nível, streak, badges, metas semanais — tudo visível no dashboard do coach. |
| Campeonatos inter-assessoria | XP de campeonato é creditado ao atleta individual, independente da assessoria. |

### 5. Compliance com GAMIFICATION_POLICY.md

| Regra | Verificação |
|-------|-------------|
| §1 — Engajamento, não monetário | ✅ XP é progressão, Goals são metas esportivas |
| §2 — OmniCoins não-convertíveis | ✅ XP e Goals independentes de OmniCoins |
| §3 — Atividade verificada | ✅ Todas as fontes exigem `isVerified == true` |
| §5 — Vocabulário | ✅ Microcopy usa: "corrida", "meta", "conquista", "nível", "sequência" |
| §8 — Anti-fraude | ✅ Caps diários, `isVerified`, dedup, UTC |

### 6. Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| Goals definidos pelo atleta | Atleta novato não sabe definir metas realistas; automático é melhor para onboarding |
| XP transferível entre assessorias | Criaria economia paralela; XP pertence ao atleta, não à assessoria |
| Streak sem freeze | Alta frustração e churn (dados da indústria) |
| Goals diários em vez de semanais | Pressão excessiva; semanal permite flexibilidade de agenda |
| Curva exponencial para níveis | Torna níveis altos impossíveis; `N^1.5` é sub-exponencial e sustentável |
| XP convertível em OmniCoins | Viola GAMIFICATION_POLICY §2; DECISAO 017 proíbe explicitamente |
| Goals com penalidade ao falhar | Frustrante para iniciantes; contradiz "para dummies" |

---

## DECISAO 045 — Catálogo Final de Badges Automáticos (Phase 20)

**Data:** 2026-02-21
**Sprint:** 20.2.0
**Status:** DECIDIDO
**Impacto:** Alto — define quais conquistas existem no app e como são avaliadas

### 1. Contexto

O `PROGRESSION_SPEC.md` (Sprint 13.1.0) definiu um catálogo de 30 badges MVP. Desde então,
o app evoluiu com assessorias, campeonatos, metas semanais e um onboarding "para dummies".

É necessário formalizar o catálogo **mínimo global** de badges automáticos, adicionando:

- Badges de milestone acessíveis para iniciantes (5 corridas, streak 3/14)
- Badges de campeonato e vitória em desafio
- Badge de meta semanal (10 km na semana)
- Revisão de linguagem para compliance com `GAMIFICATION_POLICY.md`

### 2. Princípios

| # | Princípio | Motivo |
|---|-----------|--------|
| 1 | Todas as conquistas exigem `isVerified == true` | Anti-fraude |
| 2 | Nenhuma conquista incentiva overtraining | Saúde do atleta |
| 3 | Streak máximo no catálogo = 30 dias | Evitar pressão excessiva |
| 4 | Conquistas de pace exigem ≥ 5 km | Evitar sprints curtos artificiais |
| 5 | Conquista desbloqueada = permanente, nunca revogada | Motivação de longo prazo |
| 6 | Avaliação server-side (Edge Function `evaluate-badges`) | Impede manipulação client-side |
| 7 | Dedup: badge_id + user_id = UNIQUE | Nunca desbloqueado duas vezes |
| 8 | Linguagem simples, PT-BR, sem jargão | "Para dummies" |

### 3. Catálogo — 24 badges automáticos

#### 3.1 Primeiros Passos (4) — Onboarding

| ID | Nome | Tier | Categoria | Critério | XP | criteria_type | criteria_json |
|----|------|------|-----------|----------|:--:|---------------|---------------|
| `badge_first_run` | Primeiro Passo | Bronze | frequency | 1ª sessão verificada | 50 | `session_count` | `{"count": 1}` |
| `badge_5_runs` | Corredor Dedicado | Bronze | frequency | 5 sessões verificadas | 50 | `session_count` | `{"count": 5}` |
| `badge_first_km` | Primeiro Quilômetro | Bronze | distance | 1ª sessão ≥ 1 km | 50 | `single_session_distance` | `{"threshold_m": 1000}` |
| `badge_first_challenge` | Primeiro Desafio | Bronze | social | Completar qualquer desafio | 50 | `challenges_completed` | `{"count": 1}` |

#### 3.2 Distância (5) — Marcos de sessão e acumulado

| ID | Nome | Tier | Categoria | Critério | XP | criteria_type | criteria_json |
|----|------|------|-----------|----------|:--:|---------------|---------------|
| `badge_5k` | 5K Runner | Bronze | distance | 1 sessão ≥ 5 km | 50 | `single_session_distance` | `{"threshold_m": 5000}` |
| `badge_10k` | 10K Runner | Silver | distance | 1 sessão ≥ 10 km | 100 | `single_session_distance` | `{"threshold_m": 10000}` |
| `badge_half_marathon` | Meia Maratona | Gold | distance | 1 sessão ≥ 21.1 km | 200 | `single_session_distance` | `{"threshold_m": 21100}` |
| `badge_50km_total` | 50 km Acumulados | Bronze | distance | Distância lifetime ≥ 50 km | 50 | `lifetime_distance` | `{"threshold_m": 50000}` |
| `badge_200km_total` | 200 km Acumulados | Silver | distance | Distância lifetime ≥ 200 km | 100 | `lifetime_distance` | `{"threshold_m": 200000}` |

#### 3.3 Frequência (4) — Consistência

| ID | Nome | Tier | Categoria | Critério | XP | criteria_type | criteria_json |
|----|------|------|-----------|----------|:--:|---------------|---------------|
| `badge_10_runs` | 10 Corridas | Bronze | frequency | 10 sessões lifetime | 50 | `session_count` | `{"count": 10}` |
| `badge_50_runs` | 50 Corridas | Silver | frequency | 50 sessões lifetime | 100 | `session_count` | `{"count": 50}` |
| `badge_100_runs` | 100 Corridas | Gold | frequency | 100 sessões lifetime | 200 | `session_count` | `{"count": 100}` |
| `badge_10km_week` | 10 km na Semana | Bronze | frequency | ≥ 10 km verificados na semana ISO | 50 | `weekly_distance` | `{"threshold_m": 10000}` |

#### 3.4 Sequência / Streak (3) — Dias consecutivos

| ID | Nome | Tier | Categoria | Critério | XP | criteria_type | criteria_json |
|----|------|------|-----------|----------|:--:|---------------|---------------|
| `badge_streak_3` | 3 Dias Seguidos | Bronze | frequency | Streak diário ≥ 3 dias | 50 | `daily_streak` | `{"days": 3}` |
| `badge_streak_7` | 7 Dias Seguidos | Silver | frequency | Streak diário ≥ 7 dias | 100 | `daily_streak` | `{"days": 7}` |
| `badge_streak_14` | 14 Dias Seguidos | Gold | frequency | Streak diário ≥ 14 dias | 200 | `daily_streak` | `{"days": 14}` |

> **Nota de saúde:** O catálogo global NÃO inclui streak de 30+ dias para evitar pressão
> de overtraining. Badges de streak ≥ 30 ficam reservados para temporadas especiais.

#### 3.5 Velocidade (3) — Pace

| ID | Nome | Tier | Categoria | Critério | XP | criteria_type | criteria_json |
|----|------|------|-----------|----------|:--:|---------------|---------------|
| `badge_pace_6` | Abaixo de 6:00/km | Bronze | speed | Pace < 6:00/km em sessão ≥ 5 km | 50 | `pace_below` | `{"max_pace_sec_per_km": 360, "min_distance_m": 5000}` |
| `badge_pace_5` | Abaixo de 5:00/km | Silver | speed | Pace < 5:00/km em sessão ≥ 5 km | 100 | `pace_below` | `{"max_pace_sec_per_km": 300, "min_distance_m": 5000}` |
| `badge_pr_pace` | Recorde de Pace | Bronze | speed | Novo PR de pace (sessão ≥ 1 km) | 50 | `personal_record_pace` | `{"min_distance_m": 1000}` |

#### 3.6 Social / Competitivo (3) — Desafios e campeonatos

| ID | Nome | Tier | Categoria | Critério | XP | criteria_type | criteria_json |
|----|------|------|-----------|----------|:--:|---------------|---------------|
| `badge_5_challenges` | 5 Desafios | Silver | social | Completar 5 desafios | 100 | `challenges_completed` | `{"count": 5}` |
| `badge_challenge_won` | Vitória no Desafio | Bronze | social | Vencer 1 desafio | 50 | `challenge_won` | `{"count": 1}` |
| `badge_champ_participant` | Campeonato Concluído | Silver | social | Participar e completar 1 campeonato | 100 | `championship_completed` | `{"count": 1}` |

#### 3.7 Especial (2) — Horários

| ID | Nome | Tier | Categoria | Critério | XP | criteria_type | criteria_json |
|----|------|------|-----------|----------|:--:|---------------|---------------|
| `badge_early_bird` | Madrugador | Bronze | special | Sessão iniciada antes das 06:00 | 50 | `session_before_hour` | `{"hour_local": 6}` |
| `badge_night_owl` | Coruja | Bronze | special | Sessão iniciada após 22:00 | 50 | `session_after_hour` | `{"hour_local": 22}` |

### 4. Novos criteria_types necessários

| criteria_type | Quando avaliar | Fonte de dados |
|---------------|----------------|----------------|
| `weekly_distance` | Após cada sessão | `v_weekly_progress` (view criada em 20.1.1) |
| `challenge_won` | Após settle-challenge | `challenge_results.outcome = 'won'` |
| `championship_completed` | Após finalização de campeonato | `championship_participants.status = 'completed'` |

Estes tipos precisam ser implementados no `evaluate-badges` Edge Function (sprint futura).

### 5. Badges REMOVIDOS do catálogo original (simplificação)

| Badge removido | Motivo |
|----------------|--------|
| `badge_marathon` (Diamond, 42.195 km) | Muito elitista para catálogo global mínimo; mantido como badge de temporada futura |
| `badge_1000km_total` (Gold) | Muito longo prazo; mantido como badge de temporada |
| `badge_500_runs` (Diamond) | Muito longo prazo; mantido como badge de temporada |
| `badge_streak_30` (Gold) | Risco de overtraining; reservado para temporadas com freeze garantido |
| `badge_pace_430` / `badge_pace_4` (Gold/Diamond) | Muito elitista; mantido como badges de temporada |
| `badge_2h_run` (Silver) | Incentiva overtraining para iniciantes |
| `badge_invicto` (Gold, 10 wins consecutivas) | Critério complexo; implementação adiada |
| `badge_group_leader` (Silver) | Critério complexo; implementação adiada |
| `badge_10h_total` / `badge_100h_total` (Endurance) | Duplicam métricas de distância; confusos |

### 6. Microcopy (PT-BR)

| Evento | Mensagem |
|--------|----------|
| Badge desbloqueado | "Conquista desbloqueada: **{nome}**! +{xp} XP" |
| Progresso visível | "{x}% para **{nome}**" |
| Badge secreto revelado | "Conquista secreta: **{nome}**!" |

### 7. Compliance

| Regra GAMIFICATION_POLICY | Status |
|---------------------------|--------|
| §3 — Atividade verificada | ✅ Todos exigem `isVerified == true` |
| §5 — Vocabulário | ✅ "conquista", "corrida", "desafio", "sequência" — sem termos proibidos |
| §8 — Anti-fraude | ✅ Avaliação server-side, dedup, distance mínima para pace |
| Saúde | ✅ Streak máximo 14 dias; sem badge ≥ 2h de corrida única; sem pressão elitista |

### 8. Alternativas rejeitadas

| Alternativa | Motivo de rejeição |
|-------------|-------------------|
| 50+ badges no catálogo global | Confuso para usuário; diluição de valor |
| Badges de streak 30/60/100 dias globais | Overtraining; pressão excessiva para manter |
| Badge de maratona no catálogo mínimo | Exclui 95%+ dos corredores; elitista |
| Badges por distância AND tempo | Redundantes; confusos ("qual é a diferença?") |
| Badge de "10 km em uma sessão" | Redundante com `badge_10k` já existente |

---

## DECISAO 046 — Modelo de Monetização Loja-Safe (Phase 21)

**Data:** 2026-02-21
**Sprint:** 21.1.0
**Status:** DECIDIDO
**Impacto:** Crítico — define como o produto gera receita sem violar Apple/Google policies

### 1. Contexto

O Omni Runner é um app de corrida gamificado centrado em assessorias esportivas (DECISAO 038).
O produto precisa de um modelo de receita sustentável que:

- Não viole Apple App Store Guidelines (§3.1.1, §3.1.2, §3.2.2)
- Não viole Google Play Developer Policy (Real-Money Gambling, IAP)
- Não transforme OmniCoins em moeda com valor monetário real
- Não exija processamento de pagamento dentro do app
- Preserve a GAMIFICATION_POLICY.md integralmente

### 2. Modelo Definido: Licenciamento de Créditos Digitais para Assessorias

O modelo é **B2B SaaS** (Business-to-Business Software as a Service).

A plataforma vende **pacotes de créditos digitais** diretamente para assessorias esportivas.
Esses créditos são uma **licença de uso de software**, não uma moeda virtual ao consumidor.

#### 2.1 O que É vendido

| Aspecto | Valor |
|---------|-------|
| Produto | Pacotes de créditos digitais (OmniCoins) para assessorias |
| Natureza jurídica | Licença de software / crédito de uso de plataforma |
| Comprador | Assessoria esportiva (CNPJ / entidade jurídica) |
| Canal de venda | **Externo ao app** — portal web administrativo, contato direto, contrato B2B |
| Processamento de pagamento | **Externo ao app** — Pix, boleto, transferência, gateway web |
| Nota fiscal | Emitida pela plataforma para a assessoria (serviço de software) |

#### 2.2 O que NÃO é vendido

| Aspecto | Regra |
|---------|-------|
| In-App Purchase (IAP) | **NENHUM** — o app não vende nada dentro do app |
| Venda ao consumidor final (atleta) | **PROIBIDA** — atletas nunca compram créditos |
| Moeda com valor monetário | **INEXISTENTE** — OmniCoins são unidade de progresso |
| Resgate / cashout | **PROIBIDO** — créditos nunca são convertidos em dinheiro |
| Transferência P2P | **PROIBIDA** — créditos não saem da conta do usuário |

#### 2.3 Fluxo Completo

```
EXTERNO AO APP (não visível ao usuário)
─────────────────────────────────────────
1. Assessoria contrata pacote via portal web ou contato direto
2. Pagamento processado FORA do app (Pix/boleto/gateway web)
3. Plataforma credita coaching_token_inventory para o grupo
   (via admin panel ou batch script — NUNCA via app)

DENTRO DO APP (visível ao usuário)
─────────────────────────────────────────
4. Staff da assessoria vê estoque de créditos no dashboard
5. Staff distribui créditos a atletas via QR Code
   (token-create-intent → token-consume-intent)
6. Atleta usa créditos para:
   - Participar de desafios (inscrição)
   - Desbloquear customizações visuais
7. Créditos circulam APENAS dentro da assessoria
8. Troca de assessoria = créditos não utilizados são perdidos
```

### 3. Por que este modelo é Loja-Safe

#### 3.1 Apple App Store

| Guideline | Requisito | Status |
|-----------|-----------|:------:|
| **3.1.1 In-App Purchase** | Moedas vendidas IN-APP devem usar IAP | ✅ N/A — nenhuma venda ocorre dentro do app |
| **3.1.1 (exclusão B2B)** | Apps B2B podem vender fora da App Store se a transação é entre empresas | ✅ Venda é B2B (plataforma → assessoria) |
| **3.1.3(a) Reader apps** | Conteúdo comprado externamente pode ser acessado no app | ✅ Créditos comprados externamente são usados no app |
| **3.1.2(a) Gambling** | Sem gambling | ✅ Sem apostas, sem azar |
| **3.2.2(ii) Contests** | Sem prêmios monetários | ✅ Recompensas são apenas créditos internos |

**Justificativa chave:** A Apple **não exige IAP** para transações B2B que ocorrem fora do app
entre entidades comerciais. O modelo é análogo a plataformas SaaS corporativas que vendem
licenças via web e os usuários acessam o serviço no app.

#### 3.2 Google Play Store

| Policy | Requisito | Status |
|--------|-----------|:------:|
| **Payments Policy** | Bens digitais vendidos no app devem usar Google Play Billing | ✅ N/A — nenhuma venda ocorre no app |
| **Real-Money Gambling** | Sem gambling | ✅ Sem apostas |
| **Misleading Claims** | Não prometer recompensas monetárias | ✅ Créditos não têm valor monetário |

#### 3.3 Declarações para Review (se questionado)

**Para Apple:**

> "The app does not sell any digital goods or currency to consumers.
> OmniCoins are an internal progress unit earned through physical activity.
> The app serves sports coaching organizations (assessorias) who purchase
> platform licenses through our external B2B portal. No In-App Purchases
> exist because no consumer-facing transactions occur within the app."

**Para Google:**

> "The app does not process any payments or sell digital goods. OmniCoins
> are a gamification progress metric, not a purchasable currency. Our
> revenue model is B2B SaaS — sports coaching organizations purchase
> platform access externally. The app simply provides the software service."

### 4. O que o App NÃO faz (invariantes de compliance)

| Invariante | Motivo |
|------------|--------|
| App NUNCA mostra preços em dinheiro | Eliminaria a separação entre "crédito" e "moeda" |
| App NUNCA tem botão "Comprar" | Não há transação financeira dentro do app |
| App NUNCA processa pagamento | Pagamento é exclusivamente externo (web, Pix, boleto) |
| App NUNCA menciona "venda", "compra" ou "preço" | Preserva natureza não-monetária dos créditos |
| App NUNCA mostra valores em R$, USD ou qualquer moeda | Eliminaria a separação legal |
| App NUNCA permite que atletas adquiram créditos | Apenas assessoria recebe créditos da plataforma |
| App NUNCA permite transferência de créditos entre assessorias | Cada grupo é um silo independente |

### 5. Terminologia no App (Reforço da GAMIFICATION_POLICY §5)

| No app | Significado real |
|--------|------------------|
| "OmniCoins" ou "créditos" | Unidade de progresso in-app |
| "Estoque" | coaching_token_inventory.available_tokens |
| "Distribuir" | Staff entrega créditos ao atleta via QR |
| "Inscrição" | entry_fee_coins de um desafio (não "taxa") |
| "Recompensa" | Coins ganhos por mérito esportivo |

**Termos PROIBIDOS adicionais (Phase 21):**

| Termo | Motivo |
|-------|--------|
| comprar / buy / purchase (em UI) | Implica transação monetária ao consumidor |
| preço / price / pricing | Implica valor monetário |
| R$ / USD / € / qualquer símbolo monetário | Mostra valor real |
| fatura / invoice / billing | Jargão financeiro |
| plano / subscription / assinatura | Implica IAP |
| upgrade / premium (para créditos) | Implica tier pago |

### 6. Relação com o Ecossistema Existente

| Componente existente | Impacto da DECISAO 046 |
|---------------------|------------------------|
| `coaching_token_inventory` | Continua como está — alimentado externamente pelo admin |
| `token-create-intent` / `token-consume-intent` | Sem alteração — são operações in-app de distribuição |
| `coin_ledger` | Sem alteração — registro append-only de todas as movimentações |
| `clearing_cases` / clearing flow | Sem alteração — compensação entre assessorias é in-app |
| `GAMIFICATION_POLICY.md` | **100% preservada** — nenhum princípio alterado |
| `DECISAO 038` (Assessoria ecosystem) | **Reforçada** — a assessoria é o cliente pagante |
| `DECISAO 016` (Moeda loja-safe) | **Complementada** — OmniCoins permanecem não-monetários ao consumidor |

### 7. Alternativas rejeitadas

| Opção | Rejeitada por |
|-------|---------------|
| IAP para vender OmniCoins a atletas | Violaria GAMIFICATION_POLICY §2; criaria valor monetário; exigiria 30% fee Apple/Google |
| Subscription mensal para atletas | Implica IAP; atleta é usuário final, não cliente pagante |
| Anúncios rewarded | Incentivo não-atlético; degrada UX; violaria princípio fundamental |
| Freemium com tier premium dentro do app | Exigiria IAP; complicaria compliance |
| Assessoria vende via app (intermediação) | Plataforma viraria processador de pagamento; risco regulatório |
| Mostrar preços no app para assessorias | Quebraria fronteira "app sem transação financeira" |

### 8. Riscos aceitos

| Risco | Probabilidade | Mitigação |
|-------|:------------:|-----------|
| Apple questiona o modelo | Baixa | Declaração preparada (§3.3); modelo é análogo a SaaS corporativo |
| Google questiona o modelo | Baixa | Nenhuma transação no app; declaração preparada |
| Assessoria tenta revender créditos | Média | Créditos são siloados por grupo; sem transferência cross-grupo |
| Atleta confunde créditos com dinheiro | Média | Microcopy consistente; nunca mostrar valores monetários |
| Modelo B2B exige escala de assessorias | Alta | Onboarding assistido; parcerias piloto (conforme DECISAO 038 §10) |

---

## DECISAO 047 — Stack e Estratégia do Billing Portal Web (Phase 30)

**Data:** 2026-02-21
**Sprint:** 30.1.0
**Status:** DECIDIDO
**Impacto:** Alto — define a stack tecnológica e os limites do portal web B2B

### 1. Contexto

DECISAO 046 (§2.1, §2.3) estabelece que a venda de créditos às assessorias ocorre
**exclusivamente fora do app**, via "portal web administrativo, contato direto, contrato B2B".
A monetização depende da existência desse portal. Até agora, nenhuma stack foi definida.

O monorepo `project-running/` segue o padrão de sibling folders independentes:

```
project-running/
├── omni_runner/    # Flutter app (Dart)
├── watch/          # Apple Watch (Swift) + WearOS (Kotlin)
├── supabase/       # Backend (Postgres + Edge Functions)
├── docs/           # Documentação do projeto
├── contracts/      # API contracts
└── portal/         # ← NOVO: Billing Portal Web
```

### 2. Decisão

#### 2.1 Stack

| Camada | Tecnologia | Justificativa |
|--------|-----------|---------------|
| Framework | **Next.js 14+ (App Router)** | SSR/SSG para SEO, API Routes para webhooks, React Server Components para performance |
| Linguagem | **TypeScript** | Consistência com Edge Functions (Deno/TS); type safety |
| UI | **Tailwind CSS + shadcn/ui** | Componentes acessíveis, design system rápido, sem vendor lock-in |
| Auth | **Supabase Auth (SSR)** | Mesmo backend, mesmo auth; `@supabase/ssr` para cookies server-side |
| DB | **Supabase (existente)** | Reutiliza 100% do schema Postgres; RLS para isolamento por grupo |
| Deploy | **Vercel** | Deploy zero-config para Next.js; preview deploys por branch; edge functions |
| Domínio | **`portal.omnirunner.app`** | Subdomínio do domínio principal; certificado wildcard |

#### 2.2 Localização no Monorepo

```
project-running/portal/
├── src/
│   ├── app/                # Next.js App Router pages
│   │   ├── (auth)/         # Login / recover password
│   │   ├── dashboard/      # Home do staff
│   │   ├── credits/        # Estoque + histórico de créditos
│   │   ├── billing/        # Faturas + contratos (admin plataforma)
│   │   └── api/            # API Routes (webhooks de pagamento)
│   ├── components/         # React components (shadcn/ui)
│   ├── lib/                # Helpers, Supabase client, types
│   └── middleware.ts       # Auth guard (redirect se não logado)
├── public/                 # Assets estáticos
├── tailwind.config.ts
├── next.config.ts
├── package.json
├── tsconfig.json
└── .env.local.example
```

#### 2.3 Escopo do Portal (o que faz vs o que NÃO faz)

| O portal FAZ | O portal NÃO faz |
|-------------|-------------------|
| Login de staff (admin_master/professor) via Supabase Auth | Registro de atletas |
| Visualizar estoque de créditos (`coaching_token_inventory`) | Criar desafios ou campeonatos |
| Visualizar histórico de alocações (`institution_credit_purchases`) | Distribuir créditos (isso é no app via QR) |
| Solicitar novos créditos (formulário → email/webhook) | Processar pagamento (externo: Pix/boleto) |
| Visualizar atletas da assessoria (`coaching_members`) | Alterar progressão de atletas |
| Relatórios de engajamento (sessions, retention) | Funcionalidades sociais |
| Download de faturas/NF-e (PDF estático) | Qualquer operação de gamificação |

#### 2.4 Autenticação

O portal reutiliza **Supabase Auth** com o mesmo projeto:

1. Staff faz login com email/senha (ou Google/Apple se já tem conta)
2. `middleware.ts` verifica sessão via `@supabase/ssr`
3. Queries usam RLS do user logado (mesmas políticas do app)
4. Apenas `admin_master` e `professor` veem o portal; atletas recebem 403

#### 2.5 Relação com o App

| Aspecto | Portal Web | App Flutter |
|---------|-----------|-------------|
| Público | Staff da assessoria | Atletas + Staff |
| Finalidade | Gestão B2B, créditos, faturamento | Treino, gamificação, social |
| Auth | Supabase Auth (SSR, cookies) | Supabase Auth (JWT, mobile) |
| DB | Mesmo Supabase project | Mesmo Supabase project + Isar local |
| Vocabulário | Pode usar "faturamento", "contrato" | NUNCA usa termos monetários |

**Importante:** O portal web é um produto **separado do app**. Ele pode usar termos como
"faturamento", "contrato", "plano" porque é uma interface B2B para empresas, não visível
ao consumidor final (atleta). Os termos proibidos da GAMIFICATION_POLICY §5 se aplicam
**apenas ao app mobile**, não ao portal web.

### 3. Justificativa da Escolha (Next.js)

| Alternativa | Rejeitada por |
|-------------|--------------|
| Flutter Web | Bundle size excessivo para dashboard simples; SEO ruim; overkill para forms e tabelas |
| Vite + React SPA | Sem SSR; auth mais complexa (JWT em localStorage); sem API routes nativas |
| Remix | Excelente mas menor ecossistema de componentes; equipe já familiarizada com Next.js pattern |
| SvelteKit | Menor pool de desenvolvedores; Supabase SDK melhor documentado para React |
| PHP/Laravel | Stack completamente diferente do projeto; sem benefício para o caso |

### 4. Estratégia de Deploy

| Aspecto | Valor |
|---------|-------|
| Plataforma | Vercel (free tier suficiente para MVP) |
| Branch strategy | `main` → produção, PRs → preview deploys |
| CI | Vercel auto-build + `next lint` + `tsc --noEmit` |
| Env vars | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` |
| Domínio | `portal.omnirunner.app` (CNAME para Vercel) |
| SSL | Automático via Vercel + Let's Encrypt |

### 5. Limites e Invariantes

| # | Invariante |
|---|-----------|
| P1 | Portal é **read-mostly** — escrita limitada a formulários de solicitação |
| P2 | Portal **nunca** credita `coaching_token_inventory` diretamente — isso requer admin manual ou RPC `fn_credit_institution` |
| P3 | Portal reutiliza **100% do schema existente** — nenhuma tabela nova para o portal |
| P4 | Portal **não processa pagamento** — apenas exibe histórico e formulário de contato/solicitação |
| P5 | Portal é **independente do app** — pode ser deployado, versionado e operado separadamente |
| P6 | Portal respeita **RLS existente** — nenhuma query bypassa segurança |
| P7 | Pasta `portal/` é sibling de `omni_runner/`, seguindo o padrão de `watch/` |

### 6. Roadmap do Portal (fases futuras)

| Fase | Escopo |
|------|--------|
| 30.1 | Stack decision + scaffold Next.js (esta decisão) |
| 30.2 | Auth + middleware + dashboard shell |
| 30.3 | Tela de créditos (estoque + histórico) |
| 30.4 | Tela de atletas (lista, engajamento) |
| 30.5 | Formulário de solicitação de créditos (→ email/webhook) |
| 30.6 | Relatórios exportáveis (PDF/CSV) |
| 30.7+ | Integração com gateway de pagamento (Stripe/PagSeguro) se escala justificar |

---

## DECISAO 048 — Billing Portal Auth Model (Staff-Only Access)

**Data:** 2026-02-21
**Sprint:** 30.1.1
**Status:** DECIDIDO
**Impacto:** Alto — define quem pode acessar o portal e o que cada role pode ver

### 1. Contexto

O Billing Portal (DECISAO 047) é uma interface web B2B para staff de assessorias.
O sistema de roles já existe em `coaching_members`:

```
admin_master  — dono/fundador da assessoria (1 por grupo)
professor     — treinador com permissões de gestão
assistente    — apoio operacional, permissões limitadas
atleta        — consumidor final (NUNCA acessa o portal)
```

O portal precisa:
- Impedir acesso de atletas (e usuários sem assessoria)
- Identificar o `group_id` correto para queries RLS
- Diferenciar permissões por role (admin_master vs professor vs assistente)
- Suportar staff que pertence a múltiplos grupos (possível pelo schema)

### 2. Modelo de Acesso

#### 2.1 Quem pode acessar

| Role | Acessa portal? | Motivo |
|------|:--------------:|--------|
| `admin_master` | Sim | Dono da assessoria; acesso total |
| `professor` | Sim | Treinador; acesso de gestão (sem billing) |
| `assistente` | Sim | Apoio operacional; acesso limitado (somente leitura) |
| `atleta` | **Nunca** | Consumidor final; não é parte do público B2B |
| Sem assessoria | **Nunca** | Sem `coaching_members` row com role staff = sem acesso |
| Anônimo | **Nunca** | Sem Supabase Auth session = redirect para login |

#### 2.2 Como o portal identifica o group_id

O portal **não usa** `profiles.active_coaching_group_id` porque:
- Esse campo é para atletas (indica sua assessoria ativa)
- Staff pode ser `admin_master` de uma assessoria e `professor` de outra
- Staff não necessariamente tem `active_coaching_group_id` preenchido

Em vez disso, o portal:

1. **No login**, consulta `coaching_members` para o `auth.uid()`:

```sql
SELECT cm.group_id, cm.role, cg.name AS group_name
FROM coaching_members cm
JOIN coaching_groups cg ON cg.id = cm.group_id
WHERE cm.user_id = auth.uid()
  AND cm.role IN ('admin_master', 'professor', 'assistente')
ORDER BY cm.role = 'admin_master' DESC, cg.name ASC;
```

2. **Se 0 resultados** → usuário não é staff → redirect para tela de erro "Sem acesso"
3. **Se 1 resultado** → auto-seleciona o grupo → redireciona para dashboard
4. **Se N resultados** → mostra "Selecione sua assessoria" (group picker)

O `group_id` selecionado é armazenado na **sessão do portal** (cookie httpOnly)
e usado em todas as queries subsequentes. Troca de grupo = re-seleção no header.

#### 2.3 RLS Existente (sem alteração)

O portal usa **Supabase Auth SSR** com o JWT do usuário. Todas as queries
passam pelo RLS existente. Nenhuma política precisa ser criada ou alterada:

| Tabela | Policy existente | Quem pode ler |
|--------|-----------------|---------------|
| `coaching_groups` | `coaching_groups_member_read` | Qualquer membro do grupo |
| `coaching_members` | `coaching_members_group_read` | Qualquer membro do grupo |
| `coaching_token_inventory` | `token_inventory_staff_read` | `admin_master`, `professor`, `assistente` |
| `institution_credit_purchases` | `icp_admin_master_read` | **Apenas `admin_master`** |
| `coaching_invites` | `coaching_invites_read` | `admin_master`, `professor`, `assistente` |
| `sessions` | `sessions_own_read` | Próprio (portal consulta via service_role para relatórios de grupo) |
| `coach_insights` | `coach_reads_insights` | `admin_master`, `professor`, `assistente` |
| `athlete_baselines` | `baselines_read` | `admin_master`, `professor`, `assistente` |
| `athlete_trends` | `trends_read` | `admin_master`, `professor`, `assistente` |

**Nota sobre `sessions`:** O portal precisa ler sessões de atletas do grupo para
relatórios de engajamento. Como a RLS de `sessions` é `auth.uid() = user_id`,
relatórios que agregam dados de múltiplos atletas devem usar uma **API Route**
(Next.js server-side) com `service_role` key + filtro por `group_id` validado.

### 3. Matriz de Permissões por Tela

```
                          admin_master    professor    assistente
                          ────────────    ─────────    ──────────
Dashboard                     ✅              ✅           ✅
  └ KPIs gerais               ✅              ✅           ✅

Créditos
  ├ Estoque atual             ✅              ✅           ✅
  ├ Histórico alocações       ✅              ❌           ❌
  └ Solicitar créditos        ✅              ❌           ❌

Atletas
  ├ Lista de atletas          ✅              ✅           ✅
  ├ Detalhe do atleta         ✅              ✅           ✅
  └ Remover atleta            ✅              ❌           ❌

Engajamento
  ├ DAU / WAU                 ✅              ✅           ✅
  ├ Retenção semanal          ✅              ✅           ✅
  ├ Insights do coach         ✅              ✅           ✅
  └ Exportar relatório        ✅              ✅           ❌

Configurações
  ├ Dados da assessoria       ✅              ❌           ❌
  ├ Invite code               ✅              ✅           ❌
  └ Gerenciar staff           ✅              ❌           ❌

Group Picker (multi-grupo)    ✅              ✅           ✅
```

**Legenda:**
- ✅ = visível e acessível
- ❌ = não visível (rota protegida; se acessada diretamente, retorna 403)

### 4. Implementação no Next.js Middleware

```
middleware.ts flow:
  1. Verifica Supabase session (cookie)
     → Sem session → redirect /login
  2. Verifica staff membership (cache 5min em cookie)
     → Sem staff role → redirect /no-access
  3. Verifica group_id na session
     → Sem group_id + múltiplos grupos → redirect /select-group
     → Sem group_id + 1 grupo → auto-set + continue
  4. Verifica role vs rota
     → Role insuficiente → 403 Forbidden
  5. Continue → renderiza página
```

### 5. Proteção por Role nas Rotas

| Rota | Roles permitidas |
|------|-----------------|
| `/dashboard` | `admin_master`, `professor`, `assistente` |
| `/credits` | `admin_master`, `professor`, `assistente` |
| `/credits/history` | `admin_master` |
| `/credits/request` | `admin_master` |
| `/athletes` | `admin_master`, `professor`, `assistente` |
| `/athletes/[id]` | `admin_master`, `professor`, `assistente` |
| `/athletes/[id]/remove` | `admin_master` |
| `/engagement` | `admin_master`, `professor`, `assistente` |
| `/engagement/export` | `admin_master`, `professor` |
| `/settings` | `admin_master` |
| `/settings/invite` | `admin_master`, `professor` |
| `/settings/staff` | `admin_master` |
| `/select-group` | `admin_master`, `professor`, `assistente` |

### 6. Invariantes

| # | Invariante |
|---|-----------|
| A1 | Atletas **NUNCA** acessam o portal — middleware rejeita antes de qualquer renderização |
| A2 | Todas as queries RLS usam o JWT do usuário — portal nunca bypassa segurança do Supabase |
| A3 | Exceção: relatórios de engajamento (sessions de atletas) usam API Route server-side com `service_role` + validação de membership |
| A4 | `institution_credit_purchases` é visível **apenas para admin_master** — enforced por RLS existente (`icp_admin_master_read`) |
| A5 | O `group_id` ativo é armazenado em cookie httpOnly — nunca em localStorage ou URL exposta |
| A6 | Troca de grupo é instantânea (re-seleciona no header) — sem necessidade de re-login |
| A7 | Staff sem nenhuma `coaching_members` row com role staff = sem acesso, mesmo com user_role='ASSESSORIA_STAFF' em profiles |
| A8 | Zero tabelas novas — auth model reutiliza 100% do schema existente |

---

## DECISAO 049 — Payment Gateway: Stripe (primary) + Pix via Stripe BR

**Data:** 2026-02-21
**Sprint:** 31.1.0
**Status:** DECIDIDO
**Impacto:** Alto — define como o portal processa pagamentos das assessorias

### 1. Contexto

DECISAO 046 estabelece que pagamentos são processados **exclusivamente fora do app**,
via portal web (DECISAO 047). O billing schema (Phase 30.2.0) já possui
`billing_purchases` com `payment_method`, `payment_reference` e lifecycle
`pending → paid → fulfilled`.

O mercado primário é **Brasil** (assessorias esportivas). Requisitos:

- **Pix** — método dominante B2B no Brasil; instantâneo; sem custo para o pagador
- **Cartão de crédito** — necessário para parcelamento e conveniência
- **Boleto bancário** — necessário para assessorias que operam via fluxo de caixa programado
- **Webhooks** — essencial para atualizar `billing_purchases.status` automaticamente
- **Expansão futura** — possibilidade de clientes fora do Brasil

### 2. Decisão: Stripe como Gateway Único

| Aspecto | Valor |
|---------|-------|
| Gateway primário | **Stripe** |
| Pix | **Stripe Pix** (disponível desde 2022 para contas BR) |
| Cartão de crédito | **Stripe Checkout / Payment Intents** |
| Boleto | **Stripe Boleto** (disponível para contas BR) |
| Moeda primária | BRL |
| Moedas futuras | USD, EUR (ativação sob demanda, sem mudança de código) |
| SDK server-side | `stripe` (Node.js — usado nas API Routes do Next.js) |
| SDK client-side | **Nenhum** — Stripe Checkout (hosted page) elimina PCI scope |
| Webhooks | `POST /api/webhooks/stripe` no portal Next.js |

### 3. Justificativa

#### 3.1 Por que Stripe (e não Mercado Pago ou outro)

| Critério | Stripe | Mercado Pago | PagSeguro | Asaas |
|----------|:------:|:------------:|:---------:|:-----:|
| Pix | Sim | Sim | Sim | Sim |
| Boleto | Sim | Sim | Sim | Sim |
| Cartão (intl) | Sim | Parcial | Parcial | Não |
| Webhooks confiáveis | Excelente | Bom | Regular | Bom |
| Documentação | Excelente | Boa | Regular | Boa |
| Multi-moeda (futuro) | Nativo | Não | Não | Não |
| Next.js/Vercel ecosystem | Excelente | Sem SDK oficial | Sem SDK oficial | Sem SDK oficial |
| Stripe Checkout (hosted) | Sim | N/A | N/A | N/A |
| Dashboard de disputas | Sim | Sim | Sim | Parcial |
| NF-e / fiscal | Via Stripe Tax (beta BR) | Manual | Manual | Manual |
| Custo Pix | 0,8% | 0,5% | 0,99% | 0,49% |
| Custo cartão | 3,99% + R$0,39 | 4,99% | 4,99% | 3,49% |

**Decisão:** Stripe é a melhor opção por:
1. **Único gateway para Pix + boleto + cartão** — sem necessidade de integrar dois providers
2. **Stripe Checkout** — redirect para página hospedada pelo Stripe; zero PCI scope; zero form de cartão no portal
3. **Webhooks de primeira classe** — com signature verification, retry automático, e event types granulares
4. **Multi-moeda nativo** — quando houver assessorias fora do BR, basta ativar no dashboard
5. **Ecosystem Next.js** — `stripe` npm package oficial; exemplos oficiais com Vercel

#### 3.2 Por que NÃO dual-provider (Stripe + Mercado Pago)

| Argumento | Contra-argumento |
|-----------|-----------------|
| "MP tem Pix mais barato" | Diferença de 0,3% não justifica manter dois gateways, dois webhooks, dois dashboards |
| "MP é mais popular no BR" | Stripe BR está maduro desde 2022; assessorias são B2B (não consumidores finais no marketplace) |
| "Redundância" | Volume atual não justifica; complexidade operacional dobrada |

**Revisão futura:** Se Stripe Pix se mostrar caro em escala (>R$50k/mês), reavaliar adição de Asaas ou MP como segundo provider para Pix only.

### 4. Fluxo de Pagamento

```
Portal (admin_master)                        Stripe                    Supabase
────────────────────                        ──────                    ────────
1. Seleciona pacote
   POST /api/checkout
   → cria billing_purchase (pending)
   → cria Stripe Checkout Session         ──→ Checkout Session
   ← redirect URL                         ←── session.url

2. Redirect para Stripe Checkout          ──→ Stripe hosted page
   (Pix QR / cartão / boleto)                 (zero PCI no portal)

3. Pagamento confirmado                        webhook ──→
                                          POST /api/webhooks/stripe
                                               │
4. Webhook handler:                            │
   a. Verifica signature                       │
   b. UPDATE billing_purchase (paid)           ├──→ billing_purchases.status = 'paid'
   c. INSERT billing_event (payment_confirmed) ├──→ billing_events
   d. fn_fulfill_purchase (paid → fulfilled)   ├──→ fn_credit_institution
                                               │       └→ coaching_token_inventory +
                                               │       └→ institution_credit_purchases
   e. INSERT billing_event (fulfilled)         └──→ billing_events

5. admin_master vê créditos no portal + app
```

### 5. Mapeamento Stripe → billing_purchases

| billing_purchases column | Stripe source |
|--------------------------|--------------|
| `status = 'pending'` | Checkout Session criada |
| `status = 'paid'` | `checkout.session.completed` webhook (payment_status = 'paid') |
| `status = 'fulfilled'` | Após `fn_fulfill_purchase` (automático no webhook) |
| `status = 'cancelled'` | `checkout.session.expired` ou manual |
| `payment_method` | `session.payment_method_types[0]` ('pix', 'boleto', 'card') |
| `payment_reference` | `session.payment_intent` (Stripe PaymentIntent ID) |
| `invoice_url` | `session.invoice` → Invoice PDF URL (se aplicável) |

### 6. Webhooks Consumidos

| Stripe Event | Ação no Portal |
|-------------|----------------|
| `checkout.session.completed` | `pending → paid → fulfilled` (full pipeline) |
| `checkout.session.expired` | `pending → cancelled` |
| `charge.refunded` | `fulfilled → billing_event(refunded)` + alerta admin plataforma |
| `charge.dispute.created` | billing_event(note_added) + alerta admin plataforma |

### 7. Variáveis de Ambiente (Portal)

| Variável | Onde |
|----------|------|
| `STRIPE_SECRET_KEY` | Vercel env (server-only) |
| `STRIPE_PUBLISHABLE_KEY` | `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` (client-side, apenas para redirect) |
| `STRIPE_WEBHOOK_SECRET` | Vercel env (para verificar webhook signatures) |

### 8. Invariantes

| # | Invariante |
|---|-----------|
| G1 | Pagamento é processado **exclusivamente no portal web** — app mobile nunca toca Stripe |
| G2 | Portal **nunca** manipula dados de cartão — Stripe Checkout (hosted) elimina PCI scope |
| G3 | Créditos são alocados **apenas após webhook confirmado** — nunca otimisticamente |
| G4 | Toda transição de status passa por `billing_events` (audit trail) |
| G5 | `fn_fulfill_purchase` é chamado atomicamente — não há janela onde `paid` existe sem `fulfilled` |
| G6 | Webhook signature é **sempre verificada** — rejeitar requests sem `stripe-signature` válida |
| G7 | Stripe opera em **modo live** apenas em produção; **modo test** para dev/staging |
| G8 | Nenhum SDK Stripe é adicionado ao app Flutter — o app mobile desconhece a existência de Stripe |

### 9. Dependências npm (portal)

```
stripe                  # Server-side SDK (API Routes)
```

Nenhum `@stripe/stripe-js` ou `@stripe/react-stripe-js` necessário — Stripe Checkout
é redirect-based, não embedded.

### 10. Riscos

| Risco | Probabilidade | Mitigação |
|-------|:------------:|-----------|
| Stripe Pix indisponível temporariamente | Baixa | Boleto como fallback automático no Checkout Session |
| Webhook não entregue | Baixa | Stripe retry (até 3 dias); reconciliação manual via dashboard |
| Custo Pix sobe | Média | Reavaliar Asaas/MP como segundo provider para Pix only |
| Assessoria contesta no cartão (chargeback) | Média | Stripe Radar (antifraude nativo); contrato B2B assinado previamente |

---

## DECISAO 050 — Auto Top-Up: Recarga Automática de Créditos (Phase 35)

**Data:** 2026-02-21
**Sprint:** 35.1.0
**Status:** DECIDIDO
**Impacto:** Médio — adiciona recarga automática como opt-in para assessorias

### 1. Contexto

O fluxo de compra manual (DECISAO 049) funciona:
admin_master acessa o portal, seleciona pacote, paga via Stripe Checkout,
webhook processa e credita `coaching_token_inventory.available_tokens`.

Problema: assessorias ativas consomem créditos (desafios, campeonatos, badges) e
o inventário pode chegar a zero sem aviso, bloqueando operações. O admin_master
precisa monitorar manualmente e comprar antes que acabe.

### 2. Decisão: Auto Top-Up Opt-In

Auto top-up é **opt-in por assessoria**, configurado pelo admin_master no portal.
Quando o saldo cai abaixo de um threshold, o sistema inicia automaticamente uma
compra do pacote configurado usando o método de pagamento salvo no Stripe.

### 3. Regras

#### 3.1 Configuração (por grupo)

| Campo | Tipo | Default | Descrição |
|-------|------|---------|-----------|
| `auto_topup_enabled` | BOOLEAN | `false` | Ligado/desligado |
| `auto_topup_threshold` | INTEGER | `50` | Saldo mínimo que dispara recarga |
| `auto_topup_product_id` | UUID | — | Pacote a ser comprado (ref `billing_products`) |
| `auto_topup_max_per_month` | INTEGER | `3` | Máximo de recargas por mês (safety cap) |
| `stripe_customer_id` | TEXT | — | Stripe Customer ID (para payment method salvo) |
| `stripe_payment_method_id` | TEXT | — | Payment Method default (card only) |

#### 3.2 Threshold mínimo

- Valor mínimo configurável: **10 créditos** (abaixo disso não faz sentido)
- Valor máximo configurável: **10.000 créditos**
- Default sugerido no UI: **50 créditos**
- Admin pode ajustar livremente dentro do range

#### 3.3 Pacote de recarga

- O admin escolhe **um** pacote fixo da tabela `billing_products` (is_active=true)
- Pacotes atuais disponíveis:
  - Starter (500 OmniCoins — R$75)
  - Básico (1.500 — R$199)
  - Profissional (5.000 — R$599)
  - Premium (15.000 — R$1.499)
  - Enterprise (50.000 — R$3.999)
- Recomendação no UI: destacar o pacote com melhor custo-benefício (Premium)

#### 3.4 Frequência permitida

| Regra | Valor | Justificativa |
|-------|-------|---------------|
| Max recargas por mês | **3** (default, configurável 1–10) | Evita loops de cobrança |
| Cooldown entre recargas | **24 horas** | Impede cobrança duplicada por race condition |
| Janela de verificação | Na escrita de `available_tokens` (debit) | Trigger verifica após cada consumo |

#### 3.5 Como desligar

- **Portal → Equipe/Configurações:** Toggle "Recarga Automática" → OFF
- Efeito: `auto_topup_enabled = false`, imediato
- Não cancela cobranças já em processamento (pending no Stripe)
- Manter `stripe_payment_method_id` salvo para reativação rápida

#### 3.6 Fluxo de execução

```
Token consumido (debit)
    │
    ▼
available_tokens caiu abaixo do threshold?
    │ Não → fim
    │ Sim ↓
auto_topup_enabled = true?
    │ Não → fim
    │ Sim ↓
Já atingiu max_per_month neste mês?
    │ Sim → notificar admin (log + email futuro) → fim
    │ Não ↓
Última recarga automática < 24h atrás?
    │ Sim → skip (cooldown) → fim
    │ Não ↓
stripe_payment_method_id configurado?
    │ Não → notificar admin (sem método de pagamento) → fim
    │ Sim ↓
Criar billing_purchase (status=pending, source='auto_topup')
    │
    ▼
Stripe PaymentIntent.create (off-session, confirm=true)
    │
    ├─ Sucesso → webhook confirma → fn_fulfill_purchase → créditos alocados
    ├─ Falha → billing_purchase (cancelled), notificar admin
    └─ Requires action (3DS) → billing_purchase (cancelled), notificar admin
        (auto top-up só funciona com cards que não exigem 3DS off-session)
```

### 4. Armazenamento

Nova tabela: `billing_auto_topup_config` (1 row per group):

```sql
CREATE TABLE public.billing_auto_topup_config (
  group_id                  UUID PRIMARY KEY REFERENCES coaching_groups(id),
  enabled                   BOOLEAN NOT NULL DEFAULT false,
  threshold                 INTEGER NOT NULL DEFAULT 50
                            CHECK (threshold >= 10 AND threshold <= 10000),
  product_id                UUID NOT NULL REFERENCES billing_products(id),
  max_per_month             INTEGER NOT NULL DEFAULT 3
                            CHECK (max_per_month >= 1 AND max_per_month <= 10),
  stripe_customer_id        TEXT,
  stripe_payment_method_id  TEXT,
  last_topup_at             TIMESTAMPTZ,
  topups_this_month         INTEGER NOT NULL DEFAULT 0,
  topups_month_key          TEXT,   -- 'YYYY-MM' for reset logic
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

RLS: admin_master do grupo pode SELECT e UPDATE (via portal).
Mutations ao `stripe_*` fields: service_role only (Edge Functions).

### 5. Componentes a implementar (próximos micro-passos)

| # | Componente | Tipo |
|---|-----------|------|
| 35.2.0 | Migration: `billing_auto_topup_config` + RLS | SQL |
| 35.3.0 | Edge Function: `auto-topup-check` (invocada após debit) | Deno |
| 35.4.0 | Edge Function: `setup-auto-topup` (salva payment method via Stripe SetupIntent) | Deno |
| 35.5.0 | Portal: tela de configuração auto top-up em /settings | Next.js |
| 35.6.0 | Notificações: email/log quando top-up executa ou falha | Infra |

### 6. Invariantes

| ID | Invariante |
|----|-----------|
| AT-1 | Auto top-up NUNCA é ativado por default — sempre opt-in explícito |
| AT-2 | Cooldown de 24h impede cobranças duplicadas por race condition |
| AT-3 | Cap mensal (default 3) limita exposição financeira |
| AT-4 | Se 3DS é exigido pelo emissor, a recarga falha silenciosamente (notifica admin) |
| AT-5 | Desligar é imediato — próximo check de threshold ignora |
| AT-6 | `billing_purchase.source` distingue 'manual' de 'auto_topup' para auditoria |
| AT-7 | Zero impacto no app mobile — auto top-up é backend + portal only |
| AT-8 | Nenhum preço/pagamento aparece no app (GAMIFICATION_POLICY §5 mantida) |

### 7. Riscos

| Risco | Probabilidade | Mitigação |
|-------|:------------:|-----------|
| Card exige 3DS off-session | Média | Falha graceful + notificação; admin faz manual |
| Card expirado/recusado | Média | billing_purchase(cancelled) + notificação |
| Loop de cobrança (threshold mal configurado) | Baixa | max_per_month + cooldown 24h |
| Stripe indisponível | Baixa | Retry na próxima verificação de threshold |

### 8. Alternativas rejeitadas

| Alternativa | Motivo da rejeição |
|-------------|-------------------|
| Subscription (Stripe Billing) | Over-engineering: assessorias compram créditos por demanda, não mensalidade fixa |
| Threshold baseado em % do último pacote | Complexidade sem ganho; valor absoluto é mais intuitivo |
| Auto top-up via Pix/Boleto | Pix/boleto requerem ação do pagador; auto top-up só funciona com card salvo |
| Webhook trigger (em vez de debit trigger) | Debit é o momento real de consumo; webhook é assíncrono e pode perder timing |

---

## DECISAO 051 — Política de Reembolsos (Refunds)

**Data:** 2026-02-21
**Sprint:** 35.3.0
**Status:** APROVADA

### 1. Contexto

Assessorias compram pacotes de créditos (OmniCoins) via Stripe Checkout (cartão, Pix, boleto) ou via auto top-up (cartão off-session). Após o pagamento, os créditos são alocados atomicamente em `coaching_token_inventory`. A política de reembolsos precisa definir regras claras para evitar ambiguidade, abuso e inconsistência de saldo.

### 2. Quando pode pedir reembolso

| Cenário | Elegível | Prazo | Observação |
|---------|:--------:|-------|------------|
| Cobrança duplicada | Sim | 30 dias | Verificar via billing_events.stripe_event_id |
| Erro técnico (créditos não alocados) | Sim | 30 dias | Verificar billing_purchases.status ≠ 'fulfilled' |
| Compra acidental (manual) | Sim | 7 dias | Somente se créditos NÃO foram consumidos |
| Auto top-up não desejado | Sim | 7 dias | Somente se créditos NÃO foram consumidos; admin deve desativar auto top-up |
| Créditos parcialmente consumidos | Parcial | 7 dias | Reembolso proporcional ao saldo remanescente do pacote |
| Créditos totalmente consumidos | Não | — | Serviço já prestado; sem reembolso |
| Insatisfação com o serviço | Não | — | Créditos são unidades de uso, não contrato de resultado |
| Após 30 dias da compra | Não | — | Janela de reembolso expirada |

### 3. Impacto nos créditos

#### 3.1 Reembolso total

Quando o reembolso é total (`amount_refunded == price_cents`):

1. `billing_purchases.status` → `refunded` (novo status)
2. `coaching_token_inventory.available_tokens` -= `credits_amount` do pacote
3. Se `available_tokens` resultaria negativo → reembolso bloqueado até créditos serem devolvidos/consumo parar
4. `billing_events` → novo evento tipo `refunded` com metadata (amount, reason, approved_by)
5. Analytics → `billing_refund_processed`

#### 3.2 Reembolso parcial

Quando o reembolso é parcial (`amount_refunded < price_cents`):

1. `billing_purchases.status` permanece `fulfilled` (parcialmente reembolsado)
2. `billing_events` → evento `refunded` com metadata incluindo `partial: true`, `amount_refunded`, `credits_debited`
3. Créditos debitados = `floor(credits_amount * amount_refunded / price_cents)`
4. `coaching_token_inventory.available_tokens` -= créditos debitados
5. Mesma regra: bloqueado se resultaria em saldo negativo

#### 3.3 Invariantes de saldo

| ID | Invariante |
|----|-----------|
| RF-1 | `available_tokens` NUNCA fica negativo após reembolso |
| RF-2 | Todo reembolso debita créditos proporcionalmente |
| RF-3 | Reembolso sem débito de créditos é PROIBIDO (evita abuso: pedir refund e manter créditos) |
| RF-4 | Se créditos insuficientes para débito, reembolso fica pendente até resolução manual |

### 4. Quem aprova

| Ação | Aprovador | Método |
|------|-----------|--------|
| Solicitar reembolso | admin_master da assessoria | Portal → página de Faturamento (futuro) ou email suporte |
| Avaliar elegibilidade | Plataforma (equipe Omni Runner) | Verificação manual: consumo de créditos, prazo, tipo de compra |
| Executar reembolso no Stripe | Plataforma (equipe Omni Runner) | Stripe Dashboard → Refund (gera webhook `charge.refunded`) |
| Debitar créditos do inventário | Automático (webhook) | `handleChargeRefunded` → debita `coaching_token_inventory` |
| Aprovar reembolso parcial | Plataforma (equipe Omni Runner) | Cálculo proporcional + execução no Stripe |

#### 4.1 Fluxo de aprovação

```
Admin solicita reembolso (email/portal)
    │
    ▼
Plataforma verifica:
    ├── Prazo dentro da janela? (7d acidental, 30d duplicada/erro)
    ├── Créditos consumidos? (total, parcial, nenhum)
    └── Tipo de compra? (manual, auto_topup, duplicada)
    │
    ├─ Elegível total → Stripe Refund (full) → webhook → débito total
    ├─ Elegível parcial → Stripe Refund (partial) → webhook → débito proporcional
    └─ Não elegível → Resposta ao admin com justificativa
```

### 5. Tratamento técnico no webhook

O `handleChargeRefunded` atual apenas registra o evento. O fluxo completo (fase futura) inclui:

1. Receber `charge.refunded` do Stripe
2. Localizar `billing_purchases` via `payment_reference`
3. Calcular créditos a debitar (proporcional ao `amount_refunded`)
4. Verificar `available_tokens >= créditos a debitar` (RF-1)
5. Se saldo suficiente:
   - Debitar `coaching_token_inventory.available_tokens`
   - Atualizar `billing_purchases.status` → `refunded` (se total) ou manter `fulfilled` (se parcial)
   - Inserir `billing_events` com metadata completa
6. Se saldo insuficiente:
   - Inserir `billing_events` com `status: 'refund_blocked'`
   - Notificar plataforma para resolução manual

### 6. Status `refunded` em billing_purchases

Novo status a ser adicionado (migration futura):

```sql
-- Expandir CHECK constraint para incluir 'refunded'
ALTER TABLE public.billing_purchases
  DROP CONSTRAINT IF EXISTS billing_purchases_status_check;

ALTER TABLE public.billing_purchases
  ADD CONSTRAINT billing_purchases_status_check
  CHECK (status IN ('pending', 'paid', 'fulfilled', 'cancelled', 'refunded'));
```

### 7. Casos especiais

| Caso | Tratamento |
|------|------------|
| Reembolso de compra auto_topup | Mesmas regras; admin deve desativar auto top-up para evitar recompra imediata |
| Disputas (chargebacks) | Registradas como `note_added` em billing_events; plataforma contesta via Stripe Dashboard |
| Reembolso de compra com boleto | Stripe processa via conta bancária; prazo Stripe: 5-10 dias úteis |
| Reembolso de compra com Pix | Stripe processa instantaneamente para a conta de origem |

### 8. Limites e proteções

| Proteção | Valor | Justificativa |
|----------|-------|---------------|
| Prazo máximo (duplicada/erro) | 30 dias | Alinhado com política Stripe |
| Prazo máximo (acidental) | 7 dias | Incentiva uso rápido; limita exposição |
| Max reembolsos por grupo/mês | 3 | Evita abuso sistemático |
| Reembolso automático | Não implementado | Toda solicitação passa por verificação humana |
| Self-service refund no portal | Fase futura | Requer UI + validações automáticas |

### 9. Alternativas rejeitadas

| Alternativa | Motivo da rejeição |
|-------------|-------------------|
| Reembolso automático sem verificação | Risco de abuso (comprar, usar créditos parcialmente, pedir refund total) |
| Créditos como "store credit" em vez de refund | Não resolve o problema financeiro do cliente; Stripe suporta refunds nativamente |
| Sem política formal | Inconsistência no tratamento; risco legal |
| Refund sem débito de créditos | Abuso direto: cliente fica com dinheiro E créditos |

---

## DECISAO 052 — Limites Operacionais do Sistema

**Data:** 2026-02-21
**Sprint:** 35.4.0
**Status:** APROVADA

### 1. Contexto

Com billing, auto top-up, reembolsos, gamificação e distribuição de tokens em produção, o sistema precisa de limites operacionais formais para prevenir abuso, controlar custos e garantir estabilidade. Alguns limites já existem dispersos (DECISAO 044 caps de XP, DECISAO 050 auto top-up caps, GAMIFICATION_POLICY rate limiting). Esta decisão consolida e formaliza todos os limites num único documento de referência.

### 2. Créditos emitidos por dia (Token Issuance)

Limites sobre quantos OmniCoins podem ser distribuídos por grupo por dia.

| Limite | Valor | Escopo | Justificativa |
|--------|:-----:|--------|---------------|
| Tokens emitidos por grupo/dia (via staff) | **5.000** | `token-create-intent` ISSUE_TO_ATHLETE | Evita burn acidental de estoque |
| Tokens emitidos por intent individual | **100.000** | `MAX_AMOUNT` em token-create-intent | Já implementado — teto por operação |
| Auto top-up recargas/mês | **3** (config 1–10) | `billing_auto_topup_settings.max_per_month` | DECISAO 050 AT-3 |
| Auto top-up cooldown | **24 horas** | `last_triggered_at` check | DECISAO 050 AT-2 |
| Compras manuais/dia por admin | **10** | Rate limit `create-checkout-session` | 10 req/60s já implementado |

#### 2.1 Implementação: cap diário de emissão

O cap de 5.000 tokens/grupo/dia é enforced na Edge Function `token-create-intent`:

```
Antes de criar o intent:
  1. Contar SUM(amount) de token_intents
     WHERE group_id = ? AND type = 'ISSUE_TO_ATHLETE'
     AND status IN ('OPEN', 'CONSUMED')
     AND created_at >= início do dia UTC
  2. Se (total + amount_solicitado) > 5.000 → rejeitar
```

### 3. Resgates por dia (Token Burns / Consumption)

| Limite | Valor | Escopo | Justificativa |
|--------|:-----:|--------|---------------|
| Burns por grupo/dia | **5.000** | `token-create-intent` BURN_FROM_ATHLETE | Simétrico à emissão |
| Burns por atleta/dia | **500** | `token-consume-intent` por user_id | Protege atleta de staff malicioso |
| Sessões que geram Coins/dia | **10** | GAMIFICATION_POLICY §8 | Anti-farm, já implementado |
| XP por sessões/dia | **1.000** | DECISAO 044 §2 cap diário | Anti-farm, já implementado |
| XP por badges+missões/dia | **500** | DECISAO 044 §2 cap diário | Anti-farm, já implementado |

### 4. Desafios simultâneos

| Limite | Valor | Escopo | Justificativa |
|--------|:-----:|--------|---------------|
| Desafios ativos por atleta | **5** | Challenges com status 'accepted' por user | Evita sobrecarga de UX e exploits de Coins |
| Desafios pendentes (aguardando aceite) por atleta | **10** | Challenges com status 'pending' para target_user | Evita spam de convites |
| Desafios criados por atleta/dia | **20** | Rate limit em settle-challenge | Evita flood de desafios |
| Campeonatos ativos por grupo | **3** | `championships` com status 'active' por group | Foco e gestão viável |
| Participantes por campeonato | **200** | `championship_participants` count | Performance de leaderboard |

### 5. Limites de billing

| Limite | Valor | Escopo | Justificativa |
|--------|:-----:|--------|---------------|
| Checkout sessions/min por admin | **10** | Rate limit `create-checkout-session` | Já implementado |
| Portal sessions/min por admin | **10** | Rate limit `create-portal-session` | Já implementado |
| Refund requests abertas por purchase | **1** | UNIQUE partial index `idx_refund_requests_open_unique` | DECISAO 051, já implementado |
| Refund requests por grupo/mês | **3** | Count check na aprovação | DECISAO 051 §8 |
| Valor máximo por compra | **R$ 50.000** | Validação em `create-checkout-session` | Proteção contra erros de input |

### 6. Limites de API (Edge Functions)

| Edge Function | Rate Limit | Janela | Implementado |
|---------------|:----------:|:------:|:------------:|
| `verify-session` | 30 req | 60s | Sim |
| `submit-analytics` | 60 req | 60s | Sim |
| `compute-leaderboard` | 10 req | 60s | Sim |
| `settle-challenge` | 20 req | 60s | Sim |
| `evaluate-badges` | 20 req | 60s | Sim |
| `calculate-progression` | 20 req | 60s | Sim |
| `create-checkout-session` | 10 req | 60s | Sim |
| `create-portal-session` | 10 req | 60s | Sim |
| `token-create-intent` | 30 req | 60s | Sim |
| `token-consume-intent` | 30 req | 60s | Sim |
| `list-purchases` | 20 req | 60s | Sim |
| `auto-topup-check` | — | Service-role | N/A (server-to-server) |
| `auto-topup-cron` | — | Service-role | N/A (pg_cron) |
| `process-refund` | — | Service-role | N/A (platform team) |

### 7. Limites de storage e dados

| Recurso | Limite | Justificativa |
|---------|:------:|---------------|
| Membros por grupo (coaching_members) | **500** | Performance de queries RLS |
| Atletas por grupo | **300** | Capacidade operacional razoável |
| Staff por grupo | **20** | Limite prático de gestão |
| Billing events por purchase | **50** | Proteção contra loops |
| Product events por user/dia | **200** | Analytics sem flood |

### 8. Matriz de enforcement

| Nível | Mecanismo | Onde |
|-------|-----------|-----|
| **L1 — DB constraint** | CHECK, UNIQUE, FK | Migrations |
| **L2 — RLS policy** | SELECT/INSERT/UPDATE guards | Migrations |
| **L3 — Rate limit** | `increment_rate_limit` RPC | Edge Functions |
| **L4 — Business logic** | Count queries + reject | Edge Functions |
| **L5 — Monitoring** | product_events + logs | Analytics pipeline |

### 9. Limites ainda não implementados (roadmap)

| Limite | Tipo | Prioridade | Micro-passo sugerido |
|--------|------|:----------:|---------------------|
| Cap diário de emissão (5.000/grupo/dia) | L4 | Alta | Adicionar count check em token-create-intent |
| Burns por atleta/dia (500) | L4 | Alta | Adicionar count check em token-consume-intent |
| Desafios ativos por atleta (5) | L4 | Média | Adicionar count check em settle-challenge |
| Desafios pendentes por atleta (10) | L4 | Média | Adicionar count check em challenge creation |
| Campeonatos ativos por grupo (3) | L4 | Baixa | Adicionar count check em champ-create |
| Valor máximo por compra (R$ 50.000) | L4 | Baixa | Adicionar check em create-checkout-session |
| Membros por grupo (500) | L4 | Baixa | Adicionar count check em invite API |

### 10. Alternativas rejeitadas

| Alternativa | Motivo da rejeição |
|-------------|-------------------|
| Sem limites formais | Risco de abuso, custos imprevisíveis, instabilidade |
| Limites extremamente restritivos | Prejudica UX e operação legítima das assessorias |
| Limites dinâmicos baseados em plano | Premature optimization — todos no mesmo tier por agora |
| Rate limiting via API Gateway (nginx/cloudflare) | Supabase Edge Functions já têm rate limiting integrado via RPC |

---

## DECISAO 053 — Atleta Verificado: State Machine & Monetization Gate

**Data:** 2026-02-24
**Sprint:** 22.1.0
**Status:** CONGELADA

### Contexto

O sistema de gamificação permite desafios com `entry_fee_coins > 0` (stake). Sem um gate de verificação, qualquer usuário — inclusive recém-cadastrados ou com histórico de fraude — pode criar e participar de desafios com stake, expondo outros atletas a risco.

### Decisão

Implementar um sistema de "Atleta Verificado" com as seguintes regras **congeladas**:

1. **stake=0 sempre liberado** — qualquer usuário pode criar/participar de desafios gratuitos
2. **stake>0 exige `verification_status = 'VERIFIED'`** — enforçado no servidor (Edge Functions)
3. **ZERO override** — não existe e nunca será criado qualquer botão, endpoint, backdoor, ajuste manual ou "admin set verified"
4. **Server wins** — o app pode mostrar UX hints (pré-check), mas o servidor é a fonte de verdade para elegibilidade

### State Machine

```
UNVERIFIED → CALIBRATING → MONITORED → VERIFIED
                                         ↓
                                     DOWNGRADED
```

| Estado | Descrição | Pode stake>0? |
|---|---|---|
| UNVERIFIED | Novo usuário, sem corridas verificadas | NÃO |
| CALIBRATING | Tem corridas verificadas, acumulando histórico | NÃO |
| MONITORED | Atingiu threshold de calibração, sob observação | NÃO |
| VERIFIED | Provado confiável — trust_score >= 70, >= 15 sessões | SIM |
| DOWNGRADED | Era VERIFIED mas violações de integridade detectadas | NÃO |

### Tabela

`public.athlete_verification` (nova tabela dedicada, PK = user_id)

**Por que NÃO `profile_progress`?**
- `profile_progress` tem RLS `progress_public_read USING (true)` — qualquer user lê qualquer profile
- Verificação exige `own-read-only` (trust_score e flags são sensíveis)
- Bounded context distinto (ARCHITECTURE.md §12)

### Colunas

| Coluna | Tipo | Propósito |
|---|---|---|
| verification_status | TEXT (CHECK) | Estado na state machine |
| trust_score | INT (0..100) | Score composto: volume + consistência + distância + record limpo + longevidade |
| verified_at | TIMESTAMPTZ | Quando promovido a VERIFIED |
| last_eval_at | TIMESTAMPTZ | Última avaliação |
| verification_flags | TEXT[] | Sinais detectados |
| calibration_valid_runs | INT | Sessões válidas acumuladas |
| last_integrity_flag_at | TIMESTAMPTZ | Último flag negativo |

### Enforcement

| Camada | Mecanismo |
|---|---|
| DB RLS | SELECT own-only. ZERO UPDATE/INSERT/DELETE para user |
| RPC | `eval_athlete_verification` (SECURITY DEFINER) — único path de mutação |
| Helper | `is_user_verified(p_user_id)` — lookup rápido para EFs |
| Edge Functions | `challenge-create` e `challenge-join` chamam `is_user_verified` quando `entry_fee_coins > 0` |
| Flutter | UX gates (pré-check cosmético). Servidor decide |

### Alternativas rejeitadas

| Rejeitada | Motivo |
|---|---|
| Adicionar colunas em `profile_progress` | RLS `public_read` incompatível com own-read-only |
| Adicionar colunas em `profiles` | `profiles` tem `public_read` (mesmo problema) |
| Admin "set verified" manual | Viola regra de produto congelada — ZERO override |
| Verificação por email/documento | Over-engineering para MVP; run history é mais relevante para running app |
| Trust score visível para outros users | Gameable; info sensível deve ser own-read-only |

---

## DECISAO 054 — Verificação: Checklist MVP, Thresholds & Edge Function

**Data:** 2026-02-24
**Sprint:** VERIFIED-2 (22.1.1)
**Status:** CONCLUIDA

### Contexto
Sprint 1 criou a tabela e state machine mas os thresholds ficaram provisórios
(_verified_min_runs=15, _verified_min_score=70, volume=2pts/session). O app precisa
de um RPC read-only que retorne checklist booleans para exibir progresso. Avaliação
precisa ser disparada via Edge Function com user_id do JWT.

### Decisões

**Thresholds finalizados:**
- N (VERIFIED_MIN_RUNS) = **7** (sugestão de produto; viável para MVP de running app)
- Trust threshold (VERIFIED_MIN_SCORE) = **80**
- Fórmula recalibrada: volume=5pts/session (cap 35), consistency max 15, distance max 20, clean max 20, longevity max 10
- Exemplo: 7 corridas limpas × 3km avg (21km) = 35+15+14+20+0 = 84 → passa 80

**State machine simplificada:**
- 0 runs → UNVERIFIED
- 1..6 runs → CALIBRATING
- >= 7 + trust < 80 → MONITORED (oscilação ou distância curta)
- >= 7 + trust >= 80 + clean → VERIFIED
- >= 3 flags/30d → DOWNGRADED

**Checklist MVP (6 itens):**
| Item | Status MVP |
|---|---|
| identity_ok (selfie/liveness) | NULL — futuro, não bloqueia |
| permissions_ok (GPS/sensores) | NULL — client-side, server não rastreia |
| valid_runs_ok (>= 7 corridas) | BOOLEAN — avaliado |
| integrity_ok (0 flags graves 30d) | BOOLEAN — avaliado |
| baseline_ok (avg >= 1km + >= 3 sessions) | BOOLEAN — avaliado |
| trust_ok (trust_score >= 80) | BOOLEAN — avaliado |

**RPC `get_verification_state()`:**
- SECURITY DEFINER STABLE, usa auth.uid()
- Retorna: estado completo + 6 checklist bools + contagens + thresholds
- Read-only, auto-cria registro se ausente
- O app recebe `required_valid_runs` e `required_trust_score` (sem hardcodar thresholds)

**Edge Function `eval-athlete-verification`:**
- POST, JWT auth, user_id do JWT (NUNCA do client)
- Chama RPC `eval_athlete_verification(user.id)` → build checklist → return
- Idempotente: mesma data de sessões → mesmo resultado
- Rate limit: 10/60s

**Error codes padronizados:**
| Code | HTTP | Uso |
|---|---|---|
| ATHLETE_NOT_VERIFIED | 403 | stake>0 sem VERIFIED |
| VERIFICATION_EVAL_FAILED | 500 | Erro no RPC eval |
| SESSION_DATA_MISSING | 500 | Registro não encontrado |
| INTEGRITY_FLAGS_BLOCKING | 403 | Flags graves impedem avanço |
| AUTH_ERROR | 401 | JWT ausente/inválido |

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| trust_score >= 70 (threshold original) | Com N=7, formula original (2pts/session) atingia max 69; com formula recalibrada 80 é achievable e mais exigente |
| Checklist no Flutter com thresholds hardcoded | Server retorna thresholds via RPC; single source of truth |
| EF aceitar user_id no body | Violaria regra congelada — user_id SEMPRE do JWT |

---

## DECISAO 055 — Gate de Monetização: 3 Camadas de Enforcement

**Data:** 2026-02-24
**Sprint:** VERIFIED-3 (22.2.0)
**Status:** CONCLUIDA

### Contexto
O campo `challenges.entry_fee_coins` determina o stake de um desafio. Qualquer
valor > 0 exige `verification_status = 'VERIFIED'` tanto para criar quanto para
participar. As Edge Functions usam `service_role` que bypassa RLS, então RLS
sozinha é insuficiente.

### Decisão
Implementar 3 camadas independentes de enforcement:

1. **EF validation** (challenge-create, challenge-join): chama `is_user_verified()`
   ANTES do insert. Retorna 403 `ATHLETE_NOT_VERIFIED` com mensagem UX clara.

2. **RLS INSERT policy** (challenges): `challenges_insert_auth` atualizada para
   exigir `entry_fee_coins = 0 OR is_user_verified(auth.uid())`. Bloqueia acesso
   direto via Supabase client.

3. **DB triggers** (challenges + challenge_participants): `BEFORE INSERT/UPDATE`
   triggers que disparam MESMO para service_role. Última linha de defesa.
   Impossível burlar sem alterar o trigger no banco.

### Vetores de ataque bloqueados
- Criar com stake>0 sem VERIFIED → 3 camadas bloqueiam
- Criar com 0, UPDATE para >0 → trigger em `UPDATE OF entry_fee_coins` bloqueia
- Join em challenge com stake>0 → 2 camadas bloqueiam (EF + trigger)
- Acesso direto via client → RLS bloqueia
- Acesso via service_role → trigger bloqueia

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| Apenas RLS | service_role bypassa RLS — insuficiente |
| Apenas EF validation | Outro EF futuro poderia esquecer a validação |
| CHECK CONSTRAINT no challenges | Constraints não podem chamar functions que leem outras tabelas |
| Bloquear via app (Flutter) | App NUNCA é fonte de verdade para elegibilidade monetizada |

---

## DECISAO 056 — Integrity Flags: Dicionário Oficial & Pipeline Único

**Data:** 2026-02-24
**Sprint:** VERIFIED-4 (22.2.1)
**Status:** CONCLUIDA

### Contexto
O sistema tinha flag names inconsistentes entre server e client (ex: `SPEED_EXCEEDED`
vs `HIGH_SPEED`). Faltavam checks server-side (NO_MOTION, GPS gaps, time skew).
A avaliação de verificação (`eval_athlete_verification`) depende de `is_verified=false`
nas sessions — precisamos que os flags sejam consistentes e abrangentes.

### Decisão
1. Dicionário oficial em `_shared/integrity_flags.ts` (7 critical + 4 quality)
2. `verify-session` EF é o pipeline ÚNICO e autoritativo — sobrescreve flags do client
3. Classificação critical/quality para futura ponderação no trust_score
4. Legacy names mantidos no Flutter `InvalidatedRunCard` para backward compat
5. `VEHICLE_SUSPECTED` é client-only (server não recebe step cadence data)
6. `integrity_score` per-session é opcional/futuro (trust_score = aggregate)

### Flag names renomeados
| Antigo (server) | Novo (oficial) |
|---|---|
| `SPEED_EXCEEDED` | `SPEED_IMPOSSIBLE` |
| `TELEPORT_DETECTED` | `GPS_JUMP` (raw) + `TELEPORT` (accuracy-filtered) |

### Novos checks adicionados
| Flag | Check |
|---|---|
| `NO_MOTION_PATTERN` | Todos pontos dentro de 50m do centroide |
| `BACKGROUND_GPS_GAP` | Gap > 60s entre pontos consecutivos |
| `TIME_SKEW` | end <= start OU > 10% deltas negativos |

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| Renomear flags dos client detectors | Quebraria contratos internos do Flutter; server sobrescreve anyway |
| integrity_score per-session | Over-engineering; trust_score no athlete_verification agrega |
| VEHICLE check server-side | Server não recebe step data; mantido client-side |

---

## DECISAO 057 — Flutter UX: Jornada Atleta Verificado (Gate + Tela)

**Data:** 2026-02-24
**Status:** ACEITA
**Contexto:** Precisamos exibir ao usuário seu status de verificação e bloquear no app (UX) a criação/join de desafios com stake>0 para não-verificados. O server já bloqueia (EF + RLS + DB triggers); o Flutter adiciona camada UX.

### Decisão

1. **AthleteVerificationEntity** — domain entity imutável, parseia resposta de `get_verification_state()` e `eval-athlete-verification` EF. Checklist com 4 itens avaliáveis (validRunsOk, integrityOk, baselineOk, trustOk) + 2 futuros (identityOk, permissionsOk como nullable).

2. **VerificationBloc** — BLoC dedicado (não misturado com ChallengesBloc). Dois events: `LoadVerificationState` (RPC) e `RequestEvaluation` (EF). Mantém `_cached` para consulta síncrona no gate.

3. **AthleteVerificationScreen** — tela independente com status badge, progress bar, checklist detalhado ("faltam X corridas"), stats, botão "Reavaliar agora", seção explicativa.

4. **verification_gate.dart** — função `checkVerificationGate()` + modal bottom sheet. stake=0 → true. VERIFIED → true. Caso contrário → modal + false.

5. **ChallengeCreateScreen** — `_submit()` chama gate antes de despachar. VerificationBloc carregado eagerly.

6. **ChallengeDetailsScreen** — `_AcceptDeclineCard` convertido para StatefulWidget com VerificationBloc condicional (só se hasStake). `_onAccept()` chama gate.

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| Provider global de VerificationBloc | Over-engineering; poucos pontos de uso, melhor criar sob demanda |
| Bloquear no ChallengesBloc | Misturaria responsabilidades; gate é UX, não domain logic |
| Não mostrar tela de verificação | UX ruim; usuário precisa entender o que falta |
| Cache local (Isar) do verification state | Complexidade desnecessária; dado vem do server e muda a cada sessão |

---

## DECISAO 058 — Reavaliação Automática: Event-driven + Cron

**Data:** 2026-02-24
**Status:** ACEITA
**Contexto:** Precisamos que `eval_athlete_verification` rode automaticamente após cada sessão verificada e periodicamente para capturar edge cases (falhas, usuários em transição).

### Decisão

1. **Event-driven (pós-sync)**: Cadeia `SyncRepo._syncOne()` → `SyncService.verifySession()` → `verify-session` EF → `eval_athlete_verification` RPC (fire-and-forget). Cada sessão sincronizada trigger avaliação automaticamente.

2. **Fire-and-forget pattern**: O call ao RPC dentro de `verify-session` usa `.then()/.catch()` — a resposta do EF não espera a avaliação terminar. Falhas são logadas mas não bloqueiam o fluxo.

3. **Cron diário (03:00 UTC)**: `eval-verification-cron` EF via pg_cron. Reavalia até 100 candidatos: CALIBRATING/MONITORED/DOWNGRADED, flags recentes, não avaliados em 24h. Usa o mesmo `eval_athlete_verification` RPC.

4. **config.toml**: `[functions.eval-verification-cron]` com `verify_jwt = false` (auth via service_role key check no handler).

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| DB trigger no sessions (AFTER UPDATE is_verified) | Trigger chamando RPC complexo com múltiplos SELECTs é anti-pattern; risco de deadlock e performance |
| Supabase Database Webhook | Requer configuração externa, menos controle, overhead HTTP desnecessário para cada row |
| Client-side eval após sync | Depende do app estar online e bem-comportado; viola "server wins" |
| Cron a cada 5 minutos | Over-engineering; avaliação diária é suficiente dado que event-driven cobre o caso principal |
| Fila (pg_boss / queue) | Complexidade desnecessária para MVP; fire-and-forget + cron cobre todos cenários |

---

## DECISAO 059 — Portal: Observabilidade de Verificação sem Override

**Data:** 2026-02-24
**Status:** ACEITA
**Contexto:** Staff da assessoria precisa visualizar o status de verificação dos atletas. Deve ser somente leitura — sem possibilidade de alterar status manualmente.

### Decisão

1. **Página `/verification`** — Server Component que busca `coaching_members` + `athlete_verification` via service client (necessário para ler dados cross-user, já que RLS é own-read-only). Tabela com status, trust, corridas, flags, última avaliação.

2. **Botão "Reavaliar"** — Disponível apenas para `admin_master` e `professor`. Chama o mesmo `eval_athlete_verification` RPC usado pelo event-driven e cron. API route valida session + role + pertencimento ao grupo.

3. **Service client para leitura** — A tabela `athlete_verification` tem RLS `own-read-only`. O portal precisa ler dados de múltiplos atletas, então usa `createServiceClient()` (service_role) no server component. Seguro pois roda server-side (nunca exposto ao browser).

4. **Sem campo editável** — Nenhum input de status, trust ou flags. A página é puramente informacional. O botão "Reavaliar" executa as mesmas regras automatizadas.

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| RLS policy para staff ler verification | Complexidade desnecessária; service client no server component é seguro e mais simples |
| Botão disponível para assistente | Princípio do menor privilégio; assistentes veem dados mas não triggeram ações |
| Campo editável para "forçar VERIFIED" | Viola regra congelada: ZERO override admin |
| Página no Flutter (staff dashboard) | Portal é o local canônico para staff; Flutter é para atletas |

---

## DECISAO 060 — Testes: Script Curl + Test Plan Flutter

**Data:** 2026-02-24
**Status:** ACEITA
**Contexto:** Precisamos provas reproduzíveis de que o gate de monetização é não-burlável em todas as 4 camadas.

### Decisão

1. **`scripts/test_verification_gate.sh`** — Script bash com 12 testes automatizados. Usa curl + Supabase REST API + EFs. Sequência: reset → stake=0 ok → stake>0 bloqueado → simulate VERIFIED → stake>0 ok → simulate DOWNGRADE → stake>0 bloqueado → bypass attempts → RLS check → cleanup. Saída pass/fail com contagem.

2. **`scripts/TEST_PLAN_FLUTTER.md`** — 12 test cases manuais para QA do app. Cobre todos os estados da state machine, modal gate, fluxos completos UNVERIFIED→VERIFIED→DOWNGRADED, error states. Inclui matriz de cobertura 4 camadas.

3. **Testes provam as 4 camadas:** Flutter UX gate (modal), EF validation (403), RLS policy (DENY), DB triggers (RAISE EXCEPTION). Mesmo bypass de uma camada não compromete as outras.

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| Testes unitários Dart para o gate | Gate real depende do server; mocks não provam não-burlabilidade |
| Integration tests com Supabase local | Overhead de setup; curl contra instância real é mais convincente |
| Testes apenas server-side | Não cobre UX (modal, navigation) |

---

## DECISAO 061 — Settle: Verificação de Elegibilidade no Payout

**Data:** 2026-02-24
**Status:** ACEITA
**Contexto:** Um participante pode perder status VERIFIED durante a janela do desafio (ex: corrida com flags detectadas → DOWNGRADED). Sem check no settle, ele receberia pool winnings mesmo após perder elegibilidade.

### Decisão

Para challenges com `entry_fee_coins > 0`, no momento do settle:
1. Buscar `verification_status` de todos os participantes aceitos
2. Participantes que NÃO são VERIFIED recebem apenas coins-base (participation reward) — SEM pool share
3. Log estruturado `pool_forfeited` para auditoria

O ranking e outcome são preservados (o participante "ganhou" mas perdeu eligibilidade para receber o prêmio monetizado).

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| Bloquear participação retroativamente | Injusto — o user era VERIFIED ao entrar |
| Não verificar no settle (confiar no join-time check) | Exploit: verify→join→cheat→collect |
| Reverter entrada (refund) | Complexidade desnecessária; base coins é justo |
| Snapshot VERIFIED no momento do join | Overhead de armazenamento; verificar no settle é mais simples e atual |

---

## DECISAO 062 — Matchmaking por Fila (Queue-based)

**Data:** 2026-02-24
**Status:** ACEITA
**Contexto:** Sem mecanismo de descoberta, desafios dependiam de links compartilhados. Com escala (milhares de desafios), um feed cronológico seria inutilizável.

### Decisão

Queue-based matchmaking (modelo Uber): usuário declara intenção, sistema encontra oponente automaticamente. Zero browsing. Matching atômico com `FOR UPDATE SKIP LOCKED`. Skill brackets por pace médio.

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| Feed com filtros | Decision paralysis, desigualdade (itens no final nunca selecionados) |
| Feed com ranking/recomendação | Complexidade de ML desnecessária; fila é mais justa |
| Matchmaking síncrono (WebSocket) | Overhead de infra; polling a 5s é suficiente para MVP |

---

## DECISAO 063 — Assessoria obrigatória para desafios

**Data:** 2026-02-24
**Status:** ACEITA
**Contexto:** Atletas sem vínculo com assessoria estavam criando desafios sem supervisão de um treinador. Regra de produto: toda atividade competitiva exige vínculo com assessoria.

### Decisão

Atleta sem assessoria NÃO pode: criar desafios, participar de desafios, entrar na fila de matchmaking, nem acessar campeonatos. Gate enforçado em 3 camadas:
1. **Edge Functions** (`challenge-create`, `challenge-join`, `matchmake`): query `coaching_members` → retorna `NO_ASSESSORIA` (403)
2. **Flutter UX**: `AssessoriaRequiredSheet` bloqueia navegação com CTA "Entrar em assessoria"
3. **Mensagem clara**: "Peça o código de convite ao seu professor"

### Alternativas rejeitadas
| Rejeitada | Motivo |
|---|---|
| Bloquear apenas desafios com stake | Regra de produto define assessoria como pré-requisito para TODOS os desafios |
| Bloquear apenas no frontend | Violaria "server wins" — backend deve ser fonte de verdade |
| Permitir desafios gratuitos sem assessoria | Contraria a decisão de produto |

---

*Novas decisoes sao adicionadas ao final deste arquivo com numero sequencial.*
