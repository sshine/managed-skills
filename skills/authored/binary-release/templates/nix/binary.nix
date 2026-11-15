# Prebuilt release binaries, for consumers who want example without a Rust toolchain
# entering their build closure.
#
# The pinned version deliberately trails Cargo.toml: it names the last tag whose
# artifacts are published, not whatever the working tree happens to claim. Bump it
# once a tag's Release workflow has finished; `just release-hashes <tag>` prints the
# values.
#
# The hashes are of the tarballs the release publishes, so they can be checked against
# the .sha256 assets rather than taken on faith. Systems absent from `hashes` do not get
# the package, which is what keeps it off Darwin when the release builds only Linux.
#
# The values below are lib.fakeHash on purpose: the first `nix build .#example-bin`
# fails with the real hash in the mismatch message, which is the intended way to fill
# them in before the first tag exists. Replace both as soon as `just release-hashes`
# can reach the published assets.
{ ... }:
{
  perSystem =
    {
      system,
      pkgs,
      lib,
      ...
    }:
    let
      release = {
        version = "0.1.0";
        hashes = {
          "x86_64-linux" = lib.fakeHash;
          "aarch64-linux" = lib.fakeHash;
          # "aarch64-darwin" = lib.fakeHash;  # only when dist-macos is released
        };
      };

      triple = {
        "x86_64-linux" = "x86_64-unknown-linux-musl";
        "aarch64-linux" = "aarch64-unknown-linux-musl";
        "aarch64-darwin" = "aarch64-apple-darwin";
      };

      tag = "v${release.version}";

      tarball = pkgs.fetchurl {
        url = "https://github.com/sshine/example/releases/download/${tag}/example-${tag}-${triple.${system}}.tar.gz";
        hash = release.hashes.${system};
      };
    in
    lib.optionalAttrs (release.hashes ? ${system}) {
      packages.example-bin =
        pkgs.runCommand "example-bin-${release.version}"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];

            meta = {
              description = "What example does, in one line (prebuilt)";
              mainProgram = "example";
              license = with lib.licenses; [
                mit
                asl20
              ];
              platforms = lib.attrNames release.hashes;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            };
          }
          ''
            tar -xzf ${tarball}
            install -Dm755 example $out/bin/example

            # Only for a binary that shells out: the wrapper puts the tools it calls on
            # PATH, so the prebuilt package behaves like the source one. Drop it when
            # nothing is spawned; `wrapProgram` with no prefix is pure overhead.
            wrapProgram $out/bin/example \
              --prefix PATH : ${lib.makeBinPath [ pkgs.git ]}
          '';
    };
}
