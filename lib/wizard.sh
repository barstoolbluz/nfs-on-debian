#!/usr/bin/env bash
# lib/wizard.sh — Dual-mode prompt framework (interactive + CLI flags)

[[ -n "${_NFSCTL_WIZARD_LOADED:-}" ]] && return 0
_NFSCTL_WIZARD_LOADED=1

source "${NFSCTL_ROOT}/lib/common.sh"

# ── Associative array for wizard values ──────────────────────────────
declare -gA _WIZARD_VALUES=()

wizard_set() {
    local key="$1" value="$2"
    _WIZARD_VALUES["$key"]="$value"
}

wizard_get() {
    local key="$1"
    echo "${_WIZARD_VALUES[$key]:-}"
}

wizard_has() {
    local key="$1"
    [[ -n "${_WIZARD_VALUES[$key]+set}" && -n "${_WIZARD_VALUES[$key]}" ]]
}

# ── Interactive detection ────────────────────────────────────────────
is_interactive() {
    [[ -t 0 && "${YES:-0}" -eq 0 ]]
}

# ── Core prompt function ─────────────────────────────────────────────
# ask_value KEY PROMPT [DEFAULT] [VALIDATOR]
# Priority: 1) CLI flag (wizard_set), 2) interactive prompt, 3) default
ask_value() {
    local key="$1"
    local prompt="$2"
    local default="${3:-}"
    local validator="${4:-}"

    # 1. Already set via CLI flag
    if wizard_has "$key"; then
        local val
        val=$(wizard_get "$key")
        if [[ -n "$validator" ]] && ! "$validator" "$val"; then
            die "Invalid value for $key: $val"
        fi
        log_debug "$key = $val (from flag)"
        echo "$val"
        return 0
    fi

    # 2. Interactive prompt
    if is_interactive; then
        local input
        while true; do
            if [[ -n "$default" ]]; then
                printf "%s [%s]: " "$prompt" "$default" >&2
            else
                printf "%s: " "$prompt" >&2
            fi
            read -r input
            input="${input:-$default}"

            if [[ -z "$input" ]]; then
                log_warn "A value is required."
                continue
            fi

            if [[ -n "$validator" ]] && ! "$validator" "$input"; then
                log_warn "Invalid input. Please try again."
                continue
            fi

            wizard_set "$key" "$input"
            echo "$input"
            return 0
        done
    fi

    # 3. Default value
    if [[ -n "$default" ]]; then
        if [[ -n "$validator" ]] && ! "$validator" "$default"; then
            die "Invalid default for $key: $default"
        fi
        wizard_set "$key" "$default"
        log_debug "$key = $default (from default)"
        echo "$default"
        return 0
    fi

    local flag_hint="${key//_/-}"
    die "No value provided for '$key' and no default available. Use --${flag_hint} flag or run interactively."
}

# ── Confirmation prompt ──────────────────────────────────────────────
# ask_confirm PROMPT [DEFAULT_YES=true]
ask_confirm() {
    local prompt="$1"
    local default_yes="${2:-true}"

    # --yes mode: always confirm
    if (( YES )); then
        return 0
    fi

    if ! is_interactive; then
        # Non-interactive without --yes: use default
        [[ "$default_yes" == "true" ]] && return 0 || return 1
    fi

    local yn_hint
    [[ "$default_yes" == "true" ]] && yn_hint="Y/n" || yn_hint="y/N"

    while true; do
        printf "%s [%s]: " "$prompt" "$yn_hint" >&2
        local answer
        read -r answer
        answer="${answer:-$( [[ "$default_yes" == "true" ]] && echo y || echo n )}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     log_warn "Please answer y or n." ;;
        esac
    done
}

# ── Choice prompt ────────────────────────────────────────────────────
# ask_choice KEY PROMPT DEFAULT OPTION1 OPTION2 ...
ask_choice() {
    local key="$1"; shift
    local prompt="$1"; shift
    local default="$1"; shift
    local -a options=("$@")

    # Inline validator: must be one of the options
    _is_valid_choice() {
        local val="$1"
        local opt
        for opt in "${options[@]}"; do
            [[ "$val" == "$opt" ]] && return 0
        done
        return 1
    }

    # If already set via flag, validate and return
    if wizard_has "$key"; then
        local val
        val=$(wizard_get "$key")
        if ! _is_valid_choice "$val"; then
            die "Invalid choice for $key: $val (must be one of: ${options[*]})"
        fi
        echo "$val"
        unset -f _is_valid_choice
        return 0
    fi

    if is_interactive; then
        printf "\n%s\n" "$prompt" >&2
        local i
        for i in "${!options[@]}"; do
            local marker=" "
            [[ "${options[$i]}" == "$default" ]] && marker="*"
            printf "  %s %d) %s\n" "$marker" $((i + 1)) "${options[$i]}" >&2
        done
        while true; do
            printf "Choice [%s]: " "$default" >&2
            local input
            read -r input
            input="${input:-$default}"

            # Accept number or value
            if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#options[@]} )); then
                input="${options[$((input - 1))]}"
            fi

            if _is_valid_choice "$input"; then
                wizard_set "$key" "$input"
                echo "$input"
                unset -f _is_valid_choice
                return 0
            fi
            log_warn "Invalid choice. Pick a number (1-${#options[@]}) or one of: ${options[*]}"
        done
    fi

    # Non-interactive: use default
    wizard_set "$key" "$default"
    echo "$default"
    unset -f _is_valid_choice
}
