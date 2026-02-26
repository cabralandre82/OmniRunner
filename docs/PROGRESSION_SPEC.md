# PROGRESSION_SPEC.md — Sistema de Progressão do Omni Runner

> **Sprint:** 13.1.0 (Phase 13 — Progression Engine)
> **Status:** ESPECIFICAÇÃO — documento obrigatório antes de implementação
> **Dependências:** `GAMIFICATION_POLICY.md`, `DECISIONS.md` (DECISÃO 016)
> **Princípio:** Toda XP e progressão é derivada de atividade física verificada.
> Nenhum sistema de progressão substitui ou compete com OmniCoins — são complementares.

---

## 1. VISÃO GERAL

O Progression Engine adiciona 6 sistemas ao Omni Runner:

| # | Sistema | Função |
|---|---------|--------|
| 1 | **XP** | Unidade de progressão por sessão — não é moeda, não é gasto |
| 2 | **Níveis** | Escala logarítmica derivada do XP total acumulado |
| 3 | **Badges** | Conquistas desbloqueáveis por critérios específicos |
| 4 | **Streaks** | Sequências contínuas de atividade (diário/semanal) |
| 5 | **Missões** | Objetivos temporários com recompensa de XP + Coins |
| 6 | **Temporadas** | Ciclos de 90 dias com ranking, missões exclusivas, e reset de posição |

### Relação XP × OmniCoins

| Aspecto | XP | OmniCoins |
|---------|------|-----------|
| Natureza | Progressão permanente — nunca decresce | Moeda virtual — ganha e gasta |
| Uso | Determina nível, desbloqueia badges | Compra customizações visuais |
| Reset | **NUNCA** | Nunca expira, mas saldo varia |
| Fonte | Sessões verificadas, missões, streaks, badges | Sessões, desafios, streaks, PRs |
| Conversão XP ↔ Coins | **PROIBIDA** — são sistemas independentes | — |

---

## 2. CURVA DE XP

### 2.1 Fórmula

O XP necessário para alcançar o nível `N` (com `N ≥ 1`) é:

```
xpForLevel(N) = floor(100 × N^1.5)
```

| Nível | XP acumulado necessário | XP incremental (do nível anterior) |
|:-----:|:-----------------------:|:----------------------------------:|
| 1 | 100 | 100 |
| 2 | 283 | 183 |
| 3 | 520 | 237 |
| 5 | 1 118 | 289 |
| 10 | 3 162 | 393 |
| 15 | 5 809 | 480 |
| 20 | 8 944 | 558 |
| 25 | 12 500 | 630 |
| 30 | 16 432 | 697 |
| 40 | 25 298 | 818 |
| 50 | 35 355 | 927 |
| 75 | 64 952 | 1 140 |
| 100 | 100 000 | 1 329 |

### 2.2 Propriedades da curva

- **Início rápido:** Nível 1 em 100 XP (1 sessão de 5 km).
- **Crescimento sub-exponencial:** `N^1.5` cresce mais devagar que `2^N` — nunca fica impossível.
- **Sem teto:** Nível máximo é infinito (nível 100 = ~100k XP, alcançável em ~6 meses de corrida consistente).
- **Determinística:** dado o XP total, o nível é calculado sem estado adicional.

### 2.3 Cálculo inverso (XP total → nível)

```
levelFromXp(totalXp) = floor((totalXp / 100)^(2/3))
```

Clampado em `max(0, ...)`. Nível 0 = nenhuma sessão ainda.

---

## 3. FONTES DE XP

### 3.1 Sessão verificada (fonte primária)

```
sessionXp = baseXp + distanceBonus + durationBonus + hrBonus
```

| Componente | Fórmula | Min | Max |
|------------|---------|:---:|:---:|
| `baseXp` | 20 (fixo) | 20 | 20 |
| `distanceBonus` | `floor(distanceKm × 10)` | 0 | 500 (cap 50 km) |
| `durationBonus` | `floor(durationMin / 5) × 2` | 0 | 120 (cap 5 h) |
| `hrBonus` | 10 se `avgBpm != null` | 0 | 10 |

**Exemplos:**

| Sessão | distKm | durMin | HR? | XP total |
|--------|:------:|:------:|:---:|:--------:|
| Corrida curta (2 km, 15 min) | 20 + 20 + 6 + 0 | — | — | 46 |
| Corrida típica (5 km, 30 min, HR) | 20 + 50 + 12 + 10 | — | — | 92 |
| Corrida longa (21 km, 120 min, HR) | 20 + 210 + 48 + 10 | — | — | 288 |
| Ultra (50 km, 300 min, HR) | 20 + 500 + 120 + 10 | — | — | 650 |

### 3.2 Outras fontes

| Fonte | XP | Condição |
|-------|:--:|----------|
| Badge desbloqueado (bronze) | 50 | Primeiro desbloqueio |
| Badge desbloqueado (prata) | 100 | — |
| Badge desbloqueado (ouro) | 200 | — |
| Badge desbloqueado (diamante) | 500 | — |
| Missão completada (fácil) | 30–50 | Ver §6 |
| Missão completada (média) | 80–150 | Ver §6 |
| Missão completada (difícil) | 200–400 | Ver §6 |
| Streak semanal (3+ corridas) | 50 | Além dos +20 Coins já existentes |
| Streak mensal (12+ corridas) | 150 | Além dos +50 Coins já existentes |
| Desafio completado | 30 | Participação verificada |
| Desafio vencido | 75 | Bônus de vitória |

---

## 4. LIMITES DIÁRIOS

| Recurso | Limite | Motivo |
|---------|:------:|--------|
| XP por sessões | **1 000 XP/dia** | Anti-farm: ~10 sessões boas por dia |
| Sessões que geram XP | **10/dia** | Alinhado com `GAMIFICATION_POLICY.md` §8 |
| Sessões que geram Coins | **10/dia** | Regra existente (§3) |
| Badges desbloqueados | Sem limite | Badges são achievement, não farm |
| Missões completadas | Sem limite | Controlado pela oferta de missões (ver §6) |
| XP por fonte não-sessão | **500 XP/dia** | Cap para badges + missões (evita XP farming via badges triviais) |

### 4.1 Cálculo do cap

```
dailySessionXp = sum(sessionXp) para sessões do dia (UTC)
if dailySessionXp > 1000:
    xpCreditado = 1000 - xpJaComputadoHoje
```

O cap é aplicado no momento do crédito, nunca retroativamente.
XP de badges/missões tem cap separado (500/dia).

**Total máximo teórico:** 1 000 (sessões) + 500 (badges/missões) = **1 500 XP/dia**.

---

## 5. BADGES

### 5.1 Estrutura

Cada badge possui:

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | `String` | Identificador único (ex: `badge_first_5k`) |
| `category` | `BadgeCategory` | Enum: `distance`, `frequency`, `speed`, `endurance`, `social`, `special` |
| `tier` | `BadgeTier` | Enum: `bronze`, `silver`, `gold`, `diamond` |
| `name` | `String` | Nome exibido (PT-BR) |
| `description` | `String` | Descrição curta da condição |
| `iconAsset` | `String` | Path do ícone |
| `xpReward` | `int` | XP ao desbloquear (50/100/200/500 por tier) |
| `coinsReward` | `int` | OmniCoins ao desbloquear (0 para maioria) |
| `criteria` | `BadgeCriteria` | Regra de desbloqueio (sealed class) |
| `isSecret` | `bool` | Se true, nome/descrição ocultos até desbloqueio |

### 5.2 Regras de desbloqueio

Badges são avaliados após cada sessão verificada. O motor avalia
todos os badges não-desbloqueados e desbloqueia os elegíveis.

**Regra fundamental:** Nunca re-lock um badge. Uma vez desbloqueado, é permanente.

### 5.3 Catálogo de badges (MVP — 30 badges)

#### Distância (8)

| Badge | Tier | Critério |
|-------|------|----------|
| Primeiro Quilômetro | Bronze | 1ª sessão verificada ≥ 1 km |
| 5K Runner | Bronze | 1ª sessão ≥ 5 km |
| 10K Runner | Silver | 1ª sessão ≥ 10 km |
| Meia Maratona | Gold | 1ª sessão ≥ 21.1 km |
| Maratona | Diamond | 1ª sessão ≥ 42.195 km |
| 50 km acumulados | Bronze | Distância total lifetime ≥ 50 km |
| 200 km acumulados | Silver | Distância total lifetime ≥ 200 km |
| 1000 km acumulados | Gold | Distância total lifetime ≥ 1000 km |

#### Frequência (7)

| Badge | Tier | Critério |
|-------|------|----------|
| Primeiro Passo | Bronze | 1ª sessão verificada completada |
| 10 corridas | Bronze | 10 sessões verificadas lifetime |
| 50 corridas | Silver | 50 sessões verificadas lifetime |
| 100 corridas | Gold | 100 sessões verificadas lifetime |
| 500 corridas | Diamond | 500 sessões verificadas lifetime |
| 7 dias seguidos | Silver | Streak diário de 7 dias |
| 30 dias seguidos | Gold | Streak diário de 30 dias |

#### Velocidade (5)

| Badge | Tier | Critério |
|-------|------|----------|
| Abaixo de 6:00/km | Bronze | Pace médio < 6:00/km em sessão ≥ 5 km |
| Abaixo de 5:00/km | Silver | Pace médio < 5:00/km em sessão ≥ 5 km |
| Abaixo de 4:30/km | Gold | Pace médio < 4:30/km em sessão ≥ 5 km |
| Abaixo de 4:00/km | Diamond | Pace médio < 4:00/km em sessão ≥ 5 km |
| PR Pace | Bronze | Qualquer novo PR de pace (sessão ≥ 1 km) |

#### Resistência (4)

| Badge | Tier | Critério |
|-------|------|----------|
| 1 hora correndo | Bronze | 1ª sessão ≥ 60 min |
| 2 horas correndo | Silver | 1ª sessão ≥ 120 min |
| 10 horas acumuladas | Bronze | Tempo total de corrida lifetime ≥ 600 min |
| 100 horas acumuladas | Gold | Tempo total de corrida lifetime ≥ 6000 min |

#### Social (4)

| Badge | Tier | Critério |
|-------|------|----------|
| Primeiro Desafio | Bronze | Completar qualquer desafio |
| 5 Desafios | Silver | Completar 5 desafios |
| Invicto | Gold | Vencer 10 desafios 1v1 consecutivos |
| Líder de Grupo | Silver | Ser rank #1 em desafio de grupo ≥ 5 participantes |

#### Especial (2)

| Badge | Tier | Critério |
|-------|------|----------|
| Madrugador | Bronze | Sessão verificada iniciada antes das 06:00 local |
| Coruja | Bronze | Sessão verificada iniciada após 22:00 local |

### 5.4 Anti-exploits para badges

| Regra | Descrição |
|-------|-----------|
| Sessão verificada obrigatória | `isVerified == true` |
| Distância mínima | Badges de pace requerem ≥ 5 km |
| Sem retroatividade artificial | Badges avaliados no momento da sessão, não recalculados em batch |
| Dedup | Badge ID + user ID = unique — nunca desbloqueado duas vezes |

---

## 6. STREAKS

### 6.1 Tipos de streak

| Streak | Período | Critério | Recompensa |
|--------|---------|----------|------------|
| **Diário** | 1 dia (UTC midnight–midnight) | ≥ 1 sessão verificada ≥ 1 km | Mantém contador |
| **Semanal** | Segunda 00:00 UTC – Domingo 23:59 UTC | ≥ 3 sessões verificadas na semana | +50 XP, +20 Coins |
| **Mensal** | Dia 1 00:00 UTC – último dia 23:59 UTC | ≥ 12 sessões verificadas no mês | +150 XP, +50 Coins |

### 6.2 Regras de streak diário

| Regra | Valor |
|-------|-------|
| Incrementa | +1 ao completar ≥ 1 sessão verificada ≥ 1 km no dia UTC |
| Reseta | Volta a 0 se nenhuma sessão no dia UTC anterior |
| Freeze | **1 freeze gratuito a cada 7 dias de streak** (calculado, não comprado) |
| Freeze máximo | 1 acumulado por vez — não acumula múltiplos |
| Freeze uso | Consumido automaticamente se o dia passar sem sessão |
| Visibilidade | Contador + chama animada na home |

### 6.3 XP por streaks

O streak diário gera XP bônus em milestones:

| Streak diário | XP bônus (one-time) | Coins bônus |
|:-------------:|:-------------------:|:-----------:|
| 3 dias | 20 | 0 |
| 7 dias | 50 | 10 |
| 14 dias | 100 | 20 |
| 30 dias | 250 | 50 |
| 60 dias | 500 | 100 |
| 100 dias | 1 000 | 200 |
| 365 dias | 5 000 | 1 000 |

Milestones são one-time per streak chain. Se o streak resetar e
o usuário alcançar 7 novamente, o bônus é concedido novamente.

---

## 7. MISSÕES

### 7.1 Estrutura

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | `String` | UUID |
| `title` | `String` | Nome da missão (PT-BR) |
| `description` | `String` | Objetivo claro |
| `difficulty` | `MissionDifficulty` | `easy`, `medium`, `hard` |
| `xpReward` | `int` | XP ao completar |
| `coinsReward` | `int` | Coins ao completar |
| `criteria` | `MissionCriteria` | Sealed class com condição de conclusão |
| `expiresAtMs` | `int?` | Prazo (null = sem expiração) |
| `seasonId` | `String?` | Null = missão permanente |
| `maxCompletions` | `int` | 1 = one-time; >1 = repetível |
| `cooldownMs` | `int?` | Tempo entre completions (para repetíveis) |

### 7.2 Tipos de missão

| Tipo | Critério | Exemplo |
|------|----------|---------|
| **Distância total** | Acumular X km em Y dias | "Corra 20 km esta semana" |
| **Sessões count** | Completar N sessões em Y dias | "Complete 5 corridas em 7 dias" |
| **Pace target** | Alcançar pace < X em sessão ≥ Y km | "Corra abaixo de 5:30/km em 5+ km" |
| **Duration** | Correr por X minutos em uma sessão | "Corra por 45 min sem parar" |
| **HR zone** | Passar X min em zona Y | "Passe 20 min na zona 3" |
| **Streak** | Manter streak diário de N dias | "Mantenha 7 dias de streak" |
| **Social** | Completar N desafios | "Complete 3 desafios esta semana" |

### 7.3 Slots de missões ativas

| Slot | Tipo | Rotação |
|------|------|---------|
| 1–2 | Missão diária (easy) | Renovada a cada 24h UTC |
| 3–4 | Missão semanal (medium) | Renovada toda segunda 00:00 UTC |
| 5 | Missão de temporada (hard) | Fixa durante a temporada |

O usuário sempre tem **5 missões ativas** disponíveis.
Missões expiradas não completadas simplesmente desaparecem — sem penalidade.

### 7.4 Tabela de recompensas

| Dificuldade | XP | Coins | Prazo típico |
|-------------|:--:|:-----:|:------------:|
| Fácil | 30–50 | 5–10 | 24h |
| Média | 80–150 | 15–30 | 7 dias |
| Difícil | 200–400 | 50–100 | 90 dias (temporada) |

---

## 8. TEMPORADAS

### 8.1 Estrutura

| Campo | Valor |
|-------|-------|
| Duração | **90 dias** (trimestral) |
| Nome | Temático (ex: "Temporada do Inverno 2026") |
| Início | 1º dia do trimestre (Jan/Abr/Jul/Out) |
| Fim | Último dia do trimestre, 23:59:59 UTC |

### 8.2 O que reseta

| Reseta | Não reseta |
|--------|-----------|
| Season XP (ranking sazonal) | XP total (lifetime) |
| Posição no ranking sazonal | Nível do jogador |
| Missões de temporada | Badges desbloqueados |
| Season pass progress | OmniCoins balance |
| — | Streaks ativos |

### 8.3 Season XP

Season XP é um subconjunto do XP total ganho **durante** a temporada.
Todo XP ganho durante a temporada conta tanto para o nível global
quanto para o ranking sazonal.

```
seasonXp = sum(xp ganho entre season.startsAtMs e season.endsAtMs)
```

### 8.4 Ranking sazonal

| Tier | Season XP necessário | % estimado de jogadores |
|------|:--------------------:|:-----------------------:|
| Bronze | 0–999 | ~50% |
| Prata | 1 000–4 999 | ~30% |
| Ouro | 5 000–14 999 | ~15% |
| Diamante | 15 000–29 999 | ~4% |
| Elite | 30 000+ | ~1% |

### 8.5 Recompensas de fim de temporada

| Tier alcançado | XP bônus | Coins bônus | Badge exclusivo |
|----------------|:--------:|:-----------:|:---------------:|
| Bronze | 0 | 0 | Não |
| Prata | 100 | 50 | Badge sazonal (bronze tier) |
| Ouro | 300 | 150 | Badge sazonal (silver tier) |
| Diamante | 600 | 300 | Badge sazonal (gold tier) |
| Elite | 1 000 | 500 | Badge sazonal (diamond tier) |

Badges sazonais são **exclusivos** — nunca mais disponíveis após a temporada.
Isso incentiva engajamento contínuo sem criar FOMO excessivo.

### 8.6 Season Pass (NÃO é IAP)

O season pass é um track de recompensas progressivo baseado em Season XP.
Não é pago. Não tem tier premium. É gratuito para todos.

```
Season XP milestones: 200, 500, 1000, 2000, 3500, 5000, 7500, 10000, 15000, 20000
```

Cada milestone desbloqueia uma recompensa (Coins, XP bônus, badge sazonal,
cosmético exclusivo). Total: **10 milestones por temporada**.

---

## 9. ENTIDADES DE DOMÍNIO (PLANEJADAS)

| Entidade | Responsabilidade |
|----------|-----------------|
| `UserProgressEntity` | XP total, nível atual, season XP |
| `BadgeDefinitionEntity` | Definição estática de um badge (catálogo) |
| `UserBadgeEntity` | Badge desbloqueado por um usuário (quando, em qual sessão) |
| `StreakEntity` | Streak diário/semanal/mensal do usuário |
| `MissionDefinitionEntity` | Template de missão (catálogo) |
| `UserMissionEntity` | Progresso do usuário em uma missão ativa |
| `SeasonEntity` | Metadados da temporada (nome, datas, status) |
| `SeasonProgressEntity` | Progresso do usuário na temporada (season XP, tier, milestones) |
| `XpTransactionEntity` | Registro imutável de cada crédito de XP (append-only, como ledger) |

---

## 10. REPOSITÓRIOS (PLANEJADOS)

| Interface | Métodos principais |
|-----------|--------------------|
| `IUserProgressRepo` | `getByUserId`, `save` |
| `IBadgeDefinitionRepo` | `getAll`, `getById` |
| `IUserBadgeRepo` | `getByUserId`, `unlock`, `isUnlocked` |
| `IStreakRepo` | `getByUserId`, `save` |
| `IMissionRepo` | `getActiveMissions`, `getByUserId`, `updateProgress`, `complete` |
| `ISeasonRepo` | `getCurrentSeason`, `getProgress`, `saveProgress` |
| `IXpTransactionRepo` | `append`, `sumByUserId`, `sumByUserIdAndSeason`, `countToday` |

---

## 11. USE CASES (PLANEJADOS)

| Use Case | Input → Output |
|----------|----------------|
| `CalculateSessionXp` | `WorkoutSessionEntity` → `int` (XP) |
| `CreditSessionXp` | Sessão verificada → XP creditado (com daily cap) |
| `EvaluateBadges` | Sessão → lista de badges desbloqueados |
| `UpdateStreak` | Sessão → streak atualizado |
| `CheckMissionProgress` | Sessão → missões atualizadas |
| `GetUserLevel` | `userId` → `(level, xpInLevel, xpToNext)` |
| `GetSeasonProgress` | `userId` → `(seasonXp, tier, milestones)` |
| `SettleSeason` | Temporada expirada → distribui recompensas |
| `GenerateDailyMissions` | Clock → novas missões diárias |
| `GenerateWeeklyMissions` | Clock → novas missões semanais |

---

## 12. SPRINTS PLANEJADOS

| Sprint | Descrição |
|--------|-----------|
| 13.1.0 | Este documento (PROGRESSION_SPEC.md) |
| 13.1.1 | Entidades: `UserProgressEntity`, `XpTransactionEntity`, `StreakEntity` |
| 13.1.2 | Use Cases: `CalculateSessionXp`, `CreditSessionXp` (com daily cap) |
| 13.1.3 | Isar: `UserProgressRecord`, `XpTransactionRecord` + repos |
| 13.1.4 | Use Cases: `EvaluateBadges`, `BadgeDefinitionEntity`, `UserBadgeEntity` |
| 13.1.5 | Isar: `BadgeDefinitionRecord`, `UserBadgeRecord` + repos |
| 13.1.6 | Use Cases: `UpdateStreak` + `StreakEntity` persistence |
| 13.1.7 | Use Cases: missões (`CheckMissionProgress`, `GenerateDailyMissions`) |
| 13.1.8 | Use Cases: temporadas (`GetSeasonProgress`, `SettleSeason`) |
| 13.1.9 | Integração: wiring no `TrackingBloc` (session → XP + badges + streak + missions) |
| 13.1.10 | UI: tela de perfil (nível, XP, badges, streak) |
| 13.1.11 | UI: tela de missões |
| 13.1.12 | UI: tela de temporada (ranking, season pass) |
| 13.1.13 | Testes unitários (curva XP, badge evaluation, streak logic, mission progress) |
| 13.1.14 | QA: auditoria termos, consistência, fraude |

---

## 13. ANTI-FARM / ANTI-EXPLOIT

| Vetor | Mitigação |
|-------|-----------|
| Sessões muito curtas para XP | `baseXp` = 20 fixo; sem bônus abaixo de 1 km |
| Farm de badges via sessões mínimas | Badges de pace requerem ≥ 5 km; badges de distância usam `isVerified` |
| Farm de XP via missões triviais | Cap de 500 XP/dia para fontes não-sessão |
| Manipulação de streak via timezone | Cálculo sempre em UTC midnight |
| Repeat mission exploit | `maxCompletions` + `cooldownMs` por missão |
| Season tier inflation | Tiers baseados em XP absoluto, não percentil — sem manipulação relativa |
| Multi-account para self-challenge | Desafios requerem auth; anti-cheat cross-validates |

---

## 14. COMPLIANCE COM GAMIFICATION_POLICY.md

| Regra da Policy | Status na Progressão |
|-----------------|---------------------|
| §1: Engajamento e diversão, não monetário | ✅ XP é progressão, não moeda |
| §2: Coins não-convertíveis | ✅ XP não é convertível em Coins |
| §3: Coins por atividade verificada | ✅ Missões/streaks mantêm regra |
| §5: Vocabulário proibido | ✅ Termos usados: "nível", "conquista", "missão", "temporada" |
| §8: `isVerified` obrigatório | ✅ Todo XP requer sessão verificada |
| §8: Audit trail | ✅ `XpTransactionEntity` append-only |

---

## 15. PARK LEADERBOARD TIERS (Sprint 25.0.0)

O sistema de progressão agora inclui reconhecimento em parques com tiers e categorias:

### 15.1 Tiers de Reconhecimento

| Tier | Rank | Emoji | Descrição |
|------|------|-------|-----------|
| Rei do Parque | #1 | 👑 | Melhor atleta na categoria para aquele parque |
| Elite | #2-3 | ⭐ | Top 3 do parque |
| Destaque | #4-10 | 🏅 | Top 10 do parque |
| Pelotão | #11-20 | 🎯 | Top 20 do parque |
| Frequentador | #21+ | 🏃 | Corre regularmente no parque |

### 15.2 Categorias de Ranking

| Categoria | Métrica | Unidade |
|-----------|---------|---------|
| Pace | Melhor pace médio | sec/km |
| Distância | Km total no parque | km |
| Frequência | Total de corridas | contagem |
| Sequência | Maior streak no parque | dias |
| Evolução | Melhoria de pace (%) | percentual |
| Maior Corrida | Corrida mais longa | km |

### 15.3 Fontes de XP de Parque (futuro)

| Ação | XP |
|------|----|
| Primeira corrida no parque | 50 XP |
| Subir de tier | 100 XP |
| Conquistar "Rei do Parque" | 200 XP |
| Quebrar recorde de segmento | 150 XP |

### 15.4 Entities

- `ParkLeaderboardTier` (enum: rei, elite, destaque, pelotao, frequentador)
- `ParkLeaderboardCategory` (enum: pace, distance, frequency, streak, evolution, longestRun)
- `ParkLeaderboardEntry` (parkId, userId, displayName, rank, tier, category, value, period)
- `ParkActivityEntity` (id, parkId, userId, distanceM, startTime, displayName)

### 15.5 Anti-Exploit

| Vetor | Mitigação |
|-------|-----------|
| GPS spoofing para park detection | Atividades devem vir do Strava (não do app); Strava valida GPS |
| Farm de frequência com runs curtas | Mínimo 1 km dentro do polygon para contar |
| Multi-account para monopolizar leaderboard | Vinculado ao Strava account (unique athlete_id) |

---

## 16. GLOSSÁRIO

| Termo | Definição |
|-------|-----------|
| XP | Experience Points — unidade de progressão permanente |
| Nível | Derivado do XP total via fórmula `floor(100 × N^1.5)` |
| Badge | Conquista desbloqueável por critério específico |
| Tier | Rarity do badge: bronze / silver / gold / diamond |
| Streak | Sequência ininterrupta de dias com atividade verificada |
| Freeze | Proteção automática contra perda de streak (1 a cada 7 dias) |
| Missão | Objetivo temporário com prazo e recompensa |
| Temporada | Ciclo de 90 dias com ranking e recompensas exclusivas |
| Season XP | XP ganho durante a temporada (subconjunto do XP total) |
| Season Pass | Track de 10 milestones por temporada (gratuito) |
| Park Tier | Nível de reconhecimento em um parque (Rei/Elite/Destaque/Pelotão/Frequentador) |
| Park Category | Dimensão de ranking (pace/distância/frequência/sequência/evolução/maior corrida) |
| Park Check-in | Registro automático de atividade em parque detectado por GPS polygon |

---

*Documento criado no Sprint 13.1.0 — Atualizado em 26/02/2026 (Sprint 25.0.0 — Parks)*
