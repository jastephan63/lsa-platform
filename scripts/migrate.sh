#!/usr/bin/env bash
# Apply numbered SQL migrations from db/migrations/ to a PostgreSQL database.
# Idempotent: applied versions are recorded in schema_migrations and skipped
# on re-run. Each migration runs in a single transaction together with its
# bookkeeping row, so a failed migration leaves no trace.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: migrate.sh [--dry-run] [--help]

Applies all pending migrations from db/migrations/*.sql in filename order.

Connection is taken from the environment (see .env.example):
  POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD

Options:
  --dry-run   List pending migrations without applying them
  --help      Show this help
EOF
}

dry_run=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
migrations_dir="$repo_root/db/migrations"

: "${POSTGRES_HOST:?set POSTGRES_HOST (see .env.example)}"
: "${POSTGRES_PORT:?set POSTGRES_PORT}"
: "${POSTGRES_DB:?set POSTGRES_DB}"
: "${POSTGRES_USER:?set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD}"

psql_cmd() {
  PGOPTIONS='-c client_min_messages=warning' PGPASSWORD="$POSTGRES_PASSWORD" psql \
    --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --no-psqlrc --quiet --set ON_ERROR_STOP=1 "$@"
}

psql_cmd --command "CREATE TABLE IF NOT EXISTS schema_migrations (
  version text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);"

applied="$(psql_cmd --tuples-only --no-align \
  --command 'SELECT version FROM schema_migrations ORDER BY version;')"

pending=0
for file in "$migrations_dir"/*.sql; do
  version="$(basename "$file" .sql)"
  if grep -qx "$version" <<<"$applied"; then
    continue
  fi
  pending=$((pending + 1))
  if "$dry_run"; then
    echo "pending: $version"
    continue
  fi
  echo "applying: $version"
  {
    echo 'BEGIN;'
    cat "$file"
    printf "INSERT INTO schema_migrations (version) VALUES ('%s');\n" "$version"
    echo 'COMMIT;'
  } | psql_cmd
done

if [ "$pending" -eq 0 ]; then
  echo "database is up to date"
elif ! "$dry_run"; then
  echo "applied $pending migration(s)"
fi
