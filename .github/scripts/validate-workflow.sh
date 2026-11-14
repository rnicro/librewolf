#!/usr/bin/env bash
set -euo pipefail

workflow=${1:?workflow path required}
[ -f "$workflow" ] || {
  echo "workflow file not found: $workflow" >&2
  exit 1
}

awk '
  /^  push:/ { in_push = 1 }
  /^  workflow_dispatch:/ { in_push = 0 }
  in_push && /^    tags:$/ { saw_tags = 1 }
  in_push && /^    branches:$/ { saw_branches = 1 }
  END { exit !(saw_tags && !saw_branches) }
' "$workflow" || {
  echo "automatic builds must be restricted to tag pushes, not branch pushes" >&2
  exit 1
}
grep -Fq "      - '*-r*'" "$workflow" || {
  echo "automatic builds must accept only version/revision release-tag patterns" >&2
  exit 1
}

grep -Fq "default: false" "$workflow" || {
  echo "manual PGO dispatch must default to the LTO-only baseline" >&2
  exit 1
}

pgo_gate_count=$(grep -F -o "github.event_name == 'workflow_dispatch' && inputs.pgo" "$workflow" | wc -l)
[ "$pgo_gate_count" -eq 4 ] || {
  echo "PGO cache, build, and profile-save steps must be manual opt-in only (found $pgo_gate_count gates)" >&2
  exit 1
}

grep -Fq "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/')" "$workflow" || {
  echo "release publishing must be restricted to tag pushes" >&2
  exit 1
}

grep -Fq 'packages=(librewolf-*.xbps)' "$workflow" || {
  echo "build staging must include LibreWolf packages only" >&2
  exit 1
}

publish_line=$(grep -n '^  publish:' "$workflow" | cut -d: -f1)
sign_line=$(grep -n 'name: sign XBPS repository' "$workflow" | cut -d: -f1)
[ -n "$publish_line" ] && [ -n "$sign_line" ] && [ "$sign_line" -gt "$publish_line" ] || {
  echo "XBPS signing must run in the separate publish job, never in the browser build job" >&2
  exit 1
}

build_section=$(sed '/^  publish:/,$d' "$workflow")
if printf '%s\n' "$build_section" | grep -Eq 'secrets\.(PRIV_KEY|SIGN_PASS)'; then
  echo "private signing credentials must not be exposed to the build job" >&2
  exit 1
fi

grep -Fq 'xbps-rindex -a "${packages[@]}"' "$workflow" || {
  echo "publish job must add the built package to the XBPS index" >&2
  exit 1
}
grep -Fq 'xbps-rindex -s --signedby "$SIGNEDBY" --privkey "$key_file" "$PWD"' "$workflow" || {
  echo "publish job must sign the XBPS repository index" >&2
  exit 1
}
grep -Fq 'xbps-rindex -S --privkey "$key_file" "${packages[@]}"' "$workflow" || {
  echo "publish job must sign the XBPS package archives" >&2
  exit 1
}
grep -Fq 'xbps-rindex -c "$PWD"' "$workflow" || {
  echo "publish job must validate/clean XBPS repository metadata" >&2
  exit 1
}
grep -Fq 'assets=(./*.xbps ./*.xbps.sig2 ./*-repodata* ./SHA256SUMS)' "$workflow" || {
  echo "release upload must include packages, signatures, repository metadata, and checksums" >&2
  exit 1
}
if grep -Eq '^[[:space:]]*uses: actions/[^[:space:]@]+@v[0-9]+' "$workflow"; then
  echo "GitHub Actions must be pinned to immutable commit SHAs" >&2
  exit 1
fi

printf 'validated: %s\n' "$workflow"
