---
name: agentic-playwright-nix
description: >-
  Wire Agentic Playwright into a Nix project: the flake's playwright-test package and a
  trimmed browser set, the devshell PATH/NODE_PATH/browser variables, a headed debugging
  partition, a Playwright test config with a throwaway e2e server, the test-runner MCP
  server for Claude Code and OpenCode, and the planner/generator/healer agents. Use this
  skill whenever the user asks to enable Playwright agents, set up Playwright with Nix,
  wire the Playwright MCP server into a flake, fix "npx: command not found", "playwright:
  command not found", a failed or pending MCP connection, or when the feature-e2e-nix
  skill reports that Agentic Playwright is not wired in. It includes the post-article
  corrections that make screenshots trustworthy: run the flake's playwright rather than
  npx, launch OpenCode's MCP server through direnv, and content-version asset URLs so a
  service worker cannot serve the previous deploy's CSS and JavaScript.
---

# Agentic Playwright with Nix

This sets up Playwright, its browsers, its test runner, and its three agents entirely from
a Nix flake. There is no `package.json`, no lockfile, no `node_modules` in the repository,
and no `npm install` or `npx playwright install` step. The browser that runs on a
developer's machine is the browser that runs in CI, because both are the same store path.

The original article is in `references/original-article.md`. Read it for the rationale
and the closure measurements. The instructions below supersede its advice on caching:
the article predates the stale-asset failure described in "Cache correctness".

## The outcome

Agentic Playwright is wired when all of these are true:

- `playwright` is on `PATH` inside the Nix devshell.
- `@playwright/test` resolves through the runner's `NODE_PATH`, with no npm step.
- A browser exists in the store, and `PLAYWRIGHT_BROWSERS_PATH` points at it.
- The three Playwright agents exist and the test-runner MCP server is configured for
  whichever harness the user works in (Claude Code, OpenCode, or both).
- A real page can be opened, screenshotted at phone size, and looked at.
- If the app has a cache-first service worker, asset URLs carry a content version.

Verification is not `playwright --version`. It is a screenshot you have opened and
described. A behavior test can pass while the page is visually broken; that happened in
the session this skill was written from.

## Read the project before editing

- Find the flake and how modules are loaded. This repository uses dendritic flake-parts
  and `import-tree`, which skips files beginning with `_`; the Playwright helper is
  `nix/_playwright.nix` for that reason. If the project uses a plain `flake.nix`, put the
  same `let` block beside the devshell instead of inventing a new file.
- Find the devshell (devshell, devenv, or a plain `devShells.default`), the `justfile`,
  and any existing `e2e/` or `tests/` directory.
- Check for `package.json`, `package-lock.json`, or `node_modules`. If they exist, stop
  and ask before mixing npm with the flake. The point of this setup is one pinned version.
- Check for `.mcp.json`, `opencode.json(c)`, and `.claude/agents/`. Reuse what is there.
- Check whether the app has a service worker that caches `/assets/*`.

Do not silently rewrite the flake. Show the user the files you intend to add or change.

## 1. The Playwright package with a chosen browser set

nixpkgs' `playwright-test` puts the **full** browser set in its wrapper, so it keeps a
runtime reference to all of Chromium, Firefox and WebKit no matter what
`PLAYWRIGHT_BROWSERS_PATH` says at runtime. For a suite that only drives Chromium, retarget
the wrapper:

```nix
# nix/_playwright.nix
{ pkgs, withChromium }:
let
  browsers = pkgs.playwright-driver.browsers.override {
    inherit withChromium;
    withFirefox = false;
    withWebkit = false;
  };

  playwright-test = pkgs.playwright-test.overrideAttrs (old: {
    installPhase =
      builtins.replaceStrings [ "${pkgs.playwright-driver.browsers}" ] [ "${browsers}" ]
        old.installPhase;
  });
in
{
  inherit browsers playwright-test;
}
```

The closure drops from roughly 2.3 GB to 634 MB. `withChromium = false` keeps only
`chromium_headless_shell`, which is what headless tests use anyway. Do not add Firefox or
WebKit to the default shell; if the user wants cross-browser runs, that is a separate
decision and a separate closure.

Do **not** use the separate `playwright-mcp` package. It resolves its browser as
"chrome-for-testing" and will not fall back to the headless shell, which drags headed
Chromium back into the default closure. `playwright run-test-mcp-server` ships in
`playwright-test` and is what the generated agents call.

## 2. The devshell

Add the wrapper and the two variables:

```nix
{
  packages = [
    playwright.playwright-test
    # ... the project's own tools
  ];

  env = [
    # The wrappers already point at this; naming it again keeps a bare node and
    # anything spawned from the tests pointing at the same store path.
    { name = "PLAYWRIGHT_BROWSERS_PATH"; value = "${playwright.browsers}"; }

    # The browsers come from the store, so Playwright's check for a distribution it
    # recognises has nothing useful to say.
    { name = "PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS"; value = "true"; }
  ];
}
```

The wrapper already puts its own `node_modules` on `NODE_PATH`, which is why

```ts
import { test, expect } from "@playwright/test";
```

resolves in a Rust repository with no JavaScript toolchain in sight. `which node` may be
empty in the devshell; that is fine. Do not add Node just to satisfy a tool that
`playwright` supplies itself.

## 3. Headed Chromium as a partition

Headed Chromium is another ~574 MB and only interactive debugging wants it:
`playwright test --headed`, `--ui`, and `codegen`. Keep it out of the default evaluation
with a flake-parts partition:

```nix
# nix/partitions.nix
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs.devShells = "headed";
  partitions.headed.module = ./_headed.nix;
}
```

```nix
# nix/_headed.nix
{
  perSystem =
    { config, pkgs, ... }:
    {
      devshells.headed = {
        imports = [
          (import ./_devshell-common.nix { inherit config pkgs; withChromium = true; })
        ];
        env = [{ name = "PW_HEADED"; value = "1"; }];
      };
    };
}
```

The config reads `PW_HEADED` to drop the headless-shell channel, so one config serves both
shells:

```ts
channel: process.env.PW_HEADED ? undefined : "chromium-headless-shell",
```

`nix develop .#headed` is then the only shell that can run `--headed` or `--ui`.

## 4. The test config and a throwaway server

```ts
// e2e/playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

const PORT = 8081;
const BASE_URL = `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: "./tests",
  outputDir: "./test-results",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [
    ["list"],
    ["html", { outputFolder: "playwright-report", open: "never" }],
  ],
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        channel: process.env.PW_HEADED ? undefined : "chromium-headless-shell",
      },
    },
  ],
  webServer: {
    command: "just serve-e2e",
    cwd: "..",
    url: BASE_URL,
    reuseExistingServer: !process.env.CI,
    timeout: 300_000,
    stdout: "pipe",
    stderr: "pipe",
  },
});
```

Do not point the suite at the dev database. A code id, a user, or a fixture is spent once;
a suite that reuses the dev state asserts against rows it did not create and becomes
order-dependent. The e2e recipe should:

- create a database per run and drop it on exit;
- mint fixture secrets into a gitignored file (a secret exists in plaintext only at mint);
- start the server on a port away from the dev server, with `--insecure-cookies` on plain
  HTTP;
- be the only thing `playwright` starts, so a test run cannot mutate what is being
  clicked through by hand.

Add `e2e/tests/seed.spec.ts` (a trivial test that opens the landing page) for the
generator, and write plans to `e2e/specs/`. Leave the seed alone once it exists.

## 5. MCP for Claude Code

`playwright run-test-mcp-server` is a subcommand of Playwright even though it is not in
`playwright --help`.

```json
{
  "mcpServers": {
    "playwright-test": {
      "command": "playwright",
      "args": [
        "run-test-mcp-server",
        "--headless",
        "-c",
        "e2e/playwright.config.ts"
      ]
    }
  }
}
```

`command` is `playwright`, not `npx`. The generated file often says `npx`; replace it.
`npx` is not in the devshell and would fetch an unpinned version, so the MCP server and
the test runner could quietly disagree. Claude Code treats `.mcp.json` as project-scoped
and asks for approval; approve it.

## 6. MCP for OpenCode

OpenCode's background service does **not** inherit the terminal's devshell `PATH`. A
command that works in your shell can still fail to spawn:

```text
✗ playwright-test  failed: NotFound: ChildProcess.spawn
```

Launch it through the environment instead:

```sh
opencode mcp add playwright-test -- \
  direnv exec . playwright run-test-mcp-server --headless \
  -c e2e/playwright.config.ts
```

If the project does not use direnv, use `nix develop --command`:

```sh
opencode mcp add playwright-test -- \
  nix develop --command playwright run-test-mcp-server --headless \
  -c e2e/playwright.config.ts
```

Then verify:

```sh
opencode mcp list
# ○ playwright-test  pending
# ✓ playwright-test  connected
```

`direnv exec` writes its environment-loading lines to stderr, so they do not corrupt the
JSON-RPC stream; if another wrapper prints to stdout, move it to stderr or the handshake
will fail. A server that is configured but not connected is not wired. The tools appear as
`playwright-test_*` (or under `tools["playwright-test"]` in Code Mode); a session may need
to be restarted before its catalog sees them.

## 7. The three agents

```sh
playwright init-agents --loop=claude -c e2e/playwright.config.ts
```

This writes `.claude/agents/playwright-test-{planner,generator,healer}.md`. They drive the
browser through the test runner's own MCP server and run on the session's existing
authentication; no API key is involved. Regenerate all three after a Playwright upgrade,
because the MCP tool list changes:

```sh
playwright init-agents --loop=claude -c e2e/playwright.config.ts
```

The planner explores the running app and writes a plan; the generator turns a plan item
into TypeScript while checking selectors live; the healer replays a failing test, reads
`e2e/test-results/<slug>/error-context.md`, and patches it. Ask for plans in `e2e/specs/`
explicitly: the generated definitions' examples say a bare `specs/`.

## 8. Verify by looking

Run the bundled check from the project root:

```sh
bash ~/.claude/skills/agentic-playwright-nix/scripts/check.sh
```

Then prove it with a page, not with a version string:

1. Start the e2e server through the project's recipe.
2. Open the app with the MCP browser (or `playwright test` if the MCP tools are absent).
3. Resize to **390×844** and to **1440×900**.
4. Take a screenshot of each, saving into a temporary directory (for example
   `.playwright-mcp/<feature>/`).
5. Open the images with an image-reading tool and describe what you see before asserting
   anything. Confirm the CSS and JavaScript actually loaded: an unstyled button, a giant
   SVG, labels running into inputs, or a dialog sitting inline in the page means the
   assets are stale or the stylesheet did not load.
6. Run at least one behavior test through the runner.

If the MCP tools are not in the current session, say so and use the CLI; do not claim
agentic visual validation you did not do.

The detailed look checklist, dimensions and failure catalogue are in
`~/.claude/skills/feature-e2e-nix/references/visual-review.md`; read it the first time
you take a screenshot, not after a user complains.

## Cache correctness: the correction that matters

A cache-first service worker plus an unversioned asset URL is a trap. The HTML is
network-only, but `/assets/app.css` and `/assets/app.js` are cached forever; after a
deploy a returning phone gets **new markup with the previous deploy's styles and
scripts**. The visible symptoms are exactly:

- a full-width inline SVG where an icon should be;
- title and blurb running together, labels and inputs on one line;
- a modal visible inline in the page instead of over it;
- control links with no spacing (`ManageLocation`);
- a photo that is a small square instead of the intended full-width row.

Make the asset URL part of the content identity:

- Compute one version from the bytes of every emitted asset (CSS, JS, vendored script,
  icon). In a Rust/rust-embed app, hash each embedded file's SHA-256 and concatenate a
  short prefix.
- Emit `/assets/app.css?v=<version>`, and the same for every script, icon and manifest
  icon. The page and the manifest must agree.
- Serve a versioned asset with `Cache-Control: public, max-age=31536000, immutable`;
  keep `sw.js` itself `no-cache`.
- In the service worker, keep cache-first **because the URL changes with the content**.
  Do not precache unversioned asset URLs. Bump the worker's cache version once so old
  shells are evicted; clients already controlled by the old worker will still request the
  new versioned URL, which is a miss, so the first load after the deploy is correct.
- Test it: the page's `<link rel="stylesheet">` matches
  `^/assets/app\.css\?v=[0-9a-f]{16}$`, the served stylesheet contains a rule the page
  depends on, and the response is `immutable`. If the project has no service worker, the
  same versioning still protects browser and CDN caches.

## Failure catalogue

| Symptom | Cause | Fix |
| --- | --- | --- |
| `npx: command not found` | The flake does not install npm | Use `playwright`, or `direnv exec . playwright` for OpenCode |
| MCP `failed: NotFound: spawn` | OpenCode's service lacks the devshell `PATH` | Configure `direnv exec .` or `nix develop --command` |
| MCP `pending` forever | Wrong command, missing browser, or stdout noise | Check `opencode mcp list`, run the command by hand, move wrapper output to stderr |
| `No tests found` from `just e2e -g "..."` | The shell stripped the quotes | Quote the whole argument or call `playwright test` directly |
| `Host system is missing dependencies` | Playwright is checking the host distribution | The store browsers are fine; set `PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true` |
| `--headed` or `--ui` fails | The default shell has only the headless shell | `nix develop .#headed` |
| New UI looks unstyled after deploy | Unversioned assets cached by the worker | Content-version URLs, bump the worker cache |
| Modal covers only the top bar | `backdrop-filter`/`transform` made an ancestor the containing block for `position: fixed` | Render the dialog outside that ancestor |
| Delete button below the image | The JS button did not match `.tile-delete button` | Position the button itself; share the selector with the no-script form |
| Capture buttons differ in height | Different padding on the labels' spans | Make the labels flex items and share a min-height |

## Do not

- Add `package.json`, run `npm install`, or run `npx playwright install`.
- Add Firefox and WebKit to the default closure "just in case".
- Use the separate `playwright-mcp` package.
- Cache `/assets/*` under a URL that does not change with the bytes.
- Store fixture secrets in the repository; mint them per run.
- Edit the flake silently. Show the change and let the user approve.

When the check passes and a phone screenshot has been looked at, return to
`feature-e2e-nix` and continue there.
