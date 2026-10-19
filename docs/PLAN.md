# Implementation plan

Current increment: [UI upgrade](UI-UPGRADE.md), implemented in v0.2.0-local. The item browser, fixed sync panel, history view, tools, and saved geometry pass local tests; in-game visual acceptance remains.

Implemented in `0.1.5-local`: [merge shared profession lists and track character contributions](MULTI-CHARACTER-SYNC.md), including schema migration, `/gcs history`, and an automated two-character/reload regression in both layouts. All local checks pass. In-game integration gates remain open; see [local testing](LOCAL-TESTING.md).

This plan implements [the PRD](PRD.md). The UI upgrade is ready for in-game review. Cleanup/rebuild was dropped on 2026-10-19; sync stays additive.

Gorloc CraftScan belongs to the Gorloc suite and uses `GorlocCraftScan` as its add-on folder and identifier. Prioritize the user's price-refresh workflow: prepare profession material lists, search them in Auctionator, and verify the resulting prices in the user's crafting profit add-ons.

Deduplication from Phase 4 has been moved into the local build. Preview groups materials by item ID, and export combines equivalent searches without quality filters.

## Phase 0 — Prove the two integrations

Implemented in 0.1.4-local: detect the logged-in character’s crafting professions, select one, automatically open it for scanning, and close only a matching session opened by CraftScan. A separate ProfessionSession module owns the bounded loading wait and cleanup. API research and live acceptance checks are in [profession automation](PROFESSION-AUTOMATION.md).

Create a minimal diagnostic add-on on the chosen client. Record the client build, flavor, Auctionator version, and fixture profession. Use documented API calls; do not modify installed add-on source.

### Profession prototype

1. Open the player's profession and wait until its data source is stable.
2. Probe `GetAllRecipeIDs()` and read recipe metadata. Count learned, unlearned, excluded, and unavailable entries separately.
3. Repeat with text, learned/unlearned, makeable, and category filters changed. Verify that enumeration is independent of these filters.
4. Compare results with each exposed child skill line. Establish the mapping between expansions and profession skill lines, and verify how to identify the current game expansion for the client. Use explicit skill-line membership checks for recipes, independent of the profession window's current selection. The local build matches Blizzard's localized expansion labels only for the initial current-expansion default, and leaves selection empty if no match exists; validate that default in-game.
5. Read schematics for ordinary, unlearned, ranked, quality-based, and special-slot recipes. Compare them manually with the game UI.
6. Verify the data lifecycle on profession switching, reopening, and learning a new recipe.

If enumeration cannot cover the selected expansions without switching context, implement a controlled scan that snapshots and restores the original context. If coverage still cannot be established, mark the affected selections unsupported or incomplete. Do not silently substitute the profession window's current scope or present a partial cross-expansion result as complete.

### Auctionator prototype

1. Verify the current public list-management contract in-game. The local adapter implements `CreateShoppingList` and `ConvertToSearchString` call shapes corroborated by an independently published integration; see [local testing](LOCAL-TESTING.md). Mock tests do not establish installed-version compatibility.
2. Create a uniquely named test list with two ordinary materials and two qualities of the same material. Check exact-name matching, absence of quality restrictions and quantity targets, and one search per material name across qualities.
3. Reopen Auctionator and reload the UI; verify persistence and search behavior.
4. Test name collisions, repeat export, merge, and failure reporting. Establish whether creation works with the auction house closed.
5. If public list creation is unavailable, validate Auctionator's supported import format with an export/import round trip. Document the manual import flow before implementing serialization.
6. Identify the user's crafting add-ons and configured price sources. Record a sample material price before and after running the list in Auctionator; verify the downstream calculation uses the updated value. Check quality variants and an item without current listings. Record any missing-price or refresh limitations instead of assuming compatibility.

Crafted outputs were added in 0.1.3-local. Read output quality IDs and the schematic output ID, falling back to output item data or its item hyperlink. Resolve and classify these alongside materials. Validate known/unlearned, expansion scope, bound outputs, non-item recipes, and quality variants in-game.

**Exit gate:** one persistent shopping list created by the proposed route and one independently checked profession scan. If neither public creation nor verified import is available, record list creation as blocked; do not replace it with a multi-search and declare success. Other scanner work can continue independently.

## Phase 1 — Scanner and normalized data

Use small modules with a pure collection layer:

```text
GorlocCraftScan/
  GorlocCraftScan.toc
  Core.lua
  ProfessionScanner.lua
  MaterialCollector.lua
  ItemResolver.lua
  AuctionatorAdapter.lua
  UI.lua
  Locales/enUS.lua
tests/
  fixtures/
  collector_spec.lua
  scanner_spec.lua
  adapter_spec.lua
```

Set the TOC interface to the tested client build during implementation. Persist preferences, schema version, and per-character/profession/scope scan and sync history. Label it as history; offline character data is not refreshed automatically.

Proposed internal records:

```text
ScanContext:
  token, character, clientBuild, baseSkillLineID, selectedChildSkillLineID,
  recipeMode, currentExpansionID, selectedExpansionIDs[], selectedSkillLineIDs[]

Recipe:
  recipeID, skillLineID, learned, rankRelationship, slots[], exclusionReason?

Slot:
  slotIndex, required, quantityRequired, alternatives[], variableQuantities[]

Material:
  itemID, localizedName?, reagentTier?, recipeIDs[], slotReferences[],
  tradabilityStatus

ScanResult:
  context, recipes[], materialEntries[], nonShoppingRequirements[],
  excludedRecipes[], unresolvedRecipes[], unresolvedItems[], complete
```

Collection retains occurrences internally; resolution aggregates material and output item IDs separately with recipe provenance. Combined export unions both sets. Separate export creates ` - Materials` and ` - Items` destinations.

Implement an event-driven state machine: `idle → waiting → scanning → resolving → preview → exporting → done/error`. New scans, profession changes, and cancellation invalidate the prior token. Item callbacks must check that token before writing results.

Start with short time-budgeted scan batches, targeting at most roughly 5 ms of scanner work per frame on the test machine. This is an engineering target to measure, not a measured result. Cache within a scan, bound retries, and avoid a permanent per-frame polling loop.

**Exit gate:** deterministic fixtures produce the expected recipe/material entries, with unique item IDs and preserved recipe/slot provenance, and incomplete data can never be mistaken for a complete empty result.

## Phase 2 — Preview and material policies

Build a small native window accessible through `/gorloccraftscan`; add the profession-window button once loading and placement are verified.

Implement known/all-exposed selection and an expansion checklist allowing any combination. Start each export session with the current game expansion selected; provide select-all and reset-to-current actions. Require a nonempty selection, and show an explicit empty/unavailable state if the current expansion has no exposed recipes. Keep the checklist independent of Blizzard's profession-window selection.

Filter recipes to the selected expansion skill lines before collecting materials, then combine their entries. Deduplicate materials across that selection while preserving all recipe/slot provenance. Include the expansion selection in the scan context and preview. Keep the fixed list name stable as `Gorloc - <Profession>` across scope changes. Changing the selection invalidates any pending scan or preview. Show read-only list destinations, progress/cancel, recipe count, material list, and an expandable explanation of alternatives and exclusions. Label counts as unique material items; quality variants with different IDs can share an exported search. Preserve per-slot quantities for inspection without attaching purchase quantities to the catalog.

Resolve names and quality metadata asynchronously using the client-supported item-loading mechanism verified during implementation. Keep IDs as the identity throughout. Unknown names must never be serialized as empty searches.

Classify currencies and definitely non-auctionable items separately. If item metadata is insufficient, keep an explicit unknown state. Implement the material rules from the PRD in the pure collector so they can be checked independently of the UI, including deduplication.

**Exit gate:** a player can understand the scope, alternatives, and omissions before exporting; switching profession during resolution cannot contaminate the preview.

## Phase 3 — Persistent list export

Keep all Auctionator-specific behavior in one adapter with conceptual methods `GetCapabilities`, `BuildSearchTerms`, and `MergeList`. These are this add-on's interfaces, not claims about Auctionator function names.

Feature-detect the established public functions. Serialize exact-name searches with no quality or rarity restriction. Validate every payload and read every destination before changing lists. Use the guarded read-only existence check described in [research](RESEARCH.md); never interpret a read error as absence. Union existing and new terms, write through `CreateShoppingList`, and verify all preserved/new terms through `GetShoppingListItems`. Normal sync has no deletion path. Unsupported integration or failed reads stop before writes.

Show the destination and explain that sync adds missing searches and keeps existing ones. Partial scans require explicit opt-in to add resolved entries; use the same name without a suffix. Store verified outcomes per destination and keep failed attempts separate. Keep scanning independent of auction-house access and never initiate purchases.

If manual import is the chosen route, show selectable text plus concise import instructions. Do not call it direct list creation, and do not assume clipboard APIs are available. A plain-text material dump is a separate diagnostic export.

**Exit gate for local testing:** exported material coverage matches the preview, survives reload, and repeated export preserves unrelated lists. Duplicate item IDs and equivalent searches must be removed in both layouts. Preflight both split payloads before the first write, and report which destination succeeded if the second sync fails.

## Phase 4 — Deduplication (implemented in 0.1.1-local; in-game validation pending)

1. Aggregate material entries by item ID across recipes and selected expansions, retaining all recipe/slot provenance and distinct quality variants.
2. Deduplicate equivalent serialized search terms without dropping coverage; quality variants sharing a name intentionally use one unrestricted search.
3. Use the deduplicated result in both preview and export, and display accurate unique-material counts.
4. Verify shared ingredients within a recipe, across recipes, and across expansions; also verify equivalent terms and repeated exports.

**Go-live gate:** duplicate items/materials and equivalent search terms are removed, intended quality variants remain searchable, and re-export does not introduce duplicates. This phase must pass before release.

## Phase 5 — Verify and package

Automate the collection and adapter contracts with stubbed client APIs. Use in-game tests for engine behavior and Auctionator interoperability; mocks cannot establish those facts. The matrix below describes release acceptance; uniqueness and repeat-sync checks are included in local tests.

| Test | Expected result |
| --- | --- |
| Shared ingredient across several recipes | One material entry with all contributing recipes. |
| Known versus all-exposed | Correct recipe membership; missing metadata reported. |
| Zero owned materials | Learned recipe remains included. |
| Search/category filters and collapsed groups | Full-scope scan result unchanged. |
| New export session | Current game expansion selected, even if Blizzard's profession window displays an older expansion. |
| One, several, or all expansions | Only selected expansions contribute recipes; shared materials appear once in the combined list. |
| Reset to current expansion | Selection returns to the current game expansion; pending scan/preview is invalidated. |
| No expansion selected | Preview and export disabled until a selection is made. |
| Current expansion unavailable | Explicit empty/unavailable state; no silent fallback to older expansions. |
| Expansion switch | Correct scope; original UI context restored if changed by scanner; stale results ignored. |
| Alternative qualities sharing a name | IDs preserved; one unrestricted search covers all same-name qualities without duplicate equivalent searches. |
| Required special slot and optional slot | Required input included or flagged; optional excluded explicitly. |
| Currency, bound material, vendor material | Correct preview classification; no currency searches. |
| Intermediate reagent | Included directly; no recursive expansion. |
| Ranked/dummy/recraft/salvage recipe | PRD policy applied and exclusions visible. |
| Cold item cache or failed item load | Bounded loading; unresolved entries visible; no blank terms. |
| Cancel or switch profession during callback | Old callback ignored. |
| Empty or partial scan | Empty scans do not write; partial additions require explicit opt-in. |
| Existing destination and repeated export | Explicit collision behavior; no duplicate terms or unrelated changes. |
| Missing/unsupported Auctionator | Preview works; export explains the limitation. |
| Reload and AH closed/open | Persistence and access requirements match Phase 0 findings. |
| List creation versus AH search | Creating a list does not claim prices were refreshed; the player runs the search in Auctionator. |
| Downstream crafting price source | A recorded supported add-on/configuration consumes the material prices refreshed by the list search. |
| Item without current auctions | No claim of a fresh observed price; downstream missing/stale-price behavior documented. |

In-game coverage should include a simple older-expansion recipe set, a profession with quality reagents, an unlearned recipe, a required special reagent, Enchanting, and Cooking. Check another locale when available; otherwise record localization testing as incomplete. Measure the largest available profession scan for responsiveness.

Package an installable folder with setup instructions, supported versions, known limitations, and the exact compatibility results. Do not publish or claim Classic support without flavor-specific testing.

## Suggested order after MVP

1. Prototype a Gorloc **Refresh prices** action delegated to Auctionator, proving price persistence and downstream compatibility.
2. Investigate direct Blizzard-API scanning with verified Auctionator ingestion; proceed only if it retains the required price-store compatibility. Follow the [research and proof-of-concept gates](AH-SCANNING.md). Do not write Auctionator's private database or equate received results with persisted prices.
3. Broader output coverage for random or reagent-dependent results not exposed by the current output APIs.
4. Optional reagent catalog toggle, preserving alternative groups.
5. Additional client flavors through separate scanner adapters.

Purchase-quantity planning and inventory subtraction are outside the current roadmap; prioritize price coverage and downstream compatibility.

Do not estimate the full project from the scanner alone: the Phase 0 integration results determine whether direct export, manual import, and all-expansion support stay small.
