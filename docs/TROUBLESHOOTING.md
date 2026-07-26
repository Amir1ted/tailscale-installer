# Troubleshooting

## The script says it must run as root

Run:

```bash
sudo ./install.sh --login
```

Do not weaken the root check. APT repository files and systemd services require
administrative access.

## `systemd is not running`

This installer targets Ubuntu Server hosts booted with systemd. Minimal
containers and some WSL configurations do not run systemd even when
`systemctl` is installed.

For a container, follow Tailscale's container-specific documentation. For WSL,
enable systemd in the supported WSL configuration before using this project.

## The repository URL returns 404

The detected Ubuntu codename is not published on the selected Tailscale track.
Check:

```bash
. /etc/os-release
printf '%s %s\n' "$VERSION_ID" "$VERSION_CODENAME"
```

Then confirm that codename on the
[official package page](https://pkgs.tailscale.com/stable/). Do not substitute
another Ubuntu codename unless Tailscale explicitly documents that combination.

## APT reports a signature error

Check system time, HTTPS interception, and the current repository files:

```bash
timedatectl status
sudo apt-get update
```

Re-running the installer refreshes the dedicated keyring and source definition.
If the issue persists, compare it with the Tailscale status page and official
package instructions.

## `tailscaled` is not active

Inspect the service and recent logs:

```bash
sudo systemctl status tailscaled --no-pager
sudo journalctl -u tailscaled -n 200 --no-pager
```

Generate a diagnostic identifier when contacting Tailscale support:

```bash
sudo tailscale bugreport
```

Do not paste auth keys, node keys, or unrelated sensitive journal data into a
public issue.

## Authentication remains at `NeedsLogin`

Run interactive login and open the displayed URL:

```bash
sudo tailscale up
```

For automation, verify that the auth key is unexpired, valid for the target
tailnet, and approved for requested tags.

## Auth-key file permission failure

Protect the file:

```bash
sudo chown root:root /run/secrets/tailscale-authkey
sudo chmod 600 /run/secrets/tailscale-authkey
```

The installer rejects files accessible by group or other.

## Requested tags were not changed

The node was already connected. The installer avoids a potentially disruptive
re-authentication. Provision tags with a tagged auth key on first connection or
perform a deliberate re-authentication after reviewing current preferences and
tailnet policy.

## Cannot connect over SSH

Check each layer:

```bash
tailscale status
tailscale ping <target>
ssh -vvv <user>@<target>
```

Also verify:

- both nodes are in the expected tailnet;
- the target is `Running`;
- tailnet network access allows TCP port 22;
- Tailscale SSH policy allows the source, destination, and Unix user when using
  Tailscale SSH;
- traditional `sshd` is listening when using ordinary SSH over a Tailscale IP.

## Collecting safe issue information

Include:

- Ubuntu version and codename;
- installer version (`./install.sh --version`);
- Tailscale version (`tailscale version`);
- selected options with all secret values removed;
- failing phase and exit code;
- sanitized service output.

Never include an auth key or signed authentication URL.
