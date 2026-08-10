# Changelog

## Unreleased — generic Sony S-Log3 workflow

### Changed

- Replaced the camera-specific three-script layout with one diagnostic script and one gated AutoGrade runner.
- Moved resolution, playback/timeline FPS, paths, project name, manifests, and authorization into a private runtime profile.
- Removed the old V2B values as production defaults. The historical values (Contrast 1.120, Pivot 0.440, Color Boost 12, Saturation 54, Highlights -8) remain regression context only.
- Added the Neutral Safe test-candidate policy without claiming permanent look parameters.
- Added an Original Log → RCM Only → Neutral Safe → high-quality master → delivery codec display/LED diagnostic chain.

### Fixed

- Internal Resolve Free scripts now use the empirically verified `app:GetResolve()` path.
- Logging now initializes under `%TEMP%\SonySLog3AutoGrade` with emergency fallback, `xpcall`, traceback, and stage markers.
- Dynamic project setup sets and verifies Playback FPS before Timeline FPS. A production diagnostic demonstrated that setting Timeline FPS first could leave Playback FPS locked at its prior value and stop preflight.
- Unicode media paths are passed to Resolve APIs while Lua file logs/config are staged at ASCII-only paths.

### Safety

- Mixed or unknown batch metadata stops preflight.
- Source overwrite and output overwrite remain prohibited.
- AutoGrade requires a human-approved reference grade plus explicit test/batch and render-start authorization.

## v0.1.0 legacy

The original camera-specific implementation is preserved without history rewriting at tag `v0.1.0-fx3-legacy`.
