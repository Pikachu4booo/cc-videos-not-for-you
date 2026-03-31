-- Optimized ComputerCraft Video Player
-- Supports duplicate frame compression

local dfpwm = require("cc.audio.dfpwm")

local speaker = peripheral.find("speaker")
local monitor = peripheral.find("monitor")

if not monitor then
    error("No monitor found! Please connect a monitor.")
end

local videoFile = "/video.nfv"
local audioFile = "/audio.dfpwm"

-- Check if files exist
if not fs.exists(videoFile) then
    error("Video file not found: " .. videoFile)
end

print("Loading video data...")
local videoData = {}
for line in io.lines(videoFile) do
    table.insert(videoData, line)
end

-- Parse header
local header = videoData[1]
local width, height, fps = header:match("(%d+) (%d+) (%d+)")
width = tonumber(width)
height = tonumber(height)
fps = tonumber(fps)

print("Video: " .. width .. "x" .. height .. " @ " .. fps .. " FPS")
print("Total lines: " .. #videoData)

table.remove(videoData, 1)

-- Set up monitor
monitor.setTextScale(0.5)
term.redirect(monitor)
term.clear()

local frameIndex = 1
local currentFrame = nil
local frameCount = 0

function nextFrame()
    if frameIndex > #videoData then
        return false
    end
    
    local line = videoData[frameIndex]
    frameIndex = frameIndex + 1
    
    -- Check if this is a duplicate frame marker
    if line == "=" then
        -- Reuse previous frame
        if currentFrame then
            paintutils.drawImage(currentFrame, 1, 1)
        end
    else
        -- Load new frame
        local frameLines = {line}
        
        -- Read remaining lines for this frame
        for i = 2, height do
            if frameIndex > #videoData then
                break
            end
            line = videoData[frameIndex]
            if line == "=" then
                break
            end
            table.insert(frameLines, line)
            frameIndex = frameIndex + 1
        end
        
        -- Parse and draw frame
        local frameData = table.concat(frameLines, "\n")
        currentFrame = paintutils.parseImage(frameData)
        
        if currentFrame then
            paintutils.drawImage(currentFrame, 1, 1)
        end
    end
    
    frameCount = frameCount + 1
    os.sleep(1 / fps)
    return true
end

function audioLoop()
    if not fs.exists(audioFile) then
        print("No audio file found, playing video only...")
        return
    end
    
    if not speaker then
        print("No speaker found, playing video only...")
        return
    end
    
    local decoder = dfpwm.make_decoder()
    for chunk in io.lines(audioFile, 16 * 1024) do
        local buffer = decoder(chunk)
        while not speaker.playAudio(buffer, 3) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

function videoLoop()
    while nextFrame() do
        -- Continue playing
    end
    print("Video finished. Played " .. frameCount .. " frames.")
end

-- Play video and audio in parallel
parallel.waitForAll(audioLoop, videoLoop)

-- Clean up
term.clear()
term.setCursorPos(1, 1)
term.redirect(term.native())
print("Playback complete!")
