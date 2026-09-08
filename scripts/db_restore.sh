#!/usr/bin/env bash
# Restore a pg_dump custom-format backup produced by db_backup.sh.
# Destructive: replaces current contents. Asks for confirmation unless --yes.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: db_restore.sh [--yes] BACKUP_FILE

Restores BACKUP_FILE (pg_dump custom format) into the database given by the
POSTGRES_* environment variables, dropping existing objects first
(pg_restore --clean --if-exists).

Options:
  --yes    Skip the interactive confirmation (for scripts and CI)
  --help   Show this help
EOF
}

confirmed=false
backup_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) confirmed=true; shift ;;
    --help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) backup_file="$1"; shift ;;
  esac
done

[ -n "$backup_file" ] || { usage >&2; exit 2; }
[ -f "$backup_file" ] || { echo "no such file: $backup_file" >&2; exit 1; }
: "${POSTGRES_HOST:?set POSTGRES_HOST (see .env.example)}"

if ! "$confirmed"; then
  printf 'This will REPLACE all data in %s on %s. Type yes to continue: ' \
    "$POSTGRES_DB" "$POSTGRES_HOST"
  read -r answer
  [ "$answer" = "yes" ] || { echo "aborted"; exit 1; }
fi

PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
  --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --clean --if-exists --no-owner --exit-on-error \
  "$backup_file"

echo "restore complete from $backup_file"
