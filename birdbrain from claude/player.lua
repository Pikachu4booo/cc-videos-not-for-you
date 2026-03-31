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
local lineCount = 0
for line in io.lines(videoFile) do
    table.insert(videoData, line)
    lineCount = lineCount + 1
    -- Yield every 100 lines to prevent "too long without yielding"
    if lineCount % 100 == 0 then
        os.sleep(0)
    end
end
print("Loaded " .. lineCount .. " lines")

-- Parse header
local header = videoData[1]
local width, height, fps = header:match("(%d+) (%d+) (%d+)")
width = tonumber(width)
height = tonumber(height)
fps = tonumber(fps)

print("Video: " .. width .. "x" .. height .. " @ " .. fps .. " FPS")
print("Total lines: " .. #videoData)

table.remove(videoData, 1)

-- Set up monitor with auto-scaling
local monitorWidth, monitorHeight = monitor.getSize()
print("Monitor size: " .. monitorWidth .. "x" .. monitorHeight)

-- Calculate best text scale to fit video on monitor
local bestScale = 0.5
for scale = 0.5, 5, 0.5 do
    monitor.setTextScale(scale)
    local w, h = monitor.getSize()
    if w >= width and h >= height then
        bestScale = scale
        break
    end
end

monitor.setTextScale(bestScale)
print("Using text scale: " .. bestScale)
print("Press any key to start...")
os.pullEvent("key")

local frameIndex = 1
local currentFrame = nil
local frameCount = 0
local startTime = nil
local skippedFrames = 0
local syncStartTime = nil  -- Shared start time for audio and video sync

function nextFrame()
    if frameIndex > #videoData then
        return false
    end
    
    -- Read timestamp for this frame
    local timestampLine = videoData[frameIndex]
    if not timestampLine or not timestampLine:match("^T:") then
        return false
    end
    
    local targetTimestamp = tonumber(timestampLine:match("^T:(%d+)")) / 1000  -- Convert ms to seconds
    frameIndex = frameIndex + 1
    
    -- Wait for sync start if not set yet (first frame waits for audio to be ready)
    while not syncStartTime do
        os.sleep(0)
    end
    
    -- Calculate how long to wait
    local currentTime = os.epoch("utc") / 1000
    local elapsedTime = currentTime - syncStartTime
    local waitTime = targetTimestamp - elapsedTime
    
    -- If we're behind schedule, check if we should skip this frame
    if waitTime < -0.1 then  -- More than 100ms behind
        -- Skip this frame entirely
        local line = videoData[frameIndex]
        if line then
            frameIndex = frameIndex + 1
            if line ~= "=" then
                -- Skip the rest of this frame's lines
                for i = 2, height do
                    if frameIndex > #videoData then break end
                    local nextLine = videoData[frameIndex]
                    if not nextLine or nextLine:match("^T:") then break end
                    frameIndex = frameIndex + 1
                end
            end
        end
        skippedFrames = skippedFrames + 1
        frameCount = frameCount + 1
        return true
    end
    
    -- Wait until it's time to display this frame
    if waitTime > 0 then
        os.sleep(waitTime)
    end
    
    -- Now render the frame
    local line = videoData[frameIndex]
    if not line then
        return false
    end
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
            if not line or line:match("^T:") then
                break
            end
            table.insert(frameLines, line)
            frameIndex = frameIndex + 1
        end
        
        -- Parse and draw frame (with yield for large frames)
        local frameData = table.concat(frameLines, "\n")
        
        -- Yield if processing large frame to prevent timeout
        if #frameData > 5000 then
            os.sleep(0)
        end
        
        currentFrame = paintutils.parseImage(frameData)
        
        if currentFrame then
            paintutils.drawImage(currentFrame, 1, 1)
        end
    end
    
    frameCount = frameCount + 1
    
    -- Brief yield to prevent timeout
    os.sleep(0)
    
    return true
end

function audioLoop()
    if not fs.exists(audioFile) then
        print("No audio file found, playing video only...")
        syncStartTime = os.epoch("utc") / 1000  -- Set start time anyway
        return
    end
    
    if not speaker then
        print("No speaker found, playing video only...")
        syncStartTime = os.epoch("utc") / 1000  -- Set start time anyway
        return
    end
    
    -- Set synchronized start time just before audio begins
    syncStartTime = os.epoch("utc") / 1000
    
    local decoder = dfpwm.make_decoder()
    for chunk in io.lines(audioFile, 16 * 1024) do
        local buffer = decoder(chunk)
        while not speaker.playAudio(buffer, 3) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

function videoLoop()
    -- Pre-load and display first frame before sync starts
    print("Pre-loading first frame...")
    
    -- Skip timestamp of first frame temporarily
    local firstTimestamp = videoData[frameIndex]
    frameIndex = frameIndex + 1
    
    -- Load first frame
    local line = videoData[frameIndex]
    frameIndex = frameIndex + 1
    
    if line and line ~= "=" then
        local frameLines = {line}
        for i = 2, height do
            if frameIndex > #videoData then break end
            line = videoData[frameIndex]
            if not line or line:match("^T:") then break end
            table.insert(frameLines, line)
            frameIndex = frameIndex + 1
        end
        
        local frameData = table.concat(frameLines, "\n")
        currentFrame = paintutils.parseImage(frameData)
        if currentFrame then
            paintutils.drawImage(currentFrame, 1, 1)
        end
        frameCount = 1
    end
    
    print("First frame loaded, waiting for audio sync...")
    
    -- Now play remaining frames
    while nextFrame() do
        -- Continue playing
    end
    
    print("Video finished.")
    print("Frames played: " .. frameCount)
    if skippedFrames > 0 then
        print("Frames skipped for sync: " .. skippedFrames)
    end
end

-- Start audio and video playback together
print("Starting playback...")
term.redirect(monitor)
term.clear()
parallel.waitForAll(audioLoop, videoLoop)

-- Clean up
term.redirect(term.native())
term.clear()
term.setCursorPos(1, 1)
print("Playback complete!")
