-- Account history and additive Auctionator integration: lua5.1 tests/multi_character.lua
local G = {}
for _, module in ipairs({ "Util", "MaterialCollector", "AuctionatorAdapter", "ContributionStore", "Runtime" }) do
    assert(loadfile("GorlocCraftScan/" .. module .. ".lua"))("GorlocCraftScan", G)
end
date = os.date
local Store, Adapter = G.ContributionStore, G.AuctionatorAdapter
local passed, failed = 0, 0
local function equal(actual, expected)
    assert(actual == expected, "Expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, fn)
    local ok, reason = pcall(fn)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(reason)) end
end
local A = { guid = "Player-1-A", name = "Alchemist", realm = "Realm A" }
local B = { guid = "Player-2-B", name = "Alchemist", realm = "Realm B" }
local function result(itemIDs, options)
    options = options or {}
    local r = {
        context = { baseID = 171, name = "Alchemy", expansions = {
            { id = 100, name = "Old" }, { id = 200, name = "Current" },
        } },
        selection = options.selection or { [200] = true }, includeUnlearned = options.all or false,
        complete = not options.partial, recipes = {}, entries = {}, outputs = {}, issues = {},
    }
    for _, id in ipairs(itemIDs) do
        r.recipes[#r.recipes + 1] = { id = id * 10 }
        r.entries[#r.entries + 1] = { itemID = id, name = "Material " .. id }
        r.outputs[#r.outputs + 1] = { itemID = id + 1000, name = "Output " .. id }
    end
    return r
end
local function fixture()
    local f = { db = Store.Initialize({}), lists = {}, writes = 0, now = 1000 }
    f.api = {
        ConvertToSearchString = function(_, term)
            equal(term.tier, ""); equal(term.quantity, nil); equal(term.quality, nil)
            return '"' .. term.searchString .. '"'
        end,
        -- Replacement semantics exercise the explicit old/new union in the adapter.
        CreateShoppingList = function(_, name, terms)
            f.writes = f.writes + 1
            local copy = {}; for i, term in ipairs(terms) do copy[i] = term end
            f.lists[name] = copy
        end,
        GetShoppingListItems = function(_, name)
            if not f.lists[name] then error("missing list") end
            return f.lists[name]
        end,
        DeleteShoppingListItem = function() error("Merge must never delete") end,
    }
    f.exists = function(name) return f.lists[name] ~= nil end
    function f:scan(character, scan)
        return assert(Store.RecordScan(self.db, character, scan))
    end
    function f:sync(ticket, scan, mode, allowPartial)
        self.now = self.now + 1
        local ok, message, outcomes = Adapter.ExportLists(self.api,
            G.Collector.ExportLists(scan, "Gorloc - Alchemy", mode or "combined"), allowPartial, self.exists)
        Store.RecordSync(self.db, ticket, outcomes, self.now)
        return ok, message, outcomes
    end
    function f:scope(character, key)
        return self.db.characters[character.guid].professions[171].scopes[key or "known:200"]
    end
    return f
end
local function serialize(value)
    if type(value) == "table" then
        local terms = {}
        for key, entry in pairs(value) do terms[#terms + 1] = "[" .. serialize(key) .. "]=" .. serialize(entry) end
        return "{" .. table.concat(terms, ",") .. "}"
    end
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

for _, mode in ipairs({ "combined", "split" }) do
    test("two characters A/B then B/C then smaller A survive reload: " .. mode, function()
        local f = fixture()
        local first, second, smaller = result({ 1, 2 }), result({ 2, 3 }), result({ 1 })
        equal(f:sync(f:scan(A, first), first, mode), true)
        -- Simulate SavedVariables serialization and a subsequent character login.
        f.db = Store.Initialize(assert(loadstring("return " .. serialize(f.db)))())
        equal(f:sync(f:scan(B, second), second, mode), true)
        equal(f:sync(f:scan(A, smaller), smaller, mode), true)
        local lists = G.Collector.ExportLists(first, "Gorloc - Alchemy", mode)
        for _, list in ipairs(lists) do
            equal(#f.lists[list.name], mode == "combined" and 6 or 3)
            local seen = {}
            for _, term in ipairs(f.lists[list.name]) do assert(not seen[term]); seen[term] = true end
        end
        equal(f.db.characters[A.guid].realm, "Realm A")
        equal(f.db.characters[B.guid].realm, "Realm B")
        equal(f:scope(A).lastSyncAt, f.now); equal(f:scope(A).syncFailed, false)
        assert(f:scope(B).lastSyncAt < f.now)
    end)
end

test("v3 migration keeps preferences and drops unused export metadata", function()
    local old = { schemaVersion = 3, listMode = "split", listNames = { [171] = "Custom" },
        lastExport = { name = "Legacy", at = 123 }, exportSequence = 5 }
    Store.Initialize(old); Store.Initialize(old)
    equal(old.schemaVersion, 5); equal(old.listMode, "split"); equal(old.listNames, nil)
    equal(old.lastExport, nil); equal(next(old.characters), nil); equal(old.exportSequence, nil)
end)

test("v4 migration keeps only what the Characters tab shows", function()
    local scan = { at = 10, complete = true, includeUnlearned = false, scopeLabel = "Current",
        expansionIDs = { 200 }, recipeIDs = { 1, 2 }, materialIDs = { 3 }, outputIDs = { 4 }, issueCount = 0 }
    local db = { schemaVersion = 4, listMode = "split", window = { point = "CENTER" },
        destinations = { ["Gorloc - Alchemy"] = { attributedTerms = { "x" }, unattributedTerms = {} } },
        characters = { [A.guid] = { name = A.name, realm = A.realm, professions = { [171] = { name = "Alchemy", scopes = {
            ["known:200"] = { latestScan = scan, completeSnapshot = scan, coverage = scan, destinations = {
                ["Gorloc - Alchemy - Materials"] = { terms = { "x" }, recipeIDs = { 1 },
                    lastAttempt = { at = 30, status = "failed", message = "Unavailable" },
                    lastVerified = { at = 20, snapshot = scan } },
                ["Gorloc - Alchemy - Items"] = { lastAttempt = { at = 25, status = "verified" }, lastVerified = { at = 25 } },
            } },
            ["all:200"] = { latestScan = { complete = false, includeUnlearned = true, scopeLabel = "Current" }, destinations = {} },
        } } } } },
    }
    Store.Initialize(db); Store.Initialize(db)
    equal(db.schemaVersion, 5); equal(db.listMode, "split"); equal(db.window.point, "CENTER"); equal(db.destinations, nil)
    local scopes = db.characters[A.guid].professions[171].scopes
    local function fields(scope)
        local count = 0; for _ in pairs(scope) do count = count + 1 end
        return count, scope.scopeLabel, scope.includeUnlearned, scope.complete, scope.lastSyncAt, scope.syncFailed
    end
    local count, label, all, complete, lastSync, failed = fields(scopes["known:200"])
    equal(count, 5); equal(label, "Current"); equal(all, false); equal(complete, true); equal(lastSync, 25); equal(failed, true)
    count, label, all, complete, lastSync, failed = fields(scopes["all:200"])
    equal(count, 4); equal(all, true); equal(complete, false); equal(lastSync, nil); equal(failed, false)
end)

test("legacy and manual filtered terms are preserved", function()
    local f = fixture(); local name = "Gorloc - Alchemy"
    f.lists[name] = { '"Material 1";tier=2', '"Manual"', '"Material 1"' }
    local r = result({ 1 }); local ticket = f:scan(A, r)
    local ok, _, outcomes = f:sync(ticket, r)
    equal(ok, true); equal(#f.lists[name], 4)
    equal(outcomes[1].added, 1); equal(outcomes[1].present, 1); equal(outcomes[1].total, 4)
    equal(f:sync(ticket, r), true); equal(#f.lists[name], 4)
end)

test("scope keys are stable and distinguish expansion coverage and known/all", function()
    local f = fixture()
    local broad = result({ 1, 2 }, { selection = { [200] = true, [100] = true } })
    local ticket = f:scan(A, broad)
    equal(ticket.scopeKey, "known:100,200")
    equal(f:sync(ticket, broad), true)
    local narrow = result({ 1 })
    equal(f:sync(f:scan(A, narrow), narrow), true)
    local all = result({ 3 }, { all = true })
    equal(f:sync(f:scan(A, all), all), true)
    equal(f:scope(A, "known:100,200").scopeLabel, "Old, Current")
    equal(f:scope(A, "all:200").includeUnlearned, true)
    equal(#f.lists['Gorloc - Alchemy'], 6)
end)

test("partial and empty scans do not erase list entries or the last sync time", function()
    local f = fixture(); local full = result({ 1, 2 }); local name = "Gorloc - Alchemy"
    equal(f:sync(f:scan(A, full), full), true)
    local at = f:scope(A).lastSyncAt
    local partial = result({ 3 }, { partial = true }); local ticket = f:scan(A, partial)
    equal(f:scope(A).complete, false)
    equal(f:sync(ticket, partial), false)
    equal(f:scope(A).lastSyncAt, at); equal(f:scope(A).syncFailed, true)
    equal(f:sync(ticket, partial, "combined", true), true)
    equal(#f.lists[name], 6); equal(f:scope(A).syncFailed, false)
    at = f:scope(A).lastSyncAt
    local empty = result({}); ticket = f:scan(A, empty)
    equal(f:sync(ticket, empty), false); equal(#f.lists[name], 6)
    equal(f:scope(A).lastSyncAt, at)
end)

test("a scan alone does not claim to be synced", function()
    local f = fixture(); f:scan(A, result({ 1 }))
    equal(f:scope(A).lastSyncAt, nil); equal(f:scope(A).syncFailed, nil); equal(f:scope(A).complete, true)
end)

test("rename retains GUID identity and missing GUID cannot invent a contributor", function()
    local f = fixture(); f:scan(A, result({ 1 }))
    f:scan({ guid = A.guid, name = "Renamed", realm = A.realm }, result({ 2 }))
    equal(f.db.characters[A.guid].name, "Renamed")
    local ticket = Store.RecordScan(f.db, { name = "Unknown" }, result({ 1 }), 1)
    equal(ticket, nil)
end)

for _, response in ipairs({ "error", "nil", "malformed", "sparse" }) do
    test("failed list read prevents every split write: " .. response, function()
        local f = fixture(); local r = result({ 1 }); local ticket = f:scan(A, r)
        f.lists['Gorloc - Alchemy - Materials'] = { "Keep material" }
        f.lists['Gorloc - Alchemy - Items'] = { "Keep item" }
        local read = f.api.GetShoppingListItems
        f.api.GetShoppingListItems = function(caller, name)
            if name:find("Items", 1, true) then
                if response == "error" then error("Not ready") end
                if response == "nil" then return nil end
                if response == "malformed" then return { [1] = false } end
                return { [1] = "A", [3] = "B" }
            end
            return read(caller, name)
        end
        equal(f:sync(ticket, r, "split"), false); equal(f.writes, 0)
        equal(f:scope(A).lastSyncAt, nil); equal(f:scope(A).syncFailed, true)
    end)
end

test("read error is not interpreted as missing without an existence probe", function()
    local f = fixture(); local r = result({ 1 })
    equal(Adapter.ExportLists(f.api, G.Collector.ExportLists(r, "Test", "combined")), false)
    equal(f.writes, 0)
    f.exists = function() error("Not ready") end
    equal(f:sync(f:scan(A, r), r), false); equal(f.writes, 0)
end)

test("second write failure records first verified destination and allows retry", function()
    local f = fixture(); local r = result({ 1 }); local ticket = f:scan(A, r)
    local write = f.api.CreateShoppingList
    f.api.CreateShoppingList = function(caller, name, terms)
        if name:find("Items", 1, true) then return false end
        return write(caller, name, terms)
    end
    local ok, message = f:sync(ticket, r, "split")
    equal(ok, false); assert(message:find("Already synced", 1, true))
    equal(f:scope(A).lastSyncAt, f.now); equal(f:scope(A).syncFailed, true)
    f.api.CreateShoppingList = write
    equal(f:sync(ticket, r, "split"), true)
    equal(#f.lists['Gorloc - Alchemy - Materials'], 1)
    equal(f:scope(A).syncFailed, false)
end)

for _, broken in ipairs({ "drop old", "drop new", "mutate payload", "readback failure", "duplicate searches" }) do
    test("failed verification cannot advance previous successful sync: " .. broken, function()
        local f = fixture(); local first = result({ 1 }); local name = "Gorloc - Alchemy"
        equal(f:sync(f:scan(A, first), first), true)
        local at = f:scope(A).lastSyncAt
        local r = result({ 2 }); local ticket = f:scan(A, r)
        local write = f.api.CreateShoppingList
        f.api.CreateShoppingList = function(caller, dest, terms)
            if broken == "duplicate searches" then terms[#terms + 1] = terms[1]
            elseif broken == "drop old" then table.remove(terms, 1)
            elseif broken == "drop new" then table.remove(terms)
            elseif broken == "mutate payload" then for i = #terms, 1, -1 do terms[i] = nil end end
            write(caller, dest, terms)
            if broken == "readback failure" then f.api.GetShoppingListItems = function() return nil end end
        end
        equal(f:sync(ticket, r), false)
        equal(f:scope(A).lastSyncAt, at); equal(f:scope(A).syncFailed, true)
    end)
end

test("read-only existence bridge rejects unavailable and invalid results", function()
    Auctionator = nil; equal(G.Runtime.AuctionatorListExists("Test"), nil)
    Auctionator = { Shopping = { ListManager = { GetIndexForName = function() return 1 end } } }
    equal(G.Runtime.AuctionatorListExists("Test"), true)
    Auctionator.Shopping.ListManager.GetIndexForName = function() return nil end
    equal(G.Runtime.AuctionatorListExists("Test"), false)
    Auctionator.Shopping.ListManager.GetIndexForName = function() error("Not ready") end
    equal(G.Runtime.AuctionatorListExists("Test"), nil)
    Auctionator.Shopping.ListManager.GetIndexForName = function() return "1" end
    equal(G.Runtime.AuctionatorListExists("Test"), nil)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
