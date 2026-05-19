#!/usr/bin/env bash
set -Eeuo pipefail

TOOLS_REPO="https://github.com/amnezia-vpn/amneziawg-tools.git"
KMOD_REPO="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git"

TOOLS_DIR="/usr/local/src/amneziawg-tools"
KMOD_DIR="/usr/local/src/amneziawg-linux-kernel-module"

KMOD_NAME="amneziawg"
KERNEL_VERSION="$(uname -r)"

log() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*" >&2; }
err() { echo -e "[ERROR] $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Run this script as root: sudo bash $0"
    exit 1
  fi
}

cleanup_on_error() {
  local exit_code=$?
  err "Installer failed with exit code ${exit_code}"
  err "Last known kernel: ${KERNEL_VERSION}"

  if command -v dkms >/dev/null 2>&1; then
    warn "DKMS status:"
    dkms status || true
  fi

  local dkms_log=""
  dkms_log="$(find "/var/lib/dkms/${KMOD_NAME}" -type f -name make.log 2>/dev/null | head -n 1 || true)"
  if [[ -n "${dkms_log}" && -f "${dkms_log}" ]]; then
    warn "Showing DKMS build log: ${dkms_log}"
    tail -n 100 "${dkms_log}" || true
  fi
}

trap cleanup_on_error ERR

install_packages() {
  log "Installing required packages"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y \
    git \
    build-essential \
    make \
    gcc \
    libc6-dev \
    pkg-config \
    dkms \
    libmnl-dev \
    libelf-dev \
    linux-headers-"${KERNEL_VERSION}"
}

clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"

  if [[ -d "${target_dir}/.git" ]]; then
    log "Updating repo ${target_dir}"
    git -C "${target_dir}" fetch --all --tags
    git -C "${target_dir}" reset --hard origin/master || \
    git -C "${target_dir}" reset --hard origin/main
  else
    log "Cloning ${repo_url} into ${target_dir}"
    rm -rf "${target_dir}"
    git clone "${repo_url}" "${target_dir}"
  fi
}

install_tools() {
  log "Installing amneziawg-tools"
  clone_or_update_repo "${TOOLS_REPO}" "${TOOLS_DIR}"

  cd "${TOOLS_DIR}/src"
  make
  make install

  log "Checking installed binaries"
  command -v awg >/dev/null 2>&1 || { err "awg binary not found"; exit 1; }
  command -v awg-quick >/dev/null 2>&1 || { err "awg-quick binary not found"; exit 1; }

  awg --version || true
}

detect_dkms_version() {
  local conf_file=""
  local version=""

  if [[ -f "${KMOD_DIR}/src/dkms.conf" ]]; then
    conf_file="${KMOD_DIR}/src/dkms.conf"
  elif [[ -f "${KMOD_DIR}/dkms.conf" ]]; then
    conf_file="${KMOD_DIR}/dkms.conf"
  else
    err "dkms.conf not found in kernel module repo"
    exit 1
  fi

  version="$(grep -E '^PACKAGE_VERSION=' "${conf_file}" | head -n1 | cut -d= -f2 | tr -d '"')"

  if [[ -z "${version}" ]]; then
    err "Could not detect PACKAGE_VERSION from ${conf_file}"
    exit 1
  fi

  echo "${version}"
}

install_kernel_module() {
  log "Installing amneziawg kernel module"
  clone_or_update_repo "${KMOD_REPO}" "${KMOD_DIR}"

  cd "${KMOD_DIR}/src"

  local dkms_version
  dkms_version="$(detect_dkms_version)"
  local dkms_src_dir="/usr/src/${KMOD_NAME}-${dkms_version}"

  log "Detected DKMS version: ${dkms_version}"

  rm -rf "${dkms_src_dir}"
  dkms remove -m "${KMOD_NAME}" -v "${dkms_version}" --all >/dev/null 2>&1 || true

  mkdir -p "${dkms_src_dir}"
  cp -a . "${dkms_src_dir}/tmp-copy"
  cp -a "${dkms_src_dir}/tmp-copy"/. "${dkms_src_dir}/"
  rm -rf "${dkms_src_dir}/tmp-copy"

  # Optional: if you have full kernel sources, link them here.
  # ln -s /usr/src/linux-source-full "${dkms_src_dir}/kernel"

  dkms add -m "${KMOD_NAME}" -v "${dkms_version}"
  dkms build -m "${KMOD_NAME}" -v "${dkms_version}" -k "${KERNEL_VERSION}"
  dkms install -m "${KMOD_NAME}" -v "${dkms_version}" -k "${KERNEL_VERSION}"

  depmod -a
  modprobe "${KMOD_NAME}"
}

verify_install() {
  log "Verifying installation"

  command -v awg >/dev/null 2>&1 || { err "awg is not installed"; exit 1; }
  command -v awg-quick >/dev/null 2>&1 || { err "awg-quick is not installed"; exit 1; }

  if ! lsmod | grep -q "^${KMOD_NAME}\b"; then
    err "Kernel module ${KMOD_NAME} is not loaded"
    exit 1
  fi

  local module_path
  module_path="$(find "/lib/modules/${KERNEL_VERSION}" -type f | grep "/${KMOD_NAME}\." | head -n1 || true)"

  if [[ -z "${module_path}" ]]; then
    err "Installed module file not found under /lib/modules/${KERNEL_VERSION}"
    exit 1
  fi

  log "Success"
  echo "awg binary:       $(command -v awg)"
  echo "awg-quick binary: $(command -v awg-quick)"
  echo "module path:      ${module_path}"
  echo "DKMS status:"
  dkms status || true
}

main() {
  require_root
  install_packages
  install_tools
  install_kernel_module
  verify_install
}

main "$@"
