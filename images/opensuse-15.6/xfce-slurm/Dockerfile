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

# Prefer the host NERSC/Cray Lmod stack when /opt is mounted.
RUN \
    set -eu; \
    printf '%s\n' \
        'if [ -r /opt/cray/pe/lmod/lmod/init/bash ]; then' \
        '    unset LMOD_CMD LMOD_DIR LMOD_ROOT LMOD_PKG MODULESHOME LMOD_SETTARG_CMD' \
        '    . /opt/cray/pe/lmod/lmod/init/bash' \
        'fi' \
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

EXPOSE 6080

ENTRYPOINT ["/usr/local/bin/vnc-novnc-entrypoint"]
CMD ["start"]
