#!/usr/bin/env bash
# tests/test_validation.sh — Unit tests for validators
# Note: set -e is intentionally omitted so test assertions can detect failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export NFSCTL_ROOT="$PROJECT_ROOT"
export VERBOSE=0
export DRY_RUN=0
export YES=1

source "$SCRIPT_DIR/helpers/mock.sh"
source "$PROJECT_ROOT/lib/validation.sh"

# ── IP validation ────────────────────────────────────────────────────
describe "validate_ip"

validate_ip "192.168.1.1"
assert_eq 0 $? "valid IP 192.168.1.1"

validate_ip "10.0.0.0"
assert_eq 0 $? "valid IP 10.0.0.0"

validate_ip "0.0.0.0"
assert_eq 0 $? "valid IP 0.0.0.0"

validate_ip "255.255.255.255"
assert_eq 0 $? "valid IP 255.255.255.255"

(validate_ip "256.1.1.1") && r=0 || r=$?
assert_fail "$r" "invalid IP 256.1.1.1"

(validate_ip "1.2.3") && r=0 || r=$?
assert_fail "$r" "invalid IP 1.2.3 (missing octet)"

(validate_ip "abc.def.ghi.jkl") && r=0 || r=$?
assert_fail "$r" "invalid IP abc.def.ghi.jkl"

(validate_ip "") && r=0 || r=$?
assert_fail "$r" "empty string is invalid"

(validate_ip "192.168.01.1") && r=0 || r=$?
assert_fail "$r" "leading zero in octet (01)"

(validate_ip "10.0.0.08") && r=0 || r=$?
assert_fail "$r" "leading zero in octet (08, invalid octal)"

(validate_ip "1.2.3.4.") && r=0 || r=$?
assert_fail "$r" "trailing dot IP"

# ── CIDR validation ──────────────────────────────────────────────────
describe "validate_cidr"

validate_cidr "10.0.0.0/8"
assert_eq 0 $? "valid CIDR 10.0.0.0/8"

validate_cidr "192.168.1.0/24"
assert_eq 0 $? "valid CIDR 192.168.1.0/24"

validate_cidr "0.0.0.0/0"
assert_eq 0 $? "valid CIDR 0.0.0.0/0"

(validate_cidr "10.0.0.0/33") && r=0 || r=$?
assert_fail "$r" "invalid CIDR prefix /33"

(validate_cidr "10.0.0.0") && r=0 || r=$?
assert_fail "$r" "missing CIDR prefix"

(validate_cidr "300.0.0.0/8") && r=0 || r=$?
assert_fail "$r" "invalid IP in CIDR"

# ── Hostname validation ──────────────────────────────────────────────
describe "validate_hostname"

validate_hostname "server1"
assert_eq 0 $? "valid hostname server1"

validate_hostname "my-server.example.com"
assert_eq 0 $? "valid hostname my-server.example.com"

validate_hostname "a"
assert_eq 0 $? "single char hostname"

(validate_hostname "-bad") && r=0 || r=$?
assert_fail "$r" "hostname starting with hyphen"

(validate_hostname "") && r=0 || r=$?
assert_fail "$r" "empty hostname"

(validate_hostname "bad-.host") && r=0 || r=$?
assert_fail "$r" "label ending with hyphen"

(validate_hostname "example.com.") && r=0 || r=$?
assert_fail "$r" "hostname with trailing dot"

# ── NFS client validation ────────────────────────────────────────────
describe "validate_nfs_client"

validate_nfs_client "*"
assert_eq 0 $? "wildcard client *"

validate_nfs_client "192.168.1.100"
assert_eq 0 $? "IP client"

validate_nfs_client "10.0.0.0/24"
assert_eq 0 $? "CIDR client"

validate_nfs_client "*.example.com"
assert_eq 0 $? "wildcard domain client"

validate_nfs_client "server1.local"
assert_eq 0 $? "hostname client"

validate_nfs_client "@netgroup1"
assert_eq 0 $? "netgroup client"

(validate_nfs_client "") && r=0 || r=$?
assert_fail "$r" "empty client"

(validate_nfs_client "300.1.1.1") && r=0 || r=$?
assert_fail "$r" "invalid IP client"

(validate_nfs_client "1.2.3.4.") && r=0 || r=$?
assert_fail "$r" "trailing-dot IP client"

(validate_nfs_client "10.0") && r=0 || r=$?
assert_fail "$r" "truncated IP 10.0"

(validate_nfs_client "192.168.1") && r=0 || r=$?
assert_fail "$r" "truncated IP 192.168.1"

# ── Export path validation ───────────────────────────────────────────
describe "validate_export_path"

validate_export_path "/srv/nfs"
assert_eq 0 $? "valid path /srv/nfs"

validate_export_path "/"
assert_eq 0 $? "root path"

validate_export_path "/srv/nfs/data-1"
assert_eq 0 $? "path with hyphen"

(validate_export_path "relative/path") && r=0 || r=$?
assert_fail "$r" "relative path"

(validate_export_path "/path//double") && r=0 || r=$?
assert_fail "$r" "double slash in path"

(validate_export_path "/trail/") && r=0 || r=$?
assert_fail "$r" "trailing slash"

(validate_export_path "") && r=0 || r=$?
assert_fail "$r" "empty path"

(validate_export_path "/path with spaces") && r=0 || r=$?
assert_fail "$r" "path with spaces"

# ── Export options validation ────────────────────────────────────────
describe "validate_export_options"

validate_export_options "rw,sync,no_subtree_check"
assert_eq 0 $? "valid standard options"

validate_export_options "ro"
assert_eq 0 $? "single option"

validate_export_options "rw,sync,no_root_squash,anonuid=1000"
assert_eq 0 $? "options with key=value"

(validate_export_options "rw,invalid_option") && r=0 || r=$?
assert_fail "$r" "invalid option"

(validate_export_options "") && r=0 || r=$?
assert_fail "$r" "empty options"

(validate_export_options "rw,sync,") && r=0 || r=$?
assert_fail "$r" "trailing comma"

(validate_export_options ",rw") && r=0 || r=$?
assert_fail "$r" "leading comma"

(validate_export_options "rw,,sync") && r=0 || r=$?
assert_fail "$r" "double comma"

# ── Summary ──────────────────────────────────────────────────────────
test_summary
