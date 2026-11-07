#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main}"
CONTAINER_NOVNC_PORT="${NOVNC_PORT:-6080}"
HOST_NOVNC_ADDR="${HOST_NOVNC_ADDR:-127.0.0.1}"
HOST_NOVNC_PORT="${HOST_NOVNC_PORT:-}"
NOVNC_TRANSPORT="${VNC_NOVNC_TRANSPORT:-${NOVNC_TRANSPORT:-tcp}}"
NOVNC_UNIX_SOCKET="${NOVNC_UNIX_SOCKET:-}"
JUPYTER_PROXY_SERVICE="${JUPYTER_PROXY_SERVICE:-vnc-novnc}"
JUPYTER_PROXY_BASE_URL="${JUPYTER_PROXY_BASE_URL:-https://jupyter.nersc.gov}"
JUPYTER_PROXY_HOST="${JUPYTER_PROXY_HOST:-jupyter.nersc.gov}"
JUPYTER_PROXY_HTTPS_PORT="${JUPYTER_PROXY_HTTPS_PORT:-443}"
JUPYTER_PROXY_PREFIX="${JUPYTER_PROXY_PREFIX:-${JUPYTERHUB_SERVICE_PREFIX:-}}"
JUPYTER_PROXY_USER="${JUPYTER_PROXY_USER:-${USER:-}}"
JUPYTER_PROXY_SERVER="${JUPYTER_PROXY_SERVER:-}"
VNC_PORT="${VNC_PORT:-5901}"
DISPLAY_MODE="${VNC_NOVNC_DISPLAY_MODE:-${DISPLAY_MODE:-default}}"
VNC_GEOMETRY="${VNC_GEOMETRY:-}"
VNC_DEPTH="${VNC_DEPTH:-}"
VNC_HOST_ADDR="${VNC_HOST_ADDR:-127.0.0.1}"
VNC_HOST_PORT="${VNC_HOST_PORT:-$VNC_PORT}"
EXPOSE_VNC="${EXPOSE_VNC:-0}"
GPU="${GPU:-${VNC_NOVNC_GPU:-0}}"
VNC_PASSWORD_LENGTH="${VNC_PASSWORD_LENGTH:-8}"
SLURM="${SLURM:-${VNC_NOVNC_SLURM:-0}}"
SCLI_SOCKET="${SCLI_SOCKET:-}"
SCLI_SERVER="${SCLI_SERVER:-${HOME}/bin/scli-server}"
SCLI_SERVER_LOG="${SCLI_SERVER_LOG:-/tmp/vnc-novnc-scli-server-${USER:-$(id -u)}.log}"
SSH_PROXY="${SSH_PROXY:-${VNC_NOVNC_SSH_PROXY:-0}}"
SSH_PROXY_SOCKET="${SSH_PROXY_SOCKET:-}"
SSH_PROXY_SERVER="${SSH_PROXY_SERVER:-${HOME}/bin/ssh-proxy-server}"
SSH_PROXY_SERVER_LOG="${SSH_PROXY_SERVER_LOG:-/tmp/vnc-novnc-ssh-proxy-server-${USER:-$(id -u)}.log}"

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
        --ssh-proxy)
            SSH_PROXY=1
            shift
            ;;
        --no-ssh-proxy)
            SSH_PROXY=0
            shift
            ;;
        --ssh-proxy-socket)
            SSH_PROXY_SOCKET="${2:?--ssh-proxy-socket requires a value}"
            shift 2
            ;;
        --ssh-proxy-server)
            SSH_PROXY_SERVER="${2:?--ssh-proxy-server requires a value}"
            shift 2
            ;;
        --ssh-proxy-server-log)
            SSH_PROXY_SERVER_LOG="${2:?--ssh-proxy-server-log requires a value}"
            shift 2
            ;;
        --display-mode)
            DISPLAY_MODE="${2:?--display-mode requires a value}"
            shift 2
            ;;
        --novnc-transport)
            NOVNC_TRANSPORT="${2:?--novnc-transport requires a value}"
            shift 2
            ;;
        --novnc-socket)
            NOVNC_UNIX_SOCKET="${2:?--novnc-socket requires a value}"
            shift 2
            ;;
        --jupyter-proxy-service)
            JUPYTER_PROXY_SERVICE="${2:?--jupyter-proxy-service requires a value}"
            shift 2
            ;;
        --gpu)
            GPU=1
            shift
            ;;
        --no-gpu)
            GPU=0
            shift
            ;;
        --vnc-geometry)
            VNC_GEOMETRY="${2:?--vnc-geometry requires a value}"
            shift 2
            ;;
        --vnc-depth)
            VNC_DEPTH="${2:?--vnc-depth requires a value}"
            shift 2
            ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/run-vnc-novnc.sh [--slurm] [--slurm-socket PATH]
                                [--slurm-server PATH] [--slurm-server-log PATH]
                                [--ssh-proxy] [--ssh-proxy-socket PATH]
                                [--ssh-proxy-server PATH] [--ssh-proxy-server-log PATH]
                                [--display-mode default|1080p|fhd|high]
                                [--novnc-transport tcp|unix] [--novnc-socket PATH]
                                [--jupyter-proxy-service NAME]
                                [--gpu] [--no-gpu]
                                [--vnc-geometry WIDTHxHEIGHT] [--vnc-depth DEPTH]

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

case "${DISPLAY_MODE,,}" in
    default|"")
        ;;
    1080p|fhd|high)
        VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
        VNC_DEPTH="${VNC_DEPTH:-32}"
        ;;
    *)
        printf 'Unsupported display mode: %s\n' "${DISPLAY_MODE}" >&2
        exit 2
        ;;
esac

case "${NOVNC_TRANSPORT,,}" in
    tcp|unix)
        NOVNC_TRANSPORT="${NOVNC_TRANSPORT,,}"
        ;;
    *)
        printf 'Unsupported noVNC transport: %s\n' "${NOVNC_TRANSPORT}" >&2
        exit 2
        ;;
esac

case "${JUPYTER_PROXY_SERVICE}" in
    ""|*/*)
        printf 'Jupyter proxy service name must be non-empty and must not contain "/": %s\n' "${JUPYTER_PROXY_SERVICE}" >&2
        exit 2
        ;;
esac

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
    local proxy_path encoded_path base_url ws_path

    if [[ -z "${prefix}" ]]; then
        if [[ -z "${JUPYTER_PROXY_USER}" || -z "${JUPYTER_PROXY_SERVER}" ]]; then
            return 1
        fi
        prefix="user/${JUPYTER_PROXY_USER}/${JUPYTER_PROXY_SERVER}"
    fi

    prefix="${prefix#/}"
    prefix="${prefix%/}"
    proxy_path="${prefix}/proxy/${HOST_NOVNC_PORT}"
    ws_path="${proxy_path}/websockify"
    encoded_path="$(urlencode "${ws_path}")"
    base_url="${JUPYTER_PROXY_BASE_URL%/}"

    printf '%s/%s/vnc.html?port=%s&host=%s&path=%s' \
        "${base_url}" "${proxy_path}" "${JUPYTER_PROXY_HTTPS_PORT}" "${JUPYTER_PROXY_HOST}" "${encoded_path}"
}

jupyter_proxy_service_url() {
    local prefix="${JUPYTER_PROXY_PREFIX}"
    local proxy_path encoded_path base_url service ws_path

    if [[ -z "${prefix}" ]]; then
        if [[ -z "${JUPYTER_PROXY_USER}" || -z "${JUPYTER_PROXY_SERVER}" ]]; then
            return 1
        fi
        prefix="user/${JUPYTER_PROXY_USER}/${JUPYTER_PROXY_SERVER}"
    fi

    prefix="${prefix#/}"
    prefix="${prefix%/}"
    service="${JUPYTER_PROXY_SERVICE#/}"
    service="${service%/}"
    proxy_path="${prefix}/${service}"
    ws_path="${proxy_path}/websockify"
    encoded_path="$(urlencode "${ws_path}")"
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

add_volume_if_exists() {
    local host_path="$1"
    local container_path="$2"
    local mode="${3:-}"
    local volume

    [[ -e "${host_path}" ]] || return 0
    volume="${host_path}:${container_path}"
    if [[ -n "${mode}" ]]; then
        volume="${volume}:${mode}"
    fi
    run_args+=( -v "${volume}" )
}

add_env_if_present() {
    local name="$1"
    if [[ -v ${name} ]]; then
        run_args+=( -e "${name}" )
    fi
}

add_nersc_programming_environment_args() {
    add_env_if_present HOME
    add_env_if_present MODULEPATH
    add_env_if_present MODULEPATH_ROOT
    add_env_if_present MODULESHOME
    add_env_if_present PE_ENV
    add_env_if_present LMOD_FAMILY_MPI
    add_env_if_present LMOD_FAMILY_CUDATOOLKIT
    add_env_if_present LMOD_FAMILY_CUDATOOLKIT_VERSION

    add_volume_if_exists /global /global
    if [[ -n "${SCRATCH:-}" ]]; then
        add_volume_if_exists "${SCRATCH}" "${SCRATCH}" rw
    fi
    if [[ -n "${CFS:-}" ]]; then
        add_volume_if_exists "${CFS}" "${CFS}" rw
    fi
    add_volume_if_exists /opt /opt
    add_volume_if_exists /etc/cray-pe.d /etc/cray-pe.d ro
    add_volume_if_exists /etc/clustername /etc/clustername ro
    add_volume_if_exists /etc/environment /etc/environment ro
}

default_scli_socket() {
    if [[ -n "${SCLI_SOCKET}" ]]; then
        printf '%s\n' "${SCLI_SOCKET}"
        return
    fi
    local host suffix
    host="$(hostname 2>/dev/null || printf unknown)"
    suffix="${host//[^A-Za-z0-9_.-]/_}"
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        printf '%s/scli-%s.sock\n' "${XDG_RUNTIME_DIR}" "${suffix}"
        return
    fi
    printf '/tmp/vnc-novnc-%s/scli-%s.sock\n' "$(id -u)" "${suffix}"
}

default_ssh_proxy_socket() {
    if [[ -n "${SSH_PROXY_SOCKET}" ]]; then
        printf '%s\n' "${SSH_PROXY_SOCKET}"
        return
    fi
    local host suffix
    host="$(hostname 2>/dev/null || printf unknown)"
    suffix="${host//[^A-Za-z0-9_.-]/_}"
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        printf '%s/ssh-proxy-%s.sock\n' "${XDG_RUNTIME_DIR}" "${suffix}"
        return
    fi
    printf '/tmp/vnc-novnc-%s/ssh-proxy-%s.sock\n' "$(id -u)" "${suffix}"
}

default_novnc_socket() {
    if [[ -n "${NOVNC_UNIX_SOCKET}" ]]; then
        printf '%s\n' "${NOVNC_UNIX_SOCKET}"
        return
    fi
    local host suffix
    host="$(hostname 2>/dev/null || printf unknown)"
    suffix="${host//[^A-Za-z0-9_.-]/_}"
    printf '/tmp/vnc-novnc-%s/novnc-%s.sock\n' "$(id -u)" "${suffix}"
}

socket_is_live() {
    [[ -S "$1" ]] || return 1
    python3 - "$1" <<'PY' >/dev/null 2>&1
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(0.5)
try:
    sock.connect(sys.argv[1])
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
}

prepare_novnc_socket() {
    if socket_is_live "${NOVNC_UNIX_SOCKET}"; then
        printf 'noVNC Unix socket is already live: %s\n' "${NOVNC_UNIX_SOCKET}" >&2
        printf 'Stop the existing noVNC kernel/container or use --novnc-transport tcp.\n' >&2
        exit 1
    fi
    remove_stale_socket "${NOVNC_UNIX_SOCKET}"
    mkdir -p "$(dirname "${NOVNC_UNIX_SOCKET}")"
    chmod 700 "$(dirname "${NOVNC_UNIX_SOCKET}")" 2>/dev/null || true
}

remove_stale_socket() {
    if [[ -S "$1" ]] && ! socket_is_live "$1"; then
        rm -f "$1"
    fi
}

start_scli_server() {
    if socket_is_live "${SCLI_SOCKET}"; then
        return 0
    fi
    remove_stale_socket "${SCLI_SOCKET}"

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

start_ssh_proxy_server() {
    if socket_is_live "${SSH_PROXY_SOCKET}"; then
        return 0
    fi
    remove_stale_socket "${SSH_PROXY_SOCKET}"

    if [[ ! -x "${SSH_PROXY_SERVER}" ]]; then
        printf 'ssh-proxy-server is not executable: %s\n' "${SSH_PROXY_SERVER}" >&2
        printf 'Install it with scripts/install-jupyter-kernel.sh for an SSH proxy-enabled kernel or set SSH_PROXY_SERVER.\n' >&2
        exit 1
    fi

    mkdir -p "$(dirname "${SSH_PROXY_SOCKET}")"
    chmod 700 "$(dirname "${SSH_PROXY_SOCKET}")" 2>/dev/null || true
    mkdir -p "$(dirname "${SSH_PROXY_SERVER_LOG}")"

    printf 'Starting ssh-proxy-server: %s --socket %s\n' "${SSH_PROXY_SERVER}" "${SSH_PROXY_SOCKET}" >&2
    "${SSH_PROXY_SERVER}" --socket "${SSH_PROXY_SOCKET}" >>"${SSH_PROXY_SERVER_LOG}" 2>&1 &

    local i=0
    while [[ "${i}" -lt 50 ]]; do
        if [[ -S "${SSH_PROXY_SOCKET}" ]]; then
            printf 'ssh-proxy-server log: %s\n' "${SSH_PROXY_SERVER_LOG}" >&2
            return 0
        fi
        i="$((i + 1))"
        sleep 0.1
    done

    printf 'Timed out waiting for ssh-proxy-server socket: %s\n' "${SSH_PROXY_SOCKET}" >&2
    printf 'See log: %s\n' "${SSH_PROXY_SERVER_LOG}" >&2
    exit 1
}

if [[ "${NOVNC_TRANSPORT}" == "tcp" && -z "${HOST_NOVNC_PORT}" ]]; then
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
    -v "${password_file}:/run/secrets/vnc-password:ro"
    -e "VNC_PASSWORD_PLAIN_FILE=/run/secrets/vnc-password"
    -e "VNC_PASSWORD_FILE=/tmp/vnc-auth/passwd"
    -e "NOVNC_PORT=${CONTAINER_NOVNC_PORT}"
    -e "VNC_PORT=${VNC_PORT}"
)

if [[ "${NOVNC_TRANSPORT}" == "tcp" ]]; then
    run_args+=( -p "${HOST_NOVNC_ADDR}:${HOST_NOVNC_PORT}:${CONTAINER_NOVNC_PORT}" )
else
    NOVNC_UNIX_SOCKET="$(default_novnc_socket)"
    prepare_novnc_socket
    run_args+=( -v "$(dirname "${NOVNC_UNIX_SOCKET}"):$(dirname "${NOVNC_UNIX_SOCKET}"):rw" )
    run_args+=( -e "NOVNC_UNIX_SOCKET=${NOVNC_UNIX_SOCKET}" )
fi

if [[ -n "${VNC_GEOMETRY}" ]]; then
    run_args+=( -e "VNC_GEOMETRY=${VNC_GEOMETRY}" )
fi
if [[ -n "${VNC_DEPTH}" ]]; then
    run_args+=( -e "VNC_DEPTH=${VNC_DEPTH}" )
fi

case "${EXPOSE_VNC,,}" in
    1|true|yes|y|on)
        run_args+=( -p "${VNC_HOST_ADDR}:${VNC_HOST_PORT}:${VNC_PORT}" )
        ;;
esac

case "${GPU,,}" in
    1|true|yes|y|on)
        run_args+=( --gpu )
        ;;
esac

case "${SLURM,,}" in
    1|true|yes|y|on)
        add_nersc_programming_environment_args
        SCLI_SOCKET="$(default_scli_socket)"
        start_scli_server
        run_args+=( -v "${SCLI_SOCKET}:${SCLI_SOCKET}:rw" -e "SCLI_SOCKET=${SCLI_SOCKET}" )
        ;;
esac

case "${SSH_PROXY,,}" in
    1|true|yes|y|on)
        SSH_PROXY_SOCKET="$(default_ssh_proxy_socket)"
        start_ssh_proxy_server
        run_args+=( -v "${SSH_PROXY_SOCKET}:${SSH_PROXY_SOCKET}:rw" -e "SSH_PROXY_SOCKET=${SSH_PROXY_SOCKET}" )
        ;;
esac

printf 'Image: %s\n' "${IMAGE}"
if [[ "${NOVNC_TRANSPORT}" == "unix" ]]; then
    if access_url="$(jupyter_proxy_service_url)"; then
        printf 'noVNC: %s\n' "${access_url}"
    else
        printf 'noVNC: /%s/vnc.html\n' "${JUPYTER_PROXY_SERVICE}"
        printf 'Set JUPYTER_PROXY_PREFIX, or set JUPYTER_PROXY_USER and JUPYTER_PROXY_SERVER, to print a full jupyter.nersc.gov named proxy URL.\n'
    fi
elif access_url="$(jupyter_proxy_url)"; then
    printf 'noVNC: %s\n' "${access_url}"
else
    printf 'noVNC: http://%s:%s/vnc.html\n' "${HOST_NOVNC_ADDR}" "${HOST_NOVNC_PORT}"
    printf 'Set JUPYTER_PROXY_PREFIX, or set JUPYTER_PROXY_USER and JUPYTER_PROXY_SERVER, to print a jupyter.nersc.gov proxy URL.\n'
fi
printf 'One-time VNC password: %s\n' "${vnc_password}"
if [[ "${NOVNC_TRANSPORT}" == "unix" ]]; then
    printf 'noVNC is exposed through a user-private Unix socket, not a host TCP port.\n'
elif [[ "${EXPOSE_VNC,,}" =~ ^(1|true|yes|y|on)$ ]]; then
    printf 'VNC: %s:%s\n' "${VNC_HOST_ADDR}" "${VNC_HOST_PORT}"
else
    printf 'VNC server port is not exposed on the host.\n'
fi
printf '\n'

exec podman-hpc "${run_args[@]}" "${IMAGE}"
