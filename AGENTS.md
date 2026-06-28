# AGENTS.md — Unraid Compose Projects

Docker Compose stacks for Unraid (Compose Manager Plugin). **YAML + bash only.**

## Key Facts

- **No CI, no linter, no formatter, no typecheck** – review changes manually
- **No package manager**
- **Scripts cannot be `chmod +x`** (FAT32 boot USB). Always run: `bash 00_sync.sh`
- **Git is single source of truth** – `00_sync.sh` does `git reset --hard origin/main`, discarding all local changes
- **Secrets never committed** – `.env` is gitignored; edit `.env.example` only
- **`compose.override.yaml` is plugin-managed** – do not edit manually unless adding/removing a service

## Dev Workflow (on Unraid)

```
# Preview .env changes after pulling updates
bash 01_sync-env-dry-run.sh

# Full pipeline (skip dry-run, apply changes and restart)
bash 99_all.sh                        # sync → env → start (continues on failure)
```

Start-all loads both `compose.yaml` and `compose.override.yaml` with `--pull always --build --remove-orphans`.

## Build-From-Source (odysseus)

`odysseus/compose.yaml` uses `build: ./build-src` — source must be cloned first:
```
bash odysseus/build.sh
bash 99_all.sh
```
`build-src/` is gitignored; `odysseus/build.sh` handles clone/pull.

## Additional Scripts

- `11_recreate_all.sh` – `--force-recreate` all stacks (useful after config changes)
- `helper_sync_env.sh` – core sync-env logic, called by `01_sync-env-dry-run.sh` and `02_sync-env.sh`

## compose.yaml Style (non-negotiable)

Key order per service: `image → restart → network → volumes → ports → environment → depends_on → healthcheck → deploy`

CPU tiers: `"7"` (heavy/user-facing), `"4"` (medium), `"2"` (light)

Healthchecks: `interval: 30s, timeout: 10s, retries: 5, start_period: 30s` (60s for heavy services).

## Networking Gotchas

- **Cross-network ≠ Docker DNS** – services on `br0` ipvlan cannot be reached by service name from the default compose network; use LAN IP
- **VPN routing** – `network_mode: "service:gluetun"` + `depends_on` with `condition: service_healthy`
- External `br0` network must exist on host: `docker network ls --filter driver=ipvlan`

## .env.example Rules

- Secrets → `your_value_here`. Paths → Unraid defaults (`/mnt/user/appdata/...`). Non-secret defaults → real values
- Never comment out variables, even if the service is disabled. Only remove when the service is fully removed
- Keep section separator style matching `compose.yaml`