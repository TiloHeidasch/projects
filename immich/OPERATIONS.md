# Immich operations

## Ingress and networks

`cloudflared` and SWAG always run. Both attach only to the `proxy` network;
`immich-server` bridges `proxy` and the backend-only network used by ML, Valkey,
and Postgres. The Tunnel and SWAG reach `immich-server:2283`. Port 2283 is
never published on the host.

The application URL is unchanged, for example `photo.<SWAG_URL>`. SWAG serves
the exact hosts `photo.<SWAG_URL>` and `photo2.<SWAG_URL>`.

## Prerequisites

- A direct public IPv4 address (not CGNAT) and control of the Cloudflare DNS
  zone.
- A router rule that can forward WAN TCP 443 to the Unraid host IPv4 on TCP
  8443 (or the configured `SWAG_HOST_PORT`), not host port 443.
- A separate IPv6 firewall rule blocking the published SWAG port unless IPv6
  direct access is intentionally configured. An IPv4 NAT rule does not protect
  IPv6.

## One-time setup

1. Run the normal environment sync, then edit the ignored `immich/.env` with
   both `TUNNEL_TOKEN` and `CF_DNS_API_TOKEN`, plus the SWAG and application
   values. Live secrets stay in this ignored file; none belong in Git.

   ```bash
   bash 02_sync-env.sh
   ```

2. Generate the DNS plugin credentials and hardened SWAG configuration:

   ```bash
   bash immich/configure_swag.sh
   ```

   The helper reads only the sibling `.env`, never executes it, and refuses to
   replace generated files unless `--force` is used.

3. Start both Compose files through the normal project command. Do not edit
   the plugin-managed override:

   ```bash
   docker compose --env-file immich/.env \
     -f immich/compose.yaml \
     -f immich/compose.override.yaml up -d
   ```

4. Confirm SWAG obtains DNS-01 certificates for both hosts and validate Nginx:

   ```bash
   docker compose --env-file immich/.env \
     -f immich/compose.yaml \
     -f immich/compose.override.yaml exec swag nginx -t
   docker compose --env-file immich/.env \
     -f immich/compose.yaml \
     -f immich/compose.override.yaml logs swag
   ```

## DNS and firewall modes

DNS switching is owned by the user's local Cloudflare agent, not by this
repository. It must maintain both records as follows:

- **Tunnel mode:** `photo` and `photo2` use proxied CNAME records to the
  Cloudflare Tunnel UUID target.
- **Direct mode:** `photo` and `photo2` use DNS-only A records to the WAN IPv4.

In direct mode, briefly open the router rule for WAN TCP 443 to the Unraid
host's TCP 8443 (or configured high port). In normal Tunnel mode, close/remove
that NAT and firewall opening; the direct origin must be closed at the router.
Direct DNS-only mode bypasses Cloudflare Access, WAF, rate limiting, and origin
hiding, so it should be enabled only for the required maintenance window.

## Validation

- Confirm `immich-server` and `swag` are healthy and `nginx -t` succeeds inside
  SWAG.
- From an external network, request
  `https://photo.<SWAG_URL>/api/server/ping` and verify the UI and WebSocket
  features. Test both DNS modes separately.
- Verify `photo2.<SWAG_URL>` and confirm unknown host/direct-IP requests do not
  show SWAG's stock landing page.
- Confirm no host port 2283 is published.
