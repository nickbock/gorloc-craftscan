-- Deterministic tests of opening, waiting, ownership and cleanup without a WoW client.
local G = {}
for _, module in ipairs({ "Util", "ProfessionSession" }) do
    assert(loadfile("GorlocCraftScan/" .. module .. ".lua"))("GorlocCraftScan", G)
end
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, fn)
    fn(); passed = passed + 1; print("PASS " .. name)
end
local function context(id, counter)
    return { baseID = id or 171, childID = 200, sourceCounter = counter or 1, isLocal = true }
end
local function fixture()
    local f = { clock = 0, timers = {}, opens = 0, closes = 0, readyCount = 0 }
    f.env = {
        now = function() return f.clock end,
        after = function(delay, fn) f.timers[#f.timers + 1] = { at = f.clock + delay, fn = fn } end,
        context = function() return f.current, f.message or "loading" end,
        snapshot = function() return f.snapshot end,
        inCombat = function() return f.combat or false end,
        open = function(id) f.opens = f.opens + 1; f.requested = id; return true end,
        close = function()
            f.closes = f.closes + 1
            f.current, f.snapshot = nil, nil
            -- Simulate the synchronous close event: cleanup must already be released.
            equal(f.session.active, false); equal(f.session.waiting, false)
            f.session:Finish()
            return true
        end,
    }
    f.session = G.ProfessionSession.New(f.env)
    function f:start(id)
        self.session:Start(id or 171, {
            ready = function(c) self.result = c; self.readyCount = self.readyCount + 1 end,
            error = function(message) self.error = message end,
        })
    end
    function f:tick()
        table.sort(self.timers, function(a, b) return a.at < b.at end)
        local timer = table.remove(self.timers, 1)
        if timer then self.clock = timer.at; timer.fn() end
    end
    function f:drain()
        local limit = 200
        while #self.timers > 0 do
            limit = limit - 1; assert(limit > 0, "Unbounded wait"); self:tick()
        end
    end
    return f
end

test("cold open waits for selected profession and closes its own session", function()
    local f = fixture(); f:start()
    equal(f.opens, 1); equal(f.readyCount, 0)
    f.snapshot = context(); f:tick(); equal(f.readyCount, 0)
    f.current = context(); f:drain(); equal(f.readyCount, 1)
    f.session:Finish(); equal(f.closes, 1)
end)

test("already open matching profession is reused and left open", function()
    local f = fixture(); f.current = context(); f.snapshot = context(); f:start()
    equal(f.readyCount, 1); equal(f.opens, 0)
    f.session:Finish(); equal(f.closes, 0)
end)

test("switching a preexisting profession waits but does not own its window", function()
    local f = fixture(); f.current = context(164); f.snapshot = context(164); f:start()
    f:tick(); equal(f.readyCount, 0)
    f.current, f.snapshot = context(171, 2), context(171, 2)
    f:drain(); equal(f.readyCount, 1)
    f.session:Finish(); equal(f.closes, 0)
end)

test("linked views cannot be reused or replaced automatically", function()
    local f = fixture(); f.snapshot = context(); f.snapshot.isLocal = false
    f:start(); equal(f.opens, 0); equal(f.closes, 0); assert(f.error)
end)

test("rejected and throwing open calls stop immediately", function()
    for _, throws in ipairs({ false, true }) do
        local f = fixture()
        f.env.open = function() if throws then error("Unavailable") end; return false end
        f:start(); assert(f.error); equal(f.session.active, false)
        equal(#f.timers, 0); equal(f.closes, 0)
    end
end)

test("zero profession ID while loading is not mistaken for a manual switch", function()
    local f = fixture(); f.env.open = function() f.snapshot = context(0); return true end
    f:start(); equal(f.error, nil)
    f.current, f.snapshot = context(), context(); f:drain()
    equal(f.readyCount, 1); f.session:Finish(); equal(f.closes, 1)
end)

test("normal loading counter changes are not mistaken for a manual reopen", function()
    local f = fixture(); f:start()
    f.snapshot = context(171, 1); f.snapshot.isChanging = true; f:tick()
    f.snapshot, f.current = context(171, 2), context(171, 2); f:drain()
    equal(f.readyCount, 1); equal(f.error, nil)
    f.session:Finish(); equal(f.closes, 1)
end)

test("timeout closes an identified owned session", function()
    local f = fixture(); f:start(); f.snapshot = context(); f:drain()
    assert(f.error:find("did not become ready", 1, true))
    equal(f.closes, 1); equal(f.readyCount, 0)
end)

test("missing UI times out without guessing which session to close", function()
    local f = fixture(); f:start(); f:drain()
    assert(f.error); equal(f.closes, 0); equal(f.readyCount, 0)
end)

test("cancel invalidates callbacks and closes only identified owned windows", function()
    local f = fixture(); f:start(); f.snapshot = context(); f:tick()
    f.session:Finish(); f.current = context(); f:drain()
    equal(f.readyCount, 0); equal(f.closes, 1)
end)

test("manual switch during loading is not closed", function()
    local f = fixture(); f:start(); f.snapshot = context(); f:tick()
    f.snapshot, f.current = context(164, 2), context(164, 2); f:drain()
    assert(f.error); equal(f.closes, 0); equal(f.readyCount, 0)
end)

test("manually reopened same profession is not adopted or closed", function()
    local f = fixture(); f:start(); f.snapshot = context(); f:tick()
    f.snapshot, f.current = context(171, 2), context(171, 2); f:drain()
    assert(f.error); equal(f.closes, 0); equal(f.readyCount, 0)
end)

test("manual expansion switch during scanning relinquishes cleanup", function()
    local f = fixture(); f:start(); f.snapshot, f.current = context(), context(); f:drain()
    f.snapshot.childID = 999; f.session:Finish(); equal(f.closes, 0)
end)

test("combat blocks starting and suppresses closing with no deferred close", function()
    local f = fixture(); f.combat = true; f:start(); equal(f.opens, 0); assert(f.error)
    f = fixture(); f:start(); f.snapshot = context(); f:tick()
    f.combat = true; f:drain(); assert(f.error); equal(f.closes, 0)
    f.combat = false; f.session:Finish(); equal(f.closes, 0)
end)

test("cleanup refusal leaves the profession open and reports it", function()
    local f = fixture(); f:start(); f.snapshot, f.current = context(), context(); f:drain()
    f.env.close = function() return false end
    assert(f.session:Finish():find("close it manually", 1, true))
    equal(f.session.active, false)
end)

test("new session invalidates the previous loading callback", function()
    local f = fixture(); f:start(171); f:start(185)
    f.snapshot, f.current = context(185), context(185); f:drain()
    equal(f.readyCount, 1); equal(f.result.baseID, 185)
end)

test("unavailable expansion metadata stops and closes the owned session", function()
    local f = fixture(); f:start(); f.snapshot = context(); f.message = "No expansion skill lines"
    f:drain(); equal(f.error, "No expansion skill lines"); equal(f.closes, 1)
end)

print(string.format("\n%d profession-session tests passed", passed))
