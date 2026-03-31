local files = {
    ["audio.dfpwm"] = "https://github.com/Pikachu4booo/cc-videos-not-for-you/raw/refs/heads/main/birdbrain%20from%20claude/audio.dfpwm",
    ["player.lua"]   = "https://github.com/Pikachu4booo/cc-videos-not-for-you/raw/refs/heads/main/birdbrain%20from%20claude/player.lua",
    ["video.nfv"]    = "https://github.com/Pikachu4booo/cc-videos-not-for-you/raw/refs/heads/main/birdbrain%20from%20claude/video.nfv"
}

-- 1. Download all files
for name, url in pairs(files) do
    print("Downloading " .. name .. "...")
    local response = http.get(url)
    if response then
        local f = fs.open(name, "wb") -- Uses binary mode for .dfpwm and .nfv
        f.write(response.readAll())
        f.close()
        response.close()
        print("Done!")
    else
        error("Failed to download " .. name)
    end
end

-- 2. Run the player
print("Launching player...")
shell.run("player.lua")
