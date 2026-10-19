# Shared profession lists across characters

Status: implemented for local testing in `0.1.5-local`, 2026-10-08. Merge sync, account-wide history, and the automated two-character test are complete. In v0.2.0, `/gcs history` opens the Characters view. On 2026-10-19 the saved history was slimmed to what that table shows (schema v5); per-item attribution and the planned cleanup/rebuild were dropped. In-game merge and persistence checks remain open; see [local testing](LOCAL-TESTING.md).

## Recommended behavior

Use **Merge** for normal sync: read the existing destination, add the current scan's missing searches, deduplicate, and preserve its other entries. Continue using the same short profession names with Combined or Separate lists. The shopping lists contain material and crafted-item searches, not recipe IDs.

For example, one Alchemist contributes materials/items for recipes A and B. A second contributes B and C. Their shared lists cover A, B, and C; overlapping item searches appear once. Syncing the first character again must not remove C. Scanning only the current expansion must not remove another character's older-expansion searches.

Do not create a shopping list per character. Keep per-character history in Gorloc so the lists remain convenient to search in Auctionator. All newly generated searches continue to cover all qualities without purchase quantities.

## Character history

Gorloc keeps a small account-wide history in its saved data, keyed by stable character identity, per profession and scan scope. A scope is the sorted selected expansion IDs plus the known/all-exposed mode; different scopes are separate rows. It is a local record of characters that have actually scanned, not live knowledge of every alt or a cross-account service.

| Record | Purpose |
| --- | --- |
| Character identity, display name, realm | Distinguish same-named characters on different realms. |
| Profession name | Group rows by profession. |
| Expansion scope label and known/all-exposed mode | Show what the scan covered. |
| Latest scan completeness | Show whether the last scan was complete or partial. |
| Last verified sync time, latest sync failed | Distinguish scanned data from data actually confirmed in a list. |

Item IDs, search terms and per-destination attribution are not stored: lists are additive, so nothing needs to know which character contributed which search. A character must be scanned again to capture newly learned recipes.

## Merge algorithm and failure behavior

1. Build and validate the new searches using the existing scanner and serializer. Preflight both destinations in Separate mode.
2. Read existing searches through the supported Auctionator integration. Distinguish a missing list from a failed read; do not interpret an API error as an empty list. The public missing-list contract could not be established. The implementation uses a guarded read-only `Shopping.ListManager:GetIndexForName` compatibility check, corroborated by CraftSim; unavailable or unexpected results stop sync before writes. List contents and writes still use public APIs.
3. Union the old and new searches, preserving existing custom searches and their filters. Deduplicate equivalent generated all-quality searches. Do not discard arbitrary existing filtered searches merely because their item names overlap.
4. Write through the supported list API and read back. Success requires all preserved old searches and all new searches to remain present. Normal Merge never removes stale searches.
5. Record the outcome per scope. The last sync time advances only when a destination is verified; any failed destination marks the scope **Sync failed** until a later sync succeeds. Keep scan data available for retry.

Partial scans may add resolved entries only after the existing explicit opt-in, and the scope then shows as Partial. Empty results add nothing and never clear a destination. Existing list entries, including those from older versions and manual searches, are always preserved.

## No automatic cleanup

Additive lists can retain obsolete searches. The planned **Rebuild from tracked characters** action was dropped on 2026-10-19 together with the attribution data it needed. Remove obsolete searches manually in Auctionator.

## UI additions

- Sync summary: “12 new searches · 48 already present · 60 total.” Compute these from the destination contents and actual serialized terms, not recipe or item-ID counts.
- Show “Adds missing entries; keeps existing searches” beside the normal Sync action.
- Add a **Characters** table: character-realm, profession, scope, complete/partial/failed status, and last verified sync. Sync time does not mean AH prices were refreshed.
- Keep Combined/Separate naming and the preview-filter behavior from the UI plan. No per-character suffixes.

## Delivery order

1. **Merge semantics and regression tests:** prevent one character's sync from removing another's entries; preserve legacy/manual terms and retain all-quality searches.
2. **History persistence:** add schema migration and per-scope scan/sync history.
3. **UI upgrade integration:** add merge counts and Characters/history to the planned sync panel and result details.
4. ~~Explicit cleanup/rebuild~~: dropped 2026-10-19.

Steps 1–2 are implemented and tested, including the two-character A/B → B/C → A regression in both list layouts. Step 3 is implemented in v0.2.0 with per-list counts/outcomes and the Characters tab.

## Acceptance checks

- Character A contributes A/B, character B contributes B/C: the shared list contains the union without duplicate generated searches.
- A repeated or narrower scan never removes another character's or another scope's entries.
- Known-only, all-exposed, and multiple-expansion scans appear as separate rows in both list layouts.
- Identical character names on different realms remain distinct contributors.
- Reload/character switching retains history; fresh login does not claim an offline alt has been scanned again.
- Legacy lists and manually added searches survive the first and subsequent merge syncs.
- Missing destination and failed list reads are handled distinctly; failed verification never advances the last sync time.
- Partial/empty scans cannot erase existing list entries or the last sync time.
- A failed second destination still records the first destination's sync time, shows Sync failed, and leaves a clear retry path.

Auctionator remains the price store. Gorloc stores only a small per-character scan/sync history; it does not become a separate price database.
