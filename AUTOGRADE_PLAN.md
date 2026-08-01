# AutoGrade workflow plan

## Goal

Convert reliably identified Sony FX3 S-Gamut3.Cine / S-Log3 footage to conservative Rec.709 Gamma 2.4 deliverables using DaVinci Resolve's internal Lua scripting environment.

## Safety gates

1. Treat `ship` as read-only. Never move, delete, overwrite, or rename source media or XML sidecars.
2. Render only below `ship_output`; never ingest generated outputs.
3. Stop when input color space cannot be confirmed from trustworthy metadata. Never guess or apply a LUT automatically.
4. Use an isolated Resolve project and verify project name, resolution, frame rates, color management, per-clip input color space, timeline source, node count, render format, and target directory before rendering.
5. Test no more than three clips before human review. Batch no more than ten clips per invocation.
6. Do not overwrite existing output or delete successful output after another clip fails.

## Color pipeline

- DaVinci YRGB Color Managed; automatic color management disabled
- Input: Sony S-Gamut3.Cine / S-Log3
- Timeline: DaVinci Wide Gamut / DaVinci Intermediate
- Output: Rec.709 Gamma 2.4
- 3840×2160 at 59.94 fps in the verified profile
- V2B serial node 02: Contrast 1.120, Pivot 0.440, Color Boost 12.00, Saturation 54.00, Highlights -8.00, Temperature 0.0, Tint 0.00
- No LUT, auto exposure, auto white balance, vignette, grain, beauty processing, noise reduction, or extra sharpening

## Stages

1. Read the locally installed official Resolve scripting documentation.
2. Confirm camera/Log metadata and HEVC Main 10 decode using one clip.
3. Render three standard tests and perform human review.
4. Render three V2A/V2B pairs and obtain an explicit human selection.
5. Build an approved filename manifest in `config/source_files.txt`.
6. Invoke the internal batch script repeatedly; each invocation handles at most ten unprocessed entries.
7. After each batch, confirm green completion, save the project, and validate output resolution, frame rate, duration, and audio metadata.
8. Mark failures `ReviewNeeded` without changing the approved uniform grade.

## Public/private boundary

Only source code, example configuration, documentation, sanitized reports, and redistributable presets belong in the public repository. Raw media, sidecars, outputs, real inventories, local paths, logs, caches, proxies, Resolve databases, and project backups must remain local.
