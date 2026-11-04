#!/usr/bin/env bash
# ======================================================================================================================
# Show the logs written by the Balatro modding stack (Lovely and Steamodded)
# ======================================================================================================================

set -euo pipefail

INVOKER="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_ROOT="${COLLECTION_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FOLLOW=false
LINES=100
EXPLICIT=""

read -r -d '' USAGE << EOF || true
Usage: $INVOKER [--follow] [--lines <n>] [file]

Shows the most recent log file of the modding stack. With --follow the file is tailed.
EOF

log_candidates() {
	local dir
	for dir in "$BALATRO_MODS_DIR/lovely/logs" "$BALATRO_MODS_DIR/logs" "$BALATRO_MODS_DIR/smods/logs" \
		"$BALATRO_SAVE_DIR/logs" "$BALATRO_GAME_DIR/logs"; do
		[[ -d "$dir" ]] || continue
		find "$dir" -maxdepth 2 -type f \( -name "*.log" -o -name "log*.txt" -o -name "lovely*.txt" \) 2> /dev/null
	done
}

main() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-f | --follow)
			FOLLOW=true
			shift
			;;
		-n | --lines)
			LINES="${2:-100}"
			shift 2
			;;
		-h | --help)
			printf '%s\n' "$USAGE"
			return 0
			;;
		*)
			EXPLICIT="$1"
			shift
			;;
		esac
	done

	resolve_env

	local log_file
	if [[ -n "$EXPLICIT" ]]; then
		[[ -f "$EXPLICIT" ]] || log_critical "File not found: $EXPLICIT"
		log_file="$EXPLICIT"
	else
		log_file="$(log_candidates | xargs -r ls -1t 2> /dev/null | head -n 1)"
		[[ -n "$log_file" ]] || log_critical "No log files found, launch the game first"
	fi

	log_info "==> $log_file"
	if [[ "$FOLLOW" == "true" ]]; then
		tail -n "$LINES" -f "$log_file"
	else
		tail -n "$LINES" "$log_file"
	fi
}

main "$@"
