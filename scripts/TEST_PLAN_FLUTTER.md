# Flutter Test Plan — Verificação de Atleta & Gate de Monetização

> Sprint 22.6.0 — QA Manual
>
> Todas as regras congeladas se aplicam:
> - Docs são lei
> - stake=0 livre; stake>0 exige VERIFIED
> - App exibe; server decide
> - ZERO override admin

---

## Pre-requisitos

1. Usuário de teste autenticado no app
2. Conta em estado UNVERIFIED (usar dashboard Supabase para resetar se necessário)
3. Conexão com internet (para testar server calls)

---

## TC-01: Tela de Verificação — Estado Inicial

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Navegar para AthleteVerificationScreen | Tela carrega sem crash |
| 2 | Observar status badge | Mostra "Não Verificado" com ícone cinza |
| 3 | Observar progress bar | 0% (ou proporcional aos checks completos) |
| 4 | Observar checklist | 4 itens: corridas válidas, integridade, consistência, trust score |
| 5 | Observar item "corridas válidas" | "Faltam 7 corridas (0/7)" |
| 6 | Observar item "trust score" | "0/80 pontos" |
| 7 | Observar seção "Seus números" | Corridas: 0, Distância: 0.0 km |

## TC-02: Tela de Verificação — Pull-to-refresh

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Pull down na tela | Indicator aparece, dados recarregam |
| 2 | Soltar | Dados atualizados sem crash |

## TC-03: Tela de Verificação — Botão Reavaliar

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Tap "Reavaliar agora" | Botão mostra spinner + "Avaliando..." |
| 2 | Aguardar resposta | Tela atualiza com novos dados |
| 3 | Tap "Reavaliar" novamente | Resultado idempotente (mesmos dados) |

## TC-04: Tela de Verificação — Error State

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Ativar modo avião | — |
| 2 | Navegar para AthleteVerificationScreen | Tela mostra error view com ícone de erro |
| 3 | Observar mensagem | "Não foi possível carregar o status de verificação." |
| 4 | Tap "Tentar novamente" | Loading indicator aparece |
| 5 | Desativar modo avião | — |
| 6 | Tap "Tentar novamente" | Dados carregam normalmente |

## TC-05: ChallengeCreateScreen — stake=0 sem VERIFIED

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Abrir ChallengeCreateScreen | Formulário aparece |
| 2 | Preencher campos, manter OmniCoins = 0 | — |
| 3 | Tap "Criar Desafio" | Desafio criado com sucesso |
| 4 | Verificar estado ChallengeCreated | Navega para tela de convite |

**Prova:** stake=0 SEMPRE funciona, independente do status de verificação.

## TC-06: ChallengeCreateScreen — stake>0 sem VERIFIED (GATE)

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Abrir ChallengeCreateScreen | Formulário aparece |
| 2 | Preencher campos, definir OmniCoins = 50 | — |
| 3 | Tap "Criar Desafio" | Modal bottom sheet aparece |
| 4 | Observar modal | Título: "Verificação necessária" |
| 5 | Observar status no modal | Mostra status atual + progresso |
| 6 | Tap "Ver minha verificação" | Navega para AthleteVerificationScreen |
| 7 | Voltar e repetir | Modal aparece novamente (não bypass) |

**Prova:** App bloqueia UX. Mesmo se Flutter gate for burlado, servidor retorna ATHLETE_NOT_VERIFIED.

## TC-07: ChallengeDetailsScreen — Join stake=0 sem VERIFIED

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Receber convite para desafio stake=0 | — |
| 2 | Abrir ChallengeDetailsScreen | Card "Você foi convidado!" aparece |
| 3 | Tap "Aceitar" | Join processado normalmente |

**Prova:** Join em stake=0 SEMPRE funciona.

## TC-08: ChallengeDetailsScreen — Join stake>0 sem VERIFIED (GATE)

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Receber convite para desafio stake>0 | — |
| 2 | Abrir ChallengeDetailsScreen | Card mostra "Inscrição: X OmniCoins" |
| 3 | Tap "Aceitar" | Modal bottom sheet aparece |
| 4 | Observar modal | "Verificação necessária" + status + CTA |
| 5 | Tap "Voltar" | Modal fecha, não faz join |

**Prova:** Join em stake>0 bloqueado no app. Servidor também bloqueia via trigger.

## TC-09: Fluxo Completo — UNVERIFIED → VERIFIED → stake>0 liberado

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Status UNVERIFIED, tentar criar stake>0 | Modal de gate aparece |
| 2 | Completar 7 corridas válidas (> 1km, sem flags) | Corridas sincronizadas |
| 3 | Navegar para AthleteVerificationScreen | — |
| 4 | Tap "Reavaliar agora" | Status muda para VERIFIED |
| 5 | Observar status badge | "Atleta Verificado" (verde) |
| 6 | Observar progress bar | 100% |
| 7 | Voltar para ChallengeCreateScreen | — |
| 8 | Definir stake=100, tap "Criar Desafio" | Desafio criado com sucesso (sem modal) |

**Prova:** Após earning VERIFIED legitimamente, stake>0 é liberado.

## TC-10: Fluxo Completo — VERIFIED → DOWNGRADED → stake>0 bloqueado

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Status VERIFIED | Pode criar stake>0 |
| 2 | Correr com GPS falsificado (trigger integrity flags) | Sessão flagged |
| 3 | Aguardar eval ou tap "Reavaliar" | Status muda para DOWNGRADED |
| 4 | Tentar criar stake>0 | Modal de gate aparece novamente |

**Prova:** DOWNGRADED perde acesso a stake>0. Verificação é dinâmica.

## TC-11: Tela de Verificação — Estado CALIBRATING

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Completar 3 corridas válidas | — |
| 2 | Reavaliar | Status: "Em Calibração" (azul) |
| 3 | Checklist mostra | "Faltam 4 corridas (3/7)" |
| 4 | Progress bar | ~25-50% |

## TC-12: Tela de Verificação — Estado MONITORED

| # | Passo | Resultado Esperado |
|---|-------|-------------------|
| 1 | Completar 7 corridas mas trust < 80 | — |
| 2 | Reavaliar | Status: "Em Observação" (laranja) |
| 3 | Checklist mostra | valid_runs OK, trust NOT OK |
| 4 | Tentar stake>0 | Modal de gate aparece |

---

## Matriz de Cobertura

| Cenário | App Gate | EF Check | RLS | DB Trigger |
|---------|----------|----------|-----|------------|
| CREATE stake=0, UNVERIFIED | Pass-through | Skip | Skip | Skip |
| CREATE stake>0, UNVERIFIED | Modal block | 403 | DENY | RAISE |
| CREATE stake>0, VERIFIED | Pass-through | Pass | ALLOW | Pass |
| CREATE stake>0, DOWNGRADED | Modal block | 403 | DENY | RAISE |
| JOIN stake=0, UNVERIFIED | Pass-through | Skip | n/a | Skip |
| JOIN stake>0, UNVERIFIED | Modal block | 403 | n/a | RAISE |
| JOIN stake>0, VERIFIED | Pass-through | Pass | n/a | Pass |
| UPDATE fee 0→100, UNVERIFIED | n/a (no UI) | n/a | n/a | RAISE |
| Direct DB INSERT, UNVERIFIED | n/a | n/a | DENY | RAISE |

---

## Evidências Necessárias

Para cada TC, capturar:
1. Screenshot da tela/modal
2. Log do console (para verificar chamadas EF)
3. Status final no Supabase Dashboard (athlete_verification table)

## Notas

- Todos os testes assumem conexão com internet ativa (exceto TC-04)
- Para simular VERIFIED/DOWNGRADED rapidamente, usar o script
  `scripts/test_verification_gate.sh` para manipular dados via service_role
- O app NUNCA é fonte de verdade — mesmo pulando todos os testes Flutter,
  o servidor bloqueia via EF + RLS + DB triggers
