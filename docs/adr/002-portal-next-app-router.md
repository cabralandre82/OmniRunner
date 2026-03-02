# ADR-002: Next.js App Router para o Portal

**Status:** Accepted  
**Date:** 2025-06-01

## Context

O Portal B2B precisa de SSR para SEO e performance, API routes colocadas junto com pages, e um sistema de layouts aninhados para platform admin vs portal assessoria.

## Decision

Usar Next.js 14+ com App Router:

- Route groups `(portal)/` e `platform/` com layouts dedicados
- Server Components por padrão, Client Components (`"use client"`) apenas quando necessário
- API routes em `app/api/` com Zod validation e rate limiting
- Supabase SSR via `@supabase/ssr` (cookie-based auth)

## Consequences

- Server Components reduzem JS enviado ao cliente
- API routes colocadas junto com UI facilitam navegação no código
- Layouts aninhados evitam re-renders desnecessários
- Complexidade de hydration mismatch com Supabase auth
