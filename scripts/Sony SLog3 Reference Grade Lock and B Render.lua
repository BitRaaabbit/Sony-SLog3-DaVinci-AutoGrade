-- Sony SLog3 Reference Grade Lock and B Render.lua
-- Locks the human-approved B reference as a DRX and starts exactly one B master render.
-- Does not alter grades, render A, or touch other source media.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ASCII_DIR = TEMP_ROOT .. "/SonySLog3AutoGrade"
local PROFILE_PATH = ASCII_DIR .. "/runtime.lua"
local LOG_PATH = ASCII_DIR .. "/reference_grade_lock.log"
local REPORT_PATH = ASCII_DIR .. "/reference_grade_lock_report.md"
local ARTIFACT_DIR = ASCII_DIR .. "/reference_grades"
local EMERGENCY_PATH = TEMP_ROOT .. "/SonySLog3AutoGrade_reference_grade_lock_emergency.log"

local state = {
    status = "STARTING", stage = "bootstrap", project = "", timeline = "",
    drx_path = "", drx_size = 0, drx_sha256 = "", render_job_id = "",
    render_start = "NOT_STARTED", output_dir = "", output_name = "",
    errors = {}, warnings = {}
}

local function appendRaw(path, text)
    local handle = io.open(path, "ab")
    if not handle then return false end
    handle:write(text); handle:close(); return true
end
local function quoted(path)
    return '"' .. tostring(path):gsub("/", "\\"):gsub('"', '""') .. '"'
end
local function ensureDirectory(path)
    os.execute("cmd.exe /d /c if not exist " .. quoted(path) .. " mkdir " .. quoted(path) .. " >NUL 2>&1")
end
ensureDirectory(ASCII_DIR)
ensureDirectory(ARTIFACT_DIR)
local function logLine(value)
    if not appendRaw(LOG_PATH, tostring(value or "") .. "\n") then
        appendRaw(EMERGENCY_PATH, tostring(value or "") .. "\n")
    end
end
local function logValue(key, value) logLine(key .. "=" .. tostring(value)) end
local function stage(name) state.stage = name; logLine("STAGE=" .. name) end
local function normalize(value) return string.lower(tostring(value or ""):gsub("%s+", "")) end
local function pathKey(value) return string.lower(tostring(value or ""):gsub("\\", "/")) end
local function isSha256(value)
    local text = tostring(value or "")
    return #text == 64 and text:match("^[0-9A-Fa-f]+$") ~= nil
end
local function fail(message)
    state.errors[#state.errors + 1] = "stage=" .. state.stage .. " | " .. tostring(message)
    error(tostring(message), 0)
end
local function tracebackHandler(value)
    if debug and type(debug.traceback) == "function" then return debug.traceback(tostring(value), 2) end
    return tostring(value)
end
local function fileSize(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local size = handle:seek("end"); handle:close(); return size
end
local function powershellLiteral(value) return "'" .. tostring(value):gsub("'", "''") .. "'" end
local function fileModificationTime(path)
    local resultPath = ASCII_DIR .. "/reference_grades/.mtime.txt"
    os.remove(resultPath)
    local command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
        .. '"$i=Get-Item -LiteralPath ' .. powershellLiteral(path)
        .. ';[IO.File]::WriteAllText(' .. powershellLiteral(resultPath)
        .. ',$i.LastWriteTime.ToString(\'yyyy-MM-dd HH:mm:ss zzz\'),[Text.Encoding]::ASCII)"'
    os.execute(command)
    local handle = io.open(resultPath, "rb")
    if not handle then return "" end
    local value = tostring(handle:read("*a") or ""):gsub("%s+$", "")
    handle:close(); os.remove(resultPath); return value
end
local function calculateSha256(path, resultPath)
    os.remove(resultPath)
    local command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
        .. '"$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '
        .. powershellLiteral(path) .. ').Hash;[IO.File]::WriteAllText('
        .. powershellLiteral(resultPath) .. ',$h,[Text.Encoding]::ASCII)"'
    local a, b, c = os.execute(command)
    logValue("sha256.os_execute.return1", a); logValue("sha256.os_execute.return2", b); logValue("sha256.os_execute.return3", c)
    local handle = io.open(resultPath, "rb")
    if not handle then fail("SHA-256 result file was not created.") end
    local hash = tostring(handle:read("*a") or ""):gsub("%s+", ""); handle:close()
    if not isSha256(hash) then fail("Invalid DRX SHA-256 result.") end
    return string.upper(hash)
end
local function snapshotDrxFiles(directory)
    local resultPath = ASCII_DIR .. "/reference_grades/.snapshot.txt"
    os.remove(resultPath)
    local command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
        .. '"$d=' .. powershellLiteral(directory) .. ';$o=' .. powershellLiteral(resultPath)
        .. ';$rows=@();if(Test-Path -LiteralPath $d){$rows=Get-ChildItem -LiteralPath $d -File -Filter *.drx | ForEach-Object {$_.FullName}};[IO.File]::WriteAllLines($o,[string[]]$rows,[Text.Encoding]::UTF8)"'
    os.execute(command)
    local snapshot = {}
    local handle = io.open(resultPath, "rb")
    if not handle then fail("Could not snapshot DRX artifact directory.") end
    for line in handle:lines() do
        local path = tostring(line):gsub("^\239\187\191", ""):gsub("\\", "/")
        if path ~= "" then snapshot[pathKey(path)] = path end
    end
    handle:close(); os.remove(resultPath); return snapshot
end
local function discoverNewDrx(before, after, requestedBasename)
    local candidates = {}
    for key, path in pairs(after) do
        if before[key] == nil then candidates[#candidates + 1] = path end
    end
    logValue("drx.discovery.new_count", #candidates)
    if #candidates ~= 1 then fail("ExportStills must create exactly one new DRX artifact; found " .. tostring(#candidates)) end
    local path = candidates[1]
    local filename = tostring(path):match("([^/]+)$") or ""
    local basename = filename:gsub("%.[Dd][Rr][Xx]$", "")
    if basename:sub(1, #requestedBasename) ~= requestedBasename then
        fail("New DRX artifact does not match requested basename prefix.")
    end
    local size = tonumber(fileSize(path)) or 0
    if size <= 0 then fail("New DRX artifact is empty.") end
    return path, filename, size
end
local function numberEquals(value, expected)
    local n = tonumber(value); return n ~= nil and math.abs(n - tonumber(expected)) < 0.001
end
local function clipPath(item)
    local ok, value = pcall(function() return item:GetClipProperty("File Path") end)
    return ok and tostring(value or "") or ""
end
local function findTimeline(project, name)
    local found = {}
    for index = 1, project:GetTimelineCount() do
        local timeline = project:GetTimelineByIndex(index)
        if timeline and tostring(timeline:GetName()) == tostring(name) then found[#found + 1] = timeline end
    end
    if #found ~= 1 then fail("Expected exactly one B reference timeline; found " .. tostring(#found)) end
    return found[1]
end
local function exactTimelineItem(timeline, expectedPath)
    local trackCount = tonumber(timeline:GetTrackCount("video")) or 0
    logValue("timeline.video_track_count", trackCount)
    if trackCount ~= 1 then fail("B reference timeline must contain exactly one Video Track.") end
    local raw = timeline:GetItemListInTrack("video", 1) or {}
    local valid = {}
    for _, item in ipairs(raw) do
        if type(item) == "userdata" then
            local ok, poolItem = pcall(function() return item:GetMediaPoolItem() end)
            if ok and type(poolItem) == "userdata" then valid[#valid + 1] = item end
        end
    end
    logValue("timeline.validated_item_count", #valid)
    if #valid ~= 1 then fail("B reference timeline must contain exactly one validated TimelineItem.") end
    local poolItem = valid[1]:GetMediaPoolItem()
    local actualPath = clipPath(poolItem)
    logValue("timeline.working_path", actualPath)
    if pathKey(actualPath) ~= pathKey(expectedPath) then fail("B TimelineItem does not point to exact working media.") end
    return valid[1]
end
local function presetExactVisible(value, target)
    if type(value) ~= "table" then return false end
    for key, item in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 2) ~= "__" then
            if type(key) == "string" and key == target then return true end
            if type(item) == "string" and item == target then return true end
        end
    end
    return false
end

logLine("")
logLine("============================================================")
logLine("REFERENCE GRADE LOCK START")
logValue("timestamp", os.date("%Y-%m-%d %H:%M:%S %z"))
logValue("scope", "human-approved B only; immutable DRX; one B master render; A rerender forbidden")

local function main()
    stage("Runtime Profile")
    local loader, loadError = loadfile(PROFILE_PATH)
    if not loader then fail("Cannot load runtime: " .. tostring(loadError)) end
    local ok, profile = pcall(loader)
    if not ok or type(profile) ~= "table" then fail("Runtime did not return a table.") end
    local colorTest, look, preset = profile.color_test, profile.look, profile.render_preset
    if type(colorTest) ~= "table" or type(look) ~= "table" or type(preset) ~= "table" then fail("Missing runtime blocks.") end
    if tostring(colorTest.status) ~= "B_REFERENCE_GRADE_APPROVED_LOCK_AND_RENDER"
        or colorTest.render_authorized ~= true or tonumber(colorTest.render_limit) ~= 1 then
        fail("B lock/render authorization gate is incomplete.")
    end
    if tostring(colorTest.b_output_preflight_status) ~= "PASS_NO_EXISTING_TARGET" then
        fail("B output preflight gate missing.")
    end
    if type(colorTest.a_master) ~= "table" or tostring(colorTest.a_master.status) ~= "PASS"
        or colorTest.a_master.rerender_forbidden ~= true then fail("A PASS/rerender-forbidden gate missing.") end
    if (tostring(look.status) ~= "HUMAN_APPROVED_REFERENCE_PENDING_LOCK"
        and tostring(look.status) ~= "HUMAN_APPROVED_REFERENCE_LOCKED") or look.approved ~= true then
        fail("Human-approved reference gate missing.")
    end
    if tostring(look.reference_timeline) ~= tostring(colorTest.neutral_safe_timeline) then fail("Reference timeline mismatch.") end
    if tostring(preset.status) ~= "CAPTURED_VERIFIED" or not isSha256(preset.sha256) then fail("Verified render preset gate missing.") end
    local mapping = profile.batch and profile.batch.media_mappings and profile.batch.media_mappings[1]
    if type(mapping) ~= "table" or tostring(mapping.resolve_decode_status) ~= "PASS" then fail("Verified working-media mapping missing.") end
    state.timeline = tostring(colorTest.neutral_safe_timeline)
    state.output_dir = tostring(colorTest.output_dir)
    state.output_name = tostring(colorTest.b_output_basename)
    local requestedBasename = "Sony_SLog3_Neutral_Safe_Human_Approved_Reference"
    state.drx_path = tostring(look.reference_drx_path or "")
    local hashPath = ARTIFACT_DIR .. "/Sony_SLog3_Neutral_Safe_Human_Approved_Reference.sha256"
    if state.output_name == "" then fail("Missing B output basename.") end

    stage("Resolve Objects")
    local appObject = rawget(_G, "app")
    local resolveObject = appObject and appObject:GetResolve() or nil
    local manager = resolveObject and resolveObject:GetProjectManager() or nil
    local project = manager and manager:GetCurrentProject() or nil
    if not project then fail("Resolve internal objects unavailable.") end
    state.project = tostring(project:GetName())
    if state.project ~= tostring(colorTest.project_name) then fail("Current project is not the verified reference project.") end
    for _, check in ipairs({
        {"timelinePlaybackFrameRate", profile.batch.frame_rate}, {"timelineFrameRate", profile.batch.frame_rate},
        {"timelineResolutionWidth", profile.batch.width}, {"timelineResolutionHeight", profile.batch.height}
    }) do
        local actual = project:GetSetting(check[1]); logValue("project." .. check[1], actual)
        if not numberEquals(actual, check[2]) then fail("Project format mismatch: " .. check[1]) end
    end
    for _, check in ipairs({
        {"colorScienceMode", "davinciYRGBColorManagedv2"}, {"rcmPresetMode", "Custom"}, {"isAutoColorManage", "0"},
        {"colorSpaceInput", "Sony S-Gamut3.Cine"}, {"colorSpaceInputGamma", "S-Log3"},
        {"colorSpaceTimeline", "DaVinci WG"}, {"colorSpaceTimelineGamma", "DaVinci Intermediate"},
        {"colorSpaceOutput", "Rec.709"}, {"colorSpaceOutputGamma", "Gamma 2.4"}
    }) do
        local actual = tostring(project:GetSetting(check[1]) or ""); logValue("project." .. check[1], actual)
        if normalize(actual) ~= normalize(check[2]) then fail("RCM mismatch: " .. check[1]) end
    end

    stage("Human Approved B Identity")
    local timeline = findTimeline(project, state.timeline)
    local item = exactTimelineItem(timeline, mapping.working_file)
    if project:SetCurrentTimeline(timeline) ~= true then fail("Could not select approved B timeline.") end
    logValue("reference.current_timecode", timeline:GetCurrentTimecode())
    local graph = item:GetNodeGraph()
    local nodeCount = graph and tonumber(graph:GetNumNodes()) or -1
    logValue("reference.node_count", nodeCount)
    if nodeCount < 1 then fail("Approved B has no valid node graph.") end
    logValue("reference.parameter_authority", "HUMAN_APPROVED_UI_VALUES")
    for key, value in pairs(look.approved_parameters or {}) do logValue("reference.approved_parameter." .. key, value) end
    logLine("B_REFERENCE_GRADE=HUMAN_APPROVED_NO_API_MUTATION")

    stage("Reference DRX Lock")
    if tostring(look.reference_grade_status) == "HUMAN_APPROVED"
        and state.drx_path ~= "" and tonumber(look.reference_drx_size) ~= nil
        and isSha256(look.reference_drx_sha256) then
        state.drx_size = tonumber(fileSize(state.drx_path)) or 0
        if state.drx_size ~= tonumber(look.reference_drx_size) then fail("Locked DRX size mismatch.") end
        state.drx_sha256 = calculateSha256(state.drx_path, hashPath)
        if string.upper(state.drx_sha256) ~= string.upper(tostring(look.reference_drx_sha256)) then fail("Locked DRX SHA-256 mismatch.") end
        logValue("requested_basename", requestedBasename)
        logValue("actual_exported_filename", state.drx_path:match("([^/]+)$") or state.drx_path)
        logValue("actual_path", state.drx_path)
        logValue("actual_size", state.drx_size)
        logValue("actual_modification_time", fileModificationTime(state.drx_path))
        logValue("actual_sha256", state.drx_sha256)
        logLine("DRX_ARTIFACT_DISCOVERED=PASS")
        logLine("REFERENCE_DRX_LOCKED=PASS")
        logLine("GRAB_STILL_AND_EXPORT=SKIPPED_EXISTING_LOCKED_ARTIFACT")
    else
        stage("Grab Still and Export DRX")
        if state.drx_path ~= "" or fileSize(hashPath) ~= nil then fail("Immutable DRX target already exists; overwrite forbidden.") end
        local gallery = project:GetGallery()
        local album = gallery and gallery:GetCurrentStillAlbum() or nil
        if not album then fail("Current Gallery Still Album unavailable.") end
        local before = snapshotDrxFiles(ARTIFACT_DIR)
        local still = timeline:GrabStill()
        if not still then fail("Timeline:GrabStill() returned nil.") end
        local labelOk = album:SetLabel(still, "Sony SLog3 Neutral Safe Human Approved Reference")
        logValue("SetLabel.return", labelOk)
        if labelOk ~= true then fail("Could not label captured still.") end
        local exportOk = album:ExportStills({still}, ARTIFACT_DIR, requestedBasename, "drx")
        logValue("ExportStills.drx.return", exportOk)
        if exportOk ~= true then fail("DRX export failed.") end
        local after = snapshotDrxFiles(ARTIFACT_DIR)
        local actualFilename
        state.drx_path, actualFilename, state.drx_size = discoverNewDrx(before, after, requestedBasename)
        state.drx_sha256 = calculateSha256(state.drx_path, hashPath)
        logValue("requested_basename", requestedBasename)
        logValue("actual_exported_filename", actualFilename)
        logValue("actual_path", state.drx_path); logValue("actual_size", state.drx_size)
        logValue("actual_sha256", state.drx_sha256)
        logLine("DRX_ARTIFACT_DISCOVERED=PASS")
        logLine("REFERENCE_DRX_LOCKED=PASS")
    end

    stage("B Master Render Start")
    if not presetExactVisible(project:GetRenderPresetList(), tostring(preset.name)) then fail("Verified render preset not visible.") end
    if project:LoadRenderPreset(tostring(preset.name)) ~= true then fail("LoadRenderPreset failed.") end
    local current = project:GetCurrentRenderFormatAndCodec()
    if type(current) ~= "table" or tostring(current.format) ~= tostring(preset.expected_format_id)
        or tostring(current.codec) ~= tostring(preset.expected_codec_id) then fail("Loaded preset format/codec mismatch.") end
    if tonumber(project:GetCurrentRenderMode()) ~= 1 then fail("Loaded preset is not Single Clip mode.") end
    local settingsOk = project:SetRenderSettings({SelectAllFrames=true, TargetDir=state.output_dir, CustomName=state.output_name})
    logValue("SetRenderSettings.return", settingsOk)
    if settingsOk ~= true then fail("Task-only SetRenderSettings failed.") end
    local jobId = project:AddRenderJob()
    state.render_job_id = tostring(jobId or "")
    logValue("AddRenderJob.return", state.render_job_id)
    if state.render_job_id == "" then fail("AddRenderJob returned no ID.") end
    if manager:SaveProject() ~= true then fail("SaveProject failed before B render.") end
    local started = project:StartRendering({state.render_job_id}, false)
    logValue("StartRendering.return", started)
    if started ~= true then fail("StartRendering failed.") end
    state.render_start = "STARTED"
    state.status = "B_MASTER_RENDER_STARTED_REFERENCE_LOCKED"
    logLine("B_NEUTRAL_SAFE_MASTER=STARTED")
    logLine("STOP_AFTER_RENDER_START")
end

local ok, tracebackText = xpcall(main, tracebackHandler)
if not ok then
    state.status = "ERROR_STOPPED"
    logLine("ERROR"); logValue("error.stage", state.stage); logValue("error.traceback", tracebackText)
end
local report = {
    "# Sony S-Log3 Reference Grade Lock report", "",
    "- Status: `" .. state.status .. "`", "- Last stage: `" .. state.stage .. "`",
    "- Project: `" .. state.project .. "`", "- Timeline: `" .. state.timeline .. "`",
    "- DRX: `" .. state.drx_path .. "`", "- DRX size: `" .. tostring(state.drx_size) .. "`",
    "- DRX SHA-256: `" .. state.drx_sha256 .. "`", "- B Render Job ID: `" .. state.render_job_id .. "`",
    "- B Render Start: `" .. state.render_start .. "`", "- Output Directory: `" .. state.output_dir .. "`",
    "- Output Basename: `" .. state.output_name .. "`", "", "## Errors", ""
}
if #state.errors == 0 then report[#report + 1] = "- None" end
for _, message in ipairs(state.errors) do report[#report + 1] = "- " .. message:gsub("[\r\n]", " ") end
if not ok then
    report[#report + 1] = ""; report[#report + 1] = "## Traceback"; report[#report + 1] = ""
    report[#report + 1] = "```"; report[#report + 1] = tracebackText; report[#report + 1] = "```"
end
local handle = io.open(REPORT_PATH, "wb")
if handle then handle:write(table.concat(report, "\n")); handle:close() end
logLine("STOP"); logValue("final.status", state.status)
