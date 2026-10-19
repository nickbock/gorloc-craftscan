local G = {}
for _, module in ipairs({ "Util", "MaterialCollector", "AuctionatorAdapter", "ContributionStore", "UIModel" }) do
    assert(loadfile("GorlocCraftScan/" .. module .. ".lua"))("GorlocCraftScan", G)
end
date = os.date
local passed, failed = 0, 0
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn)
    local ok, why = pcall(fn)
    if ok then passed = passed + 1; print("PASS " .. name) else failed = failed + 1; print("FAIL " .. name .. ": " .. why) end
end
local function result()
    return { context = { baseID = 171, name = "Alchemy", expansions = { { id = 200, name = "Current" } } },
        selection = { [200] = true }, recipes = { { id = 10 } }, includeUnlearned = false, complete = true,
        issues = {}, excluded = {}, nonShopping = {}, optionalSlots = 0,
        entries = {
            { itemID = 3, name = "Zinc", tier = 3, sources = { { recipeID = 10, recipeName = "Potion", slotIndex = 1, quantity = 2, alternatives = 3 },
                { recipeID = 10, recipeName = "Potion", slotIndex = 2, quantity = 1, alternatives = 1 } } },
            { itemID = 2, name = "Herb", sources = { { recipeID = 10 }, { recipeID = 20 } } },
            { itemID = 1, name = "Herb", sources = {} },
        }, outputs = { { itemID = 4, name = "Potion", sources = { { recipeID = 10, recipeName = "Potion", isOutput = true } } } } }
end
test("characters distinguish scanned and synced and preserve same-name realms", function()
    local db = G.ContributionStore.Initialize({}); local r = result()
    G.ContributionStore.RecordScan(db, { guid = "A", name = "Alt", realm = "Realm A" }, r)
    G.ContributionStore.RecordScan(db, { guid = "B", name = "Alt", realm = "Realm B" }, r)
    local rows = G.UIModel.CharacterRows(db)
    eq(#rows, 2); eq(rows[1].character, "Alt-Realm A"); eq(rows[2].character, "Alt-Realm B")
    eq(rows[1].lastSync, "Never"); eq(rows[1].status, "Complete")
end)
test("history keeps the verified sync time after a later failed attempt", function()
    local db = G.ContributionStore.Initialize({})
    local ticket = G.ContributionStore.RecordScan(db, { guid = "A", name = "Alt", realm = "Realm" }, result())
    local name = "Gorloc - Alchemy"
    G.ContributionStore.RecordSync(db, ticket, { { name = name, status = "verified", added = 2, present = 1, total = 3 } }, 2000)
    G.ContributionStore.RecordSync(db, ticket, { { name = name, status = "failed", message = "Unavailable" } }, 3000)
    local rows = G.UIModel.CharacterRows(db)
    eq(rows[1].state, "failed"); eq(rows[1].status, "Sync failed"); eq(rows[1].lastSync, date("%d %b %H:%M", 2000))
end)
test("partial scan history does not invent a verified sync", function()
    local db = G.ContributionStore.Initialize({}); local r = result(); r.complete = false
    G.ContributionStore.RecordScan(db, { guid = "A", name = "Alt", realm = "Realm" }, r)
    local rows = G.UIModel.CharacterRows(db)
    eq(rows[1].state, "partial"); eq(rows[1].lastSync, "Never")
    eq(rows[1].character, "Alt-Realm"); eq(rows[1].profession, "Alchemy"); eq(rows[1].scope, "Current · Known")
end)
test("sync summary counts verified destinations only and explains price refresh", function()
    local summary = G.UIModel.SyncSummary({
        { status = "verified", added = 2, present = 3 },
        { status = "failed", added = 100, present = 100 },
    })
    eq(summary, "Added 2 searches; 3 already present.\nSearch the list in Auctionator to refresh prices.")
    summary = G.UIModel.SyncSummary({ { status = "verified", added = 2, present = 3 }, { status = "verified", added = 1, present = 4 } })
    eq(summary, "Added 3 searches; 7 already present.\nSearch the lists in Auctionator to refresh prices.")
end)
print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
