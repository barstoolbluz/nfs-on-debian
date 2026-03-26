#!/usr/bin/env bash
# commands/service.sh — Manage NFS services

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/wizard.sh"
source "${NFSCTL_ROOT}/lib/services.sh"

cmd_service() {
    if [[ $# -eq 0 ]]; then
        die "Missing action. Usage: nfsctl service {start|stop|restart|enable|disable|status}"
    fi

    local action="$1"; shift
    local service="${NFS_SERVER_SERVICE:-nfs-kernel-server}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --service) require_flag_value "$1" "$#"; service="$2"; shift 2 ;;
            -h|--help)
                cat <<'EOF'
Usage: nfsctl service <action> [flags]

Actions:
  start       Start NFS server
  stop        Stop NFS server
  restart     Restart NFS server
  enable      Enable NFS server at boot
  disable     Disable NFS server at boot
  status      Show NFS service status

Flags:
  --service NAME    Override service name (default: nfs-kernel-server)
EOF
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    case "$action" in
        start)
            require_root
            ensure_service_running "$service"
            ;;
        stop)
            require_root
            stop_service "$service"
            ;;
        restart)
            require_root
            restart_service "$service"
            ;;
        enable)
            require_root
            ensure_service_enabled "$service"
            ;;
        disable)
            require_root
            disable_service "$service"
            ;;
        status)
            echo "Service: $service"
            if is_service_active "$service"; then
                echo "  Active: yes"
            else
                echo "  Active: no"
            fi
            if is_service_enabled "$service"; then
                echo "  Enabled: yes"
            else
                echo "  Enabled: no"
            fi
            ;;
        *)
            die "Unknown action: $action. Use: start|stop|restart|enable|disable|status"
            ;;
    esac
}
