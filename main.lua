-- main.lua
local path = "fnaf.lvid"
local supportedFormats = {"00.01", "00.63"}

-- Try to detect format
local format
local file = io.open(path, "rb")
if not file then
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
    os.execute('zenity --error --text="Error: Unsupported LVID format: ' .. format .. '"')
    os.exit()
end

-- Load plugin safely
local success, lvp = pcall(function()
    return require("plugins." .. ({string.gsub(format, "%.", "-")})[1])
end)

if not success or not lvp then
    os.execute('zenity --error --text="Error: Failed to load LVP plugin for format ' .. format .. '"')
    os.exit()
end

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

-- Video setup
local idx = 1
local framerate = 60
local timer = 0
local currentFrame
local currentAudio
local frameCount = 0
local paused = false
-- Load first frame in love.load
function love.load()
    love.window.setMode(640, 360, {resizable=true})
    love.window.setTitle("LVP - " .. path)
    -- Grab first frame and audio
    currentFrame, currentAudio, frameCount = lvp.lvp_makeFrame(idx, path, framerate)
    if currentAudio then currentAudio:play() end
end

-- Update every frame
function love.update(dt)
    if not paused then
        timer = timer + dt
        if timer >= 1/framerate then
            timer = timer - 1/framerate

            -- Advance frame
            idx = idx + 1

            -- If video ended, stop
            local file = love.filesystem.getInfo(path)
            if not file then return end

            -- Load next frame
            currentFrame, currentAudio = lvp.lvp_makeFrame(idx, path, framerate)
            if currentAudio then currentAudio:play() end
        end
    end
end

-- Draw current frame
function love.draw()
    if currentFrame then
        lvp.lvp_renderFrame(currentFrame, 0, 0)
    end
    local r, g, b = love.graphics.getColor()
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.rectangle("fill", 0, love.graphics.getHeight()-30, love.graphics.getWidth(),4)
    love.graphics.setColor(1, 0, 0)
    love.graphics.rectangle("fill", 0, love.graphics.getHeight()-30, math.floor((idx / frameCount) * love.graphics.getWidth()),4)
    if paused then love.graphics.circle("fill", math.floor((idx / frameCount) * love.graphics.getWidth()), love.graphics.getHeight()-28, 6) end
    love.graphics.setColor(1, 1, 1) -- white text
    local currentTime = formatTime(idx / framerate)
    local totalTime = formatTime(frameCount / framerate)
    love.graphics.print(currentTime .. " / " .. totalTime, 10, love.graphics.getHeight() - 20)
end

-- Optional: simple key controls
function love.keypressed(key)
    if key == "space" then
        paused = not paused
        if currentAudio then
            if currentAudio:isPlaying() then
                currentAudio:pause()
            else
                currentAudio:play()
            end
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