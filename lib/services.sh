#!/usr/bin/env bash
# lib/services.sh — systemd service management (enable/start/restart)

[[ -n "${_NFSCTL_SERVICES_LOADED:-}" ]] && return 0
_NFSCTL_SERVICES_LOADED=1

source "${NFSCTL_ROOT}/lib/common.sh"

# ── Service state checks ────────────────────────────────────────────
is_service_active() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

is_service_enabled() {
    local service="$1"
    systemctl is-enabled --quiet "$service" 2>/dev/null
}

# ── Idempotent service enable ────────────────────────────────────────
ensure_service_enabled() {
    local service="$1"

    if is_service_enabled "$service"; then
        log_info "Service '$service' is already enabled."
        return 0
    fi

    if dry_run_msg "Would enable service '$service'"; then
        return 0
    fi

    log_info "Enabling service '$service'..."
    systemctl enable "$service"

    if ! is_service_enabled "$service"; then
        die "Failed to enable service '$service'"
    fi
    log_info "Service '$service' enabled."
}

# ── Idempotent service start ────────────────────────────────────────
ensure_service_running() {
    local service="$1"

    ensure_service_enabled "$service"

    if is_service_active "$service"; then
        log_info "Service '$service' is already running."
        return 0
    fi

    if dry_run_msg "Would start service '$service'"; then
        return 0
    fi

    log_info "Starting service '$service'..."
    systemctl start "$service"

    if ! is_service_active "$service"; then
        die "Failed to start service '$service'"
    fi
    log_info "Service '$service' started."
}

# ── Service restart ──────────────────────────────────────────────────
restart_service() {
    local service="$1"

    if dry_run_msg "Would restart service '$service'"; then
        return 0
    fi

    log_info "Restarting service '$service'..."
    systemctl restart "$service"

    if ! is_service_active "$service"; then
        die "Failed to restart service '$service'"
    fi
    log_info "Service '$service' restarted."
}

# ── Service stop ─────────────────────────────────────────────────────
stop_service() {
    local service="$1"

    if ! is_service_active "$service"; then
        log_info "Service '$service' is already stopped."
        return 0
    fi

    if dry_run_msg "Would stop service '$service'"; then
        return 0
    fi

    log_info "Stopping service '$service'..."
    systemctl stop "$service"
    log_info "Service '$service' stopped."
}

# ── Service disable ──────────────────────────────────────────────────
disable_service() {
    local service="$1"

    if ! is_service_enabled "$service"; then
        log_info "Service '$service' is already disabled."
        return 0
    fi

    if dry_run_msg "Would disable service '$service'"; then
        return 0
    fi

    log_info "Disabling service '$service'..."
    systemctl disable "$service"
    log_info "Service '$service' disabled."
}
