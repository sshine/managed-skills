# Forgejo differences

GitHub is the default. This file is for the Forgejo or "both" answer. Only CI is in
scope here; the release workflow belongs to the release phase, which reads this too.

## Directory and triggers

- Workflows live in `.forgejo/workflows/`.
- Forgejo searches `.forgejo/workflows`, then `.gitea/workflows`, then
  `.github/workflows`, and uses only the **first that exists**. With both forges in one
  repository, the `.github/` workflows are dead on Forgejo, not merged. Keep the two
  check lists identical by hand, and do not assume a GitHub-only edit runs on Forgejo.
- Context names are still `github.*`: `${{ github.server_url }}`,
  `${{ github.repository }}`, `${{ github.ref_name }}`.

## Runner labels

- `runs-on: nixos` is a label on a local, persistent NixOS runner. Nix is already
  installed, the store survives between jobs, and no cache action is needed. The
  template assumes this.
- A generic runner registered with `docker` or `host` also works, but treat it as
  ephemeral: install Nix with the same pinned `nixbuild/nix-quick-install-action` and add
  `nix-community/cache-nix-action`, both through absolute URLs. Do not assume a local
  `./.github/actions/...` path is available on every runner and runner version; inline the
  few checks so the Forgejo workflow is self-contained.
- If the runner is not NixOS, say so and change `runs-on` to the label the runner
  actually advertises. A wrong label leaves the job queued forever.

## Absolute action URLs

Under `.forgejo/`, a bare `owner/repo` resolves against the instance's
`DEFAULT_ACTIONS_URL`, which defaults to `https://data.forgejo.org` — not github.com. The
same `owner/repo@sha` can therefore be a different repository with different commits.

Write every remote action as an absolute URL, pinned to a commit and commented:

```yaml
- name: Checkout
  uses: https://github.com/actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1, 2026-07-17
```

Local actions are relative to the repository root. Prefer inlining the few checks in the
Forgejo workflow over maintaining a second copy of the composites; if the two lists drift,
the CI is lying on one of the forges.

hashpinner reads the forge from the directory. `.forgejo/` and `.gitea/` files are
checked under Forgejo rules, so `--deep` resolves absolute URLs against github.com and
bare references against the Forgejo default. If the instance mirrors actions elsewhere,
pass the host:

```bash
hashpinner --check --deep --no-allow --forgejo-host https://git.example.com
```

Do not use `pull_request_target` or `workflow_run`: hashpinner fails them by default, and
pinning cannot constrain a workflow that runs against the base repository with secrets.

## Creating the remote

The repository shell does not create a Forgejo repository. Either the user creates an
empty one in the web UI, or `tea` does:

```bash
tea repo create --name example --owner owner --private
git remote add origin https://git.example.com/owner/example.git
git push -u origin main
```

`git ls-remote` is not an existence check: an empty repository exits 0 with no output.
Preflight therefore warns instead of claiming the name is free.

## Secrets and releases

This phase creates no release workflow. When the release phase arrives, the Forgejo
uploader is a `writeShellApplication` package (`nix run .#forgejo-release -- <tag> dist`)
that reads:

| Variable | Value in a workflow |
|---|---|
| `FORGEJO_URL` | `${{ github.server_url }}` |
| `FORGEJO_REPO` | `${{ github.repository }}` |
| `FORGEJO_TOKEN` | `${{ secrets.RELEASE_TOKEN || secrets.GITHUB_TOKEN }}` |

The token needs the `write:repository` scope to create a release and upload assets. Name
it in the repository's secrets; do not put it in a workflow file. The uploader adopts an
existing release for the tag and replaces assets of the same name, so a partial upload can
be re-run.

## What stays the same

- `vX.Y.Z` tags equal to `[workspace.package].version`.
- `just` recipes and the Nix devshell: the same commands run on both forges.
- Every check in the GitHub composite, including `just pin-check` and `nix flake check`.
- The store cache key is irrelevant on a persistent runner but must stay correct if the
  workflow is later moved to an ephemeral one.
