# Auditoria de UX Detalhada — Omni Runner

**Data:** 2026-03-06  
**Escopo:** App Flutter · Portal Next.js  
**Perspectiva:** Avaliação da experiência do usuário final (assessor e aluno)

---

## 1. Clareza do Produto

**Pergunta:** Um novo usuário entende o que o Omni Runner é e faz ao abrir o app/portal pela primeira vez?

### App Flutter

- **Onboarding "Primeiros Passos":** Fluxo guiado para novos usuários com etapas progressivas.
- **Cards de estado vazio** com textos orientadores fornecem contexto por seção.
- A proposta de valor (plataforma para assessoria esportiva) fica clara após o onboarding.

**Limitação:** O nome "Omni Runner" sugere foco exclusivo em corrida. Se a plataforma atende outros esportes, pode haver dissonância de expectativa.

### Portal Next.js

- **Banners de tutorial** contextuais por seção explicam funcionalidades.
- **Sidebar organizada** por grupos funcionais (Alunos, Financeiro, Treinos, etc.).
- O portal assume que o usuário já conhece o produto (é o lado assessor), o que é razoável.

### Avaliação: ⚠️ Parcial

A clareza é boa para quem já decidiu usar. Falta uma proposta de valor imediata no primeiro contato (splash/hero section). O onboarding "Primeiros Passos" compensa parcialmente.

---

## 2. Facilidade de Navegação

### App Flutter

- **99 telas** com navegação imperativa (`Navigator.push`).
- Bottom tabs fornecem acesso rápido às seções principais.
- A navegação funciona, mas a abordagem imperativa gera limitações:
  - Deep links são frágeis e difíceis de manter.
  - Não há rota nomeada declarativa para referência.
  - O estado de navegação é procedural, dificultando analytics de fluxo.
- A quantidade de telas (99) é alta, mas com bottom tabs a estrutura principal fica acessível.

### Portal Next.js

- **Sidebar com grupos colapsáveis** organiza funcionalidades por domínio.
- Hierarquia de navegação clara: sidebar → lista → detalhe.
- Mobile sidebar toggle para responsividade.
- A renomeação recente de labels melhora a descobribilidade (ex: Webhook → Cobranças é mais claro para assessores).

### Avaliação: ⚠️ Parcial

O portal tem navegação bem organizada. O app funciona no dia-a-dia, mas a navegação imperativa em 99 telas é uma limitação técnica que impacta deep linking e manutenabilidade. Para o usuário final, a experiência é adequada via bottom tabs.

---

## 3. Consistência Visual

### Sistema de Design

- **Design tokens:** Sistema compartilhado entre app e portal garante consistência de cores, tipografia e espaçamentos.
- **Dark mode:** Implementado e hardcoded no portal. O app segue o tema definido.

### Consistência Inter-plataforma

| Aspecto | App | Portal | Consistente? |
|---------|-----|--------|-------------|
| Cores primárias | ✅ Design tokens | ✅ Design tokens | ✅ Sim |
| Tipografia | ✅ Design tokens | ✅ Design tokens | ✅ Sim |
| Espaçamentos | ✅ Design tokens | ✅ Design tokens | ✅ Sim |
| Dark mode | Segue sistema | Hardcoded dark | ⚠️ Parcial |
| Componentes | Material + custom | Custom components | ⚠️ Similar mas não idêntico |

### Limitação: Dark Mode Hardcoded

O portal opera exclusivamente em dark mode sem opção de toggle. Implicações:
- Usuários que preferem light mode não têm alternativa.
- Em ambientes com muita luz (uso outdoor), a legibilidade pode ser prejudicada.
- Para assessores que trabalham ao ar livre com alunos, isso é uma consideração prática.

### Avaliação: ⚠️ Parcial

A consistência visual é boa graças ao sistema de design tokens. A ausência de toggle de tema no portal e diferenças naturais entre plataformas (Flutter Material vs custom web components) impedem nota máxima.

---

## 4. Feedback ao Usuário

### Loading States

- **Portal:** 40 arquivos `loading.tsx` com skeletons — cobertura excepcional.
- **App:** BLoCs emitem `LoadingState` consumido por widgets de carregamento.
- Em nenhum momento o usuário fica diante de uma tela em branco sem indicação de carregamento.

### Mensagens de Erro

- **App:** `ErrorMessages.humanize()` converte hierarquias de falha seladas em mensagens legíveis.
- **Portal:** Error boundaries exibem UI de fallback em cada nível de rota.
- **API:** Respostas de erro estruturadas com mensagens descritivas.

### Notificações e Confirmações

- **Toast notifications** para ações bem-sucedidas e erros.
- **Confirmações em ações destrutivas** (ex: cancelar parceria, estornar valor).
- **Feedback imediato:** Loading spinners em botões de ação durante processamento.

### Avaliação: ✅ Bom

A cobertura de feedback é ampla. 40 loading skeletons é acima da média. A humanização de erros via sealed failures é uma solução elegante que garante que o usuário nunca vê stack traces ou códigos técnicos.

---

## 5. Qualidade das Mensagens de Erro

### Arquitetura de Mensagens

```
Camada de Domínio        →  Sealed Failure (tipado, técnico)
        ↓
ErrorMessages.humanize() →  Mensagem legível (português, contextual)
        ↓
UI (SnackBar/Dialog)     →  Exibição ao usuário
```

### Exemplos de Transformação

| Failure Técnico | Mensagem Humanizada |
|----------------|---------------------|
| `NetworkFailure.timeout` | "Sem conexão. Verifique sua internet e tente novamente." |
| `AuthFailure.expired` | "Sua sessão expirou. Faça login novamente." |
| `ValidationFailure.invalidEmail` | "E-mail inválido. Verifique o formato." |
| `BalanceFailure.insufficient` | "Saldo insuficiente para esta operação." |

### Pontos Fortes

- Mensagens em português, contextuais ao domínio.
- Sealed class garante que todo tipo de falha é tratado (exaustividade em compile-time).
- Separação entre falha técnica e mensagem ao usuário.

### Limitação

- Strings hardcoded em português em algumas partes do app, apesar de setup i18n existente. Isso não é problema para o mercado atual (Brasil), mas dificulta expansão futura.

### Avaliação: ✅ Bom

A abordagem de sealed failures → humanização é uma das melhores práticas do projeto. Garante cobertura exaustiva de cenários de erro.

---

## 6. Tutorial e Onboarding

### App Flutter

- **"Primeiros Passos":** Fluxo progressivo que guia novos usuários pelas funcionalidades básicas.
- **Cards de estado vazio:** Cada seção sem dados exibe orientação sobre como começar.
- **Contextual:** O onboarding é relevante ao ponto em que o usuário se encontra.

### Portal Next.js

- **Banners de tutorial:** Presentes em múltiplas seções do portal.
- **Orientação por seção:** Cada área principal possui texto explicativo para primeiro uso.
- **Labels descritivos:** A renomeação recente (Webhook → Cobranças, Custódia → Saldo OmniCoins) reduz curva de aprendizado.

### Limitação

- Não há tour interativo (tooltip sequencial apontando elementos da UI).
- Não há vídeos ou GIFs demonstrativos embarcados.
- Onboarding é passivo (texto) — não há tarefas guiadas com verificação.

### Avaliação: ⚠️ Parcial

O onboarding textual existe e é bem posicionado. Para uma plataforma B2B2C com público de assessores esportivos (não necessariamente tech-savvy), um onboarding mais interativo (tour guiado, vídeos) teria impacto significativo na ativação.

---

## 7. Qualidade dos Labels

### Renomeações Recentes

| Antes | Depois | Melhoria |
|-------|--------|----------|
| Webhook | Cobranças | ✅ Significativa — assessores entendem "cobranças" |
| Custódia | Saldo OmniCoins | ✅ Significativa — conceito de saldo é universal |
| Termos técnicos | Vocabulário de negócio | ✅ Alinhamento com mental model do usuário |

### Avaliação Atual

- **Portal:** Labels majoritariamente em vocabulário de negócio, acessível ao assessor.
- **App:** Mix de labels bem nomeados e termos genéricos.
- **Consistência:** O esforço de renomeação demonstra maturidade de produto e atenção ao usuário.

### Limitação

- Algumas strings hardcoded em português (fora do sistema i18n) dificultam governança centralizada de labels.

### Avaliação: ✅ Bom

As renomeações recentes são acertadas e demonstram sensibilidade ao vocabulário do público-alvo. O resultado é uma interface que fala a língua do assessor, não do desenvolvedor.

---

## 8. Arquitetura da Informação

### Portal — Sidebar

A sidebar organiza funcionalidades em grupos colapsáveis:

```
📊 Dashboard
👥 Alunos
   ├── Lista de Alunos
   ├── Parcerias
   └── ...
🏃 Treinos
   ├── Planilhas
   ├── Sessões
   └── ...
💰 Financeiro
   ├── Cobranças
   ├── Saldo OmniCoins
   ├── Extrato
   └── ...
⚙️ Configurações
```

### Avaliação da Hierarquia

- **Agrupamento lógico:** Funcionalidades relacionadas estão juntas.
- **Profundidade adequada:** No máximo 2 níveis (grupo → item).
- **Progressive disclosure:** Grupos colapsáveis ocultam complexidade.
- **Consistência:** Padrão lista → detalhe → ações em todas as seções.

### App — Navegação

- **Bottom tabs:** Acesso rápido às seções principais (Home, Treinos, Perfil, etc.).
- **Hierarquia interna:** Tab → lista → detalhe via `Navigator.push`.
- **99 telas:** Volume alto, mas bottom tabs mantêm a raiz acessível.

### Avaliação: ✅ Bom

A arquitetura da informação é bem estruturada em ambas as plataformas. A sidebar do portal com grupos colapsáveis é eficiente para o volume de funcionalidades. O app usa o padrão mobile convencional de bottom tabs + drill-down.

---

## 9. Acessibilidade

### Implementação Atual

- **Playwright a11y tests:** Testes automatizados de acessibilidade existem no portal.
- **Semantic HTML:** Uso de elementos semânticos no portal Next.js.
- **ARIA labels:** Presentes em componentes interativos.
- **Flutter Semantics:** Framework fornece semântica padrão para widgets Material.

### Limitações

| Aspecto | Status | Observação |
|---------|--------|------------|
| Screen readers | ⚠️ Parcial | Semântica padrão do Flutter/HTML semântico; não há testes manuais documentados |
| Contraste | ⚠️ Parcial | Dark mode hardcoded — bom contraste em geral, mas sem opção light |
| Tamanhos de fonte | ⚠️ Parcial | Responsivo, mas sem controle explícito de tamanho pelo usuário |
| Navegação por teclado | ⚠️ Parcial | Portal: elementos focáveis; App: depende de framework |
| Daltonismo | ❌ Ausente | Sem modo de alto contraste ou paletas alternativas |

### Avaliação: ⚠️ Parcial

A base de acessibilidade existe (semantic HTML, ARIA labels, Playwright a11y tests), o que coloca o produto acima da média do mercado fitness. Faltam ajustes para acessibilidade avançada (alto contraste, controle de fonte, testes manuais com screen readers).

---

## 10. Responsividade

### Portal Next.js

- **Mobile sidebar toggle:** Menu hambúrguer em viewports pequenos.
- **Grids responsivos:** Layouts adaptam colunas por breakpoint.
- **Tabelas:** Scroll horizontal em telas menores.
- **40 loading skeletons** adaptam layout ao viewport.

### App Flutter

- **Nativo mobile:** Projetado para mobile-first.
- **Tablets:** Flutter adapta layouts com MediaQuery, mas otimização específica para tablet não é documentada.
- **Orientação:** Suporte a portrait é o padrão; landscape não é prioridade declarada.

### Avaliação: ✅ Bom

O portal é responsivo com breakpoints adequados. O app é mobile-first por natureza. A combinação atende ao uso típico: assessor no portal (desktop/laptop), aluno no app (smartphone).

---

## Matriz Resumo de UX

| # | Dimensão | Rating | Prioridade de Melhoria |
|---|----------|--------|----------------------|
| 1 | Clareza do produto | ⚠️ Parcial | Média |
| 2 | Facilidade de navegação | ⚠️ Parcial | Média |
| 3 | Consistência visual | ⚠️ Parcial | Baixa |
| 4 | Feedback ao usuário | ✅ Bom | — |
| 5 | Qualidade das mensagens de erro | ✅ Bom | — |
| 6 | Tutorial/onboarding | ⚠️ Parcial | Alta |
| 7 | Qualidade dos labels | ✅ Bom | — |
| 8 | Arquitetura da informação | ✅ Bom | — |
| 9 | Acessibilidade | ⚠️ Parcial | Média |
| 10 | Responsividade | ✅ Bom | — |

---

## Veredicto de UX

O Omni Runner apresenta uma experiência de usuário **funcional e bem estruturada**, com destaques significativos em feedback (40 loading skeletons), tratamento de erros humanizados (sealed failures → mensagens legíveis) e arquitetura de informação (sidebar com grupos colapsáveis, bottom tabs).

As áreas com maior oportunidade de melhoria são:

1. **Onboarding interativo:** Migrar de texto passivo para tour guiado com tarefas verificáveis. Isso é crítico para ativação de assessores não tech-savvy.
2. **Toggle de tema:** Adicionar opção light/dark no portal para acessibilidade e preferência do usuário.
3. **Navegação declarativa no app:** Migrar de `Navigator.push` imperativo para GoRouter ou equivalente, habilitando deep links confiáveis e analytics de navegação.
4. **Proposta de valor no primeiro contato:** Hero section ou splash screen que comunique "O que é → Para quem → Por que usar" em 5 segundos.

O produto está em um estágio de maturidade que prioriza funcionalidade sobre polish — o que é adequado para a fase atual. As melhorias sugeridas são incrementais e não bloqueiam o uso produtivo.
