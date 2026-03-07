# Auditoria de Escalabilidade — Omni Runner

**Data:** 2026-03-06  
**Escopo:** App Flutter · Portal Next.js · Backend Supabase  
**Metodologia:** Análise de padrões de escalabilidade, gargalos potenciais e projeções de carga

---

## 1. Escalabilidade do Banco de Dados

### 1.1 Indexação e Busca

- **Indexes:** Colunas utilizadas em WHERE, JOIN e ORDER BY possuem indexes adequados.
- **pg_trgm:** Extensão habilitada para busca fuzzy (busca de alunos por nome, treinos por título).
- **GIN indexes em trgm:** Permitem buscas `ILIKE`/`similarity()` com performance sub-linear.

### 1.2 Padrões de Consulta

- **Paginação em RPCs:** Funções RPC implementam paginação (LIMIT/OFFSET ou cursor-based) para evitar retorno de datasets grandes.
- **LATERAL JOIN:** Utilizado para resolver N+1 queries, buscando dados relacionados em uma única query.
- **Views materializadas:** Não identificadas — podem ser necessárias para dashboards com agregações complexas em escala.

### 1.3 Schema Evolution

- **131 migrações** demonstram evolução iterativa saudável.
- **11 migrações "fix"** indicam que o schema estabilizou após iterações — normal em produto em desenvolvimento.
- **CHECK constraints financeiros** (`balance >= 0`) são verificados inline pelo PostgreSQL sem overhead significativo.

### 1.4 Limitações de Escalabilidade

| Fator | Status | Impacto em Escala |
|-------|--------|------------------|
| RLS auto-referente | ⚠️ Presente | Pode causar sequential scans em tabelas grandes se policy consulta a própria tabela |
| Ausência de connection pooling dedicado | ⚠️ Supabase PgBouncer | Limite de conexões pode ser atingido com muitas Edge Functions simultâneas |
| Ledger append-only crescente | ⚠️ Crescimento linear | Necessita particionamento ou archiving a longo prazo |

### Avaliação: ⚠️ Escalável com Atenção

O banco está bem indexado e usa padrões corretos (paginação, LATERAL JOIN, trgm). Os riscos de escala são conhecidos e mitigáveis (particionamento de ledger, otimização de RLS policies).

---

## 2. Escalabilidade das Edge Functions

### 2.1 Características

- **Stateless:** Todas as 59 Edge Functions são stateless — cada invocação é independente.
- **Deno Deploy:** Execução na edge, próximo ao usuário, com cold start baixo.
- **Infraestrutura compartilhada (`shared/`):** Código reutilizado entre funções reduz duplicação.

### 2.2 Processamento de Webhooks

- **Queue-based:** Webhooks Strava são processados via fila, desacoplando recebimento de processamento.
- **Idempotência:** Reprocessamento seguro sem efeitos duplicados.
- **Escalabilidade horizontal:** Novas instâncias de consumers podem ser adicionadas sem alteração de código.

### 2.3 Limitações

| Fator | Status | Impacto em Escala |
|-------|--------|------------------|
| `asaas-webhook` isolado | ⚠️ Não usa shared | Manutenção independente, possível divergência |
| Mixed Deno imports | ⚠️ Versões variadas | Risco de incompatibilidade em atualizações |
| Anti-cheat duplicado | ⚠️ Dois locais | Overhead de manutenção, risco de divergência |

### Avaliação: ✅ Escalável

Edge Functions stateless com processamento queue-based são nativamente escaláveis. O padrão é correto para crescimento.

---

## 3. Escalabilidade do App

### 3.1 Offline-First com Isar v3

- **Redução de carga no servidor:** Leituras são servidas localmente; apenas escritas e sincronizações tocam o backend.
- **Tolerância a picos:** Mesmo com backend sobrecarregado, o app funciona para leitura de dados em cache.
- **Sincronização inteligente:** Apenas deltas são sincronizados (não datasets completos).

### 3.2 Impacto da Estratégia Offline-First na Escala

```
Sem offline-first:     Cada ação do usuário = 1+ request ao servidor
Com offline-first:     Maioria das leituras = local, apenas writes = server

Redução estimada de requests: 60-80% das leituras
```

### 3.3 Risco: Isar v3 EOL

- Isar v3 está arquivado/EOL com override de path local.
- **Impacto em escala:** Nenhum impacto direto na escalabilidade, mas risco de incompatibilidade com futuras versões de Flutter/Dart.
- **Mitigação:** Monitorar Isar v4 ou avaliar migração para Drift/ObjectBox.

### Avaliação: ✅ Escalável

A arquitetura offline-first é um multiplicador de escalabilidade. Cada dispositivo atua como cache distribuído, reduzindo significativamente a carga no servidor.

---

## 4. Escalabilidade do Portal

### 4.1 Server Components

- **Redução de JavaScript no cliente:** Server Components renderizam HTML no servidor, enviando zero JS para componentes estáticos.
- **Streaming:** Conteúdo é enviado progressivamente com Suspense boundaries.
- **40 loading skeletons:** Cada rota possui skeleton independente, permitindo carregamento parcial.

### 4.2 Deployment (Vercel)

- **Edge deployment:** Estático e Server Components executam na edge globalmente.
- **Auto-scaling:** Vercel escala automaticamente sob carga.
- **CDN integrado:** Assets estáticos servidos via CDN global.

### 4.3 Limitações

| Fator | Status | Impacto em Escala |
|-------|--------|------------------|
| `force-dynamic` generalizado | ⚠️ Maioria das páginas | Elimina cache estático; cada request re-renderiza no servidor |
| WebVitals só console | ⚠️ Sem telemetria | Impossível detectar degradação de performance em produção |
| Rate limiter in-memory | ⚠️ Stateful | Não funciona com múltiplas réplicas |

### 4.4 Impacto do `force-dynamic`

```
Com cache estático (padrão Next.js):
  Request → CDN hit → Resposta em ~50ms

Com force-dynamic (atual):
  Request → Server render → DB query → Resposta em ~200-500ms
```

A diferença é significativa em escala. Páginas que não mudam frequentemente (documentação, configurações) se beneficiariam de ISR (Incremental Static Regeneration).

### Avaliação: ⚠️ Escalável com Atenção

Server Components e Vercel fornecem base escalável. O `force-dynamic` generalizado é o principal limitante — migrar páginas estáveis para ISR reduziria carga no servidor e melhoraria latência.

---

## 5. Escalabilidade do Motor Financeiro

### 5.1 Operações Atômicas

- **RPCs transacionais:** Débito/crédito executam em transação SQL — atomicidade garantida pelo PostgreSQL.
- **CHECK constraints:** `balance >= 0` verificado pelo banco, sem race condition possível.
- **Ledger imutável:** Append-only permite write-heavy workload sem contention de locks em leitura.

### 5.2 Idempotência

- **Webhooks de pagamento:** Chave de idempotência impede processamento duplicado.
- **ON CONFLICT:** Upserts para operações que podem ser repetidas.

### 5.3 Escalabilidade de Write

```
Transação financeira típica:
  1. BEGIN
  2. INSERT ledger entry
  3. UPDATE wallet balance
  4. COMMIT

Custo: ~2-5ms por transação
Throughput estimado: 200-500 TPS por instância PostgreSQL
```

Para o volume esperado de assessorias de corrida, esse throughput é mais do que suficiente.

### 5.4 Limitações em Escala Extrema

- Sem `SELECT ... FOR UPDATE` explícito — sob concorrência extrema na mesma wallet, serialization failures podem ocorrer (PostgreSQL retorna erro, necessitando retry).
- Ledger sem particionamento — crescimento a longo prazo pode impactar queries de histórico.

### Avaliação: ✅ Escalável

O motor financeiro está corretamente implementado para o domínio. O throughput nativo do PostgreSQL excede em ordens de magnitude o volume esperado.

---

## 6. Gargalos Potenciais

### 6.1 Rate Limiter In-Memory

**Problema:** O rate limiter armazena contadores em memória do processo Node.js. Com múltiplas réplicas (Vercel, load balancer), cada réplica mantém contadores independentes.

**Impacto em escala:**
- 3 réplicas = rate limit efetivo 3x maior que o configurado.
- Um atacante pode distribuir requests entre réplicas.

**Solução:** Redis-based rate limiting (Upstash, com latência <1ms) ou Vercel/Cloudflare native rate limiting.

**Severidade:** 🔴 Alta — Deve ser resolvido antes de escala horizontal.

### 6.2 N+1 Queries

**Status:** Mitigado com LATERAL JOIN em queries identificadas.

**Risco residual:** Novas features podem introduzir N+1 inadvertidamente se não houver vigilância.

**Solução:** Query logging em desenvolvimento para detectar N+1 patterns; pg_stat_statements em produção.

**Severidade:** 🟢 Baixa — Já mitigado nos casos conhecidos.

### 6.3 RLS Auto-Referente

**Problema:** Políticas RLS que consultam a própria tabela para verificar permissão podem causar sequential scans quando a tabela cresce.

**Impacto em escala:**
- Tabela com 10K registros: imperceptível.
- Tabela com 1M registros: query de permissão pode levar segundos.

**Solução:** Desnormalizar a informação de permissão em colunas indexadas ou usar materialized views para caching de permissões.

**Severidade:** 🟡 Média — Impacto cresce com volume de dados.

### 6.4 Conexões de Banco

**Status:** Supabase usa PgBouncer como connection pooler.

**Risco:** 59 Edge Functions executando simultaneamente + queries do portal + conexões do app = potencial exaustão do pool.

**Solução:** Monitorar connection pool usage; considerar Supabase Pro para limites maiores.

**Severidade:** 🟡 Média — Depende do crescimento.

---

## 7. Cenário: 10.000 Assessorias

### 7.1 Premissas

| Métrica | Estimativa |
|---------|-----------|
| Assessorias | 10.000 |
| Alunos por assessoria (média) | 30 |
| Total de alunos | 300.000 |
| Sessões de treino/dia (alunos ativos 30%) | 90.000 |
| Webhooks Strava/dia | 90.000 |
| Cobranças/mês | 300.000 |
| Webhooks de pagamento/mês | 300.000 |

### 7.2 Processamento de Webhooks

```
Webhooks Strava: 90.000/dia = ~1/segundo (média)
Picos (6h-8h manhã): ~5-10/segundo
Queue-based processing: ✅ Adequado para esse volume
```

**Veredicto:** ✅ A fila absorve picos. 10/s está dentro do throughput de uma única Edge Function consumer.

### 7.3 Cron Jobs / Billing

```
Cobranças mensais: 300.000
Window de processamento: 24h (billing cycle)
Throughput necessário: ~3.5 cobranças/segundo
PostgreSQL throughput: 200-500 TPS
```

**Veredicto:** ✅ Confortável. O banco processa o billing inteiro em minutos, não horas.

### 7.4 Armazenamento

```
Dados GPS por sessão: ~200KB-1MB (depende da duração)
Sessões/dia: 90.000
Storage diário: ~18-90 GB
Storage mensal: ~540-2700 GB
Storage anual: ~6.5-32 TB
```

**Veredicto:** ⚠️ Necessita política de retenção. Dados GPS brutos devem ser processados (agregados) e os brutos arquivados em cold storage após período definido.

### 7.5 Banco de Dados

```
Registros de ledger/mês: 300.000+ (uma ou mais entradas por cobrança)
Crescimento anual: ~4M registros de ledger
Sessões de treino/mês: 2.7M
```

**Veredicto:** ⚠️ PostgreSQL suporta, mas necessita:
- Particionamento do ledger por período (range partitioning por mês/ano).
- Archiving de sessões antigas.
- Monitoring de table bloat e vacuum.

### 7.6 Conexões Simultâneas

```
Assessores ativos no portal (pico): ~2.000
Alunos com app aberto (pico): ~30.000
Edge Function connections (pico): ~100
Total connections necessárias: ~32.000 (maioria via PgBouncer pooling)
```

**Veredicto:** ⚠️ O offline-first do app reduz drasticamente connections reais (app lê local). Supabase Pro ou Enterprise pode ser necessário para o pool de conexões. O PgBouncer do Supabase suporta centenas de conexões ativas; milhares com pooling transacional.

---

## 8. Concerns de Crescimento de Dados

### 8.1 Migrações (131)

As 131 migrações não impactam performance em runtime — são executadas uma vez no deploy. As 11 migrações "fix" são debt histórico, não operacional.

**Recomendação para escala:** Considerar squash de migrações em um baseline quando o produto atingir estabilidade de schema, para acelerar setup de ambientes de desenvolvimento.

### 8.2 Crescimento do Ledger

| Período | Registros Estimados (10K assessorias) | Tamanho Estimado |
|---------|---------------------------------------|-----------------|
| 1 mês | 300K+ | ~100 MB |
| 1 ano | 4M+ | ~1.2 GB |
| 3 anos | 12M+ | ~3.6 GB |
| 5 anos | 20M+ | ~6 GB |

O PostgreSQL lida bem com tabelas de 20M+ registros com indexação adequada. Particionamento por período melhora performance de queries de range (ex: "extrato do mês").

### 8.3 Dados GPS no Storage

Sessões de corrida armazenam polylines/GPS data no Supabase Storage. Este é o maior vetor de crescimento em volume.

**Recomendações:**
- Política de retenção: Manter GPS raw por 6-12 meses, depois agregar e mover raw para cold storage.
- Compressão: Polylines podem ser comprimidas com Encoded Polyline Algorithm.
- Tiered storage: Dados recentes em hot storage, históricos em S3/GCS.

### 8.4 Suítes de Reconciliação

As suítes de reconciliação QA verificam invariantes financeiras. Com crescimento do ledger, o tempo de execução dessas suítes aumentará.

**Recomendação:** Executar reconciliação em janela de baixo tráfego e com LIMIT por período para manter tempo de execução constante.

---

## 9. Recomendações para Escalabilidade

### 9.1 Prioridade Alta (Antes de Escalar)

| # | Recomendação | Justificativa | Esforço |
|---|-------------|---------------|---------|
| 1 | **Migrar rate limiter para Redis** (Upstash) | Rate limiting in-memory não funciona com múltiplas réplicas | 1-2 dias |
| 2 | **Particionar ledger por período** | Manter performance de queries financeiras com crescimento | 2-3 dias |
| 3 | **Política de retenção de GPS data** | Storage é o maior custo de crescimento | 1-2 dias |
| 4 | **Monitorar connection pool** | Instrumentar PgBouncer usage para alertar antes de saturar | 1 dia |

### 9.2 Prioridade Média (Crescimento de 1K→10K assessorias)

| # | Recomendação | Justificativa | Esforço |
|---|-------------|---------------|---------|
| 5 | **Migrar páginas estáveis para ISR** | Reduzir carga de server render em páginas que mudam pouco | 3-5 dias |
| 6 | **Otimizar RLS auto-referente** | Prevenir degradação de queries de permissão | 2-3 dias |
| 7 | **WebVitals → telemetria real** | Detectar degradação de performance antes dos usuários | 1-2 dias |
| 8 | **Consolidar anti-cheat em módulo único** | Reduzir overhead de manutenção e risco de divergência | 1-2 dias |

### 9.3 Prioridade Baixa (10K+ assessorias)

| # | Recomendação | Justificativa | Esforço |
|---|-------------|---------------|---------|
| 9 | **Read replicas para queries analíticas** | Separar workload OLTP (operacional) de OLAP (dashboards) | Setup Supabase |
| 10 | **CDN para assets do portal** | Já fornecido pelo Vercel, mas validar cache headers | 1 dia |
| 11 | **Squash de migrações** | Acelerar setup de ambientes de desenvolvimento | 1 dia |
| 12 | **Worker dedicado para billing** | Desacoplar cron de billing das Edge Functions | 3-5 dias |

---

## Matriz Resumo de Escalabilidade

| Componente | Estado Atual | 1K Assessorias | 10K Assessorias | 100K Assessorias |
|-----------|-------------|----------------|-----------------|------------------|
| **Banco de dados** | ✅ Bom | ✅ Confortável | ⚠️ Requer particionamento | 🔴 Requer read replicas |
| **Edge Functions** | ✅ Bom | ✅ Confortável | ✅ Confortável | ⚠️ Monitorar limites Deno Deploy |
| **App (offline-first)** | ✅ Excelente | ✅ Reduz carga | ✅ Reduz carga | ✅ Reduz carga |
| **Portal** | ⚠️ force-dynamic | ✅ Aceitável | ⚠️ Requer ISR | 🔴 Requer otimização agressiva |
| **Motor financeiro** | ✅ Bom | ✅ Confortável | ✅ Confortável | ⚠️ Requer particionamento |
| **Storage (GPS)** | ⚠️ Sem retenção | ✅ Aceitável | ⚠️ Requer política | 🔴 Requer tiered storage |
| **Rate limiting** | 🔴 In-memory | 🔴 Não escala | 🔴 Não escala | 🔴 Não escala |

---

## Veredicto de Escalabilidade

O Omni Runner possui uma **arquitetura fundamentalmente escalável**. As escolhas de design — offline-first, Server Components, Edge Functions stateless, queue-based processing, RPCs atômicas — são padrões que escalam naturalmente.

Os gargalos identificados são **pontuais e remediáveis**:

1. **Rate limiter in-memory** é o único bloqueador real de escala horizontal — migração para Redis resolve em 1-2 dias.
2. **`force-dynamic` generalizado** desperdiça a capacidade de cache do Next.js — migração incremental para ISR.
3. **Crescimento de storage GPS** é o maior custo operacional a longo prazo — política de retenção necessária.

Para o cenário realista de **1.000-10.000 assessorias**, o sistema escala com ajustes mínimos. Para **100K+ assessorias**, seria necessário investimento em infraestrutura (read replicas, tiered storage, worker dedicado para billing), mas a arquitetura base suporta a evolução sem reescrita.

A estratégia offline-first do app é um diferencial de escalabilidade: cada smartphone é um nó de cache distribuído que reduz em 60-80% as leituras no servidor.
