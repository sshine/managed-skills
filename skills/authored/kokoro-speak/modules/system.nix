# The system module, shared by NixOS and numtide/system-manager.
#
# The flake-parts module in ../modules/flake-parts.nix supplies the flake-wide
# defaults. `package` is derived from the per-system cudaSupport and
# cudaArchitectures options, so a host can override either one. A host can also
# override any option here directly, which is what makes the same wrapper
# useful on a desktop and on a minimal system-manager profile.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.kokoro-tts;

  extraArgs =
    lib.optionals (cfg.lang != null) [
      "--lang"
      cfg.lang
    ]
    ++ lib.optionals (cfg.player != null) [
      "--player"
      cfg.player
    ];

  kokoro-speak = pkgs.writeShellScriptBin "kokoro-speak" ''
    exec ${cfg.package}/bin/kokoro-speak \
      --voice ${lib.escapeShellArg cfg.voice} \
      --speed ${lib.escapeShellArg (toString cfg.speed)} \
      --lead-silence ${lib.escapeShellArg (toString cfg.leadSilence)} \
      ${lib.escapeShellArgs extraArgs} \
      "$@"
  '';
in
{
  options.programs.kokoro-tts = {
    enable = lib.mkEnableOption "Kokoro-82M offline text-to-speech";

    package = lib.mkOption {
      type = lib.types.package;
      default =
        (import ../nix/package.nix {
          inherit pkgs;
          cudaSupport = cfg.cudaSupport;
          cudaArchitectures = cfg.cudaArchitectures;
          cudaOnnxRuntime = cfg.cudaOnnxRuntime;
        }).kokoro-speak;
      defaultText = lib.literalExpression ''
        (import ../nix/package.nix {
          inherit pkgs;
          cudaSupport = config.programs.kokoro-tts.cudaSupport;
          cudaArchitectures = config.programs.kokoro-tts.cudaArchitectures;
          cudaOnnxRuntime = config.programs.kokoro-tts.cudaOnnxRuntime;
        }).kokoro-speak
      '';
      description = "Package providing the kokoro-speak executable.";
    };

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Build ONNX Runtime with the CUDA execution provider. The package is
        built here rather than requiring `nixpkgs.config.cudaSupport`; the
        first build compiles ONNX Runtime and takes a while.
      '';
    };

    cudaArchitectures = lib.mkOption {
      type = lib.types.str;
      default = "75;80;86;89;120";
      description = ''
        Semicolon-separated CUDA compute capabilities to compile for, or an
        empty string to use nixpkgs' full default list. Only used when
        `cudaSupport` is true and `package` is left at its default.
      '';
    };

    cudaOnnxRuntime = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        A prebuilt Python `onnxruntime` package with CUDA support. When set,
        the package default uses it instead of compiling ONNX Runtime, which
        is the difference between a fast rebuild and roughly an hour of nvcc.
      '';
    };

    voice = lib.mkOption {
      type = lib.types.str;
      default = "af_heart";
      description = ''
        Kokoro voice. The first letter selects the language: af_heart is
        American English, bf_emma is British, zm_yunyang is Mandarin.
      '';
    };

    speed = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Speaking rate multiplier, 0.5 to 2.0.";
    };

    lang = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        espeak-ng language code. When null it is derived from the first letter
        of `voice`, which is right for every stock Kokoro voice.
      '';
    };

    leadSilence = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
      description = "Seconds of silence prepended to the utterance.";
    };

    player = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Audio player command. When null kokoro-speak tries pw-play, paplay,
        aplay, ffplay and mpv, in that order.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ kokoro-speak ];
  };
}
