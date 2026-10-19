# Detecting and opening professions for a scan

Implementation status: available in 0.1.4-local. The selector detects the current character’s crafting professions and Cooking. Scan opens the selected profession, waits for its data, and closes only a window opened by CraftScan. The user reported the preceding list-export build working; this new lifecycle still needs the live checks below.

## Findings

Blizzard's profession book enumerates the logged-in character with `GetProfessions()`, receiving two primary-profession indices plus Archaeology, Fishing, and Cooking indices. `GetProfessionInfo(index)` provides the name, icon, rank, and skill-line ID (seventh return value). Missing indices must be skipped individually; do not use `ipairs` over a sparse return-value table. These calls identify the current character's professions, not an arbitrary player's or an offline alt's recipe catalog. [Blizzard profession book](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_ProfessionsBook/Blizzard_ProfessionsBook.lua).

The generated Retail API exposes `C_TradeSkillUI.OpenTradeSkill(skillLineID)`, returning an `opened` boolean, and `C_TradeSkillUI.CloseTradeSkill()`. It also declares profession show, close, list-update, and data-source-change events. This supports a player-started open/scan/close workflow in principle; a successful open is not proof that all recipe data is ready. [Generated TradeSkillUI API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua).

Blizzard's profession frame waits while `IsDataSourceChanging()` is true. Its `OnHide` resets the crafting page and calls `CloseTradeSkill()`. Hiding the standard window immediately after opening therefore risks closing the data source. Keep it open until the scanner has copied its result; closing afterward leaves Gorloc's independent preview usable. Whether a fully invisible data session can be supported is not established and is unnecessary for the first implementation. [Blizzard profession-frame lifecycle](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_Professions/Blizzard_ProfessionsFrame.lua).

Context7 was queried first with the WoW UI source library; its results did not document these calls, so the linked Blizzard source mirror was used.

## Implemented behavior

1. Show the character's learned crafting professions in CraftScan, including Cooking. Refresh on profession/skill changes. Exclude unsupported noncrafting journals from this material-scan selector; validate profession classification in-game.
2. On a user-initiated scan outside combat, reuse an already-open matching local profession or call `OpenTradeSkill` for the selected skill-line ID. Keep linked, guild, and NPC views excluded. Handle a false return or an exception with an actionable message.
3. Wait for the selected profession's stable data source and expansion metadata, with a bounded timeout and cancellation. Confirm the base profession before scanning; never scan the previous profession's catalog during the transition. Default to the current game expansion; if unavailable, let the player select a supported expansion rather than exporting another scope.
4. Run the existing batched scanner. Preserve expansion selection for repeat scans of the same profession, but invalidate it when the selected profession changes.
5. After copying the result and ending the active scan, close the profession session only if CraftScan opened it and it is still the same session. Keep the Gorloc preview and Sync action available. Do not close a window that was already open or that the user switched to another profession during the scan. Respect pending profession UI edits and combat restrictions.
6. Apply the same ownership checks on cancellation, timeout, error, and closing CraftScan. Suppress reentrant cleanup from the resulting `TRADE_SKILL_CLOSE`; a finished snapshot must survive. Avoid leaving delayed callbacks able to reopen or close unrelated windows.

## In-game acceptance checks

- Cold start: `/gcs` with no profession window loaded; discover both primary professions and Cooking correctly.
- Open the correct profession from Scan, including while at the AH, away from a crafting table, and on clients with profession UI replacements.
- Wait through delayed profession data; do not publish an empty successful scan prematurely.
- Current-expansion default, multiple expansions, and repeat scans work after an automatic close.
- The profession closes after completion when CraftScan opened it; a preexisting window stays open.
- Manual close, profession switching, combat, addon-window close, and timeout cancel safely without closing another session.
- The completed snapshot can sync to the same short Auctionator list after the profession closes.

49 logic tests, 17 session-lifecycle tests, and the headless UI/controller flow pass. Exact client restrictions, UI event ordering, and AH coexistence still need these live checks. If a data session cannot be identified, is changing, enters combat, or has pending specialization edits, cleanup leaves the profession window open rather than closing another session. No deferred close runs later.
