#!/usr/bin/env bash
# commands/install.sh — Install NFS server/client packages

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/wizard.sh"
source "${NFSCTL_ROOT}/lib/packages.sh"

cmd_install() {
    # Parse command flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)  require_flag_value "$1" "$#"; wizard_set "type" "$2"; shift 2 ;;
            -h|--help)
                echo "Usage: nfsctl install [--type server|client]"
                echo "  --type    Installation type: 'server' or 'client'"
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    require_root

    local install_type
    install_type=$(ask_choice "type" "What would you like to install?" "server" "server" "client")

    case "$install_type" in
        server)
            log_info "Installing NFS server packages..."
            # shellcheck disable=SC2086
            ensure_packages_installed $NFS_SERVER_PACKAGES
            ;;
        client)
            log_info "Installing NFS client packages..."
            # shellcheck disable=SC2086
            ensure_packages_installed $NFS_CLIENT_PACKAGES
            ;;
    esac

    log_info "NFS $install_type installation complete."
}
