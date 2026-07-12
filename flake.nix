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
        nodejs = pkgs.nodejs_22;

        # --- pin (updated by ./update.sh) ---
        version = "1.0.129";
        hash = "sha256-dSJmP5X5ixDe5s/4U/rnWh+gAx/cD5wPIEj33yfSVcM=";
        # -------------------------------------

        machine0 = pkgs.stdenv.mkDerivation {
          pname = "machine0-cli";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/@machine0/cli/-/cli-${version}.tgz";
            inherit hash;
          };

          nativeBuildInputs = [ pkgs.makeWrapper ];

          # No build/configure: the tarball is a prebuilt, dependency-free bundle.
          dontBuild = true;
          dontConfigure = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/machine0
            cp -r bin dist package.json $out/lib/machine0/
            makeWrapper ${nodejs}/bin/node $out/bin/machine0 \
              --add-flags $out/lib/machine0/bin/entry.cjs
            runHook postInstall
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
