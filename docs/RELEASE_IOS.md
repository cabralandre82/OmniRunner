# Omni Runner — iOS Release Signing Checklist

> Guia passo-a-passo para preparar, assinar e publicar o app na App Store.
> Atualizado: 2026-02-12 (Sprint 10.6)

---

## Pre-requisitos

- [ ] Mac com Xcode 15+ instalado
- [ ] Apple Developer Account ativa ($99/ano) — https://developer.apple.com
- [ ] Flutter SDK instalado e `flutter doctor` sem erros iOS
- [ ] CocoaPods instalado (`sudo gem install cocoapods`)

---

## 1. Bundle Identifier

O Bundle ID atual do projeto é:

```
com.omnirunner.omniRunner
```

Definido em: `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`)

**Ações necessárias:**

- [ ] Decidir Bundle ID final (sugestão: `com.omnirunner.app` ou manter atual)
- [ ] Registrar Bundle ID no Apple Developer Portal:
  - https://developer.apple.com/account/resources/identifiers/add/bundleId
  - Platform: iOS
  - Capabilities: Background Modes (Location updates)
- [ ] Se alterar o Bundle ID, atualizar em **todos** os targets do Xcode:
  - Runner (3 configurations: Debug, Release, Profile)
  - RunnerTests (3 configurations)

---

## 2. Certificates (Certificados)

Certificados vinculam sua identidade ao app assinado.

### 2.1 Development Certificate

Para builds de teste em devices reais.

- [ ] Em Xcode: Preferences > Accounts > Manage Certificates
- [ ] Criar "Apple Development" certificate se não existir
- [ ] Alternativa: Xcode Automatic Signing faz isso automaticamente

### 2.2 Distribution Certificate

Para publicação na App Store.

- [ ] Criar "Apple Distribution" certificate no Developer Portal:
  - https://developer.apple.com/account/resources/certificates/add
  - Tipo: Apple Distribution
- [ ] Gerar CSR (Certificate Signing Request) no Keychain Access:
  1. Keychain Access > Certificate Assistant > Request a Certificate from CA
  2. Email: seu email do Apple Developer
  3. Request is: Saved to disk
- [ ] Upload CSR no portal e baixar o certificado `.cer`
- [ ] Duplo-click no `.cer` para instalar no Keychain
- [ ] Verificar: Keychain Access > My Certificates > "Apple Distribution: ..."

**Limite:** Máximo 3 Distribution Certificates por conta.

---

## 3. Provisioning Profiles

Profiles vinculam Bundle ID + Certificate + Devices (dev) ou App Store (dist).

### 3.1 Development Profile

- [ ] Criar em: https://developer.apple.com/account/resources/profiles/add
  - Tipo: iOS App Development
  - App ID: (seu Bundle ID)
  - Certificate: (seu Development cert)
  - Devices: (selecionar devices de teste)
- [ ] Baixar e instalar (duplo-click ou arrastar para Xcode)

### 3.2 App Store Distribution Profile

- [ ] Criar em: https://developer.apple.com/account/resources/profiles/add
  - Tipo: App Store Connect
  - App ID: (seu Bundle ID)
  - Certificate: (seu Distribution cert)
- [ ] Baixar e instalar

### 3.3 Automatic Signing (recomendado para MVP)

Xcode pode gerenciar tudo automaticamente:

- [ ] Abrir `ios/Runner.xcworkspace` no Xcode
- [ ] Selecionar target Runner > Signing & Capabilities
- [ ] Marcar "Automatically manage signing"
- [ ] Selecionar Team (sua conta Apple Developer)
- [ ] Xcode cria certificates e profiles automaticamente

> **Recomendação MVP:** Usar Automatic Signing. Migrar para manual apenas
> se precisar de CI/CD sem Xcode (ex: Codemagic, GitHub Actions).

---

## 4. Capabilities & Entitlements

O app usa capabilities que precisam ser habilitadas no portal:

- [ ] **Background Modes** > Location updates (já em Info.plist: `UIBackgroundModes = [location]`)
- [ ] Verificar que o Bundle ID no portal tem essa capability ativa

Capabilities **não necessárias** (não habilitar):
- Push Notifications (não usado)
- In-App Purchase (não usado no MVP)
- HealthKit (não usado no MVP)

---

## 5. Info.plist — Verificação Final

| Campo | Valor atual | Ação |
|---|---|---|
| `CFBundleDisplayName` | Omni Runner | ✅ OK |
| `CFBundleName` | omni_runner | ⚠️ Mudar para `Omni Runner` (aparece em Settings) |
| `NSLocationWhenInUseUsageDescription` | (texto claro) | ✅ OK |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | (texto claro) | ✅ OK |
| `UIBackgroundModes` | [location] | ✅ OK |

**Ação:**

- [ ] Alterar `CFBundleName` de `omni_runner` para `Omni Runner`

---

## 6. Xcode Build Configurations

Configurações atuais (padrão Flutter):

| Configuration | Uso |
|---|---|
| Debug | `flutter run` (desenvolvimento) |
| Release | `flutter build ipa` (produção) |
| Profile | `flutter run --profile` (performance) |

### 6.1 Flavors iOS (opcional, para dev/prod no mesmo device)

Se quiser iOS flavors equivalentes ao Android `productFlavors`:

1. No Xcode, duplicar cada configuration:
   - Debug > Debug-dev, Debug-prod
   - Release > Release-dev, Release-prod
   - Profile > Profile-dev, Profile-prod

2. Criar Schemes:
   - dev: usa Debug-dev / Release-dev / Profile-dev
   - prod: usa Debug-prod / Release-prod / Profile-prod

3. Em cada configuration, definir `PRODUCT_BUNDLE_IDENTIFIER`:
   - dev: `com.omnirunner.omniRunner.dev`
   - prod: `com.omnirunner.omniRunner`

4. Flutter detecta automaticamente via `--flavor dev|prod`

> **Para MVP:** Não é necessário. Basta usar `--dart-define-from-file=.env.prod`
> para separar keys. Flavors iOS só são necessários para instalar dev+prod
> simultaneamente no mesmo device.

---

## 7. Gerar IPA / Publicar

### 7.1 Build via Flutter CLI

```bash
# Gerar IPA (requer Xcode com signing configurado)
flutter build ipa \
  --dart-define-from-file=.env.prod \
  --release

# Saída: build/ios/ipa/omni_runner.ipa
```

### 7.2 Build via Xcode (alternativa)

1. Abrir `ios/Runner.xcworkspace`
2. Selecionar scheme "Runner" e device "Any iOS Device"
3. Product > Archive
4. Window > Organizer > selecionar archive
5. Distribute App > App Store Connect

### 7.3 Upload via Transporter (alternativa)

```bash
# Instalar Transporter (app da Apple) ou usar xcrun
xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/omni_runner.ipa \
  --apiKey YOUR_API_KEY \
  --apiIssuer YOUR_ISSUER_ID
```

---

## 8. App Store Connect — Preparação

- [ ] Criar app em https://appstoreconnect.apple.com
  - Bundle ID: (mesmo do Xcode)
  - SKU: `omni-runner`
  - Primary Language: Portuguese (Brazil) ou English
- [ ] Preencher metadata:
  - Nome: Omni Runner
  - Subtitle: (opcional, ex: "Your intelligent running companion")
  - Description: (textos em PT-BR e EN)
  - Keywords: running, GPS, tracker, corrida
  - Category: Health & Fitness
  - Privacy Policy URL: **OBRIGATÓRIO** (bloqueador da Sprint 10.1)
- [ ] Screenshots: iPhone 6.7" (obrigatório), iPhone 6.1", iPad (se universal)
- [ ] App Icon: 1024x1024 sem alpha channel
- [ ] Age Rating: 4+ (sem conteúdo restrito)
- [ ] Pricing: Free

---

## 9. Review Guidelines — Pontos de Atenção

| Guideline | Status | Notas |
|---|---|---|
| 2.16 Background Location | ⚠️ | Precisa de vídeo/texto explicando uso de background location |
| 5.1.1 Data Collection | ⚠️ | Declarar GPS no App Privacy (nutrition label) |
| 5.1.2 Privacy Policy | ❌ BLOQUEADOR | URL pública obrigatória |
| 2.1 App Completeness | ✅ | MVP funcional |
| 4.0 Design | ✅ | UI nativa Flutter Material |

**Nota sobre Background Location (2.16):**

A Apple exige justificativa detalhada para `NSLocationAlwaysAndWhenInUseUsageDescription`.
No campo "Notes" da submissão, explicar:

> "Omni Runner is a GPS running tracker. Background location is required to
> continue recording the user's route when the screen is locked or the app
> is in the background during an active workout session. Location data is
> only collected during active tracking sessions initiated by the user."

---

## 10. Checklist Final Pre-Submissão

- [ ] Bundle ID registrado no portal
- [ ] Signing configurado (Automatic ou Manual)
- [ ] `CFBundleName` corrigido para "Omni Runner"
- [ ] `flutter build ipa` gera sem erros
- [ ] App testado em device real (iPhone)
- [ ] Privacy Policy URL pública criada
- [ ] App Privacy labels preenchidos no App Store Connect
- [ ] Screenshots capturados
- [ ] App Icon 1024x1024 sem alpha
- [ ] Vídeo/texto de justificativa para background location
- [ ] Metadata completo (nome, descrição, keywords, categoria)
- [ ] TestFlight build submetido e testado antes do release

---

*Documento criado na Sprint 10.6. Atualizar conforme o processo avança.*
