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
CHECK_GROUP=""
CHECKS=()

# --- Helpers -----------------------------------------------------------------------------------------------------

group() {
	CHECK_GROUP="$1"

	if [[ "$JSON_OUTPUT" != "true" ]]; then
		printf '\n%s%s%s\n' "$C_INFO" "$1" "$C_RESET"
	fi
}

check() {
	local -r id="$1"
	local -r label="$2"
	local -r status="$3"
	local -r detail="${4:-}"
	local -r fix_description="${5:-}"
	local -r fix_command="${6:-}"

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

	if [[ "$JSON_OUTPUT" != "true" ]]; then
		if [[ -n "$detail" ]]; then
			printf '%s %-18s %s\n' "$icon" "$label" "$detail"
		else
			printf '%s %s\n' "$icon" "$label"
		fi
	fi

	record_check "$id" "$label" "$status" "$detail" "$fix_description" "$fix_command"
}

record_check() {
	local -r id="$1"
	local -r label="$2"
	local -r status="$3"
	local -r detail="$4"
	local -r fix_description="$5"
	local -r fix_command="$6"

	local fix="null"
	if [[ -n "$fix_command" ]]; then
		fix="{\"description\": \"$(json_escape "$fix_description")\", \"command\": \"$(json_escape "$fix_command")\"}"
	fi

	CHECKS+=(
		"{\"id\": \"$(json_escape "$id")\", \"group\": \"$(json_escape "$CHECK_GROUP")\", \"label\": \"$(json_escape "$label")\", \"status\": \"$status\", \"detail\": \"$(json_escape "$detail")\", \"fix\": $fix}"
	)
}

emit_json() {
	local -r payload="$(IFS=$','; printf '%s' "${CHECKS[*]-}")"
	local ok="true"

	if [[ "$FAILURES" -gt 0 ]]; then
		ok="false"
	fi

	printf '{"ok": %s, "failures": %d, "checks": [%s]}\n' "$ok" "$FAILURES" "$payload"
}

check_launch_options() {
	group "Steam"

	local -r options="${STEAM_LAUNCH_OPTIONS:-}"

	if [[ -z "$options" ]]; then
		check "steam.launch_options" "launch options" warn "<STEAM_LAUNCH_OPTIONS is not set>"
		return
	fi

	if ! have_cmd python3; then
		check "steam.launch_options" "launch options" warn "<python3 is missing>"
		return
	fi

	local current
	local -a args=(--appid "$BALATRO_APP_ID" --options "$options")
	if [[ -n "${STEAM_CONFIG_FILE:-}" ]]; then
		args+=(--config "$STEAM_CONFIG_FILE")
	fi

	current="$(python3 "$SCRIPT_DIR/steam/launch_options.py" "${args[@]}" --check 2> /dev/null || true)"

	if [[ "$current" == "$options" ]]; then
		check "steam.launch_options" "launch options" ok "$current"
	elif [[ -z "$current" ]]; then
		check "steam.launch_options" "launch options" warn "<not set>" \
			"Set the launch options of Balatro" "bash scripts/steam.sh launch-options --force"
	else
		check "steam.launch_options" "launch options" warn "<$current>" \
			"Update the launch options of Balatro" "bash scripts/steam.sh launch-options --force"
	fi
}

check_dependencies() {
	group "Dependencies"

	local cmd
	for cmd in git jq curl unzip python3; do
		if have_cmd "$cmd"; then
			check "dep.$cmd" "$cmd" ok
		else
			check "dep.$cmd" "$cmd" fail "<missing>"
		fi
	done

	if have_cmd task; then
		check "dep.task" "task" ok
	else
		check "dep.task" "task" warn "<missing, only needed for the task interface>"
	fi

	if [[ "${MOD_LINK_MODE:-symlink}" == "copy" ]]; then
		if have_cmd rsync; then
			check "dep.rsync" "rsync" ok
		else
			check "dep.rsync" "rsync" fail "<missing, required by MOD_LINK_MODE=copy>"
		fi
	fi
}

check_paths() {
	group "Paths"

	if [[ -n "$BALATRO_GAME_DIR" && -d "$BALATRO_GAME_DIR" ]]; then
		check "path.game_dir" "game dir" ok "$BALATRO_GAME_DIR"
	else
		check "path.game_dir" "game dir" fail "<not found, set BALATRO_GAME_DIR in config/balatro.local.env>"
	fi

	if [[ -n "$BALATRO_SAVE_DIR" && -d "$BALATRO_SAVE_DIR" ]]; then
		check "path.save_dir" "save dir" ok "$BALATRO_SAVE_DIR"
	else
		check "path.save_dir" "save dir" fail "<not found, set BALATRO_SAVE_DIR in config/balatro.local.env>"
	fi

	if [[ -n "$BALATRO_MODS_DIR" && -d "$BALATRO_MODS_DIR" ]]; then
		check "path.mods_dir" "mods dir" ok "$BALATRO_MODS_DIR"
	elif [[ -n "$BALATRO_MODS_DIR" ]]; then
		check "path.mods_dir" "mods dir" warn "<will be created>" \
			"Create the Mods folder" "bash scripts/mods.sh sync"
	else
		check "path.mods_dir" "mods dir" fail "<not found, the save directory could not be detected>"
	fi
}

check_modding_stack() {
	group "Modding stack"

	local injector=""
	if [[ -n "$BALATRO_GAME_DIR" && -d "$BALATRO_GAME_DIR" ]]; then
		if [[ -f "$BALATRO_GAME_DIR/winmm.dll" ]]; then
			injector="winmm.dll"
		elif [[ -f "$BALATRO_GAME_DIR/version.dll" ]]; then
			injector="version.dll"
		fi
	fi

	if [[ -n "$injector" ]]; then
		check "stack.lovely" "lovely" ok "$injector"
	else
		check "stack.lovely" "lovely" warn "<not installed>" \
			"Install the Lovely Injector" "bash scripts/loader.sh install"
	fi

	if [[ -n "$BALATRO_MODS_DIR" && -d "$BALATRO_MODS_DIR/smods" ]]; then
		check "stack.steamodded" "steamodded" ok "$BALATRO_MODS_DIR/smods"
	else
		check "stack.steamodded" "steamodded" warn "<not installed>" \
			"Install Steamodded" "bash scripts/loader.sh install"
	fi
}

check_collection() {
	group "Collection"

	if [[ -f "$MANIFEST_FILE" ]]; then
		if jq empty "$MANIFEST_FILE" 2> /dev/null; then
			check "collection.manifest" "manifest" ok "$MANIFEST_FILE ($(manifest_mod_count) mod(s))"
		else
			check "collection.manifest" "manifest" fail "<invalid JSON>"
		fi
	else
		check "collection.manifest" "manifest" fail "<missing: $MANIFEST_FILE>"
	fi

	if [[ -d "$COLLECTION_ROOT/.git" ]]; then
		local -r registered="$(git -C "$COLLECTION_ROOT" submodule status 2> /dev/null | wc -l | tr -d ' ')"
		local -r pending="$(git -C "$COLLECTION_ROOT" submodule status 2> /dev/null | grep -c '^-' || true)"

		if [[ "$pending" -gt 0 ]]; then
			check "collection.submodules" "submodules" warn "<$pending of $registered not initialized>" \
				"Initialize the submodules" "git submodule update --init"
		else
			check "collection.submodules" "submodules" ok "$registered registered"
		fi
	else
		check "collection.submodules" "submodules" warn "<not a git repository>"
	fi

	if [[ -n "$BALATRO_MODS_DIR" && -d "$BALATRO_MODS_DIR" && -w "$BALATRO_MODS_DIR" ]]; then
		check "collection.mods_dir_writable" "mods dir writable" ok
	else
		check "collection.mods_dir_writable" "mods dir writable" fail "<${BALATRO_MODS_DIR:-<unknown>} is not writable>"
	fi
}

main() {
	local -a args=("$@")
	parse_json_flag args

	load_config

	if [[ "$JSON_OUTPUT" != "true" ]]; then
		printf '\n%sBalatro Mod Hub — environment check%s\n\n' "$C_INFO" "$C_RESET"
	fi

	check_dependencies

	resolve_env false

	check_paths
	check_modding_stack
	check_collection

	check_launch_options

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		emit_json
		if [[ "$FAILURES" -gt 0 ]]; then
			exit 1
		fi
		exit 0
	fi

	printf '\n'
	if [[ "$FAILURES" -gt 0 ]]; then
		log_critical "$FAILURES check(s) failed"
	fi

	log_ok "Everything looks good"
}

main "$@"
