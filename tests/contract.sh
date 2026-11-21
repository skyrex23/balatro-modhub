#!/usr/bin/env bash
# ======================================================================================================================
# Contract tests of the structured output of the scripts
# ======================================================================================================================

set -euo pipefail

INVOKER="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

TESTS=0
FAILURES=0
STATUS=0
FIXTURE_ROOT=""
TMP_DIR=""

cleanup() {
	if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

trap cleanup EXIT

# --- Helpers -----------------------------------------------------------------------------------------------------

assert_json() {
	local -r description="$1"
	local -r file="$2"
	local -r filter="$3"
	local -r expected="$4"

	local actual
	actual="$(jq -r "$filter" "$file" 2> /dev/null || printf '<invalid json>')"

	TESTS=$((TESTS + 1))
	if [[ "$actual" == "$expected" ]]; then
		printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$description"
	else
		printf '  %sx%s %s (expected %s, got %s)\n' "$C_ERR" "$C_RESET" "$description" "$expected" "$actual"
		FAILURES=$((FAILURES + 1))
	fi
}

assert_equal() {
	local -r description="$1"
	local -r expected="$2"
	local -r actual="$3"

	TESTS=$((TESTS + 1))
	if [[ "$actual" == "$expected" ]]; then
		printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$description"
	else
		printf '  %sx%s %s (expected %s, got %s)\n' "$C_ERR" "$C_RESET" "$description" "$expected" "$actual"
		FAILURES=$((FAILURES + 1))
	fi
}

run_script() {
	local -r script="$1"
	local -r output="$2"
	shift 2

	STATUS=0
	env COLLECTION_ROOT="$FIXTURE_ROOT" STEAM_CONFIG_FILE="$TMP_DIR/localconfig.vdf" \
		bash "$REPO_ROOT/scripts/$script" "$@" > "$output" 2> "$TMP_DIR/stderr.log" || STATUS=$?
}

# --- Fixture -----------------------------------------------------------------------------------------------------

setup_fixture() {
	TMP_DIR="$(mktemp -d)"
	FIXTURE_ROOT="$TMP_DIR/collection"

	mkdir -p "$FIXTURE_ROOT/config" \
		"$FIXTURE_ROOT/mods/shared-checkout/alpha" \
		"$FIXTURE_ROOT/mods/shared-checkout/beta" \
		"$TMP_DIR/game" \
		"$TMP_DIR/save/Mods"

	cat > "$FIXTURE_ROOT/config/balatro.env" << EOF
BALATRO_APP_ID="2379780"
STEAM_LAUNCH_OPTIONS='WINEDLLOVERRIDES="winmm=n,b" %command%'
BALATRO_GAME_DIR="$TMP_DIR/game"
BALATRO_SAVE_DIR="$TMP_DIR/save"
MOD_LINK_MODE="symlink"
SUBMODULE_INIT_RECURSIVE="false"
EOF

	cat > "$FIXTURE_ROOT/config/mods.json" << EOF
{
  "mods": [
    {
      "name": "alpha",
      "repo": "https://example.com/mods",
      "checkout": "shared-checkout",
      "path": "alpha",
      "branch": "main",
      "enabled": true,
      "description": "The first mod"
    },
    {
      "name": "beta",
      "repo": "https://example.com/mods",
      "checkout": "shared-checkout",
      "path": "beta",
      "branch": "main",
      "enabled": false,
      "description": "The second mod"
    }
  ]
}
EOF

	cat > "$TMP_DIR/localconfig.vdf" << EOF
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"2379780"
					{
						"LastPlayed"		"0"
					}
				}
			}
		}
	}
}
EOF
}

# --- Tests -------------------------------------------------------------------------------------------------------

test_list_json() {
	local -r out="$TMP_DIR/list.json"

	run_script mods.sh "$out" list --json

	assert_json "list returns ok" "$out" ".ok" "true"
	assert_json "list returns the number of mods" "$out" ".total" "2"
	assert_json "list returns the names" "$out" "[.mods[].name] | join(\",\")" "alpha,beta"
	assert_json "list returns the state of every mod" "$out" "[.mods[].state] | join(\",\")" "diverged,disabled"
	assert_json "list returns the checkout of every mod" "$out" "[.mods[].checkout] | join(\",\")" "shared-checkout,shared-checkout"
	assert_json "list returns the mods folder" "$out" ".mods_dir" "$TMP_DIR/save/Mods"
	assert_json "list reports the enabled flag of the manifest" "$out" "[.mods[].enabled] | join(\",\")" "true,false"
	assert_json "list reports the description of every mod" "$out" "[.mods[].description] | join(\",\")" "The first mod,The second mod"
	assert_equal "list exits with 0" "0" "$STATUS"
}

test_status_json() {
	local -r out="$TMP_DIR/status.json"

	run_script mods.sh "$out" status --json

	assert_json "status returns ok" "$out" ".ok" "true"
	assert_json "status counts the mods" "$out" ".total" "2"
	assert_json "status counts the diverged mods" "$out" ".diverged" "1"
	assert_json "status counts the disabled mods" "$out" ".disabled" "1"
	assert_json "status counts the enabled mods" "$out" ".enabled" "0"
	assert_json "status counts the orphan mods" "$out" ".orphan" "0"
}

test_info_json() {
	local -r out="$TMP_DIR/info.json"

	run_script mods.sh "$out" info alpha --json

	assert_json "info returns ok" "$out" ".ok" "true"
	assert_json "info returns the mod" "$out" ".mod.name" "alpha"
	assert_json "info returns the mods that share the checkout" "$out" ".shared_checkout_with | join(\",\")" "beta"
}

test_mutations_json() {
	local -r out="$TMP_DIR/mutation.json"

	run_script mods.sh "$out" enable alpha --json
	assert_json "enable returns ok" "$out" ".ok" "true"
	assert_json "enable returns the new state" "$out" ".mod.state" "enabled"
	assert_json "enable reports the link" "$out" ".mod.linked" "true"
	assert_equal "enable creates the link" "yes" "$([[ -L "$TMP_DIR/save/Mods/alpha" ]] && echo yes || echo no)"

	run_script mods.sh "$out" disable alpha --json
	assert_json "disable returns ok" "$out" ".ok" "true"
	assert_json "disable returns the new state" "$out" ".mod.state" "disabled"
	assert_equal "disable removes the link" "no" "$([[ -L "$TMP_DIR/save/Mods/alpha" ]] && echo yes || echo no)"

	run_script mods.sh "$out" toggle alpha --json
	assert_json "toggle returns ok" "$out" ".ok" "true"
	assert_json "toggle returns the new state" "$out" ".mod.state" "enabled"
}

test_sync_json() {
	local -r out="$TMP_DIR/sync.json"

	mkdir -p "$TMP_DIR/save/Mods/hand-installed"
	run_script mods.sh "$out" sync --json

	assert_json "sync returns ok" "$out" ".ok" "true"
	assert_json "sync lists the foreign entries" "$out" ".foreign | join(\",\")" "hand-installed"
	assert_json "sync returns the state of every mod" "$out" "[.mods[].state] | join(\",\")" "enabled,disabled"
}

test_doctor_json() {
	local -r out="$TMP_DIR/doctor.json"

	run_script doctor.sh "$out" --json

	assert_json "doctor returns ok" "$out" ".ok" "true"
	assert_json "doctor returns the checks" "$out" ".checks | length > 0" "true"
	assert_json "doctor checks the dependencies" "$out" "[.checks[].id] | index(\"dep.git\") != null" "true"
	assert_json "doctor checks the paths" "$out" "[.checks[].id] | index(\"path.save_dir\") != null" "true"
	assert_json "doctor checks the modding stack" "$out" "[.checks[].id] | index(\"stack.lovely\") != null" "true"
	assert_json "doctor checks the collection" "$out" "[.checks[].id] | index(\"collection.manifest\") != null" "true"
	assert_json "doctor groups the checks" "$out" "[.checks[].group] | index(\"Dependencies\") != null" "true"
	assert_json "doctor offers a fix for the loader" "$out" "[.checks[] | select(.id == \"stack.lovely\")][0].fix.command" "bash scripts/loader.sh install"
	assert_json "doctor offers a fix for the launch options" "$out" "[.checks[] | select(.id == \"steam.launch_options\")][0].fix.command" "bash scripts/steam.sh launch-options --force"
	assert_json "doctor has no fix for the manifest" "$out" "[.checks[] | select(.id == \"collection.manifest\")][0].fix" "null"
}

test_loader_json() {
	local -r out="$TMP_DIR/loader.json"

	run_script loader.sh "$out" status --json

	assert_json "loader returns ok" "$out" ".ok" "true"
	assert_json "loader returns the game folder" "$out" ".game_dir" "$TMP_DIR/game"
	assert_json "loader returns the save folder" "$out" ".save_dir" "$TMP_DIR/save"
	assert_json "loader reports the missing injector" "$out" ".lovely" ""
}

test_errors_json() {
	local -r out="$TMP_DIR/error.json"

	run_script mods.sh "$out" info unknown --json

	assert_equal "an unknown mod exits with 1" "1" "$STATUS"
	assert_json "an unknown mod returns the error" "$out" ".ok" "false"
	assert_json "an unknown mod explains the error" "$out" ".error | length > 0" "true"
}

test_doctor_with_failures() {
	local -r out="$TMP_DIR/doctor_failed.json"
	local -r config="$FIXTURE_ROOT/config/balatro.env"
	local -r backup="$TMP_DIR/balatro.env.backup"

	cp "$config" "$backup"
	cat > "$config" << EOF
BALATRO_APP_ID="2379780"
STEAM_LAUNCH_OPTIONS='WINEDLLOVERRIDES="winmm=n,b" %command%'
BALATRO_GAME_DIR="$TMP_DIR/missing-game"
BALATRO_SAVE_DIR="$TMP_DIR/missing-save"
MOD_LINK_MODE="symlink"
EOF

	run_script doctor.sh "$out" --json

	assert_equal "a broken environment exits with 1" "1" "$STATUS"
	assert_json "a broken environment is not ok" "$out" ".ok" "false"
	assert_json "a broken environment counts the failures" "$out" ".failures > 0" "true"
	assert_json "a broken environment still returns the checks" "$out" ".checks | length > 0" "true"
	assert_json "the missing game folder is a failure" "$out" \
		"[.checks[] | select(.id == \"path.game_dir\")][0].status" "fail"

	cp "$backup" "$config"
}

main() {
	# shellcheck source=lib/common.sh
	source "$REPO_ROOT/scripts/lib/common.sh"

	setup_fixture

	printf '%sStructured output contract%s\n\n' "$C_INFO" "$C_RESET"

	printf '%smods.sh list%s\n' "$C_INFO" "$C_RESET"
	test_list_json

	printf '\n%smods.sh status%s\n' "$C_INFO" "$C_RESET"
	test_status_json

	printf '\n%smods.sh info%s\n' "$C_INFO" "$C_RESET"
	test_info_json

	printf '\n%smods.sh enable / disable / toggle%s\n' "$C_INFO" "$C_RESET"
	test_mutations_json

	printf '\n%smods.sh sync%s\n' "$C_INFO" "$C_RESET"
	test_sync_json

	printf '\n%sdoctor.sh%s\n' "$C_INFO" "$C_RESET"
	test_doctor_json

	printf '\n%sloader.sh status%s\n' "$C_INFO" "$C_RESET"
	test_loader_json

	printf '\n%sErrors%s\n' "$C_INFO" "$C_RESET"
	test_errors_json

	printf '\n%sdoctor.sh with failures%s\n' "$C_INFO" "$C_RESET"
	test_doctor_with_failures

	printf '\n'
	if [[ "$FAILURES" -gt 0 ]]; then
		log_critical "$FAILURES of $TESTS test(s) failed"
	fi

	log_ok "$TESTS test(s) passed"
}

main "$@"
