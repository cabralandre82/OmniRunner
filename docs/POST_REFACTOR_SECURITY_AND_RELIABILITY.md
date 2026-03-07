# POST_REFACTOR_SECURITY_AND_RELIABILITY.md

> Data: 2026-03-07

---

## 1. SEGURANÇA

| Verificação | Resultado | Notas |
|---|---|---|
| Secrets hardcoded em .dart? | ✅ NENHUM | Tudo via String.fromEnvironment() |
| .env files no .gitignore? | ✅ SIM | .env.dev e .env.prod ignorados |
| Supabase keys são anon (público)? | ✅ SIM | Anon key = safe para client-side |
| Strava client_secret no .env? | ⚠️ PARCIAL | Está em .env.prod mas compilado no app — aceitável para mobile OAuth |
| RLS ativo no Postgres? | ✅ SIM | Políticas em todas as tabelas |
| Auth tokens gerenciados por Supabase? | ✅ SIM | Token refresh automático |
| FlutterSecureStorage para dados sensíveis? | ✅ SIM | Encryption key, Strava tokens |
| Isar encriptado? | ❌ NÃO | Key existe mas Isar 3.1 não suporta |
| Portal CSRF protection? | ✅ SIM | csrf.ts implementado |
| Portal rate limiting? | ✅ SIM | Redis/in-memory fallback |
| Portal CSP headers? | ✅ SIM | middleware.ts |
| Error messages vazam detalhes? | ⚠️ PARCIAL | 3-4 screens mostram e.toString() raw |

---

## 2. CONFIABILIDADE

| Cenário | Resultado | Notas |
|---|---|---|
| Backend indisponível | ✅ RESILIENTE | Offline queue + local-first data |
| Supabase não inicializado | ✅ SAFE | AppConfig.isSupabaseReady guard |
| Dados locais corrompidos | ⚠️ NÃO TESTADO | Isar recovery não documentado |
| Double click em ações | ✅ PARCIAL | Alguns buttons usam _loading guard |
| Operação repetida (idempotência) | ✅ PARCIAL | Sync usa upsert (ON CONFLICT) |
| Reload durante operação | ✅ SAFE | mounted guard em todos os setState |
| Session crash recovery | ✅ FUNCIONAL | RecoverActiveSession no bootstrap |
| Connectivity loss during sync | ✅ RESILIENTE | Sync marks individual sessions, retries |

---

## 3. AUTH REGRESSÃO

| Fluxo | Status |
|---|---|
| Google Sign-In | ✅ Sem regressão |
| Apple Sign-In | ✅ Sem regressão |
| Email/Password | ✅ Sem regressão |
| Token refresh | ✅ Automático via Supabase |
| Logout | ✅ Funcional |
| Deep link auth callback | ✅ DeepLinkHandler registrado |

---

## 4. CIRCUIT BREAKER (NOVO)

| API | Implementado | Localização |
|---|---|---|
| Strava OAuth token refresh | ✅ | strava-webhook Edge Function |
| Strava activity fetch | ✅ | strava-webhook Edge Function |
| Strava streams fetch | ✅ | strava-webhook Edge Function |
| Asaas webhook | ❌ Não | asaas-webhook Edge Function |
| Supabase client calls | ❌ Não | App-side (relies on connectivity monitor) |

---

## 5. PROBLEMAS DE SEGURANÇA

| # | Problema | Severidade | Recomendação |
|---|---|---|---|
| 1 | Isar não encriptado no device | ALTO | Migrar para Drift + SQLCipher ou aguardar Isar 4 |
| 2 | Algumas screens vazam exception details | MÉDIO | Centralizar error handling com ErrorMessages.humanize() |
| 3 | Strava client_secret compilado no APK | BAIXO | Aceitável para OAuth PKCE mobile, mas preferível server-side |
| 4 | Sem rate limit nas Edge Functions | MÉDIO | Implementar via Supabase gateway ou custom middleware |
