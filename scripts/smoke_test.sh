#!/usr/bin/env bash
# Smoke tests against a running API instance. Used locally, by compose, and
# by the kind-based end-to-end CI job. Exits non-zero on the first failure.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: smoke_test.sh [--base-url URL] [--help]

Checks that a deployed lsa-platform API behaves: health and readiness,
aggregate endpoints with sane shapes, request-id propagation, and that the
disclosure-control rule (no published cell under the minimum size) holds.

Options:
  --base-url URL   API base URL (default: http://localhost:8000)
  --help           Show this help
EOF
}

base_url="http://localhost:8000"
while [ $# -gt 0 ]; do
  case "$1" in
    --base-url) base_url="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

pass=0
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { pass=$((pass + 1)); echo "ok: $1"; }

# The stack may still be starting (compose one-shot jobs, pod rollout);
# give the API up to 90s to answer before the checks begin.
waited=0
until curl -fsS -o /dev/null "$base_url/healthz" 2>/dev/null; do
  waited=$((waited + 3))
  if [ "$waited" -gt 90 ]; then
    fail "API did not answer on $base_url within 90s (is the stack up? try: docker compose ps)"
  fi
  echo "waiting for the API on $base_url ..."
  sleep 3
done

body="$(curl -fsS "$base_url/healthz")" || fail "healthz unreachable"
grep -q '"ok"' <<<"$body" || fail "healthz body: $body"
ok "healthz"

body="$(curl -fsS "$base_url/readyz")" || fail "readyz unreachable"
grep -q '"ready"' <<<"$body" || fail "readyz body: $body"
ok "readyz"

body="$(curl -fsS "$base_url/api/results/cantons")"
n_cantons="$(grep -o '"canton"' <<<"$body" | wc -l | tr -d ' ')"
[ "$n_cantons" -eq 26 ] || fail "expected 26 cantons, got $n_cantons"
ok "cantons endpoint returns 26 rows"

grep -q '"student_id"' <<<"$body" && fail "row-level data leaked from /api/results/cantons"
ok "no row-level fields in aggregate response"

# Disclosure control: any cell with n below the threshold must carry null.
# The python interpreter in the API image is guaranteed present; jq is not.
python3 - "$body" <<'EOF' || fail "small cell published"
import json, os, sys
rows = json.loads(sys.argv[1])
threshold = int(os.environ.get("LSA_MIN_CELL_SIZE", "10"))
bad = [r for r in rows if r["n_students"] < threshold and r["mean_score"] is not None]
sys.exit(1 if bad else 0)
EOF
ok "no published cell below the minimum size"

rid="smoke-$$"
echo_rid="$(curl -fsS -D - -o /dev/null -H "x-request-id: $rid" "$base_url/healthz" \
  | tr -d '\r' | awk -F': ' 'tolower($1)=="x-request-id" {print $2}')"
[ "$echo_rid" = "$rid" ] || fail "request id not echoed (got '$echo_rid')"
ok "request id propagation"

body="$(curl -fsS "$base_url/")"
grep -qi "synthetic" <<<"$body" || fail "html page missing the synthetic-data disclaimer"
ok "html page renders with disclaimer"

echo "smoke tests passed ($pass checks)"
