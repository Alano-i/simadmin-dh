SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

TARGET_X86 ?= x86_64-unknown-linux-gnu
TARGET_X86_MUSL ?= x86_64-unknown-linux-musl
TARGET_ARM64_MUSL ?= aarch64-unknown-linux-musl
TARGET_X86_CC ?= $(shell command -v x86_64-linux-gnu-gcc 2>/dev/null || command -v x86_64-unknown-linux-gnu-gcc 2>/dev/null || printf 'x86_64-linux-gnu-gcc')
TARGET_X86_MUSL_CC ?= $(shell command -v x86_64-linux-musl-gcc 2>/dev/null || command -v x86_64-unknown-linux-musl-gcc 2>/dev/null || printf 'x86_64-unknown-linux-musl-gcc')
TARGET_ARM64_MUSL_CC ?= $(shell command -v aarch64-linux-musl-gcc 2>/dev/null || command -v aarch64-unknown-linux-musl-gcc 2>/dev/null || printf 'aarch64-unknown-linux-musl-gcc')
CARGO ?= $(shell command -v cargo 2>/dev/null || if [ -x "$$HOME/.cargo/bin/cargo" ]; then printf '%s/.cargo/bin/cargo' "$$HOME"; else printf 'cargo'; fi)
RUSTUP ?= $(shell command -v rustup 2>/dev/null || if [ -x "$$HOME/.cargo/bin/rustup" ]; then printf '%s/.cargo/bin/rustup' "$$HOME"; else printf 'rustup'; fi)

VERSION := $(shell if [ -f VERSION ]; then tr -d '[:space:]' < VERSION; else printf '1.1.5'; fi)
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || printf 'unknown')
BUILD_TIME := $(shell TZ=Asia/Shanghai date +"%Y-%m-%dT%H:%M:%S+08:00")

BACKEND_BIN_X86 := backend/target/$(TARGET_X86)/release/simadmin
BACKEND_BIN_X86_MUSL := backend/target/$(TARGET_X86_MUSL)/release/simadmin
BACKEND_BIN_ARM64_MUSL := backend/target/$(TARGET_ARM64_MUSL)/release/simadmin
PACKAGE_X86 := release/simadmin_$(VERSION)_$(TARGET_X86).tar.gz
PACKAGE_X86_MUSL := release/simadmin_$(VERSION)_$(TARGET_X86_MUSL).tar.gz
PACKAGE_ARM64_MUSL := release/simadmin_$(VERSION)_$(TARGET_ARM64_MUSL).tar.gz

.PHONY: help x86 x86-musl arm64-musl backend-x86 backend-x86-musl backend-arm64-musl frontend frontend-install package-x86 package-x86-musl package-arm64-musl package-all print-x86-path check-cargo check-node

help:
	@printf '%s\n' 'SimAdmin build targets:'
	@printf '%s\n' '  make x86              Build frontend and Linux x86_64 backend'
	@printf '%s\n' '  make x86-musl         Build frontend and Linux x86_64 musl backend'
	@printf '%s\n' '  make arm64-musl       Build frontend and Linux arm64 musl backend'
	@printf '%s\n' '  make backend-x86      Build Linux x86_64 backend only'
	@printf '%s\n' '  make frontend         Build frontend only'
	@printf '%s\n' '  make frontend-install Install/update frontend dependencies'
	@printf '%s\n' '  make package-x86      Build and package x86_64 release tarball'
	@printf '%s\n' '  make package-x86-musl Build and package x86_64 musl tarball'
	@printf '%s\n' '  make package-arm64-musl Build and package arm64 musl tarball'
	@printf '%s\n' '  make package-all      Build and package all Linux release tarballs'
	@printf '%s\n' ''
	@printf '%s\n' 'Variables:'
	@printf '  TARGET_X86=%s\n' '$(TARGET_X86)'
	@printf '  TARGET_X86_MUSL=%s\n' '$(TARGET_X86_MUSL)'
	@printf '  TARGET_ARM64_MUSL=%s\n' '$(TARGET_ARM64_MUSL)'

x86: frontend backend-x86

x86-musl: frontend backend-x86-musl

arm64-musl: frontend backend-arm64-musl

frontend: check-node
	cd frontend && PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN=false pnpm run build

frontend-install: check-node
	cd frontend && CI=true pnpm install --frozen-lockfile --config.confirmModulesPurge=false

backend-x86: check-cargo
	@if command -v "$(RUSTUP)" >/dev/null 2>&1; then "$(RUSTUP)" target add "$(TARGET_X86)"; fi
	@command -v "$(TARGET_X86_CC)" >/dev/null 2>&1 || { printf '%s\n' 'x86_64 Linux GNU cross compiler is required. Try: brew tap messense/macos-cross-toolchains && brew trust --formula messense/macos-cross-toolchains/x86_64-unknown-linux-gnu && brew install x86_64-unknown-linux-gnu'; exit 1; }
	cd backend && CC_x86_64_unknown_linux_gnu="$(TARGET_X86_CC)" CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$(TARGET_X86_CC)" SQLITE3_STATIC=1 LIBSQLITE3_SYS_USE_PKG_CONFIG=0 "$(CARGO)" build --release --target "$(TARGET_X86)"
	@ls -lh "$(BACKEND_BIN_X86)"

backend-x86-musl: check-cargo
	@if command -v "$(RUSTUP)" >/dev/null 2>&1; then "$(RUSTUP)" target add "$(TARGET_X86_MUSL)"; fi
	@command -v "$(TARGET_X86_MUSL_CC)" >/dev/null 2>&1 || { printf '%s\n' 'x86_64 Linux musl cross compiler is required. Try: brew install messense/macos-cross-toolchains/x86_64-unknown-linux-musl'; exit 1; }
	cd backend && CC_x86_64_unknown_linux_musl="$(TARGET_X86_MUSL_CC)" CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER="$(TARGET_X86_MUSL_CC)" SQLITE3_STATIC=1 LIBSQLITE3_SYS_USE_PKG_CONFIG=0 "$(CARGO)" build --release --target "$(TARGET_X86_MUSL)"
	@ls -lh "$(BACKEND_BIN_X86_MUSL)"

backend-arm64-musl: check-cargo
	@if command -v "$(RUSTUP)" >/dev/null 2>&1; then "$(RUSTUP)" target add "$(TARGET_ARM64_MUSL)"; fi
	@command -v "$(TARGET_ARM64_MUSL_CC)" >/dev/null 2>&1 || { printf '%s\n' 'aarch64 Linux musl cross compiler is required. Try: brew install messense/macos-cross-toolchains/aarch64-unknown-linux-musl'; exit 1; }
	cd backend && CC_aarch64_unknown_linux_musl="$(TARGET_ARM64_MUSL_CC)" CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="$(TARGET_ARM64_MUSL_CC)" SQLITE3_STATIC=1 LIBSQLITE3_SYS_USE_PKG_CONFIG=0 "$(CARGO)" build --release --target "$(TARGET_ARM64_MUSL)"
	@ls -lh "$(BACKEND_BIN_ARM64_MUSL)"

package-x86: x86
	@mkdir -p release
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	cp "$(BACKEND_BIN_X86)" "$$tmp/simadmin"; \
	chmod 755 "$$tmp/simadmin"; \
	mkdir -p "$$tmp/www"; \
	cp -R frontend/dist/. "$$tmp/www/"; \
	if command -v md5sum >/dev/null 2>&1; then \
		binary_md5="$$(md5sum "$$tmp/simadmin" | awk '{print $$1}')"; \
		frontend_md5="$$(find "$$tmp/www" -type f -exec md5sum {} \; | awk '{print $$1}' | sort | md5sum | awk '{print $$1}')"; \
	else \
		binary_md5="$$(md5 -q "$$tmp/simadmin")"; \
		frontend_md5="$$(find "$$tmp/www" -type f -exec md5 -q {} \; | sort | md5 -q)"; \
	fi; \
	printf '{\n  "version": "%s",\n  "commit": "%s",\n  "build_time": "%s",\n  "binary_md5": "%s",\n  "frontend_md5": "%s",\n  "arch": "%s"\n}\n' "$(VERSION)" "$(COMMIT)" "$(BUILD_TIME)" "$$binary_md5" "$$frontend_md5" "$(TARGET_X86)" > "$$tmp/meta.json"; \
	if command -v xattr >/dev/null 2>&1; then xattr -cr "$$tmp"; fi; \
	COPYFILE_DISABLE=1 tar -czf "$(PACKAGE_X86)" -C "$$tmp" meta.json simadmin www; \
	ls -lh "$(PACKAGE_X86)"

package-x86-musl: x86-musl
	@mkdir -p release
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	cp "$(BACKEND_BIN_X86_MUSL)" "$$tmp/simadmin"; \
	chmod 755 "$$tmp/simadmin"; \
	mkdir -p "$$tmp/www"; \
	cp -R frontend/dist/. "$$tmp/www/"; \
	if command -v md5sum >/dev/null 2>&1; then \
		binary_md5="$$(md5sum "$$tmp/simadmin" | awk '{print $$1}')"; \
		frontend_md5="$$(find "$$tmp/www" -type f -exec md5sum {} \; | awk '{print $$1}' | sort | md5sum | awk '{print $$1}')"; \
	else \
		binary_md5="$$(md5 -q "$$tmp/simadmin")"; \
		frontend_md5="$$(find "$$tmp/www" -type f -exec md5 -q {} \; | sort | md5 -q)"; \
	fi; \
	printf '{\n  "version": "%s",\n  "commit": "%s",\n  "build_time": "%s",\n  "binary_md5": "%s",\n  "frontend_md5": "%s",\n  "arch": "%s"\n}\n' "$(VERSION)" "$(COMMIT)" "$(BUILD_TIME)" "$$binary_md5" "$$frontend_md5" "$(TARGET_X86_MUSL)" > "$$tmp/meta.json"; \
	if command -v xattr >/dev/null 2>&1; then xattr -cr "$$tmp"; fi; \
	COPYFILE_DISABLE=1 tar -czf "$(PACKAGE_X86_MUSL)" -C "$$tmp" meta.json simadmin www; \
	ls -lh "$(PACKAGE_X86_MUSL)"

package-arm64-musl: arm64-musl
	@mkdir -p release
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	cp "$(BACKEND_BIN_ARM64_MUSL)" "$$tmp/simadmin"; \
	chmod 755 "$$tmp/simadmin"; \
	mkdir -p "$$tmp/www"; \
	cp -R frontend/dist/. "$$tmp/www/"; \
	if command -v md5sum >/dev/null 2>&1; then \
		binary_md5="$$(md5sum "$$tmp/simadmin" | awk '{print $$1}')"; \
		frontend_md5="$$(find "$$tmp/www" -type f -exec md5sum {} \; | awk '{print $$1}' | sort | md5sum | awk '{print $$1}')"; \
	else \
		binary_md5="$$(md5 -q "$$tmp/simadmin")"; \
		frontend_md5="$$(find "$$tmp/www" -type f -exec md5 -q {} \; | sort | md5 -q)"; \
	fi; \
	printf '{\n  "version": "%s",\n  "commit": "%s",\n  "build_time": "%s",\n  "binary_md5": "%s",\n  "frontend_md5": "%s",\n  "arch": "%s"\n}\n' "$(VERSION)" "$(COMMIT)" "$(BUILD_TIME)" "$$binary_md5" "$$frontend_md5" "$(TARGET_ARM64_MUSL)" > "$$tmp/meta.json"; \
	if command -v xattr >/dev/null 2>&1; then xattr -cr "$$tmp"; fi; \
	COPYFILE_DISABLE=1 tar -czf "$(PACKAGE_ARM64_MUSL)" -C "$$tmp" meta.json simadmin www; \
	ls -lh "$(PACKAGE_ARM64_MUSL)"

package-all: package-x86 package-x86-musl package-arm64-musl

print-x86-path:
	@printf '%s\n' "$(BACKEND_BIN_X86)"

check-cargo:
	@command -v "$(CARGO)" >/dev/null 2>&1 || { printf '%s\n' 'cargo is required. Install Rust with rustup first.'; exit 1; }

check-node:
	@command -v node >/dev/null 2>&1 || { printf '%s\n' 'node is required.'; exit 1; }
	@command -v pnpm >/dev/null 2>&1 || { printf '%s\n' 'pnpm is required. Try: corepack enable && corepack prepare pnpm@11 --activate'; exit 1; }
