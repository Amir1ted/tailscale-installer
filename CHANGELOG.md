# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Changed

- Consolidated documentation to English only; removed `README.fa.md` and the
  bilingual documentation requirement from the contribution checklists

## 1.0.1 - 2026-07-26

### Fixed

- Made CI and the test suite independent of executable permission bits, which
  can be lost when project files are uploaded through GitHub's web interface
- Replaced the grouped Dependabot configuration with GitHub's minimal
  documented `github-actions` configuration for maximum schema compatibility

## 1.0.0 - 2026-07-26

### Added

- Official codename-specific Tailscale APT repository installation
- Strict Ubuntu and systemd preflight checks
- Interactive and protected auth-key-file provisioning
- Hostname, tags, Tailscale SSH, route acceptance, operator, and track options
- Safe defaults, dry-run mode, idempotent connected-node behavior, and
  actionable summaries
- English and Persian documentation
- Bash tests, ShellCheck CI, GitHub templates, Dependabot, and tagged releases
