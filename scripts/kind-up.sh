#!/usr/bin/env bash
# Create (or reuse) a local kind cluster, build and load the images, create
# the secret from the environment, deploy the dev overlay, and wait until the
# API answers through the ingress. The same script drives the e2e CI job.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: kind-up.sh [--cluster NAME] [--help]

Brings up the whole platform on a local kind cluster with ingress-nginx,
then waits for readiness. Requires: kind, kubectl, kustomize, docker.
Secrets are taken from the environment (see .env.example):
  POSTGRES_USER, POSTGRES_PASSWORD, LSA_API_DB_USER, LSA_API_DB_PASSWORD,
  LSA_ANALYST_DB_USER, LSA_ANALYST_DB_PASSWORD

The API is reachable on http://localhost:8080 afterwards.

Options:
  --cluster NAME   kind cluster name (default: lsa)
  --help           Show this help
EOF
}

cluster="lsa"
while [ $# -gt 0 ]; do
  case "$1" in
    --cluster) cluster="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${POSTGRES_USER:?set POSTGRES_USER (see .env.example)}"
: "${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD}"
: "${LSA_API_DB_USER:?set LSA_API_DB_USER}"
: "${LSA_API_DB_PASSWORD:?set LSA_API_DB_PASSWORD}"
: "${LSA_ANALYST_DB_USER:?set LSA_ANALYST_DB_USER}"
: "${LSA_ANALYST_DB_PASSWORD:?set LSA_ANALYST_DB_PASSWORD}"

if ! kind get clusters 2>/dev/null | grep -qx "$cluster"; then
  # Port mapping 8080→80 lets the host reach the ingress controller.
  kind create cluster --name "$cluster" --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080
        protocol: TCP
EOF
fi
kubectl config use-context "kind-$cluster" >/dev/null

echo "==> building images"
docker build -q -f "$repo_root/docker/api.Dockerfile" -t lsa-api:local "$repo_root"
docker build -q -f "$repo_root/docker/analysis.Dockerfile" -t lsa-analysis:local "$repo_root"
kind load docker-image --name "$cluster" lsa-api:local lsa-analysis:local

echo "==> installing ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s

echo "==> creating namespace and secret (never from a committed file)"
kubectl create namespace lsa --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lsa create secret generic lsa-db-credentials \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=LSA_API_DB_USER="$LSA_API_DB_USER" \
  --from-literal=LSA_API_DB_PASSWORD="$LSA_API_DB_PASSWORD" \
  --from-literal=LSA_ANALYST_DB_USER="$LSA_ANALYST_DB_USER" \
  --from-literal=LSA_ANALYST_DB_PASSWORD="$LSA_ANALYST_DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> deploying the dev overlay"
# The setup Job is immutable; drop any previous run before re-applying.
kubectl -n lsa delete job lsa-setup --ignore-not-found
# The ingress-nginx admission webhook can lag behind its pod's Ready
# condition, refusing the Ingress for a few seconds — retry the apply.
applied=false
for attempt in $(seq 1 10); do
  if kustomize build --load-restrictor=LoadRestrictionsNone \
      "$repo_root/k8s/overlays/dev" | kubectl apply -f -; then
    applied=true
    break
  fi
  echo "apply refused (webhook warming up?), retry $attempt/10"
  sleep 5
done
"$applied" || { echo "could not apply the overlay" >&2; exit 1; }

echo "==> waiting for the setup job and the api"
kubectl -n lsa wait --for=condition=complete job/lsa-setup --timeout=300s
kubectl -n lsa rollout status deployment/lsa-api --timeout=180s

echo "==> waiting for ingress to answer"
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null http://localhost:8080/healthz; then
    echo "lsa-platform is up: http://localhost:8080"
    exit 0
  fi
  sleep 2
done
echo "ingress did not answer within 120s" >&2
exit 1
