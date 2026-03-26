#!/usr/bin/env bash
# commands/export-remove.sh — Remove an NFS export

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/wizard.sh"
source "${NFSCTL_ROOT}/lib/validation.sh"
source "${NFSCTL_ROOT}/lib/exports.sh"

cmd_export_remove() {
    # Parse command flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)    require_flag_value "$1" "$#"; wizard_set "path" "$2"; shift 2 ;;
            --client)  require_flag_value "$1" "$#"; wizard_set "client" "$2"; shift 2 ;;
            -h|--help)
                cat <<'EOF'
Usage: nfsctl export remove [flags]

Flags:
  --path PATH       Export path to remove
  --client CLIENT   Client specifier to remove
EOF
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    require_root

    # In interactive mode, show current exports and let user pick
    if ! wizard_has "path" && is_interactive; then
        local exports
        exports=$(list_exports)
        if [[ -z "$exports" ]]; then
            log_info "No managed exports found."
            return 0
        fi
        echo ""
        echo "Current managed exports:"
        echo "-----------------------------------------"
        local i=0
        local -a paths=()
        local -a clients=()
        while IFS= read -r line; do
            i=$((i + 1))
            local p c
            p=$(echo "$line" | awk '{print $1}')
            # Note: managed exports are always one client per line (nfsctl invariant)
            c=$(echo "$line" | awk '{print $2}' | sed 's/(.*//')
            paths+=("$p")
            clients+=("$c")
            printf "  %d) %s\n" "$i" "$line"
        done <<< "$exports"
        echo ""

        local choice
        printf "Select export to remove (1-%d): " "$i"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= i )); then
            wizard_set "path" "${paths[$((choice - 1))]}"
            wizard_set "client" "${clients[$((choice - 1))]}"
        else
            die "Invalid selection."
        fi
    fi

    local export_path
    export_path=$(ask_value "path" "Export path to remove" "" "validate_export_path")

    local client
    client=$(ask_value "client" "Client to remove" "${DEFAULT_CLIENT}" "validate_nfs_client")

    if ask_confirm "Remove export '$export_path' for client '$client'?"; then
        remove_export_entry "$export_path" "$client"

        if ask_confirm "Apply exports now?" "true"; then
            apply_exports
        fi
    fi
}
