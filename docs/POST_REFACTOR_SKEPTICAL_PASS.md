# Revisão Cética Pós-Refatoração

> Gerado em: 2026-03-04
> Objetivo: Identificar exclusivamente o que **ainda pode quebrar**, o que **vai falhar em produção**, e o que **parece funcionar mas é frágil**.

---

## VEREDICTO GERAL

O sistema compila, a APK builda (138.6 MB, prod), e 2027 de 2056 testes passam. Superficialmente está sólido. Abaixo estão os **problemas reais** que um revisor cético encontra ao cavar.

---

## 🔴 SEVERIDADE CRÍTICA (pode causar crash/perda de dados em produção)

### C-01: Migration v1→v2 é destrutiva — destrói dados locais não sincronizados

**Arquivo:** `lib/data/datasources/drift_database.dart:553-583`

A migration de schema v1 para v2 faz `deleteTable` em TODAS as 28 tabelas e depois `createAll()`. Isso significa:

- **Sessions de corrida que não foram sincronizadas com o backend são permanentemente perdidas.**
- Dados de wallet, challenges, badges, missões — tudo zerado.
- Não há backup, não há warning ao usuário, não há migração incremental.

O risco é real porque o schema v1 existiu em produção (foi criado na migração Isar→Drift). Qualquer usuário que atualize o app após esta mudança perde dados locais.

**Impacto:** Alto. Perda silenciosa de dados do usuário.

**Correção necessária:** Migração incremental com `ALTER TABLE ... ADD COLUMN` / `ALTER TABLE ... ALTER COLUMN TYPE` para as colunas que mudaram de `INTEGER` para `TEXT`, ou pelo mínimo um sync forçado antes da migration.

---

### C-02: 20 chamadas `.byName()` sem try/catch — crash em dados corrompidos

**Arquivos:** 10 repos em `lib/data/repositories_impl/drift_*.dart`

`EnumType.values.byName(string)` lança `ArgumentError` se o string não corresponde a nenhum valor do enum. Apenas 1 dos 21 usos tem try/catch (`_goalFromOrdinal` no `drift_challenge_repo.dart`). Os outros 20 são chamados diretamente.

Cenários de crash:
- Dados escritos por uma versão futura do app com novos enum values
- String corrompida no SQLite
- Dados migrados com encoding diferente

| Arquivo | Chamadas desprotegidas |
|---------|----------------------|
| `drift_challenge_repo.dart` | 6 (ChallengeStatus, ChallengeType, ChallengeStartMode, ChallengeAntiCheatPolicy, ParticipantStatus, ParticipantOutcome) |
| `drift_ledger_repo.dart` | 1 (LedgerReason) |
| `drift_xp_transaction_repo.dart` | 1 (XpSource) |
| `drift_mission_progress_repo.dart` | 1 (MissionProgressStatus) |
| `drift_coaching_ranking_repo.dart` | 2 (CoachingRankingMetric, CoachingRankingPeriod) |
| `drift_coaching_invite_repo.dart` | 1 (CoachingInviteStatus) |
| `drift_coaching_member_repo.dart` | 1 (CoachingRole) |
| `drift_athlete_trend_repo.dart` | 3 (EvolutionMetric, EvolutionPeriod, TrendDirection) |
| `drift_athlete_baseline_repo.dart` | 1 (EvolutionMetric) |
| `drift_coach_insight_repo.dart` | 3 (InsightType, InsightPriority, EvolutionMetric) |

**Impacto:** App crash ao ler qualquer registro com enum desconhecido.

**Correção necessária:** Criar extension method segura `T? tryByName<T>(String name, List<T> values)` com fallback e logging, usar em todos os repos.

---

### C-03: SQLCipher PRAGMA key via string interpolation — SQLite injection

**Arquivo:** `lib/data/datasources/drift_database.dart:599`

```dart
db.execute("PRAGMA key = '$_encryptionKey'");
```

A key é hex-encoded (64 chars, `[0-9a-f]`), então na prática o risco é baixo. Porém:

1. Se `_generateKey` ou a key storage for alterada para incluir `'` ou `;`, é SQL injection direta.
2. O formato `PRAGMA key = 'string'` trata o valor como **passphrase** (SQLCipher faz PBKDF2 sobre ela). Para usar como raw key, o formato correto é `PRAGMA key = "x'hex'"`.
3. Isso significa que a mesma key gera derivações diferentes dependendo do formato — mudar o formato no futuro corrompe o banco.

**Impacto:** Médio. Funciona hoje, mas é um anti-pattern que cria dívida técnica e risco de corrupção futura.

**Correção necessária:** Usar `PRAGMA key = "x'$hexKey'"` para raw key, ou melhor, usar a API nativa do `sqlcipher_flutter_libs` para passar a key sem interpolação SQL.

---

## 🟠 SEVERIDADE ALTA (falha silenciosa / comportamento incorreto)

### H-01: `movingMs` hardcoded como 0 ao salvar sessão

**Arquivo:** `lib/data/repositories_impl/drift_session_repo.dart:154`

```dart
movingMs: 0,
```

O `WorkoutSessionEntity` não tem campo `movingMs`, mas a tabela `WorkoutSessions` tem. O valor é sempre salvo como 0 e nunca atualizado via `_toCompanion`. O método `updateMetrics` atualiza `totalDistanceM` e `movingMs`, mas o valor inicial é sempre perdido.

**Impacto:** Dados de tempo de movimento sempre começam em 0 no banco local. Se `updateMetrics` nunca for chamado, o dado fica incorreto.

---

### H-02: `route` sempre vazio ao ler sessão do banco

**Arquivo:** `lib/data/repositories_impl/drift_session_repo.dart:175`

```dart
route: const [],
```

Os location points são armazenados em tabela separada (`LocationPoints`), mas `_toEntity` nunca os carrega. Quem chamar `session.route` sempre recebe lista vazia. A rota precisa ser carregada separadamente via `IPointsRepo.getBySessionId()`.

**Impacto:** Nenhum screen que usa `getById()` ou `getAll()` recebe dados de rota. Funciona apenas se o código chamador já sabe que precisa buscar os pontos separadamente.

---

### H-03: `SupabaseClient` não registrado quando `AppConfig.isSupabaseReady == false`

**Arquivo:** `lib/core/di/data_module.dart:187-200`

O `SupabaseClient` só é registrado dentro de `if (AppConfig.isSupabaseReady)`. Porém, 9 serviços que dependem dele são registrados **incondicionalmente** (linhas 568-658):

- `ITrainingSessionRepo`, `ITrainingAttendanceRepo`
- `ICrmRepo`, `IAnnouncementRepo`
- `ProfileDataService`
- `IWorkoutRepo`, `IFinancialRepo`, `ITrainingPeaksRepo`, `IWearableRepo`

Sendo lazy singletons, eles não crasham na inicialização — crasham quando alguma screen os resolve. Se o app for usado offline ou sem Supabase configurado, qualquer screen que acesse esses serviços causa `Bad state: GetIt: Object/factory with type SupabaseClient is not registered`.

**Impacto:** Runtime crash em cenários offline ou de inicialização falhada do Supabase.

---

### H-04: `DbSecureStore` usa key name legado `'isar_encryption_key'`

**Arquivo:** `lib/core/secure_storage/db_secure_store.dart:13`

```dart
static const _keyDbEncryption = 'isar_encryption_key';
```

A key antiga da era Isar é reutilizada. Isso funciona para backward compatibility, **mas**:

1. A key pode existir de uma instalação anterior onde nunca foi usada (Isar não suportava encryption).
2. Se o `clearKey()` for chamado em logout, o banco fica inacessível na próxima abertura até gerar nova key.
3. Uma nova key é gerada → banco antigo fica irrecuperável.
4. Não há mecanismo de re-keying nem fallback de abertura sem encryption.

**Impacto:** Potencial perda de acesso ao banco local após logout/login.

---

### H-05: 4 queries com strings hardcoded em vez de `enum.name`

**Arquivo:** `lib/data/repositories_impl/drift_challenge_repo.dart:45-53`

```dart
t.status.equals('pending') | t.status.equals('active') | t.status.equals('completing')
...
t.status.equals('completed')
```

Se `ChallengeStatus.pending` for renomeado para `ChallengeStatus.waiting`, estas queries retornam silenciosamente **zero resultados** sem erro. O bug seria invisível — desafios simplesmente "desaparecem" da listagem.

**Correção:** Usar `ChallengeStatus.pending.name` em vez de `'pending'`.

---

## 🟡 SEVERIDADE MÉDIA (fragilidades, dívida técnica ativa)

### M-01: 25 testes falhando — 3 categorias distintas

| Categoria | Count | Causa raiz | Exemplos |
|-----------|-------|------------|----------|
| **DI collision** | 14 | `ensureSupabaseClientRegistered()` registra `UserIdentityProvider` como lazySingleton, depois o teste tenta registrar como factory | `support_ticket_screen_test`, `leaderboards_screen_test`, `staff_dashboard_screen_test`, `park_screen_test` |
| **Missing Supabase mock** | 8 | Testes não chamam `ensureSupabaseClientRegistered()` mas screens usam `sl<SupabaseClient>()` | `league_screen_test`, `athlete_championships_screen_test`, `join_assessoria_screen_test` |
| **Timing/widget state** | 3 | Mock retorna instantaneamente, loading indicator desaparece antes do `expect` | `running_dna_screen_test`, `wrapped_screen_test`, `streaks_leaderboard_screen_test` |

**Nenhum dos 25 é regressão de lógica de negócio.** Todos são problemas de infraestrutura de teste.

---

### M-02: 6 test files com `ignore_for_file` suprimindo warnings reais

**Arquivos:**
- `matchmaking_screen_test.dart`
- `staff_workout_builder_screen_test.dart`
- `staff_training_scan_screen_test.dart`
- `athlete_attendance_screen_test.dart`
- `athlete_log_execution_screen_test.dart`
- `athlete_device_link_screen_test.dart`

Todos suprimem: `invalid_override`, `invalid_use_of_type_outside_library`, `extends_non_class`, `super_formal_parameter_without_associated_positional`.

Estes ignores escondem incompatibilidades entre as fake classes dos testes e as interfaces/classes reais. Se as interfaces mudarem, os testes continuarão "compilando" mas podem não testar o que deveriam.

---

### M-03: `WorkoutSessions.status` é `IntColumn` — único enum que ficou como integer

**Arquivo:** `lib/data/datasources/drift_database.dart:33`

Todos os outros 35 campos de enum foram migrados para `TextColumn` / string, exceto `WorkoutSessions.status` que permanece `IntColumn` com `_statusToInt` / `_statusFromInt` manual. Isso funciona, mas:

1. Inconsistência: desenvolvedores assumirão que enums são strings (como todos os outros) e cometerão erros.
2. `_statusFromInt` tem default para `WorkoutStatus.initial` em caso de valor desconhecido (bom), mas `_statusToInt` tem match exaustivo sem default (bom no Dart, mas frágil se alguém adicionar um novo status).

---

### M-04: `_encryptionKey` como static field compartilhado

**Arquivo:** `lib/data/datasources/drift_database.dart:588`

```dart
static String? _encryptionKey;
```

Se `setEncryptionKey` for chamado com uma key diferente após o banco já estar aberto, o banco ativo continua com a key antiga (a connection já foi criada). A nova key só teria efeito num novo `AppDatabase()` — mas o singleton `getDatabase()` retorna sempre o mesmo.

**Impacto:** Baixo na prática (key não muda em runtime), mas semanticamente incorreto.

---

### M-05: `StringListConverter.fromSql` aceita qualquer JSON válido

**Arquivo:** `lib/data/datasources/drift_converters.dart:10-14`

```dart
List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return [];
    final decoded = jsonDecode(fromDb);
    if (decoded is List) return decoded.cast<String>();
    return [];
}
```

Se o JSON contiver valores não-string (integers, objects), `cast<String>()` lança `TypeError` em runtime. O fallback `return []` só é atingido se `decoded` não é `List` — mas `[1, 2, 3]` É um `List`, e o `.cast<String>()` vai crashar.

---

### M-06: JSON-within-JSON para participants e results

**Arquivo:** `lib/data/repositories_impl/drift_challenge_repo.dart:171-198`

Participants e results são armazenados como `List<String>` onde cada String é um JSON object serializado. Isso gera `["{"userId":"...","status":"pending"}"]` — JSON escapado dentro de JSON.

Problemas:
1. Impossível de consultar via SQL (e.g., "quantos participantes com status=active?")
2. Debugging é confuso (double-escaping)
3. Se o converter falhar, toda a lista é perdida

---

## 🟢 O QUE ESTÁ SÓLIDO

| Aspecto | Status |
|---------|--------|
| APK builda em flavor prod | ✅ 138.6 MB (3.1 MB menor que antes — Isar removido) |
| `dart analyze lib/` | ✅ 0 errors (487 infos/warnings cosméticos) |
| Isar completamente removido | ✅ Zero imports, zero no pubspec.lock, zero no `third_party/` |
| DI wiring (17 repos Drift) | ✅ Todos registrados, interfaces corretas |
| SyncRepo refatorado | ✅ Usa ISessionRepo, sem referência a Isar |
| Schema version bumped | ✅ v2 com migration strategy definida |
| SQLCipher integrado | ✅ Key gerada, PRAGMA executado, dependency adicionada |
| Enum storage como string | ✅ 35 colunas migradas para TextColumn |

---

## RANKING DE PRIORIDADE PARA CORREÇÃO

| # | Item | Severidade | Esforço | Risco se ignorado |
|---|------|-----------|---------|-------------------|
| 1 | C-01: Trocar migration destrutiva por incremental | 🔴 Crítica | Médio | Perda de dados em produção |
| 2 | C-02: Proteger 20 `.byName()` com try/catch + fallback | 🔴 Crítica | Baixo | Crash em dados corrompidos |
| 3 | H-03: Guard serviços Supabase-dependent no DI | 🟠 Alta | Baixo | Crash offline |
| 4 | C-03: Corrigir PRAGMA key format (`x'hex'`) | 🔴 Crítica | Baixo | Anti-pattern + risco futuro |
| 5 | H-05: Hardcoded strings → `enum.name` | 🟠 Alta | Trivial | Desafios desaparecem se enum renomeado |
| 6 | H-01: Mapear `movingMs` do entity | 🟠 Alta | Trivial | Dados incorretos |
| 7 | M-01: Fix 25 testes (DI collision + missing mock) | 🟡 Média | Médio | Regressões passam despercebidas |
| 8 | H-04: Implementar re-keying / fallback de abertura | 🟠 Alta | Médio | Banco inacessível pós-logout |
| 9 | M-05: `cast<String>()` → `.map((e) => e.toString())` | 🟡 Média | Trivial | Crash em dados não-string |
| 10 | M-02: Remover `ignore_for_file` e corrigir fakes | 🟡 Média | Médio | Testes incorretos |

---

*Este relatório foi gerado por análise estática do código, execução da suíte de testes, e build da APK de produção. Nenhuma suposição otimista foi feita.*
