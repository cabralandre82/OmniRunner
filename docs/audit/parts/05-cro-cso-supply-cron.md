I have enough context. Now generating PART 5.

# PARTE 5 de 8 — LENTES 9 (CRO: Regulatório Financeiro), 10 (CSO: Segurança Estratégica), 11 (Supply Chain / Dependências) e 12 (Cron & Scheduling em Profundidade)

Auditoria de **50 itens**.

---

## LENTE 9 — CRO (Chief Regulatory Officer): BCB, CVM, Receita Federal, KYC/AML, Regulação B2B de créditos

### 🔴 [9.1] Modelo de "Coin = US$ 1" pode ser classificado como **arranjo de pagamento** (BCB Circ. 3.885/2018)

**Achado** — O produto emite tokens resgatáveis por reais/dólares (via withdrawal com `fx_rate`) e permite transferência entre grupos (`swap_orders`). Sem tabela `kyc_verifications`, sem limite por CPF/CNPJ, sem integração com COAF, sem relatório de operações suspeitas (SOS).

- Emissor ≠ banco, mas está **armazenando valor em nome de terceiros** (`custody_accounts`) e disponibilizando liquidação entre terceiros (`clearing_settlements`, `execute_swap`).
- Volume potencial > R$ 500 mi/ano × > 1 M transações aciona critério BCB para autorização de IP (Instituição de Pagamento — Resolução BCB 80/2021).

**Risco** — Operação sem autorização = intervenção BCB + sanção penal Art. 16 Lei 7.492/86 ("operação não autorizada de instituição financeira" — reclusão 1–4 anos).

**Correção** — Opções excludentes:

1. **Restringir produto a "crédito de marketing"** não-resgatável (sem withdrawal em dinheiro) → sai do perímetro BCB, vira vale-benefício.
2. **Parceria com IP autorizada** (ex.: Asaas já citado no código tem autorização de conta escrow). Plataforma vira Payment Initiation Service (PIS) — custódia roda na IP parceira, código apenas orquestra.
3. **Obter autorização BCB como IP** (prazo realista 18–24 meses, capital mínimo R$ 2 mi, estrutura de compliance, diretor estatutário).

**Teste de regressão** — `docs/compliance/BCB_CLASSIFICATION.md` explica escopo e operação. Sign-off jurídico externo obrigatório.

---

### 🔴 [9.2] **Ausência de KYC/AML** para grupos com custódia

**Achado** — `grep -rn "kyc\|cpf\|cnpj\|coaf\|aml\|pep" supabase/migrations portal/src omni_runner/lib --include="*.{sql,ts,tsx,dart}"` → resultados vazios. Grupo/Assessoria cria custódia, deposita R$ 100k, saca via withdrawal **sem** validação:

- Nome completo / razão social cadastrada
- CPF/CNPJ do representante legal
- Comprovante de endereço
- Verificação em listas de sanções (OFAC, BCB, COAF, PEPs)
- Proof of funds para depósitos > R$ 50 k

**Risco** — Plataforma vira veículo de lavagem. Comunicação COAF exigida > R$ 10 k suspeito (Circ. BCB 3.978/2020 Art. 49). Omissão = multa R$ 20 k–R$ 20 mi + responsabilidade criminal do diretor (Art. 23 Lei 9.613/98).

**Correção** —

```sql
CREATE TABLE public.kyc_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES coaching_groups(id),
  legal_entity_type text NOT NULL CHECK (legal_entity_type IN ('individual','company')),
  document_type text NOT NULL CHECK (document_type IN ('CPF','CNPJ')),
  document_number text NOT NULL,
  document_number_hash bytea GENERATED ALWAYS AS
    (digest(document_number, 'sha256')) STORED,
  legal_name text NOT NULL,
  birth_date date,  -- only for individuals
  address jsonb NOT NULL,
  pep_status text CHECK (pep_status IN ('not_pep','pep','close_associate','unknown')) DEFAULT 'unknown',
  sanctions_list_match boolean DEFAULT false,
  verified_at timestamptz,
  verified_by text,  -- provider like 'idwall','unico','serpro'
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','review')),
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX ON kyc_verifications(document_number_hash);

-- Block custody_deposits unless group has approved KYC
CREATE OR REPLACE FUNCTION fn_require_kyc() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM kyc_verifications
    WHERE group_id = NEW.group_id AND status = 'approved'
  ) THEN RAISE EXCEPTION 'KYC required' USING ERRCODE='KYC01'; END IF;
  RETURN NEW;
END;$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_custody_deposit_requires_kyc
  BEFORE INSERT ON custody_deposits FOR EACH ROW EXECUTE FUNCTION fn_require_kyc();
```

Integrar com provedor (IDWall, Unico, Serpro Datavalid).

**Teste** — `kyc.required.test.sql`: tentar inserir custody_deposit sem KYC aprovado → erro `KYC01`.

---

### 🔴 [9.3] **Relatório de Operações (SOS COAF)** inexistente

**Achado** — Mesmo que KYC seja implementado ([9.2]), não há função/cron detectando:

- Múltiplos depósitos < R$ 10 k em curto período (structuring / smurfing)
- Withdrawal imediato após depósito (dinheiro em trânsito, sem uso do produto)
- Swap entre grupos controlados pelo mesmo CPF/CNPJ (wash trading)
- Volume anômalo vs baseline histórico

**Correção** —

```sql
CREATE TABLE public.aml_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES coaching_groups(id),
  user_id uuid,
  rule_code text NOT NULL,
  severity text CHECK (severity IN ('low','medium','high','coaf_reportable')),
  details jsonb,
  created_at timestamptz DEFAULT now(),
  reviewed_at timestamptz,
  reviewer_id uuid
);

-- Detect structuring (5+ deposits < 10k BRL in 7 days)
CREATE OR REPLACE FUNCTION fn_detect_structuring() RETURNS void AS $$
BEGIN
  INSERT INTO aml_flags (group_id, rule_code, severity, details)
  SELECT d.group_id, 'STRUCTURING_R1',
    CASE WHEN COUNT(*) >= 10 THEN 'coaf_reportable' ELSE 'high' END,
    jsonb_build_object('count', COUNT(*), 'total_usd', SUM(amount_usd),
                       'window', '7_days')
  FROM custody_deposits d
  WHERE status='confirmed' AND created_at > now() - interval '7 days'
    AND amount_usd < 10000
  GROUP BY d.group_id
  HAVING COUNT(*) >= 5;
END;$$ LANGUAGE plpgsql;

-- Cron: hourly
SELECT cron.schedule('aml-structuring-detect','*/10 * * * *',
  $$SELECT fn_detect_structuring()$$);
```

UI `/platform/compliance` para revisor marcar casos, gerar arquivo COAF (layout XML do siscoaf).

---

### 🔴 [9.4] Nota fiscal / recibo fiscal **não emitida** em withdrawals

**Achado** — Quando Assessoria (CNPJ) recebe withdrawal de moedas reconvertidas em BRL, a plataforma cobra `fx_spread` + taxa de clearing + taxa de swap. Isso é **receita de serviço** (tributável). Busca por `nota_fiscal|nfe|nfs|rps|emissor_fiscal` → zero matches.

**Risco** — Receita auditada pela Receita Federal → autuação por omissão de receita + multa 75 % + juros Selic. Cliente B2B não recebe NFS-e e também autua a plataforma.

**Correção** — Integrar emissor (Focus NFe, Enotas, NFE.io):

```sql
CREATE TABLE public.fiscal_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text NOT NULL CHECK (source_type IN
    ('custody_withdrawal','clearing_settlement','swap_order','platform_fee')),
  source_ref_id text NOT NULL,
  customer_document text NOT NULL,
  customer_name text NOT NULL,
  service_code text NOT NULL,  -- código CNAE / Lei Comp. 116
  gross_amount_brl numeric(14,2) NOT NULL,
  taxes_brl numeric(14,2) NOT NULL,
  provider_response jsonb,
  nfs_pdf_url text,
  nfs_xml_url text,
  status text DEFAULT 'pending' CHECK (status IN ('pending','issued','canceled','error')),
  issued_at timestamptz,
  created_at timestamptz DEFAULT now()
);
```

Chamar após `platform_revenue` receber nova linha.

---

### 🔴 [9.5] **IOF não recolhido** em swap inter-cliente

**Achado** — `execute_swap` transfere valor entre CNPJs distintos mediante taxa. Dependendo da natureza legal (crédito de marketing vs. direitos creditórios vs. ativo), pode incidir IOF (0,38 % genérico). Código não calcula nem segrega.

**Risco** — Autuação Receita com juros desde a primeira operação.

**Correção** — Consulta prévia com tributarista; se aplicável, nova coluna `iof_amount` em `swap_orders` + recolhimento mensal DARF.

---

### 🟠 [9.6] Gateway de pagamento Asaas: chave armazenada em **plaintext** na DB

**Achado** — Conforme [1.19] de PARTE 1. Risco regulatório adicional: a LGPD (dado pessoal + financeiro) e a PCI DSS quando Asaas agrega dados de cartão.

**Risco** — Acesso DBA malicioso ou dump para staging → atacante usa chave para cobranças fraudulentas no CNPJ da assessoria.

**Correção** — Usar `pgp_sym_encrypt` com master key em KMS (AWS KMS, Supabase Vault):

```sql
UPDATE billing_providers SET api_key =
  pgp_sym_encrypt(api_key, current_setting('app.settings.kms_key'))
WHERE api_key IS NOT NULL AND api_key NOT LIKE '\x%';
```

Função `fn_get_asaas_key(group_id uuid) RETURNS text SECURITY DEFINER` faz o decrypt e loga acesso em `audit_logs`.

---

### 🟠 [9.7] Política de reembolso/chargeback **sem prazo SLA**

**Achado** — Vincula-se a [2.13]. Não há política documentada: "reembolso em até X dias". Código Defesa Consumidor Art. 49 exige 7 dias para arrependimento em vendas remotas.

**Correção** — Implementar `process-refund` Edge Function (já existe em `supabase/functions/process-refund/`) para que deposite reverso + emitir NFS-e de estorno. Configurar SLA: estorno < 48 h úteis.

---

### 🟠 [9.8] `provider_fee_usd` ([2.12]) — ônus ao cliente ou à plataforma?

**Achado** — Assessoria deposita US$ 1000, Stripe cobra US$ 38. Produto não deixa claro se assessoria credita 962 coins (absorve) ou 1000 (plataforma absorve). Contrato de adesão inexistente no repo.

**Risco** — Reclamação/processo no PROCON por "cobrança não contratada" se cobrar do cliente sem aviso prévio claro.

**Correção** — Política `platform_fee_config` linha `gateway_passthrough` boolean; UI mostra em tempo real no checkout "Taxa do gateway: US$ X (a seu cargo)". Contrato de adesão apresentado no onboarding com aceite ([4.3]).

---

### 🟠 [9.9] Contratos privados (termo de adesão do clube, termo de atleta) **inexistentes no repo**

**Achado** — `grep -rn "termo_adesao\|termo_atleta\|contrato" docs/` não encontra versões legíveis, revisadas.

**Correção** — `docs/legal/TERMO_ADESAO_ASSESSORIA.md`, `docs/legal/TERMO_ATLETA.md`, versionados no git com hash SHA-256 gravado em `consent_log.version` ([4.3]).

---

### 🟡 [9.10] Relatório anual de transparência (Marco Civil Art. 11)

**Achado** — Não há relatório periódico de solicitações governamentais, removals, etc.

**Correção** — Página `/transparencia` atualizada semestralmente.

---

### 🟡 [9.11] Cessão de crédito implícita em `clearing_settlements` — documentar

**Achado** — `settle_clearing` move saldo de debtor → creditor. Sob certa interpretação, é **cessão de crédito** (Art. 286 CC) sem instrumento formal de cessão. Para valores altos, exige registro em cartório ou aditivo contratual.

**Correção** — Contratualmente, clearing é serviço acessório do produto (não cessão): documentar no termo de adesão. Alternativa: emitir recibo eletrônico de liquidação a cada `settle_clearing` em PDF assinado digitalmente.

---

### 🟡 [9.12] Auditoria externa financeira — inexistente

**Achado** — Produto lida com dinheiro real mas não há provisão para auditoria anual independente (Big 4 ou similar) mesmo que voluntária para gerar confiança.

**Correção** — Plano para auditoria a partir de Ano 2 de operação.

---

## LENTE 10 — CSO (Chief Security Officer): Threat Modeling, Blue Team & Controles Estratégicos

### 🔴 [10.1] **Nenhum bug bounty / disclosure policy**

**Achado** — `security.txt`, `/security`, `SECURITY.md` — nada. Pesquisador que descubra falha não sabe como reportar.

**Risco** — Findings vazam em fóruns/Twitter antes de correção. Zero-day exploitado em produção.

**Correção** —

```
# portal/public/.well-known/security.txt
Contact: security@omnirunner.com
Expires: 2027-04-17T00:00:00.000Z
Preferred-Languages: pt, en
Policy: https://omnirunner.com/security-policy
Canonical: https://omnirunner.com/.well-known/security.txt
```

+ `SECURITY.md` no repo com SLA de resposta. Considerar YesWeHack, Intigriti ou HackerOne privado após primeira auditoria externa.

---

### 🔴 [10.2] **Threat model formal não documentado**

**Achado** — `grep -ri "threat_model\|STRIDE\|DFD" docs/` → vazio. Sistema com custódia financeira sem DFD nem STRIDE = segurança orgânica.

**Risco** — Cada mudança arquitetural é avaliada ad-hoc; controles derivam de "lembrei de testar isso" ao invés de matriz sistemática.

**Correção** — Documento `docs/security/THREAT_MODEL.md` com:

- Data Flow Diagrams: Mobile ↔ Portal ↔ Supabase ↔ Gateways
- Trust boundaries explícitos
- STRIDE por boundary
- Mitigações mapeadas para commits/PRs

Revisão a cada major feature.

---

### 🔴 [10.3] Service-role key **distribuída amplamente**

**Achado** — `SUPABASE_SERVICE_ROLE_KEY` aparece em env de:

- 15+ Edge Functions (legítimo)
- `portal/src/lib/supabase/service.ts` e `admin.ts` (legítimo)
- GitHub Actions `portal.yml` (para E2E e k6)
- Provavelmente Vercel prod/preview

**Risco** — Uma única key compromete todo o banco. E preview envs de PR também têm acesso a produção.

**Correção** —

1. **Separar keys** prod/staging/preview. GitHub Actions usa `SUPABASE_SERVICE_ROLE_KEY_STAGING`.
2. **Rotação trimestral** com runbook [6.11].
3. **Supabase Vault** + custom roles por caso de uso (ex.: role `billing_role` com grants mínimos).
4. Log de uso do service-role via extensão `pg_audit`.

---

### 🟠 [10.4] Sem **WAF** explícito

**Achado** — Vercel fornece edge WAF básico, mas não há regras customizadas (bloquear `User-Agent: sqlmap`, geo-fence Supabase a países operados, limite país × rate).

**Correção** — Vercel Firewall rules: bloquear por IP/country/UA/path + integrar Cloudflare (tier pago) se risco aumentar.

---

### 🟠 [10.5] **CSP** hardened ([1.31]) mas sem **report-uri**

**Achado** — `portal/next.config.mjs` CSP não tem `report-uri` nem `report-to`. Violações não são detectadas.

**Correção** —

```javascript
Content-Security-Policy-Report-Only ... ; report-to csp-endpoint
Report-To: {"group":"csp-endpoint","max_age":10886400,"endpoints":[{"url":"https://omnirunner.report-uri.com/r/d/csp/enforce"}]}
```

Usar `report-uri.com` ou endpoint interno `/api/csp-report`.

---

### 🟠 [10.6] Segregação de função (SoD) **ausente** em platform_admin

**Achado** — `platform_admin` pode: (a) configurar taxas, (b) executar withdrawals manuais, (c) criar refunds. Um único usuário comprometido move toda a tesouraria. Sem aprovação dupla.

**Correção** —

```sql
CREATE TABLE public.admin_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action_type text NOT NULL,
  payload jsonb NOT NULL,
  requested_by uuid NOT NULL,
  approved_by uuid,
  rejected_by uuid,
  status text DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','executed','expired')),
  expires_at timestamptz DEFAULT (now() + interval '24 hours'),
  executed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT chk_self_approval CHECK (approved_by IS NULL OR approved_by <> requested_by)
);
```

Ações ≥ US$ 10k ou mudança de platform_fee_config exigem duas linhas distintas (requester + approver) antes de `status = 'executed'`.

---

### 🟠 [10.7] **Zero-trust entre microserviços** — Edge Functions confiam no JWT sem validar audience

**Achado** — `supabase/functions/_shared/auth.ts` valida JWT mas não valida `aud` claim específica. Qualquer JWT válido do Supabase acessa qualquer função.

**Correção** — JWT assinado com `aud=omni-runner-mobile` ou `aud=omni-runner-portal` + validação por-função de quem pode chamar o quê.

---

### 🟠 [10.8] Logs de acesso sensíveis **sem imutabilidade**

**Achado** — `audit_logs` é tabela normal; atacante com service-role pode `DELETE`/`UPDATE`.

**Correção** —

1. Role `audit_read_only` com `GRANT SELECT` apenas.
2. Trigger `BEFORE DELETE OR UPDATE ON audit_logs` que bloqueia operações.
3. Export incremental para S3 com Object Lock (compliance mode) — 7 anos.

---

### 🟠 [10.9] Falta defesa anti **credential stuffing** no Mobile/Portal

**Achado** — Supabase Auth faz rate-limit por IP mas não por email. Ataque distribuído testa mil emails × senha comum.

**Correção** — Supabase Edge Function pré-login que mantém contador por `email_hash` e aplica `CAPTCHA` (hCaptcha) após 3 falhas.

---

### 🟡 [10.10] Não há **pentest** externo documentado

**Achado** — Nenhum PDF de relatório em `docs/security/`.

**Correção** — Pentest anual externo + após cada major feature financeira. Empresas: Tempest, Tenchi, Hakaioh.

---

### 🟡 [10.11] Sem inventário de **chaves de API terceiros**

**Achado** — Strava, TrainingPeaks, Firebase, Stripe, Asaas, MP, Sentry, Upstash — chaves distribuídas em `.env.local`, GitHub Secrets, Vercel. Não há planilha central.

**Correção** — `docs/security/SECRETS_INVENTORY.md` (SEM valores — apenas nome, local, dono, data de rotação).

---

### 🟡 [10.12] **CSRF no portal** confiando apenas em SameSite=Lax

**Achado** — Cookies `portal_group_id`, `portal_role` com `sameSite: "lax"`. Ataques com navegação top-level (GET) não são bloqueados.

**Correção** — Todas as mutações via POST/PUT/DELETE + verificação de token CSRF anti-forgery (double-submit cookie pattern) nos `api/*` que alteram estado financeiro.

---

### 🟡 [10.13] Sem DPI (Device Posture) no Flutter

**Achado** — App não verifica: root/jailbreak, debugger attached, Frida hook, emulador em produção, integridade do APK.

**Correção** — `flutter_jailbreak_detection` + Play Integrity API + bloqueio "soft" (warning) ou "hard" (bloquear transações financeiras em device comprometido).

---

### 🟡 [10.14] JWTs sem **rotação de refresh_token**

**Achado** — Supabase default: refresh_token "rotation" disponível via setting; não auditado se ativado.

**Correção** — Confirmar em Supabase Dashboard: "Refresh Token Rotation" = `ON`, "Rotation Period" = 10s, "Reuse Interval" = 0.

---

## LENTE 11 — Supply Chain / Dependências

### 🔴 [11.1] CI sem **`npm audit` / `flutter pub audit`**

**Achado** — `.github/workflows/portal.yml` rodo lint/test/build/e2e/k6 mas **nenhum passo de security scan**. `flutter.yml` idem.

**Risco** — CVE em `next`, `@supabase/ssr`, `zod`, etc. passa despercebido em builds por semanas.

**Correção** —

```yaml
- run: npm audit --production --audit-level=high
  continue-on-error: false   # falhar no build
- uses: snyk/actions/node@master
  with:
    args: --severity-threshold=high --org=omnirunner
  env: { SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }} }

# Flutter
- run: dart pub deps --json > deps.json
- run: npx better-npm-audit # ou pana/osv-scanner
```

---

### 🔴 [11.2] **Sem SBOM** (Software Bill of Materials)

**Achado** — Requisito cresceu regulatoriamente (NIST SSDF, EO 14028 US, BACEN resol. 4.893/21 brasileiro sobre gerenciamento de risco de fornecedor).

**Correção** —

```yaml
- uses: anchore/sbom-action@v0
  with:
    path: ./portal
    format: cyclonedx-json
    output-file: sbom-portal.cdx.json
- uses: actions/upload-artifact@v4
  with:
    name: sbom-portal
    path: sbom-portal.cdx.json
```

Armazenar versionado. Opcionalmente assinar com Sigstore (`cosign`).

---

### 🔴 [11.3] **Sem gitleaks / trufflehog** no CI

**Achado** — PRs com secret vazado passam direto. Dev pode fazer commit de `SUPABASE_SERVICE_ROLE_KEY=eyJ…` por engano.

**Correção** —

```yaml
- uses: gitleaks/gitleaks-action@v2
  with: { config-path: .gitleaks.toml }
```

+ pre-commit hook `gitleaks protect --staged`.

---

### 🟠 [11.4] Dependabot **agrupa todas as minor+patch** — PR monstro

**Achado** — `.github/dependabot.yml:12-16` faz um único PR com todas minor/patch semanalmente. Se uma quebra, bloqueia todas.

**Correção** — Separar por ecossistema/tópico:

```yaml
groups:
  next-ecosystem:
    patterns: ["next", "next-*", "@next/*"]
  supabase:
    patterns: ["@supabase/*"]
  testing:
    patterns: ["vitest", "@vitest/*", "@testing-library/*", "@playwright/*"]
  other-minor-patch:
    update-types: [minor, patch]
```

---

### 🟠 [11.5] **`flutter_secure_storage: ^10.0.0`** mas release inclui `shared_preferences`

**Achado** — `pubspec.yaml:63,55` declara `flutter_secure_storage: ^10.0.0` e `shared_preferences: ^2.5.4`. Auditoria anterior em [1.1] já identifica uso. Risco: devs confundem qual storage usar para dados sensíveis.

**Correção** — Lint rule custom proibindo `shared_preferences` para chaves contendo `token|key|secret|auth` via `custom_lint` package.

---

### 🟠 [11.6] Dependências com `^` permitem **breaking minor**

**Achado** — `portal/package.json`: `next: ^14.2.15`, `zod: ^4.3.6`. Caret permite minor bumps que podem quebrar tipos (zod 4 ↔ 3).

**Correção** — `^` aceitável para produção SE houver CI de integração robusto. Pinar exatos (`14.2.15`) para `next`, `@supabase/ssr` em `package.json` + `.npmrc` `save-exact=true`.

---

### 🟠 [11.7] `sqlcipher_flutter_libs: ^0.7.0+eol` — **"eol"** = end of life

**Achado** — Linha do pubspec explicitamente marca EOL. Código cripta banco local mas depende de biblioteca sem manutenção.

**Risco** — CVE futuro em sqlcipher não será corrigido; app exposto.

**Correção** — Migrar para `drift` encrypted (`drift/drift_sqlflite` + encryption plugin) ou `sqlite3_flutter_libs` + `sqlcipher-mozilla` fork mantido.

---

### 🟠 [11.8] Flutter `sdk: '>=3.8.0 <4.0.0'` — permite 3.9, 3.10…

**Achado** — Dart SDK breaking em minor não é impossível (null safety histórico). CI usa `flutter-version: '3.41.x'` — hardcoded, OK.

**Correção** — Atualizar pubspec para `sdk: '>=3.8.0 <3.13.0'` e alinhar no CI.

---

### 🟡 [11.9] GitHub Actions sem **OIDC** para deploys

**Achado** — `SUPABASE_SERVICE_ROLE_KEY` usada em `portal.yml:117`. Mesmo para E2E, seria melhor ter um service-role de staging injetado via OIDC + curto-tempo.

**Correção** — `permissions: id-token: write` + OIDC provider → Supabase Vault tem passo "emit short-lived token".

---

### 🟡 [11.10] `actions/checkout@v4` SHA **não pinned**

**Achado** — `.github/workflows/portal.yml:34,52,...` usa tag `@v4` ao invés de commit hash. Tag pode ser movida por atacante que comprometa a org.

**Correção** — Pinar por commit SHA:

```yaml
uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
```

Automatizado via `pinact` ou `renovate` config.

---

### 🟡 [11.11] Sem **Renovate** como alternativa

**Achado** — Apenas Dependabot. Renovate tem melhor agrupamento, lockfile maintenance, merge automático de patches seguros.

**Correção** — Adicionar `renovate.json` ou migrar de Dependabot.

---

### 🟡 [11.12] `npm ci` sem **--ignore-scripts**

**Achado** — `portal/package.json` pós-install arbitrário é permitido. Pacote malicioso roda código no CI.

**Correção** — `npm ci --ignore-scripts` + script explícito para os que precisam (ex.: `husky install`).

---

### 🟡 [11.13] **Lockfile drift** não validado

**Achado** — CI não faz `npm ci --only=production` nem `npm install --frozen-lockfile`. Dev esquece de commitar lockfile atualizado.

**Correção** —

```yaml
- run: npm ci  # falha se lockfile out-of-sync
- run: git diff --exit-code package-lock.json
```

---

### 🟡 [11.14] `omni_runner/pubspec.lock` commitado?

**Achado** — Não verificado. Flutter recomenda commitar para apps.

**Correção** — Confirmar `git ls-files omni_runner/pubspec.lock` existe; se não, adicionar.

---

## LENTE 12 — Cron & Scheduling (em profundidade)

### 🔴 [12.1] **`reconcile-wallets-cron` existe mas NÃO está agendado**

**Achado** — `grep -rn "cron.schedule" supabase/migrations/*.sql` lista 10 jobs (`auto-topup-hourly`, `lifecycle-cron`, `clearing-cron`, `eval-verification-cron`, `expire-matchmaking-queue`, `onboarding-nudge-daily`, `archive-old-sessions`, `archive-old-ledger`, `process-scheduled-workout-releases`, `aml-structuring-detect` proposto). **Reconcile-wallets-cron NÃO aparece**. A função `reconcile_all_wallets()` existe (`20260227500000_wallet_reconcile_and_session_retention.sql:109`) e o Edge Function `reconcile-wallets-cron/` existe — mas nenhuma migration `SELECT cron.schedule('reconcile-wallets', ...)`.

**Risco** — **Reconciliação nunca roda automaticamente**. Drift entre `wallets.balance_coins` e `SUM(coin_ledger.delta_coins)` acumula indefinidamente. O único mecanismo defensivo citado em runbooks é inexistente em produção.

**Correção** — Nova migration:

```sql
SELECT cron.schedule(
  'reconcile-wallets-daily',
  '30 4 * * *',  -- 04:30 UTC, after archive jobs
  $$
  SELECT extensions.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/reconcile-wallets-cron',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);
```

**Teste** — `SELECT * FROM cron.job WHERE jobname = 'reconcile-wallets-daily'` deve existir em prod.

---

### 🔴 [12.2] **Thundering herd** em 02:00–04:00 UTC

**Achado** — 5 jobs agendados entre 02:00 e 04:00 UTC:

| Job | Schedule |
|---|---|
| clearing-cron | 0 2 * * * |
| eval-verification-cron | 0 3 * * * |
| archive-old-sessions | 0 3 * * 0 (dom) |
| archive-old-ledger | 0 4 * * 0 (dom) |
| onboarding-nudge-daily | 0 10 * * * |
| (proposto) reconcile-wallets | 30 4 * * * |

Domingo 03:00 UTC: verification + archive-sessions batem juntos. Archive-sessions provavelmente escaneia tabela `sessions` inteira com `VACUUM`/`DELETE` massivo.

**Risco** — DB CPU saturado, queries do portal travadas; atleta domingo cedo sincronizando corrida fica pendente 10 min.

**Correção** — Redistribuir:

```sql
SELECT cron.unschedule('clearing-cron');
SELECT cron.schedule('clearing-cron','0 2 * * *', …);  -- OK
SELECT cron.unschedule('eval-verification-cron');
SELECT cron.schedule('eval-verification-cron','15 3 * * *', …);
SELECT cron.unschedule('archive-old-sessions');
SELECT cron.schedule('archive-old-sessions','45 3 * * 0', …);
SELECT cron.unschedule('archive-old-ledger');
SELECT cron.schedule('archive-old-ledger','15 5 * * 0', …);
```

Mínimo 15 min de espaçamento.

---

### 🔴 [12.3] **`*/5 * * * *` crons sem lock** — overlap risk

**Achado** — `lifecycle-cron`, `expire-matchmaking-queue`, `process-scheduled-workout-releases` rodam a cada 5 min. Se execução n dura 6 min, execução n+1 começa enquanto n ainda processa mesmos registros → double processing.

**Correção** — Advisory lock:

```sql
CREATE OR REPLACE FUNCTION fn_process_scheduled_releases_safe()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('process_scheduled_releases')) THEN
    RAISE NOTICE 'Previous run still in progress; skipping';
    RETURN;
  END IF;
  PERFORM fn_process_scheduled_releases();
END;$$;
```

Chamar a versão `_safe` no cron.

---

### 🟠 [12.4] `pg_cron` não monitora **SLA de execução**

**Achado** — `cron.job_run_details` existe mas nenhum dashboard. Se `clearing-cron` falhar 5 dias seguidos, ninguém nota.

**Correção** — Ver [6.4]: `fn_check_cron_health()` + alerta Slack se `minutes_since_success > 2 * schedule_interval_minutes`.

---

### 🟠 [12.5] `auto-topup-hourly` — **cobrança automática** sem cap diário

**Achado** — Roda de hora em hora. Se settings do atleta mal-configurado (bug ou ataque), pode cobrar 24×/dia.

**Correção** —

```sql
ALTER TABLE auto_topup_settings ADD COLUMN daily_charge_cap_brl numeric(10,2) DEFAULT 500;
ALTER TABLE auto_topup_settings ADD COLUMN charges_today integer DEFAULT 0;
ALTER TABLE auto_topup_settings ADD COLUMN last_charge_reset_at date DEFAULT current_date;
-- Edge function refuses if charges_today >= 3 OR total_today > cap
```

---

### 🟠 [12.6] `archive-old-sessions` roda como função pesada **sem batch**

**Achado** — `fn_archive_old_sessions()` provavelmente move linhas para partição fria/S3 de uma só vez. Sem `LIMIT` por execução, lock longo de `sessions`.

**Correção** — Loop em batch de 1000 + `COMMIT` entre batches (via function autonomous transactions ou DO block com savepoints).

---

### 🟠 [12.7] Horário **UTC** → usuários BR veem "meia-noite Brasil"

**Achado** — `clearing-cron` roda 02:00 UTC = 23:00 BRT. Aceitável. Mas `onboarding-nudge-daily` 10:00 UTC = 07:00 BRT — pode ser cedo demais para notificação push.

**Correção** — Ajustar para 12:00 UTC (09:00 BRT). Ou, melhor: job consulta `profiles.timezone` ([7.6]) e envia push nas "09:00 locais" de cada usuário (exigindo granularidade por timezone).

---

### 🟠 [12.8] `clearing-cron` em 02:00 — **consolidação de D-1 antes de fim do dia**

**Achado** — Aggregator consolida ledger de "a semana". Usuário que queima moeda às 01:55 está na agregação; às 02:05 está fora. Jitter no horário do job pode cruzar a fronteira.

**Correção** — Função agrega com `WHERE created_at < date_trunc('day', now())` (estritamente < início de hoje UTC). Documento "cutoff = 00:00 UTC" no runbook.

---

### 🟠 [12.9] `lifecycle-cron` dispara notificações **idempotência não garantida**

**Achado** — `*/5 * * * *` sem tabela `sent_notifications` dedicada.

**Correção** —

```sql
CREATE TABLE notification_log (
  user_id uuid, notification_code text, ref_id text,
  sent_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, notification_code, ref_id)
);
-- Before sending:
INSERT INTO notification_log VALUES (uid, 'streak_broken', today::text)
  ON CONFLICT DO NOTHING;
IF NOT FOUND THEN RETURN; END IF;  -- already sent
-- send push
```

---

### 🟡 [12.10] Jobs `pg_cron` executam como **superuser** (padrão)

**Achado** — pg_cron roda na role do criador da função (`postgres`/`supabase_admin`). Função fallha + roda em role elevada = blast radius grande.

**Correção** — Supabase "Database → Cron" UI permite escolher role. Criar role dedicada `cron_worker` com permissões mínimas.

---

### 🟡 [12.11] `cron.schedule` **em migration duplicada** corre risco

**Achado** — Se migration roda 2× (rollback + reapply), `cron.schedule` retorna erro "jobname duplicate". Algumas migrations não usam `IF NOT EXISTS`.

**Correção** — Padrão:

```sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'clearing-cron') THEN
    PERFORM cron.schedule('clearing-cron', '0 2 * * *', $job$...$job$);
  END IF;
END $$;
```

---

### 🟡 [12.12] **Timezone do cron** = UTC ok, **mas horário DST?**

**Achado** — Brasil aboliu DST em 2019; não é problema. EUA sim — se expandir, crons em horário UTC fixos mudam relação com horário comercial US.

**Correção** — Documentar decisão: "crons sempre UTC; UI local time opcional".

---

## RESUMO PARTE 5 (50 itens)

| Severidade | Quantidade | IDs |
|---|---|---|
| 🔴 CRÍTICO | 9 | 9.1, 9.2, 9.3, 9.4, 9.5, 10.1, 10.2, 10.3, 11.1, 11.2, 11.3, 12.1, 12.2, 12.3 |
| 🟠 ALTO | 18 | 9.6, 9.7, 9.8, 9.9, 10.4–10.9, 11.4–11.8, 12.4–12.9 |
| 🟡 MÉDIO | 17 | 9.10–9.12, 10.10–10.14, 11.9–11.14, 12.10–12.12 |

### Blockers absolutos antes de produção B2B:

1. **[9.1] + [9.2] + [9.3]** — **regulatório financeiro brasileiro**. Sem parceria com IP autorizada (Asaas), KYC e detecção COAF, é operação não autorizada de instituição financeira. **Risco criminal pessoal do diretor**.
2. **[10.3]** — service-role key compartilhada entre prod/staging/preview → um preview vazado = compromisso total.
3. **[11.1–11.3]** — ausência de qualquer security scan em CI; dependência maliciosa ou secret vazado passam direto.
4. **[12.1]** — reconcile-wallets **nunca roda**. Drift entre ledger e wallets se acumula invisível → perda financeira direta.

---

**CONTINUA NA PARTE 6** — Lentes 13 (Middleware & Routing profundo), 14 (API Contracts & Versioning), 15 (CMO — Marketing & Growth), 16 (CAO — Acquisitions/Parcerias B2B), totalizando ~25 itens.

Digite **"continue"** para prosseguir para a PARTE 6.

 I'm noticing that `reconcile-wallets-cron` exists as an Edge Function but was never actually scheduled through any `cron.schedule` migration—it's only being called manually right now, which is a gap worth flagging. Now I have enough to move forward and build out Part 5 covering the remaining lenses.