import type { Metadata } from "next";

export const metadata: Metadata = { title: "Glossário" };

const TERMS = [
  {
    term: "OmniCoin",
    definition:
      "Crédito interno da plataforma. Cada OmniCoin equivale a US$ 1.00 e é garantida por dinheiro real em custódia. Assessorias compram OmniCoins, distribuem para atletas, e eles gastam em treinos, desafios e funcionalidades premium.",
    relatedPages: ["/custody", "/distributions", "/credits"],
  },
  {
    term: "Custódia",
    definition:
      "Conta onde fica o dinheiro real (em dólares) que garante as OmniCoins da sua assessoria. É como uma conta bancária: você deposita dinheiro, e esse saldo permite emitir OmniCoins para seus atletas. O saldo de custódia sempre deve ser igual ou maior que as OmniCoins em circulação.",
    relatedPages: ["/custody"],
  },
  {
    term: "Lastro",
    definition:
      "É o dinheiro real (em dólares) depositado na conta de custódia que garante o valor das OmniCoins. Cada OmniCoin precisa de US$ 1.00 de lastro. Sem lastro suficiente, não é possível emitir novas OmniCoins.",
    relatedPages: ["/custody", "/swap"],
  },
  {
    term: "Swap de Lastro",
    definition:
      "Mercado B2B onde assessorias podem comprar e vender lastro entre si. Útil quando uma assessoria precisa de mais lastro rapidamente, sem depositar dinheiro novo. Uma assessoria com lastro sobrando pode vender para outra que precisa.",
    relatedPages: ["/swap"],
  },
  {
    term: "Transferências (Clearing)",
    definition:
      "Processo automático de movimentação de OmniCoins entre assessorias. Acontece quando atletas de uma assessoria gastam OmniCoins emitidas por outra (ex.: em campeonatos interclub). O sistema calcula automaticamente quem deve o quê e faz a compensação.",
    relatedPages: ["/clearing"],
  },
  {
    term: "Compensação Interclub",
    definition:
      "Quando OmniCoins de um emissor (assessoria A) são usadas por atletas em eventos de outra assessoria (assessoria B), ocorre uma compensação: o sistema transfere o valor correspondente da custódia de A para a de B, descontando taxas.",
    relatedPages: ["/clearing"],
  },
  {
    term: "Distribuição",
    definition:
      "Ação de transferir OmniCoins do estoque da assessoria para os atletas. Os atletas recebem créditos que podem usar em treinos, desafios e funcionalidades premium dentro do app.",
    relatedPages: ["/distributions"],
  },
  {
    term: "Conversão Cambial (FX)",
    definition:
      "Processo de conversão entre moeda local (ex.: BRL) e dólares (USD). Quando você deposita em reais, o sistema converte para USD usando a cotação do momento. Ao retirar, converte de volta para sua moeda local. Um pequeno spread é aplicado como taxa.",
    relatedPages: ["/fx"],
  },
  {
    term: "Spread",
    definition:
      "Diferença percentual entre a cotação de referência e a cotação aplicada na conversão cambial. É a taxa cobrada pela plataforma pelo serviço de câmbio. Configurado pelo administrador da plataforma.",
    relatedPages: ["/fx"],
  },
  {
    term: "Split (Auto-Split)",
    definition:
      "Divisão automática de pagamentos. Quando um atleta paga sua mensalidade, o sistema divide o valor automaticamente: a maior parte vai para a assessoria, e uma pequena porcentagem (comissão) vai para a plataforma.",
    relatedPages: ["/financial"],
  },
  {
    term: "Invariante Contábil",
    definition:
      "Regra que deve sempre ser verdadeira para garantir a integridade financeira. Exemplo: 'o total depositado deve ser igual ao total em uso + disponível'. O sistema verifica essas regras automaticamente e alerta se algo estiver inconsistente.",
    relatedPages: ["/audit", "/custody"],
  },
  {
    term: "Recarga Automática",
    definition:
      "Configuração que permite reabastecer seu estoque de OmniCoins automaticamente quando ele cai abaixo de um limite mínimo. O sistema gera uma cobrança automática no seu gateway de pagamento e credita as OmniCoins após confirmação.",
    relatedPages: ["/settings/payments"],
  },
  {
    term: "Gateway de Pagamento",
    definition:
      "Serviço externo que processa pagamentos reais (cartão, PIX, boleto). A plataforma suporta Asaas (Brasil) e Stripe (internacional). Você configura em Configurações > Pagamentos.",
    relatedPages: ["/settings/payments"],
  },
  {
    term: "Assessoria Parceira",
    definition:
      "Assessoria amiga com quem você tem parceria na plataforma. Assessorias parceiras podem participar juntas de campeonatos, compartilhar eventos e fazer transferências de OmniCoins entre si.",
    relatedPages: ["/championships"],
  },
  {
    term: "Badge",
    definition:
      "Conquista visual que reconhece o desempenho de um atleta. Pode ser desbloqueada ao atingir metas como completar treinos, participar de desafios ou alcançar marcos de distância.",
    relatedPages: ["/badges"],
  },
  {
    term: "XP (Pontos de Experiência)",
    definition:
      "Pontos ganhos pelo atleta ao completar atividades, treinos e desafios. O acúmulo de XP aumenta o nível do atleta no sistema de gamificação.",
    relatedPages: [],
  },
  {
    term: "Temporada",
    definition:
      "Período definido (ex.: trimestral) com rankings próprios, metas e recompensas. Ao final da temporada, os rankings são congelados e uma nova temporada começa do zero.",
    relatedPages: [],
  },
] as const;

export default function GlossaryPage() {
  return (
    <div className="mx-auto max-w-4xl space-y-8">
      <div>
        <h1 className="text-display-md font-bold text-content-primary">
          Glossário
        </h1>
        <p className="mt-2 text-body text-content-secondary">
          Definições de todos os termos e conceitos usados na plataforma.
        </p>
      </div>

      <div className="space-y-4">
        {TERMS.map((item) => (
          <div
            key={item.term}
            id={item.term.toLowerCase().replace(/\s+/g, "-")}
            className="rounded-xl border border-border bg-surface p-5 shadow-sm"
          >
            <h2 className="text-lg font-semibold text-content-primary">
              {item.term}
            </h2>
            <p className="mt-2 text-sm leading-relaxed text-content-secondary">
              {item.definition}
            </p>
            {item.relatedPages.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-2">
                {item.relatedPages.map((page) => (
                  <a
                    key={page}
                    href={page}
                    className="inline-flex rounded-full bg-brand-soft px-3 py-1 text-xs font-medium text-brand hover:bg-brand/20 transition-colors"
                  >
                    Ver página →
                  </a>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
