# ADR 0002: Kustomize, not Helm

**Status:** accepted

## Context

The Kubernetes manifests need a dev variant (kind, local images, one
replica) and a prod-shaped variant (registry images, real hostname, more
replicas) without maintaining two copies.

## Decision

Plain manifests with Kustomize (base + overlays), built with the standalone
`kustomize` CLI.

## Rationale

- **One application, deployed by its own repository.** Helm earns its
  complexity when packaging software for *other people* to install with
  their own values, or when a chart ecosystem is being consumed. Neither
  applies here.
- **Reviewability.** A reviewer reads real YAML, and `kustomize build`
  shows the exact rendered output. Go-templated YAML is harder to audit —
  significant for a repo whose purpose is to be read.
- **No release-state machinery** (Helm's release secrets, rollback
  semantics) to explain or maintain; git is the source of truth and
  `kubectl apply` is the mechanism.

## Consequences

- No `helm rollback`; rolling back means applying the previous git state.
- Templating is limited to patches and generators — fine at this size. If
  this grew into many near-identical services, the calculus would change.
- The configMapGenerator pulls migrations/scripts from the repo root, which
  requires relaxing kustomize's load restrictor (documented in the
  kustomization file) — the price of keeping a single source of truth.
