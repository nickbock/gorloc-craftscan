local _, G = ...
local Model = {}
G.UIModel = Model

local STATUS = { failed = "Sync failed", partial = "Partial", complete = "Complete" }

function Model.CharacterRows(db)
    local rows = {}
    for guid, character in pairs(db.characters or {}) do
        for _, profession in pairs(character.professions) do
            for _, scope in pairs(profession.scopes) do
                local state = scope.syncFailed and "failed" or (scope.complete and "complete" or "partial")
                rows[#rows + 1] = { state = state, status = STATUS[state],
                    character = (character.name or guid) .. "-" .. (character.realm or "Unknown realm"),
                    profession = profession.name,
                    scope = scope.scopeLabel .. " · " .. (scope.includeUnlearned and "All" or "Known"),
                    lastSync = scope.lastSyncAt and date("%d %b %H:%M", scope.lastSyncAt) or "Never" }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.character ~= b.character then return a.character < b.character end
        if a.profession ~= b.profession then return a.profession < b.profession end
        return a.scope < b.scope
    end)
    return rows
end

function Model.SyncSummary(outcomes)
    local added, present, verified = 0, 0, 0
    for _, outcome in ipairs(outcomes or {}) do
        if outcome.status == "verified" then
            added, present, verified = added + outcome.added, present + outcome.present, verified + 1
        end
    end
    return string.format("Added %d searches; %d already present.\nSearch %s in Auctionator to refresh prices.",
        added, present, verified == 1 and "the list" or "the lists")
end
