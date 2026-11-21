#!/usr/bin/env bash
set -euo pipefail

# Fetch Mozilla's unchanged host nsinstall source from an immutable commit.
# Keep the source out of Git; verify it before placing it in the temporary build input tree.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
destination="$repo_root/srcpkgs/librewolf/files/nsinstall.c"
url="https://raw.githubusercontent.com/mozilla/gecko-dev/45030f6970cae629c797527ce66836dcad7804d4/config/nsinstall.c"
expected_sha256="f245dab3eeaa6f98d612eee01aa1fd2b6848e94186ab1d97c6b69e6811966611"

tmp="$(mktemp "${destination}.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT

curl --fail --location --retry 5 --retry-all-errors \
  --connect-timeout 30 --max-time 300 \
  --output "$tmp" "$url"

printf '%s  %s\n' "$expected_sha256" "$tmp" | sha256sum --check --status || {
  echo "Mozilla config/nsinstall.c failed SHA-256 verification." >&2
  exit 1
}

install -m 644 -- "$tmp" "$destination"
echo "Prepared verified Mozilla config/nsinstall.c."
