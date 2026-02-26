# ROADMAP_NEXT.md — Planejamento de Features Aprovadas

> **Data:** 2026-02-26
> **Status:** PLANEJAMENTO
> **Referência:** DECISIONS_LOG DECISAO 066 / 067

---

## PRIORIDADE DE IMPLEMENTAÇÃO

| # | Feature | Prioridade | Complexidade | Dependência |
|---|---------|:----------:|:------------:|:-----------:|
| 0 | Regra de visibilidade em desafios | **URGENTE** | Baixa | Nenhuma |
| 1 | OmniWrapped (Retrospectiva) | Média | Média | Dados históricos |
| 2 | Liga de Assessorias | Média | Alta | Assessorias existentes |
| 3 | DNA do Corredor (Running DNA) | Baixa | Alta | Dados históricos + ML |

> **DESCARTADAS:** Corrida Fantasma (tracking nativo removido) e Marketplace
> (risco App Store/Play Store + economia cross-assessoria inviável).

---

## 0. REGRA DE VISIBILIDADE EM DESAFIOS ATIVOS

### Problema
Hoje, o `_ParticipantsCard` no `ChallengeDetailsScreen` mostra o `progressValue`
formatado (distância, pace, tempo) de TODOS os participantes enquanto o desafio
está ativo. Isso permite que um atleta espere o oponente terminar, veja o resultado
dele, e ajuste seu esforço para vencer por margem mínima. Isso é injusto.

### Regra
- Desafio **ativo**: cada atleta vê apenas:
  - Seus próprios detalhes completos (seu progress, pace, etc.)
  - Oponente: apenas "Completou" ou "Ainda não completou" (sem valores)
- Desafio **concluído** (ambos completaram ou período expirou): todos os detalhes
  são revelados normalmente

### Plano técnico

#### Front-end (Flutter)
**Arquivo:** `challenge_details_screen.dart`

1. `_ParticipantsCard._participantTile()` — linha ~1004:
   - Adicionar parâmetro `bool isActiveChallenge` ao widget
   - Se `isActiveChallenge && !isMe`:
     - Ocultar `trailing` com progressValue
     - No lugar, mostrar apenas ícone:
       - `Icons.check_circle` + "Completou" se `p.contributingSessionIds.isNotEmpty`
       - `Icons.hourglass_empty` + "Aguardando" se `p.contributingSessionIds.isEmpty`
   - Se `isMe` ou desafio concluído: manter comportamento atual

2. `_GroupLiveProgressCard` — para desafios de grupo:
   - Grupo é cooperativo, então o progresso coletivo PODE ser visível
   - Mas para Team vs Team: aplicar a mesma regra — time adversário só mostra
     "X de Y completaram" sem valores individuais

#### Back-end (Supabase)
3. **RPC/View** `get_challenge_details`:
   - Quando `challenge.status == 'active'` e o solicitante NÃO é o participante:
     - Retornar `progress_value: null` para participantes que não são o solicitante
   - Isso é uma camada extra de proteção server-side (mesmo que o front oculte,
     o dado não deve vazar na API)

#### Testes
4. Widget test: verificar que progress do oponente NÃO aparece em desafio ativo
5. Widget test: verificar que progress do oponente APARECE em desafio concluído

### Estimativa: 2-3 horas

---

## 1. OMNIWRAPPED (RETROSPECTIVA DO CORREDOR)

### Conceito
Resumo visual periódico (mensal/trimestral/anual) das estatísticas do atleta.
Formato stories-friendly para compartilhamento social.

### Plano técnico

#### Back-end (Supabase Edge Function)

`generate-wrapped`:
- Input: `user_id`, `period` (month/quarter/year)
- Queries:
  - `workout_sessions`: total km, total tempo, total sessões, pace médio, melhor pace
  - `challenges`: total disputados, vitórias, derrotas
  - `profile_progress`: XP ganho, níveis subidos
  - `badge_awards`: badges desbloqueados no período
  - `parks_visited`: parques visitados (se park detection ativa)
  - `coaching_groups`: assessoria do atleta
- Output: JSON estruturado com todas as métricas
- Cache: salvar resultado em tabela `user_wrapped` para não recalcular

```sql
CREATE TABLE user_wrapped (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  period_type TEXT NOT NULL CHECK (period_type IN ('month', 'quarter', 'year')),
  period_key TEXT NOT NULL,       -- ex: '2026-Q1', '2026-02', '2026'
  data JSONB NOT NULL,
  created_at_ms BIGINT NOT NULL,
  UNIQUE(user_id, period_type, period_key)
);
```

#### Presentation (Flutter)

```
screens/
  wrapped_screen.dart             -- Telas estilo stories com animações
  wrapped_share_screen.dart       -- Preview + botão compartilhar
```

`wrapped_screen.dart`:
- PageView com 5-7 "slides" animados:
  1. "Seu ano em números" — total km, sessões, tempo
  2. "Evolução" — gráfico pace ao longo do período
  3. "Desafios" — vitórias, participações, rivalidades
  4. "Conquistas" — badges ganhos, nível atual
  5. "Curiosidades" — dia mais ativo, horário favorito, distância mais longa
  6. "Top 3" — melhores corridas do período
  7. "Sua assessoria" — ranking na assessoria, km coletivos
- Cada slide com gradiente temático, tipografia grande, animações suaves
- Botão "Compartilhar" gera imagem (via RepaintBoundary + screenshot)
- Navegação por swipe + dots indicator

### Estimativa: 6-8 horas

---

## 2. LIGA DE ASSESSORIAS

### Conceito
Competição sazonal entre assessorias. Ranking baseado em métricas agregadas.
Temporadas mensais/trimestrais. Cria senso de comunidade entre assessorias.

### Plano técnico

#### Database (Supabase/PostgreSQL)

```sql
-- Temporadas da liga
CREATE TABLE league_seasons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,                -- ex: 'Liga OmniRunner Q1 2026'
  starts_at_ms BIGINT NOT NULL,
  ends_at_ms BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'upcoming'
    CHECK (status IN ('upcoming', 'active', 'completed')),
  config JSONB NOT NULL DEFAULT '{}'  -- métricas, pesos, regras
);

-- Participação de assessorias na liga
CREATE TABLE league_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id UUID NOT NULL REFERENCES league_seasons(id),
  coaching_group_id UUID NOT NULL REFERENCES coaching_groups(id),
  enrolled_at_ms BIGINT NOT NULL,
  UNIQUE(season_id, coaching_group_id)
);

-- Snapshots semanais do ranking (para histórico)
CREATE TABLE league_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id UUID NOT NULL REFERENCES league_seasons(id),
  coaching_group_id UUID NOT NULL REFERENCES coaching_groups(id),
  week_number INT NOT NULL,
  total_km DOUBLE PRECISION DEFAULT 0,
  total_sessions INT DEFAULT 0,
  active_members INT DEFAULT 0,
  avg_frequency DOUBLE PRECISION DEFAULT 0,
  challenge_wins INT DEFAULT 0,
  score DOUBLE PRECISION DEFAULT 0,   -- score ponderado
  rank INT,
  snapshot_at_ms BIGINT NOT NULL
);
```

#### Cálculo de score (Edge Function `league-snapshot`)

Score semanal = soma ponderada:
- Total km da assessoria × 1.0
- Número de sessões verificadas × 0.5
- % membros ativos na semana × 2.0 (incentiva participação coletiva)
- Vitórias em desafios × 3.0
- Normalizado pelo número de membros (para não favorecer assessorias grandes)

#### Presentation (Flutter)

```
screens/
  league_screen.dart              -- Ranking geral da temporada
  league_season_detail.dart       -- Detalhes da temporada + gráfico evolução
  league_assessoria_detail.dart   -- Stats de uma assessoria na liga
```

`league_screen.dart`:
- Banner da temporada ativa (nome, período, dias restantes)
- Lista ranqueada de assessorias com: posição, nome, score, variação (↑↓)
- Top 3 com destaque visual (ouro/prata/bronze)
- "Sua assessoria" highlighted se participando
- Ao tocar: detalhes da assessoria na liga

#### Fluxo
1. Staff inscreve assessoria na liga da temporada (ou auto-inscrição)
2. Edge Function `league-snapshot` roda semanalmente (cron) e calcula scores
3. Atletas veem ranking na tela "Liga"
4. Fim da temporada: badge exclusivo para top 3, troféu digital

### Estimativa: 10-15 horas

---

## 3. DNA DO CORREDOR (RUNNING DNA)

### Conceito
Perfil atlético gerado por análise estatística de todo o histórico do corredor.
Identifica padrões, prevê PRs, sugere otimizações.

### Plano técnico

#### Back-end (Supabase Edge Function)

`generate-running-dna`:
- Input: `user_id`
- Análise sobre `workout_sessions` do atleta:

```
1. PERFIL TEMPORAL
   - Hora do dia mais ativa (histograma de start_time por hora)
   - Dia da semana mais ativo
   - Performance por hora (pace médio por faixa horária)
   → "Corredor matutino: pace 12% melhor entre 6h-7h"

2. PERFIL DE TERRENO (se altitude disponível)
   - Ganho de elevação médio por corrida
   - Impacto da elevação no pace
   → "Terreno plano: seu pace cai 18% em subidas"

3. PERFIL DE RECUPERAÇÃO
   - Performance após 1, 2, 3 dias de descanso
   - Tendência de fadiga (performance ao longo da semana)
   → "Após 2 dias de descanso, performance sobe 9%"

4. PERFIL DE DISTÂNCIA
   - Distribuição de distâncias (histograma)
   - Pace por faixa de distância
   - "Zona confortável" vs "zona de crescimento"
   → "Corredor de 5-7km. Pace degrada 8% acima de 10km"

5. CURVA DE EVOLUÇÃO
   - Regressão linear do pace ao longo do tempo
   - Velocidade de melhoria (pace/mês)
   - Previsão de PR baseada na tendência
   → "PR de 5K estimado em 2 semanas: 24:12"

6. PERFIL DE CONSISTÊNCIA
   - Frequência semanal média
   - Variância de frequência
   - Streaks
   → "Consistência: 4.2 corridas/semana, desvio de 0.8"
```

#### Resultado

```sql
CREATE TABLE running_dna (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) UNIQUE,
  data JSONB NOT NULL,            -- Todos os perfis calculados
  radar_scores JSONB NOT NULL,    -- 6 eixos do radar: 0-100 cada
  insights TEXT[] NOT NULL,       -- Lista de insights em linguagem natural
  pr_predictions JSONB,           -- PRs previstos com datas estimadas
  updated_at_ms BIGINT NOT NULL
);
```

`radar_scores` (6 eixos do "DNA"):
- Velocidade (pace médio relativo ao nível)
- Resistência (performance em distâncias longas)
- Consistência (frequência e regularidade)
- Evolução (taxa de melhoria ao longo do tempo)
- Versatilidade (variedade de distâncias/terrenos)
- Competitividade (win rate em desafios)

#### Presentation (Flutter)

```
screens/
  running_dna_screen.dart         -- Tela principal com radar chart
  running_dna_insights.dart       -- Lista de insights detalhados
  running_dna_share.dart          -- Imagem compartilhável
```

`running_dna_screen.dart`:
- Radar chart animado (6 eixos) como visual central
- Abaixo: cards de insight ("Você é um corredor matutino...")
- Seção "Previsão de PR" com barras de progresso
- Botão "Compartilhar meu DNA" → gera imagem estilo poster
- Botão "Ver detalhes" → tela com gráficos detalhados por perfil
- Atualização automática semanal (ou manual)

#### Dependências
- Mínimo de 10-15 sessões para gerar DNA confiável
- Altitude (opcional, melhora perfil de terreno)
- Biblioteca de radar chart: `fl_chart` (já usado?) ou `syncfusion_flutter_charts`

### Estimativa: 12-18 horas

---

## ORDEM DE IMPLEMENTAÇÃO RECOMENDADA

```
Fase 1 (Urgente — pré-release):
  └── #0 Regra de visibilidade em desafios         ~2-3h

Fase 2 (Engajamento — viralidade):
  └── #1 OmniWrapped                               ~6-8h

Fase 3 (Escala — competição):
  └── #2 Liga de Assessorias                       ~10-15h

Fase 4 (Diferencial — inteligência):
  └── #3 DNA do Corredor                           ~12-18h
```

**Total estimado: 30-44 horas de desenvolvimento**

---

## NOTAS

- A regra de visibilidade (#0) é a única que bloqueia release. As demais são
  incrementais e podem ser entregues em sprints separados.
- DNA do Corredor (#3) é o mais complexo mas é o maior diferencial competitivo.
  Pode ser entregue em fases (radar básico → insights → previsão de PR).

## IDEIAS DESCARTADAS

- **Corrida Fantasma (Ghost Rival):** tracking nativo removido, todas as corridas
  vêm do Strava (pós-corrida). Ghost precisa de GPS em tempo real. Inviável.
- **Marketplace de OmniCoins:** risco de rejeição App Store/Play Store (moeda
  virtual + bens reais = desvio de IAP). Economia cross-assessoria cria obrigações
  sem consentimento entre coaches. Inviável sem reestruturação profunda.
