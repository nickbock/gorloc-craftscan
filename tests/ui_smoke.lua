-- Headless integration smoke test. Verifies wiring/state, not actual WoW rendering.
local G, frames, timers, writes, lists = {}, {}, {}, {}, {}
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local methods = {}
local function widget(kind, name, parent)
    local value = setmetatable({ kind = kind, name = name, parent = parent, shown = true,
        enabled = true, scripts = {}, width = 820, height = 660 }, { __index = function(_, key)
        assert(methods[key], "Unknown widget method " .. key)
        return methods[key]
    end })
    if name then _G[name] = value end
    return value
end
for _, key in ipairs({ "SetPoint", "ClearAllPoints", "SetJustifyH", "SetJustifyV", "SetFrameStrata", "SetScale",
    "SetClampedToScreen", "EnableMouse", "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetAutoFocus", "SetFontObject", "SetMultiLine",
    "SetMaxLetters", "SetCursorPosition", "ClearFocus", "SetWordWrap", "SetTextColor",
    "SetResizable", "SetResizeBounds", "StartSizing", "EnableMouseWheel", "SetTexture", "SetFocus",
    "SetHighlightTexture", "SetAllPoints", "SetColorTexture" }) do
    methods[key] = function() end
end
function methods:SetSize(w, h)
    self.width, self.height = w, h
    if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end
end
function methods:SetPoint(point, a, b, c, d)
    self.point = { point, type(a) == "table" and a or self.parent, type(a) == "table" and b or point,
        type(a) == "table" and c or a or 0, type(a) == "table" and d or b or 0 }
end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 }) end
function methods:SetVerticalScroll(value)
    self.offset = value
    if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, value) end
end
function methods:GetVerticalScroll() return rawget(self, "offset") or 0 end
function methods:HookScript(event, fn)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end; fn(...) end
end
function methods:IsEnabled() return self.enabled end
function methods:CreateTexture() return widget("Texture", nil, self) end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetStringHeight()
    assert(self.kind == "FontString", "GetStringHeight is only mocked for FontString")
    return 250
end
function methods:CreateFontString() return widget("FontString", nil, self) end
function methods:SetText(text)
    self.text = text
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function methods:GetText() return rawget(self, "text") or "" end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:SetScrollChild(child) self.child = child end
function methods:SetEnabled(value) self.enabled = value and true or false end
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:Show() self.shown = true end
function methods:Hide()
    local shown = self.shown
    self.shown = false
    if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:RegisterEvent(event)
    self.events = rawget(self, "events") or {}
    self.events[event] = true
end
function CreateFrame(kind, name, parent, template)
    local frame = widget(kind, name, parent)
    frame.template = template
    if template == "BasicFrameTemplateWithInset" then
        frame.TitleText = widget("FontString", nil, frame)
        frame.CloseButton = widget("Button", nil, frame)
    elseif template == "UIPanelScrollFrameTemplate" then
        frame.ScrollBar = widget("Slider", nil, frame)
    elseif template == "PanelTabButtonTemplate" then
        parent.Tabs = rawget(parent, "Tabs") or {}
        parent.Tabs[#parent.Tabs + 1] = frame
    end
    frames[#frames + 1] = frame
    return frame
end
-- Mirrors Blizzard: the selected tab is disabled, the others enabled.
function PanelTemplates_SetNumTabs(frame, count) frame.numTabs = count end
function PanelTemplates_SetTab(frame, id)
    for i = 1, frame.numTabs do frame.Tabs[i]:SetEnabled(i ~= id) end
end
function methods:SetDefaultText(text) self.defaultText = text end
function methods:SetSelectionText(fn) self.selectionText = fn end
function methods:SetupMenu(fn) self.generator = fn; self:GenerateMenu() end
function methods:GenerateMenu()
    local root = { options = {} }
    function root:CreateRadio(text, selected, callback, data)
        self.options[#self.options + 1] = { text = text, selected = selected, callback = callback, data = data }
    end
    root.CreateCheckbox = root.CreateRadio
    function root:CreateButton(text, callback) self.options[#self.options + 1] = { text = text, callback = callback } end
    function root:CreateTitle() end
    function root:CreateDivider() end
    self.generator(self, root); self.options = root.options
end
local function choose(dropdown, text)
    assert(dropdown.enabled, "Dropdown disabled")
    dropdown:GenerateMenu()
    for _, option in ipairs(dropdown.options) do
        if option.text == text then option.callback(option.data); return end
    end
    error("Missing dropdown option: " .. text)
end
local function send(event, ...)
    for _, frame in ipairs(frames) do
        if rawget(frame, "events") and frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
    end
end
local function click(frame)
    assert(frame.enabled, "Clicked disabled button")
    frame.scripts.OnClick(frame)
end
local function drain()
    local max = 2000
    while #timers > 0 do
        max = max - 1; assert(max > 0)
        table.remove(timers, 1)()
    end
end

UIParent = widget("Frame"); UIParent:SetSize(1920, 1080)
ProfessionsFrame = widget("Frame")
ProfessionsFrame.SpecPage = false
UISpecialFrames, SlashCmdList = {}, {}
tinsert = table.insert
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, LE_EXPANSION_LEVEL_CURRENT = 1, 1, 11
EXPANSION_NAME11 = "Midnight"
local displaySkillLine, baseProfession, sourceCounter = 100, 171, 1
local professionNames = { [171] = "Alchemy", [164] = "Blacksmithing", [185] = "Cooking" }
local opened, closed, combat = 0, 0, false
function GetProfessions() return 1, 2, nil, nil, 3 end
function GetProfessionInfo(index)
    local id = ({ 171, 164, 185 })[index]
    return professionNames[id], nil, 1, 100, 1, 0, id
end
C_TradeSkillUI = {
    GetAllRecipeIDs = function() return { 500 } end,
    IsRecipeInSkillLine = function(_, skillLineID) return skillLineID == 200 end,
    GetRecipeInfo = function() return { recipeID = 500, name = "Potion", learned = true } end,
    GetRecipeSchematic = function() return { reagentSlotSchematics = {
        { required = true, quantityRequired = 2, dataSlotIndex = 1, reagents = { { itemID = 600 } } },
    } } end,
    GetBaseProfessionInfo = function() return { professionID = baseProfession, professionName = professionNames[baseProfession], sourceCounter = sourceCounter } end,
    GetChildProfessionInfo = function() return { professionID = displaySkillLine } end,
    GetChildProfessionInfos = function() return {
        { professionID = 100, expansionName = "Dragonflight" },
        { professionID = 200, expansionName = "Midnight" },
    } end,
    GetItemReagentQualityByItemInfo = function() return 2 end,
    GetRecipeQualityItemIDs = function() return { 601, 602 } end,
    OpenTradeSkill = function(id)
        opened = opened + 1; baseProfession = id; sourceCounter = sourceCounter + 1
        ProfessionsFrame:Show(); send("TRADE_SKILL_SHOW")
        return true
    end,
    CloseTradeSkill = function()
        closed = closed + 1; ProfessionsFrame:Hide(); send("TRADE_SKILL_CLOSE")
    end,
}
C_Item = {
    GetItemInfo = function(id) return id == 600 and "Herb" or "Potion", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0 end,
    RequestLoadItemDataByID = function() end,
}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
C_AddOns = { GetAddOnMetadata = function() return "test" end }
function GetTime() return 123.456 end
function InCombatLockdown() return combat end
function GetBuildInfo() return "12.1.5", "12345", "", 120105 end
function UnitName() return "Test" end
function UnitGUID() return "Player-1-Test" end
function GetNormalizedRealmName() return "Realm" end
date, time = os.date, os.time
Auctionator = { API = { v1 = {
    ConvertToSearchString = function(_, item)
        equal(item.tier, ""); equal(item.quality, nil); equal(item.quantity, nil)
        return item.searchString
    end,
    CreateShoppingList = function(_, name, terms)
        writes[#writes + 1] = { name = name, terms = terms }
        lists[name] = lists[name] or {}
        for _, term in ipairs(terms) do
            local found = false
            for _, existing in ipairs(lists[name]) do if term == existing then found = true end end
            if not found then lists[name][#lists[name] + 1] = term end
        end
    end,
    GetShoppingListItems = function(_, name) return lists[name] end,
    DeleteShoppingListItem = function(_, name, term)
        for i = #lists[name], 1, -1 do
            if lists[name][i] == term then table.remove(lists[name], i) end
        end
    end,
} } }

Auctionator.Shopping = { ListManager = { GetIndexForName = function(_, name)
    if lists[name] then return 1 end
end } }

for line in io.lines("GorlocCraftScan/GorlocCraftScan.toc") do
    if line:match("%.lua$") then assert(loadfile("GorlocCraftScan/" .. line))("GorlocCraftScan", G) end
end
send("ADDON_LOADED", "GorlocCraftScan")
SlashCmdList.GORLOCCRAFTSCAN("")
equal(G.UI.frame.template, "BasicFrameTemplateWithInset")
equal(G.UI.profession.template, "WowStyle1DropdownTemplate")
equal(G.UI.frame:GetWidth(), 540); equal(G.UI.frame:GetHeight(), 482)
equal(G.UI.browser, nil); equal(G.UI.debug, nil); equal(G.UI.report, nil)
equal(G.selectedProfession, 171); equal(G.selection[200], true)

-- A single action scans and merges automatically; an existing window remains open.
click(G.UI.action); assert(G.UI.cancel:IsShown()); assert(not G.UI.action:IsShown())
drain(); equal(#writes, 1); equal(G.viewState, "synced"); equal(G.exported, true)
equal(writes[1].name, "Gorloc - Alchemy"); equal(#writes[1].terms, 2)
equal(opened, 0); equal(closed, 0); assert(ProfessionsFrame:IsShown())
assert(G.status:find("Added 2 searches", 1, true)); assert(not G.UI.cancel:IsShown())
local scope = GorlocCraftScanDB.characters['Player-1-Test'].professions[171].scopes['known:200']
assert(scope.lastSyncAt); equal(scope.syncFailed, false)

-- Repeat clicks perform a fresh scan, preserving existing/manual entries.
lists['Gorloc - Alchemy'][3] = "Manual search"
click(G.UI.action); drain(); equal(#writes, 2); equal(#lists['Gorloc - Alchemy'], 3)
assert(G.status:find("Added 0 searches", 1, true))
choose(G.UI.recipeScope, "All exposed recipes"); equal(G.includeUnlearned, true); equal(G.result, nil)
choose(G.UI.expansions, "All expansions"); assert(G.selection[100] and G.selection[200])
choose(G.UI.expansions, "Dragonflight"); equal(G.selection[100], nil)

-- Fixed split names include both categories.
choose(G.UI.listMode, "Separate materials and items"); equal(G.result, nil)
click(G.UI.action); drain(); equal(#writes, 4)
equal(writes[3].name, "Gorloc - Alchemy - Materials"); equal(writes[4].name, "Gorloc - Alchemy - Items")
equal(G.UI.destinations:GetText(), "Gorloc - Alchemy - Materials\nGorloc - Alchemy - Items")

-- Cold selection opens the chosen profession and closes only the owned window.
ProfessionsFrame:Hide(); choose(G.UI.profession, "Cooking")
equal(G.context, nil); assert(G.UI.action.enabled)
local before = #writes
click(G.UI.action); drain(); equal(opened, 1); equal(closed, 1); equal(#writes, before + 2)
equal(G.result.context.baseID, 185); assert(not ProfessionsFrame:IsShown())
choose(G.UI.expansions, "All expansions"); click(G.UI.action); drain()
assert(G.selection[100] and G.selection[200]); equal(opened, 2); equal(closed, 2)

-- Partial reads do not write until the dedicated confirmation action is clicked.
local outputReader = G.scanner.env.outputs
G.scanner.env.outputs = function() return nil, "Output data unavailable" end
before = #writes
click(G.UI.action); drain(); equal(G.viewState, "partial"); equal(#writes, before)
assert(G.UI.partial:IsShown()); assert(G.UI.details:IsShown())
click(G.UI.details); assert(G.UI.dialog.edit:GetText():find("Output data unavailable", 1, true))
G.UI.dialog.edit.scripts.OnEscapePressed(G.UI.dialog.edit); assert(G.UI.frame:IsShown())
click(G.UI.partial); equal(#writes, before + 1); equal(G.viewState, "synced")
assert(not G.UI.partial:IsShown())
G.scanner.env.outputs = outputReader

-- A changed scope discards the pending partial result and its confirmation.
G.scanner.env.outputs = function() return nil, "Unavailable" end
click(G.UI.action); drain(); equal(G.viewState, "partial")
choose(G.UI.recipeScope, "Known recipes"); before = #writes
G.ConfirmPartialSync(); equal(#writes, before); equal(G.result, nil)
G.scanner.env.outputs = outputReader

-- A failed Items write preserves Materials success; retry does not rescan.
local create = Auctionator.API.v1.CreateShoppingList
Auctionator.API.v1.CreateShoppingList = function(caller, name, terms)
    if name:find("Items", 1, true) then return false end
    return create(caller, name, terms)
end
click(G.UI.action); drain(); equal(G.viewState, "sync-failed")
equal(G.syncOutcomes[1].status, "verified"); equal(G.syncOutcomes[2].status, "failed")
equal(G.UI.action:GetText(), "Retry sync")
local previousResult, previousOpens = G.result, opened
Auctionator.API.v1.CreateShoppingList = create
click(G.UI.action); equal(G.result, previousResult); equal(opened, previousOpens); equal(G.viewState, "synced")

-- Empty scans never mutate a list; missing Auctionator blocks opening/scanning.
local recipes = G.scanner.env.recipes
G.scanner.env.recipes = function() return {} end
before = #writes; click(G.UI.action); drain(); equal(#writes, before)
assert(G.status:find("No resolved", 1, true)); G.scanner.env.recipes = recipes
click(G.UI.action); drain(); equal(G.viewState, "synced") -- Empty results must allow a fresh scan.
local api = Auctionator.API.v1
Auctionator.API.v1 = nil; G.UI:Refresh(); assert(not G.UI.action.enabled)
previousOpens = opened; G.StartScan(); equal(opened, previousOpens)
Auctionator.API.v1 = api; G.UI:Refresh()

-- Cancel, window close, combat, and manual changes cannot trigger automatic export.
G.Invalidate("Ready")
before = #writes; click(G.UI.action); click(G.UI.cancel); drain()
equal(#writes, before); equal(G.result, nil); equal(G.IsBusy(), false)
click(G.UI.action); G.UI.frame:Hide(); drain(); equal(#writes, before); equal(G.result, nil)
SlashCmdList.GORLOCCRAFTSCAN("")
click(G.UI.action); combat = true; send("PLAYER_REGEN_DISABLED"); drain()
equal(#writes, before); equal(G.result, nil)
local closedInCombat = closed
combat = false; send("PLAYER_REGEN_ENABLED"); equal(closed, closedInCombat)
click(G.UI.action); baseProfession = 164; sourceCounter = sourceCounter + 1
send("TRADE_SKILL_SHOW"); drain(); equal(#writes, before); equal(G.result, nil)
assert(ProfessionsFrame:IsShown()); equal(G.viewState, "failed")

-- Cold profession UI initialization remains supported.
local originalFrame, originalOpen = ProfessionsFrame, C_TradeSkillUI.OpenTradeSkill
ProfessionsFrame = nil
C_TradeSkillUI.OpenTradeSkill = function(id) ProfessionsFrame = originalFrame; return originalOpen(id) end
click(G.UI.action); drain(); equal(G.viewState, "synced"); assert(not ProfessionsFrame:IsShown())
C_TradeSkillUI.OpenTradeSkill = originalOpen

-- History remains accessible without altering the scan or current selections.
previousResult = G.result
assert(not G.UI.syncTab:IsEnabled())
click(G.UI.charactersTab); equal(G.UI.tab, "characters"); assert(#G.UI.historyRows > 0)
assert(G.UI.syncTab:IsEnabled()); assert(not G.UI.charactersTab:IsEnabled())
assert(not G.UI.historyScroll.ScrollBar:IsShown())
equal(G.UI.historyPool[1].columns.profession:GetText(), "Alchemy"); equal(G.result, previousResult)
SlashCmdList.GORLOCCRAFTSCAN("history"); equal(G.UI.tab, "characters")
SlashCmdList.GORLOCCRAFTSCAN("debug"); assert(G.UI.dialog.edit:GetText():find("CreateShoppingList", 1, true))
G.UI.dialog:Hide(); click(G.UI.syncTab); equal(G.UI.tab, "sync")

-- Character history uses a bounded row pool even with many recorded scopes.
local history = G.UIModel.CharacterRows
G.UIModel.CharacterRows = function()
    local rows = {}; for i = 1, 300 do rows[i] = { character = "Character " .. i, profession = "Alchemy", state = "complete" } end
    return rows
end
click(G.UI.charactersTab); equal(#G.UI.historyPool, 14); assert(G.UI.historyScroll.ScrollBar:IsShown())
G.UI.historyScroll:SetVerticalScroll(290 * 22); equal(G.UI.historyPool[1].columns.character:GetText(), "Character 291")
G.UIModel.CharacterRows = history; G.UI:Refresh()

G.UI:SavePosition(); assert(GorlocCraftScanDB.window.point)
UIParent:SetSize(1280, 720); G.UI:FitWindow(); equal(G.UI.frame:GetWidth(), 540)
print("PASS minimal Blizzard UI: auto sync, dropdowns, confirmation, retries, history, cancellation and lifecycle")
