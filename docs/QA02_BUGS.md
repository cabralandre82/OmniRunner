# QA-02 — Bugs de Integração Front/Back

## P0 — Bloqueadores

| # | Bug | Arquivo | Evidência | Patch Sugerido |
|---|-----|---------|-----------|----------------|
| I01 | **Export engagement sem autenticação** — `/api/export/engagement` não chama `getSession()`. Usa `createServiceClient()` que bypassa RLS. Qualquer cookie `portal_group_id` forjado retorna CSV completo. | `portal/src/app/api/export/engagement/route.ts` | Ausência de `getSession()` no início da route handler | Adicionar auth check idêntico ao `/api/export/alerts/route.ts` |
| I02 | **Column mismatch `resolved` vs `is_read`** — Flutter entity define `resolved: bool`, Portal risk page filtra por `is_read`, migration cria coluna `resolved`. Queries vão falhar ou retornar empty silenciosamente. | App: entity, Portal: `risk/page.tsx`, DB: migration | Campo não alinhado entre as 3 camadas | Padronizar para `resolved` em todos os pontos |

## P1 — Importantes

| # | Bug | Arquivo | Evidência | Patch Sugerido |
|---|-----|---------|-----------|----------------|
| I03 | **9 repos Flutter sem try/catch** — `PostgrestException` sobe raw até o widget. Mensagens de erro como `PostgrestException: {code: 42501, message: ...}` são exibidas ao usuário. | `supabase_training_session_repo.dart`, `supabase_training_attendance_repo.dart`, `supabase_crm_repo.dart`, `supabase_announcement_repo.dart` | Nenhum `try/catch` nos métodos | Wrap em try/catch + `AppLogger.error()` + rethrow com mensagem user-friendly |
| I04 | **4 Portal SSR pages sem try/catch** — Se Supabase retorna erro, Next.js mostra error 500 genérico (crash branco). | `attendance/page.tsx`, `crm/page.tsx`, `announcements/page.tsx`, `risk/page.tsx` | Queries diretas sem try/catch no server component | Wrap em try/catch + `<ErrorFallback message="Falha ao carregar dados">` |
| I05 | **CRM notes aceita `groupId` do body** — Client pode enviar `groupId` diferente do cookie. RLS mitiga cross-group, mas viola defense-in-depth. | `portal/src/app/api/crm/notes/route.ts:20` | `const { groupId, ... } = await req.json()` — aceita do body | Usar `cookies().get('portal_group_id')` apenas |
| I06 | **CRM tags aceita `groupId` de query params** | `portal/src/app/api/crm/tags/route.ts:15` | `searchParams.get('groupId')` — aceita do client | Usar cookie |
| I07 | **QR nonce não validado** — `fn_mark_attendance` aceita `p_nonce text DEFAULT NULL` mas nunca valida. Anti-replay é placeholder. | `supabase/migrations/20260303400000_training_sessions_attendance.sql` | `p_nonce` parameter existe mas lógica de validação ausente | Documentar como "MVP: TTL-only" ou implementar validação HMAC |

## P2 — Melhorias

| # | Bug | Arquivo | Evidência | Patch Sugerido |
|---|-----|---------|-----------|----------------|
| I08 | **Attendance method hardcoded `'qr'`** — `fn_mark_attendance` sempre insere `method = 'qr'`, mas o schema permite outros valores. Presença manual futura vai precisar de alteração. | Migration OS-01 | `VALUES (..., 'qr')` hardcoded | Adicionar parâmetro `p_method text DEFAULT 'qr'` |
| I09 | **`FutureBuilder` per-card no training list** — `staff_training_list_screen` faz query `countBySession` dentro de `FutureBuilder` em cada card. N cards = N queries durante scroll. | `staff_training_list_screen.dart` | `FutureBuilder` dentro de `ListView.builder` | Batch: buscar counts em bulk no BLoC via `SELECT session_id, count(*) GROUP BY session_id` |
| I10 | **CRM tags API sem role check** — `/api/crm/tags` GET não verifica se o user é staff. Athlete com cookie válido pode listar tags (baixo impacto, mas inconsistente). | `portal/src/app/api/crm/tags/route.ts` | Ausência de `isStaff()` check | Adicionar `if (!isStaff(role)) return NextResponse.json({error: 'forbidden'}, {status: 403})` |
