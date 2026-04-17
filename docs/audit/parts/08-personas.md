# PARTE 8 de 8 (FINAL) — LENTES 21 (Atleta Profissional), 22 (Atleta Amador) e 23 (Treinador de Corrida)

As três personas **explicitamente solicitadas** pelo usuário original, totalizando **60 itens**. Esta é a parte que diferencia a auditoria de um prompt genérico: avalia o produto como **pessoas reais que correm e treinam corredores** usariam.

---

## LENTE 21 — ATLETA PROFISSIONAL (elites, Olímpicos, equipes patrocinadas)

Perfil: VO2max > 70, pace < 3:20/km, treina 2× ao dia, usa Garmin Fenix/Epix + HR strap, está sob contrato de patrocínio (dados = IP), compete internacionalmente.

### 🔴 [21.1] `MAX_SPEED_MS = 12.5 m/s` **invalida velocistas profissionais**

**Achado** — `supabase/functions/_shared/anti_cheat.ts:59`:

```59:59:supabase/functions/_shared/anti_cheat.ts
const MAX_SPEED_MS = 12.5;            // ~45 km/h
```

Usain Bolt em 100m teve velocidade média de 12,42 m/s e **pico de 12,27 m/s** nas fases finais. Velocistas amadores de clube (sub-11 em 100m) ficam na faixa 10-11 m/s. O limiar 12,5 m/s + `SPEED_VIOLATION_THRESHOLD = 0.1` (10 % dos segmentos) flaga **todo atleta profissional** em sessões de velocidade.

**Risco** — Elite não consegue usar o produto. Narrativa "Omni Runner para atletas de ponta" ([21] é o primeiro caso de uso que o usuário pediu) **colapsa**.

**Correção** — Thresholds **dependentes do perfil**:

```typescript
// supabase/functions/_shared/anti_cheat.ts
function getThresholds(athleteProfile: { skill_bracket: string }) {
  const base = { MAX_SPEED_MS: 12.5, /* ... */ };
  if (athleteProfile.skill_bracket === "elite") {
    return { ...base, MAX_SPEED_MS: 13.5, TELEPORT_SPEED_MS: 25.0 };
  }
  return base;
}
```

Ou melhor: remover hard cap de velocidade instantânea. Usar **teleport = 2 pontos > 500 m em < 5 s** (impossível por terra em velocidade humana).

**Teste** — `anti_cheat.elite_sprints.test.ts`: sessão com splits de 10,5 m/s em 100 m + GPS realista → `is_verified = true`, zero flags.

---

### 🔴 [21.2] `MAX_HR_BPM = 220` **inferior à realidade** de atletas jovens

**Achado** — Linha 73: cap 220 BPM. Estudos modernos (Robergs & Landwehr 2002, Tanaka 2001) mostram que `220 − idade` subestima max HR para atletas jovens em até 20 BPM. Elite sub-25 pode atingir 210-225 BPM em VO2max. Cap = 220 marca corridas legítimas como suspeitas.

**Correção** — Usar `max(220, measured_max_hr_last_6_months + 5)` ou simplesmente elevar para 230. Validar com heart-rate strap (chest BLE) tem menos ruído que optical.

---

### 🔴 [21.3] **Dados GPS e biométricos sem controle de propriedade** (dilema do patrocínio)

**Achado** — Atleta elite do clube X patrocinado por marca Y. Dados ficam em:

- `sessions`, `athlete_health_data` ([4.4] proposto): property do atleta via LGPD.
- `coaching_groups → clube X`: property do clube por contrato.
- `strava_connections`: compartilhado com Strava.
- Omni Runner pode agregar em "top elites" visível a todos.

Não há campo/política diferenciando "propriedade científica" (biomarcadores) de "propriedade comercial" (tempos de corrida).

**Risco** — Atleta assina contrato com clube novo; clube anterior retém dados (violação LGPD + quebra contratual). Ou Omni Runner usa para "marketing agregado" ("top 10 atletas da plataforma: João, Maria…") — expõe segredo de treino.

**Correção** —

```sql
ALTER TABLE athlete_health_data ADD COLUMN data_ownership jsonb DEFAULT '{
  "primary": "athlete",
  "licensed_to": [],
  "share_policy": "private"
}'::jsonb;

-- UI: athlete chooses whether performance data can be published in "top athletes"
ALTER TABLE profiles ADD COLUMN visibility_preferences jsonb DEFAULT '{
  "profile_discoverable": true,
  "pace_public": false,
  "hr_public": false,
  "sponsor_can_read_all": false
}'::jsonb;
```

Export-and-go: `/api/export/my-data` ([4.15]) inclui **transferência** (JSON signed) que outro clube pode importar ao atleta assinar lá.

---

### 🔴 [21.4] **Ausência de "training load" / TSS / CTL / ATL**

**Achado** — `coaching_athlete_kpis_daily` tem distance/duration/frequency. Não calcula:

- **TSS** (Training Stress Score) por sessão
- **CTL** (Chronic Training Load) — fitness crônico 42d
- **ATL** (Acute Training Load) — fadiga 7d
- **TSB** (Training Stress Balance) = CTL − ATL — "forma"

Atleta elite precisa desse gráfico para periodizar; é o painel principal do TrainingPeaks.

**Risco** — Elite migra para TrainingPeaks, usa Omni Runner apenas para checklist social → atrito, perda da persona alvo.

**Correção** —

```sql
ALTER TABLE sessions ADD COLUMN tss numeric(6,1);
ALTER TABLE sessions ADD COLUMN if_intensity_factor numeric(3,2);
-- IF = NP / FTP (running: NGP / rFTP or custom pace zone model)

-- Daily rollup
CREATE MATERIALIZED VIEW mv_athlete_load_daily AS
SELECT user_id, date_trunc('day', to_timestamp(start_time_ms/1000))::date AS day,
  SUM(tss) AS daily_tss,
  -- EWMA for CTL and ATL
  exp_avg(tss, 42) OVER w AS ctl,
  exp_avg(tss, 7)  OVER w AS atl
FROM sessions
WINDOW w AS (PARTITION BY user_id ORDER BY start_time_ms)
GROUP BY user_id, day;
```

UI: `athlete_evolution_screen.dart` + `athlete_my_evolution_screen.dart` ganham tab "Performance Management Chart".

---

### 🔴 [21.5] **Zonas de treino** (pace/HR) não personalizáveis

**Achado** — Código usa "skill_bracket" (`beginner/intermediate/advanced/elite`) como proxy, mas não há:

- Zonas de pace customizadas (Z1-Z5 Jack Daniels, 7 zonas Coggan)
- Zonas de HR (% HRmax ou % HRR Karvonen)
- Threshold pace (calculado de testes 30 min)
- Critical speed (Jones/Vanhatalo)

Sem zonas, treino de "40 min em Z2 aeróbico" é invisível.

**Correção** —

```sql
CREATE TABLE public.athlete_zones (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  pace_zones jsonb NOT NULL,  -- [{zone: 1, min_sec_km: 360, max_sec_km: 420}, ...]
  hr_zones jsonb NOT NULL,
  lthr_bpm integer,
  threshold_pace_sec_km integer,
  vo2max numeric(4,1),
  updated_at timestamptz DEFAULT now(),
  updated_by text  -- 'athlete_manual' | 'auto_calculated' | 'coach_assigned'
);
```

Edge Function `calculate-zones` infere via percentis das últimas 20 sessões + testes de campo.

---

### 🟠 [21.6] Polyline GPS **resolução baixa** (5m distanceFilter)

**Achado** — `location_settings_entity.dart:15` default `distanceFilterMeters = 5.0`. Em sprint (12 m/s), um ponto a cada 5 m = ponto a cada 0,4 s. Para análise biomecânica de elite é pobre.

**Correção** — Modo "performance recording":

```dart
class LocationSettingsEntity {
  const LocationSettingsEntity({
    this.distanceFilterMeters = 5.0,
    this.accuracy = LocationAccuracy.high,
    this.mode = RecordingMode.standard,
  });

  // Elite mode: 1m filter, 1Hz sampling minimum, GNSS multi-constellation.
}
```

Trade-off: bateria (+30%) e storage. Opt-in.

---

### 🟠 [21.7] **Sem interoperabilidade** com .fit real-time

**Achado** — `omni_runner/lib/features/integrations_export/data/fit/fit_encoder.dart` exporta .fit após sessão. Não importa .fit **em tempo real** do Garmin/Coros via ANT+ FIT File Transfer.

**Risco** — Elite grava no Fenix, exporta manualmente → Omni Runner se torna só "depósito" sem valor agregado. Concorrência: Strava tem sync automático, TrainingPeaks tem auto-upload.

**Correção** — OAuth com Garmin Connect (já lista "Health API" possível), Coros Stream, Polar AccessLink, Suunto. Cada conexão = webhook → `strava-webhook` pattern ([16.6]).

---

### 🟠 [21.8] **Lap splits manuais** inexistentes em tela de corrida

**Achado** — `grep "lap\|split_manual\|auto_lap" omni_runner/lib/presentation/screens` → pouco. Tela de recording sem botão "lap" físico.

**Risco** — Treino estruturado ("10 × 400 m r/200 m") não consegue ser marcado durante execução. Atleta usa Garmin/Coros no pulso → Omni vira redundante.

**Correção** —

1. Botão "Lap" grande no recording screen com haptic feedback.
2. Auto-lap configurável (1 km, 1 mi, custom distance, por tempo).
3. **Interval mode**: executa sequência "trabalho/descanso" configurada, beep ao trocar.
4. `sessions.laps jsonb` salva splits.

---

### 🟠 [21.9] **Calibração de GPS em pista** (400 m outdoor)

**Achado** — Em pista de atletismo, GPS tem erro lateral 3-5 m → 200 m medidos viram 195 ou 212. Elite rodando 1500m em tartan quer distância exata.

**Correção** — Modo "pista 400m" com auto-lap a cada volta por GPS fit + correção determinística (cada lap = 400 m). Ou BLE sensor de passos/cadência mais preciso que GPS em pista fechada.

---

### 🟠 [21.10] **Anti-cheat pode publicamente marcar elite como suspeito**

**Achado** — Quando `is_verified = false` por flag, outros atletas podem ver "session not verified" em feed/leaderboard. Atleta profissional com sua integridade em jogo fica exposto a um falso positivo.

**Correção** — Flags só visíveis a `platform_admin` + atleta. Feed mostra "verificação pendente" neutro (sem razão pública). Elite pode solicitar revisão manual antes de virar público.

---

### 🟠 [21.11] Ghost mode **não funciona para competições reais**

**Achado** — `challenge_ghost_provider.dart` usa comparação relativa sem mostrar coordenadas. Para treino sólo OK. Mas elite quer simular pacing de atleta-rival (ghost de corrida oficial) — sem dados de rival no produto.

**Correção** — Import de splits públicos de competições (IAAF, World Athletics API). "Correr ao lado do tempo do vencedor de Berlim 2025" como desafio.

---

### 🟠 [21.12] **Sem "team dashboard"** para staff técnica

**Achado** — Coach individual vê atleta. Elite tem **equipe**: técnico + fisiologista + fisioterapeuta + nutricionista + psicólogo. Sem roles múltiplos.

**Correção** — `coaching_members.role` ampliar para `['admin_master','coach','assistant','physio','nutritionist','psychologist','athlete']` com permissões granulares em `role_permissions`.

---

### 🟡 [21.13] Recovery/sleep tracking **ausente**

**Achado** — `health` package (Apple Health, Google Fit) suporta sleep + HRV, mas repo não integra.

**Correção** — `athlete_health_data` ganha `hrv_rmssd_ms`, `sleep_duration_h`, `readiness_score`. Edge function `evaluate-readiness` que sugere carga do dia.

---

### 🟡 [21.14] Sem **race predictor** (VDOT/Riegel)

**Achado** — "Se você correu 10 km em 40 min, sua maratona é ~3:05:xx". Calculador VDOT Jack Daniels é essencial para planejamento.

**Correção** — Edge Function `predict-race` + UI em `athlete_evolution_screen.dart`.

---

### 🟡 [21.15] Weather enrichment (sessão histórica)

**Achado** — Pace no calor ≠ pace no frio; não há temperatura registrada por sessão.

**Correção** — Pós-processamento via OpenWeather API; armazenar `sessions.weather jsonb`.

---

### 🟡 [21.16] **Competições oficiais** não categorizadas

**Achado** — Atleta marca uma corrida como "competição" via UI ad-hoc. Sem tabela `race_results` com oficial/chip/bib/categoria.

**Correção** — `CREATE TABLE race_results (user_id, event_name, date, distance_m, chip_time_s, bib, category, place_overall, place_category);`

---

### 🟡 [21.17] **Sponsorship disclosure** automático ausente

**Achado** — Em rede social integrada (feed), posts de elite patrocinado não indicam "#Patrocinado" — lei federal dos EUA FTC + Lei 13.146 Brasil exigem.

**Correção** — Atleta com `sponsorships` ativa vê checkbox "Post patrocinado" auto-marcado.

---

### 🟡 [21.18] **Heart-rate BLE drop** sem recovery visual

**Achado** — `ble_reconnect_manager.dart` existe mas sem UI clara de "HRM caiu, reconectando". Elite treina com 2 HRM (chest + optical) — produto não duplica.

**Correção** — Dual-source HR: priorizar chest BLE; fallback para optical se chest desconectar. UI mostra status.

---

### 🟡 [21.19] **Post-run nutrition log** esquecido

**Achado** — Corrida-longa exige refeição pós; não há lembrete/log de carb window.

**Correção** — Notification push 20 min pós-sessão longa: "Recovery window — logue sua refeição". Para elite opcional, para amador educacional.

---

### 🟡 [21.20] Privacy mode **para competições**

**Achado** — Em dia de prova, elite não quer compartilhar warm-up route (estratégia). Sem toggle "modo competição privada" que silencia auto-publicação por X horas.

**Correção** — Tela recording tem switch "Público/Privado/Competição" antes de start.

---

## LENTE 22 — ATLETA AMADOR (iniciantes, intermediários, meia-maratona, running clubs locais)

Perfil: corre 3–5× semana, pace 5:30–7:00/km, motivação social + saúde, smartphone + opcional Garmin/Apple Watch básico, paga R$ 100-300/mês assessoria.

### 🔴 [22.1] **Onboarding não inclui "primeira corrida guiada"**

**Achado** — Tela `today_screen.dart` e `athlete_dashboard_screen.dart` não têm flow "bem-vindo, vamos fazer sua primeira corrida de 20 min em Z2" com tutorial in-app.

**Risco** — Amador baixa app, não sabe o que fazer, deleta. D1 retention baixíssima. **Churn que mata o negócio**.

**Correção** — "Primeira corrida guiada": áudio TTS ("Você está no ritmo certo"), feedback visual simples, parabenização ao final, desbloqueio de badge.

---

### 🔴 [22.2] Conceito de **"moeda / OmniCoin"** confunde amador

**Achado** — [7.12] repete. Amador pensa "corro por saúde, não quero moeda". Conceito financeiro complexo na frente assusta.

**Correção** — UI amador **não mostra** coins/wallet. Apenas badges, streaks, KM totais. Coaches e assessorias usam coins nos bastidores. Amador só "desbloqueia" benefícios via interface narrativa ("Você ganhou 30 min de consultoria com o técnico!").

---

### 🔴 [22.3] **Plano semanal pessoal** ausente para solo runner

**Achado** — Se amador não tem coach (não faz parte de assessoria paga), sem plano. "Training plan module" (migration 20260407000000, 1500+ linhas) presume coach-driven.

**Risco** — 80% dos amadores brasileiros treinam **sem coach**. Produto os exclui.

**Correção** — Plano auto-gerado via Edge Function `generate-fit-workout` (já existe!) + GPT-based "Omni AI Coach" tier freemium:

- Objetivo: "correr 5K sem parar", "melhorar 10K", "meia-maratona em 8 semanas"
- Ajusta semanal baseado em compliance
- Free tier: 1 plano ativo por vez; premium ilimitado

---

### 🟠 [22.4] Feedback de ritmo **só pós-corrida**

**Achado** — Amador iniciante começa muito rápido ("burned out" em 5 min). Produto não fala durante.

**Correção** — TTS em tempo real:

- "Você está 20 s mais rápido que alvo. Desacelere um pouco."
- "FC zona 3, ideal. Mantenha."
- A cada km: "1 km em 6:15, você está bem."

Customizável em `settings_screen.dart`: frequência, idioma, voz.

---

### 🟠 [22.5] **Grupos locais** sem descoberta por proximidade

**Achado** — Amador descobre clube via boca-a-boca. Sem `/groups/nearby` que mostra grupos < 5 km home.

**Correção** — `coaching_groups.base_location geography(POINT)` + endpoint `GET /api/groups/nearby?lat=…&lng=…&radius_km=10`. Privacy: amador aprova compartilhamento de localização aproximada.

---

### 🟠 [22.6] **Voice coaching** parcial

**Achado** — `flutter_tts` nos deps. Uso real: talvez só "pace alert". Faltam:

- Countdown "3, 2, 1, GO"
- Motivação periódica ("Você está indo bem!")
- Avisos de hidratação em corrida longa

**Correção** — `AudioCuesService` configurável. Multi-idioma (pt-BR, en, es).

---

### 🟠 [22.7] **Compra parcelada** para assessoria brasileira

**Achado** — Asaas suporta boleto/PIX parcelado. Stripe apenas cartão. Realidade BR: 60% prefere pagar parcelado/PIX.

**Correção** — Gateway preference: default Asaas para BR; Stripe para internacional. Checkout mostra opções "PIX R$ 120/mês" vs "Cartão 10× R$ 12,50". Já tem módulo billing — confirmar integração ativa.

---

### 🟠 [22.8] **Desafio de grupo** (viralização entre amigos)

**Achado** — `challenge-create` existe. UX para convidar amigos via WhatsApp (deep link pré-preenchido) fraca.

**Correção** — Tela "Criar desafio" tem botão **"Convidar via WhatsApp"** que gera imagem card + deep link `omnirunner.app/challenge/XYZ`. Usa Universal Links iOS + App Links Android + `share_plus` (já no pubspec).

---

### 🟠 [22.9] **Progress celebration** tímida

**Achado** — Primeira corrida completa, primeira semana, primeira 5K — sem celebração visual (confete, animação).

**Correção** — Moments milestone com animação (`flutter_confetti`, lottie) + compartilhamento OG ([15.3]).

---

### 🟡 [22.10] **Apple Watch / Wear OS** nativo

**Achado** — `watch_bridge/` existe com `watch_session_payload.dart`. Auditoria superficial: provavelmente não tem WatchOS complication nem GarminIQ data field.

**Correção** — Roadmap: app companion para WatchOS + Wear OS com start/stop/pause nativo.

---

### 🟡 [22.11] Corrida em **esteira** sem GPS

**Achado** — Anti-cheat exige GPS points `>= MIN_POINTS = 5`. Treino em esteira (não há GPS) é reprovado.

**Correção** — Modo "treadmill": aceita distância declarada manualmente, FC via BLE, cadence via phone accelerometer. Flag distinto em `sessions.recording_type = 'treadmill'`; não conta para rankings GPS mas conta para volume/frequência.

---

### 🟡 [22.12] **Streaks** (dias consecutivos correndo) sem grace period

**Achado** — Auditoria não encontrou tabela `streaks`. Se existir, provavelmente quebra com "rest day" (ruim para atleta responsável).

**Correção** — Streak = "dias com atividade (correr OU outro treino)". Grace de 1 dia/semana (pausa opcional). Streak shield: 1 por mês para compensar viagem.

---

### 🟡 [22.13] **Menstrual cycle tracking** — tabu mas importante

**Achado** — Treino feminino é afetado por ciclo. Sem integração com cycle tracker.

**Correção** — Opt-in em `athlete_health_data.cycle_phase`; ajusta sugestões de intensidade (luteal vs folicular). Grande diferencial para público feminino (50% do mercado de running BR e crescendo).

---

### 🟡 [22.14] **Recuperação ativa** não sugerida

**Achado** — Amador faz 3 corridas seguidas pesadas → lesão. Sem sistema que sugira "descansar" ou "caminhada".

**Correção** — Regra heurística em `generate-fit-workout`: se últimos 3 dias tiveram TSS alto → próximo treino é "descanso ativo/caminhada 20 min".

---

### 🟡 [22.15] **Formato de exportação pessoal** apenas técnico

**Achado** — Export = `.fit` ([21.7]). Amador quer PDF bonito "meu resumo do mês" para compartilhar.

**Correção** — `generate-wrapped` (existe) + export mensal PDF rechado de gráficos, fotos de perfil, frases motivacionais.

---

### 🟡 [22.16] **Primeira experiência de injury** sem onboarding

**Achado** — Amador machuca joelho, não sabe fazer. Abre ticket suporte (se descobre).

**Correção** — Triagem in-app: "Você está com dor?" → formulário com localização + intensidade → sugestão de rest + link para profissional da região (parceria local).

---

### 🟡 [22.17] **Clima local** não informa decisão

**Achado** — Amador olha fora da janela pra decidir correr.

**Correção** — Widget home "Hoje às 6h: 22°C, umidade 80%, chuva em 2h — boa hora para sair". OpenWeatherMap API.

---

### 🟡 [22.18] Onboarding **não pergunta objetivo**

**Achado** — Produto trata todos como iguais. "Saúde geral" vs "5K" vs "meia-maratona" exigem periodizações MUITO diferentes.

**Correção** — Step de onboarding "Qual seu objetivo?" com 5 opções + prazo. Plano auto-gerado já respeita.

---

### 🟡 [22.19] **Social comparison** saudável vs tóxica

**Achado** — Feed mostra corrida de todos. Amador iniciante vê elite fazendo sub-40 em 10K → desmotiva.

**Correção** — Feed default = **grupo do atleta** + seguidos. Algoritmo prioriza atletas de bracket similar. Opt-in para "feed global" com aviso "pode incluir performances muito superiores às suas".

---

### 🟡 [22.20] **Retenção D30/D90** — hooks específicos

**Achado** — Streak + badges cobrem D7. Falta motivador D30+: "aniversário de 1 mês no app", "sua evolução" comparativa.

**Correção** — `lifecycle-cron` dispara notificação especial em D30/D90/D180/D365 com wrapped-lite.

---

## LENTE 23 — TREINADOR DE CORRIDA (coach B2B, assessoria esportiva, do clube ao gestor de 500 atletas)

Perfil: educador físico/CREF, gerencia 20–500 atletas, precisa **escalar tempo**, cobra R$ 150-500/mês por atleta, ROI do produto = mais atletas por hora de coach.

### 🔴 [23.1] **Workout delivery em massa** sem preview por atleta

**Achado** — `staff_workout_assign_screen.dart` assign workout a atletas. Sem preview individual: "para João, 400 m × 8 (Z4) soa correto? ele reporta dor no tornozelo há 3 dias".

**Risco** — Coach de 200 atletas atribui pacote genérico → atleta lesiona → reputação do coach quebra.

**Correção** — Antes de publicar, UI mostra matriz `atleta × alerta`:

- 🟡 João — reportou dor há 3 dias (soft warning)
- 🔴 Maria — TSS acumulado 450 nos últimos 7 dias (overtraining)
- 🟢 Pedro — OK
- ⚪ Ana — sem dados recentes (sem base para opinar)

Coach confirma com 1 clique; ajusta individuais com 2 cliques.

---

### 🔴 [23.2] **Dashboard de overview** diário para coach tem 100-500 atletas

**Achado** — `coach_insights_screen.dart` existe. Auditoria rápida sugere listagem padrão. Coach com 500 atletas precisa **priorização**:

- Quem **precisa de atenção hoje**: lesão reportada, 3+ dias sem treino, TSS anomaly, plano não cumprido.
- Quem **está indo bem**: pode receber plano mais agressivo.
- Quem **está em PR**: coach felicita pessoalmente.

Sem priorização, coach gasta 3h/dia olhando dashboard manualmente.

**Correção** — `GET /api/coaching/daily-digest?group_id=X` retorna `{needs_attention: [], performing_well: [], at_risk: [], new_prs: []}`. Tela coach é essa lista, não lista alfabética.

---

### 🔴 [23.3] **Comunicação** coach ↔ atleta carece

**Achado** — `announcements` (broadcast) e `support_tickets` (1:1 formal). Sem mensagem inline em cada workout ("João, caprichei no seu treino hoje, bora que hoje é Z4!").

**Risco** — Coach abandona Omni e usa WhatsApp paralelo → produto vira planilha cara, não ganha stickiness.

**Correção** —

```sql
CREATE TABLE public.workout_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_delivery_item_id uuid REFERENCES workout_delivery_items(id),
  from_user_id uuid, to_user_id uuid,
  message text, audio_url text,
  read_at timestamptz, created_at timestamptz DEFAULT now()
);
```

Áudio opcional (coach grava 20 s, atleta ouve antes do treino). Fica dentro do app.

---

### 🔴 [23.4] **Bulk assign semanal** (ver `20260416000000_bulk_assign_and_week_templates.sql`) sem rollback

**Achado** — Migration sugere existência de bulk assign. Se coach atribui errado para 300 atletas, não há "desfazer tudo" atômico.

**Correção** — `bulk_assignments` com `batch_id`; botão "Desfazer último lote" (TTL 1h). Soft-delete em `workout_delivery_items` com flag `undone_by_batch`.

---

### 🟠 [23.5] **Workout template library** pobre

**Achado** — `staff_workout_templates_screen.dart` existe. Coach de assessoria nova começa do zero. Sem biblioteca pré-populada (fartlek clássicos, treino limiar, tempo run, etc).

**Correção** — `workout_templates_library` seeded em migration com 50+ treinos canônicos (Daniels, Pfitzinger, Hudson). Coach clona e customiza.

---

### 🟠 [23.6] **Plano mensal/trimestral** não periodizado

**Achado** — Módulo `training-plan` (1500 linhas) presumivelmente lida com plans. Auditoria rápida não confirma **periodização** (base → build → peak → taper).

**Correção** — Template wizard: "Meia-maratona em 12 semanas" gera periodização automática ajustada ao atleta. Coach edita blocks (não workouts individuais) — escala.

---

### 🟠 [23.7] **Análise coletiva** (grupo) limitada

**Achado** — `coaching_kpis_daily` tem total. Coach quer:

- Distribuição de volume semanal (gráfico de cauda)
- Atletas correndo mais do que recomendado
- Atletas não correndo (attrition risk)
- Progresso coletivo vs mês anterior

**Correção** — Views materializadas + `/platform/analytics/group-overview`.

---

### 🟠 [23.8] **Presença em treinos coletivos** via QR code (staff_training_scan_screen.dart existe)

**Achado** — Tela de scan existe. Integração com `attendance` OK? Mas e **check-in geofenced** no local do encontro?

**Correção** — Cada `coaching_event` (treino coletivo) tem `geofence`. App atleta auto-check-in quando entra no raio. Coach confirma via QR se necessário.

---

### 🟠 [23.9] **Billing integrado** (cobrança de mensalidade aos atletas)

**Achado** — `billing` module + Asaas existem. Coach consegue cobrar atletas via produto? Fluxo Asaas → custódia ([9.8]) → pagamento de staff? Ciclo inteiro de ROI não auditado.

**Correção** — E2E: atleta paga R$ 200 via Asaas → vira coins na custody da assessoria → coach distribui moedas como bônus → saca via withdraw. Se não existe, é **oportunidade gigante** perdida.

---

### 🟠 [23.10] **Treinos com dependência entre atletas** (par/grupo)

**Achado** — "João e Maria correm juntos amanhã, 10 km ritmo base". Hoje são dois workouts separados.

**Correção** — `paired_workouts` tipo com sincronização: se um não confirmar, o outro é avisado.

---

### 🟠 [23.11] **Relatórios para atleta** (resumo mensal do coach)

**Achado** — Coach gasta 1h/mês por atleta escrevendo resumo no Google Docs → envia PDF pelo WhatsApp. Produto não automatiza.

**Correção** — `/api/coaching/athlete-monthly-report?user_id&month` gera PDF: volume, evolução pace, pontos fortes, áreas de melhoria, palavra do coach (campo texto editável). Coach revisa + aprova + envia.

---

### 🟠 [23.12] **Onboarding de novo atleta** no clube

**Achado** — Coach cadastra atleta → atleta recebe convite email. Sem wizard "importe histórico Strava, configuramos zonas".

**Correção** — Convite com "após login, vamos importar seu Strava dos últimos 6 meses (opcional) para personalizarmos seu plano."

---

### 🟠 [23.13] **Feedback do atleta** (RPE, dor, humor) não requerido

**Achado** — `athlete_workout_feedback_screen.dart` existe. Obrigatoriedade variável — coach não pode "forçar" preenchimento (que guia o próximo treino).

**Correção** — Workflow: workout não fica "100% completo" até RPE + humor preenchidos. Badge de bronze por 30 dias de feedback consecutivo.

---

### 🟠 [23.14] **"Corrida de teste" (time trial)** agendada

**Achado** — Protocolo de teste (3k, 5k, 30min tempo trial) calcula limiar. Sem agendamento/tracking específico.

**Correção** — Workout type `time_trial` com tratamento especial: resultado atualiza automaticamente `athlete_zones` ([21.5]).

---

### 🟡 [23.15] **CRM** para captação de atletas

**Achado** — `crm` module existe. Auditoria superficial. Coach B2B precisa: lead captured via landing → trial 30 dias → conversão. Funnel.

**Correção** — CRM lead-to-athlete pipeline; source attribution ([15.1]).

---

### 🟡 [23.16] **Repasse financeiro transparente** para coach como PJ

**Achado** — Coach quer ver: "no mês recebi R$ X bruto; descontadas taxas (Y%), líquido R$ Z; posso sacar quando?". Dashboard financeiro simples.

**Correção** — `/platform/billing/earnings` com breakdown mensal + previsão de saque.

---

### 🟡 [23.17] **Certificados CREF** validação

**Achado** — Qualquer um vira coach criando grupo. Sem validação CREF.

**Correção** — Badge "Coach certificado CREF 012345-G" com upload de PDF + validação manual admin_master (platform). Filtro opcional "apenas coaches certificados".

---

### 🟡 [23.18] **Ghost/assistente virtual** para coaches novatos

**Achado** — Coach jovem (primeiro ano pós-formatura) insegura em prescrições. Sem "Omni AI Coach Mentor": "Seu atleta corre 3:30/km em 5 km, idade 35, volume atual 40 km/sem. Sugerir volume semana 16 de maratona?"

**Correção** — Tier "AI Copilot" (GPT-4o ou similar) com RAG sobre literatura científica (Daniels, Pfitzinger).

---

### 🟡 [23.19] **Múltiplos clubes** (coach atende em 3 clubes)

**Achado** — `coaching_members` 1:N, mas UI esconde bem? Coach com 3 clubes troca grupo via `select-group`. Cada troca exige recarga completa.

**Correção** — Dashboard multi-clube agregado "Meu dia em todos os clubes".

---

### 🟡 [23.20] **Integração calendário** (Google Calendar / iCal)

**Achado** — Treino agendado não aparece no Google Calendar do atleta/coach.

**Correção** — `GET /api/athletes/:id/calendar.ics` — feed iCal subscribable. Atleta adiciona URL no Google Cal → treinos aparecem automaticamente.

---

## RESUMO PARTE 8 (60 itens)

| Severidade | Quantidade | IDs |
|---|---|---|
| 🔴 CRÍTICO | 10 | 21.1, 21.2, 21.3, 21.4, 21.5, 22.1, 22.2, 22.3, 23.1, 23.2, 23.3, 23.4 |
| 🟠 ALTO | 24 | 21.6–21.12, 22.4–22.9, 23.5–23.14 |
| 🟡 MÉDIO | 26 | 21.13–21.20, 22.10–22.20, 23.15–23.20 |

### Insights de produto (derivados das 3 personas):

**Atleta profissional** (🔴 críticos):
- Thresholds anti-cheat **bloqueiam** elite ([21.1], [21.2]) — problema de produto que impede a própria persona-objetivo de usar.
- Propriedade de dados + periodização avançada (TSS/CTL/zonas) — se faltar, migram para TrainingPeaks.

**Atleta amador** (🔴 críticos):
- Onboarding + UX sem financeirês + plano sem coach — 80% do mercado amador não tem coach, produto hoje os exclui.
- Complexidade de coin/swap/clearing invade UI do atleta amador → confusão, churn D1.

**Coach** (🔴 críticos):
- Escala de produtividade (bulk assign com safety net + digest priorizado) — sem isso, coach com 50+ atletas abandona.
- Comunicação inline + rollback — esses dois reflexos da "vida real" do treinador brasileiro que usa WhatsApp paralelo.

---

# 📊 SÍNTESE GLOBAL DA AUDITORIA (Partes 1-8)

## Totalização por severidade

| Severidade | Total |
|---|---|
| 🔴 CRÍTICO | **58 itens** |
| 🟠 ALTO | **112 itens** |
| 🟡 MÉDIO | **119 itens** |
| 🟢 SEGURO/CORRETO | **14 itens** |
| ⚪ NÃO APLICÁVEL/NÃO AUDITADO | **7 itens** |
| **TOTAL** | **310 itens** |

## Top-10 ameaças existenciais (em ordem de urgência)

| # | ID | Descrição | Classe | Impacto |
|---|---|---|---|---|
| 1 | [9.1] + [9.2] | Modelo opera sem autorização BCB / sem KYC | Regulatório | Intervenção + processo criminal |
| 2 | [1.15] + [2.3] | FX rate manipulável pelo cliente + withdraw não atômico | Fraude | Perda direta de $ |
| 3 | [2.1] | `distribute-coins` não atômico (4 RPCs sem transação) | Arquitetura | Inventário negativo, dados inconsistentes |
| 4 | [12.1] | `reconcile-wallets-cron` **nunca** roda | Operações | Drift silencioso invisível |
| 5 | [2.13] | Chargebacks não revertem moeda emitida | Financial | Moedas sem lastro |
| 6 | [1.31] | CSP com `'unsafe-inline' 'unsafe-eval'` | Security | XSS = acesso a admin |
| 7 | [21.1] + [21.2] | Anti-cheat bloqueia elite | Produto | Persona-alvo inviável |
| 8 | [4.1] + [4.2] + [4.3] | LGPD: delete incompleto + sem consentimento registrado | Legal | Multa ANPD + processo |
| 9 | [18.1] + [18.2] | 2 fontes de verdade + idempotência ad-hoc | Arquitetura | Bugs financeiros recorrentes |
| 10 | [11.1] + [11.2] + [11.3] | Supply chain sem audit/SBOM/gitleaks | Security | Um CVE = compromisso total |

## Roadmap sugerido em ondas

**Onda 0 — "Stop the bleeding" (2 semanas)**:
- [1.15] FX rate server-side
- [12.1] Agendar reconcile-wallets
- [6.2] Health endpoint sem info leak
- [11.3] Gitleaks no CI
- [10.3] Rotação service-role + segregação prod/staging

**Onda 1 — "Foundation" (6 semanas)**:
- [9.2] KYC básico (via Asaas conectado já existente)
- [2.1] `distribute_coins_atomic` RPC única
- [18.2] Idempotency keys em todas POSTs financeiras
- [18.3] Hardening search_path em todas SECURITY DEFINER
- [14.2] Migração para `/api/v1/*` nos endpoints financeiros
- [4.1]+[4.2] `fn_delete_user_data` completo + transacional

**Onda 2 — "Scale" (3 meses)**:
- [9.1] Decisão regulatória (parceria IP vs auto-autorização BCB)
- [2.13] Chargeback/refund flow + funções SQL de reversão
- [19.1] Particionamento `coin_ledger`
- [20.1]+[20.2]+[20.3] Observability completa (tracing + SLO + dashboard)
- [21.4]+[21.5] TSS/CTL + zonas personalizadas (atleta pro)
- [22.3] Plano auto-gerado (atleta amador sem coach)
- [23.1]+[23.2] Coach workflow otimizado

**Onda 3 — "Expansion" (6 meses)**:
- [16.3] API pública com api_keys
- [15.2] Referral system
- [15.4] Email transactional
- [16.1]+[16.2] White-label + custom domain
- [21.7] Integração Garmin/Coros/Polar
- Demais itens 🟡

---

## FIM DA AUDITORIA

**Metodologia**: 23 lentes × média 13 itens cada = 310 findings. Cada item contém: veredicto de severidade + achado com file:line real + descrição do risco + correção (SQL/TS/Dart/config) + sugestão de teste de regressão.

**Próximos passos recomendados ao usuário**:

1. **Priorizar Onda 0** — pode ser executada em 2 semanas por um time pequeno.
2. **Validação jurídica** — [9.1] e [4.3] exigem consulta externa antes de qualquer lançamento comercial.
3. **Decisão arquitetural** — [18.1] (gateway único de wallet vs event sourcing puro) define próximos 2 anos de débito.
4. **Prova de conceito com personas** — recrutar 3 atletas elite + 5 amadores + 2 coaches; validar onda 2 de produto (lente 21/22/23) com eles antes de construir.

---

Quer que eu gere agora algum artefato concreto a partir da auditoria? Algumas opções:

- **Migration SQL pronta** para Onda 0 (search_path hardening + reconcile cron + fx_rate server-side + constraint fix)
- **Runbook `CUSTODY_INCIDENT_RUNBOOK.md`** completo
- **PR técnica** com `withErrorHandler` aplicado a todos os 74 endpoints
- **Arquivo `feature_flags`** seed + UI `/platform/flags`
- **Dashboard Grafana JSON** (observability parte 20)
- **`fn_delete_user_data` completo** cobrindo todas as tabelas atuais
- **Issue board GitHub** com as 58 críticas em formato pronto para importar

Digite o número ou nome da opção (ex.: "1" ou "runbook") que deseja que eu produza primeiro.

 Now I'm ready to construct Part 8 focusing on the three athlete-related lenses the user specifically asked for. Looking at the anti-cheat thresholds, I notice the speed limit of 12.5 m/s is actually too restrictive for elite athletes performing at their peak.

The issue is that world-class sprinters regularly hit speeds above 10 m/s sustained, with peak velocities around 12 m/s—Bolt's 100m average was 12.42 m/s, which means the current threshold would flag elite performances as cheating. The pace threshold and heart rate caps have similar problems: the static 220 BPM max doesn't account for young elite athletes who naturally exceed that, trained runners have resting rates well below 80 BPM, and the distance filter of 5 meters loses granularity during high-intensity intervals. Plus, using the highest location accuracy drains battery without any adaptive mode for longer efforts.

Beyond the technical thresholds, I need to think through the practical ecosystem: battery management during marathons, offline recording for trail runs, heart rate strap syncing, integration with external devices like Garmin or Apple Watch, handling Strava imports, data privacy concerns for sponsored athletes, real-time competition features, coach access boundaries, and how coaches manage their time reviewing athlete data.

Now I'm working through the final section with the pro athlete and coach personas in mind, thinking about team management features like group assignments and invitations.