-- REAPER Script: Import Drums (Strict Match + Immediate Mode)
-- FIX: Strict Token Matching (Only matches -token-, _token_, etc.)
-- FIX: Immediate processing to prevent stale pointers/restart bug.
-- FIX: Strips GUID during copy to prevent ghost items/overlapping cleanup failures.

local function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

-- =========================================================
-- CONFIG
-- =========================================================

local token_map = {
    snare    = "Snare",
    kick     = "Kick",
    toms     = "Toms",
    crash    = "Crash",
    ride     = "Ride",
    hh       = "HH",
    drums    = "Drums",
    residual = "Other",
    other    = "Other",
    others   = "Other",
}

-- Tracks that get Copied + Normalized
local type_copy_norm = {
    HH   = true,
    Ride = true
}

-- Tracks that get Baked + Processed
local type_bake_move = {
    Crash = true
}

-- =========================================================
-- HELPERS
-- =========================================================

local protected_tracks = {}

local function GetTrackByName(name)
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if trackName == name then 
            protected_tracks[track] = true
            return track 
        end
    end
    return nil
end

local function NormalizeKey(s)
    s = tostring(s or "")
    -- 1. Lowercase
    s = s:lower()
    -- 2. Convert dashes to underscores (User convention: -snare- becomes _snare_)
    s = s:gsub("%-", "_")
    return s
end

local function NameHasToken(normalized_name, token)
    local t = token:lower()
    t = t:gsub("([^%w])", "%%%1") -- Escape magic characters in token

    -- 1. Exact Match ("snare")
    if normalized_name == t then return true end

    -- 2. Surrounded by delimiters ("_snare_")
    if normalized_name:find("_" .. t .. "_", 1, false) then return true end

    -- 3. Starts with token + delimiter ("snare_...")
    if normalized_name:find("^" .. t .. "_") then return true end

    -- 4. Ends with delimiter + token ("..._snare")
    if normalized_name:find("_" .. t .. "$") then return true end

    -- STRICT MODE: No loose matching. "snaretop" will NOT match "snare".
    return false
end

local function UnselectAllItems()
    reaper.Main_OnCommand(40289, 0)
end

local function SelectOnlyItem(item)
    if reaper.ValidatePtr(item, "MediaItem*") then
        UnselectAllItems()
        reaper.SetMediaItemSelected(item, true)
    end
end

local function CopyItemToTrack(item, destTrack)
    -- Get the raw state of the item
    local _, chunk = reaper.GetItemStateChunk(item, "", false)
    
    -- [FIX] Remove the existing GUID from the chunk.
    -- If we don't do this, the new item has the exact same ID as the old one.
    -- This causes REAPER to confuse which item is selected during the "Delete Take" step.
    chunk = chunk:gsub("GUID {.-}\n", "")
    
    local newItem = reaper.AddMediaItemToTrack(destTrack)
    reaper.SetItemStateChunk(newItem, chunk, false)
    
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", pos)
    
    -- Ensure the new item is fresh in REAPER's eyes
    reaper.UpdateItemInProject(newItem)
    
    return newItem
end

local function BakeFXOnItem(trackWithFX, item)
    reaper.SetOnlyTrackSelected(trackWithFX)
    SelectOnlyItem(item)
    reaper.UpdateArrange()
    reaper.Main_OnCommand(40209, 0) -- Apply track/take FX to items as new take
end

-- =========================================================
-- MAIN
-- =========================================================

local function Main()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- DISABLE RIPPLE EDITING
    local ripple_state = reaper.GetToggleCommandState(41991)
    local ripple_all = reaper.GetToggleCommandState(41990)
    reaper.Main_OnCommand(40307, 0) 

    local tracks_to_cleanup = {}
    local items_to_normalize = {}

    -- SCAN TRACKS
    for i = 0, reaper.CountTracks(0) - 1 do
        local srcTrack = reaper.GetTrack(0, i)
        local _, srcName = reaper.GetSetMediaTrackInfo_String(srcTrack, "P_NAME", "", false)
        local normName = NormalizeKey(srcName)
        
        -- Identify Target using STRICT matching
        local matchedTargetName = nil
        for token, targetName in pairs(token_map) do
            if NameHasToken(normName, token) then
                matchedTargetName = targetName
                break
            end
        end

        if matchedTargetName then
            local destTrack = GetTrackByName(matchedTargetName)
            
            -- Safety: Don't move if source IS the destination
            if destTrack and srcTrack ~= destTrack then
                tracks_to_cleanup[srcTrack] = true

                -- ITERATE ITEMS (Backwards)
                local count = reaper.CountTrackMediaItems(srcTrack)
                for j = count - 1, 0, -1 do
                    local item = reaper.GetTrackMediaItem(srcTrack, j)
                    
                    if item then
                        -- 1. MOVE
                        reaper.MoveMediaItemToTrack(item, destTrack)
                        
                        -- 2. PROCESS (HH / Ride)
                        if type_copy_norm[matchedTargetName] then
                            local procTrackName = matchedTargetName .. " Processed"
                            local procTrack = GetTrackByName(procTrackName)
                            if procTrack then
                                local newItem = CopyItemToTrack(item, procTrack)
                                table.insert(items_to_normalize, newItem)
                            end

                        -- 3. PROCESS (Crash)
                        elseif type_bake_move[matchedTargetName] then
                            local procTrackName = matchedTargetName .. " Processed"
                            local procTrack = GetTrackByName(procTrackName)
                            
                            if procTrack then
                                local start_takes = reaper.CountTakes(item)
                                BakeFXOnItem(destTrack, item)
                                local end_takes = reaper.CountTakes(item)
                                
                                if end_takes > start_takes then
                                    local newItem = CopyItemToTrack(item, procTrack)
                                    
                                    -- Crop Processed Copy
                                    SelectOnlyItem(newItem)
                                    reaper.Main_OnCommand(40131, 0) -- Crop to active take
                                    table.insert(items_to_normalize, newItem)

                                    -- Revert Original
                                    SelectOnlyItem(item)
                                    reaper.Main_OnCommand(40130, 0) -- Delete active take
                                else
                                    -- Fail safe: do not delete original if bake failed
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- NORMALIZE
    if #items_to_normalize > 0 then
        UnselectAllItems()
        for _, it in ipairs(items_to_normalize) do
            if reaper.ValidatePtr(it, "MediaItem*") then
                reaper.SetMediaItemSelected(it, true)
            end
        end
        reaper.Main_OnCommand(40108, 0) -- Normalize to 0 dB
    end

    -- CLEANUP
    for track, _ in pairs(tracks_to_cleanup) do
        if reaper.ValidatePtr(track, "MediaTrack*") and not protected_tracks[track] then
            if reaper.CountTrackMediaItems(track) == 0 then
                reaper.DeleteTrack(track)
            end
        end
    end

    -- RESTORE RIPPLE
    if ripple_all == 1 then reaper.Main_OnCommand(41990, 0)
    elseif ripple_state == 1 then reaper.Main_OnCommand(41991, 0) end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Import Drums Strict", -1)
end

Main()