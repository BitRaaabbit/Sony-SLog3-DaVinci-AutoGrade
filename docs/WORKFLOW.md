# Workflow

## 1. Confirm source metadata

Before Resolve changes anything, record every source file and reliably confirm codec/profile, bit depth, chroma subsampling, width, height, accurate frame rate, gamma, and primaries. Camera model is informational only.

One batch must be homogeneous in width, height, frame rate, gamma, and primaries. Any mismatch stops the workflow.

## 2. Prepare the private runtime profile

Copy `config/runtime.example.lua` to `config/runtime.local.lua`, fill in the confirmed batch values, and copy it to `%TEMP%\SonySLog3AutoGrade\runtime.lua`. The local file and all real paths/manifests are ignored by Git.

## 3. Run diagnostic once

Run `Sony SLog3 Diagnostic` from Resolve's internal Workspace menu. It:

1. initializes ASCII logging;
2. loads and validates the runtime profile;
3. acquires Resolve with `app:GetResolve()`;
4. creates or loads the exact isolated project;
5. records untouched initial settings, applies the exact verified Project Format preset declared by the runtime, and reads back Playback FPS, Timeline FPS, width, and height;
6. only after that gate passes, configures and reads back the fixed Sony S-Log3 color-managed transform;
7. imports only the first declared source;
8. creates one diagnostic timeline;
9. saves the project and stages a collision-safe DRP;
10. opens Edit and stops.

Do not continue if the diagnostic report contains an error.

Resolve 20.3.2 Free has been observed to return `false` when `Project:SetSetting("timelinePlaybackFrameRate", ...)` is called in a fresh empty project, even though the same key is readable. `Project:GetSetting()` therefore does not imply that the corresponding property is writable through `Project:SetSetting()`. Do not brute-force additional values. Create and manually verify a Project Format preset for each confirmed format that is actually needed (for example 4K50, 4K59.94, 4K25, or 1080p50), declare its exact name in the private runtime, call the documented `Project:SetPreset()`, and read back all four format values. A missing preset, failed API return, or mismatch stops before color management and media import. Presets establish only Project Format; the script continues to own and verify the color pipeline separately.

## 4. Compatibility and image review

Confirm normal thumbnail, frame stepping, playback, audio, duration, and no Media Offline behavior. Inspect an Original Log view and RCM Only view before adding a look.

## 5. Neutral Safe candidate

Create a separate reference timeline and enter a conservative candidate with native Resolve controls. Do not use a LUT or automatic warming. Review representative people, neutral objects, normal booths, LED/displays, highlights, shadows, and saturated scenes.

The final candidate becomes eligible only after explicit human approval. Record its reference timeline and exact node count in the private runtime profile.

## 6. Test and batch

Switch profile mode to `test`, list at most three representative clips, and explicitly authorize test plus render start. Review every output. Only then set batch authorization. Each batch invocation is capped at ten clips and refuses a non-empty render queue or existing output overwrite.

## 7. Display/LED regression

Compare the same frame through Original Log, RCM Only, Neutral Safe, a high-quality low-loss master, and delivery H.264/H.265. Do not change color to hide a delivery encoder defect.
