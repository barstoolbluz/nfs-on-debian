#!/usr/bin/env bash
# commands/export-apply.sh — Apply exports (exportfs -ra)

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/exports.sh"

cmd_export_apply() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "Usage: nfsctl export apply"
                echo "  Applies current /etc/exports configuration (runs exportfs -ra)"
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    require_root
    apply_exports
}
