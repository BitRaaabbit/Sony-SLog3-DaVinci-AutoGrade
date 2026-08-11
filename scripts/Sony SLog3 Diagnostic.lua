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
    original_source = "",
    resolve_working_media = "",
    working_media_required = false,
    working_media_mapping = "NOT_CHECKED",
    working_media_import = "NOT_STARTED",
    working_media_video_decode = "NOT_TESTED",
    compatibility_reason = "NONE",
    range_transform = "NONE",
    signal_equivalence_status = "NOT_APPLICABLE",
    original_metadata_policy = "NOT_VERIFIED",
    working_resolution = "",
    working_fps = "",
    working_video_codec = "",
    working_codec_declared = "",
    working_pixel_format_declared = "",
    working_width_declared = "",
    working_height_declared = "",
    working_frame_rate_declared = "",
    working_frames_declared = "",
    working_duration_declared = "",
    working_sha256_declared = "",
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
    media_pool_source_count = -1,
    media_pool_timeline_item_count = -1,
    media_pool_other_count = -1,
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
local function dirname(path)
    local normalized = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
    return normalized:match("^(.*)/[^/]+$") or ""
end
local function joinPath(root, name)
    return tostring(root or ""):gsub("[\\/]$", "") .. "/" .. tostring(name or "")
end
local function isAbsolutePath(path)
    local value = tostring(path or ""):gsub("\\", "/")
    return value:match("^%a:/") ~= nil or value:match("^//") ~= nil or value:match("^/") ~= nil
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

local function firstMediaMapping(profile)
    local mappings = profile.batch and profile.batch.media_mappings
    if type(mappings) == "table" and #mappings > 0 then
        local entry = mappings[1]
        local required = entry.working_media_required == true
        return {
            original_file = tostring(entry.original_file or ""),
            working_file = tostring(entry.working_file or ""),
            import_file = required and tostring(entry.working_file or "") or tostring(entry.original_file or ""),
            working_media_required = required,
            compatibility_reason = tostring(entry.compatibility_reason or ""),
            original_gamma = tostring(entry.original_gamma or ""),
            original_primaries = tostring(entry.original_primaries or ""),
            range_transform = tostring(entry.range_transform or ""),
            signal_equivalence_status = tostring(entry.signal_equivalence_status or ""),
            resolve_decode_status = tostring(entry.resolve_decode_status or ""),
            working_codec = tostring(entry.working_codec or ""),
            working_pixel_format = tostring(entry.working_pixel_format or ""),
            working_width = tonumber(entry.working_width),
            working_height = tonumber(entry.working_height),
            working_frame_rate = tonumber(entry.working_frame_rate),
            working_frames = tonumber(entry.working_frames),
            working_duration = tonumber(entry.working_duration),
            working_sha256 = tostring(entry.working_sha256 or ""),
            declared = true
        }
    end
    local firstName = tostring(profile.batch.source_files[1])
    local original = joinPath(profile.paths.input_dir, firstName)
    return {
        original_file = original,
        working_file = original,
        import_file = original,
        working_media_required = false,
        compatibility_reason = "NONE",
        original_gamma = tostring(profile.batch.gamma or ""),
        original_primaries = tostring(profile.batch.primaries or ""),
        range_transform = "NONE",
        signal_equivalence_status = "NOT_APPLICABLE",
        resolve_decode_status = "NOT_APPLICABLE",
        working_codec = "",
        working_pixel_format = "",
        working_width = tonumber(profile.batch.width),
        working_height = tonumber(profile.batch.height),
        working_frame_rate = tonumber(profile.batch.frame_rate),
        working_frames = nil,
        working_duration = nil,
        working_sha256 = "",
        declared = false
    }
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
    if profile.batch.media_mappings ~= nil then
        if type(profile.batch.media_mappings) ~= "table" or #profile.batch.media_mappings < 1 then
            fail("batch.media_mappings must be a non-empty array when declared.")
        end
        local mappingOriginals = {}
        for index, entry in ipairs(profile.batch.media_mappings) do
            if type(entry) ~= "table" then fail("media_mappings entry must be a table: " .. tostring(index)) end
            local original = tostring(entry.original_file or "")
            local working = tostring(entry.working_file or "")
            if not isAbsolutePath(original) then fail("media_mappings original_file must be an absolute path.") end
            if not seen[normalize(basename(original))] then fail("Mapped original_file is not in source_files: " .. original) end
            if index == 1 and normalize(basename(original)) ~= normalize(profile.batch.source_files[1]) then
                fail("The first media mapping must correspond to the first diagnostic source_file.")
            end
            if mappingOriginals[pathKey(original)] then fail("Duplicate original_file mapping: " .. original) end
            mappingOriginals[pathKey(original)] = true
            if normalize(entry.original_gamma) ~= normalize("S-Log3") then fail("Mapping original_gamma is not S-Log3.") end
            if normalize(entry.original_primaries) ~= normalize("Sony S-Gamut3.Cine") then
                fail("Mapping original_primaries is not Sony S-Gamut3.Cine.")
            end
            if entry.working_media_required == true then
                if not isAbsolutePath(working) then fail("Required working_file must be an absolute path.") end
                if pathKey(original) == pathKey(working) then fail("Original and working media paths must differ.") end
                if tostring(entry.compatibility_reason or "") == "" then fail("Required working media needs compatibility_reason.") end
                if tostring(entry.range_transform or "") ~= "FULL_TO_LIMITED_NORMALIZATION" then
                    fail("Required DNxHR working media must declare FULL_TO_LIMITED_NORMALIZATION.")
                end
                if tostring(entry.signal_equivalence_status or "") ~= "PASS" then
                    fail("SIGNAL_EQUIVALENCE_GATE: required working media has not passed signal equivalence.")
                end
            end
        end
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
    local firstMapping = firstMediaMapping(profile)
    state.original_source = firstMapping.original_file
    state.resolve_working_media = firstMapping.import_file
    state.working_media_required = firstMapping.working_media_required
    state.compatibility_reason = firstMapping.compatibility_reason
    state.range_transform = firstMapping.range_transform
    state.signal_equivalence_status = firstMapping.signal_equivalence_status
    state.original_metadata_policy = "FROM_VERIFIED_ORIGINAL_SOURCE_METADATA"
    state.working_media_mapping = firstMapping.working_media_required and "DECLARED" or "ORIGINAL_DIRECT"
    state.working_codec_declared = firstMapping.working_codec
    state.working_pixel_format_declared = firstMapping.working_pixel_format
    state.working_width_declared = tostring(firstMapping.working_width or "")
    state.working_height_declared = tostring(firstMapping.working_height or "")
    state.working_frame_rate_declared = tostring(firstMapping.working_frame_rate or "")
    state.working_frames_declared = tostring(firstMapping.working_frames or "")
    state.working_duration_declared = tostring(firstMapping.working_duration or "")
    state.working_sha256_declared = firstMapping.working_sha256
    logValue("preflight.original_source", state.original_source)
    logValue("preflight.resolve_working_media", state.resolve_working_media)
    logValue("preflight.working_media_required", state.working_media_required)
    logValue("preflight.compatibility_reason", state.compatibility_reason)
    logValue("preflight.range_transform", state.range_transform)
    logValue("preflight.signal_equivalence_status", state.signal_equivalence_status)
    logValue("preflight.original_metadata_policy", state.original_metadata_policy)
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

local function dumpRawClipProperties(label, properties)
    logLine(label .. " GET CLIP PROPERTY RAW BEGIN")
    logValue(label .. ".properties_type", type(properties))
    if type(properties) == "table" then
        local diagnosticCount = 0
        local iterateOk, iterateError = pcall(function()
            for key, value in pairs(properties) do
                diagnosticCount = diagnosticCount + 1
                local entry = label .. ".property[" .. tostring(diagnosticCount) .. "]"
                logValue(entry .. ".key_type", type(key))
                logValue(entry .. ".key", safeString(key))
                logValue(entry .. ".value_type", type(value))
                logValue(entry .. ".value", safeString(value))
                logValue(entry .. ".classification",
                    type(key) == "string" and key:sub(1, 2) == "__" and "BRIDGE_METADATA" or "PROPERTY_EVIDENCE")
            end
        end)
        logValue(label .. ".property_entry_count_diagnostic_only", diagnosticCount)
        logValue(label .. ".property_iterate_ok", iterateOk)
        if not iterateOk then logValue(label .. ".property_iterate_error", iterateError) end
    end
    logLine(label .. " GET CLIP PROPERTY RAW END")
end

local function readNamedClipProperty(item, propertyName, label)
    local callOk, value = pcall(function() return item:GetClipProperty(propertyName) end)
    logValue(label .. "." .. compact(propertyName) .. ".call_ok", callOk)
    logValue(label .. "." .. compact(propertyName) .. ".return_type", type(value))
    logValue(label .. "." .. compact(propertyName) .. ".value", callOk and value or "")
    return callOk and tostring(value or "") or ""
end

local function mediaStoragePathExists(resolveObject, path, label)
    local directory = dirname(path)
    logValue(label .. ".path", path)
    logValue(label .. ".directory", directory)
    if directory == "" then fail(label .. " has no parent directory.") end
    local storage = resolveObject:GetMediaStorage()
    if not storage then fail("GetMediaStorage returned nil during " .. label) end
    local callOk, files = pcall(function() return storage:GetFileList(directory) end)
    logValue(label .. ".get_file_list_call_ok", callOk)
    logValue(label .. ".get_file_list_return_type", type(files))
    if not callOk or type(files) ~= "table" then fail(label .. " MediaStorage:GetFileList failed.") end
    dumpRawCollection(string.upper(label) .. " FILE LIST", files)
    local exact = false
    for index, candidate in ipairs(files) do
        logValue(label .. ".candidate[" .. tostring(index) .. "]", candidate)
        if type(candidate) == "string" and pathKey(candidate) == pathKey(path) then exact = true end
    end
    logValue(label .. ".exact_path_exists", exact)
    if not exact then fail(label .. " exact declared path is not visible through Resolve MediaStorage.") end
    return true
end

local function propertyNumber(value)
    return tonumber(tostring(value or ""):match("[%d%.]+"))
end

local function resolutionMatches(value, width, height)
    local numbers = {}
    for number in tostring(value or ""):gmatch("%d+") do numbers[#numbers + 1] = tonumber(number) end
    return #numbers >= 2 and numbers[1] == tonumber(width) and numbers[2] == tonumber(height)
end

local function validateWorkingClipProperties(clip, mapping)
    setStage("Working Media Decode Properties")
    local label = "working_media"
    local actualPath = readNamedClipProperty(clip, "File Path", label)
    local resolution = readNamedClipProperty(clip, "Resolution", label)
    local fps = readNamedClipProperty(clip, "FPS", label)
    local videoCodec = readNamedClipProperty(clip, "Video Codec", label)
    local itemType = readNamedClipProperty(clip, "Type", label)
    state.working_resolution = resolution
    state.working_fps = fps
    state.working_video_codec = videoCodec
    logValue("working_media.item_type", itemType)
    if pathKey(actualPath) ~= pathKey(mapping.import_file) then fail("Working Media File Path does not match the declared mapping.") end
    if resolution ~= "" and not resolutionMatches(resolution, mapping.working_width or state.profile.batch.width,
            mapping.working_height or state.profile.batch.height) then
        fail("Working Media Resolution conflicts with the declared mapping.")
    end
    if fps ~= "" and not numberEquals(propertyNumber(fps), mapping.working_frame_rate or state.profile.batch.frame_rate) then
        fail("Working Media FPS conflicts with the declared mapping.")
    end
    if mapping.working_media_required and videoCodec ~= "" and not contains(videoCodec, "dnx") then
        fail("Working Media Video Codec is not DNxHR/DNxHD: " .. videoCodec)
    end
    if mapping.working_media_required and videoCodec == "" then
        append(state.warnings, "Working Media Video Codec property is unavailable; TimelineItem video validation remains the decisive decode gate.")
    end
    state.working_media_import = "PASS"
    logLine("WORKING MEDIA IMPORT=PASS")
end

local function classifyMediaPoolItems(rawItems, expectedPath, projectTimelineName, label)
    local items, validatedCount = validatedSequenceItems(rawItems, function(item)
        if type(item) ~= "userdata" then return false, "expected MediaPoolItem userdata" end
        local nameOk, itemName = pcall(function() return item:GetName() end)
        if not nameOk then return false, "MediaPoolItem:GetName failed: " .. tostring(itemName) end
        local propertiesOk, properties = pcall(function() return item:GetClipProperty() end)
        if not propertiesOk then return false, "MediaPoolItem:GetClipProperty failed: " .. tostring(properties) end
        if type(properties) ~= "table" then return false, "GetClipProperty did not return a property table" end
        return true
    end, label .. "_validated_items")

    local result = {
        validated_count = validatedCount,
        source_media = {},
        timeline_media_pool_items = {},
        other_media_pool_items = {},
        source_count = 0,
        timeline_item_count = 0,
        other_count = 0,
        exact_source = nil
    }
    for index, item in ipairs(items) do
        local itemLabel = label .. ".item[" .. tostring(index) .. "]"
        logLine(itemLabel .. " DIAGNOSTICS BEGIN")
        local nameOk, itemName = pcall(function() return item:GetName() end)
        logValue(itemLabel .. ".get_name_call_ok", nameOk)
        logValue(itemLabel .. ".name", itemName)
        if not nameOk then fail("Validated MediaPoolItem lost GetName capability.") end
        local propertiesOk, properties = pcall(function() return item:GetClipProperty() end)
        logValue(itemLabel .. ".get_clip_property_call_ok", propertiesOk)
        logValue(itemLabel .. ".get_clip_property_return_type", type(properties))
        if not propertiesOk or type(properties) ~= "table" then fail("Validated MediaPoolItem lost GetClipProperty capability.") end
        dumpRawClipProperties(itemLabel, properties)

        local filePath = readNamedClipProperty(item, "File Path", itemLabel)
        local itemType = readNamedClipProperty(item, "Type", itemLabel)
        local resolution = readNamedClipProperty(item, "Resolution", itemLabel)
        local fps = readNamedClipProperty(item, "FPS", itemLabel)
        readNamedClipProperty(item, "Video Codec", itemLabel)
        readNamedClipProperty(item, "Audio Codec", itemLabel)
        readNamedClipProperty(item, "Duration", itemLabel)
        local classification = "OTHER_MEDIA_POOL_ITEM"
        local detail = {
            item = item,
            name = tostring(itemName or ""),
            file_path = filePath,
            item_type = itemType,
            resolution = resolution,
            fps = fps
        }
        if filePath ~= "" then
            classification = "SOURCE_MEDIA"
            result.source_count = result.source_count + 1
            result.source_media[result.source_count] = detail
            if pathKey(filePath) == pathKey(expectedPath) then result.exact_source = detail end
        elseif tostring(projectTimelineName or "") ~= "" and tostring(itemName or "") == tostring(projectTimelineName) then
            classification = "TIMELINE_MEDIA_POOL_ITEM"
            result.timeline_item_count = result.timeline_item_count + 1
            result.timeline_media_pool_items[result.timeline_item_count] = detail
        else
            result.other_count = result.other_count + 1
            result.other_media_pool_items[result.other_count] = detail
        end
        logValue(itemLabel .. ".normalized_file_path", pathKey(filePath))
        logValue(itemLabel .. ".expected_source_path_match", filePath ~= "" and pathKey(filePath) == pathKey(expectedPath))
        logValue(itemLabel .. ".project_timeline_name_match",
            filePath == "" and tostring(projectTimelineName or "") ~= "" and tostring(itemName or "") == tostring(projectTimelineName))
        logValue(itemLabel .. ".classification", classification)
        logLine(itemLabel .. " DIAGNOSTICS END")
    end
    logValue(label .. ".validated_userdata_count", result.validated_count)
    logValue(label .. ".source_media_count", result.source_count)
    logValue(label .. ".timeline_media_pool_item_count", result.timeline_item_count)
    logValue(label .. ".other_media_pool_item_count", result.other_count)
    return result
end

local function projectTimelineState(project, expectedName, label)
    local count = tonumber(project:GetTimelineCount()) or -1
    logValue(label .. ".timeline_count", count)
    if count < 0 or count > 1 then fail("Project must contain zero or one diagnostic timeline.") end
    if count == 0 then return 0, nil, "" end
    local timeline = project:GetTimelineByIndex(1)
    local nameOk, timelineName = pcall(function() return timeline and timeline:GetName() end)
    logValue(label .. ".timeline_name_call_ok", nameOk)
    logValue(label .. ".timeline_name", timelineName)
    logValue(label .. ".expected_timeline_name", expectedName)
    if not nameOk or not timeline or tostring(timelineName) ~= tostring(expectedName) then
        fail("Existing timeline name does not match the expected diagnostic timeline.")
    end
    return 1, timeline, tostring(timelineName)
end

local function validateMediaPoolClassification(classified, expectedTimelineCount, requireSource, label)
    state.media_pool_source_count = classified.source_count
    state.media_pool_timeline_item_count = classified.timeline_item_count
    state.media_pool_other_count = classified.other_count
    if classified.source_count > 1 then fail("Media Pool contains a second file-backed source.") end
    if requireSource and classified.source_count ~= 1 then fail("Media Pool must contain exactly one file-backed source.") end
    if classified.source_count == 1 and not classified.exact_source then fail("The sole file-backed source is not the declared diagnostic source.") end
    if classified.timeline_item_count ~= expectedTimelineCount then
        fail("Timeline MediaPoolItem count does not match Project Timeline count.")
    end
    if classified.other_count ~= 0 then fail("Media Pool contains an unexpected non-file-backed object.") end
    logLine(label .. "=VALID")
    return classified.exact_source and classified.exact_source.item or nil
end

local function validateTimelineItems(timeline, expectedPath, label, workingMediaRequired)
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
    if workingMediaRequired then
        state.working_media_video_decode = "PASS"
        logLine("WORKING_MEDIA_VIDEO_DECODE=PASS")
        logLine("TIMELINE=ONE_EXACT_WORKING_SOURCE")
    else
        logLine("TIMELINE=ONE_EXACT_SOURCE")
    end
    return items[1]
end

local function rootObjects(project)
    local mediaPool = project:GetMediaPool()
    if not mediaPool then fail("GetMediaPool returned nil.") end
    local root = mediaPool:GetRootFolder()
    if not root then fail("GetRootFolder returned nil.") end
    return mediaPool, root, root:GetClipList() or {}
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
    dumpRawCollection("RESUME CLIP LIST", clips)
    dumpRawCollection("RESUME SUBFOLDER LIST", folders)
    dumpRawCollection("RESUME RENDER JOB LIST", renderJobs)
    local folderCount = validatedSequenceCount(folders, function(item)
        if type(item) ~= "userdata" then return false, "expected Folder userdata" end
        return true
    end, "resume_subfolder_list")
    local renderJobCount = validatedSequenceCount(renderJobs, function(item)
        if type(item) ~= "table" then return false, "expected render job information table" end
        if tostring(item.JobId or "") == "" then return false, "missing JobId" end
        return true
    end, "resume_render_job_list")
    local mapping = firstMediaMapping(profile)
    local firstName = basename(mapping.original_file)
    local expectedPath = mapping.import_file
    local timelineCount, existingTimeline, timelineName = projectTimelineState(
        project, profile.diagnostic.timeline_name, "resume_project_timeline")
    local classified = classifyMediaPoolItems(clips, expectedPath, timelineName, "resume_media_pool")
    local exactClip = validateMediaPoolClassification(classified, timelineCount, true, "RESUME MEDIA POOL")
    logValue("resume.root_media_pool_userdata_count", classified.validated_count)
    logValue("resume.source_media_count", classified.source_count)
    logValue("resume.timeline_media_pool_item_count", classified.timeline_item_count)
    logValue("resume.other_media_pool_item_count", classified.other_count)
    logValue("resume.root_folder_count", folderCount)
    logValue("resume.timeline_count", timelineCount)
    logValue("resume.render_job_count", renderJobCount)
    logValue("resume.exact_first_source", exactClip ~= nil)
    if folderCount ~= 0 then fail("Resume target contains unexpected Media Pool folders.") end
    if renderJobCount ~= 0 then fail("Resume target contains render jobs.") end
    state.imported_file = firstName
    if timelineCount == 1 then
        validateTimelineItems(existingTimeline, expectedPath, "resume_timeline_item_list", mapping.working_media_required)
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

local function ensureOneClip(resolveObject, project, profile)
    setStage("Media Pool")
    local mediaPool, root, clips = rootObjects(project)
    local folders = root:GetSubFolderList() or {}
    dumpRawCollection("MEDIA POOL CLIP LIST", clips)
    dumpRawCollection("MEDIA POOL SUBFOLDER LIST", folders)
    local folderCount = validatedSequenceCount(folders, function(item)
        if type(item) ~= "userdata" then return false, "expected Folder userdata" end
        return true
    end, "media_pool_subfolder_list")
    local mapping = firstMediaMapping(profile)
    local firstName = basename(mapping.original_file)
    local fullPath = mapping.import_file
    setStage("Original and Working Media Mapping")
    mediaStoragePathExists(resolveObject, mapping.original_file, "original_source_media")
    if mapping.working_media_required then mediaStoragePathExists(resolveObject, mapping.working_file, "resolve_working_media") end
    logValue("mapping.original_source", mapping.original_file)
    logValue("mapping.resolve_working_media", mapping.import_file)
    logValue("mapping.original_gamma", mapping.original_gamma)
    logValue("mapping.original_primaries", mapping.original_primaries)
    logValue("mapping.compatibility_reason", mapping.compatibility_reason)
    logValue("mapping.range_transform", mapping.range_transform)
    logValue("mapping.signal_equivalence_status", mapping.signal_equivalence_status)
    logValue("mapping.resolve_data_levels_policy", "CODEC_NATIVE_VIDEO_LEVELS")
    state.working_media_mapping = mapping.working_media_required and "VERIFIED" or "ORIGINAL_DIRECT"
    logLine("WORKING MEDIA MAPPING=VERIFIED")
    setStage("Media Pool")
    local timelineCount, _, timelineName = projectTimelineState(project, profile.diagnostic.timeline_name, "media_pool_project_timeline")
    local before = classifyMediaPoolItems(clips, fullPath, timelineName, "media_pool_before")
    local clip = validateMediaPoolClassification(before, timelineCount, false, "MEDIA POOL PRE-IMPORT")
    if folderCount > 0 then fail("Target project contains unexpected Media Pool folders.") end
    if not clip then
        if timelineCount ~= 0 then fail("Existing diagnostic timeline has no exact file-backed source; import is forbidden.") end
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
    local afterClassification = classifyMediaPoolItems(after, fullPath, timelineName, "media_pool_after")
    clip = validateMediaPoolClassification(afterClassification, timelineCount, true, "MEDIA POOL")
    state.imported_file = firstName
    validateWorkingClipProperties(clip, mapping)
    logLine("Media Import=SUCCESS")
    logLine("Media Pool=ONE_EXACT_SOURCE")
    return mediaPool, clip, fullPath, mapping
end

local function evaluateInputPolicy(project, clip, profile, mapping)
    setStage("Input Color Space Policy")
    local metadataVerified = tostring(profile.batch.metadata_confirmation or "") ~= ""
        and normalize(mapping.original_gamma) == normalize("S-Log3")
        and normalize(mapping.original_primaries) == normalize("Sony S-Gamut3.Cine")
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
    logValue("input_policy.original_source", mapping.original_file)
    logValue("input_policy.resolve_working_media", mapping.import_file)
    logValue("input_policy.original_metadata_policy", state.original_metadata_policy)
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
    state.input_confidence = mapping.working_media_required
        and "HIGH — verified original metadata plus verified project input applied to compatibility working media"
        or "HIGH — homogeneous metadata plus verified project input"
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

local function ensureTimeline(project, mediaPool, clip, sourcePath, profile, mapping)
    setStage("Timeline")
    local name = profile.diagnostic.timeline_name
    local timeline = findTimeline(project, name)
    if project:GetTimelineCount() > 0 and not (project:GetTimelineCount() == 1 and timeline) then
        fail("Target project contains unexpected timeline content.")
    end
    local reused = timeline ~= nil
    if not timeline then timeline = mediaPool:CreateTimelineFromClips(name, {clip}) end
    if not timeline then fail("CreateTimelineFromClips returned nil.") end
    validateTimelineItems(timeline, sourcePath, "timeline_item_list", mapping.working_media_required)
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
        "- Original Source: `" .. state.original_source .. "`",
        "- Resolve Working Media: `" .. state.resolve_working_media .. "`",
        "- Working Media Required: `" .. tostring(state.working_media_required) .. "`",
        "- Working Media Mapping: `" .. state.working_media_mapping .. "`",
        "- Compatibility Reason: `" .. state.compatibility_reason .. "`",
        "- Range Transform: `" .. state.range_transform .. "`",
        "- Signal Equivalence: `" .. state.signal_equivalence_status .. "`",
        "- Working Media Import: `" .. state.working_media_import .. "`",
        "- Working Media Video Decode: `" .. state.working_media_video_decode .. "`",
        "- Declared Working Codec: `" .. state.working_codec_declared .. "`",
        "- Declared Working Pixel Format: `" .. state.working_pixel_format_declared .. "`",
        "- Declared Working Geometry: `" .. state.working_width_declared .. "x" .. state.working_height_declared .. "`",
        "- Declared Working FPS: `" .. state.working_frame_rate_declared .. "`",
        "- Declared Working Frames: `" .. state.working_frames_declared .. "`",
        "- Declared Working Duration: `" .. state.working_duration_declared .. "`",
        "- Declared Working SHA-256: `" .. state.working_sha256_declared .. "`",
        "- Resolve Working Resolution: `" .. state.working_resolution .. "`",
        "- Resolve Working FPS: `" .. state.working_fps .. "`",
        "- Resolve Working Video Codec: `" .. state.working_video_codec .. "`",
        "- Timeline: `" .. state.timeline .. "`",
        "- DRP staging: `" .. state.drp_path .. "`", "",
        "## Media Pool classification", "",
        "- Source media count: `" .. tostring(state.media_pool_source_count) .. "`",
        "- Timeline MediaPoolItem count: `" .. tostring(state.media_pool_timeline_item_count) .. "`",
        "- Other MediaPoolItem count: `" .. tostring(state.media_pool_other_count) .. "`", "",
        "## Input policy", "",
        "- Original Metadata Policy: `" .. state.original_metadata_policy .. "`",
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
    local mediaPool, clip, sourcePath, mapping = ensureOneClip(resolveObject, project, profile)
    evaluateInputPolicy(project, clip, profile, mapping)
    ensureTimeline(project, mediaPool, clip, sourcePath, profile, mapping)

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
    if mapping.working_media_required then
        if state.working_media_mapping ~= "VERIFIED" or state.working_media_import ~= "PASS"
            or state.working_media_video_decode ~= "PASS" then
            fail("Compatibility working-media success gates are incomplete.")
        end
        state.status = "SUCCESS_DNXHR_COMPATIBILITY_READY"
    else
        state.status = "SUCCESS_DIAGNOSTIC_READY"
    end
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
