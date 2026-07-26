SHELL := /bin/bash
.DEFAULT_GOAL := check

PROJECT := ubuntu-tailscale-installer
VERSION := $(shell tr -d '[:space:]' < VERSION)
ARCHIVE := dist/$(PROJECT)-v$(VERSION).zip

.PHONY: help syntax lint test check package clean

help:
	@printf '%s\n' \
		'make syntax   Validate Bash syntax' \
		'make lint     Run ShellCheck (when installed)' \
		'make test     Run the test suite' \
		'make check    Run syntax, lint, and tests' \
		'make package  Build a versioned ZIP in dist/' \
		'make clean    Remove the generated dist archive'

syntax:
	bash -n install.sh tests/test.sh tests/mock-command.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck install.sh tests/test.sh tests/mock-command.sh; \
	else \
		printf '%s\n' 'warning: shellcheck is not installed; CI will enforce it'; \
	fi

test:
	bash tests/test.sh

check: syntax lint test

package: check
	@mkdir -p dist
	@rm -f -- "$(ARCHIVE)"
	@zip -q -r "$(ARCHIVE)" . \
		-x '.git/*' \
		-x 'dist/*' \
		-x '*.DS_Store'
	@printf 'Created %s\n' "$(ARCHIVE)"
	@sha256sum "$(ARCHIVE)"

clean:
	@rm -f -- "$(ARCHIVE)"
