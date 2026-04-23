# Contratos privados (`docs/legal/`) — Manual de versionamento

> **Lente / finding:** [L09-09](../audit/findings/L09-09-contratos-privados-termo-de-adesao-do-clube-termo.md) ·
> **Runbook operacional:** [`docs/runbooks/LEGAL_CONTRACTS_RUNBOOK.md`](../runbooks/LEGAL_CONTRACTS_RUNBOOK.md).

Este diretório guarda os **contratos privados versionados** que governam a relação
entre a plataforma, assessorias/clubes e atletas. Cada arquivo é a **fonte canônica
imutável** de uma versão específica de contrato — qualquer alteração no conteúdo
exige bump de versão (v1.0 → v2.0) e nova entrada em
[`consent_policy_versions`](../../supabase/migrations/20260417220000_lgpd_consent_management.sql).

## Documentos vigentes

| Arquivo | Tipo de consent | Versão atual | Aplicável a |
| --- | --- | --- | --- |
| [`TERMO_ADESAO_ASSESSORIA.md`](./TERMO_ADESAO_ASSESSORIA.md) | `club_adhesion` | v1.0 | Assessorias/Clubes (B2B) que contratam a plataforma |
| [`TERMO_ATLETA.md`](./TERMO_ATLETA.md) | `athlete_contract` | v1.0 | Atletas que aderem a uma assessoria/clube via plataforma |

## Modelo de integridade (hash SHA-256)

Cada arquivo tem um SHA-256 calculado sobre o **conteúdo bruto em UTF-8 sem BOM,
com `\n` como separador de linha**. Esse hash:

1. Está gravado no campo `consent_policy_versions.document_hash` (seed da migration
   correspondente — ver `supabase/migrations/2026*_l09_09_legal_contracts_consent.sql`).
2. É verificado em CI por
   [`tools/legal/check-document-hashes.ts`](../../tools/legal/check-document-hashes.ts);
   qualquer alteração no MD sem bump de versão **falha o build**.
3. É devolvido pelo endpoint `GET /api/consent` junto com `current_version`, para
   que o app/portal exiba ao usuário **exatamente** qual texto está aceitando — o
   `consent_events.version` registrado fica colado ao hash.

Para imprimir o hash atual sem alterar nada:

```bash
npx tsx tools/legal/check-document-hashes.ts --print
```

Saída esperada (exemplo):

```
docs/legal/TERMO_ADESAO_ASSESSORIA.md  v1.0  sha256=ab12...
docs/legal/TERMO_ATLETA.md             v1.0  sha256=cd34...
```

## Como rotacionar uma versão (v1.0 → v2.0)

1. **Não edite o arquivo existente.** Crie `TERMO_*_v2.md` (ou edite e bump versão
   internamente — ambas as opções são suportadas, mas mantenha o histórico via
   git tag `legal/<contrato>-v<N>`).
2. Atualize o campo `Versão` no cabeçalho do MD para a nova versão.
3. Rode `npx tsx tools/legal/check-document-hashes.ts --print` para obter o novo
   hash.
4. Crie uma nova migration:
   ```sql
   UPDATE public.consent_policy_versions
      SET current_version = '2.0',
          minimum_version = '2.0',           -- exige reconsent
          document_url    = '/legal/TERMO_ATLETA_v2.md',
          document_hash   = '<novo_sha256>',
          updated_at      = now()
    WHERE consent_type = 'athlete_contract';
   ```
5. Rode novamente `tools/legal/check-document-hashes.ts` (sem `--print`) para
   confirmar que não há drift.
6. Detalhamento operacional completo em
   [`docs/runbooks/LEGAL_CONTRACTS_RUNBOOK.md`](../runbooks/LEGAL_CONTRACTS_RUNBOOK.md).

## Convenções editoriais

- **Idioma:** Português brasileiro técnico-jurídico.
- **Numeração:** Cláusulas em algarismos romanos (Cláusula I, II, III…), parágrafos
  em algarismos arábicos (§ 1º, § 2º…), incisos em romanos minúsculos (i, ii, iii).
- **Marcadores variáveis:** `[NOME_DA_PARTE]`, `[CNPJ]`, `[ENDEREÇO]`, `[VALOR_MENSAL_BRL]`,
  `[DATA_ASSINATURA]`. A plataforma renderiza o documento substituindo no
  momento do aceite, mas o **hash registrado no `consent_events` é sempre o do
  template canônico** — a substituição é parte do `request_id` / metadata do
  evento, não do hash da política.
- **Imutabilidade:** uma vez publicada, uma versão jamais é editada. Correção
  tipográfica = bump v1.0 → v1.1; alteração material = bump v1.0 → v2.0.

## Justificativa LGPD

LGPD Art. 7º I e Art. 8 §1 exigem que o consentimento seja **demonstrável e
documental**. Em uma ação judicial ou inquérito ANPD, a plataforma precisa provar:

1. **Que** o usuário aceitou (`consent_events.action='granted'`).
2. **Quando** (`consent_events.granted_at`).
3. **Qual versão exata do texto** aceitou (`consent_events.version` + `consent_policy_versions.document_hash`).

Sem o ponto (3) verificável, qualquer alegação de "li e concordei" cai por terra
porque a plataforma não consegue reconstituir **o que** o usuário leu. O hash
SHA-256 do MD imutável fecha esse gap.
