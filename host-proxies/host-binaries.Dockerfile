FROM scratch

LABEL org.opencontainers.image.source="https://github.com/NERSC/perlmutter-desktop-containers"
LABEL org.opencontainers.image.description="Static Perlmutter host Slurm and SSH proxy servers"

COPY --chmod=0755 scli-server /usr/local/bin/scli-server
COPY --chmod=0755 ssh-proxy-server /usr/local/bin/ssh-proxy-server
COPY SHA256SUMS /usr/local/bin/SHA256SUMS

ENTRYPOINT ["/usr/local/bin/scli-server"]
