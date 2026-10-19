local _, G = ...

G.VERSION = "1.0.0"
G.TITLE = "Gorloc CraftScan"
G.CALLER = "GorlocCraftScan"

function G.Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function G.CopySelection(selection)
    local copy = {}
    for id, selected in pairs(selection) do
        if selected then copy[id] = true end
    end
    return copy
end

function G.HasSelection(selection)
    return next(selection) ~= nil
end

function G.SameContext(a, b)
    return a and b and a.baseID == b.baseID and a.childID == b.childID
        and a.sourceCounter == b.sourceCounter
end

function G.ScopeLabel(context, selected)
    local names = {}
    for _, expansion in ipairs(context.expansions) do
        if selected[expansion.id] then names[#names + 1] = expansion.name end
    end
    if #names == 0 then return "No expansions" end
    return table.concat(names, ", ")
end

function G.DefaultSelection(context)
    local selected = {}
    for _, expansion in ipairs(context.expansions) do
        if expansion.isCurrent then selected[expansion.id] = true end
    end
    return selected
end
