# Playwright recipes for visual acceptance

Use the flake's Playwright, not `npx`, and a mock server with stable fixtures. If another
checkout or worktree may be serving the same port, use an isolated port for the run; a
screenshot from the wrong tree is not evidence.

## Screenshot the state matrix

```ts
const states = [
    { name: "inbox", url: "/" },
    { name: "mailbox", url: "/mailbox/sent" },
    { name: "message", url: "/message/m01" },
    { name: "compose", url: "/compose" },
    { name: "reply", url: "/compose?to=mira%40example.com" },
    { name: "search", url: "/search?q=invoice" },
    { name: "search-empty", url: "/search?q=zzzz-no-match" },
];

for (const viewport of [
    { name: "desktop", width: 1440, height: 900 },
    { name: "phone", width: 390, height: 844 },
]) {
    await page.setViewportSize(viewport);
    for (const state of states) {
        await page.goto(state.url);
        await page.screenshot({
            path: `screenshots/${state.name}-${viewport.name}.png`,
            fullPage: true,
        });
    }
}
```

Open every resulting PNG with the image tool. Do not treat the loop as the review.

## Drive the interaction

```ts
await page.getByRole("link", { name: "Compose" }).click();
await expect(page.locator(".compose-form")).toBeVisible();
await page.locator('input[name="subject"]').fill("A long subject that should not wrap per character");
await page.locator('textarea[name="body"]').fill("A body with enough text to reveal a narrow pane.");
await expect(page.getByRole("button", { name: /Send/ })).toBeVisible();

await page.getByRole("link", { name: "Reply" }).click();
await expect(page.locator('input[name="to"]')).toHaveValue(/@/);
```

## Assert geometry, not presence

```ts
const workspace = (await page.locator(".workspace").boundingBox())!;
expect(workspace.width).toBeGreaterThan(900);

const form = (await page.locator(".compose-form").boundingBox())!;
expect(form.width).toBeGreaterThan(600);

expect(
    await page.evaluate(
        () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
    ),
).toBe(true);

// A single-column page must not reserve a splitter track.
await expect(page.locator(".app")).toHaveClass(/is-single/);
await expect(page.getByRole("separator", { name: "Resize folder list" })).toHaveCount(0);
```

Use `expect.poll` for values that settle after a layout pass:

```ts
await expect
    .poll(async () => (await page.locator(".compose-pane").boundingBox())?.width)
    .toBeGreaterThan(600);
```

## Drag a splitter

```ts
async function drag(page: Page, handle: Locator, dx: number) {
    const box = (await handle.boundingBox())!;
    const x = box.x + box.width / 2;
    const y = box.y + box.height / 2;
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x + dx, y, { steps: 5 });
    await page.mouse.up();
}

await drag(page, page.getByRole("separator", { name: "Resize message list" }), 100);
```

Then navigate to another mailbox and reload; the width must survive if the app persists
it. A full-page navigation is the usual place where in-memory widths disappear.

## Regression test per bug

Add the smallest test that fails on the old layout and passes on the fixed one. Keep it
next to the other e2e tests. Run the full suite, not only the new test:

```bash
nix develop -c just e2e
```

Re-take the phone and desktop screenshots after the fix, open them, and compare with the
before screenshot. If the fix changed a shared layout, check the split view, mobile, and
one unrelated subpage.

## Server isolation

If the config uses `reuseExistingServer: true`, a stale server from another checkout can
answer the test. For a visual acceptance run:

- use a unique port, or
- set `reuseExistingServer: false`, or
- stop the other server and confirm the port owner.

The test must prove the current working tree, not whichever process happened to be
listening.
