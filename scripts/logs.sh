#!/usr/bin/env bash
# Inspect the API's structured JSON logs: filter by level or request id,
# from a file or stdin. Plain grep/sed so it works anywhere.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: logs.sh [--level LEVEL] [--request-id ID] [--tail N] [FILE]

Filters structured JSON log lines (one object per line). Reads FILE, or
stdin when no file is given — e.g.:

  kubectl logs deploy/lsa-api | scripts/logs.sh --level ERROR
  docker compose logs --no-log-prefix api | scripts/logs.sh --request-id abc

Options:
  --level LEVEL      Keep lines with "level": "LEVEL" (e.g. ERROR, WARNING)
  --request-id ID    Keep lines belonging to one request
  --tail N           Keep only the last N matching lines
  --help             Show this help
EOF
}

level=""
request_id=""
tail_n=""
file="-"
while [ $# -gt 0 ]; do
  case "$1" in
    --level) level="$2"; shift 2 ;;
    --request-id) request_id="$2"; shift 2 ;;
    --tail) tail_n="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) file="$1"; shift ;;
  esac
done

filter() {
  local out
  out="$(cat "$file")"
  if [ -n "$level" ]; then
    out="$(grep -F "\"level\": \"$level\"" <<<"$out" || true)"
  fi
  if [ -n "$request_id" ]; then
    out="$(grep -F "\"request_id\": \"$request_id\"" <<<"$out" || true)"
  fi
  if [ -n "$tail_n" ]; then
    out="$(tail -n "$tail_n" <<<"$out")"
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
}

filter || true
