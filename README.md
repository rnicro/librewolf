# LibreWolf for Void Linux (musl)

A resource-conscious LibreWolf package for Void Linux `x86_64-musl`, tuned for an Intel Skylake CPU, 4 GB RAM, HDD storage, and native Wayland. This is a specialized build, not a portable x86-64 binary.

## Target and runtime

- **Platform:** Void Linux, `x86_64-musl` only.
- **CPU:** Skylake or newer. The binary uses `-O2 -march=skylake` and Rust `target-cpu=skylake`; it will not run on older x86-64 CPUs.
- **Display:** GTK3 native Wayland, intended for systems without Xwayland. Run `librewolf-wayland` (or `MOZ_ENABLE_WAYLAND=1 librewolf`). Check `about:support` and confirm **Window Protocol** is `wayland`.
- **Audio:** ALSA and PulseAudio protocol support, including PipeWire through `pipewire-pulse`.

### Low-resource defaults

`srcpkgs/librewolf/files/vendor.js` configures inactive-tab unloading under memory pressure, a shared content-process limit, one prelaunched process, no new-tab preload, and a 30-second session-store interval. Disk-cache write buffers are limited to 24 MiB per class. These choices trade some parallelism and preloading for lower memory pressure and fewer HDD writes; they are target-specific, not universal performance recommendations.

The package disables Firefox's built-in updater and crash reporter. Keep the package updated by installing newer builds; browser security still depends on timely upstream releases and package rebuilds.

## Install a release

Download the `.xbps` package from [GitHub Releases](https://github.com/rnicro/librewolf/releases). Keep the official Void repositories enabled for dependencies. To install a downloaded package from the current directory:

```sh
xbps-rindex -a ./librewolf-*.xbps
sudo xbps-install --repository="$PWD" librewolf
```

Releases contain package archives, not an XBPS repository or checksum manifest. Verify downloads against a trusted checksum obtained independently where one is provided.

## Build and CI

The GitHub Actions workflow builds through Void's `xbps-src` on an Ubuntu runner and publishes the LibreWolf package for commits to `master`. It runs when package files, the workflow, or its validation script change; manual dispatch supports an LTO-only build without PGO.

- Clang/LLVM/LLD are pinned to major version 23 to match Void Rust's LLVM bitcode. The build uses cross-language full LTO by default.
- Release CI enables PGO. Profiles are validated before use; failed profiling falls back to an LTO-only build. Source, PGO, Void dependency, and compiler-object caches reduce repeated work. Cache contents are validated rather than trusted blindly.
- Xvfb and sandbox-disabling environment variables are used only for the temporary instrumented PGO profiling run in CI. They are not configured into the shipped browser, which retains its normal sandbox behavior and native Wayland configuration.
- CI checks the source archive SHA-256 before building. Release tags use `<version>-r<package-revision>`; existing tags are not retargeted when package inputs change.

## Updating LibreWolf

1. Set `version`, `_rev` and `checksum` in `srcpkgs/librewolf/template` to match the upstream source archive. The `distfiles` URL is derived from those fields.
2. Increase `revision` for downstream packaging changes; reset it only when intentionally starting a new upstream package version.
3. Review the downstream patches against the new source and remove a patch only after verifying it is no longer needed.
4. Push the changes to `master` and inspect CI validation, checksum verification, compiler-cache statistics, build completion, and the release assets.
5. Bump `LIBREWOLF_PGO_CACHE_VERSION` in `.github/workflows/main.yml` when profile-relevant inputs change but are not covered by the PGO cache key.

The workflow pins `void-linux/void-packages` at a known commit so compiler and package recipes do not drift between runs. Update the `ref` in `.github/workflows/main.yml` deliberately when refreshing the build toolchain; the validator checks that LibreWolf's LLVM major matches Void Rust and WASI SDK. GitHub Actions are also pinned by commit SHA. These pins improve consistency, but the runner image and the `xbps-static` download are still external inputs, so the build is not fully hermetic.

## Repository layout

- `srcpkgs/librewolf/template` — package recipe, compiler settings, PGO flow, and installation.
- `srcpkgs/librewolf/patches/` — musl, sandbox, WASI, and upstream-build compatibility patches.
- `srcpkgs/librewolf/files/vendor.js` — runtime preferences.
- `srcpkgs/librewolf/files/librewolf.desktop` — desktop entry and actions.
- `.github/workflows/main.yml` — build, cache, and release automation.
- `.github/scripts/validate-template.sh` — checks package metadata and important toolchain/build invariants.

The patches are build compatibility fixes and should be kept small. Re-audit them on each upstream bump; do not remove them solely to reduce file count.
