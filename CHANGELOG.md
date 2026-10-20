# Changelog

## 1.0.0 (2026-10-20)

First public release.

- Scan any detected crafting profession, including Cooking, with one click: CraftScan opens the profession, reads it, and closes it again if it opened it.
- Known recipes only, or all recipes the game exposes; choose one, several, or all expansions.
- Sync reagents and crafted items into Auctionator shopping lists, combined or as separate Materials and Items lists. Searches cover all qualities.
- Sync only adds missing searches: other characters' searches and manual entries are always kept.
- Incomplete scans never sync automatically; **Sync available items** adds what was found, and **Details** explains what was missing.
- **Characters** tab with a table of synced characters, professions, scope, status and last sync time.
- `/gcs`, `/gcs history` and `/gcs debug` commands.

Upgrading from a local test build: saved history is converted automatically and reduced to what the Characters tab shows.
