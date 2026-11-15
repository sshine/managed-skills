# hashpinner checks that every `uses:` in the workflows and local actions is pinned to
# a commit with a truthful version comment. It lives in the devshell so the pre-push
# hook, CI and a developer's shell all run the same binary.
#
# `hashpinner-bin` is the published static binary and exists on Linux only. Darwin
# falls back to the source build, which costs one Rust build the first time.
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      devshells.default.packages = [
        (
          inputs.hashpinner.packages.${system}.hashpinner-bin
          or inputs.hashpinner.packages.${system}.default
        )
      ];
    };
}
