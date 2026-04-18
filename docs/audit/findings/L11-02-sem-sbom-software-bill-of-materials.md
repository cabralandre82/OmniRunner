---
id: L11-02
audit_ref: "11.2"
lens: 11
title: "Sem SBOM (Software Bill of Materials)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "mobile", "supply-chain", "compliance", "ci"]
files:
  - .github/workflows/security.yml
correction_type: process
test_required: true
tests:
  - .github/workflows/security.yml
linked_issues: []
linked_prs:
  - "commit:HEAD"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "SBOMs CycloneDX gerados em todo build (portal + omni_runner) via anchore/sbom-action@v0, retidos 90 dias como GitHub artifact. Atende requisitos de NIST SSDF / EO 14028 (US) e BACEN res. 4.893/21 (BR — gestão de risco de fornecedor). Assinatura Sigstore/cosign fica como follow-up (L11-02-followup-sigstore-signing) — depende de provisionar OIDC token + KMS para chaves."
---
# [L11-02] Sem SBOM (Software Bill of Materials)
> **Lente:** 11 — Supply Chain · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** CI / supply chain
**Personas impactadas:** Plataforma (compliance/legal), Auditoria externa, Parceiros B2B

## Achado
SBOM (Software Bill of Materials) é exigência regulatória crescente:
- **NIST SSDF** (Secure Software Development Framework): SBOM entregável para
  toda release.
- **US EO 14028** (Improving the Nation's Cybersecurity, 2021): SBOM
  obrigatório para fornecedores do governo federal.
- **BACEN res. 4.893/21** (BR): instituições financeiras devem manter
  inventário e gerenciamento de risco da cadeia de suprimentos de
  software.
- **B2B compliance**: assessorias de elite e parceiros institucionais
  (L16-04 outbound webhooks) cada vez mais auditam fornecedores e exigem
  SBOM em onboarding.

Antes desta correção: zero geração de SBOM, zero retenção, zero
inventário público de dependências.

## Risco / Impacto
- Bloqueio em onboarding B2B com instituições financeiras / corporate
  (CRO/Legal não consegue responder a due diligence).
- Em incidente de supply chain (e.g. compromise upstream tipo
  `colors.js` 2022, `ua-parser-js` 2021, xz-utils 2024), sem SBOM o
  time não consegue responder rapidamente: "estamos afetados? por qual
  versão? em qual deploy?".
- Auditoria externa (ISO 27001, SOC 2) exige inventário de software.

## Correção implementada

`.github/workflows/security.yml` jobs `sbom-portal` + `sbom-flutter`:

### 1. SBOM portal (CycloneDX-JSON)
- **Action**: `anchore/sbom-action@v0` (Anchore Syft engine — industry
  standard, CycloneDX 1.5 + SPDX support).
- **Path**: `./portal` — escaneia `package.json` + `package-lock.json` +
  `node_modules` resolvido após `npm ci`.
- **Output**: `sbom-portal.cdx.json` (CycloneDX JSON 1.5).
- **Retenção**: 90 dias como GitHub artifact (compatível com janela de
  due diligence típica).

### 2. SBOM omni_runner (CycloneDX-JSON)
- Mesma action, escaneia `./omni_runner` após `flutter pub get`.
- Output: `sbom-omni-runner.cdx.json`.
- Cobre **TODAS** as deps Flutter/Dart resolvidas (pubspec.lock + plugin
  Android/iOS deps quando detectáveis).

### Por que CycloneDX (e não SPDX)
- CycloneDX é **OWASP-flagship**, mais leve, foco em security
  (vulnerability tracking, VDR/VEX integration). SPDX é mais focado em
  licensing.
- Maioria dos consumidores B2B BR/EU pede CycloneDX. Trivial gerar SPDX
  adicional via `anchore/sbom-action` (`format: spdx-json`) se algum
  parceiro pedir explicitamente.

### Formato consumível
SBOMs gerados são auto-descritivos:

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "components": [
    {
      "type": "library",
      "bom-ref": "pkg:npm/next@14.2.32",
      "name": "next",
      "version": "14.2.32",
      "purl": "pkg:npm/next@14.2.32",
      "licenses": [{"license": {"id": "MIT"}}]
    },
    ...
  ]
}
```

Pode ser ingerido por:
- Dependency Track (FOSS dashboard de vulns por SBOM)
- GitHub Dependency Graph
- Snyk / Mend / Black Duck
- Scripts próprios (jq, Python `cyclonedx-bom`)

## Follow-ups

1. **L11-02-followup-sigstore-signing** — assinar SBOMs com `cosign`
  (Sigstore) para garantir integridade de cadeia. Provê
  attestation auditável "este SBOM foi gerado para o commit `<sha>`".
  Requer OIDC issuer config + KMS. Estimado: 3-5 pontos.

2. **L11-02-followup-publish-sbom** — publicar SBOM versionado em
  `docs/sbom/` (commitado no repo, atualizado por bot a cada release)
  para consumo público sem precisar baixar de artifact GitHub.
  Estimado: 2 pontos.

3. **L11-02-followup-dependency-track** — provisionar instância de
  Dependency Track (self-hosted) para dashboard contínuo + alertas de
  novas CVEs em deps já em uso. Estimado: 5-8 pontos
  (infra + automação).

## Teste de regressão
Job `sbom-portal` + `sbom-flutter` rodam em todo push para `master` e
todo PR contra `master`. Falha se a geração quebrar (e.g. `package.json`
malformado, `pubspec.lock` ausente). Artifact é validável manualmente
via:

```bash
gh run download <run-id> -n sbom-portal
jq '.bomFormat, .specVersion, (.components | length)' sbom-portal.cdx.json
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.2).
- `2026-04-17` — Correção implementada: workflow `security.yml` jobs `sbom-portal` + `sbom-flutter`, formato CycloneDX 1.5, retenção 90d. Follow-ups (Sigstore signing, publicação versionada, Dependency Track) documentados. Promovido a `fixed`.
