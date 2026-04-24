---
id: L05-29
audit_ref: "5.29"
lens: 5
title: "Atleta não tem tela 'Meus envios ao relógio' (histórico de .fit)"
severity: medium
status: fix-pending
wave: 0
discovered_at: 2026-04-24
fixed_at: null
closed_at: null
tags: ["workout", "athlete", "fit-export", "delivery-confirmation", "ui"]
files:
  - omni_runner/lib/domain/entities/athlete_workout_export_entity.dart
  - omni_runner/lib/data/services/athlete_export_history_service.dart
  - omni_runner/lib/presentation/screens/athlete_my_exports_screen.dart
  - omni_runner/lib/core/di/data_module.dart
  - omni_runner/lib/core/router/app_router.dart
  - omni_runner/lib/presentation/screens/more_screen.dart
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/entities/athlete_workout_export_entity_test.dart
linked_issues: []
linked_prs: []
owner: platform-workout
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-29] Atleta não tem tela 'Meus envios ao relógio' (histórico de .fit)

> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 0 · **Status:** fix-pending

**Camada:** Flutter app (presentation + data)
**Personas impactadas:** atleta amador (não consegue auditar os próprios
envios ao relógio e não tem como reabrir um `.fit` que falhou), suporte
(não tem como guiar um atleta do tipo "puxei o treino mas não apareceu
no Garmin" sem compartilhar acesso ao portal do coach)

## Achado

A Wave B slice 2 (L05-26) montou a infra completa de *delivery
confirmation* para `.fit`:

- Tabela `coaching_workout_export_log` (insert-only, RLS dupla).
- Policy `athlete_export_log_select_own` já permite ao atleta ler as
  próprias rows.
- Edge Function `generate-fit-workout` loga `generated` e `failed` com
  `actor_user_id = auth.uid()` em cada push iniciado pelo app.
- Slice 3 (L05-27) populou `device_hint` automaticamente a partir de
  `v_athlete_watch_type`, então cada row já sabe dizer "enviado pro seu
  Garmin há 2h".

O Portal do coach expõe esse log na coluna "Relógio" da página de
atribuições (`/workouts/assignments`). O **atleta não tem superfície
equivalente** — as rows existem, a RLS deixa ele ler, mas no Flutter
não há nenhuma tela que consulte `coaching_workout_export_log`.

Concretamente isso significa:

- O atleta que tocou em "Enviar para o relógio" há dois dias não
  consegue ver "quando foi, pra qual treino, deu certo?".
- Se o push falhou (kind='failed', com error_code populado), o atleta
  não tem nenhuma mensagem de erro persistida. O snackbar original
  pode ter desaparecido antes dele ler.
- Não há caminho fácil pro atleta fazer um re-push de um treino antigo
  ("preciso refazer aquele treino de terça"), já que o ponto de entrada
  normal (`AthleteWorkoutDetailScreen`) exige contexto de dia corrente.

## Impacto

- Retenção: atleta que teve um push falho silencioso culpa o app/coach
  (não sabe diferenciar problema de relógio desconectado vs. bug do
  encoder). Sem tela pra auditar, não tem como ele mesmo triangular.
- Suporte: os tickets do tipo "o treino não chegou no relógio" hoje
  dependem do coach abrir o portal pro atleta. Quebra o modelo de
  atendimento "atleta se serve", que era uma promessa do app.
- Observabilidade do lado atleta: zero. O log existe, mas só o coach
  vê. Atleta voa no escuro.

Medium porque não bloqueia o fluxo feliz (enviar pro relógio funciona),
mas o loop de confiança não fecha — atleta manda e não tem como
confirmar depois. Isso fica pior em proporção direta ao % de atletas
self-serve (sem coach do lado monitorando).

## Correção proposta

### 1. Entity `AthleteWorkoutExport`

`omni_runner/lib/domain/entities/athlete_workout_export_entity.dart`:

```dart
class AthleteWorkoutExport {
  final String id;
  final String? templateId;
  final String? templateName;
  final String? assignmentId;
  final DateTime? scheduledDate;
  final String surface;       // 'app' | 'portal'
  final String kind;          // 'generated' | 'shared' | 'delivered' | 'failed'
  final String? deviceHint;   // garmin/coros/suunto/polar/apple_watch/wear_os/other
  final int? bytes;
  final String? errorCode;
  final DateTime createdAt;
  // ...
}
```

`fromJson` tolera shapes com/sem o join de `coaching_workout_templates`
e `coaching_workout_assignments` (ambos os joins podem voltar null por
RLS ou FK nula).

### 2. Service `AthleteExportHistoryService`

`omni_runner/lib/data/services/athlete_export_history_service.dart`:

```dart
Future<List<AthleteWorkoutExport>> listMyExports({
  int limit = 100,
  String? surfaceFilter, // null = todas
});
```

Consulta:

```
from('coaching_workout_export_log')
  .select('id, template_id, assignment_id, surface, kind, '
          'device_hint, bytes, error_code, created_at, '
          'coaching_workout_templates(name), '
          'coaching_workout_assignments(scheduled_date)')
  .eq('actor_user_id', <uid>)
  .order('created_at', ascending: false)
  .limit(limit)
```

O `.eq` em `actor_user_id` é redundante com a RLS, mas ajuda o planner
a escolher o índice `idx_export_log_actor` e protege caso a RLS seja
flexibilizada no futuro.

### 3. Screen `AthleteMyExportsScreen`

Caminho: `/workouts/my-exports`.

Exibe cards agrupados por status:

- `generated` / `delivered` → card branco/verde: template_name, "Enviado
  ao seu Garmin há 2h", surface.
- `failed` → card vermelho: template_name, error_code humanizado, CTA
  "Tentar novamente".
- Vazio → empty-state "Você ainda não enviou nenhum treino pro relógio".
- Estado de loading e erro via `AppLoadingState` / `ErrorState` (mesmo
  padrão de `AthleteDeliveryScreen`).

RefreshIndicator para pull-to-refresh.

### 4. MoreScreen — tile novo

Na seção "Treinos" (não-staff), adicionar:

```
Meus envios ao relógio
Histórico de treinos que você mandou pro seu relógio (.fit)
```

Ícone sugerido: `Icons.watch_outlined`. Rota: `AppRoutes.myExports`.

### 5. DI + rota

- `data_module.dart`: `registerLazySingleton<AthleteExportHistoryService>`.
- `app_router.dart`: `AppRoutes.myExports = '/workouts/my-exports'` +
  `GoRoute` apontando para `AthleteMyExportsScreen`.

## Teste de regressão

Unitários da entity (`athlete_workout_export_entity_test.dart`):

- `fromJson` com join completo (template + assignment) → preenche tudo.
- `fromJson` sem join de template (RLS bloqueou) → `templateName = null`.
- `fromJson` sem join de assignment → `scheduledDate = null`.
- `fromJson` com `device_hint` desconhecido → coerce para `other`.
- `statusLabel` e `deviceLabel` retornam strings em pt-BR corretas.
- `isFailure` é true só para `kind='failed'`.

Manual:
- Atleta puxa treino → aparece na tela como "Enviado ao Garmin, agora".
- Atleta força erro (offline) → aparece como "Falhou, erro XYZ" com
  CTA de re-tentar.

## Cross-refs

- L05-26 (fixed) — tabela `coaching_workout_export_log`.
- L05-27 (fixed) — device_hint autofill.
- L22-10 (fixed, deferred) — quando WorkoutKit/Connect IQ pingar
  `delivered`, essa tela exibe naturalmente (o entity já lê `kind`).

## Histórico

- `2026-04-24` — Descoberto ao revisar Wave B concluída, notei que
  expusemos o log pro coach mas não pro atleta.
