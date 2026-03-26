#!/usr/bin/env bash
# tests/test_exports.sh — Unit tests for exports parsing
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

# Override globals for testing
export EXPORTS_FILE="${TEST_TMPDIR}/exports"
export LOCK_FILE="${TEST_TMPDIR}/nfsctl.lock"
export BACKUP_DIR="${TEST_TMPDIR}/backups"

# ── Test: add_export_entry to empty file ─────────────────────────────
describe "add_export_entry (new file)"

add_export_entry "/srv/nfs" "192.168.1.0/24" "rw,sync,no_subtree_check"
assert_file_contains "$EXPORTS_FILE" "/srv/nfs 192.168.1.0/24(rw,sync,no_subtree_check) ${MANAGED_TAG}" \
    "export entry is written correctly"

# ── Test: add duplicate (idempotent) ─────────────────────────────────
describe "add_export_entry (idempotent — same entry)"

add_export_entry "/srv/nfs" "192.168.1.0/24" "rw,sync,no_subtree_check"
local_count=$(grep -c "/srv/nfs" "$EXPORTS_FILE" || true)
assert_eq "1" "$local_count" "duplicate add does not create second entry"

# ── Test: add different client for same path ─────────────────────────
describe "add_export_entry (different client)"

add_export_entry "/srv/nfs" "10.0.0.0/8" "rw,sync"
assert_file_contains "$EXPORTS_FILE" "/srv/nfs 10.0.0.0/8(rw,sync) ${MANAGED_TAG}" \
    "second client entry is added"
local_count=$(grep -c "/srv/nfs" "$EXPORTS_FILE" || true)
assert_eq "2" "$local_count" "two entries for same path, different clients"

# ── Test: update options for existing entry ──────────────────────────
describe "add_export_entry (update options)"

add_export_entry "/srv/nfs" "192.168.1.0/24" "ro,sync"
assert_file_contains "$EXPORTS_FILE" "/srv/nfs 192.168.1.0/24(ro,sync) ${MANAGED_TAG}" \
    "options updated in-place"
local_count=$(grep -c "192.168.1.0/24" "$EXPORTS_FILE" || true)
assert_eq "1" "$local_count" "still only one entry for that client"

# ── Test: add second path ────────────────────────────────────────────
describe "add_export_entry (second path)"

add_export_entry "/srv/data" "*" "rw,sync,no_root_squash"
assert_file_contains "$EXPORTS_FILE" "/srv/data *(rw,sync,no_root_squash) ${MANAGED_TAG}" \
    "second path added"

# ── Test: list_exports ───────────────────────────────────────────────
describe "list_exports"

local_exports=$(list_exports)
assert_contains "$local_exports" "/srv/nfs" "lists /srv/nfs"
assert_contains "$local_exports" "/srv/data" "lists /srv/data"

# ── Test: get_export_entry ───────────────────────────────────────────
describe "get_export_entry"

local_result=$(get_export_entry "/srv/nfs" "10.0.0.0/8")
assert_contains "$local_result" "10.0.0.0/8" "finds entry by path and client"

local_result=$(get_export_entry "/nonexistent" "*")
assert_eq "" "$local_result" "returns empty for nonexistent entry"

# ── Test: remove_export_entry ────────────────────────────────────────
describe "remove_export_entry"

remove_export_entry "/srv/nfs" "10.0.0.0/8"
assert_file_not_contains "$EXPORTS_FILE" "10.0.0.0/8" \
    "entry removed from file"
assert_file_contains "$EXPORTS_FILE" "/srv/nfs 192.168.1.0/24" \
    "other entry for same path preserved"

# ── Test: remove nonexistent (idempotent) ────────────────────────────
describe "remove_export_entry (idempotent — nonexistent)"

remove_export_entry "/srv/nfs" "10.0.0.0/8"
assert_eq 0 $? "removing nonexistent entry succeeds (idempotent)"

# ── Test: does not touch unmanaged lines ─────────────────────────────
describe "unmanaged lines preserved"

echo "/manual/export 10.0.0.0/8(rw)" >> "$EXPORTS_FILE"
add_export_entry "/srv/auto" "172.16.0.0/12" "rw,sync"
assert_file_contains "$EXPORTS_FILE" "/manual/export 10.0.0.0/8(rw)" \
    "unmanaged line not modified"

# ── Test: backups created ────────────────────────────────────────────
describe "backup files"

local_backup_count=$(find "$BACKUP_DIR" -name 'exports.*' 2>/dev/null | wc -l)
[[ "$local_backup_count" -gt 0 ]] && _bk_ok=0 || _bk_ok=1
assert_eq 0 "$_bk_ok" "backup files were created"

# ── Summary ──────────────────────────────────────────────────────────
test_summary
