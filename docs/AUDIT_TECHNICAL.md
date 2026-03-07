# Auditoria Técnica — Omni Runner

**Data:** 2026-03-06  
**Escopo:** App Flutter · Portal Next.js · Backend Supabase  
**Metodologia:** Análise estática de código-fonte, revisão de arquitetura, inventário de dívida técnica

---

## 1. Qualidade da Arquitetura de Código

### 1.1 Aderência ao Clean Architecture (App)

O app Flutter segue Clean Architecture de forma consistente ao longo de 636 arquivos `.dart`:

| Camada | Responsabilidade | Aderência |
|--------|-----------------|-----------|
| **Domain** | Entidades (67), interfaces de repositório (48), use cases | ✅ Alta |
| **Data** | Implementações de repositório, data sources (Supabase + Isar) | ✅ Alta |
| **Presentation** | BLoCs (31), screens (99), widgets | ⚠️ Alta com exceções |

**Pontos fortes:**
- Entidades de domínio são PODOs puros, sem dependência de frameworks.
- Interfaces de repositório residem na camada de domínio; implementações na camada de data.
- Use cases encapsulam regras de negócio unitárias.

**Desvios identificados:**
- Algumas telas fazem chamadas diretas ao Supabase, contornando a camada de BLoC/repositório. Isso viola a separação de camadas e dificulta testes unitários.
- Diretório `tracking_bloc` encontrado vazio — indica feature abandonada ou incompleta.

### 1.2 Padrão BLoC

Os 31 BLoCs utilizam hierarquias de falha seladas (`sealed class Failure`) para comunicar erros do domínio à apresentação de forma tipada. A adoção do padrão é consistente, com exceção das telas que fazem bypass direto.

### 1.3 Injeção de Dependência

A DI é centralizada em um único arquivo de registro com 663 linhas. Embora funcional, essa abordagem apresenta problemas:

- **Legibilidade:** difícil navegar e localizar registros específicos.
- **Conflitos de merge:** arquivo único gera colisões frequentes em trabalho paralelo.
- **Recomendação:** particionar por feature module (`di/auth_module.dart`, `di/workout_module.dart`, etc.).

### 1.4 Arquitetura do Portal

O portal Next.js emprega Server Components com `force-dynamic` na maioria das páginas. A estrutura segue o padrão App Router com:

- 40 arquivos `loading.tsx` fornecendo skeletons durante carregamento.
- Error boundaries em cada nível de rota.
- Validação Zod em todas as rotas de API.
- 338 arquivos organizados por domínio funcional.

### 1.5 Arquitetura do Backend

- 131 migrações SQL indicam evolução iterativa do schema.
- 59 Edge Functions com padrão stateless.
- RLS em todas as tabelas com funções `SECURITY DEFINER` e `search_path` hardening.
- Processamento de webhooks Strava via fila (queue-based), evitando perda de eventos.

---

## 2. Organização do Código

### 2.1 Estrutura de Diretórios

| Componente | Estrutura | Avaliação |
|-----------|-----------|-----------|
| App Flutter | Feature-first com subdivisão `domain/data/presentation` | ✅ Boa |
| Portal Next.js | App Router com colocalização de componentes por rota | ✅ Boa |
| Edge Functions | Uma pasta por função, com `index.ts` | ✅ Consistente |
| Migrações | Sequenciais numeradas | ⚠️ 11 migrações "fix" corrigindo anteriores |

### 2.2 Convenções de Nomenclatura

- **Dart:** `snake_case` para arquivos, `PascalCase` para classes — padrão Dart respeitado.
- **TypeScript/Next.js:** `kebab-case` para rotas, `PascalCase` para componentes.
- **SQL:** `snake_case` para tabelas e colunas, prefixo descritivo em funções RPC.
- **Renomeações recentes** de labels (Webhook → Cobranças, Custódia → Saldo OmniCoins) melhoram a clareza semântica.

### 2.3 Consistência

A consistência geral é alta, com desvios pontuais:
- Versões mistas de imports Deno nas Edge Functions.
- Strings hardcoded em português apesar de setup de i18n existente no app.

---

## 3. Separação de Responsabilidades

### 3.1 App Flutter

```
Domain ──────── Entities (67) + Repository Interfaces (48) + Use Cases
    │                    ↑ depende apenas de abstrações
Data ────────── Repository Impl + DataSources (Supabase + Isar)
    │                    ↑ implementa interfaces do domínio
Presentation ── BLoCs (31) + Screens (99) + Widgets
                         ↑ consome use cases via DI
```

**Violações:** Chamadas diretas a Supabase em algumas telas quebram a inversão de dependência.

### 3.2 Portal Next.js

- **Server Components:** Buscam dados e renderizam HTML.
- **API Routes:** Validam com Zod, delegam a serviços/Supabase.
- **Client Components:** Estado local + interação do usuário.
- **Middleware:** Autenticação, CSRF, rate limiting.

A separação é clara. O uso de Server Components é predominante, reduzindo JavaScript no cliente.

### 3.3 Backend Supabase

- **RLS:** Controle de acesso declarativo em nível de linha.
- **RPCs (SECURITY DEFINER):** Operações atômicas com lógica de negócio (wallet, billing).
- **Edge Functions:** Integrações externas (Strava, Asaas, webhooks).
- **Triggers:** Auditoria automática e propagação de estado.

---

## 4. Uso do Backend

### 4.1 Corretude do RLS

- RLS ativado em todas as tabelas.
- Testes de penetração RLS existentes validam que usuários não acessam dados alheios.
- Funções `SECURITY DEFINER` com `search_path` fixo previnem ataques de path injection.

**Riscos:**
- Políticas RLS auto-referentes (uma policy que consulta a própria tabela) podem impactar performance em tabelas grandes.

### 4.2 Padrões de Edge Functions

- 59 funções seguem padrão stateless.
- Infraestrutura compartilhada (`shared/`) para autenticação, logging e respostas padronizadas.
- **Exceção:** `asaas-webhook` não utiliza os utilitários compartilhados, divergindo do padrão.
- Lógica anti-cheat duplicada entre `verify-session` e `strava-webhook`.
- Versões mistas de imports Deno criam risco de incompatibilidade.

### 4.3 Infraestrutura Compartilhada

- Validação HMAC de webhooks.
- Processamento via fila para webhooks Strava.
- Webhooks idempotentes (upsert com chave de idempotência).

---

## 5. Tratamento de Erros

### 5.1 Visão Multi-Camada

| Camada | Mecanismo | Avaliação |
|--------|-----------|-----------|
| **Domain (App)** | Sealed failure hierarchies (`Failure` → `NetworkFailure`, `AuthFailure`, etc.) | ✅ Excelente |
| **BLoC (App)** | Emissão de estados de erro tipados; mapeamento `Failure → ErrorState` | ✅ Bom |
| **UI (App)** | Tratamento de `ErrorState` com mensagens humanizadas via `ErrorMessages.humanize()` | ✅ Bom |
| **Bootstrap (App)** | Cada inicialização em try/catch individual — falha parcial não impede start | ✅ Excelente |
| **API Routes (Portal)** | Validação Zod com respostas 400 estruturadas | ✅ Bom |
| **Error Boundaries (Portal)** | Em cada nível de rota; fallback com UI de erro | ✅ Bom |
| **Edge Functions** | Try/catch com logging estruturado e resposta JSON padronizada | ✅ Bom |
| **Sentry** | Integração no app para captura de exceções não tratadas | ✅ Bom |

### 5.2 Resiliência de Bootstrap

O app inicializa cada módulo (auth, Isar, Sentry, analytics, etc.) em blocos try/catch individuais. Se um módulo falha, os demais continuam. Essa abordagem é exemplar para apps mobile onde condições de inicialização são imprevisíveis.

### 5.3 Logging Estruturado

O portal utiliza logging JSON estruturado, facilitando ingestão por ferramentas como Datadog/CloudWatch. O backend usa os logs nativos do Supabase/Deno.

---

## 6. Implementação de Segurança

### 6.1 Matriz de Segurança

| Controle | Implementação | Status |
|----------|--------------|--------|
| **CSP (Content Security Policy)** | Headers configurados no portal Next.js | ✅ Ativo |
| **CSRF Protection** | Token CSRF em mutações do portal | ✅ Ativo |
| **Webhook HMAC** | Verificação de assinatura em webhooks recebidos | ✅ Ativo |
| **Rate Limiting** | Middleware no portal | ⚠️ In-memory (não escala com load balancer) |
| **RLS** | Todas as tabelas com políticas ativas | ✅ Ativo |
| **RLS Penetration Tests** | Suítes de teste que tentam acessar dados como usuário errado | ✅ Ativo |
| **SECURITY DEFINER + search_path** | Funções SQL com path hardening | ✅ Ativo |
| **Anti-Cheat** | Flags de integridade em sessões de corrida | ✅ Ativo |
| **Audit Trail** | Logging de ações sensíveis | ✅ Ativo |

### 6.2 Vulnerabilidade Identificada: Rate Limiting

O rate limiter in-memory funciona em instância única. Em deploy com múltiplas réplicas (load balancer), cada instância mantém contadores separados, permitindo bypass multiplicando requisições pelo número de réplicas.

**Mitigação recomendada:** Migrar para rate limiting baseado em Redis (Upstash) ou utilizar o rate limiting nativo do Vercel/Cloudflare.

### 6.3 Anti-Cheat

Pipeline de anti-cheat com flags de integridade para validar sessões de corrida. Lógica duplicada entre `verify-session` e `strava-webhook` — risco de divergência se apenas uma cópia for atualizada.

---

## 7. Legibilidade do Código

### 7.1 Nomenclatura

- Entidades e classes seguem nomes descritivos e auto-documentados.
- Funções RPC no backend usam nomes verbais claros (ex: `transfer_balance`, `process_billing`).
- A renomeação recente de labels de UI (Custódia → Saldo OmniCoins) demonstra preocupação com clareza para o usuário final.

### 7.2 Documentação

- Extensa documentação em `/docs/` com 150+ arquivos cobrindo arquitetura, QA, segurança, ADRs, runbooks.
- Código em si tem comentários moderados — a tipagem forte (Dart/TypeScript) reduz necessidade.

### 7.3 Complexidade Ciclomática

- Os 31 BLoCs mantêm responsabilidade focada.
- O arquivo de DI (663 linhas) é o principal ponto de complexidade de leitura.
- Edge Functions são curtas e focadas em geral.

---

## 8. Inventário de Dívida Técnica

| # | Item | Severidade | Impacto | Esforço |
|---|------|-----------|---------|---------|
| 1 | **Isar v3 arquivado/EOL** com override de path local | 🔴 Alta | Risco de incompatibilidade futura; sem patches de segurança | Alto |
| 2 | **Rate limiter in-memory** não escala com múltiplas instâncias | 🔴 Alta | Bypass de rate limiting em produção com load balancer | Baixo |
| 3 | **Telas fazendo bypass de BLoC** com chamadas diretas ao Supabase | 🟡 Média | Viola Clean Arch; dificulta testes e manutenção | Médio |
| 4 | **Navegação imperativa** (`Navigator.push`) em 99 telas, sem rota declarativa | 🟡 Média | Deep links frágeis; difícil rastreamento de rotas; acoplamento | Alto |
| 5 | **Lógica anti-cheat duplicada** em `verify-session` e `strava-webhook` | 🟡 Média | Risco de divergência silenciosa | Baixo |
| 6 | **`asaas-webhook` não usa utilitários compartilhados** | 🟡 Média | Inconsistência de tratamento de erros e logging | Baixo |
| 7 | **Dark mode hardcoded** no portal (sem toggle) | 🟢 Baixa | Acessibilidade reduzida para usuários que preferem light mode | Baixo |
| 8 | **WebVitals só logam no console** | 🟢 Baixa | Sem telemetria de performance real em produção | Baixo |
| 9 | **Versões mistas de imports Deno** nas Edge Functions | 🟢 Baixa | Risco de quebra em atualizações | Baixo |
| 10 | **11 migrações "fix"** corrigindo migrações anteriores | 🟢 Baixa | Poluição do histórico de schema; não afeta runtime | Nenhum |
| 11 | **Diretório `tracking_bloc` vazio** | 🟢 Baixa | Código morto / feature abandonada | Nenhum |
| 12 | **Strings hardcoded em português** apesar de setup i18n | 🟢 Baixa | Bloqueia internacionalização futura | Médio |
| 13 | **Arquivo de DI com 663 linhas** | 🟢 Baixa | Dificulta manutenção e gera conflitos de merge | Médio |
| 14 | **`force-dynamic` na maioria das páginas do portal** | 🟢 Baixa | Perde otimização de cache estático do Next.js | Médio |

---

## 9. Resumo de Forças e Fraquezas

| Aspecto | Força | Fraqueza |
|---------|-------|----------|
| **Arquitetura** | Clean Architecture consistente com 67 entidades, 48 interfaces, 31 BLoCs | Bypass de BLoC em algumas telas; DI monolítico |
| **Segurança** | RLS em tudo + penetration tests + HMAC + CSP + CSRF + anti-cheat | Rate limiter in-memory; anti-cheat duplicado |
| **Resiliência** | Bootstrap fault-tolerant; Error boundaries em todo nível; sealed failures | Isar v3 EOL; imports Deno inconsistentes |
| **Testes** | 263 arquivos de teste; 600 testes portal; 169 testes app; Playwright E2E | Cobertura não verificada em telas que bypassam BLoC |
| **Backend** | SECURITY DEFINER + search_path; webhooks idempotentes; ledger imutável | 11 migrações corretivas; asaas-webhook isolado |
| **UX Técnico** | 40 loading skeletons; Zod validation; mensagens humanizadas | Dark mode sem toggle; WebVitals só console |
| **Organização** | Feature-first; nomenclatura consistente; 150+ docs | 663 linhas DI; tracking_bloc vazio; strings hardcoded |
| **Escalabilidade** | Offline-first; Server Components; queue-based webhooks | force-dynamic generalizado; rate limiter stateful |

---

## Veredicto Geral

O Omni Runner apresenta uma base técnica **sólida e madura**, com aderência consistente ao Clean Architecture, segurança em múltiplas camadas, e resiliência acima da média para um produto neste estágio. A dívida técnica existente é **gerenciável** — os itens de severidade alta (Isar EOL e rate limiter) possuem caminhos de mitigação claros. A cobertura de testes (263 arquivos incluindo penetration tests RLS) é um diferencial significativo. O principal risco estrutural é a dependência do Isar v3 arquivado, que deve ser endereçada no médio prazo com migração para alternativa mantida (Drift, ObjectBox, ou Isar v4 quando disponível).
