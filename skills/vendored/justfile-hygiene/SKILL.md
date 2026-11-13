---
name: justfile-hygiene
description: Review or author a Justfile with proper hygiene - every recipe has a comment, recipes are grouped logically, and the file is NOT bloated with overly specific one-off recipes. Use when creating a new Justfile, reviewing one, or asked to add a recipe to an existing file.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
user-invocable: true
---

# Justfile Hygiene

Keeps Justfiles tidy and discoverable. Three rules, in priority order:

1. **Every recipe has a doc comment** (line directly above, prefixed with `#`). `just --list` then renders it as the recipe's help text.
2. **Recipes are grouped** using `[group('name')]` attributes (or section banner comments for older `just` versions). Grouping reflects *purpose*, not alphabetical order.
3. **Recipes stay generic.** A Justfile is a menu of the project's common verbs, not a scratchpad. Resist adding narrow one-off recipes.

## When to use

- Creating a new Justfile for a project
- User asks to "add a recipe for X"
- Reviewing an existing Justfile (scoped check, not rewrite)
- Justfile has grown unwieldy and needs a pruning pass

## Core verbs (the typical menu)

Most projects need some subset of these. Do NOT add a recipe just because it's on this list - add it if the project actually needs it:

- `build` - produce artifacts
- `test` - run all tests
- `e2e` - end-to-end tests (separate from `test` if they're slow / gated)
- `lint` - static checks / clippy / ruff / eslint
- `fmt` - autoformat
- `run` - launch the primary binary / dev server
- `clean` - remove build artifacts
- `check` - umbrella: fmt + lint + test (cheap pre-commit gate)

If a project uses a `shell.nix`, recipes assume the user is already in `nix-shell`. Do NOT wrap every recipe in `nix-shell --run '...'` - that's the user's responsibility per project convention.

## Procedure

### Step 1: Survey

```bash
ls Justfile justfile 2>/dev/null
just --version 2>/dev/null   # [group(...)] attribute requires >= 1.27 (May 2024)
```

If a Justfile exists, read it end-to-end before changing anything. Count recipes. Note duplication and one-offs.

### Step 2: Decide the action

- **No Justfile, user wants one scaffolded:** Go to Step 3a.
- **Justfile exists, user asked to add a recipe:** Go to Step 3b.
- **User asked for review/cleanup:** Go to Step 3c.

### Step 3a: Scaffold a new Justfile

Start minimal. Only include verbs the project actually needs (check for `Cargo.toml`, `pyproject.toml`, `CMakeLists.txt`, `package.json`, test dirs, etc.). Replace the `<...>` placeholders with the project's real commands — do NOT ship the template verbatim.

If the project has a `shell.nix` / `flake.nix`, add a reminder at the top: `# Run recipes from inside nix-shell / nix develop.`

Template (modern `just` >= 1.27, uses `[group(...)]` attributes):

```makefile
# List available recipes.
default:
    @just --list

# Compile the project.
[group('build')]
build:
    <build command>

# Remove build artifacts.
[group('build')]
clean:
    <clean command>

# Run unit and integration tests.
[group('test')]
test:
    <test command>

# Run end-to-end tests (slow).
[group('test')]
e2e:
    <e2e command>

# Format all code in place.
[group('quality')]
fmt:
    <formatter command>

# Run static checks.
[group('quality')]
lint:
    <linter command>

# Cheap pre-commit gate: fmt + lint + test.
[group('quality')]
check: fmt lint test
```

Common substitutions by language:

| Language | build | test | fmt | lint |
|---|---|---|---|---|
| Rust | `cargo build --release` | `cargo test` | `cargo fmt --all` | `cargo clippy --all-targets -- -D warnings` |
| Python | (n/a or `python -m build`) | `pytest` | `ruff format .` | `ruff check .` |
| Node | `npm run build` | `npm test` | `prettier -w .` | `eslint .` |
| Go | `go build ./...` | `go test ./...` | `gofmt -w .` | `go vet ./...` |
| CMake | `cmake --build build` | `ctest --test-dir build` | `clang-format -i ...` | (project-specific) |

If `just` version < 1.27, the `[group(...)]` attributes will error. Fall back to banner comments only (drop the `[group(...)]` lines and separate groups with `# ---- build -----` section headers). Do NOT use both styles at once.

### Step 3b: Add a single recipe

Before writing anything, **challenge the request**:

- Is this a *verb the project will use repeatedly*, or a one-shot command the user can run directly?
- Does it belong inside an existing recipe instead (flag on `test`, option on `build`)?
- Would a `just foo` + 3-line shell script be clearer than encoding it as a recipe?

If the recipe fails the challenge (it's a one-shot, or belongs as a flag on an existing recipe, or is just a shell command the user can run directly), **do not add it**. Explain why, and propose the alternative (parameterize an existing recipe, extract to a script in `scripts/`, or just run the command ad-hoc).

If the recipe passes the challenge:
1. Add a doc comment explaining *what* it does (not *how*).
2. Put it in the right `[group(...)]`, adjacent to siblings.
3. Keep the body short. If it's > ~10 lines, move the logic to a script and have the recipe invoke it.

### Step 3c: Review pass

Run through the Justfile with this checklist. Report findings as a table; do not rewrite unless the user asks.

| Check | How to spot |
|---|---|
| Missing doc comment | Recipe line with no `#` comment directly above |
| Ungrouped recipes | Recipe without `[group(...)]` attribute (or not in a banner section) |
| Over-specific recipe | Name encodes a one-shot scenario: `test-only-foo-on-tuesday`, `build-for-alice-laptop`, `deploy-v1-2-3` |
| Near-duplicate recipes | Two recipes differing only by a flag - merge with a parameter |
| Dead recipe | References a path/tool/file that no longer exists |
| Long body (>10 lines) | Should be extracted to `scripts/` |
| Encodes secrets / personal paths | `/home/alice/...`, API tokens, hostnames |

Output:

```
## Justfile Review

**Recipes:** N total, G groups

### Findings
| Severity | Recipe | Issue |
|---|---|---|
| high | deploy-v1-2-3 | Over-specific one-shot; should be parameterized or deleted |
| med  | test-foo | Missing doc comment |
| med  | build-debug-for-laptop | Encodes personal machine name |
| low  | fmt | Not in a `[group(...)]` |

**Recommendation:** <short paragraph>
```

### Step 4: Validate

After any edit, confirm the Justfile parses:

```bash
just --list
just --summary
```

If parsing fails, fix before reporting success.

## Anti-patterns (push back on these)

- `test-<module-name>` recipes for every module - use `just test <module>` with a parameter, or let the test runner handle filtering.
- Recipes that are `cd some/path && command` - if `some/path` is always the same, move there at project root or use `set working-directory`.
- Recipes that duplicate what `cargo`/`npm`/`make` already does cleanly - a Justfile is a shortcut menu, not a re-implementation.
- Dozens of `deploy-<env>` recipes - parameterize: `deploy env:`.
- "Helper" recipes that are called only by one other recipe - inline them.
- Recipes without comments: render in `just --list` with no description, making the menu much less useful for newcomers.

## Tone

When pushing back on a recipe request, be direct: explain *why* it shouldn't be added (over-specific, belongs in a script, duplicates existing recipe) and propose the alternative. Don't just refuse.
