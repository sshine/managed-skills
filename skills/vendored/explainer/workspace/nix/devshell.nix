# The one devshell: every tool the pipeline shells out to, pinned by flake.lock.
{ inputs, ... }:
{
  imports = [ inputs.devshell.flakeModule ];

  perSystem =
    { config, pkgs, ... }:
    let
      # Headless Chromium renders the scene pages; text must come out identical
      # regardless of what fonts the host happens to have, so the shell hands it
      # a fontconfig file listing only these.
      fonts = [
        pkgs.inter
        pkgs.jetbrains-mono
        pkgs.dejavu_fonts
        pkgs.liberation_ttf
        # Chinese scenes render as tofu without a CJK face on the list.
        pkgs.noto-fonts-cjk-sans
        pkgs.noto-fonts-cjk-serif
      ];
    in
    {
      devshells.default = {
        devshell.name = "explainer";

        packages = [
          config.packages.kokoro-python
          pkgs.chromium
          pkgs.espeak-ng
          pkgs.ffmpeg-full
          pkgs.imagemagick
          pkgs.jq
          pkgs.nodejs_24
        ];

        commands = [
          {
            package = pkgs.just;
            category = "workspace";
          }
        ];

        env = [
          {
            name = "CHROMIUM_BIN";
            value = "${pkgs.chromium}/bin/chromium";
          }
          {
            name = "FONTCONFIG_FILE";
            value = pkgs.makeFontsConf { fontDirectories = fonts; };
          }
          {
            name = "KOKORO_MODEL_DIR";
            value = "${config.packages.kokoro-model}";
          }
          # phonemizer would otherwise reach for the manylinux libespeak-ng
          # bundled in the espeakng-loader wheel, which the nix loader cannot
          # open. Point every lookup at the nix build instead.
          {
            name = "ESPEAK_LIBRARY";
            value = "${pkgs.espeak-ng}/lib/libespeak-ng.so";
          }
          {
            name = "ESPEAK_DATA_PATH";
            value = "${pkgs.espeak-ng}/share/espeak-ng-data";
          }
          {
            name = "PHONEMIZER_ESPEAK_LIBRARY";
            value = "${pkgs.espeak-ng}/lib/libespeak-ng.so";
          }
        ];
      };
    };
}
