# Unraid Compose Projects

Docker Compose project stacks for Unraid, managed via the [Compose Manager Plugin](https://github.com/mstrhakr/compose_plugin).

**Location on Unraid:** `/boot/config/plugins/compose.manager/projects/`

---

## Directory Structure

```
projects/
├── .gitignore
├── README.md
├── start-all.sh          # Start all stacks
├── sync.sh               # Git pull latest
├── update-all.sh         # Sync + Start all
├── <stack>/
│   ├── compose.yaml           # Main compose file (tracked)
│   ├── compose.override.yaml  # Unraid labels (plugin-managed, tracked)
│   ├── .env.example           # Template with placeholders (tracked)
│   ├── .env                   # Actual secrets (NOT tracked)
│   ├── autostart              # Unraid-specific (tracked)
│   ├── icon_url               # Unraid-specific (tracked)
│   └── name                   # Unraid-specific (tracked)
```

### Stacks

| Stack | Services | Purpose |
|---|---|---|
| `anythingllm` | cloudflared, anythingllm | Local LLM interface |
| `documents_bine` | cloudflared, broker, gotenberg, tika, db, paperless | Paperless-ngx instance |
| `documents_eltern` | (same as above) | Paperless-ngx instance |
| `documents_jens` | (same as above) | Paperless-ngx instance |
| `documents_tilo` | (same as above) | Paperless-ngx instance |
| `homeautomation` | cloudflared, mosquitto, nodered | IoT / Home Automation |
| `immich` | cloudflared, immich-server, immich-machine-learning, broker, database | Photo management |
| `jellyfin` | jellyfin, cloudflared, radarr, sonarr, prowlarr, sabnzbd, gluetun, jellyseerr | Media server + *arr stack |
| `monitoring` | dozzle | Docker logs UI |
| `nextcloud` | cloudflared, broker, database, collabora, nextcloud | Cloud storage + office |
| `open_webui` | cloudflared, open-webui | Open WebUI (Ollama frontend) |
| `vaultwarden` | cloudflared, vaultwarden | Password manager |

---

## compose.yaml Conventions

### Style

- **Separators:** Each service is preceded by a comment block:
  ```yaml
  # ---------------------------------------------------------
  # SERVICE NAME IN CAPS
  # ---------------------------------------------------------
  ```
- **No inline comments** on values (except where absolutely necessary)
- **Blank line** between services

### Key Order (per service)

Follow this order for consistency across all services:

1. `image`
2. `restart`
3. Network-related: `network_mode`, `networks`, `cap_add`, `devices`, `group_add`
4. `volumes`
5. `ports`
6. `environment` / `env_file`
7. `depends_on`
8. `healthcheck`
9. `deploy`

### Example

```yaml
services:
  # ---------------------------------------------------------
  # SERVICE NAME
  # ---------------------------------------------------------
  service_name:
    image: org/image:tag
    restart: unless-stopped
    volumes:
      - ${DATA_PATH}:/data
    environment:
      - VAR=${VAR}
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: curl -f http://localhost:8080/health || exit 1
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: "4"
```

---

## .env.example Conventions

### Style

Must match `compose.yaml` style exactly:

```
# ---------------------------------------------------------
# SECTION NAME IN CAPS
# ---------------------------------------------------------
VARIABLE=value

# ---------------------------------------------------------
# ANOTHER SECTION
# ---------------------------------------------------------
ANOTHER_VAR=your_value_here
```

### Rules

- **Secrets** → `your_value_here` (e.g., `TUNNEL_TOKEN=your_value_here`)
- **Paths** → Use realistic Unraid defaults (e.g., `/mnt/user/appdata/service/`)
- **Non-secret defaults** → Use actual values (e.g., `PUID=99`, `POSTGRES_DB=paperless`)
- **One blank line** between sections
- **Comments only where necessary** (e.g., explaining a non-obvious default)

---

## compose.override.yaml

### Purpose

Contains **Unraid-specific labels** that integrate containers with the Unraid Docker UI:

```yaml
services:
  service_name:
    labels:
      net.unraid.docker.managed: composeman
      net.unraid.docker.icon: "https://..."
      net.unraid.docker.webui: ""
      net.unraid.docker.shell: ""
```

### Important

- **Managed by the Compose Manager plugin** – do not edit manually unless necessary
- **Always loaded alongside `compose.yaml`** by `start-all.sh`
- Without these labels, containers show as "3rd Party" instead of "Compose" in the Unraid UI

---

## Networking on Unraid

### IPvlan `br0` Network

Unraid uses an ipvlan network named `br0` to give containers direct LAN IPs on the host's `br0` bridge:

| Property | Value |
|---|---|
| **Driver** | `ipvlan` |
| **Parent** | `br0` |
| **Subnet** | `10.0.0.0/16` |
| **Gateway** | `10.0.0.1` |
| **IP Range** | `10.0.1.0/24` |

To list existing ipvlan networks:

```bash
docker network ls --filter driver=ipvlan
docker network inspect br0
```

### Static IPs for Individual Services

Only specific services need a fixed LAN IP (e.g. mosquitto at `10.0.254.4`). Other services in the same stack stay in the default compose network.

```yaml
services:
  mosquitto:
    image: eclipse-mosquitto:latest
    networks:
      br0:
        ipv4_address: 10.0.254.4

networks:
  br0:
    external: true
```

### Cross-Network Communication

Services in different networks **cannot** reach each other via Docker service names. They must use the LAN IP address.

**Example:** nodered (default compose network) connects to mosquitto (`br0` network) via `10.0.254.4:1883`, not `mosquitto:1883`.

Node-RED MQTT nodes must be configured with the IP address, not the service name.

---

## CPU Limits (3 Tiers)

CPU limits prevent any single service from monopolizing all 8 threads (AMD 3400G: 4 cores / 8 threads).

### Tier 1: 7 CPUs (Heavy / User-facing)

| Service | Reason |
|---|---|
| `immich-server` | Main app, must stay responsive |
| `immich-machine-learning` | ML workloads, needs max available threads |
| `nextcloud` | Many background tasks, user-facing |
| `jellyfin` | GPU transcoding, but UI/IO still needs CPU |

### Tier 2: 4 CPUs (Medium)

| Service | Reason |
|---|---|
| `paperless` (4x) | User-facing, OCR/processing |
| `sabnzbd` | Unpacking is intensive but variable |
| `gotenberg` (4x) | Chromium-based, can spike |
| `collabora` | Only active when editing documents |
| `open-webui` | LLM requests are external |
| `anythingllm` | LLM is external |
| `database` (all 6x Postgres) | Must stay responsive |

### Tier 3: 2 CPUs (Light)

| Service | Reason |
|---|---|
| `cloudflared` (6x) | Tunnel only, minimal CPU |
| `broker/redis` (5x) | In-memory, very efficient |
| `mosquitto` | In-memory, very efficient |
| `nodered` | Event-driven, lightweight |
| `tika` (4x) | Only active on demand |
| `radarr`, `sonarr`, `prowlarr` | Background tasks, not urgent |
| `jellyseerr` | Moderate usage |
| `vaultwarden` | Minimal |
| `dozzle` | Log reading is lightweight |

### Syntax

```yaml
deploy:
  resources:
    limits:
      cpus: "7"  # or "4" or "2"
```

---

## Healthcheck Strategy

### General Rules

- **Interval:** `30s`, **Timeout:** `10s`, **Retries:** `5`
- **Start period:** `30s` (standard), `60s` (heavy services: nextcloud, paperless, collabora)

### Healthcheck Types

| Type | Example | Used For |
|---|---|---|
| **HTTP curl** | `curl -f http://localhost:8080/health \|\| exit 1` | Web services (jellyfin, radarr, sonarr, nextcloud, etc.) |
| **pg_isready** | `pg_isready -U $USER -d $DB \|\| exit 1` | PostgreSQL databases |
| **redis-cli** | `redis-cli ping \|\| exit 1` | Redis/Valkey brokers |
| **Image-native** | `disable: false` | Services with built-in healthchecks |

### Services WITHOUT Healthchecks

| Service | Reason |
|---|---|
| `cloudflared` | No local HTTP endpoint (outbound tunnel only) |
| `tika` | No `curl` or `wget` in the image; TCP-only checks are unreliable |
| `immich-machine-learning` | Known issues with ML container healthchecks across Immich versions |

### Endpoint Reference

| Service | Endpoint | Port |
|---|---|---|
| `jellyfin` | `/health` | 8096 |
| `radarr` | `/ping` | 7878 |
| `sonarr` | `/ping` | 8989 |
| `prowlarr` | `/ping` | 9696 |
| `sabnzbd` | `/api?mode=version` | 8085 |
| `jellyseerr` | `/api/v1/status` | 5055 |
| `nextcloud` | `/status.php` | 80 |
| `collabora` | `/hosting/discovery` | 9980 |
| `gotenberg` | `/health` | 3000 |
| `paperless` | `/accounts/login/` | 8000 |
| `open-webui` | `/health` | 8080 |
| `vaultwarden` | `/alive` | 80 |
| `immich-server` | `/api/server-info/ping` | 2283 |
| `anythingllm` | `/` | 3001 |
| `dozzle` | `/` | 8080 |
| `nodered` | `/` | 1880 |
| `mosquitto` | `mosquitto_sub -t '$SYS/broker/version' -W 3` | 1883 |

---

## Scripts

### `sync.sh`

Pulls the latest version from Git.

```bash
bash sync.sh
```

### `start-all.sh`

Starts all compose stacks:
- Loads both `compose.yaml` and `compose.override.yaml`
- Pulls latest images (`--pull always`)
- Removes orphaned containers (`--remove-orphans`)
- Updates `started_at` timestamp only when containers actually change

```bash
bash start-all.sh
```

### `update-all.sh`

Runs `sync.sh` then `start-all.sh` in sequence.

```bash
bash update-all.sh
```

### Important Notes

- Scripts **cannot be made executable** on Unraid's FAT32 boot USB – always run with `bash script.sh`
- `start-all.sh` tracks `started_at` by comparing container start times before/after `up`. Only updates if containers actually changed.

---

## .gitignore Rules

### Ignored (never commit)

| Pattern | Reason |
|---|---|
| `.env` | Contains secrets |
| `last_cmd.log` | Runtime log |
| `last_result.json` | Runtime state |
| `started_at` | Runtime timestamp |
| `has_build` | Runtime flag |
| `webui_url` | Runtime URL |
| `version` | Runtime version |
| `.compose.lock` | Docker Compose lock file (machine-specific) |

### Tracked (commit)

| File | Purpose |
|---|---|
| `compose.yaml` | Main compose file |
| `compose.override.yaml` | Unraid labels |
| `.env.example` | Template |
| `autostart`, `icon_url`, `name` | Unraid config |
| `start-all.sh`, `sync.sh`, `update-all.sh` | Scripts |

---

## Adding New Services

### To an Existing Stack

1. Add service to `compose.yaml` following the [conventions](#composeyaml-conventions)
2. Add matching section to `.env.example` with the same separator style
3. Add any new variables to `.env.example` as `your_value_here`
4. Assign appropriate [CPU tier](#cpu-limits-3-tiers)
5. Add a [healthcheck](#healthcheck-strategy) if the service has an HTTP endpoint
6. The plugin will auto-generate `compose.override.yaml` labels on next start

### New Stack

1. Create directory: `projects/<stack_name>/`
2. Create `compose.yaml` with all services
3. Create `.env.example` with all variables (secrets as `your_value_here`)
4. Create Unraid config files: `autostart`, `icon_url`, `name`
5. Update `.env.example` if any new variable types are introduced

### Services with Static IPs

When a service needs a fixed LAN IP via the `br0` ipvlan network:

1. Verify the network exists on the host: `docker network ls --filter driver=ipvlan`
2. Add `networks` section to the service with `ipv4_address`
3. Add `networks: br0: external: true` at the bottom of `compose.yaml`
4. Any service in a different network that depends on it must connect via IP, not service name

---

## Checklist for New Services

When adding a new service, verify:

- [ ] Service follows the [key order convention](#key-order-per-service)
- [ ] Separator comment block is present (`# ---\n# NAME\n# ---`)
- [ ] `restart` is set (`unless-stopped` or `always`)
- [ ] CPU limit assigned (Tier 1: 7, Tier 2: 4, Tier 3: 2)
- [ ] Healthcheck added (unless service is in the [no-healthcheck list](#services-without-healthchecks))
- [ ] All secrets use `${VAR}` syntax (no hardcoded values)
- [ ] Corresponding `.env.example` entry added with `your_value_here` for secrets
- [ ] `.env.example` uses the same separator style as `compose.yaml`
- [ ] No personal data in `compose.yaml` or `.env.example` (no IPs, URLs, names)
- [ ] Service is NOT in `.gitignore` patterns
- [ ] External networks referenced (`external: true`) exist on the host
- [ ] Cross-network dependencies use IP addresses, not service names

---

## Syncing .env Files on Server

When `.env.example` changes (new variables added), sync to existing `.env` files:

```bash
# Create sync-env.sh on the server (not in repo)
bash sync-env.sh
```

This script:
- Adds new variables from `.env.example` to `.env` (with `your_value_here`)
- Preserves existing values (never overwrites)
- Preserves old variables not in `.env.example` (never deletes)
