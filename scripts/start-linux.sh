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

MODS2="$(python3 - "${MAPCYCLE}" "${SERVER_START_MAP}" "${PRINT}" <<'PY'
import json
import sys
from pathlib import Path

mapcycle_path = Path(sys.argv[1])
print_only = sys.argv[3] == "1"

def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)

data = load_json(mapcycle_path)
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

shine_mod_ids = {
    1651491195: "[Shine] Switch Teams",
    593421222: "[Shine] Wonitor",
    208649136: "[Shine] Epsilon",
    2608952840: "Devnull - [Shine] Extras",
    2898899845: "[Shine]BAD",
}
shine_mod_present = 117887554 in mods
if not shine_mod_present:
    missing_shine_for = [name for mod_id, name in shine_mod_ids.items() if mod_id in mods]
    if missing_shine_for:
        raise SystemExit(
            "Shine Workshop ID 117887554 is required by: " + ", ".join(missing_shine_for)
        )

active_extensions = {}
if shine_mod_present:
    shine_config_path = mapcycle_path.parent / "shine" / "BaseConfig.json"
    if not shine_config_path.is_file():
        raise SystemExit("Shine Workshop ID 117887554 requires config/shine/BaseConfig.json")

    shine_config = load_json(shine_config_path)
    active_extensions = shine_config.get("ActiveExtensions")
    if not isinstance(active_extensions, dict):
        raise SystemExit("BaseConfig.json ActiveExtensions must be an object")

    web_configs = shine_config.get("WebConfigs", {})
    if not isinstance(web_configs.get("Plugins", {}), dict):
        raise SystemExit("BaseConfig.json WebConfigs.Plugins must be an object")

    if 2856795526 in mods and active_extensions.get("ns2panel"):
        raise SystemExit("Do not enable Epsilon ns2panel while the NS2Panel Workshop mod is mounted")

    if 1651491195 in mods:
        if active_extensions.get("switchteams") is not True:
            raise SystemExit("[Shine] Switch Teams requires ActiveExtensions.switchteams=true")
        switchteams_path = mapcycle_path.parent / "shine" / "plugins" / "switchteams.json"
        if not switchteams_path.is_file():
            raise SystemExit("[Shine] Switch Teams requires config/shine/plugins/switchteams.json")
        switchteams = load_json(switchteams_path)
        team_gap_limit = switchteams.get("teamgaplimit")
        if not isinstance(team_gap_limit, int) or team_gap_limit < 1:
            raise SystemExit("switchteams.json teamgaplimit must be a positive integer")

    if active_extensions.get("workshopupdater"):
        updater_path = mapcycle_path.parent / "shine" / "plugins" / "WorkshopUpdater.json"
        if not updater_path.is_file():
            raise SystemExit("Shine workshopupdater requires config/shine/plugins/WorkshopUpdater.json")

    if 1132771326 in mods:
        basecommands_path = mapcycle_path.parent / "shine" / "plugins" / "BaseCommands.json"
        if not basecommands_path.is_file():
            raise SystemExit("Enhanced Spectator requires config/shine/plugins/BaseCommands.json")
        basecommands = load_json(basecommands_path)
        if basecommands.get("AllTalkSpectator") is not True:
            raise SystemExit("Enhanced Spectator requires BaseCommands.json AllTalkSpectator=true")

if 593421222 in mods:
    if active_extensions.get("wonitor") is not True:
        raise SystemExit("[Shine] Wonitor requires ActiveExtensions.wonitor=true")
    wonitor_config_path = mapcycle_path.parent / "shine" / "plugins" / "wonitor.json"
    if not wonitor_config_path.is_file():
        raise SystemExit("Wonitor Workshop ID 593421222 requires config/shine/plugins/wonitor.json")
    wonitor = load_json(wonitor_config_path)
    server_id = wonitor.get("ServerIdentifier")
    wonitor_url = wonitor.get("WonitorURL")
    if not isinstance(server_id, str) or not server_id:
        raise SystemExit("wonitor.json must set non-empty ServerIdentifier")
    if not isinstance(wonitor_url, str) or not wonitor_url.startswith("http://"):
        raise SystemExit("wonitor.json must set WonitorURL to an http:// update.php endpoint")

if 2856795526 in mods:
    ns2panel_path = mapcycle_path.parent / "NS2Panel.json"
    if not ns2panel_path.is_file():
        raise SystemExit("NS2Panel Workshop ID 2856795526 requires config/NS2Panel.json")
    ns2panel = load_json(ns2panel_path)
    if not isinstance(ns2panel.get("PlayerConnectReport"), dict):
        raise SystemExit("NS2Panel.json must include PlayerConnectReport")
    if not isinstance(ns2panel.get("RoundEndReport"), dict):
        raise SystemExit("NS2Panel.json must include RoundEndReport")
    if not isinstance(ns2panel.get("PlayerSkillReport"), dict):
        raise SystemExit("NS2Panel.json must include PlayerSkillReport")
    auth_token = ns2panel.get("AuthToken")
    if not isinstance(auth_token, str):
        raise SystemExit("NS2Panel.json AuthToken must be a string")
    if not print_only and not auth_token:
        raise SystemExit("Set config/NS2Panel.json AuthToken before starting with NS2Panel enabled")

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
