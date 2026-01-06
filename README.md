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
