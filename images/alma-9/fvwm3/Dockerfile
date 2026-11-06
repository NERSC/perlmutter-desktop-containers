FROM docker.io/almalinux:9-minimal

ARG TARGETARCH
ARG SSHPROXY_VERSION=2.1.2
ARG SSHPROXY_ARCH
ARG FVWM3_VERSION=1.1.5

RUN \
    set -eu; \
    case "${SSHPROXY_ARCH:-${TARGETARCH:-amd64}}" in \
        amd64|x86_64|linux-x86_64) sshproxy_arch=linux-x86_64 ;; \
        *) echo "AlmaLinux desktop variant currently supports amd64 only: ${SSHPROXY_ARCH:-${TARGETARCH:-}}" >&2; exit 1 ;; \
    esac; \
    sshproxy_url="https://portal.nersc.gov/cfs/mfa/sshproxy-${SSHPROXY_VERSION}-${sshproxy_arch}.tar.gz"; \
    microdnf -y install dnf dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf -y install --allowerasing --setopt=install_weak_deps=False \
        ca-certificates \
        bash \
        chromium \
        curl \
        dbus \
        dbus-x11 \
        dejavu-sans-fonts \
        dejavu-sans-mono-fonts \
        dejavu-serif-fonts \
        file \
        findutils \
        fontconfig \
        gcc \
        gdb \
        git \
        google-noto-emoji-fonts \
        google-noto-sans-fonts \
        google-noto-serif-fonts \
        gzip \
        iproute \
        less \
        libevent-devel \
        libpng-devel \
        libX11-devel \
        libXcursor-devel \
        libXext-devel \
        libXft-devel \
        libXinerama-devel \
        libXpm-devel \
        libXrandr-devel \
        libXrender-devel \
        libXt-devel \
        liberation-fonts \
        libxkbcommon-devel \
        make \
        net-tools \
        ninja-build \
        nfs-utils \
        nmap \
        novnc \
        openssh-clients \
        openssh-server \
        openssl-devel \
        pkgconf-pkg-config \
        procps-ng \
        python3 \
        python3-pip \
        python3-websockify \
        readline-devel \
        tar \
        Thunar \
        tigervnc \
        tigervnc-server \
        tmux \
        tcpdump \
        vim \
        wireshark-cli \
        wget \
        which \
        xorg-x11-util-macros \
        xorg-x11-server-utils \
        xorg-x11-xauth \
        xorg-x11-xtrans-devel \
        xterm \
        xfce4-terminal \
        zlib-devel && \
    python3 -m pip install --no-cache-dir ipykernel 'meson>=1.5.1' && \
    curl --fail --location --show-error \
        --retry 5 --retry-all-errors --retry-delay 5 --retry-max-time 300 --connect-timeout 30 \
        "https://github.com/fvwmorg/fvwm3/releases/download/${FVWM3_VERSION}/fvwm3-${FVWM3_VERSION}.tar.gz" --output /tmp/fvwm3.tar.gz && \
    mkdir -p /tmp/fvwm3-src && \
    tar -xzf /tmp/fvwm3.tar.gz -C /tmp/fvwm3-src --strip-components=1 && \
    cd /tmp/fvwm3-src && \
    python3 -m mesonbuild.mesonmain setup compile --prefix=/usr/local -Dgolang=disabled && \
    python3 -m mesonbuild.mesonmain compile -C compile && \
    python3 -m mesonbuild.mesonmain install -C compile && \
    test -x /usr/local/bin/fvwm3 && \
    curl --fail --location --show-error \
        --retry 5 --retry-all-errors --retry-delay 5 --retry-max-time 300 --connect-timeout 30 \
        "${sshproxy_url}" --output /tmp/sshproxy.tar.gz && \
    tar -xzf /tmp/sshproxy.tar.gz -C /usr/local/bin sshproxy && \
    chmod 0755 /usr/local/bin/sshproxy && \
    mkdir -p /etc/vnc-novnc /root/.fvwm && \
    sed -i 's#^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*#\1/bin/bash#' /etc/passwd && \
    dnf clean all && \
    rm -rf /tmp/fvwm3.tar.gz /tmp/fvwm3-src /tmp/sshproxy.tar.gz /var/cache/dnf

COPY container/vnc/vnc-novnc-entrypoint /usr/local/bin/vnc-novnc-entrypoint
COPY container/kernel/vnc-novnc-jupyter-kernel /usr/local/bin/vnc-novnc-jupyter-kernel
COPY container/vnc/fvwm3-config /etc/vnc-novnc/fvwm3-config
COPY container/vnc/fvwm3-config /root/.fvwm/config
COPY vnc_novnc /usr/local/lib/vnc-novnc/vnc_novnc

RUN \
    chmod 0755 /usr/local/bin/vnc-novnc-entrypoint /usr/local/bin/vnc-novnc-jupyter-kernel && \
    chmod -R a+rX /usr/local/lib/vnc-novnc && \
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
        '    exec dbus-run-session -- /usr/bin/chromium-browser ${chromium_sandbox_args} ${chromium_default_args} "$@"' \
        'fi' \
        'if [ "${dbus_session_valid}" != "1" ] && command -v dbus-launch >/dev/null 2>&1; then' \
        '    exec dbus-launch --exit-with-session /usr/bin/chromium-browser ${chromium_sandbox_args} ${chromium_default_args} "$@"' \
        'fi' \
        'exec /usr/bin/chromium-browser ${chromium_sandbox_args} ${chromium_default_args} "$@"' \
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
    VNC_DESKTOP_CMD=fvwm3 \
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
