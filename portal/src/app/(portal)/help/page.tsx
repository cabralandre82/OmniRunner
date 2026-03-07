import type { Metadata } from "next";
import { HelpCenterContent } from "./help-center-content";
import type { HelpCategory } from "./help-center-content";

export const metadata: Metadata = { title: "Central de Ajuda" };
export const dynamic = "force-dynamic";

const HELP_CATEGORIES: HelpCategory[] = [
  {
    id: "primeiros-passos",
    label: "Primeiros Passos",
    articles: [
      {
        id: "config-assessoria",
        title: "Como configurar sua assessoria",
        content: `1. Acesse Configurações no menu lateral (ícone de engrenagem).
2. Na seção "Identidade Visual", faça upload do logo da sua assessoria e defina as cores primárias.
3. Configure o "Gateway de Pagamento Preferido" (Mercado Pago ou Stripe) para cobranças.
4. Em "Equipe", convide treinadores e assistentes usando o e-mail deles (precisam já ter conta na plataforma).
5. Acesse Configurações > Pagamentos para vincular sua conta Asaas ou Stripe e ativar cobranças.`,
      },
      {
        id: "adicionar-atletas",
        title: "Como adicionar atletas",
        content: `1. Vá em Atletas no menu lateral.
2. Clique em "Adicionar atleta" ou "Convidar".
3. Informe o e-mail do atleta. Ele receberá um convite para criar conta e entrar na sua assessoria.
4. Alternativamente, compartilhe o link de convite único da sua assessoria (Configurações > Equipe).
5. Após aceitar, o atleta aparecerá na lista. Você pode atribuir planos e treinos a partir daí.`,
      },
      {
        id: "criar-atribuir-treinos",
        title: "Como criar e atribuir treinos",
        content: `Criar templates:
1. Acesse Treinos > Templates.
2. Clique em "Novo template" e preencha nome, descrição e estrutura do treino (blocos, séries, descansos).
3. Salve o template para reutilizar.

Atribuir treinos:
1. Vá em Treinos > Atribuir Treinos.
2. Selecione um ou mais atletas.
3. Escolha o template e a data de entrega.
4. Opcionalmente, personalize a carga ou observações.
5. Confirme. O atleta verá o treino no app na data programada.`,
      },
    ],
  },
  {
    id: "financeiro",
    label: "Financeiro",
    articles: [
      {
        id: "cobrar-asaas",
        title: "Como cobrar atletas via Asaas",
        content: `1. Em Configurações > Pagamentos, vincule sua conta Asaas (chaves de API).
2. Crie planos em Financeiro > Planos (ex.: Mensal, Trimestral) com valor e recorrência.
3. Vá em Financeiro > Atribuir Plano e associe o plano ao atleta.
4. O sistema gera cobranças automaticamente via Asaas (boleto, PIX ou cartão).
5. Acompanhe em Financeiro > Assinaturas e Histórico de Cobranças.`,
      },
      {
        id: "omnicoins",
        title: "Como funciona o sistema de OmniCoins",
        content: `OmniCoins são créditos internos da plataforma usados para:
• Pagar taxas de treinos, campeonatos e funcionalidades premium
• Recompensar atletas (badges, desafios)

Fluxo:
1. Sua assessoria compra créditos (recarga manual ou automática).
2. Os créditos ficam em Saldo OmniCoins (custódia).
3. Use "Distribuir OmniCoins" para dar créditos aos atletas.
4. Atletas gastam em treinos, desafios etc. O saldo é debitado da custódia.
5. Acompanhe em Financeiro > Saldo OmniCoins e Transferências OmniCoins.`,
      },
      {
        id: "kpis-dashboard",
        title: "Como interpretar os KPIs do dashboard financeiro",
        content: `Principais indicadores:

• Receita total: Soma das cobranças realizadas no período.
• MRR (Receita Recorrente Mensal): Valor médio mensal das assinaturas ativas.
• Churn: Taxa de cancelamento. Quanto menor, melhor.
• Inadimplência: Cobranças vencidas ou não pagas.
• Taxa de conversão: Novos atletas que efetivaram pagamento vs. convites enviados.

Use os filtros de período para comparar meses e identificar tendências.`,
      },
      {
        id: "custodia-transferencias",
        title: "Como funciona a custódia e transferências",
        content: `Custódia:
• É a conta onde ficam os OmniCoins da sua assessoria.
• Você deposita valor (em USD) e recebe créditos equivalentes.
• O saldo "disponível" é o que pode ser usado; "reservado" é o já comprometido com atletas.

Transferências:
1. Em Transferências OmniCoins, você pode enviar créditos para outras assessorias (parceiras).
2. Útil para ligas, campeonatos compartilhados ou parcerias.
3. Informe o grupo de destino e o valor. A transferência é instantânea.`,
      },
    ],
  },
  {
    id: "engajamento",
    label: "Engajamento",
    articles: [
      {
        id: "criar-desafios",
        title: "Como criar desafios para seus atletas",
        content: `1. Acesse Engajamento no menu lateral.
2. Vá em "Desafios" (ou equivalente na sua versão).
3. Clique em "Criar desafio".
4. Defina nome, descrição, tipo (ex.: distância, tempo, frequência) e período.
5. Escolha os atletas participantes e a recompensa (OmniCoins ou badge).
6. Publique. Os atletas verão o desafio no app e poderão participar.`,
      },
      {
        id: "badges-missoes",
        title: "Como funciona o sistema de badges e missões",
        content: `Badges:
• São conquistas visuais que reconhecem o desempenho do atleta.
• Configure em Configurações > Badges: crie critérios (ex.: "10 treinos em um mês", "primeiro 5K").
• Atletas desbloqueiam badges automaticamente ao atingir as metas.

Missões:
• São tarefas ou objetivos que você pode definir (ex.: "Complete 3 treinos esta semana").
• Podem dar OmniCoins ou pontos. Acompanhe o progresso em Engajamento.`,
      },
      {
        id: "mural-avisos",
        title: "Como usar o mural de avisos",
        content: `1. Acesse Engajamento > Mural (ou Mural de Avisos).
2. Clique em "Novo aviso".
3. Escreva o título e o texto. Você pode marcar como destaque ou fixar no topo.
4. Escolha o público: todos os atletas ou grupos específicos.
5. Publique. O aviso aparece no app para os atletas selecionados.
6. Use para comunicar treinos cancelados, eventos, dicas ou novidades.`,
      },
    ],
  },
  {
    id: "campeonatos",
    label: "Campeonatos",
    articles: [
      {
        id: "criar-campeonato",
        title: "Como criar um campeonato",
        content: `1. Vá em Treinos > Campeonatos.
2. Clique em "Criar campeonato".
3. Preencha nome, descrição, datas de início e fim.
4. Defina as regras de pontuação (ex.: por treino concluído, por distância).
5. Adicione as provas/etapas do campeonato.
6. Selecione os atletas participantes (ou abra inscrições).
7. Publique. Os atletas verão o campeonato e suas colocações em tempo real.`,
      },
      {
        id: "convidar-assessorias",
        title: "Como convidar assessorias parceiras",
        content: `1. No campeonato criado, vá em "Convidar assessorias" ou "Parceiros".
2. Gere um link de convite ou informe o e-mail do administrador da assessoria parceira.
3. A assessoria parceira aceita o convite e seus atletas entram no mesmo campeonato.
4. O ranking passa a incluir atletas de todas as assessorias participantes.
5. Útil para ligas regionais, copas entre assessorias e eventos colaborativos.`,
      },
    ],
  },
  {
    id: "configuracoes",
    label: "Configurações",
    articles: [
      {
        id: "integrar-strava",
        title: "Como integrar com Strava",
        content: `1. Acesse Configurações (ou a seção de integrações).
2. Procure por "Strava" ou "Integrações".
3. Clique em "Conectar Strava" e autorize o acesso com sua conta Strava.
4. Os atletas também precisam conectar o Strava no app para sincronizar treinos.
5. Treinos executados no Strava podem ser importados automaticamente para a plataforma.
6. Verifique as permissões (leitura de atividades) para que a sincronização funcione.`,
      },
      {
        id: "configurar-pagamentos",
        title: "Como configurar pagamentos",
        content: `1. Vá em Configurações > Pagamentos (apenas administradores).
2. Escolha o gateway: Asaas (Brasil) ou Stripe (internacional).
3. Para Asaas: insira a API Key e o Webhook URL fornecido pela plataforma.
4. Para Stripe: conecte sua conta Stripe e salve um método de pagamento para recargas.
5. Configure a Recarga Automática (opcional): defina um limite mínimo de créditos e um produto para cobrança automática.
6. Teste com um valor baixo antes de ativar em produção.`,
      },
      {
        id: "gerenciar-equipe",
        title: "Como gerenciar sua equipe",
        content: `Convidar:
• Configurações > Equipe > Convidar Membro.
• Informe o e-mail (o usuário precisa ter conta na plataforma).
• Escolha a função: Admin, Treinador ou Assistente.

Permissões:
• Admin: acesso total, incluindo pagamentos e exclusão de membros.
• Treinador: atletas, treinos, engajamento, financeiro (sem configurações sensíveis).
• Assistente: geralmente apenas visualização e tarefas operacionais.

Remover:
• Apenas admins podem remover. Assistentes podem ser removidos por admin ou treinador.
• O membro removido perde acesso imediato à assessoria.`,
      },
    ],
  },
  {
    id: "financeiro-avancado",
    label: "Financeiro Avançado",
    articles: [
      {
        id: "swap-lastro",
        title: "Como funciona o Swap de Lastro",
        content: `O lastro é a reserva em USD que garante o valor dos OmniCoins na plataforma. Cada OmniCoin tem lastro em dólar.

Swap entre assessorias:
1. Acesse Financeiro > Swap (ou FX/Swap no menu).
2. O Swap de Lastro permite que assessorias comprem ou vendam lastro entre si.
3. Útil quando uma assessoria precisa de liquidez (vender lastro) e outra tem excesso (comprar lastro).
4. As operações são feitas diretamente entre assessorias, sem passar pela plataforma central.
5. Consulte a tela de Swap para ver ofertas disponíveis e executar a operação desejada.`,
      },
      {
        id: "conversao-cambial-fx",
        title: "Como funciona a Conversão Cambial (FX)",
        content: `A conversão cambial permite depositar em moeda local e usar OmniCoins em USD.

Depósito:
1. Ao fazer um depósito, você informa o valor em sua moeda local (BRL, etc.).
2. O sistema converte automaticamente para USD usando a taxa do dia.
3. Um spread (margem) pode ser aplicado na conversão — consulte as taxas em Configurações > Pagamentos.
4. O valor em USD é creditado na sua custódia e vira OmniCoins disponíveis.

Saque:
1. Em Saque ou Withdraw, você solicita o valor em USD.
2. O sistema converte para sua moeda local na taxa vigente.
3. O valor é enviado para a conta cadastrada (conta bancária ou gateway).`,
      },
      {
        id: "distribuir-omnicoins",
        title: "Como distribuir OmniCoins para atletas",
        content: `1. Acesse Financeiro > Distribuir OmniCoins (ou Distribuições no menu).
2. Verifique seu saldo disponível em OmniCoins na custódia.
3. Selecione um ou mais atletas da sua assessoria.
4. Informe a quantidade de OmniCoins a distribuir para cada atleta.
5. Opcionalmente, adicione uma observação (ex.: "Bônus desafio março").
6. Revise e confirme a operação.
7. Os créditos são debitados da sua custódia e creditados na carteira do atleta.
8. Os atletas podem usar os OmniCoins em treinos, campeonatos e funcionalidades premium.`,
      },
      {
        id: "recarga-automatica",
        title: "Como configurar a Recarga Automática",
        content: `A Recarga Automática evita ficar sem OmniCoins quando o saldo está baixo.

Configuração:
1. Acesse Configurações > Pagamentos (ou Financeiro > Recarga Automática).
2. Ative a opção "Recarga Automática".
3. Defina o limite mínimo: quando o saldo em OmniCoins cair abaixo desse valor, a recarga é disparada.
4. Escolha o valor a ser recarregado (ex.: 100 USD) ou um pacote pré-definido.
5. Vincule um método de pagamento (cartão ou conta) para cobrança automática.
6. Salve. O sistema monitora seu saldo e cobra automaticamente quando necessário.
7. Você receberá um e-mail de confirmação a cada recarga realizada.`,
      },
    ],
  },
  {
    id: "operacoes",
    label: "Operações",
    articles: [
      {
        id: "auditoria",
        title: "Como usar a Auditoria",
        content: `A página de Auditoria monitora a integridade da custódia e operações financeiras.

O que é exibido:
1. Acesse Operações > Auditoria (ou Auditoria no menu).
2. A tela mostra os invariantes de custódia: regras que garantem que o saldo total bate com as obrigações.
3. Exemplos: saldo da assessoria = soma das carteiras dos atletas + reservas.

Se houver violações:
1. Violações aparecem em destaque (vermelho ou alerta).
2. Não execute novas operações até resolver. Entre em contato com o suporte.
3. O suporte pode ajudar a identificar a causa (ex.: inconsistência em transferência ou distribuição).
4. Em casos raros, pode ser necessário um ajuste manual pela plataforma.`,
      },
      {
        id: "crm-atletas",
        title: "Como usar o CRM de Atletas",
        content: `O CRM ajuda a organizar e acompanhar o relacionamento com seus atletas.

Tags e notas:
1. Acesse Atletas > CRM (ou CRM no menu lateral).
2. Crie tags personalizadas (ex.: "VIP", "Novato", "Em risco") e aplique aos atletas.
3. Adicione notas em cada atleta: observações, histórico de contato, preferências.
4. Use filtros para listar atletas por tag, status ou data de entrada.

Status e alertas:
• Status: ativo, inativo, inadimplente, etc. Atualize conforme a situação.
• Alertas de risco: o sistema pode sinalizar atletas com pagamentos atrasados ou baixa atividade.
• Use o CRM para priorizar follow-ups e ações de retenção.`,
      },
      {
        id: "exportar-dados",
        title: "Como exportar dados",
        content: `1. Acesse Operações > Exportar (ou Exportar Dados no menu).
2. Escolha o tipo de exportação:
   • Atletas: lista de atletas com dados cadastrais e status.
   • Financeiro: cobranças, assinaturas, transferências OmniCoins.
   • Treinos: histórico de treinos atribuídos e executados.
   • Outros: conforme disponível na sua versão.
3. Selecione o período (data inicial e final) quando aplicável.
4. Escolha o formato: CSV ou Excel.
5. Clique em "Gerar exportação". O arquivo será processado e disponibilizado para download.
6. Você receberá um link por e-mail se a exportação for grande.`,
      },
      {
        id: "verificar-atletas",
        title: "Como verificar atletas",
        content: `A verificação valida a identidade e elegibilidade do atleta para certas funcionalidades.

O que é verificação:
• Atletas verificados têm identidade e dados conferidos pela plataforma.
• Necessário para participar de campeonatos oficiais, receber premiações ou acessar recursos sensíveis.

Passos para verificar:
1. Acesse Atletas > Verificação (ou Verificação no menu).
2. Liste os atletas pendentes de verificação.
3. O atleta envia documentos (RG, CPF, etc.) pelo app ou portal.
4. A plataforma avalia automaticamente ou encaminha para revisão manual.
5. Após aprovação, o atleta fica com status "Verificado".
6. Atletas não verificados podem ter acesso limitado a algumas funcionalidades.`,
      },
    ],
  },
];

export default function HelpPage() {
  return (
    <div className="mx-auto max-w-4xl">
      <div className="mb-8">
        <h1 className="text-display-md text-content-primary font-bold">
          Central de Ajuda
        </h1>
        <p className="mt-2 text-body text-content-secondary">
          Encontre respostas e guias passo a passo para usar o portal da sua assessoria.
        </p>
      </div>
      <HelpCenterContent categories={HELP_CATEGORIES} />
    </div>
  );
}
