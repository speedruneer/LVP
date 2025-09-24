local lvp_05_10 = {}
local imgData, texture

-- Helpers
local function readInt16LE(str, o)
    local b1, b2 = str:byte(o,o), str:byte(o+1,o+1)
    return b1 + b2*256
end

local function readInt32LE(str,o)
    local b1,b2,b3,b4 = str:byte(o),str:byte(o+1),str:byte(o+2),str:byte(o+3)
    return b1 + b2*256 + b3*65536 + b4*16777216
end

local function rshift(x,n) return math.floor(x / 2^n) end

-- PCM decode
local function makeAudioPCM8(raw, rate)
    local n = #raw
    local sd = love.sound.newSoundData(n, rate, 8, 1)
    for i=0,n-1 do
        local v = (raw:byte(i+1)-128)/128
        sd:setSample(i, v)
    end
    return love.audio.newSource(sd, "static")
end

local function makeAudioPCM16(raw, rate)
    local n = #raw/2
    local sd = love.sound.newSoundData(n, rate, 16, 1)
    for i=0,n-1 do
        local lo = raw:byte(i*2+1)
        local hi = raw:byte(i*2+2)
        local sample = lo + hi*256
        if sample >= 32768 then sample = sample - 65536 end
        sd:setSample(i, sample/32768)
    end
    return love.audio.newSource(sd, "static")
end

-- Main frame loader
function lvp_05_10.lvp_makeFrame(index, path)
    local f = assert(io.open(path, "rb"), "couldn't load file")
    local magic = f:read(4); assert(magic=="LVID","bad magic")
    local version = f:read(5) -- "05.10"
    local framerate = f:read(1):byte()
    local frameCount = readInt32LE(f:read(4),1)
    local imageFormat = f:read(1):byte()
    local audioFormat = f:read(1):byte()
    local compression = f:read(1):byte()
    local rateKHz = f:read(1):byte()
    local sampleRate = rateKHz*1000
    local width = readInt16LE(f:read(2),1)
    local height = readInt16LE(f:read(2),1)
    local bytesPerFrameAudio = readInt16LE(f:read(2),1)

    if not imgData or imgData:getWidth()~=width or imgData:getHeight()~=height then
        imgData = love.image.newImageData(width,height)
        texture = love.graphics.newImage(imgData)
    end

    local bpp = (imageFormat==0 and 1) or (imageFormat==1 and 2) or 3
    local frameSize = width*height*bpp
    if imageFormat==0 then frameSize = frameSize + 256*3 end

    -- skip to the correct block (linear scan)
    local blockSize = bytesPerFrameAudio + frameSize
    for i=1,index-1 do
        local data = f:read(blockSize)
        if compression==1 then
            data = love.data.decompress("string","lz4",data)
        end
    end

    -- now read the target block
    local block = f:read(blockSize)
    if compression==1 then
        block = love.data.decompress("string","lz4",block)
    end

    local audioRaw = block:sub(1, bytesPerFrameAudio)
    local frameRaw = block:sub(bytesPerFrameAudio+1)

    local audioSrc
    if audioFormat==0 then
        audioSrc = makeAudioPCM8(audioRaw,sampleRate)
    elseif audioFormat==1 then
        audioSrc = makeAudioPCM16(audioRaw,sampleRate)
    end

    if imageFormat==0 then
        -- Pal8
        local palette = {}
        for c=0,255 do
            local b = frameRaw:byte(c*3+1)
            local g = frameRaw:byte(c*3+2)
            local r = frameRaw:byte(c*3+3)
            palette[c+1] = {r/255,g/255,b/255,1}
        end
        local pixels = frameRaw:sub(256*3+1)
        for y=0,height-1 do
            local fy = height-1-y
            for x=0,width-1 do
                local idx = pixels:byte(y*width+x+1)+1
                local col = palette[idx] or {1,1,1,1}
                imgData:setPixel(x,fy,col[1],col[2],col[3],1)
            end
        end
    elseif imageFormat==1 then
        -- RGB565
        local p=1
        for y=0,height-1 do
            local fy=height-1-y
            for x=0,width-1 do
                local lo = frameRaw:byte(p); local hi = frameRaw:byte(p+1); p=p+2
                local val = lo + hi*256
                local r = rshift(val,11) % 32 * (255/31)
                local g = rshift(val,5) % 64 * (255/63)
                local b = val % 32 * (255/31)
                imgData:setPixel(x,fy,r/255,g/255,b/255,1)
            end
        end
    elseif imageFormat==2 then
        -- RGB24
        local p=1
        for y=0,height-1 do
            local fy=height-1-y
            for x=0,width-1 do
                local r = frameRaw:byte(p); local g = frameRaw:byte(p+1); local b = frameRaw:byte(p+2); p=p+3
                imgData:setPixel(x,fy,r/255,g/255,b/255,1)
            end
        end
    end

    texture:replacePixels(imgData)
    f:close()
    return texture,audioSrc,frameCount
end

-- Render helper
function lvp_05_10.lvp_renderFrame(frame,x,y)
    x,y=x or 0,y or 0
    local sw,sh=love.graphics.getWidth(),love.graphics.getHeight()
    local fw,fh=frame:getWidth(),frame:getHeight()
    local sx,sy
    if SCALE_RATIO then
        local s=math.min(sw/fw,sh/fh)
        sx,sy=s,s
    else
        sx,sy=sw/fw,sh/fh
    end
    love.graphics.draw(frame,x,y,0,sx,sy)
end

return lvp_05_10
