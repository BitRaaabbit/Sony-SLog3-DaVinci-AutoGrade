# Development notes

## 2026-08-10 — project frame-rate preflight stop

An internal Resolve 20.3.2 Free diagnostic produced a complete ASCII-path log and traceback. The script successfully acquired `app:GetResolve()`, ProjectManager, and CurrentProject. It then read back:

- resolution width: requested 3840, actual 3840;
- resolution height: requested 2160, actual 2160;
- timeline frame rate: requested 50, actual 50;
- playback frame rate: requested 50 and 50.000, `SetSetting` returned false both times, actual remained 24.

The script stopped before MediaStorage, Unicode media-path testing, ImportMedia, Media Pool, timeline creation, SaveProject, ExportProject, or rendering. This proves that the media path and decoder were not involved in that failure.

The first failed implementation set Timeline FPS before Playback FPS. Resolve accepted the Timeline FPS change, then refused the Playback FPS change. A subsequent fresh-project test recorded untouched defaults of Playback 24, Timeline 24, and 1920×1080. `Project:SetSetting("timelinePlaybackFrameRate", value)` returned `false` for `"50"`, `"50.0"`, and `"50.000"`; every readback remained 24. The script stopped before resolution, color management, or media import.

The installed Resolve 20.3.2 scripting README explicitly enumerates `timelineFrameRate` for `Project:SetSetting` but does not enumerate `timelinePlaybackFrameRate`. A property returned by `Project:GetSetting()` must not be assumed writable through `Project:SetSetting()`. The compatibility boundary is now: human-verified Project Format preset → exact runtime `preset_name` → documented `Project:SetPreset()` → full Playback/Timeline/width/height readback → immediate stop on mismatch. Preset names are format-specific local configuration, never a hard-coded universal Sony default. Color management remains a separate scripted and verified stage. Inconsistent projects are preserved as fault evidence.

Runtime text is also not evidence that Resolve exposes the named preset to scripting. A failed exact `Project:SetPreset()` call led to the Project Preset discovery gate: query `Project:GetPresetList()` on the already open project, preserve its complete safely traversable structure in the log, extract only defensible name candidates, and require an exact match before creating another diagnostic project. Trimmed or case-insensitive matches never authorize selection.

## 2026-08-10 — internal object and logging

In the same installed Workspace Lua environment, `Resolve()` returned nil while `app:GetResolve()` returned a valid userdata. ProjectManager, CurrentProject, `OpenPage("edit")`, and `SaveProject()` succeeded.

Lua `io.open` failed on an existing Windows directory containing Chinese characters and reported `No such file or directory`. Logging, reports, traceback, state, runtime profile, and temporary DRP staging therefore use `%TEMP%\SonySLog3AutoGrade`. Media paths remain unchanged and are passed directly to Resolve for an explicit ImportMedia test.
