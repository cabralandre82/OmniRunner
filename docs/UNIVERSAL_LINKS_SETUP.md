# UNIVERSAL_LINKS_SETUP.md — Deep Links Universais (Android App Links + iOS Universal Links)

> **Sprint:** 19.2.0
> **Domínio:** `omnirunner.app`
> **Padrão:** `https://omnirunner.app/invite/{code}`

---

## 1. VISÃO GERAL

| Plataforma | Mecanismo | Verificação |
|------------|-----------|-------------|
| Android | App Links (`autoVerify=true`) | `/.well-known/assetlinks.json` |
| iOS | Universal Links (Associated Domains) | `/.well-known/apple-app-site-association` |
| Fallback | Se app não instalado, abre `https://omnirunner.app/invite/{code}` no browser |

---

## 2. ARQUIVOS DE VERIFICAÇÃO (servir em HTTPS)

### 2.1 Android — `/.well-known/assetlinks.json`

Servir em `https://omnirunner.app/.well-known/assetlinks.json` com
`Content-Type: application/json`.

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.omnirunner.omni_runner",
      "sha256_cert_fingerprints": [
        "<RELEASE_SHA256_FINGERPRINT>"
      ]
    }
  }
]
```

Para obter o fingerprint:

```bash
keytool -list -v -keystore <release.keystore> -alias <alias> \
  | grep SHA256 | awk '{print $NF}'
```

Para debug (signing report do Gradle):

```bash
cd android && ./gradlew signingReport 2>&1 | grep SHA-256
```

### 2.2 iOS — `/.well-known/apple-app-site-association`

Servir em `https://omnirunner.app/.well-known/apple-app-site-association` com
`Content-Type: application/json` (sem extensão `.json`).

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "<TEAM_ID>.com.omnirunner.omniRunner",
        "paths": [
          "/invite/*",
          "/auth-callback"
        ]
      }
    ]
  }
}
```

Substituir `<TEAM_ID>` pelo Apple Team ID (visível em
developer.apple.com → Membership).

---

## 3. CONFIGURAÇÃO NO APP

### 3.1 Android (`AndroidManifest.xml`)

```xml
<!-- App Links: https://omnirunner.app (invite, share, fallback web) -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https" android:host="omnirunner.app"/>
</intent-filter>
```

### 3.2 iOS (`Runner.entitlements`)

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:omnirunner.app</string>
</array>
```

### 3.3 Flutter (deep link handler)

O pacote `app_links` intercepta Universal/App Links e custom schemes.
O handler em `lib/core/deep_links/deep_link_handler.dart` parseia o path
e roteia para a tela correta.

Rotas suportadas:

| Path | Ação |
|------|------|
| `/invite/{code}` | Abre fluxo de convite de assessoria |
| `/auth-callback` | Supabase auth session recovery |

---

## 4. FALLBACK WEB

Se o app não estiver instalado, o link `https://omnirunner.app/invite/{code}`
deve exibir uma página web com:

1. Mensagem: "Você foi convidado para uma assessoria no Omni Runner"
2. Botões para download (App Store / Google Play)
3. O código do convite visível para entrada manual

A landing page pode ser uma página estática hospedada no domínio `omnirunner.app`.

---

## 5. CHECKLIST

| # | Item | Status |
|---|------|--------|
| 1 | Domínio `omnirunner.app` registrado | [ ] |
| 2 | HTTPS ativo no domínio | [ ] |
| 3 | `assetlinks.json` publicado com SHA-256 correto | [ ] |
| 4 | `apple-app-site-association` publicado com Team ID correto | [ ] |
| 5 | Android `autoVerify="true"` no AndroidManifest | [x] |
| 6 | iOS `applinks:omnirunner.app` no entitlements | [x] |
| 7 | Flutter `app_links` handler implementado | [x] |
| 8 | Fallback web page criada | [ ] |
| 9 | Testado: link abre app (Android) | [ ] |
| 10 | Testado: link abre app (iOS) | [ ] |
| 11 | Testado: fallback web funciona | [ ] |

---

## 6. TESTE LOCAL

### Android

```bash
adb shell am start -a android.intent.action.VIEW \
  -d "https://omnirunner.app/invite/TEST123" \
  com.omnirunner.omni_runner
```

### iOS

```bash
xcrun simctl openurl booted "https://omnirunner.app/invite/TEST123"
```

---

*Documento criado em 19.2.0.*
