#!/usr/bin/env bash
# lib/firewall.sh — ufw/nftables NFS rule management

[[ -n "${_NFSCTL_FIREWALL_LOADED:-}" ]] && return 0
_NFSCTL_FIREWALL_LOADED=1

source "${NFSCTL_ROOT}/lib/common.sh"

# ── Firewall detection ───────────────────────────────────────────────
detect_firewall() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "ufw"
    elif command -v nft &>/dev/null && nft list ruleset 2>/dev/null | grep -q "table"; then
        echo "nftables"
    else
        echo "none"
    fi
}

# ── UFW helpers ──────────────────────────────────────────────────────
_ufw_rule_exists() {
    local port="$1"
    local proto="${2:-tcp}"
    # \b word boundary matches at line start and prevents substring false matches
    ufw status | grep -qE "\b${port}/${proto}\s+ALLOW"
}

_ufw_allow_port() {
    local port="$1"
    local proto="${2:-tcp}"
    local from="${3:-any}"

    if _ufw_rule_exists "$port" "$proto"; then
        log_info "UFW rule already exists for port ${port}/${proto}."
        return 0
    fi

    if dry_run_msg "Would add UFW rule: allow from $from to any port $port proto $proto"; then
        return 0
    fi

    if [[ "$from" == "any" ]]; then
        ufw allow "${port}/${proto}" >/dev/null
    else
        ufw allow from "$from" to any port "$port" proto "$proto" >/dev/null
    fi
    log_info "UFW rule added: allow port ${port}/${proto} from ${from}."
}

# ── nftables helpers ─────────────────────────────────────────────────
_nft_rule_exists() {
    local port="$1"
    local proto="${2:-tcp}"
    # Check both port and protocol; search our table first, then system-wide
    if nft list table inet nfsctl 2>/dev/null | grep -q "${proto} dport ${port} accept"; then
        return 0
    fi
    # Also check if rule exists in the system's filter table
    nft list table inet filter 2>/dev/null | grep -q "${proto} dport ${port} accept"
}

# Detect whether a system filter table with an input chain exists
_nft_has_system_filter() {
    nft list chain inet filter input 2>/dev/null | grep -q "type filter"
}

_nft_allow_port() {
    local port="$1"
    local proto="${2:-tcp}"

    if _nft_rule_exists "$port" "$proto"; then
        log_info "nftables rule already exists for port ${port}/${proto}."
        return 0
    fi

    if dry_run_msg "Would add nftables rule for port $port/$proto"; then
        return 0
    fi

    if _nft_has_system_filter; then
        # Insert into the existing system filter table so rules are effective
        # even when the system chain has a drop policy
        nft add rule inet filter input "$proto" dport "$port" accept \
            comment \"nfsctl\"
        log_info "nftables rule added to inet filter: allow port ${port}/${proto}."
    else
        # No system filter table — create our own
        nft add table inet nfsctl 2>/dev/null || true
        nft add chain inet nfsctl input \
            '{ type filter hook input priority 10 ; }' 2>/dev/null || true
        nft add rule inet nfsctl input "$proto" dport "$port" accept
        log_info "nftables rule added to inet nfsctl: allow port ${port}/${proto}."
    fi
}

# ── High-level: open NFS ports ───────────────────────────────────────
ensure_nfs_firewall_rules() {
    local fw
    fw=$(detect_firewall)

    case "$fw" in
        ufw)
            log_info "Configuring UFW rules for NFS..."
            _ufw_allow_port "${NFS_PORT:-2049}" "tcp"
            _ufw_allow_port "${NFS_PORT:-2049}" "udp"
            _ufw_allow_port "${RPCBIND_PORT:-111}" "tcp"
            _ufw_allow_port "${RPCBIND_PORT:-111}" "udp"
            _ufw_allow_port "${MOUNTD_PORT:-20048}" "tcp"
            _ufw_allow_port "${MOUNTD_PORT:-20048}" "udp"
            ;;
        nftables)
            log_info "Configuring nftables rules for NFS..."
            _nft_allow_port "${NFS_PORT:-2049}" "tcp"
            _nft_allow_port "${NFS_PORT:-2049}" "udp"
            _nft_allow_port "${RPCBIND_PORT:-111}" "tcp"
            _nft_allow_port "${RPCBIND_PORT:-111}" "udp"
            _nft_allow_port "${MOUNTD_PORT:-20048}" "tcp"
            _nft_allow_port "${MOUNTD_PORT:-20048}" "udp"
            ;;
        none)
            log_info "No active firewall detected. Skipping firewall configuration."
            ;;
    esac
}

# ── Remove NFS firewall rules ────────────────────────────────────────
remove_nfs_firewall_rules() {
    local fw
    fw=$(detect_firewall)

    case "$fw" in
        ufw)
            log_info "Removing UFW rules for NFS..."
            if dry_run_msg "Would remove UFW NFS rules"; then return 0; fi
            local port proto
            for port in "${NFS_PORT:-2049}" "${RPCBIND_PORT:-111}" "${MOUNTD_PORT:-20048}"; do
                for proto in tcp udp; do
                    ufw delete allow "${port}/${proto}" 2>/dev/null || true
                    # Also try removing source-scoped rules (numbered delete as fallback)
                done
            done
            log_info "UFW NFS rules removed."
            ;;
        nftables)
            log_info "Removing nftables rules for NFS..."
            if dry_run_msg "Would remove nftables NFS rules"; then return 0; fi
            # Remove rules we inserted into the system filter table (tagged with comment "nfsctl")
            local handles
            handles=$(nft -a list chain inet filter input 2>/dev/null \
                | grep 'comment "nfsctl"' \
                | sed -n 's/.*handle \([0-9]\+\)/\1/p') || true
            local h
            for h in $handles; do
                nft delete rule inet filter input handle "$h" 2>/dev/null || true
            done
            # Also remove our own table if it exists
            nft delete table inet nfsctl 2>/dev/null || true
            log_info "nftables NFS rules removed."
            ;;
        none)
            log_info "No active firewall detected."
            ;;
    esac
}
