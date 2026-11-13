---
name: dendritic-nix-flake
description: >-
  Convert a Nix flake to Dendritic Nix: a flake-parts layout where every .nix file is a module, recursively imported with import-tree. Use when converting or rewriting a flake.nix into modules, splitting a monolithic flake into per-aspect files, reorganizing a flake with flake-parts or import-tree, adding devshell, treefmt-nix or hk-nix inputs, or whenever someone says dendritic, dendritic nix, flake-parts module, import-tree, or wants one file per host, package or aspect.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Dendritic Nix flakes

Dendritic Nix is a layout convention for flakes, not a library.

**One rule: every `.nix` file is a [flake-parts][flake-parts] module** — except `flake.nix`,
which is reduced to a stub. Two pieces make that work:

- [flake-parts][flake-parts] gives modules their `options`/`config` shape, so files merge
  instead of overwriting each other.
- [import-tree][import-tree] recursively imports every `.nix` file under a directory, so
  there is no import list to maintain.

[flake-parts]: https://flake.parts
[import-tree]: https://github.com/vic/import-tree

A minimal flake:

```nix
{
  inputs.nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.import-tree.url = "github:vic/import-tree";
  outputs = { flake-parts, import-tree, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; }
    (import-tree ./modules);
}
```

## What a module earns you

One file expresses one aspect, and that aspect can contribute to `nixosConfigurations`,
`packages`, `perSystem`, `terranixModules` and anything else at the same time. Enabling a
feature is adding a file; disabling it is setting an option.

The payoff is where things live. A host is an *emergent property* of which aspects apply,
not a file that lists imports. Conditionality belongs inside modules as flags and options,
not in the choice of what to import — that choice is what makes conventional flakes drift
into unreadable import graphs. A module can still `imports = [ ... ]` for local composition
when a file genuinely needs a helper that is not itself an aspect.

## Converting an existing flake

Work through these in order. The goal is to finish with a flake that behaves exactly as
before, but with every output living in a file that names its own concern.

### 1. Pick the subdirectory that holds the parts

- A workspace project (Cargo, npm, …) with no other Nix code usually reads best as `nix/`.
- A Nix-heavy project can use `lib/`, `modules/` or `flake/`.

Avoid any name already carrying meaning in the project: don't call it `lib/` if `lib/` holds
functions that are not flake-parts modules, and don't call it `modules/` if "module" already
means something domain-specific there. A wrong name costs more than a plain `nix/`.

### 2. Reduce flake.nix

Keep every input, and move every output into files inside that subdirectory. `flake.nix`
should end up as inputs plus `mkFlake` plus `import-tree`.

While rewriting, make the input blocks syntactically consistent — pick one of these two
shapes and use it throughout, with one blank line between blocks:

```nix
devshell.url = "github:numtide/devshell";
devshell.inputs.nixpkgs.follows = "nixpkgs";
```

```nix
devshell = {
  url = "github:numtide/devshell";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Consistency here matters because this file is the one everyone diffs when inputs change;
mixed styles make the meaningful line hard to spot.

### 3. Choose the flake dependencies

Fetch nixpkgs from the channel tarball:
`https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz`.

The optional inputs below are worth adding when the project is a blank slate — a new git
repository, a new project, or no prior Nix code. Add them individually if a particular one
is clearly wanted. **If the project already has Nix code, leave them out of a rewrite:**
whoever wrote that Nix made choices, and quietly replacing `pkgs.mkShell` with a devshell
is fighting those choices rather than converting the layout.

- [numtide/devshell](https://github.com/numtide/devshell) — if there is an existing
  `pkgs.mkShell`, refactor it into a devshell while you are here.

  ```nix
  devshell.url = "github:numtide/devshell";
  devshell.inputs.nixpkgs.follows = "nixpkgs";
  ```

- [treefmt-nix](https://github.com/numtide/treefmt-nix) — owns all code formatting.

  ```nix
  treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```

  Once it is clear which syntaxes the project contains, add their formatters to the
  treefmt-nix module. Enumerate the actual file types; don't guess.

- [hk-nix](https://github.com/nix-tools/hk-nix) — activates treefmt-nix and owns linting
  and custom hooks.

  ```nix
  hk-nix.url = "github:nix-tools/hk-nix";
  hk-nix.inputs.nixpkgs.follows = "nixpkgs";
  ```

  Hook latency is a design constraint, not a detail: pre-commit and commit-msg hooks must
  be blazing fast or people start committing with `--no-verify`. pre-push may take a few
  seconds.

### 4. Deduplicate flake.lock

After adding inputs, look for duplicated transitive inputs showing up as `_2`, `_3`, and so
on, and add `.follows` on the direct inputs to collapse them. Fewer nixpkgs copies means
less evaluation and no mixed-library surprises.

### 5. Make it a git repository if it is not one

Flakes only see files git tracks, so a flake outside a repository is not really working.
If the directory is not a repository, initialize it — but first check `git config
user.name` and `git config user.email`. If they are unset or obviously wrong (sandboxing
often leaves placeholders), stop and say so. A first commit authored by a botchy default
identity has to be rebased later, which is exactly the kind of tax that makes people give
up on a clean history.

## Verify the conversion

- `nix flake show` should list the same outputs as the flake before the conversion; a
  missing attribute usually means a module landed outside the `import-tree` directory or
  that its `options`/`config` shape is wrong.
- `nix flake check` evaluates every module and catches assertions and type errors early.
- `nix build .#<package>` for one package and `nix develop` for the devshell prove the two
  entry points most people actually use.

Report what was verified and what was not; don't claim a conversion works because the
files look organized.
