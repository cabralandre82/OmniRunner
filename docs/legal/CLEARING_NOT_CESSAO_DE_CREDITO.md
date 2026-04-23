# Clearing settlements ≠ Cessão de crédito (Art. 286 CC)

> **Versão:** 1.0
> **Vigência:** 2026-04-23
> **Status:** Aceito
> **Cross-ref ADR:** [`docs/adr/008-swap-as-off-platform-credit-cession.md`](../adr/008-swap-as-off-platform-credit-cession.md)

---

## 1. Pergunta

A função `public.settle_clearing` (e seus correlatos no módulo de
custódia) move saldo de devedor para credor entre membros de uma
mesma assessoria. Sob certa interpretação, isto seria **cessão de
crédito** (Código Civil Art. 286), o que exigiria instrumento
formal de cessão e — para valores superiores a 30 salários
mínimos — registro em cartório (Lei 6.015/73 Art. 130).

Este documento é a posição **canônica** da Omni Runner sobre por
que `clearing_settlements` **não** caracteriza cessão de crédito,
e quais salvaguardas reforçam essa interpretação.

---

## 2. Fundamento jurídico

### 2.1 Cessão de crédito (CC Art. 286 ss.)

Cessão de crédito pressupõe:

1. **Negócio bilateral** entre cedente e cessionário com causa
   própria (alienação, garantia, etc).
2. **Notificação ao devedor** (CC Art. 290) ou ciência inequívoca.
3. **Substituição** do credor: o cessionário assume a posição
   contratual do cedente perante o devedor.

### 2.2 Compensação (CC Art. 368 ss.)

Compensação ocorre quando duas pessoas são, ao mesmo tempo,
credoras e devedoras umas das outras: as obrigações se extinguem
até onde se compensarem. **Não há transferência de crédito** —
há extinção mútua.

### 2.3 Serviço de clearing como serviço acessório

`settle_clearing` opera em ambiente fechado (membros de uma
mesma assessoria, todos partes do mesmo *Termo de Adesão*). As
obrigações são geradas e extintas dentro do mesmo perímetro
contratual. A operação é, juridicamente, **compensação
multilateral** intermediada — não cessão. Caracterização de
serviço acessório (Termo de Adesão da Assessoria, cláusula
4.2) afasta a aplicação do regime de cessão.

---

## 3. Salvaguardas operacionais

Para reforçar a tese de "compensação intermediada, não cessão":

1. **Limite por evento de clearing.** Cada `settle_clearing` é
   capped em valor agregado por janela móvel de 30 dias por
   assessoria (parametrizável; padrão R$ 100.000). Acima disso,
   exige aprovação do `admin_master` da assessoria via UI
   dedicada.
2. **Termo de adesão.** O Termo de Adesão da Assessoria
   (`docs/legal/TERMO_ADESAO_ASSESSORIA.md`) contém cláusula
   expressa autorizando o serviço de clearing como serviço
   acessório do produto principal e equiparando-o a compensação
   multilateral.
3. **Recibo eletrônico.** Cada `settle_clearing` gera registro
   em `audit_logs.category='clearing'` com hash SHA-256 do
   payload (devedor, credor, valor, timestamp). Esse hash é
   exposto na UI ao membro como "número do recibo".
4. **Reconciliação diária.** O job `reconcile_clearing_daily`
   verifica que `SUM(settled) == SUM(canceled) - SUM(open)` por
   assessoria.
5. **Sem repasse fora do perímetro.** Membros que saem da
   assessoria (`coaching_members.role -> NULL` ou registro
   removido) têm clearing **encerrado** antes da saída ser
   efetivada (validado por trigger).

---

## 4. Quando esta interpretação muda

A posição neste documento deve ser revisitada se **qualquer** das
condições abaixo for verdadeira:

| Trigger | Próxima ação |
|---|---|
| Volume mensal agregado por assessoria > R$ 1.000.000 | Reavaliar com PJ tributarista; possivelmente migrar para IP autorizado pelo BCB. |
| Membros de assessorias diferentes podem fazer clearing entre si | Vira cessão (perímetro perdido) — ler ADR-008 e replanjar. |
| ANPD/BCB emitir circular específica sobre netting privado | Compliance recalibra. |
| Adoção de feature de "transferência" entre wallets de assessorias diferentes | Retirar essa feature OU formalizar cessão. |

---

## 5. Diferença para swap_orders (ADR-008)

`swap_orders` (FX BRL↔USD entre membros) **é** cessão de crédito
formal — formalizada como off-platform credit cession via ADR-008.
A diferença é:

| Aspecto | clearing_settlements | swap_orders |
|---|---|---|
| Cross-assessoria | não | sim |
| Moeda diferente | não (BRL ↔ BRL) | sim (BRL ↔ USD) |
| Bilateral c/ contraparte ID | não (compensação) | sim (cessão) |
| Tributo IOF | não | não (cessão onerosa) |
| Categoria CC | Art. 368 (compensação) | Art. 286 (cessão) |

---

## 6. Cross-references

- `docs/adr/008-swap-as-off-platform-credit-cession.md` — ADR canonical
- `docs/adr/007-custody-clearing-model.md` — modelo operacional
- `docs/legal/TERMO_ADESAO_ASSESSORIA.md` — cláusula 4.2 (clearing)
- `docs/compliance/BCB_CLASSIFICATION.md` — posicionamento BCB (L09-01)
- `docs/audit/findings/L09-05` — IOF primitive
- `docs/audit/findings/L03-08` — invariantes de custódia

---

## 7. Histórico de revisão

| Versão | Data | Autor | Mudança |
|---|---|---|---|
| 1.0 | 2026-04-23 | Audit Wave 2 (Batch K) | Documento canônico inicial — fecha L09-11. |
