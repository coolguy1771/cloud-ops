# Review VPA capacity recommendations

The Vertical Pod Autoscalers in this repository use `updateMode: Off`. They
observe usage and publish recommendations but never resize or restart pods.
KEDA remains responsible for replica counts.

## Review cadence

Wait at least 14 days after deployment, then review monthly and after major
traffic changes:

```bash
kubectl get vpa -A
kubectl get vpa -A -o json | jq -r '
  .items[] |
  .metadata.namespace as $ns |
  .metadata.name as $name |
  .status.recommendation.containerRecommendations[]? |
  [$ns, $name, .containerName,
   (.lowerBound | tostring), (.target | tostring), (.upperBound | tostring)] |
  @tsv'
```

Compare recommendations with 7- and 30-day p95 CPU/memory usage in Grafana.
Do not copy a short-lived recommendation directly into Git.

## Change rules

1. Change requests in Git; never enable automatic VPA updates on KEDA or
   operator-managed workloads.
2. Raise requests promptly when the target repeatedly exceeds the configured
   request or Pods experience throttling/OOM kills.
3. Lower requests only when both the 30-day history and VPA lower bound support
   the change.
4. Change one workload group per pull request and watch it for at least one
   normal traffic cycle.
5. Keep limits high enough for bursts; avoid CPU limits on latency-sensitive
   components unless a noisy-neighbor risk requires them.

## Preserve regional N+1 capacity

Before lowering requests or removing a worker, simulate one unavailable worker
in each required region. The remaining nodes in that region must fit all hard
region-constrained requests, DaemonSets, topology-spread minima, and disruption
budgets. Do not approve a capacity reduction if eviction would leave required
Pods Pending.

Use the scheduler view and allocated requests, not only current utilization:

```bash
kubectl get nodes -L topology.kubernetes.io/region
kubectl describe nodes | sed -n '/Allocated resources:/,/Events:/p'
kubectl get pods -A -o wide
kubectl get pdb -A
```
