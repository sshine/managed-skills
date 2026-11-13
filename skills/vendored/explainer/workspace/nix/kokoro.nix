# Kokoro-82M text-to-speech: the Python environment and the model weights.
#
# kokoro-onnx and espeakng-loader are not in nixpkgs and phonemizer there is
# still 3.3.0, which lacks the EspeakWrapper.set_data_path that kokoro-onnx
# calls. All three are pure wheels, so they are built here instead of in a pip
# venv; onnxruntime, numpy and soundfile stay nixpkgs builds because those are
# the native ones.
{
  perSystem =
    { pkgs, ... }:
    let
      python = pkgs.python3;
      pyPkgs = python.pkgs;

      espeakng-loader = pyPkgs.buildPythonPackage {
        pname = "espeakng_loader";
        version = "0.2.4";
        format = "wheel";
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/py3/e/espeakng_loader/espeakng_loader-0.2.4-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
          hash = "sha256-CHIbryfRPUYfa+bu2aZSd+cNaCNP9IT9i5iXsiLNy20=";
        };
        doCheck = false;
      };

      # The bundled espeak-ng the wheel carries is never loaded: tts.py points
      # phonemizer at the nix build through EspeakConfig.
      phonemizer = pyPkgs.phonemizer.overridePythonAttrs (old: rec {
        # The nixpkgs derivation patches hardcoded espeak paths into 3.3.0; the
        # patch does not apply here and is not needed, because the espeak
        # library and data are named explicitly at every call site.
        patches = [ ];
        version = "3.4.0";
        src = pkgs.fetchPypi {
          pname = "phonemizer";
          inherit version;
          hash = "sha256-4TIxmAxQvGcewEZjeboCcmCtnWGSmVLYrpZls9DyUes=";
        };
        doCheck = false;
      });

      kokoro-onnx = pyPkgs.buildPythonPackage {
        pname = "kokoro_onnx";
        version = "0.6.1";
        format = "wheel";
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/py3/k/kokoro_onnx/kokoro_onnx-0.6.1-py3-none-any.whl";
          hash = "sha256-UMjeSVDWAd9BQo7lRipIyKeL70Qb9nHySS4HDvRNijI=";
        };
        propagatedBuildInputs = [
          espeakng-loader
          phonemizer
          pyPkgs.numpy
          pyPkgs.onnxruntime
        ];
        doCheck = false;
      };
    in
    {
      # cmudict is not a Kokoro dependency: lib/pronounce.py reads it as the
      # reference lexicon for deciding which words it cannot vouch for.
      packages.kokoro-python = python.withPackages (_: [
        kokoro-onnx
        pyPkgs.cmudict
        pyPkgs.numpy
        pyPkgs.soundfile
      ]);

      # Weights and voice pack, fetched once into the store and read from there
      # rather than copied into the workspace.
      packages.kokoro-model =
        let
          base = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0";
        in
        pkgs.runCommand "kokoro-82m-v1.0" { } ''
          mkdir -p $out
          cp ${
            pkgs.fetchurl {
              url = "${base}/kokoro-v1.0.onnx";
              hash = "sha256-fV347PfUsYeAFaMmhgU/0O6+K8N3I0YIdkzA7zY2psU=";
            }
          } $out/kokoro-v1.0.onnx
          cp ${
            pkgs.fetchurl {
              url = "${base}/voices-v1.0.bin";
              hash = "sha256-vKYQuDCOjZnzLm/kGX5+wBZ5Jk7+0MrJFA/pwp8fv30=";
            }
          } $out/voices-v1.0.bin
        '';
    };
}
