# Regression tests

- **REG-001 — Internal object:** Workspace Lua uses the empirically verified `app:GetResolve()` and never imports the external Resolve scripting module.
- **REG-002 — Unicode logging:** Lua file I/O uses `%TEMP%\SonySLog3AutoGrade`; media paths remain original and are tested through Resolve APIs.
- **REG-003 — No silent failure:** fallback log, `xpcall`, traceback, stage, `START`, `ERROR/SUCCESS`, and `STOP` are mandatory.
- **REG-004 — Camera-agnostic eligibility:** camera model is metadata; eligibility is reliable Sony S-Gamut3.Cine / S-Log3 confirmation.
- **REG-005 — Dynamic geometry:** resolution and FPS come from confirmed batch metadata; mixed batches stop.
- **REG-006 — No global warming:** Neutral Safe does not use automatic or uniform warming.
- **REG-007 — Display/LED chain:** compare Original Log, RCM Only, Neutral Safe, high-quality master, and delivery codec.
- **REG-008 — Read-only source:** never modify, move, rename, delete, overwrite, or render into source.
- **REG-009 — Collision safety:** existing output is never silently overwritten.
- **REG-010 — Test before batch:** representative small-scale output and human approval are required.
- **REG-011 — Readable is not writable:** never assume that `Project:SetSetting()` can write every property exposed by `Project:GetSetting()`. Resolve 20.3.2 Free on Windows exposes `timelinePlaybackFrameRate` for reading but rejects writes. Bootstrap Project Format from a verified blank DRP, or from an exact API-visible verified preset, then read back Playback FPS, Timeline FPS, width, and height; stop before color management or import on any failure or mismatch.
- **REG-012 — Homogeneous color science:** mixed/unknown gamma or primaries stops preflight; no automatic LUT guessing.
- **REG-013 — Reference-grade integrity:** AutoGrade requires an approved reference timeline and exact node count.
- **REG-014 — Bounded batch:** first test is at most three clips; each batch invocation is at most ten.
- **REG-015 — Project Preset discovery gate:** before creating a diagnostic project or calling `Project:SetPreset()`, call `Project:GetPresetList()` on the current project, log its complete safely traversable structure, and prove the runtime `preset_name` is an exact visible candidate. Trimmed or case-insensitive matches are warnings only. A missing exact match stops before project creation.
- **REG-016 — Private DRP bootstrap gate:** Template Capture must prove an empty Media Pool, zero timelines, an empty render queue, and exact Project Format readback before a collision-safe `ExportProject`. Diagnostic must import the private DRP under a new unique project name, repeat both blank-state and format validation, and stop before color management or media import on any mismatch. DRP files and real runtime paths never enter Git.
- **REG-017 — Resolve Lua collection metadata:** Resolve/Fusion's internal Lua bridge may add metadata keys such as `__flags`, `__idxtokey`, `__keytoidx`, or future `__*` fields to tables returned by list APIs. A raw `pairs()` entry count must never be treated as the number of Resolve objects. Log the complete safe top-level structure for diagnosis, but traverse only validated sequence entries: userdata candidates for Media Pool objects/folders and information tables with `JobId` for render jobs. MediaPoolItem userdata still requires semantic classification under REG-020. Regression case: an empty GUI returned a naive top-level count of one for clips, folders, and render jobs.
- **REG-018 — Clip Input Color Space API capability:** Project-level color management and MediaPoolItem clip-property visibility are independent capabilities. Never call `SetClipProperty` for Input Color Space unless the installed official API explicitly guarantees that field is writable. An explicit matching clip value yields `EXPLICIT_CLIP_MATCH`; an explicit conflict stops. For a batch with explicit `homogeneous_metadata_verified=true`, an empty/unavailable clip value may yield `VERIFIED_PROJECT_DEFAULT` only when confirmed gamut/gamma match Sony S-Gamut3.Cine / S-Log3, project input gamut/gamma match, automatic color management is off, and no override evidence is exposed. The fallback must be reported with a warning, never disguised as per-clip verification.
- **REG-019 — Resolve Lua collections must not be validated by raw table length:** neither `pairs()` entry count nor `#table` may be treated as a Resolve/Fusion bridge collection's real object count. `pairs()` is diagnostic-only and must log keys, types, values, sequence candidacy, userdata status, and classification. Object validation uses sequence traversal plus API-specific read-only capability checks. For `Timeline:GetItemListInTrack()`, every accepted entry must be TimelineItem userdata whose `GetName()` is callable and whose `GetMediaPoolItem()` returns MediaPoolItem userdata; the sole item's normalized source path must match the declared source.
- **REG-020 — Media Pool items are not equivalent to source media:** `RootFolder:GetClipList()` can expose file-backed source MediaPoolItems, Timeline MediaPoolItems, other non-file-backed MediaPoolItems, and bridge metadata. Validated userdata count is never source count. `SOURCE_MEDIA` requires a non-empty normalized File Path. `TIMELINE_MEDIA_POOL_ITEM` requires an empty File Path plus exact name correspondence with the sole expected Project Timeline; localized `Type` is diagnostic evidence only. Any second file-backed source or any unclassified object stops. Object UUID text is not an identity gate.

## Release gate

The development branch must not merge to main until real footage confirms:

- normal decode and frame stepping;
- correct dynamic project resolution and frame rates;
- RCM Only image integrity;
- human-approved Neutral Safe skin tone and neutral objects;
- no recurrence of obvious warm/yellow people;
- at least one display/LED clip tested through master and delivery stages;
- no source overwrite;
- complete output frame rate, duration, audio, and render status.
