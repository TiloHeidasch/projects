# Immich operations

## Ingress and networks

The Cloudflare Tunnel path remains available through `cloudflared`. It, SWAG,
and `immich-server` share the `proxy` network; `immich-server` also bridges to
the backend-only network used by Immich, Valkey, Postgres, and ML. The Tunnel
and SWAG both reach the Docker service name `immich-server:2283`. Port 2283 is
never published on the host.

The direct path uses the unchanged canonical application URL, such as
`photo.<SWAG_URL>`. SWAG generates exact-host virtual hosts only for `photo`
and `photo2`.

## Prerequisites

- A direct public IPv4 address (not CGNAT) and control of the public DNS zone.
- A router rule forwarding WAN TCP 443 to the Unraid host IPv4 and the SWAG
  high host port (the default is `8443`), not to host port 443.
- A separate IPv6 firewall rule blocking public IPv6 access to the published
  SWAG port unless IPv6 direct access is intentionally configured. An IPv4 NAT
  rule does not protect the IPv6 path.
- A Cloudflare API token scoped only to this zone with **Zone DNS Edit**
  permission. Live ingress secrets belong only in the appdata secret files,
  never in this repository or its `.env`.

## First setup and secret migration

1. Run the normal environment sync from the repository root:

   ```bash
   bash 02_sync-env.sh
   ```

   The sync removes the old ingress keys from the active `.env` and archives
   them as comments. Do not start Compose until the secret migration below is
   complete.

2. Create the appdata-only secret directory and copy both tracked templates to
   the absolute paths from `.env` (these are the defaults shown here):

   ```bash
   mkdir -p /mnt/user/appdata/immich-secrets
   chmod 700 /mnt/user/appdata/immich-secrets
   cp -n immich/tunnel.env.example /mnt/user/appdata/immich-secrets/tunnel.env
   cp -n immich/direct.env.example /mnt/user/appdata/immich-secrets/direct.env
   chmod 600 /mnt/user/appdata/immich-secrets/tunnel.env
   chmod 600 /mnt/user/appdata/immich-secrets/direct.env
   ```

   If the paths in `.env` were changed, copy the templates to those paths
   instead. The tracked files are templates only; no live token belongs on the
   FAT32 boot-USB repository.

3. Move the existing `TUNNEL_TOKEN` value from the archived/commented `.env`
   line or its sync backup into the appdata `tunnel.env`. Move the existing
   direct DNS values into appdata `direct.env`. After the values are safely
   copied, remove the now-commented archived `TUNNEL_TOKEN` line from the repo
   `.env`; also remove any archived direct-DNS secret lines there. Leave only
   the two non-secret ingress path settings there; keep the ordinary Compose,
   SWAG, Immich, path, and database settings in the main `.env`.

4. Fill in the remaining `.env` and appdata secret-file values, then generate
   the DNS plugin file, exact-host vhost, and restrictive TLS catch-all:

   ```bash
   bash immich/configure_swag.sh
   ```

   The helper reads `IMMICH_DIRECT_ENV` literally from the main `.env` and
   refuses to replace any generated file unless `--force` is used.

5. Start the stack with both the base Compose file and the plugin-managed
   override; do not edit the override manually:

   ```bash
   docker compose --env-file immich/.env \
     -f immich/compose.yaml \
     -f immich/compose.override.yaml up -d
   ```

6. Confirm the DNS-01 certificate for both labels and validate the generated
   Nginx configuration. After a forced regeneration, recreate/restart SWAG
   before this check:

   ```bash
   docker compose --env-file immich/.env \
     -f immich/compose.yaml \
     -f immich/compose.override.yaml exec swag nginx -t
   docker compose --env-file immich/.env \
     -f immich/compose.yaml \
     -f immich/compose.override.yaml logs swag
   ```

## Switching modes

Use the companion toggle explicitly, after the direct path has been tested:

```bash
bash immich/toggle_direct.sh direct --ready
bash immich/toggle_direct.sh tunnel
```

In **direct** mode, enable the router's WAN TCP 443 to host IPv4 high-port
mapping and use a DNS-only record for the canonical hostname pointing to
`IMMICH_DIRECT_IPV4`. This path bypasses Cloudflare Access, WAF, rate limiting,
and origin hiding, so enable it only briefly and close it at the router when
finished.

In normal **Tunnel** mode, use the Cloudflare Tunnel target from appdata
`direct.env` for the canonical DNS record, then disable/remove the direct NAT
and firewall opening. The direct origin must be closed at the router while
normal Tunnel mode is active.

## Validation

- Confirm `immich-server` and `swag` are healthy and run `nginx -t` inside SWAG.
- Confirm SWAG logs show successful DNS-01 issuance and no Nginx errors.
- From an external network, request the canonical API endpoint, for example
  `https://photo.<SWAG_URL>/api/server/ping`, and verify the Immich UI and
  WebSocket features. Test both direct and Tunnel modes separately.
- Verify an unknown host or direct-IP HTTPS request does not show SWAG's stock
  landing page, and verify no host port 2283 is published.
