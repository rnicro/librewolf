# LibreWolf XBPS Repository for Void Linux (x86_64-musl)

A custom [LibreWolf](https://librewolf.dev/librewolf/source/releases) package profile for **Void Linux** `x86_64-musl`, tuned primarily for Intel Skylake-class CPUs and systems with limited memory or slow storage.

Inspired by [index-0/librewolf-void](https://github.com/index-0/librewolf-void).

## Install from the XBPS repository

This repository publishes a LibreWolf package for **Void Linux x86_64-musl**.

Add the repository for automatic package updates:

```sh
printf '%s\n' 'repository=https://github.com/rnicro/librewolf/releases/latest/download' \
  | sudo tee /etc/xbps.d/20-librewolf.conf
sudo xbps-install -S
sudo xbps-install librewolf
```

To install from one specific release without configuring a persistent repository:

```sh
sudo xbps-install -R https://github.com/rnicro/librewolf/releases/download/<tag> librewolf
```

The release contains the XBPS package, architecture-specific repository index, package signatures, and a `SHA256SUMS` manifest. Remote XBPS repositories require signed metadata and signed package archives. On first use, XBPS may ask you to trust the repository's signing key; verify its fingerprint with the repository maintainer before accepting it.

For repository maintainers, configure the GitHub Actions secret `PRIV_KEY` with a PEM-encoded RSA private key, the optional secret `SIGN_PASS` when that key is encrypted, and the Actions variable `SIGNEDBY` with the signing identity. Generate a key with `ssh-keygen -t rsa -b 4096 -m PEM -f privkey.pem`; store the private key only in GitHub Actions secrets and never commit it to this repository. Signing happens in the separate publishing job, after the build job has finished.

## Browser customization

New profiles receive the packaged `userChrome.css` as their primary chrome stylesheet. The preference bundle also enables user stylesheets with `toolkit.legacyUserProfileCustomizations.stylesheets`, disables legacy RFP, and enables FPP with `+AllTargets,-CSSPrefersColorScheme` so fingerprinting protection remains enabled while sites can follow the selected light/dark content theme.

## Build locally

To build the package yourself:

```sh
git clone https://github.com/void-linux/void-packages
cd void-packages
./xbps-src binary-bootstrap
cd ..
git clone https://github.com/rnicro/librewolf
cp -a librewolf/srcpkgs/librewolf void-packages/srcpkgs/
cd void-packages
./xbps-src pkg librewolf
sudo xbps-install -R hostdir/binpkgs librewolf
```

The template intentionally supports only `x86_64-musl` and targets Skylake-class CPUs.

## Target and compatibility

- Void Linux `x86_64-musl`.
- Intel Skylake-class CPU; the reference system is an Intel Core i3-6100U.
- Intended for systems around 4 GB RAM and traditional HDD storage.
- Native GTK3 Wayland build; Xvfb is used only for optional CI PGO training.

**Compatibility:** This is a deliberately hardware-specific personal build, not a general-purpose x86_64 binary. The `-march=skylake` compiler target can produce instructions unsupported by older CPUs.

## Build features

### Performance

- C and C++: `-O2 -march=skylake`.
- Rust: `-C target-cpu=skylake`, optimization level 2.
- Cross-language full LTO with Clang 23 and LLD 23 by default.
- sccache for compiler-object reuse.
- PGO is supported, but experimental and opt-in only.

### Memory and storage

- Firefox's low-memory tab unloading is enabled.
- Fission site isolation remains enabled.
- Content-process pool and prelaunch values are tuned for the target system.
- New-tab preloading is disabled.
- Session-store writes are set to 30 seconds: fewer periodic writes, but a crash can lose more recent session state.
- Disk-cache chunk buffers are limited to 24 MiB per cache class. Heavy cache workloads may see more re-downloads.

These are workload-specific trade-offs, not benchmark-proven improvements. Measure on target hardware before describing them as faster.

## Experimental and opt-in features

- **PGO:** Experimental. Automatic release builds use the LTO-only baseline. A manual GitHub Actions dispatch can opt in to PGO; that run creates an artifact but does not publish a release.
- **WASI integration:** Enabled by default and tied to the pinned LLVM 23 / WASI SDK toolchain. Revalidate it when Void updates Rust, LLVM, or wasi-sdk.
- Downstream patches are kept only while needed. The old Parakeet `<cstdint>` patch was removed because Firefox 160 already includes that header.
- **Tab unloading:** Firefox's built-in memory-pressure feature, not a project-specific experimental feature. It may reload inactive tabs after memory pressure.

## Security and privacy notes

- Mozilla hardening is enabled and the normal content-process sandbox is retained.
- The musl scheduler-syscall patch keeps the current-thread PID restriction used by the upstream sandbox policy.
- LibreWolf intentionally disables extension-signature enforcement. Unsigned extensions may be accepted; install add-ons only from sources you trust.
- The retired Mozilla Location Service endpoint and API-key stub are not used. Geolocation follows upstream browser defaults.
- Crash reporting, telemetry reporting, and the in-browser updater are disabled; package updates must come from the Void package/release process.

## Build and release workflow

Only tags matching the package template's `<version>-r<revision>` format trigger an automatic build and release. Ordinary branch pushes and merges—including pushes to `main`—do not start builds. A manual GitHub Actions dispatch is available when explicitly requested; it builds an artifact but does not publish a release. The tag must match the version and revision in `srcpkgs/librewolf/template`.

The workflow verifies the upstream source archive with the package SHA-256, validates template and workflow invariants, and budgets build parallelism using available memory. It stages only the LibreWolf package from the build job. A separate publishing job signs the package and XBPS repository index, then publishes the package, signatures, repository metadata, and a `SHA256SUMS` manifest.

Build reproducibility is improved with `SOURCE_DATE_EPOCH`, but full reproducibility is not guaranteed while the Void package tree and host build tools are fetched from moving upstream references.

## Maintenance checklist

When updating LibreWolf:

1. Update the source version and SHA-256 checksum.
2. Increment the package revision for packaging-only changes.
3. Re-check every downstream patch against the new source.
4. Keep Clang, LLVM, LLD, Rust, Cargo, and wasi-sdk compatible.
5. Run automated template/workflow validation and a complete package build.
6. Compare LTO-only and PGO builds before changing the release default.
7. Test Wayland startup, audio/video, WebRTC, extension behavior, sandboxing, tab unloading, suspend/resume, and session recovery.

## References

- [LibreWolf source releases](https://librewolf.dev/librewolf/source/releases)
- [Void Linux Firefox package](https://github.com/void-linux/void-packages/tree/master/srcpkgs/firefox)
- [Mozilla Firefox build documentation](https://firefox-source-docs.mozilla.org/build/buildsystem.html)
- [Firefox tab unloading documentation](https://gecko-docs.mozilla.org.s3.amazonaws.com/browser/components/tabbrowser/docs/tab-unloading.html)
