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

# Regenerate the lockfile for the runtime deps. The published package.json
# carries devDependencies with bun `workspace:*` refs npm cannot parse, so
# strip them first — mirroring the postPatch in flake.nix.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL "$url" | tar xz -C "$tmpdir"
(
  cd "$tmpdir/package"
  jq 'del(.devDependencies)' package.json > package.json.tmp
  mv package.json.tmp package.json
  npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null
)
cp "$tmpdir/package/package-lock.json" package-lock.json

# Compute the npm deps hash for the new lockfile.
if command -v prefetch-npm-deps >/dev/null 2>&1; then
  deps_hash="$(prefetch-npm-deps package-lock.json 2>/dev/null | tail -1)"
else
  deps_hash="$(nix --extra-experimental-features 'nix-command flakes' \
    run nixpkgs#prefetch-npm-deps -- package-lock.json 2>/dev/null | tail -1)"
fi

if [ -z "$deps_hash" ]; then
  echo "error: could not compute npmDepsHash" >&2
  exit 1
fi
echo "  npmDepsHash: $deps_hash"

# Rewrite the three pin lines in flake.nix. The `hash` pattern is anchored so
# it cannot match the `npmDepsHash` line.
sed -i.bak -E \
  -e "s|^( *version = )\"[^\"]*\";|\1\"${version}\";|" \
  -e "s|^( *hash = )\"[^\"]*\";|\1\"${hash}\";|" \
  -e "s|^( *npmDepsHash = )\"[^\"]*\";|\1\"${deps_hash}\";|" \
  flake.nix
rm -f flake.nix.bak

echo
git --no-pager diff -- flake.nix || true
git --no-pager diff --stat -- package-lock.json || true
echo
echo "done. review the diff above, then: git add flake.nix package-lock.json && git commit -m \"pin ${PKG}@${version}\" && git push"
