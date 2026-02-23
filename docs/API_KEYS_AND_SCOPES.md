# API_KEYS_AND_SCOPES.md — Política de Segredos e Chaves de API

> **Data:** 2026-02-17
> **Status:** Ativo
> **Referência:** DECISIONS.md (DECISAO 005, DECISAO 011, DECISAO 013)

---

## 1. REGRAS GLOBAIS

1. **NUNCA** commitar secrets no repositório (`.env`, tokens, client secrets)
2. **NUNCA** hardcoded em código-fonte Dart, Swift, Kotlin ou XML
3. Todos os segredos via `--dart-define` (Flutter) ou variável de ambiente (CI/CD)
4. `.gitignore` DEVE incluir `*.env`, `.env.*`, `credentials.json`, `*.keystore`
5. Rotação de chaves: a cada release major ou se comprometida

---

## 2. INVENTÁRIO DE CHAVES

| Serviço | Variável | Tipo | Onde armazenar | Sprint de origem |
|---------|----------|------|----------------|------------------|
| MapTiler | `MAPTILER_API_KEY` | API Key (público, read-only) | `--dart-define` | 5.2 (DECISAO 005) |
| Supabase | `SUPABASE_URL` | URL (público) | `--dart-define` | 9.1 (DECISAO 010) |
| Supabase | `SUPABASE_ANON_KEY` | Anon Key (público, RLS protege) | `--dart-define` | 9.1 (DECISAO 010) |
| Sentry | `SENTRY_DSN` | DSN (público, write-only) | `--dart-define` | 10.2 (DECISAO 011) |
| Strava | `STRAVA_CLIENT_ID` | Client ID (público) | `--dart-define` | 14.1.1 |
| Strava | `STRAVA_CLIENT_SECRET` | Client Secret (**PRIVADO**) | `--dart-define` (dev) / backend proxy (prod) | 14.1.1 |

---

## 3. STRAVA — DETALHES

### 3.1 App Registration

```
Portal:        https://www.strava.com/settings/api
App Name:      Omni Runner
Category:      Training
Website:       (TBD — app website or GitHub)
Authorization Callback Domain: omnirunner
  → Deep link: omnirunner://strava/callback
  → Registered in AndroidManifest.xml + Info.plist
```

### 3.2 Scopes — Mínimo necessário

| Scope | Obrigatório | Por quê | Sprint |
|-------|:-----------:|---------|--------|
| `activity:write` | **SIM** | Upload de arquivos GPX/FIT/TCX para `/api/v3/uploads`. Sem este scope, o POST retorna 403. | 14.3.1 |
| `activity:read` | NÃO (MVP) | Permite `GET /api/v3/athlete/activities` para verificar duplicatas antes de upload. **Não necessário** porque `external_id` no upload já previne duplicatas server-side. Adiar para pós-MVP. | — |
| `read` | NÃO | Lê perfil do atleta. Não necessário para upload. Evitar solicitar scopes desnecessários (princípio de menor privilégio). | — |
| `read_all` | NÃO | Lê atividades privadas de outros. Nunca necessário. | — |
| `profile:write` | NÃO | Altera perfil. Nunca necessário. | — |

**Decisão:** Solicitar APENAS `activity:write`. Scope mínimo = menor fricção de consentimento = maior taxa de conversão.

### 3.3 Fluxo OAuth2 — Authorization Code (sem PKCE*)

> \* Nota: A API Strava (fev/2026) **não suporta PKCE** (code_challenge/code_verifier).
> O fluxo usa Authorization Code clássico com `client_secret` no token exchange.
> Esta é uma limitação conhecida da API Strava, documentada em
> https://developers.strava.com/docs/authentication/

#### Diagrama de sequência

```
┌─────┐        ┌──────────┐       ┌──────────────┐
│ App │        │ Browser  │       │ Strava OAuth  │
└──┬──┘        └────┬─────┘       └──────┬───────┘
   │                │                     │
   │ 1. Abrir URL   │                     │
   │ ──────────────>│                     │
   │                │ 2. User autoriza    │
   │                │ ──────────────────> │
   │                │                     │
   │                │ 3. Redirect com     │
   │ <──────────────│    ?code=XXX        │
   │                │                     │
   │ 4. POST /oauth/token                │
   │   (client_id + client_secret + code) │
   │ ────────────────────────────────────>│
   │                                      │
   │ 5. {access_token, refresh_token,     │
   │     expires_at, athlete}             │
   │ <────────────────────────────────────│
   │                                      │
   │ 6. Salvar tokens em secure storage   │
   └──────────────────────────────────────┘
```

#### Etapa 1 — Authorization URL

```
https://www.strava.com/oauth/mobile/authorize
  ?client_id={STRAVA_CLIENT_ID}
  &redirect_uri=omnirunner://strava/callback
  &response_type=code
  &approval_prompt=auto
  &scope=activity:write
```

| Parâmetro | Valor | Nota |
|-----------|-------|------|
| `client_id` | `STRAVA_CLIENT_ID` (via dart-define) | Público |
| `redirect_uri` | `omnirunner://strava/callback` | Deep link registrado no app |
| `response_type` | `code` | Authorization Code flow |
| `approval_prompt` | `auto` | Só pede consentimento na 1ª vez; `force` re-pede sempre |
| `scope` | `activity:write` | Mínimo necessário |

**iOS:** Abrir via `ASWebAuthenticationSession` (Safari ViewController) — exigido pela Apple para OAuth.
**Android:** Abrir via Custom Tab (Chrome) — padrão aceito pelo Google.

#### Etapa 2 — Callback Deep Link

```
omnirunner://strava/callback?code=AUTHORIZATION_CODE&scope=activity:write
```

O app intercepta o deep link, extrai `code` e `scope`.

#### Etapa 3 — Token Exchange

```
POST https://www.strava.com/oauth/token
Content-Type: application/x-www-form-urlencoded

client_id={STRAVA_CLIENT_ID}
client_secret={STRAVA_CLIENT_SECRET}
code={AUTHORIZATION_CODE}
grant_type=authorization_code
```

**Resposta 200:**

```json
{
  "token_type": "Bearer",
  "access_token": "a4b945687g...",
  "refresh_token": "e5n567567...",
  "expires_at": 1708300000,
  "expires_in": 21600,
  "athlete": {
    "id": 12345,
    "firstname": "João",
    "lastname": "Silva"
  }
}
```

#### Erros comuns no token exchange

| HTTP | Causa | Ação no app |
|------|-------|-------------|
| 400 `"Bad Request"` | Code expirado (15min TTL) ou já usado | Reiniciar fluxo OAuth |
| 401 `"Unauthorized"` | client_id/secret inválidos | Verificar dart-define; não retry |
| 500+ | Strava indisponível | Retry com backoff; notificar user |

### 3.4 Token Storage — Armazenamento Seguro

| Item | Chave no Secure Storage | Tipo | Nota |
|------|------------------------|------|------|
| Access Token | `strava_access_token` | String | Expira em 6h |
| Refresh Token | `strava_refresh_token` | String | Não expira (até revogação) |
| Expiry Timestamp | `strava_expires_at` | String (int serializado) | Unix epoch seconds |
| Athlete ID | `strava_athlete_id` | String (int serializado) | Para identificar a conta conectada |
| Athlete Name | `strava_athlete_name` | String | Display name na UI |

**Plataforma de armazenamento:**

| Plataforma | Backend do `flutter_secure_storage` | Criptografia |
|------------|-------------------------------------|-------------|
| iOS | Keychain Services | AES-256-GCM (hardware-backed no Secure Enclave) |
| Android | EncryptedSharedPreferences (AndroidX) | AES-256-SIV (keystore-backed) |

**NUNCA:**
- SharedPreferences (plain text XML no Android)
- Arquivo JSON no disco
- Hardcoded no código

### 3.5 Estratégia de Token Refresh

```
┌──────────────────────────────────────────────────┐
│            CICLO DE VIDA DO TOKEN                 │
├──────────────────────────────────────────────────┤
│                                                  │
│  t=0h        Token obtido (expires_in=21600s)    │
│  t=0h..5h55  Token válido — usar normalmente     │
│  t=5h55      ⚠️  REFRESH PROATIVO (5min antes)   │
│  t=6h        ❌ Token expirado                    │
│                                                  │
│  Se refresh falhar:                              │
│    • 1ª falha: retry em 30s                      │
│    • 2ª falha: retry em 60s                      │
│    • 3ª falha: marcar como `needs_reauth`        │
│    • Mostrar UI "Reconecte Strava"               │
│                                                  │
│  Se 401 em qualquer request:                     │
│    • Tentar refresh 1x                           │
│    • Se refresh OK: replay request original      │
│    • Se refresh falha: limpar tokens, UI reauth  │
│                                                  │
└──────────────────────────────────────────────────┘
```

#### Refresh Request

```
POST https://www.strava.com/oauth/token
Content-Type: application/x-www-form-urlencoded

client_id={STRAVA_CLIENT_ID}
client_secret={STRAVA_CLIENT_SECRET}
grant_type=refresh_token
refresh_token={STORED_REFRESH_TOKEN}
```

**Resposta 200:**

```json
{
  "token_type": "Bearer",
  "access_token": "new_access_token...",
  "refresh_token": "new_or_same_refresh_token...",
  "expires_at": 1708321600,
  "expires_in": 21600
}
```

**IMPORTANTE:** O `refresh_token` na resposta pode ser **diferente** do enviado.
Sempre sobrescrever o refresh_token armazenado com o valor da resposta.

#### Quando fazer refresh

| Momento | Trigger |
|---------|---------|
| Antes de qualquer API call | Se `now >= expires_at - 300` (5 min buffer) |
| Ao receber HTTP 401 | Refresh 1x, replay request; se falhar, reauth |
| Ao abrir o app | Se token expirou enquanto o app estava fechado |
| Antes de upload | Garantir token fresh antes de multipart POST |

### 3.6 Rate Limits e Estratégia de Retry

#### Limites oficiais (fev/2026)

| Janela | Leitura | Escrita | Nota |
|--------|---------|---------|------|
| 15 minutos | 200 requests | 200 requests | Reset a cada janela de 15min |
| Diário | 2.000 requests | 2.000 requests | Reset à meia-noite UTC |

> Strava retorna rate limit info nos headers:
> `X-RateLimit-Limit: 200,2000`
> `X-RateLimit-Usage: 5,100`

#### Custo por operação

| Operação | Requests consumidos | Nota |
|----------|:-------------------:|------|
| Token exchange | 1 | POST /oauth/token |
| Token refresh | 1 | POST /oauth/token |
| Upload POST | 1 | POST /api/v3/uploads |
| Upload poll | 1 por poll | GET /api/v3/uploads/{id} |
| Upload completo | ~4 | 1 POST + ~3 polls |

**Budget efetivo:** ~50 uploads por janela de 15min; ~500 uploads/dia.
Para um app de corrida, isso é mais que suficiente.

#### Estratégia de retry/backoff

```
HTTP 429 (Rate Limited):
  1. Ler header `X-RateLimit-Usage` para saber quanto falta
  2. Se 15-min limit: wait 60s e retry
  3. Se daily limit: enqueue para próximo dia (PendingUpload)
  4. NÃO fazer retry agressivo — respeitar 429

HTTP 5xx (Server Error):
  Backoff exponencial: 2s → 4s → 8s → 16s → 32s (max 5 tentativas)
  Após 5 falhas: enqueue como PendingUpload, retry na próxima sessão

HTTP 401 (Unauthorized):
  1. Refresh token 1x
  2. Se refresh OK → replay request
  3. Se refresh 401 → user revogou acesso → limpar tokens, UI reauth
  NÃO retry em loop

Timeout de rede:
  Timeout do POST: 60s (arquivos podem ser grandes)
  Timeout do poll: 10s
  Retry: mesma estratégia de 5xx
```

### 3.7 Campos Obrigatórios para Upload

#### POST `/api/v3/uploads` — Multipart Form

| Campo | Tipo | Obrigatório | Valor | Nota |
|-------|------|:-----------:|-------|------|
| `file` | Binary (multipart) | **SIM** | Conteúdo do arquivo GPX/FIT/TCX | Max ~25 MB |
| `data_type` | String | **SIM** | `"gpx"` \| `"tcx"` \| `"fit"` | Deve corresponder ao conteúdo real |
| `activity_type` | String | NÃO (recomendado) | `"run"` | Strava infere se omitido, mas melhor ser explícito |
| `name` | String | NÃO (recomendado) | `"Morning Run"` | Strava gera nome se omitido |
| `description` | String | NÃO | `"Tracked with Omni Runner"` | Visível na atividade |
| `external_id` | String | NÃO (**CRÍTICO**) | `"{session_uuid}"` | **Deduplicação**: Strava rejeita upload com external_id já existente. SEMPRE enviar. |
| `trainer` | Int (0/1) | NÃO | `0` | 1 = indoor/trainer; 0 = outdoor |
| `commute` | Int (0/1) | NÃO | `0` | 1 = commute; 0 = workout |

#### Resposta 201 (Created)

```json
{
  "id": 12345678,
  "id_str": "12345678",
  "external_id": "abc-123-session-uuid.gpx",
  "error": null,
  "status": "Your activity is still being processed.",
  "activity_id": null
}
```

#### Polling `GET /api/v3/uploads/{id}`

```json
// Processando:
{
  "id": 12345678,
  "status": "Your activity is still being processed.",
  "activity_id": null
}

// Concluído:
{
  "id": 12345678,
  "status": "Your activity is ready.",
  "activity_id": 9876543210
}

// Erro:
{
  "id": 12345678,
  "status": "There was an error processing your activity.",
  "error": "duplicate of activity 9876543210",
  "activity_id": null
}
```

#### Estratégia de polling

```
Max polls:     10
Intervalo:     3s (primeiros 5), 5s (últimos 5)
Timeout total: ~40s
Se "still processing" após 10 polls → UploadProcessingTimeout
Se "error" contém "duplicate" → Considerar sucesso (já existe)
```

### 3.8 Segurança do Client Secret (Produção)

Em desenvolvimento, `STRAVA_CLIENT_SECRET` pode ser passado via `--dart-define`.
Em produção, o secret **NÃO** deve estar no APK/IPA (pode ser extraído).

**Opções para produção:**

| Opção | Complexidade | Segurança |
|-------|-------------|-----------|
| A: Backend proxy (Supabase Edge Function) | Média | Alta — secret nunca no device |
| B: PKCE-only (sem secret no token exchange) | N/A | N/A — Strava **não suporta PKCE** |
| C: Secret no APK via `--dart-define` | Zero | Baixa — extraível por reverse engineering |

**Decisão MVP:** Opção C (aceitável para MVP / beta fechado).
**Decisão Produção:** Opção A — Supabase Edge Function como proxy para token exchange e refresh.

---

## 4. MAPTILER — DETALHES

```
Tipo:           API Key (read-only, público por design)
Rate Limit:     100,000 tile loads/mês (free tier)
Risco de leak:  Baixo — read-only, rate limited
Proteção extra: Restringir key por bundle ID no MapTiler dashboard
```

---

## 5. SUPABASE — DETALHES

```
SUPABASE_URL:       Público — endereço do projeto
SUPABASE_ANON_KEY:  Público por design — RLS protege dados
                    Não é um secret; é um "capability token" limitado por RLS

Risco de leak:  Baixo — anon key só permite o que RLS autoriza
Proteção extra: RLS policies restritivas em todas as tabelas
```

---

## 6. SENTRY — DETALHES

```
Tipo:           DSN (write-only, público por design)
Risco de leak:  Nenhum — DSN é projetado para estar no client-side
Proteção extra: Rate limiting no dashboard Sentry
```

---

## 7. .env.example

Arquivo de referência para desenvolvedores (sem valores reais):

```bash
# Omni Runner — Environment Variables
# Copy to .env and fill with real values. NEVER commit .env.

MAPTILER_API_KEY=your_maptiler_key_here
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key_here
SENTRY_DSN=https://your-dsn@sentry.io/project-id
SENTRY_ENVIRONMENT=development

# Strava (Phase 14)
STRAVA_CLIENT_ID=your_strava_client_id
STRAVA_CLIENT_SECRET=your_strava_client_secret
```

### Build command

```bash
flutter run \
  --dart-define=MAPTILER_API_KEY=$MAPTILER_API_KEY \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define=SENTRY_DSN=$SENTRY_DSN \
  --dart-define=SENTRY_ENVIRONMENT=$SENTRY_ENVIRONMENT \
  --dart-define=STRAVA_CLIENT_ID=$STRAVA_CLIENT_ID \
  --dart-define=STRAVA_CLIENT_SECRET=$STRAVA_CLIENT_SECRET
```

### Access in Dart

```dart
const stravaClientId = String.fromEnvironment('STRAVA_CLIENT_ID');
const stravaClientSecret = String.fromEnvironment('STRAVA_CLIENT_SECRET');
```

---

*Documento criado em Sprint 14.0.1. Atualizar a cada nova chave/serviço adicionado.*
