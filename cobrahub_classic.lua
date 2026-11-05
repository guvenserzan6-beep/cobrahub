-- Keep the pre-teleport Duel release and the renamed COBRAHUB menu separate.
local function startMenu(name, url)
    task.spawn(function()
        local ok, problem = pcall(function()
            local source = game:HttpGet(url)
            local run, compileError = loadstring(source, "=" .. name)
            if not run then error(compileError or "Script okunamadi", 0) end
            run()
        end)
        if not ok then warn("[COBRAHUB] " .. name .. " acilamadi: " .. tostring(problem)) end
    end)
end
startMenu("COBRA HUB Duel", "https://raw.githubusercontent.com/guvenserzan6-beep/cobrahub/0ceb7cbed16259e5328b1e6a3d47b590783a05ba/cobrahub.lua")
startMenu("COBRAHUB", "https://raw.githubusercontent.com/guvenserzan6-beep/cobrahub/main/cobrahub_menu.lua")