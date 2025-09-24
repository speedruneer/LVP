-- lvp_05_10.lua
local lvp_05_10 = {}

-- Image cache
local imgData, texture

-- ===========================
-- Helpers
-- ===========================

-- Read little-endian 2-byte int
local function readInt16LE(str, offset)
    local b1 = str:byte(offset)
    local b2 = str:byte(offset+1)
    return b1 + b2*256
end

-- Read little-endian 4-byte int
local function readInt32LE(str, offset)
    local b1 = str:byte(offset)
    local b2 = str:byte(offset+1)
    local b3 = str:byte(offset+2)
    local b4 = str:byte(offset+3)
    return b1 + b2*256 + b3*65536 + b4*16777216
end

-- PCM-8 → SoundData
local function makeAudioPCM8(raw, sampleRate)
    local n = #raw
    local sd = love.sound.newSoundData(n, sampleRate, 8, 1)
    for i=0,n-1 do
        local v = (raw:byte(i+1)-128)/128
        sd:setSample(i, v)
    end
    return love.audio.newSource(sd, "static")
end

-- PCM-16 → SoundData
local function makeAudioPCM16(raw, sampleRate)
    local n = #raw / 2
    local sd = love.sound.newSoundData(n, sampleRate, 16, 1)
    for i=0,n-1 do
        local lo = raw:byte(i*2+1)
        local hi = raw:byte(i*2+2)
        local sample = hi*256 + lo
        if sample >= 32768 then sample = sample - 65536 end -- signed
        sd:setSample(i, sample/32768)
    end
    return love.audio.newSource(sd, "static")
end

-- ===========================
-- Frame Loading
-- ===========================
function lvp_05_10.lvp_makeFrame(index, path)
    local file = love.filesystem.newFile(path, "r")
    assert(file:open("r"))

    -- Read header
    file:seek(0)
    local magic = file:read(4) -- "LVID"
    assert(magic == "LVID", "Invalid LVID file")

    local verMajor = file:read(1):byte()
    file:read(1) -- dot "."
    local verMinor = file:read(1):byte()

    local framerate = file:read(1):byte()
    local frameCount = readInt32LE(file:read(4), 1)
    local imageFormat = file:read(1):byte()
    local audioFormat = file:read(1):byte()
    local compression = file:read(1):byte()
    local audioRateKHz = file:read(1):byte()
    local sampleRate = audioRateKHz * 1000
    local width = readInt16LE(file:read(2), 1)
    local height = readInt16LE(file:read(2), 1)

    -- Prepare imgData if needed
    if not imgData or imgData:getWidth() ~= width or imgData:getHeight() ~= height then
        imgData = love.image.newImageData(width, height)
        texture = love.graphics.newImage(imgData)
    end

    -- Calculate frame offset (rough: depends on compression, so we must scan sequentially)
    local headerSize = 4+1+1+1+4+1+1+1+1+2+2
    file:seek(headerSize)

    local current = 1
    local frameData, audioSource

    while current <= frameCount do
        -- Read audio chunk
        local audioBytes = math.floor(sampleRate / framerate) * (audioFormat==1 and 2 or 1)
        local audioRaw = file:read(audioBytes)

        if compression == 1 then
            audioRaw = love.data.decompress("string", "lz4", audioRaw)
        end

        if audioFormat == 0 then
            audioSource = makeAudioPCM8(audioRaw, sampleRate)
        elseif audioFormat == 1 then
            audioSource = makeAudioPCM16(audioRaw, sampleRate)
        else
            audioSource = nil
        end

        -- Read frame raw
        local frameSize
        if imageFormat == 0 then
            frameSize = width*height + 256*3 -- pal8
        elseif imageFormat == 1 then
            frameSize = width*height*2 -- rgb565
        elseif imageFormat == 2 then
            frameSize = width*height*3 -- rgb24
        else
            error("Unsupported image format: "..imageFormat)
        end

        local rawFrame = file:read(frameSize)
        if compression == 1 then
            rawFrame = love.data.decompress("string", "lz4", rawFrame)
        end

        if current == index then
            -- Decode frame
            if imageFormat == 0 then
                -- Pal8
                local palette = {}
                for i=0,255 do
                    local b = rawFrame:byte(i*3+1)
                    local g = rawFrame:byte(i*3+2)
                    local r = rawFrame:byte(i*3+3)
                    palette[i+1] = {r/255,g/255,b/255,1}
                end
                local pixels = rawFrame:sub(256*3+1)
                for y=0,height-1 do
                    local fy = height-1-y
                    for x=0,width-1 do
                        local idx = pixels:byte(y*width+x+1)+1
                        local col = palette[idx] or {1,1,1,1}
                        imgData:setPixel(x, fy, col[1], col[2], col[3], 1)
                    end
                end
            elseif imageFormat == 1 then
                -- RGB565
                local p = 1
                for y=0,height-1 do
                    local fy = height-1-y
                    for x=0,width-1 do
                        local lo = rawFrame:byte(p); local hi = rawFrame:byte(p+1); p=p+2
                        local val = lo + hi*256
                        local r = ((val >> 11) & 31) * 255/31
                        local g = ((val >> 5) & 63) * 255/63
                        local b = (val & 31) * 255/31
                        imgData:setPixel(x, fy, r/255, g/255, b/255, 1)
                    end
                end
            elseif imageFormat == 2 then
                -- RGB24
                local p=1
                for y=0,height-1 do
                    local fy = height-1-y
                    for x=0,width-1 do
                        local r = rawFrame:byte(p); local g = rawFrame:byte(p+1); local b = rawFrame:byte(p+2); p=p+3
                        imgData:setPixel(x, fy, r/255, g/255, b/255, 1)
                    end
                end
            end
            break
        else
            -- Skip decoding, just advance
        end
        current = current + 1
    end

    texture:replacePixels(imgData)
    file:close()

    return texture, audioSource, frameCount
end

-- Render (same as 00_01)
function lvp_05_10.lvp_renderFrame(frame, x, y)
    x = x or 0; y = y or 0
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local fw, fh = frame:getWidth(), frame:getHeight()
    local sx, sy
    if SCALE_RATIO then
        local s = math.min(sw/fw, sh/fh)
        sx, sy = s, s
    else
        sx, sy = sw/fw, sh/fh
    end
    love.graphics.draw(frame, x, y, 0, sx, sy)
end

return lvp_05_10
