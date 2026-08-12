# Troubleshooting

## Script click produces no visible result

Check `%TEMP%\SonySLog3AutoGrade\diagnostic.log` and the emergency log `%TEMP%\SonySLog3AutoGrade_emergency.log`. Every invocation must contain `START`, a stage marker, and either `SUCCESS` or `ERROR` followed by `STOP`.

Resolve 20.3.2 Free was observed to expose a valid internal Resolve userdata through `app:GetResolve()` while `Resolve()` returned nil in the same Workspace script context. The public scripts therefore use `app:GetResolve()` and never load the external scripting module.

## Unicode Windows paths

Resolve's internal Lua `io.open` may report `No such file or directory` for an existing path containing Chinese or other Unicode characters. Keep Lua profiles, logs, reports, traceback, state, and temporary DRP staging under `%TEMP%\SonySLog3AutoGrade`.

This does not prove that Resolve's media APIs reject Unicode. In a direct-media workflow, pass the declared import path to `MediaPool:ImportMedia` and verify its returned MediaPoolItem and exact File Path. In a compatibility workflow, never ask Resolve MediaStorage to enumerate the original camera path: external filesystem/hash/ffprobe evidence owns original identity, while Resolve imports and validates only the working path. Do not create a junction or move source media as an automatic workaround.

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

Generate a private `EXTERNAL_MEDIA_ATTESTATION` immediately before runtime sync. It must bind one `mapping_id` to exact original/working paths and SHA-256 values, confirmed original gamma/primaries, both technical baselines, preflight timestamp/tool, range transform, and signal-equivalence result. A missing, stale, duplicate, mismatched, or non-PASS attestation stops before `ImportMedia`. Resolve does not independently re-prove original existence because Unicode directory enumeration is not a reliable source-identity authority.

Use a fresh diagnostic project from the verified DRP. Import the exact working path and require one real Video Track TimelineItem linked back to that exact MediaPoolItem. `ImportMedia()` returning an object is not enough. Missing/incorrect Resolution, FPS, codec evidence, an audio-only timeline, or a mismatched path stops before grading or rendering.

A successful generic DNxHR HQX compatibility diagnostic on Resolve 20.3.2 Free returned a video+audio MediaPoolItem, expected 10-bit 4:2:2 working geometry/FPS/codec evidence, one real Video Track, one exact TimelineItem-to-MediaPoolItem path match, successful project save, and `SUCCESS_DNXHR_COMPATIBILITY_READY`. Record `resolve_decode_status="PASS"` only after this complete chain, never after import alone.

## Launcher runs newer formal logic

The Workspace launcher and formal Diagnostic script are intentionally separate. The launcher writes `launcher_id`/`deployment_id`, then loads the formal script from its installed Utility path. Formal logs must also record externally attested `logic_commit` and `logic_sha256`. If the launcher file did not change, deploy the updated formal script and keep the already-enumerated launcher; do not create another menu item or restart Resolve merely for a business-logic commit.

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

## Native primary values cannot be scripted

The documented API exposes node graphs, node count, LUT/cache operations, `Timeline:GrabStill()`, `GalleryStillAlbum:ExportStills(..., "drx")`, `Graph:ApplyGradeFromDRX()`, `TimelineItem:CopyGrades()`, and CDL, but not reliable native setters/readback for Contrast, Pivot, Color Boost, Highlights, Temperature, and Tint. These controls must not be approximated with CDL or guessed property names. Create an untouched reference seed, let a human approve its native Color Page grade, then export and hash-pin the DRX artifact.

Prefer the DRX path for an immutable long-lived asset because the installed official README explicitly supports still capture, DRX export, and graph application. Verify the exported file exists, is non-empty, and has the recorded SHA-256 before any application. `CopyGrades()` is appropriate for same-project direct copying and regression comparison, but reference TimelineItem identity and node count alone do not freeze hidden grade values.

If `ExportStills()` returns true but the exact requested DRX path is absent, inspect the pre/post snapshot delta rather than exporting again. Resolve can append a suffix such as `_1.1.1`. Accept only the single new non-empty DRX whose basename begins with the requested prefix; zero, multiple, unrelated, or pre-existing candidates stop. Never use a generic "newest DRX" fallback.

## Production batch stops between clips

Read the private production log and per-clip worker result. Disk, DRP, DRX, Render Preset, RCM, and Resolve-object failures are systemic and stop before the next clip. A media-specific transcode, import, grade, render, or postflight failure is `REVIEW_NEEDED`; retain its working media and continue unless the same failure class repeats consecutively. Cleanup is eligible only after Render Job completion plus ffprobe and SHA-256 PASS, and only for a validated file inside the declared temporary working root.

If a fresh project rejects an independently verified RCM setter even after the correct separate-gamut/gamma sequence, stop treating it as a value-discovery problem. Preserve the partial project as evidence. Production should clone the exact machine-verified Reference Project through `ExportProject`/`ImportProject`, then accept only complete read-only Project Format and RCM matches before transcoding. Never repair inherited RCM with setters.

Windows exit `-1073741510` / `0xC000013A` means `STATUS_CONTROL_C_EXIT`, not an FFmpeg codec failure. If it occurs in `Resolve Lua → os.execute → PowerShell → FFmpeg`, preserve incomplete files for diagnosis and move long external work out of Resolve. Use atomic `.partial.mov` generation plus external validation; do not retry the same long synchronous process under the Resolve console group.

## Render codecs appear empty

Do not pass a Deliver-page display label directly to `GetRenderCodecs()` unless the local API has proved that label is also the format ID. `GetRenderFormats()` is a display-name→format-ID dictionary; retain and raw-dump both sides. Call `GetRenderCodecs()` with the verified value, raw-dump the returned bridge collection, and select DNxHR HQX 10-bit only from one unambiguous description→codec-ID pair. A metadata-only or unexpected table is evidence to stop and improve parsing, not evidence that the codec is absent. Never add a Render Job until SET plus exact format/codec readback succeeds.

## Full SetRenderSettings dictionary returns false

Stop removing or guessing keys one by one. Capture a human-verified Deliver configuration as a uniquely named Render Preset. `SaveAsNewRenderPreset()` and `LoadRenderPreset()` are Project methods; `ExportRenderPreset()` is a Resolve method. Refuse duplicate preset names and export-path collisions, prove the saved preset is API-visible, export and hash-pin it, and load it before each master. Automation may then override only documented job-scoped `TargetDir`, `CustomName`, and `SelectAllFrames`. A false task-only call still stops before `AddRenderJob()`.
