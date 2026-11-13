---
name: blog-post
description: Write an article for the simonshine.dk blog. Locates the Hugo repository, checks the git index for staged work, agrees on a length and a shape, picks reference posts from the existing corpus, and writes in the site's established voice. Use when asked to write a blog post, write an article, draft a post about a project, a tool or a technique, or turn work from the current session into a post for the blog.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, WebFetch, AskUserQuestion
user-invocable: true
---

# Writing a post for simonshine.dk

A post is one hard-wrapped Markdown file under `content/articles/` with TOML frontmatter.

The audience is former and future colleagues: working engineers who skim the code first and read
the prose only where it explains something they could not have inferred from the code.

Steps 1 to 7 happen before a line of the post is written.

## 1. Locate the repository

The site lives in `~/Projects/sites/simonshine.dk`. Use it when it is there:

```bash
REPO=~/Projects/sites/simonshine.dk
[ -f "$REPO/hugo.toml" ] && [ -d "$REPO/content/articles" ] && [ -d "$REPO/.git" ] && echo "$REPO"
```

If that path is gone, the repository moved. Scan for it:

```bash
for d in $(find ~ -maxdepth 4 -type d -name 'simonshine.dk' \
             -not -path '*/.cache/*' -not -path '*/backup/*' 2>/dev/null); do
  [ -f "$d/hugo.toml" ] && [ -d "$d/content/articles" ] && [ -d "$d/.git" ] \
    && echo "$(git -C "$d" log -1 --format=%ct) $d"
done | sort -rn
```

Old clones live under other paths and all carry the same git remote, so the remote does not
separate them. Take the top line: newest commit wins. If the two newest are within a week of each
other, ask which one to use. Say where the repository turned up, since the default path is wrong
at that point.

Everything below assumes `REPO` is that path. `hugo` and `just` exist only inside the devshell, so
repository commands run as `nix develop --command <cmd>`.

## 2. Check the index before anything else

```bash
git -C "$REPO" diff --cached --stat
comm -12 <(git -C "$REPO" diff --name-only | sort) \
         <(git -C "$REPO" diff --cached --name-only | sort)
```

- **Index empty**: say nothing about git, go to step 3.
- **Index non-empty**: stop and report what is staged. Offer to commit it, split into logically
  separate commits, following the user's commit style. Scopes with precedence in this repository:
  `articles`, `theme`, `nix`, `justfile`, `ci`, `branding`. Wait for an answer.

Never stage a path that is not already staged. Unstaged and untracked files are drafts the user is
deliberately not committing; do not stage them, do not list them, do not ask about them. The only
later exception is the post's own file, in step 10.

To split, unstage everything and restage one group at a time. Only safe when the second command
above printed nothing:

```bash
git -C "$REPO" reset -q
git -C "$REPO" add -- <paths for commit 1> && git -C "$REPO" commit
```

If that command printed any path, those files have both staged and worktree changes, and restaging
would sweep the worktree draft into the commit. In that case offer a single commit of the index as
it stands and say why it cannot be split.

## 3. Agree on length

Ask with AskUserQuestion. Sizes, measured against the existing corpus, counting prose words outside
code fences:

| Size   | Prose words | Code lines | `##` sections | tl;dr    | Exemplars |
|--------|-------------|-----------|---------------|----------|-----------|
| Small  | 250 to 450  | 0 to 60   | 2 to 3        | no       | `grep-pager-mode`, `hk-nix-mdformat-gotchas`, `a-terraform-dns-moment` |
| Medium | 500 to 900  | 40 to 150 | 3 to 5        | optional | `sops-nix-templates`, `dendritic-flake-partitions`, `three-levels-of-nix` |
| Long   | 1000 to 1700| 100 to 280| 6 to 10       | yes      | `hashpinning`, `a-vault-job`, `agentic-playwright-testing-with-nix` |

Treat the lower bound as a floor, not a quota. If the subject runs out early, stop there and say
the post came out one size down; padding to hit a number is worse than a short post.

Above 1700 prose words the subject is two posts. The corpus splits that way on purpose:
`poor-mans-nix-binary-cache` and `poor-mans-nix-ci-cache`, `speeding-up-ci-with-nix` and
`speeding-up-ci-more-with-nix`. Propose the split rather than writing one long post.

Ask about shape in the same round when it is not obvious from the request:

- **Walkthrough**, the default: code first, prose between snippets held to one to three sentences.
- **Story**: something broke, here is what it was and what the fix had to account for. Keeps the
  wrong turn in when the wrong turn explains the design.
- **Essay**: opinion, little or no code.

Language is English unless the topic is Danish computer science teaching, which carries the
`datamatik` tag. Ask if it could be either.

## 4. Decide what may be linked

This matters more than anything else in the post.

**Deployed infrastructure gets written about in general terms.** The cluster repository, its
Forgejo instance, its hosts and its internal URLs stay out. No repository link, no clone URL, no
hostnames, no dashboards. Relative file paths and service names are fine, and they are what the
existing posts use: `a-vault-job` shows `services/incidental.nix` and `services/keel.nix` as code
fence comments and links nothing. A reader should be able to rebuild the idea without being able
to find the deployment.

**Tools, libraries and techniques get linked freely.** A published tool, its repository, its
releases, upstream documentation, CVEs, vendor docs: all fair game, and the posts about
`hashpinner`, `hk-nix` and `helm-vendor` link theirs in the opening paragraphs.

The line is between a thing other people can use and a thing that is running. When a post covers
both, link the tool and describe the deployment.

## 5. Read the reference posts and agree on the angle

Read one or two of these before writing, whichever sits closest in shape. They are the reference
set because the voice tightened over time and these are where it arrived:

- `content/articles/hashpinning.md`, long walkthrough of a tool, with a tl;dr that carries the post.
- `content/articles/a-vault-job.md`, long, about deployed infrastructure, linking nothing.
- `content/articles/agentic-playwright-testing-with-nix.md`, long, mixes tooling with a TDD story.
- `content/articles/sops-nix-templates.md`, medium, one problem and its fix.
- `content/articles/hk-nix-mdformat-gotchas.md`, small, two gotchas and nothing else.

Name the ones picked in a single line so the user can swap them.

This list goes out of date as better posts get written. When a recent post is plainly a better
example than one above, say so and offer to replace it here.

Then say back, in two or three bullets, what the post will cover and in what order, and get a yes.
For a post about work from the current session, this is where the real material gets chosen; the
session remembers far more than the post should contain.

Take the session's account at face value. Do not re-run its commands to confirm figures it already
established. What the session never measured stays out of the post rather than being estimated.

## 6. Screenshots

Offer one when the subject has a user interface worth looking at, and skip it otherwise. Most posts
have no image.

The screenshot comes from the project being written about, not from the blog. Look for a `shot` or
`shots` recipe in its justfile, or a headless browser already in its devshell, and use that;
`agentic-playwright-testing-with-nix` names the recipe that produced its screenshot and the fact
that it was the same flake-pinned Chromium that runs the tests. If the project has no such recipe,
ask the user for the image instead of building a capture pipeline for one picture.

The file goes in `$REPO/static/img/<descriptive-name>.png` and is referenced as
`![caption](/img/<descriptive-name>.png)`.

## 7. Create the file

Slug is lowercase, hyphenated, derived from the title:

```bash
cd "$REPO" && nix develop --command just post <slug>.md
```

That writes TOML frontmatter with hugo's timestamp and `draft = true`. Add `tags` by hand, reusing
tags that already exist:

```bash
grep -h '^tags' "$REPO"/content/articles/*.md | tr -d "[]'" | sed 's/tags = //' \
  | tr ',' '\n' | sed 's/^ *//' | sort | uniq -c | sort -rn
```

Leave `draft = true`. Flipping it is the user's call when the post is ready.

## 8. Write

Read `references/house-style.md` in this skill directory first. It carries the markdown
conventions, the voice, and the words that never appear on this blog.

## 9. Verify

```bash
cd "$REPO" && nix develop --command hugo --minify -d /tmp/hugo-check
awk 'length > 100' "$REPO"/content/articles/<slug>.md
```

The build must be clean apart from the pre-existing `languageCode` deprecation warning.

The width check is a review list, not a gate. Recent posts carry two to six lines past 100, and
those are reference definitions, long URLs and code. Rewrap what is ordinary prose, leave the rest.

Report the prose word count against the agreed size:

```bash
awk 'BEGIN{fm=0} /^\+\+\+$/{fm++; next} fm<2{next} /^```/{c=!c; next} !c{w+=NF} END{print w}' \
  "$REPO"/content/articles/<slug>.md
```

## 10. Commit, still as a draft

Commit the post and any image it added, with `draft = true` left alone. Publishing is a separate
decision the user makes later by flipping the flag.

```bash
git -C "$REPO" add -- content/articles/<slug>.md static/img/<name>.png
git -C "$REPO" commit
```

Message follows the user's commit style, scope `articles`, as the repository already does:
`feat(articles): Hashpinning`. One commit for the post. Do not push.

Only the post's own paths get added. The repository carries other uncommitted drafts that stay
untouched and unmentioned.
