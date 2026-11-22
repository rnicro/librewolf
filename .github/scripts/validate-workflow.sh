#!/usr/bin/env bash
set -euo pipefail

workflow=${1:?workflow path required}
[ -f "$workflow" ] || {
  echo "workflow file not found: $workflow" >&2
  exit 1
}

push_section="$(sed -n '/^  push:/,/^  workflow_dispatch:/p' "$workflow")"
for expected in '    tags:' "      - '*-r*'"; do
  printf '%s\n' "$push_section" | grep -Fq "$expected" || {
    echo "automatic push trigger is missing required version/revision-tag filter: $expected" >&2
    exit 1
  }
done
if printf '%s\n' "$push_section" | grep -Eq '^[[:space:]]+branches(-ignore)?:'; then
  echo "branch pushes must not trigger automatic builds" >&2
  exit 1
fi

grep -Fq "default: false" "$workflow" || {
  echo "manual release-publication input must default to false" >&2
  exit 1
}

if grep -Fq 'inputs.pgo' "$workflow"; then
  echo "PGO must not be a manual opt-in; all builds must enable it" >&2
  exit 1
fi
grep -Fq 'pgo_options=(-o pgo)' "$workflow" || {
  echo "every workflow build must explicitly enable PGO" >&2
  exit 1
}
pgo_cache_count=$(grep -F -c 'path: void-packages/hostdir/pgo-cache' "$workflow")
[ "$pgo_cache_count" -eq 2 ] || {
  echo "PGO profile cache must be restored and saved for all build events" >&2
  exit 1
}

grep -Fq "github.ref_type == 'tag'" "$workflow" || {
  echo "automatic release publishing must be restricted to tag pushes" >&2
  exit 1
}
grep -Fq "inputs.publish_release)" "$workflow" || {
  echo "manual release publication must remain explicit" >&2
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
  'name: protect existing release package' \
  'cmp -s "$package" "$previous"' \
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
