#!/usr/bin/env bash
# lib/exports.sh — /etc/exports parsing, add, remove, apply

[[ -n "${_NFSCTL_EXPORTS_LOADED:-}" ]] && return 0
_NFSCTL_EXPORTS_LOADED=1

source "${NFSCTL_ROOT}/lib/common.sh"

# ── Get managed export entry ─────────────────────────────────────────
# Returns the line matching path+client, or empty
get_export_entry() {
    local path="$1"
    local client="$2"
    local exports_file="${EXPORTS_FILE:-/etc/exports}"

    [[ -f "$exports_file" ]] || return 0

    # Escape regex special chars in path and client for grep
    local epath eclient
    epath=$(printf '%s' "$path" | sed 's/[][\\.^$*+?{}()|/]/\\&/g')
    eclient=$(printf '%s' "$client" | sed 's/[][\\.^$*+?{}()|/]/\\&/g')

    # Match: path client(options) # Managed by nfsctl
    grep -n "^${epath}[[:space:]]\+${eclient}(" "$exports_file" 2>/dev/null | \
        grep "${MANAGED_TAG}" || true
}

# ── List all managed exports ─────────────────────────────────────────
list_exports() {
    local exports_file="${EXPORTS_FILE:-/etc/exports}"

    [[ -f "$exports_file" ]] || return 0

    grep "${MANAGED_TAG}" "$exports_file" 2>/dev/null || true
}

# ── List all exports (managed and unmanaged) ─────────────────────────
list_all_exports() {
    local exports_file="${EXPORTS_FILE:-/etc/exports}"

    [[ -f "$exports_file" ]] || return 0

    # Return non-empty, non-comment lines
    grep -v '^\s*$' "$exports_file" 2>/dev/null | grep -v '^\s*#' || true
}

# ── Escape sed replacement string ────────────────────────────────────
_sed_escape_replacement() {
    printf '%s' "$1" | sed 's/[&\\/|]/\\&/g'
}

# ── Add an export entry (idempotent) ─────────────────────────────────
add_export_entry() {
    local path="$1"
    local client="$2"
    local options="$3"
    local exports_file="${EXPORTS_FILE:-/etc/exports}"

    local entry="${path} ${client}(${options}) ${MANAGED_TAG}"

    # Quick pre-lock check for the exact-match (idempotent skip) case
    if [[ -f "$exports_file" ]]; then
        local existing
        existing=$(get_export_entry "$path" "$client")
        if [[ -n "$existing" ]]; then
            local existing_line
            existing_line=$(echo "$existing" | sed 's/^[0-9]*://')
            if [[ "$existing_line" == "$entry" ]]; then
                log_info "Export already exists: $entry"
                return 0
            fi
        fi
    fi

    if dry_run_msg "Would add/update export: $entry"; then
        return 0
    fi

    acquire_lock
    backup_file "$exports_file"

    # Re-check under lock to avoid TOCTOU
    local existing=""
    if [[ -f "$exports_file" ]]; then
        existing=$(get_export_entry "$path" "$client")
    fi

    if [[ -n "$existing" ]]; then
        local existing_line
        existing_line=$(echo "$existing" | sed 's/^[0-9]*://')
        if [[ "$existing_line" == "$entry" ]]; then
            release_lock
            log_info "Export already exists: $entry"
            return 0
        fi
        # Options differ — update in place
        local line_num
        line_num=$(echo "$existing" | head -1 | cut -d: -f1)
        local safe_entry
        safe_entry=$(_sed_escape_replacement "$entry")
        sed -i "${line_num}s|.*|${safe_entry}|" "$exports_file"
        release_lock
        log_info "Export updated: $entry"
    else
        # Ensure file exists and ends with a newline before appending
        touch "$exports_file"
        if [[ -s "$exports_file" ]] && [[ -n "$(tail -c 1 "$exports_file")" ]]; then
            echo >> "$exports_file"
        fi
        echo "$entry" >> "$exports_file"
        release_lock
        log_info "Export added: $entry"
    fi
}

# ── Remove an export entry ───────────────────────────────────────────
remove_export_entry() {
    local path="$1"
    local client="$2"
    local exports_file="${EXPORTS_FILE:-/etc/exports}"

    [[ -f "$exports_file" ]] || { log_warn "Exports file does not exist."; return 0; }

    # Quick pre-lock check
    local existing
    existing=$(get_export_entry "$path" "$client")
    if [[ -z "$existing" ]]; then
        log_info "No managed export found for $path $client — nothing to remove."
        return 0
    fi

    if dry_run_msg "Would remove export for $path $client"; then
        return 0
    fi

    acquire_lock
    backup_file "$exports_file"

    # Re-check under lock
    existing=$(get_export_entry "$path" "$client")
    if [[ -z "$existing" ]]; then
        release_lock
        log_info "No managed export found for $path $client — nothing to remove."
        return 0
    fi

    local line_num
    line_num=$(echo "$existing" | head -1 | cut -d: -f1)
    sed -i "${line_num}d" "$exports_file"

    release_lock
    log_info "Removed export for $path $client"
}

# ── Apply exports ────────────────────────────────────────────────────
apply_exports() {
    if dry_run_msg "Would run exportfs -ra"; then
        return 0
    fi

    log_info "Applying exports..."
    exportfs -ra
    log_info "Exports applied."
}
