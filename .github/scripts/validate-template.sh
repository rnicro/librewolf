#!/usr/bin/env bash
set -euo pipefail

template=${1:?template path required}
: "${GITHUB_OUTPUT:=}"

bash -n "$template"
pkgname=$(sed -n 's/^pkgname=//p' "$template")
version=$(sed -n 's/^version=//p' "$template")
revision=$(sed -n 's/^revision=//p' "$template")
_rev=$(sed -n 's/^_rev=//p' "$template")
checksum=$(sed -n 's/^checksum=//p' "$template")
distfiles=$(sed -n 's/^distfiles="//p' "$template" | sed 's/"$//')

: "${pkgname:?}" "${version:?}" "${revision:?}" "${_rev:?}" "${checksum:?}" "${distfiles:?}"

[ "$pkgname" = "librewolf" ] || {
  echo "workflow is only valid for pkgname=librewolf" >&2
  exit 1
}

[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
  echo "invalid LibreWolf version: $version" >&2
  exit 1
}

[[ "$revision" =~ ^[1-9][0-9]*$ ]] || {
  echo "revision must be a positive integer: $revision" >&2
  exit 1
}

[[ "$_rev" =~ ^[0-9]+$ ]] || {
  echo "_rev must be a non-negative integer: $_rev" >&2
  exit 1
}

printf '%s\n' "$checksum" | grep -Eq '^[0-9A-Fa-f]{64}$' || {
  echo "template checksum must be exactly one 64-character SHA-256 digest" >&2
  exit 1
}

llvmver=$(sed -n 's/^_llvmver=\([0-9][0-9]*\)$/\1/p' "$template")
[[ "$llvmver" =~ ^[0-9]+$ ]] || {
  echo "template must pin an explicit LLVM major version" >&2
  exit 1
}
grep -Fq 'llvm${_llvmver} clang${_llvmver} clang${_llvmver}-devel lld${_llvmver}' "$template" || {
  echo "Clang, LLD, and LLVM must use the same pinned toolchain major" >&2
  exit 1
}
grep -Fq 'clang${_llvmver}-devel' "$template" || {
  echo "Clang's development package is required for the unversioned libclang.so used by bindgen" >&2
  exit 1
}
wasi_llvmver=$(sed -n 's/^_wasi_llvmver=\([0-9][0-9]*\)$/\1/p' "$template")
[[ "$wasi_llvmver" =~ ^[0-9]+$ ]] || {
  echo "template must pin the LLVM version used by Void's WASI runtime" >&2
  exit 1
}
grep -Fq 'prepare_wasi_builtins()' "$template" || {
  echo "template must bridge Void's per-target WASI compiler-rt layout to Clang's target directories" >&2
  exit 1
}
grep -Fq 'local -a wasi_runtime_roots=(' "$template" || {
  echo "template must support current and legacy WASI compiler-rt install layouts" >&2
  exit 1
}
grep -Fq 'find "$runtime_root" -type f' "$template" || {
  echo "template must discover the installed WASI compiler-rt archive without assuming its directory layout" >&2
  exit 1
}
grep -Fq '[ -s "$target_archive" ] && continue' "$template" || {
  echo "template must preserve builtins already installed for a target triple" >&2
  exit 1
}
grep -Fq "libclang_rt.builtins-wasm32.a" "$template" || {
  echo "template must support the compiler-rt archive filename shipped by wasi-sdk" >&2
  exit 1
}
grep -Fq 'libclang_rt.builtins.a' "$template" || {
  echo "template must link the discovered WASI compiler-rt archive into Clang's target-specific resource directories" >&2
  exit 1
}
grep -Fq '"wasm32-unknown-wasip1-threads"' "$template" || {
  echo "template must bridge the WASI Preview 1 threads runtime too" >&2
  exit 1
}
grep -Fq -- '--with-libclang-path=/usr/lib/llvm/${_llvmver}/lib' "$template" || {
  echo "bindgen must search the matching versioned LLVM library directory" >&2
  exit 1
}
if [ -n "${2:-}" ]; then
  rust_template=$2
  [ -f "$rust_template" ] || {
    echo "Void Rust template not found: $rust_template" >&2
    exit 1
  }
  rust_llvmver=$(sed -n 's/^_llvmver=\([0-9][0-9]*\)$/\1/p' "$rust_template")
  [[ "$rust_llvmver" =~ ^[0-9]+$ ]] || {
    echo "could not determine LLVM major from Void Rust template: $rust_template" >&2
    exit 1
  }
  [ "$llvmver" = "$rust_llvmver" ] || {
    echo "LLVM toolchain mismatch: LibreWolf uses LLVM $llvmver but Void Rust emits LLVM $rust_llvmver bitcode" >&2
    exit 1
  }
fi
if [ -n "${3:-}" ]; then
  wasi_template=$3
  [ -f "$wasi_template" ] || {
    echo "Void WASI SDK template not found: $wasi_template" >&2
    exit 1
  }
  wasi_sdk_llvmver=$(sed -n 's/^_llvmversion="\([0-9][0-9]*\)\..*/\1/p' "$wasi_template")
  [[ "$wasi_sdk_llvmver" =~ ^[0-9]+$ ]] || {
    echo "could not determine LLVM major from Void WASI SDK template: $wasi_template" >&2
    exit 1
  }
  [ "$wasi_llvmver" = "$wasi_sdk_llvmver" ] || {
    echo "WASI runtime path mismatch: LibreWolf expects LLVM $wasi_llvmver compiler-rt but Void wasi-sdk uses LLVM $wasi_sdk_llvmver" >&2
    exit 1
  }
fi

set -- $distfiles
[ "$#" -eq 1 ] || {
  echo "template must contain exactly one distfile URL" >&2
  exit 1
}

case "$1" in
  https://*) ;;
  *) echo "distfile must use HTTPS: $1" >&2; exit 1 ;;
esac

expected_template_distfile='${pkgname}-${version}-${_rev}.source.tar.gz'
expected_distfile="${pkgname}-${version}-${_rev}.source.tar.gz"
expected_source_url="https://librewolf.dev/api/packages/librewolf/generic/librewolf-source/\${version}-\${_rev}/\${pkgname}-\${version}-\${_rev}.source.tar.gz"
[ "$1" = "$expected_source_url" ] || {
  echo "distfile URL template mismatch: expected $expected_source_url, got $1" >&2
  exit 1
}

# The shipped browser is native Wayland; only CI's temporary PGO run uses Xvfb.
grep -Fq 'ac_add_options --enable-default-toolkit=cairo-gtk3-wayland' "$template" || {
  echo "template must build the native GTK3 Wayland toolkit" >&2
  exit 1
}
grep -Fq 'xvfb-run -a -s' "$template" || {
  echo "PGO must use an isolated Xvfb profile-server workload" >&2
  exit 1
}
grep -Fq 'GDK_BACKEND=x11' "$template" || {
  echo "PGO must use the X11 backend for its isolated Xvfb run" >&2
  exit 1
}
grep -Fq 'MOZ_ENABLE_WAYLAND=0' "$template" || {
  echo "PGO must disable Firefox's Wayland display selection under Xvfb" >&2
  exit 1
}
grep -Fq 'ac_add_options RUSTC_OPT_LEVEL=2' "$template" || {
  echo "Rust code must use optimization level 2 for browser rendering and styling hot paths" >&2
  exit 1
}
for sandbox_env in \
  MOZ_DISABLE_CONTENT_SANDBOX \
  MOZ_DISABLE_GMP_SANDBOX \
  MOZ_DISABLE_GPU_SANDBOX \
  MOZ_DISABLE_RDD_SANDBOX \
  MOZ_DISABLE_SOCKET_PROCESS_SANDBOX \
  MOZ_DISABLE_UTILITY_SANDBOX \
  MOZ_DISABLE_VR_SANDBOX; do
  grep -Fq "$sandbox_env=1" "$template" || {
    echo "PGO CI profile run must disable the $sandbox_env sandbox in the restricted build container" >&2
    exit 1
  }
done
if grep -Eq 'ac_add_options --disable-(content-)?sandbox' "$template"; then
  echo "the shipped browser must retain its normal sandbox configuration" >&2
  exit 1
fi
default_options=$(sed -n 's/^build_options_default="\([^"]*\)"/\1/p' "$template")
case " $default_options " in
  *" pgo "*)
    echo "PGO must remain opt-in and must not appear in build_options_default" >&2
    exit 1
    ;;
esac
grep -Fq 'falling back to a non-PGO LTO build' "$template" || {
  echo "PGO failures must fall back to the standard LTO build" >&2
  exit 1
}
if grep -Eq '^[[:space:]]*(export[[:space:]]+)?LDFLAGS.*--lto-partitions=' "$template"; then
  echo "do not force global LTO partitions; it can break SyscallAsm linkage in the Linux sandbox" >&2
  exit 1
fi
if grep -Eq 'GDK_BACKEND=wayland|MOZ_ENABLE_WAYLAND=1|pgo-runtime/wayland' "$template"; then
  echo "obsolete headless-Wayland PGO setup remains in the package template" >&2
  exit 1
fi
package_dir="$(cd "$(dirname "$template")" && pwd)"
vendor_js="$package_dir/files/vendor.js"
sandbox_patch="$package_dir/patches/sandbox-sched_setscheduler.patch"
[ -f "$vendor_js" ] || {
  echo "package vendor.js is missing" >&2
  exit 1
}
[ -f "$sandbox_patch" ] || {
  echo "musl scheduler sandbox patch is missing" >&2
  exit 1
}
user_chrome="$package_dir/files/userChrome.css"
wasm_wrapper_source="$package_dir/files/wasm2c_sandbox_wrapper.c"
[ -s "$user_chrome" ] || {
  echo "package userChrome.css is missing" >&2
  exit 1
}
[ -s "$wasm_wrapper_source" ] || {
  echo "RLBox WASI wrapper fallback source is missing" >&2
  exit 1
}
for host_source in nsinstall.c pathsub.c; do
  [ -s "$package_dir/files/$host_source" ] || {
    echo "Mozilla $host_source fallback source is missing" >&2
    exit 1
  }
done
grep -Fq 'for host_source in nsinstall.c pathsub.c; do' "$template" || {
  echo "template must restore both Mozilla host source files after extraction" >&2
  exit 1
}
grep -Fq 'local compat_version="${version%.*}"' "$template" || {
  echo "template must derive Mozilla's major/minor source directory from the package version" >&2
  exit 1
}
grep -Fq 'local compat_srcdir="$(dirname "$PWD")/${pkgname}-${compat_version}"' "$template" || {
  echo "template must derive Mozilla's compatibility source root" >&2
  exit 1
}
grep -Fq 'ln -s "$PWD" "$compat_srcdir"' "$template" || {
  echo "template must alias the full extracted source tree at Mozilla's recorded source root" >&2
  exit 1
}
grep -Fq 'readlink -f "$compat_srcdir"' "$template" || {
  echo "template must verify an existing compatibility source symlink before reusing it" >&2
  exit 1
}
grep -Fq 'third_party/rlbox_wasm2c_sandbox/c_src/wasm2c_sandbox_wrapper.c' "$template" || {
  echo "template must restore the missing RLBox WASI wrapper source after extraction" >&2
  exit 1
}
grep -Fq 'vinstall ${FILESDIR}/userChrome.css 644 usr/lib/librewolf/browser/defaults/profile/chrome' "$template" || {
  echo "template must install userChrome.css into the default profile" >&2
  exit 1
}
for patch_file in "$package_dir"/patches/*.patch; do
  git apply --numstat "$patch_file" >/dev/null || {
    echo "invalid unified diff or hunk counts in $patch_file" >&2
    exit 1
  }
done
if grep -Fq 'location.services.mozilla.com' "$vendor_js" || grep -Fq 'MOZILLA_API_KEY' "$template"; then
  echo "retired Mozilla Location Service configuration must not be shipped" >&2
  exit 1
fi
added_pid_guards=$(grep -F -c '+        return If(pid == 0, Allow()).Else(Trap(SchedTrap, nullptr));' "$sandbox_patch" || true)
[ "$added_pid_guards" -eq 2 ] || {
  echo "both musl scheduler rules must retain the current-thread PID restriction" >&2
  exit 1
}
if grep -Fq '+        return Allow();' "$sandbox_patch"; then
  echo "musl sched_setscheduler must not be unconditionally allowed" >&2
  exit 1
fi
if [ -e "$package_dir/patches/parakeet-missing-cstdint.patch" ]; then
  echo "obsolete parakeet cstdint patch must not be shipped: Firefox 160 already includes this header" >&2
  exit 1
fi
grep -Fq 'if ./mach build && ./mach package; then' "$template" || {
  echo "instrumented PGO build/package failures must fall back to an LTO-only build" >&2
  exit 1
}
grep -Fq 'PGO-use build failed; retrying with the non-PGO LTO configuration.' "$template" || {
  echo "PGO-use build failures must have an LTO-only fallback" >&2
  exit 1
}

actual_distfile="${1##*/}"
[ "$actual_distfile" = "$expected_template_distfile" ] || {
  echo "distfile basename mismatch: expected $expected_template_distfile, got $actual_distfile" >&2
  exit 1
}

case "$expected_distfile" in
  librewolf-[0-9.]*-[0-9]*.source.tar.gz) ;;
  *) echo "resolved LibreWolf distfile name is invalid: $expected_distfile" >&2; exit 1 ;;
esac

distfile="$expected_distfile"
release_tag="${version}-r${revision}"

if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ "${GITHUB_REF_NAME:-}" != "$release_tag" ]; then
  echo "pushed tag does not match package version/revision: expected $release_tag, got ${GITHUB_REF_NAME:-unset}" >&2
  exit 1
fi

if [ "${GITHUB_EVENT_NAME:-}" = "workflow_dispatch" ] &&
  [ "${INPUT_PGO:-false}" = "true" ] &&
  [ "${INPUT_PUBLISH_RELEASE:-false}" = "true" ]; then
  echo "PGO and release publication cannot be selected for the same manual run" >&2
  exit 1
fi

if [ -n "$GITHUB_OUTPUT" ]; then
  {
    echo "sha256=$checksum"
    echo "distfile=$distfile"
    echo "version=$version"
    echo "rev=$_rev"
    echo "package_revision=$revision"
    echo "release_tag=$release_tag"
  } >> "$GITHUB_OUTPUT"
fi

printf 'validated: %s (package revision %s; tag %s; source %s)\n' "$pkgname" "$revision" "$release_tag" "$distfile"
