#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly COMMAND_NAME="${0##*/}"
: "${MOCK_LOG:?MOCK_LOG is required}"
: "${MOCK_STATE:?MOCK_STATE is required}"

log_command() {
    local argument

    printf '%s' "${COMMAND_NAME}" >> "${MOCK_LOG}"
    for argument in "$@"; do
        printf ' %q' "${argument}" >> "${MOCK_LOG}"
    done
    printf '\n' >> "${MOCK_LOG}"
}

mock_curl() {
    local destination=""
    local url=""

    while (( $# > 0 )); do
        case "$1" in
            --output)
                destination=$2
                shift 2
                ;;
            https://*)
                url=$1
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -n "${destination}" && -n "${url}" ]]
    mkdir -p "$(dirname -- "${destination}")"

    case "${url}" in
        *.noarmor.gpg)
            printf 'mock OpenPGP key bytes\n' > "${destination}"
            ;;
        *.tailscale-keyring.list)
            printf '%s\n' \
                '# Tailscale packages for ubuntu jammy' \
                'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main' \
                > "${destination}"
            ;;
        *)
            exit 64
            ;;
    esac
}

mock_jq() {
    local query=""
    local payload

    if [[ "${1-}" == "-r" ]]; then
        query=${2-}
    fi
    payload="$(cat)"

    case "${query}" in
        *BackendState*)
            if [[ "${payload}" == *'"Running"'* ]]; then
                printf 'Running\n'
            elif [[ "${payload}" == *'"NeedsLogin"'* ]]; then
                printf 'NeedsLogin\n'
            else
                printf 'Unknown\n'
            fi
            ;;
        *DNSName*)
            printf 'mock-node.example.ts.net.\n'
            ;;
        *)
            exit 64
            ;;
    esac
}

mock_tailscale() {
    local auth_file=""
    local argument
    local state="NeedsLogin"

    [[ -r "${MOCK_STATE}" ]] && state="$(< "${MOCK_STATE}")"

    case "${1-}" in
        status)
            printf '{"BackendState":"%s","Self":{"DNSName":"mock-node.example.ts.net."}}\n' \
                "${state}"
            ;;
        up)
            for argument in "$@"; do
                case "${argument}" in
                    --auth-key=file:*)
                        auth_file="${argument#--auth-key=file:}"
                        ;;
                    *)
                        ;;
                esac
            done
            [[ -n "${auth_file}" && -r "${auth_file}" ]]
            [[ "$(< "${auth_file}")" == "${EXPECTED_SECRET:?EXPECTED_SECRET is required}" ]]
            printf 'Running\n' > "${MOCK_STATE}"
            ;;
        set)
            ;;
        version)
            printf '1.98.0\n'
            ;;
        ip)
            case "${2-}" in
                -4)
                    printf '100.64.0.10\n'
                    ;;
                -6)
                    printf 'fd7a:115c:a1e0::10\n'
                    ;;
                *)
                    exit 64
                    ;;
            esac
            ;;
        *)
            exit 64
            ;;
    esac
}

log_command "$@"

case "${COMMAND_NAME}" in
    apt-get|flock|gpg|install)
        ;;
    curl)
        mock_curl "$@"
        ;;
    id)
        if [[ "${1-}" == "-u" ]]; then
            printf '0\n'
        else
            /usr/bin/id "$@"
        fi
        ;;
    jq)
        mock_jq "$@"
        ;;
    systemctl)
        case "${1-}" in
            is-active)
                [[ "${2-}" == "--quiet" ]] || printf 'active\n'
                ;;
            enable|status)
                ;;
            *)
                exit 64
                ;;
        esac
        ;;
    tailscale)
        mock_tailscale "$@"
        ;;
    *)
        exit 64
        ;;
esac
