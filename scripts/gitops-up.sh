#!/usr/bin/env bash
# Install Argo CD into the current kind cluster and hand it this repository:
# from then on the cluster state follows git (k8s/overlays/dev on main),
# not whoever last ran kubectl. Pull-based alternative to kind-up.sh's push.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gitops-up.sh [--help]

Installs Argo CD (core) into the current kubectl context, configures the
kustomize load restrictor it needs for this repo, and creates the
lsa-platform Application pointing at k8s/overlays/dev on GitHub main.

Expects a cluster prepared by kind-up.sh (images loaded, secret created).
Note: Argo pulls from GitHub, so it deploys what is PUSHED, not your
working tree.

Options:
  --help   Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
argocd_version="v3.5.2"

echo "==> installing argo cd $argocd_version"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$argocd_version/manifests/install.yaml" >/dev/null
# This repo's kustomization reads migrations/scripts from the repo root,
# which needs the relaxed load restrictor server-side in Argo.
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"kustomize.buildOptions":"--load-restrictor=LoadRestrictionsNone","resource.customizations.health.PersistentVolumeClaim":"hs = {}\nif obj.status ~= nil and obj.status.phase == \"Pending\" then\n  hs.status = \"Healthy\"\n  hs.message = \"WaitForFirstConsumer: binds when the backup job first mounts it\"\n  return hs\nend\nif obj.status ~= nil and obj.status.phase == \"Bound\" then\n  hs.status = \"Healthy\"\n  return hs\nend\nhs.status = \"Progressing\"\nreturn hs","resource.customizations.health.networking.k8s.io_Ingress":"hs = {}\nhs.status = \"Healthy\"\nhs.message = \"kind ingress publishes no LB status; reachability is verified by the smoke tests\"\nreturn hs"}}'
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

echo "==> creating the application"
kubectl apply -f "$repo_root/k8s/gitops/application.yaml"

echo "==> waiting for argo to sync and report health"
for _ in $(seq 1 60); do
  sync="$(kubectl -n argocd get application lsa-platform \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl -n argocd get application lsa-platform \
    -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  echo "sync=$sync health=$health"
  if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then
    echo "gitops is live: the cluster now follows git"
    exit 0
  fi
  sleep 10
done
echo "argo did not reach Synced/Healthy in time" >&2
kubectl -n argocd get application lsa-platform -o yaml | tail -30 >&2
exit 1
