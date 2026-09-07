# Postgres scheduling recovery after worker replacement

## Problem

All seven worker nodes were replaced successfully, but two healthy replacement nodes remained cordoned. Separately, the CloudNativePG topology spread constraints select every pod with `cnpg.io/cluster: postgres`, including PgBouncer poolers. The running poolers skew region counts and force `postgres-1` toward `hel1`, while its existing Hetzner volumes are pinned to `fsn1`.

## Design

1. Restrict both database topology spread constraints to pods carrying both `cnpg.io/cluster: postgres` and `cnpg.io/podRole: instance`.
2. Preserve the hard one-instance-per-region policy and all existing PVCs.
3. Uncordon the two healthy replacement workers after confirming Omni and Kubernetes report them ready.
4. Reconcile the database Flux Kustomization and verify all three database instances become ready.

## Validation

- Build the database Kustomization locally.
- Confirm the rendered Cluster contains the instance-only selectors.
- Confirm all worker nodes are schedulable and ready.
- Confirm `postgres-1`, `postgres-2`, and `postgres-3` are running and ready.
- Confirm the CNPG Cluster reports three ready instances.

## Rollback

Revert the selector commit if reconciliation rejects the manifest. Re-cordon a worker only if it becomes unhealthy; no storage objects are changed by this repair.
