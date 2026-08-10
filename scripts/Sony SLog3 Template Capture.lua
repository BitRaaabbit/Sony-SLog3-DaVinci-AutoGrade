-- Sony SLog3 Template Capture.lua
-- Captures one verified, completely blank Resolve project as a private DRP.
-- No project setting changes, media import, grading, rendering, or overwrite.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ASCII_DIR = TEMP_ROOT .. "/SonySLog3AutoGrade"
local PROFILE_PATH = ASCII_DIR .. "/runtime.lua"
local LOG_PATH = ASCII_DIR .. "/template_capture.log"
local REPORT_PATH = ASCII_DIR .. "/template_capture_report.md"
local EMERGENCY_LOG_PATH = TEMP_ROOT .. "/SonySLog3AutoGrade_template_capture_emergency.log"

local state = {
    status = "STARTING",
    stage = "bootstrap",
    project_name = "UNKNOWN",
    template_path = "",
    template_size = 0,
    settings = {},
    errors = {}
}

local function append(list, value) list[#list + 1] = tostring(value) end

local function appendRaw(path, text)
    local handle, openError = io.open(path, "ab")
    if not handle then return false, openError end
    handle:write(text)
    handle:close()
    return true, nil
end

local function quoted(path)
    return '"' .. tostring(path):gsub("/", "\\"):gsub('"', '""') .. '"'
end

local function ensureDirectory(path)
    os.execute("cmd.exe /d /c if not exist " .. quoted(path)
        .. " mkdir " .. quoted(path) .. " >NUL 2>&1")
end

ensureDirectory(ASCII_DIR)
local loggerReady = io.open(LOG_PATH, "ab")
if loggerReady then loggerReady:close(); loggerReady = true else loggerReady = false end

local function logLine(text)
    local line = tostring(text or "") .. "\n"
    if loggerReady then
        local ok, openError = appendRaw(LOG_PATH, line)
        if ok then return end
        appendRaw(EMERGENCY_LOG_PATH,
            "ASCII_LOG_WRITE_FAILED error=" .. tostring(openError) .. "\n" .. line)
    else
        appendRaw(EMERGENCY_LOG_PATH, line)
    end
end

logLine("")
logLine("============================================================")
logLine("START")
logLine("timestamp=" .. os.date("%Y-%m-%d %H:%M:%S %z"))
logLine("interface=internal Workspace > Scripts Lua")
logLine("scope=blank project validation and collision-safe DRP export only")

local function setStage(name) state.stage = name; logLine("STAGE=" .. name) end
local function logValue(name, value) logLine(name .. "=" .. tostring(value)) end
local function numberEquals(value, expected)
    local number = tonumber(value)
    return number ~= nil and math.abs(number - expected) < 0.001
end

local fail

local function safeString(value)
    local ok, result = pcall(function() return tostring(value) end)
    return ok and result or "<tostring failed: " .. tostring(result) .. ">"
end

local function dumpRawCollection(label, value)
    local prefix = string.lower(label):gsub("[^%w]+", "_")
    logLine(label .. " RAW BEGIN")
    logValue(prefix .. ".type", type(value))
    if type(value) == "table" then
        local index = 0
        local iterateOk, iterateError = pcall(function()
            for key, item in pairs(value) do
                index = index + 1
                local entry = prefix .. ".entry[" .. tostring(index) .. "]"
                logValue(entry .. ".key_type", type(key))
                logValue(entry .. ".key", safeString(key))
                logValue(entry .. ".value_type", type(item))
                logValue(entry .. ".value", safeString(item))
                if type(key) == "string" and key:sub(1, 2) == "__" then
                    logValue(entry .. ".classification", "BRIDGE_METADATA")
                elseif type(key) == "number" then
                    logValue(entry .. ".classification", "SEQUENCE_CANDIDATE")
                else
                    logValue(entry .. ".classification", "NON_SEQUENCE_AUXILIARY")
                end
            end
        end)
        logValue(prefix .. ".top_level_entry_count_diagnostic_only", index)
        logValue(prefix .. ".iterate_ok", iterateOk)
        if not iterateOk then logValue(prefix .. ".iterate_error", iterateError) end
    else
        logValue(prefix .. ".value", safeString(value))
    end
    logLine(label .. " RAW END")
end

local function validatedSequenceCount(value, validator, label)
    if type(value) ~= "table" then fail(label .. " did not return a Lua table.") end
    local count = 0
    for index, item in ipairs(value) do
        local valid, reason = validator(item)
        logValue(label .. ".sequence[" .. tostring(index) .. "].value_type", type(item))
        logValue(label .. ".sequence[" .. tostring(index) .. "].validated", valid)
        if not valid then fail(label .. " sequence entry is invalid: " .. tostring(reason)) end
        count = count + 1
    end
    return count
end

local function fileSize(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local size = handle:seek("end")
    handle:close()
    return size
end

local function tracebackHandler(errorValue)
    local message = tostring(errorValue)
    if debug and type(debug.traceback) == "function" then return debug.traceback(message, 2) end
    return message
end

fail = function(message)
    append(state.errors, "stage=" .. state.stage .. " | " .. tostring(message))
    error(tostring(message), 0)
end

local function loadRuntimeProfile()
    setStage("Runtime Profile")
    logValue("profile.path", PROFILE_PATH)
    local loader, loadError = loadfile(PROFILE_PATH)
    if not loader then fail("Cannot load the ASCII runtime profile: " .. tostring(loadError)) end
    local callOk, profile = pcall(loader)
    logValue("profile.call_ok", callOk)
    logValue("profile.return_type", type(profile))
    if not callOk then fail("Runtime profile raised an error: " .. tostring(profile)) end
    if type(profile) ~= "table" or tonumber(profile.schema_version) ~= 2 then fail("Unsupported runtime profile.") end
    if type(profile.project) ~= "table" then fail("Missing project table.") end
    if tostring(profile.project.bootstrap_method or "") ~= "drp_template" then
        fail("Template Capture requires project.bootstrap_method='drp_template'.")
    end
    local templatePath = tostring(profile.project.template_path or "")
    if templatePath == "" then fail("Missing project.template_path.") end
    if templatePath:find("[^\1-\127]") then fail("project.template_path must be ASCII-only.") end
    if type(profile.batch) ~= "table" then fail("Missing batch table.") end
    local width = tonumber(profile.batch.width)
    local height = tonumber(profile.batch.height)
    local fps = tonumber(profile.batch.frame_rate)
    if not width or width < 1 or not height or height < 1 or not fps or fps <= 0 then
        fail("Invalid batch format values.")
    end
    state.template_path = templatePath
    logValue("template.path", templatePath)
    logValue("expected.width", width)
    logValue("expected.height", height)
    logValue("expected.frame_rate", fps)
    logLine("Runtime Profile=SUCCESS")
    return profile
end

local function acquireResolve()
    setStage("Resolve")
    local appObject = rawget(_G, "app")
    logValue("app.type", type(appObject))
    if not appObject then fail("Internal global app is unavailable.") end
    local ok, resolveObject = pcall(function() return appObject:GetResolve() end)
    logValue("app.GetResolve.call_ok", ok)
    logValue("app.GetResolve.return_type", type(resolveObject))
    if not ok or not resolveObject then fail("app:GetResolve failed: " .. tostring(resolveObject)) end
    logLine("Resolve=SUCCESS")
    return resolveObject
end

local function acquireProject(resolveObject, profile)
    setStage("ProjectManager")
    local manager = resolveObject:GetProjectManager()
    if not manager then fail("GetProjectManager returned nil.") end
    logLine("ProjectManager=SUCCESS")
    setStage("Current Project")
    local project = manager:GetCurrentProject()
    if not project then fail("GetCurrentProject returned nil.") end
    local name = tostring(project:GetName() or "")
    state.project_name = name
    logValue("project.name", name)
    local expectedName = tostring(profile.project.template_capture_project_name or "")
    if expectedName ~= "" and name ~= expectedName then
        fail("Current project name does not match project.template_capture_project_name.")
    end
    logLine("Current Project=SUCCESS")
    return manager, project
end

local function validateBlank(project)
    setStage("Blank Project Validation")
    local mediaPool = project:GetMediaPool()
    if not mediaPool then fail("GetMediaPool returned nil.") end
    local root = mediaPool:GetRootFolder()
    if not root then fail("GetRootFolder returned nil.") end
    local clips = root:GetClipList() or {}
    local folders = root:GetSubFolderList() or {}
    local timelineCount = tonumber(project:GetTimelineCount()) or -1
    local renderJobs = project:GetRenderJobList() or {}
    dumpRawCollection("CLIP LIST", clips)
    dumpRawCollection("SUBFOLDER LIST", folders)
    dumpRawCollection("RENDER JOB LIST", renderJobs)
    local clipCount = validatedSequenceCount(clips, function(item)
        if type(item) ~= "userdata" then return false, "expected MediaPoolItem userdata" end
        return true
    end, "clip_list")
    local folderCount = validatedSequenceCount(folders, function(item)
        if type(item) ~= "userdata" then return false, "expected Folder userdata" end
        return true
    end, "subfolder_list")
    local renderJobCount = validatedSequenceCount(renderJobs, function(item)
        if type(item) ~= "table" then return false, "expected render job information table" end
        if tostring(item.JobId or "") == "" then return false, "missing JobId" end
        return true
    end, "render_job_list")
    logValue("blank.root_clip_count", clipCount)
    logValue("blank.root_folder_count", folderCount)
    logValue("blank.timeline_count", timelineCount)
    logValue("blank.render_job_count", renderJobCount)
    if clipCount ~= 0 or folderCount ~= 0 then fail("Media Pool is not completely empty.") end
    if timelineCount ~= 0 then fail("Project contains a timeline.") end
    if renderJobCount ~= 0 then fail("Render queue is not empty.") end
    logLine("Blank Project Validation=SUCCESS")
end

local function validateFormat(project, profile)
    setStage("Project Format Read Back")
    local width = tonumber(profile.batch.width)
    local height = tonumber(profile.batch.height)
    local fps = tonumber(profile.batch.frame_rate)
    local checks = {
        {"timelinePlaybackFrameRate", function(v) return numberEquals(v, fps) end},
        {"timelineFrameRate", function(v) return numberEquals(v, fps) end},
        {"timelineResolutionWidth", function(v) return tonumber(v) == width end},
        {"timelineResolutionHeight", function(v) return tonumber(v) == height end}
    }
    for _, entry in ipairs(checks) do
        local key, validator = entry[1], entry[2]
        local readOk, actual = pcall(function() return project:GetSetting(key) end)
        local matched = readOk and validator(actual)
        logValue("format." .. key .. ".read_call_ok", readOk)
        logValue("format." .. key .. ".read_back", actual)
        logValue("format." .. key .. ".compare", matched and "MATCH" or "MISMATCH")
        if not matched then fail("Project Format mismatch for " .. key .. "; actual=" .. tostring(actual)) end
        state.settings[key] = tostring(actual)
    end
    logLine("Project Format=ALL MATCH")
end

local function exportTemplate(manager, project, profile)
    setStage("Template Path Preflight")
    local path = state.template_path
    if fileSize(path) ~= nil then fail("Template path already exists; overwrite refused.") end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then fail("Template path has no parent directory.") end
    ensureDirectory(parent)
    if fileSize(path) ~= nil then fail("Template path appeared during preflight; overwrite refused.") end

    setStage("Save Project")
    local saved = manager:SaveProject()
    logValue("SaveProject.return", saved)
    if saved ~= true then fail("SaveProject did not return true.") end
    logLine("Save Project=SUCCESS")

    setStage("Export Project")
    local projectName = tostring(project:GetName())
    local callOk, result = pcall(function()
        return manager:ExportProject(projectName, path, false)
    end)
    logValue("ExportProject.call_ok", callOk)
    logValue("ExportProject.return", result)
    if not (callOk and result == true) then fail("ProjectManager:ExportProject failed.") end
    local size = fileSize(path)
    logValue("template.size", size)
    if not size or size <= 0 then fail("Exported DRP is missing or empty.") end
    state.template_size = size
    state.status = "SUCCESS_TEMPLATE_CAPTURED"
    logLine("TEMPLATE CAPTURE=SUCCESS")
end

local function writeReport(tracebackText)
    local lines = {
        "# Sony S-Log3 Template Capture report", "",
        "- Status: `" .. state.status .. "`",
        "- Last stage: `" .. state.stage .. "`",
        "- Project: `" .. state.project_name .. "`",
        "- Template path: `" .. state.template_path .. "`",
        "- Template size: `" .. tostring(state.template_size) .. "` bytes", "",
        "## Project Format read back", ""
    }
    local keys = {}
    for key, _ in pairs(state.settings) do append(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do append(lines, "- `" .. key .. "` = `" .. state.settings[key] .. "`") end
    append(lines, "")
    append(lines, "## Errors")
    append(lines, "")
    if #state.errors == 0 then append(lines, "- None") end
    for _, message in ipairs(state.errors) do append(lines, "- " .. message:gsub("[\r\n]", " ")) end
    if tracebackText and tracebackText ~= "" then
        append(lines, ""); append(lines, "## Traceback"); append(lines, ""); append(lines, "```")
        append(lines, tracebackText); append(lines, "```")
    end
    local handle = io.open(REPORT_PATH, "wb")
    if handle then handle:write(table.concat(lines, "\n")); handle:close(); return true end
    return false
end

local function main()
    local profile = loadRuntimeProfile()
    local resolveObject = acquireResolve()
    local manager, project = acquireProject(resolveObject, profile)
    validateBlank(project)
    validateFormat(project, profile)
    exportTemplate(manager, project, profile)
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
