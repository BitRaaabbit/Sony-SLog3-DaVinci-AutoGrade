# Development notes

## 2026-08-10 — project frame-rate preflight stop

An internal Resolve 20.3.2 Free diagnostic produced a complete ASCII-path log and traceback. The script successfully acquired `app:GetResolve()`, ProjectManager, and CurrentProject. It then read back:

- resolution width: requested 3840, actual 3840;
- resolution height: requested 2160, actual 2160;
- timeline frame rate: requested 50, actual 50;
- playback frame rate: requested 50 and 50.000, `SetSetting` returned false both times, actual remained 24.

The script stopped before MediaStorage, Unicode media-path testing, ImportMedia, Media Pool, timeline creation, SaveProject, ExportProject, or rendering. This proves that the media path and decoder were not involved in that failure.

The first failed implementation set Timeline FPS before Playback FPS. Resolve accepted the Timeline FPS change, then refused the Playback FPS change. A subsequent fresh-project test recorded untouched defaults of Playback 24, Timeline 24, and 1920×1080. `Project:SetSetting("timelinePlaybackFrameRate", value)` returned `false` for `"50"`, `"50.0"`, and `"50.000"`; every readback remained 24. The script stopped before resolution, color management, or media import.

The installed Resolve 20.3.2 scripting README explicitly enumerates `timelineFrameRate` for `Project:SetSetting` but does not enumerate `timelinePlaybackFrameRate`. The generic diagnostic therefore treats Playback FPS as a read-before-import gate, not as a value to brute-force. It can optionally apply an explicitly named Resolve Project Preset that has already been verified to establish the target Playback FPS; otherwise it stops and requires a manually preconfigured fresh project. Inconsistent projects are preserved as fault evidence.

## 2026-08-10 — internal object and logging

In the same installed Workspace Lua environment, `Resolve()` returned nil while `app:GetResolve()` returned a valid userdata. ProjectManager, CurrentProject, `OpenPage("edit")`, and `SaveProject()` succeeded.

Lua `io.open` failed on an existing Windows directory containing Chinese characters and reported `No such file or directory`. Logging, reports, traceback, state, runtime profile, and temporary DRP staging therefore use `%TEMP%\SonySLog3AutoGrade`. Media paths remain unchanged and are passed directly to Resolve for an explicit ImportMedia test.
