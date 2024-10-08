# argocd-vault-sidecar

ArgoCD sidecar suitable for running the [ArgoCD Vault Plugin](https://argocd-vault-plugin.readthedocs.io/en/stable/installation/#custom-image-and-configuration-via-sidecar)

## Example Usage

I am using the [GitOps Operator Helm Chart](https://github.com/redhat-cop/helm-charts/tree/master/charts/gitops-operator) from the RedHat COP.

```bash
export TEAM_NAME=rainforest
export SERVICE_ACCOUNT=vault
export GIT_SERVER=gitlab-ce.apps.sno.sandbox1117.opentlc.com
export IMAGE_TAG=$(cat VERSION)

oc new-project ${TEAM_NAME}-ci-cd
oc -n ${TEAM_NAME}-ci-cd create sa ${SERVICE_ACCOUNT}
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
    - configMap:
        name: argocd-vault-plugins
        items:
        - key: sops-age-plugin.yaml
          path: plugin.yaml
          mode: 509
      name: sops-age-plugin
    - name: sops-age-key
      secret:
        defaultMode: 420
        secretName: sops-age-key
    - name: cmp-tmp-vault
      emptyDir: {}
    - name: cmp-tmp-helm
      emptyDir: {}
    - name: cmp-tmp-kustomize
      emptyDir: {}
    - name: cmp-tmp-sops-age
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
          name: vault-plugin
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: cmp-tmp-vault
    - name: vault-plugin-helm
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
    - command: [/var/run/argocd/argocd-cmp-server]
      env:
        - name: SOPS_AGE_KEY_FILE
          value: /var/run/secrets/age-key.txt
      image: quay.io/eformat/argocd-vault-sidecar:${IMAGE_TAG}
      name: sops-age-plugin
      resources: {}
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
          name: sops-age-plugin
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: cmp-tmp-sops-age
        - mountPath: /var/run/secrets
          name: sops-age-key
          readOnly: true
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

## plugins
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
  sops-age-plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-sops-age-plugin
    spec:
      generate:
        command: ["sh", "-c"]
        args: ['AVP_TYPE=sops argocd-vault-plugin generate ./']
EOF

## sops and age
oc apply -n ${TEAM_NAME}-ci-cd -f- <<EOF
apiVersion: v1
stringData:
  age-key.txt: |
    # public key: ageXXX
    AGE-SECRET-KEY-XXX
kind: Secret
metadata:
  name: sops-age-key
  namespace: openshift-gitops
type: Opaque
EOF

## deploy
helm upgrade --install argocd \
  --namespace ${TEAM_NAME}-ci-cd \
  -f /tmp/argocd-values.yaml \
  redhat-cop/gitops-operator
```

### Signature

The public key of [argocd-vault-sidecar image](https://quay.io/repository/eformat/argocd-vault-sidecar)

[Cosign](https://github.com/sigstore/cosign) public key:

```shell
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEakwO+HEdPrtGO0bfkSiFaOwRTGVJ
rdH2gzTrs5DilXAnomraaA7Uv1ZoAyl5KQqsQ4suSr346aBm7Yrqxo4xYg==
-----END PUBLIC KEY-----
```

The public key is also available online: <https://raw.githubusercontent.com/eformat/argocd-vault-sidecar/master/cosign.pub>

To verify an image:

```shell
curl --progress-bar -o cosign.pub https://raw.githubusercontent.com/eformat/argocd-vault-sidecar/master/cosign.pub
cosign verify --key cosign.pub quay.io/eformat/argocd-vault-sidecar:${VERSION}
```
