if SERVER then return end
if NaiBase_IsKillswitchActive and NaiBase_IsKillswitchActive() then return end

local MODULE_NAME = "Benchmark Tool"
local MODULE_VERSION = "1.0.0"

local BenchmarkData = {
    isRunning = false,
    results = {},
    startTime = 0,
    currentTest = "",
    tests = {}
}

hook.Add("InitPostEntity", "NaiBase_BenchmarkInit", function()
    timer.Simple(3.5, function()
        if not NaiBase then
            print("[Benchmark Tool] Warning: NaiBase not loaded, running standalone")
            return
        end
        
        NaiBase.RegisterModule(MODULE_NAME, {
            version = MODULE_VERSION,
            author = "Nai's Base Team",
            description = "Comprehensive performance benchmarking and testing",
            icon = "icon16/time.png",
            init = function()
                InitializeBenchmark()
            end
        })
        
        RegisterBenchmarkConfigs()
    end)
end)

function RegisterBenchmarkConfigs()
    if not NaiBase or not NaiBase.RegisterConfig then return end
    
    NaiBase.RegisterConfig(MODULE_NAME, "auto_save_results", {
        displayName = "Auto-Save Results",
        description = "Automatically save benchmark results to file",
        category = "General",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "test_duration", {
        displayName = "Test Duration",
        description = "Seconds to run each benchmark test",
        category = "Testing",
        valueType = "number",
        default = 10,
        min = 5,
        max = 60
    })
end

function InitializeBenchmark()
    print("[Benchmark Tool] Initializing benchmark systems...")
    
    DefineBenchmarkTests()
    
    print("[Benchmark Tool] Benchmark ready")
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.BenchmarkReady")
    end
end

function DefineBenchmarkTests()
    BenchmarkData.tests = {
        {
            name = "CPU Performance",
            id = "cpu",
            func = function()
                local result = 0
                for i = 1, 1000000 do
                    result = result + math.sin(i) * math.cos(i)
                end
                return result
            end
        },
        {
            name = "Memory Allocation",
            id = "memory",
            func = function()
                local tables = {}
                for i = 1, 10000 do
                    tables[i] = {
                        data = string.rep("x", 100),
                        number = i,
                        nested = {a = i, b = i * 2}
                    }
                end
                return #tables
            end
        },
        {
            name = "Entity Iteration",
            id = "entities",
            func = function()
                local count = 0
                for _, ent in ipairs(ents.GetAll()) do
                    if IsValid(ent) then
                        local pos = ent:GetPos()
                        local ang = ent:GetAngles()
                        count = count + 1
                    end
                end
                return count
            end
        },
        {
            name = "Render Performance",
            id = "render",
            func = function()
                local rt = GetRenderTarget("NaiBase_BenchRT", 512, 512)
                render.PushRenderTarget(rt)
                cam.Start2D()
                for i = 1, 100 do
                    surface.SetDrawColor(math.random(255), math.random(255), math.random(255), 255)
                    surface.DrawRect(math.random(512), math.random(512), 50, 50)
                end
                cam.End2D()
                render.PopRenderTarget()
                return 100
            end
        },
        {
            name = "Network Latency",
            id = "network",
            func = function()
                local ply = LocalPlayer()
                if IsValid(ply) then
                    return ply:Ping()
                end
                return 0
            end
        }
    }
end

function NaiBase.RunBenchmark(testId)
    if BenchmarkData.isRunning then
        print("[Benchmark Tool] Benchmark already running!")
        return
    end
    
    local test = nil
    if testId then
        for _, t in ipairs(BenchmarkData.tests) do
            if t.id == testId then
                test = t
                break
            end
        end
        
        if not test then
            print("[Benchmark Tool] Unknown test: " .. testId)
            return
        end
    end
    
    BenchmarkData.isRunning = true
    BenchmarkData.results = {}
    BenchmarkData.startTime = SysTime()
    
    local testsToRun = test and {test} or BenchmarkData.tests
    
    print("[Benchmark Tool] Starting benchmark...")
    print("========================================")
    
    local function runNextTest(index)
        if index > #testsToRun then
            BenchmarkData.isRunning = false
            local totalTime = SysTime() - BenchmarkData.startTime
            print("========================================")
            print("[Benchmark Tool] Benchmark complete!")
            print(string.format("Total Time: %.2f seconds", totalTime))
            
            if GetConfigValue("auto_save_results") then
                SaveBenchmarkResults()
            end
            
            if NaiBase then
                NaiBase.TriggerEvent("NaiBase.BenchmarkComplete", BenchmarkData.results)
            end
            
            return
        end
        
        local currentTest = testsToRun[index]
        BenchmarkData.currentTest = currentTest.name
        
        print("Running: " .. currentTest.name)
        
        local iterations = 0
        local totalTime = 0
        local minTime = 999999
        local maxTime = 0
        local startTime = SysTime()
        local duration = GetConfigValue("test_duration", 10)
        
        local function runIteration()
            if SysTime() - startTime >= duration then
                local avgTime = totalTime / iterations
                
                BenchmarkData.results[currentTest.id] = {
                    name = currentTest.name,
                    iterations = iterations,
                    totalTime = totalTime,
                    avgTime = avgTime,
                    minTime = minTime,
                    maxTime = maxTime,
                    score = math.floor(iterations / duration)
                }
                
                print(string.format("  Iterations: %d", iterations))
                print(string.format("  Avg Time: %.6f ms", avgTime * 1000))
                print(string.format("  Score: %d/sec", BenchmarkData.results[currentTest.id].score))
                
                timer.Simple(0.5, function()
                    runNextTest(index + 1)
                end)
                
                return
            end
            
            local iterStart = SysTime()
            currentTest.func()
            local iterEnd = SysTime()
            local iterTime = iterEnd - iterStart
            
            iterations = iterations + 1
            totalTime = totalTime + iterTime
            
            if iterTime < minTime then minTime = iterTime end
            if iterTime > maxTime then maxTime = iterTime end
            
            timer.Simple(0, runIteration)
        end
        
        timer.Simple(0, runIteration)
    end
    
    runNextTest(1)
end

function SaveBenchmarkResults()
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = "naibase_benchmark_" .. timestamp .. ".txt"
    
    local content = "Nai's Base Benchmark Results\n"
    content = content .. "Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    content = content .. "========================================\n\n"
    
    for testId, result in pairs(BenchmarkData.results) do
        content = content .. result.name .. ":\n"
        content = content .. string.format("  Iterations: %d\n", result.iterations)
        content = content .. string.format("  Avg Time: %.6f ms\n", result.avgTime * 1000)
        content = content .. string.format("  Min Time: %.6f ms\n", result.minTime * 1000)
        content = content .. string.format("  Max Time: %.6f ms\n", result.maxTime * 1000)
        content = content .. string.format("  Score: %d/sec\n\n", result.score)
    end
    
    file.Write(filename, content)
    print("[Benchmark Tool] Results saved to: " .. filename)
end

function NaiBase.GetBenchmarkResults()
    return BenchmarkData.results
end

function NaiBase.IsBenchmarkRunning()
    return BenchmarkData.isRunning
end

function GetConfigValue(key, default)
    if NaiBase and NaiBase.GetConfig then
        return NaiBase.GetConfig(key, default, MODULE_NAME)
    end
    return default
end

concommand.Add("naibase_benchmark", function(ply, cmd, args)
    local testId = args[1]
    NaiBase.RunBenchmark(testId)
end)

concommand.Add("naibase_benchmark_list", function()
    print("========================================")
    print("[Benchmark Tool] Available Tests")
    print("========================================")
    
    for i, test in ipairs(BenchmarkData.tests) do
        print(i .. ". " .. test.name .. " (" .. test.id .. ")")
    end
    
    print("========================================")
    print("Usage: naibase_benchmark [test_id]")
    print("Run without args to benchmark all tests")
end)

concommand.Add("naibase_benchmark_results", function()
    if table.Count(BenchmarkData.results) == 0 then
        print("[Benchmark Tool] No results available. Run a benchmark first!")
        return
    end
    
    print("========================================")
    print("[Benchmark Tool] Last Results")
    print("========================================")
    
    for testId, result in pairs(BenchmarkData.results) do
        print(result.name .. ":")
        print(string.format("  Score: %d/sec", result.score))
        print(string.format("  Avg Time: %.6f ms", result.avgTime * 1000))
    end
    
    print("========================================")
end)

print("[Benchmark Tool] Module loaded successfully")
