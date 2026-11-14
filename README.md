# LibreWolf for Void Linux (musl)

A custom [LibreWolf](https://librewolf.dev/) build profile for **Void Linux** `x86_64-musl`, optimized primarily for Intel Skylake processor and slow systems.

Inspired by [index-0/librewolf-void](https://github.com/index-0/librewolf-void).

## Overview

This project focuses on providing a responsive, resource-conscious LibreWolf build for:

- Intel Core i3-6100U
- Void Linux `musl`
- Systems with 4 GB RAM and traditional HDD storage.
- Native Wayland environments, with no X server.

**Compatibility:** The binary is not intended for general usages.

## Features

### Performance optimization

- `-O2 -march=skylake` for C/C++.
- Skylake-specific Rust optimization.
- Cross-language full LTO.
- Profile-Guided Optimization (PGO) for release CI builds.
- Automatic fallback to LTO-only builds when PGO generation fails.

### Memory optimization

- Reduced content-process overhead.
- Inactive-tab unloading under memory pressure.
- Fission site isolation retained.
- Reduced unnecessary process preloading.

### HDD optimization

- Disabled new-tab preloading.
- Session-store writes every 30 seconds.
- Disk-cache write buffers configured for slower storage.

These settings prioritize stability and responsiveness on the target hardware rather than maximum parallelism.

## Build configuration

| Component | Configuration |
| --- | --- |
| Operating system | Void Linux x86\\_64 musl |
| CPU target | Intel i3 6100U (Skylake) |
| Optimization | O2 |
| Display | Native Wayland |

## Design goals

This is a specialized personal build profile, not a general-purpose LibreWolf distribution.

The priorities are:

1. Responsiveness on Skylake hardware.
2. Memory stability on 4 GB systems.
3. Reduced unnecessary HDD writes.
4. Native Wayland support.

## Maintenance

When updating the upstream version:

- Update the source version and SHA-256 checksum.
- Increment the package revision for packaging-only changes.
- Review downstream patches for obsolete fixes.
- Keep Clang, LLVM, LLD, and Rust toolchain versions compatible.
- Validate CI, package contents, PGO fallback, and release artifacts.

## References

- [LibreWolf source releases](https://librewolf.dev/librewolf/source/releases)
- [FireFox in Void Packages](https://github.com/void-linux/void-packages/tree/master/srcpkgs/firefox)
- [Mozilla Firefox Build Documentation](https://firefox-source-docs.mozilla.org/build/buildsystem.html)
