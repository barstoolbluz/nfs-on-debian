#!/usr/bin/env bash
# tests/helpers/mock.sh — Test mock framework for system commands

# ── Test framework -----------------------------------------──────────
_TEST_COUNT=0
_TEST_PASS=0
_TEST_FAIL=0
_TEST_FAILURES=()

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assertion}"
    _TEST_COUNT=$((_TEST_COUNT + 1))

    if [[ "$expected" == "$actual" ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        printf "  \033[0;32m✓\033[0m %s\n" "$msg"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        _TEST_FAILURES+=("$msg: expected='$expected' actual='$actual'")
        printf "  \033[0;31m✗\033[0m %s\n" "$msg"
        printf "    expected: %s\n" "$expected"
        printf "    actual:   %s\n" "$actual"
    fi
}

# Usage: some_cmd; assert_success $? "message"
# The caller must capture $? and pass it as the first argument.
assert_success() {
    local exit_code="$1"
    local msg="${2:-should succeed}"
    _TEST_COUNT=$((_TEST_COUNT + 1))

    if [[ "$exit_code" -eq 0 ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        printf "  \033[0;32m✓\033[0m %s\n" "$msg"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        _TEST_FAILURES+=("$msg: exit code $exit_code")
        printf "  \033[0;31m✗\033[0m %s (exit code: %d)\n" "$msg" "$exit_code"
    fi
}

assert_fail() {
    local exit_code="$1"
    local msg="${2:-should fail}"
    _TEST_COUNT=$((_TEST_COUNT + 1))

    if [[ "$exit_code" -ne 0 ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        printf "  \033[0;32m✓\033[0m %s\n" "$msg"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        _TEST_FAILURES+=("$msg: expected failure but got success")
        printf "  \033[0;31m✗\033[0m %s (expected failure but got 0)\n" "$msg"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-should contain '$needle'}"
    _TEST_COUNT=$((_TEST_COUNT + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        printf "  \033[0;32m✓\033[0m %s\n" "$msg"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        _TEST_FAILURES+=("$msg")
        printf "  \033[0;31m✗\033[0m %s\n" "$msg"
        printf "    needle:   %s\n" "$needle"
        printf "    haystack: %s\n" "$haystack"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-should not contain '$needle'}"
    _TEST_COUNT=$((_TEST_COUNT + 1))

    if [[ "$haystack" != *"$needle"* ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        printf "  \033[0;32m✓\033[0m %s\n" "$msg"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        _TEST_FAILURES+=("$msg")
        printf "  \033[0;31m✗\033[0m %s\n" "$msg"
    fi
}

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local msg="${3:-file should contain '$needle'}"
    _TEST_COUNT=$((_TEST_COUNT + 1))

    if grep -qF "$needle" "$file" 2>/dev/null; then
        _TEST_PASS=$((_TEST_PASS + 1))
        printf "  \033[0;32m✓\033[0m %s\n" "$msg"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        _TEST_FAILURES+=("$msg")
        printf "  \033[0;31m✗\033[0m %s\n" "$msg"
    fi
}

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local msg="${3:-file should not contain '$needle'}"
    _TEST_COUNT=$((_TEST_COUNT + 1))

    if ! grep -qF "$needle" "$file" 2>/dev/null; then
        _TEST_PASS=$((_TEST_PASS + 1))
        printf "  \033[0;32m✓\033[0m %s\n" "$msg"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        _TEST_FAILURES+=("$msg")
        printf "  \033[0;31m✗\033[0m %s\n" "$msg"
    fi
}

assert_line_count() {
    local file="$1"
    local expected="$2"
    local msg="${3:-file should have $expected lines}"
    local actual
    actual=$(grep -c '' "$file" 2>/dev/null || echo 0)
    assert_eq "$expected" "$actual" "$msg"
}

test_summary() {
    echo ""
    echo "-----------------------------------------"
    printf "Tests: %d total, " "$_TEST_COUNT"
    printf "\033[0;32m%d passed\033[0m, " "$_TEST_PASS"
    printf "\033[0;31m%d failed\033[0m\n" "$_TEST_FAIL"

    if [[ ${#_TEST_FAILURES[@]} -gt 0 ]]; then
        echo ""
        echo "Failures:"
        local f
        for f in "${_TEST_FAILURES[@]}"; do
            echo "  - $f"
        done
    fi

    echo "-----------------------------------------"
    (( _TEST_FAIL == 0 )) && return 0 || return 1
}

# ── Mock system commands -----------------------------------------────
# Creates temporary mock scripts that can be prepended to PATH

create_mock_dir() {
    local dir
    dir=$(mktemp -d)
    echo "$dir"
}

# mock_command DIR NAME BODY
# Creates an executable mock at DIR/NAME
mock_command() {
    local dir="$1" name="$2" body="$3"
    cat > "${dir}/${name}" <<MOCK
#!/usr/bin/env bash
${body}
MOCK
    chmod +x "${dir}/${name}"
}

# ── Temp directory helpers -----------------------------------------──
create_test_tmpdir() {
    local dir
    dir=$(mktemp -d)
    echo "$dir"
}

cleanup_test_tmpdir() {
    local dir="$1"
    [[ -d "$dir" ]] && rm -rf "$dir"
}

# ── Test group / describe -----------------------------------------───
describe() {
    echo ""
    printf "\033[1m%s\033[0m\n" "$1"
}
