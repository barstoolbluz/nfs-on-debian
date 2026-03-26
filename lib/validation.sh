#!/usr/bin/env bash
# lib/validation.sh — IP, CIDR, hostname, path, NFS option validators

[[ -n "${_NFSCTL_VALIDATION_LOADED:-}" ]] && return 0
_NFSCTL_VALIDATION_LOADED=1

# ── IP address validation ────────────────────────────────────────────
validate_ip() {
    local ip="$1"
    # Reject trailing dot (read would silently drop the empty field)
    [[ "$ip" =~ \.$ ]] && return 1
    local IFS='.'
    local -a octets
    read -ra octets <<< "$ip"

    [[ ${#octets[@]} -eq 4 ]] || return 1

    local octet
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        # Reject leading zeros (octal ambiguity)
        [[ "$octet" =~ ^0[0-9]+$ ]] && return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done
    return 0
}

# ── CIDR validation ──────────────────────────────────────────────────
validate_cidr() {
    local cidr="$1"
    [[ "$cidr" =~ ^([0-9.]+)/([0-9]+)$ ]] || return 1

    local ip="${BASH_REMATCH[1]}"
    local prefix="${BASH_REMATCH[2]}"

    validate_ip "$ip" || return 1
    (( prefix >= 0 && prefix <= 32 )) || return 1
    return 0
}

# ── Hostname validation (RFC 1123) ───────────────────────────────────
validate_hostname() {
    local host="$1"
    [[ -z "$host" ]] && return 1

    # Reject trailing dot to avoid IP-like strings falling through
    [[ "$host" =~ \.$ ]] && return 1

    # Max 253 chars
    (( ${#host} <= 253 )) || return 1

    # Each label: alphanumeric + hyphens, 1-63 chars, no leading/trailing hyphen
    local IFS='.'
    local -a labels
    read -ra labels <<< "$host"

    local label
    for label in "${labels[@]}"; do
        [[ "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || return 1
    done
    return 0
}

# ── NFS client specifier validation ──────────────────────────────────
# Accepts: IP, CIDR, hostname, wildcard (*), *.domain.com, @netgroup
validate_nfs_client() {
    local client="$1"
    [[ -z "$client" ]] && return 1

    # Wildcard
    [[ "$client" == "*" ]] && return 0

    # Wildcard domain (*.example.com)
    if [[ "$client" =~ ^\*\..+$ ]]; then
        validate_hostname "${client#\*.}" && return 0
    fi

    # CIDR
    if [[ "$client" == */* ]]; then
        validate_cidr "$client" && return 0
        return 1
    fi

    # IP address
    if [[ "$client" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        validate_ip "$client" && return 0
        return 1
    fi

    # Netgroup
    [[ "$client" =~ ^@[a-zA-Z0-9_-]+$ ]] && return 0

    # Reject all-numeric dotted strings (likely truncated IPs, e.g., 10.0, 192.168.1)
    [[ "$client" =~ ^[0-9]+(\.[0-9]+)*$ ]] && return 1

    # Hostname
    validate_hostname "$client" && return 0

    return 1
}

# ── Export path validation ───────────────────────────────────────────
validate_export_path() {
    local path="$1"
    [[ -z "$path" ]] && return 1

    # Must be absolute
    [[ "$path" == /* ]] || return 1

    # No double slashes, no trailing slash (except root)
    [[ "$path" =~ // ]] && return 1
    [[ "$path" != "/" && "$path" == */ ]] && return 1

    # Only safe characters
    [[ "$path" =~ ^[a-zA-Z0-9/_.-]+$ ]] || return 1

    return 0
}

# ── NFS export options validation ────────────────────────────────────
validate_export_options() {
    local options="$1"
    [[ -z "$options" ]] && return 1

    # Reject malformed separators
    [[ "$options" =~ ,$ ]] && return 1
    [[ "$options" =~ ^, ]] && return 1
    [[ "$options" =~ ,, ]] && return 1

    local known_options="rw ro sync async no_subtree_check subtree_check"
    known_options+=" no_root_squash root_squash all_squash no_all_squash"
    known_options+=" insecure secure wdelay no_wdelay crossmnt"
    known_options+=" anonuid anongid fsid sec"
    known_options+=" nohide hide mp mountpoint pnfs no_pnfs security_label"
    known_options+=" nordirplus no_acl"

    local -a opts
    IFS=',' read -ra opts <<< "$options"

    local opt
    for opt in "${opts[@]}"; do
        # Strip value for key=value options (e.g., anonuid=1000)
        local key="${opt%%=*}"
        local found=0
        local known
        for known in $known_options; do
            if [[ "$key" == "$known" ]]; then
                found=1
                break
            fi
        done
        if (( ! found )); then
            return 1
        fi
    done
    return 0
}
