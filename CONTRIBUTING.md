# Contributing

Contributions that improve safety, compatibility, tests, or documentation are
welcome.

## Before opening a change

1. Search existing issues and pull requests.
2. For behavior changes, open an issue describing the use case and operational
   risk.
3. Never include real auth keys, signed login URLs, private tailnet names, IPs,
   or unsanitized logs.

## Development workflow

```bash
git clone <your-fork-url>
cd ubuntu-tailscale-installer
make check
```

Make focused changes. Keep Bash compatible with the versions shipped by
supported Ubuntu releases. Avoid adding dependencies unless they materially
improve correctness or security.

## Required checks

```bash
bash -n install.sh tests/test.sh tests/mock-command.sh
shellcheck install.sh tests/test.sh tests/mock-command.sh
bash tests/test.sh
```

If ShellCheck is not installed locally, `make check` warns and continues; CI
still enforces it.

## Pull requests

- Explain what changed and why.
- Describe failure and rollback behavior.
- Add or update tests for logic changes.
- Update the README when user-facing behavior changes.
- Update `CHANGELOG.md` under `Unreleased`.
- Confirm no secrets or environment-specific data are present.

By contributing, you agree that your contribution is licensed under the
project's MIT License.
