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
  in_push && /^    branches:/ { saw_branches = 1 }
  in_push && /^      - main$/ { saw_main = 1 }
  in_push && /^      - master$/ { saw_master = 1 }
  END { exit !(saw_branches && saw_main && !saw_master) }
' "$workflow" || {
  echo "automatic builds must trigger on the main branch, not master" >&2
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

grep -Fq "github.event_name == 'push' && github.ref == 'refs/heads/main'" "$workflow" || {
  echo "release publishing must be restricted to pushes on main" >&2
  exit 1
}

grep -Fq "packages=(librewolf-*.xbps)" "$workflow" || {
  echo "release staging must include LibreWolf packages only" >&2
  exit 1
}
grep -Fq "sha256sum ./*.xbps > SHA256SUMS" "$workflow" || {
  echo "release staging must generate package SHA256SUMS" >&2
  exit 1
}
if grep -Eq '^[[:space:]]*uses: actions/[^[:space:]@]+@v[0-9]+' "$workflow"; then
  echo "GitHub Actions must be pinned to immutable commit SHAs" >&2
  exit 1
fi

printf 'validated: %s\n' "$workflow"
