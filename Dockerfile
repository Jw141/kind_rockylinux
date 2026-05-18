# Use the official Rocky Linux 9 base image
FROM rockylinux:9

# Install core dependencies using DNF
# 'tar' is mandatory to extract the Helm binary
RUN dnf update -y curl tar && dnf install -y \
     \
    git \
    && dnf clean all

# Explicitly pin stable versions
ARG KUBECTL_VERSION=v1.36.1
ARG KIND_VERSION=v0.31.0
ARG HELM_VERSION=v3.14.2

# 1. Download and install kubectl
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 2. Download and install KinD
RUN curl -Lo kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" \
    && chmod +x kind \
    && mv kind /usr/local/bin/

# 3. Download and install Helm
RUN curl -fsSL -o helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -zxvf helm.tar.gz \
    && mv linux-amd64/helm /usr/local/bin/helm \
    && rm -rf helm.tar.gz linux-amd64

# Sanity check to verify all Go binaries compile and run on the RHEL architecture
RUN kubectl version --client && kind version && helm version --client

WORKDIR /apps

ENTRYPOINT ["/bin/bash"]