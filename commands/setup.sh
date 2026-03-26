#!/usr/bin/env bash
# commands/setup.sh — Full guided setup wizard (orchestrates other commands)

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/wizard.sh"
source "${NFSCTL_ROOT}/lib/validation.sh"
source "${NFSCTL_ROOT}/lib/packages.sh"
source "${NFSCTL_ROOT}/lib/exports.sh"
source "${NFSCTL_ROOT}/lib/services.sh"
source "${NFSCTL_ROOT}/lib/firewall.sh"

cmd_setup() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)    require_flag_value "$1" "$#"; wizard_set "type" "$2"; shift 2 ;;
            --path)    require_flag_value "$1" "$#"; wizard_set "path" "$2"; shift 2 ;;
            --client)  require_flag_value "$1" "$#"; wizard_set "client" "$2"; shift 2 ;;
            --options) require_flag_value "$1" "$#"; wizard_set "options" "$2"; shift 2 ;;
            -h|--help)
                cat <<'EOF'
Usage: nfsctl setup [flags]

Full guided NFS server setup wizard. Walks through:
  1. Package installation
  2. Export configuration
  3. Apply exports (exportfs -ra)
  4. Firewall rules
  5. Service start

Flags:
  --type TYPE        Installation type: server or client
  --path PATH        Export path (can be specified once; use interactive for multiple)
  --client CLIENT    Client specifier
  --options OPTIONS  NFS export options
EOF
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    require_root

    echo "============================================"
    echo "        NFS Server Setup Wizard"
    echo "============================================"
    echo ""

    # ── Step 1: Installation type ────────────────────────────────────
    log_info "Step 1: Package Installation"
    local install_type
    install_type=$(ask_choice "type" "What would you like to install?" "server" "server" "client")

    case "$install_type" in
        server)
            # shellcheck disable=SC2086
            ensure_packages_installed $NFS_SERVER_PACKAGES
            ;;
        client)
            # shellcheck disable=SC2086
            ensure_packages_installed $NFS_CLIENT_PACKAGES
            log_info "Client setup complete."
            return 0
            ;;
    esac

    # ── Step 2: Configure exports ────────────────────────────────────
    log_info "Step 2: Export Configuration"

    local add_exports=1
    # If path was given via flag, add that single export
    if wizard_has "path"; then
        local export_path client options
        export_path=$(wizard_get "path")
        validate_export_path "$export_path" || die "Invalid export path: $export_path"

        client=$(ask_value "client" "Client" "${DEFAULT_CLIENT}" "validate_nfs_client")
        options=$(ask_value "options" "NFS options" "${DEFAULT_EXPORT_OPTIONS}" "validate_export_options")

        if [[ ! -d "$export_path" ]]; then
            if ! dry_run_msg "Would create directory $export_path"; then
                mkdir -p "$export_path"
                chmod 755 "$export_path"
                log_info "Created directory: $export_path"
            fi
        fi

        add_export_entry "$export_path" "$client" "$options"
        add_exports=0
    fi

    # Interactive: loop to add exports
    if (( add_exports )) && is_interactive; then
        while true; do
            if ! ask_confirm "Add an NFS export?"; then
                break
            fi

            # Clear previous wizard values for the loop
            unset '_WIZARD_VALUES[path]' '_WIZARD_VALUES[client]' '_WIZARD_VALUES[options]'

            local export_path client options
            export_path=$(ask_value "path" "Export path" "${DEFAULT_EXPORT_PATH}" "validate_export_path")
            client=$(ask_value "client" "Client (IP, CIDR, hostname, or *)" "${DEFAULT_CLIENT}" "validate_nfs_client")
            options=$(ask_value "options" "NFS options" "${DEFAULT_EXPORT_OPTIONS}" "validate_export_options")

            if [[ ! -d "$export_path" ]]; then
                if ask_confirm "Directory '$export_path' does not exist. Create it?"; then
                    if ! dry_run_msg "Would create directory $export_path"; then
                        mkdir -p "$export_path"
                        chmod 755 "$export_path"
                        log_info "Created directory: $export_path"
                    fi
                fi
            fi

            add_export_entry "$export_path" "$client" "$options"
        done
    elif (( add_exports )); then
        # Non-interactive with no --path: add default export
        local export_path="${DEFAULT_EXPORT_PATH}"
        local client="${DEFAULT_CLIENT}"
        local options="${DEFAULT_EXPORT_OPTIONS}"

        if [[ ! -d "$export_path" ]]; then
            if ! dry_run_msg "Would create directory $export_path"; then
                mkdir -p "$export_path"
                chmod 755 "$export_path"
                log_info "Created directory: $export_path"
            fi
        fi

        add_export_entry "$export_path" "$client" "$options"
    fi

    # ── Step 3: Apply exports ────────────────────────────────────────
    log_info "Step 3: Applying Exports"
    apply_exports

    # ── Step 4: Firewall ─────────────────────────────────────────────
    log_info "Step 4: Firewall Configuration"
    if ask_confirm "Configure firewall rules for NFS?"; then
        ensure_nfs_firewall_rules
    fi

    # ── Step 5: Start service ────────────────────────────────────────
    log_info "Step 5: Starting NFS Service"
    ensure_service_running "${NFS_SERVER_SERVICE}"

    echo ""
    log_info "NFS server setup complete!"
    echo ""
    log_info "Managed exports:"
    list_exports | while IFS= read -r line; do
        echo "  $line"
    done
}
