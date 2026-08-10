# Troubleshooting

## Script click produces no visible result

Check `%TEMP%\SonySLog3AutoGrade\diagnostic.log` and the emergency log `%TEMP%\SonySLog3AutoGrade_emergency.log`. Every invocation must contain `START`, a stage marker, and either `SUCCESS` or `ERROR` followed by `STOP`.

Resolve 20.3.2 Free was observed to expose a valid internal Resolve userdata through `app:GetResolve()` while `Resolve()` returned nil in the same Workspace script context. The public scripts therefore use `app:GetResolve()` and never load the external scripting module.

## Unicode Windows paths

Resolve's internal Lua `io.open` may report `No such file or directory` for an existing path containing Chinese or other Unicode characters. Keep Lua profiles, logs, reports, traceback, state, and temporary DRP staging under `%TEMP%\SonySLog3AutoGrade`.

This does not prove that Resolve's media APIs reject Unicode. Pass the original path directly to `MediaPool:ImportMedia`, verify its returned MediaPoolItem and exact File Path, and stop on failure. Do not create a junction or move source media as an automatic workaround.

## Playback FPS remains at the default

A real diagnostic set Timeline FPS first, after which `timelinePlaybackFrameRate` returned `false` for both `50` and `50.000` and continued to read `24`. A second test used a new empty project and tried Playback first: `"50"`, `"50.0"`, and `"50.000"` all returned `false`, with readback fixed at 24. No media had been imported in either test.

The installed official scripting README enumerates `timelineFrameRate` as writable but not `timelinePlaybackFrameRate`. Treat Playback FPS as a gate: first read it, optionally apply only an explicitly configured and previously verified Project Preset, and read it again. If it still differs, stop before Timeline FPS, resolution, color management, or import. Do not keep trying undocumented values. Preserve inconsistent projects as fault evidence.

## ImportMedia returns no clip

Stop immediately. Record the requested path, `pcall` status, return type, and Media Pool contents. Do not install codecs, transcode, move source files, or import the rest of the batch.

## Display artifacts

- RCM Only already abnormal: inspect source LED/moire/chroma noise revealed by normal Rec.709 contrast.
- RCM Only normal, Neutral Safe abnormal: reduce grading strength, starting with Color Boost.
- Resolve and master normal, delivery abnormal: investigate codec, encoder, profile, chroma, bitrate, GOP, hardware encoding, and secondary compression. Do not change color to compensate.
