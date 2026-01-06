-- REAPER Script: Backup, Process Transcription, Copy to PART DRUMS (with GUI)
-- 1. GUI Options
-- 2. Disables FX
-- 3. Backs up "TRANSCRIPTION"
-- 4. [NEW] Deduplicate Note 49 (Threshold: 1/16 + 1/32)
-- 5. Conditional Shift (Notes 42 & 49)
-- 6. Quantizes (1/16 Straight vs Triplet)
-- 7. Global Lengths & Copy to PART DRUMS
-- 8. [Optional] Filter Note 98 on Overlaps

local script_title = "Drum Transcription Processor"

-- GUI State
local gui = {
    opt_remove_hh = true, -- Default state
    w = 320,
    h = 100
}

function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

-- ========================================================
-- LOGIC: FILTER NOTE 98 (Post-Process)
-- ========================================================
function FilterHiHats(take)
    local _, noteCount = reaper.MIDI_CountEvts(take)
    local notes = {}
    for i = 0, noteCount - 1 do
        local _, sel, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        table.insert(notes, {
            index = i,
            start = startppq,
            pitch = pitch
        })
    end

    local tolerance = 5 
    local events_by_pos = {}
    
    for _, n in ipairs(notes) do
        local found_bucket = false
        for pos, bucket in pairs(events_by_pos) do
            if math.abs(n.start - pos) <= tolerance then
                table.insert(bucket, n)
                found_bucket = true
                break
            end
        end
        if not found_bucket then
            events_by_pos[n.start] = {n}
        end
    end

    local notes_to_delete = {}
    
    for _, bucket in pairs(events_by_pos) do
        local hh_note = nil   -- Note 98
        local has_99 = false  -- Snare/Rim
        local has_111 = false -- Specific Rim check
        
        for _, n in ipairs(bucket) do
            if n.pitch == 98 then hh_note = n end
            if n.pitch == 99 then has_99 = true end
            if n.pitch == 111 then has_111 = true end
        end
        
        -- Remove 98 if (99 exists) AND (111 does NOT exist)
        if hh_note and has_99 and not has_111 then
            table.insert(notes_to_delete, hh_note)
        end
    end

    if #notes_to_delete > 0 then
        table.sort(notes_to_delete, function(a,b) return a.index > b.index end)
        for _, n in ipairs(notes_to_delete) do
            reaper.MIDI_DeleteNote(take, n.index)
        end
        Msg("Filtered " .. #notes_to_delete .. " Hi-Hat (98) notes based on overlap rules.")
    end
end

-- ========================================================
-- MAIN PROCESS
-- ========================================================
function ProcessTranscription(remove_hh_flag)
    reaper.Undo_BeginBlock()

    -- 1. DISABLE ALL FX
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        reaper.SetMediaTrackInfo_Value(tr, "I_FXEN", 0)
    end
    local master = reaper.GetMasterTrack(0)
    reaper.SetMediaTrackInfo_Value(master, "I_FXEN", 0)
    Msg("All FX disabled.")

    -- 2. Find Source Track
    local srcTrack = nil
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if name == "TRANSCRIPTION" then
            srcTrack = tr
            break
        end
    end

    if not srcTrack then Msg("Error: Track 'TRANSCRIPTION' not found."); return end

    -- 3. Create Backup
    reaper.Main_OnCommand(40297, 0) -- Unselect all
    reaper.SetTrackSelected(srcTrack, true)
    reaper.Main_OnCommand(40062, 0) -- Duplicate
    local backupTrack = reaper.GetSelectedTrack(0, 0)
    if backupTrack then
        reaper.GetSetMediaTrackInfo_String(backupTrack, "P_NAME", "TRANSCRIPTION RAW", true)
    end
    reaper.SetTrackSelected(backupTrack, false)

    -- 4. Prepare Source Data
    local srcItem = reaper.GetTrackMediaItem(srcTrack, 0)
    if not srcItem then Msg("No item on TRANSCRIPTION."); return end
    local srcTake = reaper.GetActiveTake(srcItem)
    if not srcTake or not reaper.TakeIsMIDI(srcTake) then Msg("Take is not MIDI."); return end

    -- Calculate PPQ & Grid
    local itemStartQN = reaper.TimeMap2_timeToQN(0, reaper.GetMediaItemInfo_Value(srcItem, "D_POSITION"))
    local startTick = reaper.MIDI_GetPPQPosFromProjQN(srcTake, itemStartQN)
    local endTick = reaper.MIDI_GetPPQPosFromProjQN(srcTake, itemStartQN + 1)
    local SOURCE_PPQ = math.floor(endTick - startTick + 0.5)

    -- Grids
    local TICK_1_16  = SOURCE_PPQ / 4
    local TICK_1_16T = SOURCE_PPQ / 6
    local TICK_1_32  = SOURCE_PPQ / 8
    local TICK_1_64  = SOURCE_PPQ / 16

    local _, noteCount = reaper.MIDI_CountEvts(srcTake)
    local notes = {}
    for i = 0, noteCount - 1 do
        local _, sel, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(srcTake, i)
        table.insert(notes, {
            index = i, sel = sel, muted = muted,
            start = startppq, len = endppq - startppq,
            chan = chan, pitch = pitch, vel = vel, delete = false
        })
    end

    -- Ensure sorted order for deduplication logic
    table.sort(notes, function(a,b) return a.start < b.start end)

    -------------------------------------------------------
    -- LOGIC STEP B: Deduplicate Note 49
    -- Rule: If consecutive 49s are closer than 1/16 + 1/32, remove second.
    -------------------------------------------------------
    local dedup_threshold = TICK_1_16 + TICK_1_32
    local last_49_start = -math.huge -- Start far in the past
    local dedup_count = 0

    for i = 1, #notes do
        local n = notes[i]
        if not n.delete and n.pitch == 49 then
            if (n.start - last_49_start) < dedup_threshold then
                n.delete = true
                dedup_count = dedup_count + 1
            else
                last_49_start = n.start -- Update the last valid position
            end
        end
    end
    
    if dedup_count > 0 then
        Msg("Deduplicated " .. dedup_count .. " instances of Note 49.")
    end

    -------------------------------------------------------
    -- LOGIC STEP C: Conditional Shift (Notes 42 & 49)
    -------------------------------------------------------
    for _, n in ipairs(notes) do
        if not n.delete and (n.pitch == 42 or n.pitch == 49) then
            local pos = n.start
            
            -- 1. Check Distance to Straight 1/16
            local rem_s = pos % TICK_1_16
            local snap_s = pos - rem_s
            if rem_s >= (TICK_1_16 / 2) then snap_s = snap_s + TICK_1_16 end
            local dist_s = math.abs(pos - snap_s)
            
            -- 2. Check Distance to Triplet 1/16
            local rem_t = pos % TICK_1_16T
            local snap_t = pos - rem_t
            if rem_t >= (TICK_1_16T / 2) then snap_t = snap_t + TICK_1_16T end
            local dist_t = math.abs(pos - snap_t)
            
            -- 3. Logic: If closer to Triplet (dist_s > dist_t), assume it needs shifting.
            if dist_s > dist_t then
                if n.pitch == 42 then
                    n.start = n.start - TICK_1_64
                elseif n.pitch == 49 then
                    n.start = n.start - TICK_1_32
                end
                
                if n.start < 0 then n.start = 0 end
            end
        end
    end

    -------------------------------------------------------
    -- LOGIC STEP D: Quantize (1/16 Straight vs 1/16 Triplet)
    -------------------------------------------------------
    for _, n in ipairs(notes) do
        if not n.delete then
            local pos = n.start
            
            local rem_s = pos % TICK_1_16
            local snap_s = pos - rem_s
            if rem_s >= (TICK_1_16 / 2) then snap_s = snap_s + TICK_1_16 end
            
            local rem_t = pos % TICK_1_16T
            local snap_t = pos - rem_t
            if rem_t >= (TICK_1_16T / 2) then snap_t = snap_t + TICK_1_16T end
            
            if math.abs(pos - snap_t) < math.abs(pos - snap_s) then
                n.start = snap_t
            else
                n.start = snap_s
            end
        end
    end

    -------------------------------------------------------
    -- LOGIC STEP E: Adjust Lengths (Global No-Overlap)
    -------------------------------------------------------
    -- Notes are already sorted from Dedupe step, but re-sort just in case shifting changed order
    table.sort(notes, function(a,b) return a.start < b.start end)

    local length_options = {TICK_1_16, TICK_1_16T, TICK_1_32}

    for i = 1, #notes do
        local n = notes[i]
        if not n.delete then
            local dist_to_next = math.huge
            
            for j = i + 1, #notes do
                local next_n = notes[j]
                if not next_n.delete and next_n.start > n.start then
                    dist_to_next = next_n.start - n.start
                    break 
                end
            end
            
            local chosen_len = nil
            for _, len_opt in ipairs(length_options) do
                if len_opt <= dist_to_next then
                    chosen_len = len_opt
                    break 
                end
            end
            if chosen_len then n.len = chosen_len end
        end
    end

    -------------------------------------------------------
    -- COMMIT TO SOURCE
    -------------------------------------------------------
    local i = noteCount - 1
    while i >= 0 do reaper.MIDI_DeleteNote(srcTake, i); i = i - 1 end
    for _, n in ipairs(notes) do
        if not n.delete then
            reaper.MIDI_InsertNote(srcTake, n.sel, n.muted, n.start, n.start + n.len, n.chan, n.pitch, n.vel, false)
        end
    end
    reaper.MIDI_Sort(srcTake)

    -------------------------------------------------------
    -- COPY TO PART DRUMS
    -------------------------------------------------------
    local destTrack = nil
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if name == "PART DRUMS" then destTrack = tr; break end
    end
    if not destTrack then
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        destTrack = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
        reaper.GetSetMediaTrackInfo_String(destTrack, "P_NAME", "PART DRUMS", true)
    end

    local destItem = reaper.GetTrackMediaItem(destTrack, 0)
    if not destItem then
        local sPos = reaper.GetMediaItemInfo_Value(srcItem, "D_POSITION")
        local sLen = reaper.GetMediaItemInfo_Value(srcItem, "D_LENGTH")
        destItem = reaper.CreateNewMIDIItemInProj(destTrack, sPos, sPos + sLen)
    end

    local destTake = reaper.GetActiveTake(destItem)
    if destTake and reaper.TakeIsMIDI(destTake) then
        local _, dCount = reaper.MIDI_CountEvts(destTake)
        local d = dCount - 1
        while d >= 0 do reaper.MIDI_DeleteNote(destTake, d); d = d - 1 end

        local mapping = {
            [35] = {96}, [38] = {97}, [42] = {98},
            [47] = {99, 111}, [49] = {100}, [51] = {99}
        }

        local copyCount = 0
        for _, n in ipairs(notes) do
            if not n.delete and mapping[n.pitch] then
                local sQN = reaper.MIDI_GetProjQNFromPPQPos(srcTake, n.start)
                local eQN = reaper.MIDI_GetProjQNFromPPQPos(srcTake, n.start + n.len)
                local dStart = reaper.MIDI_GetPPQPosFromProjQN(destTake, sQN)
                local dEnd = reaper.MIDI_GetPPQPosFromProjQN(destTake, eQN)
                
                for _, newPitch in ipairs(mapping[n.pitch]) do
                    reaper.MIDI_InsertNote(destTake, n.sel, n.muted, dStart, dEnd, 0, newPitch, n.vel, false)
                    copyCount = copyCount + 1
                end
            end
        end
        reaper.MIDI_Sort(destTake)
        Msg("Copied " .. copyCount .. " notes to PART DRUMS.")

        -- *** APPLY GUI OPTION HERE ***
        if remove_hh_flag then
            FilterHiHats(destTake)
        end
    end

    reaper.Undo_EndBlock("Process Drums (Unified Logic)", -1)
    reaper.UpdateArrange()
end

-- ========================================================
-- SIMPLE GUI
-- ========================================================
function DrawGUI()
    gfx.set(1, 1, 1, 1) -- White
    gfx.setfont(1, "Arial", 16)
    
    -- Title
    gfx.x = 10; gfx.y = 10
    gfx.drawstr(script_title)
    
    -- Checkbox Logic
    gfx.x = 10; gfx.y = 40
    local char = gui.opt_remove_hh and "[x]" or "[ ]"
    gfx.drawstr(char .. " Remove 98 if overlapping 99 (except 111)")
    
    -- Checkbox Click Area
    if gfx.mouse_cap == 1 and gfx.mouse_x > 10 and gfx.mouse_x < 300 and gfx.mouse_y > 35 and gfx.mouse_y < 55 then
        gui.opt_remove_hh = not gui.opt_remove_hh
        -- Simple debounce
        local start = reaper.time_precise()
        while reaper.time_precise() - start < 0.15 do end
    end
    
    -- Button
    gfx.set(0.3, 0.8, 0.3, 1) -- Greenish
    gfx.rect(10, 65, 120, 25, 1)
    gfx.set(0, 0, 0, 1) -- Black Text
    gfx.x = 25; gfx.y = 70
    gfx.drawstr("Run Process")
    
    -- Button Click Logic
    if gfx.mouse_cap == 1 and gfx.mouse_x > 10 and gfx.mouse_x < 130 and gfx.mouse_y > 65 and gfx.mouse_y < 90 then
        -- Run the main function
        ProcessTranscription(gui.opt_remove_hh)
        gfx.quit() -- Close GUI
        return
    end

    -- Loop
    if gfx.getchar() >= 0 then
        reaper.defer(DrawGUI)
    end
end

-- Init
gfx.init(script_title, gui.w, gui.h)
DrawGUI()