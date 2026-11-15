# Extra hook wiring for a repository that commits Cargo.nix.
#
# Copy this file only in committed-Cargo.nix mode. The helper
# `config.packages.cargo-nix` is defined by the crate2nix module that generates and
# verifies the file, so this module does not evaluate without it.
#
# Cargo.nix is crate2nix output: deadnix flags its unused lambda patterns, nixfmt
# rewrites it into a shape `crate2nix generate` does not produce, and nobody edits
# it by hand. settings.exclude drops it from every hook at once, matching
# settings.global.excludes in nix/treefmt.nix.
#
# `cargo-nix --check` regenerates beside the real file and diffs everything after
# crate2nix's three-line argv header, so a dependency change without a regenerated
# Cargo.nix fails the push instead of the Nix build.
{ ... }:
{
  perSystem =
    { config, lib, ... }:
    {
      hk-nix.settings.exclude = [ "Cargo.nix" ];

      hk-nix.settings.hooks."pre-push".steps.cargo-nix.check =
        "${lib.getExe config.packages.cargo-nix} --check";
    };
}
