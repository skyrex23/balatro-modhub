#!/usr/bin/env bash
# ======================================================================================================================
# Install and maintain the Balatro modding stack: Lovely Injector (runtime) + Steamodded (mod loader)
# ======================================================================================================================

set -euo pipefail

INVOKER="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_ROOT="${COLLECTION_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

LOVELY_REPO="ethangreen-dev/lovely-injector"
STEAMODDED_REPO="https://github.com/Steamodded/smods.git"

TMP_DIR=""

cleanup() {
	if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

trap cleanup EXIT

read -r -d '' USAGE << EOF || true
Usage: $INVOKER <command> [arguments]

Commands:
  install [--force]   Install Lovely and Steamodded
  update              Update Lovely and Steamodded
  uninstall           Remove Lovely and Steamodded
  status              Show the state of the modding stack
EOF

# --- Helpers -----------------------------------------------------------------------------------------------------

lovely_injector_file() {
	local -r game_dir="$1"

	if [[ -f "$game_dir/winmm.dll" ]]; then
		printf '%s' "winmm.dll"
	elif [[ -f "$game_dir/version.dll" ]]; then
		printf '%s' "version.dll"
	fi
}

lovely_release_url() {
	local -r release_json="$1"
	local -r asset_name="$(jq -r '.assets[] | select(.name | test("x86_64-pc-windows-msvc\\.zip$")) | .name' <<< "$release_json" | head -n 1)"

	if [[ -z "$asset_name" ]]; then
		asset_name="$(jq -r '.assets[] | select(.name | test("windows.*\\.zip$"; "i")) | .name' <<< "$release_json" | head -n 1)"
	fi
	[[ -n "$asset_name" ]] || return 1

	jq -r --arg n "$asset_name" '.assets[] | select(.name == $n) | .browser_download_url' <<< "$release_json"
}

install_lovely() {
	local -r force="${1:-false}"
	local -r game_dir="$BALATRO_GAME_DIR"

	require_game_dir
	require_cmd curl
	require_cmd unzip
	require_cmd jq

	local -r existing="$(lovely_injector_file "$game_dir" || true)"

	if [[ -n "$existing" && "$force" != "true" ]]; then
		log_ok "Lovely Injector already installed ($existing in $game_dir)"
		return 0
	fi

	log_step "Downloading Lovely Injector"
	local -r release_json="$(curl -fsSL "https://api.github.com/repos/$LOVELY_REPO/releases/latest")"
	local -r url="$(lovely_release_url "$release_json")" || log_critical "Could not find a Windows Lovely release"

	TMP_DIR="$(mktemp -d)"

	log_info "  $url"
	curl -fsSL "$url" -o "$TMP_DIR/lovely.zip"
	unzip -o -q "$TMP_DIR/lovely.zip" -d "$TMP_DIR/extracted"

	local -r injector="$(find "$TMP_DIR/extracted" -maxdepth 3 -type f \( -name "winmm.dll" -o -name "version.dll" \) | head -n 1)"
	[[ -n "$injector" ]] || log_critical "No injector dll found in the Lovely archive"

	cp -f "$injector" "$game_dir/$(basename "$injector")"
	log_ok "Lovely Injector installed ($(basename "$injector") in $game_dir)"

	if [[ "$(basename "$injector")" == "winmm.dll" ]]; then
		log_info '  Set the Steam launch option: WINEDLLOVERRIDES="winmm=n,b" %command%'
	else
		log_info "  Set the Steam launch option: WINEDLLOVERRIDES=\"version=n,b\" %command%"
	fi
}

install_steamodded() {
	local -r force="${1:-false}"
	local -r target="$BALATRO_MODS_DIR/smods"

	require_cmd git
	mkdir -p "$BALATRO_MODS_DIR"

	if [[ -d "$target/.git" ]]; then
		if [[ "$force" == "true" ]]; then
			log_step "Updating Steamodded"
			git -C "$target" pull --ff-only
		fi
		log_ok "Steamodded already installed in $target"
		return 0
	fi

	if [[ -e "$target" ]]; then
		log_critical "'$target' exists and is not a git checkout, remove it and run the task again"
	fi

	log_step "Installing Steamodded in $target"
	git clone --depth 1 "$STEAMODDED_REPO" "$target"
	log_ok "Steamodded installed"
}

# --- Commands ----------------------------------------------------------------------------------------------------

cmd_install() {
	local -r force="${1:-false}"

	resolve_env
	require_game_dir

	install_steamodded "$force"
	install_lovely "$force"

	log_info ""
	log_info "Next steps:"
	log_info "  1. In Steam, set the launch options of Balatro to: WINEDLLOVERRIDES=\"winmm=n,b\" %command%"
	log_info "  2. Enable your mods with: task mods:sync"
}

cmd_update() {
	resolve_env
	require_game_dir

	install_steamodded "true"
	install_lovely "true"
}

cmd_uninstall() {
	resolve_env

	local -r game_dir="${BALATRO_GAME_DIR:-}"
	if [[ -n "$game_dir" ]]; then
		local -r injector="$(lovely_injector_file "$game_dir" || true)"
		if [[ -n "$injector" ]]; then
			rm -f "$game_dir/$injector"
			log_ok "Removed $injector from $game_dir"
		fi
	fi

	if [[ -d "$BALATRO_MODS_DIR/smods" ]]; then
		rm -rf "${BALATRO_MODS_DIR:?}/smods"
		log_ok "Removed Steamodded from $BALATRO_MODS_DIR"
	fi
}

cmd_status() {
	resolve_env

	printf 'game dir:   %s\n' "${BALATRO_GAME_DIR:-<not found>}"
	printf 'save dir:   %s\n' "${BALATRO_SAVE_DIR:-<not found>}"
	printf 'mods dir:   %s\n' "$BALATRO_MODS_DIR"

	local -r injector="$(lovely_injector_file "${BALATRO_GAME_DIR:-/nonexistent}" || true)"
	printf 'lovely:     %s\n' "${injector:-<not installed>}"

	if [[ -d "$BALATRO_MODS_DIR/smods" ]]; then
		printf 'steamodded: %s\n' "$(git -C "$BALATRO_MODS_DIR/smods" rev-parse --short HEAD 2> /dev/null || echo unknown)"
	else
		printf 'steamodded: <not installed>\n'
	fi
}

main() {
	local -r command="${1:-}"
	[[ -n "$command" ]] || {
		printf '%s\n' "$USAGE"
		exit 2
	}
	shift

	case "$command" in
	install) cmd_install "$@" ;;
	update) cmd_update "$@" ;;
	uninstall) cmd_uninstall "$@" ;;
	status) cmd_status "$@" ;;
	help | --help | -h) printf '%s\n' "$USAGE" ;;
	*) log_critical "Unknown command: $command" ;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
