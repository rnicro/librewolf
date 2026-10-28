#!/usr/bin/env bash
set -euo pipefail

template=${1:?template path required}
rust_template=${2:?Void Rust template path required}
wasi_template=${3:?Void WASI SDK template path required}
output=${GITHUB_OUTPUT:-}

for file in "$template" "$rust_template" "$wasi_template"; do
  [ -f "$file" ] || { echo "required template not found: $file" >&2; exit 1; }
done
bash -n "$template"

read_value() {
  sed -n "s/^$1=//p" "$2" | head -n 1
}

pkgname=$(read_value pkgname "$template")
version=$(read_value version "$template")
revision=$(read_value revision "$template")
source_revision=$(read_value _rev "$template")
checksum=$(read_value checksum "$template")
distfiles=$(sed -n 's/^distfiles="\([^"]*\)"/\1/p' "$template")
llvm_version=$(read_value _llvmver "$template")
wasi_llvm_version=$(read_value _wasi_llvmver "$template")
rust_llvm_version=$(read_value _llvmver "$rust_template")
wasi_sdk_llvm_version=$(sed -n 's/^_llvmversion="\([0-9][0-9]*\)\..*/\1/p' "$wasi_template")

[ "$pkgname" = librewolf ] || { echo "expected pkgname=librewolf" >&2; exit 1; }
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "invalid version: $version" >&2; exit 1; }
[[ "$revision" =~ ^[1-9][0-9]*$ ]] || { echo "invalid package revision: $revision" >&2; exit 1; }
[[ "$source_revision" =~ ^[0-9]+$ ]] || { echo "invalid source revision: $source_revision" >&2; exit 1; }
[[ "$checksum" =~ ^[[:xdigit:]]{64}$ ]] || { echo "checksum must be a 64-character SHA-256 digest" >&2; exit 1; }

expected_url='https://librewolf.dev/api/packages/librewolf/generic/librewolf-source/${version}-${_rev}/${pkgname}-${version}-${_rev}.source.tar.gz'
[ "$distfiles" = "$expected_url" ] || {
  echo "unexpected source URL template: $distfiles" >&2
  exit 1
}

[[ "$llvm_version" =~ ^[0-9]+$ && "$rust_llvm_version" =~ ^[0-9]+$ ]] || {
  echo "could not determine LibreWolf and Void Rust LLVM versions" >&2
  exit 1
}
[ "$llvm_version" = "$rust_llvm_version" ] || {
  echo "LLVM mismatch: LibreWolf uses $llvm_version, Void Rust uses $rust_llvm_version" >&2
  exit 1
}

[[ "$wasi_llvm_version" =~ ^[0-9]+$ && "$wasi_sdk_llvm_version" =~ ^[0-9]+$ ]] || {
  echo "could not determine LibreWolf and Void WASI SDK LLVM versions" >&2
  exit 1
}
[ "$wasi_llvm_version" = "$wasi_sdk_llvm_version" ] || {
  echo "WASI LLVM mismatch: LibreWolf expects $wasi_llvm_version, Void WASI SDK uses $wasi_sdk_llvm_version" >&2
  exit 1
}

# Keep the shipped browser sandbox enabled; CI-only PGO overrides are runtime environment variables.
if grep -Eq '^[[:space:]]*ac_add_options[[:space:]]+--disable-(content-)?sandbox([[:space:]]|$)' "$template"; then
  echo "the shipped browser must retain its normal sandbox configuration" >&2
  exit 1
fi

distfile="${pkgname}-${version}-${source_revision}.source.tar.gz"
release_tag="${version}-r${revision}"

if [ -n "$output" ]; then
  {
    echo "sha256=$checksum"
    echo "distfile=$distfile"
    echo "version=$version"
    echo "rev=$source_revision"
    echo "package_revision=$revision"
    echo "release_tag=$release_tag"
  } >> "$output"
fi

printf 'validated: %s %s-r%s (source revision %s)\n' "$pkgname" "$version" "$revision" "$source_revision"
