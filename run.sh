#!/usr/bin/env bash
# run.sh — start the stack (compose if available; host fallback), wait, and open browser
set -euo pipefail

# ===== Config (override via env) =====
APP_URL="${APP_URL:-http://localhost:5000/}"   # What to open after start
APP_SERVICE="${APP_SERVICE:-app}"               # Compose service name for Flask app
OPEN_TIMEOUT="${OPEN_TIMEOUT:-60}"              # Seconds to wait for readiness
HOST_FALLBACK="${HOST_FALLBACK:-1}"             # 1=allow running on host if compose missing

have_cmd() { command -v "$1" >/dev/null 2>&1; }

pick_engine() {
  if [[ -n "${CONTAINER_ENGINE:-}" ]] && have_cmd "$CONTAINER_ENGINE"; then
    command -v "$CONTAINER_ENGINE"; return 0
  fi
  if have_cmd podman; then command -v podman; return 0; fi
  if have_cmd docker; then command -v docker; return 0; fi
  echo ""; return 1
}

# choose_compose() {
#   local oci_bin="$1"

#   # If we're on Podman, prefer the Python podman-compose providers FIRST
#   if [[ "$oci_bin" == *podman* ]]; then
#     if have_cmd podman-compose; then COMPOSE=( podman-compose ); return 0; fi
#     if python - <<'PY' >/dev/null 2>&1
# import importlib, sys
# sys.exit(0 if importlib.util.find_spec("podman_compose") else 1)
# PY
#     then COMPOSE=( python -m podman_compose ); return 0; fi
#   fi

#   # Next, try the engine-native "compose" subcommand (works for Docker and
#   # for Podman when a proper compose provider is wired in)
#   if "$oci_bin" compose version >/dev/null 2>&1; then
#     COMPOSE=( "$oci_bin" compose )
#     return 0
#   fi

#   # Last resort: legacy docker-compose
#   if [[ "$oci_bin" == *docker* ]] && have_cmd docker-compose; then
#     COMPOSE=( docker-compose )
#     return 0
#   fi

#   return 1
# }


choose_compose() {
  local oci_bin="$1"

  # Prefer Python module frontends (works even if no exe on PATH)
  if command -v py >/dev/null 2>&1 && py - <<'PY' >/dev/null 2>&1
import pkgutil, sys
sys.exit(0 if pkgutil.find_loader("podman_compose") else 1)
PY
  then COMPOSE=( py -m podman_compose ); return 0; fi

  if command -v python >/dev/null 2>&1 && python - <<'PY' >/dev/null 2>&1
import pkgutil, sys
sys.exit(0 if pkgutil.find_loader("podman_compose") else 1)
PY
  then COMPOSE=( python -m podman_compose ); return 0; fi

  # Engine-native compose (OK if Podman has a provider wired)
  if "$oci_bin" compose version >/dev/null 2>&1; then COMPOSE=( "$oci_bin" compose ); return 0; fi

  # Legacy docker-compose
  if [[ "$oci_bin" == *docker* ]] && command -v docker-compose >/dev/null 2>&1; then COMPOSE=( docker-compose ); return 0; fi

  return 1
}



info() { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }
fail() { echo "❌ $*" >&2; }

wait_for_app() {
  local url="$1" timeout="$2"
  info "Waiting for ${url} (timeout ${timeout}s)…"
  local have_curl=1; have_cmd curl || have_curl=0
  local deadline=$(( $(date +%s) + timeout ))
  local ok_flag=0
  while [[ $(date +%s) -lt $deadline ]]; do
    if [[ $have_curl -eq 1 ]]; then
      if curl -fsS -o /dev/null "$url"; then ok_flag=1; break; fi
    else
      # TCP fallback (may not work in all shells)
      local host="localhost" port="5000"
      if (exec 3<>/dev/tcp/$host/$port) 2>/dev/null; then ok_flag=1; break; fi
    fi
    sleep 2
  done
  if [[ $ok_flag -eq 1 ]]; then ok "App responded."; else warn "App didn’t respond within ${timeout}s."; fi
  return $ok_flag
}

open_default() {
  local url="$1"
  info "Opening ${url}…"
  case "$(uname -s)" in
    Darwin)  exec /usr/bin/open "$url" ;;
    Linux)   if have_cmd xdg-open; then exec xdg-open "$url"; fi ;;
  esac
  # WSL → Windows default browser
  if have_cmd wslview; then exec wslview "$url"; fi
  # Windows shells (Git Bash/MSYS/Cygwin)
  if have_cmd powershell.exe; then exec powershell.exe -NoProfile -Command "Start-Process \"$url\""; fi
  if have_cmd cmd.exe; then exec cmd.exe /c start "" "$url"; fi
  warn "Couldn’t auto-open the browser. Please open: $url"
}

run_host() {
  info "Falling back to HOST Flask (no containers)."
  # Ensure deps installed (editable dev). Comment this if you manage deps elsewhere.
  if ! python - <<'PY' >/dev/null 2>&1
import importlib, sys
sys.exit(0 if importlib.util.find_spec("flask") else 1)
PY
  then
    info "Installing Python deps locally…"
    python -m pip install --upgrade pip
    pip install -e .[dev]
  fi

  # If DB is not available locally, UI still loads; DB health endpoints may fail.
  export DB_HOST="${DB_HOST:-127.0.0.1}"

  info "Starting Flask on host (run.py)…"
  python run.py >/dev/null 2>&1 &
  APP_PID=$!
  trap 'kill $APP_PID 2>/dev/null || true' EXIT

  wait_for_app "$APP_URL" "$OPEN_TIMEOUT" || true
  open_default "$APP_URL"
}

main() {
  local oci_bin
  oci_bin="$(pick_engine || true)"

  if [[ -z "${oci_bin}" ]]; then
    fail "No container engine found."
    if [[ "$HOST_FALLBACK" = "1" ]]; then run_host; else exit 127; fi
    return
  fi

  local eng="Docker"; [[ "$oci_bin" == *podman* ]] && eng="Podman"
  info "Using container engine: ${eng} @ ${oci_bin}"
  "$oci_bin" version || true

  if ! choose_compose "$oci_bin"; then
    fail "No compose front-end found for ${eng}."
    if [[ "$HOST_FALLBACK" = "1" ]]; then run_host; else exit 127; fi
    return
  fi

  info "Starting containers (detached)…"
  info "Compose frontend: ${COMPOSE[*]}"

  "${COMPOSE[@]}" up -d

  if wait_for_app "$APP_URL" "$OPEN_TIMEOUT"; then
    open_default "$APP_URL"
    exit 0
  fi

  # Diagnostics on failure
  warn "Dumping compose status and app logs…"
  echo "------ compose ps ------"
  "${COMPOSE[@]}" ps || true
  echo "------ ${APP_SERVICE} logs ------"
  "${COMPOSE[@]}" logs --no-color "$APP_SERVICE" || true

  # Try to open anyway (maybe it came up late); don't fail on open
  open_default "$APP_URL" || true
  exit 1
}

main
