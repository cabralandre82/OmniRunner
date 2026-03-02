# ADR-004: Estratégia de Internacionalização

**Status:** Accepted  
**Date:** 2026-02-01

## Context

O app e portal precisam suportar pt-BR (principal) e en (secundário) para expansão internacional.

## Decision

### Flutter App
- `flutter_localizations` + `intl` (ARB files)
- Template: `lib/l10n/app_pt.arb` (130+ strings)
- Tradução: `lib/l10n/app_en.arb`
- Acesso: `context.l10n.stringKey` via extension `AppLocalizationsX`

### Portal
- `next-intl` com JSON message files
- `messages/pt-BR.json` e `messages/en.json` (namespaced: common, nav, auth, settings, athletes, error)
- Server: `getTranslations()` / Client: `useTranslations(namespace)`
- Plugin integrado ao `next.config.mjs`

## Consequences

- Strings centralizadas, fáceis de auditar
- Suporte a plurais e interpolação via ICU
- Locale detection automático no Portal (via `next-intl`)
- Custo: toda nova string precisa ir nos 2 ARB/JSON files
