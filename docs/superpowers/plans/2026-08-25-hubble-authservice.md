# Hubble UI + Authservice Implementation Plan

> **For agentic workers:** Use executing-plans or implement task-by-task.

**Goal:** Hubble UI at hubble.cloud.witl.xyz behind authservice + Authentik; group cloud-ops-admin.

**Spec:** `docs/superpowers/specs/2026-08-25-hubble-authservice-design.md`

---

## Task 1: Enable Hubble UI + relay

- [x] Cilium HelmRelease: `hubble.relay.enabled: true`, `hubble.ui.enabled: true`
- [x] Add HTTPRoute `hubble` → `hubble-ui:80`

## Task 2: Deploy authservice

- [x] Namespace + Deployment/Service/SA/RBAC + ExternalSecret
- [x] Flux Kustomization under `kubernetes/apps/authservice/`

## Task 3: Wire Istio Gateway

- [x] istiod `extensionProviders` entry `authservice-grpc`
- [x] RequestAuthentication JWT rule for hubble issuer
- [x] AuthorizationPolicy CUSTOM (host hubble) + ALLOW with groups claim (callback paths exempt)

## Task 4: Authentik / secrets

- [x] Document 1Password item `hubble-oauth` + Authentik app setup (group policy)
- [x] Commit / PR
