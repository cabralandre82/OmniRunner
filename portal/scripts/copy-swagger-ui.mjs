#!/usr/bin/env node
/**
 * L14-03 — Self-host Swagger-UI para eliminar dependência de CDN externo (unpkg).
 *
 * Copia os assets mínimos de `swagger-ui-dist` para `portal/public/vendor/swagger-ui/`.
 * Roda automaticamente via `npm run build` (prebuild) e `npm install` (postinstall).
 *
 * Gera um `manifest.json` com hashes SHA-384 (subresource-integrity-compatible) que
 * pode ser usado em runtime para validar a integridade dos arquivos servidos. Não
 * dependemos mais de SRI no HTML porque os arquivos são servidos do mesmo origin,
 * mas o manifesto documenta os hashes de referência para auditoria/CI.
 *
 * Referência auditoria:
 *   docs/audit/findings/L14-03-api-docs-carrega-swagger-ui-de-unpkg-sem.md
 *   docs/audit/parts/07-qa-dx.md [14.3]
 */

import { readFile, writeFile, mkdir, access, constants, copyFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORTAL_ROOT = resolve(__dirname, "..");
const SRC_DIR = join(PORTAL_ROOT, "node_modules", "swagger-ui-dist");
const DEST_DIR = join(PORTAL_ROOT, "public", "vendor", "swagger-ui");

const ASSETS = [
  "swagger-ui.css",
  "swagger-ui-bundle.js",
  "swagger-ui-standalone-preset.js",
  "favicon-16x16.png",
  "favicon-32x32.png",
];

async function fileExists(p) {
  try {
    await access(p, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function sha384Base64(buf) {
  return createHash("sha384").update(buf).digest("base64");
}

async function copyAsset(name) {
  const src = join(SRC_DIR, name);
  const dest = join(DEST_DIR, name);
  if (!(await fileExists(src))) {
    throw new Error(
      `swagger-ui-dist asset ausente em ${src}. Verifique se 'npm install' rodou.`
    );
  }
  await copyFile(src, dest);
  const buf = await readFile(src);
  return { name, bytes: buf.length, sha384: await sha384Base64(buf) };
}

async function main() {
  if (!(await fileExists(SRC_DIR))) {
    console.warn(
      `[copy-swagger-ui] ${SRC_DIR} não encontrado; pulando (swagger-ui-dist não instalado).`
    );
    process.exit(0);
  }

  await mkdir(DEST_DIR, { recursive: true });

  const manifest = { generated_at: new Date().toISOString(), assets: {} };
  for (const asset of ASSETS) {
    const { name, bytes, sha384 } = await copyAsset(asset);
    manifest.assets[name] = { bytes, sha384: `sha384-${sha384}` };
  }

  let pkgVersion = "unknown";
  try {
    const pkg = JSON.parse(
      await readFile(join(SRC_DIR, "package.json"), "utf8")
    );
    pkgVersion = pkg.version ?? "unknown";
  } catch {
    /* ignore */
  }
  manifest.swagger_ui_dist_version = pkgVersion;

  await writeFile(
    join(DEST_DIR, "manifest.json"),
    JSON.stringify(manifest, null, 2) + "\n",
    "utf8"
  );

  console.log(
    `[copy-swagger-ui] ${ASSETS.length} assets copiados para public/vendor/swagger-ui/ (v${pkgVersion}).`
  );
}

main().catch((err) => {
  console.error("[copy-swagger-ui] falhou:", err);
  process.exit(1);
});
