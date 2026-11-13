{
  description = "Kokoro-82M offline text-to-speech, packaged for NixOS and system-manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ./modules/flake-parts.nix ];

      # Kokoro's espeakng-loader ships an x86_64 Linux wheel only.
      systems = [ "x86_64-linux" ];

      # Consume this as `inputs.kokoro-speak.flakeModules.default` in another
      # flake-parts flake, then add `config.flake.nixosModules.kokoro` to the
      # system that should speak.
      flake.flakeModules.default = ./modules/flake-parts.nix;

      # For a consumer that does not use flake-parts. The package is built with
      # the consumer's own pkgs, so this does not pull in a second nixpkgs.
      flake.nixosModules.default =
        {
          pkgs,
          lib,
          ...
        }:
        {
          imports = [ ./modules/system.nix ];

          programs.kokoro-tts = {
            enable = lib.mkDefault true;
            package = lib.mkDefault (import ./nix/package.nix { inherit pkgs; }).kokoro-speak;
          };
        };
    };
}
