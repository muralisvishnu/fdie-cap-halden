#!/usr/bin/env bash
# Install terraform into .tools/bin/ without Homebrew (avoids outdated CLT blocker).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_BIN="${ROOT}/.tools/bin"
TF_VERSION="${TF_VERSION:-1.9.8}"
TF_BIN="${TOOLS_BIN}/terraform"

if command -v terraform >/dev/null 2>&1; then
  echo "$(command -v terraform)"
  exit 0
fi

if [[ -x "${TF_BIN}" ]]; then
  echo "${TF_BIN}"
  exit 0
fi

arch="$(uname -m)"
case "${arch}" in
  arm64)  TF_ARCH=arm64 ;;
  x86_64) TF_ARCH=amd64 ;;
  *)
    echo "[ensure-terraform] unsupported arch: ${arch}" >&2
    exit 1
    ;;
esac

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
zip="terraform_${TF_VERSION}_${os}_${TF_ARCH}.zip"
url="https://releases.hashicorp.com/terraform/${TF_VERSION}/${zip}"

log() { echo "[ensure-terraform] $*"; }

log "Downloading terraform ${TF_VERSION} (${os}/${TF_ARCH})"
mkdir -p "${TOOLS_BIN}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${url}" -o "${tmpdir}/${zip}"
unzip -q "${tmpdir}/${zip}" -d "${tmpdir}"
install -m 0755 "${tmpdir}/terraform" "${TF_BIN}"

log "Installed ${TF_BIN}"
echo "${TF_BIN}"
