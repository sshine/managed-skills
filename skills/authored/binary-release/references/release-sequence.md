# The release sequence, and the cache key

The order is: bump, review, commit, push `main`, wait for green, tag, release workflow.
Every step after the push is cheap; the push is the only one that starts work, and the tag
is the only one that starts a second job.

## The commands

```bash
just bump 0.1.0                  # workspace phase: edits [workspace.package].version
just fmt && just ci              # or `just check` where the workspace has one
git diff --stat && git diff      # the bump should be one line plus derived files
git commit -am "chore: release 0.1.0"
git push origin main

gh run list --branch main --workflow ci.yml --limit 1 --json conclusion,headSha
gh run watch "$(gh run list --branch main --workflow ci.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId')"
```

Only when that run is `success`:

```bash
just tag v0.1.0
```

`just tag` re-checks the four repository conditions itself and then the CI state, so the
manual commands above are what you read, not what you trust. Its refusal messages name the
condition that failed.

On a Forgejo instance there is no `gh`:

```bash
CONFIRM=green just tag v0.1.0
```

after opening the repository's Actions page and seeing the run on `main` succeed. The
recipe prints that URL when it cannot read the state itself.

## Why the tag must wait

The CI workflow and the release workflow use the same `cache-nix-action` key:

```
nix-${{ runner.os }}-${{ hashFiles('**/*.nix', '**/flake.lock') }}
```

The tag points at a commit main has already built, so every derivation in the release is a
restore. Two properties of the cache make the order load-bearing:

- The key is immutable. When it already exists, the action restores it and does not write
  new store paths back.
- The post step is `post-if: success()`, so a job that fails saves nothing.

Push the tag before main's run finishes and the two jobs race for the same key. The loser
compiles everything the winner is compiling, cannot save it, and either job's failure
loses the whole store for the next attempt. The release is not wrong when this happens —
it is slow, and it stays slow on every retry until something changes the key.

The same collision happens without a tag when a tag is pushed alongside the commit:

```bash
git push --follow-tags origin main   # starts CI and the release at the same time
```

Push the branch, wait, then push the tag separately. That is what `just tag` does.

If the release has a genuinely different derivation set (an AppImage-only closure, a
second toolkit), give that job its own key prefix and its own cache, the way the GUI
project here does. Two caches that never share are better than one that cannot.

## If the tag was pushed too early

Nothing is public yet if the GitHub workflow drafts first. Fix main, then move the tag:

```bash
# main is red after the tag went out
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0
# fix, commit, push, wait for green, then
just tag v0.1.0
```

Delete the draft release too if it exists (`gh release delete v0.1.0 --yes`), otherwise
the recreated tag reuses it — which is fine, because the upload uses `--clobber` and the
asset set is replaced.

On Forgejo the release is public as soon as the upload starts. Deleting the tag does not
delete the release; delete the release in the web UI before re-tagging, or accept that the
rerun replaces every asset of the same name.

## If the tag is already public and the artifacts are wrong

Do not move a published tag. Tags are what `nix/binary.nix`, `cargo install --git`, and
anyone's lock file point at, and a moved tag makes those references mean something else
than they did. Bump to the next patch version and cut a new release. A tag whose assets
are wrong can have its assets replaced, but not its content.

## What to record after the run

```bash
just release-hashes v0.1.0       # SRI lines for nix/binary.nix
gh release view v0.1.0           # asset list, all with sidecars
```

Set `nix/binary.nix`'s `version` to `0.1.0` (no `v`) and paste the hashes. That commit is
a normal `chore:` commit; it is not part of the release and does not get the tag.
