# Workflow

## 1. Confirm source metadata

Before Resolve changes anything, record every source file and reliably confirm codec/profile, bit depth, chroma subsampling, width, height, accurate frame rate, gamma, and primaries. Camera model is informational only.

One batch must be homogeneous in width, height, frame rate, gamma, and primaries. Any mismatch stops the workflow.

## 2. Prepare the private runtime profile

Copy `config/runtime.example.lua` to `config/runtime.local.lua`, fill in the confirmed batch values, and copy it to `%TEMP%\SonySLog3AutoGrade\runtime.lua`. The local file and all real paths/manifests are ignored by Git.

When Resolve cannot natively decode the original video, add a `batch.media_mappings` entry instead of replacing the source manifest. `original_file` is the absolute, read-only camera source and remains the authority for gamma and primaries. `working_file` is the absolute compatibility representation imported by Resolve. Before syncing runtime, the external preflight must recheck both files with filesystem, SHA-256, and ffprobe evidence and retain the signal-equivalence result. It writes one hash-bound `batch.external_media_attestations` entry for each required mapping. Real paths and hashes remain private.

This is a strict responsibility boundary. Layer A, external preflight, proves original existence and identity, original metadata, working identity and technical baseline, exact mapping, range transform, and signal equivalence. Layer B, Resolve runtime, consumes that attestation, imports only working media, and proves actual video decode. Resolve MediaStorage enumeration is never the existence authority for original camera media. Unicode enumeration capability and media import/decode capability are separate.

`FULL_TO_LIMITED_NORMALIZATION` means full-range source code values were correctly normalized to a codec-compliant limited-range representation. It is not a Rec.709 conversion. Do not force such DNxHR media to Full levels in Resolve, and do not derive Input Color Space from its `bt709` YCbCr matrix tag. The fixed Sony Input Color Policy continues to come from verified original metadata.

## 3. Establish Project Format safely

The recommended `drp_template` method separates a one-time human Project Format decision from repeatable automation:

1. create a new, completely empty Resolve project;
2. before importing media, set and verify resolution, Timeline FPS, and Playback FPS;
3. declare that exact project name and an ASCII-only private `template_path` in the ignored runtime;
4. run `Sony SLog3 Template Capture` once;
5. require empty Media Pool, zero timelines, empty render queue, exact format readback, successful save, successful `ExportProject(projectName, filePath, false)`, and a non-empty collision-safe DRP.

Never commit the DRP or real runtime. If the format changes, capture and verify a different template. The optional `preset` method remains available only when `Project:GetPresetList()` exposes the exact verified runtime preset; it is not the fallback for an invisible preset.

## 4. Run diagnostic once

Run `Sony SLog3 Diagnostic` from Resolve's internal Workspace menu. It:

1. initializes ASCII logging;
2. loads and validates the runtime profile;
3. acquires Resolve with `app:GetResolve()`;
4. for `drp_template`, verifies the DRP exists, refuses an existing target project, calls `ImportProject(template_path, unique_project_name)`, loads it, then rechecks Playback FPS, Timeline FPS, width, height, blank Media Pool, zero timelines, and empty render queue;
5. for optional `preset`, first calls `Project:GetPresetList()` and requires an exact visible runtime `preset_name` before project creation or `SetPreset()`;
6. only after the selected bootstrap gate passes, configures and reads back the fixed Sony S-Log3 color-managed transform;
7. requires the exact hash-bound External Media Attestation, records `ORIGINAL SOURCE AUTHORITY=EXTERNAL_VERIFIED_ATTESTATION`, never enumerates or decodes the original through Resolve, imports only the exact declared working path, and evaluates input policy from externally verified original metadata without attempting undocumented per-clip Input Color Space writes;
8. accepts `EXPLICIT_CLIP_MATCH`, or `VERIFIED_PROJECT_DEFAULT` only when `homogeneous_metadata_verified=true`, source metadata identifies Sony S-Gamut3.Cine / S-Log3, project input gamut/gamma match, and automatic management is off; any missing confirmation or explicit clip conflict stops;
9. creates one diagnostic timeline and requires one validated Video Track TimelineItem whose MediaPoolItem points to the exact working file; `ImportMedia()` alone never proves video decode;
10. saves the project and stages a collision-safe DRP;
11. opens Edit and stops.

Do not continue if the diagnostic report contains an error.

Resolve 20.3.2 Free has been observed to return `false` when `Project:SetSetting("timelinePlaybackFrameRate", ...)` is called in a fresh empty project, even though the same key is readable. `Project:GetSetting()` therefore does not imply that the corresponding property is writable through `Project:SetSetting()`. Do not brute-force additional values. Capture a verified blank DRP for each confirmed format actually needed (for example 4K50, 4K59.94, 4K25, or 1080p50), then import it under a unique project name and read back all four format values. Templates establish only Project Format; the script continues to own and verify the color pipeline separately.

Runtime configuration is not proof that a preset exists. Before creating another empty diagnostic project, the workflow calls `Project:GetPresetList()` on the current project and records the API return type, every safely traversable table key/value/type, and extracted preset-name candidates. Only an exact candidate match permits project creation and `SetPreset`. Trimmed and case-insensitive matches are diagnostic warnings and are never selected automatically.

An existing diagnostic project is never reused by default. A recovery run requires all three private runtime gates: `resume_existing_diagnostic=true`, `allow_load_existing=true`, and `allow_create=false`. Before changing color settings, the script revalidates the exact project name, Project Format, zero folders, an empty render queue, and either zero timelines or one exact expected diagnostic timeline. Root MediaPoolItems are classified semantically: exactly one non-empty file-backed source must match the declared first source; one empty-path item is allowed only when its name exactly matches the sole Project Timeline; every other object stops. An existing timeline is reused only when validated sequence traversal proves exactly one TimelineItem and its MediaPoolItem path matches the first source. An empty, mismatched, unexpected, or additional timeline stops without deletion or replacement; the DRP is not imported again.

Resolve/Fusion bridge collections are never validated with `pairs()` count or raw `#table`. Raw traversal is logged for diagnosis, while the decision path counts only sequence entries that pass API-specific object and read-only method checks.

For compatibility media, success additionally requires `EXTERNAL MEDIA ATTESTATION=PASS`, `ORIGINAL SOURCE AUTHORITY=EXTERNAL_VERIFIED_ATTESTATION`, `WORKING MEDIA MAPPING=VERIFIED`, `WORKING MEDIA IMPORT=PASS`, a real Video Track, exactly one validated TimelineItem, `WORKING_MEDIA_VIDEO_DECODE=PASS`, and `TIMELINE=ONE_EXACT_WORKING_SOURCE`. The final diagnostic status is `SUCCESS_DNXHR_COMPATIBILITY_READY`. AutoGrade rejects a required working-media mapping until both signal equivalence and Resolve decode have passed; once enabled, it imports the mapped working path but keeps output naming and color policy tied to the original source identity.

A verified Resolve 20.3.2 Free run completed this entire chain with generic DNxHR HQX 10-bit 4:2:2 working media. The imported item exposed valid video+audio type, expected geometry/FPS/codec, one real Video Track, and one exact TimelineItem association before SaveProject and Edit handoff. This establishes compatibility-media eligibility, not look approval.

The stable Workspace launcher and formal Diagnostic logic have separate identities. A launcher canary records its fixed launcher ID, then loads the formal script from disk. The private deployment attestation supplies `logic_commit` and `logic_sha256`, which the formal script records in every log/report. Updating only formal business logic therefore does not require a new menu filename or Resolve restart; a restart is needed only when the launcher itself changes.

## 5. Compatibility and image review

Confirm normal thumbnail, frame stepping, playback, audio, duration, and no Media Offline behavior. Inspect an Original Log view and RCM Only view before adding a look.

If native video decode is unsupported but audio imports, preserve that project as failure evidence. Create a fresh project from the verified DRP for the working-media test; never retrofit or clean up the audio-only project automatically.

## 6. Neutral Safe candidate

Create a separate reference timeline and enter a conservative candidate with native Resolve controls. Do not use a LUT or automatic warming. Review representative people, neutral objects, normal booths, LED/displays, highlights, shadows, and saturated scenes.

The final candidate becomes eligible only after explicit human approval. Record its reference timeline and exact node count in the private runtime profile.

The official scripting API does not provide reliable native setters/readback for the complete requested primary-control set (Contrast, Pivot, Color Boost, Highlights, Temperature, and Tint). Do not substitute CDL values or undocumented keys. Reference Prep creates two new clean one-clip timelines without touching the verified diagnostic timeline: an RCM-only baseline and an untouched reference seed. It resets each new graph through the documented `Graph:ResetAllGrades()`, requires one default node with no LUT, and renders only the RCM baseline. A recovery run never creates a second pair: it requires exactly one source/A/B timeline, exact working-media identity, one node, no LUT, and private prior-reset attestation before logging `REUSE_EXISTING_REFERENCE_TIMELINES`.

Render discovery treats the key and value returned by `GetRenderFormats()` as different identities: the key is a display name and the value is the API format ID. Raw-dump both collections, prove one exact local mapping, call `GetRenderCodecs(format_id)`, and derive the codec ID only from the returned description→ID evidence. `SetCurrentRenderFormatAndCodec(format_id, codec_id)` and exact `GetCurrentRenderFormatAndCodec()` readback must pass before a job is created. After the sole RCM render reports Complete, an external ffprobe/hash postflight must prove container, DNxHR HQX profile, 10-bit 4:2:2, geometry, FPS, frame count, duration, PCM audio, size, and SHA-256. Only then may Reference Prep select the untouched seed, open Color, and log `REFERENCE GRADE UI READY`.

Production RCM bootstrap must remain identical to the machine-validated Diagnostic sequence: managed color science, Custom mode, automatic management off, `separateColorSpaceAndGamma=1`, then the separate input/timeline/output gamut and gamma fields. `SetSetting()` return values are diagnostic evidence; immediate authoritative readback decides success. Before transcoding the first clip, a second complete RCM readback must pass and log `PRODUCTION_RCM_FINAL_VERIFY=ALL_MATCH`.

Do not reconstruct a full master Deliver configuration through a large `SetRenderSettings()` dictionary. A human first verifies format, codec, geometry, FPS, Single Clip/Entire Timeline, audio, and normal/Auto data levels in Deliver. The internal Capture Utility refuses an existing name or export path, calls documented `Project:SaveAsNewRenderPreset(name)`, proves exact visibility through `GetRenderPresetList()`, then calls `Resolve:ExportRenderPreset(name, exportPath)` and records a SHA-256. Runtime must bind that artifact as `CAPTURED_VERIFIED`. Reference Prep calls `Project:LoadRenderPreset(name)`, requires exact `mov`/DNxHR HQX readback and Single Clip mode, then sends only `TargetDir`, `CustomName`, and `SelectAllFrames` to `SetRenderSettings()`.

After a human grades and approves the seed, treat that TimelineItem as immutable. The installed README documents the complete artifact chain: `Timeline:GrabStill()`, `GalleryStillAlbum:ExportStills(..., "drx")`, and `Graph:ApplyGradeFromDRX(path, gradeMode)`. The preferred long-term path exports the approved grade as a private DRX, pins its SHA-256 externally, and applies that exact artifact. `TimelineItem:CopyGrades([targets])` remains a direct same-project copy and cross-check path. Target validation uses reference identity, node count/graph evidence, artifact SHA-256, API success, and render regression—not hidden Primary readback.

Resolve may add a uniqueness suffix to a DRX export filename. Artifact identity is therefore established by a pre-export/post-export directory snapshot delta: exactly one new non-empty `.drx` must have the requested basename as its prefix. The workflow never guesses by modification time or adopts an old file. Once the actual path, size, and SHA-256 are recorded, the DRX is immutable and resume runs verify it without grabbing another still or exporting again.

## 7. Test and batch

Switch profile mode to `test`, list at most three representative clips, and explicitly authorize test plus render start. Review every output. Only then set batch authorization. Each batch invocation is capped at ten clips and refuses a non-empty render queue or existing output overwrite.

For an explicitly authorized full production run, use the one-trigger production state machine in logical sub-batches of at most ten. It processes one clip at a time: verified original → temporary decode-compatible DNxHR → one-source timeline → SHA-256-pinned DRX → human-verified master preset → render completion → ffprobe/SHA-256 postflight → authorized temporary-working cleanup. The original, reference working media, reference masters, DRX, DRP, reports, and final masters are never cleanup targets. Per-clip failures retain working media and continue; systemic gates stop the run.

## 8. Display/LED regression

Compare the same frame through Original Log, RCM Only, Neutral Safe, a high-quality low-loss master, and delivery H.264/H.265. Do not change color to hide a delivery encoder defect.
