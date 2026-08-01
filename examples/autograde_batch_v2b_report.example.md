# V2B batch report example (sanitized)

## Summary

- Manifest entries: 12
- Batches: 10 + 2
- Success: 12
- Failed: 0
- Skipped: 0
- ReviewNeeded: 0
- Input root: `<PROJECT_ROOT>/ship`
- Output root: `<PROJECT_ROOT>/ship_output/final`

## Verified grade

- Input: Sony S-Gamut3.Cine / S-Log3
- Timeline: DaVinci Wide Gamut / DaVinci Intermediate
- Output: Rec.709 Gamma 2.4
- V2B node 02: Contrast 1.120, Pivot 0.440, Color Boost 12.00, Saturation 54.00, Highlights -8.00, Temperature 0.0, Tint 0.00

## Example item

| Input | Output | Resolution | Frame rate | Duration | Status |
|---|---|---|---:|---:|---|
| `<PROJECT_ROOT>/ship/FX3_CLIP_001.MP4` | `<PROJECT_ROOT>/ship_output/final/FX3_CLIP_001_Rec709_NeutralV2B.mp4` | 3840×2160 | 59.94 | matches source | Success |

All paths and filenames in this report are placeholders. Real inventories and logs must remain untracked.
