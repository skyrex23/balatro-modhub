#!/usr/bin/env bash
# ======================================================================================================================
# Manage the Steam configuration of Balatro: the launch options needed by the Lovely Injector
# ======================================================================================================================

set -euo pipefail

INVOKER="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_ROOT="${COLLECTION_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

read -r -d '' USAGE << EOF || true
Usage: $INVOKER <command> [arguments]

Commands:
  launch-options [--force]  Set the launch options of Balatro in the Steam configuration
  check                     Show the launch options of Balatro
EOF

launch_options_args() {
	local -r force="${1:-false}"
	local -r options="${STEAM_LAUNCH_OPTIONS:-}"

	[[ -n "$options" ]] || log_critical "STEAM_LAUNCH_OPTIONS is not set, define it in config/balatro.env"

	require_cmd python3

	local -a args=(--appid "$BALATRO_APP_ID" --options "$options")
	[[ "$force" == "true" ]] && args+=(--force)

	python3 "$SCRIPT_DIR/steam/launch_options.py" "${args[@]}"
}

cmd_launch_options() {
	load_config
	launch_options_args "${1:-false}"
}

cmd_check() {
	load_config
	require_cmd python3

	local -r options="${STEAM_LAUNCH_OPTIONS:-}"
	local current
	current="$(python3 "$SCRIPT_DIR/steam/launch_options.py" --appid "$BALATRO_APP_ID" --options "$options" --check 2> /dev/null || true)"

	if [[ -z "$current" ]]; then
		log_warn "The launch options of Balatro are not set"
		return 1
	fi

	printf '%s\n' "$current"
}

main() {
	local -r command="${1:-}"
	[[ -n "$command" ]] || {
		printf '%s\n' "$USAGE"
		exit 2
	}
	shift

	case "$command" in
	launch-options) cmd_launch_options "$@" ;;
	check) cmd_check "$@" ;;
	help | --help | -h) printf '%s\n' "$USAGE" ;;
	*) log_critical "Unknown command: $command" ;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
