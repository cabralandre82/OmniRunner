# SOCIAL_AUTH_SETUP.md — Social Login Configuration (Google, Apple, TikTok, Instagram)

> **Sprint:** Phase 18 / Phase 19
> **Micro-passos:** 18.1.0 (Google/Apple), 19.1.0 (TikTok/Instagram)
> **Escopo:** External console configuration ONLY (no Flutter/migration/Edge Function changes)

---

## ESTADO ATUAL DA AUTH

| Aspecto | Valor |
|---------|-------|
| Auth backend | Supabase GoTrueClient |
| Método atual | `signInAnonymously()` fallback + email/password |
| Mock mode | `MockAuthDataSource` — local UUID via SharedPreferences |
| Remote mode | `RemoteAuthDataSource` — Supabase Auth |
| Social providers | Google ✓, Apple ✓, TikTok (sandbox), Instagram (dev mode) |
| Android package | `com.omnirunner.omni_runner` |
| iOS bundle ID | `com.omnirunner.omniRunner` |
| Deep link scheme | `omnirunner://` |

---

## 1. GOOGLE SIGN-IN

### 1.1 Google Cloud Console

1. Acessar [Google Cloud Console](https://console.cloud.google.com/)
2. Criar projeto (ou selecionar existente): **Omni Runner**
3. Ativar **Google Identity** API (APIs & Services → Library → "Google Identity")

### 1.2 Criar OAuth 2.0 Credentials

**Web Client (para Supabase callback):**

1. APIs & Services → Credentials → Create Credentials → OAuth client ID
2. Application type: **Web application**
3. Name: `Omni Runner Supabase`
4. Authorized redirect URIs:

```
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

5. Salvar **Client ID** e **Client Secret**

**Android Client:**

1. Create Credentials → OAuth client ID
2. Application type: **Android**
3. Package name: `com.omnirunner.omni_runner`
4. SHA-1 certificate fingerprint:

```bash
# Debug key
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA1

# Release key (quando disponível)
keytool -list -v -keystore <release.keystore> -alias <alias> | grep SHA1
```

5. Salvar (não gera secret — Android usa package+SHA1)

**iOS Client:**

1. Create Credentials → OAuth client ID
2. Application type: **iOS**
3. Bundle ID: `com.omnirunner.omniRunner`
4. Salvar **iOS Client ID**

### 1.3 Configurar no Supabase Dashboard

1. Supabase Dashboard → **Authentication** → **Providers** → **Google**
2. Toggle: **Enable Sign in with Google** → ON
3. Preencher:
   - **Client ID (for oauth):** `<web_client_id>` (o Web Client criado em 1.2)
   - **Client Secret:** `<web_client_secret>`
4. **Authorized Client IDs** (campo adicional): adicionar os Client IDs de Android e iOS para que `signInWithIdToken` funcione
5. Salvar

### 1.4 Redirect URL

O Supabase usa automaticamente:

```
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

Para o fluxo mobile nativo com `signInWithIdToken` (que será implementado no Flutter em um passo futuro), o redirect URL não é usado diretamente — o `idToken` é obtido pelo SDK nativo (Google Sign-In) e passado ao Supabase via API.

### 1.5 Verificação

```bash
# Testar via curl (simulando um token exchange)
# Nota: em produção, o idToken vem do google_sign_in SDK no Flutter
curl -s -X POST "https://<PROJECT_REF>.supabase.co/auth/v1/token?grant_type=id_token" \
  -H "apikey: <ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "google",
    "id_token": "<GOOGLE_ID_TOKEN>"
  }' | jq .

# ✅ ESPERADO: access_token + refresh_token + user criado em auth.users
```

---

## 2. APPLE SIGN-IN

### 2.1 Apple Developer Portal

1. Acessar [Apple Developer](https://developer.apple.com/account)

**Registrar App ID (se não existente):**

1. Certificates, Identifiers & Profiles → Identifiers → App IDs
2. Verificar que `com.omnirunner.omniRunner` existe
3. Em Capabilities, ativar **Sign in with Apple** → Enable as a primary App ID

**Criar Service ID (para web auth flow):**

1. Identifiers → + → **Services IDs**
2. Description: `Omni Runner Auth`
3. Identifier: `com.omnirunner.omniRunner.auth` (convenção: bundleId + `.auth`)
4. Ativar **Sign in with Apple** → Configure:
   - Primary App ID: `com.omnirunner.omniRunner`
   - Website URLs → Domains and Subdomains: `<PROJECT_REF>.supabase.co`
   - Return URLs:

```
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

5. Salvar

**Gerar Key (P8):**

1. Keys → + → Name: `Omni Runner Sign in with Apple`
2. Ativar **Sign in with Apple** → Configure → Primary App ID: `com.omnirunner.omniRunner`
3. Register → Download o arquivo `.p8`
4. Anotar o **Key ID** (10 caracteres)
5. Anotar o **Team ID** (visível em Membership)

### 2.2 Gerar o Secret JWT para Supabase

Apple requer um JWT assinado com a chave P8 como "client_secret". O Supabase aceita
o conteúdo da chave P8 diretamente e gera o JWT internamente.

Informações necessárias:

| Campo | Valor |
|-------|-------|
| Team ID | `<APPLE_TEAM_ID>` (10 chars, de Membership) |
| Key ID | `<APPLE_KEY_ID>` (10 chars, do Key registrado) |
| Service ID | `com.omnirunner.omniRunner.auth` |
| P8 Key content | Conteúdo do arquivo `.p8` (incluindo `-----BEGIN/END PRIVATE KEY-----`) |

### 2.3 Configurar no Supabase Dashboard

1. Supabase Dashboard → **Authentication** → **Providers** → **Apple**
2. Toggle: **Enable Sign in with Apple** → ON
3. Preencher:
   - **Client ID:** `com.omnirunner.omniRunner.auth` (o Service ID)
   - **Secret Key:** conteúdo do arquivo `.p8` (incluindo headers BEGIN/END)
4. **Additional Settings** (se disponível):
   - Team ID: `<APPLE_TEAM_ID>`
   - Key ID: `<APPLE_KEY_ID>`
5. Salvar

### 2.4 iOS: Xcode Capability

Para o fluxo nativo iOS (futuro micro-passo Flutter), o Xcode precisa da capability:

1. Xcode → Runner target → Signing & Capabilities → + → **Sign in with Apple**

> **Nota:** Isso é configuração do Xcode, não do Dashboard. Documentado aqui
> para referência, mas será executado no micro-passo Flutter.

### 2.5 Redirect URL

Igual ao Google:

```
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

Para o fluxo mobile nativo com `sign_in_with_apple`, o redirect URL não é
usado diretamente no iOS — o `identityToken` é obtido nativamente pela API
`AuthenticationServices` e passado ao Supabase via `signInWithIdToken`.

### 2.6 Verificação

```bash
# Testar via curl (simulando um token exchange)
# Nota: em produção, o identityToken vem do sign_in_with_apple SDK
curl -s -X POST "https://<PROJECT_REF>.supabase.co/auth/v1/token?grant_type=id_token" \
  -H "apikey: <ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "apple",
    "id_token": "<APPLE_IDENTITY_TOKEN>"
  }' | jq .

# ✅ ESPERADO: access_token + refresh_token + user criado em auth.users
```

---

## 3. CONFIGURAÇÃO DO supabase/config.toml (local)

Para desenvolvimento local com `supabase start`, atualizar `supabase/config.toml`:

```toml
[auth.external.google]
enabled = true
client_id = "env(GOOGLE_CLIENT_ID)"
secret = "env(GOOGLE_CLIENT_SECRET)"
redirect_uri = ""
skip_nonce_check = false

[auth.external.apple]
enabled = true
client_id = "env(APPLE_SERVICE_ID)"
secret = "env(APPLE_P8_SECRET)"
redirect_uri = ""
skip_nonce_check = false

[auth.external.facebook]
enabled = true
client_id = "env(FACEBOOK_APP_ID)"
secret = "env(FACEBOOK_APP_SECRET)"
redirect_uri = ""
skip_nonce_check = false
```

> **Instagram**: O provider `facebook` do Supabase é o caminho nativo para
> Instagram. Meta OAuth dá acesso ao perfil Instagram do usuário quando
> autorizado. Não existe provider separado "instagram" no Supabase.
>
> **TikTok**: NÃO há provider nativo no Supabase. Variáveis `TIKTOK_CLIENT_KEY`
> e `TIKTOK_CLIENT_SECRET` serão usadas pela Edge Function customizada
> `validate-social-login` (sprint 19.2.0).

As variáveis de ambiente devem ser configuradas no `.env` local
(já listado no `.gitignore`).

---

## 4. CONFIGURAÇÕES GERAIS DO SUPABASE AUTH

### 4.1 URL Configuration

1. Dashboard → Authentication → URL Configuration
2. **Site URL:** `omnirunner://auth-callback` (deep link para o app Flutter)
3. **Redirect URLs (allowlist):**

```
omnirunner://auth-callback
omnirunner://strava/callback
https://omnirunner.app/auth-callback
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

### 4.2 General Settings

1. Dashboard → Authentication → Settings
2. **Enable email confirmations:** OFF (para MVP — simplifica onboarding)
3. **Allow new users to sign up:** ON
4. **Enable anonymous sign-ins:** ON (mantém o workaround existente)

---

## 5. CHECKLIST DE CONFIGURAÇÃO

| # | Item | Status |
|---|------|--------|
| 1 | Google Cloud Console: projeto criado | [ ] |
| 2 | Google: Web OAuth Client ID + Secret gerados | [ ] |
| 3 | Google: Android OAuth Client ID (com SHA-1) | [ ] |
| 4 | Google: iOS OAuth Client ID (com bundle ID) | [ ] |
| 5 | Supabase: Google provider habilitado + credenciais | [ ] |
| 6 | Apple Developer: App ID com "Sign in with Apple" | [ ] |
| 7 | Apple: Service ID criado + Return URL configurado | [ ] |
| 8 | Apple: Key (P8) gerada e baixada | [ ] |
| 9 | Supabase: Apple provider habilitado + credenciais | [ ] |
| 10 | Supabase: Site URL = `omnirunner://auth-callback` | [ ] |
| 11 | Supabase: Redirect URLs allowlist atualizado | [ ] |
| 12 | Supabase: Anonymous sign-ins mantido ON | [ ] |
| 13 | Facebook Developers: app Consumer criado | [ ] |
| 14 | Facebook: Facebook Login + Instagram Basic Display habilitados | [ ] |
| 15 | Supabase: Facebook provider habilitado + credenciais | [ ] |
| 16 | `config.toml` atualizado com todos os providers (Google, Apple, Facebook) | [ ] |
| 14 | Teste: login Google cria user em auth.users | [ ] |
| 15 | Teste: login Apple cria user em auth.users | [ ] |

---

## 6. INFORMAÇÕES NÃO INCLUÍDAS (SEGURANÇA)

Ver seção 12 para a lista completa de segredos.

---

## 7. FLUXO FUTURO (Flutter — NÃO neste micro-passo)

O próximo micro-passo (18.2.0) implementará no Flutter:

1. Adicionar dependências: `google_sign_in`, `sign_in_with_apple`
2. Expandir `IAuthDataSource` com métodos `signInWithGoogle()` / `signInWithApple()`
3. Implementar em `RemoteAuthDataSource` usando `signInWithIdToken`
4. Criar `LoginScreen` com botões sociais
5. Xcode: adicionar capability "Sign in with Apple"
6. AndroidManifest: configurar intent filter para deep link

Este micro-passo (18.1.0) apenas habilita os providers no Supabase Dashboard.

---

---

## 8. TIKTOK LOGIN

> **Sprint:** 19.1.0
> **Nota:** Supabase NÃO tem provider nativo para TikTok. A integração será
> via SDK nativo + Edge Function customizada (passo futuro).

### 8.1 TikTok for Developers Console

1. Acessar [TikTok for Developers](https://developers.tiktok.com/)
2. Criar conta de developer (requer conta TikTok)
3. **Create App** → App name: `Omni Runner`
4. Selecionar plataforma: **Mobile Application**
   - Android package name: `com.omnirunner.omni_runner`
   - iOS bundle ID: `com.omnirunner.omniRunner`

### 8.2 Habilitar Login Kit

1. Na página do app → **Add Products** → **Login Kit** → Enable
2. Scopes necessários: `user.info.basic` (display name, avatar)
3. Redirect URI:

```
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

4. Anotar:
   - **Client Key** (App ID)
   - **Client Secret**

### 8.3 Status do App

| Aspecto | Valor |
|---------|-------|
| Status | Sandbox (teste com contas autorizadas) |
| Produção requer | Review pela TikTok — submeter quando fluxo estiver implementado |
| Sandbox limit | Até 20 test users adicionados manualmente |

### 8.4 Verificação (sandbox)

```bash
# 1. Gerar authorization URL (redireciona o usuário)
# CSRF state e PKCE code_verifier devem ser gerados pelo client
AUTHORIZE_URL="https://www.tiktok.com/v2/auth/authorize/\
?client_key=<CLIENT_KEY>\
&scope=user.info.basic\
&response_type=code\
&redirect_uri=https://<PROJECT_REF>.supabase.co/auth/v1/callback\
&state=<RANDOM_STATE>"

# 2. Após redirect, trocar code por access_token
curl -s -X POST "https://open.tiktokapis.com/v2/oauth/token/" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_key=<CLIENT_KEY>&\
client_secret=<CLIENT_SECRET>&\
code=<AUTHORIZATION_CODE>&\
grant_type=authorization_code&\
redirect_uri=https://<PROJECT_REF>.supabase.co/auth/v1/callback"

# ✅ ESPERADO: access_token + open_id + scope
```

---

## 9. INSTAGRAM LOGIN (via Facebook Developers)

> **Sprint:** 19.1.0 / 19.1.1
> **Atualização 19.1.1:** Supabase suporta **Facebook** como provider nativo
> (`auth.external.facebook`). O provider Facebook/Meta cobre Instagram quando o
> usuário autoriza Instagram Basic Display. **NÃO é necessária Edge Function
> customizada para Instagram** — usar `signInWithOAuth(OAuthProvider.facebook)`
> ou SDK nativo com `signInWithIdToken`. Veja DECISAO 043.

### 9.1 Facebook Developers Console

1. Acessar [Facebook Developers](https://developers.facebook.com/)
2. Criar conta de developer (requer conta Facebook)
3. **Create App** → App type: **Consumer**
4. App name: `Omni Runner`
5. Anotar **App ID** e **App Secret** (Settings → Basic)

### 9.2 Configurar Instagram Login

1. Na página do app → **Add Product** → **Facebook Login** → Set Up
   - (Facebook Login inclui suporte a Instagram accounts)
2. **Settings** → Valid OAuth Redirect URIs:

```
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

3. Na página do app → **Add Product** → **Instagram Basic Display** → Set Up
4. **Instagram Basic Display** → Basic Display:
   - Valid OAuth Redirect URIs:

```
https://<PROJECT_REF>.supabase.co/auth/v1/callback
```

   - Deauthorize Callback URL: `https://<PROJECT_REF>.supabase.co/auth/v1/callback`
   - Data Deletion Request URL: `https://<PROJECT_REF>.supabase.co/auth/v1/callback`

5. **Instagram App ID** e **Instagram App Secret** (diferentes do Facebook App):
   - Na seção Instagram Basic Display → anotar estes valores

### 9.3 Configurar Plataformas

1. Settings → Basic → Add Platform:
   - **Android:** package name `com.omnirunner.omni_runner`, key hashes (SHA-1 convertido para base64)
   - **iOS:** bundle ID `com.omnirunner.omniRunner`

### 9.4 Status do App

| Aspecto | Valor |
|---------|-------|
| Status | Development (teste com roles autorizados) |
| Produção requer | App Review pela Meta — submeter permissions `instagram_basic`, `pages_show_list` |
| Dev mode limit | Apenas users com role no app (admin/developer/tester) |
| Privacy Policy URL | Obrigatória antes de produção |
| Terms of Service URL | Obrigatória antes de produção |

### 9.5 Verificação (development mode)

```bash
# 1. Gerar authorization URL
AUTHORIZE_URL="https://api.instagram.com/oauth/authorize\
?client_id=<INSTAGRAM_APP_ID>\
&redirect_uri=https://<PROJECT_REF>.supabase.co/auth/v1/callback\
&scope=user_profile\
&response_type=code"

# 2. Após redirect, trocar code por access_token
curl -s -X POST "https://api.instagram.com/oauth/access_token" \
  -F "client_id=<INSTAGRAM_APP_ID>" \
  -F "client_secret=<INSTAGRAM_APP_SECRET>" \
  -F "grant_type=authorization_code" \
  -F "redirect_uri=https://<PROJECT_REF>.supabase.co/auth/v1/callback" \
  -F "code=<AUTHORIZATION_CODE>"

# ✅ ESPERADO: access_token + user_id

# 3. Buscar perfil
curl -s "https://graph.instagram.com/me?fields=id,username&access_token=<ACCESS_TOKEN>"

# ✅ ESPERADO: { "id": "...", "username": "..." }
```

---

## 10. CHECKLIST TIKTOK + INSTAGRAM

| # | Item | Status |
|---|------|--------|
| 1 | TikTok: conta developer criada | [ ] |
| 2 | TikTok: app criado (Omni Runner) | [ ] |
| 3 | TikTok: Login Kit habilitado | [ ] |
| 4 | TikTok: Client Key + Secret obtidos | [ ] |
| 5 | TikTok: Redirect URI registrada | [ ] |
| 6 | TikTok: Test users adicionados (sandbox) | [ ] |
| 7 | Instagram: conta Facebook Developer criada | [ ] |
| 8 | Instagram: app criado (Consumer type) | [ ] |
| 9 | Instagram: Facebook Login configurado | [ ] |
| 10 | Instagram: Instagram Basic Display configurado | [ ] |
| 11 | Instagram: App ID + App Secret obtidos | [ ] |
| 12 | Instagram: Instagram App ID + Secret obtidos | [ ] |
| 13 | Instagram: Redirect URIs registradas | [ ] |
| 14 | Instagram: Plataformas Android/iOS adicionadas | [ ] |
| 15 | Secrets armazenados de forma segura (NÃO em código) | [ ] |

---

## 11. INTEGRAÇÃO FUTURA (NÃO neste micro-passo)

### Instagram/Facebook — Provider nativo (sprint 19.3.0+)

Facebook é provider nativo do Supabase (`auth.external.facebook`). O fluxo é:

```
┌─────────────┐    ┌──────────────┐    ┌──────────────────┐
│ Flutter App  │───>│ Supabase Auth│───>│ Meta OAuth       │
│ signInWith   │    │ (facebook)   │    │ (FB + Instagram) │
│ OAuth()      │<───│ → JWT        │<───│ → access_token   │
└─────────────┘    └──────────────┘    └──────────────────┘
```

Passos futuros:
1. Flutter: `signInWithOAuth(OAuthProvider.facebook)` ou SDK nativo + `signInWithIdToken`
2. `profiles.created_via` expansion: `OAUTH_FACEBOOK`
3. LoginScreen: botão "Entrar com Instagram/Facebook"

### TikTok — Edge Function customizada (sprint 19.2.0+)

Supabase **não suporta TikTok nativamente**. O fluxo requer Edge Function:

```
┌─────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ Flutter App  │    │ TikTok          │    │ Edge Function    │
│              │───>│ Native SDK      │───>│ validate-social  │
│ signIn()     │    │ → auth code     │    │ → exchange code  │
│              │<───│                 │    │ → get user info  │
│ receive JWT  │<───────────────────────── │ → create session │
└─────────────┘    └─────────────────┘    └──────────────────┘
```

Passos futuros:
1. Edge Function `validate-social-login` (trocar code por access_token, buscar profile)
2. Flutter: SDK nativo TikTok
3. `IAuthDataSource.signInWithTikTok()`
4. `profiles.created_via` expansion: `OAUTH_TIKTOK`
5. LoginScreen: botão "Entrar com TikTok"

---

## 12. INFORMAÇÕES NÃO INCLUÍDAS (SEGURANÇA)

Os seguintes valores são secretos e NÃO devem estar neste documento:

- Google Client ID / Client Secret
- Apple Team ID / Key ID / P8 key content
- TikTok Client Key / Client Secret
- Instagram/Facebook App ID / App Secret
- Supabase project reference / anon key / service role key
- SHA-1 fingerprints de release

Armazenar em:
- Supabase Dashboard (providers config)
- `.env` local (gitignored)
- Gerenciador de segredos da CI/CD (para builds automatizados)

---

*Documento atualizado em 19.1.1 — Facebook provider nativo no Supabase; TikTok permanece custom. Veja DECISAO 043.*
