# data/repositories_impl/

Implementacoes concretas dos contratos definidos em domain/repositories/.

- Implementam as interfaces do domain
- Coordenam datasources (local + remoto)
- Convertem exceptions em Failures (Either)
- Nao contem logica de negocio
