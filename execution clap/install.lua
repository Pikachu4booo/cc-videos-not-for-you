local files = {
    ["audio.dfpwm"] = "https://github.com/Pikachu4booo/cc-videos-not-for-you/raw/refs/heads/main/execution%20clap/audio.dfpwm",
    ["player.lua"]   = "https://github.com/Pikachu4booo/cc-videos-not-for-you/raw/refs/heads/main/execution%20clap/player.lua"
}

local largeFile = {
    name = "video.nfv",
    url = "https://github.com/Pikachu4booo/cc-videos-not-for-you/raw/refs/heads/main/execution%20clap/video.nfv"
}

-- Function to download large files in chunks
local function downloadLargeFile(url, filename)
    local chunkSize = 5 * 1024 * 1024 -- 5MB chunks to stay under 16MB limit
    
    print("Starting chunked download of " .. filename .. "...")
    local f = fs.open(filename, "wb")
    local currentByte = 0
    local downloading = true
    
    while downloading do
        local rangeEnd = currentByte + chunkSize - 1
        print("Downloading bytes " .. currentByte .. " to " .. rangeEnd .. "...")
        
        -- Request the next chunk
        local res = http.get(url, { Range = "bytes=" .. currentByte .. "-" .. rangeEnd }, true)
        
        if res then
            local content = res.readAll()
            res.close()
            
            if content and #content > 0 then
                f.write(content)
                currentByte = currentByte + #content
                -- If we got less than we asked for, we reached the end
                if #content < chunkSize then
                    downloading = false
                end
            else
                downloading = false -- No more data
            end
        else
            f.close()
            error("Download failed for " .. filename)
        end
    end
    
    f.close()
    print("Download complete! (" .. currentByte .. " bytes)")
end

-- 1. Download small files normally
for name, url in pairs(files) do
    print("Downloading " .. name .. "...")
    local response = http.get(url)
    if response then
        local f = fs.open(name, "wb")
        f.write(response.readAll())
        f.close()
        response.close()
        print("Done!")
    else
        error("Failed to download " .. name)
    end
end

-- 2. Download large video file in chunks
downloadLargeFile(largeFile.url, largeFile.name)

-- 2. Run the player
print("Launching player...")
shell.run("player.lua")
