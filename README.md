# Vaultwarden + Cloudflare Tunnel + Litestream

Self-hosted Vaultwarden on a Mac Mini (ARM), exposed at
[vault.solenhamn.com](https://vault.solenhamn.com) through a Cloudflare
Tunnel, with continuous SQLite replication to Cloudflare R2 via Litestream.

## Layout

| File | Purpose |
| --- | --- |
| `Dockerfile` | Bundles `cloudflared` into the official `vaultwarden/server` image. |
| `start.sh` | Container entrypoint — launches `cloudflared`, then `vaultwarden`. |
| `docker-compose.yml` | Two services: the bundled vaultwarden+tunnel container, and a Litestream sidecar. |
| `litestream.yml` | Replicates `/data/db.sqlite3` to R2 every 10 s with daily snapshots, 30-day retention. |
| `.env` / `.env.example` | Secrets (tunnel token, admin token, R2 creds). |
| `scripts/backup.sh` | Checkpoints the WAL and lists current R2 snapshots. |
| `scripts/restore.sh` | Pulls the DB back from R2 (fresh install or DR). |
| `scripts/verify.sh` | Restores into a scratch dir and runs `PRAGMA integrity_check`. |

## First-time setup

1. **Cloudflare Tunnel** — create a tunnel in Zero Trust → Networks → Tunnels.
   Add a public hostname `vault.solenhamn.com` → service
   `http://vaultwarden:80`. Copy the connector token into
   `CLOUDFLARE_TUNNEL_TOKEN`.

   > **Note on the service address:** cloudflared and vaultwarden run in the
   > same container, so `http://localhost:80` also works. We use
   > `http://vaultwarden:80` (the Docker service name) because it remains
   > correct if you ever split cloudflared into its own container.
2. **R2** — create a bucket (e.g. `vaultwarden-backup`) and an API token
   with **Object Read & Write** scoped to that bucket. Note the
   account-level S3 endpoint
   `https://<account-id>.r2.cloudflarestorage.com`.
3. **Env file**
   ```sh
   cp .env.example .env
   # fill in ADMIN_TOKEN, CLOUDFLARE_TUNNEL_TOKEN, R2_*
   ```
4. **Build & run**
   ```sh
   docker compose build
   docker compose up -d
   ```
5. Open https://vault.solenhamn.com, set `SIGNUPS_ALLOWED=true` briefly to
   create your account, then flip back to `false` and
   `docker compose up -d` to apply.

## Verifying backups

Run weekly:

```sh
scripts/verify.sh
```

It restores the latest R2 snapshot into a scratch directory, runs
`PRAGMA integrity_check`, and prints row counts for `users`, `ciphers`,
`organizations`. Exits non-zero if anything is off.

## Restoring (disaster recovery)

On the **same machine** (e.g. accidental DB corruption):

```sh
scripts/restore.sh                     # restore latest
scripts/restore.sh -timestamp 2026-04-28T12:00:00Z   # point-in-time
docker compose up -d
```

The script stops the stack, moves the existing
`data/db.sqlite3` aside as `db.sqlite3.pre-restore.<epoch>`, removes the
`-wal` / `-shm` sidecar files, and pulls the chosen snapshot from R2.

On a **fresh machine**:

```sh
git clone <this repo>
cd vaultwarden
cp .env.example .env  # fill in
mkdir -p data
scripts/restore.sh
docker compose up -d
```

DNS keeps pointing through the same Cloudflare Tunnel, so as soon as the
container is up the vault is reachable again at
`vault.solenhamn.com`.

## Notes

- The custom image runs **two processes** in one container; Docker's
  restart policy bounces the container if either dies.
- Cloudflare Tunnel terminates TLS at Cloudflare's edge; vaultwarden
  speaks plain HTTP on `:80` inside the container, never exposed to the
  host network.
- Litestream's `sync-interval: 5m` means recovery point objective is
  ~5 minutes. Snapshots are kept for 30 days (`retention: 720h`).
- `data/` is gitignored. Never commit `.env`.
