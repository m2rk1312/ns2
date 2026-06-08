#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRINT=0

fail() {
  echo "$*" >&2
  exit 1
}

require_uint() {
  local name="$1"
  local value="${!name}"
  [[ "${value}" =~ ^[0-9]+$ ]] || fail "${name} must be numeric: ${value}"
}

require_range() {
  local name="$1"
  local min="$2"
  local max="$3"
  local value="${!name}"

  require_uint "${name}"
  (( 10#${value} >= min && 10#${value} <= max )) || fail "${name} must be between ${min} and ${max}: ${value}"
}

CONFIG_KEYS=(
  NS2_ROOT
  NS2_SERVERFILES
  NS2_CONFIG_PATH
  NS2_LOG_DIR
  NS2_WORKSHOP_DIR
  SERVER_NAME
  SERVER_PORT
  SERVER_LIMIT
  SERVER_SPEC_LIMIT
  SERVER_START_MAP
  WEB_ADMIN
  WEB_PORT
  WEB_USER
  WEB_PASSWORD
  MOD_SERVER_PORT
)

case "${1:-}" in
  "") ;;
  --print-command) PRINT=1 ;;
  -h|--help)
    echo "Usage: scripts/start-linux.sh [--print-command]"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    exit 2
    ;;
esac
if [[ $# -gt 1 ]]; then
  fail "Too many arguments"
fi

unset "${CONFIG_KEYS[@]}"

if [[ -f "${ROOT}/.env" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || fail "Invalid .env line: ${line}"
    key="${line%%=*}"
    [[ " ${CONFIG_KEYS[*]} " == *" ${key} "* ]] || fail "Unsupported .env key: ${key}"
    value="${line#*=}"
    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    printf -v "${key}" "%s" "${value}"
  done < "${ROOT}/.env"
fi

: "${NS2_ROOT:=/home/ns2server/ns2}"
: "${NS2_SERVERFILES:=${NS2_ROOT}/serverfiles}"
: "${NS2_CONFIG_PATH:=${ROOT}/config}"
: "${NS2_LOG_DIR:=${NS2_ROOT}/logs}"
: "${NS2_WORKSHOP_DIR:=${NS2_ROOT}/workshop}"
: "${SERVER_NAME:=<x76>EU Server (smurfs allowed)}"
: "${SERVER_PORT:=27015}"
: "${SERVER_LIMIT:=20}"
: "${SERVER_SPEC_LIMIT:=5}"
: "${SERVER_START_MAP:=ns2_biodome}"
: "${WEB_ADMIN:=0}"
: "${WEB_PORT:=8080}"
: "${WEB_USER:=admin}"
: "${WEB_PASSWORD:=}"
: "${MOD_SERVER_PORT:=27017}"

SERVER_BIN="${NS2_SERVERFILES}/x64/server_linux"
RUNTIME="${NS2_SERVERFILES}/steam-runtime/shell.sh"
MAPCYCLE="${NS2_CONFIG_PATH}/MapCycle.json"

for path in NS2_SERVERFILES NS2_CONFIG_PATH NS2_LOG_DIR NS2_WORKSHOP_DIR; do
  [[ "${!path}" == /* ]] || fail "${path} must be absolute: ${!path}"
done
require_range SERVER_PORT 1 65535
require_range WEB_PORT 1 65535
require_range MOD_SERVER_PORT 1 65535
require_range SERVER_LIMIT 1 64
require_range SERVER_SPEC_LIMIT 0 64
[[ "${WEB_ADMIN}" == 0 || "${WEB_ADMIN}" == 1 ]] || fail "WEB_ADMIN must be 0 or 1"
[[ -n "${SERVER_NAME}" ]] || fail "SERVER_NAME must not be empty"
[[ -n "${WEB_USER}" ]] || fail "WEB_USER must not be empty"
[[ -r "${MAPCYCLE}" ]] || fail "Missing readable map cycle: ${MAPCYCLE}"

if [[ "${PRINT}" == 0 ]]; then
  [[ "${EUID}" != 0 || "${ALLOW_ROOT:-0}" == 1 ]] || fail "Do not run NS2 as root. Use sudo -u ns2server, or set ALLOW_ROOT=1 only for local testing."
  [[ -x "${SERVER_BIN}" ]] || fail "Missing executable: ${SERVER_BIN}
Install NS2 dedicated server files with SteamCMD, or set NS2_SERVERFILES in .env."
fi

MODS2="$(python3 - "${MAPCYCLE}" "${SERVER_START_MAP}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
mods = data.get("mods")

def require_mod_list(value, label, allow_empty=False):
    if not isinstance(value, list) or (not value and not allow_empty):
        raise SystemExit(f"{label} must be a {'possibly empty ' if allow_empty else 'non-empty '}integer list")
    if any(not isinstance(mod, int) for mod in value):
        raise SystemExit(f"{label} must contain only integer Workshop IDs")
    if len(value) != len(set(value)):
        raise SystemExit(f"{label} must not contain duplicate Workshop IDs")

require_mod_list(mods, "MapCycle.json mods")
if 2934445221 not in mods:
    raise SystemExit("MapCycle.json must include CBM Workshop ID 2934445221")

maps = []
for index, item in enumerate(data.get("maps", []), start=1):
    if isinstance(item, str):
        map_name = item
    elif isinstance(item, dict):
        map_name = item.get("map")
        require_mod_list(item.get("mods", []), f"MapCycle.json maps[{index}].mods", allow_empty=True)
    else:
        raise SystemExit(f"MapCycle.json maps[{index}] must be a string or object")
    if not isinstance(map_name, str) or not map_name:
        raise SystemExit(f"MapCycle.json maps[{index}] must have a non-empty map name")
    maps.append(map_name)

if not maps:
    raise SystemExit("MapCycle.json maps must not be empty")
if len(maps) != len(set(maps)):
    raise SystemExit("MapCycle.json maps must not contain duplicate map names")
if sys.argv[2] not in maps:
    raise SystemExit(f"SERVER_START_MAP is not in MapCycle.json: {sys.argv[2]}")
print(",".join(map(str, mods)))
PY
)"

if [[ "${WEB_ADMIN}" == 1 ]]; then
  [[ ${#WEB_PASSWORD} -ge 16 ]] || fail "Set WEB_PASSWORD to at least 16 characters, or set WEB_ADMIN=0."
  if [[ -f "${ROOT}/.env" ]]; then
    python3 -c 'import os,sys; raise SystemExit(1 if os.stat(sys.argv[1]).st_mode & 0o077 else 0)' "${ROOT}/.env" \
      || fail ".env must not be group/world readable when WEB_ADMIN=1. Run: chmod 600 .env"
  fi
fi

ARGS=(
  "${SERVER_BIN}"
  -name "${SERVER_NAME}"
  -port "${SERVER_PORT}"
  -limit "${SERVER_LIMIT}"
  -speclimit "${SERVER_SPEC_LIMIT}"
  -map "${SERVER_START_MAP}"
  -config_path "${NS2_CONFIG_PATH}"
  -logdir "${NS2_LOG_DIR}"
  -modstorage "${NS2_WORKSHOP_DIR}"
  -startmodserver
  -modserverport "${MOD_SERVER_PORT}"
  -mods2 "${MODS2}"
)

if [[ "${WEB_ADMIN}" == 1 ]]; then
  ARGS+=(-webadmin -webport "${WEB_PORT}" -webuser "${WEB_USER}" -webpassword "${WEB_PASSWORD}")
fi

if [[ "${PRINT}" == 1 ]]; then
  PRINT_ARGS=("${ARGS[@]}")
  for ((index = 0; index < ${#PRINT_ARGS[@]}; index++)); do
    if [[ "${PRINT_ARGS[index]}" == "-webpassword" && $((index + 1)) -lt ${#PRINT_ARGS[@]} ]]; then
      PRINT_ARGS[index + 1]="<redacted>"
    fi
  done
  printf "%q" "${PRINT_ARGS[0]}"
  printf " %q" "${PRINT_ARGS[@]:1}"
  printf "\n"
  exit 0
fi

mkdir -p "${NS2_LOG_DIR}" "${NS2_WORKSHOP_DIR}"
if [[ -x "${RUNTIME}" ]]; then
  exec "${RUNTIME}" "${ARGS[@]}"
fi
exec "${ARGS[@]}"
