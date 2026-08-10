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
- **REG-011 — Readable is not writable:** never assume that `Project:SetSetting()` can write every property exposed by `Project:GetSetting()`. Resolve 20.3.2 Free on Windows exposes `timelinePlaybackFrameRate` for reading but rejects writes. Apply the exact runtime-selected, human-verified Project Format preset with `Project:SetPreset()`, then read back Playback FPS, Timeline FPS, width, and height; stop before color management or import on any failure or mismatch.
- **REG-012 — Homogeneous color science:** mixed/unknown gamma or primaries stops preflight; no automatic LUT guessing.
- **REG-013 — Reference-grade integrity:** AutoGrade requires an approved reference timeline and exact node count.
- **REG-014 — Bounded batch:** first test is at most three clips; each batch invocation is at most ten.
- **REG-015 — Project Preset discovery gate:** before creating a diagnostic project or calling `Project:SetPreset()`, call `Project:GetPresetList()` on the current project, log its complete safely traversable structure, and prove the runtime `preset_name` is an exact visible candidate. Trimmed or case-insensitive matches are warnings only. A missing exact match stops before project creation.

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
