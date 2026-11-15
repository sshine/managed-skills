# The build definition, shared by this flake's packages and by the overlay.
#
# Taking `pkgs` as an argument (rather than closing over this flake's own) is what
# lets the overlay build against the consumer's nixpkgs. That requires a committed
# Cargo.nix: appliedCargoNix generates at evaluation time, which would force IFD on
# every consumer.
{ pkgs, ... }:
let
  cargoNix = pkgs.callPackage ./_cargo-nix.nix { };
in
cargoNix.workspaceMembers.example.build.overrideAttrs (prev: {
  meta = (prev.meta or { }) // {
    description = "Say hello, once per greeting";
    mainProgram = "example";
  };
})
