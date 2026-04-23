# TERMO DE ADESÃO E CONTRATO DE PRESTAÇÃO DE SERVIÇOS — ASSESSORIA / CLUBE

**Versão:** 1.0
**Vigência a partir de:** 2026-04-21
**Código de consentimento:** `club_adhesion`
**Tipo de instrumento:** Contrato de adesão de prestação de serviços de plataforma tecnológica (B2B) — Lei nº 10.406/02 (Código Civil), Art. 421 e seguintes; Lei nº 8.078/90 (CDC) Art. 54 quando aplicável; Lei nº 12.965/14 (Marco Civil da Internet); Lei nº 13.709/18 (LGPD).

---

## PARTES

**CONTRATADA**: PROJECT RUNNING TECNOLOGIA LTDA., pessoa jurídica de direito privado, inscrita no CNPJ sob nº [CNPJ_PLATAFORMA], com sede em [ENDEREÇO_PLATAFORMA], doravante denominada "PLATAFORMA".

**CONTRATANTE**: [NOME_DA_ASSESSORIA], pessoa jurídica de direito privado, inscrita no CNPJ sob nº [CNPJ_CONTRATANTE], com sede em [ENDEREÇO_CONTRATANTE], representada por [NOME_REPRESENTANTE], [QUALIFICAÇÃO_REPRESENTANTE], doravante denominada "ASSESSORIA".

PLATAFORMA e ASSESSORIA são individualmente designadas "Parte" e conjuntamente "Partes".

---

## CONSIDERANDO QUE

i.   A PLATAFORMA opera serviço próprio de tecnologia para gestão de assessorias esportivas, distribuição de conteúdo de treino, monitoramento de sessões, integração com dispositivos GPS/HR e dispositivos de terceiros, e meios de pagamento entre treinadores e atletas (doravante, simplesmente "PLATAFORMA");

ii.  A ASSESSORIA exerce, com habitualidade e finalidade econômica, atividade de prescrição esportiva, consultoria técnica e/ou treinamento de atletas amadores e profissionais, na forma das normas da CONFEF/CREF;

iii. A ASSESSORIA tem interesse em utilizar a PLATAFORMA para gerir relacionamento com seus atletas e processar pagamentos por seus serviços; e

iv.  A PLATAFORMA tem interesse em prover acesso à ASSESSORIA, observadas as condições deste instrumento.

As Partes resolvem celebrar o presente **TERMO DE ADESÃO E CONTRATO DE PRESTAÇÃO DE SERVIÇOS** ("Contrato"), que se regerá pelas cláusulas a seguir.

---

## CLÁUSULA I — DEFINIÇÕES

§ 1º. Para os fins deste Contrato, adotam-se as seguintes definições:

i.   **"Atleta"**: pessoa natural cadastrada na PLATAFORMA que adere a um plano da ASSESSORIA, sujeitando-se ao termo `athlete_contract` (`docs/legal/TERMO_ATLETA.md`).

ii.  **"Plano"**: oferta comercial criada pela ASSESSORIA na PLATAFORMA, com periodicidade, valor, escopo de serviço e número máximo de Atletas.

iii. **"Custódia"**: saldo monetário em reais (BRL) ou unidades de conta interna da PLATAFORMA ("coins") mantidos em contas segregadas em nome da ASSESSORIA, regidas pelas regras de antifraude e cap diário (vide `docs/runbooks/CUSTODY_DAILY_CAP_RUNBOOK.md`).

iv.  **"Política de Privacidade"**, **"Termos de Uso"** e demais documentos integrantes do `docs/legal/`, conforme indexação em `consent_policy_versions`.

v.   **"Dados Pessoais"**: na acepção do Art. 5º I da LGPD.

vi.  **"Incidente de Segurança"**: qualquer evento adverso confirmado ou suspeito que comprometa a confidencialidade, integridade ou disponibilidade dos Dados Pessoais sob custódia da ASSESSORIA ou da PLATAFORMA.

---

## CLÁUSULA II — OBJETO

§ 1º. A PLATAFORMA outorga à ASSESSORIA, em caráter pessoal, intransferível, não exclusivo e revogável, **licença de uso** dos serviços da PLATAFORMA na modalidade SaaS (Software as a Service), incluindo:

i.    Painel administrativo (portal web `portal.runningplatform.com.br`);
ii.   APIs documentadas em `/api/openapi/v1` e `openapi.json`;
iii.  Distribuição automática de coins, gestão de carteiras, custódia de saldos;
iv.   Configuração de Planos, cobrança recorrente via gateway financeiro homologado;
v.    Ferramentas de comunicação com Atletas (notificações push e e-mail transacional);
vi.   Acesso a integrações com terceiros previamente homologadas pela PLATAFORMA (e.g. Strava, TrainingPeaks).

§ 2º. **Não está abrangido por este Contrato**:

i.   prestação de serviço de assessoria esportiva diretamente pela PLATAFORMA aos Atletas (essa relação é exclusiva entre ASSESSORIA e Atleta);
ii.  intermediação financeira regulada (BACEN) — a custódia operada pela PLATAFORMA é exclusivamente liquidação operacional acessória, observadas as restrições da Resolução BCB nº 80/2021 e correlatas;
iii. emissão de documentos fiscais em nome da ASSESSORIA — esta permanece integralmente responsável pela emissão de NF-Se sobre os valores recebidos.

---

## CLÁUSULA III — OBRIGAÇÕES DA ASSESSORIA

§ 1º. A ASSESSORIA obriga-se a:

i.    Manter cadastro veraz, completo e atualizado, especialmente CNPJ, endereço, dados bancários, certidões negativas e responsável técnico habilitado pelo CONFEF/CREF;
ii.   Garantir que possui licença regular para prescrever treinos e operar como pessoa jurídica de prestação de serviços esportivos;
iii.  Não utilizar a PLATAFORMA para fins ilícitos, lavagem de dinheiro, fraude fiscal, evasão de divisas, sonegação tributária, ou qualquer atividade vedada pela legislação brasileira;
iv.   Tratar os Dados Pessoais dos Atletas exclusivamente nas finalidades autorizadas pelo termo `athlete_contract` e pela Política de Privacidade vigente, na qualidade de **CONTROLADORA conjunta** com a PLATAFORMA quando aplicável (LGPD Art. 5º VI e Art. 26);
v.    Reportar à PLATAFORMA, por meio de `seguranca@runningplatform.com.br`, qualquer Incidente de Segurança envolvendo Atletas ou dados sob sua gestão **em até 24 (vinte e quatro) horas** após a ciência;
vi.   Cumprir os limites operacionais estabelecidos pela PLATAFORMA (caps diários de custódia, limites de auto-topup, regras antifraude, restrições de swap);
vii.  Pagar pontualmente os valores devidos à PLATAFORMA, na forma da Cláusula IV;
viii. Não compartilhar credenciais de acesso ao painel administrativo com terceiros não autorizados;
ix.   Manter ativos os meios de pagamento cadastrados para evitar suspensão de cobranças automáticas;
x.    Cumprir as normas internas de moderação de conteúdo da PLATAFORMA (proibição de conteúdo discriminatório, ilegal, infrator de direitos autorais, etc.).

---

## CLÁUSULA IV — REMUNERAÇÃO E COMISSIONAMENTO

§ 1º. Pela prestação dos serviços objeto deste Contrato, a ASSESSORIA pagará à PLATAFORMA:

i.   **Mensalidade fixa de plataforma**: R$ [VALOR_MENSAL_BRL], debitada via gateway financeiro homologado, conforme plano contratado;

ii.  **Taxa percentual sobre o GMV** (Gross Merchandise Value) processado em nome da ASSESSORIA, de [PERCENTUAL_TAXA_PLATAFORMA]% (referente à infraestrutura de pagamento, antifraude e custódia), nos termos de `platform_fee_config` vigente na PLATAFORMA — alterações a essa taxa observam o congelamento de preços/taxas conforme `docs/audit/findings/L03-02-fee-freezing.md`;

iii. **Custos de gateway** (Pix, cartão, boleto) repassados ao custo, conforme tabela disponível no painel administrativo.

§ 2º. **Cap antifraude diário** — a PLATAFORMA poderá estabelecer e modificar caps diários de custódia e auto-topup aplicáveis à ASSESSORIA mediante notificação prévia, observado o instrumento `docs/runbooks/AUTO_TOPUP_DAILY_CAP_RUNBOOK.md`.

§ 3º. **Inadimplência** — atraso superior a 5 (cinco) dias corridos no pagamento da mensalidade autoriza a PLATAFORMA a (i) suspender o cadastro de novos Atletas; (ii) bloquear distribuição de coins e custódia; e (iii) após 30 (trinta) dias, rescindir este Contrato unilateralmente sem prejuízo do crédito vencido.

---

## CLÁUSULA V — VIGÊNCIA E RENOVAÇÃO

§ 1º. Este Contrato vigerá por prazo indeterminado a partir da data de aceite eletrônico via PLATAFORMA, com renovação tácita mensal vinculada ao pagamento da mensalidade.

§ 2º. Qualquer das Partes poderá denunciá-lo, sem ônus, mediante notificação prévia de 30 (trinta) dias enviada pelos canais oficiais (`contratos@runningplatform.com.br` para a PLATAFORMA; e-mail cadastral para a ASSESSORIA).

---

## CLÁUSULA VI — RESCISÃO

§ 1º. Constituem hipóteses de rescisão imediata, independentemente de notificação prévia:

i.   Comprovada utilização da PLATAFORMA para fins ilícitos;
ii.  Violação grave e dolosa das obrigações da Cláusula III, especialmente proteção de Dados Pessoais ou pagamentos;
iii. Falência, recuperação judicial deferida sem prosseguimento por mais de 90 dias, ou dissolução da ASSESSORIA;
iv.  Determinação judicial ou administrativa que impeça a continuidade da prestação dos serviços;
v.   Inadimplência superior a 30 (trinta) dias após notificação extrajudicial.

§ 2º. **Efeitos da rescisão** — a ASSESSORIA perderá o acesso ao painel administrativo, ressalvado o direito de exportar seus dados (LGPD Art. 18 V) por 90 (noventa) dias após a rescisão. Saldos em custódia serão liquidados conforme `docs/audit/findings/` aplicáveis e legislação financeira vigente.

---

## CLÁUSULA VII — TRATAMENTO DE DADOS PESSOAIS (LGPD)

§ 1º. As Partes reconhecem que, no fluxo operacional, podem atuar como:

i.  **Controladoras conjuntas** (LGPD Art. 5º VI; Art. 26) quanto aos dados cadastrais dos Atletas necessários à prestação do serviço (nome, e-mail, dados de contato, dados de pagamento autorizados);

ii. **Operadora** (PLATAFORMA) e **Controladora** (ASSESSORIA) quanto aos dados gerados pela ASSESSORIA na PLATAFORMA (planos de treino, históricos de sessão, métricas, comunicações);

iii. **Controladoras independentes** quanto aos dados de relacionamento exclusivos de cada Parte.

§ 2º. A ASSESSORIA compromete-se a:

i.   Obter dos Atletas consentimento válido para tratamento de Dados Pessoais sensíveis (dados de saúde, geolocalização) nos termos do `athlete_contract` vigente;
ii.  Não utilizar Dados Pessoais dos Atletas para finalidades não vinculadas ao plano contratado;
iii. Atender às solicitações de titulares (LGPD Art. 18) cuja origem inequívoca seja a relação entre ASSESSORIA e Atleta, encaminhando-as à PLATAFORMA quando dependerem de operação sistêmica;
iv.  Implementar medidas técnicas e administrativas razoáveis (LGPD Art. 46) para proteger Dados Pessoais sob seu acesso direto.

§ 3º. **Encarregado pelo Tratamento de Dados (DPO)**: para a PLATAFORMA, `dpo@runningplatform.com.br`. A ASSESSORIA indicará seu DPO no painel administrativo.

§ 4º. **Notificação de Incidentes** (LGPD Art. 48): observado o prazo de 24 horas da Cláusula III, item v, com escalonamento conforme `docs/runbooks/`.

---

## CLÁUSULA VIII — CONFIDENCIALIDADE

§ 1º. As Partes obrigam-se a manter sigilo sobre toda informação confidencial obtida em razão deste Contrato, inclusive dados estatísticos agregados, métricas de uso, condições comerciais específicas e código-fonte da PLATAFORMA, pelo prazo de vigência deste Contrato e por 5 (cinco) anos após sua extinção.

§ 2º. Não constituem informação confidencial: (i) o que for de domínio público sem culpa da Parte receptora; (ii) o que for desenvolvido independentemente; (iii) o que for revelado por exigência legal ou ordem judicial, observada notificação prévia à outra Parte quando legalmente possível.

---

## CLÁUSULA IX — RESPONSABILIDADE E LIMITAÇÃO

§ 1º. A PLATAFORMA empenhará esforços comercialmente razoáveis para manter a disponibilidade dos serviços, sem garantir SLA superior ao especificado no painel administrativo. Falhas decorrentes de força maior, terceiros (gateways, provedores de nuvem), ou ação/omissão da própria ASSESSORIA não geram dever de indenizar.

§ 2º. A responsabilidade civil agregada da PLATAFORMA por todo e qualquer evento decorrente deste Contrato fica **limitada ao valor pago pela ASSESSORIA à PLATAFORMA nos 12 (doze) meses anteriores ao evento gerador**, salvo dolo ou culpa grave devidamente comprovados ou nos casos em que a limitação seja vedada por norma de ordem pública.

§ 3º. A ASSESSORIA é integral e exclusivamente responsável pelos serviços de assessoria esportiva prestados aos Atletas, eximindo a PLATAFORMA de qualquer reclamação, indenização ou condenação decorrente da relação ASSESSORIA–Atleta, inclusive em matéria de responsabilidade civil por danos físicos durante a prática esportiva.

---

## CLÁUSULA X — CESSÃO

§ 1º. Nenhuma das Partes poderá ceder ou transferir, total ou parcialmente, este Contrato sem o prévio consentimento por escrito da outra Parte, ressalvada cessão a sucessoras universais por reorganização societária, hipótese em que basta notificação.

---

## CLÁUSULA XI — ANTICORRUPÇÃO E COMPLIANCE

§ 1º. As Partes declaram conhecer e cumprir a Lei nº 12.846/2013 (Lei Anticorrupção), Lei nº 9.613/1998 (Lei de Lavagem de Dinheiro), Lei nº 14.193/2021 (SAF, quando aplicável), e demais normas de compliance.

§ 2º. A PLATAFORMA poderá suspender operações suspeitas e reportá-las ao COAF (Conselho de Controle de Atividades Financeiras) ou autoridades competentes nos termos da Lei.

---

## CLÁUSULA XII — DISPOSIÇÕES FINAIS E FORO

§ 1º. As notificações entre as Partes serão consideradas realizadas quando enviadas por e-mail aos endereços cadastrais com confirmação de entrega.

§ 2º. Eventuais alterações deste Contrato observarão o protocolo de versionamento descrito em `docs/legal/README.md`. Ao aceitar versão posterior, a ASSESSORIA reconhece que o aceite é registrado em `consent_events` com gravação do hash SHA-256 do texto vigente.

§ 3º. A invalidade ou ineficácia de qualquer cláusula deste Contrato não prejudicará a validade das demais.

§ 4º. Fica eleito o foro da Comarca de [FORO_PLATAFORMA], Estado de [UF_PLATAFORMA], com renúncia expressa a qualquer outro por mais privilegiado que seja, para dirimir dúvidas ou litígios oriundos deste Contrato, sem prejuízo da competência da arbitragem caso as Partes assim acordem em aditivo.

---

## ACEITE

O aceite eletrônico deste Contrato pela ASSESSORIA, registrado em `consent_events` com `consent_type='club_adhesion'` e `version='1.0'`, equivale para todos os fins legais à assinatura física, nos termos da MP 2.200-2/2001 e Lei nº 14.063/2020, ficando o hash SHA-256 do texto integral acima registrado em `consent_policy_versions.document_hash` como prova de integridade documental.

---

**Versão:** 1.0
**Hash SHA-256 calculado em CI** — ver `tools/legal/check-document-hashes.ts`.
**Data de publicação:** 2026-04-21.
**Próxima revisão programada:** 2027-04-21 ou antes, mediante alteração legal/regulatória relevante.

### Histórico de versões

| Versão | Data | Autor | Resumo |
| --- | --- | --- | --- |
| 1.0 | 2026-04-21 | Comitê Jurídico (L09-09) | Versão inaugural — fechamento do gap de contratos privados identificado em auditoria. |
