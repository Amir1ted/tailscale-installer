# Security notes

## Auth keys

Treat Tailscale auth keys as secrets. Prefer:

- one-off keys for individual servers;
- tags that grant only the required identity;
- pre-authorized keys only where device-approval workflow requires them;
- ephemeral keys for genuinely ephemeral workloads;
- a secret manager that mounts a short-lived root-only file.

The installer validates local file permissions and passes the path through
Tailscale's supported `file:` syntax. It cannot control copies held by your
shell history, CI platform, secret manager, backups, or monitoring system.

Do not put a literal key in:

- a command-line option;
- this repository;
- cloud-init logs;
- screenshots or issue reports;
- a world-readable environment file.

## Tailnet policy

Installation creates network membership, not authorization. Use least-privilege
grants/ACLs and tags. Enabling `--ssh` starts the local Tailscale SSH server, but
the tailnet policy decides who can reach it and which Unix identities they can
use.

## Key expiry

The installer does not disable device key expiry. Disabling expiry can improve
availability for a trusted server, but increases the impact of a stolen node
key. Make that decision in the admin console with an incident-revocation
procedure in place.

## Repository trust

The installer follows the official per-codename APT repository layout. It
checks transport, parses the downloaded OpenPGP key, and requires an exact APT
source definition with a dedicated `signed-by` keyring.

Like the official manual installation flow, initial repository trust is
bootstrapped over HTTPS. A future release may pin a published key fingerprint
if Tailscale documents a stable rotation policy suitable for automation.

## Server access and recovery

Before changing SSH behavior:

- confirm console or out-of-band recovery access;
- verify tailnet policy with a non-production node;
- keep an existing session open until a new connection succeeds;
- document how to revoke the node and auth key.

## Logs and diagnostics

The installer does not print auth-key values. Failed command reporting can show
paths, hostnames, tags, and package sources. Treat operational logs according to
your infrastructure metadata policy.

Review journal output before sharing it outside your organization.
