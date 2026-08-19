# Meeet-dev operations

This document covers the dev Unraid Compose Manager stack. Its Compose
definition may differ from the upstream production template.

## Components and ingress

The stack contains the one-shot `compiler`, `meeet-dev`, and `cloudflared`. Meeet
is accessed only through the cloudflared Tunnel; no host port is exposed.
Cloudflared uses Docker DNS to reach `http://meeet-dev:3000`. Meeet starts only
after the `compiler` one-shot completes successfully.

## Required configuration

Put these values in the ignored `.env` on Unraid, not in Git:

- `TUNNEL_TOKEN`: token for the remotely managed Cloudflare Tunnel.
- `MEEET_IMAGE`: a known Meeet runner image reference; prefer a digest.
- `MEEET_COMPILER_IMAGE`: a known artifact-compiler image reference; prefer the
  digest-pinned value printed by the publish workflow.
- `MEEET_SCHEDULE_HOST_DIR`: existing host directory containing the schedule
  artifact pair.

Private GHCR images require `docker login ghcr.io` on Unraid with an account or
token that has `read:packages`. Keep the credentials out of Git.

## Cloudflare setup

Create a remotely managed Tunnel and configure its public hostname origin as
`http://meeet-dev:3000`. The Tunnel token is the `TUNNEL_TOKEN` value. Do not add a
local cloudflared configuration file.

## Image updates and rollback

Before updating, record the current `MEEET_IMAGE` and `MEEET_COMPILER_IMAGE`
references. Set them to known Meeet runner and artifact-compiler references,
preferably digests, then recreate or restart the Meeet stack through Compose
Manager. A `sha-...` tag is operator-selected and is not an immutable
reference.

To roll back, restore the recorded image references in the ignored `.env` and
recreate or restart the stack through Compose Manager again.

## Schedule artifact rotation

Rotation is automatic at Meeet startup. The one-shot `compiler` service mounts
`MEEET_SCHEDULE_HOST_DIR` read-write at `/output` and runs the rotation
decision path before `meeet-dev` starts; `meeet-dev` waits for it with
`condition: service_completed_successfully` and reads the manifest from its
read-only `/opt/meeet/schedule` mount. The compiler fetches the latest MVV
feed, recompiles when the artifact is missing, stale, or built by a different
compiler version, and otherwise keeps the current artifact; it exits 0 either
way and fails hard only when no usable artifact exists.

Each rotation writes a new hash-named `.v8.bin` payload, so old payloads
accumulate in the schedule directory. After confirming the new manifest and
payload pair loads, prune the old payloads while keeping at least one archived
rollback pair.

A manual one-off compiler run still works and is intended only for offline or
backup rotations; the normal path above is automatic. `MEEET_SCHEDULE_HOST_DIR`
must already exist and contain `mvv-scheduled-artifact.json` and its matching
`.v8.bin` payload. Keep the pair together; do not rename or edit the payload
manually.

## Startup and troubleshooting

Cloudflared waits for Meeet to become healthy. The compiler one-shot runs
first; a missing, unreadable, or invalid artifact pair keeps Meeet unhealthy
and leaves the Tunnel unavailable.

The configured CPU limits are 7 for Meeet and 2 for cloudflared and the
compiler. Memory is controlled by host policy.

For background only, see the upstream
[application deployment guide](https://github.com/TiloHeidasch/meeet/blob/main/docs/application-deployment.md).
This Unraid stack is the Compose definition in this project and may differ
from the upstream production Compose file.
