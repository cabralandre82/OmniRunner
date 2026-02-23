# domain/repositories/

Contratos abstratos (interfaces) dos repositories.

- Definem O QUE o sistema faz, nao COMO
- Retornam Either<Failure, T> (via fpdart)
- Implementacoes concretas ficam em data/repositories_impl/
