# Auditoria de Robustez — Omni Runner

**Data:** 2026-03-06  
**Escopo:** App Flutter · Portal Next.js · Backend Supabase  
**Metodologia:** Avaliação de cenários adversos e mecanismos de defesa

---

## Escala de Avaliação

| Rating | Significado |
|--------|------------|
| ✅ **Robusto** | O sistema trata o cenário de forma adequada e resiliente |
| ⚠️ **Parcial** | Há tratamento, mas com lacunas ou limitações conhecidas |
| ❌ **Vulnerável** | O cenário não é tratado ou o tratamento é insuficiente |

---

## 1. Estados Vazios (Empty Data States)

**Cenário:** Usuário acessa telas/páginas sem nenhum registro (primeiro acesso, conta nova, sem treinos, sem alunos).

### Como o sistema trata

**App Flutter:**
- Cards de estado vazio orientam o usuário com call-to-action ("Crie seu primeiro treino", etc.).
- Fluxo "Primeiros Passos" guia novos usuários.
- BLoCs emitem estados específicos (`EmptyState`) que a UI consome para renderizar layouts apropriados.

**Portal Next.js:**
- Empty states com ilustrações e textos orientadores nas listas.
- Banners de tutorial contextual por seção.
- 40 arquivos `loading.tsx` garantem que não há flash de conteúdo vazio durante carregamento.

**Backend:**
- RPCs retornam arrays vazios (não null) para listas sem dados.
- Não há risco de crash por retorno inesperado.

### Avaliação: ✅ Robusto

O tratamento de estados vazios é consistente e orientado ao usuário. A combinação de empty states educativos e loading skeletons previne confusão.

---

## 2. Perda de Rede (Network Loss)

**Cenário:** Dispositivo perde conectividade durante uso ativo, envio de dados ou sessão de treino.

### Como o sistema trata

**App Flutter — Offline-first com Isar v3:**
- Isar v3 armazena dados localmente como fonte primária.
- Leitura de dados funciona sem rede.
- Escritas são enfileiradas localmente e sincronizadas quando a conexão retorna.
- Sessões de corrida continuam gravando dados GPS localmente.
- Hierarquia de falhas seladas (`NetworkFailure`) permite tratamento granular.

**Portal Next.js:**
- Error boundaries em cada nível de rota capturam falhas de fetch.
- Mensagens de erro amigáveis substituem a UI quebrada.
- Retry automático não é explícito em todas as rotas, mas o Server Component re-renderiza no próximo request.

**Backend:**
- Edge Functions são stateless — sem estado perdido por desconexão do servidor.
- Webhooks com idempotência permitem reprocessamento seguro.

### Avaliação: ✅ Robusto

A estratégia offline-first do app é o ponto mais forte. O portal é resiliente via error boundaries, embora pudesse se beneficiar de indicadores de status de conexão.

---

## 3. Respostas Lentas (Slow Responses)

**Cenário:** Backend ou APIs externas demoram para responder (latência alta, timeout).

### Como o sistema trata

**App Flutter:**
- 31 BLoCs emitem `LoadingState` consumido pela UI para exibir indicadores de carregamento.
- A camada de dados configura timeouts nas chamadas HTTP.
- Isar fornece dados em cache para UX responsiva enquanto a rede é lenta.

**Portal Next.js:**
- 40 arquivos `loading.tsx` com skeletons cobrindo cada rota.
- Server Components streamam conteúdo progressivamente.
- Páginas `force-dynamic` re-fetching a cada request pode amplificar o impacto de APIs lentas (sem cache intermediário).

**Backend:**
- Edge Functions possuem timeout nativo do Deno Deploy (limite de execução).
- Processamento de webhooks via fila desacopla latência do producer (webhook sender) do consumer (processamento).

### Avaliação: ✅ Robusto

A cobertura de loading states é excepcional (40 skeletons). O offline-first do app mitiga impacto de latência para o usuário final. Ponto de atenção: `force-dynamic` sem cache pode transformar APIs lentas em UX lenta no portal.

---

## 4. Ações Duplicadas (Duplicate Actions)

**Cenário:** Webhook enviado duas vezes, usuário clica "pagar" duas vezes, requisição duplicada por retry de rede.

### Como o sistema trata

**Webhooks:**
- Processamento idempotente com chaves de idempotência.
- Upsert com `ON CONFLICT` para operações que podem ser repetidas.
- Fila de processamento para webhooks Strava evita processamento paralelo do mesmo evento.

**Operações financeiras:**
- RPCs atômicas no banco (transações SQL) garantem atomicidade.
- `CHECK (balance >= 0)` impede saldo negativo mesmo em operações concorrentes.
- Ledger imutável (append-only) torna duplicações detectáveis.

**UI:**
- Botões de ação financeira devem desabilitar após clique (comportamento padrão dos componentes de loading).

### Avaliação: ✅ Robusto

A idempotência de webhooks e as RPCs atômicas são implementações sólidas. O ledger imutável adiciona uma camada de auditabilidade para detectar anomalias.

---

## 5. Violações de Permissão (Permission Violations)

**Cenário:** Usuário tenta acessar dados de outro usuário, aluno tenta ações de assessor, API route chamada sem autenticação.

### Como o sistema trata

**Backend — RLS:**
- Todas as tabelas possuem políticas RLS ativas.
- Políticas garantem que `auth.uid()` corresponda ao dono do registro.
- Testes de penetração RLS automatizados verificam que um usuário não consegue ler/escrever dados de outro.

**Portal — Middleware:**
- Autenticação verificada em middleware antes de atingir API routes.
- Role checks (assessor, aluno, admin) em rotas protegidas.
- CSRF protection em mutações.

**App — Autenticação:**
- Token de sessão Supabase gerenciado pelo GoTrue client.
- Expiração e refresh automáticos.

**Edge Functions:**
- Verificação de JWT em cada chamada.
- Funções SECURITY DEFINER operam com permissões elevadas apenas dentro de escopo controlado, com `search_path` fixo.

### Avaliação: ✅ Robusto

A defesa em profundidade (RLS + middleware + JWT + testes de penetração) é exemplar. Os testes de penetração RLS automatizados são um diferencial significativo que valida continuamente a integridade das políticas.

---

## 6. Operações Concorrentes (Race Conditions)

**Cenário:** Dois assessores tentam formar parceria com o mesmo aluno; duas transações debitam a mesma wallet simultaneamente; múltiplos webhooks do mesmo evento chegam em paralelo.

### Como o sistema trata

**Parcerias:**
- Constraints UNIQUE no banco impedem parcerias duplicadas.
- `ON CONFLICT` permite tratamento gracioso de tentativas concorrentes.

**Wallet/Financeiro:**
- RPCs executam em transações SQL com isolamento adequado.
- `CHECK (balance >= 0)` como constraint de banco é a última barreira — mesmo com race conditions, o saldo nunca fica negativo.
- Ledger imutável append-only torna toda operação rastreável.

**Webhooks:**
- Processamento via fila serializa o processamento de eventos Strava.
- Chaves de idempotência previnem efeitos duplicados.

**Concerns residuais:**
- Sem `SELECT ... FOR UPDATE` explícito documentado — dependência nos constraints pode ser suficiente para o volume atual, mas pode gerar retries sob carga alta.

### Avaliação: ⚠️ Parcial

As proteções de banco (constraints, transações, checks) são sólidas. O processamento via fila resolve webhooks. Porém, a ausência de locking explícito (`FOR UPDATE`) em operações de wallet pode causar serialization failures sob concorrência extrema, exigindo retry logic no caller.

---

## 7. Input Inválido (Invalid Input)

**Cenário:** Dados malformados, valores fora do range esperado, tipos errados, tentativa de SQL injection.

### Como o sistema trata

**Portal — Zod:**
- Todas as API routes validam input com schemas Zod.
- Erros de validação retornam 400 com mensagens estruturadas.
- Tipos TypeScript inferidos dos schemas garantem consistência compile-time.

**App — Sealed Failures:**
- Hierarquia selada de falhas tipada (`ValidationFailure`, `FormatFailure`).
- Validação client-side antes do envio.
- `ErrorMessages.humanize()` traduz falhas técnicas em mensagens legíveis.

**Backend — CHECK Constraints:**
- `CHECK (balance >= 0)` em tabelas financeiras.
- Constraints NOT NULL, UNIQUE e FOREIGN KEY em todo o schema.
- Funções RPC validam parâmetros antes de operar.

**SQL Injection:**
- Supabase client usa queries parametrizadas.
- RPC calls são chamadas a funções, não SQL cru.
- SECURITY DEFINER com search_path fixo previne manipulação de path.

### Avaliação: ✅ Robusto

A validação multi-camada (Zod no portal, sealed failures no app, constraints no banco) cria defesa em profundidade contra input inválido. A parametrização nativa do Supabase client elimina SQL injection na prática.

---

## 8. Falhas de Bootstrap (Bootstrap Failures)

**Cenário:** App inicia com banco local corrompido, sem acesso à rede, serviço de analytics indisponível, Sentry fora do ar.

### Como o sistema trata

**App Flutter:**
- Cada módulo de inicialização está envolvido em try/catch individual.
- Falha de um módulo (ex: analytics, Sentry) não impede o start do app.
- Isar inicializa localmente sem necessidade de rede.
- O app degrada graciosamente: funcionalidades dependentes do módulo falhado ficam indisponíveis, mas o core funciona.

**Portal Next.js:**
- Build-time: dependências verificadas durante deploy.
- Runtime: Server Components falham individualmente (error boundaries).
- Sem processo de bootstrap complexo — cada request é independente.

**Backend:**
- Edge Functions são stateless — sem bootstrap persistente.
- Migrações são aplicadas via CLI/CD, não em runtime.

### Avaliação: ✅ Robusto

A estratégia de try/catch individual por módulo de inicialização no app é uma implementação exemplar de resiliência. Cada componente falha de forma isolada sem derrubar o sistema.

---

## 9. Segurança Financeira (Financial Safety)

**Cenário:** Tentativa de saque maior que saldo, cobrança duplicada, manipulação de valores, perda de registro de transação.

### Como o sistema trata

**Constraint de Saldo:**
- `CHECK (balance >= 0)` em nível de banco — impossível violar mesmo com bypass de aplicação.
- Constraint é atômica e verificada pelo PostgreSQL em cada operação.

**Ledger Imutável:**
- Todas as movimentações financeiras são registradas em ledger append-only.
- Não há UPDATE/DELETE em registros de transação — apenas INSERT.
- Permite auditoria completa e reconciliação.

**RPCs Atômicas:**
- Operações financeiras (transferência, cobrança, saque) executam em transações SQL.
- Débito e crédito acontecem atomicamente — não há estado intermediário observável.

**Invariantes de Custódia:**
- Suítes de reconciliação QA verificam que soma dos saldos = soma do ledger.
- Testes automatizados validam invariantes financeiras.

**Webhooks de Pagamento:**
- Idempotência impede crédito duplicado por webhook repetido.
- HMAC valida autenticidade do webhook recebido.

### Avaliação: ✅ Robusto

A implementação financeira é a área mais robusta do sistema. A combinação de constraints de banco (impossíveis de violar via aplicação), ledger imutável (auditabilidade completa), RPCs atômicas (sem estados intermediários) e testes de reconciliação (validação contínua) forma uma defesa em profundidade exemplar.

---

## Matriz Resumo de Robustez

| # | Cenário | Rating | Confiança |
|---|---------|--------|-----------|
| 1 | Estados vazios | ✅ Robusto | Alta |
| 2 | Perda de rede | ✅ Robusto | Alta |
| 3 | Respostas lentas | ✅ Robusto | Alta |
| 4 | Ações duplicadas | ✅ Robusto | Alta |
| 5 | Violações de permissão | ✅ Robusto | Alta |
| 6 | Operações concorrentes | ⚠️ Parcial | Média |
| 7 | Input inválido | ✅ Robusto | Alta |
| 8 | Falhas de bootstrap | ✅ Robusto | Alta |
| 9 | Segurança financeira | ✅ Robusto | Alta |

---

## Veredicto de Robustez

O Omni Runner demonstra robustez **acima da média** em 8 de 9 cenários avaliados. O único cenário com tratamento parcial (operações concorrentes) é mitigado por constraints de banco que impedem estados inválidos, faltando apenas locking explícito para evitar serialization failures sob carga extrema.

**Destaques positivos:**
- Bootstrap fault-tolerant com degradação graciosa.
- Segurança financeira com múltiplas camadas independentes de proteção.
- Offline-first genuíno (não apenas cache).
- Idempotência de webhooks com fila de processamento.

**Recomendações prioritárias:**
1. Adicionar `SELECT ... FOR UPDATE` nas RPCs financeiras para lock pessimista sob concorrência.
2. Implementar retry logic com backoff exponencial no caller de RPCs que podem sofrer serialization failure.
3. Adicionar indicador de status de conexão no portal para melhorar UX em cenários de rede instável.
