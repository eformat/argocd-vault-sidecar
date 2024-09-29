# argocd-vault-plugin working with SOPS and AGE

https://argocd-vault-plugin.readthedocs.io/en/stable/backends/#sops

If you check this comment - https://github.com/argoproj-labs/argocd-vault-plugin/pull/265#issuecomment-1015577571

Has all the details you need to get it working.

See here for using `age` for AES encryption rather than pgp - https://github.com/getsops/sops?tab=readme-ov-file#22encrypting-using-age

This is a great video if you are new to SOPS - https://www.youtube.com/watch?v=V2PRhxphH2w

Do not call your encoded secret file "secret-test.enc.yaml" - as argocd will apply this file - rather just use "secret-test.enc"

Secret containing age private key - this mounts `age-key.txt` into the repo sidecar pod.

```yaml
apiVersion: v1
stringData:
  age-key.txt: |
    # created: 2024-09-05T09:30:53+10:00
    # public key: age1p8dtq658wa3tvkazx9686g770yvfq9yz0tv4hwmukyyvurppzuus5520ry
    AGE-SECRET-KEY-XXX
kind: Secret
metadata:
  name: sops-age-key
  namespace: openshift-gitops
type: Opaque
```

ConfigMap as part of argocd bootstrap

```yaml
  sops-age-plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-sops-age-plugin
    spec:
      generate:
        command: ["sh", "-c"]
        args: ['AVP_TYPE=sops argocd-vault-plugin generate ./']
```

ArgoCD CR snippet (you need a sidecar image with age and sops binaries in it like this one).

```yaml
      - command:
          - /var/run/argocd/argocd-cmp-server
        env:
          - name: SOPS_AGE_KEY_FILE
            value: /var/run/secrets/age-key.txt
        image: 'quay.io/eformat/argocd-vault-sidecar:2.12.3'
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
```
