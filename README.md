# cloud-ops

GitOps repo for Kuma service mesh + cluster infrastructure.

## Structure

- `argocd/apps/kuma/` — Kuma CP Application + Helm values
- `clusters/<env>/` — Kustomize overlays per environment

## Deploy (local kind cluster)

```bash
cd ~/coolguy1771/cloud-ops
export PATH="$PWD/bin:$PATH"
kind create cluster --name kuma-demo
kubectl config use-context kind-kuma-demo

helm install kuma kuma/kuma \
  --create-namespace --namespace kuma-system \
  -f argocd/apps/kuma/kuma-helm-values.yaml
```

## Verify

```bash
kubectl get pods -n kuma-system
kubectl logs -n kuma-system -l app=kuma-cp -f
kuma-dp version   # once you have the CLI installed
```
