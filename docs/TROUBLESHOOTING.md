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

## Display artifacts

- RCM Only already abnormal: inspect source LED/moire/chroma noise revealed by normal Rec.709 contrast.
- RCM Only normal, Neutral Safe abnormal: reduce grading strength, starting with Color Boost.
- Resolve and master normal, delivery abnormal: investigate codec, encoder, profile, chroma, bitrate, GOP, hardware encoding, and secondary compression. Do not change color to compensate.
