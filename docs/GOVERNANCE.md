# GOVERNANCE.md — Governanca de Codigo e Regras de Execucao (CONGELADO)

> **Status:** CONGELADO
> **Data:** 2025-01-10
> **Sprint:** 0.3
> **Regra absoluta:** Codigo que violar qualquer regra deste documento e rejeitado. Sem excecao.

---

## 1. ARQUITETURA — CAMADAS OBRIGATORIAS

```
lib/
├── domain/            # Regras de negocio puras
├── application/       # Orquestracao (BLoCs + Use Cases)
├── infrastructure/    # Implementacoes concretas
└── presentation/      # UI (Widgets + Pages)
```

### 1.1 DOMAIN (Nucleo Inviolavel)

**Contem:**
- Entities (geradas por Protobuf, imutaveis)
- Value Objects (validacoes de dominio)
- Repository Interfaces (contratos abstratos)
- Failures (tipos de erro do dominio)

**Regras:**
- NAO importa Flutter
- NAO importa nenhum package externo (exceto Protobuf generated)
- NAO importa application, infrastructure ou presentation
- NAO tem efeitos colaterais
- Dart puro, 100% testavel sem mocks de framework

### 1.2 APPLICATION (Orquestracao)

**Contem:**
- Use Cases (um por arquivo, uma responsabilidade)
- BLoCs (Events + States + logica reativa)
- DTOs de entrada/saida entre camadas

**Regras:**
- Importa domain
- NAO importa infrastructure
- NAO importa presentation
- BLoC nunca acessa banco, GPS, HTTP ou filesystem diretamente
- Depende apenas de interfaces definidas no domain
- Cada BLoC tem exatamente um Use Case principal (composicao permitida, heranca proibida)

### 1.3 INFRASTRUCTURE (Implementacoes Concretas)

**Contem:**
- Repository Implementations (implementam interfaces do domain)
- Isar models + adapters
- Supabase client wrappers
- GPS service implementation
- MapLibre data adapters

**Regras:**
- Importa domain (para implementar interfaces)
- NAO importa application
- NAO importa presentation
- NAO contem logica de negocio
- Converte dados externos -> entities do domain
- Toda operacao que pode falhar retorna Either<Failure, T>

### 1.4 PRESENTATION (Interface do Usuario)

**Contem:**
- Pages (telas completas)
- Widgets (componentes reutilizaveis)
- BLoC Providers (injecao na arvore)
- Navegacao e rotas

**Regras:**
- Importa application (para consumir BLoCs)
- Importa domain (para ler Entities)
- NAO importa infrastructure
- NAO contem logica de negocio
- NAO faz calculos de pace, distancia ou validacoes
- Apenas le estados do BLoC e despacha eventos

---

## 2. GRAFO DE DEPENDENCIA (INVIOLAVEL)

```
presentation -> application -> domain <- infrastructure
     |              |           ^           |
     |              |           |           |
     └──────────────┘           └───────────┘
                        DEPENDE DE

     presentation NUNCA -> infrastructure (PROIBIDO)
     application NUNCA -> infrastructure (PROIBIDO)
     domain NUNCA -> qualquer outra camada (PROIBIDO)
```

**Direcao unica:** Dependencias sempre apontam para o domain.
**Inversao:** Infrastructure implementa interfaces do domain (Dependency Inversion).

---

## 3. REGRAS DE CODIGO

### 3.1 Proibicoes Absolutas

| # | Regra | Consequencia |
|---|---|---|
| R1 | Nenhum singleton fora de Service Locator configurado | Codigo rejeitado |
| R2 | Nenhum `print()` em codigo de producao | Codigo rejeitado |
| R3 | Nenhum `dynamic` como tipo declarado | Codigo rejeitado |
| R4 | Nenhum `catch` generico sem tipo especifico | Codigo rejeitado |
| R5 | Nenhum import relativo (usar package imports) | Codigo rejeitado |
| R6 | Nenhum widget com logica de negocio | Codigo rejeitado |
| R7 | Nenhum BLoC com import de infrastructure | Codigo rejeitado |
| R8 | Nenhum arquivo com mais de 200 linhas | Refatorar obrigatorio |
| R9 | Nenhuma classe com mais de 5 dependencias injetadas | Redesign obrigatorio |
| R10 | Nenhum codigo comentado (dead code) | Codigo rejeitado |

### 3.2 Obrigacoes Absolutas

| # | Regra |
|---|---|
| O1 | Todo arquivo publico tem exatamente uma classe/funcao |
| O2 | Todo BLoC tem arquivo separado para Events e States |
| O3 | Todo Repository retorna `Either<Failure, T>` |
| O4 | Todo Use Case implementa `call()` como metodo unico |
| O5 | Toda Entity e imutavel (gerada por Protobuf) |
| O6 | Todo erro de dominio e um sealed class Failure |
| O7 | Todo widget de tela e sufixado com `Page` |
| O8 | Todo widget reutilizavel e sufixado com `Widget` |
| O9 | Todo BLoC e sufixado com `Bloc` |
| O10 | Todo teste segue padrao AAA (Arrange, Act, Assert) |

### 3.3 Nomenclatura

```
Arquivos:       snake_case.dart
Classes:        PascalCase
Variaveis:      camelCase
Constantes:     camelCase (com final/const)
Enums:          PascalCase com valores camelCase
BLoC Events:    PascalCase verbos (Started, Paused, Resumed, Stopped)
BLoC States:    PascalCase adjetivos (Initial, Loading, Loaded, Failed)
Pastas:         snake_case
```

---

## 4. REGRAS DE VERSIONAMENTO (GIT)

### 4.1 Estrutura de Commits

```
<tipo>(<escopo>): <descricao imperativa curta>

Tipos permitidos:
  feat     -> nova funcionalidade
  fix      -> correcao de bug
  refactor -> refatoracao sem mudanca de comportamento
  test     -> adicao ou correcao de testes
  docs     -> documentacao
  chore    -> configuracao, build, CI
  style    -> formatacao (sem mudanca de logica)
```

**Exemplos validos:**

```
feat(domain): add RunSession entity with protobuf schema
fix(infrastructure): handle GPS timeout on Android 14
test(application): add unit tests for CalculatePaceUseCase
docs(governance): freeze code governance rules
```

**Exemplos REJEITADOS:**

```
update stuff                    -> sem tipo, sem escopo
fix: things                     -> vago demais
feat: add run tracking + map    -> dois escopos no mesmo commit
WIP                             -> proibido commitar trabalho incompleto
```

### 4.2 Regras de Commit

| # | Regra |
|---|---|
| G1 | Todo commit compila sem erros |
| G2 | Todo commit tem escopo de UMA mudanca logica |
| G3 | Nenhum commit contem arquivos nao relacionados |
| G4 | Nenhum commit de WIP (work in progress) e permitido |
| G5 | Mensagem em ingles, imperativo, maximo 72 caracteres |
| G6 | Nenhum commit direto na branch main sem review |

### 4.3 Estrategia de Branches

```
main            -> codigo estavel, sempre compila
  └── dev       -> integracao de features
       ├── feat/F1-gps-tracking
       ├── feat/F2-metrics-calculation
       ├── feat/F3-local-persistence
       ├── feat/F4-map-visualization
       ├── feat/F5-ghost-runner
       ├── feat/F6-anti-cheat
       └── feat/F7-manual-sync
```

**Regra:** Branch nomeada com ID da funcionalidade do SCOPE.md.

---

## 5. REGRAS DE TESTE

| Camada | Tipo de Teste | Cobertura Minima | Obrigatorio |
|---|---|---|---|
| Domain | Unit | 100% | SIM |
| Application | Unit (BLoC test) | 100% | SIM |
| Infrastructure | Integration | 80% | SIM |
| Presentation | Widget test | Criticos apenas | Parcial |

**Regra:** Nenhum Use Case ou BLoC e considerado "pronto" sem teste.

---

## 6. SERVICE LOCATOR (UNICO SINGLETON PERMITIDO)

```dart
// Unico ponto de registro de dependencias
// Configurado uma vez no main.dart
// Nenhum outro singleton existe na aplicacao
```

**Regras:**
- Apenas o Service Locator e singleton
- Toda dependencia e registrada nele
- BLoCs recebem dependencias via construtor (injecao explicita)
- Nenhum `static` method para acessar servicos

---

## 7. ERROR HANDLING PADRAO

```
Toda operacao que pode falhar:
  -> Repository retorna Either<Failure, T>
  -> BLoC converte para State.failed(failure)
  -> Presentation exibe mensagem mapeada

Hierarquia de Failures (sealed class):
  Failure
  ├── GpsFailure (noPermission, timeout, unavailable)
  ├── StorageFailure (readError, writeError, full)
  ├── SyncFailure (noConnection, serverError, timeout)
  └── ValidationFailure (invalidPace, invalidDistance, suspectedCheat)
```

**Regra:** Nenhum `throw` no domain ou application. Apenas Either.

---

## 8. CHECKLIST DE VALIDACAO POR COMMIT

Antes de todo commit, verificar:

- [ ] Codigo compila sem warnings
- [ ] Nenhum import cruza camadas proibidas
- [ ] Nenhum arquivo excede 200 linhas
- [ ] Testes passam (existentes)
- [ ] Nomenclatura segue padrao
- [ ] Commit message segue formato
- [ ] Escopo e unico e rastreavel

---

## 9. REGRA DE MUDANCA

> Para alterar qualquer regra deste documento:
> 1. Abrir Sprint especifica de "Revisao de Governanca"
> 2. Demonstrar que a regra atual IMPEDE progresso (nao apenas incomoda)
> 3. Atualizar com data, motivo e impacto
> 4. Recongelar

---

*Documento gerado na Sprint 0.3 — Governanca de Codigo e Regras de Execucao*
