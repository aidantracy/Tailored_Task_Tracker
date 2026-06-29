#!/usr/bin/env bash
# build.sh — Podman-only, verbose, idempotent
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-dashboard-app}"
INSTALL_DEV="${INSTALL_DEV:-1}"     # 1=dev deps; 0=prod-only
DEBUG="${DEBUG:-0}"

ts() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

have podman || { echo "❌ Podman not found in PATH"; exit 127; }
OCI_BIN="$(command -v podman)"
echo "🐳 Using container engine: $OCI_BIN"

# Engine readiness (no brittle grep; just try info)
if ! $OCI_BIN info >/dev/null 2>&1; then
  ts "ℹ️  Starting Podman machine…"
  $OCI_BIN machine start
  $OCI_BIN info >/dev/null || { echo "❌ Podman engine not ready after start"; exit 1; }
else
  ts "ℹ️  Podman engine is ready."
fi

[[ -f Dockerfile ]] || { echo "❌ Dockerfile not found in $(pwd)"; exit 66; }

# Show where we’re building from (large OneDrive trees can be slow)
ts "ℹ️  Build context: $(pwd)"
ts "ℹ️  Context size (approximate):"
# This is quick on Windows; if it's slow, OneDrive is the culprit
(find . -maxdepth 2 -type f | wc -l) 2>/dev/null || true

BUILD_ARGS=( --build-arg "INSTALL_DEV=${INSTALL_DEV}" )
PROGRESS=( --progress=plain )
[[ "$DEBUG" = "1" ]] && set -x

ts "🔨 Starting build → localhost/${IMAGE_NAME}:latest"
$OCI_BIN build "${PROGRESS[@]}" -t "localhost/${IMAGE_NAME}:latest" "${BUILD_ARGS[@]}" -f Dockerfile .

ts "✅ Built image: localhost/${IMAGE_NAME}:latest"
