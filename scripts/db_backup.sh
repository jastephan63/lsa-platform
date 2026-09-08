#!/usr/bin/env bash
# Dump the database in pg_dump custom format, timestamped, into backups/.
# NOTE: pg_dump/pg_restore must match the server's major version — a newer
# client emits SET commands an older server rejects. See docs.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: db_backup.sh [--out-dir DIR] [--help]

Writes backups/lsa-YYYYmmdd-HHMMSS.dump (pg_dump custom format, compressed).
Connection from POSTGRES_* environment variables (see .env.example).
Restore with scripts/db_restore.sh.

Options:
  --out-dir DIR   Target directory (default: backups/)
  --help          Show this help
EOF
}

out_dir="backups"
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) out_dir="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

: "${POSTGRES_HOST:?set POSTGRES_HOST (see .env.example)}"

mkdir -p "$out_dir"
target="$out_dir/lsa-$(date +%Y%m%d-%H%M%S).dump"

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --format=custom --compress=6 --file "$target"

size="$(du -h "$target" | cut -f1)"
echo "backup written: $target ($size)"
