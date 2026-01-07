-- REAPER Script: Setup & Batch Render Audio to MIDI (Modular)
-- Toggle phases true/false in the configuration section below.

function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

-- =========================================================
-- PHASE CONTROL (SET THESE TO TRUE/FALSE)
-- =========================================================

local ENABLE_PHASE_SETUP    = true  -- Reset Vol, Mute/Unmute, Arm Transcription

-- =========================================================
-- CONFIGURATION
-- =========================================================

local target_track_name = "TRANSCRIPTION"

local active_tracks = {
    ["Snare"] = true,
    ["Kick"] = true,
    ["Toms"] = true,
    ["Crash Processed"] = true,
    ["Ride Processed"] = true,
    ["HH Processed"] = true
}

local silent_tracks = {
    ["Crash"] = true,
    ["Ride"]  = true,
    ["HH"]    = true,
    ["Song"]  = true,
    ["Drums"] = true
}

-- =========================================================
-- UTILITIES
-- =========================================================

function GetTrackByName(name)
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if trackName == name then return track end
    end
    return nil
end

function Main()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    reaper.ShowConsoleMsg("") -- Clear console

    local transcriptionTrack = GetTrackByName(target_track_name)
    if not transcriptionTrack then
        Msg("Error: '" .. target_track_name .. "' track not found.")
        return
    end

    -- =========================================================
    -- PHASE 0: PROJECT SETUP
    -- =========================================================
    if ENABLE_PHASE_SETUP then
        Msg("Running Phase 0: Setup...")
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            
            -- 1. RESET VOLUME TO 0dB
            reaper.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)

            -- 2. HANDLE "ACTIVE" TRACKS
            if active_tracks[name] then
                reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0) 
                reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 0) 
                reaper.SetMediaTrackInfo_Value(track, "I_FXEN", 1) 
            
            -- 3. HANDLE "SILENT" TRACKS
            elseif silent_tracks[name] then
                reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 1) 
                reaper.SetMediaTrackInfo_Value(track, "I_FXEN", 0) 
            
            -- 4. HANDLE TRANSCRIPTION TRACK
            elseif name == target_track_name then
                reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1) 
                reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0) 
            end
        end
        -- Force update so engine enables FX
        reaper.UpdateArrange()
    else
        Msg("Skipping Phase 0: Setup.")
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Setup & Render Audio to MIDI", -1)
end

Main()