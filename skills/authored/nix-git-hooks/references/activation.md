# Activating hk-nix

Three edits, all additive, plus one thing to understand. Do not rewrite
`flake.nix`, `nix/devshell.nix`, `justfile` or `nix/packages.nix`; add the lines
that are missing.

## 1. The flake input

```nix
hk-nix = {
  url = "github:nix-tools/hk-nix";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.follows = "flake-parts";
  inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.import-tree.follows = "import-tree";
};
```

All four `follows` matter: hk-nix consumes nixpkgs, flake-parts, treefmt-nix and
import-tree. Without them the lock file grows a second copy of each and
`config.treefmt` stops being the treefmt the hooks read.

## 2. The module import

`nix/hooks.nix` starts with:

```nix
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];
}
```

With import-tree, dropping the file in `nix/` is the whole registration. Nothing
else in `flake.nix` changes. Importing the module defines `checks.hk` as a side
effect.

## 3. The devshell

Under numtide/devshell:

```nix
devshells.default = {
  packages = [
    # ... existing packages ...
    config.hk-nix.package
  ];
  devshell.motd = "";
  devshell.startup.hk.text = config.hk-nix.shellHook;
};
```

Under `pkgs.mkShell`:

```nix
devShells.default = pkgs.mkShell {
  packages = [ config.hk-nix.hk pkgs.git ];
  shellHook = config.hk-nix.shellHook;
};
```

Add `config.treefmt.build.programs.mdformat` only if a `just readme` recipe in
the devshell calls bare `mdformat`; the hook itself uses the absolute command
from `config.treefmt.settings.formatter.mdformat.command`.

If the user answered no to automatic installation, skip the startup line and
install by hand with `hk install --force-local` from a shell where `hk` is
`config.hk-nix.hk`.

## The cargo-readme package

The README step runs `config.packages.cargo-readme`, not `pkgs.cargo-readme`, so
the generator is the same locally, in CI and in the hook. Add this input to
`flake.nix` (a non-flake source, so there is no `flake = true` default to inherit):

```nix
cargo-readme-src = {
  url = "github:webern/cargo-readme/v3.4.1";
  flake = false;
};
```

and this module as `nix/cargo-readme.nix`:

```nix
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.cargo-readme = pkgs.rustPlatform.buildRustPackage {
        pname = "cargo-readme";
        version = "3.4.1";
        src = inputs.cargo-readme-src;
        cargoLock.lockFile = "${inputs.cargo-readme-src}/Cargo.lock";
        # Upstream tests expect a full cargo-project fixture layout; skip.
        doCheck = false;
      };
    };
}
```

Run `nix flake lock` (not a full update) to pin the new input, and add
`nix/cargo-readme.nix` to the `.envrc` watch list when that file lists modules
explicitly. 3.4.1 resolves `--input` and `--template` against the working
directory, so the hook spells them from the repository root.

### `config.hk-nix.package` versus `config.hk-nix.hk`

- `config.hk-nix.package` is the plain hk CLI. No generated config is attached.
- `config.hk-nix.hk` is `package` with the rendered config baked in as
  `HK_FILE`; it is what the installed git hooks name by absolute store path.
- The startup hook prepends `config.hk-nix.hk` to `PATH` on entry, so an
  activated devshell resolves `hk` to the configured binary even when
  `packages` lists the plain CLI. That is why `hk run` and `hk validate` work in
  the shell while the hooks also work from an editor outside it.
- If the startup hook does not run (a bare `nix shell`, a broken shellHook, a
  `nix develop` with the startup entry removed) and the installed hook resolves a
  plain `hk`, then `hk run --from-hook` finds no config and exits 0 without
  output. Hooks appear to pass. Check that the installed command names
  `/nix/store/...-hk-hk-nix/bin/hk`, not a bare `hk`.

Both binaries are useful: the plain CLI is for `hk` as a general tool, the baked
one is for this repository's hooks. Do not put both in `packages`; the one that
wins is PATH order, which is not a contract.

## 4. `HK_FILE` and the missing `hk.pkl`

hk-nix renders `settings` into an `hk.pkl` in the Nix store and wraps the hk
binary with `--set-default HK_FILE <that path>`. `--set-default` means an
`HK_FILE` already exported in the environment wins, which is useful for testing
an alternative config.

Consequences:

- There is no `hk.pkl` in the working tree.
- There is nothing to add to `.gitignore`.
- A repository comment or `.gitignore` entry saying `hk.pkl` is symlinked into
  the root is stale. Current hk-nix does not write it. Correct the comment when
  you touch the file; remove the ignore entry only if the user agrees, since it
  is harmless.
- hk-nix also writes `.git/hk-nix.installed`, a marker holding the store path of
  the configured binary. A config change changes the path and re-triggers
  installation; an unchanged config prints "up to date" and does nothing, which
  keeps direnv and file watchers quiet.
- Garbage-collecting the store path breaks the hook until the next devshell
  entry rewrites it. That is the documented trade for not needing `hk` on
  `PATH`.

## `checks.hk`

Importing the flake module sets `checks.<system>.hk`. It is a `runCommand` that:

1. copies the flake source into the sandbox and removes `.git`;
2. `git init`, `git add -A` in a throwaway repository;
3. runs `hk run <checkHook> --all --check` with `HOME` set to the copied tree.

`checkHook` defaults to `pre-commit`. The command is run with `--check`, so even
a `fix` definition reports rather than rewrites. The derivation carries the
configured hk binary, git and a CA bundle, and nothing else: no devshell `PATH`,
no network, no cargo closure, no private keys.

Therefore:

- Every step reachable from `checkHook` needs an absolute store path.
- Builtins inject their pinned tool into the step `PATH`; custom steps get
  nothing.
- `hashpinner --deep`, `cargo test`, `nix flake check`, `sops updatekeys` and
  anything that resolves a registry or a remote tag are pre-push or CI only.
- The baseline `checks.hk` proves formatting over all files. It does not prove
  deadnix, clippy or the lock check. Those run in CI, or in a dedicated
  lint-only hook:

  ```nix
  hk-nix.checkHook = "check";
  hk-nix.settings.hooks."check".steps = lintSteps;
  hk-nix.settings.hooks."pre-push".steps = lintSteps // {
    clippy.check = "cargo clippy --all-targets --all-features -- -D warnings";
  };
  ```

  If you take this route, include treefmt in `lintSteps`; otherwise formatting
  silently drops out of `nix flake check`.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `treefmt: command not found` or `deadnix: command not found` in `nix flake check` | A bare binary in a step the sandbox runs | `lib.getExe config.treefmt.build.wrapper`, `lib.getExe pkgs.deadnix`; builtins already pin themselves |
| `nix flake check` fails on a network fetch or a missing cargo | A pre-push-shaped step on the check hook | Move it to pre-push or CI, or set a lint-only `checkHook` |
| README.md changes on every commit, or the README hook and pre-commit undo each other | Raw `cargo-readme` output compared against an mdformat-normalised file | Pipe through `config.treefmt.settings.formatter.mdformat.command`; diff that pipeline, not the raw generator |
| The tag guard rejects every tag | The version is in `[package]`, not `[workspace.package]` | Change the `sed` range to `[package]`, or print the parsed version to debug |
| `{{hook_stdin}}` is empty | The step is not on pre-push, or it reads stdin directly | Move it to pre-push; pipe with `printf '%s\n' "{{hook_stdin}}"` and never read stdin in the script |
| deadnix fails on 15k lines of `Cargo.nix` | crate2nix output with unused lambda patterns | `settings.exclude = [ "Cargo.nix" ]`, and the same exclusion in `nix/treefmt.nix` |
| `settings.exclude` seems ignored by one step | A module replaced the step with `mkForce` and lost the global exclusion | Add `--exclude Cargo.nix` to that step's command |
| Hooks install but never fire | The installed command names a bare `hk`, or the store path was garbage-collected | Re-enter the devshell; `git config --local --get-regexp '^hook\.hk-'` must name `/nix/store/.../bin/hk` |
| Hooks "pass" instantly with no output | The hook calls a plain hk with no `HK_FILE`; `--from-hook` treats the repo as not using hk | Use the baked binary or export `HK_FILE`; re-run the startup hook |
| `git commit` ignores the hooks | git older than 2.54, which does not read config-based hooks | hk-nix never uses `--legacy`; upgrade git. The install-time `PATH` uses the devshell's git, but the commit uses the user's |
| `nix flake check` fails in `sops-rekey` with "is your age key available?" | The check sandbox has no private key | Give CI a key, or keep `sops-rekey` off the check hook |
| actionlint rejects a Forgejo workflow | Its schema is GitHub's | Run actionlint only on `.github/workflows`, or accept the false positives; hashpinner covers Forgejo pinning |
| betterleaks fails on a missing `.betterleaks.toml` | `--config` names a file that is not there | Create the config, or drop `--config` and use the defaults |
| `attribute 'mdformat' missing` while evaluating the README hook | `nix/treefmt.nix` does not enable mdformat | Enable it, or drop the mdformat stage and accept the fixpoint problem |
| pre-commit takes seconds and people use `--no-verify` | A whole-workspace check on the wrong hook | Move it to pre-push; measure with `time git commit --allow-empty -m "chore: time"` |
