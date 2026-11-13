---
name: skill-refinement
description: >-
  Refine an agent skill from evidence of how its output was manually edited: infer general rules from three or more generated-versus-refined examples, then prove the rules by regenerating comparable output with isolated subagent runs before touching the skill. Use when asked to refine, improve, tighten, or regress a skill based on feedback, manual edits, diffs, or review comments on its output; when a skill's output needs repeated post-editing; when deciding whether refinements belong in an existing skill or in a new variant; or when someone says skill refinement, skill feedback, skill drift, or wants a skill's rules validated before they are adopted.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task
---

# Refining a skill from evidence

A skill is a hypothesis about how to do a task, and the edits someone makes to its output are the
data that tests it. Refining is not editing prose until it reads better: it is inferring rules from
real corrections, generating output under those rules, comparing, and only then asking whether to
adopt them. A rule that reads well and a rule that changes what a model produces are different
things, and the gap between them is most of the work here.

## Before you start

You need the skill and at least three refinement examples. A refinement example is a pair:

- the output the current skill produced for a real task, and
- the version a human turned it into — as a diff, two files, two commits, or review comments.

Ask for whatever is missing. Two examples make rules guesswork and one makes them personal taste
rather than a pattern; say that plainly and let the user decide instead of quietly proceeding.

Never edit the real skill while testing. Every candidate lives in a lab directory under
`/tmp/opencode/skill-refinement/<skill>-<timestamp>/`, because a half-tested rule in
`~/.agents/skills` reaches every session immediately, including the ones evaluating it.

A full pass is a baseline generation, up to three iteration generations, and a blind judge, so say
what it will cost before launching it; this takes minutes, not seconds, and the user may prefer to
supply better examples first.

## 1. Read the evidence as data

Copy or reference the examples into the lab, then read them whole. A diff shows the correction but
not the context that made it necessary, and half the rules come from the context.

For git-backed examples, find the generating commit and the refined commit and keep both the diff
and the surrounding text:

```bash
git -C "$REPO" log --oneline -- "$PATH"
git -C "$REPO" diff <generated>..<refined> -- "$PATH"
```

## 2. Extract rules

Walk the diffs and ask, for every hunk: *what instruction would have produced the refined version
the first time?* Name that instruction as a rule, in the imperative, and attach the examples that
support it. Then classify:

- **Correctness rules** — facts, claims, links, commands that were wrong. These are hard rules.
- **Structural rules** — reordering, merging, cutting, changing length or shape.
- **Voice rules** — hedging, throat-clearing, tense, person, jargon, rhythm.
- **Process rules** — things the skill should have looked up, asked for, or checked first.

Sort by support. A rule visible in two or more examples is general. A rule from one example is
`instance-specific` until the user confirms it, because the usual way refinement goes wrong is
promoting one person's preference about one paragraph into a law about all paragraphs. Ignore
corrections that any editor would make regardless of the skill (typos, a renamed variable).

Write `rules.md` in the lab: one line per rule, its class, its evidence (`example-2 paragraph 4`),
and whether it is confirmed by the user. This file is the rubric later, so it must be checkable
against a new output, not just readable.

## 3. Freeze a synthetic task

Improvise a task in the same domain, of the same shape and length, on a different subject. For a
blog skill, that means a short post about a project the examples do not mention; for a review skill,
a small patch of the same kind. The prompt must:

- read like something a user would type, with nothing about the refinement, the rules, or which
  skill is being exercised — the isolation wrapper in step 4 carries that separately;
- be answerable with the inputs the skill expects (a repository, a patch, a topic);
- be specific enough that a weak answer is recognisably weak.

Save it as `prompt.md` and use the identical text for the baseline and every iteration, wrapped in
the identical isolation text. Changing the prompt between runs lets a rule pass because the task got
easier, which is the one failure this whole procedure exists to prevent.

## 4. Isolate the run

Every run happens in a subagent (`Task` in Claude Code, `subagent` in OpenCode), and each run gets a
fresh one — reusing a session carries the previous attempt's context into the next comparison. The
subagent starts without your context, so hand it everything it needs by path.

The difficulty is that a subagent inherits the skill catalog: the original skill's name and
description are always in its context, and a prompt about that domain may pull it in. Asking the
subagent to ignore a skill is weak — it may still know the original's steps from the catalog or from
training on the same material. Use three layers together:

1. **A contrived name and token.** Copy the skill to the lab as
   `quillforge-<short-hash>/` and rewrite its frontmatter `name` and `description` so the description
   says *use only when the prompt names quillforge-<short-hash>*. Name the path in the prompt. The
   only skill that matches the token is the one under test.
2. **A provenance line.** Make the lab SKILL.md start with: *"Begin every reply with
   `skill: <absolute path of this file>`."* Then the evaluation can see which file the run actually
   followed, instead of assuming. Add it to every copy, baseline included, so the runs differ only by
   the rules under test.
3. **An explicit boundary in the prompt.** Name the path, hand over the task, and say that other
   skills are off limits: if the agent thinks another skill applies, it should say so and stop
   rather than use one.

A run prompt therefore looks like this, with only the directory and token changing between runs:

```
Read /tmp/opencode/skill-refinement/<lab>/baseline/quillforge-b03/SKILL.md (quillforge-b03)
and follow it. Do not open ~/.agents/skills or ~/.claude/skills, and do not use any other skill;
if you think one applies, say so and stop. Begin your reply with `skill: <the path you read>`.

Task: <the frozen prompt from prompt.md>

Write the result to /tmp/opencode/skill-refinement/<lab>/baseline/output/.
```

Baseline and each iteration get their own token and directory, so no run can be confused with
another:

```bash
LAB=/tmp/opencode/skill-refinement/blog-post-$(date +%Y%m%d-%H%M)
mkdir -p "$LAB"/{examples,baseline,iter-1,iter-2,iter-3}
cp -r <skill-dir> "$LAB"/baseline/quillforge-b03
# rewrite name/description, then repeat as quillforge-r01, quillforge-r02, ...
```

The lab copies are never symlinked into `~/.agents/skills`; that would install them as real skills.
The subagent reads them by path.

Verify isolation from the reply, not from the instructions: it must open with the provenance line for
the path you handed it. If it names another skill, cites steps that exist only in the original, or
the output has the original's fingerprints beyond what the task forces, discard the run and say so
rather than scoring it.

If isolation still looks muddy — the run keeps drifting toward the original — fall back in this
order: run the baseline and variants with the original skill temporarily uninstalled
(`skillmgr uninstall <name>`, then `skillmgr install <name>` immediately after the run, in the same
step so a dead session cannot leave the user without a skill); or give the synthetic task a surface
that the original's description does not match while still exercising the refined rules, and note
that this weakens the comparison.

## 5. Run the baseline

Spawn one subagent with the frozen prompt and the unmodified skill copy. Save its output under
`baseline/`. Score it against the rubric and keep the score: it is the floor that a refinement has to
beat, and it tells you whether the rule was needed at all. If the baseline already passes every
rule, the rules describe something the skill already does — report that and stop instead of
inventing work.

## 6. Iterate, at most three times

For `n` in 1, 2, 3:

- Copy the previous variant, apply the rules as small edits, and keep the unified diff. Prefer
  changing existing instructions to appending new ones; a skill that grows a rule per complaint
  becomes a list nobody follows.
- Run one subagent with the frozen prompt and variant `n`'s token.
- Grade the output against `rules.md`: every hard rule passes or fails with a quoted line as
  evidence. Then have a fresh subagent compare the candidate against the baseline **blind**: it
  receives the refined examples as references and the two outputs unlabelled, and says which is
  closer to the references and why. Blind judging matters because you already know which version
  you hoped would win; don't tell the judge which iteration it is looking at, or that one of the two
  is earlier.
- Accept when every correctness rule passes, the remaining rules pass except where the user has
  explicitly called the point a matter of taste, and the blind judge calls the candidate equivalent
  or better.
- When a rule fails, fix the instruction that was supposed to cause it. When the same rule fails
  twice, the rule is probably wrong about how the skill works, so revisit the inference rather than
  shouting louder in the skill.

After three attempts, stop. Report the best attempt honestly; do not widen the rubric to manufacture
a pass. A refinement that cannot reproduce the edit is useful information about the edit: it may
depend on context the skill cannot see, or be taste rather than rule.

A pass on one synthetic task is evidence that the rule transfers to one more task, not proof that it
holds generally. If the rules feel fragile, a second improvised task is cheap insurance: generate it
after the first pass and run the accepted variant once without touching the skill again.

## 7. Report and ask

Present, in this order:

- the table of iterations: rules passed, blind verdict, what changed;
- the path to the best generated output and the baseline output, quoted at a few lines at most —
  the files carry the length;
- whether the refinement reproduced the manual refinement, stated plainly, with the diagnosis when
  it did not;
- the proposed `SKILL.md` diff, as a diff and not as a rewritten file.

Save the same content as `report.md` in the lab so the evidence survives the session, and keep the
lab until the user has decided: the outputs are the argument for or against the change.

Then ask which outcome the user wants. Do not apply anything before they answer:

- **Update the skill in place.** The usual answer when the rules are general. Apply the diff, and if
  the skill lives in `~/.agents/managed-skills`, commit it with a conventional commit.
- **Save as a separate skill.** Choose this only when the rules describe a genuinely different task
  or audience, and then propose a new name and a description whose triggers do not overlap the
  original's. Two skills that answer the same request make selection arbitrary, which is worse than
  either version alone.
- **Neither.** Keep the report as evidence and leave the skill alone; sometimes the diff shows the
  human edit was the exception.

Check provenance before writing. `skillmgr list` reports `vendored` or `authored`. Editing a vendored
skill in place creates drift that the next `skillmgr sync` or `skillmgr update` will erase, so
either send the change upstream to the repository it came from, or make the local copy authoritative
first with `skillmgr remove <name> --keep-files` followed by
`skillmgr adopt <name> --from skills/vendored/<name>` — and say which one you are doing.
