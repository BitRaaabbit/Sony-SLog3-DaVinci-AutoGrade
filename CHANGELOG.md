# Changelog

## Unreleased — generic Sony S-Log3 workflow

### Changed

- Replaced the camera-specific layout with a template-capture utility, one diagnostic script, and one gated AutoGrade runner.
- Moved resolution, playback/timeline FPS, paths, project name, manifests, and authorization into a private runtime profile.
- Removed the old V2B values as production defaults. The historical values (Contrast 1.120, Pivot 0.440, Color Boost 12, Saturation 54, Highlights -8) remain regression context only.
- Added the Neutral Safe test-candidate policy without claiming permanent look parameters.
- Added an Original Log → RCM Only → Neutral Safe → high-quality master → delivery codec display/LED diagnostic chain.
- Added the private blank-DRP bootstrap as the recommended Project Format compatibility path; the exact-preset path remains optional.
- Added an explicit `ORIGINAL_SOURCE_MEDIA` → `RESOLVE_WORKING_MEDIA` runtime mapping so decode-compatible mezzanine files cannot replace or redefine immutable camera metadata.

### Fixed

- Internal Resolve Free scripts now use the empirically verified `app:GetResolve()` path.
- Logging now initializes under `%TEMP%\SonySLog3AutoGrade` with emergency fallback, `xpcall`, traceback, and stage markers.
- Fresh-project testing proved that `timelinePlaybackFrameRate` is readable but not writable through `Project:SetSetting()` in Resolve 20.3.2 Free on Windows; Project Format now uses a verified private blank DRP by default and full readback after import.
- Added a Project Preset discovery gate: log the complete safely traversable `Project:GetPresetList()` result and require an exact visible preset name before creating a fresh diagnostic project or calling `SetPreset()`.
- Added strict blank-template capture and import gates using the documented `ExportProject(projectName, filePath, false)` and `ImportProject(filePath, projectName)` APIs, with full format readback and collision refusal.
- Added a three-state effective input policy: explicit clip match, verified homogeneous project default when clip Input Color Space is unavailable, and mandatory stop on any explicit conflict. Undocumented per-clip Input Color Space writes were removed.
- Added a tightly gated recovery path for an exact one-clip diagnostic failure state, accepting either zero timelines or one exact validated diagnostic timeline, so capability fixes do not require another DRP import.
- Replaced raw Timeline bridge-table length checks with raw diagnostics plus validated TimelineItem traversal, exact MediaPoolItem source verification, and safe reuse of one already-created diagnostic timeline.
- Classified root MediaPoolItems as file-backed source, expected Timeline item, or unexpected object so a Timeline no longer inflates source-media count; added full property diagnostics and exact path/name gates.
- Unicode media paths are passed to Resolve APIs while Lua file logs/config are staged at ASCII-only paths.
- Added `UNSUPPORTED_NATIVE_VIDEO_DECODE`, `COMPATIBILITY_TRANSCODE_REQUIRED`, `FULL_TO_LIMITED_NORMALIZATION`, and `SIGNAL_EQUIVALENCE_GATE` capability rules. Compatibility range representation is explicitly separated from creative grading and colorspace conversion.
- Added a fail-closed working-media decode gate: exact mapped import, available Resolution/FPS/Video Codec evidence, one validated Video Track TimelineItem, and exact TimelineItem → MediaPoolItem → working-path verification are required for `SUCCESS_DNXHR_COMPATIBILITY_READY`.

### Safety

- Mixed or unknown batch metadata stops preflight.
- Source overwrite and output overwrite remain prohibited.
- AutoGrade requires a human-approved reference grade plus explicit test/batch and render-start authorization.

## v0.1.0 legacy

The original camera-specific implementation is preserved without history rewriting at tag `v0.1.0-fx3-legacy`.
