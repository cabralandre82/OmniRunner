# Inventário: TrainingPeaks & Workout Delivery

## 1. Arquivos TrainingPeaks (paths reais)

### Migration
| Path | Propósito |
|------|-----------|
| `supabase/migrations/20260304800000_trainingpeaks_integration.sql` | Cria `coaching_tp_sync`, RPCs `fn_push_to_trainingpeaks` / `fn_tp_sync_status`, estende CHECK constraints em device_links e executions |

### Edge Functions
| Path | Propósito |
|------|-----------|
| `supabase/functions/trainingpeaks-oauth/index.ts` | OAuth 2.0 flow (authorize, token exchange, refresh) |
| `supabase/functions/trainingpeaks-sync/index.ts` | Push/pull sync de treinos com API TrainingPeaks |

### Portal
| Path | Propósito |
|------|-----------|
| `portal/src/app/(portal)/trainingpeaks/page.tsx` | Página de status de sync e atletas vinculados |
| `portal/src/app/(portal)/trainingpeaks/loading.tsx` | Loading skeleton |
| `portal/src/components/sidebar.tsx` (linha 35) | Item de navegação "TrainingPeaks" |

### App (Flutter)
| Path | Propósito |
|------|-----------|
| `omni_runner/lib/domain/usecases/wearable/push_to_trainingpeaks.dart` | Use case para chamar RPC de sync |
| `omni_runner/lib/domain/entities/device_link_entity.dart` | Enum `DeviceProvider` inclui `trainingpeaks` |
| `omni_runner/lib/presentation/screens/staff_workout_assign_screen.dart` | Dialog "Sincronizar com TrainingPeaks?" pós-assign |
| `omni_runner/lib/presentation/screens/athlete_device_link_screen.dart` | Provider "trainingpeaks" na lista |
| `omni_runner/lib/features/integrations_export/presentation/export_screen.dart` | Menciona TP como destino de export |
| `omni_runner/lib/features/integrations_export/presentation/how_to_import_screen.dart` | Instruções de import para TP |

### Config
| Path | Propósito |
|------|-----------|
| `.env.example` | Vars `TRAININGPEAKS_CLIENT_ID/SECRET/REDIRECT_URI` |

### Docs (24 arquivos mencionam TP)
Principais: `TRAININGPEAKS_INTEGRATION.md`, `PHASE_14_INTEGRATIONS.md`, QA gates 0-12

## 2. Feature Flag System (já existente)
| Camada | Path |
|--------|------|
| DB table | `feature_flags` (key, enabled, rollout_pct) |
| App | `omni_runner/lib/core/config/feature_flags.dart` → `FeatureFlagService.isEnabled(key)` |
| Portal | `portal/src/lib/feature-flags.ts` → `isFeatureEnabled(key, userId?)` |
| Admin UI | `portal/src/app/platform/feature-flags/page.tsx` |

**Proposta**: Inserir flag `trainingpeaks_enabled` (enabled=false, rollout_pct=0) via migration.

## 3. Modelo de Workout existente
- `coaching_workout_templates` — templates de treino
- `coaching_workout_blocks` — blocos (warmup, interval, etc.)
- `coaching_workout_assignments` — atribuição atleta + data (UNIQUE por atleta/dia)
- `coaching_workout_executions` — execução registrada
- RPC: `fn_assign_workout(template_id, athlete_user_id, scheduled_date, notes)`

## 4. Arquivos que serão alterados por fase

### FASE 1 (Flag)
- `supabase/migrations/NEW_flag_trainingpeaks.sql` (NEW)
- Nenhum arquivo existente alterado

### FASE 2 (Freeze TP)
- `portal/src/components/sidebar.tsx` — condicionar item TP à flag
- `portal/src/app/(portal)/trainingpeaks/page.tsx` — guard por flag
- `omni_runner/lib/presentation/screens/staff_workout_assign_screen.dart` — condicionar dialog TP
- `omni_runner/lib/presentation/screens/athlete_device_link_screen.dart` — ocultar provider TP
- `supabase/functions/trainingpeaks-oauth/index.ts` — check flag
- `supabase/functions/trainingpeaks-sync/index.ts` — check flag

### FASE 3 (DB Delivery)
- `supabase/migrations/NEW_workout_delivery.sql` (NEW)

### FASE 4 (Portal Delivery)
- `portal/src/app/(portal)/delivery/page.tsx` (NEW)
- `portal/src/components/sidebar.tsx` — adicionar "Entrega Treinos"

### FASE 5 (App Delivery)
- `omni_runner/lib/presentation/screens/athlete_workout_day_screen.dart` — adicionar seção confirmação
- RPCs novas no Supabase

### FASE 6 (Swap fluxo)
- `omni_runner/lib/presentation/screens/staff_workout_assign_screen.dart` — trocar CTA TP por Delivery

### FASE 7 (QA + docs)
- docs/TRAININGPEAKS_FROZEN.md (NEW)
- docs/WORKOUT_DELIVERY_RUNBOOK.md (NEW)
- docs/WORKOUT_DELIVERY_ARCH.md (NEW)
- docs/DECISION_TP_FROZEN_AND_TREINUS_DELIVERY.md (NEW)
