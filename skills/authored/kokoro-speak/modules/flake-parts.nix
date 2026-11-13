# flake-parts module: the flake-level knobs and the package, plus a NixOS /
# system-manager module (`flake.nixosModules.kokoro`) whose defaults are those
# knobs. Import this module into a flake-parts flake, then list
# `config.flake.nixosModules.kokoro` in the system you want to speak.
{ config, lib, ... }:
let
  cfg = config.flake.kokoro-tts;
in
{
  options.flake.kokoro-tts = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether a system importing flake.nixosModules.kokoro gets kokoro-speak.";
    };

    voice = lib.mkOption {
      type = lib.types.str;
      default = "af_heart";
      description = "Default Kokoro voice.";
    };

    speed = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Default speaking rate multiplier.";
    };

    lang = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default espeak-ng language code, or null to derive it from the voice.";
    };

    leadSilence = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
      description = "Default seconds of silence prepended to an utterance.";
    };

    player = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default audio player command, or null to auto-detect.";
    };
  };

  config = {
    perSystem =
      { pkgs, ... }:
      let
        packages = import ../nix/package.nix { inherit pkgs; };
      in
      {
        packages = {
          inherit (packages) kokoro-python kokoro-model;
          kokoro-speak = packages.kokoro-speak;
          default = packages.kokoro-speak;
        };
      };

    flake.nixosModules.kokoro =
      { pkgs, ... }:
      {
        imports = [ ./system.nix ];

        programs.kokoro-tts = {
          enable = lib.mkDefault cfg.enable;
          voice = lib.mkDefault cfg.voice;
          speed = lib.mkDefault cfg.speed;
          lang = lib.mkDefault cfg.lang;
          leadSilence = lib.mkDefault cfg.leadSilence;
          player = lib.mkDefault cfg.player;
          # Build with the consuming system's pkgs. Importing the package here
          # avoids relying on flake-parts' internal per-system config and keeps
          # the module usable even when only `nixosModules.default` is imported.
          package = lib.mkDefault (import ../nix/package.nix { inherit pkgs; }).kokoro-speak;
        };
      };
  };
}
