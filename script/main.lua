-- مترو-آلي محمول الإصدار 0.5.3 | يبدأ التشغيل مع تعطيل المزرعة (يفعّلها المستخدم يدويًا)
local function env()
    local ok, g = pcall(function() return getgenv() end)
    if ok and type(g) == "table" then return g end
    return _G
end
local G = env()
pcall(function()
    local old = G.SUBWAY_WIN
    if old then pcall(function() old:Destroy() end) end
end)
G.SUBWAY_GEN = (G.SUBWAY_GEN or 0) + 1
local MY_GEN = G.SUBWAY_GEN
pcall(function() getgenv().SUBWAY_GEN = MY_GEN end)
pcall(function() _G.SUBWAY_GEN = MY_GEN end)

STATE = STATE or {}
STATE.alive = function() return G.SUBWAY_GEN == MY_GEN end

local SAFE_SPOT = Vector3.new(-122.9, 165.6, -139.9)
local VER = "v53"
local T0 = os.clock()
local function ms() return string.format("%.1fs", os.clock() - T0) end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer
print("[subway-auto] " .. VER .. " boot gen=" .. MY_GEN)

-- core state first (buttons need these)
STATE.cfg = { farm = false, waveMin = 1, interval = 0.5 }
local cfg = STATE.cfg
STATE.anchor = SAFE_SPOT
STATE.lastRestart = 0
STATE.lastTally = "-"
STATE.lastBuyNote = "-"
STATE.lastWalk = "-"
STATE.tick = 0
STATE.nextBuyAt = 0
STATE.boughtAt = 0
STATE.restartDelay = 0

local function getChar()
    local c = workspace:FindFirstChild("Characters") and workspace.Characters:FindFirstChild(LP.Name)
    if c then return c end
    return LP.Character
end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end
local function parseYen()
    local ok, txt = pcall(function() return LP.PlayerGui.YenHUD.Main.Yen.Text end)
    if not ok or not txt then return 0 end
    return tonumber((string.gsub(txt, "[^%d]", ""))) or 0
end
local function parseWave()
    local ok, txt = pcall(function() return LP.PlayerGui.HUD.Map.WavesAmount.Text end)
    if not ok or not txt then return 0 end
    local stripped = string.gsub(txt, "<[^>]+>", "")
    return tonumber(string.match(stripped, "(%d+)")) or 0
end
local function passage()
    local ok, f = pcall(function() return workspace.Map.Interactions.Passage_Subway end)
    if ok then return f end
    return nil
end
local function subwayBase()
    local f = passage()
    return f and f:FindFirstChild("Base") or nil
end
local function subwayPrompt()
    local b = subwayBase()
    return b and b:FindFirstChildOfClass("ProximityPrompt") or nil
end
local function onSubwayMap()
    local f = passage()
    if not f then return false end
    local b = f:FindFirstChild("Base")
    if not b then return false end
    return b:FindFirstChildOfClass("ProximityPrompt") ~= nil
end
local function isBought()
    local p = subwayPrompt()
    return p == nil or p.Enabled == false
end

local activeTween = nil
local function doPull()
    local hrp = getHRP()
    local spot = STATE.anchor or SAFE_SPOT
    if not hrp or not spot then return "no hrp/spot" end
    local dist = (spot - hrp.Position).Magnitude
    if dist > 8 then
        if activeTween then return "riding" end
        activeTween = TweenService:Create(hrp, TweenInfo.new(2.5, Enum.EasingStyle.Linear), { CFrame = CFrame.new(spot) })
        activeTween:Play()
        return "pulling"
    end
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end
    if dist > 1.5 then
        hrp.CFrame = CFrame.new(spot)
        return "snapping"
    end
    return "holding"
end
local function triggerPrompt(prompt)
    if type(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
        return "fpp"
    end
    prompt:InputHoldBegin()
    task.wait(0.1)
    pcall(function() prompt:InputHoldEnd() end)
    return "hold"
end
local function rand15()
    return 1 + math.random() * 4
end
local function doBuy()
    if isBought() then return "owned already" end
    local base = subwayBase()
    local prompt = subwayPrompt()
    if not base or not prompt then return "no base/prompt" end
    local yen = parseYen()
    if yen < 5000 then return "yen " .. yen .. " <5000" end
    local hrp = getHRP()
    if hrp then
        local d = (hrp.Position - base.Position).Magnitude
        if d > 9 then return "too far from door (" .. string.format("%.1f", d) .. "m, press Go to safe spot)" end
    end
    local now = os.clock()
    if now < (STATE.nextBuyAt or 0) then
        return "buy in " .. string.format("%.1f", STATE.nextBuyAt - now) .. "s"
    end
    local how = triggerPrompt(prompt)
    STATE.boughtAt = now
    STATE.restartDelay = rand15()
    STATE.nextBuyAt = now + rand15()
    return "fired(" .. how .. ") yen=" .. yen
end
local function doRestart()
    if not isBought() then return "not bought yet" end
    local wave = parseWave()
    if wave < (cfg.waveMin or 1) then return "wave " .. wave .. " < min" end
    if os.clock() - (STATE.lastRestart or 0) < 5 then return "cooldown" end
    if (STATE.boughtAt or 0) > 0 and os.clock() - STATE.boughtAt < (STATE.restartDelay or 0) then
        return "post-buy wait"
    end
    STATE.lastRestart = os.clock()
    local m = require(game:GetService("ReplicatedStorage").NetworkCode.GameMatchFlowClient)
    m.CastRestartVote.Fire()
    return "voted wave=" .. wave
end

local function statusText()
    local hrp = getHRP()
    local base = subwayBase()
    local dBase = (hrp and base) and string.format("%.1f", (hrp.Position - base.Position).Magnitude) or "?"
    local dAnchor = (hrp and STATE.anchor) and string.format("%.1f", (STATE.anchor - hrp.Position).Magnitude) or "?"
    return "Map=" .. (onSubwayMap() and "Subway" or "OTHER")
        .. " Yen=" .. parseYen() .. " Wave=" .. parseWave()
        .. " Bought=" .. tostring(isBought())
        .. " Tally=" .. tostring(STATE.lastTally)
        .. " Buy=" .. tostring(STATE.lastBuyNote)
        .. " distBase=" .. dBase .. " distAnchor=" .. dAnchor
end

-- لوحة فورية: البحث عن الكائن الأب مع مهلة زمنية (لا يوجد انتظار لا نهائي)
local dbgGui, dbgLabel, dbgFrame
pcall(function()
    local parent = nil
    pcall(function() parent = gethui and gethui() or nil end)
    if not parent then
        pcall(function() parent = game:GetService("CoreGui") end)
    end
    local okTest = pcall(function()
        local t = Instance.new("Frame")
        t.Parent = parent
        t:Destroy()
    end)
    if not okTest or not parent then
        parent = LP:FindFirstChild("PlayerGui")
        if not parent then
            parent = LP:WaitForChild("PlayerGui", 5)
        end
    end
    dbgGui = Instance.new("ScreenGui")
    dbgGui.Name = "SubwayAutoDbg"
    dbgGui.ResetOnSpawn = false
    dbgGui.Parent = parent
    dbgFrame = Instance.new("Frame")
    dbgFrame.Size = UDim2.fromOffset(300, 220)
    dbgFrame.Position = UDim2.new(0, 12, 0, 12)
    dbgFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    dbgFrame.BackgroundTransparency = 0.2
    dbgFrame.Parent = dbgGui
    dbgLabel = Instance.new("TextLabel")
    dbgLabel.Size = UDim2.new(1, -12, 0, 56)
    dbgLabel.Position = UDim2.new(0, 6, 0, 6)
    dbgLabel.BackgroundTransparency = 1
    dbgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    dbgLabel.TextSize = 13
    dbgLabel.TextXAlignment = Enum.TextXAlignment.Left
    dbgLabel.TextYAlignment = Enum.TextYAlignment.Top
    dbgLabel.TextWrapped = true
    dbgLabel.Text = "[subway " .. VER .. "] starting..."
    dbgLabel.Parent = dbgFrame
end)
local function dbg(t)
    t = "[" .. ms() .. "] " .. tostring(t)
    print("[subway-auto] " .. VER .. " " .. t)
    pcall(function() if dbgLabel then dbgLabel.Text = "[subway " .. VER .. "] " .. t end end)
end

-- الأزرار تعمل الآن (من دون انتظار WindUI)pcall(function()
    if not dbgFrame then return end
    local function mkBtn(y, txt, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -12, 0, 28)
        b.Position = UDim2.new(0, 6, 0, y)
        b.Text = txt
        b.TextSize = 14
        b.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Parent = dbgFrame
        b.MouseButton1Click:Connect(function()
            local ok, r = pcall(cb)
            dbg(tostring(txt) .. " -> " .. tostring(r or "ok"))
        end)
    end
    mkBtn(66, "Farm: toggle (now OFF)", function()
        cfg.farm = not cfg.farm
        return "farm=" .. tostring(cfg.farm)
    end)
    mkBtn(98, "Go to safe spot", function()
        STATE.anchor = SAFE_SPOT
        if activeTween then pcall(function() activeTween:Cancel() end) activeTween = nil end
        local hrp = getHRP()
        if hrp then hrp.CFrame = CFrame.new(SAFE_SPOT) end
        return "anchor=safe"
    end)
    mkBtn(130, "Set spot = my pos", function()
        local hrp = getHRP()
        if hrp then STATE.anchor = hrp.Position + Vector3.new(0, 1, 0) end
        return tostring(STATE.anchor)
    end)
    mkBtn(162, "Status -> label", function() return statusText() end)
    mkBtn(194, "Close panel", function()
        if dbgGui then dbgGui.Enabled = false end
        return "closed (farm keeps running)"
    end)
end)
dbg("panel ready, loading WindUI in background...")

if type(fireproximityprompt) ~= "function" then
    dbg("WARN fireproximityprompt missing, buy may fail")
end

pcall(function()
    local m = require(game:GetService("ReplicatedStorage").NetworkCode.GameMatchFlowClient)
    m.RestartVoteTallyUpdated.On(function(data)
        local ok, vc, rc = pcall(function() return data.VotedCount, data.RequiredCount end)
        if ok then STATE.lastTally = tostring(vc) .. "/" .. tostring(rc) end
    end)
end)
pcall(function()
    local GH = require(game:GetService("ReplicatedStorage").Modules.Gameplay.GameHandler)
    GH.MatchRestarted:Connect(function()
        STATE.lastRestart = 0
        STATE.boughtAt = 0
        STATE.nextBuyAt = 0
    end)
end)

-- WindUI: cache first (instant on 2nd run), then fast raw URL, then release URL
local CACHE = "subway_windui_cache.lua"
local WindUI = nil
local windErr = ""
local compile = (loadstring or load)

-- 0) disk cache
pcall(function()
    if isfile and isfile(CACHE) then
        local src = readfile(CACHE)
        if src and #src > 50000 then
            local t = os.clock()
            local fn = compile(src)
            local mod = fn()
            if mod then
                WindUI = mod
                print("[subway-auto] WindUI from cache in " .. string.format("%.1fs", os.clock() - t))
            end
        end
    end
end)

-- 1) الشبكة، عنوان URL السريع أولًا
if not WindUI then
    local WIND_URLS = {
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
        "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
    }
    for i, url in ipairs(WIND_URLS) do
        local t = os.clock()
        local ok, res = pcall(function()
            local src = game:HttpGet(url)
            local fn = compile(src)
            local mod = fn()
            if mod and src then
                pcall(function()
                    if writefile then writefile(CACHE, src) end
                end)
            end
            return mod
        end)
        if ok and res then
            WindUI = res
            print("[subway-auto] WindUI net ok via " .. i .. " in " .. string.format("%.1fs", os.clock() - t))
            break
        else
            windErr = tostring(res)
            print("[subway-auto] WindUI try " .. i .. " failed in " .. string.format("%.1fs", os.clock() - t) .. ": " .. windErr)
        end
    end
end

local uiMode = "panel"
if WindUI then
    local okUI, errUI = pcall(function()
        local Window = WindUI:CreateWindow({ Title = "subway farm portable", Author = "V0.5.3 portable", Theme = "Dark" })
        G.SUBWAY_WIN = Window
        local Tab = Window:Tab({ Title = "Zombies Mode", Icon = "zap" })
        Tab:Toggle({ Title = "Auto Subway", Desc = "Stay at safe spot + Buy + Restart (Subway map only)", Value = false, Callback = function(s) cfg.farm = s end })
        Tab:Slider({ Title = "Wave min", Value = { Min = 1, Max = 30, Default = 1 }, Step = 1, Callback = function(v)
            local n = tonumber(v)
            if not n and type(v) == "table" then n = tonumber(v.Value) or tonumber(v.Default) end
            cfg.waveMin = math.floor(n or 1)
        end })
        Tab:Button({ Title = "Go to safe spot", Callback = function()
            STATE.anchor = SAFE_SPOT
            if activeTween then
                pcall(function() activeTween:Cancel() end)
                activeTween = nil
            end
            local hrp = getHRP()
            if hrp then hrp.CFrame = CFrame.new(SAFE_SPOT) end
            WindUI:Notify({ Title = "Anchor", Content = "reset to safe spot", Duration = 3 })
        end })
        Tab:Button({ Title = "Set spot = my position", Callback = function()
            local hrp = getHRP()
            if hrp then
                STATE.anchor = hrp.Position + Vector3.new(0, 1, 0)
                WindUI:Notify({ Title = "Anchor", Content = "anchor set " .. tostring(STATE.anchor), Duration = 3 })
            end
        end })
        Tab:Button({ Title = "Check Status", Callback = function()
            WindUI:Notify({ Title = "Status", Content = statusText(), Duration = 6 })
        end })
        WindUI:Notify({ Title = "subway farm portable", Content = "V0.5.3 loaded (WindUI, farm OFF - enable to start)", Duration = 3 })
    end)
    if okUI then
        uiMode = "windui"
        pcall(function() if dbgGui then dbgGui:Destroy() end end)
        dbgGui = nil
    else
        print("[subway-auto] WindUI build failed: " .. tostring(errUI) .. " | keep panel")
        WindUI = nil
    end
end

if not WindUI then
    uiMode = "panel"
    dbg("panel mode (WindUI: " .. string.sub(windErr, 1, 100) .. ")")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "subway farm", Text = "Panel mode ready. WindUI skipped.", Duration = 4 })
    end)
end

task.spawn(function()
    while STATE.alive() and G.SUBWAY_GEN == MY_GEN do
        local okBody, errBody = pcall(function()
            STATE.tick = STATE.tick + 1
            if cfg.farm then
                if not onSubwayMap() then
                    STATE.lastBuyNote = "wrong map, idle"
                    if activeTween then
                        pcall(function() activeTween:Cancel() end)
                        activeTween = nil
                    end
                else
                    local okP, rP = pcall(doPull)
                    STATE.lastWalk = tostring(okP and rP or ("ERR " .. tostring(rP)))
                    local ok, r = pcall(doBuy)
                    if ok and r then
                        STATE.lastBuyNote = tostring(r)
                    else
                        STATE.lastBuyNote = "ERR " .. tostring(r)
                    end
                    pcall(doRestart)
                end
            elseif activeTween then
                pcall(function() activeTween:Cancel() end)
                activeTween = nil
            end
            if STATE.tick % 10 == 0 then
                print("[subway-auto] " .. VER .. " gen=" .. MY_GEN .. " ui=" .. uiMode .. " move=" .. tostring(STATE.lastWalk) .. " yen=" .. parseYen() .. " wave=" .. parseWave() .. " bought=" .. tostring(isBought()) .. " buyNote=" .. tostring(STATE.lastBuyNote) .. " tally=" .. tostring(STATE.lastTally))
            end
        end)
        if not okBody then print("[subway-auto] LOOP ERR:", tostring(errBody)) end
        task.wait(cfg.interval or 0.5)
    end
    print("[subway-auto] " .. VER .. " gen=" .. MY_GEN .. " loop ended")
end)

dbg("loaded ui=" .. uiMode .. " total " .. ms())
