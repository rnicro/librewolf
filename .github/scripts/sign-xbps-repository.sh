#!/usr/bin/env bash
set -euo pipefail

: "${PRIV_KEY:?configure the PRIV_KEY GitHub Actions secret}"
: "${SIGNEDBY:?configure the SIGNEDBY GitHub Actions variable}"
: "${XBPS_TARGET_ARCH:?XBPS_TARGET_ARCH must be set by the publish job}"

[ "$XBPS_TARGET_ARCH" = "x86_64-musl" ] || {
  echo "refusing to sign a repository for unexpected architecture: $XBPS_TARGET_ARCH" >&2
  exit 1
}
command -v xbps-rindex >/dev/null 2>&1 || {
  echo "xbps-rindex is unavailable; prepare xbps-static before signing" >&2
  exit 1
}

shopt -s nullglob
packages=(./librewolf-*.xbps)
[ "${#packages[@]}" -gt 0 ] || {
  echo "no LibreWolf XBPS packages found in ${PWD}" >&2
  exit 1
}
for package in "${packages[@]}"; do
  [ -s "$package" ] || {
    echo "package archive is empty: $package" >&2
    exit 1
  }
done

# Keep the RSA private key outside the artifact directory and delete it on every exit.
umask 077
key_tmp_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
key_file="$(mktemp "${key_tmp_dir%/}/xbps-repo-private.XXXXXX")"
trap 'rm -f -- "$key_file"' EXIT
printf '%s' "$PRIV_KEY" > "$key_file"
chmod 600 "$key_file"

# XBPS accepts the passphrase through its environment, not command-line arguments.
export XBPS_PASSPHRASE="${SIGN_PASS:-}"
unset PRIV_KEY SIGN_PASS
export XBPS_TARGET_ARCH

# Create the index, prune stale entries, then register signing metadata and signatures.
xbps-rindex -a "${packages[@]}"
xbps-rindex -c "$PWD"
xbps-rindex -s --signedby "$SIGNEDBY" --privkey "$key_file" "$PWD"
xbps-rindex -S --privkey "$key_file" "${packages[@]}"

repo_indexes=(./*-repodata)
package_signatures=(./*.xbps.sig2)
[ "${#repo_indexes[@]}" -eq 1 ] || {
  echo "expected exactly one repository index for $XBPS_TARGET_ARCH (found ${#repo_indexes[@]})" >&2
  exit 1
}
[ "${#package_signatures[@]}" -eq "${#packages[@]}" ] || {
  echo "package signature count does not match package count" >&2
  exit 1
}
for signature in "${package_signatures[@]}"; do
  [ -s "$signature" ] || {
    echo "package signature is empty: $signature" >&2
    exit 1
  }
done
[ -s "${repo_indexes[0]}" ] || {
  echo "XBPS repository index is empty: ${repo_indexes[0]}" >&2
  exit 1
}

repo_assets=("${packages[@]}" "${package_signatures[@]}" "${repo_indexes[@]}")
sha256sum "${repo_assets[@]}" > SHA256SUMS
sha256sum --check SHA256SUMS
echo "Signed and verified XBPS repository assets for $XBPS_TARGET_ARCH."
