# STACK.md — Stack Tecnologica (CONGELADA)

> **Status:** CONGELADO
> **Data:** 2025-01-10
> **Sprint:** 0.2
> **Regra absoluta:** Nenhuma substituicao. Nenhuma alternativa. Nenhuma abstracao extra.

---

## 1. STACK DEFINITIVA

| Camada | Tecnologia | Versao Minima | Funcao Exata |
|---|---|---|---|
| UI / Framework | Flutter | 3.22+ | Framework unico para Android e iOS |
| Arquitetura | Clean Arch | — | Separacao em domain, data e presentation |
| State Management | BLoC | 8.x | Gerenciamento de estado reativo via streams |
| Persistencia Local | Isar | 3.x | Banco local NoSQL, offline-first, alta performance |
| Modelos de Dados | Protobuf | 3.x | Serializacao binaria dos modelos de dominio |
| Mapas | MapLibre | 0.19+ | Renderizacao de mapas e trajetos, sem vendor lock |
| Backend / Sync | Supabase | 2.x | Autenticacao minima, storage e sync manual |

---

## 2. MAPA ARQUITETURAL

```
┌─────────────────────────────────────────────────┐
│                 PRESENTATION                     │
│         Flutter Widgets + BLoC                   │
│         MapLibre (visualizacao)                  │
├─────────────────────────────────────────────────┤
│                   DOMAIN                         │
│         Entities (Protobuf-generated)            │
│         Use Cases (pure Dart)                    │
│         Repository Interfaces                    │
├─────────────────────────────────────────────────┤
│                    DATA                          │
│         Isar (local persistence)                 │
│         Supabase Client (remote sync)            │
│         GPS Service (platform channels)          │
└─────────────────────────────────────────────────┘
```

---

## 3. JUSTIFICATIVA POR ESCOLHA (REGISTRO UNICO)

### Flutter
- Codebase unica para Android + iOS
- Controle total de rendering
- Ecossistema maduro para GPS e mapas

### Clean Architecture
- Dominio isolado de frameworks
- Testabilidade maxima nos use cases
- Troca de datasource sem impacto no dominio

### BLoC
- Padrao oficial recomendado para apps complexos Flutter
- Separacao explicita de eventos e estados
- Streams nativos do Dart, zero magia

### Isar
- NoSQL otimizado para Flutter/Dart
- Operacoes sincronas e assincronas
- Indices compostos para queries de corrida por data/distancia
- Performance superior para escrita sequencial (pontos GPS)

### Protobuf
- Modelos tipados e versionados
- Serializacao binaria compacta (ideal para dados GPS)
- Geracao automatica de codigo Dart
- Contrato rigido entre camadas

### MapLibre
- Open source, sem custo por request
- Suporte a custom tiles e renderizacao vetorial
- Sem dependencia de Google Maps ou Mapbox billing

### Supabase
- PostgreSQL gerenciado (Row Level Security)
- Auth integrado (minimo para sync)
- Storage para backups de corrida
- REST + Realtime pronto (Realtime reservado pos-MVP)

---

## 4. O QUE NAO SERA USADO

| Tecnologia | Motivo da Rejeicao |
|---|---|
| Provider / Riverpod | BLoC ja escolhido, sem segundo state manager |
| Hive / SQLite | Isar ja escolhido, sem segundo banco |
| Google Maps SDK | Vendor lock + custo, MapLibre resolve |
| Firebase | Supabase ja escolhido, sem segundo backend |
| JSON manual | Protobuf ja escolhido, sem serializacao artesanal |
| GetX | Fora de consideracao, padrao nao compativel com Clean Arch |
| REST puro manual | Supabase client abstrai, sem HTTP client manual |

---

## 5. DEPENDENCIAS FLUTTER CONGELADAS

```yaml
# pubspec.yaml — dependencias core (preview congelado)
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^8.0.0
  isar: ^3.0.0
  isar_flutter_libs: ^3.0.0
  protobuf: ^3.0.0
  maplibre_gl: ^0.19.0
  supabase_flutter: ^2.0.0
  geolocator: ^11.0.0        # GPS access
  equatable: ^2.0.0           # Value equality para BLoC states
  fpdart: ^1.0.0              # Either/Option para error handling funcional

dev_dependencies:
  isar_generator: ^3.0.0
  protoc_plugin: ^21.0.0
  build_runner: ^2.0.0
  bloc_test: ^9.0.0
  mocktail: ^1.0.0
```

---

## 6. REGRAS INVIOLAVEIS

1. **Nenhuma lib sera adicionada** sem Sprint de revisao dedicada
2. **Nenhuma lib listada sera substituida** — a escolha e final
3. **Nenhuma camada de abstracao extra** sera criada sobre essas libs
4. **Domain layer nao importa nenhuma lib externa** — apenas Dart puro + Protobuf generated
5. **Toda comunicacao entre camadas** passa por interfaces definidas no Domain

---

## 7. REGRA DE MUDANCA

> Para alterar qualquer item desta stack:
> 1. Abrir Sprint especifica de "Revisao de Stack"
> 2. Demonstrar que a tecnologia atual e IMPOSSIVEL (nao apenas inconveniente)
> 3. Atualizar este documento com data, motivo e impacto
> 4. Recongelar

---

*Documento gerado na Sprint 0.2 — Definicao de Stack e Congelamento Tecnologico*
