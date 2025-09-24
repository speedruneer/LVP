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
1 - RAW RGB332
2 - RAW RGB565
3 - RAW RGB888
4->255 - IF PLUGINS FOR IT

Audio Formats:
0 - wav
1 - MPEG-3
2 - PCM-8 mono
3 - PCM-8 stereo
4 - PCM-16 mono
5 - PCM-16 stereo
6 - none
7->255 - IF PLUGINS FOR IT
]]
local _LVID_VERSION = "05.10"

local function compressData(data)
    return love.data.compress("string", "lz4", data, 9)
end

local args = {...}
local videopath = ""
local framerate = 60
local audioencoding = 4 -- yes, I will use PCM-16 mono as a default
local audiosamplerate = 96 -- Some CASUAL 96KHz PCM-16 mono and?
local outputpath = "default.lvid"

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