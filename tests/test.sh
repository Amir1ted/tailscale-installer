#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
PROJECT_DIR="$(cd -- "${TEST_DIR}/.." && pwd)"
readonly PROJECT_DIR
readonly INSTALLER="${PROJECT_DIR}/install.sh"
readonly MOCK_COMMAND="${TEST_DIR}/mock-command.sh"

PASS_COUNT=0
FAIL_COUNT=0
TEMP_TEST_DIR=""

pass() {
    printf 'ok - %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_success() {
    local name=$1
    shift

    if "$@"; then
        pass "${name}"
    else
        fail "${name}"
    fi
}

assert_failure() {
    local name=$1
    shift

    if "$@"; then
        fail "${name}"
    else
        pass "${name}"
    fi
}

assert_contains() {
    local name=$1
    local haystack=$2
    local needle=$3

    if [[ "${haystack}" == *"${needle}"* ]]; then
        pass "${name}"
    else
        fail "${name}"
        printf '  expected output to contain: %s\n' "${needle}" >&2
    fi
}

assert_not_contains() {
    local name=$1
    local haystack=$2
    local needle=$3

    if [[ "${haystack}" != *"${needle}"* ]]; then
        pass "${name}"
    else
        fail "${name}"
        printf '  output unexpectedly contained: %s\n' "${needle}" >&2
    fi
}

run_quietly() {
    "$@" >/dev/null 2>&1
}

cleanup_tests() {
    if [[ -n "${TEMP_TEST_DIR}" && -d "${TEMP_TEST_DIR}" ]]; then
        rm -f -- \
            "${TEMP_TEST_DIR}/os-release" \
            "${TEMP_TEST_DIR}/auth-key" \
            "${TEMP_TEST_DIR}/mock.log" \
            "${TEMP_TEST_DIR}/mock.state" \
            "${TEMP_TEST_DIR}/installer.lock" \
            "${TEMP_TEST_DIR}/mockbin/apt-get" \
            "${TEMP_TEST_DIR}/mockbin/curl" \
            "${TEMP_TEST_DIR}/mockbin/flock" \
            "${TEMP_TEST_DIR}/mockbin/gpg" \
            "${TEMP_TEST_DIR}/mockbin/id" \
            "${TEMP_TEST_DIR}/mockbin/install" \
            "${TEMP_TEST_DIR}/mockbin/jq" \
            "${TEMP_TEST_DIR}/mockbin/systemctl" \
            "${TEMP_TEST_DIR}/mockbin/tailscale"
        rmdir -- \
            "${TEMP_TEST_DIR}/mockbin" \
            "${TEMP_TEST_DIR}/systemd" \
            "${TEMP_TEST_DIR}" 2>/dev/null || true
    fi
}

trap cleanup_tests EXIT

# Sourcing exposes the pure validation helpers. Clear the installer's traps so
# this test runner owns its cleanup and failure reporting.
# shellcheck disable=SC1090
source "${INSTALLER}"
trap - ERR
trap cleanup_tests EXIT

run_validation_tests() {
    local hostname
    local tag_set

    for hostname in \
        server \
        app-01 \
        app-01.example \
        university-server.internal; do
        assert_success "valid hostname: ${hostname}" validate_hostname "${hostname}"
    done

    for hostname in \
        '-server' \
        'server-' \
        'bad_name' \
        'double..dot' \
        ''; do
        assert_failure "invalid hostname: ${hostname:-<empty>}" validate_hostname "${hostname}"
    done

    for tag_set in \
        'tag:server' \
        'tag:server,tag:linux' \
        'tag:app-01,tag:prod_eu'; do
        assert_success "valid tag set: ${tag_set}" validate_tags "${tag_set}"
    done

    for tag_set in \
        'server' \
        'tag:' \
        'tag:server,linux' \
        'tag:server tag:linux'; do
        assert_failure "invalid tag set: ${tag_set}" validate_tags "${tag_set}"
    done
}

run_cli_tests() {
    local output
    local expected_version

    expected_version="$(tr -d '[:space:]' < "${PROJECT_DIR}/VERSION")"
    output="$("${INSTALLER}" --version)"

    assert_contains "CLI reports the VERSION file value" "${output}" "${expected_version}"
    assert_success "help exits successfully" run_quietly "${INSTALLER}" --help
    assert_failure "unknown option is rejected" run_quietly "${INSTALLER}" --definitely-unknown
    assert_failure "invalid package channel is rejected" run_quietly "${INSTALLER}" --channel edge
}

run_static_policy_tests() {
    local installer_text

    installer_text="$(< "${INSTALLER}")"
    assert_not_contains "remote scripts are not piped to a shell" "${installer_text}" 'curl -fsSL https://tailscale.com/install.sh | sh'
    assert_contains "strict Bash mode is enabled" "${installer_text}" 'set -Eeuo pipefail'
    assert_contains "auth keys use file input" "${installer_text}" '--auth-key=file:'
}

run_dry_run_test() {
    local legacy_output
    local output
    local secret='AUTH_KEY_TEST_VALUE_MUST_NOT_LEAK'

    TEMP_TEST_DIR="$(mktemp -d -t uti-tests.XXXXXX)"
    mkdir -p "${TEMP_TEST_DIR}/mockbin" "${TEMP_TEST_DIR}/systemd"

    printf '%s\n' \
        'ID=ubuntu' \
        'VERSION_ID="22.04"' \
        'VERSION_CODENAME=jammy' > "${TEMP_TEST_DIR}/os-release"

    printf '%s\n' \
        '#!/usr/bin/env sh' \
        "if [ \"\${1-}\" = \"-u\" ]; then" \
        '    printf "0\n"' \
        'else' \
        "    exec /usr/bin/id \"\$@\"" \
        'fi' > "${TEMP_TEST_DIR}/mockbin/id"
    chmod 0755 "${TEMP_TEST_DIR}/mockbin/id"

    output="$(
        PATH="${TEMP_TEST_DIR}/mockbin:${PATH}" \
        UTI_OS_RELEASE_FILE="${TEMP_TEST_DIR}/os-release" \
        UTI_SYSTEMD_RUNTIME_DIR="${TEMP_TEST_DIR}/systemd" \
        TS_AUTHKEY="${secret}" \
        "${INSTALLER}" \
            --dry-run \
            --no-color \
            --hostname app-01 \
            --advertise-tags tag:server \
            --ssh \
            2>&1
    )"

    assert_contains "dry run detects fixture Ubuntu" "${output}" 'Ubuntu 22.04 (jammy) detected'
    assert_contains "dry run uses official Jammy repository" "${output}" 'pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg'
    assert_contains "dry run builds protected auth-key argument" "${output}" '--auth-key=file:'
    assert_contains "dry run includes requested hostname" "${output}" '--hostname=app-01'
    assert_not_contains "dry run never prints the auth key" "${output}" "${secret}"
    assert_contains "dry run reaches completion" "${output}" 'Dry run completed'

    printf '%s\n' \
        'ID=ubuntu' \
        'VERSION_ID="18.04"' \
        'VERSION_CODENAME=bionic' > "${TEMP_TEST_DIR}/os-release"

    if legacy_output="$(
        PATH="${TEMP_TEST_DIR}/mockbin:${PATH}" \
        UTI_OS_RELEASE_FILE="${TEMP_TEST_DIR}/os-release" \
        UTI_SYSTEMD_RUNTIME_DIR="${TEMP_TEST_DIR}/systemd" \
        "${INSTALLER}" --dry-run --no-color 2>&1
    )"; then
        fail "Ubuntu older than 20.04 is rejected"
    else
        pass "Ubuntu older than 20.04 is rejected"
        assert_contains "unsupported Ubuntu has an actionable message" \
            "${legacy_output}" \
            'Ubuntu 20.04 or newer is required'
    fi

    cleanup_tests
    TEMP_TEST_DIR=""
}

run_mock_install_test() {
    local command_name
    local mock_log
    local output
    local secret='AUTH_KEY_MOCK_INSTALL_VALUE'

    TEMP_TEST_DIR="$(mktemp -d -t uti-install-tests.XXXXXX)"
    mkdir -p "${TEMP_TEST_DIR}/mockbin" "${TEMP_TEST_DIR}/systemd"

    printf '%s\n' \
        'ID=ubuntu' \
        'VERSION_ID="22.04"' \
        'VERSION_CODENAME=jammy' > "${TEMP_TEST_DIR}/os-release"
    printf '%s' "${secret}" > "${TEMP_TEST_DIR}/auth-key"
    chmod 0600 "${TEMP_TEST_DIR}/auth-key"
    : > "${TEMP_TEST_DIR}/mock.log"
    printf 'NeedsLogin\n' > "${TEMP_TEST_DIR}/mock.state"

    for command_name in apt-get curl flock gpg id install jq systemctl tailscale; do
        ln -s "${MOCK_COMMAND}" "${TEMP_TEST_DIR}/mockbin/${command_name}"
    done

    output="$(
        PATH="${TEMP_TEST_DIR}/mockbin:${PATH}" \
        UTI_OS_RELEASE_FILE="${TEMP_TEST_DIR}/os-release" \
        UTI_SYSTEMD_RUNTIME_DIR="${TEMP_TEST_DIR}/systemd" \
        UTI_LOCK_FILE="${TEMP_TEST_DIR}/installer.lock" \
        MOCK_LOG="${TEMP_TEST_DIR}/mock.log" \
        MOCK_STATE="${TEMP_TEST_DIR}/mock.state" \
        EXPECTED_SECRET="${secret}" \
        "${INSTALLER}" \
            --no-color \
            --auth-key-file "${TEMP_TEST_DIR}/auth-key" \
            --hostname app-01 \
            --advertise-tags tag:server \
            --ssh \
            --accept-routes \
            --operator root \
            2>&1
    )"
    mock_log="$(< "${TEMP_TEST_DIR}/mock.log")"

    assert_contains "mock install installs Tailscale package" "${mock_log}" 'apt-get install -y --no-install-recommends tailscale'
    assert_contains "mock install enables tailscaled" "${mock_log}" 'systemctl enable --now tailscaled'
    assert_contains "mock install authenticates through a file" "${mock_log}" 'tailscale up --auth-key=file:'
    assert_contains "mock install applies the hostname" "${mock_log}" '--hostname=app-01'
    assert_contains "mock install applies requested tags" "${mock_log}" '--advertise-tags=tag:server'
    assert_contains "mock install enables Tailscale SSH" "${mock_log}" '--ssh'
    assert_contains "mock install accepts subnet routes" "${mock_log}" '--accept-routes'
    assert_contains "mock install configures the local operator" "${mock_log}" 'tailscale set --operator=root'
    assert_contains "mock install reaches Running state" "${output}" 'Backend state     : Running'
    assert_contains "mock install prints the MagicDNS name" "${output}" 'mock-node.example.ts.net'
    assert_not_contains "mock install output does not leak auth key" "${output}" "${secret}"
    assert_not_contains "mock command log does not leak auth key" "${mock_log}" "${secret}"

    cleanup_tests
    TEMP_TEST_DIR=""
}

main() {
    run_validation_tests
    run_cli_tests
    run_static_policy_tests
    run_dry_run_test
    run_mock_install_test

    printf '\nPassed: %d\nFailed: %d\n' "${PASS_COUNT}" "${FAIL_COUNT}"
    (( FAIL_COUNT == 0 ))
}

main "$@"
