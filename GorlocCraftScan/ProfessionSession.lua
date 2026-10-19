local _, G = ...
local Session = {}
Session.__index = Session
G.ProfessionSession = Session

function Session.New(env)
    return setmetatable({ env = env, generation = 0 }, Session)
end

function Session:Finish()
    self.generation = self.generation + 1
    local owned = self.ownedContext
    self.waiting, self.active, self.ownedContext = false, false, nil
    -- Release ownership before closing: CloseTradeSkill can synchronously fire events.
    if owned then
        local current = self.env.snapshot()
        if current and current.isLocal and not current.isChanging and G.SameContext(owned, current) then
            if self.env.inCombat() then return "Profession left open because combat started." end
            local ok, closed = pcall(self.env.close)
            if not ok or closed == false then return "Profession left open; close it manually when ready." end
        end
    end
end

function Session:Start(professionID, callbacks)
    self:Finish()
    if self.env.inCombat() then callbacks.error("Leave combat before scanning professions."); return end
    local env, token = self.env, self.generation
    local before = env.snapshot()
    local context = env.context()
    self.active, self.waiting = true, true
    local function fail(message)
        local note = self:Finish()
        callbacks.error(message .. (note and (" " .. note) or ""))
    end
    local function ready(value)
        self.waiting = false
        if not before then self.ownedContext = value end
        callbacks.ready(value)
    end
    if context and context.baseID == professionID then ready(context); return end
    if before and not before.isLocal then
        fail("Close the linked, guild, or NPC profession view before scanning your profession.")
        return
    end
    self.opening = true
    local ok, opened, reason = pcall(env.open, professionID)
    self.opening = false
    if not ok or not opened then
        fail(ok and (reason or "WoW could not open this profession. Open it manually and try again.")
            or ("Could not open profession: " .. tostring(opened)))
        return
    end
    local started = env.now()
    local function poll()
        if self.generation ~= token or not self.waiting then return end
        local snapshot = env.snapshot()
        if snapshot and snapshot.isLocal and snapshot.baseID == professionID then
            if not snapshot.isChanging and self.ownedContext
                and snapshot.sourceCounter ~= self.ownedContext.sourceCounter then
                fail("The profession session changed while opening. Scan again when ready.")
                return
            end
            if not before and not snapshot.isChanging and not self.ownedContext then self.ownedContext = snapshot end
        elseif snapshot and snapshot.baseID and snapshot.baseID > 0
            and (not before or snapshot.baseID ~= before.baseID) then
            fail("The profession changed while opening. Choose a profession and scan again.")
            return
        end
        if env.inCombat() then fail("Scan canceled because combat started."); return end
        local current, message = env.context()
        if current and current.baseID == professionID then ready(current); return end
        if snapshot and snapshot.baseID == professionID and message ~= "loading" then
            fail(message or "Profession data is unavailable."); return
        end
        if env.now() - started >= 10 then
            fail("Profession data did not become ready. Open it manually and try again."); return
        end
        env.after(0.1, poll)
    end
    poll()
end
