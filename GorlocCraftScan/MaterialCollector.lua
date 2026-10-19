local _, G = ...
local Collector = {}
G.Collector = Collector

function Collector.NewResult(context, selection, includeUnlearned)
    return {
        context = context, selection = G.CopySelection(selection),
        includeUnlearned = includeUnlearned, recipes = {}, entries = {}, outputs = {},
        nonShopping = {}, issues = {}, excluded = {}, complete = true,
        scanned = 0, learned = 0, unlearned = 0, optionalSlots = 0,
    }
end

function Collector.AddOutputs(result, recipe, ids, exclusion)
    if exclusion then
        result.nonShopping[#result.nonShopping + 1] = {
            recipeID = recipe.id, recipeName = recipe.name or tostring(recipe.id),
            name = recipe.name or tostring(recipe.id), reason = exclusion, isOutput = true,
        }
    end
    for _, id in ipairs(ids) do
        result.outputs[#result.outputs + 1] = {
            itemID = id, recipeID = recipe.id, recipeName = recipe.name or tostring(recipe.id),
            isOutput = true,
        }
    end
end

function Collector.Issue(result, recipeID, message)
    result.complete = false
    result.issues[#result.issues + 1] = { recipeID = recipeID, message = message }
end

function Collector.Exclusion(info)
    if info.isDummyRecipe then return "Dummy recipe" end
    if info.isRecraft then return "Recrafting" end
    if info.isGatheringRecipe then return "Gathering" end
    if info.isSalvageRecipe then return "Salvage inputs" end
end

-- Collect occurrences first; Resolve groups them by item ID after metadata loads.
function Collector.AddRecipe(result, info, schematic)
    local recipeID = info.recipeID
    result.recipes[#result.recipes + 1] = { id = recipeID, name = info.name, learned = info.learned }
    if info.learned then result.learned = result.learned + 1
    else result.unlearned = result.unlearned + 1 end

    for index, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.required == false then
            result.optionalSlots = result.optionalSlots + 1
        elseif slot.required ~= true then
            Collector.Issue(result, recipeID, "Unknown requirement for reagent slot " .. index)
        else
            local reagents = slot.reagents
            if type(reagents) ~= "table" or #reagents == 0 then
                Collector.Issue(result, recipeID, "No alternatives available for required slot " .. index)
            else
                for _, reagent in ipairs(reagents) do
                    local entry = {
                        itemID = reagent.itemID, currencyID = reagent.currencyID,
                        recipeID = recipeID, recipeName = info.name or tostring(recipeID),
                        slotIndex = slot.dataSlotIndex or index,
                        quantity = slot.quantityRequired, alternatives = #reagents,
                    }
                    -- Variable quantities are metadata only: this is a price catalog, not a craft allocation.
                    for _, variable in ipairs(slot.variableQuantities or {}) do
                        local candidate = variable.reagent or {}
                        if (entry.itemID and entry.itemID == candidate.itemID)
                            or (entry.currencyID and entry.currencyID == candidate.currencyID) then
                            entry.quantity = variable.quantity
                        end
                    end
                    if type(entry.currencyID) == "number" and entry.currencyID > 0 then
                        entry.reason = "Currency (not auctionable)"
                        result.nonShopping[#result.nonShopping + 1] = entry
                    elseif type(entry.itemID) == "number" and entry.itemID > 0 then
                        result.entries[#result.entries + 1] = entry
                    else
                        Collector.Issue(result, recipeID, "Unsupported reagent in required slot " .. index)
                    end
                end
            end
        end
    end
end

local function resolveEntries(result, entries, items)
    local searchable, byID = {}, {}
    for _, entry in ipairs(entries) do
        local item = items[entry.itemID]
        if not item or not item.name then
            Collector.Issue(result, entry.recipeID,
                (entry.isOutput and "Crafted item data unavailable: " or "Item data unavailable: ") .. entry.itemID)
        elseif item.blocked then
            entry.name = item.name
            entry.reason = item.blocked
            result.nonShopping[#result.nonShopping + 1] = entry
        else
            entry.name = item.name
            entry.tier = item.tier
            entry.bindType = item.bindType
            local material = byID[entry.itemID]
            if not material then
                material = {}
                for key, value in pairs(entry) do material[key] = value end
                material.sources = {}
                byID[entry.itemID] = material
                searchable[#searchable + 1] = material
            end
            material.sources[#material.sources + 1] = entry
        end
    end
    return searchable
end

function Collector.Resolve(result, items)
    result.entries = resolveEntries(result, result.entries, items)
    result.outputs = resolveEntries(result, result.outputs, items)
end

function Collector.ExportLists(result, baseName, mode)
    local lists = {}
    local function add(name, entries, role)
        if #entries > 0 then
            lists[#lists + 1] = { name = name, role = role, result = { entries = entries, complete = result.complete } }
        end
    end
    if mode == "split" then
        add(baseName .. " - Materials", result.entries, "materials")
        add(baseName .. " - Items", result.outputs, "items")
    else
        local entries, seen = {}, {}
        for _, group in ipairs({ result.entries, result.outputs }) do
            for _, entry in ipairs(group) do
                if not seen[entry.itemID] then
                    seen[entry.itemID] = true
                    entries[#entries + 1] = entry
                end
            end
        end
        add(baseName, entries, "combined")
    end
    return lists
end

function Collector.Report(result, limit)
    local lines = {
        result.context.name .. " — " .. G.ScopeLabel(result.context, result.selection),
        result.includeUnlearned and "Known + unlearned recipes exposed by the game" or "Known recipes only",
        string.format("%d recipes (%d known, %d unlearned); %d unique material items; %d crafted items.",
            #result.recipes, result.learned, result.unlearned, #result.entries, #result.outputs),
        string.format("%d excluded recipes; %d optional slots skipped; %d non-shopping requirements.",
            #result.excluded, result.optionalSlots, #result.nonShopping),
        result.complete and "Recipe data loaded. Review the scope before exporting."
            or ("PARTIAL: " .. #result.issues .. " data problems. Review below."),
        "Export combines identical searches and searches all qualities. Alternatives are not cumulative purchases.", "",
    }
    local remaining = limit or math.huge
    local function add(line)
        if remaining > 0 then lines[#lines + 1] = line end
        remaining = remaining - 1
    end
    -- Problems first so a long catalog cannot hide an incomplete scan.
    for _, issue in ipairs(result.issues) do
        add("! Recipe " .. tostring(issue.recipeID or "?") .. ": " .. issue.message)
    end
    add("Materials")
    for _, entry in ipairs(result.entries) do
        local tier = entry.tier and (" [quality " .. entry.tier .. "]") or ""
        add(string.format("%s%s (item %d)", entry.name, tier, entry.itemID))
        for _, source in ipairs(entry.sources) do
            local alternatives = source.alternatives > 1
                and ("; one of " .. source.alternatives .. " alternatives") or ""
            add(string.format("  %s; slot %s; per craft %s%s",
                source.recipeName, source.slotIndex, tostring(source.quantity or "?"), alternatives))
        end
    end
    add("Crafted items")
    for _, entry in ipairs(result.outputs) do
        add(string.format("%s (item %d)", entry.name, entry.itemID))
        for _, source in ipairs(entry.sources) do add("  Crafted by: " .. source.recipeName) end
    end
    for _, entry in ipairs(result.nonShopping) do
        add((entry.isOutput and "Excluded output: " or "Excluded material: ")
            .. (entry.name or ("currency " .. tostring(entry.currencyID)))
            .. " — " .. entry.reason .. "; " .. entry.recipeName)
    end
    for _, entry in ipairs(result.excluded) do
        add("Excluded recipe: " .. entry.name .. " — " .. entry.reason)
    end
    if remaining < 0 then
        lines[#lines + 1] = string.format("... %d more preview rows. Export covers all resolved materials and crafted items.", -remaining)
    end
    return table.concat(lines, "\n")
end
