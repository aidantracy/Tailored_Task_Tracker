#!/usr/bin/env bash
# test.sh — Podman-only test runner
# - Frontend (QUnit): npm test
# - Backend (pytest): python -m pytest (src/ layout)
# - E2E (Cypress): Podman compose only (no Docker delegation)
set -euo pipefail

###########
# Helpers #
###########
have() { command -v "$1" >/dev/null 2>&1; }
require_cmd() { have "$1" || { echo "Error: '$1' not found in PATH" >&2; exit 1; }; }
ts() { printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }

# Podman only
pick_engine() {
  if have podman; then echo "podman"; else
    echo "Error: Podman not found on PATH" >&2; exit 1; fi
}

# Choose a compose frontend that NEVER delegates to docker-compose.exe
# Order: Python module → native podman compose
choose_compose() {
  if have py && py - <<'PY' >/dev/null 2>&1
import pkgutil, sys; sys.exit(0 if pkgutil.find_loader("podman_compose") else 1)
PY
  then
    COMPOSE=(py -m podman_compose); PROVIDER_EXPLICIT=1; return 0
  fi
  if have python && python - <<'PY' >/dev/null 2>&1
import pkgutil, sys; sys.exit(0 if pkgutil.find_loader("podman_compose") else 1)
PY
  then
    COMPOSE=(python -m podman_compose); PROVIDER_EXPLICIT=1; return 0
  fi
  COMPOSE=(podman compose); PROVIDER_EXPLICIT=0; return 0
}

# Project name generator (team-safe; unique per user locally unless in CI)
_default_proj() {
  local base
  if have git && git rev-parse --show-toplevel >/dev/null 2>&1; then
    base="$(basename "$(git rev-parse --show-toplevel)")"
  else
    base="$(basename "$PWD")"
  fi
  if [[ -n "${CI:-}" ]]; then echo "$base"; else echo "${base}-$(whoami 2>/dev/null || echo user)"; fi
}

#####################
# Config (env-tuned)#
#####################
BUILD_IMAGES="${BUILD_IMAGES:-auto}"   # auto | always | never

# Default to a clean DB/container each run; allow opt-out via KEEP_DB=1
RECREATE="${RECREATE:-1}"              # 1=recreate containers by default
RESET_DB="${RESET_DB:-1}"              # 1=down -v before up by default
if [[ "${KEEP_DB:-0}" = "1" ]]; then RESET_DB=0; fi

SKIP_E2E="${SKIP_E2E:-}"               # set "true" to skip E2E

APP_IMAGE="${APP_IMAGE:-dashboard-app}"         # name from compose
NPM_TEST_SCRIPT="${NPM_TEST_SCRIPT:-test}"      # front-end tests
CYPRESS_SCRIPT="${CYPRESS_SCRIPT:-cypress:run}" # E2E script

########################
# Frontend (QUnit/NPM) #
########################
require_cmd npm
if [[ ! -d node_modules ]]; then
  ts "node_modules missing; installing..."
  if [[ -f package-lock.json ]]; then npm ci; else npm install; fi
fi
ts "Running Frontend Tests (QUnit)…"
npm run "${NPM_TEST_SCRIPT}"

#######################
# Backend (pytest)    #
#######################
require_cmd python
ts "Running Backend Tests (pytest)…"
PYTHONPATH=src python -m pytest -q

if [[ "${SKIP_E2E}" == "true" ]]; then
  ts "SKIP_E2E=true — skipping container build and E2E."
  echo "All tests passed successfully!"
  exit 0
fi

#############################
# E2E (Cypress w/ Podman)   #
#############################
ts "Detecting container environment…"
OCI_BIN="$(pick_engine)"
choose_compose
echo "Using: ${OCI_BIN} and ${COMPOSE[*]}"

# Ensure Podman engine is ready (Windows/macOS)
if ! podman info >/dev/null 2>&1; then
  ts "Starting Podman machine…"
  podman machine start
  podman info >/dev/null || { echo "Podman engine not ready"; exit 1; }
fi

# Load .env if present (to honor COMPOSE_PROJECT_NAME etc.)
if [[ -f .env ]]; then set -a; source .env; set +a; fi
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(_default_proj)}"
PROJECT_FLAG=( -p "$COMPOSE_PROJECT_NAME" )
export COMPOSE_PROJECT_NAME
echo "Project: ${COMPOSE_PROJECT_NAME}"

# Prevent Podman from delegating to docker-compose.exe
if [[ "${PROVIDER_EXPLICIT}" = "1" ]]; then
  export PODMAN_COMPOSE_PROVIDER=podman-compose
else
  unset PODMAN_COMPOSE_PROVIDER
fi

# Remove stale default networks from either engine (fix label mismatch)
docker network rm "${COMPOSE_PROJECT_NAME}_default" 2>/dev/null || true
podman network rm "${COMPOSE_PROJECT_NAME}_default" 2>/dev/null || true

# Kill lingering single-name containers that bypass compose scoping
for name in dashboard-mysql dashboard-app; do
  if podman ps -aq --filter "name=^${name}$" | grep -q .; then
    ts "Removing stale container '${name}'…"
    podman rm -f "${name}" || true
  fi
done

# Helper: check if an image exists (with/without localhost prefix)
have_image() {
  podman image exists "$1" || podman image exists "localhost/$1"
}

# Optional clean start (drop volumes) — default ON; override with KEEP_DB=1
if [[ "$RESET_DB" = "1" ]]; then
  ts "Reset requested — tearing down with volumes…"
  "${COMPOSE[@]}" "${PROJECT_FLAG[@]}" down -v || true
fi

# Build policy
case "$BUILD_IMAGES" in
  always)
    ts "Building images (forced)…"
    "${COMPOSE[@]}" "${PROJECT_FLAG[@]}" build
    ;;
  never)
    ts "Skipping image build (BUILD_IMAGES=never)."
    ;;
  auto|*)
    if have_image "$APP_IMAGE"; then
      ts "Image '$APP_IMAGE' found; skipping build."
    else
      ts "Image '$APP_IMAGE' not found; building…"
      "${COMPOSE[@]}" "${PROJECT_FLAG[@]}" build
    fi
    ;;
esac

# Up (force recreate by default, and renew anon volumes)
if [[ "$RECREATE" = "1" ]]; then
  ts "Starting stack (force recreate)…"
  "${COMPOSE[@]}" "${PROJECT_FLAG[@]}" up -d --force-recreate --renew-anon-volumes
else
  ts "Starting stack…"
  "${COMPOSE[@]}" "${PROJECT_FLAG[@]}" up -d
fi

# Run E2E
ts "Running End-to-End Tests (Cypress)…"
set +e
npm run "${CYPRESS_SCRIPT}"
rc=$?
set -e

# Down (keep volumes after run; next run will reset by default anyway)
ts "Stopping containers…"
"${COMPOSE[@]}" "${PROJECT_FLAG[@]}" down

if [[ $rc -ne 0 ]]; then
  echo "E2E tests failed with exit code $rc."
  exit "$rc"
else
  echo "All tests passed successfully!"
fi
