-- Sony SLog3 Diagnostic.lua
-- Internal DaVinci Resolve preflight and one-clip diagnostic.
-- No grading, rendering, LUT, proxy, media move, rename, delete, or overwrite.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ASCII_DIR = TEMP_ROOT .. "/SonySLog3AutoGrade"
local PROFILE_PATH = ASCII_DIR .. "/runtime.lua"
local LOG_PATH = ASCII_DIR .. "/diagnostic.log"
local REPORT_PATH = ASCII_DIR .. "/diagnostic_report.md"
local EMERGENCY_LOG_PATH = TEMP_ROOT .. "/SonySLog3AutoGrade_emergency.log"

local state = {
    status = "STARTING",
    stage = "bootstrap",
    bootstrap_method = "UNKNOWN",
    bootstrap_status = "NOT_STARTED",
    template_path = "",
    project_name = "UNKNOWN",
    profile = {},
    settings = {},
    imported_file = "",
    timeline = "",
    drp_path = "",
    source_metadata_status = "NOT_VERIFIED",
    batch_homogeneity = "NOT_VERIFIED",
    project_input_color_space = "UNKNOWN",
    project_input_gamma = "UNKNOWN",
    per_clip_input_api = "NOT_CHECKED",
    per_clip_input_value = "",
    effective_input_policy = "INPUT_UNVERIFIED",
    input_confidence = "NONE",
    preset_return_type = "NOT_CALLED",
    preset_discovery_project = "UNKNOWN",
    preset_target = "",
    preset_target_status = "NOT_CHECKED",
    visible_presets = {},
    warnings = {},
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

local function ensureAsciiDirectory()
    local probe = io.open(LOG_PATH, "ab")
    if probe then probe:close(); return true end
    os.execute("cmd.exe /d /c if not exist " .. quoted(ASCII_DIR)
        .. " mkdir " .. quoted(ASCII_DIR) .. " >NUL 2>&1")
    local retry, retryError = io.open(LOG_PATH, "ab")
    if retry then retry:close(); return true end
    appendRaw(EMERGENCY_LOG_PATH,
        "ASCII_LOG_INIT_FAILED dir=" .. ASCII_DIR .. " error=" .. tostring(retryError) .. "\n")
    return false
end

local loggerReady = ensureAsciiDirectory()

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
logLine("scope=preflight plus one source clip; no grading or rendering")

local function setStage(name) state.stage = name; logLine("STAGE=" .. name) end
local function logValue(name, value) logLine(name .. "=" .. tostring(value)) end
local function normalize(value) return string.lower((tostring(value or ""):gsub("%s+", ""))) end
local function trim(value) return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function compact(value) return string.lower((tostring(value or ""):gsub("[^%w]", ""))) end
local function contains(value, token) return string.find(normalize(value), normalize(token), 1, true) ~= nil end
local function pathKey(value) return string.lower(tostring(value or ""):gsub("\\", "/")) end
local function basename(path)
    local normalized = tostring(path or ""):gsub("\\", "/")
    return normalized:match("([^/]+)$") or normalized
end
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
                local isSequenceEntry = type(key) == "number" and key >= 1 and key % 1 == 0
                logValue(entry .. ".is_sequence_entry", isSequenceEntry)
                logValue(entry .. ".is_userdata", type(item) == "userdata")
                if type(key) == "string" and key:sub(1, 2) == "__" then
                    logValue(entry .. ".classification", "BRIDGE_METADATA")
                elseif isSequenceEntry then
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

local function validatedSequenceItems(value, validator, label)
    if type(value) ~= "table" then fail(label .. " did not return a Lua table.") end
    local validated = {}
    local count = 0
    for index, item in ipairs(value) do
        local valid, reason = validator(item)
        logValue(label .. ".sequence[" .. tostring(index) .. "].value_type", type(item))
        logValue(label .. ".sequence[" .. tostring(index) .. "].validated", valid)
        if not valid then fail(label .. " sequence entry is invalid: " .. tostring(reason)) end
        count = count + 1
        validated[count] = item
    end
    return validated, count
end

local function validatedSequenceCount(value, validator, label)
    local _, count = validatedSequenceItems(value, validator, label)
    return count
end

local function fileSize(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local size = handle:seek("end")
    handle:close()
    return size
end

local function fileExists(path)
    local size = fileSize(path)
    return size ~= nil
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
    if type(profile) ~= "table" then fail("Runtime profile must return a table.") end
    if tonumber(profile.schema_version) ~= 2 then fail("Unsupported runtime profile schema_version.") end
    if profile.mode ~= "diagnostic" then fail("Diagnostic script requires profile.mode='diagnostic'.") end
    if type(profile.project) ~= "table" or tostring(profile.project.name or "") == "" then fail("Missing project.name.") end
    local bootstrapMethod = tostring(profile.project.bootstrap_method or "")
    if bootstrapMethod ~= "preset" and bootstrapMethod ~= "drp_template" then
        fail("project.bootstrap_method must be 'preset' or 'drp_template'.")
    end
    if bootstrapMethod == "preset" and tostring(profile.project.preset_name or "") == "" then
        fail("preset bootstrap requires a verified project.preset_name.")
    end
    if bootstrapMethod == "drp_template" and tostring(profile.project.template_path or "") == "" then
        fail("drp_template bootstrap requires project.template_path.")
    end
    if profile.project.resume_existing_diagnostic == true then
        if bootstrapMethod ~= "drp_template" then fail("Existing diagnostic resume requires drp_template bootstrap.") end
        if profile.project.allow_load_existing ~= true then fail("Existing diagnostic resume requires allow_load_existing=true.") end
        if profile.project.allow_create ~= false then fail("Existing diagnostic resume requires allow_create=false.") end
    elseif bootstrapMethod == "drp_template" and profile.project.allow_load_existing == true then
        fail("allow_load_existing=true requires resume_existing_diagnostic=true.")
    end
    if type(profile.paths) ~= "table" then fail("Missing paths table.") end
    if type(profile.batch) ~= "table" then fail("Missing batch table.") end
    if type(profile.batch.source_files) ~= "table" or #profile.batch.source_files < 1 then fail("No source_files declared.") end
    if tonumber(profile.batch.width) == nil or tonumber(profile.batch.width) < 1 then fail("Invalid batch.width.") end
    if tonumber(profile.batch.height) == nil or tonumber(profile.batch.height) < 1 then fail("Invalid batch.height.") end
    if tonumber(profile.batch.frame_rate) == nil or tonumber(profile.batch.frame_rate) <= 0 then fail("Invalid batch.frame_rate.") end
    if normalize(profile.batch.gamma) ~= normalize("S-Log3") then fail("Batch gamma is not reliably confirmed as S-Log3.") end
    if normalize(profile.batch.primaries) ~= normalize("Sony S-Gamut3.Cine") then fail("Batch primaries are not reliably confirmed as Sony S-Gamut3.Cine.") end
    if tostring(profile.batch.metadata_confirmation or "") == "" then fail("metadata_confirmation is required.") end
    if profile.batch.homogeneous_metadata_verified ~= true then
        fail("homogeneous_metadata_verified must be explicitly true for the declared batch.")
    end
    if tostring(profile.paths.input_dir or "") == "" or tostring(profile.paths.output_dir or "") == "" then fail("Input/output paths are required.") end
    if pathKey(profile.paths.input_dir) == pathKey(profile.paths.output_dir) then fail("Input and output directories must differ.") end
    local seen = {}
    for _, fileName in ipairs(profile.batch.source_files) do
        if tostring(fileName):find("[/\\]") then fail("source_files must contain filenames only, not paths.") end
        local key = normalize(fileName)
        if seen[key] then fail("Duplicate source filename: " .. tostring(fileName)) end
        seen[key] = true
    end
    if not profile.diagnostic or profile.diagnostic.first_clip_only ~= true then fail("diagnostic.first_clip_only must be true.") end
    if tostring(profile.diagnostic.timeline_name or "") == "" then fail("Missing diagnostic.timeline_name.") end
    state.profile = profile
    state.source_metadata_status = "VERIFIED"
    state.batch_homogeneity = "VERIFIED"
    state.bootstrap_method = bootstrapMethod
    state.template_path = tostring(profile.project.template_path or "")
    logValue("preflight.bootstrap_method", bootstrapMethod)
    logValue("preflight.width", profile.batch.width)
    logValue("preflight.height", profile.batch.height)
    logValue("preflight.frame_rate", profile.batch.frame_rate)
    logValue("preflight.gamma", profile.batch.gamma)
    logValue("preflight.primaries", profile.batch.primaries)
    logValue("preflight.camera_report_only", profile.batch.camera_model or "UNKNOWN")
    logValue("preflight.source_count", #profile.batch.source_files)
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
    if not ok then fail("app:GetResolve raised an error: " .. tostring(resolveObject)) end
    if not resolveObject then fail("app:GetResolve returned nil.") end
    logLine("Resolve=SUCCESS")
    return resolveObject
end

local function acquireProjectManager(resolveObject)
    setStage("ProjectManager")
    local manager = resolveObject:GetProjectManager()
    if not manager then fail("GetProjectManager returned nil.") end
    logLine("ProjectManager=SUCCESS")
    setStage("Current Project")
    local current = manager:GetCurrentProject()
    logValue("current_project.return_type", type(current))
    if current then
        state.preset_discovery_project = tostring(current:GetName())
        logValue("current_project.name", state.preset_discovery_project)
        logLine("Current Project=SUCCESS")
    else
        logLine("Current Project=NONE")
    end
    return manager, current
end

local function addPresetCandidate(candidates, seen, value)
    if type(value) ~= "string" or seen[value] then return end
    seen[value] = true
    candidates[#candidates + 1] = value
end

local function dumpPresetTable(value, path, depth, visited, candidates, candidateSeen)
    if visited[value] then logLine(path .. ".cycle=ALREADY_VISITED"); return true end
    visited[value] = true
    local entries = {}
    local iterateOk, iterateError = pcall(function()
        for key, item in pairs(value) do entries[#entries + 1] = {key = key, value = item} end
    end)
    logValue(path .. ".entry_count", #entries)
    logValue(path .. ".iterate_ok", iterateOk)
    if not iterateOk then logValue(path .. ".iterate_error", iterateError); return false end
    for index, entry in ipairs(entries) do
        local key, item = entry.key, entry.value
        local itemPath = path .. ".entry[" .. tostring(index) .. "]"
        logValue(itemPath .. ".key_type", type(key))
        logValue(itemPath .. ".key", safeString(key))
        logValue(itemPath .. ".value_type", type(item))
        if type(item) == "table" then
            logValue(itemPath .. ".value", "<table>")
        else
            logValue(itemPath .. ".value", safeString(item))
        end

        if depth == 1 and type(item) == "string" then addPresetCandidate(candidates, candidateSeen, item) end
        if depth == 1 and type(key) == "string" and type(item) == "table" then addPresetCandidate(candidates, candidateSeen, key) end
        local compactKey = type(key) == "string" and compact(key) or ""
        if type(item) == "string" and (compactKey == "name" or compactKey == "presetname") then
            addPresetCandidate(candidates, candidateSeen, item)
        end
        if type(item) == "table" then
            local nestedOk = dumpPresetTable(item, itemPath .. ".table", depth + 1, visited, candidates, candidateSeen)
            if not nestedOk then return false end
        end
    end
    return true
end

local function discoverProjectPreset(project, profile)
    setStage("Project Preset Discovery")
    if not project then fail("Preset discovery requires an open current project.") end
    local target = tostring(profile.project.preset_name)
    state.preset_target = target
    logValue("preset_target", target)
    local callOk, result = pcall(function() return project:GetPresetList() end)
    state.preset_return_type = type(result)
    logValue("GetPresetList.call_ok", callOk)
    logValue("GetPresetList.return_type", type(result))
    logLine("PRESET LIST BEGIN")
    if not callOk then
        logValue("GetPresetList.error", result)
        logLine("PRESET LIST END")
        fail("Project:GetPresetList raised an error.")
    end
    if type(result) ~= "table" then
        logValue("GetPresetList.value", safeString(result))
        logLine("PRESET LIST END")
        fail("Project:GetPresetList did not return a table.")
    end

    local candidates, candidateSeen = {}, {}
    local dumpOk = dumpPresetTable(result, "preset_list", 1, {}, candidates, candidateSeen)
    for _, name in ipairs(candidates) do append(state.visible_presets, name) end
    logValue("preset_candidate_count", #candidates)
    for index, name in ipairs(candidates) do logValue("preset_candidate[" .. index .. "]", name) end
    logLine("PRESET LIST END")
    if not dumpOk then fail("Project:GetPresetList returned a table that could not be safely traversed.") end

    local exact, trimmed, caseInsensitive = false, false, false
    for _, name in ipairs(candidates) do
        if name == target then exact = true end
        if trim(name) == trim(target) then trimmed = true end
        if string.lower(trim(name)) == string.lower(trim(target)) then caseInsensitive = true end
    end
    logValue("preset_match.exact", exact)
    logValue("preset_match.trimmed", trimmed)
    logValue("preset_match.case_insensitive", caseInsensitive)
    if not exact then
        state.preset_target_status = "NOT_VISIBLE_TO_API"
        if trimmed then append(state.warnings, "Target preset has only a trim-normalized diagnostic match; it was not selected.") end
        if caseInsensitive then append(state.warnings, "Target preset has only a case-insensitive diagnostic match; it was not selected.") end
        logLine("TARGET PRESET = NOT VISIBLE TO API")
        fail("TARGET PRESET = NOT VISIBLE TO API")
    end
    state.preset_target_status = "EXACT_MATCH"
    logLine("TARGET PRESET = EXACT MATCH")
    logLine("Project Preset Discovery=SUCCESS")
end

local function projectExists(manager, name)
    for _, projectName in ipairs(manager:GetProjectListInCurrentFolder() or {}) do
        if projectName == name then return true end
    end
    return false
end

local function acquireProject(manager, profile)
    setStage("Project")
    local target = profile.project.name
    local current = manager:GetCurrentProject()
    if current and current:GetName() == target then
        if profile.project.allow_load_existing ~= true then
            fail("Current target project already exists but allow_load_existing is false; fresh-project validation refused reuse.")
        end
        state.project_name = target
        logLine("Project=REUSE_CURRENT_TARGET")
        return manager, current
    end
    if current then
        local saved = manager:SaveProject()
        logValue("bootstrap_project.saved", saved)
        if saved ~= true then fail("Could not save the current project before switching.") end
    end
    if projectExists(manager, target) then
        if profile.project.allow_load_existing ~= true then fail("Target project exists but allow_load_existing is false.") end
        current = manager:LoadProject(target)
        if not current then fail("LoadProject returned nil for the exact target project.") end
        state.project_name = target
        logLine("Project=LOADED_EXISTING_TARGET")
        return manager, current
    end
    if profile.project.allow_create ~= true then fail("Target project is absent and allow_create is false.") end
    current = manager:CreateProject(target)
    if not current then fail("CreateProject returned nil for the unique target project.") end
    state.project_name = target
    logLine("Project=CREATED_NEW_TARGET")
    return manager, current
end

local function recordInitialSettings(project)
    setStage("Project Settings / Initial State")
    logLine("INITIAL SETTINGS")
    local keys = {
        "timelinePlaybackFrameRate",
        "timelineFrameRate",
        "timelineResolutionWidth",
        "timelineResolutionHeight"
    }
    for _, key in ipairs(keys) do
        local readOk, actual = pcall(function() return project:GetSetting(key) end)
        logValue("initial." .. key .. ".read_call_ok", readOk)
        logValue("initial." .. key .. ".read_back", actual)
        if not readOk then fail("Initial GetSetting failed for " .. key .. ": " .. tostring(actual)) end
    end
end

local function setReadCompare(project, key, candidates, validator, label)
    setStage("Project Settings / " .. label)
    for _, candidate in ipairs(candidates) do
        local setOk, setResult = pcall(function() return project:SetSetting(key, candidate) end)
        local readOk, actual = pcall(function() return project:GetSetting(key) end)
        logValue("setting.key", key)
        logValue("setting.requested", candidate)
        logValue("setting.set_call_ok", setOk)
        logValue("setting.set_return", setResult)
        logValue("setting.read_call_ok", readOk)
        logValue("setting.read_back", actual)
        local matched = readOk and validator(actual)
        logValue("setting.compare", matched and "MATCH" or "MISMATCH")
        if matched then state.settings[key] = tostring(actual); return actual end
    end
    fail("SET/READ BACK/COMPARE failed for " .. label .. "; actual=" .. tostring(project:GetSetting(key)))
end

local function applyProjectPresetBaseline(project, profile)
    local width = tonumber(profile.batch.width)
    local height = tonumber(profile.batch.height)
    local fps = tonumber(profile.batch.frame_rate)

    -- REG-011: GetSetting can expose properties that SetSetting cannot write.
    -- Establish the complete Project Format baseline through one explicitly
    -- configured and human-verified Resolve Project Preset, then read it back.
    setStage("Project Preset")
    local presetName = tostring(profile.project.preset_name)
    local presetOk, presetResult = pcall(function() return project:SetPreset(presetName) end)
    logValue("project_preset.name", presetName)
    logValue("project_preset.call_ok", presetOk)
    logValue("project_preset.return", presetResult)
    if not (presetOk and presetResult == true) then fail("Project:SetPreset failed for the exact configured preset name.") end

    logLine("PROJECT PRESET READ BACK")
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
        logValue("project_preset." .. key .. ".read_call_ok", readOk)
        logValue("project_preset." .. key .. ".read_back", actual)
        logValue("project_preset." .. key .. ".compare", matched and "MATCH" or "MISMATCH")
        if not matched then fail("Project Preset baseline mismatch for " .. key .. "; actual=" .. tostring(actual)) end
        state.settings[key] = tostring(actual)
    end
    logLine("Project Preset=SUCCESS")
    state.bootstrap_status = "PRESET_VALIDATED"
end

local function validateProjectFormat(project, profile, prefix)
    local width = tonumber(profile.batch.width)
    local height = tonumber(profile.batch.height)
    local fps = tonumber(profile.batch.frame_rate)
    local checks = {
        {"timelinePlaybackFrameRate", function(v) return numberEquals(v, fps) end},
        {"timelineFrameRate", function(v) return numberEquals(v, fps) end},
        {"timelineResolutionWidth", function(v) return tonumber(v) == width end},
        {"timelineResolutionHeight", function(v) return tonumber(v) == height end}
    }
    logLine(string.upper(prefix) .. " FORMAT READ BACK")
    for _, entry in ipairs(checks) do
        local key, validator = entry[1], entry[2]
        local readOk, actual = pcall(function() return project:GetSetting(key) end)
        local matched = readOk and validator(actual)
        logValue(prefix .. "." .. key .. ".read_call_ok", readOk)
        logValue(prefix .. "." .. key .. ".read_back", actual)
        logValue(prefix .. "." .. key .. ".compare", matched and "MATCH" or "MISMATCH")
        if not matched then
            logLine("TEMPLATE VALIDATION FAILED")
            fail("Project Format mismatch for " .. key .. "; actual=" .. tostring(actual))
        end
        state.settings[key] = tostring(actual)
    end
    logLine(string.upper(prefix) .. " FORMAT=ALL MATCH")
end

local function validateBlankTemplateProject(project)
    setStage("DRP Template Blank Validation")
    local mediaPool = project:GetMediaPool()
    if not mediaPool then fail("Imported template GetMediaPool returned nil.") end
    local root = mediaPool:GetRootFolder()
    if not root then fail("Imported template GetRootFolder returned nil.") end
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
    logValue("template_blank.root_clip_count", clipCount)
    logValue("template_blank.root_folder_count", folderCount)
    logValue("template_blank.timeline_count", timelineCount)
    logValue("template_blank.render_job_count", renderJobCount)
    if clipCount ~= 0 or folderCount ~= 0 then fail("Imported DRP template Media Pool is not empty.") end
    if timelineCount ~= 0 then fail("Imported DRP template contains a timeline.") end
    if renderJobCount ~= 0 then fail("Imported DRP template contains render jobs.") end
    logLine("DRP Template Blank Validation=SUCCESS")
end

local function bootstrapFromDrp(manager, currentProject, profile)
    setStage("DRP Template Preflight")
    local templatePath = tostring(profile.project.template_path)
    local target = tostring(profile.project.name)
    local size = fileSize(templatePath)
    logValue("drp_template.path", templatePath)
    logValue("drp_template.size", size)
    if not size or size <= 0 then fail("DRP template is missing or empty.") end
    if profile.project.allow_create ~= true then fail("drp_template bootstrap requires allow_create=true.") end
    if profile.project.allow_load_existing == true then fail("drp_template bootstrap requires allow_load_existing=false.") end
    if projectExists(manager, target) then fail("Target project already exists; DRP import refused reuse.") end
    if currentProject then
        local saved = manager:SaveProject()
        logValue("bootstrap_project.saved", saved)
        if saved ~= true then fail("Could not save the current project before DRP import.") end
    end

    setStage("DRP Template Import")
    local importOk, importResult = pcall(function() return manager:ImportProject(templatePath, target) end)
    logValue("ImportProject.call_ok", importOk)
    logValue("ImportProject.return", importResult)
    if not (importOk and importResult == true) then fail("ProjectManager:ImportProject failed.") end
    local project = manager:LoadProject(target)
    logValue("LoadProject.return_type", type(project))
    if not project then fail("Imported DRP project could not be loaded.") end
    state.project_name = target
    logLine("DRP Template Import=SUCCESS")

    setStage("DRP Template Format Validation")
    validateProjectFormat(project, profile, "drp_template")
    validateBlankTemplateProject(project)
    state.bootstrap_status = "DRP_TEMPLATE_VALIDATED"
    logLine("DRP Template Bootstrap=SUCCESS")
    return project
end

local function configureColorManagement(project)
    setStage("Project Settings / Color Management")
    setReadCompare(project, "colorScienceMode", {"davinciYRGBColorManagedv2", "davinciYRGBColorManaged"},
        function(v) return contains(v, "color") and contains(v, "managed") end, "DaVinci YRGB Color Managed")
    setReadCompare(project, "rcmPresetMode", {"Custom"}, function(v) return contains(v, "custom") end, "RCM Custom")
    setReadCompare(project, "isAutoColorManage", {"0", "false"},
        function(v) return tostring(v) == "0" or normalize(v) == "false" end, "Automatic Color Management OFF")
    setReadCompare(project, "separateColorSpaceAndGamma", {"1"},
        function(v) return tostring(v) == "1" or normalize(v) == "true" end, "Separate Color Space and Gamma")
    setReadCompare(project, "colorSpaceInput", {"Sony S-Gamut3.Cine", "S-Gamut3.Cine"},
        function(v) return contains(v, "s-gamut3.cine") end, "Input Sony S-Gamut3.Cine")
    setReadCompare(project, "colorSpaceInputGamma", {"S-Log3"},
        function(v) return contains(v, "s-log3") end, "Input S-Log3")
    setReadCompare(project, "colorSpaceTimeline", {"DaVinci WG", "DaVinci Wide Gamut"},
        function(v) return contains(v, "davinci") and (contains(v, "widegamut") or contains(v, "wg")) end, "Timeline DaVinci Wide Gamut")
    setReadCompare(project, "colorSpaceTimelineGamma", {"DaVinci Intermediate"},
        function(v) return contains(v, "intermediate") end, "Timeline DaVinci Intermediate")
    setReadCompare(project, "colorSpaceOutput", {"Rec.709"},
        function(v) return contains(v, "rec.709") or contains(v, "rec709") end, "Output Rec.709")
    setReadCompare(project, "colorSpaceOutputGamma", {"Gamma 2.4", "Gamma2.4"},
        function(v) return contains(v, "2.4") end, "Output Gamma 2.4")
    logLine("Color Management=SUCCESS")
end

local function verifyFinalSettings(project, profile)
    setStage("Project Settings / Final Verification")
    logLine("FINAL SETTINGS")
    local width = tonumber(profile.batch.width)
    local height = tonumber(profile.batch.height)
    local fps = tonumber(profile.batch.frame_rate)
    local checks = {
        {"timelinePlaybackFrameRate", function(v) return numberEquals(v, fps) end},
        {"timelineFrameRate", function(v) return numberEquals(v, fps) end},
        {"timelineResolutionWidth", function(v) return tonumber(v) == width end},
        {"timelineResolutionHeight", function(v) return tonumber(v) == height end},
        {"colorScienceMode", function(v) return contains(v, "color") and contains(v, "managed") end},
        {"rcmPresetMode", function(v) return contains(v, "custom") end},
        {"isAutoColorManage", function(v) return tostring(v) == "0" or normalize(v) == "false" end},
        {"separateColorSpaceAndGamma", function(v) return tostring(v) == "1" or normalize(v) == "true" end},
        {"colorSpaceInput", function(v) return contains(v, "s-gamut3.cine") end},
        {"colorSpaceInputGamma", function(v) return contains(v, "s-log3") end},
        {"colorSpaceTimeline", function(v) return contains(v, "davinci") and (contains(v, "widegamut") or contains(v, "wg")) end},
        {"colorSpaceTimelineGamma", function(v) return contains(v, "intermediate") end},
        {"colorSpaceOutput", function(v) return contains(v, "rec.709") or contains(v, "rec709") end},
        {"colorSpaceOutputGamma", function(v) return contains(v, "2.4") end}
    }
    for _, entry in ipairs(checks) do
        local key, validator = entry[1], entry[2]
        local readOk, actual = pcall(function() return project:GetSetting(key) end)
        local matched = readOk and validator(actual)
        logValue("final." .. key .. ".read_call_ok", readOk)
        logValue("final." .. key .. ".read_back", actual)
        logValue("final." .. key .. ".compare", matched and "MATCH" or "MISMATCH")
        if not matched then fail("Final project setting verification failed for " .. key .. "; actual=" .. tostring(actual)) end
        state.settings[key] = tostring(actual)
    end
    logLine("FINAL SETTINGS=ALL MATCH")
end

local function clipPath(clip)
    local direct = clip:GetClipProperty("File Path")
    if direct and tostring(direct) ~= "" then return tostring(direct) end
    for key, value in pairs(clip:GetClipProperty() or {}) do
        if compact(key) == "filepath" then return tostring(value or "") end
    end
    return ""
end

local function validateTimelineItems(timeline, expectedPath, label)
    local callOk, rawItems = pcall(function() return timeline:GetItemListInTrack("video", 1) end)
    logValue(label .. ".call_ok", callOk)
    logValue(label .. ".return_type", type(rawItems))
    if not callOk then fail("GetItemListInTrack(video, 1) failed: " .. tostring(rawItems)) end
    rawItems = rawItems or {}
    dumpRawCollection("TIMELINE ITEM LIST", rawItems)

    local items, count = validatedSequenceItems(rawItems, function(item)
        if type(item) ~= "userdata" then return false, "expected TimelineItem userdata" end
        local nameOk, itemName = pcall(function() return item:GetName() end)
        if not nameOk then return false, "TimelineItem:GetName failed: " .. tostring(itemName) end
        local poolOk, poolItem = pcall(function() return item:GetMediaPoolItem() end)
        if not poolOk then return false, "TimelineItem:GetMediaPoolItem failed: " .. tostring(poolItem) end
        if type(poolItem) ~= "userdata" then return false, "GetMediaPoolItem did not return MediaPoolItem userdata" end
        return true
    end, label)
    logValue("validated_video_item_count", count)
    if count == 0 then fail("EMPTY_DIAGNOSTIC_TIMELINE: existing timeline has no validated video item; no replacement was created.") end
    if count ~= 1 then fail("Diagnostic timeline must contain exactly one validated video item; found " .. tostring(count) .. ".") end

    local poolOk, poolItem = pcall(function() return items[1]:GetMediaPoolItem() end)
    logValue(label .. ".media_pool_item_call_ok", poolOk)
    logValue(label .. ".media_pool_item_type", type(poolItem))
    if not poolOk or type(poolItem) ~= "userdata" then fail("Validated TimelineItem lost its MediaPoolItem association.") end
    local actualPath = clipPath(poolItem)
    logValue(label .. ".media_pool_item_path", actualPath)
    logValue(label .. ".exact_source", pathKey(actualPath) == pathKey(expectedPath))
    if pathKey(actualPath) ~= pathKey(expectedPath) then fail("Timeline source verification failed.") end
    logLine("TIMELINE=ONE_EXACT_SOURCE")
    return items[1]
end

local function rootObjects(project)
    local mediaPool = project:GetMediaPool()
    if not mediaPool then fail("GetMediaPool returned nil.") end
    local root = mediaPool:GetRootFolder()
    if not root then fail("GetRootFolder returned nil.") end
    return mediaPool, root, root:GetClipList() or {}
end

local function findExactClip(clips, expectedPath)
    for _, clip in ipairs(clips) do
        if pathKey(clipPath(clip)) == pathKey(expectedPath) then return clip end
    end
    return nil
end

local function resumeExistingDiagnostic(manager, currentProject, profile)
    setStage("Existing Diagnostic Resume")
    local target = tostring(profile.project.name)
    if profile.project.resume_existing_diagnostic ~= true then fail("Existing diagnostic resume was not explicitly authorized.") end
    if profile.project.allow_create ~= false or profile.project.allow_load_existing ~= true then
        fail("Existing diagnostic resume safety flags are invalid.")
    end
    if not projectExists(manager, target) then fail("Explicit resume target does not exist; fresh project creation is disabled.") end

    local project = currentProject
    if not project or tostring(project:GetName()) ~= target then
        if project then
            local saved = manager:SaveProject()
            logValue("resume_previous_project.saved", saved)
            if saved ~= true then fail("Could not save the current project before loading the resume target.") end
        end
        project = manager:LoadProject(target)
    end
    logValue("resume_project.return_type", type(project))
    if not project or tostring(project:GetName()) ~= target then fail("Exact existing diagnostic project could not be loaded.") end
    state.project_name = target

    setStage("Existing Diagnostic Format Validation")
    validateProjectFormat(project, profile, "resume_existing")

    setStage("Existing Diagnostic Content Validation")
    local mediaPool, root, clips = rootObjects(project)
    local folders = root:GetSubFolderList() or {}
    local renderJobs = project:GetRenderJobList() or {}
    local timelineCount = tonumber(project:GetTimelineCount()) or -1
    dumpRawCollection("RESUME CLIP LIST", clips)
    dumpRawCollection("RESUME SUBFOLDER LIST", folders)
    dumpRawCollection("RESUME RENDER JOB LIST", renderJobs)
    local clipCount = validatedSequenceCount(clips, function(item)
        if type(item) ~= "userdata" then return false, "expected MediaPoolItem userdata" end
        return true
    end, "resume_clip_list")
    local folderCount = validatedSequenceCount(folders, function(item)
        if type(item) ~= "userdata" then return false, "expected Folder userdata" end
        return true
    end, "resume_subfolder_list")
    local renderJobCount = validatedSequenceCount(renderJobs, function(item)
        if type(item) ~= "table" then return false, "expected render job information table" end
        if tostring(item.JobId or "") == "" then return false, "missing JobId" end
        return true
    end, "resume_render_job_list")
    local firstName = tostring(profile.batch.source_files[1])
    local expectedPath = tostring(profile.paths.input_dir):gsub("[\\/]$", "") .. "/" .. firstName
    local exactClip = findExactClip(clips, expectedPath)
    logValue("resume.root_clip_count", clipCount)
    logValue("resume.root_folder_count", folderCount)
    logValue("resume.timeline_count", timelineCount)
    logValue("resume.render_job_count", renderJobCount)
    logValue("resume.exact_first_source", exactClip ~= nil)
    if clipCount ~= 1 or not exactClip then fail("Resume target must contain exactly the previously imported first source.") end
    if folderCount ~= 0 then fail("Resume target contains unexpected Media Pool folders.") end
    if timelineCount < 0 or timelineCount > 1 then fail("Resume target must contain zero or one diagnostic timeline.") end
    if renderJobCount ~= 0 then fail("Resume target contains render jobs.") end
    state.imported_file = firstName
    if timelineCount == 1 then
        local existingTimeline = project:GetTimelineByIndex(1)
        local nameOk, existingName = pcall(function() return existingTimeline and existingTimeline:GetName() end)
        logValue("resume.timeline_name_call_ok", nameOk)
        logValue("resume.timeline_name", existingName)
        if not nameOk or not existingTimeline or tostring(existingName) ~= tostring(profile.diagnostic.timeline_name) then
            fail("Existing timeline name does not match the expected diagnostic timeline.")
        end
        validateTimelineItems(existingTimeline, expectedPath, "resume_timeline_item_list")
        state.timeline = tostring(profile.diagnostic.timeline_name)
        state.bootstrap_status = "REUSED_EXISTING_DIAGNOSTIC_TIMELINE"
        append(state.warnings, "REUSE_EXISTING_DIAGNOSTIC_TIMELINE: the sole existing timeline was validated as the exact first source and will not be recreated.")
        logLine("REUSE_EXISTING_DIAGNOSTIC_TIMELINE")
    else
        state.bootstrap_status = "RESUMED_EXISTING_DIAGNOSTIC"
        append(state.warnings, "Explicitly resumed the exact one-clip, zero-timeline diagnostic failure state; no DRP was re-imported.")
    end
    logLine("Existing Diagnostic Resume=SUCCESS")
    return project, mediaPool, exactClip, expectedPath
end

local function ensureOneClip(project, profile)
    setStage("Media Pool")
    local mediaPool, root, clips = rootObjects(project)
    local folders = root:GetSubFolderList() or {}
    dumpRawCollection("MEDIA POOL CLIP LIST", clips)
    dumpRawCollection("MEDIA POOL SUBFOLDER LIST", folders)
    local clipCount = validatedSequenceCount(clips, function(item)
        if type(item) ~= "userdata" then return false, "expected MediaPoolItem userdata" end
        return true
    end, "media_pool_clip_list")
    local folderCount = validatedSequenceCount(folders, function(item)
        if type(item) ~= "userdata" then return false, "expected Folder userdata" end
        return true
    end, "media_pool_subfolder_list")
    local firstName = profile.batch.source_files[1]
    local fullPath = tostring(profile.paths.input_dir):gsub("[\\/]$", "") .. "/" .. firstName
    local clip = findExactClip(clips, fullPath)
    if clipCount > 0 and not (clipCount == 1 and clip) then fail("Target project contains unexpected Media Pool content.") end
    if folderCount > 0 then fail("Target project contains unexpected Media Pool folders.") end
    if not clip then
        setStage("Media Import")
        logValue("media_import.path", fullPath)
        local ok, imported = pcall(function() return mediaPool:ImportMedia({fullPath}) end)
        logValue("media_import.call_ok", ok)
        logValue("media_import.return_type", type(imported))
        if not ok then fail("ImportMedia raised an error: " .. tostring(imported)) end
        if type(imported) ~= "table" then fail("ImportMedia did not return a table.") end
        dumpRawCollection("IMPORT MEDIA RESULT", imported)
        local importedItems, importedCount = validatedSequenceItems(imported, function(item)
            if type(item) ~= "userdata" then return false, "expected imported MediaPoolItem userdata" end
            return true
        end, "import_media_result")
        logValue("media_import.validated_item_count", importedCount)
        if importedCount ~= 1 then fail("ImportMedia must return exactly one validated MediaPoolItem.") end
        clip = importedItems[1]
    else
        append(state.warnings, "The exact diagnostic source was already present and was reused.")
    end
    local _, _, after = rootObjects(project)
    dumpRawCollection("MEDIA POOL POST IMPORT CLIP LIST", after)
    local afterCount = validatedSequenceCount(after, function(item)
        if type(item) ~= "userdata" then return false, "expected MediaPoolItem userdata" end
        return true
    end, "media_pool_post_import_clip_list")
    if afterCount ~= 1 or not findExactClip(after, fullPath) then fail("Media Pool post-import verification failed.") end
    state.imported_file = firstName
    logLine("Media Import=SUCCESS")
    logLine("Media Pool=ONE_EXACT_SOURCE")
    return mediaPool, clip, fullPath
end

local function evaluateInputPolicy(project, clip, profile)
    setStage("Input Color Space Policy")
    local metadataVerified = tostring(profile.batch.metadata_confirmation or "") ~= ""
        and normalize(profile.batch.gamma) == normalize("S-Log3")
        and normalize(profile.batch.primaries) == normalize("Sony S-Gamut3.Cine")
    local homogeneousVerified = metadataVerified
        and profile.batch.homogeneous_metadata_verified == true
        and type(profile.batch.source_files) == "table" and #profile.batch.source_files > 0
    state.source_metadata_status = metadataVerified and "VERIFIED" or "NOT_VERIFIED"
    state.batch_homogeneity = homogeneousVerified and "VERIFIED" or "NOT_VERIFIED"

    local projectInput = project:GetSetting("colorSpaceInput")
    local projectGamma = project:GetSetting("colorSpaceInputGamma")
    local autoManage = project:GetSetting("isAutoColorManage")
    state.project_input_color_space = tostring(projectInput or "")
    state.project_input_gamma = tostring(projectGamma or "")
    logValue("input_policy.source_metadata", state.source_metadata_status)
    logValue("input_policy.batch_homogeneity", state.batch_homogeneity)
    logValue("input_policy.project_input_color_space", projectInput)
    logValue("input_policy.project_input_gamma", projectGamma)
    logValue("input_policy.automatic_color_management", autoManage)
    if not metadataVerified or not homogeneousVerified then
        state.effective_input_policy = "INPUT_UNVERIFIED"
        fail("Source metadata or batch homogeneity is not verified.")
    end
    if not contains(projectInput, "s-gamut3.cine") or not contains(projectGamma, "s-log3") then
        state.effective_input_policy = "INPUT_UNVERIFIED"
        fail("Verified project Input Color Space does not match the homogeneous batch.")
    end
    if not (tostring(autoManage) == "0" or normalize(autoManage) == "false") then
        state.effective_input_policy = "INPUT_UNVERIFIED"
        fail("Automatic Color Management is not OFF.")
    end

    local evidence = {}
    local inheritanceEvidence = false
    local function recordEvidence(source, value)
        local textValue = trim(value)
        logValue("clip_input." .. source .. ".value", textValue)
        if textValue == "" then return end
        if normalize(textValue) == "project" or textValue == "项目" then
            inheritanceEvidence = true
            return
        end
        evidence[#evidence + 1] = {source = source, value = textValue}
    end

    local directOk, directValue = pcall(function() return clip:GetClipProperty("Input Color Space") end)
    logValue("clip_input.direct.call_ok", directOk)
    logValue("clip_input.direct.return_type", type(directValue))
    if directOk then recordEvidence("direct", directValue) end

    local snapshotOk, properties = pcall(function() return clip:GetClipProperty() end)
    logValue("clip_input.snapshot.call_ok", snapshotOk)
    logValue("clip_input.snapshot.return_type", type(properties))
    if snapshotOk and type(properties) == "table" then
        local matchIndex = 0
        for key, value in pairs(properties) do
            if type(key) == "string" and key:sub(1, 2) ~= "__"
                and contains(key, "input") and contains(key, "color") and contains(key, "space") then
                matchIndex = matchIndex + 1
                logValue("clip_input.snapshot_match[" .. matchIndex .. "].key", key)
                logValue("clip_input.snapshot_match[" .. matchIndex .. "].value_type", type(value))
                recordEvidence("snapshot_match[" .. matchIndex .. "]", value)
            end
        end
        logValue("clip_input.snapshot_match_count", matchIndex)
    end

    for _, item in ipairs(evidence) do
        if not (contains(item.value, "s-gamut3.cine") and contains(item.value, "s-log3")) then
            state.per_clip_input_api = "AVAILABLE_CONFLICT"
            state.per_clip_input_value = item.value
            state.effective_input_policy = "INPUT_UNVERIFIED"
            fail("Per-clip Input Color Space explicitly conflicts with the verified batch: " .. item.value)
        end
    end
    if #evidence > 0 then
        state.per_clip_input_api = "AVAILABLE_MATCH"
        state.per_clip_input_value = evidence[1].value
        state.effective_input_policy = "EXPLICIT_CLIP_MATCH"
        state.input_confidence = "HIGHEST — explicit clip match plus verified project input"
        logLine("INPUT POLICY=EXPLICIT_CLIP_MATCH")
        return
    end

    state.per_clip_input_api = inheritanceEvidence and "PROJECT_INHERITANCE" or "UNAVAILABLE / EMPTY"
    state.per_clip_input_value = inheritanceEvidence and "Project" or ""
    state.effective_input_policy = "VERIFIED_PROJECT_DEFAULT"
    state.input_confidence = "HIGH — homogeneous metadata plus verified project input"
    append(state.warnings,
        "Per-clip Input Color Space is not exposed by the current Resolve scripting API. Effective input is accepted from independently verified homogeneous source metadata plus verified project-level input color management.")
    logLine("PER_CLIP_INPUT_API=" .. state.per_clip_input_api)
    logLine("INPUT POLICY=VERIFIED_PROJECT_DEFAULT")
end

local function findTimeline(project, name)
    for index = 1, project:GetTimelineCount() do
        local timeline = project:GetTimelineByIndex(index)
        if timeline and timeline:GetName() == name then return timeline end
    end
    return nil
end

local function ensureTimeline(project, mediaPool, clip, sourcePath, profile)
    setStage("Timeline")
    local name = profile.diagnostic.timeline_name
    local timeline = findTimeline(project, name)
    if project:GetTimelineCount() > 0 and not (project:GetTimelineCount() == 1 and timeline) then
        fail("Target project contains unexpected timeline content.")
    end
    local reused = timeline ~= nil
    if not timeline then timeline = mediaPool:CreateTimelineFromClips(name, {clip}) end
    if not timeline then fail("CreateTimelineFromClips returned nil.") end
    validateTimelineItems(timeline, sourcePath, "timeline_item_list")
    if reused then logLine("REUSE_EXISTING_DIAGNOSTIC_TIMELINE") end
    local checks = {
        {"timelineResolutionWidth", tonumber(profile.batch.width)},
        {"timelineResolutionHeight", tonumber(profile.batch.height)},
        {"timelineFrameRate", tonumber(profile.batch.frame_rate)},
        {"timelinePlaybackFrameRate", tonumber(profile.batch.frame_rate)}
    }
    for _, entry in ipairs(checks) do
        local actual = timeline:GetSetting(entry[1])
        logValue("timeline." .. entry[1], actual)
        if not numberEquals(actual, entry[2]) then fail("Timeline setting mismatch: " .. entry[1] .. "=" .. tostring(actual)) end
    end
    local currentSet = project:SetCurrentTimeline(timeline)
    logValue("SetCurrentTimeline.return", currentSet)
    if currentSet ~= true then fail("SetCurrentTimeline did not return true.") end
    state.timeline = name
    logLine("Timeline=SUCCESS")
end

local function backupPath(projectName)
    local safeName = tostring(projectName):gsub("[^%w%._%-]", "_")
    local base = ASCII_DIR .. "/" .. safeName .. "_01_setup"
    local preferred = base .. ".drp"
    if not fileExists(preferred) then return preferred end
    return base .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".drp"
end

local function writeReport(tracebackText)
    local lines = {
        "# Sony S-Log3 Diagnostic report", "",
        "- Status: `" .. state.status .. "`",
        "- Last stage: `" .. state.stage .. "`",
        "- Bootstrap method: `" .. state.bootstrap_method .. "`",
        "- Bootstrap status: `" .. state.bootstrap_status .. "`",
        "- Template path: `" .. state.template_path .. "`",
        "- Project: `" .. state.project_name .. "`",
        "- Imported first source: `" .. state.imported_file .. "`",
        "- Timeline: `" .. state.timeline .. "`",
        "- DRP staging: `" .. state.drp_path .. "`", "",
        "## Input policy", "",
        "- Source Metadata: `" .. state.source_metadata_status .. "`",
        "- Batch Homogeneity: `" .. state.batch_homogeneity .. "`",
        "- Project Input Color Space: `" .. state.project_input_color_space .. "`",
        "- Project Input Gamma: `" .. state.project_input_gamma .. "`",
        "- Per-Clip Input API: `" .. state.per_clip_input_api .. "`",
        "- Per-Clip Input Value: `" .. state.per_clip_input_value .. "`",
        "- Effective Input Policy: `" .. state.effective_input_policy .. "`",
        "- Confidence: `" .. state.input_confidence .. "`", "",
        "## Project Preset discovery", "",
        "- Discovery project: `" .. state.preset_discovery_project .. "`",
        "- GetPresetList return type: `" .. state.preset_return_type .. "`",
        "- Target preset: `" .. state.preset_target .. "`",
        "- Target status: `" .. state.preset_target_status .. "`",
        "- Visible preset candidates:", ""
    }
    if #state.visible_presets == 0 then append(lines, "  - None") end
    for _, name in ipairs(state.visible_presets) do append(lines, "  - `" .. name .. "`") end
    append(lines, "")
    append(lines, "## Settings read back")
    append(lines, "")
    local keys = {}
    for key, _ in pairs(state.settings) do append(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do append(lines, "- `" .. key .. "` = `" .. state.settings[key] .. "`") end
    append(lines, "")
    append(lines, "## Warnings")
    append(lines, "")
    if #state.warnings == 0 then append(lines, "- None") end
    for _, warning in ipairs(state.warnings) do append(lines, "- " .. warning) end
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
    local manager, currentProject = acquireProjectManager(resolveObject)
    local project = nil
    if profile.project.bootstrap_method == "preset" then
        discoverProjectPreset(currentProject, profile)
        local _, presetProject = acquireProject(manager, profile)
        project = presetProject
        recordInitialSettings(project)
        applyProjectPresetBaseline(project, profile)
    elseif profile.project.bootstrap_method == "drp_template" then
        if profile.project.resume_existing_diagnostic == true then
            project = resumeExistingDiagnostic(manager, currentProject, profile)
        else
            project = bootstrapFromDrp(manager, currentProject, profile)
        end
    else
        fail("Unsupported bootstrap method after runtime validation.")
    end
    configureColorManagement(project)
    verifyFinalSettings(project, profile)
    local mediaPool, clip, sourcePath = ensureOneClip(project, profile)
    evaluateInputPolicy(project, clip, profile)
    ensureTimeline(project, mediaPool, clip, sourcePath, profile)

    setStage("Save Project")
    local saved = manager:SaveProject()
    logValue("SaveProject.return", saved)
    if saved ~= true then fail("SaveProject did not return true.") end
    logLine("Save Project=SUCCESS")

    setStage("Export Project")
    local drpPath = backupPath(profile.project.name)
    state.drp_path = drpPath
    local exportOk, exportResult = pcall(function() return manager:ExportProject(profile.project.name, drpPath, false) end)
    logValue("ExportProject.call_ok", exportOk)
    logValue("ExportProject.return", exportResult)
    if not (exportOk and exportResult == true and fileExists(drpPath)) then
        append(state.warnings, "ExportProject failed after SaveProject; no retry was attempted.")
    else
        logLine("Export Project=SUCCESS")
    end

    setStage("OpenPage")
    local opened = resolveObject:OpenPage("edit")
    logValue("OpenPage.edit.return", opened)
    if opened ~= true then fail("OpenPage(edit) did not return true.") end
    logLine("OpenPage=SUCCESS")
    state.status = "SUCCESS_DIAGNOSTIC_READY"
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
