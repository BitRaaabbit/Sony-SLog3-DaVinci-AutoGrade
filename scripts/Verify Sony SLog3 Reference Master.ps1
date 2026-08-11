[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Parse-Rate {
    param([string]$Value)
    if ($Value -match '^(-?[0-9]+(?:\.[0-9]+)?)/(-?[0-9]+(?:\.[0-9]+)?)$') {
        $denominator = [double]$Matches[2]
        if ($denominator -eq 0) { throw "Invalid zero-denominator frame rate: $Value" }
        return ([double]$Matches[1] / $denominator)
    }
    return [double]$Value
}

$statusPath = $null
$reportPath = $null
$result = [ordered]@{
    status = 'FAIL'
    stage = 'bootstrap'
    error = $null
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Postflight config does not exist: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $statusPath = [string]$config.status_path
    $reportPath = [string]$config.report_path
    if ([string]::IsNullOrWhiteSpace($statusPath) -or [string]::IsNullOrWhiteSpace($reportPath)) {
        throw 'Postflight config is missing ASCII status/report paths.'
    }

    $result.stage = 'file_discovery'
    $outputDirectory = [string]$config.output_dir
    $baseName = [string]$config.output_basename
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        throw "Output directory does not exist: $outputDirectory"
    }
    $matches = @(Get-ChildItem -LiteralPath $outputDirectory -File | Where-Object {
        $_.BaseName -eq $baseName -and $_.Extension -ieq '.mov'
    })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $baseName.mov output; found $($matches.Count)."
    }
    $output = $matches[0]

    $result.stage = 'ffprobe'
    $ffprobe = [string]$config.ffprobe_path
    if (-not (Test-Path -LiteralPath $ffprobe -PathType Leaf)) {
        throw "Verified ffprobe binary does not exist: $ffprobe"
    }
    $probeText = & $ffprobe -v error -count_frames -show_streams -show_format -of json $output.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe failed with exit code $LASTEXITCODE`: $($probeText -join ' ')"
    }
    $probe = ($probeText -join [Environment]::NewLine) | ConvertFrom-Json
    $video = @($probe.streams | Where-Object { $_.codec_type -eq 'video' })
    $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
    if ($video.Count -ne 1) { throw "Expected one video stream; found $($video.Count)." }
    if ($audio.Count -ne 1) { throw "Expected one audio stream; found $($audio.Count)." }
    $video = $video[0]
    $audio = $audio[0]

    $fpsText = if ($video.avg_frame_rate -and $video.avg_frame_rate -ne '0/0') {
        [string]$video.avg_frame_rate
    } else {
        [string]$video.r_frame_rate
    }
    $fps = Parse-Rate $fpsText
    $framesText = if ($video.nb_read_frames) { [string]$video.nb_read_frames } else { [string]$video.nb_frames }
    if ([string]::IsNullOrWhiteSpace($framesText) -or $framesText -eq 'N/A') {
        throw 'ffprobe did not return a video frame count.'
    }
    $frames = [int64]$framesText
    $durationText = if ($probe.format.duration) { [string]$probe.format.duration } else { [string]$video.duration }
    $duration = [double]::Parse($durationText, [Globalization.CultureInfo]::InvariantCulture)
    $audioDuration = if ($audio.duration) {
        [double]::Parse([string]$audio.duration, [Globalization.CultureInfo]::InvariantCulture)
    } else {
        $duration
    }

    $result.stage = 'validation'
    $checks = [ordered]@{
        container_mov = ([string]$probe.format.format_name -match 'mov')
        codec_dnxhr = ([string]$video.codec_name -eq 'dnxhd')
        profile_hqx = ([string]$video.profile -match 'DNxHR HQX')
        pixel_format_10bit_422 = ([string]$video.pix_fmt -eq 'yuv422p10le')
        width = ([int]$video.width -eq [int]$config.expected_width)
        height = ([int]$video.height -eq [int]$config.expected_height)
        fps = ([math]::Abs($fps - [double]$config.expected_fps) -lt 0.001)
        frames = ($frames -eq [int64]$config.expected_frames)
        duration = ([math]::Abs($duration - [double]$config.expected_duration) -le 0.01)
        audio_pcm = ([string]$audio.codec_name -match '^pcm_')
        audio_sample_rate = ([int]$audio.sample_rate -eq [int]$config.expected_audio_sample_rate)
        audio_channels = ([int]$audio.channels -eq [int]$config.expected_audio_channels)
        audio_duration = ([math]::Abs($audioDuration - [double]$config.expected_duration) -le 0.01)
    }
    $failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
    if ($failed.Count -gt 0) {
        throw "Master validation failed: $($failed -join ', ')"
    }

    $result.status = 'PASS'
    $result.stage = 'complete'
    $result.output_path = $output.FullName
    $result.size_bytes = [int64]$output.Length
    $result.sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $output.FullName).Hash
    $result.container = [string]$probe.format.format_name
    $result.video_codec = [string]$video.codec_name
    $result.video_profile = [string]$video.profile
    $result.pixel_format = [string]$video.pix_fmt
    $result.width = [int]$video.width
    $result.height = [int]$video.height
    $result.fps = $fps
    $result.frames = $frames
    $result.duration = $duration
    $result.audio_codec = [string]$audio.codec_name
    $result.audio_sample_rate = [int]$audio.sample_rate
    $result.audio_channels = [int]$audio.channels
    $result.audio_duration = $audioDuration
    $result.checks = $checks
} catch {
    $result.error = $_.Exception.Message
} finally {
    if ($reportPath) {
        Write-Utf8NoBom -Path $reportPath -Text ($result | ConvertTo-Json -Depth 8)
    }
    if ($statusPath) {
        Write-Utf8NoBom -Path $statusPath -Text ([string]$result.status + "`n")
    }
}

if ($result.status -ne 'PASS') { exit 1 }
exit 0
