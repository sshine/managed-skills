# Kokoro-82M text-to-speech: the Python environment, the model weights, and a
# pipe-friendly `kokoro-speak` wrapper.
#
# This is the package side. It is deliberately independent of NixOS and
# system-manager; the module in ../modules/system.nix installs it and changes
# the defaults. The wheels that nixpkgs does not carry are built here, while
# onnxruntime, numpy and soundfile stay nixpkgs builds because those are the
# native ones.
{ pkgs }:
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

  # nixpkgs already carries phonemizer 3.4.0, but its derivation patches
  # hardcoded espeak paths from the 3.3.0 era. kokoro-onnx only needs the
  # library at call time, which kokoro-speak passes through EspeakConfig, so
  # the patch is dropped and the PyPI source is used directly.
  phonemizer = pyPkgs.phonemizer.overridePythonAttrs (old: rec {
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

  kokoro-python = python.withPackages (_: [
    kokoro-onnx
    pyPkgs.numpy
    pyPkgs.soundfile
  ]);

  # Weights and voice pack, fetched once into the store and read from there.
  kokoro-model =
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

  kokoro-speak = pkgs.writeShellApplication {
    name = "kokoro-speak";
    runtimeInputs = [
      kokoro-python
      pkgs.pipewire
      pkgs.alsa-utils
      pkgs.ffmpeg
    ];
    text = ''
      export KOKORO_MODEL_DIR="${kokoro-model}"
      export ESPEAK_LIBRARY="${pkgs.espeak-ng}/lib/libespeak-ng.so"
      export ESPEAK_DATA_PATH="${pkgs.espeak-ng}/share/espeak-ng-data"
      export PHONEMIZER_ESPEAK_LIBRARY="${pkgs.espeak-ng}/lib/libespeak-ng.so"
      exec ${kokoro-python}/bin/python3 ${../bin/kokoro-speak} "$@"
    '';
  };
in
{
  inherit kokoro-python kokoro-model kokoro-speak;
}
