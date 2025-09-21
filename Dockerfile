# hadolint ignore=DL3007
FROM ghcr.io/spacelift-io/runner-ansible:latest AS spacelift

USER root

# hadolint ignore=DL3018
RUN apk add --no-cache tailscale bash netcat-openbsd

# Copy Tailscale integration scripts
COPY bin/ /usr/local/bin/

# Let tailscale/d use default socket location
RUN mkdir -p /home/spacelift/.local/share/tailscale /var/run/tailscale && chown spacelift:spacelift /home/spacelift/.local/share/tailscale /var/run/tailscale

USER spacelift
