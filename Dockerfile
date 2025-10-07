# Multi-stage build to reduce final image size
# Stage 1: Builder - compile get-authkey utility
FROM golang:alpine AS builder

# Install get-authkey utility for OAuth-based auth key generation
RUN go install tailscale.com/cmd/get-authkey@latest

# Stage 2: Runtime - minimal image with only required components
# hadolint ignore=DL3007
FROM ghcr.io/spacelift-io/runner-ansible:latest AS runtime

USER root

# Install only tailscale (no Go toolchain needed in runtime)
# hadolint ignore=DL3018
RUN apk add --no-cache tailscale bash netcat-openbsd

# Copy Tailscale integration scripts
COPY bin/ /usr/local/bin/

# Copy get-authkey binary from builder stage
COPY --from=builder /go/bin/get-authkey /usr/local/bin/get-authkey
RUN chmod +x /usr/local/bin/get-authkey

# Let tailscale/d use default socket location
RUN mkdir -p /home/spacelift/.local/share/tailscale /var/run/tailscale && chown spacelift:spacelift /home/spacelift/.local/share/tailscale /var/run/tailscale

USER spacelift
