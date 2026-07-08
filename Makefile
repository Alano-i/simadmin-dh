SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

TARGET_X86 ?= x86_64-unknown-linux-gnu
TARGET_X86_MUSL ?= x86_64-unknown-linux-musl

VERSION := $(shell if [ -f VERSION ]; then tr -d '[:space:]' < VERSION; else printf '1.1.5'; fi)
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || printf 'unknown')
BUILD_TIME := $(shell TZ=Asia/Shanghai date +"%Y-%m-%dT%H:%M:%S+08:00")

BACKEND_BIN_X86 := backend/target/$(TARGET_X86)/release/simadmin
BACKEND_BIN_X86_MUSL := backend/target/$(TARGET_X86_MUSL)/release/simadmin
PACKAGE_X86 := release/simadmin_$(VERSION)_$(TARGET_X86).tar.gz
PACKAGE_X86_MUSL := release/simadmin_$(VERSION)_$(TARGET_X86_MUSL).tar.gz

.PHONY: help x86 x86-musl backend-x86 backend-x86-musl frontend frontend-install package-x86 package-x86-musl print-x86-path check-cargo check-node

help:
	@printf '%s\n' 'SimAdmin build targets:'
	@printf '%s\n' '  make x86              Build frontend and Linux x86_64 backend'
	@printf '%s\n' '  make backend-x86      Build Linux x86_64 backend only'
	@printf '%s\n' '  make frontend         Build frontend only'
	@printf '%s\n' '  make frontend-install Install/update frontend dependencies'
	@printf '%s\n' '  make package-x86      Build and package x86_64 release tarball'
	@printf '%s\n' '  make x86-musl         Build static-friendly x86_64 musl backend'
	@printf '%s\n' '  make package-x86-musl Build and package x86_64 musl tarball'
	@printf '%s\n' ''
	@printf '%s\n' 'Variables:'
	@printf '  TARGET_X86=%s\n' '$(TARGET_X86)'
	@printf '  TARGET_X86_MUSL=%s\n' '$(TARGET_X86_MUSL)'

x86: frontend backend-x86

x86-musl: frontend backend-x86-musl

frontend: check-node
	cd frontend && PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN=false pnpm run build

frontend-install: check-node
	cd frontend && CI=true pnpm install --frozen-lockfile --config.confirmModulesPurge=false

backend-x86: check-cargo
	@if command -v rustup >/dev/null 2>&1; then rustup target add "$(TARGET_X86)"; fi
	cd backend && SQLITE3_STATIC=1 LIBSQLITE3_SYS_USE_PKG_CONFIG=0 cargo build --release --target "$(TARGET_X86)"
	@ls -lh "$(BACKEND_BIN_X86)"

backend-x86-musl: check-cargo
	@if command -v rustup >/dev/null 2>&1; then rustup target add "$(TARGET_X86_MUSL)"; fi
	cd backend && SQLITE3_STATIC=1 LIBSQLITE3_SYS_USE_PKG_CONFIG=0 cargo build --release --target "$(TARGET_X86_MUSL)"
	@ls -lh "$(BACKEND_BIN_X86_MUSL)"

package-x86: x86
	@mkdir -p release
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	cp "$(BACKEND_BIN_X86)" "$$tmp/simadmin"; \
	chmod 755 "$$tmp/simadmin"; \
	mkdir -p "$$tmp/www"; \
	cp -R frontend/dist/. "$$tmp/www/"; \
	printf '{\n  "version": "%s",\n  "commit": "%s",\n  "build_time": "%s",\n  "arch": "%s"\n}\n' "$(VERSION)" "$(COMMIT)" "$(BUILD_TIME)" "$(TARGET_X86)" > "$$tmp/meta.json"; \
	tar -czf "$(PACKAGE_X86)" -C "$$tmp" meta.json simadmin www; \
	ls -lh "$(PACKAGE_X86)"

package-x86-musl: x86-musl
	@mkdir -p release
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	cp "$(BACKEND_BIN_X86_MUSL)" "$$tmp/simadmin"; \
	chmod 755 "$$tmp/simadmin"; \
	mkdir -p "$$tmp/www"; \
	cp -R frontend/dist/. "$$tmp/www/"; \
	printf '{\n  "version": "%s",\n  "commit": "%s",\n  "build_time": "%s",\n  "arch": "%s"\n}\n' "$(VERSION)" "$(COMMIT)" "$(BUILD_TIME)" "$(TARGET_X86_MUSL)" > "$$tmp/meta.json"; \
	tar -czf "$(PACKAGE_X86_MUSL)" -C "$$tmp" meta.json simadmin www; \
	ls -lh "$(PACKAGE_X86_MUSL)"

print-x86-path:
	@printf '%s\n' "$(BACKEND_BIN_X86)"

check-cargo:
	@command -v cargo >/dev/null 2>&1 || { printf '%s\n' 'cargo is required. Install Rust with rustup first.'; exit 1; }

check-node:
	@command -v node >/dev/null 2>&1 || { printf '%s\n' 'node is required.'; exit 1; }
	@command -v pnpm >/dev/null 2>&1 || { printf '%s\n' 'pnpm is required. Try: corepack enable && corepack prepare pnpm@9 --activate'; exit 1; }
