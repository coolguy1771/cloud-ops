# Cluster Hardening Design

## Objective

Improve the cloud-ops cluster's reliability, security, infrastructure safety,
and operational feedback without replacing its existing Talos, Omni, Flux,
Cilium, Istio ambient, External Secrets, or observability architecture.

The work repairs two active reconciliation faults first, then applies
infrastructure and policy hardening in stages so that a missing ambient or
operator network path cannot cause a cluster-wide outage.

## Scope

This design covers:

1. Restore CloudNativePG operator connectivity to Postgres instance managers.
2. Remove unmanaged credentials from the `default` namespace and prevent their
   recurrence.
3. Restrict Kubernetes, Talos, and NodePort exposure to private paths.
4. Replace the unreliable multi-property 1Password certificate PushSecret.
5. Migrate Terraform state to HCP Terraform and protect control-plane servers.
6. Add Terraform validation and security CI.
7. Tighten application namespace ingress isolation and Pod Security Admission.
8. Install Kyverno with an incremental policy rollout.
9. Publish Flux reconciliation status to GitHub.
10. Install VPA in recommendation-only mode for capacity right-sizing.

Synthetic monitoring and automatic VPA resource updates are explicitly out of
scope.

## Decisions

### Administrative access

Omni is the exclusive administrative entry point. The Kubernetes API load
balancer will no longer expose a public interface, and public access to Talos
TCP `50000` and worker NodePorts will be removed. Private load-balancer health
checks and cluster-internal communication remain allowed.

### Terraform state

HCP Terraform will use:

- Organization: `home-ops`
- Project: `cloud-ops`
- Workspace: `cloud-ops`

State migration must complete and a non-destructive plan must be reviewed
before infrastructure changes are applied.

### Certificate persistence

The wildcard certificate and key will be stored in separate 1Password items:

- `cloud-witl-xyz-tls-crt`
- `cloud-witl-xyz-tls-key`

Each PushSecret writes one remote property. The importing ExternalSecret
reconstructs a `kubernetes.io/tls` Secret from both items. This avoids the
1Password provider's unreliable multi-property item update behavior while
retaining 1Password as the bootstrap and cross-cluster store.

### Admission governance

Kyverno will provide policy reporting and enforcement. The first enforced
policy blocks new workloads and secret-management resources in `default`.
Broader resource, image, and security-context policies begin in audit mode.

### Namespace hardening

Pod Security Admission uses restricted audit and warning labels broadly.
Baseline enforcement is enabled only for compatible application namespaces.

Cilium ingress isolation is introduced first for application namespaces:

- `authentik`
- `authservice`
- `database`
- `mimir-system`
- `observability`
- `network`

Every policy must retain DNS, Istio ambient HBONE TCP `15008`, metrics,
operator control paths, and documented application traffic. Egress
default-deny is deferred where the destination inventory is incomplete.

### Capacity recommendations

VPA runs with `updateMode: Off`. It produces recommendations for major
workloads but never changes pods, resource requests, or KEDA-managed replica
counts. Request changes are deferred until enough historical data exists.

## Rollout

### Phase 1: Repair active faults

#### CloudNativePG connectivity

Extend the existing database CiliumNetworkPolicy with a dedicated ingress rule:

- Source namespace: `cnpg-system`
- Source workload: CloudNativePG operator
- Destination: Postgres pods
- Ports: instance-manager TCP `8000` and ambient HBONE TCP `15008`

Existing Postgres client, monitoring, and replication rules remain unchanged.

#### Certificate export

Create the two single-property PushSecrets while preserving the existing
in-cluster TLS Secret. Wait for both remote writes to become healthy before
switching the importer to the split items. The migration must support future
cluster bootstrap from the new items.

#### Default namespace cleanup

Before deletion, verify no workload references the unmanaged duplicate
credentials. Remove these unmanaged ExternalSecrets and their generated
Secrets:

- `authentik-db`
- `cnpg-backup`
- `grafana-db`
- `kiali-mimir-org`
- `kiali-oauth`
- `kiali-oauth-client-id`
- `tempo-r2-credentials`

The Kubernetes and Talos Services in `default` are unaffected.

### Phase 2: Infrastructure safety

Add the HCP Terraform `cloud` block, migrate the complete current state, and
verify `terraform state list` before planning changes. Enable Hetzner deletion
and rebuild protection on all control-plane servers.

Disable the control-plane load balancer's public interface. Restrict control
plane `6443` and `50000`, and worker `50000` and NodePorts, to the private
network where those paths remain necessary.

Add an infrastructure CI workflow for Terraform changes. It runs:

- `terraform fmt -check -recursive`
- validation-safe `terraform init`
- `terraform validate`
- `tflint`
- Terraform configuration security scanning

CI receives no production cloud credentials, performs no apply, and pins
third-party GitHub Actions by commit SHA.

### Phase 3: Policy and isolation

Install Kyverno with multiple replicas, disruption budgets, topology
spreading, explicit resources, and monitoring.

Policy modes:

- Enforce: prohibit accidental workloads and secret-management resources in
  `default`.
- Audit: missing resource requests, mutable image tags, unsafe security
  contexts, and unjustified privilege.

Add restricted PSA audit/warn labels broadly and baseline enforcement only
where rendered workloads are compatible.

Introduce application namespace Cilium policies one namespace at a time.
Validate DNS, ambient HBONE, monitoring, database, observability, webhook, and
operator paths after each reconciliation.

### Phase 4: Operations and capacity

Configure Flux notification-controller to publish reconciliation status to
GitHub. Reuse the existing External Secrets and GitHub App credential pattern
without committing a token.

Install VPA and recommendation-only VerticalPodAutoscaler resources for major
workloads. KEDA remains the only component changing replica counts. Review VPA
recommendations after sufficient history and preserve per-region N+1
scheduling capacity when later adjusting requests.

## Validation

### Repository checks

- Render every affected Flux Kustomization.
- Run `flux-local test` across the cluster tree.
- Run Terraform formatting and validation.
- Test Kyverno policies with allowed and denied fixtures.
- Check rendered manifests for accidental credential material.

### Live checks

1. Confirm CNPG can query all three instance managers and clears the status
   extraction error.
2. Confirm both new certificate PushSecrets reconcile without recurring
   controller errors and that the importer produces a valid TLS Secret.
3. Confirm no workload references the duplicate default-namespace secrets,
   then verify cleanup.
4. Confirm Kyverno webhooks are healthy before adding policies.
5. Test required application paths after each namespace policy.
6. Confirm HCP Terraform contains the complete state and produces no unexpected
   creates or destroys.
7. Confirm Omni Kubernetes and Talos access before disabling public interfaces.
8. Confirm GitHub receives Flux reconciliation status.
9. Confirm VPA recommendations appear without pod mutation or restarts.

## Failure handling and rollback

- Retain the current Kubernetes TLS Secret until the split-item import is
  healthy.
- Keep initial broad Kyverno checks in audit mode. Only the narrowly tested
  `default` namespace policy enforces immediately.
- Split network-policy changes by namespace so one policy can be reverted
  independently.
- Do not apply Terraform firewall changes if Omni proxy access or migrated
  state verification fails.
- Keep VPA in recommendation-only mode so rollback never requires undoing
  automatic resource mutations.

## Completion criteria

- CNPG reports healthy instance status for all replicas.
- No unmanaged credentials remain in `default`, and policy prevents recurrence.
- Certificate export and import reconcile without recurring 1Password errors.
- Kubernetes, Talos, and NodePort services are no longer publicly reachable.
- HCP Terraform holds the complete state and control-plane protection is
  enabled.
- CI validates Terraform and Kubernetes policy changes.
- Selected namespaces pass PSA and required network-connectivity checks.
- Flux reports reconciliation status to GitHub.
- VPA recommendations are available without modifying workloads.
