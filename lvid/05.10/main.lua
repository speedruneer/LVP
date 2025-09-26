--[[
LVID 05.10 format:
Headers:
"LVID" + 2 char version + "." + 2 char subversion
framerate 1 byte + frameCount 4 bytes + 1 byte image encoding
1 byte audio encoding + 1 byte compression type + 1 byte audio sample rate in KHz + 2 bytes width + 2 bytes height

each frame:
[audio chunk][compressed frame chunk with 3-byte size prefix]
]]

local _LVID_VERSION = "05.10"

local function compressData(data, compression)
    if compression == 1 then
        return love.data.compress("string", "lz4", data, 7) -- lower compression for speed
    else
        return data
    end
end

local function intTo2Bytes(n)
    local lo = n % 256
    local hi = math.floor(n / 256) % 256
    return string.char(lo, hi)
end

local function intTo3Bytes(n)
    local b1 = n % 256
    local b2 = math.floor(n / 256) % 256
    local b3 = math.floor(n / 65536) % 256
    return string.char(b1, b2, b3)
end

local function intTo4Bytes(n)
    local b1 = n % 256
    local b2 = math.floor(n / 256) % 256
    local b3 = math.floor(n / 65536) % 256
    local b4 = math.floor(n / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

-- Defaults
local args = {...}
local videopath = "nggyu.mp4"
local framerate = 30
local audioencoding = 1      -- PCM16
local audiosamplerate = 44.1   -- kHz
local outputpath = "default.lvid"
local frameformat = 2        -- RGB24
local compression = 1
local width = 1280
local height = 720

-- Parse CLI args
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

os.execute("mkdir -p .tmp")

-- Extract frames/audio
local ffmpegFrames = string.format(
    'ffmpeg -y -threads 0 -i "%s" -ac 1 -r %d -vf scale=%d:%d -pix_fmt %s -f rawvideo .tmp/frames.raw',
    videopath, framerate, width, height, pixelFormats[frameformat+1]
)

local ffmpegAudio = string.format(
    'ffmpeg -y -i "%s" -ar %d000 -ac 1 -f %s .tmp/audio.raw',
    videopath, audiosamplerate, audioFormats[audioencoding+1]
)

print("[FFmpeg] Extracting frames:", ffmpegFrames)
print("[FFmpeg] Extracting audio :", ffmpegAudio)
if not io.open(".tmp/frames.raw", "r") then assert(os.execute(ffmpegFrames) == 0, "FFmpeg frame extraction failed") end
if not io.open(".tmp/audio.raw", "r") then assert(os.execute(ffmpegAudio) == 0, "FFmpeg audio extraction failed") end

-- Frame/audio math
local bpp = (frameformat == 0 and 1) or (frameformat == 1 and 2) or 3
local bytesPerFrame = width * height * bpp
local frameFile = assert(io.open(".tmp/frames.raw", "rb"))
local audioFile = assert(io.open(".tmp/audio.raw", "rb"), "Could not open file")
print(audioFile)
local frameFileSize = frameFile:seek("end")
frameFile:seek("set",0)
local frameCount = math.floor(frameFileSize / bytesPerFrame)

local bytesPerSample = (audioencoding == 0 and 1 or 2)
local samplesPerFrame = math.floor(audiosamplerate*1000 / framerate + 0.5)
local bytesPerFrameAudio = samplesPerFrame * bytesPerSample

-- Open output
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

-- Pack frames: per-frame compression + 3-byte size prefix
for i=1,frameCount do
    if i % 10 == 0 then print("Processed frame: "..i.." / "..frameCount) end
    local audioChunk = audioFile:read(bytesPerFrameAudio)
    local frameChunk = frameFile:read(bytesPerFrame)
    if not audioChunk or not frameChunk then break end

    local block = audioChunk .. frameChunk
    local packed = compressData(block, compression)
    out:write(intTo3Bytes(#packed))
    out:write(packed)

end

frameFile:close()
audioFile:close()
out:close()
print("✅ LVID 05.10 written to "..outputpath)
