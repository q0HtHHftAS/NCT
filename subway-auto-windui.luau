-- subway-auto portable V0.5.0 | fixed anchor + no persist + executor check
pcall(function()
    local old = getgenv().SUBWAY_WIN
    if old then pcall(function() old:Destroy() end) end
end)
getgenv().SUBWAY_GEN = (getgenv().SUBWAY_GEN or 0) + 1
local MY_GEN = getgenv().SUBWAY_GEN

STATE = STATE or {}
if type(STATE.alive) ~= "function" then
    STATE.alive = function() return getgenv().SUBWAY_GEN == MY_GEN end
end

local SAFE_SPOT = Vector3.new(-122.9, 165.6, -139.9)

local okW, WindUI = pcall(function()
    return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not okW or not WindUI then
    warn("[subway-auto] WindUI load failed: " .. tostring(WindUI))
    return
end

-- NOTE: no Folder= param on purpose (portable: boot always farm=ON, no persisted OFF state)
local Window = WindUI:CreateWindow({ Title = "subway farm portable", Author = "V0.5.0 portable", Theme = "Dark" })
getgenv().SUBWAY_WIN = Window
local Tab = Window:Tab({ Title = "Zombies Mode", Icon = "zap" })

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

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer
print("[subway-auto] v50 portable boot gen=" .. MY_GEN .. " anchor=" .. tostring(SAFE_SPOT))

if type(fireproximityprompt) ~= "function" then
    print("[subway-auto] WARN: fireproximityprompt missing on this executor, buy will likely fail")
    pcall(function()
        WindUI:Notify({ Title = "Executor warn", Content = "fireproximityprompt NOT found, buy may fail on this executor", Duration = 5 })
    end)
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
        pcall(function() WindUI:Notify({ Title = "Restart", Content = "Match restarted!", Duration = 3 }) end)
    end)
end)

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
    WindUI:Notify({ Title = "Anchor", Content = "reset to safe spot " .. tostring(SAFE_SPOT), Duration = 3 })
end })
Tab:Button({ Title = "Set spot = my position", Callback = function()
    local hrp = getHRP()
    if hrp then
        STATE.anchor = hrp.Position + Vector3.new(0, 1, 0)
        WindUI:Notify({ Title = "Anchor", Content = "anchor set to " .. tostring(STATE.anchor), Duration = 3 })
    end
end })
Tab:Button({ Title = "Check Status", Callback = function()
    local hrp = getHRP()
    local base = subwayBase()
    local dBase = (hrp and base) and string.format("%.1f", (hrp.Position - base.Position).Magnitude) or "?"
    local dAnchor = (hrp and STATE.anchor) and string.format("%.1f", (STATE.anchor - hrp.Position).Magnitude) or "?"
    WindUI:Notify({ Title = "Status", Content = "Map=" .. (onSubwayMap() and "Subway" or "OTHER") .. " Yen=" .. parseYen() .. " Wave=" .. parseWave() .. " Bought=" .. tostring(isBought()) .. " Tally=" .. tostring(STATE.lastTally) .. " Buy=" .. tostring(STATE.lastBuyNote) .. " distBase=" .. dBase .. " distAnchor=" .. dAnchor, Duration = 6 })
end })

task.spawn(function()
    while STATE.alive() and getgenv().SUBWAY_GEN == MY_GEN do
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
                        if string.find(tostring(r), "fired") then
                            pcall(function() WindUI:Notify({ Title = "Subway", Content = tostring(r), Duration = 2 }) end)
                        else
                            STATE.lastBuyNote = tostring(r)
                        end
                    else
                        STATE.lastBuyNote = "ERR " .. tostring(r)
                    end
                    local ok2, r2 = pcall(doRestart)
                    if ok2 and r2 and string.find(tostring(r2), "voted") then
                        pcall(function() WindUI:Notify({ Title = "Restart", Content = tostring(r2), Duration = 3 }) end)
                    end
                end
            elseif activeTween then
                pcall(function() activeTween:Cancel() end)
                activeTween = nil
            end
            if STATE.tick % 10 == 0 then
                print("[subway-auto] v50 gen=" .. MY_GEN .. " move=" .. tostring(STATE.lastWalk) .. " yen=" .. parseYen() .. " wave=" .. parseWave() .. " bought=" .. tostring(isBought()) .. " buyNote=" .. tostring(STATE.lastBuyNote) .. " tally=" .. tostring(STATE.lastTally))
            end
        end)
        if not okBody then print("[subway-auto] LOOP ERR:", tostring(errBody)) end
        task.wait(cfg.interval or 0.5)
    end
    print("[subway-auto] v50 gen=" .. MY_GEN .. " loop ended")
end)

WindUI:Notify({ Title = "subway farm portable", Content = "V0.5.0 loaded, anchor=safe spot", Duration = 3 })
