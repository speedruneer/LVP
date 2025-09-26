local lvp_05_10 = {}
local imgData, texture

local function readInt16LE(str,o)
    local b1,b2 = str:byte(o,o), str:byte(o+1,o+1)
    return b1 + b2*256
end

local function readInt32LE(str,o)
    local b1,b2,b3,b4 = str:byte(o,o+3)
    return b1 + b2*256 + b3*65536 + b4*16777216
end

local function readInt24LE(str,o)
    local b1,b2,b3 = str:byte(o,o+2)
    return b1 + b2*256 + b3*65536
end

local function makeAudioPCM8(raw, rate)
    local n = #raw
    local sd = love.sound.newSoundData(n, rate, 8, 1)
    for i=0,n-1 do
        local v = (raw:byte(i+1)-128)/128
        sd:setSample(i, v)
    end
    return love.audio.newSource(sd, "stream")
end

local function makeAudioPCM16(raw, rate)
    local n = #raw / 2
    local sd = love.sound.newSoundData(n, rate, 16, 1)
    for i = 0, n-1 do
        local lo = raw:byte(i*2+1)
        local hi = raw:byte(i*2+2)
        local sample = lo + hi*256
        if sample >= 32768 then sample = sample - 65536 end
        -- Map directly to -1..1
        sd:setSample(i, sample / 32767)
    end
    return love.audio.newSource(sd, "static")
end
local audioSrc

function lvp_05_10.lvp_makeFrame(index,path)
    local f = assert(io.open(path,"rb"))
    assert(f:read(4)=="LVID")
    local version = f:read(5)
    local framerate = f:read(1):byte()
    local frameCount = readInt32LE(f:read(4),1)
    local imageFormat = f:read(1):byte()
    local audioFormat = f:read(1):byte()
    local compression = f:read(1):byte()
    local rateKHz = f:read(1):byte()
    local sampleRate = rateKHz*1000
    local width = readInt16LE(f:read(2),1)
    local height = readInt16LE(f:read(2),1)

    local bpp = (imageFormat==0 and 1) or (imageFormat==1 and 2) or 3
    local frameSizeUncompressed = width*height*bpp
    if imageFormat==0 then frameSizeUncompressed = frameSizeUncompressed+256*3 end

    if not imgData or imgData:getWidth()~=width or imgData:getHeight()~=height then
        imgData = love.image.newImageData(width,height)
        texture = love.graphics.newImage(imgData)
    end

    -- seek through previous frames
    for i=1,index-1 do
        local sizeBytes = f:read(3)
        local sz = readInt24LE(sizeBytes,1)
        f:seek("cur", sz)
    end

    -- read target frame
    local sizeBytes = f:read(3)
    local sz = readInt24LE(sizeBytes,1)
    local block = f:read(sz)
    if compression==1 then block = love.data.decompress("string","lz4",block,7) end

    local audioRaw = block:sub(1,#block-frameSizeUncompressed)
    if audioFormat==0 then audioSrc = makeAudioPCM8(audioRaw,sampleRate)
    elseif audioFormat==1 then audioSrc = makeAudioPCM16(audioRaw,sampleRate)
    end

    local frameRaw = block:sub(#block-frameSizeUncompressed+1, #block)
    
    -- RGB24
    -- RGB24 optimized with mapPixel
local p = 1
imgData:mapPixel(function(x, y, r, g, b, a)
    local r_, g_, b_ = frameRaw:byte(p, p+2)
    p = p + 3
    return r_/255, g_/255, b_/255, 1
end)


    texture:replacePixels(imgData)
    f:close()
    return texture,audioSrc,frameCount, framerate, width, height
end

function lvp_05_10.lvp_renderFrame(frame,x,y)
    x,y=x or 0,y or 0
    local sw,sh=love.graphics.getWidth(),love.graphics.getHeight()
    local fw,fh=frame:getWidth(),frame:getHeight()
    local sx,sy=sw/fw,sh/fh
    love.graphics.draw(frame,x,y,0,sx,sy)
end

return lvp_05_10
