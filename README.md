# Sony S-Log3 DaVinci AutoGrade

A conservative, safety-first DaVinci Resolve workflow for media reliably confirmed as **Sony S-Gamut3.Cine / S-Log3**. Camera model is report metadata, not an eligibility rule.

This branch is a development refactor. Do not treat it as a stable production release until the regression gates in `docs/REGRESSION_TESTS.md` pass on real footage.

## Verified host environment

- DaVinci Resolve 20.3.2 Free on Windows
- Internal Lua launched from `Workspace > Scripts > Utility`
- Internal Resolve object acquired with `app:GetResolve()`
- DaVinci YRGB Color Managed, automatic color management off
- Timeline: DaVinci Wide Gamut / DaVinci Intermediate
- Output: Rec.709 Gamma 2.4
- No LUT

External scripting access is not required. The workflow does not install codecs, plugins, LUTs, Python packages, or executables.

## Design

`Sony SLog3 Diagnostic.lua` loads an ASCII-path runtime profile, validates one homogeneous batch, creates an isolated project, records its untouched initial settings, and applies the exact human-verified Project Format preset named by the private runtime. It immediately reads back Playback FPS, Timeline FPS, width, and height and stops on any mismatch. Project Format and color are deliberately separate: only after the preset gate passes does the script configure and verify the fixed Sony color-management transform, import the first declared source, create one diagnostic timeline, save, and stop on Edit.

`Sony SLog3 AutoGrade.lua` is gated behind all of the following:

- a successful diagnostic project;
- representative test selection;
- a human-approved reference timeline;
- explicit test or batch authorization;
- explicit render-start authorization;
- an empty render queue;
- maximum three clips for a first test and ten clips per batch invocation.

The automation copies a verified reference grade. It does not encode permanent Neutral Safe Primary values in code.

## Install

1. Copy the two files under `scripts/` to:

   `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility\`

2. In Resolve, create and verify a Project Preset matching the confirmed batch resolution and frame rate. Copy `config/runtime.example.lua` to the ignored `config/runtime.local.lua`, enter that exact `preset_name`, and replace all sample values with confirmed local metadata and paths.
3. Copy the local profile to:

   `%TEMP%\SonySLog3AutoGrade\runtime.lua`

4. Open a disposable Resolve project and run `Workspace > Scripts > Utility > Sony SLog3 Diagnostic` once.
5. Read `%TEMP%\SonySLog3AutoGrade\diagnostic.log` and `diagnostic_report.md` before any grading or rendering.

The runtime profile is deliberately stored at an ASCII-only path because Resolve's internal Lua `io.open` may fail on Unicode Windows paths. Unicode media paths are still passed directly to Resolve APIs and must be tested rather than assumed unsupported.

## Neutral Safe

Neutral Safe targets natural, clean event and documentary images without an obvious filter. Its candidate range is intentionally conservative: Contrast around 1.08, Pivot around 0.44, Color Boost 0–4, Saturation around 50, Highlights around -4, Temperature 0, Tint 0.

These are **test candidates**, not permanent defaults. A human must approve the reference timeline. Global warming, strong Color Boost, strong saturation, sharpening, Midtone Detail, clarity, grain, full-frame noise reduction, and style LUTs are disabled by policy.

## Safety invariants

- Source media is read-only: never move, rename, delete, overwrite, or render back into the source tree.
- Unknown or mixed gamma, primaries, frame rate, or resolution stops preflight.
- Existing output is never silently overwritten.
- A camera model never substitutes for reliable gamma/primaries confirmation.
- Grading and delivery encoding are diagnosed separately.
- Full batch processing requires a reviewed small-scale test.

See [workflow](docs/WORKFLOW.md), [troubleshooting](docs/TROUBLESHOOTING.md), and [regression tests](docs/REGRESSION_TESTS.md).

## Compatibility

This project is designed only for media confirmed as Sony S-Gamut3.Cine / S-Log3. It does not promise correct transforms for other cameras, gamuts, Log curves, raw formats, operating systems, or Resolve versions.

## License

MIT. See `LICENSE`.
