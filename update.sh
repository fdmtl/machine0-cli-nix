#!/usr/bin/env bash
# Update the version + hash pin in flake.nix to a published @machine0/cli release.
#
# Usage:
#   ./update.sh            # pin to the latest version on npm
#   ./update.sh 1.0.130    # pin to a specific version
#
# Requires: nix, curl, sed. (npm is used if present, otherwise the registry
# is queried directly.)
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
echo "  $hash"

# Rewrite the two pin lines in flake.nix.
sed -i.bak -E \
  -e "s|^( *version = )\"[^\"]*\";|\1\"${version}\";|" \
  -e "s|^( *hash = )\"[^\"]*\";|\1\"${hash}\";|" \
  flake.nix
rm -f flake.nix.bak

echo
git --no-pager diff -- flake.nix || true
echo
echo "done. review the diff above, then: git commit -am \"pin ${PKG}@${version}\" && git push"
