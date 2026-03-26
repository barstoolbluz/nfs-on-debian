#!/usr/bin/env bash
# commands/status.sh — Show NFS server status overview

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/packages.sh"
source "${NFSCTL_ROOT}/lib/services.sh"
source "${NFSCTL_ROOT}/lib/exports.sh"
source "${NFSCTL_ROOT}/lib/firewall.sh"

cmd_status() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "Usage: nfsctl status"
                echo "  Shows comprehensive NFS server status overview"
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    if [[ $EUID -ne 0 ]]; then
        log_warn "Running without root — some information may be incomplete."
    fi

    echo "============================================"
    echo "          NFS Server Status"
    echo "============================================"
    echo ""

    # ── Packages ─────────────────────────────────────────────────────
    echo "Packages:"
    local pkg
    for pkg in $NFS_SERVER_PACKAGES; do
        if is_package_installed "$pkg"; then
            printf "  %-30s %s\n" "$pkg" "[installed]"
        else
            printf "  %-30s %s\n" "$pkg" "[not installed]"
        fi
    done
    echo ""

    # ── Services ─────────────────────────────────────────────────────
    echo "Services:"
    local service
    for service in nfs-kernel-server nfs-common rpcbind; do
        local active_str enabled_str
        if is_service_active "$service" 2>/dev/null; then
            active_str="active"
        else
            active_str="inactive"
        fi
        if is_service_enabled "$service" 2>/dev/null; then
            enabled_str="enabled"
        else
            enabled_str="disabled"
        fi
        printf "  %-30s %s, %s\n" "$service" "$active_str" "$enabled_str"
    done
    echo ""

    # ── Exports ──────────────────────────────────────────────────────
    echo "Managed Exports:"
    local exports
    exports=$(list_exports)
    if [[ -z "$exports" ]]; then
        echo "  (none)"
    else
        while IFS= read -r line; do
            echo "  $line"
        done <<< "$exports"
    fi
    echo ""

    # ── Active exports from exportfs ─────────────────────────────────
    echo "Active Exports (from exportfs):"
    if command -v exportfs &>/dev/null; then
        local active
        active=$(exportfs -v 2>/dev/null || true)
        if [[ -z "$active" ]]; then
            echo "  (none)"
        else
            while IFS= read -r line; do
                echo "  $line"
            done <<< "$active"
        fi
    else
        echo "  (exportfs not available)"
    fi
    echo ""

    # ── Firewall ─────────────────────────────────────────────────────
    echo "Firewall:"
    local fw
    fw=$(detect_firewall)
    echo "  Type: $fw"
    case "$fw" in
        ufw)
            echo "  NFS-related rules:"
            ufw status | grep -wE "(2049|111|20048)" | while IFS= read -r line; do
                echo "    $line"
            done
            ;;
        nftables)
            echo "  NFS rules (inet nfsctl table):"
            nft list table inet nfsctl 2>/dev/null | while IFS= read -r line; do
                echo "    $line"
            done || echo "    (no nfsctl table)"
            echo "  NFS rules (inet filter, tagged nfsctl):"
            local nft_filter_rules
            nft_filter_rules=$(nft list chain inet filter input 2>/dev/null \
                | grep 'comment "nfsctl"' || true)
            if [[ -z "$nft_filter_rules" ]]; then
                echo "    (none)"
            else
                while IFS= read -r line; do
                    echo "    $line"
                done <<< "$nft_filter_rules"
            fi
            ;;
        none)
            echo "  No active firewall detected."
            ;;
    esac
    echo ""

    # ── Listening ports ──────────────────────────────────────────────
    echo "NFS Listening Ports:"
    if command -v ss &>/dev/null; then
        local port_lines
        port_lines=$(ss -tulnp 2>/dev/null | grep -E ":(2049|111|20048)\s" || true)
        if [[ -z "$port_lines" ]]; then
            echo "  (no NFS ports listening)"
        else
            while IFS= read -r line; do
                echo "  $line"
            done <<< "$port_lines"
        fi
    else
        echo "  (ss not available)"
    fi
}
