#!/usr/bin/env bash
# commands/firewall.sh — Configure firewall rules for NFS

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/wizard.sh"
source "${NFSCTL_ROOT}/lib/firewall.sh"

cmd_firewall() {
    local action="add"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remove) action="remove"; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: nfsctl firewall [flags]

Configures firewall rules for NFS (ports 2049, 111, 20048).
Automatically detects ufw or nftables.

Flags:
  --remove    Remove NFS firewall rules instead of adding them
EOF
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    require_root

    local fw
    fw=$(detect_firewall)
    log_info "Detected firewall: $fw"

    case "$action" in
        add)    ensure_nfs_firewall_rules ;;
        remove) remove_nfs_firewall_rules ;;
    esac
}
