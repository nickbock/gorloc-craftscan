local _, G = ...
local Runtime = {}
G.Runtime = Runtime

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function Runtime.Professions()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return {}, "Profession detection is unavailable on this client."
    end
    local ok, first, second, _, _, cooking = pcall(GetProfessions)
    if not ok then return {}, "Could not read your professions. Try Refresh." end
    local indices, professions, seen = { first, second, cooking }, {}, {}
    -- Sparse slots are normal (for example, Cooking with no primary profession).
    local gathering = { [182] = true, [186] = true, [393] = true }
    for i = 1, 3 do
        if indices[i] then
            local loaded, name, icon, _, _, _, _, skillLineID = pcall(GetProfessionInfo, indices[i])
            if loaded and type(skillLineID) == "number" and type(name) == "string"
                and skillLineID > 0 and not gathering[skillLineID] and not seen[skillLineID] then
                professions[#professions + 1] = { id = skillLineID, name = name, icon = icon }
                seen[skillLineID] = true
            end
        end
    end
    return professions
end

function Runtime.Snapshot()
    if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return nil end
    local api = C_TradeSkillUI
    if not api then return nil end
    local base, child = call(api.GetBaseProfessionInfo), call(api.GetChildProfessionInfo)
    local isLocal = true
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        if call(api[name]) then isLocal = false end
    end
    return { baseID = base and base.professionID, childID = child and child.professionID,
        sourceCounter = base and base.sourceCounter, isLocal = isLocal,
        isChanging = call(api.IsDataSourceChanging) == true }
end

local function pendingEdits()
    local page = ProfessionsFrame and ProfessionsFrame.SpecPage
    if page and type(page.HasAnyConfigChanges) == "function" then
        local ok, pending = pcall(page.HasAnyConfigChanges, page)
        return not ok or pending
    end
    return false
end

function Runtime.OpenProfession(id)
    if InCombatLockdown() then return false, "Leave combat before opening professions." end
    if pendingEdits() then return false, "Finish your pending specialization edits before switching professions." end
    if not C_TradeSkillUI or type(C_TradeSkillUI.OpenTradeSkill) ~= "function" then
        return false, "Automatic profession opening is unavailable. Open your profession manually."
    end
    return C_TradeSkillUI.OpenTradeSkill(id)
end

function Runtime.CloseProfession()
    if InCombatLockdown() or pendingEdits() then return false end
    C_TradeSkillUI.CloseTradeSkill()
    return true
end

function Runtime.SessionEnvironment()
    return {
        context = Runtime.Context, snapshot = Runtime.Snapshot,
        open = Runtime.OpenProfession, close = Runtime.CloseProfession,
        inCombat = InCombatLockdown,
        now = function() return (GetTimePreciseSec or GetTime)() end,
        after = function(delay, callback) C_Timer.After(delay, callback) end,
    }
end

function Runtime.Context()
    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return nil, "This local build supports Retail only." end
    local api = C_TradeSkillUI
    if not api or type(api.GetAllRecipeIDs) ~= "function"
        or type(api.GetRecipeSchematic) ~= "function"
        or type(api.IsRecipeInSkillLine) ~= "function" then
        return nil, "The required Retail profession APIs are unavailable."
    end
    if not ProfessionsFrame or not ProfessionsFrame:IsShown() then
        return nil, "Select a profession and click Scan recipes."
    end
    if call(api.IsDataSourceChanging) then return nil, "loading" end
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        if call(api[name]) then return nil, "Open your own profession, not a linked, guild, or NPC view." end
    end
    local base = call(api.GetBaseProfessionInfo)
    local child = call(api.GetChildProfessionInfo)
    local children = call(api.GetChildProfessionInfos)
    if not base or not base.professionID or base.professionID == 0 or type(children) ~= "table" then
        return nil, "loading"
    end
    local currentName = LE_EXPANSION_LEVEL_CURRENT and _G["EXPANSION_NAME" .. LE_EXPANSION_LEVEL_CURRENT]
    local expansions = {}
    for _, info in ipairs(children) do
        if info.professionID and info.professionID > 0 then
            expansions[#expansions + 1] = {
                id = info.professionID,
                name = info.expansionName ~= "" and info.expansionName or info.professionName or tostring(info.professionID),
                -- Both labels come from Blizzard in the client's locale. Never guess newest-known = current.
                isCurrent = currentName ~= nil and info.expansionName == currentName,
            }
        end
    end
    if #expansions == 0 then return nil, "No expansion skill lines were exposed for this profession." end
    return {
        baseID = base.professionID, childID = child and child.professionID,
        sourceCounter = base.sourceCounter, name = base.professionName or "Profession",
        currentExpansionName = currentName or "Current expansion", expansions = expansions,
    }
end

function Runtime.Outputs(recipeID)
    local api = C_TradeSkillUI
    local schematic = api.GetRecipeSchematic(recipeID, false)
    if type(schematic) ~= "table" then return nil, "Output schematic unavailable" end
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    -- Quality variants may have distinct names. Keep all IDs; search without tier filters.
    if type(api.GetRecipeQualityItemIDs) ~= "function" then
        return nil, "Recipe quality-output API unavailable"
    end
    for _, id in ipairs(api.GetRecipeQualityItemIDs(recipeID) or {}) do add(id) end
    add(schematic.outputItemID)
    -- Enchants expose no item output; Auctionator ships a recipe-to-scroll table for them.
    local scrolls = Auctionator and Auctionator.CraftingInfo and Auctionator.CraftingInfo.EnchantSpellsToItems
    if #ids == 0 and type(scrolls) == "table" and type(scrolls[recipeID]) == "table" then
        for _, id in ipairs(scrolls[recipeID]) do add(id) end
    end
    if #ids == 0 then
        if type(api.GetRecipeOutputItemData) ~= "function" then return nil, "Recipe output API unavailable" end
        local output = api.GetRecipeOutputItemData(recipeID)
        if type(output) ~= "table" then return nil, "Crafted item data unavailable" end
        add(output.itemID)
        if #ids == 0 and type(output.hyperlink) == "string" then
            add(tonumber(output.hyperlink:match("item:(%d+)")))
        end
    end
    if #ids > 0 then return ids end
    local itemType = Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Item
    if itemType and schematic.recipeType and schematic.recipeType ~= itemType then
        return {}, "No auctionable item output exposed for this recipe type"
    end
    return nil, "Crafted item ID unavailable"
end

function Runtime.Item(id)
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(id)
    if not name then return nil end
    local tier = call(C_TradeSkillUI.GetItemReagentQualityByItemInfo, id)
    if type(tier) ~= "number" or tier < 1 then tier = nil end
    -- GetItemInfo binding categories: pickup, quest, WoW account, Battle.net account.
    local blocked = ({ [1] = "Binds on pickup", [4] = "Quest item", [7] = "Account-bound", [8] = "Account-bound" })[bindType]
    return { name = name, tier = tier, bindType = bindType, blocked = blocked }
end

function Runtime.Environment()
    return {
        context = Runtime.Context,
        after = function(delay, callback) C_Timer.After(delay, callback) end,
        now = function() return (GetTimePreciseSec or GetTime)() end,
        recipes = function() return C_TradeSkillUI.GetAllRecipeIDs() end,
        recipe = function(id) return C_TradeSkillUI.GetRecipeInfo(id) end,
        matches = function(id, skillLineID) return C_TradeSkillUI.IsRecipeInSkillLine(id, skillLineID) end,
        schematic = function(id) return C_TradeSkillUI.GetRecipeSchematic(id, false) end,
        outputs = Runtime.Outputs,
        item = Runtime.Item,
        requestItem = function(id) C_Item.RequestLoadItemDataByID(id) end,
    }
end

function Runtime.AuctionatorAPI()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- Read-only compatibility bridge, corroborated by CraftSim's shopping integration.
-- Auctionator's public missing-list read contract is not established. Never infer
-- absence from a GetShoppingListItems error or nil result.
function Runtime.AuctionatorListExists(name)
    local manager = Auctionator and Auctionator.Shopping and Auctionator.Shopping.ListManager
    if not manager or type(manager.GetIndexForName) ~= "function" then return nil end
    local ok, index = pcall(manager.GetIndexForName, manager, name)
    if not ok then return nil end
    if index == nil then return false end
    if type(index) == "number" and index >= 1 and index % 1 == 0 then return true end
    return nil
end

function Runtime.Character()
    return {
        guid = UnitGUID and UnitGUID("player"),
        name = UnitName("player"),
        realm = (GetRealmName or GetNormalizedRealmName)(),
    }
end

function Runtime.Diagnostics()
    local api = Runtime.AuctionatorAPI() or {}
    local version, build, _, interface = GetBuildInfo()
    local context, reason = Runtime.Context()
    local lines = {
        G.TITLE .. " " .. G.VERSION,
        string.format("WoW %s; build %s; interface %s", version, build, interface),
        "Auctionator: " .. tostring(C_AddOns.GetAddOnMetadata("Auctionator", "Version") or "not installed"),
        "CreateShoppingList: " .. type(api.CreateShoppingList),
        "ConvertToSearchString: " .. type(api.ConvertToSearchString),
        "GetShoppingListItems: " .. type(api.GetShoppingListItems),
        "List existence check: " .. type(Auctionator and Auctionator.Shopping
            and Auctionator.Shopping.ListManager and Auctionator.Shopping.ListManager.GetIndexForName),
        "Client expansion: " .. tostring(LE_EXPANSION_LEVEL_CURRENT),
        "OpenTradeSkill: " .. type(C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill),
    }
    local professions, detectionError = Runtime.Professions()
    for _, profession in ipairs(professions) do
        lines[#lines + 1] = string.format("Detected profession: %s (%d)", profession.name, profession.id)
    end
    if detectionError then lines[#lines + 1] = detectionError end
    if context then
        lines[#lines + 1] = string.format("Profession %s (%s); displayed skill line %s; source %s",
            context.name, context.baseID, tostring(context.childID), tostring(context.sourceCounter))
        for _, expansion in ipairs(context.expansions) do
            lines[#lines + 1] = string.format("Skill line %d: %s%s", expansion.id, expansion.name,
                expansion.isCurrent and " [current]" or "")
        end
    else lines[#lines + 1] = reason end
    return table.concat(lines, "\n")
end
