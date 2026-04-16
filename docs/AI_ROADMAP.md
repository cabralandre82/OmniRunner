# AI Roadmap — Omni Runner

Este documento registra as ideias de uso de IA identificadas em abril de 2026.
Os itens marcados como **implementado** já estão em produção.
Os demais estão documentados para avaliação e implementação futura.

---

## Implementados

### ✅ AI-01 — Parse de treino em linguagem natural (Training Plan)
**Onde:** Portal — Passagem de Treino (aba IA no workout picker drawer)  
**O que faz:** Coach digita `"4x1km em 4:30 com 2min de descanso"` e a IA retorna campos estruturados (tipo, label, descrição, notas, distância estimada).  
**Endpoint:** `POST /api/training-plan/ai/parse-workout`  
**Implementado em:** 2026-04-14

---

### ✅ AI-02 — Briefing do atleta no CRM
**Onde:** Portal — `/crm/[userId]`  
**O que faz:** Ao abrir o perfil de um atleta, um card lazy-loaded gera automaticamente um parágrafo de 2–4 frases resumindo os sinais mais relevantes do momento: aderência ao plano, RPE médio, dias inativo, alertas ativos, última nota do treinador. Retorna também um sinal semântico (`positive` / `attention` / `risk`) que colore o card.  
**Endpoint:** `POST /api/ai/athlete-briefing`  
**Arquivos:** `portal/src/app/api/ai/athlete-briefing/route.ts`, `portal/src/components/crm/athlete-briefing-card.tsx`  
**Implementado em:** 2026-04-14

---

### ✅ AI-03 — Comentário pós-corrida personalizado
**Onde:** App — `RunSummaryScreen`  
**O que faz:** Imediatamente após uma corrida, o app chama a edge function que busca as últimas 8 sessões do atleta, calcula a média histórica e pede à IA um comentário de 1–2 frases comparando a corrida atual com o histórico. Aparece como um card `✨` no painel de métricas. Falha silenciosamente — nunca quebra a tela de resumo.  
**Deploy:** Realizado manualmente via editor do Supabase Dashboard (versão standalone, sem imports relativos — lógica de CORS, autenticação e helpers inlined diretamente no arquivo). Rate limiting removido da versão de dashboard (dependia de módulo compartilhado `_shared/rate_limit.ts`). Versão completa com módulos compartilhados mantida em `supabase/functions/generate-run-comment/index.ts` para deploy via CLI (`supabase functions deploy generate-run-comment`).  
**Edge Function:** `generate-run-comment`  
**Arquivos:** `supabase/functions/generate-run-comment/index.ts`, `omni_runner/lib/presentation/screens/run_summary_screen.dart`  
**Implementado em:** 2026-04-14

---

## Roadmap futuro

### 🗂️ AI-04 — Narrativa semanal automática do grupo
**Onde:** Portal — Dashboard ou tela de relatório semanal  
**Valor:** Coaches que compartilham relatórios com donos de assessoria ou redes sociais precisam escrever um resumo toda semana. A IA poderia gerar isso automaticamente.

**O que geraria:**
> "Semana de 14 a 20 de abril: grupo acumulou 1.247km (+11% vs semana anterior) com 47 treinos registrados. Destaque para Maria Souza com 62km e 5 sessões. Atenção: 6 atletas sem atividade registrada — 3 deles com mais de 14 dias de inatividade. Semana de pré-prova para 2 atletas."

**Dados necessários:** `sessions` (grupo), `coaching_members`, `training_plans` (provas previstas via `ends_on`)  
**Esforço estimado:** Baixo — 1 API route + componente colapsável no dashboard  
**Prioridade:** Alta (impacto imediato, custo mínimo — 1 chamada/semana/grupo)

---

### 🗂️ AI-05 — Rascunho de mensagem para atleta em risco
**Onde:** Portal — `/risk` (tela de risco/churn)  
**Valor:** Coaches evitam entrar em contato com atletas em risco por falta de o que dizer. Um rascunho personalizado baseado nos dados do atleta aumenta a chance de reengajamento.

**O que geraria (exemplo para atleta 14 dias inativo com RPE histórico alto):**
> "Oi João! Sumiu faz um tempinho 😅 Tudo bem? Notei que seus últimos treinos foram bem puxados — às vezes o corpo pede uma pausa. Quando quiser voltar, me fala que ajustamos a carga."

**Dados necessários:** Status do atleta, dias inativo, RPE histórico, tags  
**Esforço estimado:** Baixo — reusar o padrão do `athlete-briefing`, adaptar prompt  
**Prioridade:** Alta

---

### 🗂️ AI-06 — Gerador de comunicado (Portal + App)
**Onde:** Portal — criação de anúncio / App — `AnnouncementCreateScreen`  
**Valor:** Coaches que não gostam de escrever procrastinam comunicados ou os escrevem com pouco impacto.

**Fluxo:** Coach digita a ideia em 1 frase → IA gera título + corpo formatado e motivador.

**Exemplo:**
- Input: `"lembrar da prova de domingo, 6h, trazer número de peito"`
- Output: Título: `"🏃 Prova de Domingo — Informações Importantes"` + corpo completo formatado

**Dados necessários:** Nenhum além do input do coach  
**Esforço estimado:** Muito baixo — idêntico ao parse-workout, sem DB  
**Prioridade:** Média

---

### 🗂️ AI-07 — Ajuste de carga sugerido por semana
**Onde:** Portal — Training Plan, visão "Por Atleta"  
**Valor:** O badge de `fatigue_alert` já existe. Mas o coach não recebe uma recomendação concreta de *o que fazer* — só um aviso.

**O que geraria:**
> "Nas últimas 3 semanas João completou 58% dos treinos prescritos com RPE médio 8.3. Sugestão: reduzir volume da próxima semana em 20–25% — trocar o longão por 45min contínuo e cancelar o tiro de quinta. Reavalie na terça antes de confirmar a semana."

**Dados necessários:** `plan_workout_releases`, `completed_workouts`, `athlete_workout_feedback` (já disponíveis no módulo de training plan)  
**Esforço estimado:** Médio — nova aba/modal no card do atleta na visão por atleta  
**Prioridade:** Média-alta

---

### 🗂️ AI-08 — Plano periodizado a partir de objetivo
**Onde:** Portal — criação de nova planilha (`/training-plan/new`)  
**Valor:** Criar um plano do zero exige conhecimento de periodização. Para atletas novos ou preparações para provas, a IA pode gerar a estrutura de semanas que o coach depois personaliza.

**Fluxo:** Coach informa data da prova-alvo, distância (5K/10K/meia/maratona), nível (iniciante/intermediário/avançado), dias disponíveis por semana → IA retorna estrutura de semanas com `cycle_type`, volume relativo e observações.

**Dados necessários:** Input do coach (nenhum dado do atleta obrigatório)  
**Esforço estimado:** Médio — novo modal no form de criação de planilha + API route + parsing da resposta em semanas  
**Prioridade:** Alta

---

### 🗂️ AI-09 — Auto-classificação do tipo de corrida
**Onde:** App — pós-corrida / histórico  
**Valor:** Corridas importadas via Strava ou registradas sem prescrição não têm tipo definido. A IA (ou heurísticas) poderia inferir se foi easy run, tempo, intervalado, longão a partir do perfil de pace e duração.

**Abordagem sugerida:** Começar com heurísticas simples (desvio padrão do pace, zonas de FC) antes de usar LLM — mais rápido, mais barato, sem latência.

**Dados necessários:** `avg_pace_sec_km`, `moving_ms`, `avg_bpm`, GPS points (variância de pace por km)  
**Esforço estimado:** Médio — edge function ou lógica no cliente  
**Prioridade:** Baixa (pode ser resolvido com regras antes de IA)

---

### 🗂️ AI-10 — Matching inteligente para desafios
**Onde:** App — `MatchmakingScreen`  
**Valor:** Duplas de desafio bem compatíveis geram mais engajamento. Hoje o matching é provavelmente por pace. A IA poderia considerar: pace médio, volume semanal, horário preferido de treino (inferido dos timestamps de sessões), regularidade.

**Dados necessários:** `sessions` (pace, timestamp, distância), `coaching_members` (grupo)  
**Esforço estimado:** Alto — requer modelo de similaridade ou ranking, edge function própria  
**Prioridade:** Baixa (complexidade alta para impacto incerto)

---

## Notas de arquitetura

### Stack de IA atual
- **Portal (Next.js):** Chama OpenAI diretamente via `fetch` nas API routes. Chave: `OPENAI_API_KEY` no Vercel.
- **App (Flutter):** Chama Supabase Edge Functions (Deno). As edge functions chamam OpenAI via `Deno.env.get("OPENAI_API_KEY")`.

### Secrets necessários
| Ambiente | Onde configurar | Chave |
|----------|----------------|-------|
| Vercel (portal) | Vercel Environment Variables | `OPENAI_API_KEY` ✅ configurada em 2026-04-14 |
| Supabase (edge functions) | `supabase secrets set OPENAI_API_KEY=...` | `OPENAI_API_KEY` — **necessário para AI-03** |

### Modelo padrão
`gpt-4o-mini` — barato, rápido, suficiente para todos os casos documentados aqui.  
Só considerar `gpt-4o` se surgir necessidade de raciocínio mais complexo (ex.: análise de periodização de 16 semanas).

### Princípios de segurança
1. **Nunca conselho médico** — prompts explicitamente proibem isso.
2. **Nunca envio automático** — o coach sempre revisa antes de enviar qualquer comunicação gerada por IA.
3. **Falha silenciosa** — toda feature de IA no app deve ter `try/catch` e nunca quebrar a tela principal.
4. **Dados reais, sem invenção** — todos os prompts incluem os dados brutos para que a IA não preencha lacunas.
