# ROADMAP_NEXT.md — Planejamento Detalhado de Features

> **Data:** 2026-02-26
> **Status:** PLANEJAMENTO DETALHADO
> **Referência:** DECISIONS_LOG DECISAO 066 / 067

---

## PRIORIDADE DE IMPLEMENTAÇÃO

| # | Feature | Prioridade | Complexidade | Dependência |
|---|---------|:----------:|:------------:|:-----------:|
| 0 | ~~Regra de visibilidade em desafios~~ | ~~URGENTE~~ | ~~Baixa~~ | ~~FEITO~~ |
| 1 | ~~OmniWrapped (Retrospectiva)~~ | ~~Média~~ | ~~Média~~ | ~~FEITO~~ |
| 2 | ~~Liga de Assessorias~~ | ~~Média~~ | ~~Alta~~ | ~~FEITO~~ |
| 3 | ~~DNA do Corredor (Running DNA)~~ | ~~Baixa~~ | ~~Alta~~ | ~~FEITO~~ |

> **DESCARTADAS:** Corrida Fantasma (tracking nativo removido) e Marketplace
> (risco App Store/Play Store + economia cross-assessoria inviável).

---

## 0. REGRA DE VISIBILIDADE EM DESAFIOS ATIVOS

### Problema identificado no código

O `challenge-get` Edge Function (linha 99) retorna `progress_value` de TODOS
os participantes sem filtro. O `_ParticipantsCard` no `ChallengeDetailsScreen`
(linha 1040) exibe esse valor formatado no `trailing` do `ListTile` do oponente.

Isso permite que um atleta veja pace/distância/tempo do oponente durante o
desafio ativo, espere ele terminar, e ajuste seu esforço.

### Pontos de vazamento encontrados

| Onde | O que vaza | Arquivo |
|------|-----------|---------|
| `challenge-get` EF | `progress_value` de todos | `supabase/functions/challenge-get/index.ts:99` |
| `_participantTile()` | progressValue formatado no trailing | `challenge_details_screen.dart:1040` |
| `_GroupLiveProgressCard` | soma coletiva (OK para grupo cooperativo) | `challenge_details_screen.dart:1150` |

### O que NÃO vaza (verificado)

- `_ActiveChallengeRow` no `TodayScreen`: só título, tipo, tempo restante, fee — OK
- `challenges_list_screen.dart`: sem progressValue — OK
- `_ResultsCard`: só renderiza quando `result != null` (após settlement) — OK
- `challenge_result_screen.dart`: só acessível após conclusão — OK

### UX proposta

**Desafio ativo (1v1):**
- Meu tile: mostrar meu progresso normalmente (distância/pace/tempo)
- Oponente tile: ocultar progresso. Mostrar apenas:
  - Se tem sessão: "Completou" (check verde)
  - Se não tem: "Aguardando..." (hourglass laranja)
  - Nunca mostrar valor numérico

**Desafio ativo (grupo cooperativo):**
- `_GroupLiveProgressCard` (progresso coletivo): MANTER — é cooperativo, todos
  do mesmo time, faz sentido ver o progresso total
- Tiles individuais: aplicar a mesma regra — cada atleta vê seu próprio
  progresso, mas não vê detalhes dos colegas (evita pressão social negativa)

**Desafio ativo (team vs team):**
- Progresso do próprio time: visível (coletivo cooperativo)
- Progresso do time adversário: oculto — só "X de Y completaram"

**Desafio concluído/resultado:**
- Tudo visível normalmente

### Passo-a-passo de implementação

```
PASSO 1: Back-end — challenge-get (server-side protection)
  Arquivo: supabase/functions/challenge-get/index.ts
  - Após fetch de participants (linha 97-101):
  - Se challenge.status == 'active':
    - Para cada participant onde user_id != caller:
      - Substituir progress_value por null
      - Manter contributing_session_ids como boolean (has_sessions: true/false)
  - Se challenge.status != 'active': retornar tudo normalmente
  Risco: nenhum — dados são filtrados antes de sair do servidor

PASSO 2: Front-end — _ParticipantsCard._participantTile()
  Arquivo: challenge_details_screen.dart, linhas 1004-1047
  - Adicionar parâmetros: bool isActive, String currentUserId
  - Lógica do trailing:
    Se isActive && !isMe:
      Se p.contributingSessionIds.isNotEmpty:
        → Chip "Completou" (verde)
      Senão:
        → Chip "Aguardando" (laranja)
    Senão:
      → Manter comportamento atual (valor formatado)
  Risco: baixo — mudança visual apenas

PASSO 3: Front-end — _GroupLiveProgressCard
  Arquivo: challenge_details_screen.dart, linhas 1150-1250
  - Manter o card de progresso coletivo inalterado para grupo cooperativo
  - Para team_vs_team: criar variante que mostra progresso do próprio time
    mas oculta detalhes do time adversário
  Risco: médio — precisa distinguir times

PASSO 4: Testes
  - Widget test: _participantTile com isActive=true não mostra progressValue
  - Widget test: _participantTile com isActive=false mostra progressValue
  - Verificar que grupo cooperativo ainda mostra progresso coletivo
```

### Estimativa: 2-3 horas

---

## 1. OMNIWRAPPED (RETROSPECTIVA DO CORREDOR) — IMPLEMENTADO

### Dados disponíveis no Supabase (verificados)

| Tabela | Campos relevantes | Uso |
|--------|-------------------|-----|
| `sessions` | `start_time_ms`, `total_distance_m`, `moving_ms`, `avg_pace_sec_km`, `avg_bpm`, `is_verified`, `source` | Métricas de corrida |
| `profile_progress` | `total_xp`, `daily_streak_count`, `streak_best`, `lifetime_session_count`, `lifetime_distance_m`, `lifetime_moving_ms` | Totais lifetime |
| `badge_awards` | `badge_id`, `awarded_at_ms` | Conquistas no período |
| `challenges` + `challenge_participants` + `challenge_results` | status, outcome, coins | Desafios disputados/ganhos |
| `coaching_members` | `group_id` | Assessoria do atleta |
| `coin_ledger` | `delta_coins`, `reason` | Movimentação de coins |

**Nota:** Todas as corridas vêm do Strava (`source='strava'`), então temos
`total_distance_m`, `moving_ms`, `avg_pace_sec_km`, `start_time_ms`.
NÃO temos GPS detalhado local (pontos são salvos em Storage, mas não para
análise de rota — apenas anti-cheat).

### Compartilhamento

Já existe `run_share_card.dart` com padrão `RepaintBoundary` + `share_plus`
para capturar widget como PNG e compartilhar. Reusável para Wrapped.

### Gráficos

`fl_chart: ^1.1.1` já está no `pubspec.yaml`. Suporta LineChart, BarChart,
RadarChart, PieChart.

### UX proposta

Tela estilo "stories" com swipe horizontal:

```
Slide 1: "Seu [período] em números"
  - Total km corridos
  - Total de sessões
  - Tempo total correndo
  - Fundo gradiente escuro, números grandes e brancos

Slide 2: "Evolução de pace"
  - LineChart mostrando pace médio mês a mês (ou semana a semana)
  - Seta indicando melhoria: "Seu pace melhorou X% nesse período"
  - Se piorou, mensagem neutra: "Variação de pace ao longo do período"

Slide 3: "Seus desafios"
  - Total disputados, vitórias, derrotas
  - "Você venceu X de Y desafios"
  - Ícone de troféu se win rate > 50%

Slide 4: "Conquistas"
  - Badges desbloqueados no período (grade visual)
  - Nível atual + XP ganho
  - "Você subiu X níveis nesse período"

Slide 5: "Curiosidades"
  - Dia da semana mais ativo (histograma simples)
  - Horário preferido para correr
  - Corrida mais longa do período
  - Melhor pace do período

Slide 6: "Compartilhe" (CTA)
  - Preview do card compartilhável (versão resumida)
  - Botão "Compartilhar" → abre share sheet com imagem
```

### Passo-a-passo de implementação

```
PASSO 1: Edge Function — generate-wrapped
  Arquivo novo: supabase/functions/generate-wrapped/index.ts
  - Input: { period_type: 'month'|'quarter'|'year', period_key: '2026-02' }
  - Queries:
    a) SELECT de sessions do período (filtrado por start_time_ms)
       → total_distance_m, moving_ms, avg_pace_sec_km, count, min/max pace
    b) SELECT de challenge_results + participants do período
       → total disputados, wins, losses
    c) SELECT de badge_awards do período → badges desbloqueados
    d) SELECT de profile_progress → XP, nível, streak
    e) Agrupar sessions por dia da semana e hora → padrões
  - Output: JSON com todas as métricas calculadas
  - Cache: upsert em tabela user_wrapped (evita recalcular)
  Risco: baixo — queries de leitura, sem side-effects
  Dependência: sessions precisam ter dados (mínimo 5 corridas para gerar)

PASSO 2: Migration — tabela user_wrapped
  Arquivo novo: supabase/migrations/YYYYMMDD_user_wrapped.sql
  CREATE TABLE user_wrapped (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    period_type TEXT NOT NULL CHECK (period_type IN ('month','quarter','year')),
    period_key TEXT NOT NULL,
    data JSONB NOT NULL,
    created_at_ms BIGINT NOT NULL,
    UNIQUE(user_id, period_type, period_key)
  );
  + RLS: owner read/insert only
  Risco: nenhum — tabela nova, não afeta nada existente

PASSO 3: Flutter — Entity + Repo
  Arquivo novo: entities/wrapped_entity.dart (simple data class)
  Não precisa de repo local (Isar) — dados vêm direto da EF, sem cache local
  Risco: nenhum

PASSO 4: Flutter — WrappedScreen (PageView)
  Arquivo novo: presentation/screens/wrapped_screen.dart
  - PageView com PageController
  - 6 slides como widgets separados privados (_SlideNumbers, _SlidePace, etc.)
  - Cada slide: Container com gradiente + animações de entrada
  - Dots indicator no bottom
  - Dados carregados no initState via EF generate-wrapped
  - Estado: loading → loaded → error
  Risco: baixo — tela nova, sem modificar nada existente
  Cuidados:
    - Tratar período sem dados (< 5 sessões): mostrar "Corra mais para gerar"
    - LineChart de pace: usar fl_chart LineChartData
    - Histograma dia da semana: BarChart

PASSO 5: Flutter — Compartilhamento
  Arquivo novo: presentation/widgets/wrapped_share_card.dart
  - Reusar padrão de run_share_card.dart (RepaintBoundary + share_plus)
  - Card resumo com: total km, sessões, melhor pace, badges, level
  - Branding OmniRunner no rodapé
  Risco: nenhum — widget novo isolado

PASSO 6: Integrar — Entry point
  Arquivo: presentation/screens/progress_hub_screen.dart
  - Adicionar tile "Minha Retrospectiva" que navega para WrappedScreen
  - Só visível se atleta tem >= 5 sessões no período
  OU
  Arquivo: presentation/screens/today_screen.dart
  - Banner sazonal: "Sua retrospectiva de fevereiro está pronta!"
  Risco: baixo — adiciona um tile/card
```

### Estimativa: 6-8 horas

---

## 2. LIGA DE ASSESSORIAS — IMPLEMENTADO

### Estrutura existente (verificada)

| O que existe | Onde | Relevância |
|-------------|------|------------|
| `coaching_groups` | Table com id, name, logo_url, coach_user_id, city | Base das assessorias |
| `coaching_members` | Table com user_id, group_id, role, display_name | Membros |
| `coaching_rankings` | Table com snapshots semanais/mensais por grupo | Rankings internos |
| `coaching_ranking_entries` | Entries por atleta em cada ranking | Dados individuais |
| `CoachingRankingMetric` | volumeDistance, totalTime, bestPace, consistencyDays | Métricas já definidas |
| `championships` | Sistema de campeonatos entre assessorias | **Pode ser base da liga** |
| `AthleteChampionshipsScreen` | Tela de campeonatos do atleta | UI existente |

### Decisão arquitetural: Liga vs Championship

O sistema de championships já existe com:
- Templates, enrollment, lifecycle (open → active → completed)
- Participant tracking por assessoria
- Ranking screen

**Recomendação: Construir a Liga SOBRE o sistema de championships existente.**
Uma "Liga" é um championship com `type: 'league'`, duração longa (trimestral),
e scoring baseado em métricas agregadas da assessoria (não individuais).

Isso evita duplicar toda a infraestrutura. A Liga é um "sabor" de championship.

### UX proposta

```
Acesso: Assessoria → "Liga OmniRunner" (card no MyAssessoriaScreen)

Tela Liga:
┌─────────────────────────────────────────┐
│ 🏆 Liga OmniRunner Q1 2026             │
│ Termina em 45 dias                      │
├─────────────────────────────────────────┤
│ #1 🥇 Assessoria Corrida SP    1.240pts │
│ #2 🥈 Running Club RJ          1.105pts │
│ #3 🥉 Equipe Maratona BH         980pts │
│ #4    Sua Assessoria ← (highlight) 870pts│
│ #5    Runners Curitiba              720pts│
│ ...                                      │
├─────────────────────────────────────────┤
│ Sua contribuição: 45 km, 12 sessões     │
│ Contribuição da equipe: 340 km total    │
└─────────────────────────────────────────┘
```

### Score da Liga (fórmula proposta)

```
score_semanal = (
  total_km_verificados × 1.0 +
  total_sessoes_verificadas × 0.5 +
  pct_membros_ativos_semana × 200 +
  vitorias_em_desafios × 3.0
) / num_membros
```

Dividir por número de membros normaliza — assessorias pequenas competem
com grandes em igualdade.

### Passo-a-passo de implementação

```
PASSO 1: Migration — league_seasons + league_snapshots
  Arquivo novo: supabase/migrations/YYYYMMDD_league.sql
  - league_seasons: temporada com nome, datas, status
  - league_enrollments: assessoria inscrita na temporada
  - league_snapshots: snapshot semanal por assessoria (score, rank, métricas)
  + RLS: leitura pública (qualquer autenticado pode ver o ranking)
  Risco: nenhum — tabelas novas
  Alternativa: reusar championship_templates + championships com type='league'
  DECISÃO: avaliar na implementação se é melhor reusar ou criar novo

PASSO 2: Edge Function — league-snapshot (cron semanal)
  Arquivo novo: supabase/functions/league-snapshot/index.ts
  - Para cada league_season ativa:
    - Para cada assessoria inscrita:
      a) Buscar sessions verificadas dos membros na última semana
      b) Calcular total_km, total_sessions, active_members_pct
      c) Buscar challenge_results com wins
      d) Calcular score normalizado
    - Ordenar assessorias por score total acumulado
    - Inserir league_snapshots com rank
  - Triggar via cron (pg_cron) ou lifecycle-cron existente
  Risco: médio — queries cross-table (sessions × coaching_members × challenges)
  Mitigação: índices em sessions(user_id, start_time_ms) já existem

PASSO 3: Edge Function — league-list / league-get
  Arquivo novo: supabase/functions/league-list/index.ts
  - Retorna temporadas ativas + ranking atual
  - Inclui posição da assessoria do caller
  Risco: baixo

PASSO 4: Flutter — Entity + Tela
  Arquivo novo: entities/league_season_entity.dart
  Arquivo novo: entities/league_snapshot_entity.dart
  Arquivo novo: presentation/screens/league_screen.dart
  - Lista ranqueada com highlight na assessoria do usuário
  - Top 3 com visual dourado/prateado/bronze
  - Card "Sua contribuição" mostrando km e sessões do atleta
  - Card "Sua assessoria" com posição e variação (↑↓)
  Risco: baixo — tela nova

PASSO 5: Integrar — Entry point
  Arquivo: presentation/screens/my_assessoria_screen.dart
  - Adicionar card "Liga OmniRunner" com posição atual
  - Navega para LeagueScreen
  E/OU
  Arquivo: presentation/screens/today_screen.dart
  - Card com posição da assessoria na liga
  Risco: baixo — adiciona card

PASSO 6: Enrollment
  Arquivo: presentation/screens/staff_dashboard_screen.dart
  - Staff pode inscrever assessoria na liga
  - OU auto-enrollment: toda assessoria com >= 3 membros ativos entra
  DECISÃO: definir na implementação
```

### Estimativa: 10-15 horas

---

## 3. DNA DO CORREDOR (RUNNING DNA) — IMPLEMENTADO

### Dados disponíveis (verificados)

| Dado | Fonte | Disponível? |
|------|-------|:-----------:|
| Pace por corrida | `sessions.avg_pace_sec_km` | ✅ |
| Distância por corrida | `sessions.total_distance_m` | ✅ |
| Duração por corrida | `sessions.moving_ms` | ✅ |
| Hora do dia | `sessions.start_time_ms` → extrair hora | ✅ |
| Dia da semana | `sessions.start_time_ms` → extrair dia | ✅ |
| Frequência semanal | Contar sessions por semana | ✅ |
| Altitude/elevação | GPS points em Storage JSON (campo `alt`) | ⚠️ Parcial |
| HR por corrida | `sessions.avg_bpm`, `sessions.max_bpm` | ⚠️ Se disponível |
| Desafios win/loss | `challenge_results` + `challenge_participants` | ✅ |
| Streak | `profile_progress.daily_streak_count`, `streak_best` | ✅ |
| XP/Level | `profile_progress.total_xp` | ✅ |
| Tempo desde registro | `profiles.created_at` | ✅ |

**Nota:** GPS detalhado (points com lat/lng) está em Storage JSON. Acessível mas
mais custoso de processar. Altitude e HR point-by-point estão lá também.

### Eixos do radar (6 dimensões) — definição

```
1. VELOCIDADE (0-100)
   Base: avg_pace_sec_km do último mês
   Referência: < 4:00/km = 100, > 8:00/km = 0
   Fórmula: 100 - ((pace_sec - 240) / (480 - 240)) * 100, clamped 0-100

2. RESISTÊNCIA (0-100)
   Base: distância média por sessão no último mês
   Referência: > 15km = 100, < 2km = 0
   Fórmula: ((avg_distance_km - 2) / (15 - 2)) * 100, clamped 0-100

3. CONSISTÊNCIA (0-100)
   Base: sessões por semana média no último mês
   Referência: >= 6/semana = 100, < 1/semana = 0
   Fórmula: (sessions_per_week / 6) * 100, clamped 0-100

4. EVOLUÇÃO (0-100)
   Base: taxa de melhoria de pace (regressão linear sobre últimos 3 meses)
   Referência: melhorando > 2%/mês = 100, piorando = 0, estável = 50
   Fórmula: baseada no coeficiente angular da regressão

5. VERSATILIDADE (0-100)
   Base: desvio padrão das distâncias (variedade de tipos de treino)
   Referência: alta variedade (sprint + longo + médio) = 100, sempre mesma distância = 0
   Fórmula: stddev normalizado por range de distâncias

6. COMPETITIVIDADE (0-100)
   Base: win rate em desafios (últimos 3 meses)
   Referência: > 70% = 100, 50% = 50, 0% = 0
   Requer mínimo 3 desafios para pontuar (senão: 50 default)
   Fórmula: (wins / total) * 100, com floor 3 desafios
```

### Insights gerados (linguagem natural)

A partir dos 6 eixos + dados brutos, gerar frases:

```
- "Você é um corredor matutino: 73% das suas corridas são entre 5h e 8h"
- "Seu pace melhora 11% após 2+ dias de descanso"
- "Sua zona de conforto é 5-7km. Considere treinos de 10km+ para crescer"
- "Você corre mais às quartas e sábados"
- "Baseado na sua evolução, seu próximo PR de 5K pode vir em ~3 semanas"
```

### Previsão de PR

```
Método: regressão linear sobre os melhores paces por período (mês)
Para cada faixa de distância (3-5km, 5-10km, 10-15km, 15-21km, 21-42km):
  - Extrair melhor pace em cada mês dos últimos 6 meses
  - Fit linear: pace = a*mês + b
  - Projetar quando pace cruza o PR atual
  - Confiança: R² da regressão (se < 0.3, não exibir previsão)
```

### UX proposta

```
Tela Running DNA:
┌─────────────────────────────────────────┐
│ 🧬 Seu DNA de Corredor                 │
│                                         │
│         Velocidade                      │
│            85                           │
│     Competit.  ╱╲  Resistência          │
│          60  ╱    ╲  72                 │
│           ╱   DNA   ╲                   │
│     Evolução  ╲    ╱  Consistência      │
│          45    ╲╱   88                  │
│       Versatilidade                     │
│            35                           │
│                                         │
│ ───────────────────────────────────────  │
│ 💡 Insights                            │
│ • Corredor matutino (73% antes das 8h) │
│ • Pace melhora 11% após descanso       │
│ • Zona de conforto: 5-7km              │
│                                         │
│ 🎯 Previsão de PR                      │
│ ████████████████░░░░ 80%               │
│ 5K PR previsto: 24:12 (~3 semanas)     │
│                                         │
│ [Compartilhar meu DNA]                  │
└─────────────────────────────────────────┘
```

### Passo-a-passo de implementação

```
PASSO 1: Edge Function — generate-running-dna
  Arquivo novo: supabase/functions/generate-running-dna/index.ts
  - Input: { user_id } (caller's own ID)
  - Queries:
    a) Buscar sessions dos últimos 6 meses (verified only)
    b) Calcular os 6 eixos do radar
    c) Gerar insights em linguagem natural (regras estáticas, sem ML)
    d) Calcular previsão de PR (regressão linear simples)
    e) Retornar JSON estruturado
  - Cache: upsert em tabela running_dna
  Risco: médio — regressão linear e agrupamentos estatísticos
  Dependência: mínimo de 10 sessões para gerar DNA confiável

PASSO 2: Migration — tabela running_dna
  Arquivo novo: supabase/migrations/YYYYMMDD_running_dna.sql
  CREATE TABLE running_dna (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) UNIQUE,
    radar_scores JSONB NOT NULL,
    insights TEXT[] NOT NULL,
    pr_predictions JSONB,
    stats JSONB NOT NULL,
    updated_at_ms BIGINT NOT NULL
  );
  + RLS: owner read only
  Risco: nenhum — tabela nova

PASSO 3: Flutter — RunningDnaScreen
  Arquivo novo: presentation/screens/running_dna_screen.dart
  - RadarChart (fl_chart RadarChartData) com 6 eixos
  - Lista de insights com ícones
  - Card de previsão de PR com barra de progresso
  - Botão "Compartilhar meu DNA"
  - Estado: loading → loaded → error → insufficient_data
  Risco: baixo — tela nova
  Cuidados:
    - fl_chart RadarChart: verificar se suporta 6 eixos (suporta)
    - Tratar caso de dados insuficientes (< 10 sessões):
      mostrar "Continue correndo! Precisamos de mais dados para gerar seu DNA"

PASSO 4: Flutter — Compartilhamento
  Arquivo novo: presentation/widgets/dna_share_card.dart
  - Reusar padrão RepaintBoundary + share_plus
  - Card visual com radar chart mini + stats resumidos
  - Branding OmniRunner
  Risco: nenhum

PASSO 5: Integrar — Entry point
  Arquivo: presentation/screens/progress_hub_screen.dart
  - Adicionar tile "Meu DNA de Corredor" que navega para RunningDnaScreen
  - Badge "Novo!" se DNA atualizado recentemente
  OU
  Arquivo: presentation/screens/personal_evolution_screen.dart
  - Seção "DNA" embutida na tela de evolução
  Risco: baixo — adiciona tile

PASSO 6: Atualização periódica
  - DNA recalculado semanalmente (via cron ou on-demand no app)
  - Botão "Atualizar" na tela para forçar recálculo
  - Cache de 7 dias no servidor (não recalcular se updated_at < 7 dias)
```

### Estimativa: 12-18 horas

---

## ORDEM DE IMPLEMENTAÇÃO

```
Fase 1 (Urgente — pré-release):          ✅ FEITO
  └── #0 Regra de visibilidade em desafios

Fase 2 (Engajamento — viralidade):       ✅ FEITO
  └── #1 OmniWrapped

Fase 3 (Escala — competição):                ✅ FEITO
  └── #2 Liga de Assessorias

Fase 4 (Diferencial — inteligência):      ✅ FEITO
  └── #3 DNA do Corredor
```

**Total estimado: 30-44 horas de desenvolvimento**

---

## CHECKLIST DE RISCOS

| Risco | Feature | Mitigação |
|-------|---------|-----------|
| progressValue vaza na API | #0 | Server-side filter no challenge-get |
| Poucos dados para Wrapped | #1 | Mínimo 5 sessões, senão "Corra mais" |
| Query lenta no league-snapshot | #2 | Índices existentes em sessions + cron off-peak |
| Regressão linear sem dados | #3 | R² < 0.3 = não exibir previsão |
| fl_chart RadarChart limitação | #3 | Testado: suporta 6+ eixos |
| RLS bloqueia cross-group read | #2 | league_snapshots com RLS público (autenticado) |

---

## IDEIAS DESCARTADAS

- **Corrida Fantasma (Ghost Rival):** tracking nativo removido, todas as corridas
  vêm do Strava (pós-corrida). Ghost precisa de GPS em tempo real. Inviável.
- **Marketplace de OmniCoins:** risco de rejeição App Store/Play Store (moeda
  virtual + bens reais = desvio de IAP). Economia cross-assessoria cria obrigações
  sem consentimento entre coaches. Inviável sem reestruturação profunda.
