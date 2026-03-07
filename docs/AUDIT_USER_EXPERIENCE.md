# Auditoria de Experiência do Usuário — Omni Runner

**Data:** 2026-03-06
**Método:** Simulação de primeiro contato baseada na análise estrutural do código, telas, componentes, loading states, design tokens e fluxos implementados.
**Classificação:** Documento de auditoria profissional

---

## 1. Primeira Abertura — App Mobile (Flutter)

### 1.1 Simulação do Primeiro Contato

O atleta instala o app pela loja (App Store / Google Play) e abre pela primeira vez.

**O que o usuário encontra:**

| Etapa | Experiência Esperada | Avaliação |
|-------|---------------------|-----------|
| Splash / Loading | Design system com suporte a light/dark mode sugere splash polida | ✅ Positivo |
| Tela de login | Autenticação via Supabase Auth (email + social login) | ✅ Padrão |
| Onboarding | Existência de tutorial banners indica orientação inicial | ✅ Positivo |
| Home | Com 99 telas registradas, há profundidade — mas pode sobrecarregar no primeiro contato | ⚠️ Atenção |
| Conexão Strava | OAuth flow para vincular conta — passo crítico que gera valor imediato | ✅ Claro |
| Permissões | GPS, Bluetooth (wearables), notificações — múltiplos pedidos de permissão na primeira sessão | ⚠️ Atenção |

### 1.2 Impressão Geral do Primeiro Contato (App)

**Pontos positivos:**
- Design system consistente com light/dark mode transmite profissionalismo
- Tutorial banners foram adicionados para guiar o usuário
- Integração Strava no onboarding fornece dados imediatos
- Gamificação (OmniCoins, XP, badges) cria curiosidade e motivação

**Pontos de atrito:**
- 99 telas representam um universo complexo para um novo usuário navegar
- Múltiplas permissões solicitadas (GPS, BLE, notificações) podem causar fadiga
- Conceitos como OmniCoins, XP, ligas e desafios precisam ser explicados gradualmente

---

## 2. Primeira Abertura — Portal Web (Next.js)

### 2.1 Simulação do Primeiro Contato

O coach acessa o portal pela primeira vez para configurar sua assessoria.

**O que o usuário encontra:**

| Etapa | Experiência Esperada | Avaliação |
|-------|---------------------|-----------|
| Login | Autenticação Supabase, redirecionamento para portal da assessoria | ✅ Padrão |
| Dashboard inicial | Server Components com streaming — carregamento progressivo com skeletons | ✅ Excelente |
| Loading states | 40 arquivos `loading.tsx` — praticamente toda rota tem skeleton dedicado | ✅ Excelente |
| Navegação | 30+ rotas de assessoria organizadas — menu lateral/superior provável | ✅ Estruturado |
| Branding | Customização visual disponível — coach vê identidade da sua assessoria | ✅ Diferencial |
| Configuração financeira | Integração Asaas — passo técnico que pode gerar fricção | ⚠️ Atenção |

### 2.2 Impressão Geral do Primeiro Contato (Portal)

**Pontos positivos:**
- Loading skeletons em 40 rotas criam percepção de velocidade e polimento
- Server Components para páginas data-heavy garantem carregamento eficiente
- Design system com CSS custom properties mantém consistência
- Multi-tenancy com branding dá sensação de "meu portal"

**Pontos de atrito:**
- 30+ rotas exigem navegação bem organizada para não sobrecarregar
- Configuração de billing (Asaas) é passo técnico que exige orientação clara
- Conceitos financeiros (Saldo OmniCoins, Transferências OmniCoins) podem confundir sem contexto

---

## 3. Navegação e Clareza

### 3.1 Estrutura de Navegação do App

| Aspecto | Avaliação | Detalhe |
|---------|-----------|---------|
| **Volume de telas** | ⚠️ Alto | 99 telas é um número substancial — requer hierarquia clara |
| **Tipo de navegação** | ⚠️ Imperativa | Navigator 1.0 — funcional mas limitado para deep links e state restoration |
| **Organização** | ✅ Clean Architecture | Features organizadas em módulos separados |
| **Consistência** | ✅ Design system | Componentes reutilizáveis garantem padrão visual |

**Risco de navegação:**
Com navegação imperativa e 99 telas, o usuário pode se perder em fluxos profundos sem caminho claro de retorno. A ausência de navegação declarativa (GoRouter/auto_route) dificulta:
- Deep links a partir de notificações push
- Restauração de estado após o app ser fechado pelo sistema
- Compartilhamento de telas específicas via URL

### 3.2 Estrutura de Navegação do Portal

| Aspecto | Avaliação | Detalhe |
|---------|-----------|---------|
| **Organização de rotas** | ✅ Boa | App Router do Next.js 14 com estrutura hierárquica |
| **Rotas de assessoria** | ✅ 30+ | Cobertura ampla de funcionalidades |
| **Rotas admin** | ✅ 11+ | Painel administrativo separado |
| **API Routes** | ✅ 40+ | Backend-for-frontend bem estruturado |
| **Skeletons** | ✅ 40 | Loading states dedicados para quase toda rota |

---

## 4. Pontos de Confusão

### 4.1 Jargão Técnico (Recentemente Corrigido)

Um problema significativo de UX foi identificado e **já corrigido** com renomeações recentes:

| Label Anterior | Label Atual | Impacto da Correção |
|---------------|-------------|-------------------|
| **Custódia** | **Saldo OmniCoins** | Linguagem financeira técnica → linguagem do dia a dia |
| **Compensações** | **Transferências OmniCoins** | Jargão contábil → ação compreensível |
| Outros labels técnicos | Versões humanizadas | Redução de carga cognitiva |

**Análise:** A renomeação demonstra consciência de produto — a equipe percebeu que terminologia interna/técnica estava vazando para a interface do usuário. A correção para linguagem humana é um sinal positivo de maturidade de UX.

### 4.2 Complexidade Conceitual

| Conceito | Nível de Confusão | Mitigação Necessária |
|----------|-------------------|---------------------|
| **OmniCoins** | Médio | O que são? Como ganho? Para que servem? Precisa de explicação no onboarding |
| **Desafios vs Campeonatos vs Ligas** | Alto | Três sistemas de competição distintos — diferenciação precisa ser clara |
| **Entry Fee** | Médio | Pagar para participar de um desafio pode causar estranheza sem contexto |
| **Clearing/Settlement** | Baixo (admin) | Relevante apenas para admins, mas conceitos financeiros avançados |
| **Assessoria** | Baixo (mercado BR) | Termo familiar no mercado brasileiro, pode confundir internacionalmente |
| **Parcerias** | Baixo | Fluxo de convite entre assessorias é relativamente intuitivo |

### 4.3 Dependência de Isar v3 (Impacto UX)

Embora seja primariamente um problema técnico, o Isar v3 EOL pode impactar a UX:
- Bugs no armazenamento local sem correção upstream
- Possível corrupção de dados offline em versões futuras do Flutter/OS
- Risco de crashes inexplicáveis para o usuário

---

## 5. Pontos de Clareza

### 5.1 Tutorial Banners

A adição de banners tutoriais é um sinal positivo de design orientado ao usuário:

| Aspecto | Avaliação |
|---------|-----------|
| **Presença** | ✅ Implementados em pontos estratégicos |
| **Função** | Orientar o usuário em features complexas |
| **Impacto** | Reduz fricção no primeiro contato com features novas |
| **Recomendação** | Garantir que sejam dismissíveis e não reapareçam após lidos |

### 5.2 Labels Humanizados

A recente renomeação de labels demonstra cuidado com a experiência:

- **"Saldo OmniCoins"** é imediatamente compreensível — o usuário sabe que é seu saldo
- **"Transferências OmniCoins"** comunica movimento de valor — linguagem bancária familiar
- Labels de ação claros reduzem a necessidade de documentação de suporte

### 5.3 Design System Consistente

| Token / Feature | Impacto UX |
|----------------|-----------|
| **CSS Custom Properties** | Consistência visual em todo o portal |
| **17 componentes UI** | Biblioteca reutilizável garante padrões |
| **Light/Dark mode** | Respeita preferência do sistema do usuário |
| **Design tokens** | Cores, espaçamentos e tipografia padronizados |

---

## 6. Avaliação do Fluxo de Onboarding

### 6.1 Onboarding do Atleta (App)

```
Instalar → Criar conta → [Tutorial banners] → Conectar Strava
    → Solicitar permissões (GPS, BLE, Push)
    → Vincular-se a assessoria → Ver dashboard
    → Primeira corrida → Ganhar XP/OmniCoins → "Aha moment"
```

| Etapa | Qualidade | Notas |
|-------|-----------|-------|
| Criação de conta | ✅ Boa | Supabase Auth com opções social login |
| Tutorial inicial | ✅ Boa | Banners tutoriais adicionados |
| Conexão Strava | ✅ Boa | OAuth padrão, mas pode falhar silenciosamente |
| Permissões | ⚠️ Média | Múltiplas permissões em sequência — risco de negação |
| Vínculo à assessoria | ⚠️ Média | Depende de convite/código — pode ter fricção |
| "Aha moment" | ✅ Boa | Primeira corrida → OmniCoins = valor tangível |

**Tempo estimado até o "Aha moment":** 15-30 minutos (instalar → configurar → primeira corrida curta → ver recompensas)

### 6.2 Onboarding da Assessoria (Portal)

```
Criar conta → Solicitar aprovação → [Aguardar] → Aprovada
    → Configurar branding → Configurar Asaas
    → Criar primeiro plano → Convidar atletas
    → Criar primeiro treino → Primeira cobrança
```

| Etapa | Qualidade | Notas |
|-------|-----------|-------|
| Criação de conta | ✅ Boa | Cadastro padrão |
| Aprovação | ⚠️ Média | Processo manual pelo admin — introduz latência |
| Configuração branding | ✅ Boa | Personalização visual engaja o coach |
| Configuração Asaas | ⚠️ Baixa | Setup técnico de gateway — precisa de orientação passo a passo |
| Primeiro plano | ✅ Boa | Criar plano de assinatura é relativamente direto |
| Convidar atletas | ✅ Boa | Fluxo de convite implementado |
| Primeiro treino | ✅ Boa | Workout builder com blocos é intuitivo |

**Tempo estimado até produtividade:** 1-3 dias (inclui aprovação manual e configuração financeira)

---

## 7. Consistência Visual

### 7.1 App Mobile

| Aspecto | Avaliação | Detalhe |
|---------|-----------|---------|
| **Design System** | ✅ Presente | Sistema de design próprio para Flutter |
| **Light/Dark Mode** | ✅ Suportado | Adapta-se à preferência do sistema |
| **Componentes** | ✅ Reutilizáveis | Biblioteca de componentes padronizada |
| **Consistência entre telas** | ⚠️ Parcial | 99 telas — probabilidade de inconsistências visuais menores |
| **Ícones e ilustrações** | ✅ Padronizados | Gamificação (badges, XP) com identidade visual |

### 7.2 Portal Web

| Aspecto | Avaliação | Detalhe |
|---------|-----------|---------|
| **CSS Custom Properties** | ✅ Presente | Tokens de design centralizados |
| **Componentes UI** | ✅ 17 componentes | Biblioteca coesa |
| **Loading Skeletons** | ✅ 40 arquivos | Cobertura quase completa |
| **Responsividade** | ✅ Esperada | Next.js + CSS custom properties permitem |
| **Consistência cross-feature** | ✅ Boa | Design system enforça padrões |

### 7.3 Consistência App ↔ Portal

| Aspecto | Avaliação |
|---------|-----------|
| **Linguagem visual** | ⚠️ Parcial — são plataformas distintas (Flutter vs Next.js) com design systems separados |
| **Linguagem verbal** | ✅ Melhorada — renomeações recentes alinham terminologia entre plataformas |
| **Modelo mental** | ✅ Consistente — mesmos conceitos (OmniCoins, desafios, treinos) em ambas |

---

## 8. Qualidade de Mensagens de Erro

### 8.1 App Mobile

| Aspecto | Avaliação | Detalhe |
|---------|-----------|---------|
| **Sentry integrado** | ✅ Positivo | Erros são capturados e rastreados automaticamente |
| **Session replays** | ✅ Positivo | Equipe pode reproduzir a experiência do usuário no momento do erro |
| **Offline errors** | ⚠️ Atenção | Com Isar v3 EOL, erros de armazenamento podem gerar mensagens confusas |
| **Erros de GPS** | ⚠️ Atenção | Anti-cheat pode rejeitar corridas legítimas — mensagem precisa ser empática |
| **Erros de conexão** | ✅ Mitigado | Offline-first absorve falhas de rede transparentemente |

### 8.2 Portal Web

| Aspecto | Avaliação | Detalhe |
|---------|-----------|---------|
| **Error boundaries** | ✅ Esperado | Next.js 14 App Router tem `error.tsx` nativo |
| **Validação de forms** | ✅ Esperado | Server Actions validam input server-side |
| **Rate limiting** | ⚠️ Atenção | Usuário pode receber erro 429 sem entender o motivo |
| **Erros de billing** | ⚠️ Atenção | Falhas de pagamento Asaas precisam de mensagens claras e ações sugeridas |
| **CSRF errors** | ⚠️ Atenção | Token expirado pode gerar erro opaco para o usuário |

---

## 9. Qualidade de Loading States

### 9.1 Portal — Excelência em Loading States

A presença de **40 arquivos `loading.tsx`** é um indicador excepcional de qualidade de UX:

| Aspecto | Avaliação |
|---------|-----------|
| **Cobertura** | ✅ Excelente — quase todas as rotas têm skeleton dedicado |
| **Implementação** | ✅ Next.js Suspense — streaming nativo com fallback |
| **Personalização** | ✅ Skeletons específicos por rota (não genéricos) |
| **Percepção de velocidade** | ✅ Usuário vê estrutura imediata, conteúdo preenche progressivamente |
| **CLS (Cumulative Layout Shift)** | ✅ Skeletons previnem shifts de layout |

**Análise:** 40 loading.tsx para 30+ rotas de assessoria + 11+ rotas admin significa cobertura quase total. Isso é raro e demonstra preocupação genuína com a percepção de performance. O uso de Server Components com streaming complementa perfeitamente.

### 9.2 App — Loading States

| Aspecto | Avaliação | Detalhe |
|---------|-----------|---------|
| **Offline-first** | ✅ Bom | Dados locais do Isar são exibidos imediatamente |
| **Sync indicators** | ⚠️ Importante | Usuário precisa saber se dados são locais ou atualizados |
| **GPS acquisition** | ⚠️ Atenção | Aquisição de sinal GPS pode demorar — precisa de feedback claro |
| **BLE connection** | ⚠️ Atenção | Pareamento Bluetooth pode ser lento — estado de conexão visível |

---

## 10. Considerações de Acessibilidade

### 10.1 App Mobile (Flutter)

| Aspecto | Avaliação | Recomendação |
|---------|-----------|-------------|
| **Semântica** | ⚠️ A verificar | Flutter requer `Semantics` widgets explícitos para screen readers |
| **Contraste** | ✅ Provável | Design system com dark mode sugere tokens de contraste definidos |
| **Tamanho de texto** | ⚠️ A verificar | Suporte a Dynamic Type / font scaling |
| **Touch targets** | ⚠️ A verificar | Mínimo de 48x48dp recomendado |
| **Screen reader** | ⚠️ A verificar | TalkBack (Android) / VoiceOver (iOS) precisam de labels explícitos |
| **Movimento** | ⚠️ A verificar | Animações devem respeitar `Reduce Motion` do sistema |

### 10.2 Portal Web (Next.js)

| Aspecto | Avaliação | Recomendação |
|---------|-----------|-------------|
| **HTML semântico** | ✅ Esperado | Server Components renderizam HTML semântico |
| **ARIA labels** | ⚠️ A verificar | 17 componentes UI precisam de ARIA adequado |
| **Navegação por teclado** | ⚠️ A verificar | 30+ rotas devem ser navegáveis sem mouse |
| **Contraste** | ✅ Provável | CSS custom properties centralizam cores |
| **Skip links** | ⚠️ A verificar | Navegação direta ao conteúdo principal |
| **Alt text** | ⚠️ A verificar | Imagens de badges, avatares, branding |
| **Focus management** | ⚠️ A verificar | Server Actions devem gerenciar foco após submit |

### 10.3 Avaliação Geral de Acessibilidade

**Nível estimado:** Parcial — o design system fornece base sólida (tokens de cor, componentes reutilizáveis), mas não há evidência de testes específicos de acessibilidade (nenhum arquivo de teste a11y identificado). Recomendação: auditoria WCAG 2.1 AA dedicada.

---

## 11. Resumo de Descobertas

### Pontos Fortes de UX

| # | Ponto Forte | Impacto |
|---|-------------|---------|
| 1 | **40 loading.tsx com skeletons** | Percepção de velocidade excepcional no portal |
| 2 | **Renomeação de labels técnicos** | Linguagem humanizada reduz confusão |
| 3 | **Tutorial banners** | Orientação contextual para features complexas |
| 4 | **Design system com dark mode** | Consistência visual e respeito à preferência do usuário |
| 5 | **Offline-first** | Experiência resiliente durante corridas sem sinal |
| 6 | **Branding customizável** | Cada assessoria tem identidade visual própria |
| 7 | **Sentry session replays** | Capacidade de diagnosticar problemas de UX em produção |

### Pontos Fracos de UX

| # | Ponto Fraco | Severidade | Recomendação |
|---|-------------|-----------|--------------|
| 1 | **99 telas com navegação imperativa** | Alta | Migrar para GoRouter, implementar hierarquia clara, deep links |
| 2 | **Complexidade conceitual** (OmniCoins + Desafios + Campeonatos + Ligas) | Média | Revelar progressivamente, não tudo no primeiro contato |
| 3 | **Múltiplas permissões no onboarding** | Média | Solicitar permissões contextualmente (GPS ao iniciar corrida, BLE ao conectar wearable) |
| 4 | **Onboarding de assessoria com aprovação manual** | Média | Adicionar status tracker visível, tempo estimado, notificação de aprovação |
| 5 | **Setup financeiro (Asaas)** | Média | Wizard passo a passo com validação em tempo real |
| 6 | **Acessibilidade não validada** | Média | Auditoria WCAG 2.1 AA, testes com screen readers |
| 7 | **Isar v3 EOL** | Alta | Migração planejada antes de impacto em UX |
| 8 | **Screens que bypasam BLoC** | Baixa | Pode causar inconsistências de estado visíveis ao usuário |

---

## 12. Recomendações Priorizadas

### Curto Prazo (Quick Wins)
1. Solicitar permissões contextualmente em vez de na instalação
2. Adicionar wizard guiado para configuração financeira da assessoria
3. Criar glossário in-app para conceitos de gamificação (OmniCoins, XP, ligas)
4. Adicionar status tracker no processo de aprovação de assessoria

### Médio Prazo
5. Migrar navegação para GoRouter com suporte a deep links
6. Implementar revelação progressiva de features (não mostrar tudo de uma vez)
7. Conduzir auditoria de acessibilidade WCAG 2.1 AA
8. Adicionar testes de acessibilidade automatizados ao CI/CD

### Longo Prazo
9. Migrar Isar v3 para alternativa suportada
10. Considerar unificação de design system entre app e portal
11. Implementar analytics de UX (funis de conversão, drop-off points)
12. A/B testing de fluxos de onboarding

---

*Documento gerado como parte da auditoria profissional do produto Omni Runner.*
