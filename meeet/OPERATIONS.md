# Meeet operations

This document covers the live Unraid Compose Manager stack. Its Compose
definition may differ from the upstream production template.

## Components and ingress

The stack contains `meeet` and `cloudflared`. Meeet is accessed only through
the cloudflared Tunnel; no host port is exposed. Cloudflared uses Docker DNS to
reach `http://meeet:3000`.

## Required configuration

Put these values in the ignored `.env` on Unraid, not in Git:

- `TUNNEL_TOKEN`: token for the remotely managed Cloudflare Tunnel.
- `MEEET_IMAGE`: a known Meeet runner image reference; prefer a digest.
- `MEEET_SCHEDULE_HOST_DIR`: existing host directory containing the schedule
  artifact pair.

Private GHCR images require `docker login ghcr.io` on Unraid with an account or
token that has `read:packages`. Keep the credentials out of Git.

## Cloudflare setup

Create a remotely managed Tunnel and configure its public hostname origin as
`http://meeet:3000`. The Tunnel token is the `TUNNEL_TOKEN` value. Do not add a
local cloudflared configuration file.

## Image updates and rollback

Before updating, record the current `MEEET_IMAGE` reference. Set it to a known
Meeet runner reference, preferably a digest, then recreate or restart the Meeet
stack through Compose Manager. A `sha-...` tag is operator-selected and is not
an immutable reference.

To roll back, restore the recorded image reference in the ignored `.env` and
recreate or restart the stack through Compose Manager again.

## Schedule artifact rotation

`MEEET_SCHEDULE_HOST_DIR` must already exist and contain both
`mvv-scheduled-artifact.json` and its matching `.v8.bin` payload. Both files
come from the matching Meeet artifact compiler on Node 24. Keep the pair
together and preserve the previous pair before rotating to a new one. Restart
Meeet after updating the artifact pair.

## Startup and troubleshooting

Cloudflared waits for Meeet to become healthy. Meeet's ready endpoint is checked
every 5 seconds during its 60-second startup period and every 30 seconds
afterwards, with a 10-second timeout and 5 retries. A missing, unreadable, or
invalid artifact pair keeps Meeet unhealthy and leaves the Tunnel unavailable.

The configured CPU limits are 7 for Meeet and 2 for cloudflared. Memory is
controlled by host policy.

For background only, see the upstream
[application deployment guide](https://github.com/TiloHeidasch/meeet/blob/main/docs/application-deployment.md).
The live Unraid stack is the Compose definition in this project and may differ
from the upstream production Compose file.
