# Workflow

## 1. Confirm source metadata

Before Resolve changes anything, record every source file and reliably confirm codec/profile, bit depth, chroma subsampling, width, height, accurate frame rate, gamma, and primaries. Camera model is informational only.

One batch must be homogeneous in width, height, frame rate, gamma, and primaries. Any mismatch stops the workflow.

## 2. Prepare the private runtime profile

Copy `config/runtime.example.lua` to `config/runtime.local.lua`, fill in the confirmed batch values, and copy it to `%TEMP%\SonySLog3AutoGrade\runtime.lua`. The local file and all real paths/manifests are ignored by Git.

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
7. imports only the first declared source and evaluates the effective input policy without attempting undocumented per-clip Input Color Space writes;
8. accepts `EXPLICIT_CLIP_MATCH`, or `VERIFIED_PROJECT_DEFAULT` only when `homogeneous_metadata_verified=true`, source metadata identifies Sony S-Gamut3.Cine / S-Log3, project input gamut/gamma match, and automatic management is off; any missing confirmation or explicit clip conflict stops;
9. creates one diagnostic timeline;
10. saves the project and stages a collision-safe DRP;
11. opens Edit and stops.

Do not continue if the diagnostic report contains an error.

Resolve 20.3.2 Free has been observed to return `false` when `Project:SetSetting("timelinePlaybackFrameRate", ...)` is called in a fresh empty project, even though the same key is readable. `Project:GetSetting()` therefore does not imply that the corresponding property is writable through `Project:SetSetting()`. Do not brute-force additional values. Capture a verified blank DRP for each confirmed format actually needed (for example 4K50, 4K59.94, 4K25, or 1080p50), then import it under a unique project name and read back all four format values. Templates establish only Project Format; the script continues to own and verify the color pipeline separately.

Runtime configuration is not proof that a preset exists. Before creating another empty diagnostic project, the workflow calls `Project:GetPresetList()` on the current project and records the API return type, every safely traversable table key/value/type, and extracted preset-name candidates. Only an exact candidate match permits project creation and `SetPreset`. Trimmed and case-insensitive matches are diagnostic warnings and are never selected automatically.

An existing diagnostic project is never reused by default. A recovery run requires all three private runtime gates: `resume_existing_diagnostic=true`, `allow_load_existing=true`, and `allow_create=false`. Before changing color settings, the script revalidates the exact project name, Project Format, one exact first source, zero folders, zero timelines, and an empty render queue. Any difference stops; the DRP is not imported again.

## 5. Compatibility and image review

Confirm normal thumbnail, frame stepping, playback, audio, duration, and no Media Offline behavior. Inspect an Original Log view and RCM Only view before adding a look.

## 6. Neutral Safe candidate

Create a separate reference timeline and enter a conservative candidate with native Resolve controls. Do not use a LUT or automatic warming. Review representative people, neutral objects, normal booths, LED/displays, highlights, shadows, and saturated scenes.

The final candidate becomes eligible only after explicit human approval. Record its reference timeline and exact node count in the private runtime profile.

## 7. Test and batch

Switch profile mode to `test`, list at most three representative clips, and explicitly authorize test plus render start. Review every output. Only then set batch authorization. Each batch invocation is capped at ten clips and refuses a non-empty render queue or existing output overwrite.

## 8. Display/LED regression

Compare the same frame through Original Log, RCM Only, Neutral Safe, a high-quality low-loss master, and delivery H.264/H.265. Do not change color to hide a delivery encoder defect.
