#!/usr/bin/env bash
# ======================================================================================================================
# Manage the mods of the collection: list, enable, disable, sync, update, add and remove
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
  list                     List the mods of the collection and their current state
  info <name>              Show the details of a single mod
  enable <name>            Enable a mod (links it into the Balatro Mods folder)
  disable <name>           Disable a mod (removes it from the Balatro Mods folder)
  toggle <name>            Toggle a mod between enabled and disabled
  sync                     Apply the enabled state of the manifest to the Balatro Mods folder
  update [name...]         Update the mods from their upstream repositories
  add <name> <repo> [path] [branch] [description]
                           Add a mod as a git submodule and register it in the manifest
                           (the description takes the rest of the arguments)
  remove <name>            Remove a mod from the collection
  path <name>              Print the local path of a mod
EOF

# --- Helpers -----------------------------------------------------------------------------------------------------

usage_error() {
	log_error "$*"
	printf '%s\n' "$USAGE" >&2
	exit 2
}

require_mod_name() {
	[[ -n "${1:-}" ]] || usage_error "Missing mod name"
	manifest_exists "$1" || log_critical "Unknown mod: $1 (see '$INVOKER list')"
}

mod_link_is_ours() {
	local -r target="$1"
	[[ -L "$target" ]] || [[ -f "$target/.collection-managed" ]]
}

remove_mod_target() {
	local -r name="$1"
	local -r target="$(mod_target_dir "$name")"

	if [[ -L "$target" ]]; then
		rm -f "$target"
		return 0
	fi

	if [[ -d "$target" ]]; then
		if [[ -f "$target/.collection-managed" ]]; then
			rm -rf "$target"
			return 0
		fi
		log_warn "'$target' is not managed by the collection, leaving it untouched"
		return 1
	fi

	return 0
}

link_mod() {
	local -r name="$1"
	local -r source="$(mod_source_dir "$name")"
	local -r target="$(mod_target_dir "$name")"

	if [[ ! -d "$source" ]]; then
		log_error "Mod '$name' is not checked out at '$source' (run '$INVOKER update $name' or 'git submodule update --init')"
		return 1
	fi

	mkdir -p "$BALATRO_MODS_DIR"

	if [[ -L "$target" ]]; then
		rm -f "$target"
	elif [[ -d "$target" ]]; then
		if [[ "$MOD_LINK_MODE" == "copy" && -f "$target/.collection-managed" ]]; then
			rm -rf "$target"
		else
			log_error "'$target' already exists and is not managed by the collection"
			return 1
		fi
	fi

	if [[ "$MOD_LINK_MODE" == "copy" ]]; then
		rsync -a --delete "$source/" "$target/"
		touch "$target/.collection-managed"
		log_ok "Copied $name into $BALATRO_MODS_DIR"
	else
		ln -sfn "$source" "$target"
		log_ok "Linked $name -> $source"
	fi
}

unlink_mod() {
	local -r name="$1"

	if remove_mod_target "$name"; then
		log_ok "Disabled $name"
	else
		log_warn "Could not disable '$name' cleanly"
	fi
}

# --- Commands ----------------------------------------------------------------------------------------------------

cmd_list() {
	require_manifest
	resolve_env

	printf '%-24s %-10s %-9s %-8s %s\n' "NAME" "STATE" "COMMIT" "BRANCH" "REPO"
	printf '%s\n' "------------------------------------------------------------------------------------------------------"

	local name state commit branch repo
	while read -r name; do
		[[ -n "$name" ]] || continue
		branch="$(manifest_field "$name" "branch")"
		repo="$(manifest_field "$name" "repo")"
		commit="$(mod_local_commit "$name")"

		if mod_is_enabled "$name"; then
			if mod_is_linked "$name"; then
				state="enabled"
			else
				state="enabled!"
			fi
		else
			state="disabled"
		fi

		printf '%-24s %-10s %-9s %-8s %s\n' "$name" "$state" "$commit" "${branch:-main}" "$repo"
	done < <(manifest_names)

	local -r total="$(manifest_mod_count)"
	printf '\n%s mod(s) in the collection\n' "$total"
}

cmd_info() {
	local -r name="${1:-}"
	require_mod_name "$name"
	resolve_env

	printf 'name:        %s\n' "$name"
	printf 'repo:        %s\n' "$(manifest_field "$name" "repo")"
	printf 'branch:      %s\n' "$(manifest_field "$name" "branch")"
	printf 'path:        %s\n' "$(manifest_field "$name" "path")"
	printf 'enabled:     %s\n' "$(manifest_field "$name" "enabled")"
	printf 'description: %s\n' "$(manifest_field "$name" "description")"
	printf 'source:      %s\n' "$(mod_source_dir "$name")"
	printf 'target:      %s\n' "$(mod_target_dir "$name")"
	printf 'commit:      %s\n' "$(mod_local_commit "$name")"
}

cmd_enable() {
	local -r name="${1:-}"
	require_mod_name "$name"
	resolve_env

	manifest_set_field "$name" "enabled" "true"
	link_mod "$name"
}

cmd_disable() {
	local -r name="${1:-}"
	require_mod_name "$name"
	resolve_env

	manifest_set_field "$name" "enabled" "false"
	unlink_mod "$name"
}

cmd_toggle() {
	local -r name="${1:-}"
	require_mod_name "$name"
	resolve_env

	if mod_is_enabled "$name"; then
		cmd_disable "$name"
	else
		cmd_enable "$name"
	fi
}

cmd_sync() {
	require_manifest
	resolve_env

	mkdir -p "$BALATRO_MODS_DIR"

	local name
	while read -r name; do
		[[ -n "$name" ]] || continue
		if mod_is_enabled "$name"; then
			link_mod "$name"
		else
			remove_mod_target "$name" && log_ok "Disabled $name"
		fi
	done < <(manifest_names)

	log_info ""
	log_info "Foreign entries in $BALATRO_MODS_DIR (not managed by the collection):"
	local entry base found=false
	for entry in "$BALATRO_MODS_DIR"/*; do
		[[ -e "$entry" ]] || continue
		base="$(basename "$entry")"
		[[ "$base" == "smods" ]] && continue
		manifest_exists "$base" && continue
		log_info "  - $base"
		found=true
	done
	[[ "$found" == "false" ]] && log_info "  (none)"
}

cmd_update() {
	require_manifest
	resolve_env

	local -a selected=("$@")
	local name

	if [[ ${#selected[@]} -eq 0 ]]; then
		mapfile -t selected < <(manifest_names)
	fi

	log_step "Updating submodules"
	if [[ "${SUBMODULE_INIT_RECURSIVE:-false}" == "true" ]]; then
		git -C "$COLLECTION_ROOT" submodule update --init --recursive
	else
		git -C "$COLLECTION_ROOT" submodule update --init
	fi

	local -A updated_checkouts=()
	for name in "${selected[@]}"; do
		[[ -n "$name" ]] || continue
		manifest_exists "$name" || log_critical "Unknown mod: $name"

		local -r checkout="$(basename "$(mod_checkout_dir "$name")")"
		if [[ -n "${updated_checkouts[$checkout]:-}" ]]; then
			continue
		fi
		updated_checkouts[$checkout]=1

		log_step "Updating $name ($checkout)"
		git -C "$COLLECTION_ROOT" submodule update --remote --checkout -- "mods/$checkout"
		git -C "$COLLECTION_ROOT" config "submodule.mods/$checkout.ignore" untracked
	done

	cmd_sync
}

cmd_add() {
	local -r name="${1:-}"
	local -r repo="${2:-}"
	local -r path="${3:-.}"
	local -r branch="${4:-}"
	local -r description="${*:5}"

	[[ -n "$name" ]] || usage_error "Missing mod name"
	[[ -n "$repo" ]] || usage_error "Missing repository url"
	require_manifest

	manifest_exists "$name" && log_critical "The mod '$name' already exists in the collection"

	# Reuse the checkout of a mod that already comes from the same repository
	local -r existing_checkout="$(jq -r --arg r "$repo" '.mods[] | select(.repo == $r) | .checkout // .name' "$MANIFEST_FILE" | head -n 1)"
	local -r checkout="${existing_checkout:-$name}"

	if [[ -z "$existing_checkout" ]]; then
		if [[ -e "$COLLECTION_MODS_DIR/$checkout" ]]; then
			log_critical "'$COLLECTION_MODS_DIR/$checkout' already exists"
		fi

		log_step "Adding $name from $repo"
		if [[ -n "$branch" ]]; then
			git -C "$COLLECTION_ROOT" submodule add --force -b "$branch" "$repo" "mods/$checkout"
		else
			git -C "$COLLECTION_ROOT" submodule add --force "$repo" "mods/$checkout"
		fi
	else
		log_step "Reusing the checkout 'mods/$checkout' for $name"
	fi

	manifest_add_mod "$name" "$repo" "$path" "$branch" "true" "$description" "$checkout"
	git -C "$COLLECTION_ROOT" config "submodule.mods/$checkout.ignore" untracked

	resolve_env
	link_mod "$name"

	log_ok "Added $name"
	log_info "Remember to commit the changes (.gitmodules, config/mods.json and the submodule pointer)"
}

cmd_remove() {
	local -r name="${1:-}"
	require_mod_name "$name"
	resolve_env

	log_step "Removing $name"
	remove_mod_target "$name" || true

	local -r checkout="$(basename "$(mod_checkout_dir "$name")")"
	local -r still_used="$(jq -r --arg c "$checkout" --arg n "$name" \
		'[.mods[] | select((.checkout // .name) == $c) | select(.name != $n)] | length' "$MANIFEST_FILE")"

	if [[ "$still_used" == "0" ]]; then
		git -C "$COLLECTION_ROOT" submodule deinit -f -- "mods/$checkout" 2> /dev/null || true
		if git -C "$COLLECTION_ROOT" ls-files --error-unmatch "mods/$checkout" &> /dev/null; then
			git -C "$COLLECTION_ROOT" rm -f -- "mods/$checkout"
		else
			rm -rf "${COLLECTION_ROOT:?}/mods/$checkout"
		fi
	else
		log_info "The checkout 'mods/$checkout' is still used by other mods, keeping it"
	fi

	manifest_remove_mod "$name"

	log_ok "Removed $name"
}

cmd_path() {
	local -r name="${1:-}"
	require_mod_name "$name"
	printf '%s\n' "$(mod_source_dir "$name")"
}

main() {
	local -r command="${1:-}"
	[[ -n "$command" ]] || {
		printf '%s\n' "$USAGE"
		exit 2
	}
	shift

	case "$command" in
	list) cmd_list "$@" ;;
	info) cmd_info "$@" ;;
	enable) cmd_enable "$@" ;;
	disable) cmd_disable "$@" ;;
	toggle) cmd_toggle "$@" ;;
	sync) cmd_sync "$@" ;;
	update) cmd_update "$@" ;;
	add) cmd_add "$@" ;;
	remove) cmd_remove "$@" ;;
	path) cmd_path "$@" ;;
	help | --help | -h) printf '%s\n' "$USAGE" ;;
	*) log_critical "Unknown command: $command" ;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
