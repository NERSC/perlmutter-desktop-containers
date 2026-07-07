FROM docker.io/library/golang:1.23-bookworm AS slurm-cli-builder

ARG TARGETOS=linux
ARG TARGETARCH

WORKDIR /src
COPY container/slurm-cli-proxy/go.mod container/slurm-cli-proxy/go.sum ./
RUN go mod download
COPY container/slurm-cli-proxy/ ./
RUN \
    set -eu; \
    arch="${TARGETARCH:-amd64}"; \
    GOOS="${TARGETOS}" GOARCH="${arch}" CGO_ENABLED=0 \
        go build -trimpath -ldflags="-s -w" -o /out/scli ./cmd/scli; \
    GOOS="${TARGETOS}" GOARCH="${arch}" CGO_ENABLED=0 \
        go build -trimpath -ldflags="-s -w" -o /out/ssh-proxy ./cmd/ssh-proxy

FROM opensuse/leap:15.6

ARG TARGETARCH
ARG SSHPROXY_VERSION=2.1.2
ARG SSHPROXY_ARCH
ARG PARAVIEW_VERSION=5.13.3

RUN \
    set -eu; \
    case "${SSHPROXY_ARCH:-${TARGETARCH:-amd64}}" in \
        amd64|x86_64|linux-x86_64) sshproxy_arch=linux-x86_64 ;; \
        arm64|aarch64|linux-aarch64) sshproxy_arch=linux-aarch64 ;; \
        *) echo "Unsupported sshproxy architecture: ${SSHPROXY_ARCH:-${TARGETARCH:-}}" >&2; exit 1 ;; \
    esac; \
    sshproxy_url="https://portal.nersc.gov/cfs/mfa/sshproxy-${SSHPROXY_VERSION}-${sshproxy_arch}.tar.gz"; \
    zypper --non-interactive refresh && \
    zypper --non-interactive install --no-recommends \
        ca-certificates \
        bash \
        chromium \
        curl \
        dbus-1 \
        dbus-1-x11 \
        dejavu-fonts \
        file \
        findutils \
        fontconfig \
        gcc \
        gcc7 \
        gcc7-c++ \
        gcc7-fortran \
        gcc12 \
        gcc12-c++ \
        gcc12-fortran \
        gcc13 \
        gcc13-c++ \
        gcc13-fortran \
        gcc14 \
        gcc14-c++ \
        gcc14-fortran \
        gdb \
        git \
        gzip \
        iproute2 \
        less \
        liberation-fonts \
        lua-lmod \
        make \
        net-tools \
        nfs-client \
        nmap \
        noto-coloremoji-fonts \
        noto-sans-fonts \
        noto-serif-fonts \
        novnc \
        openssh-clients \
        patterns-xfce-xfce \
        procps \
        python3 \
        python3-cryptography \
        python3-ipykernel \
        python3-PyJWT \
        python3-websockify \
        tar \
        thunar \
        tigervnc \
        tmux \
        tcpdump \
        vim \
        wget \
        which \
        wireshark \
        xauth \
        xorg-x11-Xvnc \
        xset \
        xsetroot \
        xterm \
        xfce4-session \
        xfce4-terminal \
        zlib-devel && \
    ln -sf /usr/lib/vncserver /usr/local/bin/vncserver && \
    mkdir -p /etc/X11/xinit && \
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$#" -gt 0 ]; then' \
        '    exec "$@"' \
        'fi' \
        'exec startxfce4' \
        > /etc/X11/xinit/Xsession && \
    chmod 0755 /etc/X11/xinit/Xsession && \
    curl --fail --location --show-error \
        --retry 5 --retry-all-errors --retry-delay 5 --retry-max-time 300 --connect-timeout 30 \
        "${sshproxy_url}" --output /tmp/sshproxy.tar.gz && \
    tar -xzf /tmp/sshproxy.tar.gz -C /usr/local/bin sshproxy && \
    chmod 0755 /usr/local/bin/sshproxy && \
    mkdir -p /etc/vnc-novnc && \
    sed -i 's#^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*#\1/bin/bash#' /etc/passwd && \
    if [ ! -d /usr/share/novnc ] && [ -d /usr/share/noVNC ]; then \
        ln -s /usr/share/noVNC /usr/share/novnc; \
    fi && \
    zypper --non-interactive clean --all && \
    rm -rf /tmp/sshproxy.tar.gz /var/cache/zypp/*

# Add OpenGL runtime libraries and diagnostics used by Nsight GUI tools in noVNC.
RUN \
    set -eu; \
    zypper --non-interactive refresh && \
    zypper --non-interactive install --no-recommends \
        Mesa-demo-x \
        Mesa-dri \
        Mesa-gallium \
        Mesa-libEGL1 \
        Mesa-libGL1 \
        libgthread-2_0-0 \
        libxcb-xinerama0 && \
    zypper --non-interactive clean --all && \
    rm -rf /var/cache/zypp/*

# Install the official ParaView binary under /usr/local because /opt may be a
# host bind mount in NERSC programming-environment containers.
RUN \
    set -eu; \
    case "${TARGETARCH:-amd64}" in \
        amd64|x86_64) paraview_arch=x86_64 ;; \
        *) echo "Unsupported ParaView architecture: ${TARGETARCH:-}" >&2; exit 1 ;; \
    esac; \
    paraview_name="ParaView-${PARAVIEW_VERSION}-MPI-Linux-Python3.10-${paraview_arch}"; \
    paraview_url="https://www.paraview.org/files/v5.13/${paraview_name}.tar.gz"; \
    curl --fail --location --show-error \
        --retry 5 --retry-all-errors --retry-delay 5 --retry-max-time 1800 --connect-timeout 30 \
        "${paraview_url}" --output /tmp/paraview.tar.gz && \
    mkdir -p "/usr/local/paraview-${PARAVIEW_VERSION}" && \
    tar -xzf /tmp/paraview.tar.gz -C "/usr/local/paraview-${PARAVIEW_VERSION}" --strip-components=1 && \
    ln -sfn "/usr/local/paraview-${PARAVIEW_VERSION}" /usr/local/paraview && \
    for exe in paraview pvpython pvserver pvbatch pvdataserver pvrenderserver; do \
        ln -sfn "/usr/local/paraview/bin/${exe}" "/usr/local/bin/${exe}"; \
    done && \
    rm -f /tmp/paraview.tar.gz

# Prefer the host NERSC/Cray Lmod stack when /opt is mounted, and restore the
# same default programming environment modules used by NERSC login shells.
RUN \
    set -eu; \
    printf '%s\n' \
        '[ -n "${BASH_VERSION:-}" ] || return 0' \
        '' \
        'vnc_novnc_nersc_lmod_reset() {' \
        '    unset LMOD_CMD LMOD_DIR LMOD_ROOT LMOD_PKG LMOD_SETTARG_CMD' \
        '    unset BASH_ENV' \
        '    unset MODULESHOME MODULEPATH MODULEPATH_ROOT' \
        '    unset LOADEDMODULES _LMFILES_ __LMOD_REF_COUNT_MODULEPATH' \
        '}' \
        '' \
        'vnc_novnc_nersc_lmod_init() {' \
        '    [ "$(id -u)" != "0" ] || return 0' \
        '    if [ -n "${PELOCAL_PRGENV:-}" ]; then' \
        '        if [ -r /opt/cray/pe/lmod/lmod/init/profile ]; then' \
        '            . /opt/cray/pe/lmod/lmod/init/profile >/dev/null 2>&1' \
        '        elif [ -r /opt/cray/pe/lmod/lmod/init/bash ]; then' \
        '            . /opt/cray/pe/lmod/lmod/init/bash >/dev/null 2>&1' \
        '        fi' \
        '        return 0' \
        '    fi' \
        '    vnc_novnc_nersc_lmod_reset' \
        '    if [ -r /opt/nersc/pe/etc/lmod/lmod_setup.sh ]; then' \
        '        . /opt/nersc/pe/etc/lmod/lmod_setup.sh' \
        '    fi' \
        '    if [ -r /opt/cray/pe/lmod/lmod/init/profile ]; then' \
        '        . /opt/cray/pe/lmod/lmod/init/profile >/dev/null 2>&1' \
        '    elif [ -r /opt/cray/pe/lmod/lmod/init/bash ]; then' \
        '        . /opt/cray/pe/lmod/lmod/init/bash >/dev/null 2>&1' \
        '    fi' \
        '}' \
        '' \
        'vnc_novnc_nersc_default_modules() {' \
        '    case "${VNC_NOVNC_NERSC_DEFAULT_MODULES:-1}" in' \
        '        0|false|FALSE|no|NO|off|OFF) return 0 ;;' \
        '    esac' \
        '    [ "$(id -u)" != "0" ] || return 0' \
        '    if [ -n "${PELOCAL_PRGENV:-}" ]; then' \
        '        command -v module >/dev/null 2>&1 && module refresh >/dev/null 2>&1 || true' \
        '        return 0' \
        '    fi' \
        '    [ -r /etc/cray-pe.d/cray-pe-configuration.sh ] || return 0' \
        '    [ -n "${MODULESHOME:-}" ] || return 0' \
        '    . /etc/cray-pe.d/cray-pe-configuration.sh' \
        '    mod_paths="/opt/cray/pe/lmod/modulefiles/core /opt/cray/pe/lmod/modulefiles/craype-targets/default ${mpaths:-} /opt/cray/modulefiles"' \
        '    for p in ${mod_paths}; do' \
        '        [ -d "${p}" ] || continue' \
        '        case ":${MODULEPATH:-}:" in' \
        '            *:"${p}":*) ;;' \
        '            *) MODULEPATH="${MODULEPATH:+${MODULEPATH}:}${p}" ;;' \
        '        esac' \
        '    done' \
        '    export MODULEPATH' \
        '    mlist="${init_module_list:-PrgEnv-${default_prgenv:-gnu}} ${site_module_list:-}"' \
        '    LMOD_SYSTEM_DEFAULT_MODULES="${LMOD_SYSTEM_DEFAULT_MODULES:-$(echo ${mlist} | sed "s_  *_:_g")}"' \
        '    export LMOD_SYSTEM_DEFAULT_MODULES' \
        '    if ! module --initial_load --no_redirect load ${mlist} >/dev/null 2>&1; then' \
        '        printf "WARNING: failed to load NERSC default modules inside container\n" >&2' \
        '    fi' \
        '    PELOCAL_PRGENV=true' \
        '    readonly PELOCAL_PRGENV' \
        '    export PELOCAL_PRGENV' \
        '}' \
        '' \
        'vnc_novnc_nersc_lmod_init' \
        'vnc_novnc_nersc_default_modules' \
        'unset -f vnc_novnc_nersc_lmod_reset vnc_novnc_nersc_lmod_init vnc_novnc_nersc_default_modules' \
        > /etc/profile.d/zz-vnc-novnc-nersc-lmod.sh && \
    printf '%s\n' \
        '[ -r /etc/profile.d/zz-vnc-novnc-nersc-lmod.sh ] && . /etc/profile.d/zz-vnc-novnc-nersc-lmod.sh' \
        >> /etc/bash.bashrc

# Preserve image-level /etc/environment because Slurm runs bind-mount the host file there.
RUN \
    set -eu; \
    mkdir -p /etc/vnc-novnc && \
    if [ -f /etc/environment ]; then \
        mv /etc/environment /etc/vnc-novnc/environment; \
    else \
        : > /etc/vnc-novnc/environment; \
    fi && \
    : > /etc/environment && \
    printf '%s\n' \
        'vnc_novnc_source_environment() {' \
        '    [ -r "$1" ] || return 0' \
        '    set -a' \
        '    . "$1"' \
        '    set +a' \
        '}' \
        'vnc_novnc_source_environment /etc/vnc-novnc/environment' \
        'vnc_novnc_source_environment /etc/environment' \
        'unset -f vnc_novnc_source_environment' \
        > /etc/profile.d/00-vnc-novnc-environment.sh && \
    sed -i '1i[ -r /etc/profile.d/00-vnc-novnc-environment.sh ] && . /etc/profile.d/00-vnc-novnc-environment.sh' /etc/bash.bashrc

COPY container/vnc/vnc-novnc-entrypoint /usr/local/bin/vnc-novnc-entrypoint
COPY container/kernel/vnc-novnc-jupyter-kernel /usr/local/bin/vnc-novnc-jupyter-kernel
COPY vnc_novnc /usr/local/lib/vnc-novnc/vnc_novnc
COPY --from=slurm-cli-builder /out/scli /usr/local/bin/scli
COPY --from=slurm-cli-builder /out/ssh-proxy /usr/local/bin/ssh-proxy

RUN \
    chmod 0755 /usr/local/bin/vnc-novnc-entrypoint /usr/local/bin/vnc-novnc-jupyter-kernel /usr/local/bin/scli /usr/local/bin/ssh-proxy && \
    chmod -R a+rX /usr/local/lib/vnc-novnc && \
    for command in srun sbatch salloc scontrol sacct squeue scancel sinfo sshare sprio; do \
        ln -sf /usr/local/bin/scli "/usr/local/bin/${command}"; \
    done && \
    ln -sf /usr/local/bin/ssh-proxy /usr/local/bin/ssh && \
    printf '%s\n' \
        '#!/bin/sh' \
        'dbus_session_valid=0' \
        'case "${DBUS_SESSION_BUS_ADDRESS:-}" in' \
        '    unix:*|tcp:*|nonce-tcp:*) dbus_session_valid=1 ;;' \
        'esac' \
        'chromium_sandbox_args=' \
        'chromium_default_args="--disable-gpu --disable-dev-shm-usage --password-store=basic --no-first-run"' \
        'if [ "$(id -u)" = "0" ]; then' \
        '    chromium_sandbox_args=--no-sandbox' \
        'fi' \
        'if [ "${dbus_session_valid}" != "1" ] && command -v dbus-run-session >/dev/null 2>&1; then' \
        '    exec dbus-run-session -- /usr/bin/chromium ${chromium_sandbox_args} ${chromium_default_args} "$@"' \
        'fi' \
        'if [ "${dbus_session_valid}" != "1" ] && command -v dbus-launch >/dev/null 2>&1; then' \
        '    exec dbus-launch --exit-with-session /usr/bin/chromium ${chromium_sandbox_args} ${chromium_default_args} "$@"' \
        'fi' \
        'exec /usr/bin/chromium ${chromium_sandbox_args} ${chromium_default_args} "$@"' \
        > /usr/local/bin/chromium && \
    chmod 0755 /usr/local/bin/chromium

ENV \
    VNC_DISPLAY=1 \
    VNC_PORT=5901 \
    VNC_GEOMETRY=1280x800 \
    VNC_DEPTH=24 \
    VNC_LOCALHOST=no \
    VNC_SECURITY_TYPES=VncAuth \
    VNC_PASSWORD=changeme \
    VNC_PASSWORD_FILE=/root/.vnc/passwd \
    VNC_PASSWORD_PLAIN_FILE= \
    VNC_XSTARTUP=/root/.vnc/xstartup \
    VNC_DESKTOP_CMD=startxfce4 \
    VNC_EXTRA_ARGS= \
    NOVNC_LISTEN=0.0.0.0 \
    NOVNC_PORT=6080 \
    NOVNC_WEB=/usr/share/novnc \
    NOVNC_VNC_HOST=127.0.0.1 \
    NOVNC_VNC_PORT= \
    NOVNC_EXTRA_ARGS= \
    SHELL=/bin/bash \
    PYTHONPATH=/usr/local/lib/vnc-novnc

ENTRYPOINT ["/usr/local/bin/vnc-novnc-entrypoint"]
CMD ["start"]
