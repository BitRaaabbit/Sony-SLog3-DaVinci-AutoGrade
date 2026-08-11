# Troubleshooting

## Script click produces no visible result

Check `%TEMP%\SonySLog3AutoGrade\diagnostic.log` and the emergency log `%TEMP%\SonySLog3AutoGrade_emergency.log`. Every invocation must contain `START`, a stage marker, and either `SUCCESS` or `ERROR` followed by `STOP`.

Resolve 20.3.2 Free was observed to expose a valid internal Resolve userdata through `app:GetResolve()` while `Resolve()` returned nil in the same Workspace script context. The public scripts therefore use `app:GetResolve()` and never load the external scripting module.

## Unicode Windows paths

Resolve's internal Lua `io.open` may report `No such file or directory` for an existing path containing Chinese or other Unicode characters. Keep Lua profiles, logs, reports, traceback, state, and temporary DRP staging under `%TEMP%\SonySLog3AutoGrade`.

This does not prove that Resolve's media APIs reject Unicode. Pass the original path directly to `MediaPool:ImportMedia`, verify its returned MediaPoolItem and exact File Path, and stop on failure. Do not create a junction or move source media as an automatic workaround.

## Playback FPS remains at the default

A real diagnostic set Timeline FPS first, after which `timelinePlaybackFrameRate` returned `false` for both `50` and `50.000` and continued to read `24`. A second test used a new empty project and tried Playback first: `"50"`, `"50.0"`, and `"50.000"` all returned `false`, with readback fixed at 24. No media had been imported in either test.

The installed official scripting README enumerates `timelineFrameRate` as writable but not `timelinePlaybackFrameRate`. Do not keep trying undocumented values. Use `Sony SLog3 Template Capture` on a manually verified, completely blank project and keep the exported DRP private. Diagnostic imports it under a unique name and immediately reads back Playback FPS, Timeline FPS, width, and height. A missing/empty template, failed import, nonblank project, or mismatch stops before color management or media import. Different confirmed formats need different verified templates. Preserve inconsistent projects as fault evidence.

If `Project:SetPreset()` returns `false`, do not try alternative names. First inspect the preceding `PRESET LIST BEGIN` / `PRESET LIST END` block. The diagnostic logs the `Project:GetPresetList()` return type and complete safely traversable table structure before it creates a new project. `TARGET PRESET = NOT VISIBLE TO API` means no exact candidate was exposed; trim-only or case-insensitive matches are warnings and cannot authorize `SetPreset`.

An invisible local preset is not evidence that `SetPreset` is broken and is not a reason to guess another name. Switch the private runtime to `bootstrap_method = "drp_template"`, capture a verified blank DRP once, and let Diagnostic validate its imported state. `ImportProject` must target a new unique project name; an existing target is never overwritten or reused.

## Template Capture refuses export

Read `%TEMP%\SonySLog3AutoGrade\template_capture.log`. The current project must match the optional capture project name, have no Media Pool clips or subfolders, have zero timelines, have an empty render queue, and read back the exact runtime resolution and Playback/Timeline FPS. The target DRP must not already exist. Correct the project manually or choose a new private path; never delete or overwrite the only template automatically.

## ImportMedia returns no clip

Stop immediately. Record the requested path, `pcall` status, return type, and Media Pool contents. Do not install codecs, transcode, move source files, or import the rest of the batch.

## Native source imports as audio only

Treat an imported MediaPoolItem with the correct path but empty Resolution/Video Codec and no validated Video Track TimelineItem as `UNSUPPORTED_NATIVE_VIDEO_DECODE`, not as successful media import. Preserve the project as decode-failure evidence and do not modify the source.

A compatibility transcode is allowed only through an explicit Original → Working mapping. The original remains read-only metadata authority. Before Resolve testing, require a private technical report proving codec, pixel format, geometry, FPS, frames, duration, audio, SHA-256, and `SIGNAL_EQUIVALENCE=PASS`. If full-range source is represented as limited-range DNxHR, record `FULL_TO_LIMITED_NORMALIZATION`; do not call it a colorspace conversion and do not force the DNxHR clip to Full levels.

Use a fresh diagnostic project from the verified DRP. Import the exact working path and require one real Video Track TimelineItem linked back to that exact MediaPoolItem. `ImportMedia()` returning an object is not enough. Missing/incorrect Resolution, FPS, codec evidence, an audio-only timeline, or a mismatched path stops before grading or rendering.

## Working DNxHR reports a bt709 matrix

Do not interpret a DNxHR `color_space=bt709` matrix tag as proof of Rec.709 primaries or Gamma 2.4. A compatibility file may retain unspecified transfer and primaries while using the codec's legal YCbCr matrix/range representation. Project Input Color Space must still read back Sony S-Gamut3.Cine / S-Log3 from verified original metadata. Any explicit per-clip Input Color Space conflict remains a stop condition.

## Per-clip Input Color Space is empty

The installed Resolve 20.3.2 README documents generic `GetClipProperty` and `SetClipProperty` methods, warns that some properties may be read-only or unavailable by context, and does not specifically enumerate Input Color Space as writable. Do not guess property aliases or keep calling `SetClipProperty` when readback is empty.

Treat clip API visibility separately from project color management. A non-empty explicit Sony S-Gamut3.Cine / S-Log3 clip value is `EXPLICIT_CLIP_MATCH`; any explicit different value is `INPUT_UNVERIFIED` and stops. An empty or unavailable value can be `VERIFIED_PROJECT_DEFAULT` only when the runtime explicitly declares `homogeneous_metadata_verified=true`, confirmed gamma/primaries are Sony S-Gamut3.Cine / S-Log3, project input gamut/gamma read back correctly, automatic color management is off, and no clip override evidence is exposed. The report must retain the API warning and confidence basis.

## Timeline item count disagrees with Resolve

Do not use `#timeline:GetItemListInTrack(...)` or a `pairs()` count as the number of TimelineItems. Log the raw bridge table first, then traverse only sequence entries and validate TimelineItem userdata through safe read-only calls. A valid diagnostic timeline has exactly one accepted TimelineItem, a valid MediaPoolItem, and an exact normalized source-path match. If an existing diagnostic timeline has zero validated video items, report `EMPTY_DIAGNOSTIC_TIMELINE` and stop without creating, deleting, or replacing a timeline.

## Media Pool shows an extra item after creating a Timeline

Do not equate `RootFolder:GetClipList()` userdata count with source-media count. Resolve can expose a Timeline as a MediaPoolItem alongside file-backed clips. Record `GetName()`, the complete safe `GetClipProperty()` table, File Path, Type, Resolution, FPS, and other available fields for every validated item. Classify a non-empty File Path as `SOURCE_MEDIA`; classify an empty-path item as `TIMELINE_MEDIA_POOL_ITEM` only when its name exactly matches the sole expected Project Timeline. Treat localized `Type` and displayed UUID text as diagnostics, not identity. A second file-backed item or any remaining `OTHER_MEDIA_POOL_ITEM` stops without cleanup.

## Display artifacts

- RCM Only already abnormal: inspect source LED/moire/chroma noise revealed by normal Rec.709 contrast.
- RCM Only normal, Neutral Safe abnormal: reduce grading strength, starting with Color Boost.
- Resolve and master normal, delivery abnormal: investigate codec, encoder, profile, chroma, bitrate, GOP, hardware encoding, and secondary compression. Do not change color to compensate.
