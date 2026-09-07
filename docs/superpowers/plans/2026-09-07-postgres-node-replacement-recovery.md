# Postgres Node Replacement Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Postgres scheduling after worker replacement without changing or recreating persistent storage.

**Architecture:** Narrow CloudNativePG topology spread selectors to database instance pods so PgBouncer does not distort placement. Restore healthy worker capacity operationally by removing stale cordons, then let Flux apply the Git-owned manifest and verify CNPG readiness.

**Tech Stack:** Kubernetes, Flux, CloudNativePG, Kustomize, YAML

---

### Task 1: Correct CloudNativePG topology selection

**Files:**
- Modify: `kubernetes/apps/database/cluster/app/cluster.yaml:118-134`

- [ ] **Step 1: Run a failing selector assertion**

Run:

```bash
yq -e '[.spec.topologySpreadConstraints[] | .labelSelector.matchLabels."cnpg.io/podRole"] | all_c(. == "instance")' kubernetes/apps/database/cluster/app/cluster.yaml
```

Expected: exit status 1 because both selectors currently omit `cnpg.io/podRole`.

- [ ] **Step 2: Add the instance role to both selectors**

Each topology spread constraint must contain:

```yaml
labelSelector:
  matchLabels:
    cnpg.io/cluster: postgres
    cnpg.io/podRole: instance
```

- [ ] **Step 3: Re-run the selector assertion**

Run the command from Step 1.

Expected: exit status 0 and output `true`.

- [ ] **Step 4: Build the database manifests**

Run:

```bash
kustomize build kubernetes/apps/database/cluster/app
```

Expected: exit status 0 and a rendered `postgresql.cnpg.io/v1` Cluster containing both instance-only topology selectors.

- [ ] **Step 5: Commit the correction**

```bash
git add kubernetes/apps/database/cluster/app/cluster.yaml docs/superpowers/plans/2026-09-07-postgres-node-replacement-recovery.md
git commit -m "fix(database): restrict postgres topology spreading"
```

### Task 2: Restore worker schedulability

**Files:**
- No repository files modified.

- [ ] **Step 1: Confirm the stale-cordoned nodes are healthy**

```bash
kubectl get nodes cloud-ops-workers-hel1-fhzx5d cloud-ops-workers-nbg1-xhtsck
omnictl get clustermachinestatuses -o json
```

Expected: both Kubernetes nodes are `Ready`; their Omni cluster machine statuses have `ready: true` and no error.

- [ ] **Step 2: Uncordon both healthy workers**

```bash
kubectl uncordon cloud-ops-workers-hel1-fhzx5d cloud-ops-workers-nbg1-xhtsck
```

Expected: both nodes report `uncordoned`.

- [ ] **Step 3: Confirm all workers are schedulable**

```bash
kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,UNSCHEDULABLE:.spec.unschedulable'
```

Expected: all seven workers report `READY=True` and no worker reports `UNSCHEDULABLE=true`.

### Task 3: Reconcile and verify database recovery

**Files:**
- No repository files modified.

- [ ] **Step 1: Push the committed GitOps correction**

```bash
git push origin main
```

Expected: `main` is accepted by `origin`.

- [ ] **Step 2: Reconcile the database Kustomization through Flux**

```bash
flux reconcile kustomization database-cluster --with-source
```

Expected: source and Kustomization reconciliation succeed.

- [ ] **Step 3: Verify the live selector**

```bash
kubectl -n database get cluster postgres -o yaml
```

Expected: both `spec.topologySpreadConstraints` entries select `cnpg.io/podRole: instance`.

- [ ] **Step 4: Wait for all database instances**

```bash
kubectl -n database wait --for=condition=Ready pod/postgres-1 pod/postgres-2 pod/postgres-3 --timeout=15m
```

Expected: all three pods satisfy `Ready`.

- [ ] **Step 5: Verify CNPG and pod placement**

```bash
kubectl -n database get cluster postgres
kubectl -n database get pods -l cnpg.io/podRole=instance -o wide
```

Expected: the Cluster reports three ready instances and each Postgres instance runs in the region matching its existing volume affinity.
