#!/usr/bin/env bash
# Bootstrap a running database into a usable platform: apply migrations,
# attach credentials to the API role, generate synthetic data if absent,
# and ingest it. Idempotent — safe to run repeatedly.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--skip-data] [--help]

Prepares the database and data for the whole platform:
  1. applies pending migrations           (scripts/migrate.sh)
  2. gives the lsa_api role its login     (from LSA_API_DB_USER/_PASSWORD)
  3. generates synthetic data if missing  (r/datagen/generate.R)
  4. validates and ingests it             (lsa-ingest)

Requires POSTGRES_* and LSA_API_DB_* in the environment (see .env.example).

Options:
  --skip-data   Only migrate and set up roles; skip generation and ingest
  --help        Show this help
EOF
}

skip_data=false
for arg in "$@"; do
  case "$arg" in
    --skip-data) skip_data=true ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${LSA_API_DB_USER:?set LSA_API_DB_USER (see .env.example)}"
: "${LSA_API_DB_PASSWORD:?set LSA_API_DB_PASSWORD}"

"$repo_root/scripts/migrate.sh"

# The migration creates the role NOLOGIN and without credentials, so no
# secret lives in a versioned file; the password is attached here, from the
# environment. psql -v quoting keeps the password out of the SQL text.
# Variable interpolation only happens for script input, not --command,
# hence the heredoc.
PGOPTIONS='-c client_min_messages=warning' PGPASSWORD="$POSTGRES_PASSWORD" psql \
  --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --no-psqlrc --quiet --set ON_ERROR_STOP=1 \
  --set api_user="$LSA_API_DB_USER" --set api_password="$LSA_API_DB_PASSWORD" \
  <<'EOF'
ALTER ROLE :"api_user" WITH LOGIN PASSWORD :'api_password';
EOF
echo "api role '$LSA_API_DB_USER' can log in"

if ! "$skip_data"; then
  if [ ! -f "$repo_root/data/raw/students.csv" ]; then
    echo "generating synthetic data"
    Rscript "$repo_root/r/datagen/generate.R" --out "$repo_root/data/raw"
  fi
  if command -v lsa-ingest >/dev/null 2>&1; then
    ingest=lsa-ingest
  else
    ingest="$repo_root/python/.venv/bin/lsa-ingest"
  fi
  "$ingest" load --data-dir "$repo_root/data/raw" \
    --report-dir "$repo_root/data/reports" --strict
fi

echo "bootstrap complete"
