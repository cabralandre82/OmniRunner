#!/usr/bin/env bash
# Build prod release APK with correct flavor and env file.
# Resolves --dart-define-from-file relative to omni_runner/:
#   1) Path passed as $1 (e.g. ~/secrets/omni_runner/.env.prod)
#   2) ../.env.prod (monorepo root — Flutter resolves from omni_runner/)
#   3) .env.prod (inside omni_runner/)
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${1:-}"
if [ -z "$ENV_FILE" ]; then
  if [ -f "../.env.prod" ]; then
    ENV_FILE="../.env.prod"
  elif [ -f ".env.prod" ]; then
    ENV_FILE=".env.prod"
  else
    echo "ERRO: defina .env.prod na raiz do monorepo (../.env.prod) ou em omni_runner/.env.prod," >&2
    echo "      ou passe o caminho: $0 /caminho/para/.env.prod" >&2
    exit 1
  fi
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "ERRO: arquivo não encontrado: $ENV_FILE" >&2
  exit 1
fi

echo "Usando: --dart-define-from-file=$ENV_FILE"
flutter pub get
# Sem --split-per-abi o Gradle gera um APK único com arm32 + arm64 + x86_64 (+ x86):
# costuma passar de ~120MB. Com split, cada ABI fica na faixa de ~40–55MB (use arm64 no celular).
flutter build apk --flavor prod --release --split-per-abi --dart-define-from-file="$ENV_FILE"
