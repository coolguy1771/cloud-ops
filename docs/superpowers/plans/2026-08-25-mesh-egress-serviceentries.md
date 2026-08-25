# Mesh egress ServiceEntries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register known external HTTPS destinations as Istio ServiceEntries in a central `network/mesh-egress` catalog.

**Architecture:** Flux Kustomization under the ambient `network` namespace applies one multi-doc YAML of MESH_EXTERNAL / DNS / 443 TLS ServiceEntries with `exportTo: ["*"]`. No app-local duplicates; Omni/Hetzner/tunnel omitted per design.

**Tech Stack:** Istio ambient ServiceEntry (`networking.istio.io/v1`), Flux Kustomization, kustomize

**Spec:** `docs/superpowers/specs/2026-08-25-mesh-egress-serviceentries-design.md`

---

## Task 1: Add mesh-egress manifests

**Files:**
- Create: `kubernetes/apps/network/mesh-egress/app/serviceentries.yaml`
- Create: `kubernetes/apps/network/mesh-egress/app/kustomization.yaml`
- Create: `kubernetes/apps/network/mesh-egress/ks.yaml`
- Modify: `kubernetes/apps/network/kustomization.yaml`

- [ ] **Step 1: Create `serviceentries.yaml`** with six ServiceEntries: `tigris-storage`, `tempo-r2`, `github`, `letsencrypt`, `cloudflare-api`, `onepassword` (hosts/ports per design)
- [ ] **Step 2: Create app `kustomization.yaml`** listing `./serviceentries.yaml`
- [ ] **Step 3: Create Flux `ks.yaml`** (`name: mesh-egress`, path `./kubernetes/apps/network/mesh-egress/app`, `targetNamespace: network`, prune true, source `flux-system`)
- [ ] **Step 4: Wire into** `kubernetes/apps/network/kustomization.yaml` as `./mesh-egress/ks.yaml`

## Task 2: Verify

- [ ] **Step 1:** `kubectl kustomize kubernetes/apps/network/mesh-egress/app` shows six ServiceEntries
- [ ] **Step 2:** Optionally apply/wait for Flux if cluster context available; `kubectl -n network get serviceentry`
