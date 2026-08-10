# Development notes

## 2026-08-10 — project frame-rate preflight stop

An internal Resolve 20.3.2 Free diagnostic produced a complete ASCII-path log and traceback. The script successfully acquired `app:GetResolve()`, ProjectManager, and CurrentProject. It then read back:

- resolution width: requested 3840, actual 3840;
- resolution height: requested 2160, actual 2160;
- timeline frame rate: requested 50, actual 50;
- playback frame rate: requested 50 and 50.000, `SetSetting` returned false both times, actual remained 24.

The script stopped before MediaStorage, Unicode media-path testing, ImportMedia, Media Pool, timeline creation, SaveProject, ExportProject, or rendering. This proves that the media path and decoder were not involved in that failure.

The first failed implementation set Timeline FPS before Playback FPS. Resolve accepted the Timeline FPS change, then refused the Playback FPS change. A subsequent fresh-project test recorded untouched defaults of Playback 24, Timeline 24, and 1920×1080. `Project:SetSetting("timelinePlaybackFrameRate", value)` returned `false` for `"50"`, `"50.0"`, and `"50.000"`; every readback remained 24. The script stopped before resolution, color management, or media import.

The installed Resolve 20.3.2 scripting README explicitly enumerates `timelineFrameRate` for `Project:SetSetting` but does not enumerate `timelinePlaybackFrameRate`. A property returned by `Project:GetSetting()` must not be assumed writable through `Project:SetSetting()`. The first compatibility attempt used a human-verified Project Format preset, an exact runtime `preset_name`, documented `Project:SetPreset()`, and full readback. Preset names were always format-specific local configuration, never a hard-coded universal Sony default. Color management remained a separate scripted and verified stage, and inconsistent projects were preserved as fault evidence.

Runtime text is also not evidence that Resolve exposes the named preset to scripting. A failed exact `Project:SetPreset()` call led to the Project Preset discovery gate: query `Project:GetPresetList()` on the already open project, preserve its complete safely traversable structure in the log, extract only defensible name candidates, and require an exact match before creating another diagnostic project. Trimmed or case-insensitive matches never authorize selection.

The local 4K50 preset was not visible in the actual `Project:GetPresetList()` result, so the primary compatibility strategy moved to a private blank DRP. The installed official API documents `ProjectManager.ExportProject(projectName, filePath, withStillsAndLUTs=True)` and `ProjectManager.ImportProject(filePath, projectName=None)`. Template Capture validates an untouched empty project and calls `ExportProject(..., false)` without overwrite. Diagnostic imports the DRP under a unique name, repeats Project Format and blank-state validation, then configures color management separately. The exact-preset path is retained only for presets demonstrably visible to the API.

## 2026-08-10 — internal object and logging

In the same installed Workspace Lua environment, `Resolve()` returned nil while `app:GetResolve()` returned a valid userdata. ProjectManager, CurrentProject, `OpenPage("edit")`, and `SaveProject()` succeeded.

Lua `io.open` failed on an existing Windows directory containing Chinese characters and reported `No such file or directory`. Logging, reports, traceback, state, runtime profile, and temporary DRP staging therefore use `%TEMP%\SonySLog3AutoGrade`. Media paths remain unchanged and are passed directly to Resolve for an explicit ImportMedia test.

## 2026-08-11 — Resolve Lua collection metadata

The first blank-template capture stopped because a generic `pairs()` counter reported one entry each for `Folder:GetClipList()`, `Folder:GetSubFolderList()`, and `Project:GetRenderJobList()` while the Resolve GUI showed no media, subfolders, or render jobs. Resolve/Fusion's Lua bridge can expose internal collection metadata as top-level table keys, so the number of `pairs()` entries is not the number of real Resolve objects. Capture and Diagnostic now log every safe top-level key/type/value for evidence, then use list sequence semantics and validate each actual item type. No hard-coded subtraction is permitted.

## 2026-08-11 — effective input policy

The verified DRP diagnostic passed 4K50, RCM, final settings, Unicode-path import, and exact one-source Media Pool validation, then found that `MediaPoolItem:GetClipProperty("Input Color Space")` returned an empty string. The installed official README documents generic clip-property access, explicitly warns that some properties may be read-only or context-disabled, and does not guarantee Input Color Space as writable. Diagnostic no longer attempts `SetClipProperty` aliases. It distinguishes an explicit clip match, a high-confidence verified project default for homogeneous metadata, and an explicit conflict that must stop.
