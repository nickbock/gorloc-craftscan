# Development

Add-on folder and identifier: `GorlocCraftScan`. Targets WoW Retail 12.1.5 (TOC interface `120105`).

## Tests

The tests need only Lua 5.1. They use simulated WoW and Auctionator APIs, so they do not prove in-game compatibility; the [in-game checklist](LOCAL-TESTING.md) covers that.

```sh
lua5.1 tests/run.lua
lua5.1 tests/multi_character.lua
lua5.1 tests/session.lua
lua5.1 tests/ui_model.lua
lua5.1 tests/ui_smoke.lua
```

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) in GitHub Actions ([release.yml](../.github/workflows/release.yml), configured by [.pkgmeta](../.pkgmeta)). Pushing a tag runs the tests, packages `GorlocCraftScan/` plus `LICENSE`, and uploads it to CurseForge, Wago and a GitHub release. The tag is the version: the packager replaces `@project-version@` in the TOC and `Util.lua`. Tags containing `alpha` or `beta` are uploaded as alpha/beta files.

1. Add a [CHANGELOG](../CHANGELOG.md) entry; the packager uploads this file as the changelog.
2. Check `## Interface` in the TOC against the current client build.
3. Run the tests and the in-game checklist.
4. Commit, then push an annotated tag: `git tag -a 1.0.1 -m "1.0.1"` and `git push origin main 1.0.1`.

One-time setup:

- Add `## X-Curse-Project-ID` and `## X-Wago-ID` to the TOC once the projects exist. Without them the packager skips that site.
- Add the repository secrets `CF_API_TOKEN` ([CurseForge API token](https://authors.curseforge.com/#/settings/api-tokens)) and `WAGO_API_TOKEN` ([Wago API token](https://addons.wago.io/account/apikeys)). The GitHub release uses the built-in `GITHUB_TOKEN`.

For a local test install, copy `GorlocCraftScan/` into `Interface/AddOns/`; the version then shows as `@project-version@`. To build a ZIP locally without uploading, run the packager's `release.sh -d` from the repository root. It writes to `.release/` and needs `zip`.

## Scope

- Detected profession selection and automatic open/wait/scan/close, with cancellation and protection for preexisting windows.
- Known recipes by default; optional unlearned recipes exposed by the game.
- Multiple expansion selection, select-all, and reset-to-current.
- Required reagents and crafted outputs, including exposed quality variants. Intermediate items can appear in both sections; the combined list searches them once.
- Partial-scan reporting, explicit partial-sync opt-in, progress, and cancellation.
- Currency, known bound-item, and non-item output exclusions; optional reagents, recrafting, gathering, and salvage are excluded.
- Materials are deduplicated by item ID. Identical searches are combined; searches have no quality filter and cover all qualities.
- Additive sync: existing and manual searches are always kept. Account-wide history keeps only what the Characters tab shows.
- Not included: a direct AH scanner, profit calculation, purchase quantities, automatic purchases, or list cleanup.

The existence check for Auctionator lists uses the non-public `Auctionator.Shopping.ListManager:GetIndexForName`. If it is unavailable or returns something unexpected, sync stops before writing. Recheck it after Auctionator updates.

## Planning and research

- [In-game test checklist](LOCAL-TESTING.md)
- [UI upgrade plan](UI-UPGRADE.md)
- [Shared lists and character sync history](MULTI-CHARACTER-SYNC.md)
- [Product requirements](PRD.md)
- [Implementation plan](PLAN.md)
- [Research and sources](RESEARCH.md)
- [Direct AH scanning and Auctionator compatibility](AH-SCANNING.md)
- [Profession detection and automatic open/close](PROFESSION-AUTOMATION.md)
