---
id: L18-04
audit_ref: "18.4"
lens: 18
title: "Architecture: Flutter viola Clean Arch em vários pontos"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "architecture", "flutter", "clean-arch", "ci-guard"]
files:
  - tools/audit/check-flutter-clean-arch.ts
  - tools/audit/baselines/flutter-clean-arch-baseline.txt
correction_type: ci-guard
test_required: true
tests:
  - tools/audit/check-flutter-clean-arch.ts
linked_issues: []
linked_prs: []
owner: mobile-platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Em vez de refactor big-bang da árvore `omni_runner/lib` (639+
  arquivos .dart), L18-04 fixa o problema via CI guard com **baseline
  ratchet** para congelar o débito existente e impedir regressão.

  Fences de Clean Architecture enforçados
  (`tools/audit/check-flutter-clean-arch.ts`):

  1. `presentation/*` e `features/*` **MUST NOT** importar `data/*`
     — deve passar por interface de repositório declarada em
     `domain/repositories/`.
  2. `presentation/*` e `features/*` **MUST NOT** importar IO clients
     de 3rd-party (`package:supabase_flutter`, `drift`, `dio`, `http`,
     `sqflite`, `firebase_firestore`) — mesma regra.
  3. `domain/*` **MUST NOT** importar `data/*`, `presentation/*`,
     `features/*`, `core/*`, ou IO clients — domain é pure core
     funcional (apenas `dart:` stdlib + pacotes puros como `meta`).
  4. `data/*` **MAY** importar `domain/*` (implementa contratos),
     mas **MUST NOT** importar `presentation/*` ou `features/*`
     (inversão de dependência).
  5. `core/*` **MAY** importar `domain/*` mas **MUST NOT** importar
     `data/*` ou `presentation/*`.

  Exceções (composition roots):
  - `core/di/*` — único local autorizado a wire implementações
    concretas.
  - `core/router/*` — binding de rotas para screens/blocs.
  - `core/push/*` — deep-link dispatcher para screens.
  - `main.dart` — app entry point.

  Baseline ratchet em `tools/audit/baselines/flutter-clean-arch-
  baseline.txt` congela 109 violações preexistentes (56 em
  `presentation`, 43 em `domain`, 7 em `data`, 3 em `features`).
  CI falha tanto em NOVAS violações quanto em entradas do baseline
  já corrigidas (ratchet monotonicamente decrescente).

  Top offenders priorizados para refactor imediato (baseado no
  achado original):
  - `presentation/screens/today_screen.dart` → `data/services/today_data_service.dart`
  - `presentation/screens/profile_screen.dart` → `data/services/profile_data_service.dart`
  - `presentation/screens/athlete_workout_day_screen.dart` → `data/services/workout_delivery_service.dart`
  - Várias telas importando `package:supabase_flutter` diretamente.

  Estratégia de repayment:
  1. Extrair repository interface em `domain/repositories/`
     espelhando o `data_service`.
  2. Mover service para `data/repositories_impl/` e fazer implementar
     a interface.
  3. Substituir import direto em `presentation/*` por injeção via
     `GetIt` resolve de interface.
  4. Regenerar baseline (`UPDATE_BASELINE=1 npm run
     audit:flutter-clean-arch`) — o ratchet só aceita baselines
     menores do que o anterior.
---
# [L18-04] Architecture: Flutter viola Clean Arch em vários pontos
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Mobile / Architecture
**Personas impactadas:** Mobile Eng (testability, migração de backend), QA (mocks excessivos)

## Achado
`omni_runner/lib` viola Clean Arch em vários pontos:
- `presentation/screens/today_screen.dart`, `profile_screen.dart`, `athlete_workout_day_screen.dart` importam `data/services/*` diretamente.
- Várias telas importam `package:supabase_flutter` sem repository.
- `domain/usecases/*` importam `core/utils/haversine.dart` e `core/errors/*_failures.dart` (core é infra, domain deve ser puro).
- Use cases misturando domain + data responsibilities.

## Risco / Impacto
- Inability to migrate backend — Supabase coupling em 50+ arquivos;
- Testing painful — Supabase client precisa ser mockado em cada tela;
- Risco de circular imports invisíveis (sem linter que veja isso);
- Onboarding mobile devs lento (sem mental model do layering).

## Correção aplicada

Em vez de refactor big-bang, **manifesto implícito via regras + CI guard + baseline ratchet**:

### 1. Fences de Clean Architecture em `tools/audit/check-flutter-clean-arch.ts`
Regras canônicas:
1. `presentation/*` e `features/*` NÃO podem importar `data/*`.
2. `presentation/*` e `features/*` NÃO podem importar IO clients 3rd-party (supabase_flutter, drift, dio, http, sqflite, firebase_firestore) — devem ir via interface em `domain/repositories/`.
3. `domain/*` é pure core: NÃO importa `data/*`, `presentation/*`, `features/*`, `core/*`, nem IO.
4. `data/*` MAY importar `domain/*` (contratos) mas NÃO `presentation/*` ou `features/*`.
5. `core/*` MAY importar `domain/*` mas NÃO `data/*` ou `presentation/*`.

### 2. Exceções documentadas (composition roots)
`core/di/*`, `core/router/*`, `core/push/*` e `main.dart` são os únicos caminhos autorizados a wire camadas. Mudar a lista requer nova ADR.

### 3. Baseline ratchet (`tools/audit/baselines/flutter-clean-arch-baseline.txt`)
Congela 109 violações preexistentes:
- 56 em `presentation` (screens + widgets importando data/supabase direto)
- 43 em `domain` (use cases importando core/utils/haversine, core/errors/*_failures, core/logging/logger)
- 7 em `data` (data importando presentation — inversão!)
- 3 em `features` (feature modules importando data)

CI falha em NOVAS violações e em entradas do baseline já corrigidas, garantindo ratchet monotonicamente decrescente.

### 4. npm script
`npm run audit:flutter-clean-arch` roda o guard.
`UPDATE_BASELINE=1 npm run audit:flutter-clean-arch` regenera baseline (apenas quando pagando débito).

## Estratégia de repayment priorizada
1. **today_screen.dart, profile_screen.dart, athlete_workout_day_screen.dart** — remover `data/services/*` imports, injetar repository via GetIt.
2. **domain/usecases** que importam `core/utils/haversine.dart` → mover `haversine.dart` para `domain/value_objects/`.
3. **domain/usecases** que importam `core/errors/*_failures.dart` → mover failures para `domain/failures/`.
4. **domain/usecases** que importam `core/logging/logger.dart` → injetar `ILogger` via constructor (interface em domain).
5. **data → presentation** (7 entradas) — refatorar para DI.

Cada PR de repayment deve regenerar o baseline com `UPDATE_BASELINE=1` para encolher o débito.

## Teste de regressão
- `npm run audit:flutter-clean-arch`
- Na CI principal, o script já impede merge de PRs que introduzam novas violações.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.4]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.4).
- `2026-04-21` — Fixed via CI guard `audit:flutter-clean-arch` + baseline ratchet (109 débitos congelados; 4 exceções documentadas: core/di, core/router, core/push, main.dart). Refactor físico pendente — guard previne regressão enquanto equipe paga débito.
