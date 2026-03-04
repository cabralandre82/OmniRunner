# Chaos de Dados — Relatório de Vulnerabilidades

**Escopo:** Análise do codebase para vulnerabilidades a dados inesperados (null, vazios, malformados, oversized, type mismatches).

**Repositório:** `/home/usuario/project-running`

---

## 1. NULL / UNDEFINED handling

### 1.1 Bang operators (`!`) em Flutter screens — risco de crash

| Arquivo | Linha | Contexto | Impacto | Severidade |
|---------|-------|----------|---------|------------|
| `omni_runner/lib/presentation/screens/today_screen.dart` | 416, 465-468, 476, 480, 488 | `_profile!`, `_lastRun!`, `_detectedPark!` após check `!= null` mas em callbacks/async podem dessincronizar | Crash se state mudar entre check e render | **MAJOR** |
| `omni_runner/lib/presentation/screens/today_screen.dart` | 254 | `lastRun.route.first` — se `lastRun` existe mas `route` vazio | RangeError | **CRITICAL** |
| `omni_runner/lib/presentation/screens/login_screen.dart` | 73, 116, 131, 155, 440 | `result.failure!`, `_errorMessage!` — failure pode ser null em alguns fluxos | Crash no login | **CRITICAL** |
| `omni_runner/lib/presentation/screens/run_replay_screen.dart` | 91, 133, 163-166, 181, 385 | `_mapCtrl!`, `revealed.last`, `replay.sprint!` | Crash se dados incompletos ou mapa não pronto | **MAJOR** |
| `omni_runner/lib/presentation/screens/wrapped_screen.dart` | 193-199 | `_data!` em múltiplos slides | Crash se dados não carregados | **MAJOR** |
| `omni_runner/lib/presentation/screens/run_details_screen.dart` | 134-135 | `_mapCtrl!` | Crash se controller null | **MINOR** |
| `omni_runner/lib/presentation/screens/profile_screen.dart` | 463 | `_error!` | Crash em estado de erro mal formado | **MINOR** |
| `omni_runner/lib/presentation/screens/staff_generate_qr_screen.dart` | 102-116, 153, 156 | `_capacity!`, `_badgeCapacity!` | Crash se capacity não carregado | **MAJOR** |
| `omni_runner/lib/presentation/screens/athlete_evolution_screen.dart` | 207, 211 | `selectedTrend!`, `selectedBaseline!` | Crash se seleção inválida | **MAJOR** |
| `omni_runner/lib/presentation/screens/event_details_screen.dart` | 28, 173 | `myParticipation!`, `event.targetValue!` | Crash em evento sem participação | **MAJOR** |
| `omni_runner/lib/presentation/screens/race_event_details_screen.dart` | 74, 78, 480 | `state.myParticipation!`, `state.myResult!`, `event.targetDistanceM!` | Crash em race sem resultado | **MAJOR** |
| `omni_runner/lib/presentation/screens/staff_crm_list_screen.dart` | 419-422, 534, 751 | `athlete.avatarUrl!`, `parts[0][0]`, `_error!` — `parts` pode ter 1 elemento vazio | Crash ou RangeError | **MAJOR** |
| `omni_runner/lib/presentation/screens/staff_setup_screen.dart` | 862 | `barcode!.rawValue` | Crash se barcode null | **MINOR** |
| `omni_runner/lib/presentation/screens/join_assessoria_screen.dart` | 943 | `barcode!.rawValue` | Idem | **MINOR** |
| `omni_runner/lib/presentation/screens/cached_avatar.dart` | 69 | `parts.first[0]`, `parts.last[0]` — nome com 1 parte só causa `parts.last` = same | OK se `parts.length >= 2`; se `parts = [""]` → crash | **MINOR** |
| `omni_runner/lib/presentation/screens/profile_screen.dart` | 73 | `displayName[0]` — displayName vazio | RangeError | **MINOR** |
| `omni_runner/lib/presentation/screens/athlete_dashboard_screen.dart` | 105 | `name[0]` — name vazio | RangeError | **MINOR** |

### 1.2 Acesso desprotegido a `.data` em respostas Supabase

| Arquivo | Linha | Contexto | Impacto | Severidade |
|---------|-------|----------|---------|------------|
| `omni_runner/lib/data/repositories_impl/remote_token_intent_repo.dart` | 42 | `res.data as Map<String, dynamic>` — sem null check; se EF retornar erro, data pode ser null | Crash ao criar intent | **CRITICAL** |
| `omni_runner/lib/data/repositories_impl/supabase_challenges_remote_source.dart` | 23 | `res.data as Map<String, dynamic>?` — usado sem ?? {} em alguns fluxos | Dados inesperados | **MAJOR** |
| `omni_runner/lib/presentation/screens/matchmaking_screen.dart` | 239, 290 | `res.data as Map<String, dynamic>?` — usado diretamente sem fallback em alguns caminhos | NullPointer ou crash | **MAJOR** |
| `portal/src/app/(portal)/custody/page.tsx` | 28 | `accountRes.data` — `accountRes` pode ter `error`; `data` pode ser null com maybeSingle | `account` undefined em loops; uso de `account?.` mitiga parcialmente | **MINOR** |
| `portal/src/app/(portal)/settings/page.tsx` | 114 | `accountRes.data` sem null check | Possível crash em UI | **MINOR** |
| `portal/src/app/(portal)/badges/page.tsx` | 31 | `inventoryRes.data` | Idem | **MINOR** |

**Nota:** Maioria dos usos em Flutter usa `res.data as Map? ?? {}` — ok. O `remote_token_intent_repo` é exceção crítica.

### 1.3 Navegação — argumentos não verificados

| Arquivo | Linha | Contexto | Impacto | Severidade |
|---------|-------|----------|---------|------------|
| Busca por `ModalRoute.of(context)?.settings.arguments` | — | **Nenhum uso encontrado** no codebase | N/A | — |
| `omni_runner/lib/features/watch_bridge/watch_bridge.dart` | 121 | `call.arguments` — método channel; sem validação de tipo | Crash se platform envia tipo inesperado | **MINOR** |

### 1.4 Edge functions — validação de parâmetros

| Arquivo | Linha | Contexto | Impacto | Severidade |
|---------|-------|----------|---------|------------|
| `supabase/functions/trainingpeaks-sync/index.ts` | 101 | `const body = await req.json();` — sem try/catch; `body.action` sem validação | Crash se JSON inválido; undefined action | **CRITICAL** |
| `supabase/functions/trainingpeaks-oauth/index.ts` | 182 | `const body = await req.json();` — sem try/catch | Crash em JSON malformado | **MAJOR** |
| `supabase/functions/strava-register-webhook/index.ts` | 37 | `const body = await req.json();` | Idem | **MAJOR** |
| `supabase/functions/notify-rules/index.ts` | 104 | `body = await req.json();` | Idem | **MAJOR** |
| `supabase/functions/champ-lifecycle/index.ts` | 74 | Idem | Idem | **MAJOR** |
| `supabase/functions/send-push/index.ts` | 80 | `payload = await req.json();` | Idem | **MAJOR** |
| `supabase/functions/validate-social-login/index.ts` | 42 | `body = await req.json();` | Idem | **MAJOR** |

**Exceções (com try/catch):**
- `webhook-mercadopago`: try/catch em 159-165 para body JSON
- `strava-webhook`: try/catch em 86-90 para `req.json()`

---

## 2. EMPTY LISTS / ARRAYS

### 2.1 `.first`, `.last`, `.single` sem checagem de segurança

| Arquivo | Linha | Contexto | Impacto | Severidade |
|---------|-------|----------|---------|------------|
| `omni_runner/lib/presentation/screens/today_screen.dart` | 254 | `lastRun.route.first` — route pode ser vazio | RangeError | **CRITICAL** |
| `omni_runner/lib/presentation/screens/run_summary_screen.dart` | 98-99 | `_coords.first` — protegido por `_coords.length < 2` antes | OK | — |
| `omni_runner/lib/presentation/screens/run_details_screen.dart` | 151-152 | `_coords.first` — sem check de length | RangeError se _coords vazio | **MAJOR** |
| `omni_runner/lib/presentation/screens/run_replay_screen.dart` | 125-126, 165 | `widget.points.first`, `revealed.last` — points/revealed vazios | RangeError | **MAJOR** |
| `omni_runner/lib/data/datasources/remote_profile_datasource.dart` | 36, 68 | `rows.first` — sem isEmpty check | Crash se query vazia | **CRITICAL** |
| `omni_runner/lib/presentation/screens/announcement_feed_screen.dart` | 64 | `stream.first` — Bloc stream; pode nunca emitir | Timeout/hang | **MINOR** |
| `omni_runner/lib/presentation/screens/staff_setup_screen.dart` | 379 | `list.first` — após fetch group by invite; list pode vir vazio | Crash | **MAJOR** |
| `omni_runner/lib/presentation/screens/join_assessoria_screen.dart` | 545, 579 | `list.first` — idem | Crash | **MAJOR** |
| `omni_runner/lib/presentation/screens/auth_gate.dart` | 143 | `list.first` — lista de grupos | Crash se sem grupos | **MAJOR** |
| `omni_runner/lib/presentation/screens/staff_scan_qr_screen.dart` | 85 | `barcodes.first` — sem isEmpty | Crash se nenhum barcode | **MINOR** |
| `omni_runner/lib/presentation/screens/staff_training_scan_screen.dart` | 109 | Idem | Idem | **MINOR** |
| `omni_runner/lib/features/wearables_ble/ble_heart_rate_source.dart` | 218, 223, 295, 300 | `firstWhere` em services/characteristics — StateError se não encontrar | Crash em BLE | **MAJOR** |
| `omni_runner/lib/data/repositories_impl/supabase_progression_remote_source.dart` | 126 | `rows.first` — sem check | Crash | **MAJOR** |
| `omni_runner/lib/data/repositories_impl/supabase_leaderboard_repo.dart` | 44 | `lbRows.first` — sem check | Crash | **MAJOR** |
| `omni_runner/lib/presentation/blocs/my_assessoria/my_assessoria_bloc.dart` | 58 | `atletaMembership.first` — sem isEmpty | Crash se membership vazio | **MAJOR** |

### 2.2 `list[0]` ou `list[index]` sem bounds checking

| Arquivo | Linha | Contexto | Impacto | Severidade |
|---------|-------|----------|---------|------------|
| `omni_runner/lib/presentation/screens/challenge_details_screen.dart` | 1441-1442 | `items[0]` — há check `isEmpty` antes; OK | — | — |
| `omni_runner/lib/presentation/screens/athlete_my_evolution_screen.dart` | 65 | `results[0]` — results de Future.wait; sem garantia de length | Crash | **MAJOR** |
| `omni_runner/lib/presentation/screens/friend_profile_screen.dart` | 81 | `results[0]` — idem | Crash | **MAJOR** |
| `omni_runner/lib/presentation/screens/leaderboards_screen.dart` | 61 | `results[0]` — profileRes | Possível null/undefined | **MAJOR** |
| `omni_runner/lib/presentation/screens/staff_crm_list_screen.dart` | 534-536 | `parts[0][0]`, `parts[1][0]` — `parts` de split; parts[0] vazio → crash | RangeError | **MAJOR** |
| `omni_runner/lib/core/deep_links/deep_link_handler.dart` | 107, 180 | `uri.pathSegments[0]` — path vazio | RangeError | **MINOR** |
| `omni_runner/lib/presentation/screens/matchmaking_screen.dart` | 704 | `(m['display_name'] as String)[0]` — display_name null ou vazio | Crash | **MAJOR** |
| `omni_runner/lib/presentation/screens/partner_assessorias_screen.dart` | 197, 579 | `p.partnerName[0]`, `r.groupName[0]` — string vazia | RangeError | **MINOR** |
| `omni_runner/lib/presentation/screens/friends_activity_feed_screen.dart` | 261 | `item.displayName[0]` — vazio | RangeError | **MINOR** |

### 2.3 Listas renderizadas sem empty-state

| Arquivo | Contexto | Impacto | Severidade |
|---------|----------|---------|------------|
| Múltiplas telas | Uso de `ListView.builder` com `itemCount: list.length` — lista vazia = 0 items, não crash | Geralmente OK | — |
| `omni_runner/lib/presentation/screens/announcement_feed_screen.dart` | Feed de anúncios — depende do Bloc; se loaded com items vazios, mostra lista vazia | UX pobre sem empty state | **MINOR** |
| Portal | Maioria usa `data ?? []` — safe | OK | — |

### 2.4 Supabase `.select()` com resultado vazio

- Flutter: `.maybeSingle()` retorna null; `.single()` lança se 0 ou >1.
- Uso de `.single()` em vários repos (supabase_financial_repo, supabase_workout_repo, etc.) pode lançar se expectativa for 1 e vier 0.
- **Impacto:** Erro de runtime, não crash silencioso.

---

## 3. OVERSIZED DATA

### 3.1 Paginação e limites

| Área | Limite | Contexto | Impacto |
|------|--------|----------|---------|
| Sessions | Diversos `.limit(50)`, `.limit(100)` | Repos de CRM, announcements, workouts, analytics | ✅ Limites presentes |
| Wallet ledger | `.limit(200)` | supabase_wallet_remote_source.dart | Ok |
| Leaderboard | `.limit(200)` | supabase_leaderboard_repo | Ok |
| Today screen | `.limit(5)` | Desafios/campeonatos ativos | Ok |
| trainingpeaks-sync | `.limit(50)` | Sync pendentes | Ok; N+1 em loop pode causar timeout |
| Portal custody | `.limit(50)` withdraw/deposits, `.limit(30)` settlements | Ok |
| **Sem LIMIT** | `portal/src/app/(portal)/custody/page.tsx` | `coin_ledger` sem limit: `db.from("coin_ledger").select("delta_coins").eq("issuer_group_id", groupId)` | Com muitas transações, resposta pode ser enorme | **MAJOR** |
| Portal clearing/audit | Queries com `.limit()` implícito ou não | Verificar export/clearing | **MINOR** |

### 3.2 Display names e textos longos

| Contexto | Limite DB | Truncamento UI |
|----------|-----------|----------------|
| `profiles.display_name` | TEXT (sem limite) | Nenhum truncamento em vários cards |
| 100+ caracteres | Aceito pelo DB | Pode quebrar layout em chips/avatares |
| `cached_avatar.dart` | `parts.first[0]` assume pelo menos 1 char | Nome vazio já é risco |
| Portal CRM | `a.last_note.slice(0, 50)` | ✅ Truncamento presente |

**Impacto:** Layout quebrado, overflow em chips. Severidade **MINOR**.

### 3.3 Notas/descrições longas

- `training_sessions.description`, `workout_templates.description` — TEXT sem limite.
- Sem truncamento em algumas telas (staff_training_detail_screen usa `session.description!`).
- **Impacto:** Overflow de texto. **MINOR**.

---

## 4. MALFORMED JSON

### 4.1 Edge functions — `req.json()` sem tratamento

| Arquivo | Linha | Tratamento | Impacto |
|---------|-------|------------|---------|
| `trainingpeaks-sync/index.ts` | 101 | Nenhum | **CRITICAL** — throw não tratado |
| `trainingpeaks-oauth/index.ts` | 182 | Nenhum | **MAJOR** |
| `strava-register-webhook/index.ts` | 37 | Nenhum | **MAJOR** |
| `webhook-mercadopago/index.ts` | 161 | try/catch → 400 BAD_REQUEST | ✅ |
| `strava-webhook/index.ts` | 87 | try/catch → 400 Invalid JSON | ✅ |
| `create-checkout-mercadopago/index.ts` | 276 | `mpRes.json()` — sem try/catch | **MAJOR** |
| `strava-webhook/index.ts` | 158, 183, 199 | `refreshRes.json()`, `activityRes.json()`, `streamsRes.json()` | Se API Strava retornar não-JSON, crash | **MAJOR** |

### 4.2 Flutter — Supabase schema inesperado

- Uso extensivo de `as String`, `as int`, `as Map` em parsing de rows.
- Se Supabase retornar tipo diferente (ex: number como string), `DateTime.parse` ou cast falha.
- Ex.: `staff_disputes_screen.dart` — `DateTime.parse(r['deadline_at'] as String)` — se vier number, crash.
- **Impacto:** Crash em telas que parseiam dados. **MAJOR** em fluxos críticos.

### 4.3 Portal — API routes e body inválido

- Uso de `parsed.data` após validação com schema (zod ou similar) em várias rotas.
- Rotas que não validam: risco de `parsed.data` com campos inesperados.
- Ex.: `portal/src/app/api/custody/withdraw/route.ts` — `parsed.data.amount_usd` etc. Se schema falhar, `parsed` pode ter error; código assume success.

---

## 5. TYPE MISMATCHES

### 5.1 Casts inseguros

| Arquivo | Padrão | Risco |
|---------|--------|-------|
| `staff_disputes_screen.dart` | `r['id'] as String`, `r['tokens_total'] as int` | Se DB retornar null ou tipo errado → crash |
| `supabase_wearable_repo.dart` | Múltiplos `r['x'] as String` em map de rows | Idem |
| `supabase_financial_repo.dart` | `r['billing_cycle'] as String`, `DateTime.parse(r['created_at'] as String)` | Idem |
| `core/offline/offline_queue.dart` | `json['params'] as Map`, `json['timestamp'] as String` | Malformed queue entry → crash no replay |
| `remote_token_intent_repo.dart` | `data['expires_at'] as String` | EF pode retornar formato diferente |

### 5.2 `int.parse` / `double.parse` sem try/catch

| Arquivo | Linha | Contexto | Impacto |
|---------|-------|----------|---------|
| `staff_crm_list_screen.dart` | 345, 569, 803 | `int.parse('FF$c', radix: 16)` — `c` pode ser inválido (ex: "GG") | FormatException |
| `staff_championship_templates_screen.dart` | 638 | `int.parse(maxText)` — usuário pode digitar não-numérico | FormatException |
| `athlete_my_evolution_screen.dart` | 236 | `int.parse(hex.substring(1), radix: 16)` — hex malformado | FormatException |
| `athlete_log_execution_screen.dart` | 60 | `int.parse(_durationCtrl.text.trim())` — campo vazio ou texto | FormatException |
| `staff_athlete_profile_screen.dart` | 623 | `int.parse('FF$c', radix: 16)` | FormatException |

### 5.3 DateTime parsing

| Arquivo | Padrão | Risco |
|---------|--------|-------|
| Diversos | `DateTime.parse(x as String)` | Invalid format → crash |
| Diversos | `DateTime.tryParse(...)` | ✅ Safe |
| `staff_disputes_screen.dart` | `DateTime.parse(r['deadline_at'] as String)` | Crash se formato inválido |
| `supabase_financial_repo.dart` | Múltiplos `DateTime.parse` | Idem |

---

## Resumo de Severidades

| Severidade | Quantidade |
|------------|------------|
| CRITICAL   | 6          |
| MAJOR      | 38         |
| MINOR      | 20         |

### Top 5 prioridades

1. **`remote_token_intent_repo.dart`** — `res.data` sem null check → crash ao criar QR/token intent.
2. **`trainingpeaks-sync`** — `req.json()` sem try/catch → crash em POST malformado.
3. **`today_screen.dart`** — `lastRun.route.first` com route vazio → RangeError.
4. **`remote_profile_datasource.dart`** — `rows.first` sem isEmpty → crash em perfil vazio.
5. **`run_details_screen.dart`** / **`run_replay_screen.dart`** — `_coords.first` / `points.first` sem guard → crash com sessão sem pontos.
