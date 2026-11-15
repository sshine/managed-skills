# Hook catalogue

One row per hook example in `hk-nix/examples/`, plus one improvised step. The baseline
(template) already contains treefmt, conventional commits, deadnix, clippy, the
lock check, the README hook and the tag guard; this catalogue is for selecting
the rest.

Legend: **hook** is where the example puts the step. **Pin** is what makes it
survive the `nix flake check` sandbox, which has no devshell `PATH` and no
network. A step that needs network, `cargo`, or a private key must not be
reachable from `checks.hk`, whose `checkHook` defaults to `pre-commit`.

| Example | What it checks | Hook | Select when | Pin | Gotcha |
| --- | --- | --- | --- | --- | --- |
| `treefmt` | One formatting pass over staged files, fixing in place | pre-commit | Always | `lib.getExe config.treefmt.build.wrapper` | `check` needs `--fail-on-change --no-cache`; the sandbox has no writable cache. `fix = true` needs `stash = "git"`, or a partial `git add -p` is lost. This is the only rewrite-capable step. |
| `conventional-commits` | Commit message is a conventional commit | commit-msg | Always | none; hk runs the builtin | Only `--allowed-types` is configurable. There is no `--require-scope`; ship a checker package and point `check` at it if a scope is mandatory. |
| `nix-hygiene` | deadnix over Nix sources, generated files excluded | pre-push | Every Nix repo | `lib.getExe pkgs.deadnix` | `settings.exclude = [ "Cargo.nix" ]` drops it from every hook at once. A per-step `--exclude Cargo.nix` is the fallback when another module owns the step. deadnix reports, so it cannot ride on pre-commit's fix pass. |
| Rust pre-push set | clippy, a locked `cargo metadata`, unit tests without integration | pre-push | Every Rust workspace | bare `cargo`, which is on the devshell `PATH` | Never reachable from `checks.hk`: the sandbox has no cargo closure. If tests are enabled, skip the integration suite (`-- --skip integration`) unless it is seconds. |
| `cargo-readme` | `README.md` still matches `README.tpl` plus rustdoc | pre-push | `README.tpl` exists | `lib.getExe' config.packages.cargo-readme "cargo-readme"` plus treefmt's mdformat | Diffing raw generator output loses to mdformat forever: pipe the generator through `config.treefmt.settings.formatter.mdformat.command`. `--input` is required for a lib target. 3.4.1 resolves `--input`/`--template` against the working directory, so spell them root-relative (`--project-root crates/example --input crates/example/src/main.rs --template README.tpl`); `config.packages.cargo-readme` is pinned by `nix/cargo-readme.nix`. Supplying the subcommand name `readme` by hand is mandatory when calling by store path. |
| `secret-scanning` | Leaked credentials in the staged files | pre-commit | The repo touches secrets | `lib.getExe pkgs.betterleaks`; `config.hk-nix.builtins.gitleaks` | A leak caught on pre-push is already in history and must be rotated, not amended. `--redact` keeps the match out of terminals and CI logs. `--config .betterleaks.toml` must name a file that exists. Without one, omit `--config`; auto-discovery does not work when the paths are individual files. |
| `sops-rekey` | Every `secrets/*.yaml` is encrypted to the current `.sops.yaml` recipients | pre-commit | `.sops.yaml` exists | `writeShellApplication` with `pkgs.sops`, `diffutils`, `coreutils` | There is no read-only form, so it re-keys a throwaway copy. It needs the age/KMS private key: `checks.hk` has `HOME` in a temp dir and no key, so `nix flake check` fails for everyone without one. Give CI a key, or keep the step out of the check hook. |
| `strip-comments` | Only doc comments survive, enforced with ast-grep rules | pre-commit | The project wants a doc-comments-only policy | `lib.getExe pkgs.ast-grep`, rules built in the store | `--update-all --error` exits 0 after rewriting, so the obvious `fix` would fix and report clean. Scan first, then update, then `exit 1`. `exclusive = true` and a name that sorts first keep it away from treefmt, which cleans up afterwards. Exclude Helm templates: they are `.yaml` with Go template syntax. |
| `go-workspace` | `go vet`, staticcheck, `go mod tidy -diff`, short tests | pre-push | Go module or workspace | `lib.getExe' pkgs.go-tools "staticcheck"` | A `go.sum` that does not describe the imports fails the Nix build later with a worse message. Unit tests only; the database-backed suite belongs in CI. |
| `eval-gates` | Flake outputs evaluate without building | pre-push | `nix flake check` is too slow to run on every push | bare `nix`, devshell only | `nix flake show --all-systems` builds nothing, so it catches broken expressions but not broken artifacts. `nix eval --raw .#version` is the smaller version; building one named check is the next step up. Never in `checks.hk`. |
| `hugo-site` | The site renders into a temporary directory | pre-push | Hugo content | `${pkgs.hugo}/bin/hugo` | No glob: a template or shortcode change can break a page that was not edited, so no file set means "the render is fine". `mktemp -d` destination; do not leave output in the tree. |
| `helm-chart` | `helm lint` plus a cheap Nix eval | pre-push | Helm chart in the repo | `lib.getExe pkgs.kubernetes-helm` | An eval catches Nix errors and dangling refs; `helm lint` catches a chart that will not render. A webpack build measured in minutes belongs in CI, not here. |
| `opentofu` | `tofu validate` on a backendless init | pre-push | OpenTofu/Terraform configuration | `lib.getExe pkgs.opentofu` | `init -backend=false -input=false -upgrade` first; never touch state. With providers in the store it needs no network. It proves the configuration parses and typechecks, not that it matches what is deployed. |
| `tag-version` | A pushed `v*` tag names the version in the tagged commit | pre-push | Every tagged release | `writeShellApplication` with `git` and `gnused` | Only pre-push gets `{{hook_stdin}}`; pipe it with `printf '%s\n'`. Skip deletions (all-zero sha) and non-`v*` refs. Read `Cargo.toml` with `git show <sha>:Cargo.toml`, never the working tree. The `sed` reads `[workspace.package]`; adapt it for a single-crate `[package]`. It does not check crates.io or the remote tag. |
| `golden-json` | A captured fixture corpus is still valid JSON | pre-push | Hand-editable golden files | `lib.getExe pkgs.jq` | `jq -e . {{files}} > /dev/null` only parses. If the fixtures also need schema checks, that is a different, heavier step. |
| `sqlx-offline` | The offline query cache matches the queries; an offline `cargo check` mirrors the Nix build | pre-push | sqlx with a `.sqlx` cache | bare `cargo` and `cargo sqlx` from the devshell | `cargo sqlx prepare --workspace --check` needs a database, so guard it on `DATABASE_URL` and print that CI will enforce it otherwise. `SQLX_OFFLINE=true cargo check --workspace --all-targets` is the cheaper reproduction of the sandbox failure. Add `sqlx-cli` to the devshell. |
| `hermetic-assets` | No build-time network fetch from `asset!`, remote asset hosts or `iconify::` | pre-push | The build embeds JS/icon assets | `lib.getExe pkgs.ripgrep` | The patterns match call syntax, so prose stays legal. `include_str!`/`include_bytes!` of a tracked file are hermetic; only the remote-fetch forms are banned. The failure it prevents is a sandbox error several layers from the line that caused it. |
| `flake-check-hook` | A dedicated lint-only hook that `checks.hk` runs | `check` (sets `checkHook`) | `checks.hk` must not run pre-commit, or you want deadnix in CI | same as the linters it shares | Shares one `lintSteps` set with pre-push so the pins and globs are written once. If you set `checkHook = "check"` and forget treefmt, formatting silently drops out of `nix flake check`. |

## Copy-paste additions

All fragments go inside `perSystem`, where `config`, `pkgs` and `lib` are in
scope. The dotted form merges with the baseline instead of replacing a hook
attribute, so it is safe to add these beside the template.

Secret scanning, with a config file when one exists:

```nix
hk-nix.settings.hooks."pre-commit".steps.betterleaks.check =
  "${lib.getExe pkgs.betterleaks} dir --redact --no-banner --config .betterleaks.toml {{files}}";

hk-nix.settings.hooks."pre-commit".steps.gitleaks.builtin =
  config.hk-nix.builtins.gitleaks;
```

Omit `--config .betterleaks.toml` when the file does not exist. `--redact`
matters: without it the hook prints the secret it just found.

sops re-keying. Add the binding to the existing `let` block:

```nix
rekey-check = pkgs.writeShellApplication {
  name = "sops-rekey-check";
  runtimeInputs = [
    pkgs.sops
    pkgs.diffutils
    pkgs.coreutils
  ];
  text = ''
    shopt -s nullglob
    files=(secrets/*.yaml)
    [ ''${#files[@]} -eq 0 ] && exit 0

    root="$PWD"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    cp "$root/.sops.yaml" "$tmpdir/.sops.yaml"

    needs_rekey=0
    for f in "''${files[@]}"; do
      mkdir -p "$tmpdir/$(dirname "$f")"
      cp "$root/$f" "$tmpdir/$f"
      if (cd "$tmpdir" && sops updatekeys --yes "$f") >/dev/null 2>&1; then
        if ! diff -q "$root/$f" "$tmpdir/$f" >/dev/null 2>&1; then
          echo "$f is not encrypted to the current .sops.yaml recipients"
          needs_rekey=1
        fi
      else
        echo "could not check $f (is your age key available?)"
        needs_rekey=1
      fi
    done

    if [ "$needs_rekey" -ne 0 ]; then
      echo "run: sops updatekeys secrets/*.yaml"
      exit 1
    fi
  '';
};
```

and the step:

```nix
hk-nix.settings.hooks."pre-commit".steps.sops-rekey = {
  glob = [
    ".sops.yaml"
    "secrets/*.yaml"
  ];
  check = lib.getExe rekey-check;
};
```

sqlx, conditional on a configured database:

```nix
hk-nix.settings.hooks."pre-push".steps.sqlx-prepared = {
  glob = "crates/example-store/**/*.rs";
  check = ''
    if [ -n "''${DATABASE_URL:-}" ]; then
      cargo sqlx prepare --workspace --check -- --all-targets
    else
      echo "DATABASE_URL unset, leaving the .sqlx check to CI"
    fi
  '';
};

hk-nix.settings.hooks."pre-push".steps.sqlx-offline.check =
  "SQLX_OFFLINE=true cargo check --workspace --all-targets";
```

The hermetic-asset guard:

```nix
hk-nix.settings.hooks."pre-push".steps.hermetic = {
  glob = "*.rs";
  check = ''! ${lib.getExe pkgs.ripgrep} --quiet -e 'asset!\("https?://' -e 'host: *Asset' -e 'iconify::' {{files}}'';
};
```

actionlint, as a builtin so its globs and binary come along:

```nix
hk-nix.settings.hooks."pre-push".steps.actionlint.builtin =
  config.hk-nix.builtins.actionlint;
```

## Improvised step: documentation build

Clippy does not resolve intra-doc links; rustdoc does. A broken `[link]` in a
public item compiles and ships. Offer this step; do not make it default, because
it costs seconds to minutes and rustdoc's lint set moves with the toolchain.

```nix
let
  # Pinned by rust-toolchain.toml, so a new rustdoc lint cannot appear without a
  # toolchain bump, and the path is absolute for the same reason every other tool
  # is. `../` is correct from nix/hooks.nix at the repository root. This needs
  # rust-overlay on pkgs, which the flake applies for the rest of the toolchain.
  rust-toolchain = pkgs.rust-bin.fromRustupToolchainFile ../rust-toolchain.toml;
in
{
  hk-nix.settings.hooks."pre-push".steps.doc.check =
    ''RUSTDOCFLAGS="-D warnings" ${lib.getExe' rust-toolchain "cargo"} doc --no-deps --all-features'';
}
```

Why pre-push: it reads the whole crate graph and may need to resolve dependency
sources on a cold cache. Why `--no-deps`: warnings in dependencies are not the
project's to fix and would make the gate unpassable. Why only offer it: a
library with a large public API gets real value; a single binary with three
public items usually does not.

## How to improvise a hook from a recurring CI failure

Use this when the repository's history shows the same CI failure twice, or when
the user names a failure they keep fixing by hand.

1. **Name the failure, not the tool.** Write down the exact CI symptom and the
   command that would have caught it earlier, e.g. "README.md drift caught by
   `just readme-check`" or "`cargo metadata --locked` fails after a manifest
   edit".
2. **Find the smallest deterministic reproduction.** Run it locally and time it.
   If it needs a service, a secret or more than a few seconds, it is a CI check,
   not a pre-push check. If it rewrites files, it is a candidate only for
   pre-commit.
3. **Choose placement by the budget.** Instant and rewrite-capable: pre-commit.
   Whole-workspace, read-only, seconds: pre-push. Anything else: CI, and say so
   instead of adding a hook that will be bypassed.
4. **Pin the tool.** `lib.getExe pkgs.foo`, `lib.getExe' pkgs.foo "binary"`, or
   `config.treefmt.build.wrapper`. A bare command is a bug if `checks.hk` can
   reach it; it is acceptable only in a pre-push step that the sandbox never
   runs, and even then a store path is better.
5. **Make it read-only where possible.** A `check` that reports is enough for
   pre-push. Add `fix` only when the repair is mechanical and safe, and only let
   pre-commit apply fixes automatically.
6. **Prove the sandbox path.** Run `nix flake check`. If the new step is on
   pre-commit, it just ran in the sandbox; if it failed for a missing binary,
   the pin is wrong; if it failed for a missing key or network, the step is in
   the wrong hook.
7. **Prove the local path.** Make a throwaway commit that should pass
   (`git commit --allow-empty -m "chore: test hooks"`, then `git reset --soft
   HEAD^`) and, if safe, a `git push --dry-run`.
8. **Write the failure into the comment.** One sentence above the step saying
   what it prevents is what keeps the next person from deleting it as noise.

If the failure only reproduces in CI because CI has a different toolchain,
service or credential, do not invent a hook: fix the CI job. A hook that cannot
reproduce the failure locally is a hook that will be bypassed.
