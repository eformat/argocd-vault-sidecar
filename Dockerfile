FROM registry.access.redhat.com/ubi9/ubi:9.2

USER root

ENV ARGOCD_VERSION=2.7.13 \
    HELM_VERSION=3.12.1 \
    KUSTOMIZE_VERSION=5.0.3 \
    AVP_VERSION=1.14.0

# Install git and friends
RUN dnf -y install \
    bash tar gzip unzip which findutils git && \
    dnf -y -q clean all && rm -rf /var/cache/yum && \
    echo "🐙🐙🐙🐙🐙"

# Install the AVP plugin
RUN curl -skL -o /tmp/argocd-vault-plugin https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v${AVP_VERSION}/argocd-vault-plugin_${AVP_VERSION}_linux_amd64 && \
    chmod +x /tmp/argocd-vault-plugin && \
    mv -v /tmp/argocd-vault-plugin /usr/local/bin && \
    echo "🔒🔒🔒🔒"

# Install helm
RUN curl -skL -o /tmp/helm.tar.gz https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz && \
    tar -C /tmp -xzf /tmp/helm.tar.gz && \
    mv -v /tmp/linux-amd64/helm /usr/local/bin && \
    chmod -R 775 /usr/local/bin/helm && \
    rm -rf /tmp/linux-amd64 && \
    echo "⚓️⚓️⚓️⚓️⚓️"

# Install kustomize
RUN curl -skL -o /tmp/kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
    tar -C /tmp -xzf /tmp/kustomize.tar.gz && \
    mv -v /tmp/kustomize /usr/local/bin && \
    chmod -R 775 /usr/local/bin/kustomize && \
    rm -rf /tmp/linux-amd64 && \
    echo "🐾🐾🐾🐾🐾"

USER 999
