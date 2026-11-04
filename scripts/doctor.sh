#!/usr/bin/env bash
# ======================================================================================================================
# Verify the local environment: dependencies, Balatro paths, modding stack and collection state
# ======================================================================================================================

set -euo pipefail

INVOKER="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_ROOT="${COLLECTION_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FAILURES=0

check() {
	local -r label="$1"
	local -r status="$2"
	local -r detail="${3:-}"

	local icon
	case "$status" in
	ok) icon="$C_OK✓$C_RESET" ;;
	warn) icon="$C_WARN!$C_RESET" ;;
	fail)
		icon="$C_ERR✗$C_RESET"
		FAILURES=$((FAILURES + 1))
		;;
	*) icon="" ;;
	esac

	if [[ -n "$detail" ]]; then
		printf '%s %-18s %s\n' "$icon" "$label" "$detail"
	else
		printf '%s %s\n' "$icon" "$label"
	fi
}

check_launch_options() {
	local vdf
	vdf="$(find "$HOME"/.steam/steam/userdata "$HOME"/.local/share/Steam/userdata \
		-maxdepth 3 -name "localconfig.vdf" 2> /dev/null | head -n 1)"

	if [[ -z "$vdf" ]]; then
		check "launch options" warn "<localconfig.vdf not found, set them manually in Steam>"
		return
	fi

	local options
	options="$(grep -A 40 "\"$BALATRO_APP_ID\"" "$vdf" | grep -m 1 '"LaunchOptions"' |
		sed 's/.*"LaunchOptions"[[:space:]]*"\(.*\)".*/\1/' || true)"

	if [[ -z "$options" ]]; then
		check "launch options" warn "<not set, use WINEDLLOVERRIDES=\"winmm=n,b\" %command%>"
	elif [[ "$options" == *"WINEDLLOVERRIDES"* ]]; then
		check "launch options" ok "$options"
	else
		check "launch options" warn "<$options, add WINEDLLOVERRIDES=\"winmm=n,b\">"
	fi
}

main() {
	printf '\n%sBalatro mods collection — environment check%s\n\n' "$C_INFO" "$C_RESET"

	printf '%sDependencies%s\n' "$C_INFO" "$C_RESET"
	local cmd
	for cmd in git jq curl unzip task; do
		if have_cmd "$cmd"; then
			check "$cmd" ok
		else
			check "$cmd" fail "<missing>"
		fi
	done

	if [[ "${MOD_LINK_MODE:-symlink}" == "copy" ]]; then
		if have_cmd rsync; then
			check "rsync" ok
		else
			check "rsync" fail "<missing, required by MOD_LINK_MODE=copy>"
		fi
	fi

	printf '\n%sPaths%s\n' "$C_INFO" "$C_RESET"
	resolve_env

	if [[ -n "$BALATRO_GAME_DIR" && -d "$BALATRO_GAME_DIR" ]]; then
		check "game dir" ok "$BALATRO_GAME_DIR"
	else
		check "game dir" fail "<not found, set BALATRO_GAME_DIR in config/balatro.local.env>"
	fi

	if [[ -n "$BALATRO_SAVE_DIR" && -d "$BALATRO_SAVE_DIR" ]]; then
		check "save dir" ok "$BALATRO_SAVE_DIR"
	else
		check "save dir" fail "<not found, set BALATRO_SAVE_DIR in config/balatro.local.env>"
	fi

	if [[ -d "$BALATRO_MODS_DIR" ]]; then
		check "mods dir" ok "$BALATRO_MODS_DIR"
	else
		check "mods dir" warn "$BALATRO_MODS_DIR <will be created>"
	fi

	printf '\n%sModding stack%s\n' "$C_INFO" "$C_RESET"
	local injector=""
	if [[ -n "$BALATRO_GAME_DIR" && -d "$BALATRO_GAME_DIR" ]]; then
		if [[ -f "$BALATRO_GAME_DIR/winmm.dll" ]]; then
			injector="winmm.dll"
		elif [[ -f "$BALATRO_GAME_DIR/version.dll" ]]; then
			injector="version.dll"
		fi
	fi

	if [[ -n "$injector" ]]; then
		check "lovely" ok "$injector"
	else
		check "lovely" warn "<not installed, run 'task loader:install'>"
	fi

	if [[ -d "$BALATRO_MODS_DIR/smods" ]]; then
		check "steamodded" ok "$BALATRO_MODS_DIR/smods"
	else
		check "steamodded" warn "<not installed, run 'task loader:install'>"
	fi

	printf '\n%sCollection%s\n' "$C_INFO" "$C_RESET"
	if [[ -f "$MANIFEST_FILE" ]]; then
		if jq empty "$MANIFEST_FILE" 2> /dev/null; then
			check "manifest" ok "$MANIFEST_FILE ($(manifest_mod_count) mod(s))"
		else
			check "manifest" fail "<invalid JSON>"
		fi
	else
		check "manifest" fail "<missing: $MANIFEST_FILE>"
	fi

	if [[ -d "$COLLECTION_ROOT/.git" ]]; then
		local -r submodules="$(git -C "$COLLECTION_ROOT" submodule status 2> /dev/null | wc -l | tr -d ' ')"
		check "submodules" ok "$submodules registered"
	else
		check "submodules" warn "<not a git repository>"
	fi

	if [[ -d "$BALATRO_MODS_DIR" && -w "$BALATRO_MODS_DIR" ]]; then
		check "mods dir writable" ok
	else
		check "mods dir writable" fail "<$BALATRO_MODS_DIR is not writable>"
	fi

	check_launch_options

	printf '\n'
	if [[ "$FAILURES" -gt 0 ]]; then
		log_critical "$FAILURES check(s) failed"
	fi

	log_ok "Everything looks good"
}

main "$@"
