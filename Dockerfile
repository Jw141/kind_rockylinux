# --- STAGE 0: Isolated Upstream Go Compiler & Security Patcher ---
FROM docker.io/library/golang:1.26-bookworm AS go-builder

WORKDIR /build

# Ensure git is available to fetch and patch source modules
RUN apt-get update && apt-get install -y git

# Pin stable versions for source compilation
ARG KIND_VERSION=v0.31.0
ARG HELM_VERSION=v3.20.2
ARG KUBECTL_VERSION=v1.36.1

# 1. Clone, inject gRPC replace shortcut, and build KinD using on-the-fly mod patching
RUN git clone --depth 1 --branch ${KIND_VERSION} https://github.com/kubernetes-sigs/kind.git /build/kind && \
    cd /build/kind && \
    go mod edit -replace google.golang.org/grpc=google.golang.org/grpc@v1.79.3 && \
    go build -mod=mod -ldflags="-w -s" -o /go/bin/kind .

# 2. Clone, inject gRPC replace shortcut, and build Helm using on-the-fly mod patching
RUN git clone --depth 1 --branch ${HELM_VERSION} https://github.com/helm/helm.git /build/helm && \
    cd /build/helm && \
    go mod edit -replace google.golang.org/grpc=google.golang.org/grpc@v1.79.3 && \
    go build -mod=mod -ldflags="-w -s" -o /go/bin/helm ./cmd/helm

# 3. Clone and compile Kubectl (Bypassing Go Workspace constraints via GOWORK=off)
RUN git clone --depth 1 --branch ${KUBECTL_VERSION} https://github.com/kubernetes/kubernetes.git /build/kubernetes && \
    cd /build/kubernetes && \
    go mod edit -replace google.golang.org/grpc=google.golang.org/grpc@v1.79.3 && \
    GOWORK=off go build -mod=mod -ldflags="-w -s" -o /go/bin/kubectl ./cmd/kubectl


# --- STAGE 1: Hardened Final Image ---
FROM docker.io/rockylinux/rockylinux:9.7

# 1. Flush metadata and pull all upstream security patches across the OS baseline
RUN dnf clean all && \
    dnf update -y --refresh && \
    dnf install -y epel-release && \
    dnf config-manager --set-enabled crb

# 2. Install secondary diagnostic runtimes (Omit curl/tar to prevent duplicate install errors)
RUN dnf install -y --allowerasing \
    shadow-utils \
    git \
    procps-ng \
    htop \
    && dnf clean all

# 3. Copy the completely secure, source-compiled assets from Stage 0
COPY --from=go-builder /go/bin/kubectl /usr/local/bin/kubectl
COPY --from=go-builder /go/bin/kind /usr/local/bin/kind
COPY --from=go-builder /go/bin/helm /usr/local/bin/helm

# 4. Sanity check to confirm operational compliance
RUN kubectl version --client && kind version && helm version --client

WORKDIR /apps

# OCI Metadata tracking compliance
LABEL org.opencontainers.image.title="Hardened Kubernetes Dev Toolbox" \
      org.opencontainers.image.description="Rocky Linux 9.7 dev toolbox featuring custom source-compiled and dependency-patched variations of KinD, Helm, and Kubectl." \
      org.opencontainers.image.vendor="Radix Metasystems"

ENTRYPOINT ["/bin/bash"]