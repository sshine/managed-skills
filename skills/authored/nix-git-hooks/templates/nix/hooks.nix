# Git hooks via hk-nix.
#
# hk-nix renders this attrset into an hk.pkl in the store and bakes that path into
# the hk binary as HK_FILE. Nothing named hk.pkl is written into the working tree,
# so there is nothing to .gitignore.
#
# Every tool is named by absolute store path. `nix flake check` runs the
# pre-commit hook in a sandbox without the devshell PATH, so a bare `treefmt` is
# not found there.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      treefmt = lib.getExe config.treefmt.build.wrapper;

      # Flags that reproduce the committed README.md from README.tpl and the crate
      # docs. --input is required when the crate has a lib target.
      #
      # 3.4.1 resolves --input and --template against the current directory, which is
      # the repository root when the hook runs, so both are spelled from there.
      #
      # `cargo-readme` comes from config.packages.cargo-readme, defined in
      # nix/cargo-readme.nix, which pins 3.4.1 from the `cargo-readme-src` input.
      # When that file is absent, add the input and module first (the snippet is in
      # references/activation.md).
      #
      # When there is no README.tpl, delete this binding, cargo-readme, mdformat,
      # readme and the readme step below. Leaving the bindings behind makes deadnix
      # report them as unused.
      readmeArgs = "--project-root crates/example --input crates/example/src/main.rs --template README.tpl";

      # Called by store path rather than via `cargo readme`, so the cargo-subcommand
      # argv has to be supplied by hand: without it clap only prints its usage.
      cargo-readme = "${lib.getExe' config.packages.cargo-readme "cargo-readme"} readme";

      # cargo-readme emits markdown that mdformat then rewrites, moving link
      # reference definitions to the end of the file. The raw output therefore never
      # equals the committed README.md, and the two hooks would undo each other
      # forever. Reusing treefmt's own mdformat gives them one fixpoint and one
      # plugin set, because nix/treefmt.nix enables mdformat.
      mdformat = config.treefmt.settings.formatter.mdformat.command;

      readme = "${cargo-readme} ${readmeArgs} | ${mdformat} -";

      # pre-push receives `<local ref> <local sha> <remote ref> <remote sha>` lines
      # on standard input. hk exposes them as {{hook_stdin}}, so the script does not
      # read stdin itself. The version comes out of the tagged commit, not out of the
      # working tree, because the two can differ. A deletion arrives with an all-zero
      # local sha and is skipped.
      check-tag-version = pkgs.writeShellApplication {
        name = "check-tag-version";
        runtimeInputs = [
          pkgs.git
          pkgs.gnused
        ];
        text = ''
          status=0
          while read -r local_ref local_sha _remote_ref _remote_sha; do
            case "$local_ref" in refs/tags/v*) ;; *) continue ;; esac
            case "$local_sha" in *[!0]*) ;; *) continue ;; esac

            tag="''${local_ref#refs/tags/}"
            commit="$(git rev-parse "$local_sha^{commit}")"
            crate="$(git show "$commit:Cargo.toml" \
              | sed -n '/^\[workspace\.package\]/,/^\[/{ s/^version = "\(.*\)"/\1/p }')"

            if [ "$tag" != "v$crate" ]; then
              echo "$tag names v$crate at ''${commit:0:12}" >&2
              status=1
            fi
          done
          exit "$status"
        '';
      };
    in
    {
      hk-nix.settings.hooks = {
        # Instant, and the only hook allowed to rewrite the tree. stash = "git"
        # puts unstaged work aside while the fix runs, so a partial `git add -p`
        # survives the rewrite.
        "pre-commit" = {
          fix = true;
          stash = "git";
          steps.treefmt = {
            # treefmt skips files it has no formatter for, so one catch-all glob is
            # cheaper than keeping a list of extensions in sync with nix/treefmt.nix.
            glob = "**/*";
            check = "${treefmt} --fail-on-change --no-cache {{files}}";
            fix = "${treefmt} {{files}}";
          };
        };

        # hk runs this builtin itself rather than shelling out to a pinned tool, so
        # nothing needs installing and the step costs nothing in the closure.
        # --allowed-types is its only policy knob.
        "commit-msg".steps.conventional.builtin =
          config.hk-nix.builtins.check_conventional_commit;

        # Seconds are allowed here; this is the last point where a failure is still
        # cheap. Everything that reads the whole workspace goes here, and nothing
        # that needs the check sandbox's missing network or cargo closure.
        "pre-push".steps = {
          # deadnix reports rather than rewrites, so it has nothing to contribute to
          # the formatting pass. Cargo.nix, when committed, is excluded from every
          # hook in nix/hooks-cargo-nix.nix.
          deadnix = {
            glob = "*.nix";
            check = "${lib.getExe pkgs.deadnix} --fail {{files}}";
          };

          clippy.check = "cargo clippy --all-targets --all-features -- -D warnings";

          # A manifest edit that left Cargo.lock behind otherwise shows up as a CI
          # failure on --locked, several commits after the one that caused it.
          lock-check.check =
            "cargo metadata --locked --format-version 1 > /dev/null";

          # Delete this step, and its four let bindings above, when the project has
          # no README.tpl. `check` reports and writes nothing; `fix` is the repair
          # hk offers when running with fixes on.
          readme = {
            check = "${readme} | diff - README.md";
            fix = "${readme} > README.md";
          };

          tag-version.check =
            ''printf '%s\n' "{{hook_stdin}}" | ${lib.getExe check-tag-version}'';
        };
      };
    };
}
