--[[
LVID 05.10 format:
Headers:
"LVID" + 1 byte version + "." + 1 byte subversion
framerate 1 byte + frameCount 4 bytes + 1 byte image encoding
1 byte audio encoding + 1 byte compression type + 1 byte audio sample rate in KHz + 2 bytes width + 2 bytes height

each frame is then put here as this format:
audio data: sampleRate/framerate bytes of data (unless compressed)
frame data: a frame

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
local _LVID_VERSION = "05.10"

local function compressData(data)
    return love.data.compress("string", "lz4", data, 9)
end

-- Convert integer to 2-byte string
local function intTo2Bytes(n)
    local g = math.floor(n/256)%256
    local b = n%256
    return string.char(b, g)
end

-- Convert integer to 4-byte string
local function intTo4Bytes(n)
    local d = math.floor(n/(256*256*256))%256
    local c = math.floor(n/(256*256))%256
    local b = math.floor(n/256)%256
    local a = n%256
    return string.char(a, b, c, d)
end

local args = {...}
local videopath = ""
local framerate = 60
local audioencoding = 1 -- yes, I will use PCM-16 mono as a default
local audiosamplerate = 96 -- Some CASUAL 96KHz PCM-16 mono and?
local outputpath = "default.lvid"
local frameformat = 2 -- yes default RGB24

for _, v in pairs(args) do
    if v:sub(1, 1) == "-" then
        if v:sub(2, 3) == "f=" then
        elseif v:sub(2, 5) == "fps=" then
            framerate = tonumber(v:sub(6, #v))
        elseif v:sub(2, 3) == "a=" then
            audioencoding = tonumber(v:sub(4, 4))
        elseif v:sub(2, 3) == "s=" then
            audiosamplerate = tonumber(v:sub(4, #v))
        elseif v:sub(2, 3) == "o=" then
            outputpath = v:sub(4, #v)
        else
            videopath = v
        end
    end
end
local pixelFormats = {"pal8", "rgb565le", "rgb24"}
local audioformats = {"u8", "s16le"}
local ffmpegCMD1 = string.format("mkdir .tmp && ffmpeg -i %s -r %d -pix_fmt %s .tmp/frame_%%08d.bmp", videopath, framerate, pixelFormats[frameformat+1])
local ffmpegCMD2 = string.format("ffmpeg -i %s -ar %d -ac %d -f %s .tmpoutput", videopath, audiosamplerate, audioformats[audioencoding+1])