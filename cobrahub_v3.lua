-- Preserve the historical Duel release; patch only its pet collection modes.
local DUEL_URL = "https://raw.githubusercontent.com/guvenserzan6-beep/cobrahub/0ceb7cbed16259e5328b1e6a3d47b590783a05ba/cobrahub.lua"
local MENU_URL = "https://raw.githubusercontent.com/guvenserzan6-beep/cobrahub/main/cobrahub_menu.lua"

local v3 = [=[
function executeStealV3(prompt, animalData)
    if not Config.AutoSteal or StealSys.isStealing or not prompt or not prompt.Parent then return end
    local data = stealBuildCallbacks(prompt)
    if not data.ready then return end
    data.ready = false
    StealSys.isStealing = true
    StealSys.progressManual = true
    StealSys.stealStart = tick()
    local duration = math.clamp(tonumber(Config.AutoStealV3Time) or 0.05, 0.01, 5)
    StealSys.totalDuration = duration
    local function active()
        return Config.AutoSteal and Config.AutoStealVersion == "V3"
            and StealSys.isStealing and prompt.Parent ~= nil
    end
    local function distance()
        local position = stealGetPromptPosition(prompt)
        local character = LP.Character
        local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso"))
        if not position or not root then return math.huge end
        return (position - root.Position).Magnitude
    end
    local function finish()
        pcall(function() prompt:InputHoldEnd() end)
        data.ready = true
        StealSys.isStealing = false
        StealSys.progressManual = false
        StealSys.stealStart = 0
        resetStealProgress()
    end
    task.spawn(function()
        local ok, problem = pcall(function()
            updateStealProgress(0, "STEALING")
            for _, fn in ipairs(data.hold) do task.spawn(fn) end
            if #data.hold == 0 then prompt:InputHoldBegin() end
            local started = tick()
            while tick() - started < duration do
                if not active() then return end
                updateStealProgress(math.min((tick() - started) / duration, 1))
                task.wait()
            end
            -- Prepare from the configured radius, then trigger on the first near frame.
            local waiting = tick()
            while distance() > 9.3 do
                if not active() or tick() - waiting >= 1.6 then return end
                task.wait()
            end
            if not active() then return end
            for _, fn in ipairs(data.trigger) do task.spawn(fn) end
            if #data.trigger == 0 and fireproximityprompt then
                fireproximityprompt(prompt)
            end
            -- Keep the classic V2 completion path, not just local callbacks.
            local podName = animalData and (animalData.name or animalData.slot)
            local remote = game:GetService("ReplicatedStorage"):FindFirstChild("StealAnimal")
            if remote and podName then remote:FireServer(podName) end
            if #data.trigger == 0 and not fireproximityprompt and not (remote and podName) then
                error("V3: pet alma islemi baslatilamadi; desteklenen tetikleme bulunamadi", 0)
            end
            updateStealProgress(1, "READY")
        end)
        finish()
        if not ok then warn("[COBRAHUB] V3: " .. tostring(problem)) end
    end)
end

]=]

-- Editable V3 collection time, saved with the other settings.
local v3TimeRow = [=[
Config.AutoStealV3Time = math.clamp(tonumber(Config.AutoStealV3Time) or 0.05, 0.01, 5)
do
    local row = rowBase(combat, "V3 Sure (sn)", false)
    local box = Instance.new("TextBox")
    box.Text = tostring(Config.AutoStealV3Time)
    box.Font = Enum.Font.GothamMedium
    box.TextSize = 12
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Size = UDim2.new(0, 50, 0, 24)
    box.Position = UDim2.new(1, -66, 0.5, -12)
    box.Parent = row
    corner(box, 8)
    box.FocusLost:Connect(function()
        local value = tonumber((box.Text:gsub(",", ".")))
        if value then Config.AutoStealV3Time = math.clamp(value, 0.01, 5) end
        box.Text = tostring(Config.AutoStealV3Time)
        saveConfig()
    end)
end
]=]

local function patchDuel(source)
    local function replaceOnce(old, replacement)
        local first, last = source:find(old, 1, true)
        if not first then error("V3: beklenen script bolumu bulunamadi", 0) end
        source = source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
    end
    replaceOnce('if Config.AutoStealVersion == "V3" then Config.AutoStealVersion = "V2" end', '-- V3 is a supported saved selection.')
    replaceOnce('{ "V1", "V2" }, Config.AutoStealVersion', '{ "V1", "V2", "V3" }, Config.AutoStealVersion')
    replaceOnce('    Config.AutoStealVersion = ver\n', '    Config.AutoStealVersion = ver\n    saveConfig()\n')
    replaceOnce('            if ver == "V3" then ver = "V2" end', '            -- Show the actual selected version.')
    replaceOnce('function executeStealV1(prompt)', v3 .. 'function executeStealV1(prompt)')
    replaceOnce('        if ver == "V3" then ver = "V2" end', '        -- V3 has its own execution path.')
    replaceOnce('        if ver == "V2" then\n            local target, dist', '        if ver == "V3" then\n            local target, dist = stealNearestAnimal(radius)\n            if not target or (dist and dist > radius) then return end\n            local prompt = stealFindPromptForAnimal(target)\n            if prompt then executeStealV3(prompt, target) end\n        elseif ver == "V2" then\n            local target, dist')
    replaceOnce('setStealRadiusBadge = setRad\n', 'setStealRadiusBadge = setRad\n' .. v3TimeRow)
    return source
end

local function startMenu(name, url, patch)
    task.spawn(function()
        local ok, problem = pcall(function()
            local source = game:HttpGet(url)
            if patch then source = patch(source) end
            local run, compileError = loadstring(source, "=" .. name)
            if not run then error(compileError or "Script okunamadi", 0) end
            run()
        end)
        if not ok then warn("[COBRAHUB] " .. name .. " acilamadi: " .. tostring(problem)) end
    end)
end
startMenu("COBRA HUB Duel V3", DUEL_URL, patchDuel)
startMenu("COBRAHUB", MENU_URL)