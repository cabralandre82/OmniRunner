# domain/usecases/

Use Cases do dominio. Um por arquivo, uma responsabilidade.

- Implementam call() como metodo unico
- Dependem apenas de Repository interfaces (domain)
- Dart puro, 100% testavel
- Retornam Either<Failure, T>
