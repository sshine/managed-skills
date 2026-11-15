---
name: nix-manage-dotfiles-softly
description: >-
  Manage dotfiles that applications need to rewrite, using hjem's native copy mode and the equivalent home-manager activation pattern. Use whenever a Nix-managed config is a read-only symlink into the store but the program wants a writable file: settings editors such as VSCodium, configs rewritten by CLIs such as git or gh, SSH config, terminal configs, migrations from home-manager copy tricks to hjem type = copy, or errors like 'could not lock config file' and 'Read-only file system'. Covers soft-copy semantics, clobber and permissions, generated configs, migration, verification, and secrets pitfalls for both hjem and home-manager.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Managing immutable dotfiles softly

A Nix-managed dotfile normally becomes a symlink into the Nix store. That is
correct for files that are only ever read, but it breaks as soon as an
application writes its own configuration: saving fails, the app replaces the
symlink, or the app silently ignores the managed version.

Use a **soft copy** for those files: keep the Nix store as the source of truth,
but deploy a regular writable file into the home directory. Every rebuild
re-seeds that file from the store, so app-made changes are temporary by design.

## Choose the deployment mode

| File behaviour | Deployment |
| --- | --- |
| The app only reads it | Symlink (`source`, or hjem's default `type = "symlink"`) |
| The app edits or rewrites it | Soft copy (`type = "copy"; clobber = true`) |
| The app needs a specific owner/mode | Soft copy with `permissions` |
| Contents are generated from a Nix value | Soft copy from `text`, or a symlink if the app never writes it |
| Contents are secret | Neither `text` nor `source` in the store; generate at activation time or use a secret manager |

Typical soft-copy candidates are settings editors, CLI credential stores, SSH
config, and any tool that validates, migrates, or rewrites its config on start.

## Hjem: native soft copy

Hjem has this directly. Put it in `hjem.users.<name>.files` for paths relative
to the home directory, or in `xdg.config.files` for paths relative to
`~/.config`:

```nix
hjem.users.sshine.xdg.config.files."VSCodium/User/settings.json" = {
  type = "copy";
  clobber = true;
  permissions = "644";
  source = ../dotfiles/vscodium-settings.json;
};
```

- `type = "copy"` installs a real file rather than a symlink.
- `clobber = true` overwrites an existing target on each activation. Without
  it, an existing local file can block the new copy.
- `permissions = "600"` sets the mode of the deployed file. Use `"600"` for
  private files such as SSH config, `"644"` for ordinary config.
- `source` points at a file kept in the repository. `text` works the same way
  and is preferable when the contents are generated from Nix.

Set `clobber = true` on each soft-copy entry even if a global default such as
`clobberFiles` is already true: the local setting documents the intent and
survives a change to the global default.

## Home-manager: source plus activation copy

Home-manager has no native copy mode. `home.file.<path>.source` and `.text`
both produce symlinks, and `onChange` only runs when that symlink changes; it
does not turn the target into a regular file. Use a source file plus an
activation copy instead:

```nix
home.file.".config/VSCodium/User/settings-source.json".source =
  ../dotfiles/vscodium-settings.json;

home.activation.copyVscodiumSettings =
  lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/VSCodium/User"
    run cp "$HOME/.config/VSCodium/User/settings-source.json" \
      "$HOME/.config/VSCodium/User/settings.json"
    run chmod 644 "$HOME/.config/VSCodium/User/settings.json"
  '';
```

`run` respects home-manager's dry-run mode. When migrating an existing
`onChange` or activation copy trick to hjem, keep the source path and change
only the deployment entry.

## Migration recipe

1. Identify the files the application writes to. Signals: a settings UI, a CLI
   that runs `git config --global`, `gh auth login`, SSH refusing a config
   because of ownership, or a GUI that saves on exit.
2. Keep the canonical content in `dotfiles/`, or generate it with `text`.
3. Replace the symlink entry with a soft-copy entry, including the correct
   `permissions`.
4. Delete the old `-source` indirection, `onChange`, and activation-copy logic
   once the soft copy is in place. If old source symlinks are still deployed,
   either remove them manually or model them as `type = "delete"` entries.
5. Rebuild, then verify the target is a regular file, not a symlink, and has the
   intended mode.

Before and after, in hjem:

```nix
# Before: application cannot write this.
files.".config/app/settings.json".source = ../dotfiles/app-settings.json;

# After: application gets a writable copy.
files.".config/app/settings.json" = {
  type = "copy";
  clobber = true;
  permissions = "644";
  source = ../dotfiles/app-settings.json;
};
```

## Worked examples

### VSCodium settings and keybindings

VSCodium rewrites these files when the user changes settings or keybindings.
Soft-copy both:

```nix
xdg.config.files = {
  "VSCodium/User/settings.json" = {
    type = "copy";
    clobber = true;
    permissions = "644";
    source = ../dotfiles/vscodium-settings.json;
  };

  "VSCodium/User/keybindings.json" = {
    type = "copy";
    clobber = true;
    permissions = "644";
    source = ../dotfiles/vscodium-keybindings.json;
  };
};
```

Do not use `home.file.".config/VSCodium/User/settings.json".source` in
home-manager unless the user never saves settings through the UI.

### SSH config

OpenSSH rejects a config whose ownership or permissions are wrong, which a
symlink into the root-owned store easily is. Deploy a private regular file:

```nix
files.".ssh/config" = {
  type = "copy";
  clobber = true;
  permissions = "600";
  source = ../dotfiles/ssh-config;
};
```

Verify with:

```sh
stat -c '%a %U:%G %n' ~/.ssh/config
test -L ~/.ssh/config && echo 'still a symlink' || echo 'regular file'
```

### `.gitconfig` and `gh` credentials

`git config --global` and `gh auth login` rewrite `.gitconfig`, so it needs a
soft copy:

```nix
files.".gitconfig" = {
  type = "copy";
  clobber = true;
  permissions = "644";
  source = ../dotfiles/gitconfig;
};
```

If `gh` should act as Git's credential helper, put that in the managed source
rather than letting `gh auth setup-git` write an absolute store path that breaks
on the next `gh` upgrade:

```ini
[credential "https://github.com"]
  helper =
  helper = !gh auth git-credential
[credential "https://gist.github.com"]
  helper =
  helper = !gh auth git-credential
```

`gh` is then resolved from `PATH`. Verify without printing the token:

```sh
printf 'protocol=https\nhost=github.com\n\n' |
  git credential fill | sed 's/^password=.*/password=<redacted>/'
```

### OpenCode config generated from Nix

When the configuration is generated, use `text` and still make the deployed
file writable:

```nix
files.".config/opencode/cli.json" = {
  type = "copy";
  clobber = true;
  permissions = "600";
  text = builtins.toJSON {
    "$schema" = "https://opencode.ai/v2/cli.json";
    keybinds."input.delete.to.line.start" = "none";
    session.sidebar = "hide";
  };
};
```

`permissions = "600"` protects the deployed copy. It does not make the Nix
store source private.

### Ghostty config with a shared Kitty theme

Keep one palette in Nix, generate the terminal theme files from it, and
soft-copy only the file the user is expected to edit:

```nix
let
  colors = {
    background = "000000";
    foreground = "ffffff";
    cursor = "ffffff";
  };

  ghosttyTheme = ''
    background = #${colors.background}
    foreground = #${colors.foreground}
    cursor-color = #${colors.cursor}
  '';

  kittyTheme = ''
    background #${colors.background}
    foreground #${colors.foreground}
    cursor #${colors.cursor}
  '';
in
{
  xdg.config.files = {
    # Generated, read-only theme files.
    "ghostty/themes/black".text = ghosttyTheme;
    "kitty/theme.conf".text = kittyTheme;
    "kitty/kitty.conf".text = ''
      font_family Droid Sans Mono
      font_size 16
      include ~/.config/kitty/theme.conf
    '';

    # The user edits this one, so it must be a copy.
    "ghostty/config" = {
      type = "copy";
      clobber = true;
      permissions = "644";
      source = ../dotfiles/ghostty-config;
    };
  };
}
```

The Ghostty config refers to the generated theme by name, for example
`theme = black`, and resolves it from `~/.config/ghostty/themes/black`. Kitty
includes the generated theme file. Neither generated theme file needs to be a
copy.

## Verification

After a rebuild, check that the deployed file is regular and has the intended
mode:

```sh
test -L ~/.config/VSCodium/User/settings.json \
  && echo 'still a symlink' \
  || echo 'regular file'
stat -c '%a %U:%G %n' ~/.config/VSCodium/User/settings.json
```

Then prove the soft-copy cycle works:

```sh
# Make a local change the way the application would.
jq '.editor.fontSize = 15' ~/.config/VSCodium/User/settings.json > /tmp/settings.json
mv /tmp/settings.json ~/.config/VSCodium/User/settings.json

# Rebuild and confirm the managed value is back.
just switch   # or: sudo nixos-rebuild switch --flake .
```

For configs that tools rewrite internally, check the tool rather than only the
file. For Git and `gh`, use `git credential fill` and `gh auth status`.

## Pitfalls

- **`clobber = true` is intentionally destructive.** Any change made through
  the application is lost on the next activation. Move settings worth keeping
  back into the Nix source.
- **Permissions do not hide secrets.** The store is world-readable; `"600"`
  only protects the deployed copy. Use a secret manager or activation-time
  generation for secrets.
- **Do not hardcode tool store paths in app config.** A helper such as
  `!/nix/store/.../bin/gh auth git-credential` breaks when the package moves.
  Prefer `!gh auth git-credential` and resolve `gh` from `PATH`.
- **`onChange` is not a copy.** In home-manager it reacts to symlink changes;
  the target remains a symlink. Use `home.file` plus `home.activation`, or
  migrate to hjem's `type = "copy"`.
- **Not every file should be copied.** Generated themes, read-only configs, and
  files applications never write should stay symlinks so the store remains the
  single source of truth.
