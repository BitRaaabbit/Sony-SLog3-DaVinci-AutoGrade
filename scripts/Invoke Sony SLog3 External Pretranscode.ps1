[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Parse-Rate {
    param([string]$Value)
    if ($Value -match '^(-?[0-9]+(?:\.[0-9]+)?)/(-?[0-9]+(?:\.[0-9]+)?)$') {
        $denominator = [double]$Matches[2]
        if ($denominator -eq 0) { throw "Invalid zero-denominator rate: $Value" }
        return ([double]$Matches[1] / $denominator)
    }
    return [double]$Value
}

function Get-MediaFacts {
    param([string]$Path, [bool]$CountFrames)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Media file is missing: $Path" }
    $arguments = @('-v', 'error')
    if ($CountFrames) { $arguments += '-count_frames' }
    $arguments += @('-show_streams', '-show_format', '-of', 'json', '--', $Path)
    $text = & ([string]$script:Config.ffprobe_path) @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed ($LASTEXITCODE): $($text -join ' ')" }
    $probe = (($text -join [Environment]::NewLine) | ConvertFrom-Json)
    $video = @($probe.streams | Where-Object { $_.codec_type -eq 'video' })
    $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
    if ($video.Count -ne 1) { throw "Expected one video stream; found $($video.Count): $Path" }
    $v = $video[0]
    $frameText = if ($CountFrames -and $v.nb_read_frames) { $v.nb_read_frames } else { $v.nb_frames }
    [ordered]@{
        path = $Path
        size = (Get-Item -LiteralPath $Path).Length
        format_name = [string]$probe.format.format_name
        duration = [double]$probe.format.duration
        codec = [string]$v.codec_name
        profile = [string]$v.profile
        pix_fmt = [string]$v.pix_fmt
        width = [int]$v.width
        height = [int]$v.height
        fps = Parse-Rate $(if ($v.avg_frame_rate -and $v.avg_frame_rate -ne '0/0') { $v.avg_frame_rate } else { $v.r_frame_rate })
        frames = [int64]$frameText
        bits = if ($v.bits_per_raw_sample) { [int]$v.bits_per_raw_sample } elseif ([string]$v.pix_fmt -match '10') { 10 } else { 0 }
        range = [string]$v.color_range
        matrix = [string]$v.color_space
        transfer = [string]$v.color_transfer
        primaries = [string]$v.color_primaries
        audio_count = $audio.Count
        audio_codec = if ($audio.Count -eq 1) { [string]$audio[0].codec_name } else { '' }
        audio_rate = if ($audio.Count -eq 1) { [int]$audio[0].sample_rate } else { 0 }
        audio_channels = if ($audio.Count -eq 1) { [int]$audio[0].channels } else { 0 }
    }
}

function Assert-Source {
    param($Facts, $Clip)
    if ($Facts.codec -ne 'h264' -or $Facts.profile -ne 'High 4:2:2') { throw 'Source codec/profile is outside the verified batch.' }
    if ($Facts.pix_fmt -ne 'yuv422p10le' -or $Facts.width -ne 3840 -or $Facts.height -ne 2160) { throw 'Source pixel format or geometry mismatch.' }
    if ([math]::Abs($Facts.fps - 50.0) -gt 0.001 -or $Facts.range -ne 'pc') { throw 'Source FPS/range mismatch.' }
    if ($Facts.frames -ne [int64]$Clip.frames) { throw "Source frame-count mismatch: $($Facts.frames) vs $($Clip.frames)" }
    if ([math]::Abs($Facts.duration - [double]$Clip.duration) -gt 0.02) { throw 'Source duration mismatch.' }
    if ($Facts.audio_count -ne 1 -or $Facts.audio_rate -ne 48000 -or $Facts.audio_channels -ne 2) { throw 'Source audio baseline mismatch.' }
}

function Assert-Working {
    param($Facts, $Clip)
    if ($Facts.codec -ne 'dnxhd' -or $Facts.profile -ne 'DNXHR HQX') { throw 'Working codec/profile mismatch.' }
    if ($Facts.pix_fmt -ne 'yuv422p10le' -or $Facts.bits -ne 10) { throw 'Working media is not 10-bit 4:2:2.' }
    if ($Facts.width -ne 3840 -or $Facts.height -ne 2160 -or [math]::Abs($Facts.fps - 50.0) -gt 0.001) { throw 'Working geometry/FPS mismatch.' }
    if ($Facts.frames -ne [int64]$Clip.frames) { throw "Working frame-count mismatch: $($Facts.frames) vs $($Clip.frames)" }
    if ([math]::Abs($Facts.duration - [double]$Clip.duration) -gt 0.02) { throw 'Working duration mismatch.' }
    if ($Facts.range -ne 'tv') { throw 'Working media is not codec-compliant limited/video range.' }
    if ($Facts.audio_count -ne 1 -or $Facts.audio_codec -notmatch '^pcm_' -or $Facts.audio_rate -ne 48000 -or $Facts.audio_channels -ne 2) { throw 'Working PCM audio mismatch.' }
}

function Assert-WithinRoot {
    param([string]$Path, [string]$Root)
    $full = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside declared working root: $full" }
    return $full
}

function Move-ToQuarantine {
    param([string]$Path, [string]$Reason)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $full = Assert-WithinRoot -Path $Path -Root ([string]$script:Config.allowed_cleanup_root)
    [IO.Directory]::CreateDirectory([string]$script:QuarantineDir) | Out-Null
    $destination = Join-Path $script:QuarantineDir (([IO.Path]::GetFileName($full)) + '.' + $Reason + '.' + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
    Move-Item -LiteralPath $full -Destination $destination
    return $destination
}

function Save-State {
    $manifest = [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString('o')
        status = $script:State.status
        total = $script:State.total
        success = $script:State.success
        review_needed = $script:State.review_needed
        entries = @($script:State.entries)
    }
    Write-Utf8NoBom -Path ([string]$script:Config.manifest_path) -Text (($manifest | ConvertTo-Json -Depth 8) + "`n")
    $jsonHash = (Get-FileHash -LiteralPath ([string]$script:Config.manifest_path) -Algorithm SHA256).Hash
    $luaLines = @(
        'return {',
        '  schema_version = 1,',
        "  status = `"$($script:State.status)`"," ,
        "  total = $($script:State.total),",
        "  success = $($script:State.success),",
        "  review_needed = $($script:State.review_needed),",
        "  manifest_json_sha256 = `"$jsonHash`"," ,
        '  entries = {'
    )
    foreach ($entry in $script:State.entries) {
        $finalPath = Join-Path ([string]$script:Config.final_dir) (([string]$entry.stem) + '_NEUTRAL_SAFE_MASTER.mov')
        $finalStatus = if (Test-Path -LiteralPath $finalPath) { 'EXISTS' } else { 'ABSENT' }
        function Q([string]$Value) { return '"' + $Value.Replace('\', '/').Replace('"', '\"') + '"' }
        $luaLines += '    {'
        foreach ($pair in @(
            @('stem', (Q ([string]$entry.stem))), @('original_path', (Q ([string]$entry.original_path))),
            @('working_path', (Q ([string]$entry.working_path))), @('working_sha256', (Q ([string]$entry.working_sha256))),
            @('working_size', [string]$entry.working_size), @('frames', [string]$entry.frames), @('duration', ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:0.###}', [double]$entry.duration))),
            @('codec', (Q ([string]$entry.codec))), @('profile', (Q ([string]$entry.profile))), @('pix_fmt', (Q ([string]$entry.pix_fmt))),
            @('width', [string]$entry.width), @('height', [string]$entry.height), @('fps', ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:0.###}', [double]$entry.fps))),
            @('working_preflight_status', (Q ([string]$entry.working_preflight_status))), @('final_path', (Q $finalPath)), @('final_preflight_status', (Q $finalStatus))
        )) { $luaLines += "      $($pair[0]) = $($pair[1])," }
        $luaLines += '    },'
    }
    $luaLines += '  }'; $luaLines += '}'
    Write-Utf8NoBom -Path ([string]$script:Config.manifest_lua_path) -Text (($luaLines -join "`n") + "`n")
    $lines = @(
        '# Sony S-Log3 external pretranscode report', '',
        "- Status: ``$($script:State.status)``",
        "- Total: ``$($script:State.total)``",
        "- Success: ``$($script:State.success)``",
        "- ReviewNeeded: ``$($script:State.review_needed)``", '',
        '## Clips', ''
    )
    foreach ($entry in $script:State.entries) {
        $lines += "- ``$($entry.stem) | $($entry.working_preflight_status) | $($entry.working_path) | $($entry.working_sha256)``"
    }
    Write-Utf8NoBom -Path ([string]$script:Config.report_path) -Text (($lines -join "`n") + "`n")
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Config missing: $ConfigPath" }
$script:Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($tool in @([string]$script:Config.ffmpeg_path, [string]$script:Config.ffprobe_path)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Required tool missing: $tool" }
}
[IO.Directory]::CreateDirectory([string]$script:Config.working_root) | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent ([string]$script:Config.manifest_path))) | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent ([string]$script:Config.manifest_lua_path))) | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent ([string]$script:Config.report_path))) | Out-Null
$script:QuarantineDir = Join-Path ([string]$script:Config.allowed_cleanup_root) ('quarantine_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))

foreach ($candidate in @($script:Config.incomplete_candidates)) {
    if (Test-Path -LiteralPath ([string]$candidate) -PathType Leaf) {
        $quarantined = Move-ToQuarantine -Path ([string]$candidate) -Reason 'confirmed_incomplete'
        Write-Output "QUARANTINED $candidate -> $quarantined"
    }
}

$script:State = [ordered]@{status = 'RUNNING'; total = @($script:Config.clips).Count; success = 0; review_needed = 0; entries = [Collections.ArrayList]::new()}
Save-State

$index = 0
foreach ($clip in @($script:Config.clips)) {
    $index++
    $stem = [string]$clip.stem
    $source = [string]$clip.original_path
    $final = [string]$clip.working_path
    $partial = [IO.Path]::Combine((Split-Path -Parent $final), (([IO.Path]::GetFileNameWithoutExtension($final)) + '.partial.mov'))
    Write-Output "PROGRESS $index/$($script:State.total) $stem PREFLIGHT"
    try {
        Assert-WithinRoot -Path $final -Root ([string]$script:Config.working_root) | Out-Null
        Assert-WithinRoot -Path $partial -Root ([string]$script:Config.working_root) | Out-Null
        $sourceFacts = Get-MediaFacts -Path $source -CountFrames $true
        Assert-Source -Facts $sourceFacts -Clip $clip

        if (Test-Path -LiteralPath $partial -PathType Leaf) { Move-ToQuarantine -Path $partial -Reason 'stale_partial' | Out-Null }
        $reuse = $false
        if (Test-Path -LiteralPath $final -PathType Leaf) {
            try {
                $workingFacts = Get-MediaFacts -Path $final -CountFrames $true
                Assert-Working -Facts $workingFacts -Clip $clip
                $reuse = $true
            }
            catch {
                Move-ToQuarantine -Path $final -Reason 'invalid_existing' | Out-Null
            }
        }

        if (-not $reuse) {
            $drive = [IO.DriveInfo]::new(([IO.Path]::GetPathRoot($final)))
            $required = [int64]([double]$script:Config.estimated_bytes_per_second * [double]$clip.duration + [double]$script:Config.reserve_bytes)
            if ($drive.AvailableFreeSpace -lt $required) { throw "Disk gate failed: free=$($drive.AvailableFreeSpace), required=$required" }
            $logPath = Join-Path ([string]$script:Config.log_dir) ($stem + '_external_pretranscode_ffmpeg.log')
            [IO.Directory]::CreateDirectory((Split-Path -Parent $logPath)) | Out-Null
            $arguments = @(
                '-hide_banner', '-nostdin', '-n', '-i', $source,
                '-map', '0:v:0', '-map', '0:a:0?', '-map_metadata', '0',
                '-c:v', 'dnxhd', '-profile:v', 'dnxhr_hqx', '-pix_fmt', 'yuv422p10le',
                '-c:a', 'copy', $partial
            )
            Write-Output "PROGRESS $index/$($script:State.total) $stem TRANSCODE"
            $oldPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & ([string]$script:Config.ffmpeg_path) @arguments 2>&1 | Out-File -LiteralPath $logPath -Encoding utf8
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = $oldPreference
            if ($exitCode -ne 0) { throw "ffmpeg failed with exit code $exitCode" }
            $workingFacts = Get-MediaFacts -Path $partial -CountFrames $true
            Assert-Working -Facts $workingFacts -Clip $clip
            if (Test-Path -LiteralPath $final) { throw "Atomic target collision after preflight: $final" }
            [IO.File]::Move($partial, $final)
        }

        $workingFacts = Get-MediaFacts -Path $final -CountFrames $true
        Assert-Working -Facts $workingFacts -Clip $clip
        $hash = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash
        $entry = [ordered]@{
            stem = $stem; original_path = $source
            original_codec = $sourceFacts.codec; original_profile = $sourceFacts.profile
            original_pix_fmt = $sourceFacts.pix_fmt; original_range = $sourceFacts.range
            working_path = $final; working_sha256 = $hash; working_size = $workingFacts.size
            frames = $workingFacts.frames; duration = $workingFacts.duration
            codec = $workingFacts.codec; profile = $workingFacts.profile; pix_fmt = $workingFacts.pix_fmt
            width = $workingFacts.width; height = $workingFacts.height; fps = $workingFacts.fps
            audio_codec = $workingFacts.audio_codec; audio_rate = $workingFacts.audio_rate; audio_channels = $workingFacts.audio_channels
            range_transform = 'FULL_TO_LIMITED_NORMALIZATION'
            working_preflight_status = 'PASS'
        }
        [void]$script:State.entries.Add($entry)
        $script:State.success++
        Write-Output "PROGRESS $index/$($script:State.total) $stem PASS"
    }
    catch {
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Move-ToQuarantine -Path $partial -Reason 'failed_partial' | Out-Null }
        [void]$script:State.entries.Add([ordered]@{stem = $stem; original_path = $source; working_path = $final; working_preflight_status = 'REVIEW_NEEDED'; error = $_.Exception.Message})
        $script:State.review_needed++
        Write-Output "PROGRESS $index/$($script:State.total) $stem REVIEW_NEEDED $($_.Exception.Message)"
    }
    Save-State
}

$script:State.status = if ($script:State.review_needed -eq 0) { 'EXTERNAL_PRETRANSCODE_PASS' } else { 'EXTERNAL_PRETRANSCODE_COMPLETED_WITH_REVIEW' }
Save-State
Write-Output "FINAL $($script:State.status) success=$($script:State.success) review_needed=$($script:State.review_needed)"
if ($script:State.review_needed -gt 0) { exit 2 }
