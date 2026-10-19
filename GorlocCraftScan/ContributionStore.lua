local _, G = ...
local Store = {}
G.ContributionStore = Store

-- Account-wide history keeps only what the Characters tab shows, per character, profession and scan scope.
local function slimScope(scope)
    local scan, lastSyncAt, syncFailed = scope.latestScan, nil, false
    for _, history in pairs(scope.destinations) do
        if history.lastVerified then lastSyncAt = math.max(lastSyncAt or 0, history.lastVerified.at) end
        if history.lastAttempt.status == "failed" then syncFailed = true end
    end
    return { scopeLabel = scan.scopeLabel, includeUnlearned = scan.includeUnlearned, complete = scan.complete,
        lastSyncAt = lastSyncAt, syncFailed = syncFailed }
end

function Store.Initialize(db)
    if type(db.characters) ~= "table" then db.characters = {} end
    if db.schemaVersion == 4 then
        -- v4 also kept item IDs, search terms and attribution for a list-rebuild feature that was dropped.
        for _, character in pairs(db.characters) do
            for _, profession in pairs(character.professions) do
                for key, scope in pairs(profession.scopes) do profession.scopes[key] = slimScope(scope) end
            end
        end
    end
    db.destinations, db.listNames, db.lastExport, db.exportSequence = nil, nil, nil, nil
    db.schemaVersion = 5
    return db
end

function Store.ScopeKey(result)
    local expansions = {}
    for id, selected in pairs(result.selection) do
        if selected then expansions[#expansions + 1] = id end
    end
    table.sort(expansions)
    return (result.includeUnlearned and "all:" or "known:") .. table.concat(expansions, ",")
end

function Store.RecordScan(db, character, result)
    if not character or type(character.guid) ~= "string" or character.guid == "" then
        return nil, "Character identity is unavailable. Scan again after login before syncing."
    end
    local player = db.characters[character.guid] or { professions = {} }
    db.characters[character.guid] = player
    player.name, player.realm = character.name, character.realm
    local professionID = result.context.baseID
    local profession = player.professions[professionID] or { scopes = {} }
    player.professions[professionID] = profession
    profession.name = result.context.name
    local key = Store.ScopeKey(result)
    local scope = profession.scopes[key] or {}
    profession.scopes[key] = scope
    scope.scopeLabel = G.ScopeLabel(result.context, result.selection)
    scope.includeUnlearned = result.includeUnlearned == true
    scope.complete = result.complete == true
    return { guid = character.guid, professionID = professionID, scopeKey = key }
end

-- Status reflects the latest sync; the sync time only advances for verified destinations.
function Store.RecordSync(db, ticket, outcomes, at)
    if not ticket then return end
    local scope = db.characters[ticket.guid].professions[ticket.professionID].scopes[ticket.scopeKey]
    scope.syncFailed = false
    for _, outcome in ipairs(outcomes or {}) do
        if outcome.status == "verified" then scope.lastSyncAt = at end
        if outcome.status == "failed" then scope.syncFailed = true end
    end
end
