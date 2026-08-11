-- Copy this file to config/runtime.local.lua and keep the local copy private.
-- The installer should copy the local profile to:
--   %TEMP%\SonySLog3AutoGrade\runtime.lua
return {
    schema_version = 2,
    mode = "diagnostic",
    -- Produced by the external deployment/preflight step. Diagnostic logs
    -- these values so a stable launcher can load newer formal logic without
    -- requiring a new Resolve menu entry for every commit.
    deployment = {
        logic_commit = "PUBLIC_COMMIT_SHORT_SHA",
        logic_sha256 = "PUBLIC_SCRIPT_SHA256"
    },
    project = {
        name = "Sony_SLog3_Diagnostic_Project",
        allow_create = true,
        allow_load_existing = false,
        -- Set true only to resume an exact, previously validated one-clip
        -- diagnostic failure state. Zero timelines is accepted; one timeline
        -- is accepted only when its name and sole validated source match.
        -- Also set allow_create=false and allow_load_existing=true.
        resume_existing_diagnostic = false,
        -- Recommended compatibility path: capture a verified blank project as
        -- a private DRP, then import it under the unique diagnostic name.
        bootstrap_method = "drp_template",
        template_path = "C:/ASCII/Path/To/Templates/SonySLog3_Format_Base.drp",
        template_capture_project_name = "Sony_SLog3_Format_Template_Source",
        -- Optional alternative when GetPresetList exposes an exact verified
        -- preset. Ignored by the drp_template method.
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
        -- Set true only after every declared source has been confirmed to use
        -- the same gamma and primaries. False/missing stops the input-policy gate.
        homogeneous_metadata_verified = false,
        camera_model = "report_only",
        source_files = {
            "SONY_SLOG3_CLIP_001.MP4",
            "SONY_SLOG3_CLIP_002.MP4",
            "SONY_SLOG3_CLIP_003.MP4"
        },
        -- Optional compatibility-media mapping. Paths are absolute so the
        -- authoritative camera source and Resolve working representation can
        -- never be confused. Keep all real paths and hashes private.
        media_mappings = {
            {
                mapping_id = "EXAMPLE_MAPPING_001",
                original_file = "C:/Path/To/ReadOnlySource/SONY_SLOG3_CLIP_001.MP4",
                working_file = "C:/Path/To/PrivateWorkingMedia/SONY_SLOG3_CLIP_001_DNxHR_HQX.mov",
                working_media_required = true,
                compatibility_reason = "UNSUPPORTED_NATIVE_VIDEO_DECODE",
                original_gamma = "S-Log3",
                original_primaries = "Sony S-Gamut3.Cine",
                range_transform = "FULL_TO_LIMITED_NORMALIZATION",
                signal_equivalence_status = "PASS",
                resolve_decode_status = "NOT_TESTED",
                working_codec = "DNxHR HQX",
                working_pixel_format = "10-bit 4:2:2",
                working_width = 1920,
                working_height = 1080,
                working_frame_rate = 25.0,
                working_frames = 1000,
                working_duration = 40.0,
                working_sha256 = "PRIVATE_SHA256"
            }
        },
        -- Private, hash-bound evidence produced outside Resolve. The internal
        -- script validates this schema and exact mapping, but never asks
        -- Resolve MediaStorage to enumerate or decode ORIGINAL_SOURCE_MEDIA.
        external_media_attestations = {
            {
                attestation_version = 1,
                mapping_id = "EXAMPLE_MAPPING_001",
                external_preflight_timestamp = "2026-01-01T00:00:00+00:00",
                external_preflight_tool = "filesystem+sha256+ffprobe+signal-equivalence",
                original_verification_status = "PASS",
                working_verification_status = "PASS",
                original_file = "C:/Path/To/ReadOnlySource/SONY_SLOG3_CLIP_001.MP4",
                original_sha256 = "PRIVATE_ORIGINAL_SHA256",
                original_size = 100000000,
                original_codec = "h264",
                original_profile = "High 4:2:2",
                original_pix_fmt = "yuv422p10le",
                original_width = 1920,
                original_height = 1080,
                original_frame_rate = 25.0,
                original_frame_count = 1000,
                original_duration = 40.0,
                original_gamma = "S-Log3",
                original_primaries = "Sony S-Gamut3.Cine",
                metadata_confirmation = "camera_or_sidecar_metadata",
                working_file = "C:/Path/To/PrivateWorkingMedia/SONY_SLOG3_CLIP_001_DNxHR_HQX.mov",
                working_sha256 = "PRIVATE_WORKING_SHA256",
                working_size = 1000000000,
                working_codec = "dnxhd",
                working_profile = "DNxHR HQX",
                working_pix_fmt = "10-bit 4:2:2",
                working_width = 1920,
                working_height = 1080,
                working_frame_rate = 25.0,
                working_frame_count = 1000,
                working_duration = 40.0,
                working_audio_codec = "pcm_s16be",
                original_metadata_verified = true,
                working_media_verified = true,
                signal_equivalence_status = "PASS",
                signal_equivalence_evidence = "private full-frame YUV comparison report",
                range_transform = "FULL_TO_LIMITED_NORMALIZATION",
                input_color_policy = "FROM_VERIFIED_ORIGINAL_SOURCE_METADATA"
            }
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
