# Usage and automation

## Execution behavior

The installer performs these phases in order:

1. Parse and validate options.
2. Verify root, Ubuntu, systemd, and base commands.
3. Acquire a non-blocking installer lock.
4. refresh APT metadata and install small prerequisites.
5. Optionally upgrade installed Ubuntu packages.
6. Download and validate the official Tailscale repository configuration.
7. Install or update the `tailscale` package.
8. Enable and start `tailscaled`.
9. Authenticate when explicitly requested.
10. Verify and print the local node summary.

Any failed required command stops execution and returns a non-zero exit code.
The error message includes the failed line and command. Auth-key values are
never placed in a command, so they cannot appear in this error output.

## Default: install only

```bash
sudo ./install.sh
```

This installs Tailscale and starts `tailscaled`. It does not block automation by
waiting for browser authentication. Complete login later:

```bash
sudo tailscale up
```

## Interactive login

```bash
sudo ./install.sh --login
```

Tailscale prints an authentication URL. Open it on any device, authenticate, and
approve the node. The installer succeeds only after the backend reaches the
`Running` state.

## Auth-key file

```bash
sudo ./install.sh --auth-key-file /run/secrets/tailscale-authkey
```

The path must:

- exist and be a regular file;
- be readable by root;
- have no permissions for group or other.

Use `chmod 600` (or stricter). The installer passes
`--auth-key=file:/run/secrets/tailscale-authkey` to the CLI. Tailscale reads the
key from the file.

## Environment-based auth key

Some CI systems expose secrets only as environment variables:

```bash
sudo --preserve-env=TS_AUTHKEY ./install.sh --hostname ci-node
```

When `TS_AUTHKEY` is present, the installer writes its value to a temporary
`0600` file, unsets its local environment copy, provisions Tailscale through
the file, and removes the file on exit.

A mounted secret file is preferred because environment variables can be
exposed by some process-inspection or crash-reporting configurations.

## Existing connected nodes

When the backend is already `Running`, the installer does not re-authenticate.
Requested hostname, Tailscale SSH, route acceptance, and operator changes are
applied with `tailscale set`, which updates only explicitly supplied settings.

Tags are intentionally not changed on an existing connection. Use a tagged auth
key during initial provisioning or perform a deliberate re-authentication after
reviewing the node's current preferences.

## Tailscale SSH

```bash
sudo ./install.sh --login --ssh
```

This enables the Tailscale SSH server locally. It does not override your tailnet
policy. Ensure the policy grants the intended sources, destinations, and Unix
users before relying on this access path.

Keep another tested recovery channel until Tailscale SSH is verified.

## Dry run

```bash
sudo ./install.sh --dry-run --no-color
```

Dry-run mode performs platform validation and prints mutating commands. It does
not acquire the persistent installer lock, invoke APT, install repository files,
start services, or authenticate.

## Package tracks

The default is Tailscale's `stable` track:

```bash
sudo ./install.sh --channel stable
```

For testing pre-release builds:

```bash
sudo ./install.sh --channel unstable
```

Changing the track replaces `/etc/apt/sources.list.d/tailscale.list` with the
requested official source. A later stable run switches it back.

## System upgrades

The installer refreshes APT metadata and installs only its prerequisites and
Tailscale. To request a full package upgrade:

```bash
sudo ./install.sh --upgrade-system
```

Review your maintenance, reboot, and rollback procedures first. This option
runs `apt-get upgrade -y`; it does not automatically reboot.

## Idempotency

Re-running the same command:

- refreshes the same official repository files;
- asks APT to install the already-selected package;
- keeps `tailscaled` enabled and active;
- avoids re-authentication when already connected;
- applies only explicitly requested mutable settings.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Requested installation/configuration completed |
| non-zero | Validation, download, APT, service, authentication, or settings failure |

Install-only mode can return `0` with backend state `NeedsLogin`; this is
intentional and is clearly shown in the summary.
