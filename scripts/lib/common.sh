#!/usr/bin/env bash
# ======================================================================================================================
# Shared helpers for the Balatro mods collection: config loading, path detection and manifest access
# ======================================================================================================================

set -euo pipefail

INVOKER="${INVOKER:-$(basename "${BASH_SOURCE[0]}")}"

COLLECTION_ROOT="${COLLECTION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_DIR="$COLLECTION_ROOT/config"
COLLECTION_MODS_DIR="$COLLECTION_ROOT/mods"
MANIFEST_FILE="${MANIFEST_FILE:-$CONFIG_DIR/mods.json}"
BALATRO_APP_ID="${BALATRO_APP_ID:-2379780}"
BALATRO_MODS_FOLDER_NAME="Mods"

# --- Logging -----------------------------------------------------------------------------------------------------

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_INFO=$'\033[36m'
	C_OK=$'\033[32m'
	C_WARN=$'\033[33m'
	C_ERR=$'\033[31m'
else
	C_RESET=""
	C_INFO=""
	C_OK=""
	C_WARN=""
	C_ERR=""
fi

log_info() { printf '%s\n' "$*"; }
log_step() { printf '%s==>%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
log_ok() { printf '%s✓%s %s\n' "$C_OK" "$C_RESET" "$*"; }
log_warn() { printf '%s!%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
log_error() { printf '%sx%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; }
log_critical() {
	printf '%sx%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
	exit 1
}

# --- Generic helpers ---------------------------------------------------------------------------------------------

require_cmd() {
	local -r cmd="$1"
	command -v "$cmd" &> /dev/null || log_critical "Required command not found: $cmd"
}

have_cmd() {
	command -v "$1" &> /dev/null
}

# --- Configuration -----------------------------------------------------------------------------------------------

load_config() {
	local -r base_config="$CONFIG_DIR/balatro.env"
	local -r local_config="$CONFIG_DIR/balatro.local.env"

	if [[ -f "$base_config" ]]; then
		# shellcheck source=/dev/null
		source "$base_config"
	fi
	if [[ -f "$local_config" ]]; then
		# shellcheck source=/dev/null
		source "$local_config"
	fi
}

# --- Path detection ----------------------------------------------------------------------------------------------

steam_library_dirs() {
	local -r vdf="$HOME/.steam/steam/steamapps/libraryfolders.vdf"
	local -r flatpak_vdf="$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/libraryfolders.vdf"

	printf '%s\n' "$HOME/.steam/steam" "$HOME/.local/share/Steam" \
		"$HOME/.var/app/com.valvesoftware.Steam/data/Steam" "$HOME/snap/steam/common/.local/share/Steam"

	local file
	for file in "$vdf" "$flatpak_vdf"; do
		[[ -f "$file" ]] || continue
		sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$file"
	done
}

detect_game_dir() {
	local candidate

	for candidate in "${BALATRO_GAME_DIR:-}" \
		"$HOME/.steam/steam/steamapps/common/Balatro" \
		"$HOME/.local/share/Steam/steamapps/common/Balatro" \
		"$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common/Balatro" \
		"$HOME/snap/steam/common/.local/share/Steam/steamapps/common/Balatro"; do
		if [[ -n "$candidate" && -d "$candidate" ]]; then
			printf '%s' "$candidate"
			return 0
		fi
	done

	local library
	while read -r library; do
		[[ -n "$library" ]] || continue
		candidate="$library/steamapps/common/Balatro"
		if [[ -d "$candidate" ]]; then
			printf '%s' "$candidate"
			return 0
		fi
	done < <(steam_library_dirs)

	return 1
}

detect_save_dir() {
	local candidate

	for candidate in "${BALATRO_SAVE_DIR:-}" \
		"$HOME/.steam/steam/steamapps/compatdata/$BALATRO_APP_ID/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro" \
		"$HOME/.local/share/Steam/steamapps/compatdata/$BALATRO_APP_ID/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro" \
		"$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata/$BALATRO_APP_ID/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro" \
		"$HOME/snap/steam/common/.local/share/Steam/steamapps/compatdata/$BALATRO_APP_ID/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro"; do
		if [[ -n "$candidate" && -d "$candidate" ]]; then
			printf '%s' "$candidate"
			return 0
		fi
	done

	# Fallback: any wine prefix that already has a Balatro save directory
	while IFS= read -r candidate; do
		printf '%s' "$candidate"
		return 0
	done < <(find "$HOME"/.steam/steam/steamapps/compatdata "$HOME"/.local/share/Steam/steamapps/compatdata \
		-maxdepth 6 -type d -path "*/AppData/Roaming/Balatro" 2> /dev/null | sort | head -n 1)

	return 1
}

resolve_env() {
	load_config

	BALATRO_GAME_DIR="${BALATRO_GAME_DIR:-$(detect_game_dir || true)}"
	BALATRO_SAVE_DIR="${BALATRO_SAVE_DIR:-$(detect_save_dir || true)}"
	MOD_LINK_MODE="${MOD_LINK_MODE:-symlink}"

	if [[ -z "$BALATRO_SAVE_DIR" ]]; then
		log_critical "Could not detect the Balatro save directory. Set BALATRO_SAVE_DIR in config/balatro.local.env"
	fi

	BALATRO_MODS_DIR="$BALATRO_SAVE_DIR/$BALATRO_MODS_FOLDER_NAME"
	export BALATRO_GAME_DIR BALATRO_SAVE_DIR BALATRO_MODS_DIR MOD_LINK_MODE
}

require_game_dir() {
	[[ -n "$BALATRO_GAME_DIR" && -d "$BALATRO_GAME_DIR" ]] ||
		log_critical "Balatro game directory not found. Set BALATRO_GAME_DIR in config/balatro.local.env"
}

# --- Manifest access ---------------------------------------------------------------------------------------------

require_manifest() {
	require_cmd jq
	[[ -f "$MANIFEST_FILE" ]] || log_critical "Manifest not found: $MANIFEST_FILE"
	jq empty "$MANIFEST_FILE" 2> /dev/null || log_critical "Manifest is not valid JSON: $MANIFEST_FILE"
}

manifest_names() {
	jq -r '.mods[].name' "$MANIFEST_FILE"
}

manifest_field() {
	local -r name="$1"
	local -r field="$2"

	jq -r --arg n "$name" --arg f "$field" '
		.mods[] | select(.name == $n) |
		if has($f) then
			.[$f] | if type == "boolean" then (if . then "true" else "false" end) else tostring end
		else
			""
		end
	' "$MANIFEST_FILE"
}

manifest_exists() {
	local -r name="$1"
	[[ "$(jq -r --arg n "$name" '[.mods[] | select(.name == $n)] | length' "$MANIFEST_FILE")" != "0" ]]
}

manifest_mod_count() {
	jq -r '.mods | length' "$MANIFEST_FILE"
}

manifest_set_field() {
	local -r name="$1"
	local -r field="$2"
	local -r value="$3"
	local -r tmp_file="$(mktemp)"

	jq --arg n "$name" --arg f "$field" --arg v "$value" '
		.mods = [.mods[] | if .name == $n then .[$f] = ($v | if $f == "enabled" then ($v == "true") else $v end) else . end]
	' "$MANIFEST_FILE" > "$tmp_file"

	mv "$tmp_file" "$MANIFEST_FILE"
}

manifest_remove_mod() {
	local -r name="$1"
	local -r tmp_file="$(mktemp)"

	jq --arg n "$name" '.mods = [.mods[] | select(.name != $n)]' "$MANIFEST_FILE" > "$tmp_file"

	mv "$tmp_file" "$MANIFEST_FILE"
}

manifest_add_mod() {
	local -r name="$1"
	local -r repo="$2"
	local -r path="$3"
	local -r ref="$4"
	local -r enabled="$5"
	local -r description="$6"
	local -r checkout="$7"
	local -r tmp_file="$(mktemp)"

	jq --arg n "$name" --arg r "$repo" --arg p "$path" --arg b "$ref" \
		--argjson e "$enabled" --arg d "$description" --arg c "$checkout" '
		.mods += [{
			name: $n,
			repo: $r,
			checkout: $c,
			path: $p,
			branch: $b,
			enabled: $e,
			description: $d
		}]
	' "$MANIFEST_FILE" > "$tmp_file"

	mv "$tmp_file" "$MANIFEST_FILE"
}

# --- Mod helpers -------------------------------------------------------------------------------------------------

mod_checkout_dir() {
	local -r name="$1"
	local -r checkout="$(manifest_field "$name" "checkout")"

	printf '%s' "$COLLECTION_MODS_DIR/${checkout:-$name}"
}

mod_source_dir() {
	local -r name="$1"
	local -r raw_path="$(manifest_field "$name" "path")"
	local -r subpath="${raw_path:-.}"

	printf '%s' "$(mod_checkout_dir "$name")/$subpath"
}

mod_target_dir() {
	local -r name="$1"
	printf '%s' "$BALATRO_MODS_DIR/$name"
}

mod_is_enabled() {
	[[ "$(manifest_field "$1" "enabled")" == "true" ]]
}

mod_is_linked() {
	local -r target="$(mod_target_dir "$1")"
	[[ -L "$target" || -d "$target" ]]
}

mod_local_commit() {
	local -r source="$(mod_checkout_dir "$1")"

	git -C "$source" rev-parse --short HEAD 2> /dev/null || printf '%s' "-"
}
