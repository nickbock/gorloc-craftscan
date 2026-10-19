# Gorloc CraftScan in-game testing

This build replaces the previous UI with a compact native Blizzard window. Simulated tests cover the scan/sync flow, additive merging, history, profession sessions, dropdowns, retries, and cancellation. Actual native rendering and Auctionator persistence require in-game checks.

Validation: 49 logic tests, 21 merge/history tests, 17 profession-session tests, 4 UI-model tests, the headless UI/controller scenario, and Lua 5.1 syntax checks passed. The 12-file ZIP passed its archive integrity check.

## First test

1. Extract `dist/GorlocCraftScan-1.0.0.zip` into `Interface/AddOns/`. Enable Gorloc CraftScan and Auctionator. Reload the UI when replacing an existing installation.
2. With professions closed, run `/gcs`. Verify the profession dropdown includes your crafting professions and Cooking. Select one and click **Scan & Sync**. Its window should open, scan, close, and sync the fixed Auctionator destination automatically.
3. Verify the current expansion is selected initially. Adjust the expansion dropdown and repeat; choices should survive automatic reopening. If the current expansion is unavailable, choose another explicitly. Use `/gcs debug` if metadata is unexpected.
4. Check representative recipe ingredients and crafted outputs against the resulting Auctionator list. A known recipe contributes even when you own none of its materials. Try **All exposed recipes** and a multi-expansion selection; unavailable data should produce a partial scan.
5. Try Combined and Separate layouts. Names must be `Gorloc - <Profession>`, or that name plus ` - Materials` / ` - Items`. Same-name quality variants must yield a single unrestricted search covering all qualities. An item used as both an input and output appears once in Combined.
6. Search the list at the AH. Compare a material/output price before and after in Auctionator and your crafting add-on. Creating or syncing the list alone does not refresh prices.
7. `/reload` and verify list contents, character history, and observed prices persist.

## UI acceptance

- Check 1920×1080 and 1280×720 at your usual UI scale. Verify the Blizzard frame, dropdowns, text, status, and bottom buttons fit. Check long profession/expansion labels and errors.
- Move by the header, `/reload`, and reopen. Position persists; the compact frame is not resizable.
- Verify dropdown selection labels, expansion checkmarks, Current/All shortcuts, and selecting no expansions. No selection disables the main action.
- Verify there are only Sync and Characters views, without item previews, report tools, or a diagnostics menu.
- A complete scan syncs automatically. An incomplete scan pauses with no writes, explains the issue, and offers **Sync available items**. Changing any scope/layout invalidates that confirmation. Empty scans never write lists.
- Verify **Details** shows missing data or a failed destination's message. A sync failure offers **Retry sync** without rescanning. If the second destination fails, Characters shows Sync failed with the first destination's sync time.
- Open Characters and scroll. Check status and last sync per row; the scrollbar only appears when rows overflow. `/gcs history` opens this view. No offline character is scanned.
- `/gcs debug` opens a separate selectable text panel. Escape closes the focused panel. Normal use requires no diagnostics.

## Session and cancellation checks

| Action | Expected result |
| --- | --- |
| Scan a profession already open | Reuse its window and leave it open afterward. |
| Cancel during loading or scanning | Stop; close only the owned, unchanged profession session; do not sync. |
| Close CraftScan or its profession during a scan | Cancel; delayed callbacks cannot finish or sync the old job. |
| Switch profession manually while scanning | Stop; leave the newly opened profession alone. |
| Enter combat while scanning | Cancel without protected cleanup or a deferred close. Main action works again after combat. |
| Learn or unlearn a profession | Refresh detection and invalidate an unavailable selection. |
| Change recipe knowledge | Invalidate previous scan data. |
| Disable Auctionator | Show dependency message and disable Scan & Sync; history/debug remain available. |
| Scan unfamiliar recipes with cold item data | Retry loading for a bounded period, then report unresolved data as partial. |
| Bound output or non-item recipe | No corresponding auction search. |
| Current expansion unavailable | Explicitly require selecting an available expansion. |

## Two-character acceptance

1. On character A, sync known/current recipes. Record a material or output unique to A.
2. On character B with the same profession but different recipes, sync the same list. Preserve A's searches and add B's once.
3. Return to A and sync a smaller expansion selection. B's searches remain. Repeat in Separate mode.
4. Add a manual filtered search in Auctionator, then sync; preserve it alongside unrestricted searches.
5. Verify both characters and their independent scopes/timestamps in Characters. A partial scan that has not been confirmed updates the scan timestamp without fabricating a sync timestamp. Reload and verify persistence.
6. Verify both missing-list creation and merging into an existing standard destination. Report `/gcs debug` if the guarded existence check blocks syncing.

## Compatibility notes

- The list adapter uses `CreateShoppingList(callerID, listName, searchStrings)` and `ConvertToSearchString(callerID, details)`. These call shapes are corroborated by an independent add-on's published integration; their behavior on the user's installed Auctionator still needs the tests above. [Published integration](https://raw.githubusercontent.com/VichobAddons/MajesticBeastTracker/v1.5.0/Core.lua).
- The read/merge call shapes and read-only `Shopping.ListManager:GetIndexForName(name)` existence check are corroborated by [CraftSim’s Shopping integration](https://raw.githubusercontent.com/derfloh205/CraftSim/main/Modules/Shopping/Shopping.lua). The public documentation did not establish a reliable missing-list read contract. This guarded private existence check is the only private integration; all reads of list contents and all writes use public APIs. If the check is unavailable, throws, or returns an unexpected value, sync stops before writes. Test both a new destination and an existing destination on the installed version.
- No Auctionator SavedVariables are modified directly. There is no separate Gorloc price store.
- Base names default to `Gorloc - <Profession>` regardless of expansion or recipe scope. Separate mode appends ` - Materials` and ` - Items`. Sync targets these exact names and preserves earlier searches. Earlier timestamped lists are left alone.
- Sync validates every payload and reads every destination before the first write. It unions existing and new searches, writes through `CreateShoppingList`, and verifies old and new searches through `GetShoppingListItems`. It never calls a deletion API. Nil, errors, malformed arrays, duplicate read-back searches, or missing read-back terms fail the sync. Empty sections are skipped. Split syncs are not atomic; a failure records any already-verified destination separately and allows retry without claiming both succeeded.
- Expansion membership uses skill-line IDs. The initial current-expansion selection matches Blizzard's localized `expansionName` against its localized current expansion label. If labels differ or the expansion is unavailable, it deliberately leaves the selection empty instead of choosing the newest learned expansion.
- The scanner uses the unfiltered recipe catalog and explicit skill-line membership. It never changes Blizzard's filters or selected expansion. Cross-expansion completeness still needs comparison with the live profession UI. “All” covers exposed recipes, not hidden or removed recipes.
- Bind-on-pickup, quest, and account-binding categories are excluded using item metadata. Other restrictions may not be detectable; an included search does not guarantee an item can be bought.
- API calls that return missing/invalid data are retried or shown as partial. A successful sync means the public API returned the expected list contents; only an in-game reload test proves persistence.

## Before go-live

Complete in-game tests, confirm the downstream price source, verify material/search-term deduplication and all-quality search results, and verify the supported client/Auctionator versions. Validate crafted-output coverage for Alchemy and Enchanting, including item links, variants, and non-item recipes. A direct AH scanner remains a separate scope decision.
