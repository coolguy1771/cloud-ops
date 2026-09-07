# Postgres Node Replacement Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Postgres after worker replacement without deleting or recreating persistent storage.

**Architecture:** Narrow CloudNativePG topology spread selectors to database instance pods so PgBouncer does not distort placement, make regional spreading preferred so region-pinned volumes take precedence, and expand WAL volumes through the CSI driver's supported in-place expansion. Restore healthy worker capacity operationally by removing stale cordons, then let Flux apply the Git-owned manifest and verify CNPG readiness.

**Tech Stack:** Kubernetes, Flux, CloudNativePG, Kustomize, YAML

---

### Task 1: Correct CloudNativePG scheduling and WAL capacity

**Files:**
- Modify: `kubernetes/apps/database/cluster/app/cluster.yaml:34-39,118-136`

- [ ] **Step 1: Run a failing selector assertion**

Run:

```bash
yq -e '[.spec.topologySpreadConstraints[] | .labelSelector.matchLabels."cnpg.io/podRole"] | all_c(. == "instance")' kubernetes/apps/database/cluster/app/cluster.yaml
```

Expected: exit status 1 because both selectors currently omit `cnpg.io/podRole`.

- [ ] **Step 2: Add the instance role to both selectors and soften regional spreading**

Each topology spread constraint must contain:

```yaml
labelSelector:
  matchLabels:
    cnpg.io/cluster: postgres
    cnpg.io/podRole: instance
```

The constraint with `topologyKey: topology.kubernetes.io/region` must use:

```yaml
whenUnsatisfiable: ScheduleAnyway
```

WAL storage must request an expandable capacity:

```yaml
walStorage:
  size: 20Gi
  storageClass: hcloud-volumes
```

- [ ] **Step 3: Re-run the selector assertion**

Run the command from Step 1.

Expected: exit status 0 and output `true`.

- [ ] **Step 4: Build the database manifests**

Run:

```bash
kustomize build kubernetes/apps/database/cluster/app
```

Expected: exit status 0 and a rendered `postgresql.cnpg.io/v1` Cluster containing both instance-only topology selectors, preferred regional spreading, and `20Gi` WAL storage.

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
flux reconcile kustomization postgres --namespace database --with-source
```

Expected: source and Kustomization reconciliation succeed.

- [ ] **Step 3: Verify the live selector**

```bash
kubectl -n database get cluster postgres -o yaml
```

Expected: both `spec.topologySpreadConstraints` entries select `cnpg.io/podRole: instance`, regional spreading uses `ScheduleAnyway`, and `spec.walStorage.size` is `20Gi`.

- [ ] **Step 4: Verify WAL PVC expansion**

```bash
kubectl -n database get pvc postgres-1-wal postgres-2-wal postgres-3-wal
```

Expected: all three claims are `Bound`, request `20Gi`, and report at least `20Gi` capacity.

- [ ] **Step 5: Wait for all database instances**

```bash
kubectl -n database wait --for=condition=Ready pod/postgres-1 pod/postgres-2 pod/postgres-3 --timeout=15m
```

Expected: all three pods satisfy `Ready`.

- [ ] **Step 6: Verify CNPG and pod placement**

```bash
kubectl -n database get cluster postgres
kubectl -n database get pods -l cnpg.io/podRole=instance -o wide
```

Expected: the Cluster reports three ready instances and each Postgres instance runs where its existing volume affinity permits.

### Task 4: Recover after loss of every WAL volume

**Files:**
- Modify: `kubernetes/apps/database/cluster/app/cluster.yaml:73-106`

- [ ] **Step 1: Preserve the backup source and separate future archives**

Configure the external recovery source with:

```yaml
serverName: postgres-recovered
```

Configure the active archiver with:

```yaml
serverName: postgres-recovered-20260907
```

Expected: recovery reads the completed `postgres-recovered` chain without writing new backups into it.

- [ ] **Step 2: Validate, commit, and push the recovery configuration**

```bash
kustomize build kubernetes/apps/database/cluster/app
git add kubernetes/apps/database/cluster/app/cluster.yaml docs/superpowers/
git commit -m "fix(database): restore postgres after WAL loss"
git push origin main
```

Expected: the manifests build and `main` contains the recovery source change.

- [ ] **Step 3: Suspend Flux and remove the unusable cluster storage**

```bash
flux suspend kustomization postgres --namespace database
kubectl -n database delete cluster postgres --wait=true
kubectl -n database delete pvc postgres-1 postgres-2 postgres-3 --ignore-not-found --wait=true
```

Expected: the Cluster, instance pods, and all six old claims are absent. Backup CRs, secrets, certificates, ObjectStore, and ScheduledBackup remain.

- [ ] **Step 4: Resume Flux and initiate recovery**

```bash
flux resume kustomization postgres --namespace database
flux reconcile kustomization postgres --namespace database --with-source
```

Expected: Flux applies the recovery revision and CNPG creates a new `postgres` Cluster with fresh data and WAL claims.

- [ ] **Step 5: Verify recovery**

```bash
kubectl -n database wait --for=condition=Ready cluster/postgres --timeout=30m
kubectl -n database get cluster postgres
kubectl -n database get pods -l cnpg.io/podRole=instance -o wide
kubectl -n database get pvc
```

Expected: the Cluster reports three ready instances, six claims are bound, every WAL claim has at least `20Gi`, and continuous archiving is healthy.
