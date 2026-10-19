# Gorloc CraftScan minimal UI

Implemented in `0.3.0-local`, 2026-10-10. Replaces the custom v0.2.0 interface with native Blizzard controls. In-game visual acceptance remains open.

## Everyday flow

1. Open `/gcs` and select a profession from a dropdown, including Cooking when learned.
2. Choose known/all exposed recipes, expansion scope, and combined/separate lists.
3. Click **Scan & Sync**. A complete, nonempty scan syncs automatically. The status shows added/already-present searches and directs the user to Auctionator to refresh prices.
4. Use **Characters** to see a table of recorded characters, professions, scopes, status, and last verified sync.

The first scan defaults to the current expansion and loads the available expansion choices. Subsequent scans preserve that profession's expansion selections. If the current expansion is unavailable, the user must choose another expansion explicitly. List mode is remembered; names remain fixed.

## Layout

A 540 × 520 movable `BasicFrameTemplateWithInset` window contains **Sync** and **Characters** views. It uses native fonts, `UIPanelButtonTemplate`, and `WowStyle1DropdownTemplate` menus. Position is saved; the window scales down only if the effective viewport cannot fit it. No custom textures or external UI framework are needed.

The Sync view contains profession, recipe, expansion, and list-layout dropdowns; read-only destination names; a short explanation of additive/all-quality searches; status; and the main action. The expansion menu has Current/All shortcuts and multi-select checkboxes.

Removed: Materials/Items/Issues browsers, preview filtering and sorting, source expansion, report tools, resize controls, and the diagnostics menu. Troubleshooting is available through `/gcs debug`. Errors can expose a **Details** button; normal successful use needs no diagnostic controls.

## Action states

| State | Behavior |
| --- | --- |
| Ready | **Scan & Sync** opens the profession and scans. |
| Loading/scanning | Controls are disabled; **Cancel** replaces the main action. |
| Complete and nonempty | Sync automatically; record verified per-destination outcomes. |
| Partial | Pause without writing. Offer a fresh **Scan & Sync**, **Details**, or explicit **Sync available items**. |
| Empty | Explain that no searchable items resolved; do not write a list. Allow a fresh scan. |
| Sync failed | Keep the payload, show **Details**, offer **Retry sync**. Earlier successful destinations remain recorded. |
| Missing Auctionator | Explain the dependency and disable Scan & Sync. Characters and troubleshooting remain accessible. |
| In combat | Disable sync; cancel active scans. Re-enable actions when combat ends. |
| Scope/layout changed | Invalidate the prior payload and partial confirmation; require a fresh scan. |

Window ownership, cancellation, additive merging, deduplication, all-quality searches, fixed names, and account-wide sync history remain intact. List synchronization never claims that AH prices were refreshed. Separate lists are not an atomic write; failure details identify each destination's outcome.

## Verification

Simulated tests cover native widget construction, dropdown callbacks, complete auto-sync, explicit partial confirmation, empty scans, independent destination failures and retry, missing Auctionator, cancellation, combat transitions, profession ownership, cold profession loading, and character history with a bounded six-row pool. Model tests cover scan/sync distinctions and summary counts.

Blizzard's actual fonts, textures, menu behavior, clipping, focus, scrolling, and UI scale require a live-client check. Follow [local testing](LOCAL-TESTING.md). The installable ZIP contains only TOC-referenced files; old unused UI module files left by an overwrite are no longer loaded.
