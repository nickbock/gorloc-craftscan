local _, G = ...
G.selection = {}
G.includeUnlearned = false
G.listMode = "combined"
G.scanner = G.Scanner.New(G.Runtime.Environment())
G.session = G.ProfessionSession.New(G.Runtime.SessionEnvironment())
G.professions = {}

function G.IsBusy()
    return G.scanner.running or G.session.waiting
end

local function status(message, progress)
    G.status = message
    if progress then G.progress, G.viewState = progress, "scanning" end
    G.UI:Refresh()
end

local function log(message)
    print("|cff55c8bcGorloc CraftScan:|r " .. message)
end

function G.Invalidate(message)
    G.scanner:Cancel()
    local note = G.session:Finish()
    G.result, G.allowPartial, G.exported, G.scanRecord = nil, false, false, nil
    G.syncOutcomes, G.progress, G.viewState, G.cleanupNote = nil, nil, "idle", nil
    status(message .. (note and (" " .. note) or ""))
end

function G.SetListMode(mode)
    if G.IsBusy() or mode == G.listMode or (mode ~= "combined" and mode ~= "split") then return end
    G.listMode, G.exported, G.syncOutcomes = mode, false, nil
    G.Invalidate("List layout changed. Ready to scan and sync.")
    GorlocCraftScanDB.listMode = mode
    status(mode == "split" and "Separate Materials and Items lists selected. Sync adds missing searches and keeps existing ones."
        or "One combined list selected. Sync adds missing searches and keeps existing ones.")
end

local function adoptContext(context)
    local previous = G.context
    G.context = context
    if not previous or previous.baseID ~= context.baseID then
        G.selection = G.DefaultSelection(context)
    else
        local valid = {}
        for _, expansion in ipairs(context.expansions) do
            if G.selection[expansion.id] then valid[expansion.id] = true end
        end
        G.selection = valid
    end
end

function G.SelectProfession(id)
    if G.IsBusy() then return end
    for _, profession in ipairs(G.professions) do
        if profession.id == id then
            if G.selectedProfession ~= id then
                G.Invalidate("Profession selected. Ready to scan and sync.")
                G.selectedProfession, G.context, G.selection = id, nil, {}
            end
            local context = G.Runtime.Context()
            if context and context.baseID == id then adoptContext(context) end
            G.UI:Refresh()
            return
        end
    end
end

function G.RefreshProfessions(preferOpen)
    local professions, reason = G.Runtime.Professions()
    G.professions = professions
    local available = {}
    for _, profession in ipairs(professions) do available[profession.id] = true end
    if G.IsBusy() then
        if not available[G.selectedProfession] then G.Invalidate("Selected profession is no longer available.")
        else G.UI:Refresh(); return end
    end
    local current = G.Runtime.Context()
    local selected = G.selectedProfession
    if preferOpen and current and available[current.baseID] then selected = current.baseID end
    if not available[selected] then selected = professions[1] and professions[1].id end
    if selected then G.SelectProfession(selected)
    else
        G.selectedProfession, G.context, G.selection = nil, nil, {}
        G.Invalidate(reason or "No crafting professions detected. Learn a crafting profession or Cooking, then reopen CraftScan.")
    end
    G.UI:Refresh()
end

function G.ReadProfession()
    if G.IsBusy() then return end
    G.Invalidate("Refreshing professions...")
    G.RefreshProfessions(true)
    if G.selectedProfession then
        status(G.context and "Choose expansions and scan recipes."
            or "Choose a profession and scan. Its window will open and close automatically.")
    end
end

function G.SelectExpansions(mode)
    G.selection = {}
    if G.context then
        for _, expansion in ipairs(G.context.expansions) do
            if mode == "all" or expansion.isCurrent then G.selection[expansion.id] = true end
        end
    end
    G.Invalidate(G.HasSelection(G.selection) and "Expansion selection changed. Scan and sync again."
        or "The current expansion is unavailable. Select an expansion explicitly.")
end

function G.StartScan()
    if G.IsBusy() then return end
    local available, why = G.AuctionatorAdapter.Check(G.Runtime.AuctionatorAPI())
    if not available then status(why); return end
    if InCombatLockdown() then status("Leave combat before scanning professions."); return end
    if not G.selectedProfession then status("Select a crafting profession first."); return end
    if G.context and not G.HasSelection(G.selection) then status("Select at least one expansion."); return end
    G.Invalidate("Opening profession and waiting for recipe data...")
    G.viewState = "loading"
    G.session:Start(G.selectedProfession, {
        error = function(message) G.result = nil; G.viewState = "failed"; status(message) end,
        ready = function(context)
            adoptContext(context)
            if not G.HasSelection(G.selection) then
                G.viewState = "failed"
                local note = G.session:Finish()
                status(context.currentExpansionName .. " is unavailable. Select an expansion, then scan again."
                    .. (note and (" " .. note) or ""))
                return
            end
            G.scanner:Start(context, G.selection, G.includeUnlearned, {
                progress = status,
                error = function(message)
                    local note = G.session:Finish()
                    G.result, G.viewState = nil, "failed"
                    status(message .. (note and (" " .. note) or ""))
                end,
                done = function(result)
                    G.result, G.allowPartial, G.exported = result, false, false
                    local trackingError
                    G.scanRecord, trackingError = G.ContributionStore.RecordScan(
                        GorlocCraftScanDB, G.Runtime.Character(), result)
                    local note = G.session:Finish()
                    G.cleanupNote = note
                    G.viewState = result.complete and "ready" or "partial"
                    local available, why = G.AuctionatorAdapter.Check(G.Runtime.AuctionatorAPI())
                    local message
                    if trackingError then message = trackingError
                    elseif not available then message = why
                    elseif #result.entries + #result.outputs == 0 then message = "No resolved auction-searchable materials or crafted items."
                    elseif not result.complete then message = "Some recipes could not be read. Nothing has been synced. Retry Scan & Sync, or choose Sync available items."
                    else message = "Scan complete. Syncing shopping lists..." end
                    status(message .. (note and (" " .. note) or ""))
                    if result.complete and available and G.scanRecord and #result.entries + #result.outputs > 0 then
                        G.Export()
                    end
                end,
            })
            G.UI:Refresh()
        end,
    })
    G.UI:Refresh()
end

function G.CancelScan()
    G.Invalidate("Scan canceled. No lists were changed.")
end

function G.Export()
    if G.IsBusy() or G.exported then return end
    if InCombatLockdown() then status("Leave combat before syncing."); return end
    if not G.result then status("Scan recipes first."); return end
    if not G.scanRecord then status("Character identity is unavailable. Scan again before syncing."); return end
    local name = "Gorloc - " .. G.result.context.name
    local lists = G.Collector.ExportLists(G.result, name, G.listMode)
    local ok, message, outcomes = G.AuctionatorAdapter.ExportLists(
        G.Runtime.AuctionatorAPI(), lists, G.allowPartial, G.Runtime.AuctionatorListExists)
    G.syncOutcomes = outcomes
    G.viewState = ok and "synced" or "sync-failed"
    G.ContributionStore.RecordSync(GorlocCraftScanDB, G.scanRecord, outcomes, time())
    if ok then
        G.exported = true
        if G.listMode == "split" and #lists < 2 then
            message = message .. " Empty sections were skipped; any existing list for them was left unchanged."
        end
        local summary = G.UIModel.SyncSummary(outcomes)
        if G.listMode == "split" and #lists < 2 then summary = summary .. " Empty sections were skipped." end
        status(summary .. (G.cleanupNote and (" " .. G.cleanupNote) or ""))
    else status(message) end
    G.lastSyncMessage = message
    log(message)
end

function G.PrimaryAction()
    if G.IsBusy() then return end
    if G.result and G.scanRecord and #G.result.entries + #G.result.outputs > 0 and not G.exported
        and (G.viewState == "sync-failed" or G.viewState == "ready") then
        G.Export()
    else G.StartScan() end
end

function G.ConfirmPartialSync()
    if G.IsBusy() or not G.result or G.result.complete or G.exported then return end
    G.allowPartial = true
    G.Export()
end

function G.ShowDiagnostics()
    G.UI:ShowText("Diagnostics", G.Runtime.Diagnostics())
end

function G.Open()
    if InCombatLockdown() then log("Open CraftScan after leaving combat."); return end
    G.UI:Create()
    if G.UI.frame:IsShown() then G.UI.frame:Hide(); return end
    -- Preserve partial results and failed-sync payloads for explicit confirmation/retry.
    G.RefreshProfessions(not G.result)
    G.UI.frame:Show()
    G.UI:Refresh()
end

local function attachButton()
    if not ProfessionsFrame or G.professionButton or InCombatLockdown() then return end
    local widget = CreateFrame("Button", nil, ProfessionsFrame, "UIPanelButtonTemplate")
    widget:SetSize(110, 23)
    widget:SetPoint("TOPRIGHT", ProfessionsFrame, "BOTTOMRIGHT", -8, -3)
    widget:SetText("CraftScan")
    widget:SetScript("OnClick", G.Open)
    G.professionButton = widget
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
events:RegisterEvent("NEW_RECIPE_LEARNED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == G.CALLER then
            if type(GorlocCraftScanDB) ~= "table" then GorlocCraftScanDB = {} end
            G.ContributionStore.Initialize(GorlocCraftScanDB)
            G.listMode = GorlocCraftScanDB.listMode == "split" and "split" or "combined"
            SLASH_GORLOCCRAFTSCAN1 = "/gorloccraftscan"
            SLASH_GORLOCCRAFTSCAN2 = "/gcs"
            SlashCmdList.GORLOCCRAFTSCAN = function(argument)
                local command = G.Trim(argument):lower()
                if command == "history" then
                    if not G.UI.frame or not G.UI.frame:IsShown() then G.Open() end
                    if G.UI.frame then
                        G.UI:SetTab("characters")
                    end
                elseif command == "debug" then
                    if not G.UI.frame or not G.UI.frame:IsShown() then G.Open() end
                    if G.UI.frame then G.ShowDiagnostics() end
                else G.Open() end
            end
        end
        attachButton()
        G.UI:Refresh()
    elseif event == "SKILL_LINES_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        if GorlocCraftScanDB then G.RefreshProfessions(false) end
    elseif event == "TRADE_SKILL_SHOW" or event == "PLAYER_REGEN_ENABLED" then
        attachButton()
        if G.UI.frame and G.UI.frame:IsShown() and not G.IsBusy() then
            local context = G.Runtime.Context()
            if context and not G.SameContext(G.context, context) then G.ReadProfession() end
        end
        G.UI:Refresh()
    elseif event == "TRADE_SKILL_CLOSE" or event == "PLAYER_REGEN_DISABLED" then
        if G.IsBusy() and not (event == "TRADE_SKILL_CLOSE" and G.session.opening) then G.CancelScan() end
        G.UI:Refresh()
    elseif event == "NEW_RECIPE_LEARNED" then
        if G.IsBusy() or G.result then G.Invalidate("Recipe knowledge changed. Scan and sync again.") end
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        if G.UI.frame and G.UI.frame:IsShown() and not G.IsBusy() then
            local context = G.Runtime.Context()
            if context and not G.SameContext(G.context, context) then G.ReadProfession() end
        end
    end
end)
