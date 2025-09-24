-- main.lua
local path = "default.lvid"
local supportedFormats = {"00.01", "05.10"}

-- Safe print replacement for terminal / debugging
local function safePrint(...)
    print(...)
    local args = {...}
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    local line = table.concat(args, " ")
    -- Use love.filesystem to log, or fallback to standard print
    if love and love.filesystem then
        -- Example: write to log file
        print(love.filesystem.setRequirePath("./?.lua;./?/init.lua"))
        local f = love.filesystem.newFile("lvp_log.txt", "w")
        f:open("a")
        f:write(line.."\n")
        f:close()
    else
        print(line)
    end
end

-- Detect format
local format
local file = io.open(path, "rb")
if not file then
    safePrint("Error: Cannot open file " .. path)
    os.execute('zenity --error --text="Error: Cannot open file ' .. path .. '"')
    os.exit()
end

format = file:read(9):sub(5, 9)
file:close()

-- Check if format is supported
local isSupported = false
for _, f in ipairs(supportedFormats) do
    if f == format then
        isSupported = true
        break
    end
end

if not isSupported then
    safePrint("Error: Unsupported LVID format: " .. format)
    os.execute('zenity --error --text="Error: Unsupported LVID format: ' .. format .. '"')
    os.exit()
end

-- Load plugin safely
local success, lvp = pcall(function()
    local pluginName = "p"..({format:gsub("%.", "")})[1]
    safePrint("Loading plugin:", pluginName)
    return require(pluginName)
end)

if not success or not lvp then
    print(lvp)
    safePrint("Error: Failed to load LVP plugin for format " .. format)
    os.execute('zenity --error --text="Error: Failed to load LVP plugin for format ' .. format .. '"')
    os.exit()
end

-- Format time helper
local function formatTime(seconds)
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    else
        return string.format("%d:%02d", m, s)
    end
end

-- Video state
local idx = 1
local framerate = 60
local timer = 0
local currentFrame
local currentAudio
local frameCount = 0
local paused = false

-- Load first frame
function love.load()
    love.window.setMode(640, 360, {resizable=true})
    love.window.setTitle("LVP - " .. path)
    currentFrame, currentAudio, frameCount = lvp.lvp_makeFrame(idx, path, framerate)
    if currentAudio then currentAudio:play() end
end

function love.update(dt)
    if not paused then
        timer = timer + dt
        if timer >= 1/framerate then
            timer = timer - 1/framerate
            idx = idx + 1
            -- Stop at end
            if idx > frameCount then return end
            currentFrame, currentAudio = lvp.lvp_makeFrame(idx, path, framerate)
            if currentAudio then currentAudio:play() end
        end
    end
end

function love.draw()
    if currentFrame then
        lvp.lvp_renderFrame(currentFrame, 0, 0)
    end

    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.rectangle("fill", 0, h-30, w, 4)
    love.graphics.setColor(1, 0, 0)
    love.graphics.rectangle("fill", 0, h-30, math.floor((idx / frameCount) * w), 4)
    if paused then love.graphics.circle("fill", math.floor((idx / frameCount) * w), h-28, 6) end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(formatTime(idx / framerate) .. " / " .. formatTime(frameCount / framerate), 10, h - 20)
end

function love.keypressed(key)
    if key == "space" then
        paused = not paused
        if currentAudio then
            if currentAudio:isPlaying() then currentAudio:pause() else currentAudio:play() end
        end
    elseif key == "left" then
        idx = math.max(1, idx - framerate*5)
        currentFrame, currentAudio = lvp.lvp_makeFrame(idx, path, framerate)
        if currentAudio then currentAudio:play() end
    elseif key == "right" then
        idx = idx + framerate*5
        currentFrame, currentAudio = lvp.lvp_makeFrame(idx, path, framerate)
        if currentAudio then currentAudio:play() end
    end
end
