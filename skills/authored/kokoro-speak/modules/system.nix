# The system module, shared by NixOS and numtide/system-manager.
#
# The flake-parts module in ../modules/flake-parts.nix supplies `package` and
# changes the defaults from flake settings. A host can override any option here
# directly, which is what makes the same wrapper useful on a desktop and on a
# minimal system-manager profile.
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.kokoro-tts;

  extraArgs =
    lib.optionals (cfg.lang != null) [ "--lang" cfg.lang ]
    ++ lib.optionals (cfg.player != null) [ "--player" cfg.player ];

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
      description = "Package providing the kokoro-speak executable.";
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
