# QA-07 — UX Review (Telas, Estados, Lógica para "Dummies")

## 1. Matriz de Telas — App Flutter

| Tela | Título | Loading | Empty State | Error + Retry | Success Feedback | Dinheiro | Status |
|------|--------|---------|-------------|---------------|------------------|----------|--------|
| `staff_training_list_screen` | "Agenda de Treinos" | ✅ CircularProgress | ✅ "Nenhum treino agendado" + hint | ✅ Error msg + "Tentar novamente" | N/A (lista) | ✅ Zero | **PASS** |
| `staff_training_create_screen` | "Novo Treino" / "Editar Treino" | ✅ Spinner | N/A (form) | ✅ Error inline | ❌ **Sem snackbar de sucesso** | ✅ Zero | **WARN** |
| `staff_training_detail_screen` | Título dinâmico | ✅ CircularProgress | ✅ "Nenhuma presença registrada" | ✅ Error + retry + snackbar | ✅ Snackbar | ✅ Zero | **PASS** |
| `staff_training_scan_screen` | "Escanear QR" | ✅ "Processando..." | N/A (câmera) | ✅ Snackbar (erro) | ✅ "Presença registrada com sucesso" | ✅ Zero | **PASS** |
| `athlete_training_list_screen` | "Meus Treinos" | ✅ CircularProgress | ✅ "Nenhum treino agendado" | ❌ **Error sem retry button** | N/A (lista) | ✅ Zero | **FAIL** |
| `athlete_checkin_qr_screen` | "Check-in de Presença" | ✅ CircularProgress | N/A (QR gen) | ✅ Error + "Tentar Novamente" | N/A (mostra QR) | ✅ Zero | **PASS** |
| `athlete_attendance_screen` | "Minha Presença" | ✅ CircularProgress | ✅ "Nenhuma presença registrada" + hint | ✅ Error + "Tentar Novamente" | N/A (lista) | ✅ Zero | **PASS** |
| `staff_crm_list_screen` | "CRM Atletas" | ✅ CircularProgress | ⚠️ "Nenhum atleta encontrado" (texto puro, sem ícone) | ✅ Error + retry | ✅ Snackbar tags | ✅ Zero | **WARN** |
| `staff_athlete_profile_screen` | Nome do atleta | ✅ Per-tab loading | ✅ "Nenhuma nota registrada" | ✅ Error + retry per tab | ✅ Snackbar | ✅ Zero | **PASS** |
| `athlete_my_status_screen` | "Meu Status" | ✅ CircularProgress | ✅ "Status não definido" | ❌ **Error sem retry button** | N/A (read-only) | ✅ Zero | **FAIL** |
| `athlete_my_evolution_screen` | "Minha Evolução" | ✅ CircularProgress | ✅ "Nenhuma presença registrada" | ❌ **Error sem retry button** | N/A (read-only) | ✅ Zero | **FAIL** |
| `announcement_feed_screen` | "Mural de Avisos" + badge | ✅ CircularProgress | ✅ "Nenhum aviso publicado" + ícone | ✅ Error + "Tentar novamente" | N/A (lista) | ✅ Zero | **PASS** |
| `announcement_detail_screen` | Título dinâmico | ✅ CircularProgress | N/A (single entity) | ⚠️ Error msg (sem retry) | ✅ Snackbar "Aviso excluído" | ✅ Zero | **WARN** |
| `announcement_create_screen` | "Novo Aviso" / "Editar Aviso" | ✅ Spinner | N/A (form) | ✅ Error inline | ❌ **Sem snackbar de sucesso** | ✅ Zero | **WARN** |

## 2. Matriz de Telas — Portal

| Página | Título | Loading | Empty State | Error | Dinheiro | Status |
|--------|--------|---------|-------------|-------|----------|--------|
| `/attendance` | "Relatório de Presença" | ⚠️ Suspense (SSR) | ✅ "Nenhum treino encontrado no período." | ❌ **Sem error state** | ✅ Zero | **WARN** |
| `/crm` | "CRM de Atletas" | SSR (sem spinner) | ✅ "Nenhum atleta encontrado." | ❌ **Sem error state** | ✅ Zero | **WARN** |
| `/announcements` | "Mural de Avisos" | SSR (sem spinner) | ❌ **Sem empty state** | ❌ **Sem error state** | ✅ Zero | **FAIL** |
| `/risk` | "Alertas e Risco" | SSR (sem spinner) | ✅ "Nenhum atleta em risco" | ❌ **Sem error state** | ✅ Zero | **WARN** |
| `/exports` | "Central de Exports" | N/A (client form) | N/A | ❌ **Sem feedback no export** | ✅ Zero | **WARN** |
| `/engagement` | "Engajamento" | SSR | ⬜ Verificar | ❌ **Sem error state** | ✅ Zero | **WARN** |
| `/communications` | "Comunicação" | SSR | ⬜ Verificar | ❌ **Sem error state** | ✅ Zero | **WARN** |
| `/attendance-analytics` | "Análise Presença" | SSR | ⬜ Verificar | ❌ **Sem error state** | ✅ Zero | **WARN** |

---

## 3. Issues por Severidade

### P1 — Usuário fica preso

| # | Tela | Issue | Fix |
|---|------|-------|-----|
| UX01 | `athlete_training_list_screen` | Error state sem retry — atleta precisa voltar e reentrar | Adicionar `ElevatedButton('Tentar novamente', onPressed: _reload)` |
| UX02 | `athlete_my_status_screen` | Error state sem retry | Adicionar retry button |
| UX03 | `athlete_my_evolution_screen` | Error state sem retry | Adicionar retry button |
| UX04 | Portal: todas as pages SSR novas | Sem try/catch + error boundary — crash branco no erro | Wrap queries em try/catch + `<ErrorFallback>` |

### P2 — UX confusa mas funcional

| # | Tela | Issue | Fix |
|---|------|-------|-----|
| UX05 | `staff_training_create_screen` | Sem snackbar após salvar — tela fecha silenciosamente | Adicionar `ScaffoldMessenger.showSnackBar(SnackBar(content: Text('Treino salvo!')))` antes de `Navigator.pop` |
| UX06 | `announcement_create_screen` | Sem snackbar após salvar | Mesmo fix |
| UX07 | `announcement_detail_screen` | Error state sem retry button | Adicionar retry |
| UX08 | `staff_crm_list_screen` | Empty state sem ícone/instrução | Adicionar `Icon(Icons.group)` + texto explicativo |
| UX09 | Portal `/announcements` | Sem empty state | Adicionar "Nenhum aviso publicado. Crie o primeiro." |
| UX10 | Portal `/exports` | Sem feedback ao clicar "Exportar" | Adicionar loading spinner + toast "Download iniciado" |
| UX11 | `staff_training_list_screen` | `FutureBuilder` por card para `countBySession` — N+1 queries no scroll | Batch no BLoC: buscar counts em bulk |

### P3 — Cosmético

| # | Tela | Issue | Fix |
|---|------|-------|-----|
| UX12 | `staff_athlete_profile_screen` `_PresencaTab` | `FutureBuilder` sem retry no error | Adicionar retry |
| UX13 | Portal pages SSR | Sem client-side loading indicator (SSR puro) | Adicionar `loading.tsx` files |

---

## 4. Fluxos Críticos — Validação por Persona

### Athlete: "Como entrar em uma assessoria"

| Passo | Tela | Esperado | OK? |
|-------|------|----------|-----|
| 1 | Buscar assessoria / receber convite | Link ou QR de convite | ⬜ |
| 2 | Solicitar entrada | `fn_request_join` → pendente | ⬜ |
| 3 | Aguardar aprovação | Tela mostra "Aguardando aprovação" | ⬜ |
| 4 | Aprovado → acesso | Refresh → dashboard athlete | ⬜ |

### Athlete: "Como gerar QR e o que acontece se expirar"

| Passo | Tela | Esperado | OK? |
|-------|------|----------|-----|
| 1 | Selecionar treino | Lista de treinos | ⬜ |
| 2 | Gerar QR | QR aparece com countdown | ⬜ |
| 3 | Countdown chega a 0 | QR desaparece/desabilita + msg "Expirado. Gere novamente." | ⬜ |
| 4 | Gerar novamente | Novo QR com novo TTL | ⬜ |

### Coach: "Como criar treino rápido"

| Passo | Tela | Esperado | OK? |
|-------|------|----------|-----|
| 1 | Abrir agenda | Lista de treinos | ⬜ |
| 2 | Tocar "+" | Form com título, data/hora | ⬜ |
| 3 | Preencher mínimo (título + starts_at) | Botão "Salvar" ativo | ⬜ |
| 4 | Salvar | Tela fecha, treino na lista | ⬜ |
| 5 | **Feedback?** | ❌ Sem snackbar (P2) | ⬜ |

### Coach: "Como ver quem faltou"

| Passo | Tela | Esperado | OK? |
|-------|------|----------|-----|
| 1 | Abrir detalhe do treino | Lista de presença | ⬜ |
| 2 | Ver quem está / quem faltou | Lista mostra presentes; "faltantes" = total_athletes - presentes | ⬜ |
| 3 | Portal: `/attendance` | Detalhe mostra % presença | ⬜ |

### Coach: "Como filtrar atletas em risco"

| Passo | Tela | Esperado | OK? |
|-------|------|----------|-----|
| 1 | Portal → `/risk` | Lista de high/medium risk | ⬜ |
| 2 | Ou app → CRM com filtro "Risco" | Filtrar por risk_level | ⬜ |
| 3 | Ver detalhe do atleta | Score, presença, alerts | ⬜ |

---

## 5. Microcopy — Verificação "Zero Dinheiro"

| Busca | Encontrado | Status |
|-------|-----------|--------|
| "R$", "$", "dólar", "real", "preço", "pagamento", "assinatura" nas telas OS | ❌ Zero | ✅ |
| "token" | ✅ Apenas "QR check-in token" (correto — não é moeda) | ✅ |
| "moeda", "coin", "saldo" | ❌ Zero nas telas OS | ✅ |

---

## 6. Sugestões de Microcopy

| Tela | Atual | Sugerido |
|------|-------|----------|
| `staff_crm_list_screen` (empty) | "Nenhum atleta encontrado" | "Nenhum atleta corresponde aos filtros. Ajuste os filtros acima." |
| `athlete_training_list_screen` (empty) | "Não há treinos agendados para este grupo." | "Seu treinador ainda não agendou treinos. Fique atento!" |
| `announcement_feed_screen` (empty, staff) | "Nenhum aviso publicado" | "Nenhum aviso publicado. Toque em '+' para criar o primeiro." |
| `athlete_my_status_screen` (null) | "Status não definido" | "Seu status ainda não foi definido pelo treinador." |
| Engagement (portal) | "Último dado" | "Dados referentes a D-1 (último dia fechado)" |
| Forms após salvar | (silêncio) | "Treino salvo com sucesso!" / "Aviso publicado!" |

---

## 7. Acessibilidade Básica

| Item | Status | Nota |
|------|--------|------|
| Contraste | ⬜ Verificar manualmente | Depende do tema Material |
| Tamanhos de fonte | ✅ Material defaults (14-16sp) | OK para leitura |
| Botões grandes no scanner | ⬜ Verificar touch target ≥ 48dp | Scanner usa câmera fullscreen |
| Feedback de sucesso (som/vibração) | ⬜ Verificar `HapticFeedback` | Scanner deveria vibrar no sucesso |
| Semantic labels | ⬜ Verificar `Semantics` widgets | Importante para screen readers |
