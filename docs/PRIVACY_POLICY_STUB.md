# Política de Privacidade — Omni Runner

**Última atualização:** [DATA]

**Versão:** 1.0 (rascunho)

---

## 1. Dados Coletados

### 1.1 Dados de Perfil
- Nome de exibição
- Endereço de e-mail
- Foto de perfil (opcional)
- Data de nascimento (opcional)
- Sexo (opcional)

### 1.2 Dados de Treino e Atividade Física
- Dados de GPS (rota, altitude, velocidade, pace)
- Frequência cardíaca (via dispositivos BLE ou integrações como Strava)
- Distância percorrida, duração, cadência
- Dados de sessões de treino e execuções

### 1.3 Dados de Dispositivos e Integrações
- Identificadores de dispositivos wearables (Garmin, Coros, Apple Watch via Strava)
- Tokens de autenticação de integrações (Strava, TrainingPeaks)
- Dados importados automaticamente de plataformas terceiras

### 1.4 Dados de Uso do Aplicativo
- Eventos de navegação e interação (analytics)
- Logs de erros e diagnósticos
- Preferências de configuração (tema, unidades, visibilidade no ranking)

### 1.5 Dados Financeiros
- Saldo de OmniCoins
- Histórico de transações dentro da plataforma
- Dados de pagamento são processados por terceiros (Stripe, MercadoPago) e não armazenados por nós

---

## 2. Finalidade da Coleta

| Finalidade | Base Legal (LGPD) |
|---|---|
| Criação e manutenção da conta do usuário | Execução de contrato |
| Registro e análise de treinos e corridas | Execução de contrato |
| Participação em desafios e rankings | Execução de contrato / Consentimento |
| Verificação de integridade (anti-cheat) | Legítimo interesse |
| Importação automática de atividades via Strava/wearables | Consentimento |
| Envio de notificações push sobre desafios e assessoria | Consentimento |
| Melhoria do produto e analytics agregados | Legítimo interesse |
| Processamento de pagamentos e gestão de OmniCoins | Execução de contrato |

---

## 3. Compartilhamento de Dados

Seus dados podem ser compartilhados com:

- **Assessoria esportiva (coaching group):** Coaches e administradores da sua assessoria podem visualizar seus dados de treino, presença, status e progresso.
- **Rankings e leaderboards:** Seu nome e métricas de desempenho podem ser exibidos em rankings, conforme sua configuração de privacidade.
- **Feed de atividades:** Suas corridas podem aparecer no feed da assessoria, conforme sua configuração de privacidade.
- **Provedores de serviço:**
  - Supabase (infraestrutura e banco de dados)
  - Strava (importação de atividades, mediante autorização)
  - TrainingPeaks (sincronização de treinos, mediante autorização)
  - Stripe / MercadoPago (processamento de pagamentos)
  - Firebase / serviço de push notifications

**Não vendemos, alugamos ou compartilhamos seus dados pessoais com terceiros para fins de marketing.**

---

## 4. Retenção de Dados

| Tipo de Dado | Período de Retenção |
|---|---|
| Dados de perfil | Enquanto a conta estiver ativa |
| Dados de treino e atividade | Enquanto a conta estiver ativa |
| Logs e analytics | [DEFINIR — sugerido: 12 meses] |
| Dados financeiros (ledger) | [DEFINIR — conforme obrigação fiscal] |
| Dados após exclusão de conta | Removidos em até 30 dias, exceto obrigações legais |

---

## 5. Direitos do Titular (LGPD — Lei 13.709/2018)

Conforme a Lei Geral de Proteção de Dados (LGPD), você tem os seguintes direitos:

1. **Acesso:** Solicitar uma cópia dos seus dados pessoais armazenados.
2. **Correção:** Solicitar a correção de dados incompletos, inexatos ou desatualizados.
3. **Exclusão (Eliminação):** Solicitar a exclusão dos seus dados pessoais. A exclusão da conta pode ser realizada diretamente pelo aplicativo.
4. **Portabilidade:** Solicitar a transferência dos seus dados para outro fornecedor de serviço, em formato estruturado.
5. **Revogação de consentimento:** Revogar a qualquer momento o consentimento dado para o tratamento de dados.
6. **Informação sobre compartilhamento:** Saber com quais entidades públicas e privadas seus dados foram compartilhados.
7. **Oposição:** Opor-se ao tratamento de dados quando realizado com base em legítimo interesse.

Para exercer qualquer destes direitos, entre em contato pelo e-mail indicado na seção 6.

---

## 6. Contato

Para dúvidas, solicitações ou exercício de direitos relacionados à privacidade:

- **E-mail:** [INSERIR EMAIL DO DPO / RESPONSÁVEL]
- **Responsável (Encarregado de Dados / DPO):** [INSERIR NOME]
- **Endereço:** [INSERIR ENDEREÇO DA EMPRESA]

---

## 7. Segurança

Adotamos medidas técnicas e organizacionais para proteger seus dados, incluindo:

- Criptografia em trânsito (TLS/HTTPS)
- Row Level Security (RLS) no banco de dados
- Autenticação via JWT com verificação server-side
- Tokens de integração armazenados de forma segura
- Logs de auditoria para ações administrativas

---

## 8. Alterações nesta Política

Esta política pode ser atualizada periodicamente. Notificaremos os usuários sobre mudanças significativas por meio do aplicativo ou e-mail.

---

> **NOTA:** Este é um documento-base (stub) que deve ser revisado por assessoria jurídica antes da publicação. Os campos marcados com [COLCHETES] devem ser preenchidos com as informações definitivas.
