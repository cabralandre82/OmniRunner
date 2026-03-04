# TrainingPeaks — Integração Congelada

## Status: FROZEN (feature flag OFF)

## Feature Flag
- **Key**: `trainingpeaks_enabled`
- **Table**: `feature_flags`
- **Default**: `enabled = false`, `rollout_pct = 0`
- **Set by**: Migration `20260305000000_workout_delivery.sql`

## O que está congelado
Todo o código TrainingPeaks continua no repositório mas está inacessível:

### Portal
- Item "TrainingPeaks" no sidebar oculto quando flag OFF (`portal/src/components/sidebar.tsx`)
- Página `/trainingpeaks` exibe "Funcionalidade indisponível" quando flag OFF (`portal/src/app/(portal)/trainingpeaks/page.tsx`)

### App (Flutter)
- Dialog "Sincronizar com TrainingPeaks?" no assign não aparece quando flag OFF (`staff_workout_assign_screen.dart`)
- Provider "trainingpeaks" filtrado da lista de device links quando flag OFF (`athlete_device_link_screen.dart`)

### Edge Functions
- `trainingpeaks-oauth/index.ts` retorna 403 TRAININGPEAKS_DISABLED quando flag OFF
- `trainingpeaks-sync/index.ts` retorna 403 TRAININGPEAKS_DISABLED quando flag OFF

### DB
- Tabela `coaching_tp_sync` e RPCs `fn_push_to_trainingpeaks`/`fn_tp_sync_status` continuam existindo
- Nenhum dado é deletado

## Como reativar (futuro)
1. Via portal admin: Platform → Feature Flags → `trainingpeaks_enabled` → ON
2. Ou via SQL: `UPDATE feature_flags SET enabled = true, rollout_pct = 100 WHERE key = 'trainingpeaks_enabled';`
3. Configurar env vars: `TRAININGPEAKS_CLIENT_ID`, `TRAININGPEAKS_CLIENT_SECRET`, `TRAININGPEAKS_REDIRECT_URI`
4. Testar OAuth flow com conta sandbox TP

## Arquivos TP preservados
- `supabase/migrations/20260304800000_trainingpeaks_integration.sql`
- `supabase/functions/trainingpeaks-oauth/index.ts`
- `supabase/functions/trainingpeaks-sync/index.ts`
- `portal/src/app/(portal)/trainingpeaks/page.tsx`
- `omni_runner/lib/domain/usecases/wearable/push_to_trainingpeaks.dart`
- `omni_runner/lib/domain/entities/device_link_entity.dart`
- `docs/TRAININGPEAKS_INTEGRATION.md`
