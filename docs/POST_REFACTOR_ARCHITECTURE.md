# POST_REFACTOR_ARCHITECTURE.md

> Data: 2026-03-07

---

## 1. SEPARAÇÃO DE CAMADAS

| Camada | Verificação | Resultado |
|---|---|---|
| Presentation → Domain | BLoCs importam domain? | ✅ 100% via interfaces |
| Presentation → Data | BLoCs importam data? | ✅ ZERO importações data |
| Domain → Data | Use cases importam data? | ✅ 99% via interfaces (1 violação) |
| Data → Domain | Repos dependem de entities? | ✅ Sim — retornam entities |
| Core → Todos | Core é compartilhado? | ✅ Sim — theme, config, logging |

---

## 2. VIOLAÇÕES IDENTIFICADAS

### CRÍTICA: 30+ screens acessam Supabase diretamente

Screens que chamam `Supabase.instance.client` sem intermediação de repository:

| Screen | Tipo de acesso |
|---|---|
| history_screen.dart | Query direta em sessions table |
| profile_screen.dart | Query em badges_earned, user_progressions, sessions |
| today_screen.dart | Query para active runners |
| settings_screen.dart | Raw HTTP com Bearer token para Edge Functions |
| staff_dashboard_screen.dart | Full Supabase client access |
| friends_screen.dart | 2 queries diretas |
| matchmaking_screen.dart | 8+ calls incluindo Edge Functions |
| coaching_group_details_screen.dart | Client + RPC call |
| staff_performance_screen.dart | Client direto |
| my_assessoria_screen.dart | Queries diretas |
| + 20 outras telas... | Variado |

### ALTA: 1 use case viola domain layer

`PushToTrainingPeaks` importa `SupabaseClient` diretamente no domain layer. Deveria usar um repository interface.

### MÉDIA: 4 screens importam data/services/

- today_screen.dart → TodayDataService
- profile_screen.dart → ProfileDataService
- diagnostics_screen.dart → (data layer access)
- settings_screen.dart → (data layer access)

### MÉDIA: 6 services sem interface no DI

SyncService, AnalyticsSyncService, ProductEventTracker, PushNotificationService, ProfileDataService, IsarSecureStore — registrados como tipos concretos, não mockáveis.

---

## 3. PADRÕES POSITIVOS

| Padrão | Status |
|---|---|---|
| Todos os 17 repos Isar implementam interfaces I*Repo | ✅ |
| Todos os 30 BLoCs recebem deps via construtor | ✅ |
| Use cases são single-responsibility | ✅ |
| Entities são imutáveis (Equatable) | ✅ |
| Failures tipadas (domain/failures/) | ✅ |
| go_router centralizado com auth redirect | ✅ |
| Feature flags como serviço injetável | ✅ |
| Error boundaries no bootstrap | ✅ |

---

## 4. TECHNICAL DEBT CRIADA PELA REFATORAÇÃO

| Debt | Origem | Impacto |
|---|---|---|
| Código Drift morto (3 files, 1500+ linhas) | Migração incompleta | Complexidade cognitiva |
| isar_generator removido mas .g.dart commitados | Processo de build frágil | Risco de CI failure |
| ignore_for_file em 30+ arquivos Isar | Mascaramento de erros | Lint warnings ocultos |
| 58 erros de compilação (Drift) em dart analyze | Código não-funcional | Mascara erros reais |

---

## 5. DIAGRAMA DE DEPENDÊNCIAS

```
Presentation (screens, BLoCs, widgets)
    │
    ├── ✅ Depende de Domain (entities, interfaces, use cases)
    ├── ❌ 30+ screens dependem diretamente de Supabase (VIOLAÇÃO)
    └── ❌ 4 screens importam Data services (VIOLAÇÃO)

Domain (entities, interfaces, use cases, services)
    │
    ├── ✅ Independente de Data e Presentation
    └── ❌ 1 use case (PushToTrainingPeaks) importa SupabaseClient (VIOLAÇÃO)

Data (repos, models, datasources, mappers)
    │
    ├── ✅ Implementa interfaces de Domain
    ├── ✅ Usa Isar para persistência local
    └── ✅ Usa Supabase para acesso remoto

Core (DI, config, logging, theme, auth, cache, offline)
    │
    └── ✅ Compartilhado entre todas as camadas
```
