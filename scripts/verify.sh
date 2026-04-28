#!/usr/bin/env bash
# Verify the R2 backup is healthy by restoring it to a temp file
# and running a SQLite integrity check. Does not touch the live DB.
set -euo pipefail

cd "$(dirname "$0")/.."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== Replication status ==="
docker compose exec -T litestream \
  litestream status -config /etc/litestream.yml

echo
echo "=== Restoring latest snapshot to scratch dir ==="
docker run --rm \
  --env-file .env \
  -v "$PWD/litestream.yml:/etc/litestream.yml:ro" \
  -v "$TMPDIR:/restore" \
  litestream/litestream:latest \
  restore -config /etc/litestream.yml -o /restore/db.sqlite3 /data/db.sqlite3

if [ ! -f "$TMPDIR/db.sqlite3" ]; then
  echo "FAIL: restore produced no file" >&2
  exit 1
fi

SIZE=$(stat -f%z "$TMPDIR/db.sqlite3" 2>/dev/null || stat -c%s "$TMPDIR/db.sqlite3")
echo "Restored size: $SIZE bytes"

echo
echo "=== SQLite integrity check ==="
RESULT=$(sqlite3 "$TMPDIR/db.sqlite3" "PRAGMA integrity_check;")
echo "$RESULT"

if [ "$RESULT" != "ok" ]; then
  echo "FAIL: integrity check did not return 'ok'" >&2
  exit 1
fi

echo
echo "=== Row counts (sanity) ==="
sqlite3 "$TMPDIR/db.sqlite3" <<'SQL'
SELECT 'users',  COUNT(*) FROM users;
SELECT 'ciphers',COUNT(*) FROM ciphers;
SELECT 'orgs',   COUNT(*) FROM organizations;
SQL

echo
echo "OK: backup verified."
