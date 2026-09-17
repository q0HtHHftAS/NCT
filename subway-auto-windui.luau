-- subway-auto portable V0.5.1 | WindUI multi-URL + native fallback UI (fixes no-UI on other executors)
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
local VER = "v51"

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer
print("[subway-auto] " .. VER .. " boot gen=" .. MY_GEN)

-- Phase A: immediate on-screen boot indicator (always shows, even if WindUI fails)
local dbgGui, dbgLabel
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
        parent = LP:WaitForChild("PlayerGui")
    end
    dbgGui = Instance.new("ScreenGui")
    dbgGui.Name = "SubwayAutoDbg"
    dbgGui.ResetOnSpawn = false
    dbgGui.Parent = parent
    local fr = Instance.new("Frame")
    fr.Size = UDim2.fromOffset(300, 64)
    fr.Position = UDim2.new(0, 12, 0, 12)
    fr.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    fr.BackgroundTransparency = 0.2
    fr.Parent = dbgGui
    dbgLabel = Instance.new("TextLabel")
    dbgLabel.Size = UDim2.new(1, -12, 1, -12)
    dbgLabel.Position = UDim2.new(0, 6, 0, 6)
    dbgLabel.BackgroundTransparency = 1
    dbgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    dbgLabel.TextSize = 13
    dbgLabel.TextXAlignment = Enum.TextXAlignment.Left
    dbgLabel.TextYAlignment = Enum.TextYAlignment.Top
    dbgLabel.TextWrapped = true
    dbgLabel.Text = "[subway " .. VER .. "] loading..."
    dbgLabel.Parent = fr
end)
local function dbg(t)
    print("[subway-auto] " .. VER .. " " .. tostring(t))
    pcall(function() if dbgLabel then dbgLabel.Text = "[subway " .. VER .. "] " .. tostring(t) end end)
end

STATE.cfg = { farm = true, waveMin = 1, interval = 0.5 }
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

-- core helpers (no UI dependency)
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

if type(fireproximityprompt) ~= "function" then
    dbg("WARN fireproximityprompt missing, buy may fail")
end

-- listeners (never fatal)
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

-- Phase B: WindUI via multiple URLs (release redirect fails on some executors)
local WIND_URLS = {
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
}
local WindUI = nil
local windErr = ""
for i, url in ipairs(WIND_URLS) do
    dbg("WindUI try " .. i .. "/2 ...")
    local ok, res = pcall(function()
        local src = game:HttpGet(url)
        local fn = (loadstring or load)(src)
        return fn()
    end)
    if ok and res then
        WindUI = res
        dbg("WindUI ok via " .. i)
        break
    else
        windErr = tostring(res)
        print("[subway-auto] WindUI try " .. i .. " failed: " .. windErr)
    end
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

local uiMode = "fallback"
if WindUI then
    local okUI, errUI = pcall(function()
        -- NOTE: no Folder= on purpose (portable: boot always farm=ON)
        local Window = WindUI:CreateWindow({ Title = "subway farm portable", Author = "V0.5.1 portable", Theme = "Dark" })
        G.SUBWAY_WIN = Window
        local Tab = Window:Tab({ Title = "Zombies Mode", Icon = "zap" })
        Tab:Toggle({ Title = "Auto Subway", Desc = "Stay at safe spot + Buy + Restart (Subway map only)", Value = true, Callback = function(s) cfg.farm = s end })
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
        WindUI:Notify({ Title = "subway farm portable", Content = "V0.5.1 loaded (WindUI)", Duration = 3 })
    end)
    if okUI then
        uiMode = "windui"
    else
        dbg("WindUI build failed: " .. tostring(errUI) .. " | fallback UI")
        WindUI = nil
    end
end

if not WindUI then
    uiMode = "fallback"
    dbg("fallback UI (WindUI fail: " .. string.sub(windErr, 1, 120) .. ")")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "subway farm", Text = "WindUI failed, fallback UI. F9 for error.", Duration = 6 })
    end)
    -- upgrade dbg panel into working fallback controls
    pcall(function()
        local fr = dbgLabel and dbgLabel.Parent or nil
        if not fr then return end
        fr.Size = UDim2.fromOffset(300, 220)
        dbgLabel.TextWrapped = true
        local function mkBtn(y, txt, cb)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -12, 0, 30)
            b.Position = UDim2.new(0, 6, 0, y)
            b.Text = txt
            b.TextSize = 14
            b.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
            b.Parent = fr
            b.MouseButton1Click:Connect(function()
                local ok, r = pcall(cb)
                dbg(tostring(txt) .. " -> " .. tostring(r or "ok") .. " | " .. statusText())
            end)
            return b
        end
        mkBtn(64, "Farm: toggle (now ON)", function()
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
        mkBtn(132, "Set spot = my pos", function()
            local hrp = getHRP()
            if hrp then STATE.anchor = hrp.Position + Vector3.new(0, 1, 0) end
            return tostring(STATE.anchor)
        end)
        mkBtn(166, "Status -> F9", function() return statusText() end)
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

dbg("loaded ui=" .. uiMode .. " anchor=safe spot")
