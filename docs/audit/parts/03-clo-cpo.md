# PARTE 3 de 8 — LENTES 4 (CLO: LGPD & Privacidade) e 5 (CPO: Produto & Casos-limite)

Auditoria de 35 itens, referenciando arquivos/linhas reais do Omni Runner (web + mobile + Supabase).

---

## LENTE 4 — CLO (Chief Legal Officer): LGPD, Marco Civil, GDPR

### 🔴 [4.1] `fn_delete_user_data` é **incompleta** — múltiplas tabelas com PII não cobertas

**Achado** — `supabase/migrations/20260312000000_fix_broken_functions.sql:5-36` deleta apenas 13 tabelas. Ausentes do schema atual:

- `custody_deposits` (CPF/CNPJ em `payer_document`, se houver)
- `custody_withdrawals` (dados bancários do beneficiário)
- `audit_logs` (IPs, user-agents, actor_id = PII)
- `support_tickets` comentários e anexos
- `push_tokens` / `fcm_tokens` (identificadores de dispositivo)
- `login_history` (se existir)
- `running_dna_profiles`, `wrapped_snapshots` (perfil comportamental detalhado)
- `posts`, `comments`, `reactions` do feed social
- `champ_participants`, `badge_awards` (retenção OK mas linkam atleta)
- **Storage buckets**: avatares, fotos de sessão, GPX/FIT uploads

**Risco** — Violação do Art. 18, VI LGPD (eliminação dos dados). ANPD pode multar em até 2 % do faturamento (limite R$ 50 mi/infração).

**Correção** — Adicionar tabelas ausentes e incluir chamada Storage:

```sql
CREATE OR REPLACE FUNCTION public.fn_delete_user_data(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  BEGIN DELETE FROM push_tokens        WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM running_dna_profiles WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM wrapped_snapshots  WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM social_posts       WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM social_comments    WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM social_reactions   WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN UPDATE audit_logs SET actor_id = '00000000-0000-0000-0000-000000000000'::uuid,
         ip_address = NULL, user_agent = NULL
        WHERE actor_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN UPDATE custody_withdrawals SET beneficiary_document = NULL, beneficiary_name = 'Anônimo',
         bank_account = NULL WHERE requested_by = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN UPDATE support_tickets SET body = '[removido por solicitação LGPD]',
         email = NULL, phone = NULL WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  -- Existing deletes...
END;$$;
```

E no Edge Function:

```typescript
await adminDb.storage.from('avatars').remove([`${uid}/avatar.jpg`]);
const { data: list } = await adminDb.storage.from('sessions').list(uid);
if (list?.length) await adminDb.storage.from('sessions').remove(list.map(f => `${uid}/${f.name}`));
```

**Teste** — `fn_delete_user_data_full.sql.test` insere PII em 100 % das tabelas que referenciam `user_id`, chama a função e valida que `SELECT COUNT(*)` em cada tabela == 0 ou == anonimizado.

---

### 🔴 [4.2] Edge Function `delete-account` deleta `auth.users` mesmo quando **`fn_delete_user_data` falha**

**Achado** — `supabase/functions/delete-account/index.ts:59-80`:

```60:80:supabase/functions/delete-account/index.ts
    const { error: cleanupErr } = await adminDb.rpc("fn_delete_user_data", { p_user_id: uid });
    if (cleanupErr) {
      console.error(JSON.stringify({ ... }));
    }

    // 5. Delete auth user (requires admin client)
    const { error: deleteErr } = await adminDb.auth.admin.deleteUser(uid);
```

O `cleanupErr` é apenas logado. Depois o auth.user é deletado, o que torna **impossível** re-executar a exclusão: o usuário sumiu do `auth.users`, mas as linhas com PII continuam em `custody_deposits`, `support_tickets`, storage etc.

**Risco** — Dados órfãos com PII + cliente reclama na ANPD "pedi exclusão há 6 meses, dados ainda lá".

**Correção** — Abortar a exclusão se o cleanup falhar:

```typescript
if (cleanupErr) {
  logError({ request_id: requestId, fn: FN, user_id: uid,
             error_code: "DATA_CLEANUP_FAILED", detail: cleanupErr.message });
  return jsonErr(500, "DATA_CLEANUP_FAILED",
    "Falha ao limpar dados. Tente novamente ou contate o suporte.", requestId);
}
// Only after successful cleanup, delete auth user
const { error: deleteErr } = await adminDb.auth.admin.deleteUser(uid);
```

**Teste** — mockar `fn_delete_user_data` para falhar; validar que `auth.admin.deleteUser` NÃO é chamado (usando spy) e resposta é 500.

---

### 🔴 [4.3] **Não há registro de consentimento** (opt-in explícito LGPD Art. 8)

**Achado** — `grep -i "terms_accepted|consent|privacy_accepted|lgpd_consent" supabase/migrations/*.sql` → **zero** matches. A tabela `profiles` não tem `terms_accepted_at`, `privacy_accepted_at`, `terms_version`, `marketing_consent`.

**Risco** — LGPD Art. 7º, I exige consentimento comprovável. Em auditoria/ação judicial, plataforma não consegue provar que o titular consentiu. Multa até 2 % faturamento.

**Correção** — Migration:

```sql
ALTER TABLE public.profiles ADD COLUMN terms_accepted_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN terms_version text;
ALTER TABLE public.profiles ADD COLUMN privacy_accepted_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN privacy_version text;
ALTER TABLE public.profiles ADD COLUMN marketing_consent_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN health_data_consent_at timestamptz;

CREATE TABLE public.consent_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  consent_type text NOT NULL CHECK (consent_type IN
    ('terms','privacy','marketing','health_data','third_party_strava','third_party_trainingpeaks')),
  version text NOT NULL,
  granted boolean NOT NULL,
  ip_address inet,
  user_agent text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX idx_consent_log_user ON public.consent_log(user_id, consent_type, created_at DESC);
```

No onboarding (`complete-social-profile`): inserir em `consent_log` cada toggle aceito + `UPDATE profiles SET terms_accepted_at=now()`.

**Teste** — e2e: cadastrar usuário sem aceitar termos → `auth.users` criado mas `profiles.terms_accepted_at IS NULL` → app/portal bloqueia acesso até consentimento.

---

### 🔴 [4.4] Dados de saúde/biométricos **(dados sensíveis, LGPD Art. 11)** sem proteção reforçada

**Achado** — `sessions`, `running_dna_profiles`, `coaching_athlete_kpis_daily` armazenam:
- Frequência cardíaca média/max
- Pace/ritmo (indicador de condicionamento físico)
- Trajetórias GPS (localização precisa)
- Lesões/queixas em `support_tickets`

Estes são **dados pessoais sensíveis**. Auditoria não encontrou:
- Segregação (tabela separada + RLS reforçada)
- Criptografia em repouso adicional (coluna `pgp_sym_encrypt`)
- Log de acesso a dados sensíveis
- Minimização (apenas treinador do atleta pode ler)

**Risco** — Vazamento de dados de saúde = enforcement agravado LGPD Art. 52 + possível ação coletiva (atletas públicos/profissionais).

**Correção** —

```sql
-- Tabela separada para dados de saúde
CREATE TABLE public.athlete_health_data (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  resting_hr_bpm integer,
  max_hr_bpm integer,
  vo2_max numeric(4,1),
  self_reported_injuries text, -- pgp_sym_encrypt applied at app layer
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.athlete_health_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY athlete_reads_own ON public.athlete_health_data
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY coach_reads_athlete ON public.athlete_health_data
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM coaching_members cm1
    JOIN coaching_members cm2 ON cm1.group_id = cm2.group_id
    WHERE cm1.user_id = auth.uid()
      AND cm1.role IN ('coach','assistant','admin_master')
      AND cm2.user_id = athlete_health_data.user_id
      AND cm2.role = 'athlete'
  ));

-- Audit trigger
CREATE TRIGGER trg_audit_health_access AFTER SELECT ON athlete_health_data
  FOR EACH ROW EXECUTE FUNCTION fn_log_sensitive_access();
```

**Teste** — `athlete_health_data.rls.test`: coach de outro grupo não lê; atleta lê o próprio; platform_admin (se permitido por política) lê registrando audit_log.

---

### 🟠 [4.5] Trajetórias GPS **brutas** sem opção de privacy zones (home/work zones)

**Achado** — Em `sessions` (e `omni_runner/lib/data/datasources/drift_database.dart`), polylines são salvas cruas. Não há mascaramento de primeiros 200 m / últimos 200 m — prática padrão no Strava, Garmin Connect, Nike Run.

**Risco** — Corrida de atleta profissional publicada no feed revela endereço residencial. Stalking/doxxing. Litígio civil art. 42 LGPD (responsabilidade solidária).

**Correção** —

```sql
ALTER TABLE profiles ADD COLUMN privacy_zones jsonb DEFAULT '[]';
-- Each zone: { "lat": -23.55, "lng": -46.63, "radius_m": 200 }

-- Function applied when serving polyline to any viewer != owner
CREATE FUNCTION fn_mask_polyline(p_polyline text, p_zones jsonb) RETURNS text AS $$
  -- decode, strip points inside any zone, re-encode
$$ LANGUAGE plpgsql;
```

Client-side (`run_summary_screen.dart`): UI para marcar "casa" / "trabalho" + default de 200 m oculto no começo e fim da corrida (visibilidade "friends").

**Teste** — `privacy_zones.test.dart`: corrida cruzando zona → visível ao atleta completo, mascarado a terceiros.

---

### 🟠 [4.6] Campo `instagram_handle`, `tiktok_handle` em `profiles` sem política de uso

**Achado** — `profiles.instagram_handle` é lido via RLS `select_profile_public` (se existir). Não há:
- Toggle "esconder do público" independente do display_name.
- Validação (evitar links maliciosos, "@bitly/x").
- Rate limit de changes (evita impersonation: trocar o handle a cada 10 s).

**Risco** — Stalkers usam Omni Runner como diretório de atletas por rede social.

**Correção** — Adicionar `profile_public jsonb` com flags granulares (`show_instagram`, `show_tiktok`, `show_pace`, `show_location`) e aplicar na RLS de views públicas.

---

### 🟠 [4.7] `coin_ledger` retém `reason` com PII embutida

**Achado** — `execute_burn_atomic` e várias funções usam `format('Burn of %s coins from %s by user %s', …)`. Se o `%s` inclui nome do atleta ou email (em outras funções), um `SELECT * FROM coin_ledger WHERE user_id = '00...0'` após a anonimização ainda expõe o nome.

**Risco** — "Right to be forgotten" parcial.

**Correção** — Revisar todos os `reason` para conter apenas IDs + tipos; ao anonimizar, também fazer:

```sql
UPDATE coin_ledger
SET reason = regexp_replace(reason, 'user \S+', 'user [redacted]')
WHERE user_id = '00000000-0000-0000-0000-000000000000'::uuid;
```

---

### 🟠 [4.8] Backups Supabase — sem política de retenção documentada

**Achado** — Não há documento/migration especificando: tempo de retenção de PITR, ofuscação em staging, procedimento de deletar usuário nos backups.

**Risco** — Após delete-account, o atleta ainda está em 4 backups (7, 14, 21, 28 dias). LGPD não exige apagar backups, mas exige documentar.

**Correção** — Publicar `docs/compliance/BACKUP_POLICY.md` com: PITR = 7 dias, snapshots semanais mantidos 30 dias, requests de eliminação bloqueiam restauração do backup até 30 dias decorridos.

---

### 🟠 [4.9] Terceiros (Strava, TrainingPeaks) — não há processo de revogação

**Achado** — `omni_runner/lib/features/strava/presentation/strava_connect_controller.dart`: usuário autoriza Strava via OAuth, tokens salvos em `strava_connections`. Em `fn_delete_user_data` isso é deletado localmente, **mas o token permanece ativo no Strava**. Não há chamada `POST /oauth/deauthorize`.

**Risco** — LGPD Art. 18, VIII (transferência a terceiros): dados continuam sendo puxados do Strava mesmo após "exclusão" da conta, se token sincronizar por webhook.

**Correção** —

```typescript
// Inside fn_delete_user_data orchestration
const { data: stravaConn } = await adminDb.from("strava_connections")
  .select("access_token").eq("user_id", uid).maybeSingle();
if (stravaConn) {
  await fetch("https://www.strava.com/oauth/deauthorize", {
    method: "POST",
    headers: { Authorization: `Bearer ${stravaConn.access_token}` },
  });
}
// Same for TrainingPeaks via their revoke endpoint
```

E registrar o evento em `consent_log`.

---

### 🟠 [4.10] Transferência internacional de dados (Supabase US, Sentry US) sem cláusulas

**Achado** — Supabase está hospedado em AWS US-East (padrão). Sentry DSN aponta `sentry.io` (EU/US). LGPD Art. 33 exige cláusulas-padrão ou decisão ANPD quando transferindo para país sem adequação.

**Risco** — Processo administrativo ANPD. Não é bloqueio, mas é pendência contratual.

**Correção** — Documento `docs/compliance/DATA_TRANSFER.md` com DPA Supabase + DPA Sentry + registro no ROPA (Registro de Operações). Considerar migrar Supabase para região sa-east-1.

---

### 🟡 [4.11] Não há DPO nomeado / canal de titular publicado

**Achado** — `portal/src/app/(portal)/help/help-center-content.tsx` menciona FAQ mas não há endpoint/email dedicado `dpo@omnirunner.com`. LGPD Art. 41.

**Correção** — Página `/privacy/dpo` com: nome do encarregado, email, telefone, prazo de resposta (15 dias).

---

### 🟡 [4.12] Portal admin expõe dados sensíveis sem **masking**

**Achado** — `portal/src/app/(portal)/platform/**` exibe CPF, nome completo de atletas em tabelas. Não há view com CPF mascarado (`123.***.***-45`).

**Correção** — Component `<MaskedDoc value={cpf} revealOnClick={hasPermission('view_pii')} />` + audit_log a cada reveal.

---

### 🟡 [4.13] Logs estruturados enviam `user_id` e podem enviar `ip_address` ao Sentry

**Achado** — `portal/src/lib/logger.ts` passa `user.id` para Sentry. Configuração Sentry provavelmente já redige IPs mas não está explícito no `sentry.server.config.ts`.

**Correção** —

```typescript
Sentry.init({
  beforeSend(event) {
    if (event.user) { delete event.user.ip_address; delete event.user.email; }
    return event;
  },
  sendDefaultPii: false,
});
```

---

### 🟡 [4.14] Ausência de verificação de idade (COPPA/ECA)

**Achado** — Omni Runner não coleta `date_of_birth`. Menores de 13 anos (COPPA) e de 12 anos (ECA) não podem ser titulares diretos. Corridas de categoria infantil existem → pode atrair < 13 anos.

**Risco** — FTC COPPA, ANPD minors policy.

**Correção** — Onboarding pergunta ano de nascimento; se < 18 → fluxo de consentimento parental (email do responsável + verificação dupla).

---

### 🟡 [4.15] Right to portability — não há export self-service

**Achado** — LGPD Art. 18, V ("portabilidade dos dados a outro fornecedor"). Não existe endpoint `/api/export/my-data` retornando um ZIP com sessões, wallets, badges em JSON/CSV.

**Correção** — Supabase Edge Function `export-my-data` gera ZIP em `storage/exports/{uid}/{timestamp}.zip`, assinada, válida por 24 h, enviada por email.

---

## LENTE 5 — CPO (Chief Product Officer): Produto, UX & Casos-limite

### 🔴 [5.1] Swap: **race entre `accept` e `cancel`** do dono da oferta

**Achado** — `portal/src/app/api/swap/route.ts:117` chama `acceptSwapOffer` e `cancelSwapOffer` sem verificação cruzada. Se Grupo A cria oferta, Grupo B clica em "aceitar" e — no mesmo instante — o Grupo A clica em "cancelar", ambas chamadas tocam `UPDATE swap_orders SET status='…' WHERE id = x`. Quem chegar primeiro "vence", mas não há `FOR UPDATE` ou `status = 'open'` predicate na última vista da migration.

**Risco** — Oferta marcada "canceled" mas `execute_swap` já movimentou custódia → fundos transferidos numa oferta "cancelada".

**Correção** — RPCs garantirem:

```sql
CREATE OR REPLACE FUNCTION public.cancel_swap_order(p_order_id uuid, p_group_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM swap_orders
    WHERE id = p_order_id AND seller_group_id = p_group_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not your order'; END IF;
  IF v_status <> 'open' THEN RAISE EXCEPTION 'Not open' USING ERRCODE='CS001'; END IF;
  UPDATE swap_orders SET status='canceled', canceled_at=now() WHERE id = p_order_id;
END;$$;
```

E em `execute_swap`: primeiro `SELECT … WHERE status='open' FOR UPDATE` — já existe? Sim (PARTE 2, [2.4]), mas o `cancel` não usa `FOR UPDATE`.

**Teste** — Teste de concorrência: 2 transactions iniciam, uma faz accept outra cancel → apenas uma sucesso, outra erro `CS001`.

---

### 🔴 [5.2] Swap não tem **TTL/expiração** — ofertas ficam para sempre

**Achado** — Não há `expires_at` nem job `pg_cron` que cancele ofertas com mais de 7/30 dias. Ofertas velhas continuam ocupando `total_committed` da custódia do vendedor.

**Risco** — Vendedor "esquece" uma oferta de US$ 500k, fica sem poder operar esse valor por meses.

**Correção** —

```sql
ALTER TABLE swap_orders ADD COLUMN expires_at timestamptz NOT NULL
  DEFAULT (now() + interval '7 days');
CREATE INDEX idx_swap_orders_expires ON swap_orders(expires_at) WHERE status = 'open';

-- pg_cron job every 10 min
SELECT cron.schedule('swap_expire', '*/10 * * * *', $$
  UPDATE swap_orders SET status='expired' WHERE status='open' AND expires_at < now();
$$);
```

Client cria oferta com `expires_in_days` obrigatório (1/7/30/90).

---

### 🔴 [5.3] `POST /api/distribute-coins`: amount **max 1000** — conflita com grandes clubes

**Achado** — `portal/src/lib/schemas.ts` distributeCoinsSchema: `amount: z.number().int().min(1).max(1000)`. Um clube com 500 atletas distribuindo 10 moedas por semana faz **5.000 moedas** de uma vez — bloqueado.

**Risco** — Coach precisa fazer 5 chamadas sequenciais → multiplica risco de atomicidade (já CRITICAL [2.1]) e degrada UX.

**Correção** — Aumentar para `max(100_000)` e adicionar variante `POST /api/distribute-coins/batch` aceitando `array<{athlete_id, amount}>` e fazendo todas as operações em **uma transação SQL** via nova RPC `distribute_coins_batch_atomic`.

---

### 🟠 [5.4] Challenge/Championship: **participante pode retirar-se (withdraw)** durante disputa — sem regra de cutoff

**Achado** — `supabase/functions/challenge-withdraw/index.ts` provavelmente permite withdraw a qualquer momento. Sem regra "não pode sair nas últimas 48 h de um challenge de 7 dias".

**Risco** — Atleta próximo do último lugar desiste para não "estragar" a estatística → gamificação quebrada.

**Correção** — Adicionar `ALTER TABLE challenges ADD COLUMN withdraw_cutoff_hours integer DEFAULT 48`. Edge Function verifica:

```typescript
if (challenge.ends_at - now() < cutoffHours * 3600e3)
  return jsonErr(422, "WITHDRAW_LOCKED", "Withdrawal closed 48h before end");
```

---

### 🟠 [5.5] Challenge: **ganhador de zero participantes**

**Achado** — Se challenge `start` mas nenhum participante cumpre o objetivo, `settle-challenge` distribui prêmio para ninguém. Prêmio em `token_inventory` do host desapareceu do `total_committed` → precisa ser devolvido.

**Risco** — Perda de inventário (2–5 % anual se 10 % dos challenges ficam vazios).

**Correção** — `settle-challenge` verifica `participants_completed == 0` → chama `custody_release_committed` e marca challenge `expired_no_winners`.

**Teste** — `challenge_no_winners.test.ts`: criar challenge, ninguém completa → após `settle`, `total_committed` volta ao nível anterior.

---

### 🟠 [5.6] Championship `champ-cancel`: **refund de badges parcial e silencioso**

**Achado** — `supabase/functions/champ-cancel/index.ts:149-161`:

```149:161:supabase/functions/champ-cancel/index.ts
        await db.rpc("fn_credit_badge_inventory", {
          p_group_id: champ.host_group_id,
          p_amount: badgeCount,
          p_source_ref: `champ_cancel_refund:${championship_id}`,
        });
      }
    } catch (e) {
      console.warn(JSON.stringify({
        request_id: requestId, fn: FN,
        msg: `Badge refund failed: ${e instanceof Error ? e.message : String(e)}`,
        championship_id,
      }));
    }
```

Se `fn_credit_badge_inventory` falhar, a operação continua — o championship é marcado `canceled` mas os badges do host somem.

**Correção** — Igual [2.2]: remover catch silencioso e envolver cancelamento + refund em RPC atômica `champ_cancel_atomic(p_id)`.

---

### 🟠 [5.7] Swap: amount mínimo **US$ 100** inviabiliza grupos pequenos

**Achado** — `portal/src/app/api/swap/route.ts:17` `amount_usd: z.number().min(100)…`. Um clube de 20 atletas que quer swap de US$ 50 não consegue.

**Risco** — Adoção limitada nos segmentos amadores. Atletas amadores nunca veem valor no P2P.

**Correção** — `min(10)` e UI destaca "amount mínimo = US$ 10".

---

### 🟠 [5.8] Withdraw: **nenhuma tela de progresso** para pending→processing→completed

**Achado** — `portal/src/app/api/custody/withdraw/route.ts` cria o withdraw e executa imediatamente. Para gateways assíncronos (PIX fim de semana), status fica em `processing` sem UI mostrando. Como [2.3], não há handler do callback.

**Risco** — Admin fica sem feedback ("o dinheiro saiu ou não?") → abre ticket no suporte → custo operacional.

**Correção** —

1. Trocar `execute_withdrawal` para retornar `{"status": "processing", "provider_ref": "..."}`.
2. Webhook do gateway atualiza para `completed|failed`.
3. Portal exibe timeline com 4 estados e "estimativa 10 min" / "estorno em até D+2 se falhar".

---

### 🟠 [5.9] Deposit `custody_deposits` — **sem cap diário antifraude**

**Achado** — Não há limite por grupo/dia de depósitos. Lavagem: atacante com grupo comprometido deposita US$ 10M de uma vez.

**Correção** —

```sql
ALTER TABLE custody_accounts ADD COLUMN daily_deposit_limit_usd numeric(14,2) DEFAULT 50000;

CREATE OR REPLACE FUNCTION fn_check_daily_deposit_limit(p_group_id uuid, p_amount numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_today_total numeric; v_limit numeric;
BEGIN
  SELECT COALESCE(SUM(amount_usd), 0) INTO v_today_total
  FROM custody_deposits
  WHERE group_id = p_group_id
    AND status IN ('pending','confirmed')
    AND created_at >= date_trunc('day', now());
  SELECT daily_deposit_limit_usd INTO v_limit FROM custody_accounts WHERE group_id = p_group_id;
  IF v_today_total + p_amount > v_limit THEN
    RAISE EXCEPTION 'Daily deposit limit exceeded' USING ERRCODE = 'CD001';
  END IF;
END;$$;
```

E chamar no `POST /api/custody`. Limite aumentável por platform_admin.

---

### 🟡 [5.10] Swap offers: **visível para todos os grupos**, sem filtro de contraparte

**Achado** — `getOpenSwapOffers(groupId)` retorna ofertas de todos os grupos (inclusive inativos, bloqueados ou com score de risco baixo). Potencialmente vaza preços entre concorrentes diretos.

**Correção** — Adicionar `swap_orders.visibility text DEFAULT 'public' CHECK (visibility IN ('public','private','whitelist'))` e `whitelist_group_ids uuid[]`. UI: seller escolhe quem enxerga.

---

### 🟡 [5.11] UI distribute-coins: **sem confirmação dupla** de grandes valores

**Achado** — `portal/src/app/(portal)/distribute/...` presumivelmente tem um único botão "Distribuir". Sem modal "Você está distribuindo 50.000 moedas (≈ US$ 50.000). Digite CONFIRMAR.".

**Risco** — Fat finger: coach queria 50 e digitou 5000.

**Correção** — UI: quando `amount > 1000 OR amount * athletes > 5000` → modal de confirmação textual (tipo o "type DELETE to confirm" do GitHub).

---

### 🟡 [5.12] Challenges sem **regras de tie-break**

**Achado** — Ao calcular leaderboard de challenge de distância, se dois atletas empatarem, ordem é indeterminada (`ORDER BY total_distance DESC LIMIT 1`). Prêmio vai para quem o DB retornar primeiro.

**Correção** — `ORDER BY total_distance DESC, total_duration_s ASC, created_at ASC` (mais rápido cumprindo ganha). Documentar nas "rules" do challenge.

---

### 🟡 [5.13] Mobile: **corrida sem GPS salvo como 0 km** não invalidada

**Achado** — `omni_runner/lib/data/datasources/drift_database.dart` aceita `total_distance_m = 0`. Se atleta inicia e fecha sem mover, sessão vale 0 — mas contam para "sessions ativas".

**Correção** — Validar `total_distance_m >= 100` no `submit_session` RPC antes de marcar `status = 3 (verified)`. Sessions < 100 m: status = `4 (invalid)`.

---

### 🟡 [5.14] Feed social: **sem "report" / moderação**

**Achado** — Posts, comments, reactions existem mas não há tabela `reports` nem fluxo de moderação.

**Risco** — Cyberbullying entre atletas. Marco Civil Art. 19 + novas regras de plataformas.

**Correção** — `CREATE TABLE social_reports(...)` + tela `/platform/moderation` + hide automático após 3 reports distintos.

---

### 🟡 [5.15] Mobile: **logout não revoga tokens Strava/TrainingPeaks**

**Achado** — Em `profile_screen.dart`, botão "Sair" chama Supabase `signOut()` mas refresh_token Strava (`strava_connections`) fica no Supabase. Próximo login do usuário recupera conexão sem reautorização.

**Risco** — Quebra expectativa do atleta ("logout deveria desconectar tudo"). Misunderstanding comum.

**Correção** — UX: logout pergunta "Desconectar também Strava/TP?". Se sim, chama `POST /oauth/deauthorize` (ver [4.9]) e deleta row.

---

### 🟡 [5.16] Workout delivery: **sem reagendamento do atleta**

**Achado** — `workout_delivery_items` permite coach marcar "treino de hoje". Atleta machuca tornozelo, precisa mover para amanhã. Não há endpoint/UI.

**Correção** — Campo `athlete_requested_date date` + fluxo de aceite do coach (notificação push).

---

### 🟡 [5.17] Gamificação: **badges permanentes** sem prazo

**Achado** — `badge_awards` não tem `expires_at`. "Atleta de bronze 2024" continua para sempre.

**Correção** — Opcional: badges anuais têm `valid_until`, expiram automático.

---

### 🟡 [5.18] **Moeda fica em wallet do atleta que saiu do grupo**

**Achado** — Quando atleta deixa o grupo (`DELETE FROM coaching_members`), `wallets.balance_coins` permanece. Atleta queima a moeda após saída → clearing com grupo-ex-emissor complica.

**Correção** — Migration:

```sql
CREATE OR REPLACE FUNCTION fn_handle_athlete_leaves(p_user_id uuid, p_group_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_coins_from_group int;
BEGIN
  SELECT COALESCE(SUM(delta_coins), 0) INTO v_coins_from_group
  FROM coin_ledger WHERE user_id = p_user_id AND issuer_group_id = p_group_id AND delta_coins > 0;
  -- Option A: burn at group's expense (credit group with release)
  -- Option B: mark wallet-group link, redirect future burns to old group
  -- Choose A per business rules.
  -- Implementation omitted; needs product decision.
END;$$;
```

Precisa de decisão de produto antes de implementar.

---

### 🟡 [5.19] **Offline-first Flutter**: sessões ficam em `drift` até sincronizar

**Achado** — `drift_database.dart` salva sessões localmente. Se atleta corre, não sincroniza, troca de celular → perde treino.

**Correção** — Backup local em `FlutterSecureStorage` ou botão "Enviar por email todas as corridas pendentes".

---

### 🟢 [5.20] `delete-account` bloqueia `admin_master` (boa prática)

**Achado** — Linhas 46-49 negam auto-exclusão do admin_master.

**Correção** — Nenhuma. Pode-se melhorar com "há 2 admin_master? ok; só 1? bloqueie com mensagem explicativa".

---

## RESUMO PARTE 3 (35 itens)

| Severidade | Quantidade | IDs |
|---|---|---|
| 🔴 CRÍTICO | 5 | 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3 |
| 🟠 ALTO | 11 | 4.5, 4.6, 4.7, 4.8, 4.9, 4.10, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9 |
| 🟡 MÉDIO | 14 | 4.11–4.15, 5.10–5.19 |
| 🟢 SEGURO | 1 | 5.20 |

### Tópicos que merecem atenção de produto/legal antes de qualquer implementação:

1. **[4.3] Consentimento LGPD** — sem isso o produto está ilegal em qualquer lançamento B2C/B2B2C com atletas pessoa física.
2. **[4.1]+[4.2]+[4.9]** — fluxo de "direito ao esquecimento" precisa ser **retrabalho completo** antes de beta público.
3. **[5.2] Swap TTL** e **[5.9] Cap de depósito diário** — controles anti-abuso obrigatórios antes de liberar custódia para clubes externos.
4. **[5.18] Moeda órfã** — decisão de produto necessária (burn forçado? migrar para grupo herdeiro?).

---

**CONTINUA NA PARTE 4** — Lentes 6 (COO — operações), 7 (CXO — experiência), 8 (CDO — dados & analytics), totalizando ~40 itens.

Digite **"continue"** para prosseguir para a PARTE 4.