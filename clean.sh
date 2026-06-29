#!/usr/bin/env bash
# clean.sh — stop/remove the stack and optionally nuke ALL images (Docker or Podman)
set -euo pipefail

echo "🧹 Cleaning project"

# ----- Podman-first envs -----
export CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
export PODMAN_COMPOSE_PROVIDER="${PODMAN_COMPOSE_PROVIDER:-podman-compose}"
export PODMAN_COMPOSE_WARNING_LOGS="${PODMAN_COMPOSE_WARNING_LOGS:-false}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-tailored-task-tracker}"  # avoid label collisions

# ----- Options -----
PRUNE_UNUSED="${PRUNE_UNUSED:-0}"   # 1 = run `system prune -f` after down (non-destructive)
NUKE_IMAGES="${NUKE_IMAGES:-0}"     # 1 = stop/remove ALL containers, remove ALL images (dangerous!)
NUKE_ALL="${NUKE_ALL:-0}"           # 1 = like NUKE_IMAGES plus prune networks/volumes/build cache (very destructive)

have_cmd() { command -v "$1" >/dev/null 2>&1; }

pick_engine() {
  if [[ -n "${CONTAINER_ENGINE:-}" ]] && have_cmd "$CONTAINER_ENGINE"; then
    command -v "$CONTAINER_ENGINE"; return 0
  fi
  if have_cmd podman; then command -v podman; return 0; fi
  if have_cmd docker; then command -v docker; return 0; fi
  return 1
}

choose_compose() {
  local oci_bin="$1"

  # Prefer Python module provider (works even if no exe on PATH)
  if have_cmd py && py - <<'PY' >/dev/null 2>&1
import pkgutil, sys
sys.exit(0 if pkgutil.find_loader("podman_compose") else 1)
PY
  then COMPOSE=( py -m podman_compose ); return 0; fi

  if have_cmd python && python - <<'PY' >/dev/null 2>&1
import pkgutil, sys
sys.exit(0 if pkgutil.find_loader("podman_compose") else 1)
PY
  then COMPOSE=( python -m podman_compose ); return 0; fi

  # Engine-native compose
  if "$oci_bin" compose version >/dev/null 2>&1; then COMPOSE=( "$oci_bin" compose ); return 0; fi

  # Legacy docker-compose as a last resort
  if [[ "$oci_bin" == *docker* ]] && have_cmd docker-compose; then COMPOSE=( docker-compose ); return 0; fi

  return 1
}

OCI_BIN="$(pick_engine || true)" || true
if [[ -z "${OCI_BIN:-}" ]]; then echo "❌ No container engine found (docker/podman)"; exit 127; fi
ENGINE="docker"; [[ "$OCI_BIN" == *podman* ]] && ENGINE="podman"
echo "ℹ️  Using engine: $ENGINE @ $OCI_BIN"

if choose_compose "$OCI_BIN"; then
  echo "ℹ️  Compose frontend: ${COMPOSE[*]}"
  # Try to remove any stale default network name (ignore errors)
  ( docker network rm "${COMPOSE_PROJECT_NAME}_default" 2>/dev/null || true )
  ( podman network rm "${COMPOSE_PROJECT_NAME}_default" 2>/dev/null || true )
  # Bring the stack down + volumes
  "${COMPOSE[@]}" down -v || true
else
  echo "⚠️  No compose frontend detected; continuing with raw $ENGINE cleanup."
fi

# Optional: light prune of *unused* objects only (safe)
if [[ "$PRUNE_UNUSED" = "1" && "$NUKE_IMAGES" = "0" && "$NUKE_ALL" = "0" ]]; then
  if [[ "$ENGINE" = "docker" ]]; then docker system prune -f || true
  else podman system prune -f || true
  fi
fi

# ----- NUKE paths -----
if [[ "$NUKE_ALL" = "1" ]]; then
  echo "💥 NUKE_ALL=1 — stopping ALL containers and pruning images/networks/volumes/cache"
  if [[ "$ENGINE" = "docker" ]]; then
    docker ps -aq | xargs -r docker rm -f || true
    docker system prune -a --volumes -f || true
  else
    podman ps -aq | xargs -r podman rm -f || true
    podman system prune -a --volumes -f || true
  fi
elif [[ "$NUKE_IMAGES" = "1" ]]; then
  echo "🧨 NUKE_IMAGES=1 — stopping ALL containers and removing ALL images"
  if [[ "$ENGINE" = "docker" ]]; then
    docker ps -aq | xargs -r docker rm -f || true
    docker images -aq | xargs -r docker rmi -f || true
  else
    podman ps -aq | xargs -r podman rm -f || true
    podman images -aq | xargs -r podman rmi -f || true
  fi
fi

echo "✅ Clean complete"
