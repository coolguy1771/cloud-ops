# Postgres scheduling recovery after worker replacement

## Problem

All seven worker nodes were replaced successfully, but two healthy replacement nodes remained cordoned. Separately, the CloudNativePG topology spread constraints select every pod with `cnpg.io/cluster: postgres`, including PgBouncer poolers. The running poolers skew region counts and force `postgres-1` toward `hel1`, while its existing Hetzner volumes are pinned to `fsn1`. Once scheduling recovered, CNPG found the WAL volumes for `postgres-1` and `postgres-2` 99.7% full and refused to start `postgres-1`.

## Design

1. Restrict both database topology spread constraints to pods carrying both `cnpg.io/cluster: postgres` and `cnpg.io/podRole: instance`.
2. Make regional spreading preferred because the existing region-pinned PVCs occupy two regions rather than all three. Volume node affinity takes precedence without recreating storage.
3. Increase `walStorage.size` to `20Gi` through the expandable `hcloud-volumes` StorageClass; do not delete or recreate PVCs.
4. Uncordon the two healthy replacement workers after confirming Omni and Kubernetes report them ready.
5. Reconcile the database Flux Kustomization and verify all three database instances become ready.

## Validation

- Build the database Kustomization locally.
- Confirm the rendered Cluster contains the instance-only selectors and requests `20Gi` WAL storage.
- Confirm all six database PVCs are bound and all three WAL PVCs have expanded to at least `20Gi`.
- Confirm all worker nodes are schedulable and ready.
- Confirm `postgres-1`, `postgres-2`, and `postgres-3` are running and ready.
- Confirm the CNPG Cluster reports three ready instances.

## Rollback

Revert the selector commit if reconciliation rejects the manifest. Re-cordon a worker only if it becomes unhealthy; no storage objects are changed by this repair.
