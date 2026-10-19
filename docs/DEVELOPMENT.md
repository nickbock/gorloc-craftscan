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

1. Update `## Version` in `GorlocCraftScan/GorlocCraftScan.toc` and `G.VERSION` in `GorlocCraftScan/Util.lua`, and add a [CHANGELOG](../CHANGELOG.md) entry.
2. Check `## Interface` against the current client build.
3. Run the tests and the in-game checklist.
4. Build the ZIP with `python3 tools/package.py`. It contains the files listed in the TOC plus `LICENSE`, under `GorlocCraftScan/`, and is written to `dist/`.
5. Commit, tag the version (`git tag v1.0.0`), and upload the ZIP to CurseForge and Wago.

Once the CurseForge and Wago projects exist, add `## X-Curse-Project-ID` and `## X-Wago-ID` to the TOC.

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
