#!/bin/sh

set -eu

REPO="${REPO:-Alano-i/simadmin-dh}"
SOURCE_DIR="${SOURCE_DIR:-$(CDPATH= cd "$(dirname "$0")" && pwd)}"
INSTALL_MODE="${INSTALL_MODE:-release}"
INSTALL_DIR="${INSTALL_DIR:-/opt/simadmin}"
SERVICE_NAME="${SERVICE_NAME:-simadmin}"
SIMADMIN_ENV_FILE="${SIMADMIN_ENV_FILE:-/etc/default/simadmin}"
VERSION="${VERSION:-latest}"
BUILD_TARGET="${BUILD_TARGET:-x86_64-unknown-linux-gnu}"
SIMADMIN_INSTALL_RUNTIME_DEPS="${SIMADMIN_INSTALL_RUNTIME_DEPS:-1}"
SIMADMIN_INSTALL_BUILD_DEPS="${SIMADMIN_INSTALL_BUILD_DEPS:-1}"
SIMADMIN_NODE_MAJOR="${SIMADMIN_NODE_MAJOR:-22}"
SIMADMIN_PNPM_VERSION="${SIMADMIN_PNPM_VERSION:-11}"
SIMADMIN_FORCE_FRONTEND_INSTALL="${SIMADMIN_FORCE_FRONTEND_INSTALL:-1}"
GH_PROXY="${GH_PROXY:-https://gh-proxy.com/}"
GH_PROXY_FALLBACKS="${GH_PROXY_FALLBACKS:-https://ghproxy.net/ https://githubproxy.cc/}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${REPO}}"
SERVICE_URL="${SERVICE_URL:-${RAW_BASE}/main/scripts/simadmin.service}"
MODEM_RECOVERY_SCRIPT_URL="${MODEM_RECOVERY_SCRIPT_URL:-${RAW_BASE}/main/scripts/simadmin-modem-recovery.sh}"
MODEM_RECOVERY_SERVICE_URL="${MODEM_RECOVERY_SERVICE_URL:-${RAW_BASE}/main/scripts/simadmin-modem-recovery.service}"
ASSET_URL="${ASSET_URL:-}"
ASSET_NAME="${ASSET_NAME:-}"
SIMADMIN_INSTALL_LPAC="${SIMADMIN_INSTALL_LPAC:-1}"
LPAC_REPO="${LPAC_REPO:-estkme-group/lpac}"
LPAC_RELEASE_BASE_URL="${LPAC_RELEASE_BASE_URL:-https://github.com/${LPAC_REPO}/releases/latest/download}"
LPAC_LATEST_RELEASE_URL="${LPAC_LATEST_RELEASE_URL:-https://github.com/${LPAC_REPO}/releases/latest}"
LPAC_COMPAT_RELEASE_BASE_URL="${LPAC_COMPAT_RELEASE_BASE_URL:-https://github.com/3899/SimAdmin/releases/download/lpac}"
LPAC_COMPAT_MANIFEST_NAME="${LPAC_COMPAT_MANIFEST_NAME:-lpac.json}"
LPAC_TARGET_ARCH="${LPAC_TARGET_ARCH:-}"
LPAC_TARGET_VERSION="${LPAC_TARGET_VERSION:-}"
LPAC_LATEST_RELEASE_API_URL="${LPAC_LATEST_RELEASE_API_URL:-https://api.github.com/repos/${LPAC_REPO}/releases/latest}"
LPAC_ASSET_FLAVOR="${LPAC_ASSET_FLAVOR:-default}"
LPAC_ASSET_NAME="${LPAC_ASSET_NAME:-}"
LPAC_ASSET_URL="${LPAC_ASSET_URL:-}"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "error: please run as root" >&2
    exit 1
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1" >&2
    exit 1
  fi
}

prepend_cargo_path() {
  if [ -n "${HOME:-}" ] && [ -d "${HOME}/.cargo/bin" ]; then
    PATH="${HOME}/.cargo/bin:${PATH}"
    export PATH
  fi

  if [ -f "${HOME:-}/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "${HOME}/.cargo/env"
  fi
}

truthy() {
  case "$1" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

apt_install_packages() {
  packages="$1"
  if [ -z "$packages" ]; then
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "warning: apt-get not found, cannot install missing packages: $packages" >&2
    return 0
  fi

  echo "==> installing runtime dependencies:$packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  # shellcheck disable=SC2086
  apt-get install -y $packages
}

append_package() {
  package_list="$1"
  package_name="$2"

  case " $package_list " in
    *" $package_name "*)
      printf '%s\n' "$package_list"
      ;;
    *)
      printf '%s %s\n' "$package_list" "$package_name"
      ;;
  esac
}

append_package_if_missing_cmd() {
  package_list="$1"
  command_name="$2"
  package_name="$3"

  if command -v "$command_name" >/dev/null 2>&1; then
    printf '%s\n' "$package_list"
  else
    append_package "$package_list" "$package_name"
  fi
}

append_package_if_missing_dpkg() {
  package_list="$1"
  package_name="$2"

  if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed"; then
    printf '%s\n' "$package_list"
  else
    append_package "$package_list" "$package_name"
  fi
}

systemd_unit_exists() {
  systemctl list-unit-files "$1" >/dev/null 2>&1
}

enable_systemd_unit_if_present() {
  unit_name="$1"

  if ! systemd_unit_exists "$unit_name"; then
    return 0
  fi

  systemctl enable "$unit_name" >/dev/null 2>&1 || true
  systemctl start "$unit_name" >/dev/null 2>&1 || true
}

ensure_runtime_deps() {
  if ! truthy "$SIMADMIN_INSTALL_RUNTIME_DEPS"; then
    echo "==> skipping runtime dependency install (SIMADMIN_INSTALL_RUNTIME_DEPS=${SIMADMIN_INSTALL_RUNTIME_DEPS})"
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "warning: apt-get not found, skipping automatic runtime dependency install" >&2
    return 0
  fi

  packages=""
  packages="$(append_package_if_missing_dpkg "$packages" ca-certificates)"
  packages="$(append_package_if_missing_dpkg "$packages" dbus)"
  packages="$(append_package_if_missing_cmd "$packages" curl curl)"
  packages="$(append_package_if_missing_cmd "$packages" tar tar)"
  packages="$(append_package_if_missing_cmd "$packages" unzip unzip)"
  packages="$(append_package_if_missing_cmd "$packages" python3 python3)"
  packages="$(append_package_if_missing_cmd "$packages" ip iproute2)"
  packages="$(append_package_if_missing_cmd "$packages" iptables iptables)"
  packages="$(append_package_if_missing_cmd "$packages" ip6tables iptables)"
  packages="$(append_package_if_missing_cmd "$packages" modprobe kmod)"
  packages="$(append_package_if_missing_cmd "$packages" killall psmisc)"
  packages="$(append_package_if_missing_cmd "$packages" udevadm udev)"
  packages="$(append_package_if_missing_cmd "$packages" mmcli modemmanager)"
  packages="$(append_package_if_missing_cmd "$packages" qmicli libqmi-utils)"
  packages="$(append_package_if_missing_cmd "$packages" mbimcli libmbim-utils)"
  packages="$(append_package_if_missing_cmd "$packages" nmcli network-manager)"
  packages="$(append_package_if_missing_dpkg "$packages" libcurl4)"
  packages="$(append_package_if_missing_dpkg "$packages" libpcsclite1)"
  packages="$(append_package_if_missing_cmd "$packages" pcscd pcscd)"

  apt_install_packages "$packages"

  enable_systemd_unit_if_present dbus.service
  enable_systemd_unit_if_present ModemManager.service
  enable_systemd_unit_if_present NetworkManager.service
  enable_systemd_unit_if_present pcscd.socket
  enable_systemd_unit_if_present pcscd.service
}

download_with_proxies() {
  src_url="$1"
  dst_path="$2"

  case "$src_url" in
    https://github.com/*|https://raw.githubusercontent.com/*|https://objects.githubusercontent.com/*|https://api.github.com/*)
      for proxy in $GH_PROXY $GH_PROXY_FALLBACKS ""; do
        url="${proxy}${src_url}"
        echo "    ${url}"
        if curl -fsSL "$url" -o "$dst_path"; then
          return 0
        fi
        echo "    download failed, trying next mirror" >&2
      done
      ;;
    *)
      echo "    ${src_url}"
      curl -fsSL "$src_url" -o "$dst_path"
      return $?
      ;;
  esac

  return 1
}

read_with_proxies() {
  src_url="$1"

  case "$src_url" in
    https://github.com/*|https://raw.githubusercontent.com/*|https://objects.githubusercontent.com/*|https://api.github.com/*)
      for proxy in $GH_PROXY $GH_PROXY_FALLBACKS ""; do
        url="${proxy}${src_url}"
        echo "    ${url}" >&2
        if curl -fsSL "$url"; then
          return 0
        fi
        echo "    download failed, trying next mirror" >&2
      done
      ;;
    *)
      echo "    ${src_url}" >&2
      curl -fsSL "$src_url"
      return $?
      ;;
  esac

  return 1
}

version_to_tag() {
  case "$1" in
    v*) printf '%s\n' "$1" ;;
    *) printf 'v%s\n' "$1" ;;
  esac
}

asset_url_from_tag() {
  tag="$1"
  version="${2:-${tag#v}}"
  asset_name="${ASSET_NAME:-$(asset_name_for_version "$version")}"
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$REPO" "$tag" "$asset_name"
}

asset_name_for_version() {
  version="$1"
  version="${version#v}"
  version="${version#V}"
  printf 'simadmin_%s_%s.tar.gz\n' "$version" "$BUILD_TARGET"
}

repo_version() {
  version_text="$(read_with_proxies "${RAW_BASE}/main/VERSION" | tr -d '[:space:]')"
  if [ -z "$version_text" ]; then
    return 1
  fi
  printf '%s\n' "$version_text"
}

resolve_asset_url() {
  if [ -n "$ASSET_URL" ]; then
    printf '%s\n' "$ASSET_URL"
    return 0
  fi

  if [ "$VERSION" = "latest" ]; then
    if [ -n "$ASSET_NAME" ]; then
      asset_name="$ASSET_NAME"
    elif version_text="$(repo_version)"; then
      asset_name="$(asset_name_for_version "$version_text")"
    else
      asset_name="simadmin.tar.gz"
    fi
    printf 'https://github.com/%s/releases/latest/download/%s\n' "$REPO" "$asset_name"
  else
    asset_url_from_tag "$(version_to_tag "$VERSION")" "$VERSION"
  fi
}

fallback_asset_url() {
  if [ "$VERSION" = "latest" ] && [ -z "$ASSET_URL" ]; then
    if version_text="$(repo_version)"; then
      asset_url_from_tag "$(version_to_tag "$version_text")" "$version_text"
      return 0
    fi
  fi

  return 1
}

download_release_asset() {
  archive_path="$1"
  primary_url="$2"
  fallback_url=""

  echo "==> downloading release asset"
  if download_with_proxies "$primary_url" "$archive_path"; then
    return 0
  fi

  if fallback_url="$(fallback_asset_url)" && [ "$fallback_url" != "$primary_url" ]; then
    echo "==> latest asset alias download failed, trying versioned asset"
    if download_with_proxies "$fallback_url" "$archive_path"; then
      return 0
    fi
  fi

  echo "error: failed to download OTA asset" >&2
  echo "       tried: $primary_url" >&2
  if [ -n "$fallback_url" ]; then
    echo "       tried: $fallback_url" >&2
  fi
  exit 1
}

install_service_file() {
  service_dst="/etc/systemd/system/${SERVICE_NAME}.service"
  mkdir -p /etc/systemd/system

  if [ "$INSTALL_MODE" = "local" ]; then
    if [ ! -f "${SOURCE_DIR}/scripts/simadmin.service" ]; then
      echo "error: local service file not found: ${SOURCE_DIR}/scripts/simadmin.service" >&2
      exit 1
    fi
    install -m 0644 "${SOURCE_DIR}/scripts/simadmin.service" "$service_dst"
  else
    download_with_proxies "$SERVICE_URL" "$service_dst"
  fi

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service" >/dev/null
}

install_environment_file() {
  if [ -f "$SIMADMIN_ENV_FILE" ]; then
    return 0
  fi

  echo "==> installing environment file to ${SIMADMIN_ENV_FILE}"
  mkdir -p "$(dirname "$SIMADMIN_ENV_FILE")"
  cat > "$SIMADMIN_ENV_FILE" <<'EOF'
# Optional SimAdmin runtime overrides.
#
# lpac eSIM APDU backend examples:
#   QMI modem control port:
#     LPAC_APDU=qmi
#     LPAC_APDU_QMI_DEVICE=/dev/cdc-wdm0
#     LPAC_APDU_QMI_UIM_SLOT=1
#
#   AT modem port:
#     LPAC_APDU=at
#     LPAC_APDU_AT_DEVICE=/dev/ttyUSB2
#
#   PC/SC card reader:
#     LPAC_APDU=pcsc
#
# If unset, SimAdmin defaults to:
#   LPAC_APDU=qmi
#   LPAC_APDU_QMI_DEVICE=/dev/wwan0qmi0
#   LPAC_APDU_QMI_UIM_SLOT=1
#   LPAC_HTTP=curl
EOF
  chmod 0644 "$SIMADMIN_ENV_FILE"
}

install_modem_recovery_service() {
  script_dst="/usr/local/bin/simadmin-modem-recovery.sh"
  service_dst="/etc/systemd/system/simadmin-modem-recovery.service"

  mkdir -p /usr/local/bin /etc/systemd/system

  if [ "$INSTALL_MODE" = "local" ]; then
    if [ ! -f "${SOURCE_DIR}/scripts/simadmin-modem-recovery.sh" ]; then
      echo "error: local modem recovery script not found: ${SOURCE_DIR}/scripts/simadmin-modem-recovery.sh" >&2
      exit 1
    fi
    if [ ! -f "${SOURCE_DIR}/scripts/simadmin-modem-recovery.service" ]; then
      echo "error: local modem recovery service not found: ${SOURCE_DIR}/scripts/simadmin-modem-recovery.service" >&2
      exit 1
    fi
    install -m 0755 "${SOURCE_DIR}/scripts/simadmin-modem-recovery.sh" "$script_dst"
    install -m 0644 "${SOURCE_DIR}/scripts/simadmin-modem-recovery.service" "$service_dst"
  else
    download_with_proxies "$MODEM_RECOVERY_SCRIPT_URL" "$script_dst"
    chmod 0755 "$script_dst"
    download_with_proxies "$MODEM_RECOVERY_SERVICE_URL" "$service_dst"
  fi

  systemctl daemon-reload
  systemctl enable simadmin-modem-recovery.service >/dev/null
}

configure_networkmanager_modem_unmanaged() {
  if [ ! -d /etc/NetworkManager ]; then
    return 0
  fi

  echo "==> configuring NetworkManager to ignore wwan modem"
  mkdir -p /etc/NetworkManager/conf.d
  nm_conf="/etc/NetworkManager/conf.d/99-simadmin-unmanaged-modem.conf"
  {
    printf '%s\n' '[keyfile]'
    printf '%s\n' 'unmanaged-devices=interface-name:wwan*'
  } > "$nm_conf"

  if systemctl is-active --quiet NetworkManager.service; then
    systemctl restart NetworkManager.service || true
  fi
}

install_dji_baiwang_modem_rules() {
  if ! command -v udevadm >/dev/null 2>&1; then
    echo "warning: udevadm not found, skipping DJI/Baiwang modem udev rules" >&2
    return 0
  fi

  echo "==> installing DJI/Baiwang modem udev rules"
  mkdir -p /etc/udev/rules.d
  rules_path="/etc/udev/rules.d/78-simadmin-dji-baiwang-modem.rules"
  cat > "$rules_path" <<'EOF'
# DJI/Baiwang first generation 4G module, USB ID 2ca3:4006.
# It is EG25/EC25-like but does not use Quectel USB IDs, so bind option
# and tell ModemManager which AT ports are useful.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2ca3", ATTR{idProduct}=="4006", RUN+="/sbin/modprobe option", RUN+="/bin/sh -c 'echo 2ca3 4006 > /sys/bus/usb-serial/drivers/option1/new_id 2>/dev/null || true'"
ATTRS{idVendor}=="2ca3", ATTRS{idProduct}=="4006", ENV{ID_MM_DEVICE_PROCESS}="1"
ATTRS{idVendor}=="2ca3", ATTRS{idProduct}=="4006", ENV{ID_USB_INTERFACE_NUM}=="00", ENV{ID_MM_PORT_IGNORE}="1"
ATTRS{idVendor}=="2ca3", ATTRS{idProduct}=="4006", ENV{ID_USB_INTERFACE_NUM}=="01", ENV{ID_MM_PORT_IGNORE}="1"
ATTRS{idVendor}=="2ca3", ATTRS{idProduct}=="4006", ENV{ID_USB_INTERFACE_NUM}=="02", SUBSYSTEM=="tty", ENV{ID_MM_PORT_TYPE_AT_PRIMARY}="1"
ATTRS{idVendor}=="2ca3", ATTRS{idProduct}=="4006", ENV{ID_USB_INTERFACE_NUM}=="03", SUBSYSTEM=="tty", ENV{ID_MM_PORT_TYPE_AT_SECONDARY}="1"
ATTRS{idVendor}=="2ca3", ATTRS{idProduct}=="4006", ENV{ID_USB_INTERFACE_NUM}=="04", ENV{ID_MM_PORT_IGNORE}="1"
EOF

  udevadm control --reload-rules || true

  if command -v modprobe >/dev/null 2>&1; then
    modprobe option || true
  fi
  if [ -w /sys/bus/usb-serial/drivers/option1/new_id ]; then
    echo "2ca3 4006" > /sys/bus/usb-serial/drivers/option1/new_id 2>/dev/null || true
  fi

  udevadm trigger --subsystem-match=tty --action=change || true
  udevadm settle || true

  if systemctl is-active --quiet ModemManager.service; then
    systemctl restart ModemManager.service || true
  fi
}

install_ubuntu_build_deps() {
  if ! truthy "$SIMADMIN_INSTALL_BUILD_DEPS"; then
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "warning: apt-get not found, skipping automatic build dependency install" >&2
    return 0
  fi

  echo "==> installing Ubuntu build dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    bash \
    build-essential \
    ca-certificates \
    coreutils \
    curl \
    git \
    gnupg \
    make \
    pkg-config \
    python3 \
    tar \
    unzip \
    xz-utils
}

node_major_version() {
  if ! command -v node >/dev/null 2>&1; then
    return 1
  fi

  node -v 2>/dev/null | sed -nE 's/^v([0-9]+).*/\1/p' | head -n 1
}

install_nodesource_node() {
  require_cmd curl
  require_cmd bash

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "error: node >= 20 is required, and automatic Node.js install needs apt-get" >&2
    exit 1
  fi

  echo "==> installing Node.js ${SIMADMIN_NODE_MAJOR}.x"
  nodesource_setup="${tmp_dir}/nodesource_setup.sh"
  curl -fsSL "https://deb.nodesource.com/setup_${SIMADMIN_NODE_MAJOR}.x" -o "$nodesource_setup"
  bash "$nodesource_setup"
  apt-get install -y nodejs
}

ensure_node_toolchain() {
  node_major="$(node_major_version || true)"
  if [ -z "$node_major" ] || [ "$node_major" -lt 20 ]; then
    install_nodesource_node
  fi

  if command -v corepack >/dev/null 2>&1; then
    if corepack enable && corepack prepare "pnpm@${SIMADMIN_PNPM_VERSION}" --activate; then
      :
    else
      echo "warning: corepack failed, falling back to npm global pnpm install" >&2
    fi
  fi

  if ! command -v pnpm >/dev/null 2>&1; then
    require_cmd npm
    npm install -g "pnpm@${SIMADMIN_PNPM_VERSION}"
  fi
}

ensure_rust_toolchain() {
  prepend_cargo_path

  if ! command -v cargo >/dev/null 2>&1; then
    require_cmd curl
    echo "==> installing Rust toolchain"
    rustup_script="${tmp_dir}/rustup-init.sh"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$rustup_script"
    sh "$rustup_script" -y --profile minimal
    prepend_cargo_path
  fi

  require_cmd cargo
  if command -v rustup >/dev/null 2>&1; then
    rustup target add "$BUILD_TARGET"
  fi
}

local_source_version() {
  if [ -f "${SOURCE_DIR}/VERSION" ]; then
    tr -d '[:space:]' < "${SOURCE_DIR}/VERSION"
  else
    printf '%s\n' "1.1.5"
  fi
}

local_make_package_target() {
  case "$BUILD_TARGET" in
    x86_64-unknown-linux-gnu)
      printf '%s\n' "package-x86"
      ;;
    x86_64-unknown-linux-musl)
      printf '%s\n' "package-x86-musl"
      ;;
    *)
      echo "error: unsupported local BUILD_TARGET: $BUILD_TARGET" >&2
      echo "       supported: x86_64-unknown-linux-gnu, x86_64-unknown-linux-musl" >&2
      exit 1
      ;;
  esac
}

local_package_path() {
  printf '%s/release/simadmin_%s_%s.tar.gz\n' \
    "$SOURCE_DIR" \
    "$(local_source_version)" \
    "$BUILD_TARGET"
}

build_local_release_asset() {
  archive_path="$1"

  if [ ! -f "${SOURCE_DIR}/Makefile" ]; then
    echo "error: local Makefile not found: ${SOURCE_DIR}/Makefile" >&2
    exit 1
  fi
  if [ ! -f "${SOURCE_DIR}/backend/Cargo.toml" ]; then
    echo "error: local backend source not found: ${SOURCE_DIR}/backend/Cargo.toml" >&2
    exit 1
  fi
  if [ ! -f "${SOURCE_DIR}/frontend/package.json" ]; then
    echo "error: local frontend source not found: ${SOURCE_DIR}/frontend/package.json" >&2
    exit 1
  fi

  case "$(uname -m)" in
    x86_64|amd64)
      ;;
    *)
      echo "warning: current machine is $(uname -m), but BUILD_TARGET=${BUILD_TARGET}" >&2
      ;;
  esac

  install_ubuntu_build_deps
  ensure_node_toolchain
  ensure_rust_toolchain

  make_target="$(local_make_package_target)"

  echo "==> building local SimAdmin source (${BUILD_TARGET})"
  (
    cd "$SOURCE_DIR"
    if truthy "$SIMADMIN_FORCE_FRONTEND_INSTALL"; then
      make frontend-install
    fi
    make "$make_target"
  )

  package_path="$(local_package_path)"
  if [ ! -f "$package_path" ]; then
    echo "error: local build did not create package: $package_path" >&2
    exit 1
  fi

  cp "$package_path" "$archive_path"
}

normalize_lpac_arch() {
  case "$1" in
    aarch64|arm64)
      printf '%s\n' "aarch64"
      ;;
    x86_64|amd64)
      printf '%s\n' "x86_64"
      ;;
    *)
      return 1
      ;;
  esac
}

detect_lpac_arch() {
  if [ -n "$LPAC_TARGET_ARCH" ]; then
    normalize_lpac_arch "$LPAC_TARGET_ARCH"
    return $?
  fi

  normalize_lpac_arch "$(uname -m)"
}

detect_glibc_version() {
  if command -v getconf >/dev/null 2>&1; then
    version="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
    if [ -n "$version" ]; then
      printf '%s\n' "$version"
      return 0
    fi
  fi

  if command -v ldd >/dev/null 2>&1; then
    version="$(ldd --version 2>/dev/null | head -n 1 | sed -E 's/.* ([0-9]+\.[0-9]+).*/\1/' || true)"
    if [ -n "$version" ]; then
      printf '%s\n' "$version"
      return 0
    fi
  fi

  printf '%s\n' ""
}

version_le() {
  [ "$1" = "$2" ] && return 0
  [ -n "$1" ] || return 0
  [ -n "$2" ] || return 1
  first="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)"
  [ "$first" = "$1" ]
}

normalize_version_value() {
  value="$1"
  value="${value#refs/tags/}"
  value="${value#tags/}"
  value="${value#v}"
  value="${value#V}"
  printf '%s\n' "$value"
}

version_lt() {
  left="$(normalize_version_value "$1")"
  right="$(normalize_version_value "$2")"
  [ -n "$left" ] || return 0
  [ -n "$right" ] || return 1
  [ "$left" = "$right" ] && return 1
  version_le "$left" "$right"
}

version_token_from_text() {
  printf '%s\n' "$1" \
    | tr '",:{}[]()' '          ' \
    | tr '[:space:]' '\n' \
    | sed -nE '/^[vV]?[0-9]+(\.[0-9]+)+([-+][0-9A-Za-z._-]+)?$/p' \
    | head -n 1
}

json_string_field() {
  field="$1"
  sed -nE 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1
}

resolve_lpac_asset_name() {
  arch="$1"

  if [ -n "$LPAC_ASSET_NAME" ]; then
    printf '%s\n' "$LPAC_ASSET_NAME"
    return 0
  fi

  case "$LPAC_ASSET_FLAVOR" in
    compat)
      glibc_version="$(detect_glibc_version)"
      if [ "$arch" = "aarch64" ] && version_le "2.31" "$glibc_version"; then
        printf 'lpac-linux-aarch64-glibc2.31.zip\n'
      else
        printf 'lpac-linux-%s.zip\n' "$arch"
      fi
      ;;
    ""|default)
      printf 'lpac-linux-%s.zip\n' "$arch"
      ;;
    with-qmi)
      printf 'lpac-linux-%s-with-qmi.zip\n' "$arch"
      ;;
    without-lto)
      printf 'lpac-linux-%s-without-lto.zip\n' "$arch"
      ;;
    *)
      echo "warning: unsupported LPAC_ASSET_FLAVOR=${LPAC_ASSET_FLAVOR}, skipping lpac install" >&2
      return 1
      ;;
  esac
}

resolve_lpac_asset_url() {
  if [ -n "$LPAC_ASSET_URL" ]; then
    printf '%s\n' "$LPAC_ASSET_URL"
    return 0
  fi

  arch="$(detect_lpac_arch)" || return 1
  asset_name="$(resolve_lpac_asset_name "$arch")" || return 1
  if [ "$LPAC_ASSET_FLAVOR" = "compat" ] && [ "$asset_name" = "lpac-linux-aarch64-glibc2.31.zip" ]; then
    printf '%s/%s\n' "$LPAC_COMPAT_RELEASE_BASE_URL" "$asset_name"
    return 0
  fi
  printf '%s/%s\n' "$LPAC_RELEASE_BASE_URL" "$asset_name"
}

extract_lpac_archive() {
  archive="$1"
  target="$2"

  mkdir -p "$target"
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$archive" -d "$target"
    return $?
  fi

  if command -v busybox >/dev/null 2>&1; then
    busybox unzip -oq "$archive" -d "$target"
    return $?
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$archive" "$target" <<'PY'
import sys
from zipfile import ZipFile

archive, target = sys.argv[1], sys.argv[2]
ZipFile(archive).extractall(target)
PY
    return $?
  fi

  # Use simadmin's built-in zip extractor if external tools are unavailable.
  if [ -x "${INSTALL_DIR}/simadmin" ]; then
    echo "    using simadmin extract-zip (built-in)"
    "${INSTALL_DIR}/simadmin" extract-zip "$archive" "$target"
    return $?
  fi

  echo "warning: no zip extractor available, skipping lpac install" >&2
  return 1
}

copy_lpac_tree() {
  extract_dir="$1"
  lpac_dst="$2"
  asset_url="$3"

  if [ -f "${extract_dir}/lpac" ]; then
    bundle_root="${extract_dir}"
  elif [ -f "${extract_dir}/executables/lpac" ]; then
    bundle_root="${extract_dir}/executables"
  else
    bundle_root="$(find "$extract_dir" -type f -name lpac -exec dirname {} \; | head -n 1 || true)"
  fi

  if [ -z "$bundle_root" ] || [ ! -f "${bundle_root}/lpac" ]; then
    echo "warning: downloaded lpac asset does not contain lpac executable" >&2
    return 1
  fi

  rm -rf "${lpac_dst}"
  mkdir -p "${lpac_dst}"
  cp -R "${bundle_root}/." "${lpac_dst}/"

  if [ -d "${extract_dir}/lib" ] && [ ! -d "${lpac_dst}/lib" ]; then
    mkdir -p "${lpac_dst}/lib"
    cp -R "${extract_dir}/lib/." "${lpac_dst}/lib/"
  fi

  if [ -d "${extract_dir}/libraries" ] && [ ! -d "${lpac_dst}/lib" ]; then
    mkdir -p "${lpac_dst}/lib"
    cp -R "${extract_dir}/libraries/." "${lpac_dst}/lib/"
  fi

  chmod -R a+rX "${lpac_dst}"
  chmod 0755 "${lpac_dst}/lpac"

  cat > "${lpac_dst}/SOURCE.txt" <<EOF
lpac is installed from:
${asset_url}

Project:
https://github.com/estkme-group/lpac
EOF
}

lpac_env_prefix() {
  lpac_path="$1"
  lpac_home="$(dirname "$lpac_path")"
  printf '%s\n' "${lpac_home}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
}

lpac_binary_path_usable() {
  lpac_path="$1"
  if [ ! -x "$lpac_path" ]; then
    return 1
  fi

  output=$(LD_LIBRARY_PATH="$(lpac_env_prefix "$lpac_path")" "$lpac_path" 2>&1 || true)
  case "$output" in
    *GLIBC_*|*No\ such\ file\ or\ directory*)
      return 1
      ;;
  esac

  return 0
}

lpac_binary_usable() {
  lpac_home="$1"
  lpac_binary_path_usable "${lpac_home}/lpac"
}

lpac_command_version() {
  lpac_path="$1"
  [ -x "$lpac_path" ] || return 1

  for arg in version --version -v; do
    output="$(LD_LIBRARY_PATH="$(lpac_env_prefix "$lpac_path")" "$lpac_path" "$arg" 2>&1 || true)"
    version="$(version_token_from_text "$output")"
    if [ -n "$version" ]; then
      printf '%s\n' "$version"
      return 0
    fi
  done

  return 1
}

lpac_installed_version() {
  lpac_path="$1"
  lpac_home="$(dirname "$lpac_path")"

  if [ -f "${lpac_home}/VERSION.txt" ]; then
    version="$(version_token_from_text "$(cat "${lpac_home}/VERSION.txt")")"
    if [ -n "$version" ]; then
      printf '%s\n' "$version"
      return 0
    fi
  fi

  if version="$(lpac_command_version "$lpac_path")"; then
    printf '%s\n' "$version"
    return 0
  fi

  if [ -f "${lpac_home}/SOURCE.txt" ]; then
    version="$(version_token_from_text "$(cat "${lpac_home}/SOURCE.txt")")"
    if [ -n "$version" ]; then
      printf '%s\n' "$version"
      return 0
    fi
  fi

  return 1
}

lpac_release_version_from_url() {
  url="$1"
  tag="$(printf '%s\n' "$url" | sed -nE 's#^.*/releases/download/([^/]+)/.*#\1#p' | head -n 1)"
  case "$tag" in
    ""|latest)
      return 1
      ;;
  esac

  version="$(version_token_from_text "$tag")"
  [ -n "$version" ] || return 1
  printf '%s\n' "$version"
}

lpac_asset_name_from_url() {
  url="$1"
  asset_name="${url%%\?*}"
  asset_name="${asset_name##*/}"
  printf '%s\n' "$asset_name"
}

lpac_url_source() {
  url="$1"
  case "$url" in
    "$LPAC_COMPAT_RELEASE_BASE_URL"/*|https://github.com/3899/SimAdmin/releases/download/lpac/*)
      printf '%s\n' "compat"
      ;;
    "$LPAC_RELEASE_BASE_URL"/*|https://github.com/"$LPAC_REPO"/releases/latest/download/*|https://github.com/"$LPAC_REPO"/releases/download/*)
      printf '%s\n' "official"
      ;;
    *)
      printf '%s\n' "custom"
      ;;
  esac
}

compat_lpac_release_version() {
  lpac_url="$1"
  manifest_url="${LPAC_COMPAT_RELEASE_BASE_URL}/${LPAC_COMPAT_MANIFEST_NAME}"
  manifest="$(read_with_proxies "$manifest_url" 2>/dev/null || true)"
  [ -n "$manifest" ] || return 1

  asset_name="$(lpac_asset_name_from_url "$lpac_url")"
  if [ -n "$asset_name" ]; then
    asset_record="$(printf '%s\n' "$manifest" \
      | tr '\n' ' ' \
      | sed 's/}[[:space:]]*,[[:space:]]*{/}\
{/g' \
      | grep "\"name\"[[:space:]]*:[[:space:]]*\"${asset_name}\"" \
      | head -n 1 || true)"
    version="$(printf '%s\n' "$asset_record" | json_string_field version)"
    version="$(version_token_from_text "$version")"
    if [ -n "$version" ]; then
      printf '%s\n' "$version"
      return 0
    fi
  fi

  version="$(printf '%s\n' "$manifest" | json_string_field version)"
  version="$(version_token_from_text "$version")"
  [ -n "$version" ] || return 1
  printf '%s\n' "$version"
}

official_lpac_release_version() {
  lpac_url="$1"

  version="$(lpac_release_version_from_url "$lpac_url" || true)"
  if [ -n "$version" ]; then
    printf '%s\n' "$version"
    return 0
  fi

  json="$(read_with_proxies "$LPAC_LATEST_RELEASE_API_URL" 2>/dev/null || true)"
  tag="$(printf '%s\n' "$json" | json_string_field tag_name)"
  version="$(version_token_from_text "$tag")"
  if [ -n "$version" ]; then
    printf '%s\n' "$version"
    return 0
  fi

  html="$(read_with_proxies "$LPAC_LATEST_RELEASE_URL" 2>/dev/null || true)"
  tag="$(printf '%s\n' "$html" \
    | sed -nE 's#.*releases/(tag|expanded_assets)/([vV]?[0-9]+(\.[0-9]+)+[^"<>/?[:space:]]*).*#\2#p' \
    | head -n 1)"
  version="$(version_token_from_text "$tag")"
  if [ -n "$version" ]; then
    printf '%s\n' "$version"
    return 0
  fi

  return 1
}

resolve_lpac_target_version() {
  lpac_url="$1"

  if [ -n "$LPAC_TARGET_VERSION" ]; then
    version="$(version_token_from_text "$LPAC_TARGET_VERSION")"
    [ -n "$version" ] || return 1
    LPAC_TARGET_RELEASE_SOURCE="override"
    printf '%s\n' "$version"
    return 0
  fi

  LPAC_TARGET_RELEASE_SOURCE="$(lpac_url_source "$lpac_url")"
  case "$LPAC_TARGET_RELEASE_SOURCE" in
    compat)
      compat_lpac_release_version "$lpac_url"
      ;;
    official)
      official_lpac_release_version "$lpac_url"
      ;;
    *)
      for candidate in "$lpac_url" "$LPAC_ASSET_URL" "$LPAC_RELEASE_BASE_URL"; do
        version="$(lpac_release_version_from_url "$candidate" || true)"
        if [ -n "$version" ]; then
          printf '%s\n' "$version"
          return 0
        fi
      done

      LPAC_TARGET_RELEASE_SOURCE="official"
      official_lpac_release_version "$LPAC_RELEASE_BASE_URL"
      ;;
  esac
}

find_current_lpac_path() {
  private_path="${INSTALL_DIR}/lpac/lpac"
  if [ -e "$private_path" ] || [ -d "${INSTALL_DIR}/lpac" ]; then
    printf '%s\n' "$private_path"
    return 0
  fi

  if command_path="$(command -v lpac 2>/dev/null)"; then
    printf '%s\n' "$command_path"
    return 0
  fi

  return 1
}

write_lpac_version_file() {
  lpac_home="$1"
  version="$2"
  [ -n "$version" ] || return 0
  printf '%s\n' "$version" > "${lpac_home}/VERSION.txt"
  chmod 0644 "${lpac_home}/VERSION.txt" || true
}

lpac_install_needed() {
  lpac_path="$1"
  lpac_url="$2"
  LPAC_INSTALL_REASON=""
  LPAC_TARGET_RELEASE_VERSION=""
  LPAC_TARGET_RELEASE_SOURCE=""

  if [ -z "$lpac_path" ] || [ ! -x "$lpac_path" ]; then
    LPAC_INSTALL_REASON="not installed"
    return 0
  fi

  if ! lpac_binary_path_usable "$lpac_path"; then
    LPAC_INSTALL_REASON="installed lpac is not usable"
    return 0
  fi

  current_version="$(lpac_installed_version "$lpac_path" || true)"
  if [ -z "$current_version" ]; then
    LPAC_INSTALL_REASON="installed version is unknown"
    return 0
  fi

  LPAC_TARGET_RELEASE_VERSION="$(resolve_lpac_target_version "$lpac_url" || true)"
  if [ -z "$LPAC_TARGET_RELEASE_VERSION" ]; then
    LPAC_INSTALL_REASON="latest version could not be verified"
    return 0
  fi

  if version_lt "$current_version" "$LPAC_TARGET_RELEASE_VERSION"; then
    LPAC_INSTALL_REASON="installed ${current_version}, ${LPAC_TARGET_RELEASE_SOURCE:-target} ${LPAC_TARGET_RELEASE_VERSION}"
    return 0
  fi

  echo "==> skipping lpac install (installed ${current_version}, ${LPAC_TARGET_RELEASE_SOURCE:-target} ${LPAC_TARGET_RELEASE_VERSION})"
  return 1
}

install_lpac() {
  lpac_dst="${INSTALL_DIR}/lpac"
  lpac_archive="${tmp_dir}/lpac.zip"
  lpac_extract="${tmp_dir}/lpac-extract"

  if ! truthy "$SIMADMIN_INSTALL_LPAC"; then
    echo "==> skipping lpac install (SIMADMIN_INSTALL_LPAC=${SIMADMIN_INSTALL_LPAC})"
    return 0
  fi

  lpac_arch="$(detect_lpac_arch || true)"
  if [ -z "$lpac_arch" ]; then
    echo "warning: unsupported device arch for lpac: $(uname -m), skipping lpac install" >&2
    return 0
  fi

  lpac_url="$(resolve_lpac_asset_url || true)"
  if [ -z "$lpac_url" ]; then
    echo "warning: failed to resolve lpac asset, skipping lpac install" >&2
    return 0
  fi

  current_lpac_path="$(find_current_lpac_path || true)"
  if ! lpac_install_needed "$current_lpac_path" "$lpac_url"; then
    return 0
  fi

  if [ -z "$LPAC_TARGET_RELEASE_VERSION" ]; then
    LPAC_TARGET_RELEASE_VERSION="$(resolve_lpac_target_version "$lpac_url" || true)"
  fi

  echo "==> installing lpac for ${lpac_arch} (${LPAC_INSTALL_REASON})"
  if ! download_with_proxies "$lpac_url" "$lpac_archive"; then
    echo "warning: failed to download lpac, keeping existing lpac if present" >&2
    return 0
  fi

  if ! extract_lpac_archive "$lpac_archive" "$lpac_extract"; then
    echo "warning: failed to extract lpac, keeping existing lpac if present" >&2
    return 0
  fi

  if copy_lpac_tree "$lpac_extract" "$lpac_dst" "$lpac_url"; then
    detected_version="$(lpac_command_version "${lpac_dst}/lpac" || true)"
    if [ -z "$detected_version" ]; then
      detected_version="$LPAC_TARGET_RELEASE_VERSION"
    fi
    write_lpac_version_file "$lpac_dst" "$detected_version"
    if lpac_binary_usable "$lpac_dst"; then
      if [ -n "$detected_version" ]; then
        echo "==> lpac ${detected_version} installed to ${lpac_dst}"
      else
        echo "==> lpac installed to ${lpac_dst}"
      fi
    else
      echo "warning: lpac was installed but may not be executable on this device; check glibc/architecture compatibility" >&2
    fi
  else
    echo "warning: failed to install lpac, keeping existing lpac if present" >&2
  fi
}



main() {
  require_root
  require_cmd systemctl
  require_cmd mktemp

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT INT TERM

  ensure_runtime_deps

  archive_path="${tmp_dir}/simadmin.tar.gz"

  case "$INSTALL_MODE" in
    local)
      require_cmd tar
      build_local_release_asset "$archive_path"
      ;;
    release)
      require_cmd curl
      asset_url="$(resolve_asset_url)"
      case "$asset_url" in
        *.tar.gz)
          require_cmd tar
          ;;
        *)
          echo "error: unsupported OTA asset format, expected .tar.gz: $asset_url" >&2
          exit 1
          ;;
      esac
      download_release_asset "$archive_path" "$asset_url"
      ;;
    *)
      echo "error: unsupported INSTALL_MODE: $INSTALL_MODE" >&2
      echo "       supported: local, release" >&2
      exit 1
      ;;
  esac

  echo "==> extracting package"
  mkdir -p "${tmp_dir}/pkg"
  tar -xzf "$archive_path" -C "${tmp_dir}/pkg"

  if [ ! -f "${tmp_dir}/pkg/simadmin" ]; then
    echo "error: invalid package, missing simadmin binary" >&2
    exit 1
  fi

  if [ ! -d "${tmp_dir}/pkg/www" ]; then
    echo "error: invalid package, missing frontend www directory" >&2
    exit 1
  fi

  echo "==> stopping existing service"
  systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true

  echo "==> installing files to ${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"
  install -m 0755 "${tmp_dir}/pkg/simadmin" "${INSTALL_DIR}/simadmin"
  rm -rf "${INSTALL_DIR}/www"
  cp -R "${tmp_dir}/pkg/www" "${INSTALL_DIR}/www"
  chmod -R a+rX "${INSTALL_DIR}/www"

  if [ -f "${tmp_dir}/pkg/meta.json" ]; then
    install -m 0644 "${tmp_dir}/pkg/meta.json" "${INSTALL_DIR}/meta.json"
  fi

  install_lpac

  echo "==> installing systemd unit"
  install_environment_file
  install_service_file
  echo "==> installing modem recovery service"
  install_modem_recovery_service

  configure_networkmanager_modem_unmanaged
  install_dji_baiwang_modem_rules

  echo "==> starting service"
  systemctl restart "${SERVICE_NAME}.service"

  echo "==> done"
  echo "    service: ${SERVICE_NAME}.service"
  echo "    modem recovery: simadmin-modem-recovery.service"
  echo "    install dir: ${INSTALL_DIR}"
  systemctl status "${SERVICE_NAME}.service" --no-pager
}

main "$@"
