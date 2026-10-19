# Research: direct auction-house scanning and Auctionator compatibility

Researched 2026-10-07. Retail assumption; source research only, with no in-game proof yet. This is a candidate follow-up to the shopping-list MVP.

## Conclusion

**Direct scanning is technically feasible, but it does not by itself meet the requirement to save prices in Auctionator.** Keep Auctionator as the price store consumed by existing crafting add-ons. First investigate a Gorloc **Refresh prices** action that delegates the search to Auctionator. A direct Blizzard-API scanner is a later experiment gated on verified Auctionator ingestion.

The user clarified that prices must remain available through Auctionator. Removing Auctionator entirely is therefore not the objective of this follow-up; making the refresh workflow accessible from Gorloc is useful independently.

## Evidence

Blizzard's generated Retail API exposes `C_AuctionHouse.SendSearchQuery(itemKey, sorts, separateOwnerItems, minLevelFilter?, maxLevelFilter?)`, commodity/item result readers, result-update events, and requests for additional results. It documents a **100-search-calls-per-minute** limit and directs whole-auction-house queries to `ReplicateItems`. This supports a targeted profession-material scanner, but not unlimited querying or a promised scan duration. Exact behavior must be tested on the target client. [Blizzard auction-house API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua).

Blizzard's own auction-house frame calls the search API and closes the auction-house connection when its frame hides. Design the feature for a player-started scan with the auction house open; stop issuing requests when it closes. [Blizzard auction-house frame](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua).

The commodity helper reads quantities and unit prices and distinguishes owner quantities. A scanner must define the price it records and handle commodity and individual-item results appropriately; an arbitrary listing total is not a substitute for a per-item price. [Blizzard auction-house helpers](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseUtil.lua).

The indexed Auctionator maintainer documentation exposes search commands, price getters, and `RegisterForDBUpdate`, which subscribes to updates. **No public price-write/import API was established by this research.** A callback registration is not a price setter. The original wiki remains unavailable, so this is an unresolved compatibility question rather than proof that no such facility exists. [Indexed maintainer documentation](https://context7.com/themousenest/auctionator), [original wiki](https://github.com/TheMouseNest/Auctionator/wiki/API-Documentation).

Examples support the user's concern: CraftSim's published Auctionator adapter reads Auctionator's price API, and TSM documents its `AtrValue` external price source. Neither establishes that either add-on would automatically read an unrelated Gorloc database. These are examples, not confirmation of which add-ons the user runs. [CraftSim pricing adapter](https://raw.githubusercontent.com/derfloh205/CraftSim/main/Pricing/PriceAPIs.lua), [TSM external price sources](https://support.tradeskillmaster.com/en_US/custom-strings/which-external-sources-are-available-to-use).

## Options

| Approach | Price storage | Assessment |
| --- | --- | --- |
| Current MVP: export a list, player searches it | Auctionator | Preserve the original scope; verify price persistence and downstream use. |
| Gorloc starts a supported Auctionator search | Auctionator | Recommended next prototype. Reduces manual steps while retaining the existing price source. |
| Gorloc queries Blizzard; Auctionator observes the result events | Auctionator, if observation actually occurs | Unverified. Test whether current Auctionator records externally initiated queries and persists them. Do not assume shared events guarantee ingestion. |
| Gorloc queries Blizzard and submits prices through a public write API | Auctionator | Conditional on establishing a supported write contract; none verified yet. |
| Gorloc stores prices and exposes its own provider | Gorloc | Separate future product scope requiring consumer integrations; does not meet the clarified Auctionator-storage requirement on its own. |

Do not implement compatibility by editing Auctionator SavedVariables, calling private database functions, or substituting Gorloc's getters for Auctionator's. Keep price collection and storage integration behind separate adapters.

## Recommended proof of concept

1. Record client and Auctionator versions and identify the user's crafting add-on and price-source settings.
2. Select a small test set: ordinary reagent, quality variants, a non-commodity material, and an item without listings.
3. Capture Auctionator's public price reads before scanning. Prefer an item with a demonstrably missing or outdated value; an unchanged value alone cannot prove that new data was saved.
4. Try a user-triggered Auctionator search through its supported API. Confirm price reads afterward, persistence after `/reload`, and the downstream crafting calculation's inputs.
5. Separately issue a small targeted Blizzard search with Auctionator loaded and idle. Observe whether Auctionator records it without an explicit write. Record notification behavior, but verify actual reads and persistence rather than relying on a notification alone.
6. If observation fails, look for a supported ingestion contract. If none is available, keep the delegated-search route; do not ship a scanner that reports compatibility while leaving Auctionator prices stale.

**Success:** a Gorloc-initiated refresh causes the intended prices to be readable through Auctionator after reload and consumable by the user's crafting add-on. An in-memory Gorloc price or an on-screen auction result alone does not pass.

## Direct-scanner design, if ingestion is proven

These are proposed engineering requirements, not claims about behavior already tested:

- Reuse the selected profession/expansion material IDs and preserve quality variants. The local list exporter now deduplicates item IDs and equivalent searches. A future direct scanner must also deduplicate its query queue while preserving distinct quality item IDs.
- Use a bounded request queue with conservative rate limiting, retries, timeouts, progress, and cancellation. Validate available readiness signals on the target build; do not hard-code remembered API names or treat the documented ceiling as guaranteed throughput.
- Correlate responses with the active item key and scan generation. Stop or pause when other auction-house activity could invalidate the result context. Do not run simultaneous Gorloc and Auctionator scans.
- Establish result completeness before treating an observed minimum as final. Handle pagination, late events, cancellation, and empty results distinctly.
- Record the lowest eligible buyout per unit under an explicit own-auction policy; validate agreement with Auctionator's consumer-facing semantics. No auctions, timeouts, and partial results must not become zero prices or fresh successful observations.
- Preserve timestamps and market/item identity in any diagnostic cache. Reuse Auctionator's supported storage semantics rather than inventing compatible-looking records.
- Keep list creation, requests sent, results received, and prices persisted as distinct states. Only claim **prices saved** after the persistence path has been verified.

A whole-market scan is unnecessary for the first version of this feature. Revisit bulk approaches only if measured profession-list performance justifies the added scope. Classic requires its own API investigation.
