#!/usr/bin/env bash
# tests/test_idempotency.sh — Integration tests for idempotency
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

# ── Setup ────────────────────────────────────────────────────────────
TEST_TMPDIR=$(create_test_tmpdir)
trap 'cleanup_test_tmpdir "$TEST_TMPDIR"' EXIT

export EXPORTS_FILE="${TEST_TMPDIR}/exports"
export LOCK_FILE="${TEST_TMPDIR}/nfsctl.lock"
export BACKUP_DIR="${TEST_TMPDIR}/backups"

# ── Test: repeated add is idempotent ─────────────────────────────────
describe "Idempotency: repeated add_export_entry"

add_export_entry "/srv/test" "10.0.0.0/8" "rw,sync"
local_hash1=$(md5sum "$EXPORTS_FILE" | awk '{print $1}')

add_export_entry "/srv/test" "10.0.0.0/8" "rw,sync"
local_hash2=$(md5sum "$EXPORTS_FILE" | awk '{print $1}')

assert_eq "$local_hash1" "$local_hash2" "file unchanged after duplicate add"

local_count=$(grep -c "/srv/test" "$EXPORTS_FILE" || true)
assert_eq "1" "$local_count" "exactly one entry after two adds"

# ── Test: repeated remove is idempotent ──────────────────────────────
describe "Idempotency: repeated remove_export_entry"

remove_export_entry "/srv/test" "10.0.0.0/8"
assert_file_not_contains "$EXPORTS_FILE" "/srv/test" "entry removed"

remove_export_entry "/srv/test" "10.0.0.0/8"
assert_eq 0 $? "second remove succeeds without error"

# ── Test: add-remove-add cycle ───────────────────────────────────────
describe "Idempotency: add-remove-add cycle"

add_export_entry "/srv/cycle" "192.168.0.0/16" "rw,sync"
assert_file_contains "$EXPORTS_FILE" "/srv/cycle" "added"

remove_export_entry "/srv/cycle" "192.168.0.0/16"
assert_file_not_contains "$EXPORTS_FILE" "/srv/cycle" "removed"

add_export_entry "/srv/cycle" "192.168.0.0/16" "rw,sync"
assert_file_contains "$EXPORTS_FILE" "/srv/cycle" "re-added after removal"

local_count=$(grep -c "/srv/cycle" "$EXPORTS_FILE" || true)
assert_eq "1" "$local_count" "exactly one entry after cycle"

# ── Test: options update is idempotent ───────────────────────────────
describe "Idempotency: options update"

add_export_entry "/srv/opts" "*" "rw,sync"
add_export_entry "/srv/opts" "*" "ro,sync"
assert_file_contains "$EXPORTS_FILE" "/srv/opts *(ro,sync)" "options updated"
assert_file_not_contains "$EXPORTS_FILE" "/srv/opts *(rw,sync)" "old options gone"

add_export_entry "/srv/opts" "*" "ro,sync"
local_count=$(grep -c "/srv/opts" "$EXPORTS_FILE" || true)
assert_eq "1" "$local_count" "update+repeat leaves one entry"

# ── Test: dry-run makes no changes ───────────────────────────────────
describe "Dry-run mode"

DRY_RUN=1
local_before=$(cat "$EXPORTS_FILE")
add_export_entry "/srv/dryrun" "10.0.0.0/8" "rw"
local_after=$(cat "$EXPORTS_FILE")
assert_eq "$local_before" "$local_after" "dry-run add does not modify file"
DRY_RUN=0

# ── Test: multiple clients for same path ─────────────────────────────
describe "Multiple clients per path"

add_export_entry "/srv/multi" "10.0.0.0/8" "rw,sync"
add_export_entry "/srv/multi" "172.16.0.0/12" "ro,sync"
add_export_entry "/srv/multi" "192.168.0.0/16" "rw,sync,no_root_squash"

local_count=$(grep -c "/srv/multi" "$EXPORTS_FILE" || true)
assert_eq "3" "$local_count" "three entries for three different clients"

# Repeat all three
add_export_entry "/srv/multi" "10.0.0.0/8" "rw,sync"
add_export_entry "/srv/multi" "172.16.0.0/12" "ro,sync"
add_export_entry "/srv/multi" "192.168.0.0/16" "rw,sync,no_root_squash"

local_count=$(grep -c "/srv/multi" "$EXPORTS_FILE" || true)
assert_eq "3" "$local_count" "still three entries after repeating all adds"

# ── Summary ──────────────────────────────────────────────────────────
test_summary
