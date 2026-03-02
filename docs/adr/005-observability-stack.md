# ADR-005: Stack de Observabilidade

**Status:** Accepted  
**Date:** 2026-02-01

## Context

Precisamos de visibilidade sobre erros, performance e saúde da aplicação em produção, tanto no app Flutter quanto no Portal Next.js.

## Decision

### Logging
- **Flutter:** `AppLogger` (wrapper sobre `dart:developer`), com `onError` hook para Sentry
- **Portal:** `logger.ts` customizado com integração Sentry

### Error Tracking
- **Sentry** para ambos: client, server, e edge configs no Portal; app-wide no Flutter
- Captura de exceções via `FlutterError.onError` e `PlatformDispatcher.instance.onError`

### Health Check
- `GET /api/health` retorna `{ status: "ok", timestamp, db: "ok|error" }`
- Ping ao Supabase para validar conectividade do banco

### Debug
- `DiagnosticsScreen` no Flutter (somente debug mode) com status de todos os serviços

## Consequences

- Erros em produção são capturados automaticamente com context
- Health check permite monitoramento externo (UptimeRobot, etc.)
- Zero custo extra — Sentry free tier é suficiente para o volume atual
