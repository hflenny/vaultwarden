#!/usr/bin/env bash
# Litestream replicates continuously, so there is no separate "backup" step.
# This script:
#   1. checkpoints the WAL so the latest writes are flushed into the main DB,
#   2. shows replication status so you can confirm freshness.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Checkpointing WAL ==="
docker compose exec -T vaultwarden \
  sh -c 'sqlite3 /data/db.sqlite3 "PRAGMA wal_checkpoint(TRUNCATE);"' || \
  echo "(sqlite3 not present in image; WAL will sync on the next 5m tick)"

echo
echo "=== Replication status ==="
docker compose exec -T litestream \
  litestream status -config /etc/litestream.yml
