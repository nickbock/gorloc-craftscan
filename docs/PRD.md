# PRD: Gorloc CraftScan

Status: proposed. Research date: 2026-10-07. Add-on name: **Gorloc CraftScan**. Folder and identifier: `GorlocCraftScan`.

Implementation status: `0.2.0-local` implements merge sync and account-wide character/profession/scope history. Searches remain deduplicated and unrestricted by quality, using the same stable list names. Partial/empty scans cannot erase earlier contributions. Release acceptance remains open; see [local testing](LOCAL-TESTING.md) and [shared profession lists](MULTI-CHARACTER-SYNC.md).

Suite: Gorloc. Description: “Build Auctionator price-scan lists for your professions.”

## Problem and outcome

A player wants to refresh auction-house prices for the materials used by a profession, then use those prices in other crafting add-ons' profit calculations. They need an Auctionator shopping list covering those materials without opening every recipe and adding ingredients manually.

The add-on will detect the current character’s crafting professions, open the selected profession for scanning, collect its recipe materials and crafted outputs, show a preview, and sync one combined list or separate Materials and Items lists. Players can choose known recipes or all recipes exposed by the game. The technical evidence and limitations are recorded in [RESEARCH.md](RESEARCH.md).

The intended workflow is: **profession recipes → material price-scan list → player runs the list in Auctionator → compatible crafting add-ons use the refreshed prices**. This add-on prepares the list; Auctionator performs the auction-house search, and the player's crafting add-ons calculate and display profits. Verify that price updates reach the chosen downstream add-ons before claiming that integration works.

Prices must remain saved in Auctionator for the user's existing crafting-add-on workflow. A future Gorloc-initiated scan must preserve that compatibility; a separate Gorloc price database alone does not satisfy it.

## Initial decisions

Expansion selection, the current-expansion default, deduplication, and searches without quality restrictions are user requirements. Deduplication was moved into the local build at the user’s request. The remaining defaults are proposals.

| Decision | Initial behavior |
| --- | --- |
| Client | Retail first; pending user confirmation. |
| Character | Scan the logged-in character; retain account-wide history and merge contributions into shared lists. |
| Profession | Select a detected crafting profession or Cooking; open it automatically for scanning. |
| Recipe selection | Known recipes by default; all exposed recipes as an option. |
| Expansion scope | Select one or more expansions; default to the current game expansion. Provide an explicit all-expansions shortcut. |
| Output | Materials and crafted items in one combined list or two separate lists, with no purchase quantities. Deduplicate item IDs and equivalent exported searches. |
| Reagent qualities | Include all exposed alternatives, visibly identified as alternatives; export searches without quality filters. |
| Optional reagents | Excluded initially; show that exclusion in the preview. |
| Export | Create a persistent Auctionator list through its supported interface. |

The material catalog answers “which material prices should I refresh for this profession?” Include materials even when the player already owns them. Purchase quantities and inventory subtraction are unnecessary for this price-refresh workflow.

## User flow

1. Enter `/gcs` and choose a detected profession, or click CraftScan from an existing profession window.
2. Choose **Known recipes** or **All recipes available in this profession**.
3. The first **Scan recipes** loads profession data and uses the current game expansion. Review the **Expansions** checklist once loaded. Select any combination, or use **Select all**. **Current expansion** resets the selection to the default.
4. Click **Scan recipes** to rescan after changing scope. CraftScan opens the selected profession and closes it afterward only if it opened the window. The window shows recipes included, materials, alternatives, and any unavailable data. Show unique item counts with grouped recipe/slot details; combine identical export searches across qualities.
5. Choose **Combined** or **Separate**, review the fixed list destinations, and click **Sync Auctionator lists**.
6. Open Auctionator's Shopping tab at the auction house and run the saved list to refresh prices.
7. Review crafting profits in the player's compatible crafting add-on, configured to use the relevant Auctionator price source.

Combined example: `Gorloc - Alchemy`. Separate examples: `Gorloc - Alchemy - Materials` and `Gorloc - Alchemy - Items`. Expansion and recipe scope stay in the preview, not in the list name.

“Current expansion” means the active game expansion for the supported client, independent of which expansion is selected in Blizzard's profession window. Each newly opened export session starts with that default. If the profession exposes no recipes for the current expansion, show an empty/unavailable state and let the player choose another expansion; do not silently select older expansions. At least one expansion must be selected before preview or export. Both recipe modes apply only within the selected expansions, and their materials and crafted outputs follow the chosen list layout, with duplicate items/searches removed.

Default to `Gorloc - <Profession>` without character, expansion, recipe scope, time, or sequence suffixes. In Separate mode append ` - Materials` and ` - Items`. **Sync Auctionator lists** creates or merges into the selected layout’s named lists, retaining searches from earlier scans and other characters. Use fixed standard names; do not offer custom names or a migration option. The UI states that sync adds missing searches and keeps existing ones. Other list names, including the other layout and older timestamped exports, remain untouched. Skip empty sections and say that any previous list for an empty section was left unchanged.

## MVP requirements

These are go-live acceptance conditions. Deduplication now also applies to the local build: preserve distinct item IDs and recipe/slot provenance, and combine equivalent search terms without quality restrictions. Existing-list protection still applies during local testing.

| ID | Requirement | Acceptance condition |
| --- | --- | --- |
| R1 | Detect, select, and scan a local crafting profession. | No recipes from another profession, linked player view, or guild view enter the result. |
| R2 | Support known-only selection. | Every included recipe is learned; recipes remain eligible when the player lacks materials. |
| R3 | Support all-exposed selection where the client permits it. | Known and unlearned recipes are included; coverage and omissions are visible. If unavailable, disable this option with an explanation. |
| R4 | Support selection of one or more expansions, defaulting to the current game expansion. | Only selected expansions contribute recipes. Select-all and reset-to-current work; text filters and the profession window's expansion selection do not override this scope. |
| R5 | Collect required consumed reagents. | Materials shared by recipes appear once; preview retains recipe provenance and per-slot quantities. |
| R6 | Preserve alternative ingredients and qualities. | Alternatives can be inspected without being described as simultaneous requirements. Distinct item IDs survive collection. |
| R7 | Separate non-shopping requirements. | Currencies and definitely non-auctionable items appear in a separate preview section. Tools/stations are not added as consumed ingredients. |
| R8 | Preview before export. | Counts, scope, list name, exclusions, and incomplete data are visible. |
| R9 | Create a persistent Auctionator list. | Entries are searchable and the list survives UI reopening and `/reload`. A transient multi-search is insufficient. |
| R10 | Handle repeated exports safely. | Repeated or narrower syncs add no duplicate generated terms and preserve earlier searches; unrelated lists remain untouched. |
| R11 | Handle unavailable data. | Loading, unsupported, empty, partial, and complete states are distinct. No empty result overwrites a useful list. |
| R12 | Remain responsive. | Scanning yields between batches, supports cancellation, and ignores callbacks from canceled scans. |
| R13 | Validate the price-refresh workflow. | On a recorded client/Auctionator/crafting-add-on combination, searching the generated list updates the material prices used by the downstream profit calculation. Creating a list alone must not be reported as refreshing prices. |
| R14 | Track account-wide sync history. | Retain GUID, display name/realm, profession, expansion/mode scope, latest scan completeness, last verified sync time and whether the latest sync failed. Partial or failed attempts cannot erase the last successful sync time. |

## Material rules

These are product rules for the implementation, including how ambiguous cases should be represented.

- Maintain recipe and item IDs internally; resolve localized names for display and search only at the boundary.
- Retain required slot quantities in the preview, even though the default export has no quantity targets.
- Deduplicate by item ID and deduplicate equivalent search terms during serialization without losing coverage information.
- For a required slot accepting several materials or qualities, include the possible items in the catalog and label the group as alternatives. Use exact-name searches without reagent-tier or rarity restrictions, so all qualities are searched together.
- Include intermediate crafted reagents as ingredients. Do not recursively replace them with their own raw materials.
- Keep vendor-sold items eligible when they can also be traded. Vendor availability does not prove an item cannot appear on the auction house.
- Definitely soulbound/account-bound materials and currencies remain visible as requirements but are excluded from auction searches. Uncertain tradability is labeled; do not claim exhaustive auctionability detection.
- Exclude optional embellishments, finishing reagents, and similar choices in the first release. Required special slots must still be handled or explicitly reported as unsupported.
- Skip dummy, recraft-only, gathering, and salvage entries in the first release and report the exclusions. Salvage inputs need a separate design. Include ordinary enchanting and Cooking recipes when their consumed reagents are available.
- Preserve distinct recipe IDs and rank relationships. A catalog may union their materials; a later quantity mode must select the applicable rank instead of summing upgrades indiscriminately.

## Reliability and user messages

| State | Behavior |
| --- | --- |
| No profession open | Let the player select a detected crafting profession; Scan opens it automatically. |
| Profession loading | Wait for stable data, show progress, allow cancellation. |
| Missing item names | Resolve asynchronously with bounded retries; show remaining unresolved items. |
| Profession changes mid-scan | Cancel the scan and require a fresh preview. |
| Partial scan | Show missing recipes/materials; require explicit opt-in to add resolved entries to the named list; do not add a suffix. |
| Unsupported Auctionator version | Keep preview usable; disable direct creation and explain compatibility. |
| No searchable materials or outputs after filtering | Show an empty state; do not create or modify a list. |
| Export fails | Keep the preview available for retry; do not report success. |

The add-on should work without the auction house being open for scanning. Whether direct list creation can also happen away from the auction house must be established in the initial integration test; if not, retain the prepared preview and ask the player to export at the auction house.

## Scope boundaries

The MVP is a Lua add-on using native WoW frames and an Auctionator adapter. It needs no web service, Battle.net credentials, pricing database, or external recipe database. Auctionator may be an optional load dependency so preview remains usable when it is missing; it is required to complete direct list creation.

Out of scope for the shopping-list MVP: automatic buying/crafting, implementing a separate auction-house scanner, profit calculation/display, profit optimization, leveling routes, cross-character scanning, inventory/bank subtraction, crafting-order queues, recursive subcrafting, and guarantees about recipes the game does not expose.

## Candidate follow-up: refresh prices from Gorloc

Investigate a **Refresh prices** action with the auction house open. The recommended first prototype delegates searches to Auctionator. Direct Blizzard-API scanning is a separate candidate only if its results reliably reach Auctionator's price store through a verified integration. Success requires prices readable through Auctionator after reload and usable by the chosen crafting add-ons. This follow-up is research scope, not an addition to the first local build. See [direct scanning research](AH-SCANNING.md).

## Price coverage decisions to validate

Identify which crafting add-ons and price-source settings the user uses. Do not assume every crafting add-on consumes Auctionator data, or that a shopping search refreshes every relevant price field.

Crafted outputs are now approved scope and included in the local build. Collect the output item IDs and exposed quality variants of the same selected recipes. Bound outputs and explicit non-item recipe types stay visible as exclusions; missing item-output data makes the scan partial. Combined mode unions inputs and outputs, while Separate mode keeps them in Materials and Items lists. Both search without quality restrictions. Optional reagents and unexposed random or reagent-dependent outputs remain coverage limits.

An item without auction listings does not provide a new observed price. Check how Auctionator and the downstream add-on handle missing or older prices; do not equate a completed search with fresh prices for every item or guaranteed accurate profits.

Purchase quantities and inventory subtraction are deferred ideas outside the current roadmap, since they do not advance the stated price-refresh goal.

## Release success

The first release is ready when the player can create a correct persistent list from a complete known-recipe scan, use it to refresh material prices consumed by at least one of their chosen crafting add-ons, and repeat the workflow while preserving existing lists. All-exposed mode must either pass its coverage checks or clearly declare its limit. Deduplication of items/materials and equivalent search terms must be implemented and verified before go-live, including shared materials across recipes and selected expansions. The [implementation plan](PLAN.md) contains the test matrix and release gates.
