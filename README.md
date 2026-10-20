# Gorloc CraftScan

Turn your professions into Auctionator shopping lists. Gorloc CraftScan reads the recipes your character knows, collects every reagent and crafted item, and adds them to an Auctionator shopping list. Search that list at the Auction House and Auctionator, and every crafting addon that reads its prices, is up to date for everything you craft.

Part of the Gorloc suite.

![The Sync tab](https://raw.githubusercontent.com/nickbock/gorloc-craftscan/main/assets/sync-tab.png)

## Installation

Install with the CurseForge or Wago app. Requires World of Warcraft Retail (Midnight) and [Auctionator](https://www.curseforge.com/wow/addons/auctionator).

## Usage

1. Type `/gcs`, or click **CraftScan** below an open profession window.
2. Pick a profession. All your crafting professions and Cooking are detected.
3. Choose your options:
   - **Recipes:** known recipes only, or all recipes the game exposes, including ones you have not learned.
   - **Expansions:** the current expansion by default; pick others or all of them.
   - **Shopping lists:** one combined list, or separate lists for materials and crafted items.
4. Click **Scan & Sync**. CraftScan opens the profession, scans it, closes it again if it opened it, and adds the searches to Auctionator.
5. At the Auction House, open Auctionator's **Shopping** tab and search the list. Creating the list alone does not refresh prices.

Lists are named per profession: `Gorloc - Alchemy`, or `Gorloc - Alchemy - Materials` and `Gorloc - Alchemy - Items` in separate mode.

### Several characters, one list

Each character adds its own recipes to the same profession list. Syncing only adds missing searches; it never removes entries, so other characters' searches and your own manual searches are kept. Searches cover all qualities of an item.

The **Characters** tab (or `/gcs history`) shows which characters and professions have been synced, with their scope, status and last sync time. Characters update only when you log into them and scan again.

### If a scan is incomplete

When the game does not return all recipe data, nothing is synced automatically. Retry **Scan & Sync**, or click **Sync available items** to add what was found. **Details** shows what was missing.

## Screenshots

| Characters tab | Resulting Auctionator lists |
| --- | --- |
| ![Characters tab with synced characters and professions](https://raw.githubusercontent.com/nickbock/gorloc-craftscan/main/assets/characters-tab.png) | ![Gorloc shopping lists in Auctionator's Shopping tab](https://raw.githubusercontent.com/nickbock/gorloc-craftscan/main/assets/auctionator-lists.png) |

## Good to know

- Sync never deletes searches. Remove searches you no longer need in Auctionator.
- CraftScan does not scan the Auction House itself, calculate profit, or buy anything.
- Reagents for optional slots, recrafting, gathering and salvage are not included, nor are currencies and items that cannot be traded.
- The interface is English only.

## Commands

| Command | Opens |
| --- | --- |
| `/gcs` or `/gorloccraftscan` | The CraftScan window |
| `/gcs history` | The Characters tab |
| `/gcs debug` | Diagnostics to copy when reporting a problem |

## Reporting problems

[Open an issue](https://github.com/nickbock/gorloc-craftscan/issues/new/choose) and include the output of `/gcs debug`.

## License

Copyright (C) 2026 Tevoll. Licensed under the [GNU General Public License v3.0](https://github.com/nickbock/gorloc-craftscan/blob/main/LICENSE). Developer notes are in [docs/DEVELOPMENT.md](https://github.com/nickbock/gorloc-craftscan/blob/main/docs/DEVELOPMENT.md).
