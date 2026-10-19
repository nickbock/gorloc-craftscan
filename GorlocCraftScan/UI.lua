local _, G = ...
local UI = { tab = "sync" }
G.UI = UI

local function place(widget, x, y, width, height)
    widget:SetPoint("TOPLEFT", x, -y)
    widget:SetSize(width, height)
end

local function label(parent, text, x, y, width, height, font)
    local widget = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    widget:SetJustifyH("LEFT"); widget:SetJustifyV("TOP")
    widget:SetText(text); place(widget, x, y, width, height)
    return widget
end

-- Character history table: column widths sum to the 470px scroll area.
local HISTORY_ROW, HISTORY_HEIGHT, HISTORY_POOL = 22, 286, 14
local HISTORY_COLUMNS = {
    { key = "character", title = "Character", width = 135 },
    { key = "profession", title = "Profession", width = 85 },
    { key = "scope", title = "Scope", width = 100 },
    { key = "status", title = "Status", width = 70 },
    { key = "lastSync", title = "Last sync", width = 80 },
}
local STATUS_COLORS = { complete = { 0.4, 1, 0.4 }, partial = { 1, 0.65, 0.2 }, failed = { 1, 0.3, 0.3 } }

local function columnLabels(parent, x, y, font)
    local labels = {}
    for _, column in ipairs(HISTORY_COLUMNS) do
        labels[column.key] = label(parent, column.title, x, y, column.width - 8, 16, font)
        labels[column.key]:SetWordWrap(false)
        x = x + column.width
    end
    return labels
end

local function button(parent, text, x, y, width, callback)
    local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    place(widget, x, y, width, 26); widget:SetText(text); widget:SetScript("OnClick", callback)
    return widget
end

local function dropdown(parent, y, default, generator)
    local widget = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    place(widget, 158, y, 336, 28)
    widget:SetDefaultText(default); widget:SetupMenu(generator)
    return widget
end

function UI:SavePosition()
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    GorlocCraftScanDB.window = { point = point, relativePoint = relativePoint, x = x, y = y }
end

function UI:FitWindow()
    -- 520 covers the 482px frame plus the tabs hanging below it.
    self.frame:SetScale(math.min(1, (UIParent:GetWidth() - 32) / 540, (UIParent:GetHeight() - 40) / 520))
end

function UI:SetTab(tab)
    self.tab = tab
    self:Refresh()
end

-- Used only for actionable failures and the /gcs debug command.
function UI:ShowText(title, text)
    if not self.dialog then
        local dialog = CreateFrame("Frame", nil, self.frame, "BasicFrameTemplateWithInset")
        self.dialog = dialog
        dialog:SetSize(500, 420); dialog:SetPoint("CENTER"); dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:EnableMouse(true)
        dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        place(scroll, 18, 42, 444, 350); dialog.scroll = scroll
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(434); edit:SetHeight(350); edit:SetMaxLetters(0)
        dialog.edit = edit; scroll:SetScrollChild(edit)
        local measure = label(dialog, "", 0, 0, 434, 1, "ChatFontNormal")
        measure:SetHeight(0); measure:Hide()
        edit:SetScript("OnTextChanged", function(self)
            measure:SetText(self:GetText()); self:SetHeight(math.max(350, measure:GetStringHeight() + 20))
        end)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); dialog:Hide() end)
        dialog:SetScript("OnHide", function() edit:ClearFocus() end)
    end
    self.dialog.TitleText:SetText(title)
    self.dialog.edit:SetText(text); self.dialog.edit:SetCursorPosition(0)
    self.dialog.scroll:SetVerticalScroll(0); self.dialog:Show(); self.dialog.edit:SetFocus()
end

function UI:ShowProblems()
    local lines = { G.status or "", "" }
    for _, issue in ipairs(G.result and G.result.issues or {}) do
        lines[#lines + 1] = "Recipe " .. tostring(issue.recipeID or "unknown") .. ": " .. issue.message
    end
    for _, outcome in ipairs(G.syncOutcomes or {}) do
        lines[#lines + 1] = outcome.name .. ": " .. outcome.status .. (outcome.message and (" — " .. outcome.message) or "")
    end
    self:ShowText("Sync details", table.concat(lines, "\n"))
end

function UI:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "GorlocCraftScanFrame", UIParent, "BasicFrameTemplateWithInset")
    self.frame = frame
    frame:SetSize(540, 482); frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true)
    frame:EnableMouse(true); frame:SetMovable(true)
    frame.TitleText:SetText(G.TITLE)
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    local saved = type(GorlocCraftScanDB.window) == "table" and GorlocCraftScanDB.window or {}
    local valid = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
        RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
    local function offset(value) return type(value) == "number" and value == value and math.max(-400, math.min(400, value)) or 0 end
    frame:SetPoint(valid[saved.point] and saved.point or "CENTER", UIParent,
        valid[saved.relativePoint] and saved.relativePoint or "CENTER", offset(saved.x), offset(saved.y))
    self:FitWindow()
    self.drag = CreateFrame("Frame", nil, frame)
    place(self.drag, 4, 0, 504, 24); self.drag:EnableMouse(true); self.drag:RegisterForDrag("LeftButton")
    self.drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    self.drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); self:SavePosition() end)
    tinsert(UISpecialFrames, "GorlocCraftScanFrame")
    -- Blizzard-style bottom tabs; PanelTabButtonTemplate registers each in frame.Tabs.
    self.syncTab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    self.syncTab:SetText("Sync"); self.syncTab:SetScript("OnClick", function() self:SetTab("sync") end)
    self.syncTab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    self.charactersTab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    self.charactersTab:SetText("Characters"); self.charactersTab:SetScript("OnClick", function() self:SetTab("characters") end)
    PanelTemplates_SetNumTabs(frame, 2)
    self.syncPanel = CreateFrame("Frame", nil, frame); place(self.syncPanel, 0, 34, 540, 436)
    local panel = self.syncPanel
    label(panel, "Profession", 24, 10, 126, 22, "GameFontNormal")
    self.profession = dropdown(panel, 2, "Select a profession", function(_, root)
        for _, profession in ipairs(G.professions) do
            root:CreateRadio(profession.name, function(id) return G.selectedProfession == id end,
                function(id) if not G.IsBusy() then G.SelectProfession(id) end end, profession.id)
        end
    end)
    label(panel, "Recipes", 24, 54, 126, 22, "GameFontNormal")
    self.recipeScope = dropdown(panel, 46, "Known recipes", function(_, root)
        for _, option in ipairs({ { false, "Known recipes" }, { true, "All exposed recipes" } }) do
            root:CreateRadio(option[2], function(all) return G.includeUnlearned == all end, function(all)
                if G.IsBusy() or G.includeUnlearned == all then return end
                G.includeUnlearned = all; G.Invalidate("Recipe scope changed. Ready to scan and sync.")
            end, option[1])
        end
    end)
    label(panel, "Expansions", 24, 98, 126, 22, "GameFontNormal")
    self.expansions = dropdown(panel, 90, "Current expansion", function(_, root)
        if not G.context then root:CreateTitle("First sync uses the current expansion."); return end
        root:CreateButton("Current expansion", function() if not G.IsBusy() then G.SelectExpansions("current") end end)
        root:CreateButton("All expansions", function() if not G.IsBusy() then G.SelectExpansions("all") end end)
        root:CreateDivider()
        for _, expansion in ipairs(G.context.expansions) do
            root:CreateCheckbox(expansion.name .. (expansion.isCurrent and " (current)" or ""),
                function(id) return G.selection[id] == true end, function(id)
                    if G.IsBusy() then return end
                    G.selection[id] = not G.selection[id] or nil
                    G.Invalidate("Expansion selection changed. Ready to scan and sync.")
                end, expansion.id)
        end
    end)
    self.expansions:SetSelectionText(function()
        if not G.context then return "Current expansion" end
        local count = 0; for _ in pairs(G.selection) do count = count + 1 end
        if count == 0 then return "Select at least one expansion" end
        if count == 1 then return G.ScopeLabel(G.context, G.selection) end
        return count .. " expansions selected"
    end)
    self.hint = label(panel, "", 24, 128, 470, 38, "GameFontHighlightSmall")
    label(panel, "Shopping lists", 24, 182, 130, 22, "GameFontNormal")
    self.listMode = dropdown(panel, 174, "Combined", function(_, root)
        root:CreateRadio("Combined", function() return G.listMode == "combined" end, function() G.SetListMode("combined") end)
        root:CreateRadio("Separate materials and items", function() return G.listMode == "split" end, function() G.SetListMode("split") end)
    end)
    self.destinations = label(panel, "", 24, 214, 470, 40)
    label(panel, "Adds missing searches and keeps existing entries.\nAll qualities are included.", 24, 264, 470, 36, "GameFontHighlightSmall")
    self.status = label(panel, "", 24, 310, 470, 70)
    self.details = button(panel, "Details", 24, 382, 88, function() self:ShowProblems() end)
    self.partial = button(panel, "Sync available items", 24, 410, 196, function() G.ConfirmPartialSync() end)
    self.action = button(panel, "Scan & Sync", 274, 410, 220, function() G.PrimaryAction() end)
    self.cancel = button(panel, "Cancel", 274, 410, 220, function() G.CancelScan() end)
    self.charactersPanel = CreateFrame("Frame", nil, frame); place(self.charactersPanel, 0, 34, 540, 436)
    label(self.charactersPanel, "Synced characters and professions", 24, 8, 470, 24, "GameFontNormal")
    label(self.charactersPanel, "Offline characters are not scanned automatically. Log in and scan each one to update it.", 24, 38, 470, 38, "GameFontHighlightSmall")
    columnLabels(self.charactersPanel, 30, 82, "GameFontNormalSmall")
    local divider = self.charactersPanel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 0.82, 0, 0.4); place(divider, 24, 100, 470, 1)
    self.historyScroll = CreateFrame("ScrollFrame", nil, self.charactersPanel, "UIPanelScrollFrameTemplate")
    place(self.historyScroll, 24, 104, 470, HISTORY_HEIGHT)
    self.historyContent = CreateFrame("Frame", nil, self.historyScroll)
    self.historyContent:SetSize(470, 1); self.historyScroll:SetScrollChild(self.historyContent)
    self.historyPool, self.historyRows = {}, {}
    self.historyScroll:HookScript("OnVerticalScroll", function() self:RenderHistory() end)
    self.historyScroll:EnableMouseWheel(true)
    self.historyScroll:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, #self.historyRows * HISTORY_ROW - HISTORY_HEIGHT)
        local step = delta * 3 * HISTORY_ROW
        self.historyScroll:SetVerticalScroll(math.max(0, math.min(maximum, self.historyScroll:GetVerticalScroll() - step)))
    end)
    self.historyEmpty = label(self.charactersPanel, "No scans recorded yet. Scan and sync a profession to get started.", 30, 110, 450, 60)
    self.historyHint = label(self.charactersPanel, "Sync times indicate list updates, not AH price freshness.", 24, 406, 470, 28, "GameFontHighlightSmall")
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing(); self:SavePosition()
        if self.dialog then self.dialog:Hide() end
        if G.IsBusy() then G.CancelScan() end
    end)
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED"); frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:SetScript("OnEvent", function() self:FitWindow() end)
    frame:Hide()
end

function UI:RenderHistory()
    local first = math.floor(self.historyScroll:GetVerticalScroll() / HISTORY_ROW) + 1
    for i = 1, HISTORY_POOL do
        local index = first + i - 1
        local data, row = self.historyRows[index], self.historyPool[i]
        if data and not row then
            row = CreateFrame("Frame", nil, self.historyContent)
            row:SetSize(470, HISTORY_ROW)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints(); row.stripe:SetColorTexture(1, 1, 1, 0.05)
            row.columns = columnLabels(row, 6, 4, "GameFontHighlightSmall")
            self.historyPool[i] = row
        end
        if row then
            row:SetShown(data ~= nil)
            if data then
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(index - 1) * HISTORY_ROW)
                for _, column in ipairs(HISTORY_COLUMNS) do row.columns[column.key]:SetText(data[column.key]) end
                row.columns.status:SetTextColor(unpack(STATUS_COLORS[data.state]))
                row.stripe:SetShown(index % 2 == 0)
            end
        end
    end
end

function UI:Refresh()
    if not self.frame then return end
    local busy = G.IsBusy()
    self.syncPanel:SetShown(self.tab == "sync"); self.charactersPanel:SetShown(self.tab == "characters")
    PanelTemplates_SetTab(self.frame, self.tab == "sync" and 1 or 2)
    for _, widget in ipairs({ self.profession, self.recipeScope, self.expansions, self.listMode }) do
        widget:SetEnabled(not busy); widget:GenerateMenu()
    end
    self.hint:SetText(not G.context and "First sync uses the current expansion. More expansion choices appear after that scan."
        or (G.includeUnlearned and "Includes unlearned recipes exposed by WoW in the selected expansions." or "Only recipes known by this character are included."))
    local name
    for _, profession in ipairs(G.professions) do if profession.id == G.selectedProfession then name = profession.name end end
    local base = name and ("Gorloc - " .. name)
    self.destinations:SetText(not base and "No crafting professions detected." or (G.listMode == "split"
        and (base .. " - Materials\n" .. base .. " - Items") or base))
    local available, why = G.AuctionatorAdapter.Check(G.Runtime.AuctionatorAPI())
    self.status:SetText(not available and why or G.status or "Choose a profession, then Scan & Sync.")
    self.action:SetShown(not busy); self.cancel:SetShown(busy)
    self.action:SetText(G.viewState == "sync-failed" and "Retry sync" or "Scan & Sync")
    self.action:SetEnabled(not busy and not InCombatLockdown() and available and G.selectedProfession ~= nil
        and (not G.context or G.HasSelection(G.selection)))
    self.cancel:SetEnabled(busy)
    self.partial:SetShown(not busy and G.result ~= nil and not G.result.complete and not G.exported and G.viewState == "partial")
    self.partial:SetEnabled(not busy and available and not InCombatLockdown() and G.scanRecord ~= nil
        and G.result ~= nil and #G.result.entries + #G.result.outputs > 0)
    self.details:SetShown(not busy and (G.viewState == "partial" or G.viewState == "sync-failed" or G.viewState == "failed"))
    if self.tab == "characters" then
        self.historyRows = G.UIModel.CharacterRows(GorlocCraftScanDB)
        self.historyContent:SetHeight(math.max(1, #self.historyRows * HISTORY_ROW))
        self.historyEmpty:SetShown(#self.historyRows == 0)
        -- The template only re-evaluates its scrollbar when the range changes, so a short list kept it visible.
        self.historyScroll.ScrollBar:SetShown(#self.historyRows * HISTORY_ROW > HISTORY_HEIGHT)
        self.historyScroll:SetVerticalScroll(math.min(self.historyScroll:GetVerticalScroll(), math.max(0, #self.historyRows * HISTORY_ROW - HISTORY_HEIGHT)))
        self:RenderHistory()
    end
end
