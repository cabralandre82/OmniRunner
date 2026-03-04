# Decisão: Congelar TrainingPeaks + Implementar Treinus Delivery

## Data: 2026-03-03

## Contexto
A integração com TrainingPeaks foi implementada (OAuth, sync push/pull, DB schema) mas o modelo de API do TrainingPeaks não atende ao fluxo desejado para o produto. A decisão é congelar o código existente e implementar um fluxo alternativo.

## Decisão
1. **Congelar** toda a integração TrainingPeaks com feature flag (`trainingpeaks_enabled = false`)
2. **Não deletar** nenhum código TP — preservar para possível reativação futura
3. **Implementar** "Workout Delivery" como fluxo principal de entrega de treinos
4. **Workflow**: coach publica manualmente no Treinus + tracking de confirmação do atleta

## Consequências

### Positivas
- Sem dependência de API externa (TrainingPeaks)
- Atleta usa Treinus/Garmin como já faz — sem mudança de hábito
- Auditoria completa de cada entrega (quem publicou, quando, confirmação)
- Código TP preservado — pode ser reativado se o modelo de negócio mudar

### Negativas
- Publicação no Treinus é manual (coach copia e cola)
- Dependência de confirmação manual do atleta
- Não há integração direta com relógio

## Alternativas Consideradas
1. **Manter TP ativo**: Descartado — API não atende ao fluxo
2. **Deletar código TP**: Descartado — evita retrabalho se precisar reativar
3. **Automação Treinus API**: Não disponível — Treinus não oferece API pública

## Como reativar TrainingPeaks
Ver `docs/TRAININGPEAKS_FROZEN.md`
