--[[
LVID 05.10 format:
Headers:
"LVID" + 1 byte version + "." + 1 byte subversion
framerate 1 byte + frameCount 4 bytes + 1 byte image encoding
1 byte audio encoding + 1 byte compression type + 1 byte audio sample rate in KHz + 2 bytes width + 2 bytes height

each frame is then put here as this format:
audio data: sampleRate/framerate bytes of data (before compression)
frame data: a frame

A frame if compressed is fully compressed, not just a piece

Compression types:
0 - none
1 - LZ4

Image Formats:
0 - RAW BMP 8bpp palette indexed
1 - RAW RGB565
2 - RAW RGB24
3->255 - IF PLUGINS FOR IT

Audio Formats:
0 - PCM-8 mono
1 - PCM-16 mono
2 - none
3->255 - IF PLUGINS FOR IT
]]
-- LVID 05.10 Converter
-- Converts video + audio into LVID 05.10 format

-- LVID 05.10 Converter (single big raw frame file)
local _LVID_VERSION = "05.10"

local function compressData(data, compression)
    if compression == 1 then
        return love.data.compress("string", "lz4", data, 9)
    else
        return data
    end
end

local function intTo2Bytes(n)
    local g = math.floor(n/256)%256
    local b = n%256
    return string.char(b, g)
end

local function intTo4Bytes(n)
    local d = math.floor(n/(256*256*256))%256
    local c = math.floor(n/(256*256))%256
    local b = math.floor(n/256)%256
    local a = n%256
    return string.char(a, b, c, d)
end

-- Args
local args = {...}
local videopath = "fnaf.mp4"
local framerate = 60
local audioencoding = 1
local audiosamplerate = 96
local outputpath = "default.lvid"
local frameformat = 2
local compression = 0

for _, v in pairs(args) do
    if v:sub(1,1) == "-" then
        if v:sub(2,5) == "fps=" then framerate = tonumber(v:sub(6))
        elseif v:sub(2,3) == "a=" then audioencoding = tonumber(v:sub(4))
        elseif v:sub(2,3) == "s=" then audiosamplerate = tonumber(v:sub(4))
        elseif v:sub(2,3) == "o=" then outputpath = v:sub(4)
        elseif v:sub(2,3) == "c=" then compression = tonumber(v:sub(4))
        elseif v:sub(2,3) == "f=" then frameformat = tonumber(v:sub(4))
        end
    elseif v ~= "main" then
        videopath = v
    end
end

local pixelFormats = {"pal8", "rgb565le", "rgb24"}
local audioformats = {"u8", "s16le"}

-- Temp folder
os.execute("mkdir -p .tmp")

-- FFmpeg: single big raw frame file
local ffmpegFrames = string.format(
    'ffmpeg -y -i "%s" -r %d -pix_fmt %s -f rawvideo -threads 0 -c:v copy .tmp/frames.raw',
    videopath, framerate, pixelFormats[frameformat+1]
)
local ffmpegAudio = string.format(
    'ffmpeg -y -i "%s" -ar %d000 -ac 1 -f %s .tmp/audio.raw',
    videopath, audiosamplerate, audioformats[audioencoding+1]
)
assert(os.execute(ffmpegFrames) == 0, "FFmpeg frame extraction failed")
assert(os.execute(ffmpegAudio) == 0, "FFmpeg audio extraction failed")

-- Load full frames & audio
local fFrames = io.open(".tmp/frames.raw", "rb")
local frameDataAll = fFrames:read("*a")
fFrames:close()

local fAudio = io.open(".tmp/audio.raw", "rb")
local audioData = fAudio:read("*a")
fAudio:close()

-- Remove raw files after loading
os.remove(".tmp/frames.raw")
os.remove(".tmp/audio.raw")

-- Count frames
local bpp = (frameformat == 0) and 1 or (frameformat == 1 and 2 or 3)
local pixelsPerFrame = 640*360 -- You can set static 640x360 if you know it
local bytesPerFrame = pixelsPerFrame * bpp
local frameCount = #frameDataAll / bytesPerFrame

-- Write header
local out = assert(io.open(outputpath, "wb"))
out:write("LVID")
out:write(string.char(5,10))            -- version
out:write(string.char(framerate))       -- framerate
out:write(intTo4Bytes(frameCount))      -- frame count
out:write(string.char(frameformat))     -- image encoding
out:write(string.char(audioencoding))   -- audio encoding
out:write(string.char(compression))     -- compression
out:write(string.char(audiosamplerate)) -- audio sample rate
out:write(intTo2Bytes(640))             -- width
out:write(intTo2Bytes(360))             -- height

-- Audio per frame
local samplesPerFrame = (audiosamplerate*1000)/framerate
local bytesPerSample = (audioencoding == 0) and 1 or 2
local bytesPerFrameAudio = samplesPerFrame * bytesPerSample

-- Write frames
for i=1, frameCount do
    local frameStart = (i-1)*bytesPerFrame + 1
    local frameEnd   = i*bytesPerFrame
    local frameChunk = frameDataAll:sub(frameStart, frameEnd)

    local audioStart = math.floor((i-1)*bytesPerFrameAudio)+1
    local audioEnd   = math.floor(i*bytesPerFrameAudio)
    local audioChunk = audioData:sub(audioStart, audioEnd)

    local block = audioChunk .. frameChunk
    local packed = compressData(block, compression)
    out:write(packed)
end

out:close()
print("LVID 05.10 written to "..outputpath)
