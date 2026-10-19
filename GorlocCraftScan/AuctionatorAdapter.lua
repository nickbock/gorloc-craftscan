local _, G = ...
local Adapter = {}
G.AuctionatorAdapter = Adapter

function Adapter.Check(api)
    if type(api) ~= "table" then return false, "Enable Auctionator to sync a shopping list." end
    if type(api.CreateShoppingList) ~= "function" or type(api.ConvertToSearchString) ~= "function"
        or type(api.GetShoppingListItems) ~= "function" then
        return false, "This Auctionator version does not expose the required shopping-list API. Update Auctionator."
    end
    return true
end

function Adapter.BuildTerms(api, result)
    local available, reason = Adapter.Check(api)
    if not available then return nil, reason end
    local terms, seen = {}, {}
    for _, entry in ipairs(result.entries) do
        -- Do not try to escape Auctionator grammar ourselves.
        if type(entry.name) ~= "string" or G.Trim(entry.name) == "" or entry.name:find('[;"\r\n]') then
            return nil, "Cannot safely search for item " .. tostring(entry.itemID) .. ". No list was created."
        end
        local ok, term = pcall(api.ConvertToSearchString, G.CALLER, {
            searchString = entry.name, isExact = true, categoryKey = "", tier = "",
            -- Empty tier means no reagent-quality restriction. Omit quantity and rarity.
        })
        if not ok or type(term) ~= "string" or term == "" then
            return nil, "Auctionator could not format item " .. entry.itemID .. ": " .. tostring(term)
        end
        -- Distinct quality item IDs can serialize to the same unrestricted search.
        if not seen[term] then
            seen[term] = true
            terms[#terms + 1] = term
        end
    end
    if #terms == 0 then return nil, "No resolved auction-searchable materials to export." end
    return terms
end

-- A missing-list probe is separate from reading: nil/errors never mean an empty list.
local function readItems(api, name, exists)
    if exists then
        local ok, present = pcall(exists, name)
        if not ok or type(present) ~= "boolean" then
            return nil, "Cannot determine whether the Auctionator list exists. Update Auctionator and retry."
        end
        if not present then return {} end
    end
    local ok, items = pcall(api.GetShoppingListItems, G.CALLER, name)
    if not ok or type(items) ~= "table" then
        return nil, "Cannot read the Auctionator list. No changes were made to this destination. Retry when Auctionator is ready."
    end
    local copy, count = {}, 0
    for key, term in pairs(items) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(term) ~= "string" or term == "" then
            return nil, "Auctionator returned invalid list contents. No changes were made to this destination."
        end
        count = count + 1
        copy[key] = term
    end
    for i = 1, count do
        if not copy[i] then return nil, "Auctionator returned an incomplete list. No changes were made to this destination." end
    end
    return copy
end

local function union(old, new)
    local terms, seen, added, present = {}, {}, 0, 0
    for _, term in ipairs(old) do
        if not seen[term] then seen[term] = true; terms[#terms + 1] = term end
    end
    for _, term in ipairs(new) do
        if seen[term] then present = present + 1
        else seen[term] = true; terms[#terms + 1] = term; added = added + 1 end
    end
    return terms, seen, added, present
end

function Adapter.ExportLists(api, lists, allowPartial, exists)
    local outcomes, prepared = {}, {}
    if #lists == 0 then return false, "No resolved materials or crafted items to sync.", outcomes end
    for i, list in ipairs(lists) do
        outcomes[i] = { name = list.name, role = list.role, status = "not attempted" }
    end
    local function failed(index, reason)
        local outcome = outcomes[index]
        outcome.status, outcome.message = "failed", reason
        local synced = {}
        for _, other in ipairs(outcomes) do
            if other.status == "verified" then synced[#synced + 1] = other.name end
        end
        local prefix = #synced > 0 and ("Already synced: " .. table.concat(synced, ", ") .. ". ") or ""
        return false, prefix .. "Failed: " .. tostring(outcome.name) .. ". " .. reason, outcomes
    end
    -- Validate all payloads and read every destination before the first write.
    for i, list in ipairs(lists) do
        if not list.result then return failed(i, "Preview recipes before syncing a list.") end
        if not list.result.complete and not allowPartial then
            return failed(i, "This scan is partial. Review Details and choose Sync available items to continue.")
        end
        if type(list.name) ~= "string" or G.Trim(list.name) == "" or list.name:find('[;\r\n]') then
            return failed(i, "Enter a list name without semicolons or line breaks.")
        end
        local terms, reason = Adapter.BuildTerms(api, list.result)
        if not terms then return failed(i, reason) end
        prepared[i] = terms
    end
    for i, list in ipairs(lists) do
        local old, reason = readItems(api, list.name, exists)
        if not old then return failed(i, reason) end
        local new = prepared[i]
        local merged, wanted, added, present = union(old, new)
        prepared[i] = { terms = merged, wanted = wanted }
        local outcome = outcomes[i]
        outcome.added, outcome.present, outcome.total = added, present, #merged
    end
    local summaries = {}
    for i, list in ipairs(lists) do
        local job, outcome = prepared[i], outcomes[i]
        -- Pass a copy: a third-party API must not mutate our verification target.
        local payload = {}
        for j, term in ipairs(job.terms) do payload[j] = term end
        local ok, response = pcall(api.CreateShoppingList, G.CALLER, list.name, payload)
        if not ok or response == false then
            return failed(i, "Auctionator did not confirm list creation: " .. tostring(response) .. ". Retry syncing.")
        end
        local current = readItems(api, list.name)
        if not current then return failed(i, "Cannot verify the Auctionator list after writing. Check its Shopping tab and retry.") end
        local unique, present = union(current, {})
        if #unique ~= #current then
            return failed(i, "Auctionator returned duplicate searches. Remove duplicates in its Shopping tab and retry syncing.")
        end
        outcome.total = #unique
        for term in pairs(job.wanted) do
            if not present[term] then
                return failed(i, "Auctionator list contents could not be verified. Check its Shopping tab and retry syncing.")
            end
        end
        outcome.status = "verified"
        summaries[#summaries + 1] = string.format("%s: %d new, %d already present, %d total",
            list.name, outcome.added, outcome.present, outcome.total)
    end
    return true, "Synced: " .. table.concat(summaries, "; ")
        .. ". Search the lists in Auctionator to refresh prices.", outcomes
end

function Adapter.Export(api, result, destination, allowPartial, exists)
    return Adapter.ExportLists(api, { { name = destination, result = result } }, allowPartial, exists)
end
