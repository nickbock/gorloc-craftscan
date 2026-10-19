-- No game client or third-party libraries required: lua5.1 tests/run.lua
local G = {}
local function loadModule(name)
    assert(loadfile("GorlocCraftScan/" .. name .. ".lua"))("GorlocCraftScan", G)
end
for _, name in ipairs({ "Util", "MaterialCollector", "ProfessionScanner", "Runtime", "AuctionatorAdapter" }) do
    loadModule(name)
end

local passed, failed = 0, 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(text, part)
    assert(text and text:find(part, 1, true), "Expected '" .. tostring(text) .. "' to contain '" .. part .. "'")
end
local function test(name, callback)
    local ok, err = pcall(callback)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. "\n  " .. tostring(err)) end
end

local function context()
    return { baseID = 171, childID = 100, sourceCounter = 1, name = "Alchemy", currentExpansionName = "Current",
        expansions = { { id = 100, name = "Old" }, { id = 200, name = "Current", isCurrent = true } } }
end
local function recipe(id, learned, extra)
    local info = { recipeID = id, name = "Recipe " .. id, learned = learned }
    for k, v in pairs(extra or {}) do info[k] = v end
    return info
end
local function slot(id, quantity, extras)
    local s = { required = true, quantityRequired = quantity or 2, dataSlotIndex = 1, reagents = { { itemID = id } } }
    for k, v in pairs(extras or {}) do s[k] = v end
    return s
end
local function fixture()
    local f = { clock = 0, timers = {}, current = context(), requested = {}, reads = {},
        recipes = { 1, 2, 3, 4 },
        info = { [1] = recipe(1, true), [2] = recipe(2, false), [3] = recipe(3, true),
            [4] = recipe(4, true, { isRecraft = true }) },
        skills = { [1] = 200, [2] = 200, [3] = 100, [4] = 200 },
        schematics = { [1] = { reagentSlotSchematics = { slot(10) } },
            [2] = { reagentSlotSchematics = { slot(20) } },
            [3] = { reagentSlotSchematics = { slot(10), slot(30) } } },
        items = { [10] = { name = "Ore" }, [20] = { name = "Dust" }, [30] = { name = "Herb" },
            [101] = { name = "Potion" }, [102] = { name = "Elixir" }, [103] = { name = "Flask" } },
    }
    f.env = {
        after = function(delay, callback) f.timers[#f.timers + 1] = { at = f.clock + delay, callback = callback } end,
        now = function() return f.clock end,
        context = function() return f.current, f.contextMessage end,
        recipes = function() return f.recipes end,
        recipe = function(id) f.reads[id] = (f.reads[id] or 0) + 1; return f.info[id] end,
        matches = function(id, skillLine) return f.skills[id] == skillLine end,
        schematic = function(id) return f.schematics[id] end,
        outputs = function(id) return { 100 + id } end,
        item = function(id) return f.items[id] end,
        requestItem = function(id) f.requested[id] = (f.requested[id] or 0) + 1 end,
    }
    f.scanner = G.Scanner.New(f.env)
    f.callbacks = { progress = function(text) f.progress = text end,
        done = function(result) f.result = result; f.doneCount = (f.doneCount or 0) + 1 end,
        error = function(err) f.error = err end }
    function f:tick()
        table.sort(self.timers, function(a, b) return a.at < b.at end)
        local timer = table.remove(self.timers, 1)
        if timer then self.clock = timer.at; timer.callback() end
    end
    function f:drain()
        local remaining = 2000
        while #self.timers > 0 do
            remaining = remaining - 1
            assert(remaining > 0, "Unbounded timer loop")
            self:tick()
        end
    end
    function f:start(selection, includeUnlearned)
        self.scanner:Start(self.current, selection or { [200] = true }, includeUnlearned or false, self.callbacks)
    end
    return f
end

test("default selection is current expansion, not the displayed older expansion", function()
    local selected = G.DefaultSelection(context())
    equal(selected[200], true)
    equal(selected[100], nil)
end)

test("no fallback to older expansion when current is unavailable", function()
    local c = context(); c.expansions[2] = nil
    equal(next(G.DefaultSelection(c)), nil)
end)

test("known recipes ignore inventory and stay within selected expansion", function()
    local f = fixture(); f:start(); f:drain()
    equal(f.error, nil)
    equal(f.result.complete, true)
    equal(#f.result.recipes, 1)
    equal(f.result.recipes[1].id, 1)
    equal(#f.result.entries, 1)
    equal(#f.result.excluded, 1)
    equal(f.result.entries[1].itemID, 10)
end)

test("all exposed includes unlearned recipes", function()
    local f = fixture(); f:start(nil, true); f:drain()
    equal(#f.result.recipes, 2)
    equal(f.result.learned, 1)
    equal(f.result.unlearned, 1)
    equal(f.result.entries[2].itemID, 20)
end)

test("multiple expansions deduplicate materials and preserve recipe provenance", function()
    local f = fixture(); f:start({ [100] = true, [200] = true }); f:drain()
    equal(#f.result.recipes, 2)
    equal(#f.result.entries, 2)
    equal(f.result.entries[1].itemID, 10)
    equal(f.result.entries[2].itemID, 30)
    equal(#f.result.entries[1].sources, 2)
    equal(f.result.entries[1].sources[1].recipeID, 1)
    equal(f.result.entries[1].sources[2].recipeID, 3)
    contains(G.Collector.Report(f.result), "2 unique material items")
    contains(G.Collector.Report(f.result), "Recipe 3; slot 1; per craft 2")
end)

test("empty selection fails without scheduling work", function()
    local f = fixture(); f:start({})
    contains(f.error, "Select at least")
    equal(#f.timers, 0)
end)

test("selection is snapshotted while asynchronous scan is in flight", function()
    local f = fixture(); local selection = { [200] = true }
    f:start(selection); selection[100] = true; f:drain()
    equal(#f.result.recipes, 1)
end)

test("cancel discards pending callbacks", function()
    local f = fixture(); f:start(); f.scanner:Cancel(); f:drain()
    equal(f.result, nil); equal(f.error, nil); equal(next(f.reads), nil)
end)

test("a newer scan supersedes the old job", function()
    local f = fixture(); f:start(); f:start({ [100] = true }); f:drain()
    equal(f.doneCount, 1)
    equal(f.result.recipes[1].id, 3)
end)

test("profession switch prevents stale callbacks from completing", function()
    local f = fixture(); f:start(); f:tick()
    f.current = context(); f.current.baseID = 164
    f:drain()
    equal(f.result, nil); contains(f.error, "changed or closed")
end)

test("closing profession during item resolution fails safely", function()
    local f = fixture(); f.items[10] = nil; f:start(); f:tick(); f.current = nil; f:drain()
    equal(f.result, nil); contains(f.error, "changed or closed")
end)

test("loading context waits and times out", function()
    local f = fixture(); f:start(); f.current = nil; f.contextMessage = "loading"; f:drain()
    contains(f.error, "did not become ready")
    equal(f.result, nil)
end)

test("transient metadata is retried and recovered", function()
    local f = fixture()
    local original = f.env.recipe
    f.env.recipe = function(id)
        if id == 1 and not f.missed then f.missed = true; return nil end
        return original(id)
    end
    f:start(); f:drain()
    equal(f.result.complete, true); equal(#f.result.recipes, 1)
end)

test("missing schematics are visible as partial, not a successful empty scan", function()
    local f = fixture(); f.schematics[1] = nil; f:start(); f:drain()
    equal(f.result.complete, false)
    equal(f.reads[1], 3)
    contains(f.result.issues[1].message, "schematic unavailable")
end)

test("item cache resolves later and groups duplicate occurrences", function()
    local f = fixture(); f.items[10] = nil
    f.env.requestItem = function(id)
        f.requested[id] = (f.requested[id] or 0) + 1
        f.env.after(0.5, function() f.items[id] = { name = "Delayed ore", tier = 2 } end)
    end
    f:start({ [100] = true, [200] = true }); f:drain()
    equal(f.result.complete, true)
    equal(f.requested[10], 1)
    equal(f.result.entries[1].name, "Delayed ore")
    equal(f.result.entries[1].tier, 2)
    equal(#f.result.entries, 2)
    equal(#f.result.entries[1].sources, 2)
end)

test("failed item requests stop retrying and mark the result partial", function()
    local f = fixture(); f.items[10] = nil; f:start(); f:drain()
    equal(f.result.complete, false); equal(#f.result.entries, 0)
    equal(f.requested[10], 2)
    contains(f.result.issues[1].message, "Item data unavailable")
end)

test("required alternatives, variable quantities, optional slots and currency stay distinct", function()
    local f = fixture()
    f.schematics[1] = { reagentSlotSchematics = {
        slot(10, 2, { reagents = { { itemID = 10 }, { itemID = 30 } },
            variableQuantities = { { reagent = { itemID = 30 }, quantity = 4 } } }),
        slot(20, 1, { required = false }),
        slot(nil, 5, { reagents = { { currencyID = 99 } } }),
    } }
    f:start(); f:drain()
    equal(#f.result.entries, 2)
    equal(f.result.entries[1].alternatives, 2)
    equal(f.result.entries[2].quantity, 4)
    equal(f.result.optionalSlots, 1)
    equal(f.result.nonShopping[1].currencyID, 99)
    equal(f.result.complete, true)
end)

test("bound reagents remain in the report but are not searched", function()
    local f = fixture(); f.items[10].blocked = "Binds on pickup"
    f:start(); f:drain()
    equal(#f.result.entries, 0); equal(#f.result.nonShopping, 1)
    contains(G.Collector.Report(f.result), "Binds on pickup")
end)

test("unknown required-slot shape cannot silently disappear", function()
    local f = fixture(); f.schematics[1].reagentSlotSchematics[1].required = nil
    f:start(); f:drain()
    equal(f.result.complete, false); contains(f.result.issues[1].message, "Unknown requirement")
end)

test("malformed later slots do not leak partially collected recipes on retry", function()
    local f = fixture(); f.schematics[1].reagentSlotSchematics[2] = false
    f:start(); f:drain()
    equal(f.result.complete, false)
    equal(#f.result.entries, 0)
    equal(#f.result.recipes, 0)
    equal(f.result.learned, 0)
    equal(f.reads[1], 3)
end)

test("crafted outputs follow learned and expansion scope", function()
    local f = fixture(); f:start(); f:drain()
    equal(#f.result.outputs, 1); equal(f.result.outputs[1].itemID, 101)
    f:start({ [100] = true, [200] = true }, true); f:drain()
    equal(#f.result.outputs, 3)
    contains(G.Collector.Report(f.result), "Crafted by: Recipe 2")
end)

test("outputs deduplicate across recipes and share the item cache with materials", function()
    local f = fixture(); f.items[10] = nil
    f.env.outputs = function() return { 10 } end
    f.env.requestItem = function(id)
        f.requested[id] = (f.requested[id] or 0) + 1
        f.items[id] = { name = "Intermediate" }
    end
    f:start({ [100] = true, [200] = true }); f:drain()
    equal(f.requested[10], 1)
    equal(#f.result.outputs, 1); equal(#f.result.outputs[1].sources, 2)
    local lists = G.Collector.ExportLists(f.result, "Gorloc - Alchemy", "combined")
    equal(#lists, 1); equal(#lists[1].result.entries, 2)
end)

test("output retries preserve materials and mark unrecoverable data partial", function()
    local f = fixture(); local reads = 0
    f.env.outputs = function() reads = reads + 1; return nil, "Unavailable output" end
    f:start(); f:drain()
    equal(reads, 3); equal(f.result.complete, false)
    equal(#f.result.entries, 1); equal(#f.result.outputs, 0)
    contains(f.result.issues[1].message, "Unavailable output")
end)

test("transient output errors recover without duplicate results", function()
    local f = fixture(); local reads = 0
    f.env.outputs = function()
        reads = reads + 1
        if reads == 1 then error("Loading") end
        return { 101 }
    end
    f:start(); f:drain()
    equal(reads, 2); equal(f.result.complete, true); equal(#f.result.outputs, 1)
end)

test("bound and non-item outputs are reported separately", function()
    local f = fixture(); f.items[101].blocked = "Binds on pickup"
    f.env.outputs = function(id)
        if id == 3 then return {}, "No item output" end
        return { 101 }
    end
    f:start({ [100] = true, [200] = true }); f:drain()
    equal(f.result.complete, true); equal(#f.result.outputs, 0)
    equal(#f.result.nonShopping, 2)
    contains(G.Collector.Report(f.result), "Excluded output: Potion")
end)

test("unresolved output item names make a scan partial", function()
    local f = fixture(); f.items[101] = nil; f:start(); f:drain()
    equal(f.result.complete, false); equal(#f.result.outputs, 0)
    equal(f.requested[101], 2)
    contains(f.result.issues[1].message, "Crafted item data unavailable: 101")
end)

local function auctionator()
    local calls, details, lists = {}, {}, {}
    return {
        ConvertToSearchString = function(caller, term)
            equal(caller, "GorlocCraftScan")
            details[#details + 1] = term
            return '"' .. term.searchString .. '"' .. (term.tier ~= "" and ";tier=" .. tostring(term.tier) or "")
        end,
        CreateShoppingList = function(caller, name, terms)
            calls[#calls + 1] = { caller = caller, name = name, terms = terms }
            lists[name] = lists[name] or {}
            for _, term in ipairs(terms) do
                local present = false
                for _, existing in ipairs(lists[name]) do if existing == term then present = true end end
                if not present then lists[name][#lists[name] + 1] = term end
            end
        end,
        GetShoppingListItems = function(caller, name)
            equal(caller, "GorlocCraftScan")
            return lists[name] or {}
        end,
        DeleteShoppingListItem = function(caller, name, term)
            equal(caller, "GorlocCraftScan")
            for i = #lists[name], 1, -1 do
                if lists[name][i] == term then table.remove(lists[name], i) end
            end
        end,
    }, calls, details, lists
end
local function exportResult()
    local f = fixture(); f:start({ [100] = true, [200] = true }); f:drain(); return f.result
end

test("export uses exact names without quality restrictions or purchase quantities", function()
    local api, calls, details = auctionator()
    local result = exportResult(); result.entries[1].tier = 3
    local ok = G.AuctionatorAdapter.Export(api, result, "New test list", false)
    equal(ok, true); equal(#calls, 1); equal(#calls[1].terms, 2)
    equal(details[1].isExact, true); equal(details[1].tier, "")
    equal(details[1].quantity, nil); equal(details[1].quality, nil)
    equal(details[2].searchString, "Herb")
    equal(calls[1].terms[1], '"Ore"')
end)

test("same-name quality IDs stay distinct in preview and collapse to one unrestricted search", function()
    local f = fixture()
    f.schematics[1].reagentSlotSchematics = {
        slot(10, 2, { reagents = { { itemID = 10 }, { itemID = 11 }, { itemID = 12 } } }),
        slot(10, 7, { dataSlotIndex = 2 }),
    }
    f.items[10] = { name = "Ore", tier = 1 }
    f.items[11] = { name = "Ore", tier = 2 }
    f.items[12] = { name = "Ore", tier = 3 }
    f:start(); f:drain()
    equal(#f.result.entries, 3)
    local sources = f.result.entries[1].sources
    equal(#sources, 2)
    equal(sources[1].quantity, 2); equal(sources[1].alternatives, 3)
    equal(sources[2].quantity, 7); equal(sources[2].slotIndex, 2)
    local api, calls, details = auctionator()
    equal(G.AuctionatorAdapter.Export(api, f.result, "Qualities"), true)
    equal(#calls[1].terms, 1); equal(calls[1].terms[1], '"Ore"')
    for _, term in ipairs(details) do
        equal(term.tier, ""); equal(term.quality, nil); equal(term.quantity, nil)
    end
end)

test("export also deduplicates repeated inputs and converter-equivalent searches", function()
    local api, calls = auctionator()
    api.ConvertToSearchString = function(_, term) return term.searchString:lower() end
    local result = exportResult()
    result.entries[#result.entries + 1] = result.entries[1]
    result.entries[#result.entries + 1] = { itemID = 99, name = "ORE" }
    equal(G.AuctionatorAdapter.Export(api, result, "Duplicates"), true)
    equal(#calls[1].terms, 2)
    equal(calls[1].terms[1], "ore"); equal(calls[1].terms[2], "herb")
end)

test("conversion error prevents any list mutation", function()
    local api, calls = auctionator()
    api.ConvertToSearchString = function() error("Bad format") end
    local ok, message = G.AuctionatorAdapter.Export(api, exportResult(), "New test list")
    equal(ok, false); equal(#calls, 0); contains(message, "Bad format")
end)

test("partial export requires explicit opt-in", function()
    local api, calls = auctionator(); local result = exportResult(); result.complete = false
    local ok = G.AuctionatorAdapter.Export(api, result, "New test list", false)
    equal(ok, false); equal(#calls, 0)
    equal(G.AuctionatorAdapter.Export(api, result, "New PARTIAL list", true), true)
end)

test("missing Auctionator and empty material lists are actionable errors", function()
    local ok, message = G.AuctionatorAdapter.Export(nil, exportResult(), "Test")
    equal(ok, false); contains(message, "Enable Auctionator")
    local api, calls = auctionator(); local result = exportResult(); result.entries = {}
    ok, message = G.AuctionatorAdapter.Export(api, result, "Test")
    equal(ok, false); contains(message, "No resolved"); equal(#calls, 0)
end)

test("invalid names and grammar cannot create broad accidental searches", function()
    local api, calls = auctionator(); local result = exportResult()
    result.entries[2].name = 'Ore;anything'
    equal(G.AuctionatorAdapter.Export(api, result, "Test"), false)
    equal(#calls, 0)
    result.entries[2].name = "Ore"
    equal(G.AuctionatorAdapter.Export(api, result, "\n"), false)
    equal(#calls, 0)
end)

test("Auctionator write failures are reported without a success message", function()
    local api = auctionator()
    api.CreateShoppingList = function() error("unavailable") end
    local ok, message = G.AuctionatorAdapter.Export(api, exportResult(), "Test")
    equal(ok, false); contains(message, "did not confirm")
end)

test("sync merges searches and preserves other characters, filters and other lists", function()
    local api, calls, _, lists = auctionator()
    lists.Test = { '"Old ore";tier=2', '"Ore"' }
    lists.Other = { "Keep me" }
    equal(G.AuctionatorAdapter.Export(api, exportResult(), "Test"), true)
    equal(#lists.Test, 3); equal(lists.Test[1], '"Old ore";tier=2'); equal(lists.Test[3], '"Herb"')
    local smaller = exportResult(); table.remove(smaller.entries, 2)
    equal(G.AuctionatorAdapter.Export(api, smaller, "Test"), true)
    equal(#lists.Test, 3); equal(lists.Test[2], '"Ore"')
    equal(G.AuctionatorAdapter.Export(api, smaller, "Test"), true)
    equal(#lists.Test, 3); equal(calls[3].name, "Test"); equal(lists.Other[1], "Keep me")
end)

test("missing sync APIs prevent writes", function()
    for _, missing in ipairs({ "GetShoppingListItems", "CreateShoppingList", "ConvertToSearchString" }) do
        local api, calls = auctionator(); api[missing] = nil
        equal(G.AuctionatorAdapter.Export(api, exportResult(), "Test"), false)
        equal(#calls, 0)
    end
end)

test("formatting and empty or unapproved partial results preserve an existing list", function()
    local api, calls, _, lists = auctionator(); lists.Test = { "Keep me" }
    local result = exportResult(); result.entries[2].name = 'bad;name'
    equal(G.AuctionatorAdapter.Export(api, result, "Test"), false)
    result.entries = {}
    equal(G.AuctionatorAdapter.Export(api, result, "Test"), false)
    result = exportResult(); result.complete = false
    equal(G.AuctionatorAdapter.Export(api, result, "Test"), false)
    equal(#calls, 0); equal(lists.Test[1], "Keep me")
    equal(G.AuctionatorAdapter.Export(api, result, "Test", true), true)
    equal(#lists.Test, 3); equal(lists.Test[1], "Keep me")
end)

test("read failures and missing new terms never trigger stale-item deletion", function()
    for _, mode in ipairs({ "read error", "missing term" }) do
        local api, _, _, lists = auctionator(); lists.Test = { "Keep me" }
        if mode == "read error" then api.GetShoppingListItems = function() error("not ready") end
        else api.CreateShoppingList = function() end end
        api.DeleteShoppingListItem = function() error("Must not delete") end
        local ok, message = G.AuctionatorAdapter.Export(api, exportResult(), "Test")
        equal(ok, false); contains(message, mode == "read error" and "Cannot read" or "could not be verified")
        equal(lists.Test[1], "Keep me")
    end
end)

test("merge does not require or call the deletion API", function()
    local api, _, _, lists = auctionator(); lists.Test = { "Stale" }
    api.DeleteShoppingListItem = nil
    equal(G.AuctionatorAdapter.Export(api, exportResult(), "Test"), true)
    equal(#lists.Test, 3)
    api.DeleteShoppingListItem = function() error("Must not delete") end
    equal(G.AuctionatorAdapter.Export(api, exportResult(), "Test"), true)
    equal(#lists.Test, 3)
end)

test("combined and split lists include outputs with stable names and no quality filter", function()
    local api, calls, _, lists = auctionator()
    local result = exportResult()
    local split = G.Collector.ExportLists(result, "Gorloc - Alchemy", "split")
    equal(#split, 2)
    equal(split[1].name, "Gorloc - Alchemy - Materials")
    equal(split[2].name, "Gorloc - Alchemy - Items")
    equal(G.AuctionatorAdapter.ExportLists(api, split, false), true)
    equal(#lists[split[1].name], 2); equal(#lists[split[2].name], 2)
    result.outputs = { result.outputs[1] }
    equal(G.AuctionatorAdapter.ExportLists(api, G.Collector.ExportLists(result, "Gorloc - Alchemy", "split")), true)
    equal(#lists[split[2].name], 2); equal(lists[split[2].name][1], '"Potion"')
    local combined = G.Collector.ExportLists(result, "Gorloc - Alchemy", "combined")
    equal(G.AuctionatorAdapter.ExportLists(api, combined), true)
    equal(#lists['Gorloc - Alchemy'], 3)
end)

test("invalid second payload prevents either split-list write", function()
    local api, calls = auctionator(); local result = exportResult()
    result.outputs[1].name = 'bad;output'
    equal(G.AuctionatorAdapter.ExportLists(api, G.Collector.ExportLists(result, "Test", "split")), false)
    equal(#calls, 0)
end)

test("split failure reports the completed list and allows retry", function()
    local api, _, _, lists = auctionator(); local create = api.CreateShoppingList
    api.CreateShoppingList = function(caller, name, terms)
        if name == "Test - Items" then error("unavailable") end
        return create(caller, name, terms)
    end
    local jobs = G.Collector.ExportLists(exportResult(), "Test", "split")
    local ok, message = G.AuctionatorAdapter.ExportLists(api, jobs)
    equal(ok, false); contains(message, "Already synced: Test - Materials")
    contains(message, "Failed: Test - Items")
    api.CreateShoppingList = create
    equal(G.AuctionatorAdapter.ExportLists(api, jobs), true)
    equal(#lists['Test - Materials'], 2); equal(#lists['Test - Items'], 2)
end)

test("empty sections skip writes and output-only recipes can export", function()
    local result = exportResult(); result.entries = {}
    local jobs = G.Collector.ExportLists(result, "Test", "split")
    equal(#jobs, 1); equal(jobs[1].name, "Test - Items")
    local api = auctionator(); equal(G.AuctionatorAdapter.ExportLists(api, jobs), true)
    result.outputs = {}
    equal(G.AuctionatorAdapter.ExportLists(api, G.Collector.ExportLists(result, "Test", "combined")), false)
end)

test("runtime collects output quality IDs and falls back to item data or links", function()
    C_TradeSkillUI = {
        GetRecipeSchematic = function() return { outputItemID = 101 } end,
        GetRecipeQualityItemIDs = function() return { 101, 102, 103 } end,
    }
    local ids = G.Runtime.Outputs(1)
    equal(#ids, 3); equal(ids[3], 103)
    C_TradeSkillUI.GetRecipeSchematic = function() return {} end
    C_TradeSkillUI.GetRecipeQualityItemIDs = function() end
    C_TradeSkillUI.GetRecipeOutputItemData = function() return { itemID = 104 } end
    ids = G.Runtime.Outputs(1); equal(ids[1], 104)
    C_TradeSkillUI.GetRecipeOutputItemData = function() return { hyperlink = '|Hitem:105:0|h[Scroll]|h' } end
    ids = G.Runtime.Outputs(1); equal(ids[1], 105)
    C_TradeSkillUI.GetRecipeOutputItemData = function() return {} end
    local missing, why = G.Runtime.Outputs(1); equal(missing, nil); contains(why, "unavailable")
    Enum = { TradeskillRecipeType = { Item = 0, Enchant = 1 } }
    C_TradeSkillUI.GetRecipeSchematic = function() return { recipeType = 1 } end
    ids, why = G.Runtime.Outputs(1); equal(#ids, 0); contains(why, "No auctionable item output")
    Auctionator = { CraftingInfo = { EnchantSpellsToItems = { [1] = { 106, 107 } } } }
    ids = G.Runtime.Outputs(1); equal(#ids, 2); equal(ids[2], 107)
    ids, why = G.Runtime.Outputs(2); equal(#ids, 0); contains(why, "No auctionable item output")
    Auctionator = nil
end)

test("Retail runtime uses stable skill IDs for membership and localized current label only for default", function()
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, LE_EXPANSION_LEVEL_CURRENT = 1, 1, 11
    EXPANSION_NAME11 = "Current"
    ProfessionsFrame = { IsShown = function() return true end }
    C_TradeSkillUI = {
        GetAllRecipeIDs = function() return {} end,
        GetRecipeSchematic = function() end,
        IsRecipeInSkillLine = function() return true end,
        GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy", sourceCounter = 7 } end,
        GetChildProfessionInfo = function() return { professionID = 100 } end,
        GetChildProfessionInfos = function() return {
            { professionID = 100, expansionName = "Old" },
            { professionID = 200, expansionName = "Current" },
        } end,
    }
    local c = G.Runtime.Context()
    equal(c.baseID, 171); equal(c.childID, 100)
    equal(G.DefaultSelection(c)[200], true)
    C_TradeSkillUI.IsTradeSkillLinked = function() return true end
    local blocked, reason = G.Runtime.Context()
    equal(blocked, nil); contains(reason, "linked")
    C_TradeSkillUI.IsTradeSkillLinked = nil
    WOW_PROJECT_ID = 2
    blocked, reason = G.Runtime.Context()
    equal(blocked, nil); contains(reason, "Retail")
end)

test("profession detection handles sparse slots, Cooking and gathering exclusions", function()
    GetProfessions = function() return nil, 7, 8, 9, 10 end
    GetProfessionInfo = function(index)
        local id = ({ [7] = 171, [8] = 794, [9] = 356, [10] = 185 })[index]
        return "Profession " .. id, nil, 1, 100, 1, 0, id
    end
    local professions = G.Runtime.Professions()
    equal(#professions, 2); equal(professions[1].id, 171); equal(professions[2].id, 185)
    GetProfessions = function() return 1, 2, nil, nil, 10 end
    GetProfessionInfo = function(index)
        local id = ({ [1] = 182, [2] = 393, [10] = 185 })[index]
        return "Profession " .. id, nil, 1, 100, 1, 0, id
    end
    professions = G.Runtime.Professions()
    equal(#professions, 1); equal(professions[1].id, 185)
    GetProfessions = function() return nil, nil, nil, nil, 10 end
    professions = G.Runtime.Professions(); equal(#professions, 1); equal(professions[1].id, 185)
end)

test("profession detection tolerates unavailable API and duplicate metadata", function()
    GetProfessions = nil
    local professions, reason = G.Runtime.Professions(); equal(#professions, 0); contains(reason, "unavailable")
    GetProfessions = function() return 1, 2, nil, nil, 3 end
    GetProfessionInfo = function(index)
        if index == 3 then error("Loading") end
        return "Alchemy", nil, 1, 100, 1, 0, 171
    end
    professions = G.Runtime.Professions(); equal(#professions, 1)
end)

test("automatic opening and closing respect pending specialization edits", function()
    local opens, closes, pending, combat = 0, 0, true, false
    InCombatLockdown = function() return combat end
    ProfessionsFrame = { SpecPage = { HasAnyConfigChanges = function() return pending end } }
    C_TradeSkillUI.OpenTradeSkill = function(id) equal(id, 171); opens = opens + 1; return true end
    C_TradeSkillUI.CloseTradeSkill = function() closes = closes + 1 end
    local ok, message = G.Runtime.OpenProfession(171)
    equal(ok, false); contains(message, "specialization")
    equal(G.Runtime.CloseProfession(), false); equal(closes, 0)
    pending, combat = false, true
    equal(G.Runtime.OpenProfession(171), false); equal(G.Runtime.CloseProfession(), false)
    equal(opens, 0); equal(closes, 0)
    combat = false
    equal(G.Runtime.OpenProfession(171), true); equal(G.Runtime.CloseProfession(), true)
    equal(opens, 1); equal(closes, 1)
end)

test("runtime distinguishes bound reagents and quality tiers", function()
    C_Item = { GetItemInfo = function() return "Ore", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1 end }
    C_TradeSkillUI.GetItemReagentQualityByItemInfo = function() return 2 end
    local item = G.Runtime.Item(10)
    equal(item.name, "Ore"); equal(item.tier, 2); equal(item.blocked, "Binds on pickup")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
