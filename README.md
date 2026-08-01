# FX3-SLog3-DaVinci-AutoGrade

[简体中文](README_zh-CN.md)

An internal-Lua workflow for conservative, repeatable conversion of confirmed Sony FX3 S-Gamut3.Cine / S-Log3 footage to Rec.709 Gamma 2.4 in DaVinci Resolve.

The project favors verified color management over LUT guessing. It provides a three-clip compatibility test, an A/B neutral-grade comparison, and a maximum-ten-clips-per-run batch script. Raw media is treated as read-only and renders are confined to `ship_output`.

## Verified environment

- Windows 11
- DaVinci Resolve 20.3.2 Free
- Sony FX3 / ILME-FX3
- Sony S-Gamut3.Cine / S-Log3
- HEVC Main 10, 3840×2160, 59.94p test footage
- MP4/H.264 Individual Clips output with AAC stereo at 48 kHz

Other Resolve versions may expose different setting labels or render capabilities. This project is not validated for other cameras, gamuts, gamma curves, frame rates, or codecs.

## Default color pipeline

- DaVinci YRGB Color Managed; automatic color management off
- Input: Sony S-Gamut3.Cine / S-Log3
- Timeline: DaVinci Wide Gamut / DaVinci Intermediate
- Output: Rec.709 Gamma 2.4
- Timeline and playback: 59.94 fps
- Resolution: 3840×2160
- No LUT, auto exposure, auto white balance, temperature/tint correction, vignette, grain, skin processing, noise reduction, or extra sharpening

The approved V2B adjustment is a serial node 02 after the color-managed transform:

| Parameter | Value |
|---|---:|
| Contrast | 1.120 |
| Pivot | 0.440 |
| Color Boost | 12.00 |
| Saturation | 54.00 |
| Highlights | -8.00 |
| Temperature | 0.0 |
| Tint | 0.00 |

## Install

1. Download or clone this project into a local folder. Paths containing Unicode characters and spaces are supported, but keep every path fully quoted in shell commands.
2. Create local `ship`, `ship_output`, `ship_review`, `logs`, and `temp` directories. They are intentionally ignored by Git.
3. Put only original camera MP4s and their optional metadata sidecars in `ship`. Never put generated output back into `ship`.
4. Copy `config/autograde.example.json` to `config/autograde.json` and update local paths. The real config is ignored by Git.
5. Copy `config/source_files.example.txt` to `config/source_files.txt` and list the approved MP4 filenames, one per line. Do not list XML files or paths.
6. Set `FX3_AUTOGRADE_ROOT` before launching Resolve, or edit the public fallback `PROJECT_ROOT` near the top of the test and comparison Lua scripts.
7. Copy each Lua template to a `*.local.lua` file under `scripts/` (these local copies are ignored by Git). Replace the three `FX3_TEST_00X.MP4` placeholders in the local test and comparison scripts with three confirmed filenames. In the local batch script, set `REFERENCE_TIMELINE` to `CMP_<first-clip-stem>_NeutralV2B`.
8. Copy the three customized local Lua files to the Resolve Utility directory, optionally removing `.local` from their installed names:

   `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility\`

9. Restart Resolve so the scripts appear under `Workspace > Scripts`.

## Run

1. Create or open an isolated empty project named `FX3_SLog3_AutoGrade_Test`. Do not reuse a production project.
2. Before importing media or creating a timeline, set 3840×2160, Timeline Frame Rate 59.94, and Playback Frame Rate 59.94. Read both frame-rate values back.
3. Run `Workspace > Scripts > FX3 Standard AutoGrade Test`. It processes only the three configured test clips. Stop immediately if HEVC Main 10 is Media Offline or audio-only.
4. Review the three standard test renders manually.
5. Run `FX3 Neutral Comparison` to create V2A and V2B comparison renders. Confirm the intended V2B reference timeline contains exactly two serial nodes.
6. After explicit approval, run `FX3 Batch V2B`. Each invocation processes at most ten manifest entries. Confirm every render job is green, save the project, validate output frame rate and duration, then invoke the next batch.
7. Stop after all manifest entries are complete. Never start a larger batch automatically.

## Minimum manual actions in Resolve Free

The verified free-edition workflow does not use an external Resolve scripting connection. The minimum manual work is:

- create/select the isolated project;
- set and read back resolution and both frame rates before media import;
- restart Resolve after script installation;
- choose each internal script from `Workspace > Scripts`;
- visually confirm the first clip decodes correctly;
- start or supervise the approved test/batch render and confirm green completion.

The scripts obtain Resolve through the internal `app:GetResolve()` object. No UIManager integration, mouse-macro framework, image recognition, third-party plugin, or downloaded LUT is required.

## Safety limits

- `ship` is read-only: never move, delete, overwrite, or rename source MP4/XML files.
- Write rendered media only below `ship_output`; never treat that tree as input.
- Do not overwrite existing output. Validate a complete same-name file before skipping it; use a timestamp or sequence for an incomplete retry.
- Do not infer a camera or Log profile. If reliable metadata does not confirm Sony FX3 S-Gamut3.Cine / S-Log3, stop for human confirmation.
- Do not import XML sidecars as media.
- Do not install unknown packages, executables, LUTs, or plugins.
- Test at most three clips before approving a batch; process at most ten clips per batch.
- A failed clip must not cause successful outputs to be deleted.

## Reports and privacy

Only sanitized examples under `examples/` are publishable. Real inventories, logs, local configuration, media, Resolve databases, proxies, caches, and backups are excluded by `.gitignore`.

## License

MIT. See [LICENSE](LICENSE).
