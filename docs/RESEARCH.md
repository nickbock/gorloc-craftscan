# Technical research

Research date: 2026-10-07. Target assumption: WoW Retail. This is documentation research, not an in-game compatibility test. Links using `live` can change; pin the client build and source revision during implementation.

User context added after the initial research: this is a Gorloc-suite add-on intended to generate lists for auction-house price refreshes, with profit calculations displayed by other crafting add-ons. The research below establishes candidate collection/export approaches; it does not yet verify those downstream price-source integrations.

## Feasibility

The core design is feasible: read profession recipe information, collect reagent slots, deduplicate materials, and pass the result to an Auctionator integration. Two things need an early in-game proof: recipe coverage across expansion skill lines and the current contract for creating a persistent Auctionator list.

### Recipes and materials

Blizzard's generated documentation defines `C_TradeSkillUI.GetRecipeInfo(recipeSpellID, recipeLevel?)` and `C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, isRecraft, recipeLevel?)`. It also exposes base/child profession information and reagent-quality lookups. Use `false` for ordinary crafting schematics; recipe-level handling needs explicit validation for ranked recipes. [Generated TradeSkillUI API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua).

The documented recipe structure includes `learned`, `disabled`, and flags identifying recrafting, gathering, salvage, and dummy recipes. Schematics contain reagent slots with `required`, `quantityRequired`, `reagents`, and `variableQuantities`. A reagent can reference an item or a currency. Consequently, a flat loop that treats every alternative as a separate mandatory purchase would be incorrect. [Generated recipe and reagent types](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua).

Blizzard's own recipe-list builder uses `GetFilteredRecipeIDs()`, checks `IsRecipeInSkillLine(recipeID, professionID)`, and constructs learned/unlearned groups. Its UI also handles recipe chains. This supports the feasibility of an unlearned-recipe mode, but does not establish a complete catalog of every historical recipe. [Blizzard profession helpers](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_ProfessionsTemplates/Blizzard_Professions.lua).

**Enumeration proposal:** use `C_TradeSkillUI.GetAllRecipeIDs()` as the candidate unfiltered source, then apply this add-on's scope and learned filters. An independently maintained add-on uses this function with `GetRecipeInfo(...).learned` to record known recipes. Its implementation is corroboration of usage, not proof of current Retail coverage. The first prototype must verify unlearned inclusion, independence from UI filters, and expansion coverage. Do not silently substitute the filtered API and claim a complete scan. [TradeSkillInfo implementation](https://github.com/Ravendwyr/TradeSkillInfo/blob/master/TradeskillInfo.lua).

Blizzard's profession frame defers updates while `IsDataSourceChanging()` is true, responds to `TRADE_SKILL_LIST_UPDATE` and `TRADE_SKILL_CLOSE`, and distinguishes linked/guild profession views. The add-on should likewise wait for a stable local profession context. [Blizzard profession frame](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_Professions/Blizzard_ProfessionsFrame.lua).

### What “all recipes” can mean

Proposed contract: **all recipes exposed by the game for the selected profession scope**, including unlearned recipes when available. Do not promise hidden, removed, other-character, or unavailable profession recipes. Missing recipe metadata must be reported rather than silently counted as success.

Known recipes means learned by this character, regardless of materials currently owned. A recipe blocked by a cooldown or missing crafting station can still contribute materials. A separate “craftable with current inventory” filter would undermine the main shopping use case and is outside the MVP.

### Auctionator integration

Auctionator's publisher describes persistent shopping lists and an existing crafting-reagent search feature. The product page currently lists release 340 and Retail 12.1.0 support; these are research context, not a tested minimum-version promise. [Auctionator publisher page](https://www.curseforge.com/wow/addons/auctionator).

Context7 was queried first, resolving `/themousenest/auctionator` and `/auctionator/auctionator`. Its indexed maintainer documentation describes `Auctionator.API.v1.MultiSearchAdvanced(callerID, terms)`, including exact search, reagent tier, item rarity, and quantity fields. It also says searches require the auction house to be open. However, the older index describes shopping-list management as future work. Both linked GitHub wiki URLs returned 404 during this research. These cached descriptions are insufficient to certify today's persistent-list API. [Indexed maintainer API documentation](https://context7.com/themousenest/auctionator), [original wiki URL, currently unavailable](https://github.com/Auctionator/Auctionator/wiki/API-Documentation).

The author of Craft Shopper explicitly advertises creating/updating Auctionator lists through its supported API. This is useful evidence that the integration is practical, but that page does not establish function arguments or collision behavior. `CreateShoppingList` and `ConvertToSearchString` are candidate API names to verify, not signatures to copy into implementation. [Craft Shopper author description](https://www.curseforge.com/wow/addons/craft-shopper).

**Integration decision:** isolate the public API behind a small adapter. Before building the full UI, verify list creation, replacement/merge behavior, exact matching, unrestricted quality coverage, and persistence after reload on the target release. Do not write Auctionator SavedVariables or use private list mutations. The v0.1.5 read-only existence-check exception is described below. A search result is not a persistent shopping list.

**Fallback:** a user-copyable Auctionator import string is acceptable only after its format passes an actual import/export round trip. Plain material text remains useful for diagnostics but does not meet the shopping-list acceptance criterion.

**Local implementation update:** an independently published integration uses `CreateShoppingList(callerID, listName, searchStrings)` together with `ConvertToSearchString(callerID, details)`. The `0.1.2-local` adapter now uses those call shapes behind capability checks. This corroborates usage but does not replace an in-game test of the installed Auctionator version. No guessed manual import format is implemented. [Published integration](https://raw.githubusercontent.com/VichobAddons/MajesticBeastTracker/v1.5.0/Core.lua), [local test guide](LOCAL-TESTING.md).

**Stable-name sync update (0.1.2-local):** CraftSim’s published Shopping integration calls `GetShoppingListItems(callerID, listName)` and `DeleteShoppingListItem(callerID, listName, searchString)`, and passes merged terms to `CreateShoppingList` for an existing destination. Gorloc uses these public call shapes to add desired terms, verify their presence, prune stale searches, and verify exact final contents. It does not use CraftSim’s private ListManager deletion approach. The add/merge behavior is inferred from this consumer integration and checked at runtime; installed-version persistence still requires in-game testing. [CraftSim Shopping integration](https://raw.githubusercontent.com/derfloh205/CraftSim/main/Modules/Shopping/Shopping.lua).

**Merge/history update (0.1.5-local, 2026-10-08):** The adapter now reads and unions existing/new terms, writes through the public API, verifies the union, and never deletes searches. Context7 returned only proposed future existence APIs; the public wiki was unavailable, so no new public existence signature is assumed. CraftSim independently demonstrates a read-only `Auctionator.Shopping.ListManager:GetIndexForName(name)` check before reading/creating a list. Gorloc now isolates this private read-only compatibility check in Runtime and fails before writing if unavailable or invalid. This is an explicit exception to the earlier public-only plan; no Auctionator source was used, and all list mutations remain public. Live compatibility still needs verification. [CraftSim integration](https://raw.githubusercontent.com/derfloh205/CraftSim/main/Modules/Shopping/Shopping.lua), [acceptance checks](LOCAL-TESTING.md).

### Related functionality

Auctionator already covers searching reagents from crafting views. Craft Shopper focuses on the selected recipe, craft quantities, and owned-material subtraction. ShoppingLister converts TSM groups. The proposed product focuses on a profession-wide material catalog with learned/all-exposed selection. This is a narrow differentiation, not a claim that no similar add-on exists. [Auctionator](https://www.curseforge.com/wow/addons/auctionator), [Craft Shopper](https://www.curseforge.com/wow/addons/craft-shopper), [ShoppingLister](https://www.curseforge.com/wow/addons/shoppinglister).

## Remaining evidence to collect

Follow-up research: [Direct AH scanning and Auctionator compatibility](AH-SCANNING.md). Direct queries are feasible in principle; getting externally collected prices saved in Auctionator remains unverified. The user requires that price-store compatibility, so a Gorloc-triggered Auctionator search is the recommended first experiment.

| Question | Required evidence |
| --- | --- |
| Which client flavor? | User choice; Retail is the planning assumption. |
| Which recipes does enumeration return? | Counts and representative IDs with learned/unlearned, text, category, and expansion filters changed. |
| Can unlearned schematics be read reliably? | Fixtures from several professions, including gated recipes. |
| How is the current game expansion identified? | Verify client expansion identity separately from the profession window's selection and map it to profession skill lines. |
| Does scanning selected expansions need context changes? | Compare base enumeration with each exposed child skill line and verify combined selections. |
| Which public Auctionator calls are supported? | Current API contract plus successful list creation and reload test. |
| How are identical-name quality variants represented? | One exact-name search with no tier restriction; verify all same-name quality variants appear with real materials. |
| Can non-auctionable materials be classified reliably? | Validate item binding metadata; represent uncertain cases explicitly. |
| Do list searches refresh the prices used for crafting profits? | Identify the user's crafting add-ons/settings and compare material price inputs before and after an Auctionator search. |
| Are crafted-output prices refreshed for the selected recipes? | Compare the new output searches with the profession UI and the downstream crafting price source. |
| What happens when an item has no auctions? | Verify missing/stale-price behavior in Auctionator and the chosen downstream add-on. |
| Can Gorloc trigger the refresh? | Verify supported Auctionator search calls, public price reads, persistence after reload, and downstream use. |
| Would Auctionator save direct Blizzard-query results? | Test externally initiated queries; otherwise establish a supported ingestion API before planning direct-scanner compatibility. |

Classic is a separate compatibility project. Retail API availability and unlearned-recipe coverage must not be assumed for Classic. A flavor without an exposed unlearned catalog could require a separately maintained recipe database; that maintenance cost is outside this MVP.

### Crafted-output collection (0.1.3-local)

Retail exposes `GetRecipeQualityItemIDs(recipeSpellID)` and `GetRecipeOutputItemData(recipeSpellID, ...)`. The latter returns an item ID or hyperlink. The recipe schematic also contains an optional output item ID. The collector unions exposed quality IDs with the schematic ID, falling back to output data when needed; the shared item loader then resolves names and binding information. This uses the same learned/expansion-filtered recipe set as materials. Missing item output data is retried and marked partial; explicit non-item outputs are reported separately. Random results and optional-reagent-dependent variants beyond what these calls expose are not guaranteed. [Output APIs](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua), [output and schematic structures](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua).

Combined export unions material and output IDs before serializing unique all-quality searches. Separate export uses stable ` - Materials` and ` - Items` names. Both destinations are preflighted before writes; runtime errors during the second sync report which destination already succeeded. No automatic list deletion occurs when changing layouts.

## UI widget verification (2026-10-10)

Context7 resolved the current WoW UI source mirror but returned no matching resize/scroll example. Blizzard's generated documentation in that mirror confirms `SetResizable`, `SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)` and `StartSizing`, plus the ScrollFrame vertical scrolling API. The browser uses native scroll frames and a visible row pool. [Frame API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua), [ScrollFrame API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleScrollFrameAPIDocumentation.lua).

Item icons use `C_Item.GetItemIconByID` with a fallback icon. Item hover uses the standard owned GameTooltip and an item hyperlink; these are supported by generated item documentation and Blizzard's own tooltip usage. [Item API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua), [Blizzard tooltip usage](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseUtil.lua). Native font rendering, tooltips, mouse-wheel behavior and scaling must still be checked in the installed client.


## Minimal Blizzard UI (0.3.0-local, 2026-10-10)

Context7 resolved `/gethe/wow-ui-source` and returned Blizzard menu examples using `CreateRadio` with selection and callback functions. The native menu guide documents `WowStyle1DropdownTemplate`, `SetupMenu`, `CreateCheckbox`, `GenerateMenu`, and `SetSelectionText`. These implement profession, scope, expansion, and layout dropdowns. [Blizzard menu implementation guide](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_Menu/11_0_0_MenuImplementationGuide.lua).

The Retail panel templates define `BasicFrameTemplateWithInset` with a native border, background, title, and close button. CraftScan now uses it with standard buttons and fonts; the previous custom skin and item browser are removed. [Retail panel templates](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml), [shared panel templates](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml). Source verification and mocked tests do not replace checking rendering and menus in the user's client.
