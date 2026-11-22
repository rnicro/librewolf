#!/usr/bin/env bash
set -euo pipefail

workflow=${1:?workflow path required}
[ -f "$workflow" ] || {
  echo "workflow file not found: $workflow" >&2
  exit 1
}

push_section="$(sed -n '/^  push:/,/^  workflow_dispatch:/p' "$workflow")"
for expected in '    branches:' '      - main' '    tags:' "      - '*-r*'"; do
  printf '%s\n' "$push_section" | grep -Fq "$expected" || {
    echo "push trigger is missing required main-branch or version/revision-tag filter: $expected" >&2
    exit 1
  }
done

grep -Fq "default: false" "$workflow" || {
  echo "manual PGO and release-publication inputs must default to false" >&2
  exit 1
}

pgo_gate_count=$(grep -F -o "github.event_name == 'workflow_dispatch' && inputs.pgo" "$workflow" | wc -l)
[ "$pgo_gate_count" -eq 4 ] || {
  echo "PGO cache, build, and profile-save steps must be manual opt-in only (found $pgo_gate_count gates)" >&2
  exit 1
}

grep -Fq "github.ref_type == 'tag'" "$workflow" || {
  echo "automatic release publishing must be restricted to tag pushes" >&2
  exit 1
}
grep -Fq "inputs.publish_release && !inputs.pgo" "$workflow" || {
  echo "manual release publication must be explicit and mutually exclusive with PGO" >&2
  exit 1
}

publish_section="$(sed -n '/^  publish:/,$p' "$workflow")"
build_section="$(sed '/^  publish:/,$d' "$workflow")"
if printf '%s\n' "$build_section" | grep -Eq 'secrets\.(PRIV_KEY|SIGN_PASS)'; then
  echo "private signing credentials must not be exposed to the build job" >&2
  exit 1
fi

for permission in 'contents: write' 'id-token: write' 'attestations: write'; do
  printf '%s\n' "$publish_section" | grep -Fq "$permission" || {
    echo "publish job is missing required permission: $permission" >&2
    exit 1
  }
done

for required in \
  'secrets.PRIV_KEY' \
  'secrets.SIGN_PASS' \
  'vars.SIGNEDBY' \
  'bash ../.github/scripts/sign-xbps-repository.sh' \
  'uses: actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6' \
  'subject-path: binpkgs/librewolf-*.xbps' \
  'gh release upload "$TAG" --clobber'; do
  printf '%s\n' "$publish_section" | grep -Fq "$required" || {
    echo "publish job is missing required release integration: $required" >&2
    exit 1
  }
done

sign_script="$(cd "$(dirname "$workflow")/../scripts" && pwd)/sign-xbps-repository.sh"
[ -s "$sign_script" ] || {
  echo "signed XBPS repository helper is missing: $sign_script" >&2
  exit 1
}
bash -n "$sign_script"

if grep -Eq '^[[:space:]]*uses: actions/[^[:space:]@]+@v[0-9]+' "$workflow"; then
  echo "GitHub Actions must be pinned to immutable commit SHAs" >&2
  exit 1
fi

printf 'validated: %s\n' "$workflow"
