#!/usr/bin/env bash
# tests/test_json.sh — Tests for JSON output, _json_escape, _parse_export_line
# Note: set -e is intentionally omitted so test assertions can detect failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export NFSCTL_ROOT="$PROJECT_ROOT"
export VERBOSE=0
export DRY_RUN=0
export YES=1

source "$SCRIPT_DIR/helpers/mock.sh"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/exports.sh"
source "$PROJECT_ROOT/commands/export-list.sh"

# ── _json_escape ─────────────────────────────────────────────────────
describe "_json_escape"

result=$(_json_escape 'hello')
assert_eq "hello" "$result" "clean string unchanged"

result=$(_json_escape 'say "hi"')
assert_eq 'say \"hi\"' "$result" "double quotes escaped"

result=$(_json_escape 'back\slash')
assert_eq 'back\\slash' "$result" "backslash escaped"

result=$(_json_escape $'line1\nline2')
# Newline should become literal \n
assert_contains "$result" '\n' "newline escaped"

result=$(_json_escape $'col1\tcol2')
assert_contains "$result" '\t' "tab escaped"

result=$(_json_escape $'end\rret')
assert_contains "$result" '\r' "carriage return escaped"

result=$(_json_escape '')
assert_eq "" "$result" "empty string unchanged"

# ── _parse_export_line ───────────────────────────────────────────────
describe "_parse_export_line (single client — managed)"

_parse_export_line "/srv/nfs 192.168.1.0/24(rw,sync,no_subtree_check) # Managed by nfsctl"
assert_eq "1" "$_parsed_count" "one client parsed"
assert_eq "/srv/nfs" "$_parsed_path_0" "path correct"
assert_eq "192.168.1.0/24" "$_parsed_client_0" "client correct"
assert_eq "rw,sync,no_subtree_check" "$_parsed_options_0" "options correct"

describe "_parse_export_line (wildcard client)"

_parse_export_line "/srv/data *(rw,sync) # Managed by nfsctl"
assert_eq "1" "$_parsed_count" "one client parsed"
assert_eq "*" "$_parsed_client_0" "wildcard client correct"
assert_eq "rw,sync" "$_parsed_options_0" "options correct"

describe "_parse_export_line (multi-client line)"

_parse_export_line "/export 10.0.0.0/8(rw,sync) 172.16.0.0/12(ro)"
assert_eq "2" "$_parsed_count" "two clients parsed"
assert_eq "/export" "$_parsed_path_0" "path for first client"
assert_eq "10.0.0.0/8" "$_parsed_client_0" "first client correct"
assert_eq "rw,sync" "$_parsed_options_0" "first options correct"
assert_eq "/export" "$_parsed_path_1" "path for second client"
assert_eq "172.16.0.0/12" "$_parsed_client_1" "second client correct"
assert_eq "ro" "$_parsed_options_1" "second options correct"

describe "_parse_export_line (unmanaged, no parens)"

_parse_export_line "/raw/line no-parens-here"
assert_eq "1" "$_parsed_count" "fallback to one entry"
assert_eq "/raw/line" "$_parsed_path_0" "path extracted"
assert_eq "(unknown)" "$_parsed_client_0" "client fallback"

# ── End-to-end cmd_export_list --json ────────────────────────────────
describe "cmd_export_list --json (end-to-end)"

TEST_TMPDIR=$(create_test_tmpdir)
trap 'cleanup_test_tmpdir "$TEST_TMPDIR"' EXIT

export EXPORTS_FILE="${TEST_TMPDIR}/exports"
export LOCK_FILE="${TEST_TMPDIR}/nfsctl.lock"
export BACKUP_DIR="${TEST_TMPDIR}/backups"

add_export_entry "/srv/nfs" "10.0.0.0/8" "rw,sync"
add_export_entry "/srv/data" "192.168.1.0/24" "ro,sync,no_subtree_check"

json_output=$(cmd_export_list --json 2>/dev/null)

assert_contains "$json_output" '"path": "/srv/nfs"' "JSON contains first path"
assert_contains "$json_output" '"client": "10.0.0.0/8"' "JSON contains first client"
assert_contains "$json_output" '"options": "rw,sync"' "JSON contains first options"
assert_contains "$json_output" '"path": "/srv/data"' "JSON contains second path"
assert_contains "$json_output" '[' "JSON opens with bracket"
assert_contains "$json_output" ']' "JSON closes with bracket"

# ── Summary ──────────────────────────────────────────────────────────
test_summary
