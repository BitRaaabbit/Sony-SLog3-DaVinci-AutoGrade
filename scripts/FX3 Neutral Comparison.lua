-- FX3 Neutral Comparison.lua
-- Internal DaVinci Resolve 20.3.2 script. Run only from Workspace > Scripts.

local PROJECT_NAME = "FX3_SLog3_AutoGrade_Test"
local PROJECT_ROOT = os.getenv("FX3_AUTOGRADE_ROOT") or [[C:/FX3-SLog3-DaVinci-AutoGrade]]
local OUTPUT_DIR = PROJECT_ROOT .. "/ship_output/comparison"
local REPORT_PATH = PROJECT_ROOT .. "/logs/autograde_comparison_report.md"

local TEST_FILES = {
    "FX3_TEST_001.MP4",
    "FX3_TEST_002.MP4",
    "FX3_TEST_003.MP4"
}

local VARIANTS = {
    {
        code = "V2A",
        label = "Standard Neutral V2A",
        contrast = "1.08",
        pivot = "0.44",
        color_boost = "+8",
        saturation = "52",
        highlights = "-5"
    },
    {
        code = "V2B",
        label = "Standard Neutral V2B",
        contrast = "1.12",
        pivot = "0.44",
        color_boost = "+12",
        saturation = "54",
        highlights = "-8"
    }
}

local state = {
    phase = "STARTING",
    warnings = {},
    failures = {},
    timelines = {},
    render_jobs = {},
    outputs = {}
}

local function append(list, value)
    list[#list + 1] = value
end

local function normalize(value)
    return string.lower((tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function contains(value, needle)
    return string.find(normalize(value), normalize(needle), 1, true) ~= nil
end

local function basename(path)
    return tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or ""
end

local function stem(fileName)
    return tostring(fileName):gsub("%.[^%.]+$", "")
end

local function valueEqualsNumber(actual, expected)
    local number = tonumber(actual)
    return number and math.abs(number - expected) < 0.0005
end

local function fail(message)
    append(state.failures, tostring(message))
    error(message)
end

local function scalar(value)
    local kind = type(value)
    return kind == "string" or kind == "number" or kind == "boolean"
end

local function writeReport()
    local handle, openError = io.open(REPORT_PATH, "w")
    if not handle then
        print("Could not write comparison report: " .. tostring(openError))
        return false
    end
    handle:write("# FX3 Neutral V2A / V2B comparison report\n\n")
    handle:write("- Phase: **" .. tostring(state.phase) .. "**\n")
    handle:write("- Project: `" .. PROJECT_NAME .. "`\n")
    handle:write("- Output: `" .. OUTPUT_DIR .. "`\n\n")
    handle:write("## Required native Primary settings\n\n")
    for _, variant in ipairs(VARIANTS) do
        handle:write("- " .. variant.label .. ": Contrast=" .. variant.contrast
            .. ", Pivot=" .. variant.pivot
            .. ", Color Boost=" .. variant.color_boost
            .. ", Saturation=" .. variant.saturation
            .. ", Highlights=" .. variant.highlights .. "\n")
    end
    handle:write("\nThese values must be entered and read back in the native Color page on a newly added serial corrector node.\n\n")
    handle:write("## Comparison timelines\n\n")
    for _, line in ipairs(state.timelines) do handle:write("- `" .. line .. "`\n") end
    handle:write("\n## Render jobs\n\n")
    for _, line in ipairs(state.render_jobs) do handle:write("- `" .. line .. "`\n") end
    handle:write("\n## Intended/final outputs\n\n")
    for _, line in ipairs(state.outputs) do handle:write("- `" .. line .. "`\n") end
    handle:write("\n## Warnings\n\n")
    if #state.warnings == 0 then handle:write("- None\n") end
    for _, line in ipairs(state.warnings) do handle:write("- " .. line .. "\n") end
    handle:write("\n## Failures\n\n")
    if #state.failures == 0 then handle:write("- None\n") end
    for _, line in ipairs(state.failures) do handle:write("- " .. line .. "\n") end
    handle:write("\nThe remaining 36 clips are out of scope and must not be processed.\n")
    handle:close()
    return true
end

local function getResolveObject()
    if app and app.GetResolve then return app:GetResolve() end
    if fusion and fusion.GetResolve then return fusion:GetResolve() end
    return nil
end

local function verifyProjectSettings(project)
    local requiredText = {
        {"colorScienceMode", "davinciYRGBColorManagedv2"},
        {"rcmPresetMode", "Custom"},
        {"isAutoColorManage", "0"},
        {"separateColorSpaceAndGamma", "1"},
        {"colorSpaceInput", "Sony S-Gamut3.Cine"},
        {"colorSpaceInputGamma", "S-Log3"},
        {"colorSpaceTimeline", "DaVinci WG"},
        {"colorSpaceTimelineGamma", "DaVinci Intermediate"},
        {"colorSpaceOutput", "Rec.709"},
        {"colorSpaceOutputGamma", "Gamma 2.4"},
        {"timelineResolutionWidth", "3840"},
        {"timelineResolutionHeight", "2160"}
    }
    for _, entry in ipairs(requiredText) do
        local actual = tostring(project:GetSetting(entry[1]) or "")
        if normalize(actual) ~= normalize(entry[2]) then
            fail("Project setting changed: " .. entry[1] .. " expected='" .. entry[2] .. "' actual='" .. actual .. "'.")
        end
    end
    if not valueEqualsNumber(project:GetSetting("timelineFrameRate"), 59.94) then
        fail("Project timeline frame rate is not 59.94.")
    end
    if not valueEqualsNumber(project:GetSetting("timelinePlaybackFrameRate"), 59.94) then
        fail("Project playback frame rate is not 59.94.")
    end
end

local function clipFilePath(item)
    local properties = item and item:GetClipProperty() or {}
    return properties["File Path"] or properties["FilePath"] or properties["Path"] or ""
end

local function collectClips(folder, result)
    for _, clip in ipairs(folder:GetClipList() or {}) do append(result, clip) end
    for _, child in ipairs(folder:GetSubFolderList() or {}) do collectClips(child, result) end
end

local function sourceClipMap(project)
    local result = {}
    local clips = {}
    collectClips(project:GetMediaPool():GetRootFolder(), clips)
    for _, clip in ipairs(clips) do
        local name = basename(clipFilePath(clip))
        for _, expected in ipairs(TEST_FILES) do
            if normalize(name) == normalize(expected) then result[expected] = clip end
        end
    end
    for _, expected in ipairs(TEST_FILES) do
        if not result[expected] then fail("Expected source clip is missing from the isolated test project: " .. expected) end
    end
    return result
end

local function findTimeline(project, name)
    for index = 1, project:GetTimelineCount() do
        local timeline = project:GetTimelineByIndex(index)
        if timeline and timeline:GetName() == name then return timeline end
    end
    return nil
end

local function timelineName(fileName, variantCode)
    return "CMP_" .. stem(fileName) .. "_Neutral" .. variantCode
end

local function outputBase(fileName, variantCode)
    return stem(fileName) .. "_Rec709_Neutral" .. variantCode .. "_Test"
end

local function oneVideoItem(timeline, expectedFileName)
    local items = timeline:GetItemListInTrack("video", 1) or {}
    if #items ~= 1 then fail("Comparison timeline must contain exactly one video item: " .. timeline:GetName()) end
    local mediaPoolItem = items[1]:GetMediaPoolItem()
    if normalize(basename(clipFilePath(mediaPoolItem))) ~= normalize(expectedFileName) then
        fail("Comparison timeline source mismatch: " .. timeline:GetName())
    end
    return items[1]
end

local function verifyTimelineGeometry(timeline)
    if not valueEqualsNumber(timeline:GetSetting("timelineFrameRate"), 59.94) then
        fail("Timeline frame rate is not 59.94: " .. timeline:GetName())
    end
    if not valueEqualsNumber(timeline:GetSetting("timelinePlaybackFrameRate"), 59.94) then
        fail("Timeline playback frame rate is not 59.94: " .. timeline:GetName())
    end
    if tonumber(timeline:GetSetting("timelineResolutionWidth")) ~= 3840
        or tonumber(timeline:GetSetting("timelineResolutionHeight")) ~= 2160 then
        fail("Timeline resolution is not 3840x2160: " .. timeline:GetName())
    end
end

local function createOrVerifyTimelines(project, clips)
    local result = {V2A = {}, V2B = {}}
    for _, variant in ipairs(VARIANTS) do
        for _, fileName in ipairs(TEST_FILES) do
            local name = timelineName(fileName, variant.code)
            local timeline = findTimeline(project, name)
            if not timeline then
                timeline = project:GetMediaPool():CreateTimelineFromClips(name, {clips[fileName]})
                if not timeline then fail("Could not create comparison timeline " .. name) end
            end
            verifyTimelineGeometry(timeline)
            local item = oneVideoItem(timeline, fileName)
            result[variant.code][fileName] = {timeline = timeline, item = item}
            append(state.timelines, name .. " | nodes=" .. tostring(item:GetNodeGraph():GetNumNodes()))
        end
    end
    return result
end

local function selectForColor(resolveObject, project, entry)
    if not project:SetCurrentTimeline(entry.timeline) then
        local current = project:GetCurrentTimeline()
        if not current or current:GetName() ~= entry.timeline:GetName() then
            fail("Could not select comparison timeline " .. entry.timeline:GetName())
        end
    end
    local startTimecode = entry.timeline:GetStartTimecode()
    if startTimecode and tostring(startTimecode) ~= "" then entry.timeline:SetCurrentTimecode(startTimecode) end
    resolveObject:OpenPage("color")
end

local function copyVariantGrades(project, entries, variantCode)
    local source = entries[TEST_FILES[1]]
    local sourceNodes = source.item:GetNodeGraph():GetNumNodes()
    if sourceNodes ~= 2 then fail(variantCode .. " source grade must contain exactly two nodes before copying.") end
    local targets = {}
    for index = 2, #TEST_FILES do append(targets, entries[TEST_FILES[index]].item) end
    project:SetCurrentTimeline(source.timeline)
    local copied = source.item:CopyGrades(targets)
    for _, target in ipairs(targets) do
        if target:GetNodeGraph():GetNumNodes() ~= 2 then
            fail("CopyGrades did not produce exactly two nodes for a " .. variantCode .. " target.")
        end
    end
    if not copied then append(state.warnings, "CopyGrades returned false for " .. variantCode .. " but both target graphs verified as two nodes.") end
end

local function listOutputFiles(resolveObject)
    local mediaStorage = resolveObject:GetMediaStorage()
    if not mediaStorage then fail("Resolve did not return MediaStorage.") end
    return mediaStorage:GetFileList(OUTPUT_DIR) or {}
end

local function ensureNoComparisonOutputs(resolveObject)
    for _, listedPath in ipairs(listOutputFiles(resolveObject)) do
        local name = normalize(basename(listedPath))
        if contains(name, "_rec709_neutralv2a_test") or contains(name, "_rec709_neutralv2b_test") then
            fail("A comparison output already exists; refusing to overwrite or duplicate it: " .. basename(listedPath))
        end
    end
end

local function chooseMp4H264(project)
    local formatName = nil
    for name, extension in pairs(project:GetRenderFormats() or {}) do
        if normalize(name) == "mp4" or normalize(extension) == "mp4" then formatName = name break end
    end
    if not formatName then fail("MP4 render format is unavailable.") end
    local codecName = nil
    for description, name in pairs(project:GetRenderCodecs(formatName) or {}) do
        if contains(description, "h.264") or contains(description, "h264")
            or contains(name, "h.264") or contains(name, "h264") then codecName = name break end
    end
    if not codecName then fail("H.264 codec is unavailable for MP4.") end
    project:SetCurrentRenderFormatAndCodec(formatName, codecName)
    local actual = project:GetCurrentRenderFormatAndCodec() or {}
    if normalize(actual.format) ~= "mp4" or not (contains(actual.codec, "h264") or contains(actual.codec, "h.264")) then
        fail("Could not verify MP4/H.264 render format and codec.")
    end
end

local function setDocumentedRenderSettings(project, outputName)
    local settings = {
        {"SelectAllFrames", true},
        {"TargetDir", OUTPUT_DIR},
        {"CustomName", outputName},
        {"ExportVideo", true},
        {"ExportAudio", true},
        {"FormatWidth", 3840},
        {"FormatHeight", 2160},
        {"FrameRate", 59.94},
        {"VideoQuality", "Best"},
        {"AudioCodec", "aac"},
        {"AudioSampleRate", 48000},
        {"ColorSpaceTag", "Same as Project"},
        {"GammaTag", "Same as Project"},
        {"ReplaceExistingFilesInPlace", false}
    }
    local rejected = {}
    for _, entry in ipairs(settings) do
        local single = {}
        single[entry[1]] = entry[2]
        if not project:SetRenderSettings(single) then append(rejected, entry[1]) end
    end
    if #rejected > 0 then
        append(state.warnings, "Resolve returned false for these individually submitted settings for "
            .. outputName .. ": " .. table.concat(rejected, ", ") .. ". Actual job fields will be verified.")
    end
end

local function comparisonJobsAlreadyExist(project)
    for _, job in ipairs(project:GetRenderJobList() or {}) do
        if contains(job.TimelineName, "CMP_") then return true end
    end
    return false
end

local function verifyNewJob(job, expectedTimeline, expectedOutputPrefix)
    local target = normalize(job.TargetDir):gsub("\\", "/")
    local outputName = tostring(job.OutputFilename or "")
    return tostring(job.TimelineName or "") == expectedTimeline
        and string.sub(outputName, 1, #expectedOutputPrefix) == expectedOutputPrefix
        and normalize(string.sub(outputName, -4)) == ".mp4"
        and string.sub(target, -22) == "ship_output/comparison"
        and normalize(job.VideoFormat) == "mp4"
        and (contains(job.VideoCodec, "h.264") or contains(job.VideoCodec, "h264"))
        and tonumber(job.FormatWidth) == 3840
        and tonumber(job.FormatHeight) == 2160
        and valueEqualsNumber(job.FrameRate, 59.94)
        and job.IsExportVideo == true
        and job.IsExportAudio == true
        and normalize(job.AudioCodec) == "aac"
        and tonumber(job.AudioSampleRate) == 48000
        and contains(job.RenderMode, "individual")
end

local function queueAndStartSix(resolveObject, project, entries)
    ensureNoComparisonOutputs(resolveObject)
    if comparisonJobsAlreadyExist(project) then fail("Comparison render jobs already exist; refusing to duplicate them.") end
    if project:IsRenderingInProgress() then fail("Resolve is already rendering; refusing to start comparison renders.") end
    if not project:SetCurrentRenderMode(0) and tonumber(project:GetCurrentRenderMode()) ~= 0 then
        fail("Could not set Individual Clips render mode.")
    end
    if tonumber(project:GetCurrentRenderMode()) ~= 0 then fail("Render mode did not read back as Individual Clips.") end
    chooseMp4H264(project)

    local newJobIds = {}
    local expectations = {}
    for _, variant in ipairs(VARIANTS) do
        for _, fileName in ipairs(TEST_FILES) do
            local entry = entries[variant.code][fileName]
            project:SetCurrentTimeline(entry.timeline)
            local base = outputBase(fileName, variant.code)
            setDocumentedRenderSettings(project, base)
            local jobId = project:AddRenderJob()
            if not jobId or tostring(jobId) == "" then fail("Could not add comparison render job for " .. base) end
            jobId = tostring(jobId)
            append(newJobIds, jobId)
            expectations[jobId] = {timeline = entry.timeline:GetName(), output = base}
            append(state.outputs, OUTPUT_DIR .. "/" .. base .. ".mp4")
        end
    end

    local seen = {}
    for _, job in ipairs(project:GetRenderJobList() or {}) do
        local jobId = tostring(job.JobId or job.RenderJobId or "")
        local expected = expectations[jobId]
        if expected then
            if not verifyNewJob(job, expected.timeline, expected.output) then
                fail("Comparison render job verification failed for " .. expected.timeline .. ". No comparison render was started.")
            end
            seen[jobId] = true
            local fields = {}
            for key, value in pairs(job) do if scalar(value) then append(fields, tostring(key) .. "=" .. tostring(value)) end end
            table.sort(fields)
            append(state.render_jobs, table.concat(fields, "; "))
        end
    end
    for _, jobId in ipairs(newJobIds) do
        if not seen[jobId] then fail("New comparison job was not returned by GetRenderJobList: " .. jobId) end
    end

    resolveObject:GetProjectManager():SaveProject()
    state.phase = "SIX_COMPARISON_RENDERS_STARTED"
    writeReport()
    local started = project:StartRendering(newJobIds, true)
    if not started then fail("Resolve refused to start the six verified comparison render jobs.") end
    resolveObject:OpenPage("deliver")
    print("FX3_NEUTRAL_COMPARISON_SIX_RENDERS_STARTED")
end

local function nodeCount(entry)
    return entry.item:GetNodeGraph():GetNumNodes()
end

local function allTargetsHave(entries, count)
    for index = 2, #TEST_FILES do
        if nodeCount(entries[TEST_FILES[index]]) ~= count then return false end
    end
    return true
end

local function main()
    local resolveObject = getResolveObject()
    if not resolveObject then fail("No internal Resolve object. Run from Workspace > Scripts inside Resolve.") end
    local projectManager = resolveObject:GetProjectManager()
    local project = projectManager and projectManager:GetCurrentProject() or nil
    if not project or project:GetName() ~= PROJECT_NAME then
        fail("The isolated test project is not the current project. Refusing to modify any other project.")
    end
    verifyProjectSettings(project)
    local clips = sourceClipMap(project)
    local entries = createOrVerifyTimelines(project, clips)

    local aSource = entries.V2A[TEST_FILES[1]]
    local bSource = entries.V2B[TEST_FILES[1]]
    local aSourceNodes = nodeCount(aSource)
    local bSourceNodes = nodeCount(bSource)

    if aSourceNodes == 1 and allTargetsHave(entries.V2A, 1)
        and bSourceNodes == 1 and allTargetsHave(entries.V2B, 1) then
        projectManager:SaveProject()
        state.phase = "AWAITING_NATIVE_V2A_NODE_ENTRY"
        append(state.warnings, "On the selected first V2A clip, add exactly one serial corrector node and enter/read back the five requested native Primary values. Do not change node 1.")
        writeReport()
        selectForColor(resolveObject, project, aSource)
        print("FX3_NEUTRAL_COMPARISON_READY_FOR_V2A")
        return
    end

    if aSourceNodes == 2 and allTargetsHave(entries.V2A, 1)
        and bSourceNodes == 1 and allTargetsHave(entries.V2B, 1) then
        copyVariantGrades(project, entries.V2A, "V2A")
        projectManager:SaveProject()
        state.phase = "AWAITING_NATIVE_V2B_NODE_ENTRY"
        append(state.warnings, "V2A was copied through the official CopyGrades API. On the selected first V2B clip, add exactly one serial corrector node and enter/read back the five requested native Primary values. Do not change node 1.")
        writeReport()
        selectForColor(resolveObject, project, bSource)
        print("FX3_NEUTRAL_COMPARISON_READY_FOR_V2B")
        return
    end

    if aSourceNodes == 2 and allTargetsHave(entries.V2A, 2)
        and bSourceNodes == 2 and allTargetsHave(entries.V2B, 1) then
        copyVariantGrades(project, entries.V2B, "V2B")
        projectManager:SaveProject()
        queueAndStartSix(resolveObject, project, entries)
        return
    end

    fail("Comparison node state is not one of the three safe workflow stages. Refusing automatic recovery or rendering.")
end

local ok, message = pcall(main)
if not ok then
    if #state.failures == 0 then append(state.failures, tostring(message)) end
    state.phase = "FAILED"
    writeReport()
    print("FX3_NEUTRAL_COMPARISON_FAILED: " .. tostring(message))
end
