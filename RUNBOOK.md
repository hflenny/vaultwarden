# Vaultwarden Runbook

## What this is

A self-hosted password manager running on a Mac Mini, accessible from anywhere via Cloudflare's network. No ports open on the router. Continuous backup to cloud storage.

---

## Architecture

### Three components

**Vaultwarden** is an open-source reimplementation of Bitwarden. It stores all passwords, notes, and credentials in a single SQLite file at `./data/db.sqlite3`. The official Bitwarden apps (iOS, Android, browser extensions) work with it unchanged.

**Cloudflare Tunnel** (cloudflared) connects the Mac Mini to Cloudflare's edge without opening any firewall ports. When you visit `vault.solenhamn.com`, the request travels over Cloudflare's network to your Mac Mini through an outbound-only tunnel the Mac initiates. Cloudflare handles TLS — vaultwarden only speaks plain HTTP internally.

**Litestream** watches the SQLite database file and continuously ships changes to Cloudflare R2 (cloud storage). It runs as a sidecar container alongside Vaultwarden, reading the same `./data` volume.

### Why one container for Vaultwarden + cloudflared

We built a custom Docker image that bundles both processes. The entrypoint script (`start.sh`) launches cloudflared first, then Vaultwarden. If either process dies, the container exits and Docker restarts it. This keeps the deployment simple — one image to build, one container to manage for the app itself.

### Why Litestream + R2

SQLite cannot be safely copied while it's being written to. Litestream understands SQLite's WAL (write-ahead log) format and captures changes at the transaction level, making it safe to replicate a live database. R2 was chosen because it has no egress fees (you pay nothing to download your backup in a disaster) and integrates naturally since Cloudflare Tunnel is already in use.

---

## Backup configuration

| Parameter | Value | Reason |
|---|---|---|
| Sync interval | 5 minutes | Short enough that losing a session's worth of new passwords is unlikely; long enough to avoid unnecessary R2 writes |
| Snapshot interval | 24 hours | Full DB copy daily gives a clean restore point without relying purely on WAL replay |
| Retention | 30 days | Month of point-in-time recovery available |

These are set in `litestream.yml`. Change them and run `docker compose restart litestream` to apply.

---

## What lives where

| Path | Contents |
|---|---|
| `./data/db.sqlite3` | Live Vaultwarden database |
| `./data/` | All Vaultwarden state (attachments, config) |
| `.env` | All secrets — never committed to git |
| `litestream.yml` | Backup configuration |
| `docker-compose.yml` | Stack definition |
| `Dockerfile` | Custom image (vaultwarden + cloudflared) |
| `start.sh` | Container entrypoint |
| `scripts/` | Operational scripts |

---

## Day-to-day operations

### Check everything is running
```sh
docker compose ps
```
Both `vaultwarden` and `vaultwarden-litestream` should show as running.

### Check backup is syncing
```sh
docker compose logs litestream --tail 10
```
You should see `replica sync` lines appearing every 5 minutes.

### Verify backup can actually be restored (run weekly)
```sh
bash scripts/verify.sh
```
Restores the latest R2 snapshot into a temporary directory, runs SQLite integrity check, prints row counts. Deletes the temp files on exit. Does not touch the live database.

### Force a backup status check
```sh
bash scripts/backup.sh
```
Lists current snapshots in R2 and their timestamps.

---

## Recovery

### Scenario 1: Corrupted database, Mac Mini still running

```sh
bash scripts/restore.sh
```

This will:
1. Stop all containers
2. Move the broken `db.sqlite3` aside (keeps it as `db.sqlite3.pre-restore.<timestamp>`)
3. Pull the latest snapshot from R2
4. Leave the stack stopped for you to inspect

When ready:
```sh
docker compose up -d
```

### Scenario 2: Point-in-time restore (e.g. accidentally deleted a password an hour ago)

```sh
bash scripts/restore.sh -timestamp 2026-04-28T12:00:00Z
```

Use a timestamp just before the unwanted change occurred.

### Scenario 3: Mac Mini is dead, starting fresh on a new machine

1. Install Docker
2. Clone this repo (or copy the files)
3. Create `.env` with all credentials (use `.env.example` as a guide)
4. Run:
```sh
mkdir -p data
bash scripts/restore.sh
docker compose up -d
```

DNS already points through Cloudflare. Once the container is up, `vault.solenhamn.com` is live again. Maximum data loss: 5 minutes.

---

## Secrets reference

All secrets live in `.env`. Never commit this file.

| Variable | What it is | Where to get it |
|---|---|---|
| `ADMIN_TOKEN` | Vaultwarden admin panel password | Generate: `openssl rand -base64 48` |
| `CLOUDFLARE_TUNNEL_TOKEN` | Authenticates cloudflared to your tunnel | Cloudflare Zero Trust → Networks → Tunnels |
| `R2_BUCKET` | R2 bucket name | `vaultwarden-backup` |
| `R2_ENDPOINT` | R2 S3 endpoint | Cloudflare dashboard → R2 → bucket → settings |
| `R2_ACCESS_KEY_ID` | R2 API credential | Cloudflare R2 → Manage API Tokens |
| `R2_SECRET_ACCESS_KEY` | R2 API credential | Same page, shown once on creation |

---

## Monitoring agent

An AI agent running on the Mac Mini performs automated checks and alerts via Telegram. Configure it with the following commands and cadences.

| Check | Command | Cadence |
|---|---|---|
| Vault reachable | `curl -sf https://vault.solenhamn.com > /dev/null` | Every 5 minutes |
| Containers running | `docker compose -f ~/Docker/vaultwarden/docker-compose.yml ps` | Every 5 minutes |
| Sync status | `docker compose -f ~/Docker/vaultwarden/docker-compose.yml exec -T litestream litestream status -config /etc/litestream.yml` | Every hour |
| Backup healthy | `bash ~/Docker/vaultwarden/scripts/verify.sh` | Daily |

All commands exit `0` on success and non-zero on failure. The agent should treat any non-zero exit as a Telegram alert.

**What each check catches:**
- **Vault reachable** — tunnel is down, container crashed, or Cloudflare issue
- **Containers running** — Docker daemon issue or unexpected container exit
- **Sync status** — Litestream connected and replicating; look for `status: ok`
- **Backup healthy** — full end-to-end restore test; catches R2 credential issues, corrupt snapshots, or DB integrity problems

---

## Turning signups on/off

Signups are off by default. To create a new account:

1. Set `SIGNUPS_ALLOWED=true` in `.env`
2. `docker compose up -d`
3. Create the account at `vault.solenhamn.com`
4. Set `SIGNUPS_ALLOWED=false` in `.env`
5. `docker compose up -d`
