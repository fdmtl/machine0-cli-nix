#!/usr/bin/env bash
# Update the version + hash pins in flake.nix to a published @machine0/cli release.
#
# Usage:
#   ./update.sh            # pin to the latest version on npm
#   ./update.sh 1.0.130    # pin to a specific version
#
# Rewrites three pins in flake.nix (version, tarball hash, npmDepsHash) and
# regenerates package-lock.json for the CLI's runtime dependencies.
#
# Requires: nix, curl, sed, jq, npm.
set -euo pipefail

cd "$(dirname "$0")"

PKG="@machine0/cli"
REGISTRY="https://registry.npmjs.org"

resolve_latest() {
  if command -v npm >/dev/null 2>&1; then
    npm view "$PKG" version
  else
    curl -fsSL "$REGISTRY/$PKG/latest" \
      | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
  fi
}

version="${1:-$(resolve_latest)}"
if [ -z "$version" ]; then
  echo "error: could not determine version" >&2
  exit 1
fi

url="$REGISTRY/$PKG/-/cli-${version}.tgz"
echo "pinning $PKG@$version"
echo "  $url"

# Prefer the modern `nix store prefetch-file`; fall back to nix-prefetch-url.
if hash="$(nix store prefetch-file --json "$url" 2>/dev/null | sed -n 's/.*"hash":"\([^"]*\)".*/\1/p')" && [ -n "$hash" ]; then
  :
else
  raw="$(nix-prefetch-url "$url")"
  hash="$(nix hash to-sri --type sha256 "$raw")"
fi

if [ -z "$hash" ]; then
  echo "error: could not compute hash" >&2
  exit 1
fi
echo "  hash: $hash"

# Assert the release is dependency-free.
#
# The flake unpacks the tarball and wraps bin/entry.cjs with node — there is
# no npm install and therefore no node_modules. A release that declares
# runtime dependencies would build fine here and then die on the user's first
# invocation with ERR_MODULE_NOT_FOUND. That is not hypothetical: 1.0.147
# through 1.0.163 externalised `open` and `update-notifier` out of the bundle
# (fdmtl/machine0#626) and shipped exactly that failure to every consumer
# packaging the tarball directly. 1.0.164 re-bundled them
# (fdmtl/machine0#733).
#
# Fail loudly rather than pinning a version this flake cannot actually run.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL "$url" | tar xz -C "$tmpdir"
# Both `dependencies` and `optionalDependencies` are installed by a normal
# `npm i -g`, so both would be missing from this unpacked tree.
ndeps="$(jq '((.dependencies // {}) + (.optionalDependencies // {})) | length' "$tmpdir/package/package.json")"
if [ "$ndeps" != "0" ]; then
  echo "error: @machine0/cli@${version} declares ${ndeps} runtime dependencies:" >&2
  jq -r '((.dependencies // {}) + (.optionalDependencies // {})) | keys[]' "$tmpdir/package/package.json" >&2
  echo >&2
  echo "This flake unpacks the tarball with no node_modules, so those imports" >&2
  echo "would fail at runtime. Either the release regressed (see" >&2
  echo "fdmtl/machine0#626 / #733), or the flake needs a dependency-aware" >&2
  echo "builder again. Refusing to pin." >&2
  exit 1
fi
echo "  dependencies: none (bundle is self-contained)"

# Rewrite the two pin lines in flake.nix.
sed -i.bak -E \
  -e "s|^( *version = )\"[^\"]*\";|\1\"${version}\";|" \
  -e "s|^( *hash = )\"[^\"]*\";|\1\"${hash}\";|" \
  flake.nix
rm -f flake.nix.bak

echo
git --no-pager diff -- flake.nix || true
echo
echo "done. review the diff above, then: git add flake.nix && git commit -m \"pin ${PKG}@${version}\" && git push"
