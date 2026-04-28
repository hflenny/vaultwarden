#!/usr/bin/env bash
# Restore the Vaultwarden SQLite DB from R2 via Litestream.
# Usage:
#   scripts/restore.sh                # restore latest
#   scripts/restore.sh -timestamp 2026-04-28T12:00:00Z
#
# Stops the stack, replaces ./data/db.sqlite3, then leaves the stack down so
# you can inspect before restarting with `docker compose up -d`.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "ERROR: .env not found" >&2
  exit 1
fi

DB_PATH="./data/db.sqlite3"
BACKUP_PATH="./data/db.sqlite3.pre-restore.$(date +%s)"

echo "Stopping stack..."
docker compose down

if [ -f "$DB_PATH" ]; then
  echo "Moving existing DB aside -> $BACKUP_PATH"
  mv "$DB_PATH" "$BACKUP_PATH"
  # WAL/SHM files would corrupt the restored DB if left behind.
  rm -f "$DB_PATH-wal" "$DB_PATH-shm"
fi

echo "Restoring from R2..."
docker run --rm \
  --env-file .env \
  -v "$PWD/data:/data" \
  -v "$PWD/litestream.yml:/etc/litestream.yml:ro" \
  litestream/litestream:latest \
  restore -config /etc/litestream.yml "$@" /data/db.sqlite3

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: restore failed; DB not present" >&2
  exit 1
fi

echo
echo "Restore complete: $DB_PATH"
echo "Pre-restore DB preserved at: $BACKUP_PATH"
echo "Start the stack with: docker compose up -d"
