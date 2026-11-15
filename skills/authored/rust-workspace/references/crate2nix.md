# crate2nix: committed `Cargo.nix` or IFD

crate2nix reads `Cargo.lock` and emits one Nix derivation per crate, each calling
`rustc` directly. Nothing runs `cargo` during the build, so a shared dependency is
built once and every binary, test and check that needs it resolves the same store
path. That is why it is the default builder here, and why `rustPlatform.buildRustPackage`
is not.

It is always wired. The only choice is whether the generated graph is a file in the
tree or a function evaluated on demand.

## The two modes

| | Committed `Cargo.nix` | IFD (`appliedCargoNix`) |
|---|---|---|
| Evaluation cost | Loads a generated Nix file | Runs the generator at evaluation and writes the graph to the store |
| First evaluation | No store write | Needs a writable store; slower on a cold machine |
| Overlay | Works: `final.callPackage ./_package.nix { }` builds against the consumer's nixpkgs | Not practical; the generator belongs to this flake's inputs |
| Drift | Possible; `just cargo-nix-check` and CI catch it | Impossible; regenerated every evaluation |
| Review | The dependency graph is a reviewable diff | Invisible |
| Best for | Large closures (~100+ crates) or several binaries | A small single binary |

Committing is the recommendation in the first case: a large closure makes evaluation
cost matter, and IFD has to write the graph to the store on every evaluation, which is
a poor fit for several binaries and repeated `nix build` / `nix flake check` runs.
IFD is acceptable for a small single binary, where the graph is cheap and the extra
file is noise.

## Committed mode

Files:

- `Cargo.nix` at the root, generated, committed.
- `nix/cargo-nix.nix`: the `cargo-nix` package that regenerates and `--check`s it.
- `nix/_cargo-nix.nix`: the one import of `../Cargo.nix`, with native overrides.
- `nix/_package.nix`: the build definition the overlay shares.
- `nix/packages.nix`: `workspaceMembers.<crate>.build` for each binary, plus
  `flake.overlays.default`.

Bootstrap and verify:

```bash
nix develop -c crate2nix generate
just cargo-nix-check
```

`cargo-nix --check` regenerates into `.Cargo.nix.check` beside the real file, because
crate2nix records crate source paths relative to the output; generating in `/tmp`
produces paths that can never match. It compares from line 4 onward, since the first
three lines record the generator's argv and therefore always differ. Both scratch
files are in `.gitignore`.

`Cargo.nix` must stay out of every tool that walks the tree:

- treefmt: `settings.global.excludes = [ "Cargo.nix" ]` in `nix/treefmt.nix`.
- deadnix: the `lint-nix` recipe scans `nix/` and `flake.nix` only, so it never sees
  the root file.
- explicit file lists: treefmt's `global.excludes` applies to a tree walk, but a hook
  that hands treefmt or deadnix staged paths bypasses it. The hooks phase must repeat
  the exclusion on the command line (`--excludes Cargo.nix` for treefmt, `--exclude
  Cargo.nix` for deadnix). Formatting the generated file makes `cargo-nix-check`
  report drift that is really the formatter's doing.

## IFD mode

Delete `Cargo.nix`, `nix/cargo-nix.nix`, `nix/_cargo-nix.nix` and `nix/_package.nix`.
Replace `nix/packages.nix` with:

```nix
{ inputs, ... }:
{
  perSystem =
    { system, lib, ... }:
    let
      cargoNix = inputs.crate2nix.tools.${system}.appliedCargoNix {
        name = "example";
        src = ../.;
      };

      binaries = [ "example" ];

      built = lib.genAttrs binaries (crate: cargoNix.workspaceMembers.${crate}.build);
    in
    {
      packages = built // {
        default = built.example;
      };

      checks = built;

      apps.default = {
        type = "app";
        # crate2nix does not set meta.mainProgram, so name the binary.
        program = "${built.example}/bin/example";
      };
    };
}
```

Then:

- delete the `cargo-nix` and `cargo-nix-check` recipes and drop `cargo-nix-check`
  from `ci`;
- delete `settings.global.excludes = [ "Cargo.nix" ];` from `nix/treefmt.nix`;
- remove `inputs.crate2nix.packages.${system}.default` and
  `config.packages.cargo-nix` from `nix/devshell.nix`;
- drop the overlay and NixOS section from `README.tpl`: an overlay cannot call
  `appliedCargoNix` without this flake's `system` and inputs, so there is no package
  to expose to a consumer's nixpkgs.

The trade is explicit: no drift check, no generated file to review, and a slower
first evaluation that needs a store write.

## Per-crate clippy (optional, for large workspaces)

Do not enable this by default. `cargo clippy` in the devshell is the normal lint. The
crate2nix flavour exists because `nix flake check` otherwise has no clippy at all,
and on a large workspace compiling the whole tree to lint it is wasteful.

It is only safe with all four repairs below. Any one missing produces a check that
compiles, prints nothing and passes:

1. `capLints`. `buildRustCrate` defaults to `capLints = "allow"`, which caps clippy's
   lints too. Use `"forbid"`; `#[allow]` and `#[expect]` still work.
2. `lints`. `[lints] workspace = true` is cargo's to resolve. crate2nix emits no
   lints, so read `manifest.workspace.lints` and pass it as `lints`.
3. `rust-version`. crate2nix does not emit it and `CARGO_PKG_RUST_VERSION` arrives
   empty, so clippy suggests APIs newer than the declared MSRV. Pass the value from
   `[workspace.package]`.
4. Features. crate2nix resolves a member's features from its manifest alone; there is
   no `--all-features`. A test behind a feature compiles to zero tests and passes.
   Build the list from the member's own `[features]`.

Add a `lint` flag to `nix/_cargo-nix.nix` and select the workspace members by name:

```nix
{ lib, pkgs, ... }:
let
  manifest = lib.importTOML ../Cargo.toml;
  members = builtins.attrNames (builtins.readDir ../crates);
  msrv = manifest.workspace.package.rust-version or null;
  lints = manifest.workspace.lints or { };
in
{
  lint ? false,
}:
import ../Cargo.nix {
  inherit pkgs;
  buildRustCrateForPkgs =
    p:
    let
      base = p.buildRustCrate.override (
        { defaultCrateOverrides = p.defaultCrateOverrides; }
        // lib.optionalAttrs (p ? rust-bin) (
          let
            toolchain = p.rust-bin.fromRustupToolchainFile ../rust-toolchain.toml;
          in
          {
            rustc = toolchain;
            cargo = toolchain;
            clippy = toolchain;
          }
        )
      );
    in
    crate:
    base (
      crate
      // lib.optionalAttrs (lint && builtins.elem crate.crateName members) {
        useClippy = true;
        capLints = "forbid";
        inherit lints;
        extraRustcOpts = (crate.extraRustcOpts or [ ]) ++ [ "-D" "warnings" ];
      }
      // lib.optionalAttrs (lint && msrv != null) {
        rust-version = msrv;
      }
    );
}
// {
  # Everything `--all-features` would enable for one member: its defaults plus every
  # feature its own manifest declares.
  allFeatures =
    crate:
    [ "default" ]
    ++ builtins.attrNames ((lib.importTOML (../crates + "/${crate}/Cargo.toml")).features or { });
}
```

Expose it as a check, not as the default package:

```nix
{ pkgs, lib, ... }:
let
  cargoNix = pkgs.callPackage ./_cargo-nix.nix { } { lint = true; };

  linted = lib.mapAttrsToList (
    crate: member:
    member.build.override {
      features = cargoNix.allFeatures crate;
      runTests = true;
      testCrateFlags = [ "--list" ];
    }
  ) cargoNix.workspaceMembers;
in
{
  checks.clippy = pkgs.runCommand "example-clippy" { inherit linted; } ''
    for crate in $linted; do
      echo "clippy: $crate"
    done
    touch $out
  '';
}
```

Naming the list in the derivation's environment is what makes it build; the script
reads nothing back. `runTests = true` wires the dev-dependencies and compiles
`tests/*.rs`; `testCrateFlags` is read by the test runner, not the build, so a lint
check can pass `[ "--list" ]` and share one compile with an integration check that
actually runs them.

The long version, with the failure modes that led to each repair, is the article
"Per-crate clippy through crate2nix" on simonshine.dk.
