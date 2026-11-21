#!/usr/bin/env bash
set -euo pipefail

# Fetch Mozilla's unchanged host-side sources from an immutable Gecko commit.
# Keep the sources out of Git; verify each file before placing it in the build inputs.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
files_dir="$repo_root/srcpkgs/librewolf/files"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/librewolf-source-fallbacks.XXXXXX")"
trap 'rm -rf -- "$tmp_dir"' EXIT

fetch_verify_install() {
  local filename="$1"
  local url="$2"
  local expected_sha256="$3"
  local tmp="$tmp_dir/$filename"
  local destination="$files_dir/$filename"

  curl --fail --location --retry 5 --retry-all-errors \
    --connect-timeout 30 --max-time 300 \
    --output "$tmp" "$url"

  printf '%s  %s\n' "$expected_sha256" "$tmp" | sha256sum --check --status || {
    echo "Mozilla config/$filename failed SHA-256 verification." >&2
    exit 1
  }

  install -m 644 -- "$tmp" "$destination"
  echo "Prepared verified Mozilla config/$filename."
}

fetch_verify_install \
  nsinstall.c \
  "https://raw.githubusercontent.com/mozilla/gecko-dev/45030f6970cae629c797527ce66836dcad7804d4/config/nsinstall.c" \
  "f245dab3eeaa6f98d612eee01aa1fd2b6848e94186ab1d97c6b69e6811966611"

fetch_verify_install \
  pathsub.c \
  "https://raw.githubusercontent.com/mozilla/gecko-dev/45030f6970cae629c797527ce66836dcad7804d4/config/pathsub.c" \
  "a9a772f937ab63cbaf9c01fa62204e4e455aa414709bd047ccd00f1701f6b95a"
