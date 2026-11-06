FROM docker.io/almalinux:10-minimal

# AlmaLinux 10/EPEL 10 does not currently package TigerVNC server or a full
# XFCE desktop stack. Keep this variant explicit so the gap is visible.
RUN \
    printf '%s\n' \
        'AlmaLinux 10 XFCE is scaffolded but not buildable yet.' \
        'Missing probed packages: tigervnc-server, xfce4-session, xfce4-panel, xfdesktop, xfwm4.' >&2 && \
    exit 1
