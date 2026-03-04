# AUDIT MASTER REPORT — Omni Runner

**Data:** 2026-03-04  
**Auditor:** Principal Engineer / Lead QA / Security Auditor  
**Nível de Rigor:** 100/100  
**Escopo:** Repositório completo (`/home/usuario/project-running`)  
**Branch:** `master` (commit `8b27870`)

---

## Resumo Executivo

O sistema Omni Runner é uma plataforma completa de running com coaching, gamificação, financeiro e social. O repositório é um **monorepo** contendo:
- **Flutter App** (100 telas, 31 BLoCs, 619 arquivos Dart)
- **Portal Next.js** (55+ páginas, 36 API routes, 273 arquivos TS/TSX)
- **Supabase Backend** (57 edge functions, 92 migrations, 75+ tabelas)
- **Watch Apps** (Apple Watch + Wear OS)

A auditoria cobriu 12 etapas e gerou 12 documentos detalhados. Abaixo está a consolidação de todos os problemas encontrados.

---

## Documentos Gerados

| # | Documento | Etapa |
|---|-----------|-------|
| 1 | `AUDIT_REPO_ARCHITECTURE.md` | Arquitetura do repo |
| 2 | `AUDIT_FEATURE_MAP.md` | Mapa de funcionalidades |
| 3 | `AUDIT_USER_FLOW.md` | Fluxos de usuário |
| 4 | `AUDIT_FRONTEND.md` | Auditoria frontend |
| 5 | `AUDIT_BACKEND.md` | Auditoria backend |
| 6 | `AUDIT_RLS.md` | Auditoria RLS |
| 7 | `AUDIT_LOCAL_DATA.md` | Dados locais |
| 8 | `AUDIT_INTEGRATIONS.md` | Integrações |
| 9 | `AUDIT_WEARABLES.md` | Wearables |
| 10 | `AUDIT_PERFORMANCE.md` | Performance |
| 11 | `AUDIT_SECURITY.md` | Segurança |
| 12 | `AUDIT_UX.md` | UX |

---

## Lista Completa de Problemas

### CRITICAL (P0) — Corrigir antes de produção

| # | Problema | Etapa | Impacto | Correção Recomendada | Prioridade |
|---|----------|-------|---------|---------------------|------------|
| C1 | **MercadoPago webhook sem verificação de assinatura HMAC** | Security | Atacante pode fabricar webhooks de pagamento, criando tokens/créditos falsos | Implementar verificação `x-signature` do MP usando shared secret | **P0** |
| C2 | **Edge functions retornam service-role client no `requireUser()`** | Backend | Todas as queries em edge functions bypassam RLS. Se validação de role falhar em qualquer ponto, acesso irrestrito ao DB | Separar user client (anon+JWT) do service client. Usar service client apenas para operações admin explícitas | **P0** |
| C3 | **CORS com wildcard `*` em edge functions** | Security | Qualquer site pode chamar edge functions com credenciais do usuário | Restringir `Access-Control-Allow-Origin` ao domínio do app e portal | **P0** |
| C4 | **~15-20 SECURITY DEFINER functions sem `SET search_path`** | Security/RLS | Vulnerável a search_path injection se atacante criar schema malicioso | Adicionar `SET search_path = public` em todas as funções SECURITY DEFINER restantes | **P0** |
| C5 | **Confirmação de email desabilitada no Supabase** | Security | Qualquer email pode ser usado para criar conta sem verificação | Habilitar `enable_confirmations = true` em `config.toml` | **P0** |

### MAJOR (P1) — Corrigir no próximo sprint

| # | Problema | Etapa | Impacto | Correção Recomendada | Prioridade |
|---|----------|-------|---------|---------------------|------------|
| M1 | **TrainingPeaks OAuth state parameter não é assinado** | Security/Integrations | Account linking hijack — atacante pode vincular conta TP de outro usuário | Gerar state com HMAC usando server secret | **P1** |
| M2 | **OAuth tokens (Strava/TP) armazenados em plaintext no DB** | Security | Staff com acesso à tabela `coaching_device_links`/`strava_tokens` pode ler tokens de atletas | Criptografar tokens em repouso com envelope encryption | **P1** |
| M3 | **N+1 serial no `trainingpeaks-sync` push** | Performance | 4 queries + 1 API call por item × 50 = 250 operações seriais. Timeout provável em produção | Batch RPC + `Promise.all()` para paralelizar | **P1** |
| M4 | **Platform admin pages usam service-role com gate apenas de cookie** | Backend/Security | Cookie `portal_role` pode ser manipulado pelo browser. Gate admin é app-level, não DB-level | Verificar `platform_role` via query ao `profiles` (server-side) em cada request admin | **P1** |
| M5 | **Journal do TodayScreen não persiste dados** | User Flow | Atleta escreve nota, vê "salva!", mas dados são descartados | Criar tabela `session_journal_entries` ou usar `profiles.notes`, persistir via RPC | **P1** |
| M6 | **Portal confia em `group_id` do cookie sem re-verificação** | Security | Coach pode trocar cookie para acessar dados de outro grupo | Verificar `coaching_members` membership no server component antes de cada query | **P1** |
| M7 | **Isar sem criptografia** | Local Data | Dados financeiros, coaching e pessoais armazenados em plaintext no dispositivo | Habilitar `Isar.open(encryptionKey: ...)` com chave derivada | **P1** |
| M8 | **Sem cache invalidation/TTL no Isar** | Local Data | Dados podem ficar eternamente desatualizados se sync falhar | Implementar TTL por coleção + forçar refresh em app resume | **P1** |

### MINOR (P2) — Melhorias para próximas releases

| # | Problema | Etapa | Impacto | Correção Recomendada | Prioridade |
|---|----------|-------|---------|---------------------|------------|
| m1 | **5 telas órfãs sem ponto de navegação** | User Flow | Código morto: `groups_screen`, `group_evolution_screen`, `group_events_screen`, `group_rankings_screen`, `recovery_screen` | Remover ou reintegrar na navegação | **P2** |
| m2 | **Friends Activity Feed desabilitado** | User Flow | Screen + RPC existem, mas tile mostra "Coming Soon" | Completar e habilitar quando pronto | **P2** |
| m3 | **Deleção de tag e unlink de device sem confirmation dialog** | UX | Ação destrutiva sem confirmação — usuário pode deletar por acidente | Adicionar `ConfirmDialog` antes de deletar | **P2** |
| m4 | **Mensagens de erro raw (`e.toString()`) mostradas ao usuário** | Frontend/UX | Mensagens técnicas incompreensíveis para o usuário final | Mapear erros para mensagens amigáveis | **P2** |
| m5 | **~40 telas Flutter fazem query direta ao Supabase** | Architecture | Viola Clean Architecture — presentation layer acessa data layer diretamente | Migrar para repository pattern via service locator | **P2** |
| m6 | **`select('*')` em queries sem restringir colunas** | Performance | Transfere dados desnecessários, payload maior | Especificar colunas em todas as queries | **P2** |
| m7 | **Missing indexes em `coaching_device_links(group_id, provider)` e `billing_purchases(payment_reference)`** | Performance | Queries lentas em produção com volume alto | Criar migration com CREATE INDEX | **P2** |
| m8 | **Accessibility (Semantics) esparsa no Flutter** | UX | Screen readers não conseguem navegar corretamente | Adicionar `Semantics` widget em todos os elementos interativos | **P2** |
| m9 | **Sem queue offline para log de execução de wearable** | Wearables | Se dispositivo offline durante log, dados perdidos | Implementar queue local com retry | **P2** |
| m10 | **Senha mínima 6 caracteres sem complexidade** | Security | Senhas fracas permitem brute force | Aumentar para 8+ e exigir maiúscula + número | **P2** |
| m11 | **FIT encoder doc-comment diz "not implemented" mas está implementado** | Integration | Documentação desatualizada confunde devs | Atualizar doc-comment | **P2** |
| m12 | **Portal páginas sem `loading.tsx`** | Frontend | Flash of empty content durante SSR fetch | Adicionar loading.tsx em todas as páginas dinâmicas | **P2** |
| m13 | **Social groups (groups, group_members) coexistem com coaching_groups** | Architecture | Schemas duplicados, confusão semântica | Depreciar formalmente ou migrar dados | **P2** |
| m14 | **Service locator com 965 linhas** | Architecture | Monolítico, difícil de manter | Modularizar em `sl_core.dart`, `sl_coaching.dart`, etc. | **P2** |

---

## Métricas de Saúde

| Dimensão | Score | Justificativa |
|----------|-------|--------------|
| **Segurança** | 72/100 | 5 criticals (webhook, CORS, search_path, email, service-role) |
| **Performance** | 85/100 | 1 N+1 critical, some missing indexes, select(*) |
| **RLS** | 88/100 | Cobertura boa, alguns gaps em search_path |
| **Frontend** | 90/100 | Loading/error/empty states sólidos, ~40 screens bypass architecture |
| **UX** | 91/100 | Design system consistente, gaps menores (confirmações, a11y) |
| **Backend** | 82/100 | Auth pattern inconsistente (service-role everywhere), validação sólida |
| **Integrações** | 92/100 | Strava production-ready, TP frozen corretamente |
| **Dados Locais** | 78/100 | Isar sem encryption, sem TTL, financial data cached |
| **Completude** | 95/100 | 98.4% dos fluxos completos, 5 telas órfãs |
| **Testes** | 83/100 | 138 Flutter + 68 portal + 16 E2E, gaps em screens e integration |

### **Score Geral: 86/100**

---

## Plano de Correção Recomendado

### Sprint 1 (Imediato — P0)
1. Implementar verificação HMAC no webhook MercadoPago
2. Separar user client / service client em edge functions
3. Restringir CORS para domínios do app e portal
4. Adicionar `SET search_path = public` em todas SECURITY DEFINER functions
5. Habilitar confirmação de email no Supabase

### Sprint 2 (Próximo — P1)
6. Assinar OAuth state parameter (HMAC)
7. Criptografar tokens OAuth em repouso
8. Refatorar N+1 no trainingpeaks-sync (batch)
9. Verificar platform_role via DB (não cookie)
10. Persistir journal entries no TodayScreen
11. Re-verificar group_id membership no server
12. Habilitar Isar encryption
13. Implementar cache TTL no Isar

### Sprint 3 (Melhorias — P2)
14. Limpar telas órfãs
15. Adicionar confirmation dialogs
16. Mapear erros para mensagens amigáveis
17. Criar indexes faltantes
18. Melhorar accessibility
19. Modularizar service locator

---

## Conclusão

O sistema está em estado **sólido para staging** mas tem **5 blockers críticos de segurança** que devem ser corrigidos antes de produção. A arquitetura é bem estruturada (Clean Architecture + BLoC no Flutter, SSR + API routes no Portal), com uma base de código significativa (~900 arquivos) e boa cobertura de testes.

As maiores preocupações são:
1. **Segurança de webhooks** (MercadoPago sem verificação)
2. **Modelo de autorização em edge functions** (service-role usado universalmente)
3. **CORS permissivo** (wildcard em produção)
4. **Dados locais sem proteção** (Isar sem encryption)

Com as correções P0 implementadas, o score subiria para **92+/100**.
