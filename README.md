# BADASS: Big Automated Drums And Stuff System
**BADASS** is a pipeline designed to automate large parts of the authoring process for instrument-based rhythm games, starting with drums. It takes raw audio stems and converts them into game-ready MIDI maps (`PART DRUMS`) using a combination of Lua scripts and custom JSFX plugins.

## 📋 Prerequisites

* **Software:** Cockos Reaper 7 (or any version supporting Lua and the required plugins).
* **Template:** `Automatic Mapping.RPP` (The project template with pre-routed tracks).
* **Scripts:**
    * `prep_automation_drums_tracks.lua`
    * `fix_automated_drums.lua`
    * (both loaded with the **Action List** > **New Action** > **Load...**
* **Plugins:** `Audio To MIDI Drum Trigger (True Peak Logic)`

---

# 🥁 Quickstart: Zero to Transcribed (BADASS Pipeline, speedrun, no questions asked)

## 🚀 Phase 1: Audio Preparation (Outside Reaper)

### 1. Get Your Stems
You need isolated drum stems. A simple "Drums vs Song" split is not enough. Use a high-quality stem separator (e.g., using the latest Ensemble models in MVSEP) to extract the following specific tracks:
* **Kick**
* **Snare**
* **Hi-Hat**
* **Ride**
* **Crash**
* **Toms**

### 2. File Naming (Strict Rules)
The automation script relies on strict pattern matching. Your filenames **must** contain specific keywords, either delimited by dashes/underscores or wrapped in them.
**Required Keywords:** `kick`, `snare`, `toms`, `crash`, `ride`, `hh`, `drums`, `residual` (or `other`).

| Filename Example | Status | Reason |
| :--- | :--- | :--- |
| `01-Snare-Top.wav` | ✅ **Good** | Delimited by `-` |
| `Song_Kick_01.wav` | ✅ **Good** | Delimited by `_` |
| `Ride-Main.wav` | ✅ **Good** | Delimited |
| `MySnare.wav` | ❌ **Bad** | No delimiter |
| `KickDrum.wav` | ❌ **Bad** | No delimiter |


## 🎛️ Phase 2: Import & Organization (In Reaper)

### 1. Open the Template
Open `Automatic Mapping.RPP`.

### 2. Drag & Drop
Drag all your prepared stems into the project, placing them **at the bottom** of the track list (below existing tracks).

### 3. Run the Prep Script
* Open the **Action List** (`?` key).
* Run: **`Script: prep_automation_drums_tracks.lua`**.
    * *Alert:* The script will ask for confirmation to delete tracks **twice**. Click **Confirm/Yes**.

### 4. Alignment
Once processed, ensure your audio is aligned with the project grid. You can now import your existing tempo map or create one to match the audio.


## ⚡ Phase 3: MIDI Generation (The Trigger)

### 1. Record to MIDI
* **Record** the song from start to finish.
* 
### 2. Run the Processor Script
* Open Action List and run: **`Script: fix_automated_drums.lua`**.
* Click **Run Process**.

## ✅ Final Result

Check the **`PART DRUMS`** track. It now contains a quantized, cleaned, and mapped drum chart ready for final human review.

```text
[ SUMMARY FLOWCHART ]

[ Raw Stems ] 
      │ (Renamed: Kick_01.wav, etc.)
      ▼
[ Drag to Reaper ]
      │
      ▼
[ Run: prep_automation_drums_tracks.lua ] ──► (Moves tracks, Normalizes Cymbals)
      │
      ▼
[ JSFX Triggers ] ──────────────────────────► (Detects Hits via True Peak)
      │
      ▼
[ Record to "TRANSCRIPTION" ]
      │
      ▼
[ Run: Drum Transcription Processor.lua ] ──► (Quantizes, Dedupes, Remaps)
      │
      ▼
[ ✅ PART DRUMS READY ]
```

---

# Audio Importer (Drums only for now)

## 1. Overview
This script automates the organization, processing, and cleanup of imported drum multitracks in Cockos Reaper.

### Key Features
* **Strict Token Matching:** Prevents false positives. A track named `SnareTop` will be ignored; only explicitly delimited names like `Snare_Top`, `01-Snare`, or `Song_Snare_01` are processed.
* **Immediate Processing:** items are moved and processed the millisecond they are identified, preventing Reaper from losing track of item IDs during batch imports.
* **Safe "Bake" Logic:** When processing Crash tracks, the script verifies that the FX render was successful (take count increased) before reverting the original track.
* **Ripple Edit Protection:** Temporarily disables Ripple Editing to prevent accidental shifts on other tracks during the move process.

---

## 2. Requirements & Setup

### A. Destination Tracks
The Automatic Mapping.RPP project already contains tracks with the exact names defined in the configuration:
* `Kick`, `Snare`, `Toms`
* `HH`, `Ride`, `Crash`
* `HH Processed`, `Ride Processed`, `Crash Processed` (for processed copies)

### B. Naming Convention (Strict Mode)
The script ignores loose matches to prevent accidents. The instrument name must be **delimited** by non-alphanumeric characters (underscores or dashes) or be at the absolute start/end of the filename.

| Imported File Name | Status | Reason |
| :--- | :--- | :--- |
| `01-Snare-Top.wav` | ✅ **Match** | Delimited by `-` |
| `Song_Snare_01.wav` | ✅ **Match** | Delimited by `_` |
| `Snare_Main.wav` | ✅ **Match** | Starts with `Snare_` |
| `MySnare.wav` | ❌ **Ignore** | No delimiter |
| `SnareBus.wav` | ❌ **Ignore** | No delimiter |

---

## 3. Workflow Logic

The script follows this logical flow for every track in the project:

```text
[ START SCRIPT ]
       │
       ▼
[ DISABLE RIPPLE EDITING ]
       │
       ▼
[ SCAN SOURCE TRACKS ]
       │
       ├─(No Match)─────────────► [ IGNORE TRACK ]
       │
       ▼
( Match Found ) ──► [ MOVE ITEM TO DESTINATION ]
                                │
                                ▼
                       [ CHECK DRUM TYPE ]
       ┌────────────────────────┼─────────────────────────┐
       ▼                        ▼                         ▼
  ( Standard )             ( HH / Ride )               ( Crash )
  Snare/Kick/Toms               │                         │
       │                        │                         ▼
       │                        │                 [ APPLY TRACK FX ]
       │                        │                (Bake as new take)
       │                        │                         │
       │                        ▼                         ▼
       │               [ COPY TO "PROCESSED" ]    < Bake Success? >
       │                        │                    │         │
       │                        ▼               (Yes)│         │(No)
       │                 [ NORMALIZE ]               ▼         ▼
       │                        │             [ COPY BAKED ] [ KEEP ]
       │                        │             [ TO PROCESS ] [ RAW  ]
       │                        │                    │
       │                        │                    ▼
       │                        │              [ REVERT ORIG ]
       │                        │              (Clean Backup)
       ▼                        ▼                    │
[ CLEANUP: DELETE EMPTY SOURCE TRACKS ] ◄────────────┘
       │
       ▼
[ RESTORE RIPPLE STATE ]
```

# Automated Drum Mapping Post-processing

This part of the process is designed to automate the cleaning, quantization, and re-mapping of raw MIDI drum transcriptions.

It bridges the gap between raw transcription (e.g., from audio-to-MIDI tools) and production-ready drum parts by applying smart quantization logic, removing artifacts, and mapping specific notes to a destination track.

## 🚀 Features

* **GUI Control:** Simple interface to toggle specific post-processing rules.
* **Safety First:** Automatically creates a backup of your source track (`TRANSCRIPTION RAW`) before processing.
* **System Optimization:** Disables FX on all tracks to ensure smooth processing speed.
* **Smart Deduplication:** Removes double-triggered crash cymbals (Note 49) based on a specific time threshold.
* **Hybrid Quantization:** Intelligently detects if a note is closer to a **Straight 1/16** or **Triplet 1/16** grid and snaps accordingly.
* **Legato Processing:** Automatically adjusts note lengths to prevent overlaps.
* **Auto-Mapping:** Copies and transforms notes from the source track to a destination `PART DRUMS` track.

---

## ⚙️ Installation

1.  Download the `.lua` script.
2.  Open REAPER.
3.  Go to **Actions** -> **Show Action List**.
4.  Click **New Action** -> **Load ReaScript**.
5.  Select the downloaded file.

---

## 🛠️ Usage
* Launch the script from the Action List.
**The GUI:**
    * A window will appear. Select your options (see *Logic Details* below).
    * Click **Run Process**.
---

## 🧠 Logic & Algorithms

This script performs several passes over the MIDI data. Here is the exact logic applied:

### 1. Deduplication (Note 49)
Raw transcriptions often accidentally double-trigger crash cymbals.
* **Target:** Note 49.
* **Threshold:** `1/16th note + 1/32nd note` duration.
* **Action:** If two Note 49s occur within this window, the second one is deleted.

### 2. Conditional Shifting (Notes 42 & 49)
Hi-Hats (42) and Crashes (49) have a very loose attack. In part because of their inherent wave forms, in part because stem splitting might end up chewing up a portion of the shape. For this reason we compensate moving their notes back a bit: hi-hats require less movement, while crashes have an even looser attack. We don't follow this process only if the note is already seemingly on grid: this can happen if the attack is actually cleaner or in case of consecutive hits.
* **Logic:** The script calculates the distance of the note to the nearest **Straight 1/16** vs. the nearest **Triplet 1/16**.
* **Action:** If the note is closer to the Triplet grid, it is pre-shifted backwards slightly (1/64 or 1/32) to ensure the subsequent quantization step catches it correctly.

### 3. Hybrid Quantization
The script does not force a single grid type, to avoid mangling triplets. However it doesn't go as fine as 1/32nd notes because transcription is likely to not being able to discern them and in turn we would be stuck with a number of notes off by 1/32nd. It iterates through every note:
* **Compare:** Distance to Straight 1/16 vs. Distance to Triplet 1/16.
* **Snap:** The note is moved to whichever grid point is closer.

### 4. Overlap Filtering (Hi-Hats)
*Controlled via the GUI Checkbox: "Remove 98 if overlapping 99"*
This cleans up articulations where a "Open Hi-Hat" might clash with a "Snare/Rim". Sometimes the stem splitter correctly recognizes the ping of the ride but it confuses its wash with that of a hi-hat. So any hi-hat and ride note couple gets reduced to a ride hit. This is optional in case there are genuine tracks in which ride and hi-hat sound at the same time.
* **Rule:** Delete Note 98 (Hi-Hat) **IF**:
    * Note 99 (Snare/Rim) exists at the same position.
    * **AND** Note 111 (Specific Rim check) does **NOT** exist.

---

## 🎹 MIDI Mapping Table

The script copies notes from `TRANSCRIPTION` to `PART DRUMS` and re-pitches them according to this table:

| Source Pitch (Input) | Destination Pitch (Output) | Instrument / Articulation |
| :--- | :--- | :--- |
| **35** | **96** | Kick |
| **38** | **97** | Snare |
| **42** | **98** | Closed Hi-Hat |
| **47** | **99** & **111** | Toms (With pro note marker) |
| **49** | **100** | Crash Cymbal |
| **51** | **99** | Ride |

---

## ⚠️ Requirements

* **REAPER:** Tested on REAPER 6.x and 7.x.

# Audio To MIDI Drum Trigger (True Peak Logic)

## Overview
This version of the standard JSFX Drum Trigger includes a **True Peak analysis algorithm**. Unlike standard triggers that fire solely based on a fixed volume threshold, this mod analyzes the *context* of the audio. It compares the incoming transient against the average volume of the preceding audio (the "Lookback" window) to distinguish genuine drum hits from bleed or sustain.

## New Mod Parameters

### 1. Transient Lookback (ms)
* **Slider 9**
* **Range:** 0ms to 200ms

This defines the "Context Window" preceding a potential hit. When the signal crosses the open threshold, the plugin looks backwards into a memory buffer for the duration set here. It calculates the average volume of that previous audio.

* **Higher Values (e.g., 50-100ms):** The plugin compares the hit against the general "noise floor" or room tone. This is more stable for isolated tracks.
* **Lower Values (e.g., 10-20ms):** The plugin compares the hit against the immediate previous audio. This is better for fast rolls where the sustain of the previous hit might mask the attack of the next one.

### 2. Transient Sensitivity (Ratio)
* **Slider 10**
* **Range:** 1.0 to 100.0

This acts as a "Contrast Control". It sets the required ratio between the **Detected Peak** and the **Lookback Average**.

$$\text{Ratio} = \frac{\text{Current Peak Volume}}{\text{Average Lookback Volume}}$$

* **Example (Ratio 3.0):** The transient peak must be **3 times louder** than the average volume of the lookback window to trigger a MIDI note.
* **Tuning:**
    * **Increase** this value to eliminate bleed (e.g., snare bleed on a kick track).
    * **Decrease** this value if ghost notes or soft hits are being ignored.



### 3. Detection Mode
* **Slider 11**
* **Options:** Average Window (Diluted), True Peak (Accurate)

This changes how the plugin calculates the "numerator" of the ratio formula.

* **Mode 0: Average Window (Diluted)**
    * *Logic:* Uses `Hit Volume * 0.5`.
    * *Behavior:* This mimics older "RMS" style detection. It is less sensitive and smoother. Use this for messy recordings where the transient is not very sharp.
* **Mode 1: True Peak (Accurate)**
    * *Logic:* Uses the raw `Hit Volume`.
    * *Behavior:* This uses the absolute loudest sample found within the 4ms attack window. It is highly accurate and aggressive. This is the recommended mode for modern, punchy drums.

---

## The "True Peak" Workflow

Unlike standard triggers that fire the instant a threshold is crossed, this plugin adds a smart logic phase:

1.  **Gate Open:** Signal crosses the `Open Threshold` (Slider 1).
2.  **Wait Phase:** The plugin waits for **4ms** (hardcoded `attack_ms`) to scan for the true maximum peak of the transient.
3.  **Context Check:** It calculates the average volume of the `Lookback` window.
4.  **Decision:**
    * If `(Peak / Lookback) > Sensitivity`, the Note is fired.
    * If the ratio is too low (meaning the volume rose, but not sharply enough relative to the background), the trigger is rejected as "Bleed/Sustain".

## Debugging

The plugin features an on-screen Graphics Overlay (`@gfx`) that displays the statistics of the last 10 detected hits:

* **MBT:** Measure.Beat.Time location.
* **Jump:** The calculated ratio (e.g., `3.5x`).
* **Hit:** The volume of the peak.
* **Tail:** The average volume of the lookback window.

*Use these numbers to fine-tune your Sensitivity Ratio slider.*
