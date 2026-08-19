{
  description = "ant0no's personal package set";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # Matches the platforms the-flake actually configures.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Consumers get every package in ./pkgs as `pkgs.<name>`.
      overlays.default = import ./overlay.nix;

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
            }
          );
        in
        lib.getAttrs names extended // { default = extended.deplexity; }
      );

      # `nix flake check` builds every package for the current system.
      checks = self.packages;

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
