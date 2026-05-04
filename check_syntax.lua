#!/usr/bin/env lua
-- Simple Lua syntax checker for GMod addons
-- Usage: lua check_syntax.lua

local function checkFile(filePath)
    local file = io.open(filePath, "r")
    if not file then
        return false, "Could not open file: " .. filePath
    end

    local content = file:read("*all")
    file:close()

    -- Try to load the file (this checks syntax)
    local func, err = load(content, "@" .. filePath)

    if not func then
        return false, err
    end

    return true, nil
end

local function main()
    -- List of main Lua files to check
    local filesToCheck = {
        "lua/autorun/nai_npc_passengers.lua",
        "lua/nai_npc_passengers/main.lua",
        "lua/nai_npc_passengers/ui.lua",
        "lua/nai_npc_passengers/settings.lua",
        "lua/nai_npc_passengers/lvs_driver.lua",
        "lua/nai_npc_passengers/lvs_turret.lua",
        "lua/nai_npc_passengers/vj_base.lua",
    }

    local scriptDir = debug.getinfo(1).source:match("@?(.*/)")
    local addonDir = scriptDir:gsub("\\check_syntax%.lua$", ""):gsub("/check_syntax%.lua$", "")

    print("Checking Lua files in: " .. addonDir)
    print("")

    local errorCount = 0
    local fileCount = 0

    for _, relativePath in ipairs(filesToCheck) do
        local filePath = addonDir .. "/" .. relativePath:gsub("/", package.config:sub(1,1) == "\\" and "\\" or "/")

        fileCount = fileCount + 1
        local success, err = checkFile(filePath)

        if success then
            print("✓ " .. relativePath)
        else
            print("✗ " .. relativePath)
            print("  Error: " .. err)
            errorCount = errorCount + 1
        end
    end

    print("")
    print("Checked " .. fileCount .. " files")
    print("Errors found: " .. errorCount)

    if errorCount > 0 then
        os.exit(1)
    else
        print("All files passed syntax check!")
        os.exit(0)
    end
end

main()
