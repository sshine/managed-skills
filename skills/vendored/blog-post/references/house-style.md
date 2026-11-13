# House style for simonshine.dk

Read this before writing. Everything here is derived from the existing corpus; when this file and
a recent post disagree, the post wins and this file is out of date.

## Frontmatter

TOML, in this order, as `just post` generates it plus `tags`:

```toml
+++
date = '2026-08-08T01:59:35+02:00'
draft = true
title = 'Hashpinning'
tags = ['rust', 'nix', 'security']
+++
```

Single quotes. Two to four tags, taken from the tags already in use.

## Title

Sentence case. Median length in the corpus is 33 characters; 55 is the practical ceiling, because
longer titles overflow the space beside their date in the post list. Capitals cost more than
lowercase there, so a title full of acronyms needs to be shorter still.

Titles state the thing, not the lesson: `Hashpinning`, `A Vault Job`, `sops-nix templates for
passwords in legacy configs`. Not `How I learned to...`, not `A deep dive into...`.

## Wrapping

Prose hard-wraps at 100 columns. Never rewrap inside a code fence, and never break a URL to fit.
Reference definitions sit on their own line and may run past 100, as may a bullet whose breaking
point falls badly. Recent posts have two to six such lines each.

## Links

Reference style dominates, roughly three to two over inline:

```markdown
I wrote a CLI tool, [hashpinner][hp], to automate this.

[hp]: https://github.com/sshine/hashpinner
```

Definitions go directly under the paragraph or section that uses them, not at the bottom of the
file. Reference names are short and lowercase: `hp`, `pw`, `tj`, `cve1`, `vso`.

Inline links are fine for a single incidental link in a sentence.

Links to other posts on the blog use the path: `[flake-parts partition](/articles/dendritic-flake-partitions)`.

## Code fences

Always tag the language: `nix`, `yaml`, `just`, `rust`, `bash`, `console`, `markdown`, `diff`.

When the snippet is a real file, the first line inside the fence is a comment with its path:

```nix
# nix/devshell.nix
{ ... }
```

`console` for shell sessions, with `$` on the command and the real output under it. Real output,
copied, not reconstructed.

A `diff` fence is the right way to show a fix.

## Images

```markdown
![The dashboard signup form](/img/mxroute-dashboard-signup.png)
```

The file goes in `static/img/`. Alt text is a caption, written as a sentence.

Shortcodes in use: `{{< youtube ID >}}` and `{{< rawhtml >}}`.

## Opening

Start inside the problem. One to four short paragraphs, concrete from the first sentence, often a
code snippet within the first ten lines:

> GitHub Actions workflows usually start like this:
>
> ```yaml
> - uses: actions/checkout@v6
> ```

Or a plain statement of position:

> I don't do much front-end web development these days, but I enable people who do.

Never open with what the post is going to do, why the topic matters, or what year it is.

## tl;dr

Medium and long posts carry a `## tl;dr` right after the opening. It is a bullet list where every
bullet is a complete claim carrying a number, a name or a command:

- `hashpinner --check` fails on anything unpinned. You can run this as a git hook.
- nixpkgs' `playwright-test` hardcodes the full browser set into its wrapper, so the naive setup
  drags 2.2 GB into your devshell. I managed to push that down to 634 MB.

A bullet that could sit in any post on the subject does not belong.

## Headings

`##` for sections, `###` sparingly. Short, declarative, occasionally wry:

> Nobody needs to know · Pins get old · Existence is not membership · The bug that check had ·
> Where `uses:` hides · What this is not

Never `Introduction`, `Overview`, `Conclusion`, `Summary`, `Final thoughts`, `Key takeaways`.

## Ending

Stop on something concrete: a snippet, a command and its output, one observation. No wrap-up
section, no restating, no call to action, no invitation to comment.

`a-vault-job` ends on three lines of `kubectl logs` output and one sentence about it. `hashpinning`
ends on a `flake.nix` with nothing after it.

## Voice

First person. Present tense for how things work, past tense for what happened. Short sentences;
the average line is around 45 characters of a 100-column wrap, which is what short sentences look
like.

Prose between snippets runs one to three sentences in a walkthrough. The code carries the post.

Keep the wrong turn when the wrong turn explains the design, and say plainly that it was wrong.
Opinions are stated as opinions and not hedged into neutrality.

Numbers are measured. "I managed to push that down to 634 MB" is in the corpus because the figure
was measured. If a number cannot be measured, the sentence goes.

## Words that never appear

The user's global list of forbidden words and phrases applies in full. On top of it, for posts:

delve, leverage, robust, seamless, powerful, journey, realm, landscape, testament, unlock,
elevate, crucial, vital, ensure that, it is important to note, in today's world, at the end of the
day, let's dive in, the beauty of this approach, best of both worlds.

No em-dashes. Commas, periods, semicolons, and the occasional colon.

Bold lead-ins on bullets are for labelled enumerations and nothing else. Twelve posts use them,
fifty-six do not; a plain bullet is the default.

No sentence that describes the post itself: "In this section we will", "As mentioned above",
"Now that we have covered". The headings already do that work.
