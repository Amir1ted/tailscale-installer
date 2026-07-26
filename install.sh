#!/usr/bin/env bash

# Ubuntu Tailscale Installer
# Copyright (c) 2026 Ubuntu Tailscale Installer contributors
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="1.0.1"
readonly DEFAULT_CHANNEL="stable"

# These overrides are intentionally undocumented and exist only so the
# test suite can exercise platform checks without touching the host system.
readonly OS_RELEASE_FILE="${UTI_OS_RELEASE_FILE:-/etc/os-release}"
readonly SYSTEMD_RUNTIME_DIR="${UTI_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"
readonly LOCK_FILE="${UTI_LOCK_FILE:-/run/lock/ubuntu-tailscale-installer.lock}"

CHANNEL="${DEFAULT_CHANNEL}"
ENV_NO_COLOR="${NO_COLOR+x}"
AUTH_KEY_FILE=""
TEMP_AUTH_KEY_FILE=""
HOSTNAME_OVERRIDE=""
ADVERTISE_TAGS=""
OPERATOR_USER=""
LOGIN_MODE="none"
ENABLE_TS_SSH=false
ACCEPT_ROUTES=false
UPGRADE_SYSTEM=false
DRY_RUN=false
DISABLE_COLOR=false
TEMP_DIR=""
BACKEND_STATE=""

RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
BOLD=""
RESET=""

usage() {
    cat <<'EOF'
Ubuntu Tailscale Installer

Usage:
  sudo ./install.sh [options]

Options:
  --login                    Start interactive browser-based authentication.
  --no-login                 Install only (default).
  --auth-key-file PATH       Authenticate unattended using a protected key file.
  --hostname NAME            Set the Tailscale/MagicDNS machine name.
  --advertise-tags TAGS      Comma-separated tags, for example tag:server.
  --ssh                      Enable Tailscale SSH (tailnet policy still applies).
  --accept-routes            Accept routes advertised by subnet routers.
  --operator USER            Allow a local Unix user to operate tailscaled.
  --channel stable|unstable  Select the official package track (default: stable).
  --upgrade-system           Run apt-get upgrade before installing Tailscale.
  --dry-run                  Print planned commands without changing the system.
  --no-color                 Disable ANSI colors.
  -h, --help                 Show this help text.
  -v, --version              Print the installer version.

Environment:
  TS_AUTHKEY                 Alternative to --auth-key-file. A temporary 0600
                             file is created and removed automatically. A file
                             is preferred for production automation.

Examples:
  sudo ./install.sh --login
  sudo ./install.sh --auth-key-file /run/secrets/tailscale-authkey \
    --hostname app-01 --advertise-tags tag:server --ssh
  sudo ./install.sh --dry-run --no-color
EOF
}

init_colors() {
    if [[ "${DISABLE_COLOR}" == true || ! -t 1 || -n "${ENV_NO_COLOR}" ]]; then
        return
    fi

    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
}

log_info() {
    printf '%b[INFO]%b %s\n' "${BLUE}" "${RESET}" "$*"
}

log_success() {
    printf '%b[ OK ]%b %s\n' "${GREEN}" "${RESET}" "$*"
}

log_warn() {
    printf '%b[WARN]%b %s\n' "${YELLOW}" "${RESET}" "$*" >&2
}

log_error() {
    printf '%b[FAIL]%b %s\n' "${RED}" "${RESET}" "$*" >&2
}

die() {
    log_error "$*"
    trap - ERR
    exit 1
}

cleanup() {
    local exit_code=$?

    if [[ -n "${TEMP_AUTH_KEY_FILE}" && -f "${TEMP_AUTH_KEY_FILE}" ]]; then
        rm -f -- "${TEMP_AUTH_KEY_FILE}"
    fi

    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -f -- \
            "${TEMP_DIR}/tailscale-archive-keyring.gpg" \
            "${TEMP_DIR}/tailscale.list" \
            "${TEMP_DIR}/tailscale-authkey" \
            "${TEMP_DIR}/pubring.kbx" \
            "${TEMP_DIR}/trustdb.gpg" \
            "${TEMP_DIR}/random_seed" \
            "${TEMP_DIR}/.gpg-v21-migrated"
        rmdir -- "${TEMP_DIR}" 2>/dev/null || true
    fi

    return "${exit_code}"
}

on_error() {
    local exit_code=$1
    local line_no=$2
    local command_text=$3

    trap - ERR
    log_error "Command failed with exit code ${exit_code} at line ${line_no}."
    log_error "Command: ${command_text}"
    exit "${exit_code}"
}

trap cleanup EXIT
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

shell_join() {
    local output=""
    local argument
    local quoted

    for argument in "$@"; do
        printf -v quoted '%q' "${argument}"
        output+="${output:+ }${quoted}"
    done

    printf '%s' "${output}"
}

run() {
    if [[ "${DRY_RUN}" == true ]]; then
        printf '%b[DRY ]%b %s\n' "${CYAN}" "${RESET}" "$(shell_join "$@")"
        return 0
    fi

    "$@"
}

require_value() {
    local option=$1
    local value=${2-}

    [[ -n "${value}" ]] || die "${option} requires a value."
}

validate_hostname() {
    local hostname=$1
    local label
    local old_ifs="${IFS}"
    local -a labels=()

    (( ${#hostname} >= 1 && ${#hostname} <= 253 )) || return 1
    [[ "${hostname}" != *".."* ]] || return 1

    IFS='.'
    read -r -a labels <<< "${hostname}"
    IFS="${old_ifs}"

    for label in "${labels[@]}"; do
        (( ${#label} >= 1 && ${#label} <= 63 )) || return 1
        [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

validate_tags() {
    local tags=$1

    [[ "${tags}" =~ ^tag:[A-Za-z0-9._-]+(,tag:[A-Za-z0-9._-]+)*$ ]]
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --login)
                LOGIN_MODE="interactive"
                ;;
            --no-login)
                LOGIN_MODE="none"
                ;;
            --auth-key-file)
                require_value "$1" "${2-}"
                AUTH_KEY_FILE=$2
                LOGIN_MODE="auth-key"
                shift
                ;;
            --hostname)
                require_value "$1" "${2-}"
                HOSTNAME_OVERRIDE=$2
                shift
                ;;
            --advertise-tags)
                require_value "$1" "${2-}"
                ADVERTISE_TAGS=$2
                shift
                ;;
            --operator)
                require_value "$1" "${2-}"
                OPERATOR_USER=$2
                shift
                ;;
            --ssh)
                ENABLE_TS_SSH=true
                ;;
            --accept-routes)
                ACCEPT_ROUTES=true
                ;;
            --channel)
                require_value "$1" "${2-}"
                CHANNEL=$2
                shift
                ;;
            --upgrade-system)
                UPGRADE_SYSTEM=true
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --no-color)
                DISABLE_COLOR=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                printf '%s %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
                exit 0
                ;;
            --)
                shift
                (( $# == 0 )) || die "Unexpected positional arguments: $*"
                break
                ;;
            -*)
                die "Unknown option: $1. Run --help for usage."
                ;;
            *)
                die "Unexpected positional argument: $1. Run --help for usage."
                ;;
        esac
        shift
    done

    [[ "${CHANNEL}" == "stable" || "${CHANNEL}" == "unstable" ]] \
        || die "--channel must be either stable or unstable."

    if [[ -n "${HOSTNAME_OVERRIDE}" ]]; then
        validate_hostname "${HOSTNAME_OVERRIDE}" \
            || die "Invalid hostname: ${HOSTNAME_OVERRIDE}"
    fi

    if [[ -n "${ADVERTISE_TAGS}" ]]; then
        validate_tags "${ADVERTISE_TAGS}" \
            || die "Invalid tags. Use a comma-separated value such as tag:server,tag:linux."
    fi

    if [[ -n "${AUTH_KEY_FILE}" && -n "${TS_AUTHKEY:-}" ]]; then
        die "Use either --auth-key-file or TS_AUTHKEY, not both."
    fi

    if [[ -z "${AUTH_KEY_FILE}" && -n "${TS_AUTHKEY:-}" ]]; then
        LOGIN_MODE="auth-key-env"
    fi
}

check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "Run this installer as root, for example: sudo ./install.sh"
    fi

    log_success "Root privileges verified."
}

check_os() {
    local ID=""
    local VERSION_ID=""
    local VERSION_CODENAME=""
    local version_major

    [[ -r "${OS_RELEASE_FILE}" ]] || die "Cannot read ${OS_RELEASE_FILE}."

    # shellcheck disable=SC1090
    source "${OS_RELEASE_FILE}"

    [[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only."
    [[ -n "${VERSION_ID:-}" ]] || die "VERSION_ID is missing from ${OS_RELEASE_FILE}."
    [[ -n "${VERSION_CODENAME:-}" ]] || die "VERSION_CODENAME is missing from ${OS_RELEASE_FILE}."
    [[ "${VERSION_ID}" =~ ^[0-9]{2}\.[0-9]{2}$ ]] \
        || die "Unexpected Ubuntu version format: ${VERSION_ID}"
    [[ "${VERSION_CODENAME}" =~ ^[a-z][a-z0-9-]*$ ]] \
        || die "Unsafe Ubuntu codename: ${VERSION_CODENAME}"

    version_major="${VERSION_ID%%.*}"
    (( 10#${version_major} >= 20 )) \
        || die "Ubuntu ${VERSION_ID} is unsupported; Ubuntu 20.04 or newer is required."

    UBUNTU_VERSION="${VERSION_ID}"
    UBUNTU_CODENAME="${VERSION_CODENAME}"
    readonly UBUNTU_VERSION UBUNTU_CODENAME

    log_success "Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME}) detected."
}

check_systemd() {
    command -v systemctl >/dev/null 2>&1 || die "systemctl is required."
    [[ -d "${SYSTEMD_RUNTIME_DIR}" ]] \
        || die "systemd is not running. This installer targets Ubuntu Server with systemd."

    log_success "systemd is available."
}

require_base_commands() {
    local command_name
    local missing=()

    for command_name in apt-get install id readlink stat; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            missing+=("${command_name}")
        fi
    done

    (( ${#missing[@]} == 0 )) \
        || die "Required commands are missing: ${missing[*]}"
}

check_operator_user() {
    if [[ -z "${OPERATOR_USER}" ]]; then
        return
    fi

    id -- "${OPERATOR_USER}" >/dev/null 2>&1 \
        || die "Local operator user does not exist: ${OPERATOR_USER}"
}

acquire_lock() {
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "Dry run: installer lock is not required."
        return
    fi

    if ! command -v flock >/dev/null 2>&1; then
        log_warn "flock is unavailable; continuing without an installer lock."
        return
    fi

    exec 9>"${LOCK_FILE}"
    flock -n 9 || die "Another installer instance is already running."
}

apt_update() {
    log_info "Refreshing APT package metadata..."
    run apt-get update
}

install_dependencies() {
    log_info "Installing required packages..."
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        jq
    log_success "Required packages are installed."
}

upgrade_system_if_requested() {
    if [[ "${UPGRADE_SYSTEM}" != true ]]; then
        return
    fi

    log_warn "A full package upgrade was explicitly requested."
    run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    log_success "Installed Ubuntu packages were upgraded."
}

download() {
    local url=$1
    local destination=$2

    run curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --proto '=https' \
        --tlsv1.2 \
        --retry 3 \
        --retry-connrefused \
        --connect-timeout 10 \
        --max-time 120 \
        --output "${destination}" \
        "${url}"
}

configure_repository() {
    local base_url="https://pkgs.tailscale.com/${CHANNEL}/ubuntu"
    local key_url="${base_url}/${UBUNTU_CODENAME}.noarmor.gpg"
    local list_url="${base_url}/${UBUNTU_CODENAME}.tailscale-keyring.list"
    local key_file
    local list_file
    local expected_source

    TEMP_DIR="$(mktemp -d -t ubuntu-tailscale-installer.XXXXXX)"
    key_file="${TEMP_DIR}/tailscale-archive-keyring.gpg"
    list_file="${TEMP_DIR}/tailscale.list"
    expected_source="deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] ${base_url} ${UBUNTU_CODENAME} main"

    log_info "Downloading the official Tailscale ${CHANNEL} repository configuration..."
    download "${key_url}" "${key_file}"
    download "${list_url}" "${list_file}"

    if [[ "${DRY_RUN}" != true ]]; then
        [[ -s "${key_file}" ]] || die "Downloaded Tailscale signing key is empty."
        [[ -s "${list_file}" ]] || die "Downloaded Tailscale repository file is empty."
        gpg --batch --quiet --no-options --homedir "${TEMP_DIR}" \
            --show-keys "${key_file}" >/dev/null \
            || die "Downloaded Tailscale signing key is not a valid OpenPGP key."
        grep -Fxq "${expected_source}" "${list_file}" \
            || die "The downloaded repository definition did not match the expected official source."
    fi

    run install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
    run install -m 0644 "${key_file}" /usr/share/keyrings/tailscale-archive-keyring.gpg
    run install -m 0644 "${list_file}" /etc/apt/sources.list.d/tailscale.list
    log_success "Official Tailscale ${CHANNEL} repository configured."
}

install_tailscale() {
    apt_update
    log_info "Installing or updating Tailscale..."
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tailscale
    log_success "Tailscale package is installed."
}

enable_service() {
    log_info "Enabling and starting tailscaled..."
    run systemctl enable --now tailscaled

    if [[ "${DRY_RUN}" == true ]]; then
        return
    fi

    if ! systemctl is-active --quiet tailscaled; then
        systemctl status tailscaled --no-pager || true
        die "tailscaled did not become active."
    fi

    log_success "tailscaled is active."
}

prepare_auth_key() {
    local mode
    local numeric_mode

    case "${LOGIN_MODE}" in
        auth-key)
            [[ -r "${AUTH_KEY_FILE}" ]] || die "Cannot read auth key file: ${AUTH_KEY_FILE}"
            [[ -f "${AUTH_KEY_FILE}" ]] || die "Auth key path is not a regular file: ${AUTH_KEY_FILE}"
            [[ -s "${AUTH_KEY_FILE}" ]] || die "Auth key file is empty: ${AUTH_KEY_FILE}"

            mode="$(stat -c '%a' "${AUTH_KEY_FILE}")"
            numeric_mode=$((8#${mode}))
            if (( numeric_mode & 077 )); then
                die "Auth key file must not be accessible by group or others (use chmod 600)."
            fi
            AUTH_KEY_FILE="$(readlink -f -- "${AUTH_KEY_FILE}")"
            ;;
        auth-key-env)
            TEMP_AUTH_KEY_FILE="${TEMP_DIR}/tailscale-authkey"
            if [[ "${DRY_RUN}" == true ]]; then
                AUTH_KEY_FILE="${TEMP_AUTH_KEY_FILE}"
                LOGIN_MODE="auth-key"
                unset TS_AUTHKEY
                log_warn "TS_AUTHKEY would be copied to a temporary protected file."
                return
            fi
            (
                umask 077
                printf '%s' "${TS_AUTHKEY}" > "${TEMP_AUTH_KEY_FILE}"
            )
            unset TS_AUTHKEY
            AUTH_KEY_FILE="${TEMP_AUTH_KEY_FILE}"
            LOGIN_MODE="auth-key"
            log_warn "TS_AUTHKEY was copied to a temporary protected file; --auth-key-file is safer for automation."
            ;;
        none|interactive)
            ;;
        *)
            die "Internal error: unsupported login mode ${LOGIN_MODE}"
            ;;
    esac
}

read_status_json() {
    tailscale status --json 2>/dev/null || true
}

get_backend_state() {
    local status_json

    status_json="$(read_status_json)"
    if [[ -z "${status_json}" ]]; then
        printf 'Unknown'
        return
    fi

    jq -r '.BackendState // "Unknown"' <<< "${status_json}" 2>/dev/null || printf 'Unknown'
}

build_up_args() {
    UP_ARGS=(tailscale up)

    if [[ "${LOGIN_MODE}" == "auth-key" ]]; then
        UP_ARGS+=("--auth-key=file:${AUTH_KEY_FILE}")
    fi
    if [[ -n "${HOSTNAME_OVERRIDE}" ]]; then
        UP_ARGS+=("--hostname=${HOSTNAME_OVERRIDE}")
    fi
    if [[ -n "${ADVERTISE_TAGS}" ]]; then
        UP_ARGS+=("--advertise-tags=${ADVERTISE_TAGS}")
    fi
    if [[ "${ENABLE_TS_SSH}" == true ]]; then
        UP_ARGS+=("--ssh")
    fi
    if [[ "${ACCEPT_ROUTES}" == true ]]; then
        UP_ARGS+=("--accept-routes")
    fi
}

apply_existing_settings() {
    local set_args=(tailscale set)

    if [[ -n "${HOSTNAME_OVERRIDE}" ]]; then
        set_args+=("--hostname=${HOSTNAME_OVERRIDE}")
    fi
    if [[ "${ENABLE_TS_SSH}" == true ]]; then
        set_args+=("--ssh=true")
    fi
    if [[ "${ACCEPT_ROUTES}" == true ]]; then
        set_args+=("--accept-routes=true")
    fi
    if [[ -n "${OPERATOR_USER}" ]]; then
        set_args+=("--operator=${OPERATOR_USER}")
    fi

    if (( ${#set_args[@]} > 2 )); then
        log_info "Applying requested settings to the connected node..."
        run "${set_args[@]}"
    fi

    if [[ -n "${ADVERTISE_TAGS}" ]]; then
        log_warn "The node is already connected; tags were not changed automatically."
        log_warn "Apply tags with a tagged auth key during initial provisioning or re-authenticate deliberately."
    fi
}

apply_operator_after_login() {
    if [[ -z "${OPERATOR_USER}" ]]; then
        return
    fi

    run tailscale set "--operator=${OPERATOR_USER}"
}

configure_tailscale() {
    BACKEND_STATE="$(get_backend_state)"

    if [[ "${BACKEND_STATE}" == "Running" ]]; then
        log_success "This machine is already connected to a tailnet."
        if [[ "${LOGIN_MODE}" == "auth-key" ]]; then
            log_warn "The supplied auth key was not used because the node is already connected."
        fi
        apply_existing_settings
        return
    fi

    build_up_args

    case "${LOGIN_MODE}" in
        auth-key)
            log_info "Authenticating with the protected auth key file..."
            run "${UP_ARGS[@]}"
            ;;
        interactive)
            log_info "Starting interactive Tailscale authentication..."
            run "${UP_ARGS[@]}"
            ;;
        none)
            log_warn "Tailscale is installed but this machine is not authenticated."
            return
            ;;
        *)
            die "Internal error: unsupported login mode ${LOGIN_MODE}"
            ;;
    esac

    if [[ "${DRY_RUN}" == true ]]; then
        return
    fi

    BACKEND_STATE="$(get_backend_state)"
    if [[ "${BACKEND_STATE}" != "Running" ]]; then
        die "Authentication did not reach the Running state (state: ${BACKEND_STATE})."
    fi

    apply_operator_after_login
    log_success "Tailscale authentication completed."
}

print_summary() {
    local status_json=""
    local version=""
    local ipv4=""
    local ipv6=""
    local dns_name=""
    local ssh_target=""

    if [[ "${DRY_RUN}" == true ]]; then
        printf '\n%bDry run completed; no system changes were made.%b\n' "${BOLD}" "${RESET}"
        return
    fi

    version="$(tailscale version 2>/dev/null | head -n 1 || true)"
    BACKEND_STATE="$(get_backend_state)"

    printf '\n%b============================================================%b\n' "${GREEN}" "${RESET}"
    printf '%b Ubuntu Tailscale Installer completed%b\n' "${BOLD}" "${RESET}"
    printf '%b============================================================%b\n' "${GREEN}" "${RESET}"
    printf 'Tailscale version : %s\n' "${version:-unknown}"
    printf 'Service           : %s\n' "$(systemctl is-active tailscaled 2>/dev/null || printf 'unknown')"
    printf 'Backend state     : %s\n' "${BACKEND_STATE}"

    if [[ "${BACKEND_STATE}" != "Running" ]]; then
        build_up_args
        printf '\nAuthenticate later with:\n\n  sudo %s\n\n' "$(shell_join "${UP_ARGS[@]}")"
        if [[ -n "${OPERATOR_USER}" ]]; then
            printf 'Then configure the local operator:\n\n  sudo tailscale set --operator=%q\n\n' \
                "${OPERATOR_USER}"
        fi
        return
    fi

    status_json="$(read_status_json)"
    ipv4="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
    ipv6="$(tailscale ip -6 2>/dev/null | head -n 1 || true)"
    dns_name="$(jq -r '.Self.DNSName // .Self.HostName // empty' <<< "${status_json}" 2>/dev/null || true)"
    dns_name="${dns_name%.}"
    ssh_target="${dns_name:-${ipv4}}"

    [[ -n "${dns_name}" ]] && printf 'MagicDNS name     : %s\n' "${dns_name}"
    [[ -n "${ipv4}" ]] && printf 'Tailscale IPv4    : %s\n' "${ipv4}"
    [[ -n "${ipv6}" ]] && printf 'Tailscale IPv6    : %s\n' "${ipv6}"

    if [[ -n "${ssh_target}" ]]; then
        printf '\nSSH example:\n\n  ssh <username>@%s\n\n' "${ssh_target}"
    fi
}

main() {
    parse_args "$@"
    init_colors

    printf '\n%bUbuntu Tailscale Installer v%s%b\n\n' "${BOLD}" "${SCRIPT_VERSION}" "${RESET}"

    check_root
    check_os
    check_systemd
    require_base_commands
    check_operator_user
    acquire_lock

    apt_update
    install_dependencies
    upgrade_system_if_requested
    configure_repository
    install_tailscale
    enable_service
    prepare_auth_key
    configure_tailscale
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
