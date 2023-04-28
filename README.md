# argocd-vault-sidecar

ArgoCD sidecar suitable for running the [ArgoCD Vault Plugin](https://argocd-vault-plugin.readthedocs.io/en/stable/installation/#custom-image-and-configuration-via-sidecar)

# Example Usage

I am using the [GitOps Operator Helm Chart](https://github.com/redhat-cop/helm-charts/tree/master/charts/gitops-operator) from the RedHat COP.

I have configured the vault service account with a long lived token for now. This should be [changed for newer k8s](https://github.com/hashicorp/vault/blob/main/website/content/docs/auth/kubernetes.mdx#use-local-service-account-token-as-the-reviewer-jwt) to support short-lived tokens.

```bash
export TEAM_NAME=rainforest
export SERVICE_ACCOUNT=vault
export GIT_SERVER=gitlab-ce.apps.sno.sandbox1117.opentlc.com
export IMAGE_TAG=2.6.7

oc new-project ${TEAM_NAME}-ci-cd
oc -n ${TEAM_NAME}-ci-cd create sa ${SERVICE_ACCOUNT}
cat <<EOF | oc -n ${TEAM_NAME}-ci-cd apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  annotations:
    kubernetes.io/service-account.name: "${SERVICE_ACCOUNT}" 
type: kubernetes.io/service-account-token 
EOF
oc -n ${TEAM_NAME}-ci-cd secrets link ${SERVICE_ACCOUNT} vault-token
oc adm policy add-cluster-role-to-user edit -z ${SERVICE_ACCOUNT} -n ${TEAM_NAME}-ci-cd
oc adm policy add-cluster-role-to-user system:auth-delegator -z ${SERVICE_ACCOUNT} -n ${TEAM_NAME}-ci-cd

cat << EOF > /tmp/argocd-values.yaml
ignoreHelmHooks: true
operator: []
namespaces:
  - ${TEAM_NAME}-ci-cd
argocd_cr:
  statusBadgeEnabled: true
  repo:
    mountsatoken: true
    serviceaccount: ${SERVICE_ACCOUNT}
    volumes:
    - name: vault-plugin
      configMap:
        name: argocd-vault-plugins
        items:
        - key: vault-plugin.yaml
          path: plugin.yaml
          mode: 509
    - name: vault-plugin-helm
      configMap:
        name: argocd-vault-plugins
        items:
        - key: helm-plugin.yaml
          path: plugin.yaml
          mode: 509
    - name: vault-plugin-kustomize
      configMap:
        name: argocd-vault-plugins
        items:
        - key: kustomize-plugin.yaml
          path: plugin.yaml
          mode: 509
    - name: cmp-tmp-vault
      emptyDir: {}
    - name: cmp-tmp-helm
      emptyDir: {}
    - name: cmp-tmp-kustomize
      emptyDir: {}      
    initContainers:
    - name: copy-cmp-server
      command:
      - cp
      - -n
      - /usr/local/bin/argocd
      - /var/run/argocd/argocd-cmp-server
      image: quay.io/argoproj/argocd:v${IMAGE_TAG}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
          - ALL
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      terminationMessagePath: /dev/termination-log
      terminationMessagePolicy: File
      volumeMounts:
      - mountPath: /var/run/argocd
        name: var-files
    sidecarContainers:
    - name: vault-plugin
      command: [/var/run/argocd/argocd-cmp-server]
      image: quay.io/eformat/argocd-vault-sidecar:latest
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
          - ALL
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/config
          name: vault-plugin
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: cmp-tmp-vault
    - name: vault-plugin-helm
      command: [/var/run/argocd/argocd-cmp-server]
      image: quay.io/eformat/argocd-vault-sidecar:latest
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
          - ALL
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/config
          name: vault-plugin-helm
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: cmp-tmp-helm
    - name: vault-plugin-kustomize
      command: [/var/run/argocd/argocd-cmp-server]
      image: quay.io/eformat/argocd-vault-sidecar:${IMAGE_TAG}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
          - ALL
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/config
          name: vault-plugin-kustomize
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: cmp-tmp-kustomize
  initialRepositories: |
    - name: rainforest
      url: https://${GIT_SERVER}/${TEAM_NAME}/data-mesh-pattern.git
  repositoryCredentials: |
    - url: https://${GIT_SERVER}
      type: git
      passwordSecret:
        key: password
        name: git-auth
      usernameSecret:
        key: username
        name: git-auth
EOF

oc apply -n ${TEAM_NAME}-ci-cd -f- <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-vault-plugins
data:
  vault-plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-vault-plugin
    spec:
      generate:
        command: ["sh", "-c"]
        args: ["argocd-vault-plugin -s ${TEAM_NAME}-ci-cd:team-avp-credentials generate ./"]
  helm-plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-vault-plugin-helm
    spec:
      init:
        command: [sh, -c]
        args: ["helm dependency build"]
      generate:
        command: ["bash", "-c"]
        args: ['helm template "\$ARGOCD_APP_NAME" -n "\$ARGOCD_APP_NAMESPACE" -f <(echo "\$ARGOCD_ENV_HELM_VALUES") . | argocd-vault-plugin generate -s ${TEAM_NAME}-ci-cd:team-avp-credentials -']
  kustomize-plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-vault-plugin-kustomize
    spec:
      generate:
        command: ["sh", "-c"]
        args: ["kustomize build . | argocd-vault-plugin -s ${TEAM_NAME}-ci-cd:team-avp-credentials generate -"]
EOF

helm upgrade --install argocd \
  --namespace ${TEAM_NAME}-ci-cd \
  -f /tmp/argocd-values.yaml \
  redhat-cop/gitops-operator
```
