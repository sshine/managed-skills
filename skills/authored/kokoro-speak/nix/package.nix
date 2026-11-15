# Kokoro-82M text-to-speech: the Python environment, the model weights, and a
# pipe-friendly `kokoro-speak` wrapper.
#
# This is the package side. It is deliberately independent of NixOS and
# system-manager; the module in ../modules/system.nix installs it and changes
# the defaults. The wheels that nixpkgs does not carry are built here, while
# onnxruntime, numpy and soundfile stay nixpkgs builds because those are the
# native ones.
#
# `cudaSupport = true` builds one CUDA-enabled onnxruntime and feeds it to the
# Python bindings, rather than asking the consumer to rebuild all of nixpkgs
# with `config.cudaSupport = true`. Kokoro-82M is small enough that the CUDA
# execution provider wins on long text and loses a little to launch overhead on
# one short sentence; see ../BENCHMARK.md.
{
  pkgs,
  cudaSupport ? false,
  # A prebuilt Python `onnxruntime` package with CUDA. When set, the expensive
  # ONNX Runtime compile is skipped; the package must be importable as
  # `onnxruntime` and built for this Python minor version.
  cudaOnnxRuntime ? null,
  # Consumer GPUs, not data-centre parts. Building for every architecture in
  # nixpkgs' default costs a lot of nvcc time; override this if you need
  # another one (for example "89" for Ada or "120" for Blackwell).
  cudaArchitectures ? "75;80;86;89;120",
}:
let
  python = pkgs.python3;
  pyPkgs = python.pkgs;

  # NCCL, TensorRT and OpenVINO are inference-server features. Leaving them
  # out keeps the closure and the build smaller; the CUDA execution provider
  # needs only the CUDA runtime, cuBLAS, cuDNN and cuFFT.
  cudaPackages = pkgs.cudaPackages // {
    flags = pkgs.cudaPackages.flags // {
      cmakeCudaArchitecturesString =
        if cudaArchitectures == "" then
          pkgs.cudaPackages.flags.cmakeCudaArchitecturesString
        else
          cudaArchitectures;
    };
    # ONNX Runtime only needs the header-only cudnn-frontend for its
    # find_package check. The samples and tests are extra outputs that add
    # tens of minutes of C++ compilation to a first build.
    cudnn-frontend = pkgs.cudaPackages.cudnn-frontend.override {
      withSamples = false;
      withTests = false;
    };
  };

  cudaOnnxRuntimeBuilt = pkgs.onnxruntime.override {
    inherit cudaPackages;
    cudaSupport = true;
    ncclSupport = false;
    tensorrtSupport = false;
    openvinoSupport = false;
  };

  # The Python bindings are a separate derivation that takes the non-Python
  # onnxruntime's wheel as its source. Swapping that argument is how the CUDA
  # build reaches `import onnxruntime` without rebuilding the whole package
  # set with config.cudaSupport. An externally supplied package, such as one
  # built from a prebuilt wheel, replaces the whole compile.
  cudaOnnxRuntimePackage =
    if cudaOnnxRuntime != null then
      cudaOnnxRuntime
    else
      pyPkgs.onnxruntime.override { onnxruntime = cudaOnnxRuntimeBuilt; };

  mkOnnxRuntime = cuda: if cuda then cudaOnnxRuntimePackage else pyPkgs.onnxruntime;

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

  mkKokoroOnnx =
    cuda:
    pyPkgs.buildPythonPackage {
      pname = "kokoro_onnx";
      version = "0.6.1";
      format = "wheel";
      src = pkgs.fetchurl {
        url = "https://files.pythonhosted.org/packages/py3/k/kokoro_onnx/kokoro_onnx-0.6.1-py3-none-any.whl";
        hash = "sha256-UMjeSVDWAd9BQo7lRipIyKeL70Qb9nHySS4HDvRNijI=";
      };
      # The CUDA build keeps the same Python package name. kokoro-onnx only
      # auto-selects an accelerated provider when it sees a distribution named
      # onnxruntime-gpu, so the wrapper names the provider with ONNX_PROVIDER.
      propagatedBuildInputs = [
        espeakng-loader
        phonemizer
        pyPkgs.numpy
        (mkOnnxRuntime cuda)
      ];
      # The prebuilt ONNX Runtime wheel is distributed as `onnxruntime-gpu`,
      # while kokoro-onnx declares a dependency on `onnxruntime`. The module
      # is present either way; only the metadata name differs.
      dontCheckRuntimeDeps = true;
      doCheck = false;
    };

  mkKokoroPython =
    cuda:
    python.withPackages (_: [
      (mkKokoroOnnx cuda)
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

  mkKokoroEnv = cuda: ''
    export KOKORO_MODEL_DIR="${kokoro-model}"
    export ESPEAK_LIBRARY="${pkgs.espeak-ng}/lib/libespeak-ng.so"
    export ESPEAK_DATA_PATH="${pkgs.espeak-ng}/share/espeak-ng-data"
    export PHONEMIZER_ESPEAK_LIBRARY="${pkgs.espeak-ng}/lib/libespeak-ng.so"
    ${
      if cuda then
        ''
          # ONNX Runtime dlopens libcuda; on NixOS it lives with the driver
          # rather than in the CUDA runtime closure. The prebuilt wheel also
          # dlopens libcudnn by its unversioned name, which is not on the
          # default loader path.
          export LD_LIBRARY_PATH="${
            pkgs.lib.makeLibraryPath (
              with cudaPackages;
              [
                cudnn
                libcublas
                libcurand
                libcufft
                cuda_cudart
                cuda_nvrtc
              ]
            )
          }:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          # kokoro-onnx sees the plain `onnxruntime` distribution name, not
          # `onnxruntime-gpu`, so it would choose CPU by itself.
          export ONNX_PROVIDER="CUDAExecutionProvider"
        ''
      else
        ""
    }
  '';

  mkKokoroSpeak =
    cuda:
    pkgs.writeShellApplication {
      name = "kokoro-speak";
      runtimeInputs = [
        (mkKokoroPython cuda)
        pkgs.pipewire
        pkgs.alsa-utils
        pkgs.ffmpeg
      ];
      text = ''
        ${mkKokoroEnv cuda}
        exec ${mkKokoroPython cuda}/bin/python3 ${../bin/kokoro-speak} "$@"
      '';
    };

  mkKokoroBench =
    cuda:
    pkgs.writeShellApplication {
      name = "kokoro-bench";
      runtimeInputs = [ (mkKokoroPython cuda) ];
      text = ''
        ${mkKokoroEnv cuda}
        exec ${mkKokoroPython cuda}/bin/python3 ${../bench/bench.py} "$@"
      '';
    };

  cpu = {
    onnxruntime = mkOnnxRuntime false;
    kokoro-python = mkKokoroPython false;
    kokoro-speak = mkKokoroSpeak false;
    kokoro-bench = mkKokoroBench false;
  };

  cuda = {
    onnxruntime = mkOnnxRuntime true;
    kokoro-python = mkKokoroPython true;
    kokoro-speak = mkKokoroSpeak true;
    kokoro-bench = mkKokoroBench true;
  };

  selected = if cudaSupport then cuda else cpu;
in
{
  inherit kokoro-model;
  inherit (selected)
    onnxruntime
    kokoro-python
    kokoro-speak
    kokoro-bench
    ;
  kokoro-speak-cpu = cpu.kokoro-speak;
  kokoro-speak-cuda = cuda.kokoro-speak;
  kokoro-python-cpu = cpu.kokoro-python;
  kokoro-python-cuda = cuda.kokoro-python;
  kokoro-bench-cpu = cpu.kokoro-bench;
  kokoro-bench-cuda = cuda.kokoro-bench;
}
