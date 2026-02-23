# DEFINITION_OF_DONE.md — Criterios Globais de "Pronto"

> **Sprint:** 1.2
> **Status:** Ativo

---

## 1. DoD GLOBAL (TODA SPRINT)

Nenhuma sprint e considerada CONCLUIDA sem todos os itens abaixo:

| # | Criterio | Obrigatorio |
|---|---|---|
| D1 | Codigo compila sem erros (`flutter build apk --debug`) | SIM |
| D2 | Testes passam (`flutter test`) | SIM |
| D3 | Zero warnings em `dart analyze` | SIM |
| D4 | Nenhum import viola grafo de dependencia (GOVERNANCE.md) | SIM |
| D5 | Nenhum arquivo excede 200 linhas | SIM |
| D6 | Nomenclatura segue padrao (GOVERNANCE.md 3.3) | SIM |
| D7 | `docs/CONTEXT_DUMP.md` atualizado com evidencias | SIM |

---

## 2. DoD POR CAMADA

### Domain
- Entities geradas por Protobuf e imutaveis
- Use Cases implementam `call()` como metodo unico
- Repository interfaces sao abstratas (contratos)
- Failures sao sealed classes
- Cobertura de testes: 100%

### Application
- BLoC tem arquivos separados para Events e States
- BLoC depende apenas de Use Cases (nenhum import de infrastructure)
- BLoC e sufixado com `Bloc`
- Cobertura de testes: 100%

### Infrastructure
- Repository implementations retornam `Either<Failure, T>`
- Models convertem dados externos para entities do domain
- Nenhuma logica de negocio
- Cobertura de testes: 80%

### Presentation
- Nenhuma logica de negocio em widgets
- Pages sufixadas com `Page`
- Widgets reutilizaveis sufixados com `Widget`
- Apenas le estados do BLoC e despacha eventos
- Testes de widget: criticos apenas

---

## 3. DoD POR COMMIT

Antes de cada commit:

- [ ] Compila sem erros
- [ ] Testes passam
- [ ] Um escopo logico por commit
- [ ] Mensagem segue Conventional Commits (ingles, imperativo, max 72 chars)
- [ ] Nenhum WIP, nenhum dead code, nenhum `print()`

---

## 4. DoD POR FEATURE

Uma feature F(n) do SCOPE.md so e "pronta" quando:

- [ ] Todos os use cases implementados e testados
- [ ] BLoC implementado e testado
- [ ] Repository implementado e testado
- [ ] UI conectada ao BLoC
- [ ] Fluxo completo funciona no device/emulador
- [ ] Nenhum TODO restante no codigo da feature

---

*Documento gerado na Sprint 1.2*
