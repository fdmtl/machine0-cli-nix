{
  description = "machine0 CLI — Cloud VMs from the CLI (Nix package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # --- pin (updated by ./update.sh) ---
        version = "1.0.164";
        hash = "sha256-7BLWBUZcV7l4KTwf0RvIn2+z7P1w5Q4KWAwsiA1jHdw=";
        # -------------------------------------

        # The published tarball is a self-contained bundle: no runtime
        # dependencies, no native modules, nothing to build. So this is an
        # unpack-and-wrap, not an npm build.
        #
        # It used to be a `buildNpmPackage` with a vendored package-lock.json
        # and an `npmDepsHash`, because 1.0.147-1.0.163 marked `open` and
        # `update-notifier` as `--external` and declared them as runtime
        # dependencies (fdmtl/machine0#626, a Windows path fix).
        # fdmtl/machine0#733 re-bundled both and moved them back to
        # devDependencies, keeping the `--format=esm` flag that was the part
        # of #626 actually responsible for the Windows fix.
        #
        # From 1.0.164 the dependency tree is EMPTY, and buildNpmPackage
        # cannot express that: `prefetch-npm-deps` refuses a lockfile with no
        # cacheable dependencies ("No cacheable dependencies were found"),
        # which is what made ./update.sh abort halfway and leave the pins
        # stale at 1.0.155 while reporting the new hash. Rather than set
        # `forceEmptyCache` to keep an npm builder that installs nothing,
        # drop the builder.
        #
        # If a future release reintroduces runtime dependencies this package
        # breaks LOUDLY at runtime (ERR_MODULE_NOT_FOUND on first invocation),
        # not at build time — so ./update.sh asserts the dependency tree is
        # empty on every bump.
        machine0 = pkgs.stdenvNoCC.mkDerivation {
          pname = "machine0-cli";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/@machine0/cli/-/cli-${version}.tgz";
            inherit hash;
          };

          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontBuild = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/machine0-cli $out/bin
            cp -r . $out/lib/machine0-cli
            makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/machine0 \
              --add-flags "$out/lib/machine0-cli/bin/entry.cjs"
            runHook postInstall
          '';

          # Catch a reintroduced runtime dependency at BUILD time rather than
          # on a user's first invocation. `npm pack` output is the same tree
          # this derivation installs, so an empty `.dependencies` here is
          # exactly the property the unpack-and-wrap relies on.
          doInstallCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            if ${pkgs.jq}/bin/jq -e '.dependencies | length > 0' package.json >/dev/null 2>&1; then
              echo "ERROR: @machine0/cli@${version} declares runtime dependencies:" >&2
              ${pkgs.jq}/bin/jq -r '.dependencies | keys[]' package.json >&2
              echo "This derivation unpacks the tarball with no node_modules, so those" >&2
              echo "imports would fail at runtime. Restore a dependency-aware builder." >&2
              exit 1
            fi
            runHook postInstallCheck
          '';

          meta = with pkgs.lib; {
            description = "machine0 CLI — cloud VMs from the command line";
            homepage = "https://machine0.io";
            mainProgram = "machine0";
            platforms = platforms.unix;
          };
        };
      in {
        packages.default = machine0;
        packages.machine0 = machine0;
        apps.default = { type = "app"; program = "${machine0}/bin/machine0"; };
      });
}
