-- FX3 Batch V2B.lua
-- Internal DaVinci Resolve 20.3.2 script. Run from Workspace > Scripts only.
-- Processes at most ten missing final outputs per invocation.

local PROJECT_NAME = "FX3_SLog3_AutoGrade_Test"
local REFERENCE_TIMELINE = "CMP_FX3_TEST_001_NeutralV2B"
local BATCH_SIZE = 10
local OUTPUT_SUFFIX = "_Rec709_NeutralV2B"

local INPUT_COLOR_SPACE_LABELS = {
    "S-Gamut3.Cine/S-Log3",
    "Sony S-Gamut3.Cine/S-Log3",
    "Sony S-Gamut3.Cine / S-Log3"
}

local function normalize(value)
    return string.lower((tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function compact(value)
    return string.lower((tostring(value or ""):gsub("%s+", "")))
end

local function contains(value, needle)
    return string.find(normalize(value), normalize(needle), 1, true) ~= nil
end

local function basename(path)
    return tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or ""
end

local function dirname(path)
    local normalized = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
    return normalized:match("^(.*)/[^/]+$") or ""
end

local function stem(fileName)
    return tostring(fileName or ""):gsub("%.[^%.]+$", "")
end

local function valueEqualsNumber(actual, expected)
    local number = tonumber(actual)
    return number and math.abs(number - expected) < 0.0005
end

local function fail(message)
    error(tostring(message))
end

local function getResolveObject()
    if app and app.GetResolve then return app:GetResolve() end
    if fusion and fusion.GetResolve then return fusion:GetResolve() end
    return nil
end

local function verifyProjectSettings(project)
    local required = {
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
    for _, entry in ipairs(required) do
        local actual = tostring(project:GetSetting(entry[1]) or "")
        if normalize(actual) ~= normalize(entry[2]) then
            fail("Project setting mismatch: " .. entry[1] .. " expected='" .. entry[2] .. "' actual='" .. actual .. "'.")
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

local function collectMediaPoolClips(folder, result)
    for _, clip in ipairs(folder:GetClipList() or {}) do result[#result + 1] = clip end
    for _, child in ipairs(folder:GetSubFolderList() or {}) do collectMediaPoolClips(child, result) end
end

local function mediaPoolPathMap(project)
    local clips = {}
    local result = {}
    collectMediaPoolClips(project:GetMediaPool():GetRootFolder(), clips)
    for _, clip in ipairs(clips) do
        local path = clipFilePath(clip):gsub("\\", "/")
        if path ~= "" then result[normalize(path)] = clip end
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

local function oneVideoItem(timeline, expectedPath)
    local items = timeline:GetItemListInTrack("video", 1) or {}
    if #items ~= 1 then fail("Timeline must contain exactly one video item: " .. timeline:GetName()) end
    local media = items[1]:GetMediaPoolItem()
    if normalize(clipFilePath(media):gsub("\\", "/")) ~= normalize(expectedPath:gsub("\\", "/")) then
        fail("Timeline source mismatch: " .. timeline:GetName())
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

local function findInputColorSpaceKey(clip)
    local properties = clip:GetClipProperty() or {}
    for key, _ in pairs(properties) do
        local lowerKey = string.lower(tostring(key))
        if lowerKey == "input color space" then return key end
        if string.find(lowerKey, "input", 1, true)
            and string.find(lowerKey, "color", 1, true)
            and string.find(lowerKey, "space", 1, true) then return key end
    end
    return "Input Color Space"
end

local function setAndVerifyInputColorSpace(project, clip, fileName)
    local key = findInputColorSpaceKey(clip)
    for _, label in ipairs(INPUT_COLOR_SPACE_LABELS) do
        local ok = clip:SetClipProperty(key, label)
        local actual = clip:GetClipProperty(key)
        if ok and contains(actual, "s-gamut3.cine") and contains(actual, "s-log3") then
            return actual
        end
    end
    local actual = clip:GetClipProperty(key)
    local projectInput = project:GetSetting("colorSpaceInput")
    local projectGamma = project:GetSetting("colorSpaceInputGamma")
    local inherits = compact(actual) == "project" or tostring(actual) == "项目"
    if inherits and contains(projectInput, "s-gamut3.cine") and contains(projectGamma, "s-log3") then
        return "Project -> " .. tostring(projectInput) .. " / " .. tostring(projectGamma)
    end
    fail("Could not set/read Input Color Space for " .. fileName .. ". Actual='" .. tostring(actual) .. "'.")
end

local function referenceEntry(project)
    local timeline = findTimeline(project, REFERENCE_TIMELINE)
    if not timeline then fail("Verified V2B reference timeline is missing: " .. REFERENCE_TIMELINE) end
    local items = timeline:GetItemListInTrack("video", 1) or {}
    if #items ~= 1 then fail("V2B reference timeline must contain exactly one video item.") end
    local item = items[1]
    if item:GetNodeGraph():GetNumNodes() ~= 2 then
        fail("Verified V2B reference grade no longer contains exactly two nodes.")
    end
    local media = item:GetMediaPoolItem()
    local path = clipFilePath(media):gsub("\\", "/")
    if path == "" then fail("V2B reference source path is unavailable.") end
    return {timeline = timeline, item = item, media = media, path = path}
end

local function readSourceManifest(path)
    local handle, openError = io.open(path, "rb")
    if not handle then fail("Could not open source manifest: " .. path .. "; " .. tostring(openError)) end
    local files = {}
    local seen = {}
    for line in handle:lines() do
        line = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            if not string.match(string.lower(line), "%.mp4$") then
                handle:close()
                fail("Only MP4 filenames are allowed in source manifest: " .. line)
            end
            if basename(line) ~= line or string.find(line, "..", 1, true) then
                handle:close()
                fail("Manifest entries must be plain filenames, not paths: " .. line)
            end
            local key = normalize(line)
            if seen[key] then
                handle:close()
                fail("Duplicate source filename in manifest: " .. line)
            end
            seen[key] = true
            files[#files + 1] = line
        end
    end
    handle:close()
    if #files == 0 then fail("Source manifest is empty: " .. path) end
    return files
end

local function discoverSourcePaths(resolveObject, reference)
    local shipDir = dirname(reference.path)
    if normalize(basename(shipDir)) ~= "ship" then fail("Reference source is not inside a ship directory.") end
    local projectRoot = dirname(shipDir)
    local outputDir = projectRoot .. "/ship_output/final"
    local sourceFiles = readSourceManifest(projectRoot .. "/config/source_files.txt")
    local paths = {}
    for _, fileName in ipairs(sourceFiles) do paths[#paths + 1] = shipDir .. "/" .. fileName end
    return shipDir, outputDir, paths
end

local function outputBase(path)
    return stem(basename(path)) .. OUTPUT_SUFFIX
end

local function selectNextBatch(project, allPaths)
    local selected = {}
    local skipped = 0
    for _, path in ipairs(allPaths) do
        local timelineName = "FINAL_" .. stem(basename(path)) .. "_NeutralV2B"
        if findTimeline(project, timelineName) then
            skipped = skipped + 1
        elseif #selected < BATCH_SIZE then
            selected[#selected + 1] = path
        end
    end
    return selected, skipped
end

local function importSelected(project, selected)
    local mediaPool = project:GetMediaPool()
    local pathMap = mediaPoolPathMap(project)
    local result = {}
    for _, path in ipairs(selected) do
        local key = normalize(path)
        local clip = pathMap[key]
        if not clip then
            local imported = mediaPool:ImportMedia({path}) or {}
            clip = imported[1]
            if not clip then fail("Resolve failed to import MP4: " .. path) end
            pathMap[key] = clip
        end
        setAndVerifyInputColorSpace(project, clip, basename(path))
        result[path] = clip
    end
    return result
end

local function createOrVerifyFinalTimelines(project, selected, clips)
    local result = {}
    for _, path in ipairs(selected) do
        local name = "FINAL_" .. stem(basename(path)) .. "_NeutralV2B"
        local timeline = findTimeline(project, name)
        if not timeline then
            timeline = project:GetMediaPool():CreateTimelineFromClips(name, {clips[path]})
            if not timeline then fail("Could not create final timeline: " .. name) end
        end
        verifyTimelineGeometry(timeline)
        local item = oneVideoItem(timeline, path)
        result[#result + 1] = {path = path, timeline = timeline, item = item}
    end
    return result
end

local function copyVerifiedV2B(project, reference, targets)
    if not project:SetCurrentTimeline(reference.timeline) then
        fail("Could not select verified V2B reference timeline.")
    end
    local targetItems = {}
    for _, entry in ipairs(targets) do targetItems[#targetItems + 1] = entry.item end
    local copied = reference.item:CopyGrades(targetItems)
    for _, entry in ipairs(targets) do
        if entry.item:GetNodeGraph():GetNumNodes() ~= 2 then
            fail("V2B CopyGrades did not produce exactly two nodes: " .. entry.timeline:GetName())
        end
    end
    if not copied then print("WARNING: CopyGrades returned false, but all target node graphs verified as two nodes.") end
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
    if not project:SetCurrentRenderFormatAndCodec(formatName, codecName) then
        fail("Could not set MP4/H.264 render format and codec.")
    end
    local actual = project:GetCurrentRenderFormatAndCodec() or {}
    if normalize(actual.format) ~= "mp4"
        or not (contains(actual.codec, "h264") or contains(actual.codec, "h.264")) then
        fail("Could not read back MP4/H.264 render format and codec.")
    end
end

local function setRenderSettings(project, outputDir, customName)
    local settings = {
        {"SelectAllFrames", true},
        {"TargetDir", outputDir},
        {"CustomName", customName},
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
    for _, setting in ipairs(settings) do
        local one = {}
        one[setting[1]] = setting[2]
        if not project:SetRenderSettings(one) then rejected[#rejected + 1] = setting[1] end
    end
    if #rejected > 0 then
        print("WARNING: SetRenderSettings returned false for " .. customName .. ": " .. table.concat(rejected, ", "))
    end
end

local function verifyJob(job, expectedTimeline, expectedPrefix, outputDir)
    local target = tostring(job.TargetDir or ""):gsub("\\", "/"):gsub("/+$", "")
    local fileName = tostring(job.OutputFilename or "")
    return tostring(job.TimelineName or "") == expectedTimeline
        and string.sub(fileName, 1, #expectedPrefix) == expectedPrefix
        and normalize(string.sub(fileName, -4)) == ".mp4"
        and normalize(target) == normalize(outputDir)
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

local function queueAndStart(resolveObject, project, projectManager, outputDir, entries, skipped)
    if project:IsRenderingInProgress() then fail("Resolve is already rendering.") end
    if not project:SetCurrentRenderMode(0) and tonumber(project:GetCurrentRenderMode()) ~= 0 then
        fail("Could not set Individual Clips render mode.")
    end
    if tonumber(project:GetCurrentRenderMode()) ~= 0 then fail("Render mode did not read back as Individual Clips.") end
    chooseMp4H264(project)

    local ids = {}
    local expected = {}
    for _, entry in ipairs(entries) do
        if not project:SetCurrentTimeline(entry.timeline) then
            fail("Could not select final timeline: " .. entry.timeline:GetName())
        end
        local base = outputBase(entry.path)
        setRenderSettings(project, outputDir, base)
        local id = project:AddRenderJob()
        if not id or tostring(id) == "" then fail("Could not add render job: " .. base) end
        id = tostring(id)
        ids[#ids + 1] = id
        expected[id] = {timeline = entry.timeline:GetName(), prefix = base}
    end

    local verified = {}
    for _, job in ipairs(project:GetRenderJobList() or {}) do
        local id = tostring(job.JobId or job.RenderJobId or "")
        local target = expected[id]
        if target then
            if not verifyJob(job, target.timeline, target.prefix, outputDir) then
                fail("Render job verification failed: " .. target.timeline)
            end
            verified[id] = true
        end
    end
    for _, id in ipairs(ids) do
        if not verified[id] then fail("New job missing from render queue: " .. id) end
    end

    if not projectManager:SaveProject() then fail("Could not save isolated project before render.") end
    local started = project:StartRendering(ids, true)
    if not started then fail("Resolve refused to start the verified batch.") end
    resolveObject:OpenPage("deliver")
    print("FX3_BATCH_V2B_STARTED count=" .. tostring(#ids) .. " already_complete=" .. tostring(skipped))
    for _, entry in ipairs(entries) do print("BATCH_ITEM " .. basename(entry.path)) end
end

local function main()
    local resolveObject = getResolveObject()
    if not resolveObject then fail("No internal Resolve object. Run this script inside Resolve.") end
    local projectManager = resolveObject:GetProjectManager()
    local project = projectManager and projectManager:GetCurrentProject() or nil
    if not project or project:GetName() ~= PROJECT_NAME then
        fail("The isolated FX3 test project is not current. Refusing to modify any other project.")
    end
    verifyProjectSettings(project)
    local reference = referenceEntry(project)
    local _, outputDir, allPaths = discoverSourcePaths(resolveObject, reference)
    local selected, skipped = selectNextBatch(project, allPaths)
    if #selected == 0 then
        projectManager:SaveProject()
        resolveObject:OpenPage("deliver")
        print("FX3_BATCH_V2B_ALL_MANIFEST_OUTPUTS_PRESENT")
        return
    end
    local clips = importSelected(project, selected)
    local entries = createOrVerifyFinalTimelines(project, selected, clips)
    copyVerifiedV2B(project, reference, entries)
    queueAndStart(resolveObject, project, projectManager, outputDir, entries, skipped)
end

local ok, message = pcall(main)
if not ok then print("FX3_BATCH_V2B_FAILED: " .. tostring(message)) end
