ARG CUDA_IMAGE=nvcr.io/nvidia/cuda:13.3.0-cudnn-devel-ubuntu24.04
FROM ${CUDA_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

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
    apt-get update && \
    apt-get install --yes --no-install-recommends \
        ca-certificates \
        bash \
        curl \
        debian-archive-keyring && \
    printf '%s\n' \
        'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main' \
        'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian-security bookworm-security main' \
        > /etc/apt/sources.list.d/debian-bookworm.list && \
    printf '%s\n' \
        'Package: *' \
        'Pin: release n=bookworm' \
        'Pin-Priority: 100' \
        '' \
        'Package: *' \
        'Pin: release n=bookworm-security' \
        'Pin-Priority: 100' \
        '' \
        'Package: chromium chromium-common chromium-sandbox' \
        'Pin: release n=bookworm-security' \
        'Pin-Priority: 990' \
        '' \
        'Package: chromium chromium-common chromium-sandbox' \
        'Pin: release n=bookworm' \
        'Pin-Priority: 990' \
        > /etc/apt/preferences.d/debian-chromium && \
    apt-get update && \
    apt-get install --yes --no-install-recommends \
        chromium \
        chromium-sandbox \
        dbus \
        dbus-user-session \
        dbus-x11 \
        file \
        findutils \
        fontconfig \
        fonts-dejavu \
        fonts-liberation \
        fonts-noto-color-emoji \
        fonts-noto-core \
        gcc \
        gdb \
        git \
        iproute2 \
        less \
        libegl1 \
        libegl-mesa0 \
        libgl1 \
        libgl1-mesa-dri \
        libgles2 \
        libglu1-mesa \
        libglvnd0 \
        libglx0 \
        libglx-mesa0 \
        libosmesa6 \
        libvulkan1 \
        libx11-6 \
        libxau6 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxdmcp6 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxinerama1 \
        libxrandr2 \
        libxrender1 \
        make \
        mesa-utils \
        mesa-utils-extra \
        net-tools \
        nfs-common \
        nmap \
        novnc \
        openssh-client \
        procps \
        python3 \
        python3-ipykernel \
        tar \
        thunar \
        tigervnc-standalone-server \
        tigervnc-tools \
        tmux \
        tcpdump \
        tshark \
        vim \
        vulkan-tools \
        wget \
        websockify \
        x11-xserver-utils \
        xauth \
        xfonts-base \
        xterm \
        xfce4-panel \
        xfce4-session \
        xfce4-settings \
        xfce4-terminal \
        xfdesktop4 \
        xfwm4 \
        zlib1g-dev && \
    curl --fail --location --show-error \
        --retry 5 --retry-all-errors --retry-delay 5 --retry-max-time 300 --connect-timeout 30 \
        "${sshproxy_url}" --output /tmp/sshproxy.tar.gz && \
    tar -xzf /tmp/sshproxy.tar.gz -C /usr/local/bin sshproxy && \
    chmod 0755 /usr/local/bin/sshproxy && \
    mkdir -p /etc/vnc-novnc && \
    sed -i 's#^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*#\1/bin/bash#' /etc/passwd && \
    apt-get clean && \
    rm -f /etc/apt/sources.list.d/debian-bookworm.list /etc/apt/preferences.d/debian-chromium && \
    rm -rf /var/lib/apt/lists/* /tmp/sshproxy.tar.gz

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
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,display \
    CUDA_PATH=/usr/local/cuda \
    QT_X11_NO_MITSHM=1 \
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
