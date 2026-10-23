# LibreWolf — Skylake / Void Linux musl

LibreWolf 158.0.1, tuned for an Intel Core i3-6100U (Skylake), 4 GB RAM, HDD, and Void Linux `x86_64-musl`. The binary requires a Skylake-class CPU or newer.

## Native Wayland runtime

Built with GTK3 `cairo-gtk3-wayland` for `dwl` without Xwayland or an X11 server. Launch with:

```sh
MOZ_ENABLE_WAYLAND=1 librewolf-wayland
```

Verify `about:support` → **Window Protocol** reports `wayland`, not `xwayland`. Xvfb/X11 is used only by the optional CI PGO profiling path; it is not a runtime requirement.


## Download and install

Open [GitHub Releases](https://github.com/Azuuuuure222/librewolf/releases) and download the `.xbps` package for your target. Releases intentionally contain package archives only—no repository metadata or checksum manifests.

For a local install, keep the official Void repositories enabled for dependencies, install `xbps` tools, and create local repository metadata from the downloaded package:

```sh
xbps-rindex -a ./librewolf-*.xbps
sudo xbps-install --repository="$PWD" librewolf
```

If you want to verify a download, calculate its checksum locally and compare it with a trusted value obtained independently. Do not assume a release contains checksum files or repository metadata. The source recipe may be newer than the latest published binary; check the release's actual version and assets.

## Target tuning

- C/C++: Clang/LLD/LLVM 23 (matched to Void's Rust LLVM version), `-O2 -march=skylake`; Rust: `-C target-cpu=skylake`.
- Build: cross-language LLVM LTO is the default; experimental PGO is disabled unless requested in a manual workflow dispatch.
- PGO: a manual workflow dispatch can opt in. Profiles are checksum-validated and cached by source and profile-relevant inputs; failed or invalid profile generation falls back to a regular LTO build. Benchmark against an LTO-only baseline before assuming a runtime win.
- Memory: unload tabs under low-memory conditions; constrain Fission process reuse and prelaunch.
- HDD: disable new-tab preload, save session state every 30 seconds, and cap cache-chunk memory at 16 MiB per cache class.
- Audio: ALSA and PulseAudio protocol support, including `pipewire-pulse`.

These settings prioritize resource stability on the target; process limits trade some parallelism for lower memory pressure.

## Build and release

- Source revision: LibreWolf 158.0.1-2; package revision: 1.
- CI builds on a hosted runner. Build parallelism follows runner CPU and RAM capacity.
- CI validates the source checksum, caches source/compiler/Void dependencies, and publishes only `.xbps` package files. Release tags and release titles use the LibreWolf version alone. PGO profiles are cached when available and regenerated when the cache key changes.
- Build permissions are read-only; publishing runs separately and only for `master`.

## Key paths

- `srcpkgs/librewolf/template`: package recipe and build flags.
- `srcpkgs/librewolf/files/vendor.js`: runtime preferences.
- `.github/workflows/main.yml`: build and release automation.
- `.github/scripts/validate-template.sh`: pre-build checks.

## Repository rule

Commit changes directly to `master`. Do not create feature branches or pull requests unless explicitly instructed otherwise.

## Full technical reference

The sections above are the quick-start summary. This reference records the full package configuration, build pipeline, cache rules, compatibility patches and the important history behind the current choices.

### Target and optimization boundaries

| Target property | Value |
|---|---|
| Operating system/libc | Void Linux, musl |
| Architecture | `x86_64-musl` |
| CPU | Intel Core i3-6100U, Skylake, 2 cores / 4 threads |
| RAM/storage | 4 GB DDR3 / HDD |
| Display/audio | Native Wayland / ALSA and PulseAudio protocol |
| Source/package revision | LibreWolf 158.0.1, source revision 2, Void package revision 1 |

Priorities are runtime responsiveness on the actual Skylake machine, memory stability, reduced unnecessary HDD writes, useful CI throughput, reuse of expensive build outputs, and a small maintainable patch set. The **build host and runtime target are different machines**: compile and link concurrency should follow the actual GitHub runner's CPU/RAM, not the laptop's four hardware threads.

The package intentionally does not target pre-Skylake CPUs, glibc variants, unrelated architectures, or universal x86_64 portability. It does not blindly maximize compiler flags, run the full Firefox test suite on every personal build, or treat benchmark results as proof of real-world improvement. Security updates and behavior still depend on the upstream LibreWolf/Firefox and Void packaging model; this repository is a specialized personal build profile, not a general-purpose distribution package.

### Complete current runtime preference profile

Installed in `srcpkgs/librewolf/files/vendor.js`:

| Preference | Value | Effect |
|---|---:|---|
| `intl.locale.requested` | empty | Normal locale selection |
| `browser.shell.checkDefaultBrowser` | false | Disable default-browser prompt/check |
| `extensions.autoDisableScopes` | 11 | Keep application-bundled extensions enabled |
| `browser.tabs.unloadOnLowMemory` | true | Permit inactive-tab unloading under memory pressure |
| `browser.sessionstore.interval` | 30000 ms | Reduce session-store write frequency on HDD |
| `browser.newtab.preload` | false | Do not preload an unused new-tab page |
| `browser.cache.disk.max_chunks_memory_usage` | 16384 KiB | 16 MiB cache-chunk memory cap |
| `browser.cache.disk.max_priority_chunks_memory_usage` | 16384 KiB | Same cap for priority chunks |
| `dom.ipc.processCount` | 4 | General content-process limit |
| `dom.ipc.processCount.webIsolated` | 2 | Isolated-site process pool/reuse limit |
| `dom.ipc.processPrelaunch.fission.number` | 1 | One Fission prelaunch |
| `geo.provider.network.url` | Mozilla location service | Avoid the default Google geolocation provider |

Earlier README revisions also documented `browser.low_commit_space_threshold_mb=384` and `browser.low_commit_space_threshold_percent=10`. They are no longer present in the current preference file and must not be described as active settings. The current numbers prioritize resource stability and accept some loss of parallelism/preloading; they are not universal recommendations.

### Compiler, LTO, and linker details

- C/C++ uses Clang 23 and `-O2 -march=skylake`; Rust uses `-C target-cpu=skylake` and `RUSTC_OPT_LEVEL=2`. The current template does not separately add `-mtune=skylake`, although older README revisions documented it.
- Clang, LLVM, LLD and the LLVM major used by Void's Rust template are explicitly aligned at version 23. The validator checks this before compilation because incompatible LLVM bitcode can break cross-language LTO.
- Void's `wasi-sdk` 32 packages separate LLVM 22 compiler-rt builtins for `wasm32-unknown-wasip1` and `wasm32-unknown-wasip1-threads`. Clang 23 expects corresponding target-triple directories under its own resource root. The build recipe maps each real archive into the matching Clang 23 directory and fails early with a clear error if either archive is absent. This is a build-time compatibility fix; the final package's native x86_64 runtime is unaffected.
- Rust bindgen requires the unversioned `libclang.so`, which Void ships in `clang23-devel` under `/usr/lib/llvm/23/lib`. The package installs that build-only dependency and points `--with-libclang-path` at the versioned library directory instead of the obsolete `/usr/lib` path.
- Full cross-language LTO uses `--enable-lto=cross,full` when the default LTO option is enabled. LLD adds `-Wl,--threads=N` and `-Wl,--lto-O2`; N follows the selected build job count.
- **Do not re-add forced LTO partitions.** The latest fix leaves LLD's partitioning default because multiple partitions can separate the Linux sandbox's file-scope `SyscallAsm` symbol from its C++ callers.
- `-O2` is intentional: `-O3` is not automatically faster and can increase code size, instruction-cache pressure, memory use and compile time on the 4 GB target.
- WASI sandboxed libraries are enabled by default. Release mode, Mozilla hardening, path remapping, packed relative relocations and Rust SIMD are configured.
- The former Rust ThinLTO patch modified an obsolete Firefox Cargo flag path; it was removed after Firefox moved that work into `RUN_CARGO_ACTION`.

### Build options, system libraries, and install behavior

The recipe defines `alsa`, `dbus`, `pulseaudio`, `lto`, `pgo`, `clang`, `wasi` and `debug`. Defaults enable ALSA, D-Bus, PulseAudio, LTO, Clang and WASI; PGO and debug are opt-in. Wayland is enforced by the template. For non-debug builds, debug mode and debug symbols are disabled.

Build settings disable package-build tests, the updater, crash reporter, telemetry/data-reporting features, Cargo incremental compilation, jemalloc and ELF hack; Firefox's install/strip options are also explicitly controlled by the recipe. The environment uses system Python for mach, a dedicated mozbuild state directory, `MOZ_NOSPAM=1` and reproducible-date support through `SOURCE_DATE_EPOCH` when supplied.

Build dependencies include GTK3, NSS/NSPR, pixman, JPEG, libevent, libnotify, WebP, FreeType, the required X11 protocol/header libraries, Rust/Cargo, Node.js, cbindgen, NASM, Clang/LLVM/LLD, Clang development libraries for bindgen, and Void's packaged `rust-sccache`. Option-specific dependencies cover ALSA, D-Bus, PulseAudio, WASI and PGO.

System-library configuration includes FFI, JPEG, libevent, NSPR, NSS, WebP, zlib and pixman. System PNG is disabled because the target system's libpng lacks APNG support. System libvpx remains commented out. Runtime dependencies include NSS, NSPR, desktop-file-utils, hicolor-icon-theme, pciutils and Void's `libavcodec6` for codec support; FFmpeg development headers are not required by this recipe.

Audio backend configuration disables all backends first, then enables ALSA and the PulseAudio protocol; this supports PipeWire through `pipewire-pulse`. XScreenSaver, sndio and JACK were removed as irrelevant to this target. Installation adds the desktop file, icons and `vendor.js`, copies `stab.h` into Breakpad for compatibility, writes the Mozilla location API key required by the Void packaging flow, removes development/IDL artifacts, and creates the `librewolf-bin` and `librewolf-wayland` symlinks.

### PGO failure handling

PGO is **experimental and disabled by default** because profile-server startup crashed across earlier built-in headless, synthetic native-Wayland/Weston and Xvfb experiments. An explicit manual workflow dispatch can request PGO; ordinary push builds remain LTO-only. Only PGO-enabled runs restore or save the PGO cache.

When requested, the recipe checks for `merged.profdata` and `jarlog`, and validates the profile using `llvm-profdata`. On a miss, the instrumented browser is built and packaged, then `build/pgo/profileserver.py` runs inside D-Bus through `xvfb-run` with `GDK_BACKEND=x11`, `MOZ_ENABLE_WAYLAND=0`, a 1920×1080×24 display and a 30-minute timeout. These are build-time dependencies only; the final package still uses native Wayland.

If profiling fails or its files are missing/invalid, the template prints the relevant profile logs, removes the bad output/cache, restores the original mozconfig, clobbers the instrumented objdir and continues with a standard LTO build. A successful profile is cached only after checking both the profile and jarlog. Thus PGO failure should not prevent a standard non-PGO build from succeeding.

### CI concurrency, validation and publication

The workflow:
1. Runs on pushes to `master` that touch the package, workflow or validation scripts, or from manual dispatch.
2. Frees runner disk space when less than 60 GiB is available, checks out this repository and Void's `void-packages` master, then overlays this package.
3. Pre-validates the template and LLVM/Rust toolchain match; prepares static XBPS and the runner's user-namespace environment; bootstraps `xbps-src`.
4. Restores the source, Void binary-package and (only when PGO is requested) profile caches. The Void binary-package cache rotates weekly so it refreshes rather than staying frozen at its first immutable entry.
5. Creates the cache runtime environment for the chroot; builds with concurrency calculated from runner CPU count and available memory.
6. Reserves approximately 2 GiB for the OS/linker and budgets around 3 GiB per concurrent worker, then caps workers by visible CPU count.
7. Generates SHA-256/SHA-512 manifests for package and repository metadata and transfers a short-lived build artifact to publishing.
8. Publishes only on `refs/heads/master`. It ties the release tag to the build commit, refuses to retarget an existing tag, validates digests for existing asset names, uploads missing matching assets, and marks the release latest.

The build job is read-only for repository contents; the separate publish job has write permission. The default runner is Ubuntu 24.04 and `LIBREWOLF_RUNNER` can override it. Total workflow timeout is 360 minutes; the package build step is limited to 350 minutes. New commits do not cancel an active expensive build, but replace the queued pending run for that ref. README-only commits do not match the build path filters.

The validator checks shell syntax, package name, version, positive package revision, source revision, a 64-character SHA-256 checksum, exactly one HTTPS source URL and the expected distfile name. It also verifies the pinned LLVM major matches Clang/LLD and Void Rust, requires the native GTK Wayland toolkit and the Xvfb PGO configuration, confirms PGO remains opt-in with fallback, rejects the obsolete headless/Wayland PGO path and rejects forced global LTO partitions. Metadata exported to Actions includes the checksum, distfile, version, source revision and release tag.

### Cache inventory and invalidation

| Cache | Current key/namespace | Validation and purpose |
|---|---|---|
| Source archive | `librewolf-source-v5-<SHA256>` | Re-hash cached file against template checksum; refetch on mismatch |
| Experimental PGO | `LIBREWOLF_PGO_CACHE_VERSION=v12` | Manual opt-in only; source digest, recipe, patches, `stab.h`, LLVM 23/Rust/Cargo/WASI/sccache/base-chroot inputs |
| Void binary dependencies | `void-repocache-v3` | Weekly immutable snapshot; restores the previous v2 cache or the latest matching v3 week, then saves a refreshed snapshot. This updates package downloads without creating a cache for every commit. |
| Compiler cache | `librewolf-x86_64-musl-skylake-llvm23-v2` | Packaged `rust-sccache` with local disk + GitHub Actions cache |

Important compiler-cache settings are `RUSTC_WRAPPER=/usr/bin/sccache`, `SCCACHE_CLIENT_SIDE=false`, `SCCACHE_DIR=/host/sccache`, `SCCACHE_CACHE_SIZE=16G`, `SCCACHE_CACHE_ZSTD_LEVEL=1` and `SCCACHE_IDLE_TIMEOUT=0`. The multi-level chain is `disk,gha` and remote write failures are ignored so a transient cache outage does not fail the package build. The build uses a packaged cache executable because `xbps-src` can clean/reconstruct its chroot, and it explicitly points Firefox configure at `/usr/bin/sccache` because a bare executable name proved unreliable.

Cache keys are optimizations, never authorities: source is checksum-verified, and PGO output is parsed/validated before use. Bump `LIBREWOLF_PGO_CACHE_VERSION` when workload/schema assumptions change outside the keyed inputs; update `SCCACHE_GHA_VERSION` when the compiler cache namespace/compatibility changes. Release housekeeping should not invalidate otherwise reusable source/compiler/profile data.

### Active downstream patch inventory

| File | Reason it exists |
|---|---|
| `audio_thread_priority-musl.patch` | Serializes `pthread_t` through `usize` because glibc and musl represent the type differently; fixes both Linux audio-priority implementations. |
| `firefox-146-musl-linux-sys-prctl-conflict.patch` | Avoids a musl WebRTC conflict between Linux and system `prctl` headers. |
| `firefox-148-mach-clobber.patch` | Corrects `mozshellutil` lookup in Firefox's build environment dump helper. |
| `fix-fortify-system-wrappers.patch` | Removes `features.h` from generated system headers for this musl/system-wrapper configuration. |
| `wasi-target-wasip1.patch` | Changes Mozilla's WASI target triplet from the old `wasm32-wasi` spelling to `wasm32-wasip1`, matching the renamed target. |
| `mallinfo.patch` | Limits Linux system heap `mallinfo` reporting to glibc. |
| `parakeet-missing-cstdint.patch` | Adds `<cstdint>` to Parakeet's backend header. This is distinct from a different older missing-`cstdint` patch that became obsolete after its fix reached upstream. |
| `sandbox-sched_setscheduler.patch` | Adjusts Linux sandbox scheduler syscall filtering for musl while retaining the glibc PID-restricted logic. |

The current recipe also removes `sys/single_threaded.h` from Firefox's generated system-header list and installs `stab.h` for Breakpad. Keep patches small, re-audit all hunks at every upstream/toolchain update and remove fixes that become unnecessary.

## Condensed commit history and lessons

| Period | Commit-history summary |
|---|---|
| 2022–2025 | Initial README/repository identity and rename, routine upstream LibreWolf updates, release automation and integrity documentation. |
| Sep 23–25, 2026 | Restricted the package to Skylake/`x86_64-musl`; repaired musl compatibility; improved source downloads, metadata/signing checks, Void input pinning, Ubuntu runner support and packaged compiler caching. |
| Sep 30 | Added the 4 GB/HDD runtime profile and Skylake compiler settings; introduced LTO/PGO experiments and source, compiler, PGO and Void dependency caches; improved checksum-aware source reuse. |
| Oct 1 | Simplified master-only CI/release automation, restored the package overlay, improved credential handling and release integrity, and fixed SQLite/FFvpx full-LTO compatibility. |
| Oct 2 | Hardened `sccache` in the chroot, added template validation, fixed metadata/patch/cache errors and documented build-host versus target-device resource use. |
| Oct 3 | Refined PGO cache invalidation and validation, checksum artifact behavior and CI/display profiling constraints. |
| Oct 14 | Updated to LibreWolf 158.0; fixed scheduler sandbox patch ranges, `mallinfo`, source-cache identity and obsolete Rust LTO handling; removed old branch-cleanup logic. |
| Oct 15 | Tuned Fission reuse, corrected LLD worker parsing, improved PGO helpers/cache handling, documented direct-to-master workflow and shortened the 1,078-line README. |
| Oct 16 | Tried headless and native-Wayland PGO, then switched to optional Xvfb PGO after profile startup failures; added an LTO-only fallback, validation guards and packaging/CI cleanup. |
| Oct 17 | Pinned Clang/LLVM/LLD to LLVM 23 to match Void Rust, removed forced LTO partitioning, corrected bindgen's versioned `libclang.so` path, and bridged Void's LLVM 22 WASI runtime layout to Clang 23. |

Key lessons from failures: don't copy unmanaged tools into an XBPS chroot; use explicit compiler-cache paths; validate package/source metadata before costly builds; re-hash source-cache entries; validate LLVM profiles instead of trusting file existence; make cache keys specific to profile-affecting inputs; don't base CI worker counts on the laptop; don't force LTO partitions that can break sandbox linkage; and remove stale patches when upstream fixes or source layout make them obsolete.

Earlier README revisions contained far more implementation narratives and temporary PGO approaches, reached 1,078 lines, and were deliberately compressed. The current README keeps the technical facts, maintenance rules and historical transitions while identifying superseded behavior as history rather than current practice.

## Source updates and maintenance checklist

1. Change `version`, `_rev` and source `checksum` for a new upstream archive; increase `revision` for packaging-only changes.
2. Audit each downstream patch, remove obsolete patches and add only narrow source/toolchain fixes.
3. Keep the `x86_64-musl`/Skylake restriction explicit unless the build is deliberately redesigned for portability.
4. Keep Clang/LLVM/LLD aligned with Void Rust's LLVM major.
5. Do not restore global LTO partitioning without fixing the sandbox assembly-linkage problem.
6. Run CI and inspect checksum verification, validation, compiler output, cache behavior, PGO fallback, package contents and release assets.
7. Bump `LIBREWOLF_PGO_CACHE_VERSION` when PGO inputs/workload change outside the cache key; update `SCCACHE_GHA_VERSION` if compiler-cache namespace compatibility changes.

Routine changes should be committed directly to `master`. Do not create feature branches or pull requests unless explicitly instructed otherwise.

## Upstream references

- [LibreWolf](https://librewolf.dev/)
- [LibreWolf source releases](https://librewolf.dev/librewolf/source/releases)
- [Void Linux](https://voidlinux.org/)
- [Void `void-packages`](https://github.com/void-linux/void-packages)
- [Void Firefox package](https://github.com/void-linux/void-packages/tree/master/srcpkgs/firefox)
- [Mozilla Firefox build documentation](https://firefox-source-docs.mozilla.org/build/buildsystem.html)
- [Mozilla build configuration](https://firefox-source-docs.mozilla.org/setup/configuring_build_options.html)
- [Mozilla `sccache`](https://github.com/mozilla/sccache)

