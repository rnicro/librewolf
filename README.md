# LibreWolf for Void Linux (musl)

A custom [LibreWolf](https://librewolf.dev/librewolf/source/releases) package profile for **Void Linux** `x86_64-musl`, tuned primarily for Intel Skylake-class CPUs and systems with limited memory or slow storage.

Inspired by [index-0/librewolf-void](https://github.com/index-0/librewolf-void), whose XBPS repository and provenance workflow informed the signed-repository publishing design here.

## Install from the signed XBPS repository

This project currently publishes packages for **Void Linux `x86_64-musl`** only.

For automatic package updates, add the release-backed repository:

```sh
printf '%s\n' 'repository=https://github.com/rnicro/librewolf/releases/latest/download' | sudo tee /etc/xbps.d/20-librewolf.conf
sudo xbps-install -S
sudo xbps-install librewolf
```
To install from one specific release without configuring a persistent repository:

```sh
sudo xbps-install -SR https://github.com/rnicro/librewolf/releases/download/<release-tag> librewolf
```

The first install may ask you to trust the repository signing key. Verify the signing identity with the maintainer before accepting it. The release contains the XBPS repository index, signed package archives, a `SHA256SUMS` manifest, and GitHub build provenance for the package.

### Repository signing setup

The release workflow requires these GitHub repository settings:

- Actions secret `PRIV_KEY`: an RSA private key in PEM format.
- Actions secret `SIGN_PASS`: the key passphrase; optional for an unencrypted key.
- Actions variable `SIGNEDBY`: the signing identity shown in XBPS metadata (for example, a maintainer name and email).

A compatible key can be generated with:

```sh
ssh-keygen -t rsa -b 4096 -m PEM -f privkey.pem
```

Store the private key only in GitHub Actions secrets; never commit it. Signing runs in a separate publishing job, after the build job has completed, so build scripts and third-party build dependencies do not receive the signing credentials.

Releases created before PGO became the default contain LTO-only packages and cannot be promoted in place by the PGO-enabled workflow: the rebuilt package will not be byte-identical. The package revision has therefore been incremented; publish the new version/revision tag to move to the PGO-enabled package. Configure a GitHub tag ruleset for `*-r*` and disallow tag updates/deletions to protect published version tags.

Verify package checksums and GitHub provenance after downloading a release:

```sh
sha256sum -c SHA256SUMS
gh attestation verify -R rnicro/librewolf librewolf-<version>_<revision>.x86_64-musl.xbps
```

## Browser customization

New profiles receive the packaged `userChrome.css`, which provides a compact navigation-bar/tab layout and hides titlebar decorations for the dwl compositor. The preference bundle enables loading user stylesheets and Firefox Fingerprinting Protection (FPP). Legacy Resist Fingerprinting is disabled; FPP remains enabled, with only the `CSSPrefersColorScheme` target excluded so websites can follow the selected light/dark theme.

## Target and compatibility

- Void Linux `x86_64-musl`.
- Intel Skylake-class CPU; the reference system is an Intel Core i3-6100U.
- Intended for systems around 4 GB RAM and traditional HDD storage.
- Native GTK3 Wayland build; Xvfb is used only for isolated CI PGO training.

**Compatibility:** This is a deliberately hardware-specific personal build, not a general-purpose x86_64 binary. The `-march=skylake` compiler target can produce instructions unsupported by older CPUs.

## Build features

### Performance

- C and C++: `-O2 -march=skylake`.
- Rust: `-C target-cpu=skylake`, optimization level 2.
- Cross-language full LTO with Clang 23 and LLD 23 by default.
- sccache for compiler-object reuse.
- PGO is enabled for every build. CI generates a training profile when no valid cached profile exists; profile-generation or profile-use failures fall back to the LTO-only configuration.

### Memory and storage

- Firefox's low-memory tab unloading is enabled.
- Fission site isolation remains enabled.
- Content-process pool and prelaunch values are tuned for the target system.
- New-tab preloading is disabled.
- Session-store writes are set to 30 seconds: fewer periodic writes, but a crash can lose more recent session state.
- Disk-cache chunk buffers are limited to 24 MiB per cache class. Heavy cache workloads may see more re-downloads.

These are workload-specific trade-offs, not benchmark-proven improvements. Measure on target hardware before describing them as faster.

## Additional build details

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

Commits pushed to branches do not trigger automatic builds. Only a pushed tag matching the package template's exact `<version>-r<revision>` value starts an automatic PGO-enabled build, XBPS repository signing, a GitHub provenance attestation, and release publication.

A manual dispatch has `publish_release` enabled by default, so it attempts to publish the matching version/revision tag. Turn this input off when you only want a PGO-enabled build artifact. Publishing proceeds only when the package recipe and Mozilla source-fallback inputs are unchanged from the tag and, when a release already exists, the rebuilt package bytes match. This can refresh signing metadata for a release already built with PGO. Older LTO-only releases cannot be promoted in place; increment the package revision and publish a new tag. If PGO profile generation or profile use fails, the package template falls back to the LTO-only configuration.

The workflow verifies the upstream source archive with its SHA-256, validates package and workflow invariants, budgets build parallelism using available memory, and stages only LibreWolf package archives. The separate publisher initializes the architecture-specific XBPS index, signs the repository metadata and each package, verifies the resulting files, generates `SHA256SUMS`, and creates a GitHub attestation for the package.

The build restores Mozilla's host-side `config/nsinstall.c` and `config/pathsub.c` sources from an immutable upstream commit when the LibreWolf source snapshot omits them, verifying each file's SHA-256. Mozilla's generated build metadata can refer to the major/minor source-root path even though xbps extracts under the full package version, so the template creates a guarded symlink from the compatibility path to the complete extracted source tree. For local builds, run `bash .github/scripts/prepare-source-fallbacks.sh` before copying the package into `void-packages`.

Build reproducibility is improved with `SOURCE_DATE_EPOCH`, but full reproducibility is not guaranteed while the Void package tree and host build tools are fetched from moving upstream references.

## Maintenance checklist

When updating LibreWolf:

1. Update the source version and SHA-256 checksum.
2. Increment the package revision for packaging-only changes.
3. Re-check every downstream patch against the new source.
4. Keep Clang, LLVM, LLD, Rust, Cargo, and wasi-sdk compatible.
5. Run automated template/workflow validation and a complete package build.
6. Validate cached PGO profiles and benchmark performance against an LTO-only build during maintenance.
7. Test Wayland startup, audio/video, WebRTC, extension behavior, sandboxing, tab unloading, suspend/resume, and session recovery.

## References

- [LibreWolf source releases](https://librewolf.dev/librewolf/source/releases)
- [XBPS signing and repository reference implementation](https://github.com/index-0/librewolf-void)
- [XBPS repository index documentation](https://man.voidlinux.org/xbps-rindex)
- [Void Linux Firefox package](https://github.com/void-linux/void-packages/tree/master/srcpkgs/firefox)
- [Mozilla Firefox build documentation](https://firefox-source-docs.mozilla.org/build/buildsystem.html)
- [Firefox tab unloading documentation](https://gecko-docs.mozilla.org.s3.amazonaws.com/browser/components/tabbrowser/docs/tab-unloading.html)
