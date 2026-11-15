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

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Build ONNX Runtime with the CUDA execution provider.";
    };

    cudaArchitectures = lib.mkOption {
      type = lib.types.str;
      default = "75;80;86;89;120";
      description = "CUDA compute capabilities to compile for; empty means nixpkgs' full list.";
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
        packages = import ../nix/package.nix {
          inherit pkgs;
          cudaSupport = cfg.cudaSupport;
          cudaArchitectures = cfg.cudaArchitectures;
        };
      in
      {
        packages = {
          inherit (packages)
            kokoro-python
            kokoro-python-cpu
            kokoro-python-cuda
            kokoro-model
            kokoro-speak-cuda
            kokoro-bench-cuda
            ;
          kokoro-speak = packages.kokoro-speak;
          kokoro-speak-cpu = packages.kokoro-speak-cpu;
          kokoro-bench = packages.kokoro-bench;
          kokoro-bench-cpu = packages.kokoro-bench-cpu;
          default = packages.kokoro-speak;
        };
      };

    flake.nixosModules.kokoro =
      { ... }:
      {
        imports = [ ./system.nix ];

        programs.kokoro-tts = {
          enable = lib.mkDefault cfg.enable;
          cudaSupport = lib.mkDefault cfg.cudaSupport;
          cudaArchitectures = lib.mkDefault cfg.cudaArchitectures;
          voice = lib.mkDefault cfg.voice;
          speed = lib.mkDefault cfg.speed;
          lang = lib.mkDefault cfg.lang;
          leadSilence = lib.mkDefault cfg.leadSilence;
          player = lib.mkDefault cfg.player;
          # `package` is left alone: the system module's default follows the
          # per-system cudaSupport/cudaArchitectures, so a host can override
          # the flake defaults without the package staying stale.
        };
      };
  };
}
