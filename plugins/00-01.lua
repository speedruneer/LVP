-- lvp_00_01.lua
local lvp_00_01 = {}

-- Global palette accessible
palette = {}

-- Preallocate imageData and texture
local width, height = 640, 360
local imgData = love.image.newImageData(width, height)
local texture = love.graphics.newImage(imgData)

-- Convert PCM-8 raw audio to Love2D SoundData
local function makeAudioSource(rawData, sampleRate)
    local sampleCount = #rawData
    local sd = love.sound.newSoundData(sampleCount, sampleRate, 8, 1)
    for i = 0, sampleCount-1 do
        -- Normalize PCM-8 (0-255) to -1..1
        local value = (rawData:byte(i+1) - 128)/128
        sd:setSample(i, value)
    end
    return love.audio.newSource(sd, "static")
end

-- Load a frame with audio (flipped Y and proper seek)
function lvp_00_01.lvp_makeFrame(index, path, framerate)
    framerate = framerate or 60
    local file = love.filesystem.newFile(path, "r")
    file:open("r")

    -- Header size and frame size
    local headerSize = 13 -- Adjust this if your header is bigger
    local frameSize = math.floor(48000/framerate) + (256*3) + width*height

    -- Seek to correct frame
    file:read(9)
    framerate = string.byte(file:read(1))
    local countBytes = {file:read(3):byte(1,3)}
    local frameCount = countBytes[1]*65536 + countBytes[2]*256 + countBytes[3]
    file:seek(headerSize + (index-1) * frameSize)

    -- Read audio chunk
    local audioData = file:read(math.floor(48000/framerate))
    local audioSource = makeAudioSource(audioData, 48000)

    -- Read palette
    local paletteData = file:read(256*3)
    for i=1,256 do
        local b,g,r = paletteData:byte((i-1)*3+1,(i-1)*3+3)
        palette[i] = {r/255,g/255,b/255,1}
    end

    -- Read pixels
    local pixelsData = file:read(width*height)

    -- Update imageData (flip Y-axis)
    for y=0,height-1 do
        local flippedY = height-1 - y
        for x=0,width-1 do
            local idx = y*width + x + 1
            local colIdx = pixelsData:byte(idx) + 1
            local col = palette[colIdx] or {1,1,1,1}
            imgData:setPixel(x, flippedY, col[1], col[2], col[3], col[4])
        end
    end

    -- Update texture
    texture:replacePixels(imgData)
    file:close()

    return texture, audioSource, frameCount
end



function lvp_00_01.lvp_renderFrame(frame, x, y)
    x = x or 0
    y = y or 0

    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()

    local frameW = frame:getWidth()
    local frameH = frame:getHeight()

    local sx, sy

    if SCALE_RATIO then
        -- Uniform scaling to fit screen while keeping aspect ratio
        local scaleX = screenW / frameW
        local scaleY = screenH / frameH
        local scale = math.min(scaleX, scaleY)
        sx, sy = scale, scale
    else
        -- Non-uniform scaling to fill screen (may distort)
        sx = screenW / frameW
        sy = screenH / frameH
    end

    love.graphics.draw(frame, x, y, 0, sx, sy)
end

return lvp_00_01
