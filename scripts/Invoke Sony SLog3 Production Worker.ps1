[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ArtifactGate', 'PrepareDirectories', 'InspectFinal', 'Transcode', 'VerifyFinal', 'DeleteWorking', 'DiskGate', 'PublishReport')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Write-Result {
    param([System.Collections.IDictionary]$Values)
    $lines = foreach ($key in $Values.Keys) {
        $value = [string]$Values[$key]
        $value = $value.Replace("`r", ' ').Replace("`n", ' ')
        "$key=$value"
    }
    Write-Utf8NoBom -Path ([string]$script:Config.result_path) -Text (($lines -join "`n") + "`n")
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

function Invoke-Probe {
    param([string]$Path, [bool]$CountFrames)
    $arguments = @('-v', 'error')
    if ($CountFrames) { $arguments += '-count_frames' }
    $arguments += @('-show_streams', '-show_format', '-of', 'json', '--', $Path)
    $text = & ([string]$script:Config.ffprobe_path) @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed ($LASTEXITCODE): $($text -join ' ')" }
    return (($text -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Get-MediaFacts {
    param([string]$Path, [bool]$CountFrames)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Media file is missing: $Path" }
    $probe = Invoke-Probe -Path $Path -CountFrames $CountFrames
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
    param($Facts)
    if ($Facts.codec -ne 'h264' -or $Facts.profile -ne 'High 4:2:2') { throw 'Source codec/profile is outside the verified homogeneous batch.' }
    if ($Facts.pix_fmt -ne 'yuv422p10le' -or $Facts.width -ne 3840 -or $Facts.height -ne 2160) { throw 'Source pixel format or geometry mismatch.' }
    if ([math]::Abs($Facts.fps - 50.0) -gt 0.001) { throw 'Source FPS mismatch.' }
    if ($Facts.range -ne 'pc') { throw 'Source is not declared full range.' }
    if ($Facts.frames -ne [int64]$script:Config.expected_frames) { throw 'Source frame-count mismatch.' }
    if ([math]::Abs($Facts.duration - [double]$script:Config.expected_duration) -gt 0.02) { throw 'Source duration mismatch.' }
    if ($Facts.audio_count -ne 1 -or $Facts.audio_rate -ne 48000 -or $Facts.audio_channels -ne 2) { throw 'Source audio baseline mismatch.' }
}

function Assert-Working {
    param($Facts)
    if ($Facts.codec -ne 'dnxhd' -or $Facts.profile -ne 'DNXHR HQX') { throw 'Working codec/profile mismatch.' }
    if ($Facts.pix_fmt -ne 'yuv422p10le' -or $Facts.bits -ne 10) { throw 'Working media is not DNxHR HQX 10-bit 4:2:2.' }
    if ($Facts.width -ne 3840 -or $Facts.height -ne 2160 -or [math]::Abs($Facts.fps - 50.0) -gt 0.001) { throw 'Working geometry/FPS mismatch.' }
    if ($Facts.frames -ne [int64]$script:Config.expected_frames) { throw 'Working frame-count mismatch.' }
    if ([math]::Abs($Facts.duration - [double]$script:Config.expected_duration) -gt 0.02) { throw 'Working duration mismatch.' }
    if ($Facts.range -ne 'tv') { throw 'Working range is not codec-compliant limited/video range.' }
    if ($Facts.audio_count -ne 1 -or $Facts.audio_rate -ne 48000 -or $Facts.audio_channels -ne 2) { throw 'Working audio mismatch.' }
}

function Assert-Final {
    param($Facts)
    Assert-Working -Facts $Facts
    if ($Facts.format_name -notmatch 'mov') { throw 'Final container is not MOV.' }
    if ($Facts.audio_codec -notmatch '^pcm_') { throw 'Final audio is not PCM.' }
}

function Invoke-Transcode {
    $source = [string]$script:Config.source_path
    $working = [string]$script:Config.working_path
    $sourceFacts = Get-MediaFacts -Path $source -CountFrames $false
    Assert-Source -Facts $sourceFacts

    if (Test-Path -LiteralPath $working -PathType Leaf) {
        $workingFacts = Get-MediaFacts -Path $working -CountFrames $true
        Assert-Working -Facts $workingFacts
        Write-Result ([ordered]@{
            status = 'PASS'; stage = 'working_reuse'; working_path = $working
            working_size = $workingFacts.size; working_frames = $workingFacts.frames
            working_duration = $workingFacts.duration; transcode = 'SKIP_VERIFIED_EXISTING'
        })
        return
    }

    $workingDirectory = Split-Path -Parent $working
    [IO.Directory]::CreateDirectory($workingDirectory) | Out-Null
    [IO.Directory]::CreateDirectory([string]$script:Config.report_dir) | Out-Null
    $logPath = Join-Path ([string]$script:Config.report_dir) (([string]$script:Config.stem) + '_transcode_ffmpeg.log')
    $arguments = @(
        '-hide_banner', '-nostdin', '-n', '-i', $source,
        '-map', '0:v:0', '-map', '0:a:0?', '-map_metadata', '0',
        '-c:v', 'dnxhd', '-profile:v', 'dnxhr_hqx', '-pix_fmt', 'yuv422p10le',
        '-c:a', 'copy', $working
    )
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $ffmpegOutput = & ([string]$script:Config.ffmpeg_path) @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    Write-Utf8NoBom -Path $logPath -Text (($ffmpegOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    if ($exitCode -ne 0) { throw "ffmpeg compatibility transcode failed with exit code $exitCode" }

    $workingFacts = Get-MediaFacts -Path $working -CountFrames $true
    Assert-Working -Facts $workingFacts
    Write-Result ([ordered]@{
        status = 'PASS'; stage = 'transcode_complete'; working_path = $working
        working_size = $workingFacts.size; working_frames = $workingFacts.frames
        working_duration = $workingFacts.duration; working_range = $workingFacts.range
        working_matrix = $workingFacts.matrix; working_transfer = $workingFacts.transfer
        working_primaries = $workingFacts.primaries; transcode = 'CREATED'
        ffmpeg_exit_code = $exitCode; log_path = $logPath
    })
}

function Invoke-VerifyFinal {
    $facts = Get-MediaFacts -Path ([string]$script:Config.final_path) -CountFrames $true
    Assert-Final -Facts $facts
    $hash = (Get-FileHash -LiteralPath $facts.path -Algorithm SHA256).Hash
    Write-Result ([ordered]@{
        status = 'PASS'; stage = 'final_postflight'; final_path = $facts.path
        final_size = $facts.size; final_sha256 = $hash; final_codec = $facts.codec
        final_profile = $facts.profile; final_pix_fmt = $facts.pix_fmt
        final_width = $facts.width; final_height = $facts.height; final_fps = $facts.fps
        final_frames = $facts.frames; final_duration = $facts.duration
        final_audio_codec = $facts.audio_codec; final_audio_rate = $facts.audio_rate
        final_audio_channels = $facts.audio_channels; final_master = 'PASS'
    })
}

function Invoke-InspectFinal {
    $path = [string]$script:Config.final_path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Result ([ordered]@{status = 'PASS'; stage = 'inspect_final'; output_policy = 'NEW'; final_path = $path})
        return
    }
    try {
        $facts = Get-MediaFacts -Path $path -CountFrames $true
        Assert-Final -Facts $facts
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Write-Result ([ordered]@{status = 'PASS'; stage = 'inspect_final'; output_policy = 'SKIP_VERIFIED_EXISTING'; final_path = $path; final_size = $facts.size; final_sha256 = $hash})
    }
    catch {
        Write-Result ([ordered]@{status = 'PASS'; stage = 'inspect_final'; output_policy = 'RETRY_NON_OVERWRITE'; final_path = $path; existing_error = $_.Exception.Message})
    }
}

function Invoke-PrepareDirectories {
    foreach ($path in @([string]$script:Config.working_root, [string]$script:Config.final_dir, [string]$script:Config.report_dir)) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw 'Authorized directory declaration is empty.' }
        [IO.Directory]::CreateDirectory($path) | Out-Null
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Could not create authorized directory: $path" }
    }
    Write-Result ([ordered]@{status = 'PASS'; stage = 'prepare_directories'; directories = 'READY'})
}

function Invoke-DeleteWorking {
    $working = [IO.Path]::GetFullPath([string]$script:Config.working_path)
    $root = [IO.Path]::GetFullPath([string]$script:Config.working_root).TrimEnd('\') + '\'
    if (-not $working.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Working cleanup target is outside the authorized working root.' }
    if ([IO.Path]::GetExtension($working) -ine '.mov' -or [IO.Path]::GetFileNameWithoutExtension($working) -notmatch '_DNxHR_HQX(?:_RETRY_[0-9_]+)?$') {
        throw 'Working cleanup target does not match the authorized compatibility filename policy.'
    }
    $protected = [string]$script:Config.protected_working_path
    if (-not [string]::IsNullOrWhiteSpace($protected) -and $working.Equals([IO.Path]::GetFullPath($protected), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Reference working media cleanup is forbidden.'
    }
    if (-not (Test-Path -LiteralPath $working -PathType Leaf)) {
        Write-Result ([ordered]@{status = 'PASS'; stage = 'working_cleanup'; cleanup = 'ALREADY_ABSENT'; working_path = $working})
        return
    }
    Remove-Item -LiteralPath $working -Force
    if (Test-Path -LiteralPath $working) { throw 'Working media still exists after authorized cleanup.' }
    Write-Result ([ordered]@{status = 'PASS'; stage = 'working_cleanup'; cleanup = 'DELETED_VERIFIED_TEMP'; working_path = $working})
}

function Invoke-DiskGate {
    $drive = [IO.DriveInfo]::new(([IO.Path]::GetPathRoot([string]$script:Config.final_path)))
    $required = [int64]$script:Config.required_free_bytes
    if ($drive.AvailableFreeSpace -lt $required) { throw "Disk gate failed: free=$($drive.AvailableFreeSpace), required=$required" }
    Write-Result ([ordered]@{status = 'PASS'; stage = 'disk_gate'; free_bytes = $drive.AvailableFreeSpace; required_free_bytes = $required})
}

function Invoke-ArtifactGate {
    $path = [string]$script:Config.artifact_path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Artifact missing: $path" }
    $item = Get-Item -LiteralPath $path
    if ($item.Length -ne [int64]$script:Config.expected_size) { throw "Artifact size mismatch: $path" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ine [string]$script:Config.expected_sha256) { throw "Artifact SHA-256 mismatch: $path" }
    Write-Result ([ordered]@{status = 'PASS'; stage = 'artifact_gate'; artifact_path = $path; artifact_size = $item.Length; artifact_sha256 = $hash})
}

function Invoke-PublishReport {
    $source = [string]$script:Config.source_report
    $destination = [string]$script:Config.destination_report
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Source report missing: $source" }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'Published report is missing.' }
    Write-Result ([ordered]@{status = 'PASS'; stage = 'publish_report'; destination_report = $destination; report_size = (Get-Item -LiteralPath $destination).Length})
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Config missing: $ConfigPath" }
    $script:Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$script:Config.result_path)) { throw 'Missing result_path.' }
    switch ($Action) {
        'ArtifactGate' { Invoke-ArtifactGate }
        'PrepareDirectories' { Invoke-PrepareDirectories }
        'InspectFinal' { Invoke-InspectFinal }
        'Transcode' { Invoke-Transcode }
        'VerifyFinal' { Invoke-VerifyFinal }
        'DeleteWorking' { Invoke-DeleteWorking }
        'DiskGate' { Invoke-DiskGate }
        'PublishReport' { Invoke-PublishReport }
    }
    exit 0
}
catch {
    if ($script:Config -and $script:Config.result_path) {
        Write-Result ([ordered]@{status = 'FAIL'; stage = $Action; error = $_.Exception.Message})
    }
    exit 1
}
