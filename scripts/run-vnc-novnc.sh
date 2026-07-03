#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/dingp/vnc-novnc-container:debian-12-main}"
CONTAINER_NOVNC_PORT="${NOVNC_PORT:-6080}"
HOST_NOVNC_ADDR="${HOST_NOVNC_ADDR:-127.0.0.1}"
HOST_NOVNC_PORT="${HOST_NOVNC_PORT:-}"
JUPYTER_PROXY_BASE_URL="${JUPYTER_PROXY_BASE_URL:-https://jupyter.nersc.gov}"
JUPYTER_PROXY_HOST="${JUPYTER_PROXY_HOST:-jupyter.nersc.gov}"
JUPYTER_PROXY_HTTPS_PORT="${JUPYTER_PROXY_HTTPS_PORT:-443}"
JUPYTER_PROXY_PREFIX="${JUPYTER_PROXY_PREFIX:-${JUPYTERHUB_SERVICE_PREFIX:-}}"
JUPYTER_PROXY_USER="${JUPYTER_PROXY_USER:-${USER:-}}"
JUPYTER_PROXY_SERVER="${JUPYTER_PROXY_SERVER:-}"
VNC_PORT="${VNC_PORT:-5901}"
VNC_HOST_ADDR="${VNC_HOST_ADDR:-127.0.0.1}"
VNC_HOST_PORT="${VNC_HOST_PORT:-$VNC_PORT}"
EXPOSE_VNC="${EXPOSE_VNC:-0}"
VNC_PASSWORD_LENGTH="${VNC_PASSWORD_LENGTH:-8}"
SLURM="${SLURM:-${VNC_NOVNC_SLURM:-0}}"
SCLI_SOCKET="${SCLI_SOCKET:-}"
SCLI_SERVER="${SCLI_SERVER:-${HOME}/bin/scli-server}"
SCLI_SERVER_LOG="${SCLI_SERVER_LOG:-/tmp/vnc-novnc-scli-server-${USER:-$(id -u)}.log}"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --slurm)
            SLURM=1
            shift
            ;;
        --no-slurm)
            SLURM=0
            shift
            ;;
        --slurm-socket)
            SCLI_SOCKET="${2:?--slurm-socket requires a value}"
            shift 2
            ;;
        --slurm-server)
            SCLI_SERVER="${2:?--slurm-server requires a value}"
            shift 2
            ;;
        --slurm-server-log)
            SCLI_SERVER_LOG="${2:?--slurm-server-log requires a value}"
            shift 2
            ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/run-vnc-novnc.sh [--slurm] [--slurm-socket PATH]
                                [--slurm-server PATH] [--slurm-server-log PATH]

Legacy shell helper for running the default VNC/noVNC image.
Prefer scripts/run-vnc-novnc.py for full option support.
EOF
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

urlencode() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$1" <<'PY'
import sys
import urllib.parse

print(urllib.parse.quote(sys.argv[1], safe=""), end="")
PY
        return
    fi

    local input="$1"
    local output=""
    local i char hex

    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_-]) output+="${char}" ;;
            *) printf -v hex '%%%02X' "'${char}"; output+="${hex}" ;;
        esac
    done

    printf '%s' "${output}"
}

jupyter_proxy_url() {
    local prefix="${JUPYTER_PROXY_PREFIX}"
    local proxy_path encoded_path base_url

    if [[ -z "${prefix}" ]]; then
        if [[ -z "${JUPYTER_PROXY_USER}" || -z "${JUPYTER_PROXY_SERVER}" ]]; then
            return 1
        fi
        prefix="user/${JUPYTER_PROXY_USER}/${JUPYTER_PROXY_SERVER}"
    fi

    prefix="${prefix#/}"
    prefix="${prefix%/}"
    proxy_path="${prefix}/proxy/${HOST_NOVNC_PORT}"
    encoded_path="$(urlencode "${proxy_path}")"
    base_url="${JUPYTER_PROXY_BASE_URL%/}"

    printf '%s/%s/vnc.html?port=%s&host=%s&path=%s' \
        "${base_url}" "${proxy_path}" "${JUPYTER_PROXY_HTTPS_PORT}" "${JUPYTER_PROXY_HOST}" "${encoded_path}"
}

random_password() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - "${VNC_PASSWORD_LENGTH}" <<'PY'
import secrets
import string
import sys

length = int(sys.argv[1])
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(length)), end="")
PY
        return
    fi

    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "${VNC_PASSWORD_LENGTH}" | cut -c "1-${VNC_PASSWORD_LENGTH}"
        return
    fi

    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${VNC_PASSWORD_LENGTH}"
}

random_port() {
    if command -v shuf >/dev/null 2>&1; then
        shuf -i 49152-60999 -n 1
        return
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY'
import secrets

print(secrets.randbelow(11848) + 49152)
PY
        return
    fi

    printf '%s\n' "$((49152 + RANDOM % 11848))"
}

default_scli_socket() {
    if [[ -n "${SCLI_SOCKET}" ]]; then
        printf '%s\n' "${SCLI_SOCKET}"
        return
    fi
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        printf '%s/scli.sock\n' "${XDG_RUNTIME_DIR}"
        return
    fi
    printf '%s/.local/run/scli.sock\n' "${HOME:-}"
}

start_scli_server() {
    if [[ -S "${SCLI_SOCKET}" ]]; then
        return 0
    fi

    if [[ ! -x "${SCLI_SERVER}" ]]; then
        printf 'scli-server is not executable: %s\n' "${SCLI_SERVER}" >&2
        printf 'Install it with scripts/install-jupyter-kernel.sh for a Slurm-enabled kernel or set SCLI_SERVER.\n' >&2
        exit 1
    fi

    mkdir -p "$(dirname "${SCLI_SOCKET}")"
    chmod 700 "$(dirname "${SCLI_SOCKET}")" 2>/dev/null || true
    mkdir -p "$(dirname "${SCLI_SERVER_LOG}")"

    printf 'Starting scli-server: %s --socket %s\n' "${SCLI_SERVER}" "${SCLI_SOCKET}" >&2
    "${SCLI_SERVER}" --socket "${SCLI_SOCKET}" >>"${SCLI_SERVER_LOG}" 2>&1 &

    local i=0
    while [[ "${i}" -lt 50 ]]; do
        if [[ -S "${SCLI_SOCKET}" ]]; then
            printf 'scli-server log: %s\n' "${SCLI_SERVER_LOG}" >&2
            return 0
        fi
        i="$((i + 1))"
        sleep 0.1
    done

    printf 'Timed out waiting for scli-server socket: %s\n' "${SCLI_SOCKET}" >&2
    printf 'See log: %s\n' "${SCLI_SERVER_LOG}" >&2
    exit 1
}

if [[ -z "${HOST_NOVNC_PORT}" ]]; then
    HOST_NOVNC_PORT="$(random_port)"
fi

tmpdir="$(mktemp -d)"
password_file="${tmpdir}/vnc-password"
cleanup() {
    rm -rf "${tmpdir}"
}
trap cleanup EXIT

vnc_password="$(random_password)"
printf '%s\n' "${vnc_password}" > "${password_file}"
chmod 0600 "${password_file}"

run_args=(
    run
    --rm
    -p "${HOST_NOVNC_ADDR}:${HOST_NOVNC_PORT}:${CONTAINER_NOVNC_PORT}"
    -v "${password_file}:/run/secrets/vnc-password:ro"
    -e "VNC_PASSWORD_PLAIN_FILE=/run/secrets/vnc-password"
    -e "VNC_PASSWORD_FILE=/tmp/vnc-auth/passwd"
    -e "NOVNC_PORT=${CONTAINER_NOVNC_PORT}"
    -e "VNC_PORT=${VNC_PORT}"
)

case "${EXPOSE_VNC,,}" in
    1|true|yes|y|on)
        run_args+=( -p "${VNC_HOST_ADDR}:${VNC_HOST_PORT}:${VNC_PORT}" )
        ;;
esac

case "${SLURM,,}" in
    1|true|yes|y|on)
        SCLI_SOCKET="$(default_scli_socket)"
        start_scli_server
        run_args+=( -v "${SCLI_SOCKET}:${SCLI_SOCKET}:rw" -e "SCLI_SOCKET=${SCLI_SOCKET}" )
        ;;
esac

printf 'Image: %s\n' "${IMAGE}"
if access_url="$(jupyter_proxy_url)"; then
    printf 'noVNC: %s\n' "${access_url}"
else
    printf 'noVNC: http://%s:%s/vnc.html\n' "${HOST_NOVNC_ADDR}" "${HOST_NOVNC_PORT}"
    printf 'Set JUPYTER_PROXY_PREFIX, or set JUPYTER_PROXY_USER and JUPYTER_PROXY_SERVER, to print a jupyter.nersc.gov proxy URL.\n'
fi
printf 'One-time VNC password: %s\n' "${vnc_password}"
if [[ "${EXPOSE_VNC,,}" =~ ^(1|true|yes|y|on)$ ]]; then
    printf 'VNC: %s:%s\n' "${VNC_HOST_ADDR}" "${VNC_HOST_PORT}"
else
    printf 'VNC server port is not exposed on the host.\n'
fi
printf '\n'

exec podman-hpc "${run_args[@]}" "${IMAGE}"
