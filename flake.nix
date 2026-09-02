{
  description = "antono's personal package set";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # Only for tolaria: a pinned Rust toolchain (fenix) and the Rust builder
    # (crane) its Tauri package is written against. Packages that need nothing
    # beyond nixpkgs should stay that way.
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";

    # Composed with, not forked: sneg's MCP servers plug into upstream's module
    # system, and `lib.mkConfig` here can enable servers from either side.
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      # Matches the platforms my personal flake actually configures.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Consumers get every package in ./pkgs as `pkgs.<name>`.
      overlays.default = import ./overlay.nix inputs;

      # Just the MCP servers, for extending the nixpkgs instance passed to
      # mcp-servers-nix' own `lib.mkConfig`. `lib.mkConfig` below applies it.
      overlays.mcp-servers = final: prev: import ./pkgs/mcp-servers { inherit final prev; };

      # `mkConfig`, `evalModule` and `serverModules` — see ./lib/default.nix.
      lib = import ./lib {
        inherit (inputs) mcp-servers-nix;
        overlay = self.overlays.mcp-servers;
      };

      # Drop-in superset of mcp-servers-nix' own home-manager module: feeds
      # `mcp-servers.programs.<name>` into home-manager's programs.mcp.servers.
      homeManagerModules.default = import ./modules/home-manager.nix { snegLib = self.lib; };

      packages = forAllSystems (
        pkgs:
        let
          # Read the packages back out of the overlay's fixed point, so one
          # package may depend on another from this set. The second call is
          # used only for its attribute *names* — the derivations under them
          # are never forced, so there is no circularity here.
          extended = pkgs.extend self.overlays.default;
          names = lib.attrNames (
            import ./pkgs {
              final = pkgs;
              prev = pkgs;
              inherit inputs;
            }
          );
        in
        lib.getAttrs names extended // { default = extended.deplexity; }
      );

      # `nix flake check` builds every package for the current system, plus the
      # composed MCP config, which is where module-level mistakes surface.
      checks = forAllSystems (
        pkgs:
        self.packages.${pkgs.stdenv.hostPlatform.system}
        // {
          mcp-servers = import ./tests/mcp-servers.nix {
            inherit pkgs;
            snegLib = self.lib;
          };
          mcp-home-manager = import ./tests/home-manager.nix {
            inherit pkgs;
            snegLib = self.lib;
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nix-update
            pkgs.nix-init
            pkgs.nixfmt-tree
          ];
        };
      });
    };
}
