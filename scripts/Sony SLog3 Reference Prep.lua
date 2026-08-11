-- Sony SLog3 Reference Prep.lua
-- Creates two clean one-clip timelines from a previously verified compatibility project.
-- Renders only the RCM-only master, then opens the untouched reference seed on Color.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ASCII_DIR = TEMP_ROOT .. "/SonySLog3AutoGrade"
local PROFILE_PATH = ASCII_DIR .. "/runtime.lua"
local LOG_PATH = ASCII_DIR .. "/reference_prep.log"
local REPORT_PATH = ASCII_DIR .. "/reference_prep_report.md"
local EMERGENCY_PATH = TEMP_ROOT .. "/SonySLog3AutoGrade_reference_prep_emergency.log"

local state = {
    status = "STARTING",
    stage = "bootstrap",
    project = "",
    source_timeline = "",
    a_timeline = "",
    b_timeline = "",
    a_grade = "NOT_TESTED",
    b_grade = "NOT_TESTED",
    render_job_id = "",
    render_start = "NOT_STARTED",
    output_dir = "",
    output_name = "",
    selected_format = "",
    selected_codec = "",
    format_display_name = "",
    render_job_status = "NOT_STARTED",
    postflight_status = "NOT_STARTED",
    warnings = {},
    errors = {}
}

local function append(list, value) list[#list + 1] = tostring(value) end
local function appendRaw(path, text)
    local handle = io.open(path, "ab")
    if not handle then return false end
    handle:write(text); handle:close(); return true
end
local function ensureLog()
    local probe = io.open(LOG_PATH, "ab")
    if probe then probe:close(); return true end
    local quoted = '"' .. ASCII_DIR:gsub("/", "\\"):gsub('"', '""') .. '"'
    os.execute("cmd.exe /d /c if not exist " .. quoted .. " mkdir " .. quoted .. " >NUL 2>&1")
    probe = io.open(LOG_PATH, "ab")
    if probe then probe:close(); return true end
    appendRaw(EMERGENCY_PATH, "REFERENCE_PREP_LOG_INIT_FAILED\n")
    return false
end
local loggerReady = ensureLog()
local function logLine(value)
    local line = tostring(value or "") .. "\n"
    if loggerReady and appendRaw(LOG_PATH, line) then return end
    appendRaw(EMERGENCY_PATH, line)
end
local function logValue(key, value) logLine(key .. "=" .. tostring(value)) end
local function stage(name) state.stage = name; logLine("STAGE=" .. name) end
local function normalize(value) return string.lower((tostring(value or ""):gsub("%s+", ""))) end
local function pathKey(value) return string.lower(tostring(value or ""):gsub("\\", "/")) end
local function numberEquals(value, expected)
    local number = tonumber(value)
    return number ~= nil and math.abs(number - tonumber(expected)) < 0.001
end
local function isSha256(value)
    local text = tostring(value or "")
    return #text == 64 and text:match("^[0-9A-Fa-f]+$") ~= nil
end
local function tracebackHandler(errorValue)
    local message = tostring(errorValue)
    if debug and type(debug.traceback) == "function" then return debug.traceback(message, 2) end
    return message
end
local function fail(message)
    append(state.errors, "stage=" .. state.stage .. " | " .. tostring(message))
    error(tostring(message), 0)
end

logLine("")
logLine("============================================================")
logLine("REFERENCE PREP START")
logValue("timestamp", os.date("%Y-%m-%d %H:%M:%S %z"))
logValue("interface", "internal Workspace launcher -> formal reference prep")
logValue("scope", "one verified working clip; A RCM-only render; B untouched reference seed")

local function loadProfile()
    stage("Runtime Profile")
    local loader, loadError = loadfile(PROFILE_PATH)
    if not loader then fail("Cannot load runtime: " .. tostring(loadError)) end
    local ok, profile = pcall(loader)
    if not ok or type(profile) ~= "table" then fail("Runtime did not return a table: " .. tostring(profile)) end
    if profile.mode ~= "reference_prep" then fail("Reference Prep requires mode='reference_prep'.") end
    if type(profile.deployment) ~= "table" then fail("Missing deployment identity.") end
    if not tostring(profile.deployment.logic_commit or ""):match("^[0-9A-Fa-f]+$") then fail("Invalid logic commit identity.") end
    if not isSha256(profile.deployment.logic_sha256) or not isSha256(profile.deployment.reference_prep_sha256)
        or not isSha256(profile.deployment.reference_postflight_sha256) then
        fail("Invalid formal-script SHA-256 deployment identity.")
    end
    if type(profile.color_test) ~= "table" then fail("Missing color_test profile.") end
    if profile.color_test.render_authorized ~= true or tonumber(profile.color_test.render_limit) ~= 1 then
        fail("Color-test render authorization is incomplete.")
    end
    if tostring(profile.color_test.status or "") ~= "READY_TO_RUN" then fail("color_test.status is not READY_TO_RUN.") end
    if tostring(profile.color_test.output_preflight_status or "") ~= "PASS" then fail("Output preflight is not PASS.") end
    if tostring(profile.color_test.a_output_basename or "") == "" then fail("Missing A output basename.") end
    local timelineState = tostring(profile.color_test.existing_timelines_state or "")
    if timelineState ~= "CREATE_NEW_RESET_AUTHORIZED" and timelineState ~= "PURE_RCM_RESET_VERIFIED" then
        fail("Invalid existing_timelines_state gate.")
    end
    if type(profile.color_test.postflight) ~= "table"
        or tostring(profile.color_test.postflight.script_path or "") == ""
        or tostring(profile.color_test.postflight.config_path or "") == ""
        or tostring(profile.color_test.postflight.status_path or "") == "" then
        fail("Missing render postflight configuration.")
    end
    if type(profile.render_preset) ~= "table"
        or tostring(profile.render_preset.status or "") ~= "CAPTURED_VERIFIED"
        or tostring(profile.render_preset.name or "") == ""
        or not isSha256(profile.render_preset.sha256) then
        fail("A SHA-256-pinned CAPTURED_VERIFIED render preset is required.")
    end
    local mapping = profile.batch and profile.batch.media_mappings and profile.batch.media_mappings[1]
    if type(mapping) ~= "table" or mapping.working_media_required ~= true then fail("Missing required working-media mapping.") end
    if tostring(mapping.resolve_decode_status or "") ~= "PASS"
        or tostring(mapping.signal_equivalence_status or "") ~= "PASS" then
        fail("Compatibility success gates are not PASS.")
    end
    logValue("logic_commit", profile.deployment.logic_commit)
    logValue("logic_sha256", profile.deployment.logic_sha256)
    logValue("reference_prep_sha256", profile.deployment.reference_prep_sha256)
    logValue("reference_postflight_sha256", profile.deployment.reference_postflight_sha256)
    logValue("render_preset_name", profile.render_preset.name)
    logValue("render_preset_sha256", profile.render_preset.sha256)
    logValue("project", profile.color_test.project_name)
    logValue("working_media", mapping.working_file)
    logValue("resolve_decode_status", mapping.resolve_decode_status)
    logValue("input_color_policy", mapping.input_color_policy)
    return profile, mapping
end

local function acquire(profile)
    stage("Resolve Objects")
    local appObject = rawget(_G, "app")
    if not appObject then fail("Internal app object is unavailable.") end
    local resolveObject = appObject:GetResolve()
    if not resolveObject then fail("app:GetResolve() returned nil.") end
    local manager = resolveObject:GetProjectManager()
    if not manager then fail("GetProjectManager() returned nil.") end
    local project = manager:GetCurrentProject()
    if not project then fail("No current project.") end
    state.project = tostring(project:GetName())
    if state.project ~= tostring(profile.color_test.project_name) then fail("Current project is not the verified compatibility project.") end
    logLine("Resolve Objects=SUCCESS")
    return resolveObject, manager, project
end

local function verifyProject(project, profile)
    stage("Verified Project Readback")
    local checks = {
        {"timelinePlaybackFrameRate", profile.batch.frame_rate},
        {"timelineFrameRate", profile.batch.frame_rate},
        {"timelineResolutionWidth", profile.batch.width},
        {"timelineResolutionHeight", profile.batch.height}
    }
    for _, entry in ipairs(checks) do
        local actual = project:GetSetting(entry[1])
        logValue("project." .. entry[1], actual)
        if not numberEquals(actual, entry[2]) then fail("Project format mismatch: " .. entry[1]) end
    end
    local exact = {
        {"colorScienceMode", "davinciYRGBColorManagedv2"},
        {"rcmPresetMode", "Custom"},
        {"isAutoColorManage", "0"},
        {"colorSpaceInput", "Sony S-Gamut3.Cine"},
        {"colorSpaceInputGamma", "S-Log3"},
        {"colorSpaceTimeline", "DaVinci WG"},
        {"colorSpaceTimelineGamma", "DaVinci Intermediate"},
        {"colorSpaceOutput", "Rec.709"},
        {"colorSpaceOutputGamma", "Gamma 2.4"}
    }
    for _, entry in ipairs(exact) do
        local actual = tostring(project:GetSetting(entry[1]) or "")
        logValue("project." .. entry[1], actual)
        if normalize(actual) ~= normalize(entry[2]) then fail("Color-management mismatch: " .. entry[1]) end
    end
    logLine("VERIFIED PROJECT=PASS")
end

local function clipPath(item)
    local ok, value = pcall(function() return item:GetClipProperty("File Path") end)
    return ok and tostring(value or "") or ""
end

local function dumpRawCollection(label, value)
    logLine(label .. " RAW BEGIN")
    logValue(label .. ".return_type", type(value))
    if type(value) ~= "table" then
        logLine(label .. " RAW END")
        return
    end
    local entryCount = 0
    local iterateOk, iterateError = pcall(function()
        for key, item in pairs(value) do
            entryCount = entryCount + 1
            local prefix = label .. ".entry[" .. entryCount .. "]"
            local keyType, valueType = type(key), type(item)
            local classification = "DICTIONARY_ENTRY"
            if keyType == "string" and key:sub(1, 2) == "__" then
                classification = "BRIDGE_METADATA"
            elseif keyType == "number" and key >= 1 and key % 1 == 0 then
                classification = "SEQUENCE_ENTRY"
            end
            logValue(prefix .. ".key_type", keyType)
            logValue(prefix .. ".key", key)
            logValue(prefix .. ".value_type", valueType)
            logValue(prefix .. ".value", item)
            logValue(prefix .. ".classification", classification)
            if valueType == "table" then
                local nestedCount = 0
                for nestedKey, nestedValue in pairs(item) do
                    nestedCount = nestedCount + 1
                    local nested = prefix .. ".nested[" .. nestedCount .. "]"
                    logValue(nested .. ".key_type", type(nestedKey))
                    logValue(nested .. ".key", nestedKey)
                    logValue(nested .. ".value_type", type(nestedValue))
                    logValue(nested .. ".value", nestedValue)
                end
                logValue(prefix .. ".nested_count", nestedCount)
            end
        end
    end)
    logValue(label .. ".top_level_entry_count_diagnostic_only", entryCount)
    logValue(label .. ".iterate_ok", iterateOk)
    if not iterateOk then logValue(label .. ".iterate_error", iterateError) end
    logLine(label .. " RAW END")
end

local function timelineItem(timeline, expectedPath, label)
    local trackCount = tonumber(timeline:GetTrackCount("video")) or 0
    logValue(label .. ".video_track_count", trackCount)
    if trackCount ~= 1 then fail(label .. " must contain exactly one Video Track.") end
    local raw = timeline:GetItemListInTrack("video", 1) or {}
    local valid = {}
    for index, item in ipairs(raw) do
        if type(item) ~= "userdata" then fail(label .. " contains a non-userdata sequence entry.") end
        local ok, poolItem = pcall(function() return item:GetMediaPoolItem() end)
        if not ok or type(poolItem) ~= "userdata" then fail(label .. " TimelineItem has no MediaPoolItem.") end
        valid[#valid + 1] = item
        logValue(label .. ".item[" .. index .. "].path", clipPath(poolItem))
    end
    logValue(label .. ".validated_item_count", #valid)
    if #valid ~= 1 then fail(label .. " must contain exactly one validated TimelineItem.") end
    local poolItem = valid[1]:GetMediaPoolItem()
    if pathKey(clipPath(poolItem)) ~= pathKey(expectedPath) then fail(label .. " does not point to the exact working media.") end
    return valid[1], poolItem
end

local function findTimelines(project, name)
    local matches = {}
    for index = 1, project:GetTimelineCount() do
        local timeline = project:GetTimelineByIndex(index)
        if timeline and tostring(timeline:GetName()) == tostring(name) then
            matches[#matches + 1] = timeline
        end
    end
    return matches
end

local function findWorkingMedia(project, expectedPath)
    local root = project:GetMediaPool():GetRootFolder()
    local raw = root:GetClipList() or {}
    local exact, fileBackedCount = nil, 0
    for _, item in ipairs(raw) do
        if type(item) == "userdata" then
            local path = clipPath(item)
            if path ~= "" then
                fileBackedCount = fileBackedCount + 1
                if pathKey(path) == pathKey(expectedPath) then exact = item end
            end
        end
    end
    logValue("media_pool.file_backed_count", fileBackedCount)
    if fileBackedCount ~= 1 or not exact then fail("Media Pool must contain exactly the verified working file.") end
    return exact
end

local function resetAndValidateCleanGrade(item, label)
    local graph = item:GetNodeGraph()
    if not graph then fail(label .. " GetNodeGraph returned nil.") end
    local reset = graph:ResetAllGrades()
    logValue(label .. ".ResetAllGrades.return", reset)
    if reset ~= true then fail(label .. " ResetAllGrades did not return true.") end
    local count = tonumber(graph:GetNumNodes()) or -1
    logValue(label .. ".node_count", count)
    if count ~= 1 then fail(label .. " clean grade must contain exactly one default serial node.") end
    local lut = tostring(graph:GetLUT(1) or "")
    logValue(label .. ".node1_lut", lut)
    if lut ~= "" then fail(label .. " default node unexpectedly contains a LUT.") end
    logLine(label .. "=PURE_RCM_RESET_GRADE")
end

local function validatePreviouslyResetGrade(item, label)
    local graph = item:GetNodeGraph()
    if not graph then fail(label .. " GetNodeGraph returned nil.") end
    local count = tonumber(graph:GetNumNodes()) or -1
    logValue(label .. ".node_count", count)
    if count ~= 1 then fail(label .. " must retain exactly one default serial node.") end
    local lut = tostring(graph:GetLUT(1) or "")
    logValue(label .. ".node1_lut", lut)
    if lut ~= "" then fail(label .. " unexpectedly contains a LUT.") end
    logValue(label .. ".clean_grade_authority", "PRIOR_RESET_EVIDENCE_PLUS_PRIVATE_RUNTIME_ATTESTATION")
    logLine(label .. "=PURE_RCM_RESET_GRADE")
end

local function createTimelines(project, profile, mapping)
    stage("Timeline Preparation")
    local sourceName = tostring(profile.color_test.source_timeline)
    local aName = tostring(profile.color_test.rcm_only_timeline)
    local bName = tostring(profile.color_test.neutral_safe_timeline)
    local sourceMatches = findTimelines(project, sourceName)
    local aMatches = findTimelines(project, aName)
    local bMatches = findTimelines(project, bName)
    logValue("timeline_inventory.total", project:GetTimelineCount())
    logValue("timeline_inventory.source_matches", #sourceMatches)
    logValue("timeline_inventory.a_matches", #aMatches)
    logValue("timeline_inventory.b_matches", #bMatches)
    if #sourceMatches ~= 1 then fail("Expected exactly one verified source timeline.") end
    local source = sourceMatches[1]
    timelineItem(source, mapping.working_file, "source_timeline")
    if #aMatches == 1 and #bMatches == 1 then
        if tostring(profile.color_test.existing_timelines_state) ~= "PURE_RCM_RESET_VERIFIED" then
            fail("Existing A/B timelines require PURE_RCM_RESET_VERIFIED private attestation.")
        end
        if tonumber(project:GetTimelineCount()) ~= 3 then fail("Existing reference project contains unexpected timelines.") end
        local itemA = timelineItem(aMatches[1], mapping.working_file, "timeline_a")
        local itemB = timelineItem(bMatches[1], mapping.working_file, "timeline_b")
        validatePreviouslyResetGrade(itemA, "A_RCM_ONLY_GRADE")
        validatePreviouslyResetGrade(itemB, "B_REFERENCE_SEED_GRADE")
        state.source_timeline = sourceName
        state.a_timeline = aName
        state.b_timeline = bName
        state.a_grade = "PURE_RCM_RESET_GRADE"
        state.b_grade = "PURE_RCM_RESET_GRADE"
        logLine("REUSE_EXISTING_REFERENCE_TIMELINES")
        logLine("TIMELINE PREPARATION=SUCCESS")
        return aMatches[1], bMatches[1]
    end
    if #aMatches ~= 0 or #bMatches ~= 0 then fail("Partial or duplicate A/B timeline state; refusing repair.") end
    if tostring(profile.color_test.existing_timelines_state) ~= "CREATE_NEW_RESET_AUTHORIZED" then
        fail("Creating new A/B timelines requires CREATE_NEW_RESET_AUTHORIZED.")
    end
    if tonumber(project:GetTimelineCount()) ~= 1 then fail("Project contains unexpected timelines before reference preparation.") end
    local workingItem = findWorkingMedia(project, mapping.working_file)
    local mediaPool = project:GetMediaPool()
    local timelineA = mediaPool:CreateTimelineFromClips(aName, {workingItem})
    if not timelineA then fail("Could not create A RCM-only timeline.") end
    local itemA = timelineItem(timelineA, mapping.working_file, "timeline_a")
    resetAndValidateCleanGrade(itemA, "A_RCM_ONLY_GRADE")
    state.a_timeline = aName
    state.a_grade = "PURE_RCM_RESET_GRADE"
    local timelineB = mediaPool:CreateTimelineFromClips(bName, {workingItem})
    if not timelineB then fail("Could not create B reference timeline.") end
    local itemB = timelineItem(timelineB, mapping.working_file, "timeline_b")
    resetAndValidateCleanGrade(itemB, "B_REFERENCE_SEED_GRADE")
    state.b_timeline = bName
    state.b_grade = "PURE_RCM_RESET_GRADE"
    state.source_timeline = sourceName
    if tonumber(project:GetTimelineCount()) ~= 3 then fail("Project must contain source, A, and B timelines only.") end
    logLine("TIMELINE PREPARATION=SUCCESS")
    return timelineA, timelineB
end

local function renderQueueCount(project)
    local jobs = project:GetRenderJobList() or {}
    local count = 0
    for _, job in ipairs(jobs) do
        if type(job) ~= "table" or tostring(job.JobId or "") == "" then fail("Invalid render-job sequence entry.") end
        count = count + 1
    end
    return count
end

local function presetExactVisible(value, target)
    if type(value) ~= "table" then return false end
    for key, item in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 2) ~= "__" then
            if type(key) == "string" and key == target then return true end
            if type(item) == "string" and item == target then return true end
            if type(item) == "table" then
                for _, nestedValue in pairs(item) do
                    if type(nestedValue) == "string" and nestedValue == target then return true end
                end
            end
        end
    end
    return false
end

local function loadVerifiedRenderPreset(project, profile)
    stage("Render Preset Load")
    local preset = profile.render_preset
    local presets = project:GetRenderPresetList()
    dumpRawCollection("RENDER PRESET LIST", presets)
    if not presetExactVisible(presets, tostring(preset.name)) then
        fail("Pinned render preset is not EXACT VISIBLE in GetRenderPresetList.")
    end
    local loaded = project:LoadRenderPreset(tostring(preset.name))
    logValue("LoadRenderPreset.return", loaded)
    if loaded ~= true then fail("LoadRenderPreset returned false.") end
    local current = project:GetCurrentRenderFormatAndCodec()
    dumpRawCollection("CURRENT RENDER FORMAT AND CODEC", current)
    if type(current) ~= "table" then fail("GetCurrentRenderFormatAndCodec did not return a table.") end
    state.selected_format = tostring(current.format or "")
    state.selected_codec = tostring(current.codec or "")
    state.format_display_name = tostring(preset.expected_format_display_name or "")
    logValue("render.current_format", state.selected_format)
    logValue("render.current_codec", state.selected_codec)
    if state.selected_format ~= tostring(preset.expected_format_id)
        or state.selected_codec ~= tostring(preset.expected_codec_id) then
        fail("Loaded render preset format/codec readback mismatch.")
    end
    if tonumber(project:GetCurrentRenderMode()) ~= 1 then fail("Loaded render preset is not Single Clip mode.") end
    logLine("RENDER PRESET=LOADED_AND_VERIFIED")
end

local function waitOneSecond()
    if type(bmd) == "table" and type(bmd.wait) == "function" then
        bmd.wait(1000)
    else
        os.execute('powershell.exe -NoProfile -Command "Start-Sleep -Seconds 1"')
    end
end

local function waitForCompletedRender(project, jobId, timeoutSeconds)
    stage("A Render Completion")
    local startedAt = os.time()
    local nextLog = 0
    while project:IsRenderingInProgress() == true do
        local elapsed = os.difftime(os.time(), startedAt)
        if elapsed >= nextLog then
            logValue("render.elapsed_seconds", elapsed)
            nextLog = elapsed + 30
        end
        if elapsed > timeoutSeconds then fail("A render exceeded the configured timeout.") end
        waitOneSecond()
    end
    local status = project:GetRenderJobStatus(jobId)
    dumpRawCollection("RENDER JOB STATUS", status)
    if type(status) ~= "table" then fail("GetRenderJobStatus did not return a table.") end
    state.render_job_status = tostring(status.JobStatus or status.jobStatus or "")
    logValue("render.job_status", state.render_job_status)
    if normalize(state.render_job_status) ~= "complete" and normalize(state.render_job_status) ~= "completed" then
        fail("Resolve Render Job did not complete successfully.")
    end
    logLine("RESOLVE RENDER JOB=COMPLETED")
end

local function quoteCommandArgument(value)
    return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

local function runPostflight(profile)
    stage("A Master Postflight")
    local postflight = profile.color_test.postflight
    os.remove(tostring(postflight.status_path))
    os.remove(tostring(postflight.report_path))
    local command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File "
        .. quoteCommandArgument(postflight.script_path)
        .. " -ConfigPath " .. quoteCommandArgument(postflight.config_path)
    logValue("postflight.command_interface", "PowerShell -File with ASCII-only script/config paths")
    local resultA, resultB, resultC = os.execute(command)
    logValue("postflight.os_execute.return1", resultA)
    logValue("postflight.os_execute.return2", resultB)
    logValue("postflight.os_execute.return3", resultC)
    local statusHandle = io.open(tostring(postflight.status_path), "rb")
    if not statusHandle then fail("Postflight did not create its ASCII status file.") end
    local statusText = tostring(statusHandle:read("*a") or ""):gsub("%s+", "")
    statusHandle:close()
    state.postflight_status = statusText
    logValue("postflight.status", statusText)
    logValue("postflight.report_path", postflight.report_path)
    if statusText ~= "PASS" then fail("A master ffprobe/hash postflight did not pass.") end
    logLine("A_RCM_ONLY_MASTER=PASS")
end

local function queueAndStartRender(resolveObject, manager, project, timelineA, timelineB, profile)
    stage("A RCM Only Render")
    if renderQueueCount(project) ~= 0 then fail("Render Queue must be empty.") end
    if project:SetCurrentTimeline(timelineA) ~= true then fail("Could not select A timeline for render.") end
    loadVerifiedRenderPreset(project, profile)
    state.output_dir = tostring(profile.color_test.output_dir)
    state.output_name = tostring(profile.color_test.a_output_basename)
    local settings = {
        SelectAllFrames = true,
        TargetDir = state.output_dir,
        CustomName = state.output_name
    }
    local settingsOk = project:SetRenderSettings(settings)
    logValue("SetRenderSettings.task_fields", "SelectAllFrames,TargetDir,CustomName")
    logValue("SetRenderSettings.return", settingsOk)
    if settingsOk ~= true then fail("Task-only SetRenderSettings did not return true.") end
    local jobId = project:AddRenderJob()
    state.render_job_id = tostring(jobId or "")
    logValue("AddRenderJob.return", state.render_job_id)
    if state.render_job_id == "" then fail("AddRenderJob did not return a job ID.") end
    if renderQueueCount(project) ~= 1 then fail("Render Queue must contain exactly one A job.") end
    if manager:SaveProject() ~= true then fail("SaveProject failed before rendering.") end
    logLine("Save Project=SUCCESS")
    local started = project:StartRendering({state.render_job_id}, false)
    logValue("StartRendering.return", started)
    if started ~= true then fail("StartRendering did not return true.") end
    state.render_start = "STARTED"
    waitForCompletedRender(project, state.render_job_id, tonumber(profile.color_test.render_timeout_seconds) or 7200)
    runPostflight(profile)
    if project:SetCurrentTimeline(timelineB) ~= true then fail("Could not select B reference timeline.") end
    local startTimecode = timelineB:GetStartTimecode()
    if startTimecode and tostring(startTimecode) ~= "" then timelineB:SetCurrentTimecode(startTimecode) end
    local opened = resolveObject:OpenPage("color")
    logValue("OpenPage.color.return", opened)
    if opened ~= true then fail("OpenPage(color) did not return true.") end
    logLine("REFERENCE GRADE UI READY")
    if manager:SaveProject() ~= true then fail("SaveProject failed after B Color-page handoff.") end
    state.status = "REFERENCE_GRADE_UI_READY_A_MASTER_PASS"
end

local function writeReport(tracebackText)
    local lines = {
        "# Sony S-Log3 Reference Prep report", "",
        "- Status: `" .. state.status .. "`",
        "- Last stage: `" .. state.stage .. "`",
        "- Project: `" .. state.project .. "`",
        "- Source Timeline: `" .. state.source_timeline .. "`",
        "- A Timeline: `" .. state.a_timeline .. "`",
        "- A Grade State: `" .. state.a_grade .. "`",
        "- B Timeline: `" .. state.b_timeline .. "`",
        "- B Grade State: `" .. state.b_grade .. "`",
        "- Render Format Display Name: `" .. state.format_display_name .. "`",
        "- Render Format: `" .. state.selected_format .. "`",
        "- Render Codec: `" .. state.selected_codec .. "`",
        "- Render Job ID: `" .. state.render_job_id .. "`",
        "- Render Start: `" .. state.render_start .. "`",
        "- Render Job Status: `" .. state.render_job_status .. "`",
        "- Master Postflight: `" .. state.postflight_status .. "`",
        "- Output Directory: `" .. state.output_dir .. "`",
        "- Output Basename: `" .. state.output_name .. "`", "",
        "## Warnings", ""
    }
    if #state.warnings == 0 then append(lines, "- None") end
    for _, warning in ipairs(state.warnings) do append(lines, "- " .. warning) end
    append(lines, ""); append(lines, "## Errors"); append(lines, "")
    if #state.errors == 0 then append(lines, "- None") end
    for _, message in ipairs(state.errors) do append(lines, "- " .. message:gsub("[\r\n]", " ")) end
    if tracebackText and tracebackText ~= "" then
        append(lines, ""); append(lines, "## Traceback"); append(lines, ""); append(lines, "```")
        append(lines, tracebackText); append(lines, "```")
    end
    local handle = io.open(REPORT_PATH, "wb")
    if handle then handle:write(table.concat(lines, "\n")); handle:close() end
end

local function main()
    local profile, mapping = loadProfile()
    local resolveObject, manager, project = acquire(profile)
    verifyProject(project, profile)
    local timelineA, timelineB = createTimelines(project, profile, mapping)
    queueAndStartRender(resolveObject, manager, project, timelineA, timelineB, profile)
end

local ok, tracebackText = xpcall(main, tracebackHandler)
if not ok then
    state.status = "ERROR_STOPPED"
    logLine("ERROR")
    logValue("error.stage", state.stage)
    logValue("error.traceback", tracebackText)
else
    logLine("SUCCESS")
end
writeReport(ok and "" or tracebackText)
logLine("STOP")
logValue("final.status", state.status)
