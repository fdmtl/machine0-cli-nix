# machine0-cli-nix

A small, standalone [Nix flake](https://nixos.wiki/wiki/Flakes) that packages the
[machine0 CLI](https://machine0.io) (`@machine0/cli`) — no `npm` required on your
machine.

The flake fetches the prebuilt bundle straight from the public npm registry and
wraps it with a pinned Node.js. The published CLI is a single dependency-free
bundle, so this is a plain fetch-and-wrap — no `node_modules`, no build step.

## Use it

Run it once without installing:

```sh
nix run github:fdmtl/machine0-cli-nix -- --help
```

Install it into your profile:

```sh
nix profile install github:fdmtl/machine0-cli-nix
machine0 --version
```

## Import into another flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    machine0-cli.url = "git+ssh://git@github.com/fdmtl/machine0-cli-nix";
    # Or, if you have a GitHub token with access to this repo configured for Nix:
    #   machine0-cli.url = "github:fdmtl/machine0-cli-nix";
  };

  outputs = { self, nixpkgs, machine0-cli, ... }:
    let system = "aarch64-darwin"; in {
      # e.g. drop it into a devShell:
      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = [ machine0-cli.packages.${system}.default ];
      };
    };
}
```

**Auth note:** this repo is INTERNAL, so `github:fdmtl/machine0-cli-nix` needs a
GitHub token with access configured for Nix (`access-tokens` in `nix.conf`).
`git+ssh://git@github.com/fdmtl/machine0-cli-nix` uses your SSH agent instead and
works out of the box for org members.

## Updating the pinned version

The flake pins an exact published version and its tarball hash. To bump it:

```sh
./update.sh            # pin to the latest version on npm
./update.sh 1.0.130    # pin to a specific version
```

Then review the diff, commit, and push.
