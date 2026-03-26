#!/usr/bin/env bash
# commands/export-add.sh — Add an NFS export

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/wizard.sh"
source "${NFSCTL_ROOT}/lib/validation.sh"
source "${NFSCTL_ROOT}/lib/exports.sh"

cmd_export_add() {
    # Parse command flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)     require_flag_value "$1" "$#"; wizard_set "path" "$2"; shift 2 ;;
            --client)   require_flag_value "$1" "$#"; wizard_set "client" "$2"; shift 2 ;;
            --options)  require_flag_value "$1" "$#"; wizard_set "options" "$2"; shift 2 ;;
            --create-dir) wizard_set "create_dir" "yes"; shift ;;
            --no-create-dir) wizard_set "create_dir" "no"; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: nfsctl export add [flags]

Flags:
  --path PATH          Export path (e.g., /srv/nfs/data)
  --client CLIENT      Client specifier (e.g., 10.0.0.0/24, *, hostname)
  --options OPTIONS    NFS export options (e.g., rw,sync,no_subtree_check)
  --create-dir         Create the export directory if it doesn't exist
  --no-create-dir      Do not create the export directory
EOF
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    require_root

    local export_path
    export_path=$(ask_value "path" "Export path" "${DEFAULT_EXPORT_PATH}" "validate_export_path")

    local client
    client=$(ask_value "client" "Client (IP, CIDR, hostname, or *)" "${DEFAULT_CLIENT}" "validate_nfs_client")

    if is_interactive && ! wizard_has "options"; then
        printf "  Tip: add no_root_squash if clients need root access to the share\n" >&2
        printf "  (without it, remote root is mapped to 'nobody' for safety)\n" >&2
    fi
    local options
    options=$(ask_value "options" "NFS options" "${DEFAULT_EXPORT_OPTIONS}" "validate_export_options")

    # Handle directory creation
    if [[ ! -d "$export_path" ]]; then
        local create_dir
        if wizard_has "create_dir"; then
            create_dir=$(wizard_get "create_dir")
        elif is_interactive; then
            if ask_confirm "Directory '$export_path' does not exist. Create it?"; then
                create_dir="yes"
            else
                create_dir="no"
            fi
        else
            create_dir="yes"
        fi

        if [[ "$create_dir" == "yes" ]]; then
            if dry_run_msg "Would create directory $export_path"; then
                :
            else
                mkdir -p "$export_path"
                chmod 755 "$export_path"
                log_info "Created directory: $export_path"
            fi
        fi
    fi

    add_export_entry "$export_path" "$client" "$options"

    if ask_confirm "Apply exports now?" "true"; then
        apply_exports
    fi
}
