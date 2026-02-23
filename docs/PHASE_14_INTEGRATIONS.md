# PHASE 14 — INTEGRAÇÕES EXTERNAS (Strava + Export/Import)

> **Data:** 2026-02-17
> **Status:** EM PLANEJAMENTO
> **Sprint atual:** 14.0.1 — Trava de contexto

---

## 1. O QUE ENTRA NA FASE 14

### 1.1 Strava Upload via API OAuth2

Upload automático de workouts para Strava após conclusão da corrida.

| Item | Detalhe |
|------|---------|
| Protocolo | OAuth2 Authorization Code (PKCE) |
| Endpoint | `https://www.strava.com/api/v3/uploads` |
| Formato de upload | FIT (preferido) ou GPX (fallback) |
| Dados enviados | GPS route, HR, distance, time, pace, calories |
| Trigger | Automático (opt-in) após `endWorkout()` + manual via botão |
| Token refresh | Background refresh via `refresh_token` antes de expirar |
| Deduplicação | Strava rejeita uploads com `external_id` duplicado |
| Offline | Enfileirar uploads; sincronizar quando houver rede |

### 1.2 Exportação de Arquivos: FIT / GPX / TCX

Gerar arquivos exportáveis para importação manual em qualquer plataforma.

| Formato | Uso principal | Dados suportados |
|---------|--------------|------------------|
| **GPX 1.1** | Universal (Garmin, Coros, Suunto, etc.) | GPS track, elevation, time, HR (via extensions) |
| **TCX** | Garmin Connect, TrainingPeaks | GPS, HR, laps, calories, distance |
| **FIT** | Garmin, Strava, TrainingPeaks (binário, mais completo) | GPS, HR, pace, cadence, calories, device info |

### 1.3 Share Sheet (Compartilhamento Nativo)

Após exportar, oferecer share sheet do OS para enviar arquivo via:
- Email, WhatsApp, Telegram, AirDrop
- "Abrir com" (Garmin Connect, Strava, etc.)
- Salvar em Files/Downloads

### 1.4 HealthKit / Health Connect Export

| Plataforma | Use Case original | Status | Sprint |
|-----------|-------------------|--------|--------|
| iOS (HealthKit) | `ExportWorkoutToHealth` | ✅ Implementado | W2.3 |
| Android (Health Connect) | `ExportWorkoutToHealth` | ✅ Implementado | W3.3 |
| Bridge: `IHealthExportService` | Feature-flagged + controller | ✅ Implementado | 14.4.1 |

**Sprint 14.4.1** criou um bridge layer (`health_export/`) que:
- Encapsula `IHealthProvider` + `IPointsRepo` com verificações de plataforma
- Diferencia iOS (HealthKit auto-correlaciona HR) vs Android (precisa escrever HR explicitamente)
- Expõe `HealthExportController` com mensagens user-facing em PT-BR
- Sealed class `HealthExportFailure` com 6 subtipos para pattern matching
- **TODO:** Wiring na tela de detalhes (botão "Exportar para Saúde") — Sprint 14.5
- **TODO:** Integrar no `endWorkout()` como auto-export opt-in — Sprint 14.5

### 1.5 Fallback Offline (Queue de Uploads)

| Cenário | Comportamento |
|---------|---------------|
| Sem rede ao finalizar corrida | Salvar upload pendente no Isar |
| Rede recuperada | Auto-sync via `connectivity_plus` listener |
| Token expirado | Refresh silencioso; se falhar, marcar para re-auth |
| Upload falha (5xx) | Retry com exponential backoff (max 5 tentativas) |
| Upload falha (4xx) | Logar erro, notificar usuário, não retry |

---

## 2. O QUE NÃO ENTRA NA FASE 14

| Excluído | Motivo |
|----------|--------|
| **Garmin Connect IQ app** | Requer Garmin SDK separado, device-specific, fora do escopo |
| **Upload direto para Garmin Connect via API** | Garmin não oferece API pública de upload de atividades; exige parceria comercial |
| **Coros / Suunto / Polar Flow API upload** | APIs proprietárias; usuário importa via arquivo FIT/GPX |
| **Import de atividades de outras plataformas** | Complexidade alta; fora do MVP. Futuro: import GPX/FIT |
| **Strava Segments / Live Activities** | Requer Strava Premium API; fora do escopo MVP |
| **Social features (feed, kudos)** | Fora do escopo do app |
| **Training plan sync (TrainingPeaks, intervals.icu)** | Requer APIs específicas; futuro |

---

## 3. CHECKLIST DE MICRO-PASSOS

### Sprint 14.0 — Preparação

- [x] **14.0.1** — Trava de contexto: definir escopo, criar PHASE_14_INTEGRATIONS.md
- [x] **14.0.2** — Criar `docs/API_KEYS_AND_SCOPES.md` com política de segredos

### Sprint 14.1 — Strava OAuth2

- [x] **14.1.1** — Registrar app no Strava Developer Portal; documentar Client ID/Secret/scopes — Sprint 14.2.1
- [x] **14.1.2** — Implementar OAuth2 Authorization Code flow + módulo Strava — Sprint 14.2.2
- [x] **14.1.3** — Persistir tokens (access + refresh) de forma segura (`flutter_secure_storage`) — Sprint 14.2.2
- [ ] **14.1.4** — Implementar token refresh automático (background, antes de expirar)
- [ ] **14.1.5** — Criar UI de conexão/desconexão Strava na tela de Settings
- [ ] **14.1.6** — Testes unitários do fluxo OAuth2

### Sprint 14.2 — Geração de Arquivos de Exportação

- [x] **14.2.1** — Implementar gerador GPX 1.1 (`GpxEncoder`) — Sprint 14.1.1
- [x] **14.2.2** — Implementar gerador TCX (`TcxEncoder`) — Sprint 14.1.1
- [ ] **14.2.3** — Implementar gerador FIT (`FitEncoder`) — formato binário (stub com `ExportNotImplemented`)
- [x] **14.2.4** — Criar interface `IExportService` e `ExportServiceImpl` factory — Sprint 14.1.1
- [x] **14.2.5** — Testes unitários para GPX (8 tests) e TCX (11 tests) — Sprint 14.1.1

### Sprint 14.3 — Strava Upload

- [x] **14.3.1** — Implementar `StravaUploadService` (multipart POST para `/api/v3/uploads`) — Sprint 14.2.3
- [x] **14.3.2** — Polling de status do upload (`GET /api/v3/uploads/{id}`) — Sprint 14.2.3
- [ ] **14.3.3** — Integrar no fluxo de `endWorkout()` (auto-upload opt-in)
- [ ] **14.3.4** — Upload manual via botão na tela de detalhes da corrida
- [ ] **14.3.5** — Testes unitários + mock HTTP

### Sprint 14.4 — Queue Offline + Retry

- [ ] **14.4.1** — Criar modelo `PendingUpload` no Isar (sessionId, format, status, retries, error)
- [ ] **14.4.2** — Implementar `UploadQueueManager` (enqueue, dequeue, retry com backoff)
- [ ] **14.4.3** — Listener de conectividade (`connectivity_plus`) para auto-sync
- [ ] **14.4.4** — Exibir badge de "uploads pendentes" na UI
- [ ] **14.4.5** — Testes unitários da queue + retry logic

### Sprint 14.5 — Share Sheet + UX

- [x] **14.5.1** — Implementar share sheet nativa (`share_plus`) com arquivo FIT/GPX/TCX — Sprint 14.1.2
- [ ] **14.5.2** — Adicionar botões de export na tela de detalhes da corrida
- [ ] **14.5.3** — Tela de "Export History" (lista de uploads feitos/pendentes/falhos)
- [ ] **14.5.4** — Feedback visual: toast/snackbar de sucesso/erro em cada upload

### Sprint 14.6 — Polimento e Validação

- [ ] **14.6.1** — Validar GPX exportado no GPXSee / Garmin Connect web
- [ ] **14.6.2** — Validar FIT exportado no Garmin Connect web / Strava web
- [ ] **14.6.3** — Validar TCX exportado no Garmin Connect web
- [ ] **14.6.4** — Testar upload Strava end-to-end em conta de teste
- [ ] **14.6.5** — Revisão de privacidade: nenhum PII vazando nos arquivos exportados
- [ ] **14.6.6** — Atualizar `CONTEXT_DUMP.md` final da fase

---

## 4. MATRIZ DE RISCOS

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|-------|---------------|---------|-----------|
| R1 | **Token Strava expira** (6h access token) | Alta | Médio | Refresh automático via `refresh_token` (validade: indefinida enquanto app autorizado). Guardar `expires_at` e renovar 5min antes. |
| R2 | **Rate limit Strava API** (600 req/15min, 30.000/dia) | Baixa (MVP) | Médio | Rate limiter no client; queue serializa uploads; 1 upload = ~3 requests (POST + polling). Até 10.000 uploads/dia é seguro. |
| R3 | **Falha de rede durante upload** | Alta | Baixo | `PendingUpload` no Isar + retry automático via connectivity listener. Exponential backoff (1s, 2s, 4s... max 60s). |
| R4 | **Strava rejeita arquivo** (formato inválido) | Baixa | Alto | Validação local do arquivo antes de enviar. Testes com round-trip parse. Error log com body da resposta para debug. |
| R5 | **Strava desautoriza app** (usuário revoga no Strava) | Baixa | Médio | Interceptar 401 → limpar tokens → mostrar UI de re-conexão. Não tentar retry com token revogado. |
| R6 | **Privacidade: GPS em arquivos compartilhados** | Média | Alto | Aviso explícito antes de compartilhar: "Este arquivo contém sua rota GPS". Opção futura: truncar início/fim da rota (home detection). |
| R7 | **Store compliance (Apple)** | Baixa | Alto | OAuth2 PKCE é o padrão aceito pela Apple. Não armazenar senha do Strava. Usar `ASWebAuthenticationSession` no iOS. |
| R8 | **Store compliance (Google)** | Baixa | Alto | Health Connect export já aprovado. Share sheet é API nativa. OAuth2 via Custom Tab (Chrome) é padrão aceito. |
| R9 | **FIT format complexity** | Média | Médio | FIT é binário com CRC. Usar package `fit_tool` ou gerar manualmente. Fallback: usar GPX para Strava upload se FIT for muito complexo. |
| R10 | **Strava API changes** | Baixa | Médio | Versionar API calls. Monitorar changelog Strava. Upload endpoint é estável há 5+ anos. |
| R11 | **Client Secret vazado** | Baixa | Alto | Secret NUNCA no código. Usar `--dart-define`. Para produção: proxy backend ou PKCE-only (sem secret). |

---

## 5. PADRÃO DE LOGS / OBSERVABILIDADE

### 5.1 Eventos que DEVEM ser logados

| Evento | Nível | Tag | Dados logados |
|--------|-------|-----|---------------|
| OAuth flow started | INFO | `StravaAuth` | — |
| OAuth callback received | INFO | `StravaAuth` | success/failure, has_code |
| Token refreshed | DEBUG | `StravaAuth` | expires_at |
| Token refresh failed | WARN | `StravaAuth` | error type (network, revoked, expired) |
| Upload enqueued | INFO | `UploadQueue` | sessionId, format, queue_size |
| Upload started | INFO | `StravaUpload` | sessionId, format, file_size_bytes |
| Upload polling | DEBUG | `StravaUpload` | upload_id, status, attempt |
| Upload succeeded | INFO | `StravaUpload` | sessionId, strava_activity_id, duration_ms |
| Upload failed (4xx) | WARN | `StravaUpload` | sessionId, status_code, error_body |
| Upload failed (5xx/network) | WARN | `StravaUpload` | sessionId, error, retry_count |
| Upload retry scheduled | DEBUG | `UploadQueue` | sessionId, delay_ms, attempt |
| Upload abandoned (max retries) | ERROR | `UploadQueue` | sessionId, total_attempts |
| File exported (GPX/FIT/TCX) | INFO | `FileExport` | sessionId, format, file_size_bytes |
| Share sheet opened | INFO | `FileExport` | sessionId, format |
| Connectivity changed | DEBUG | `UploadQueue` | is_connected, pending_count |
| Queue drain started | INFO | `UploadQueue` | pending_count |
| Queue drain completed | INFO | `UploadQueue` | uploaded, failed, remaining |

### 5.2 Dados que NUNCA devem ser logados

- Access token / refresh token (nem parcialmente)
- Client secret
- Coordenadas GPS do usuário
- Email ou dados pessoais do perfil Strava

### 5.3 Sentry Breadcrumbs

Cada evento INFO/WARN acima será registrado como breadcrumb no Sentry para
contexto em caso de crash. Tags de Sentry por sessão:

```
strava.connected: true/false
strava.last_upload: "2026-02-17T10:30:00Z"
upload.pending_count: 3
```

---

## 6. PADRÃO DE ERROS (Failure Classes)

### 6.1 Nova hierarquia: `IntegrationFailure`

Segue o mesmo padrão de `HealthFailure`, `BleFailure`, `SyncFailure`:

```dart
/// Failures related to external integrations (Strava, file export).
///
/// Sealed hierarchy — exhaustive pattern matching in BLoC.
sealed class IntegrationFailure {
  const IntegrationFailure();
}

// ── Auth ──────────────────────────────────────────────────────

/// OAuth2 flow was cancelled by the user.
final class AuthCancelled extends IntegrationFailure {
  const AuthCancelled();
}

/// OAuth2 flow failed (network, server error, invalid response).
final class AuthFailed extends IntegrationFailure {
  final String reason;
  const AuthFailed(this.reason);
}

/// Token refresh failed — user must re-authenticate.
final class TokenExpired extends IntegrationFailure {
  const TokenExpired();
}

/// User revoked access on the provider side.
final class AuthRevoked extends IntegrationFailure {
  const AuthRevoked();
}

// ── Upload ────────────────────────────────────────────────────

/// Upload rejected by provider (4xx — bad file, duplicate, etc.).
final class UploadRejected extends IntegrationFailure {
  final int statusCode;
  final String message;
  const UploadRejected(this.statusCode, this.message);
}

/// Upload failed due to network error (retryable).
final class UploadNetworkError extends IntegrationFailure {
  final String message;
  const UploadNetworkError(this.message);
}

/// Upload failed due to server error (5xx, retryable).
final class UploadServerError extends IntegrationFailure {
  final int statusCode;
  const UploadServerError(this.statusCode);
}

/// Rate limit exceeded (429).
final class UploadRateLimited extends IntegrationFailure {
  final int retryAfterSeconds;
  const UploadRateLimited(this.retryAfterSeconds);
}

/// Upload processing timed out on Strava side.
final class UploadProcessingTimeout extends IntegrationFailure {
  final String uploadId;
  const UploadProcessingTimeout(this.uploadId);
}

// ── File Export ───────────────────────────────────────────────

/// Failed to generate the export file (GPX/FIT/TCX).
final class ExportGenerationFailed extends IntegrationFailure {
  final String format;
  final String reason;
  const ExportGenerationFailed(this.format, this.reason);
}

/// Failed to write the file to disk.
final class ExportWriteFailed extends IntegrationFailure {
  final String path;
  final String reason;
  const ExportWriteFailed(this.path, this.reason);
}
```

### 6.2 Mapeamento Failure → UI Message

| Failure | Mensagem UI (pt-BR) |
|---------|---------------------|
| `AuthCancelled` | "Conexão com Strava cancelada." |
| `AuthFailed` | "Falha ao conectar com Strava. Tente novamente." |
| `TokenExpired` | "Sessão Strava expirada. Reconecte sua conta." |
| `AuthRevoked` | "Acesso ao Strava foi revogado. Reconecte sua conta." |
| `UploadRejected` | "Strava rejeitou o upload: {message}" |
| `UploadNetworkError` | "Sem conexão. Upload será tentado quando houver rede." |
| `UploadServerError` | "Erro no servidor Strava. Tentaremos novamente em breve." |
| `UploadRateLimited` | "Muitas requisições. Tentando novamente em {n} segundos." |
| `UploadProcessingTimeout` | "Strava está processando. Verifique em alguns minutos." |
| `ExportGenerationFailed` | "Erro ao gerar arquivo {format}." |
| `ExportWriteFailed` | "Erro ao salvar arquivo. Verifique espaço disponível." |

---

## 7. ARQUITETURA

### 7.1 Camadas (Clean Architecture)

```
domain/
├── entities/
│   └── pending_upload_entity.dart       # Upload pendente
├── repositories/
│   ├── i_strava_auth_repo.dart          # OAuth2 tokens
│   ├── i_strava_upload_repo.dart        # Upload + polling
│   ├── i_upload_queue_repo.dart         # Queue de uploads pendentes
│   └── i_workout_exporter.dart          # Interface: session → file bytes
├── usecases/
│   ├── connect_strava.dart              # OAuth2 flow
│   ├── disconnect_strava.dart           # Revoke + clear tokens
│   ├── upload_to_strava.dart            # Generate file + upload + poll
│   ├── export_workout_file.dart         # Generate GPX/FIT/TCX
│   └── drain_upload_queue.dart          # Process pending uploads
└── failures/
    └── integration_failure.dart         # Sealed hierarchy

data/
├── datasources/
│   ├── strava_api_client.dart           # HTTP client (upload, poll, token)
│   └── strava_auth_service.dart         # OAuth2 PKCE flow (platform-specific)
├── repositories_impl/
│   ├── strava_auth_repo.dart            # flutter_secure_storage
│   ├── strava_upload_repo.dart          # HTTP + retry
│   ├── isar_upload_queue_repo.dart      # Isar persistence
│   └── workout_exporters/
│       ├── gpx_exporter.dart            # GPX 1.1 XML
│       ├── tcx_exporter.dart            # TCX XML
│       └── fit_exporter.dart            # FIT binary
└── models/
    └── isar/
        └── pending_upload_record.dart   # Isar schema

presentation/
├── blocs/
│   └── integrations/
│       ├── strava_bloc.dart             # Connect/disconnect/upload state
│       └── export_bloc.dart             # File generation + share
├── screens/
│   └── integrations_screen.dart         # Settings → Strava connection
└── widgets/
    ├── strava_connect_button.dart       # OAuth trigger
    ├── export_format_picker.dart        # GPX/FIT/TCX selector
    └── upload_status_badge.dart         # Pending/success/error indicator
```

### 7.2 Fluxo de Upload Strava

```
endWorkout() (TrackingBloc)
  │
  ├─ 1. ExportWorkoutToHealth (already exists — HealthKit/HC)
  │
  └─ 2. UploadToStrava (new)
       │
       ├─ Check: strava_connected? tokens valid?
       │   └─ No → enqueue as PendingUpload, return
       │
       ├─ Check: connectivity?
       │   └─ No → enqueue as PendingUpload, return
       │
       ├─ Generate FIT file (FitExporter)
       │
       ├─ POST /api/v3/uploads (multipart, file + metadata)
       │   ├─ 201 → poll status
       │   ├─ 401 → refresh token → retry once
       │   ├─ 429 → enqueue with retry_after
       │   └─ 5xx → enqueue for retry
       │
       └─ Poll GET /api/v3/uploads/{id}
           ├─ "Your activity is ready" → success, save strava_activity_id
           ├─ "still processing" → poll again (max 10x, 3s interval)
           └─ "error" → log, notify user
```

### 7.3 Fluxo de Export File

```
User taps "Export GPX" (RunDetailsScreen)
  │
  ├─ ExportWorkoutFile.call(sessionId, format: .gpx)
  │   ├─ Load session + points from repos
  │   ├─ GpxExporter.generate(session, points) → Uint8List
  │   └─ Write to temp file → return path
  │
  └─ Share sheet (share_plus) with file path
```

---

## 8. DEPENDÊNCIAS NECESSÁRIAS

| Package | Versão | Uso |
|---------|--------|-----|
| `url_launcher` | latest | Abrir OAuth2 URL no browser |
| `flutter_secure_storage` | latest | Armazenar access/refresh tokens |
| `http` | latest | HTTP client para Strava API |
| `share_plus` | latest | Share sheet nativa (file sharing) |
| `xml` | latest | Gerar GPX e TCX (XML) |
| `connectivity_plus` | ^7.0.0 | ✅ Já instalado — listener de rede |

> **Nota:** `fit_tool` para gerar FIT binário será avaliado em 14.2.3.
> Se muito complexo ou sem manutenção, FIT será gerado manualmente
> (protocol buffer-like binary encoding).

---

## 9. STRAVA API REFERENCE (RESUMO)

### 9.1 OAuth2

```
Authorization URL: https://www.strava.com/oauth/mobile/authorize
Token URL:         https://www.strava.com/oauth/token
Scopes:            activity:write  (mínimo MVP)
Grant type:        authorization_code  (Strava NÃO suporta PKCE)
```

> **Nota importante (fev/2026):** Strava não implementa PKCE
> (code_challenge / code_verifier). O fluxo exige `client_secret`
> no token exchange. Ver `API_KEYS_AND_SCOPES.md §3.3` para detalhes.

### 9.2 Endpoints que vamos usar

| # | Método | URL | Uso | Sprint |
|---|--------|-----|-----|--------|
| E1 | GET | `https://www.strava.com/oauth/mobile/authorize?...` | Abrir consentimento OAuth2 no browser | 14.1.2 |
| E2 | POST | `https://www.strava.com/oauth/token` | Token exchange (code → tokens) | 14.1.2 |
| E3 | POST | `https://www.strava.com/oauth/token` | Token refresh (refresh_token → new tokens) | 14.1.4 |
| E4 | POST | `https://www.strava.com/api/v3/uploads` | Upload de arquivo GPX/FIT/TCX | 14.3.1 |
| E5 | GET | `https://www.strava.com/api/v3/uploads/{id}` | Polling de status do upload | 14.3.2 |
| E6 | POST | `https://www.strava.com/oauth/deauthorize` | Revogar acesso (disconnect) | 14.1.5 |

#### E1 — Authorization URL (browser)

```
GET https://www.strava.com/oauth/mobile/authorize
  ?client_id={STRAVA_CLIENT_ID}
  &redirect_uri=omnirunner://strava/callback
  &response_type=code
  &approval_prompt=auto
  &scope=activity:write
```

**Callback:** `omnirunner://strava/callback?code=XXX&scope=activity:write`

#### E2 — Token Exchange

```
POST https://www.strava.com/oauth/token
Content-Type: application/x-www-form-urlencoded

  client_id={STRAVA_CLIENT_ID}
  client_secret={STRAVA_CLIENT_SECRET}
  code={AUTHORIZATION_CODE}
  grant_type=authorization_code
```

**Response 200:**
```json
{
  "token_type": "Bearer",
  "access_token": "...",
  "refresh_token": "...",
  "expires_at": 1708300000,
  "expires_in": 21600,
  "athlete": { "id": 12345, "firstname": "João" }
}
```

#### E3 — Token Refresh

```
POST https://www.strava.com/oauth/token
Content-Type: application/x-www-form-urlencoded

  client_id={STRAVA_CLIENT_ID}
  client_secret={STRAVA_CLIENT_SECRET}
  grant_type=refresh_token
  refresh_token={STORED_REFRESH_TOKEN}
```

**Response 200:** mesmo formato do E2 (novo access_token, possivelmente novo refresh_token).

#### E4 — Upload Activity

```
POST https://www.strava.com/api/v3/uploads
Authorization: Bearer {access_token}
Content-Type: multipart/form-data

  file:          (binary)           ← arquivo GPX/FIT/TCX
  data_type:     "gpx"|"tcx"|"fit" ← OBRIGATÓRIO
  name:          "Morning Run"     ← opcional mas recomendado
  description:   "Tracked with Omni Runner"
  external_id:   "{session_uuid}"  ← DEDUPLICAÇÃO
  activity_type: "run"             ← recomendado
```

**Response 201:**
```json
{
  "id": 12345678,
  "external_id": "abc-123.gpx",
  "status": "Your activity is still being processed.",
  "activity_id": null,
  "error": null
}
```

#### E5 — Poll Upload Status

```
GET https://www.strava.com/api/v3/uploads/{upload_id}
Authorization: Bearer {access_token}
```

**Response 200 (processing):**
```json
{ "id": 12345678, "status": "Your activity is still being processed.", "activity_id": null }
```

**Response 200 (ready):**
```json
{ "id": 12345678, "status": "Your activity is ready.", "activity_id": 9876543210 }
```

**Response 200 (error):**
```json
{ "id": 12345678, "status": "There was an error processing your activity.", "error": "duplicate of activity 9876543210" }
```

#### E6 — Deauthorize (Disconnect)

```
POST https://www.strava.com/oauth/deauthorize
Authorization: Bearer {access_token}
```

**Response 200:** `{ "access_token": "..." }`

Após deauthorize: limpar todos os tokens do secure storage.

### 9.3 Rate Limits

```
Janela de 15 minutos: 200 read + 200 write
Janela diária:        2.000 read + 2.000 write

Headers de resposta:
  X-RateLimit-Limit: {15min},{daily}
  X-RateLimit-Usage: {15min_used},{daily_used}

1 upload completo ≈ 4 write requests (1 POST + 3 polls)
Budget efetivo: ~50 uploads/15min, ~500 uploads/dia
```

### 9.4 Token Lifecycle

```
access_token:   expira em 6h (21600s)
refresh_token:  não expira (até revogação pelo usuário)
expires_at:     Unix timestamp (epoch seconds)

Refresh proativo: quando now >= expires_at - 300 (5min antes)
Refresh reativo:  ao receber HTTP 401 (1 tentativa)
```

---

## 10. O QUE FAZER QUANDO FALHAR — Tabela de Decisão

Esta seção mapeia cada tipo de falha para a ação concreta no app.

### 10.1 Falhas no OAuth2

| Cenário | HTTP | Detecção | Ação no App | Failure Class |
|---------|------|----------|-------------|---------------|
| User cancela consentimento | — | Callback sem `code` ou deep link not received | Mostrar "Conexão cancelada" | `AuthCancelled` |
| Code expirado (>15min) | 400 | `"Bad Request"` no token exchange | Reiniciar fluxo OAuth | `AuthFailed` |
| client_id/secret inválidos | 401 | Token exchange retorna 401 | Verificar config; NÃO retry | `AuthFailed` |
| Strava down durante OAuth | 5xx | Timeout ou 5xx no token exchange | Retry 1x com backoff; se falha → "Tente novamente mais tarde" | `AuthFailed` |
| User revoga acesso no strava.com | 401 | Qualquer API call retorna 401 + refresh falha com 401 | Limpar tokens; mostrar "Reconecte Strava" | `AuthRevoked` |

### 10.2 Falhas no Token Refresh

| Cenário | HTTP | Ação | Failure Class |
|---------|------|------|---------------|
| Refresh OK | 200 | Salvar novos tokens, continuar | — |
| Refresh falha (network) | timeout | Retry 3x (30s, 60s, 120s); se falha → marcar needs_reauth | `TokenExpired` |
| Refresh falha (revogado) | 401 | Limpar todos os tokens; UI "Reconecte Strava" | `AuthRevoked` |
| Refresh falha (rate limit) | 429 | Wait `Retry-After` header ou 60s; retry | `UploadRateLimited` |

### 10.3 Falhas no Upload

| Cenário | HTTP | Ação | Retry? | Failure Class |
|---------|------|------|:------:|---------------|
| Upload aceito | 201 | Iniciar polling | — | — |
| Token inválido | 401 | Refresh 1x → replay POST; se falha → enqueue | 1x | `TokenExpired` |
| Arquivo inválido | 400 | Logar body; notificar user; NÃO retry | ❌ | `UploadRejected(400, ...)` |
| Duplicata | 409 (ou status "duplicate") | Considerar **sucesso** (já existe no Strava) | ❌ | — (sucesso) |
| Rate limited | 429 | Enqueue com delay; respeitar `Retry-After` | ✅ (delayed) | `UploadRateLimited` |
| Server error | 500/502/503 | Backoff exponencial: 2s→4s→8s→16s→32s (max 5x) | ✅ | `UploadServerError` |
| Timeout de rede | — | Enqueue para retry automático (connectivity listener) | ✅ | `UploadNetworkError` |
| Arquivo muito grande | 413 | Logar; user message "Arquivo muito grande" | ❌ | `UploadRejected(413, ...)` |

### 10.4 Falhas no Polling

| Cenário | HTTP | Ação | Failure Class |
|---------|------|------|---------------|
| "still processing" | 200 | Continuar poll (max 10x) | — |
| "ready" | 200 | Sucesso! Salvar `activity_id` | — |
| "error: duplicate" | 200 | Considerar sucesso | — |
| "error: other" | 200 | Logar; notificar user | `UploadRejected(200, status.error)` |
| Timeout (10 polls) | — | Salvar upload_id; verificar depois | `UploadProcessingTimeout` |
| Token expirado mid-poll | 401 | Refresh 1x → retomar poll | `TokenExpired` |

### 10.5 Falhas na Exportação de Arquivo

| Cenário | Ação | Failure Class |
|---------|------|---------------|
| Sessão sem GPS points | Gerar arquivo sem track (só metadata) ou avisar user | `ExportGenerationFailed` |
| Sessão sem HR data | Gerar arquivo sem HR extensions (graceful) | — |
| Falha ao escrever temp file | Notificar user "Espaço insuficiente" | `ExportWriteFailed` |
| Share sheet cancelada pelo user | Ignorar (não é erro) | — |
| FIT format solicitado (stub) | Notificar "Formato FIT em desenvolvimento" | `ExportNotImplemented("FIT")` |

---

## 11. GARMIN / OUTROS — IMPORTAÇÃO MANUAL

### 11.1 Por que não existe upload automático para Garmin Connect

Garmin **não disponibiliza API pública** para upload de atividades.
O endpoint `POST /activity-service/activity/import` visível no portal web
é interno e exige cookie de sessão autenticada — não há OAuth, não há
client ID público, não há documentação. Usar engenharia reversa violaria
os Termos de Serviço da Garmin e resultaria em bloqueio de conta.

O caminho oficial para apps de terceiros é o **Garmin Health API /
Garmin Connect IQ SDK**, mas ambos exigem:

| Requisito | Realidade Omni Runner |
|-----------|----------------------|
| Contrato comercial com Garmin ("Health API Partner Program") | Inviável para MVP; processo de meses |
| Dispositivo Garmin com Connect IQ | Limita a um fabricante; fora do escopo |
| Garmin Health Enterprise API | Requer volume de usuários e aprovação corporativa |

A mesma situação se aplica a **Coros** (API fechada), **Suunto** (Suunto
App API apenas para parceiros), **Polar** (Polar AccessLink, read-only
para atividades de terceiros) e **Apple Fitness+** (não aceita import
externo via API).

**Conclusão:** A exportação de arquivo FIT/GPX/TCX + share sheet é a
estratégia universal que funciona com 100% das plataformas, hoje e no
futuro, sem depender de nenhum contrato ou aprovação.

### 11.2 Passo-a-passo para o usuário

#### Garmin Connect (Web)

1. No Omni Runner, tocar **Exportar** → escolher **FIT** (ou GPX)
2. Na share sheet, escolher **Salvar em Arquivos** (iOS) ou
   **Downloads** (Android)
3. Abrir [connect.garmin.com](https://connect.garmin.com) no navegador
4. Menu lateral → **Importar Dados** → arrastar o arquivo `.fit` / `.gpx`
5. Garmin processa e a atividade aparece no histórico

#### Garmin Connect (App Mobile)

1. No Omni Runner, exportar como **FIT** e compartilhar via share sheet
2. Escolher **Garmin Connect** na lista de apps (se disponível no
   dispositivo) — ou usar "Abrir com" → Garmin Connect
3. O app da Garmin importa automaticamente ao receber o arquivo

> **Nota:** A opção "Abrir com Garmin Connect" depende do dispositivo
> e versão do app. Se não aparecer, usar o método via web.

#### Coros / Suunto / Polar / TrainingPeaks / intervals.icu

| Plataforma | Formato recomendado | Como importar |
|------------|:-------------------:|---------------|
| **Coros** | FIT | coros.com → Histórico → Importar Arquivo |
| **Suunto** | GPX ou FIT | suuntoapp.com → arrastar arquivo |
| **Polar Flow** | GPX ou TCX | flow.polar.com → não suporta import direto; usar FIT via Strava sync |
| **TrainingPeaks** | FIT | trainingpeaks.com → Adicionar Treino → Importar Arquivo |
| **intervals.icu** | FIT ou GPX | intervals.icu → Activities → Upload |
| **Runalyze** | FIT, GPX ou TCX | runalyze.com → Importar → arrastar arquivo |
| **Smashrun** | GPX ou TCX | smashrun.com → Import → selecionar arquivo |

### 11.3 Limitações a comunicar ao usuário

| Limitação | Explicação honesta |
|-----------|-------------------|
| Não é automático | Garmin/Coros/Suunto não oferecem API pública de upload. Isso não é uma falha do Omni Runner. |
| FIT é o formato mais completo | GPX preserva rota e HR, mas FIT inclui pace, cadência, calorias, info do device. Se a plataforma aceitar FIT, prefira. |
| HR pode não aparecer em todos | Algumas plataformas ignoram HR em GPX se o namespace da extension não for reconhecido. FIT é mais confiável. |
| Dados de lap/split não exportam em GPX | GPX é uma trilha contínua. Splits só existem em TCX (Lap) e FIT (Lap message). |

### 11.4 UX Copy — Telas de instrução no app

O fluxo é acionado quando o usuário toca "Exportar para Garmin/Outros"
na tela de detalhes da corrida. São **2 telas** (máximo 3 se contar a
share sheet do OS):

#### Tela 1 — Escolher formato

```
┌────────────────────────────────────┐
│          Exportar Corrida          │
│                                    │
│  Escolha o formato:                │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  ★ FIT  (recomendado)       │  │
│  │  Mais completo: HR, pace,   │  │
│  │  calorias. Garmin, Coros,   │  │
│  │  TrainingPeaks.             │  │
│  └──────────────────────────────┘  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  GPX                        │  │
│  │  Universal: rota + HR.      │  │
│  │  Funciona em qualquer app.  │  │
│  └──────────────────────────────┘  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  TCX                        │  │
│  │  Garmin Connect,            │  │
│  │  TrainingPeaks, Strava.     │  │
│  └──────────────────────────────┘  │
│                                    │
│        [ Exportar ]                │
└────────────────────────────────────┘
```

**Copy:** Título = "Exportar Corrida". Subtítulo ausente (auto-explicativo).
FIT é o primeiro e marcado com estrela porque é o mais completo.

#### Tela 2 — Instrução rápida (bottom sheet, após share sheet fechar)

```
┌────────────────────────────────────┐
│  ✓  Arquivo salvo!                 │
│                                    │
│  Para importar no Garmin Connect:  │
│                                    │
│  1. Abra connect.garmin.com       │
│  2. Vá em Importar Dados          │
│  3. Arraste o arquivo .fit        │
│                                    │
│  Ou abra o arquivo direto no app  │
│  Garmin Connect do seu celular.   │
│                                    │
│  ── Outras plataformas ──         │
│  Coros, Suunto, TrainingPeaks:    │
│  mesmo processo no site oficial.  │
│                                    │
│        [ Entendi ]                 │
└────────────────────────────────────┘
```

**Copy guidelines:**
- Não pedir desculpa ("infelizmente…") — tom neutro e prático
- Não prometer integração futura — pode mudar
- Não culpar Garmin — apenas instruir
- Máximo 5 linhas de texto + 3 passos numerados
- Botão de dismiss = "Entendi" (não "OK", que é vago)

#### Tela 3 (opcional) — Primeiro uso apenas

Mostrada apenas na **primeira vez** que o usuário exporta para
"Garmin/Outros". Armazenar flag `has_seen_garmin_import_guide` em
`SharedPreferences`.

```
┌────────────────────────────────────┐
│  Sabia que…                        │
│                                    │
│  O Strava recebe corridas          │
│  automaticamente! Conecte sua      │
│  conta em Configurações → Strava.  │
│                                    │
│  Para Garmin e outros, a           │
│  importação é por arquivo — é      │
│  o padrão da indústria.            │
│                                    │
│  [ Conectar Strava ]  [ Pular ]    │
└────────────────────────────────────┘
```

**Objetivo:** educar sem irritar. Oferecer o caminho automático (Strava)
para quem não sabia, sem forçar.

---

## 12. FORMATO DE ARQUIVOS (RESUMO TÉCNICO)

### 12.1 GPX 1.1

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Omni Runner"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <metadata>
    <name>Morning Run</name>
    <time>2026-02-17T06:00:00Z</time>
  </metadata>
  <trk>
    <name>Morning Run</name>
    <trkseg>
      <trkpt lat="-23.550520" lon="-46.633308">
        <ele>760.0</ele>
        <time>2026-02-17T06:00:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>145</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <!-- ... -->
    </trkseg>
  </trk>
</gpx>
```

### 12.2 TCX

```xml
<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-02-17T06:00:00Z</Id>
      <Lap StartTime="2026-02-17T06:00:00Z">
        <TotalTimeSeconds>3600</TotalTimeSeconds>
        <DistanceMeters>10000.0</DistanceMeters>
        <Calories>650</Calories>
        <AverageHeartRateBpm><Value>145</Value></AverageHeartRateBpm>
        <MaximumHeartRateBpm><Value>175</Value></MaximumHeartRateBpm>
        <Track>
          <Trackpoint>
            <Time>2026-02-17T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>-23.550520</LatitudeDegrees>
              <LongitudeDegrees>-46.633308</LongitudeDegrees>
            </Position>
            <AltitudeMeters>760.0</AltitudeMeters>
            <DistanceMeters>0.0</DistanceMeters>
            <HeartRateBpm><Value>145</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>
```

### 12.3 FIT (Resumo)

FIT é binário (ANT+ / Garmin protocol). Estrutura:

```
[File Header (14 bytes)]
[Data Records]
  - File ID message
  - Device Info message
  - Session message (total distance, time, HR)
  - Lap message(s)
  - Record messages (per-point: lat, lng, alt, HR, timestamp)
[CRC (2 bytes)]
```

Coordenadas em FIT: semicircles (lat * (2^31 / 180)).
Timestamps: seconds since 1989-12-31T00:00:00Z (Garmin epoch).

---

## 13. DEFINITION OF DONE — PHASE 14

> Checklist testável. Cada item pode ser verificado por um QA humano
> ou por teste automatizado. A Fase 14 só é considerada DONE quando
> todos os itens estiverem marcados.

### 13.1 Export GPX/TCX funciona offline

| # | Critério | Como testar | Status |
|---|----------|-------------|--------|
| D01 | `GpxEncoder.encode()` gera XML válido GPX 1.1 com `<trk>`, `<trkseg>`, `<trkpt>` | `gpx_encoder_test.dart` (8 tests) | ✅ |
| D02 | `TcxEncoder.encode()` gera XML válido TCX com `<Activity>`, `<Lap>`, `<Track>` | `tcx_encoder_test.dart` (11 tests) | ✅ |
| D03 | GPX inclui HR via Garmin `TrackPointExtension` namespace | Abrir GPX no GPXSee → HR aparece no gráfico | ⬜ Manual |
| D04 | TCX inclui `<HeartRateBpm>` por trackpoint | Importar TCX no Garmin Connect web → HR visível | ⬜ Manual |
| D05 | Export funciona sem rede (opera somente em memória + disco local) | Ativar modo avião → exportar → arquivo gerado sem erro | ⬜ Manual |
| D06 | Sessão sem GPS gera arquivo vazio/metadata-only sem crash | `gpx_encoder_test.dart`: "empty route" test | ✅ |
| D07 | Sessão sem HR gera arquivo sem extensions (graceful degradation) | `gpx_encoder_test.dart`: "no HR" test | ✅ |
| D08 | FIT encoder retorna `ExportNotImplemented` com mensagem clara | `ExportServiceImpl` switch case + UI snackbar | ✅ Stub |

### 13.2 Share abre painel e gera arquivo válido

| # | Critério | Como testar | Status |
|---|----------|-------------|--------|
| D09 | `shareExportFile()` escreve temp file e abre share sheet nativa | `share_export_file_test.dart` + device manual | ✅ + ⬜ |
| D10 | Arquivo temp é cleanup best-effort após share | Log `[ShareExport] Temp file cleaned` no console | ✅ |
| D11 | Share cancellation pelo user NÃO gera erro | `shareExportFile` swallows share-cancelled exception | ✅ |
| D12 | Filename segue padrão `run_YYYY-MM-DD_HHMMSS.ext` | `share_export_file_test.dart` filename mapping test | ✅ |
| D13 | MIME type correto por formato (gpx+xml, vnd.garmin.tcx+xml, vnd.ant.fit) | `ExportFormat.mimeType` getter + `share_export_file_test.dart` | ✅ |
| D14 | `ExportScreen` → selecionar formato → "Exportar" → share sheet abre | Device manual test (iOS + Android) | ⬜ Manual |
| D15 | "Como importar" (ícone ?) mostra `HowToImportScreen` com passo-a-passo | Device manual test | ⬜ Manual |

### 13.3 Strava connect + upload funciona (com statuses)

| # | Critério | Como testar | Status |
|---|----------|-------------|--------|
| D16 | `StravaAuthRepositoryImpl.authenticate()` abre browser com URL correto | `strava_auth_repository_test.dart` | ✅ |
| D17 | `exchangeCode()` persiste tokens em `flutter_secure_storage` | `strava_auth_repository_test.dart` (mock store) | ✅ |
| D18 | `refreshToken()` atualiza access_token + refresh_token no store | `strava_auth_repository_test.dart` | ✅ |
| D19 | `getValidAccessToken()` faz refresh proativo quando `expires_at - 300 < now` | `strava_auth_repository_test.dart` | ✅ |
| D20 | `disconnect()` chama deauthorize + limpa store | `strava_auth_repository_test.dart` | ✅ |
| D21 | Upload POST retorna `StravaUploadQueued` com `uploadId` | `strava_upload_repository_test.dart` | ✅ |
| D22 | Polling loop transiciona: Queued → Processing → Ready | `strava_upload_repository_test.dart` | ✅ |
| D23 | Duplicate upload retorna `StravaUploadDuplicate` (não erro) | `strava_upload_repository_test.dart` | ✅ |
| D24 | 401 durante upload → refresh token 1x → replay request | `strava_upload_repository_test.dart` | ✅ |
| D25 | 429 rate limit → throw `UploadRateLimited` (não retry imediato) | `strava_upload_repository_test.dart` | ✅ |
| D26 | 5xx → exponential backoff (max 5 tentativas) | `StravaHttpClient.uploadFile` retry logic | ✅ |
| D27 | Multipart POST envia MIME type correto por formato | `strava_upload_repository_test.dart` filename test | ✅ |
| D28 | `isTerminal` getter correto para todos os 5 status subtypes | `strava_upload_repository_test.dart` | ✅ |
| D29 | End-to-end: conectar conta Strava real → upload GPX → atividade aparece | Conta de teste Strava | ⬜ Manual |

### 13.4 Erros têm mensagens acionáveis

| # | Critério | Como testar | Status |
|---|----------|-------------|--------|
| D30 | `IntegrationFailure` sealed class com pattern matching exhaustivo | `integrations_failures.dart` — compilador garante | ✅ |
| D31 | `HealthExportFailure` sealed class com 6 subtypes | `health_export_service_test.dart` | ✅ |
| D32 | Cada failure mapeia para mensagem PT-BR user-facing | `HealthExportController` switch + `PHASE_14_INTEGRATIONS.md` §6.2 | ✅ |
| D33 | `HealthExportNeedsUpdate` → mensagem inclui "Google Play" | `health_export_service_test.dart` | ✅ |
| D34 | `HealthExportPermissionDenied` → mensagem guia para Settings | `health_export_service_test.dart` | ✅ |
| D35 | `ExportNotImplemented("FIT")` → snackbar "Formato FIT em desenvolvimento" | `ExportScreen._export()` catch block | ✅ |
| D36 | Strava `AuthRevoked` → "Reconecte sua conta" (não "erro desconhecido") | `PHASE_14_INTEGRATIONS.md` §6.2 | ✅ |
| D37 | Nenhuma mensagem de erro genérica sem contexto ("Error", "Failed") | Code review: grep para mensagens vagas | ⬜ Review |

### 13.5 Logs de integração existem (sem dados sensíveis)

| # | Critério | Como testar | Status |
|---|----------|-------------|--------|
| D38 | Upload events logados: enqueued, started, polling, succeeded, failed | `StravaUploadRepositoryImpl` dev.log calls | ✅ |
| D39 | Auth events logados: flow started, callback, refresh, revoked | `StravaAuthRepositoryImpl` dev.log calls | ✅ |
| D40 | File export events logados: format, size, filename | `ExportSheetController` + `shareExportFile` | ✅ |
| D41 | Health export events logados: platform, route pts, HR samples | `HealthExportServiceImpl` AppLogger calls | ✅ |
| D42 | `access_token` NUNCA aparece em nenhum log | `grep -r "access_token" lib/ --include="*.dart"` → apenas em store keys e JSON parsing, nunca em log() | ✅ |
| D43 | `refresh_token` NUNCA aparece em nenhum log | Idem | ✅ |
| D44 | `client_secret` NUNCA aparece em nenhum log | Idem | ✅ |
| D45 | Coordenadas GPS NUNCA logadas em texto (lat/lng individuais) | Logs usam apenas "count" de pontos, não valores | ✅ |

### 13.6 Sem segredos hardcoded

| # | Critério | Como testar | Status |
|---|----------|-------------|--------|
| D46 | `STRAVA_CLIENT_ID` vem de `--dart-define` (não literal no código) | `StravaHttpClient` constructor recebe parâmetros | ✅ |
| D47 | `STRAVA_CLIENT_SECRET` vem de `--dart-define` | Idem | ✅ |
| D48 | Tokens armazenados em `flutter_secure_storage` (não SharedPreferences) | `StravaSecureStore` usa `FlutterSecureStorage` | ✅ |
| D49 | `.env` / `.env.example` no `.gitignore` | Verificar `.gitignore` | ⬜ Verify |
| D50 | Nenhum token ou secret em arquivos versionados | `git log --all -p -- "*.dart" \| grep -i secret` → 0 | ⬜ Verify |

---

## 14. TOP 10 RISCOS — DETECÇÃO RÁPIDA EM QA

| # | Risco | Probabilidade | Impacto | Como detectar rápido | Tempo para detectar |
|---|-------|:---:|:---:|----------------------|:---:|
| **Q1** | **GPX exportado inválido** (XML malformado, namespace errado) | Média | Alto | Importar no GPXSee (desktop, gratuito) + Garmin Connect web. Se rejeitar, o XML está quebrado. Automatizável: parse GPX com `xml` package no teste. | 2 min |
| **Q2** | **Token Strava não refresha** (refresh_token corrompido ou não salvo) | Média | Alto | Conectar Strava → esperar 6h (ou forçar `expires_at = 0` no store) → tentar upload. Se 401 sem recovery → bug no refresh flow. | 5 min (forçado) |
| **Q3** | **Upload Strava retorna "duplicate" quando não deveria** | Baixa | Médio | Exportar 2 sessões diferentes → ambas devem gerar `activity_id` distintos. Se a 2ª retorna "duplicate" → `external_id` não é unique (usar session UUID). | 3 min |
| **Q4** | **Share sheet não abre no Android 14+** (mudanças de intent) | Média | Médio | Testar em device Android 14+ (API 34). Se share sheet não abre → verificar `share_plus` versão e `FileProvider` config. Android 12-13 como baseline. | 1 min |
| **Q5** | **Health Connect não instalado** (Android < 14 sem HC pré-instalado) | Alta | Médio | Testar em emulador Android 13 sem Health Connect. A UI deve mostrar "Health Connect não está instalado" com link para Play Store — NÃO crash. | 1 min |
| **Q6** | **HealthKit permission denied silenciosamente no iOS** | Média | Médio | Negar permissão no Health app → exportar → deve retornar `HealthExportPermissionDenied` com mensagem guiando o user para Settings. Apple NÃO diz se read foi negado, mas write denial é detectável. | 2 min |
| **Q7** | **Arquivo TCX sem HR quando sessão tem HR** | Média | Médio | Correr com HR monitor → exportar TCX → abrir XML → procurar `<HeartRateBpm>`. Se ausente → `TcxEncoder` não recebeu `hrSamples` (bug de wiring no controller). | 2 min |
| **Q8** | **OAuth callback deep link não interceptado** (app em background) | Média | Alto | iOS: fechar app via task switcher durante OAuth → reabrir → callback `omnirunner://strava/callback` deve ser processado. Android: Custom Tab → back button → retentar. Se loop infinito → `app_links` config incorreta. | 3 min |
| **Q9** | **Rate limit Strava em rajada** (muitos uploads seguidos) | Baixa | Médio | Fazer 5 uploads em sequência rápida → verificar que o 6º recebe 429 → app mostra "Limite de uploads atingido" (não crash ou retry infinito). Headers `X-RateLimit-Usage` devem ser respeitados. | 5 min |
| **Q10** | **Temp file não limpo após share** (acumula em cache) | Baixa | Baixo | Exportar 20 vezes → verificar `getTemporaryDirectory()` → arquivos `run_*.gpx` devem ser < 5 (cleanup best-effort). Se > 20 → cleanup não funciona, mas OS eventualmente limpa. | 2 min |

### Matriz de prioridade QA

```
              IMPACTO
         Baixo    Médio    Alto
Alta   |        | Q5     |        |
Média  |        | Q4,Q6  | Q1,Q2  |
       |        | Q7,Q9  | Q8     |
Baixa  | Q10    | Q3     |        |
```

**Ordem de teste recomendada (blast radius):**
1. Q1 — GPX/TCX válido (fundação de tudo)
2. Q2 — Token refresh (bloqueia upload)
3. Q8 — Deep link callback (bloqueia OAuth)
4. Q5 — Health Connect ausente (crash potential)
5. Q6 — HealthKit permission denied
6. Q4 — Share sheet Android 14+
7. Q7 — TCX sem HR
8. Q3 — Duplicate upload
9. Q9 — Rate limit
10. Q10 — Temp cleanup

### Ferramentas de QA recomendadas

| Ferramenta | Uso | Custo |
|------------|-----|-------|
| GPXSee | Validar GPX/TCX visualmente | Gratuito, desktop |
| Garmin Connect web | Importar GPX/FIT/TCX real | Gratuito, conta Garmin |
| Strava test account | Upload end-to-end | Gratuito, conta dedicada |
| FIT SDK Validator (Garmin) | Validar FIT binário | Gratuito, Java |
| Charles Proxy | Inspecionar HTTP sem MITM em release | Pago / trial |
| Android Studio Device File Explorer | Verificar temp files | Gratuito |
| Xcode Instruments | Medir I/O e network | Gratuito |

---

*Documento criado em Sprint 14.0.1. Atualizado a cada micro-passo.*
