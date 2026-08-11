-- Sony SLog3 Render Preset Capture.lua
-- Captures one human-verified Deliver preset. Does not render or alter grades.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ASCII_DIR = TEMP_ROOT .. "/SonySLog3AutoGrade"
local PROFILE_PATH = ASCII_DIR .. "/runtime.lua"
local LOG_PATH = ASCII_DIR .. "/render_preset_capture.log"
local REPORT_PATH = ASCII_DIR .. "/render_preset_capture_report.md"
local EMERGENCY_PATH = TEMP_ROOT .. "/SonySLog3AutoGrade_render_preset_capture_emergency.log"

local state = {
    status = "STARTING",
    stage = "bootstrap",
    project = "",
    preset_name = "",
    export_path = "",
    export_size = 0,
    sha256 = "",
    errors = {}
}

local function appendRaw(path, text)
    local handle = io.open(path, "ab")
    if not handle then return false end
    handle:write(text); handle:close(); return true
end
local function ensureDirectory(path)
    local quoted = '"' .. tostring(path):gsub("/", "\\"):gsub('"', '""') .. '"'
    os.execute("cmd.exe /d /c if not exist " .. quoted .. " mkdir " .. quoted .. " >NUL 2>&1")
end
ensureDirectory(ASCII_DIR)
local function logLine(value)
    if not appendRaw(LOG_PATH, tostring(value or "") .. "\n") then
        appendRaw(EMERGENCY_PATH, tostring(value or "") .. "\n")
    end
end
local function logValue(key, value) logLine(key .. "=" .. tostring(value)) end
local function stage(name) state.stage = name; logLine("STAGE=" .. name) end
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

local function dumpRawCollection(label, value)
    logLine(label .. " RAW BEGIN")
    logValue(label .. ".return_type", type(value))
    if type(value) == "table" then
        local count = 0
        for key, item in pairs(value) do
            count = count + 1
            local prefix = label .. ".entry[" .. count .. "]"
            local classification = "DICTIONARY_ENTRY"
            if type(key) == "string" and key:sub(1, 2) == "__" then classification = "BRIDGE_METADATA"
            elseif type(key) == "number" then classification = "SEQUENCE_ENTRY" end
            logValue(prefix .. ".key_type", type(key))
            logValue(prefix .. ".key", key)
            logValue(prefix .. ".value_type", type(item))
            logValue(prefix .. ".value", item)
            logValue(prefix .. ".classification", classification)
            if type(item) == "table" then
                local nestedCount = 0
                for nestedKey, nestedValue in pairs(item) do
                    nestedCount = nestedCount + 1
                    logValue(prefix .. ".nested[" .. nestedCount .. "].key", nestedKey)
                    logValue(prefix .. ".nested[" .. nestedCount .. "].key_type", type(nestedKey))
                    logValue(prefix .. ".nested[" .. nestedCount .. "].value", nestedValue)
                    logValue(prefix .. ".nested[" .. nestedCount .. "].value_type", type(nestedValue))
                end
                logValue(prefix .. ".nested_count", nestedCount)
            end
        end
        logValue(label .. ".top_level_entry_count_diagnostic_only", count)
    end
    logLine(label .. " RAW END")
end

local function exactScalarLocations(value, target)
    local locations = {}
    if type(value) ~= "table" then return locations end
    for key, item in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 2) ~= "__" then
            if type(key) == "string" and key == target then locations[#locations + 1] = "key:" .. key end
            if type(item) == "string" and item == target then locations[#locations + 1] = "value:" .. tostring(key) end
            if type(item) == "table" then
                for nestedKey, nestedValue in pairs(item) do
                    if type(nestedValue) == "string" and nestedValue == target then
                        locations[#locations + 1] = "nested:" .. tostring(key) .. "." .. tostring(nestedKey)
                    end
                end
            end
        end
    end
    return locations
end

local function fileSize(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local size = handle:seek("end")
    handle:close()
    return size
end

local function powershellLiteral(value)
    return "'" .. tostring(value):gsub("'", "''") .. "'"
end

local function calculateSha256(path, hashPath)
    os.remove(hashPath)
    local command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
        .. '"$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '
        .. powershellLiteral(path) .. ').Hash;[IO.File]::WriteAllText('
        .. powershellLiteral(hashPath) .. ',$h,[Text.Encoding]::ASCII)"'
    local resultA, resultB, resultC = os.execute(command)
    logValue("sha256.os_execute.return1", resultA)
    logValue("sha256.os_execute.return2", resultB)
    logValue("sha256.os_execute.return3", resultC)
    local handle = io.open(hashPath, "rb")
    if not handle then fail("External SHA-256 calculation did not create its result file.") end
    local hash = tostring(handle:read("*a") or ""):gsub("%s+", "")
    handle:close()
    if #hash ~= 64 or not hash:match("^[0-9A-Fa-f]+$") then fail("Invalid exported preset SHA-256.") end
    return string.upper(hash)
end

logLine("")
logLine("============================================================")
logLine("RENDER PRESET CAPTURE START")
logValue("timestamp", os.date("%Y-%m-%d %H:%M:%S %z"))

local function main()
    stage("Runtime Profile")
    local loader, loadError = loadfile(PROFILE_PATH)
    if not loader then fail("Cannot load runtime: " .. tostring(loadError)) end
    local ok, profile = pcall(loader)
    if not ok or type(profile) ~= "table" then fail("Runtime did not return a table.") end
    if type(profile.deployment) ~= "table" or not isSha256(profile.deployment.render_preset_capture_sha256) then
        fail("Missing Render Preset Capture deployment SHA-256.")
    end
    logValue("render_preset_capture_sha256", profile.deployment.render_preset_capture_sha256)
    local preset = profile.render_preset
    if type(preset) ~= "table" or tostring(preset.name or "") == "" then fail("Missing render_preset runtime block.") end
    if tostring(preset.capture_status or "") ~= "PENDING_HUMAN_VERIFIED_CAPTURE" then
        fail("Preset capture is not in PENDING_HUMAN_VERIFIED_CAPTURE state.")
    end
    state.preset_name = tostring(preset.name)
    state.export_path = tostring(preset.export_path)
    local hashPath = tostring(preset.hash_result_path)
    if state.export_path == "" or hashPath == "" then fail("Missing ASCII export/hash path.") end
    if fileSize(state.export_path) ~= nil then fail("Preset export target already exists; overwrite forbidden.") end
    ensureDirectory(state.export_path:match("^(.*)/[^/]+$") or ASCII_DIR)

    stage("Resolve Objects")
    local appObject = rawget(_G, "app")
    if not appObject then fail("Internal app object is unavailable.") end
    local resolveObject = appObject:GetResolve()
    if not resolveObject then fail("app:GetResolve() returned nil.") end
    local manager = resolveObject:GetProjectManager()
    local project = manager and manager:GetCurrentProject() or nil
    if not project then fail("No current project.") end
    state.project = tostring(project:GetName())
    if state.project ~= tostring(profile.color_test.project_name) then fail("Current project is not the verified reference project.") end
    local currentPage = tostring(resolveObject:GetCurrentPage() or "")
    logValue("current_page", currentPage)
    if currentPage ~= "deliver" then fail("Render Preset Capture must be launched from the Deliver page.") end
    local jobs = project:GetRenderJobList() or {}
    dumpRawCollection("RENDER JOB LIST", jobs)
    local jobCount = 0
    for _, job in ipairs(jobs) do
        if type(job) == "table" and tostring(job.JobId or "") ~= "" then jobCount = jobCount + 1 end
    end
    logValue("render_job_count", jobCount)
    if jobCount ~= 0 then fail("Render Queue must be empty during preset capture.") end

    stage("Deliver Settings Identity")
    local current = project:GetCurrentRenderFormatAndCodec()
    dumpRawCollection("CURRENT RENDER FORMAT AND CODEC", current)
    if type(current) ~= "table" or tostring(current.format or "") ~= tostring(preset.expected_format_id)
        or tostring(current.codec or "") ~= tostring(preset.expected_codec_id) then
        fail("Current Deliver format/codec is not the expected verified DNxHR HQX target.")
    end
    local renderMode = tonumber(project:GetCurrentRenderMode())
    logValue("current_render_mode", renderMode)
    if renderMode ~= 1 then fail("Current Deliver mode must be Single Clip (1).") end

    stage("Preset Preflight")
    local before = project:GetRenderPresetList()
    dumpRawCollection("RENDER PRESET LIST BEFORE", before)
    local beforeMatches = exactScalarLocations(before, state.preset_name)
    logValue("preset_exact_matches_before", #beforeMatches)
    if #beforeMatches > 0 then fail("Target render preset already exists; overwrite forbidden.") end

    stage("Save Render Preset")
    local saved = project:SaveAsNewRenderPreset(state.preset_name)
    logValue("SaveAsNewRenderPreset.return", saved)
    if saved ~= true then fail("SaveAsNewRenderPreset returned false.") end
    local after = project:GetRenderPresetList()
    dumpRawCollection("RENDER PRESET LIST AFTER", after)
    local afterMatches = exactScalarLocations(after, state.preset_name)
    logValue("preset_exact_matches_after", #afterMatches)
    if #afterMatches == 0 then fail("Saved preset is not EXACT VISIBLE in GetRenderPresetList.") end
    logLine("RENDER PRESET=EXACT VISIBLE")

    stage("Export Render Preset")
    local exported = resolveObject:ExportRenderPreset(state.preset_name, state.export_path)
    logValue("ExportRenderPreset.return", exported)
    if exported ~= true then fail("ExportRenderPreset returned false.") end
    state.export_size = tonumber(fileSize(state.export_path)) or 0
    logValue("preset_export_size", state.export_size)
    if state.export_size <= 0 then fail("Exported render preset is missing or empty.") end
    state.sha256 = calculateSha256(state.export_path, hashPath)
    logValue("preset_export_sha256", state.sha256)
    if manager:SaveProject() ~= true then fail("SaveProject failed after preset capture.") end
    state.status = "RENDER_PRESET_CAPTURE_SUCCESS"
    logLine("RENDER_PRESET_CAPTURE=SUCCESS")
end

local ok, tracebackText = xpcall(main, tracebackHandler)
if not ok then
    state.status = "ERROR_STOPPED"
    logLine("ERROR")
    logValue("error.stage", state.stage)
    logValue("error.traceback", tracebackText)
end
local report = {
    "# Sony S-Log3 Render Preset Capture report", "",
    "- Status: `" .. state.status .. "`",
    "- Last stage: `" .. state.stage .. "`",
    "- Project: `" .. state.project .. "`",
    "- Preset: `" .. state.preset_name .. "`",
    "- Export path: `" .. state.export_path .. "`",
    "- Export size: `" .. tostring(state.export_size) .. "`",
    "- SHA-256: `" .. state.sha256 .. "`", "", "## Errors", ""
}
if #state.errors == 0 then report[#report + 1] = "- None" end
for _, message in ipairs(state.errors) do report[#report + 1] = "- " .. message:gsub("[\r\n]", " ") end
if not ok then
    report[#report + 1] = ""; report[#report + 1] = "## Traceback"; report[#report + 1] = ""
    report[#report + 1] = "```"; report[#report + 1] = tracebackText; report[#report + 1] = "```"
end
local handle = io.open(REPORT_PATH, "wb")
if handle then handle:write(table.concat(report, "\n")); handle:close() end
logLine("STOP")
logValue("final.status", state.status)
