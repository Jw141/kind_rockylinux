# --- STAGE 0: Build from Source using secure Go 1.26 ---
FROM docker.io/library/golang:1.26-bookworm AS go-builder

# Pin the correct, existing upstream versions for source compilation
ARG KIND_VERSION=v0.31.0
ARG HELM_VERSION=v3.20.2

# Compile the KinD CLI directly from its source code using Go 1.26
RUN GOPROXY=https://proxy.golang.org,direct \
    go install sigs.k8s.io/kind@${KIND_VERSION}

# Compile Helm directly from its source code using Go 1.26
RUN GOPROXY=https://proxy.golang.org,direct \
    go install helm.sh/helm/v3/cmd/helm@${HELM_VERSION}


# --- STAGE 1: Final Secure Rocky Linux Runtime ---
FROM docker.io/rockylinux/rockylinux:9.7

# Ensure packages are installed properly, not just updated
RUN dnf update -y curl tar && dnf install -y \
    git \
    && dnf clean all

# Grab the latest patched kubectl binary (precompiled from Kubernetes)
ARG KUBECTL_VERSION=v1.36.1
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# COPY the secure binaries you custom-built using Go 1.26 from Stage 0
COPY --from=go-builder /go/bin/kind /usr/local/bin/kind
COPY --from=go-builder /go/bin/helm /usr/local/bin/helm

# Sanity check to verify all binaries work on Rocky Linux
RUN kubectl version --client && kind version && helm version --client

WORKDIR /apps
ENTRYPOINT ["/bin/bash"]