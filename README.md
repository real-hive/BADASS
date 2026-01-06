# BADASS
Big Automated Drums And Stuff System is a pipeline to automate authoring for rhythm games
This is a project for automating large parts of the authoring process for instruments-based rhythm games, starting from drums. 
Requirements:
- Cockos Reaper 7 (or any version supporting Lua and the plug-ins used)
- Python 2.7+

It's split in different scripts and sections that represent steps in the automation process.

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
