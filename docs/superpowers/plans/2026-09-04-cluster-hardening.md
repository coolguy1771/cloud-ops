# Cluster Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair active CNPG and certificate reconciliation failures, remove leaked namespace drift, and incrementally harden cloud-ops infrastructure, admission, networking, GitOps feedback, and capacity planning.

**Architecture:** Apply the approved design in four independently reversible phases: active-fault repair, Terraform safety, admission/network isolation, and operational feedback. Every GitOps resource follows the repository's namespace → Flux Kustomization → app Kustomization structure; live cleanup and Terraform state migration occur only after preflight checks.

**Tech Stack:** Kubernetes 1.36, Talos/Omni, CiliumNetworkPolicy, Istio ambient, Flux, External Secrets/1Password Connect, HCP Terraform, Hetzner Cloud, GitHub Actions, Kyverno 1.19/chart 3.9, Fairwinds VPA chart 5.0.1.

---

## File map

| Area | Files |
|---|---|
| CNPG repair | Modify `kubernetes/apps/database/cluster/app/networkpolicy.yaml` |
| Certificate migration | Modify `kubernetes/apps/network/certificates/export/pushsecret.yaml`, `kubernetes/apps/network/certificates/import/externalsecret.yaml` |
| Terraform safety | Modify `infrastructure/terraform/versions.tf`, `servers.tf`, `loadbalancer.tf`, `firewall.tf`; create `docs/runbooks/terraform-cloud-migration.md` |
| Terraform CI | Create `.github/workflows/terraform.yaml`, `.tflint.hcl` |
| Kyverno | Create `kubernetes/apps/kyverno-system/{namespace.yaml,kustomization.yaml}`, `kubernetes/apps/kyverno-system/kyverno/{ks.yaml,app/{helmrepository.yaml,helmrelease.yaml,kustomization.yaml}}` |
| Policies | Create `kubernetes/apps/kyverno-system/policies/{ks.yaml,app/{kustomization.yaml,disallow-default-namespace.yaml,audit-workload-standards.yaml}}` |
| PSA | Modify application namespace manifests under `kubernetes/apps/{authentik,authservice,database,mimir-system,network,observability}/namespace.yaml` |
| Ingress isolation | Create or modify namespace-level `networkpolicy.yaml` files and their `kustomization.yaml` resource lists |
| Flux GitHub status | Create `kubernetes/apps/flux-system/github-status/{ks.yaml,secrets/,app/}`; modify `kubernetes/apps/flux-system/kustomization.yaml` |
| VPA | Create `kubernetes/apps/vpa-system/{namespace.yaml,kustomization.yaml}`, controller and recommendation manifests |

## Task 1: Repair CloudNativePG instance-manager access

**Files:**
- Modify: `kubernetes/apps/database/cluster/app/networkpolicy.yaml:36-55`

- [ ] **Step 1: Record the failing health assertion**

Run:

```bash
kubectl get cluster postgres -n database -o jsonpath='{.status.phase}{"\n"}'
kubectl logs -n cnpg-system deploy/cloudnative-pg --since=10m \
  | rg 'Cannot extract Pod status.*context deadline exceeded'
```

Expected before the fix: phase contains `Instance Status Extraction Error` and
the logs contain timeouts to `https://<pod-ip>:8000/pg/status`.

- [ ] **Step 2: Add the minimal operator allowance**

Append this ingress item before the existing Postgres self-traffic item:

```yaml
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: cnpg-system
            app.kubernetes.io/name: cloudnative-pg
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
            - port: "15008"
              protocol: TCP
```

- [ ] **Step 3: Render and validate**

Run:

```bash
just kube render-local-ks flux-system cluster-apps >/tmp/cluster-apps.yaml
rg -n -A14 'io.kubernetes.pod.namespace: cnpg-system' /tmp/cluster-apps.yaml
```

Expected: one database policy rule containing ports `8000` and `15008`.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/apps/database/cluster/app/networkpolicy.yaml
git commit -m "fix(database): allow CNPG instance status traffic"
```

## Task 2: Split certificate persistence into single-property items

**Files:**
- Modify: `kubernetes/apps/network/certificates/export/pushsecret.yaml`
- Modify: `kubernetes/apps/network/certificates/import/externalsecret.yaml`

- [ ] **Step 1: Capture current certificate integrity**

Run:

```bash
kubectl get secret cloud-witl-xyz-tls -n network \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -fingerprint -sha256
kubectl get pushsecret cloud-witl-xyz-tls -n network -o yaml \
  | rg 'Unable to update|Ready|refreshTime'
```

Save the fingerprint in the implementation notes. Never print or decode
`tls.key`.

- [ ] **Step 2: Replace the multi-property PushSecret**

Define two PushSecrets in `export/pushsecret.yaml`. Each selects the existing
`cloud-witl-xyz-tls` Secret and writes one Base64 value:

```yaml
---
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: cloud-witl-xyz-tls-crt
spec:
  refreshInterval: 1h
  secretStoreRefs:
    - name: onepassword-connect
      kind: ClusterSecretStore
  selector:
    secret:
      name: cloud-witl-xyz-tls
  template:
    data:
      value: '{{ index . "tls.crt" | b64enc }}'
  data:
    - match:
        secretKey: tls.crt
        remoteRef:
          remoteKey: cloud-witl-xyz-tls-crt
          property: value
---
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: cloud-witl-xyz-tls-key
spec:
  refreshInterval: 1h
  secretStoreRefs:
    - name: onepassword-connect
      kind: ClusterSecretStore
  selector:
    secret:
      name: cloud-witl-xyz-tls
  template:
    data:
      value: '{{ index . "tls.key" | b64enc }}'
  data:
    - match:
        secretKey: tls.key
        remoteRef:
          remoteKey: cloud-witl-xyz-tls-key
          property: value
```

- [ ] **Step 3: Update the importer**

Replace `dataFrom.extract` with explicit remote references:

```yaml
  data:
    - secretKey: tls.crt
      remoteRef:
        key: cloud-witl-xyz-tls-crt
        property: value
        decodingStrategy: Base64
    - secretKey: tls.key
      remoteRef:
        key: cloud-witl-xyz-tls-key
        property: value
        decodingStrategy: Base64
```

Keep `refreshPolicy: CreatedOnce`, `creationPolicy: Orphan`, and the TLS target
template unchanged.

- [ ] **Step 4: Validate the final-state manifests**

```bash
kustomize build kubernetes/apps/network/certificates/export \
  | yq 'select(.kind == "PushSecret") | .metadata.name'
kustomize build kubernetes/apps/network/certificates/import \
  | yq 'select(.kind == "ExternalSecret") | .spec.data'
```

Expected: two PushSecrets and two decoded importer keys.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/apps/network/certificates/{export/pushsecret.yaml,import/externalsecret.yaml}
git commit -m "fix(certificates): split 1Password TLS export"
```

## Task 3: Clean unmanaged default-namespace credentials

**Files:**
- No repository files; this is a one-time live-state correction before Kyverno enforcement.

- [ ] **Step 1: Prove the credentials are not consumed**

```bash
kubectl get pods,deploy,statefulset,daemonset,job,cronjob -n default
kubectl get pods -A -o json | jq -e '
  [.items[] |
   select(any(.spec.volumes[]?; .secret.secretName as $n |
     ["authentik-db","cnpg-backup","grafana-db","kiali","kiali-mimir-org",
      "kiali-oauth-client-id","tempo-r2-credentials"] | index($n)))] | length == 0'
```

Expected: only built-in Services in `default`; `jq` exits zero.

- [ ] **Step 2: Delete only the seven unmanaged ExternalSecrets**

```bash
kubectl delete externalsecret -n default \
  authentik-db cnpg-backup grafana-db kiali-mimir-org \
  kiali-oauth kiali-oauth-client-id tempo-r2-credentials
```

- [ ] **Step 3: Remove the orphaned `kiali` Secret**

The other generated Secrets use owner/managed deletion behavior. Verify them,
then remove only leftovers:

```bash
kubectl get secret -n default \
  authentik-db cnpg-backup grafana-db kiali kiali-mimir-org \
  kiali-oauth-client-id tempo-r2-credentials --ignore-not-found
kubectl delete secret kiali -n default --ignore-not-found
```

Expected: none of the listed credentials remains.

## Task 4: Configure HCP Terraform and protect infrastructure

**Files:**
- Modify: `infrastructure/terraform/versions.tf:1-30`
- Modify: `infrastructure/terraform/servers.tf:26-28`
- Modify: `infrastructure/terraform/loadbalancer.tf:1-17`
- Modify: `infrastructure/terraform/firewall.tf:9-23,65-87`
- Create: `docs/runbooks/terraform-cloud-migration.md`

- [ ] **Step 1: Add the HCP Terraform cloud block**

Add inside `terraform {}`:

```hcl
  cloud {
    organization = "home-ops"

    workspaces {
      project = "cloud-ops"
      name    = "cloud-ops"
    }
  }
```

Remove the commented backend examples. Document that the workspace execution
mode must be **Local**, because this configuration invokes local `omnictl`
provisioners.

- [ ] **Step 2: Enable deletion protection**

Change the control-plane server settings to:

```hcl
  delete_protection  = true
  rebuild_protection = true
```

Also set `delete_protection = true` on
`hcloud_load_balancer.control_plane`.

- [ ] **Step 3: Disable the load balancer public interface**

Set this on `hcloud_load_balancer_network.control_plane`:

```hcl
  enable_public_interface = false
```

- [ ] **Step 4: Restrict firewall source ranges**

Change control-plane `6443` and `50000`, and worker `50000` and
`30000-32767`, to:

```hcl
    source_ips = [var.network_ip_range]
```

Do not alter etcd, kubelet, Cilium, or ICMP rules in this task.

- [ ] **Step 5: Write the migration runbook**

The runbook must use this exact safe sequence:

```bash
cd infrastructure/terraform
terraform login
terraform state pull >"terraform-state-backup-$(date +%Y%m%dT%H%M%S).json"
terraform init -migrate-state
terraform state list
terraform plan -out=tfplan
terraform show tfplan
```

It must require: HCP project/workspace creation, Local execution mode, state
list comparison, zero unexpected creates/deletes, Omni proxy verification,
and a separately approved `terraform apply tfplan`.

- [ ] **Step 6: Validate without migrating live state**

```bash
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform init -backend=false
terraform -chdir=infrastructure/terraform validate
```

Expected: all commands succeed without contacting HCP state.

- [ ] **Step 7: Commit**

```bash
git add infrastructure/terraform/{versions.tf,servers.tf,loadbalancer.tf,firewall.tf} \
  docs/runbooks/terraform-cloud-migration.md
git commit -m "feat(terraform): harden state and control plane access"
```

## Task 5: Add Terraform CI

**Files:**
- Create: `.github/workflows/terraform.yaml`
- Create: `.tflint.hcl`

- [ ] **Step 1: Add TFLint configuration**

```hcl
config {
  call_module_type = "all"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
```

- [ ] **Step 2: Add the infrastructure workflow**

Create a pull-request workflow filtered to `infrastructure/terraform/**`,
`.tflint.hcl`, and its own workflow file. Use:

```yaml
permissions:
  contents: read
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  - uses: hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd # v3.1.2
  - uses: terraform-linters/setup-tflint@4cb9feea73331a35b422df102992a03a44a3bb33 # v6.2.1
  - run: terraform fmt -check -recursive
  - run: terraform init -backend=false
  - run: terraform validate
  - run: tflint --init
  - run: tflint --recursive
  - uses: aquasecurity/trivy-action@b6643a29fecd7f34b3597bc6acb0a98b03d33ff8 # v0.33.1
    with:
      scan-type: config
      scan-ref: infrastructure/terraform
      exit-code: "1"
      severity: HIGH,CRITICAL
```

Set `working-directory: infrastructure/terraform` only on Terraform/TFLint
shell steps; Trivy's path remains repository-relative.

- [ ] **Step 3: Run local equivalents**

```bash
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform init -backend=false
terraform -chdir=infrastructure/terraform validate
tflint --chdir=infrastructure/terraform --init
tflint --chdir=infrastructure/terraform --recursive
trivy config --exit-code 1 --severity HIGH,CRITICAL infrastructure/terraform
```

Expected: no formatting, validation, lint, or high/critical configuration
findings.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/terraform.yaml .tflint.hcl
git commit -m "ci(terraform): validate infrastructure changes"
```

## Task 6: Install Kyverno with high availability

**Files:**
- Create: `kubernetes/apps/kyverno-system/namespace.yaml`
- Create: `kubernetes/apps/kyverno-system/kustomization.yaml`
- Create: `kubernetes/apps/kyverno-system/kyverno/ks.yaml`
- Create: `kubernetes/apps/kyverno-system/kyverno/app/{helmrepository.yaml,helmrelease.yaml,kustomization.yaml}`

- [ ] **Step 1: Add namespace and Flux wiring**

Use namespace labels:

```yaml
istio.io/dataplane-mode: ambient
pod-security.kubernetes.io/enforce: baseline
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/warn: restricted
```

The root kustomization includes the namespace and `./kyverno/ks.yaml`.
The Flux Kustomization depends on `cilium` and targets `kyverno-system`.

- [ ] **Step 2: Add the official Kyverno source**

Use a `HelmRepository` with:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
spec:
  interval: 1h
  url: https://kyverno.github.io/kyverno/
```

Set the HelmRelease chart name to `kyverno` and version to `3.9.0`.

- [ ] **Step 3: Configure the HelmRelease**

Use three admission-controller replicas, two replicas for background, cleanup,
and reports controllers, PDBs with `minAvailable: 1`, topology spreading by
`kubernetes.io/hostname`, ServiceMonitor creation, explicit requests/limits,
and webhook failure policy `Ignore` during rollout. Do not install the optional
policy chart.

- [ ] **Step 4: Render and commit**

```bash
just kube render-local-ks flux-system cluster-apps >/tmp/cluster-apps.yaml
rg -n 'name: kyverno|replicas: 3|failurePolicy: Ignore' /tmp/cluster-apps.yaml
git add kubernetes/apps/kyverno-system
git commit -m "feat(kyverno): install admission policy engine"
```

## Task 7: Add default-namespace enforcement and audit policies

**Files:**
- Create: `kubernetes/apps/kyverno-system/policies/ks.yaml`
- Create: `kubernetes/apps/kyverno-system/policies/app/kustomization.yaml`
- Create: `kubernetes/apps/kyverno-system/policies/app/disallow-default-namespace.yaml`
- Create: `kubernetes/apps/kyverno-system/policies/app/audit-workload-standards.yaml`
- Modify: `kubernetes/apps/kyverno-system/kustomization.yaml`

- [ ] **Step 1: Write policy fixtures before policies**

Create `/tmp/kyverno-tests/{allowed,denied}.yaml`: an allowed Deployment in
`authentik`, and denied Deployment plus ExternalSecret in `default`.

- [ ] **Step 2: Add enforced default-namespace policy**

Create a `ClusterPolicy` with `validationFailureAction: Enforce`, matching
Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, ReplicaSets,
ReplicationControllers, ExternalSecrets, PushSecrets, and SecretStores where
`request.namespace == 'default'`. The validation message is:
`The default namespace is reserved; choose an application namespace.`

- [ ] **Step 3: Add audit workload standards**

Create separate `Audit` rules requiring container requests, disallowing
`:latest`/untagged images, and requiring `allowPrivilegeEscalation: false`,
capability drop `ALL`, and a runtime-default seccomp profile. Exclude
`kube-system`, `istio-system`, `kyverno-system`, `cnpg-system`,
`cert-manager`, `external-secrets`, and `flux-system`.

- [ ] **Step 4: Test and commit**

```bash
kyverno apply kubernetes/apps/kyverno-system/policies/app \
  --resource /tmp/kyverno-tests/allowed.yaml
! kyverno apply kubernetes/apps/kyverno-system/policies/app \
  --resource /tmp/kyverno-tests/denied.yaml
git add kubernetes/apps/kyverno-system
git commit -m "feat(kyverno): enforce namespace and audit workload standards"
```

## Task 8: Tighten PSA and application ingress

**Files:**
- Modify: namespace manifests and root kustomizations for `authentik`, `authservice`, `database`, `mimir-system`, `network`, `observability`
- Create: `networkpolicy.yaml` in each root lacking an existing policy

- [ ] **Step 1: Add PSA labels**

Set `audit` and `warn` to `restricted` with `*-version: latest` in all six
namespaces. Set `enforce: baseline` in `authentik`, `authservice`, `database`,
`mimir-system`, and `network`. Keep `observability` enforcement privileged
because node-exporter requires it.

- [ ] **Step 2: Add ambient ingress isolation**

For each namespace without a specialized policy, add:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ambient-ingress
spec:
  endpointSelector: {}
  ingress:
    - fromEntities:
        - cluster
      toPorts:
        - ports:
            - port: "15008"
              protocol: TCP
```

Keep the database's label-specific policy instead of adding a second catch-all
policy. Add each file to its namespace root kustomization. Do not add egress
default-deny in this task.

- [ ] **Step 3: Render and inspect policy count**

```bash
just kube render-local-ks flux-system cluster-apps >/tmp/cluster-apps.yaml
yq '[select(.kind == "CiliumNetworkPolicy")] | length' /tmp/cluster-apps.yaml
yq 'select(.kind == "Namespace") |
  [.metadata.name,.metadata.labels."pod-security.kubernetes.io/audit",
   .metadata.labels."pod-security.kubernetes.io/enforce"]' /tmp/cluster-apps.yaml
```

Expected: all six application namespaces report restricted audit; only
observability remains privileged.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/apps/{authentik,authservice,database,mimir-system,network,observability}
git commit -m "feat(network): isolate ambient application ingress"
```

## Task 9: Publish Flux reconciliation status to GitHub

**Files:**
- Create: `kubernetes/apps/flux-system/github-status/secrets/{ks.yaml,app/externalsecret.yaml,app/kustomization.yaml}`
- Create: `kubernetes/apps/flux-system/github-status/app/{githubaccesstoken.yaml,provider.yaml,alert.yaml,kustomization.yaml}`
- Create: `kubernetes/apps/flux-system/github-status/ks.yaml`
- Modify: `kubernetes/apps/flux-system/kustomization.yaml`

- [ ] **Step 1: Materialize GitHub App configuration separately**

Create an ExternalSecret extracting the existing `actions-runner` item into
`github-status-app`, mapping app ID, installation ID, and private key. This
secret Kustomization depends on `onepassword-connect`.

- [ ] **Step 2: Generate a short-lived status token**

Use a `GithubAccessToken` generator scoped to repository `cloud-ops`, with
`statuses: write` and `contents: read`. Resolve app and installation IDs through
Flux `postBuild.substituteFrom` from `github-status-app`; reference the private
key key in that Secret. Use the existing
`kubernetes/components/alerts/github-status/externalsecret.yaml` to refresh the
generated token every 30 minutes.

- [ ] **Step 3: Add Provider and Alert**

Use:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: github-status
spec:
  type: github
  address: https://github.com/coolguy1771/cloud-ops
  secretRef:
    name: github-status-token-secret
---
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: github-status
spec:
  providerRef:
    name: github-status
  eventSeverity: info
  eventSources:
    - kind: GitRepository
      name: flux-system
    - kind: Kustomization
      name: '*'
    - kind: HelmRelease
      name: '*'
```

- [ ] **Step 4: Render and commit**

```bash
just kube render-local-ks flux-system cluster-apps >/tmp/cluster-apps.yaml
rg -n 'kind: (GithubAccessToken|Provider|Alert)|github-status-token' /tmp/cluster-apps.yaml
git add kubernetes/apps/flux-system kubernetes/components/alerts/github-status
git commit -m "feat(flux): report reconciliation status to GitHub"
```

## Task 10: Install recommendation-only VPA

**Files:**
- Create: `kubernetes/apps/vpa-system/namespace.yaml`
- Create: `kubernetes/apps/vpa-system/kustomization.yaml`
- Create: `kubernetes/apps/vpa-system/vpa/ks.yaml`
- Create: `kubernetes/apps/vpa-system/vpa/app/{helmrepository.yaml,helmrelease.yaml,kustomization.yaml}`
- Create: `kubernetes/apps/vpa-system/recommendations/{ks.yaml,app/{kustomization.yaml,vpas.yaml}}`

- [ ] **Step 1: Add controller namespace and source**

Use baseline PSA enforcement plus restricted audit/warn. Add a Fairwinds
HelmRepository at `https://charts.fairwinds.com/stable`.

- [ ] **Step 2: Install only the recommender**

Install chart `vpa` version `5.0.1`; enable one recommender replica and disable
the updater and admission controller. Configure explicit resources and a
ServiceMonitor.

- [ ] **Step 3: Add recommendation objects**

Create VerticalPodAutoscalers with `updateMode: "Off"` for:

- `authentik-server`, `authentik-worker`
- `mimir`
- `loki-read`, `loki-write`, `loki-backend`
- `tempo-ingester`, `tempo-distributor`, `tempo-querier`,
  `tempo-query-frontend`, `tempo-metrics-generator`
- `grafana-deployment`
- `k8s-monitoring-alloy-metrics`

Set the correct `targetRef.apiVersion` and `kind` for each live Deployment,
StatefulSet, or DaemonSet. Do not target Istio waypoints or any resource whose
replica ownership conflicts with an operator.

- [ ] **Step 4: Validate and commit**

```bash
just kube render-local-ks flux-system cluster-apps >/tmp/cluster-apps.yaml
yq 'select(.kind == "VerticalPodAutoscaler") |
  [.metadata.namespace,.metadata.name,.spec.updatePolicy.updateMode]' \
  /tmp/cluster-apps.yaml
git add kubernetes/apps/vpa-system
git commit -m "feat(vpa): add recommendation-only capacity guidance"
```

Expected: every VPA reports update mode `Off`.

## Task 11: Full verification and guarded rollout

**Files:**
- Modify only if validation exposes a defect in an earlier task.

- [ ] **Step 1: Run repository validation**

```bash
git diff --check origin/main...HEAD
just kube render-local-ks flux-system cluster-apps >/tmp/cluster-apps.yaml
docker run --rm -v "$PWD:/github/workspace" \
  -e GITHUB_TOKEN ghcr.io/allenporter/flux-local:v8.0.1 \
  test --all-namespaces --enable-helm \
  --path /github/workspace/kubernetes/flux/cluster --verbose
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform init -backend=false
terraform -chdir=infrastructure/terraform validate
```

Expected: all commands exit zero.

- [ ] **Step 2: Reconcile fault repairs before hardening**

After merge/push, reconcile CNPG and certificate Kustomizations. Verify:

```bash
kubectl get cluster postgres -n database
kubectl get pushsecret,externalsecret -n network
kubectl logs -n cnpg-system deploy/cloudnative-pg --since=10m \
  | rg 'Cannot extract Pod status|context deadline exceeded' && exit 1 || true
```

Expected: healthy CNPG phase; both PushSecrets and importer Ready; no current
instance-status timeouts.

- [ ] **Step 3: Reconcile Kyverno and policies**

```bash
flux reconcile kustomization kyverno --with-source
kubectl wait -n kyverno-system --for=condition=Available deploy --all --timeout=5m
flux reconcile kustomization kyverno-policies --with-source
kubectl get clusterpolicy,policyreport -A
```

Expected: controllers Available, default policy Enforce, workload policies
Audit.

- [ ] **Step 4: Reconcile namespace isolation one namespace at a time**

For each selected namespace, reconcile its owning Kustomization and verify
Pods Ready, DNS resolution, HTTPRoute health, metrics targets, and database
connections before moving to the next namespace. Stop and revert only the
failing namespace policy if any check fails.

- [ ] **Step 5: Migrate state before applying Terraform**

Follow `docs/runbooks/terraform-cloud-migration.md`. Do not apply unless the
remote state list matches the local backup and the plan contains only intended
protection/firewall/load-balancer updates. Verify Omni Kubernetes and Talos
proxy access before and after apply.

- [ ] **Step 6: Verify Flux status and VPA recommendations**

```bash
kubectl get provider,alert -n flux-system
kubectl get externalsecret github-status-token -n flux-system
kubectl get vpa -A
kubectl describe vpa -A | rg 'Recommendation|Target|Lower Bound|Upper Bound'
```

Expected: Provider/Alert and token are Ready; GitHub shows commit status; VPA
recommendations appear without pod restarts or resource mutation.

- [ ] **Step 7: Review final live state**

```bash
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
flux get kustomizations -A
flux get helmreleases -A
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp
```

Expected: all nodes Ready, no unexpected non-running Pods, all Flux resources
Ready, and no recurring CNPG, PushSecret, webhook, or network-policy warnings.
