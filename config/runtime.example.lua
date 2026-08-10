-- Copy this file to config/runtime.local.lua and keep the local copy private.
-- The installer should copy the local profile to:
--   %TEMP%\SonySLog3AutoGrade\runtime.lua
return {
    schema_version = 2,
    mode = "diagnostic",
    project = {
        name = "Sony_SLog3_Diagnostic_Project",
        allow_create = true,
        allow_load_existing = false,
        -- Required. Select a human-verified Project Format preset matching the
        -- confirmed batch resolution and frame rate; never guess this name.
        preset_name = ""
    },
    paths = {
        input_dir = "C:/Path/To/ReadOnlySource",
        output_dir = "C:/Path/To/Output",
        drp_backup_dir = "C:/Path/To/ASCII/Staging"
    },
    batch = {
        width = 1920,
        height = 1080,
        frame_rate = 25.0,
        gamma = "S-Log3",
        primaries = "Sony S-Gamut3.Cine",
        metadata_confirmation = "camera_or_sidecar_metadata",
        camera_model = "report_only",
        source_files = {
            "SONY_SLOG3_CLIP_001.MP4",
            "SONY_SLOG3_CLIP_002.MP4",
            "SONY_SLOG3_CLIP_003.MP4"
        }
    },
    diagnostic = {
        first_clip_only = true,
        timeline_name = "Sony_SLog3_Diagnostic"
    },
    look = {
        name = "Neutral Safe",
        status = "test_candidate_not_approved",
        approved = false,
        reference_timeline = ""
    },
    authorization = {
        test_approved = false,
        batch_approved = false,
        start_rendering = false,
        max_test_clips = 3,
        max_batch_size = 10
    },
    selection = {
        test_files = {
            "SONY_SLOG3_CLIP_001.MP4",
            "SONY_SLOG3_CLIP_002.MP4",
            "SONY_SLOG3_CLIP_003.MP4"
        },
        batch_offset = 1
    },
    output = {
        suffix = "_Rec709_NeutralSafe",
        container = "MP4",
        codec = "H.264",
        quality = "Best",
        audio_codec = "aac",
        audio_sample_rate = 48000
    }
}
