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
- Split compatibility validation into external preflight authority and Resolve runtime validation. A private hash-bound attestation now proves original/working identity and signal equivalence; Resolve imports only working media and never uses MediaStorage enumeration as original-source authority.
- Separated stable launcher identity from formal Diagnostic logic identity so logic commits can be deployed without creating another Workspace menu entry.

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
- Removed the invalid requirement that Resolve enumerate original camera media before a compatibility import. Unicode original-path existence is now owned by external filesystem/hash/ffprobe preflight and bound to runtime evidence.
- Verified the complete compatibility path on Resolve 20.3.2 Free for a generic 10-bit 4:2:2 AVC source: hash-bound external evidence, signal-equivalent DNxHR HQX working media, exact import, valid video properties, one real Video Track, one exact TimelineItem, project save, and Edit-page handoff all passed.
- Documented that the public API does not expose native primary-control setters/readback for Contrast, Pivot, Color Boost, Highlights, Temperature, or Tint. A color test must stop rather than approximate those controls with CDL or undocumented property names when reliable native UI automation is unavailable.
- Adopted human-approved Reference TimelineItem → official Still/DRX export → SHA-256-pinned DRX → `ApplyGradeFromDRX()` as the immutable primary-grade architecture. Added Reference Prep for one clean RCM-only master timeline and one untouched Color Page seed; `CopyGrades()` remains a same-project copy/cross-check path.
- Separated render format display names from API format IDs. Reference Prep now raw-dumps both format/codec bridge collections, proves the local display-name→ID mapping, requires exact codec SET/readback, safely resumes previously reset A/B timelines, and gates the Color-page handoff on a completed render plus ffprobe/hash postflight.
- Replaced brittle reconstruction of master render settings with a human-verified immutable Render Preset. A dedicated internal Capture Utility uses `Project:SaveAsNewRenderPreset()`, proves exact visibility, exports through `Resolve:ExportRenderPreset()`, and records SHA-256; Reference Prep uses `Project:LoadRenderPreset()` and overrides only the three documented job fields.
- Made DRX artifact discovery suffix-safe by validating the exact pre/post export snapshot delta, then pinning the actual Resolve-generated filename, size, and SHA-256. Recovery of an already completed export requires matching log time and a unique candidate; it never re-exports or guesses the newest file.
- Added a one-trigger production state machine with storage gating, one-clip compatibility transcode/render lifecycle, immutable DRX replication, human-verified master preset loading, per-clip failure isolation, logical 10+N batching, hard final postflight, and constrained cleanup of verified rebuildable working media.

### Safety

- Mixed or unknown batch metadata stops preflight.
- Source overwrite and output overwrite remain prohibited.
- AutoGrade requires a human-approved reference grade plus explicit test/batch and render-start authorization.

## v0.1.0 legacy

The original camera-specific implementation is preserved without history rewriting at tag `v0.1.0-fx3-legacy`.
