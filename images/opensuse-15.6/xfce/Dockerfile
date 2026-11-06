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
        gdb \
        git \
        gzip \
        iproute2 \
        less \
        liberation-fonts \
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

COPY container/vnc/vnc-novnc-entrypoint /usr/local/bin/vnc-novnc-entrypoint
COPY container/kernel/vnc-novnc-jupyter-kernel /usr/local/bin/vnc-novnc-jupyter-kernel
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
