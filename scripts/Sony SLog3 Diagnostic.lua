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
    project_name = "UNKNOWN",
    profile = {},
    settings = {},
    imported_file = "",
    timeline = "",
    drp_path = "",
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

local function tracebackHandler(errorValue)
    local message = tostring(errorValue)
    if debug and type(debug.traceback) == "function" then return debug.traceback(message, 2) end
    return message
end

local function fail(message)
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
    if tostring(profile.project.preset_name or "") == "" then fail("A verified project.preset_name is required for the Project Format baseline.") end
    if type(profile.paths) ~= "table" then fail("Missing paths table.") end
    if type(profile.batch) ~= "table" then fail("Missing batch table.") end
    if type(profile.batch.source_files) ~= "table" or #profile.batch.source_files < 1 then fail("No source_files declared.") end
    if tonumber(profile.batch.width) == nil or tonumber(profile.batch.width) < 1 then fail("Invalid batch.width.") end
    if tonumber(profile.batch.height) == nil or tonumber(profile.batch.height) < 1 then fail("Invalid batch.height.") end
    if tonumber(profile.batch.frame_rate) == nil or tonumber(profile.batch.frame_rate) <= 0 then fail("Invalid batch.frame_rate.") end
    if normalize(profile.batch.gamma) ~= normalize("S-Log3") then fail("Batch gamma is not reliably confirmed as S-Log3.") end
    if normalize(profile.batch.primaries) ~= normalize("Sony S-Gamut3.Cine") then fail("Batch primaries are not reliably confirmed as Sony S-Gamut3.Cine.") end
    if tostring(profile.batch.metadata_confirmation or "") == "" then fail("metadata_confirmation is required.") end
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

local function projectExists(manager, name)
    for _, projectName in ipairs(manager:GetProjectListInCurrentFolder() or {}) do
        if projectName == name then return true end
    end
    return false
end

local function acquireProject(resolveObject, profile)
    setStage("ProjectManager")
    local manager = resolveObject:GetProjectManager()
    if not manager then fail("GetProjectManager returned nil.") end
    logLine("ProjectManager=SUCCESS")
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

local function ensureOneClip(project, profile)
    setStage("Media Pool")
    local mediaPool, root, clips = rootObjects(project)
    local firstName = profile.batch.source_files[1]
    local fullPath = tostring(profile.paths.input_dir):gsub("[\\/]$", "") .. "/" .. firstName
    local clip = findExactClip(clips, fullPath)
    if #clips > 0 and not (#clips == 1 and clip) then fail("Target project contains unexpected Media Pool content.") end
    if #(root:GetSubFolderList() or {}) > 0 then fail("Target project contains unexpected Media Pool folders.") end
    if not clip then
        setStage("Media Import")
        logValue("media_import.path", fullPath)
        local ok, imported = pcall(function() return mediaPool:ImportMedia({fullPath}) end)
        logValue("media_import.call_ok", ok)
        logValue("media_import.return_type", type(imported))
        if not ok then fail("ImportMedia raised an error: " .. tostring(imported)) end
        if type(imported) ~= "table" then fail("ImportMedia did not return a table.") end
        clip = imported[1]
        if not clip then for _, value in pairs(imported) do clip = value; break end end
        if not clip then fail("ImportMedia returned no MediaPoolItem.") end
    else
        append(state.warnings, "The exact diagnostic source was already present and was reused.")
    end
    local _, _, after = rootObjects(project)
    if #after ~= 1 or not findExactClip(after, fullPath) then fail("Media Pool post-import verification failed.") end
    state.imported_file = firstName
    logLine("Media Import=SUCCESS")
    logLine("Media Pool=ONE_EXACT_SOURCE")
    return mediaPool, clip, fullPath
end

local function setClipInput(project, clip)
    setStage("Input Color Space")
    local key = "Input Color Space"
    for propertyKey, _ in pairs(clip:GetClipProperty() or {}) do
        if contains(propertyKey, "input") and contains(propertyKey, "color") and contains(propertyKey, "space") then key = propertyKey break end
    end
    local labels = {"S-Gamut3.Cine/S-Log3", "Sony S-Gamut3.Cine/S-Log3", "Sony S-Gamut3.Cine / S-Log3"}
    for _, label in ipairs(labels) do
        clip:SetClipProperty(key, label)
        local actual = clip:GetClipProperty(key)
        logValue("clip_input.read_back", actual)
        if contains(actual, "s-gamut3.cine") and contains(actual, "s-log3") then return end
    end
    local actual = clip:GetClipProperty(key)
    local inherited = normalize(actual) == "project" or tostring(actual) == "项目"
    if inherited and contains(project:GetSetting("colorSpaceInput"), "s-gamut3.cine")
        and contains(project:GetSetting("colorSpaceInputGamma"), "s-log3") then return end
    fail("Effective Input Color Space could not be verified.")
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
    if not timeline then timeline = mediaPool:CreateTimelineFromClips(name, {clip}) end
    if not timeline then fail("CreateTimelineFromClips returned nil.") end
    local items = timeline:GetItemListInTrack("video", 1) or {}
    if #items ~= 1 then fail("Diagnostic timeline must contain exactly one video item.") end
    local poolItem = items[1]:GetMediaPoolItem()
    if not poolItem or pathKey(clipPath(poolItem)) ~= pathKey(sourcePath) then fail("Timeline source verification failed.") end
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
    project:SetCurrentTimeline(timeline)
    state.timeline = name
    logLine("Timeline=SUCCESS")
end

local function fileExists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
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
        "- Project: `" .. state.project_name .. "`",
        "- Imported first source: `" .. state.imported_file .. "`",
        "- Timeline: `" .. state.timeline .. "`",
        "- DRP staging: `" .. state.drp_path .. "`", "",
        "## Settings read back", ""
    }
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
    local manager, project = acquireProject(resolveObject, profile)
    recordInitialSettings(project)
    applyProjectPresetBaseline(project, profile)
    configureColorManagement(project)
    verifyFinalSettings(project, profile)
    local mediaPool, clip, sourcePath = ensureOneClip(project, profile)
    setClipInput(project, clip)
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
    state.status = "SUCCESS_ONE_CLIP_DIAGNOSTIC"
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
