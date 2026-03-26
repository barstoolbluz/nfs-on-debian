#!/usr/bin/env bash
# commands/export-list.sh — List current exports

source "${NFSCTL_ROOT}/lib/common.sh"
source "${NFSCTL_ROOT}/lib/exports.sh"

# Escape a string for safe JSON embedding
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    # Strip any remaining control characters (U+0001-U+001F except \n \t \r already handled)
    s=$(printf '%s' "$s" | tr -d '\001-\010\013\014\016-\037')
    printf '%s' "$s"
}

# Parse an export line into arrays of (path, client, options) tuples.
# Handles multi-client lines like: /export client1(opts1) client2(opts2)
# Sets _parsed_count and indexed _parsed_path_N, _parsed_client_N, _parsed_options_N
_parse_export_line() {
    local line="$1"
    local path
    path=$(echo "$line" | awk '{print $1}')

    # Clean up stale variables from previous calls
    local _ci
    for (( _ci=0; _ci<${_parsed_count:-0}; _ci++ )); do
        unset "_parsed_path_${_ci}" "_parsed_client_${_ci}" "_parsed_options_${_ci}"
    done

    # Collect all client(options) fields (field 2..NF, skipping managed tag)
    local -a fields
    read -ra fields <<< "$line"

    _parsed_count=0
    local i
    for (( i=1; i<${#fields[@]}; i++ )); do
        local field="${fields[$i]}"
        # Skip the managed tag words: #, Managed, by, nfsctl
        [[ "$field" == "#" || "$field" == "Managed" || "$field" == "by" || "$field" == "nfsctl" ]] && continue
        # Must contain parentheses to be a client(options) pair
        [[ "$field" == *"("*")"* ]] || continue

        local client="${field%%(*}"
        local options="${field#*(}"
        options="${options%)}"

        eval "_parsed_path_${_parsed_count}=\"\$path\""
        eval "_parsed_client_${_parsed_count}=\"\$client\""
        eval "_parsed_options_${_parsed_count}=\"\$options\""
        _parsed_count=$((_parsed_count + 1))
    done

    # Fallback: if no client(options) found, output the raw line
    if (( _parsed_count == 0 )); then
        _parsed_path_0="$path"
        _parsed_client_0="(unknown)"
        _parsed_options_0="(unknown)"
        _parsed_count=1
    fi
}

cmd_export_list() {
    local show_all=0
    local format="table"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)    show_all=1; shift ;;
            --json)   format="json"; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: nfsctl export list [flags]

Flags:
  --all     Show all exports (including unmanaged)
  --json    Output in JSON format
EOF
                return 0
                ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    local exports
    if (( show_all )); then
        exports=$(list_all_exports)
    else
        exports=$(list_exports)
    fi

    if [[ -z "$exports" ]]; then
        log_info "No exports found."
        return 0
    fi

    case "$format" in
        json)
            echo "["
            local first=1
            while IFS= read -r line; do
                _parse_export_line "$line"
                local j
                for (( j=0; j<_parsed_count; j++ )); do
                    local p c o
                    eval "p=\"\$_parsed_path_${j}\""
                    eval "c=\"\$_parsed_client_${j}\""
                    eval "o=\"\$_parsed_options_${j}\""

                    (( first )) || echo ","
                    first=0
                    printf '  {"path": "%s", "client": "%s", "options": "%s"}' \
                        "$(_json_escape "$p")" \
                        "$(_json_escape "$c")" \
                        "$(_json_escape "$o")"
                done
            done <<< "$exports"
            echo ""
            echo "]"
            ;;
        table)
            printf "%-30s %-25s %-30s\n" "PATH" "CLIENT" "OPTIONS"
            printf "%-30s %-25s %-30s\n" "----------------------------" "-----------------------" "----------------------------"
            while IFS= read -r line; do
                _parse_export_line "$line"
                local j
                for (( j=0; j<_parsed_count; j++ )); do
                    local p c o
                    eval "p=\"\$_parsed_path_${j}\""
                    eval "c=\"\$_parsed_client_${j}\""
                    eval "o=\"\$_parsed_options_${j}\""
                    printf "%-30s %-25s %-30s\n" "$p" "$c" "$o"
                done
            done <<< "$exports"
            ;;
    esac
}
