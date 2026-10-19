local _, G = ...
local Scanner = {}
Scanner.__index = Scanner
G.Scanner = Scanner

function Scanner.New(env)
    return setmetatable({ env = env, generation = 0 }, Scanner)
end

function Scanner:Cancel()
    self.generation = self.generation + 1
    self.running = false
end

function Scanner:Start(context, selection, includeUnlearned, callbacks)
    self:Cancel()
    local token, env = self.generation, self.env
    local result = G.Collector.NewResult(context, selection, includeUnlearned)
    if not G.HasSelection(result.selection) then
        callbacks.error("Select at least one expansion.")
        return
    end
    self.running = true
    local waitingSince
    local function active() return token == self.generation and self.running end
    local function fail(message)
        if active() then self.running = false; callbacks.error(message) end
    end
    local function later(delay, fn)
        env.after(delay, function()
            if active() then
                local ok, err = pcall(fn)
                if not ok then fail("Scan failed: " .. tostring(err)) end
            end
        end)
    end
    local function checkContext(retry)
        local current, message = env.context()
        if not current and message == "loading" then
            waitingSince = waitingSince or env.now()
            if env.now() - waitingSince < 10 then
                callbacks.progress("Waiting for profession data...", { phase = "waiting" })
                later(0.2, retry)
            else fail("Profession data did not become ready. Reopen the profession and try again.") end
            return false
        end
        waitingSince = nil
        if not G.SameContext(context, current) then
            fail("The profession view changed or closed. Scan and sync again.")
            return false
        end
        return true
    end

    local function resolveItems()
        local ids, seen, items = {}, {}, {}
        -- Request each item once; Resolve then groups occurrences with their provenance.
        for _, group in ipairs({ result.entries, result.outputs }) do
            for _, entry in ipairs(group) do
                if not seen[entry.itemID] then
                    seen[entry.itemID] = true
                    ids[#ids + 1] = entry.itemID
                end
            end
        end
        local cursor, pending, pass = 1, {}, 1
        local function step()
            if not checkContext(step) then return end
            local started, count = env.now(), 0
            while cursor <= #ids and count < 40 and env.now() - started < 0.005 do
                local id = ids[cursor]
                local ok, item = pcall(env.item, id)
                if ok and item and item.name then items[id] = item
                else
                    pending[#pending + 1] = id
                    if pass == 1 or pass == 10 then pcall(env.requestItem, id) end
                end
                cursor, count = cursor + 1, count + 1
            end
            callbacks.progress(string.format("Loading item names: %d / %d (attempt %d)",
                cursor - 1, #ids, pass), { phase = "items", current = cursor - 1, total = #ids, attempt = pass })
            if cursor <= #ids then later(0, step)
            elseif #pending > 0 and pass < 20 then
                ids, pending, cursor, pass = pending, {}, 1, pass + 1
                later(0.25, step)
            else
                G.Collector.Resolve(result, items)
                self.running = false
                callbacks.done(result)
            end
        end
        later(0, step)
    end

    local function resolveOutputs()
        local recipes, cursor, pending, pass = result.recipes, 1, {}, 1
        local function step()
            if not checkContext(step) then return end
            local started, count = env.now(), 0
            while cursor <= #recipes and count < 30 and env.now() - started < 0.005 do
                local recipe = recipes[cursor]
                local ok, ids, reason = pcall(env.outputs, recipe.id)
                if ok and type(ids) == "table" then
                    G.Collector.AddOutputs(result, recipe, ids, reason)
                elseif pass < 3 then pending[#pending + 1] = recipe
                else
                    G.Collector.Issue(result, recipe.id, "Crafted output: "
                        .. tostring(ok and reason or ids))
                end
                cursor, count = cursor + 1, count + 1
            end
            callbacks.progress(string.format("Reading crafted items: %d / %d (attempt %d)", cursor - 1, #recipes, pass),
                { phase = "outputs", current = cursor - 1, total = #recipes, attempt = pass })
            if cursor <= #recipes then later(0, step)
            elseif #pending > 0 then
                recipes, cursor, pending, pass = pending, 1, {}, pass + 1
                later(0.25, step)
            else resolveItems() end
        end
        later(0, step)
    end

    local ids, cursor, pending, pass = nil, 1, {}, 1
    local function readRecipe(id)
        local info = env.recipe(id)
        if type(info) ~= "table" or type(info.learned) ~= "boolean" then
            return false, "Recipe metadata unavailable"
        end
        if not includeUnlearned and not info.learned then return true end
        local belongs = false
        for skillLineID in pairs(result.selection) do
            local matches = env.matches(id, skillLineID)
            if matches == nil then return false, "Expansion membership unavailable" end
            if matches then belongs = true; break end
        end
        if not belongs then return true end
        local reason = G.Collector.Exclusion(info)
        if reason then
            result.excluded[#result.excluded + 1] = { name = info.name or tostring(id), reason = reason }
            return true
        end
        local schematic = env.schematic(id)
        if type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then
            return false, "Reagent schematic unavailable"
        end
        -- Some clients omit recipeID on intermediate metadata tables.
        info.recipeID = info.recipeID or id
        -- Commit a recipe atomically. A malformed later slot must not leave earlier
        -- slots/counts behind when the API read is retried.
        local collected = G.Collector.NewResult(context, result.selection, includeUnlearned)
        G.Collector.AddRecipe(collected, info, schematic)
        for _, key in ipairs({ "recipes", "entries", "nonShopping", "issues" }) do
            for _, value in ipairs(collected[key]) do result[key][#result[key] + 1] = value end
        end
        for _, key in ipairs({ "learned", "unlearned", "optionalSlots" }) do
            result[key] = result[key] + collected[key]
        end
        result.complete = result.complete and collected.complete
        return true
    end
    local function step()
        if not checkContext(step) then return end
        if not ids then
            ids = env.recipes()
            if type(ids) ~= "table" then fail("The game did not return a recipe catalog."); return end
        end
        local started, count = env.now(), 0
        while cursor <= #ids and count < 30 and env.now() - started < 0.005 do
            local id = ids[cursor]
            local ok, loaded, reason = pcall(readRecipe, id)
            if not ok or not loaded then
                if pass < 3 then pending[#pending + 1] = id
                else G.Collector.Issue(result, id, ok and reason or ("API error: " .. tostring(loaded))) end
            end
            cursor, count = cursor + 1, count + 1
            if pass == 1 then result.scanned = result.scanned + 1 end
        end
        callbacks.progress(string.format("Reading recipes: %d / %d (attempt %d)", cursor - 1, #ids, pass),
            { phase = "recipes", current = cursor - 1, total = #ids, attempt = pass })
        if cursor <= #ids then later(0, step)
        elseif #pending > 0 then
            ids, pending, cursor, pass = pending, {}, 1, pass + 1
            later(0.25, step)
        else resolveOutputs() end
    end
    later(0, step)
end
