# SCOPE.md — Escopo Funcional do MVP (CONGELADO)

> **Status:** CONGELADO
> **Data:** 2025-01-10
> **Sprint:** 0.1
> **Regra:** Qualquer item nao marcado como [ENTRA NO MVP] e considerado FORA.

---

## 1. VISAO DO PRODUTO

Aplicativo mobile de corrida com GPS que permite ao corredor registrar treinos,
visualizar metricas basicas e competir contra si mesmo atraves de um Ghost Runner local.

---

## 2. FUNCIONALIDADES — DECISAO FINAL

### [ENTRA NO MVP]

| # | Funcionalidade | Descricao Objetiva |
|---|---|---|
| F1 | Registro de corrida GPS | Capturar coordenadas GPS em tempo real durante a corrida, com start/pause/stop |
| F2 | Calculo de metricas | Calcular distancia (km), pace (min/km) e tempo total a partir dos pontos GPS |
| F3 | Persistencia local offline | Salvar todas as corridas no dispositivo sem necessidade de internet |
| F4 | Visualizacao basica de mapa | Exibir o trajeto da corrida sobre um mapa apos finalizacao |
| F5 | Ghost Runner (local) | Replay de uma corrida anterior como "fantasma" para comparacao em tempo real |
| F6 | Anti-cheat basico | Validacao local de velocidade maxima plausivel e deteccao de saltos GPS absurdos |
| F7 | Sincronizacao manual | Botao explicito para enviar corridas salvas localmente para o servidor quando online |

### [FORA DO MVP]

| # | Funcionalidade | Motivo da Exclusao |
|---|---|---|
| X1 | Ranking global | Requer backend complexo, moderacao e escala |
| X2 | Compartilhamento social | Feature de engajamento, nao essencial para validacao core |
| X3 | Musica integrada | Complexidade de integracao com Spotify/Apple Music |
| X4 | IA de performance | Requer coleta de dados historicos significativa primeiro |
| X5 | Multiplayer em tempo real | Requer WebSocket, sincronizacao de estado e infra dedicada |

---

## 3. LIMITES EXPLICITOS

### O que o MVP FAZ:
- Funciona 100% offline (exceto sync manual)
- Roda em um unico dispositivo
- Dados ficam no dispositivo ate sync explicito
- Ghost Runner compara apenas contra corridas do proprio usuario
- Anti-cheat roda apenas localmente (sem validacao server-side)

### O que o MVP NAO FAZ:
- Nao cria conta de usuario (autenticacao e escopo de sync, minima)
- Nao envia notificacoes push
- Nao integra com wearables
- Nao importa/exporta arquivos GPX
- Nao tem modo de ciclismo ou caminhada (apenas corrida)
- Nao tem planos de treino
- Nao tem feed social
- Nao tem achievements/badges

---

## 4. CRITERIOS DE ACEITACAO DO ESCOPO

- [x] Toda funcionalidade imaginada esta listada
- [x] Toda funcionalidade tem marcacao explicita (ENTRA ou FORA)
- [x] Nenhum item esta ambiguo ou "talvez"
- [x] Motivo de exclusao documentado para cada item FORA
- [x] Limites explicitos definidos (o que FAZ vs o que NAO FAZ)
- [x] Arquivo congelado — alteracoes so via Sprint dedicada

---

## 5. REGRA DE MUDANCA

> Para adicionar ou remover qualquer item deste escopo:
> 1. Abrir uma Sprint especifica de "Revisao de Escopo"
> 2. Justificar com impacto em prazo e complexidade
> 3. Atualizar este documento com data e motivo da alteracao
> 4. Recongelar

---

*Documento gerado na Sprint 0.1 — Definicao de Escopo Funcional*
