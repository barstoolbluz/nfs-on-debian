#!/usr/bin/env bash
# lib/packages.sh — Idempotent apt package management

[[ -n "${_NFSCTL_PACKAGES_LOADED:-}" ]] && return 0
_NFSCTL_PACKAGES_LOADED=1

source "${NFSCTL_ROOT}/lib/common.sh"

# ── Check if package is installed ────────────────────────────────────
is_package_installed() {
    local pkg="$1"
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

# ── Idempotent package install ───────────────────────────────────────
ensure_package_installed() {
    local pkg="$1"

    if is_package_installed "$pkg"; then
        log_info "Package '$pkg' is already installed."
        return 0
    fi

    if dry_run_msg "Would install package '$pkg'"; then
        return 0
    fi

    log_info "Installing package '$pkg'..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"

    if ! is_package_installed "$pkg"; then
        die "Failed to install package '$pkg'"
    fi

    log_info "Package '$pkg' installed successfully."
}

# ── Install multiple packages ────────────────────────────────────────
ensure_packages_installed() {
    local -a packages=("$@")
    local pkg
    local -a to_install=()

    for pkg in "${packages[@]}"; do
        if ! is_package_installed "$pkg"; then
            to_install+=("$pkg")
        else
            log_info "Package '$pkg' is already installed."
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_info "All requested packages are already installed."
        return 0
    fi

    if dry_run_msg "Would install packages: ${to_install[*]}"; then
        return 0
    fi

    log_info "Installing packages: ${to_install[*]}..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${to_install[@]}"

    for pkg in "${to_install[@]}"; do
        if ! is_package_installed "$pkg"; then
            die "Failed to install package '$pkg'"
        fi
    done

    log_info "All packages installed successfully."
}
