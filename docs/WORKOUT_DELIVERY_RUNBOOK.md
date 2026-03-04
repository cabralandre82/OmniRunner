# Workout Delivery — Runbook Operacional (para Assessorias)

## Visão Geral
O Workout Delivery permite que a assessoria publique treinos no Treinus manualmente e rastreie se cada atleta recebeu o treino no relógio.

## Fluxo Operacional

### 1. Preparar Treinos
- Atribua treinos aos atletas normalmente via Portal → Treinos
- Cada atribuição gera um `coaching_workout_assignment` com status "planned"

### 2. Criar Lote de Entrega
- Acesse Portal → Entrega Treinos
- Clique "Criar Lote" com período opcional (ex: próxima semana)
- O lote agrupa todos os treinos planejados daquele período

### 3. Gerar Itens
- No lote criado, clique "Gerar Itens"
- O sistema cria um item para cada atleta com treino planejado no período
- Cada item contém o payload do treino (blocos, pace, HR zone, etc.)

### 4. Publicar no Treinus
- Para cada item pendente, clique "Copiar Treino"
- O conteúdo é copiado para a área de transferência
- Abra o Treinus e crie o treino manualmente com as informações copiadas
- Volte ao portal e clique "Marcar Publicado" para registrar que o treino foi enviado

### 5. Confirmação do Atleta
- O atleta vê entregas pendentes no App → Entregas Pendentes
- Atleta clica "Apareceu no relógio" ou "Não apareceu" (com motivo)
- O status atualiza automaticamente no portal

## Troubleshooting

### "Não apareceu no relógio"
| Motivo | Ação |
|--------|------|
| Não sincronizou | Verificar conexão Bluetooth do relógio, forçar sync manual no app do relógio |
| Treino diferente | Conferir se o treino correto foi publicado no Treinus |
| Erro no relógio | Reiniciar relógio, verificar firmware atualizado |
| Outro | Contatar atleta para mais detalhes |

### Lote sem itens gerados
- Verificar se existem treinos atribuídos com status "planned" no período selecionado
- Confirmar que os atletas são membros ativos do grupo

### Status preso em "Pendente"
- O coach precisa clicar "Marcar Publicado" após publicar no Treinus
- O item só muda para "Publicado" após essa ação manual

## Métricas
- **Total**: todos os itens de entrega
- **Pendentes**: aguardando publicação pelo coach
- **Publicados**: publicados no Treinus, aguardando confirmação do atleta
- **Confirmados**: atleta confirmou recebimento no relógio
- **Falha**: atleta reportou problema
