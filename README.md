# Ubuntu Tailscale Installer

[![CI](https://github.com/Amir1ted/tailscale-installer/actions/workflows/ci.yml/badge.svg)](https://github.com/Amir1ted/tailscale-installer/actions/workflows/ci.yml)
[![Ubuntu 20.04+](https://img.shields.io/badge/Ubuntu-20.04%2B-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![ShellCheck](https://img.shields.io/badge/lint-ShellCheck-4EAA25?logo=gnu-bash&logoColor=white)](https://www.shellcheck.net/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A security-conscious, idempotent Bash installer that installs and provisions
Tailscale on Ubuntu Server from Tailscale's official APT repository.

> This is an independent community project. It is not affiliated with or
> endorsed by Tailscale Inc. Tailscale is a trademark of Tailscale Inc.

## Why this project?

The official one-line installer is convenient, but production automation
usually needs a reviewable workflow, safe secret handling, repeatable
behavior, CI, and clear operational documentation. This project provides those
pieces without hiding the underlying APT and `tailscale` commands.

Key features:

- Uses the official, codename-specific Tailscale APT repository
- Never pipes a remote script directly into a shell
- Safe to run repeatedly; no duplicate configuration is created
- Supports interactive login and unattended auth-key provisioning
- Passes auth keys through `--auth-key=file:PATH` rather than the process list
- Validates Ubuntu, systemd, repository metadata, hostnames, tags, and
  key-file permissions
- Enables and verifies `tailscaled`
- Supports Tailscale SSH, subnet-route acceptance, custom hostnames, tags, and
  a non-root operator
- Keeps full Ubuntu upgrades opt-in
- Ships with dry-run mode, strict Bash settings, a test suite, ShellCheck CI,
  issue templates, and release automation

## Requirements

- Ubuntu 20.04 or newer
- A Tailscale-supported Ubuntu codename in the
  [official package repository](https://pkgs.tailscale.com/stable/)
- `systemd`
- Root privileges
- Outbound HTTPS access to Ubuntu mirrors and `pkgs.tailscale.com`

Ubuntu 22.04 LTS and 24.04 LTS are the primary targets. Newer supported Ubuntu
releases work dynamically through `VERSION_CODENAME`.

## Quick start

Clone or download the project, review the script, then run:

```bash
chmod +x install.sh
sudo ./install.sh --login
```

To install without starting authentication:

```bash
sudo ./install.sh
sudo tailscale up
```

The default run deliberately installs only Tailscale and its small
dependencies. It does **not** upgrade every package on the server.

## Unattended server provisioning

Create a tagged, pre-authorized auth key in the Tailscale admin console, store
it in a root-only file, and run:

```bash
sudo install -m 600 /dev/null /run/tailscale-authkey
sudoedit /run/tailscale-authkey

sudo ./install.sh \
  --auth-key-file /run/tailscale-authkey \
  --hostname app-01 \
  --advertise-tags tag:server \
  --ssh
```

Delete the source key file after successful provisioning if your secret
manager does not manage its lifecycle. Prefer one-off, tagged, pre-authorized
keys when they fit your deployment.

## Common examples

Preview every planned action:

```bash
sudo ./install.sh --dry-run --no-color
```

Accept advertised subnet routes:

```bash
sudo ./install.sh --login --accept-routes
```

Allow a local user to operate `tailscaled` without `sudo`:

```bash
sudo ./install.sh --login --operator ubuntu
```

Use the unstable Tailscale package track:

```bash
sudo ./install.sh --channel unstable --login
```

Upgrade all installed Ubuntu packages before installation:

```bash
sudo ./install.sh --upgrade-system --login
```

## Options

| Option | Purpose |
| --- | --- |
| `--login` | Start browser-based interactive authentication |
| `--no-login` | Install only; this is the default |
| `--auth-key-file PATH` | Authenticate from a file that is not group/world-readable |
| `--hostname NAME` | Set the node's Tailscale/MagicDNS name |
| `--advertise-tags TAGS` | Advertise comma-separated tags such as `tag:server` |
| `--ssh` | Enable the Tailscale SSH server; tailnet policy still controls access |
| `--accept-routes` | Accept routes advertised by subnet routers |
| `--operator USER` | Let an existing local Unix user operate `tailscaled` |
| `--channel TRACK` | Use `stable` or `unstable` |
| `--upgrade-system` | Opt in to a full `apt-get upgrade` |
| `--dry-run` | Print planned commands without persistent system changes |
| `--no-color` | Disable ANSI colors |
| `-h`, `--help` | Show built-in help |
| `-v`, `--version` | Print the installer version |

See [Usage](docs/USAGE.md) for behavior, automation examples, and exit
semantics.

## Security model

- Repository configuration is fetched only over HTTPS from
  `pkgs.tailscale.com`.
- The downloaded key must parse as OpenPGP data.
- The downloaded APT source must exactly match the expected official
  repository, track, Ubuntu codename, and `signed-by` path.
- A supplied auth-key file must be a regular readable file with no group or
  other permissions.
- The key is supplied as `--auth-key=file:PATH`, so its value never lands in
  command-line arguments or installer logs.
- `TS_AUTHKEY` is supported for CI compatibility, but the installer immediately
  copies it into a temporary `0600` file and unsets its local copy. A mounted
  secret file is still preferred.
- Enabling Tailscale SSH does not grant access by itself. Your tailnet access
  policy remains authoritative.
- Disabling key expiry is never done automatically. Do it only for trusted
  nodes, and only if you accept the risk.

Read [Security notes](docs/SECURITY-NOTES.md) and the project's
[security policy](SECURITY.md) before a production rollout.

## Development

Run the local checks:

```bash
make check
```

Create a distributable archive:

```bash
make package
```

ShellCheck is optional locally but required by CI. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow.

## Documentation

- [Usage and automation](docs/USAGE.md)
- [Architecture and execution flow](docs/ARCHITECTURE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Security notes](docs/SECURITY-NOTES.md)
- [Changelog](CHANGELOG.md)
- [Support](SUPPORT.md)

## Official references

- [Install Tailscale on Linux](https://tailscale.com/docs/install/linux)
- [Tailscale stable packages](https://pkgs.tailscale.com/stable/)
- [`tailscale up` reference](https://tailscale.com/docs/reference/tailscale-cli/up)
- [Set up a Tailscale server](https://tailscale.com/docs/how-to/set-up-servers)
- [Tailscale CLI reference](https://tailscale.com/docs/reference/tailscale-cli)

## License

Released under the [MIT License](LICENSE).
