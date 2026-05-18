# --- STAGE 0: Isolated Upstream Go Compiler ---
FROM docker.io/library/golang:1.26-bookworm AS go-builder

ARG KIND_VERSION=v0.31.0
ARG HELM_VERSION=v3.20.2

# Compile KinD and Helm strictly from source code to eliminate Go runtime CVEs
RUN GOPROXY=https://proxy.golang.org,direct \
    go install sigs.k8s.io/kind@${KIND_VERSION}

RUN GOPROXY=https://proxy.golang.org,direct \
    go install helm.sh/helm/v3/cmd/helm@${HELM_VERSION}


# --- STAGE 1: Builder (Verification & Preparation) ---
FROM docker.io/rockylinux/rockylinux:9.7 AS builder

# Install core tools needed to stage the environment (curl and tar are already present)
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y git

# Set up the official Kubernetes signed RPM repository 
RUN echo $'[kubernetes]\n\
name=Kubernetes\n\
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/\n\
enabled=1\n\
gpgcheck=1\n\
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key' > /etc/yum.repos.d/kubernetes.repo

# Install kubectl cleanly via the verified package manager channel
RUN dnf install -y kubectl

# Pull your custom-built binaries from the Go compiler stage
COPY --from=go-builder /go/bin/kind /usr/bin/kind
COPY --from=go-builder /go/bin/helm /usr/bin/helm


# --- STAGE 2: Hardened Final Image ---
FROM docker.io/rockylinux/rockylinux:9.7

# 1. Flush metadata, pull all upstream security patches
RUN dnf clean all && \
    dnf update -y --refresh && \
    dnf install -y epel-release && \
    dnf config-manager --set-enabled crb

# 2. Install supplementary runtimes and diagnostic tools (No curl/tar here to prevent errors)
RUN dnf install -y --allowerasing \
    shadow-utils \
    git \
    procps-ng \
    htop \
    && dnf clean all

# 3. Copy the verified, compiled, and signed assets from the builder stage
COPY --from=builder /usr/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/bin/kind /usr/local/bin/kind
COPY --from=builder /usr/bin/helm /usr/local/bin/helm

# 4. Sanity check to confirm architectural operational security
RUN kubectl version --client && kind version && helm version --client

WORKDIR /apps

# OCI Metadata tracking compliance
LABEL org.opencontainers.image.title="Hardened Kubernetes Dev Toolbox" \
      org.opencontainers.image.description="Rocky Linux 9.7 toolbox bundling custom source-compiled KinD, Helm, and native RPM managed Kubectl." \
      org.opencontainers.image.vendor="Radix Metasystems"

ENTRYPOINT ["/bin/bash"]