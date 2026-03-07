# POST_REFACTOR_ISAR_TO_DRIFT_AUDIT.md

> Data: 2026-03-07 | Veredicto: **MIGRAÇÃO NÃO CONCLUÍDA**

---

## 1. STATUS DA MIGRAÇÃO

| Etapa | Status | Evidência |
|---|---|---|
| Adicionar Drift ao pubspec | ✅ Feito | drift ^2.32.0, drift_flutter ^0.3.0, drift_dev ^2.32.0 |
| Definir tabelas Drift (28) | ✅ Feito | drift_database.dart com 28 Table classes |
| Criar converters | ✅ Feito | StringListConverter em drift_converters.dart |
| Escrever migrator Isar→Drift | ✅ Feito | isar_to_drift_migrator.dart (903 linhas) |
| Rodar build_runner para Drift | ❌ **NÃO FEITO** | drift_database.g.dart NÃO EXISTE |
| Criar DAOs | ❌ Não feito | Zero DatabaseAccessor subclasses |
| Criar repos Drift | ❌ Não feito | Zero repos usando AppDatabase |
| Registrar AppDatabase no DI | ❌ Não feito | data_module.dart não importa Drift |
| Executar migrator | ❌ Não feito | Migrator nunca instanciado |
| Remover Isar | ❌ Não feito | 68 arquivos ainda dependem de Isar |

**Resultado: O app roda 100% em Isar. Drift é código morto.**

---

## 2. ERROS DE COMPILAÇÃO DRIFT

58 erros em dart analyze, todos em 2 arquivos:

### drift_database.dart (2 erros)
- `uri_has_not_been_generated` — .g.dart ausente
- `super_formal_parameter_without_associated_positional` — construtor depende de classe gerada

### isar_to_drift_migrator.dart (56 erros)
- 28x `undefined_method` (batch, *Companion) — dependem do código gerado
- 28x `undefined_identifier` (schemas Isar) — suprimidos por ignore_for_file mas .g.dart ausente para Drift

---

## 3. RISCO DO ESTADO HÍBRIDO

| Risco | Severidade |
|---|---|
| Código morto Drift aumenta complexidade cognitiva | MÉDIO |
| Desenvolvedores podem assumir que Drift funciona | ALTO |
| 58 erros de compilação mascaram erros reais futuros | ALTO |
| pubspec tem deps desnecessárias (drift, drift_flutter, drift_dev) | BAIXO |
| isar_generator removido mas .g.dart commitados — processo frágil | MÉDIO |

---

## 4. COERÊNCIA ARQUITETURAL

| Verificação | Resultado |
|---|---|
| Repository interfaces consistentes? | ✅ Sim — todas IXxxRepo |
| Storage não vazou para presentation? | ✅ Sim — BLoCs limpos |
| Use cases independentes do banco? | ✅ Sim (1 exceção: PushToTrainingPeaks) |
| Isar provider funciona corretamente? | ✅ Sim — singleton via DI |

---

## 5. RECOMENDAÇÃO

**Opção A — Completar a migração Drift:**
1. `dart run build_runner build` (gerar .g.dart Drift)
2. Criar DAOs e repos Drift para todas as 28 tabelas
3. Registrar AppDatabase no DI
4. Wiring do migrator no bootstrap (one-time)
5. Trocar bindings de IsarXxxRepo para DriftXxxRepo
6. Testar completamente
7. Remover Isar, isar_flutter_libs, third_party/, modelos .g.dart

**Opção B — Reverter e manter Isar:**
1. Remover drift, drift_flutter, drift_dev do pubspec
2. Deletar drift_database.dart, drift_converters.dart, isar_to_drift_migrator.dart
3. Re-adicionar isar_generator ao dev_dependencies
4. Eliminar 58 erros de compilação instantaneamente

**Recomendação: Opção B a curto prazo** (estabilizar), **Opção A a médio prazo** (quando Isar 3.x tornar-se insustentável).
