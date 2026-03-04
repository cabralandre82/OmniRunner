# Workout Delivery — Arquitetura Técnica

## Tabelas

### workout_delivery_batches
Agrupa itens de entrega por período. Multi-tenant via `group_id`.
- Status flow: `draft` → `publishing` → `published` → `closed`

### workout_delivery_items
Item individual: 1 treino atribuído para 1 atleta.
- FK → `coaching_workout_assignments`
- Status flow: `pending` → `published` → `confirmed` | `failed`
- `export_payload` (jsonb): representação completa do treino (template name, blocks, dates)
- UNIQUE constraint: `(batch_id, athlete_user_id, assignment_id)` para idempotência

### workout_delivery_events
Audit trail. Cada ação gera 1 evento.
- Types: `BATCH_CREATED`, `MARK_PUBLISHED`, `ATHLETE_CONFIRMED`, `ATHLETE_FAILED`, `STAFF_NOTE`

## RLS
- Staff (admin_master, coach, assistant): full access dentro do group_id
- Atleta: SELECT apenas itens próprios; INSERT eventos apenas em itens próprios; UPDATE direto proibido
- Confirmação apenas via RPC `fn_athlete_confirm_item`

## RPCs (SECURITY DEFINER, search_path = public)
| Função | Caller | Descrição |
|--------|--------|-----------|
| `fn_create_delivery_batch(group_id, period_start?, period_end?)` | Staff | Cria batch, emite evento BATCH_CREATED |
| `fn_generate_delivery_items(batch_id)` | Staff | Gera items set-based a partir de assignments planned, retorna count |
| `fn_mark_item_published(item_id, note?)` | Staff | Status → published, idempotente |
| `fn_athlete_confirm_item(item_id, result, reason?, note?)` | Atleta | Status → confirmed/failed, idempotente |

## Portal
- Página: `/delivery` (server component + client actions)
- Components: `CreateBatchForm`, `GenerateItemsButton`, `PublishButton`, `CopyPayloadButton`
- Data fetching via `createClient()` (RLS-aware)

## App (Flutter)
- Tela: `AthleteDeliveryScreen` — lista entregas pendentes para o atleta
- Entrada: badge no AppBar de `athlete_workout_day_screen.dart` + item em `more_screen.dart`
- Chama RPCs via `Supabase.instance.client.rpc()`

## Diagrama de Fluxo
```
Coach atribui treino → Cria batch → Gera itens (set-based)
    ↓
Coach copia payload → Publica no Treinus → Marca publicado
    ↓
Atleta vê no app → Confirma "apareceu" ou "não apareceu"
    ↓
Dashboard mostra métricas por status
```

## Feature Flag
`trainingpeaks_enabled` controla a integração TP (OFF por padrão).
O Workout Delivery é o caminho principal e não depende de flag.
