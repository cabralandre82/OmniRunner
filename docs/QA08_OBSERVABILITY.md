# QA-08 — Observabilidade (Logs, Sentry, Auditoria)

## 1. AppLogger — Cobertura

### Código antigo (pré-OS): BEM instrumentado ✅

| Camada | Exemplos | AppLogger? |
|--------|----------|------------|
| Staff screens (dashboard, setup, retention, weekly, performance) | `AppLogger.error(...)`, `AppLogger.info(...)` | ✅ |
| Athlete screens (dashboard, matchmaking, more, my_assessoria) | `AppLogger.error(...)` em catches | ✅ |
| Core services (sync, auth, push, strava) | Logging granular | ✅ |
| `remote_token_intent_repo.dart` | `AppLogger.error('RPC failed', tags: {...})` | ✅ |

### Código novo (OS-01/02/03): ZERO instrumentação ❌

| Camada | Arquivos sem AppLogger | Severidade |
|--------|------------------------|------------|
| **BLoCs** (7) | `training_list_bloc.dart`, `training_detail_bloc.dart`, `checkin_bloc.dart`, `crm_list_bloc.dart`, `athlete_profile_bloc.dart`, `announcement_feed_bloc.dart`, `announcement_detail_bloc.dart` | **P0** |
| **Repos** (4) | `supabase_training_session_repo.dart`, `supabase_training_attendance_repo.dart`, `supabase_crm_repo.dart`, `supabase_announcement_repo.dart` | **P0** |
| **Screens** (14) | Todas as 14 telas novas — zero chamadas a `AppLogger` | **P2** |

**Impacto**: Nenhum erro dos módulos OS-01/02/03 chega ao Sentry. Em produção, falhas de presença, CRM e avisos serão invisíveis para a equipe.

---

## 2. Sentry — Configuração

| Plataforma | Configurado? | Funciona para OS? |
|------------|-------------|-------------------|
| Flutter App | ✅ `lib/main.dart` + `lib/core/logging/logger.dart` | ❌ Novas features não chamam `AppLogger` |
| Portal Next.js | ✅ `portal/src/lib/logger.ts` wraps `@sentry/nextjs` | ❌ Novas pages SSR não chamam `logger.error()` |

### O que chega ao Sentry hoje

- ✅ Erros de auth, sync, push, Strava, leaderboard
- ✅ Role desconhecido (`AppLogger.warn` no `coachingRoleFromString`)
- ✅ Portal: clearing, custody, distribute-coins
- ❌ **Nenhum** erro de: treinos, presença, CRM, avisos, KPIs

---

## 3. RPC Failure Logging

| Repo | Loga context? | O que falta |
|------|--------------|-------------|
| `remote_token_intent_repo.dart` (antigo) | ✅ `AppLogger.error('RPC failed', tags: {intentId, action})` | Nada — bom exemplo |
| `supabase_training_session_repo.dart` (novo) | ❌ Zero logging | `AppLogger.error('training_session query failed', tags: {groupId, error})` |
| `supabase_training_attendance_repo.dart` (novo) | ❌ Zero logging | `AppLogger.error('mark_attendance failed', tags: {sessionId, athleteId})` |
| `supabase_crm_repo.dart` (novo) | ❌ Zero logging | `AppLogger.error('crm query failed', tags: {groupId, action})` |
| `supabase_announcement_repo.dart` (novo) | ❌ Zero logging | `AppLogger.error('announcement query failed', tags: {groupId})` |

---

## 4. `_role_migration_audit` Table

| Aspecto | Status |
|---------|--------|
| Definida na spec/migration | ✅ `20260303300000_fix_coaching_roles.sql` cria `_role_migration_audit` |
| Populada no backfill | ✅ Registra anomalias de role |
| Padrão reutilizado para OS-01/02/03 | ❌ **Não existe audit table para treinos, CRM ou avisos** |

**Recomendação**: Criar `coaching_audit_log` genérico:
```sql
CREATE TABLE IF NOT EXISTS public.coaching_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  group_id uuid NOT NULL,
  user_id uuid NOT NULL,
  action text NOT NULL,  -- 'session_created', 'attendance_marked', 'note_added', etc.
  entity_type text NOT NULL,  -- 'training_session', 'announcement', etc.
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_group_time ON coaching_audit_log (group_id, created_at DESC);
```

---

## 5. Silent Catch Blocks

### Flutter App — Catch blocks que não logam

| Arquivo | Catch | Comportamento | Severidade |
|---------|-------|---------------|------------|
| 7 novos BLoCs | `catch (e) { emit(ErrorState(e.toString())) }` | Mostra erro na UI mas **não loga** | **P0** |
| 4 novos Repos | Sem try/catch — `PostgrestException` sobe raw | Exception não capturada, não logada | **P0** |

### Flutter App — Catch blocks intencionalmente silent (antigos, safe)

Nenhum encontrado que seja realmente "silencioso" — todos antigos ou emitem state ou logam.

### Supabase Edge Functions

| Arquivo | Pattern | Aceitável? |
|---------|---------|------------|
| `challenge-join/index.ts` | `catch { // Push is best-effort }` | ✅ Fire-and-forget push |
| `champ-invite/index.ts` | `catch { /* non-blocking */ }` | ✅ |
| `evaluate-badges/index.ts` | `catch { /* fire-and-forget */ }` | ✅ |
| `lifecycle-cron/index.ts` | 5 silent catches para ops non-critical | ⚠️ **P2** — deveria `console.warn` |
| `clearing-cron/index.ts` | `catch { custodyFailed++ }` | ✅ Contabilizado |

### Portal

| Arquivo | Pattern | Severidade |
|---------|---------|------------|
| `crm/crm-filters.tsx` | `.catch(() => {})` | **P2** — swallows tag fetch error |
| `settings/branding-form.tsx` | `.catch(() => setLoading(false))` | **P2** — no error shown |
| `risk-actions.tsx` | `console.error(...)` | **P2** — deveria usar `logger.error()` |
| Todas as pages SSR novas (6+) | **Sem try/catch** | **P1** — crash on Supabase error |

---

## 6. Portal Error Logging

| Componente | Usa `logger`? | Status |
|------------|--------------|--------|
| `lib/logger.ts` | N/A — é o próprio logger | ✅ Existe |
| `lib/audit.ts` | ✅ Audit log to DB + Sentry | ✅ |
| API routes antigos (clearing, custody, etc.) | ✅ `logger.error(...)` | ✅ |
| **API routes novos** (export/engagement, crm/notes, crm/tags) | ❌ | **P1** |
| **SSR pages novas** (attendance, crm, announcements, risk, exports) | ❌ | **P1** |
| `risk-actions.tsx` | ❌ (usa `console.error`) | **P2** |

---

## 7. Resumo de Findings

| # | Prioridade | Finding | Impacto | Patch |
|---|-----------|---------|---------|-------|
| O01 | **P0** | Zero AppLogger nos 7 BLoCs e 4 repos novos (OS-01/02/03) | Erros de produção invisíveis — Sentry nunca vê falhas de treinos, CRM, avisos | Adicionar `AppLogger.error()` em cada catch, com `tags: {groupId, entityId}` |
| O02 | **P1** | Portal SSR pages sem try/catch | Crash branco quando Supabase falha | Wrap queries em try/catch + `logger.error()` + `<ErrorFallback>` |
| O03 | **P1** | Portal API routes novos sem logging | Falhas de export/CRM não rastreáveis | Adicionar `logger.error()` em catches |
| O04 | **P2** | `risk-actions.tsx` usa `console.error` em vez de `logger` | Não vai para Sentry | Trocar por `logger.error()` |
| O05 | **P2** | 2 silent `.catch(() => {})` no portal | Tag fetch e branding errors silenciados | Adicionar `.catch((e) => logger.warn('...', e))` |
| O06 | **P2** | `lifecycle-cron` 5 silent catches | Ops failed sem trace | Adicionar `console.warn()` |
| O07 | **P2** | Sem audit table para OS-01/02/03 mutations | Sem rastreabilidade de quem criou/editou treinos, avisos | Criar `coaching_audit_log` (recomendado, não bloqueador) |
| O08 | **P3** | `_role_migration_audit` não reutilizado para novos módulos | Spec-code drift | Documentar como "one-time migration audit" |

---

## 8. Patch Recomendado (P0)

### Template para adicionar logging nos repos novos

```dart
// supabase_training_session_repo.dart
import 'package:omni_runner/core/logging/logger.dart';

class SupabaseTrainingSessionRepo implements ITrainingSessionRepo {
  @override
  Future<List<TrainingSessionEntity>> listByGroup(String groupId) async {
    try {
      final res = await _client
          .from('coaching_training_sessions')
          .select()
          .eq('group_id', groupId)
          .order('starts_at', ascending: false);
      return (res as List).map((e) => TrainingSessionEntity.fromMap(e)).toList();
    } catch (e, st) {
      AppLogger.error(
        'listByGroup failed',
        error: e,
        stackTrace: st,
        tags: {'groupId': groupId, 'repo': 'TrainingSession'},
      );
      rethrow;
    }
  }
}
```

### Template para BLoCs

```dart
// training_list_bloc.dart
on<LoadTrainings>((event, emit) async {
  emit(TrainingListLoading());
  try {
    final sessions = await listTrainingSessions(event.groupId);
    emit(TrainingListLoaded(sessions));
  } catch (e, st) {
    AppLogger.error(
      'LoadTrainings failed',
      error: e,
      stackTrace: st,
      tags: {'groupId': event.groupId},
    );
    emit(TrainingListError(e.toString()));
  }
});
```
