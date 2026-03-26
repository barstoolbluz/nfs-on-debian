#!/usr/bin/env bash
# lib/common.sh — Logging, error handling, locking, root check, config

set -euo pipefail

# Guard against double-sourcing
[[ -n "${_NFSCTL_COMMON_LOADED:-}" ]] && return 0
_NFSCTL_COMMON_LOADED=1

# ── Globals ──────────────────────────────────────────────────────────
NFSCTL_ROOT="${NFSCTL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERBOSE="${VERBOSE:-0}"
DRY_RUN="${DRY_RUN:-0}"
YES="${YES:-0}"

# ── Config loading ───────────────────────────────────────────────────
load_config() {
    local system_conf="/etc/nfsctl/defaults.conf"
    local project_conf="${NFSCTL_ROOT}/conf/defaults.conf"

    # Load project defaults first, then system overrides
    if [[ -f "$project_conf" ]]; then
        # shellcheck source=../conf/defaults.conf
        source "$project_conf"
    fi
    if [[ -f "$system_conf" ]]; then
        source "$system_conf"
    fi
}

load_config

# ── Logging ──────────────────────────────────────────────────────────
_log() {
    local level="$1"; shift
    local color=""
    local reset="\033[0m"
    case "$level" in
        INFO)  color="\033[0;32m" ;;  # green
        WARN)  color="\033[0;33m" ;;  # yellow
        ERROR) color="\033[0;31m" ;;  # red
        DEBUG) color="\033[0;36m" ;;  # cyan
    esac
    if [[ -t 2 ]]; then
        printf "${color}[%s]${reset} %s\n" "$level" "$*" >&2
    else
        printf "[%s] %s\n" "$level" "$*" >&2
    fi
}

log_info()  { _log INFO "$@"; }
log_warn()  { _log WARN "$@"; }
log_error() { _log ERROR "$@"; }
log_debug() { (( VERBOSE )) && _log DEBUG "$@"; return 0; }

die() {
    log_error "$@"
    exit 1
}

# ── Root check ───────────────────────────────────────────────────────
# Call this BEFORE parsing flags. It re-execs the entire original command line.
# The original argv must be saved in _NFSCTL_ORIG_ARGS by the dispatcher.
# Note: sudo -E is best-effort; if sudoers has env_reset (the default),
# env vars like VERBOSE/DRY_RUN may be dropped. The CLI flags in
# _NFSCTL_ORIG_ARGS are re-parsed on re-exec, so --verbose/--dry-run/--yes
# are preserved regardless.
require_root() {
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            log_info "Elevating to root via sudo..."
            exec sudo -E "$0" "${_NFSCTL_ORIG_ARGS[@]}"
        else
            die "This command must be run as root."
        fi
    fi
}

# ── Locking ──────────────────────────────────────────────────────────
_LOCK_FD=""

acquire_lock() {
    local lockfile="${LOCK_FILE:-/var/lock/nfsctl.lock}"
    # Remove stale lock file if it exists but can't be opened (e.g., wrong ownership)
    if [[ -f "$lockfile" ]] && ! bash -c "exec 200>\"$lockfile\"" 2>/dev/null; then
        rm -f "$lockfile" 2>/dev/null || true
    fi
    exec 200>"$lockfile"
    _LOCK_FD=200
    if ! flock -n 200; then
        die "Another nfsctl process is running (lock: $lockfile)"
    fi
    log_debug "Acquired lock: $lockfile"
}

release_lock() {
    if [[ -n "$_LOCK_FD" ]]; then
        flock -u "$_LOCK_FD" 2>/dev/null || true
        _LOCK_FD=""
        log_debug "Released lock"
    fi
}

# ── Backup ───────────────────────────────────────────────────────────
backup_file() {
    local file="$1"
    local backup_dir="${BACKUP_DIR:-/var/backups/nfsctl}"

    [[ -f "$file" ]] || return 0

    mkdir -p "$backup_dir"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S_%N)
    local basename
    basename=$(basename "$file")
    local dest="${backup_dir}/${basename}.${timestamp}"
    cp -a "$file" "$dest"
    log_debug "Backed up $file → $dest"
}

# ── Flag parsing helper ───────────────────────────────────────────────
# Require that a flag has a value argument following it
require_flag_value() {
    local flag="$1"
    local remaining="$2"
    if (( remaining < 2 )); then
        die "Flag '$flag' requires a value."
    fi
}

# ── Dry-run helper ───────────────────────────────────────────────────
is_dry_run() {
    (( DRY_RUN ))
}

dry_run_msg() {
    if is_dry_run; then
        log_info "[dry-run] $*"
        return 0
    fi
    return 1
}
