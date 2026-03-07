# POST_REFACTOR_BUILD_AND_STATIC.md

> Data: 2026-03-07

---

## 1. BUILD STATUS

| Target | Resultado | Detalhes |
|---|---|---|
| Flutter APK (--flavor prod) | ✅ **SUCESSO** | app-prod-release.apk (141MB) |
| Portal (next build) | ✅ SUCESSO | Sem erros |
| Portal lint (ESLint) | ✅ SUCESSO | 0 warnings, 0 errors |
| dart analyze | ❌ **771 issues** | 58 errors, 57 warnings, 656 infos |

---

## 2. ERROS (58)

| Arquivo | Tipo | Causa |
|---|---|---|
| drift_database.dart | 2 erros | .g.dart não gerado (build_runner nunca rodou para Drift) |
| isar_to_drift_migrator.dart | 56 erros | Dependem de código gerado Drift (Companion classes, batch method) |

**100% dos erros são do código Drift não-gerado. O app Isar compila normalmente.**

---

## 3. WARNINGS (57)

| Categoria | Contagem | Arquivos principais |
|---|---|---|
| unused_import | 12 | test files |
| deprecated_member_use | 8 | Flutter/third-party APIs |
| invalid_annotation_target | 15 | Isar annotations em testes |
| unnecessary_type_check | 5 | Condicionais redundantes |
| dead_code | 8 | Branches unreachable |
| Outros | 9 | Variados |

---

## 4. INFOS (656)

| Categoria | Contagem |
|---|---|
| prefer_const_constructors | ~250 |
| prefer_final_locals | ~120 |
| prefer_const_declarations | ~80 |
| unnecessary_parenthesis | ~40 |
| prefer_const_literals_to_create_immutables | ~60 |
| Outros lint | ~106 |

---

## 5. CÓDIGO MORTO DETECTADO

| Arquivo/Módulo | Tipo | Impacto |
|---|---|---|
| drift_database.dart | Scaffolding não-wired | Nenhum — nunca executado |
| drift_converters.dart | Converter não-usado | Nenhum |
| isar_to_drift_migrator.dart | Migrator não-wired | Nenhum |
| lib/core/utils/offline_queue.dart | Duplicata antiga | Nenhum — não importado |

---

## 6. GERAÇÃO DE CÓDIGO

| Gerador | Status | Arquivos |
|---|---|---|
| isar_generator (removido) | .g.dart existem no disco | 22 arquivos commitados |
| drift_dev | .g.dart **NÃO EXISTE** | 0 — build_runner nunca rodou |
| build_runner | Instalado | Disponível mas precisa de swap de deps |
