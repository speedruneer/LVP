--[[
LVID 05.10 format:
Headers:
"LVID" + 2 char version + "." + 2 char subversion
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
-- LVID 05.10 Converter - fixed
local _LVID_VERSION = "05.10"

-- Helpers
local function compressData(data, compression)
    if compression == 1 then
        return love.data.compress("string", "lz4", data, 9)
    else
        return data
    end
end

local function intTo2Bytes(n)
    local lo = n % 256
    local hi = math.floor(n / 256) % 256
    return string.char(lo, hi)
end

local function intTo4Bytes(n)
    local b1 = n % 256
    local b2 = math.floor(n / 256) % 256
    local b3 = math.floor(n / 65536) % 256
    local b4 = math.floor(n / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

-- ============================
-- Defaults
-- ============================
local args = {...}
local videopath = "fnaf.mp4"
local framerate = 60
local audioencoding = 1      -- PCM16
local audiosamplerate = 48   -- kHz
local outputpath = "default.lvid"
local frameformat = 2        -- RGB24
local compression = 1
local width = 720
local height = 480

-- ============================
-- Parse args
-- ============================
for _,v in ipairs(args) do
    if v:sub(1,5) == "-fps=" then framerate = tonumber(v:sub(6))
    elseif v:sub(1,3) == "-a=" then audioencoding = tonumber(v:sub(4))
    elseif v:sub(1,3) == "-s=" then audiosamplerate = tonumber(v:sub(4))
    elseif v:sub(1,3) == "-o=" then outputpath = v:sub(4)
    elseif v:sub(1,3) == "-c=" then compression = tonumber(v:sub(4))
    elseif v:sub(1,3) == "-f=" then frameformat = tonumber(v:sub(4))
    elseif v:sub(1,3) == "-w=" then width = tonumber(v:sub(4))
    elseif v:sub(1,3) == "-h=" then height = tonumber(v:sub(4))
    elseif v ~= "main" then videopath = v
    end
end

local pixelFormats = {"pal8", "rgb565le", "rgb24"}
local audioFormats = {"u8", "s16le"}

-- ============================
-- Temp folder
-- ============================
os.execute("mkdir -p .tmp")

-- ============================
-- FFmpeg extraction
-- ============================
-- Video: decode properly to raw frames (NO copy)
local ffmpegFrames = string.format(
    'ffmpeg -y -threads 0 -i "%s" -r %d -vf scale=%d:%d -pix_fmt %s -f rawvideo .tmp/frames.raw',
    videopath, framerate, width, height, pixelFormats[frameformat+1]
)

-- Audio: mono, correct sample rate
local ffmpegAudio = string.format(
    'ffmpeg -y -i "%s" -ar %d000 -ac 1 -f %s .tmp/audio.raw',
    videopath, audiosamplerate, audioFormats[audioencoding+1]
)

print("[FFmpeg] Extracting frames:", ffmpegFrames)
print("[FFmpeg] Extracting audio :", ffmpegAudio)
if not io.open(".tmp/frames.raw", "r") then assert(os.execute(ffmpegFrames) == 0, "FFmpeg frame extraction failed") end
if not io.open(".tmp/audio.raw", "r") then assert(os.execute(ffmpegAudio) == 0, "FFmpeg audio extraction failed") end

-- ============================
-- Load raw data
-- ============================
local frameFile = assert(io.open(".tmp/frames.raw", "rb"))
local frameDataAll = frameFile:read("*a")
frameFile:close()

local audioFile = assert(io.open(".tmp/audio.raw", "rb"))
local audioData = audioFile:read("*a")
audioFile:close()

-- cleanup
os.remove(".tmp/frames.raw")
os.remove(".tmp/audio.raw")

-- ============================
-- Frame and audio math
-- ============================
local bpp = (frameformat == 0 and 1) or (frameformat == 1 and 2) or 3
local bytesPerFrame = width * height * bpp
local frameCount = math.floor(#frameDataAll / bytesPerFrame)

local bytesPerSample = (audioencoding == 0 and 1) or 2
local samplesPerFrame = math.floor(audiosamplerate*1000 / framerate + 0.5)
local bytesPerFrameAudio = samplesPerFrame * bytesPerSample

-- ============================
-- Write LVID
-- ============================
local out = assert(io.open(outputpath, "wb"))
out:write("LVID")
out:write(_LVID_VERSION)
out:write(string.char(framerate))
out:write(intTo4Bytes(frameCount))
out:write(string.char(frameformat))
out:write(string.char(audioencoding))
out:write(string.char(compression))
out:write(string.char(audiosamplerate))
out:write(intTo2Bytes(width))
out:write(intTo2Bytes(height))

-- ============================
-- Pack each frame
-- ============================
for i=1, frameCount do
    local fStart = (i-1)*bytesPerFrame + 1
    local fEnd   = i*bytesPerFrame
    local frameChunk = frameDataAll:sub(fStart, fEnd)

    local aStart = (i-1)*bytesPerFrameAudio + 1
    local aEnd   = i*bytesPerFrameAudio
    local audioChunk = audioData:sub(aStart, aEnd)

    local block = audioChunk .. frameChunk
    local packed = compressData(block, compression)
    out:write(packed)
end

out:close()
print("✅ LVID 05.10 written to "..outputpath)
