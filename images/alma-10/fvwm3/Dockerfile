FROM docker.io/almalinux:10-minimal

# AlmaLinux 10/EPEL 10 does not currently package TigerVNC server or fvwm3.
# Keep this variant explicit so the gap is visible.
RUN \
    printf '%s\n' \
        'AlmaLinux 10 fvwm3 is scaffolded but not buildable yet.' \
        'Missing probed packages: tigervnc-server, fvwm3.' >&2 && \
    exit 1
