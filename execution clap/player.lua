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
local skippedFrames = 0
local syncStartTime = nil  -- Shared start time for audio and video sync
local videoReady = false
local audioReady = false

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
    
    -- Calculate how long to wait
    local currentTime = os.epoch("utc") / 1000
    local elapsedTime = currentTime - syncStartTime
    local waitTime = targetTimestamp - elapsedTime
    
    -- If we're behind schedule by more than 150ms, skip this frame
    if waitTime < -0.15 then
        -- Skip this frame entirely without rendering
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
        os.sleep(0)
        return true
    end
    
    -- Wait until it's time to display this frame
    if waitTime > 0.001 then
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
        
        -- Parse and draw frame
        local frameData = table.concat(frameLines, "\n")
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
        audioReady = true
        -- Wait for video to be ready
        while not videoReady do
            os.sleep(0)
        end
        -- Set sync time
        syncStartTime = os.epoch("utc") / 1000
        return
    end
    
    if not speaker then
        print("No speaker found, playing video only...")
        audioReady = true
        -- Wait for video to be ready
        while not videoReady do
            os.sleep(0)
        end
        -- Set sync time
        syncStartTime = os.epoch("utc") / 1000
        return
    end
    
    -- Prepare audio decoder
    local decoder = dfpwm.make_decoder()
    local file = fs.open(audioFile, "rb")
    
    -- Signal ready
    audioReady = true
    print("Audio ready, waiting for video...")
    
    -- Wait for video to be ready
    while not videoReady do
        os.sleep(0)
    end
    
    -- Set synchronized start time
    syncStartTime = os.epoch("utc") / 1000
    print("Playback starting NOW")
    
    -- Play audio
    while true do
        local chunk = file.read(16 * 1024)
        if not chunk then
            break
        end
        
        local buffer = decoder(chunk)
        while not speaker.playAudio(buffer, 3) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    
    file.close()
end

function videoLoop()
    -- Redirect to monitor and prepare
    term.redirect(monitor)
    term.clear()
    
    -- Signal ready
    videoReady = true
    print("Video ready, waiting for audio...")
    
    -- Wait for audio to be ready and set sync time
    while not audioReady or not syncStartTime do
        os.sleep(0)
    end
    
    -- Start playing frames
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
parallel.waitForAll(audioLoop, videoLoop)

-- Clean up
term.redirect(term.native())
term.clear()
term.setCursorPos(1, 1)
print("Playback complete!")
