-- Sony SLog3 AutoGrade.lua
-- Internal Resolve test/batch runner for a human-approved reference grade.
-- It never writes to source media and contains no built-in look parameters or LUT.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ASCII_DIR = TEMP_ROOT .. "/SonySLog3AutoGrade"
local PROFILE_PATH = ASCII_DIR .. "/runtime.lua"
local LOG_PATH = ASCII_DIR .. "/autograde.log"
local REPORT_PATH = ASCII_DIR .. "/autograde_report.md"
local EMERGENCY_LOG = TEMP_ROOT .. "/SonySLog3AutoGrade_emergency.log"

local state = {status="STARTING", stage="bootstrap", jobs={}, outputs={}, warnings={}, errors={}}
local function append(list, value) list[#list + 1] = tostring(value) end
local function rawAppend(path, text)
    local handle, err = io.open(path, "ab"); if not handle then return false, err end
    handle:write(text); handle:close(); return true, nil
end
local function quoted(path) return '"' .. tostring(path):gsub("/", "\\"):gsub('"', '""') .. '"' end
local function ensureDir()
    local probe=io.open(LOG_PATH,"ab"); if probe then probe:close(); return true end
    os.execute("cmd.exe /d /c if not exist "..quoted(ASCII_DIR).." mkdir "..quoted(ASCII_DIR).." >NUL 2>&1")
    local retry=io.open(LOG_PATH,"ab"); if retry then retry:close(); return true end
    return false
end
local loggerReady=ensureDir()
local function logLine(text)
    local line=tostring(text or "").."\n"
    if loggerReady then local ok=rawAppend(LOG_PATH,line); if ok then return end end
    rawAppend(EMERGENCY_LOG,line)
end
logLine(""); logLine("============================================================"); logLine("START")
logLine("timestamp="..os.date("%Y-%m-%d %H:%M:%S %z")); logLine("interface=internal app:GetResolve()")

local function stage(name) state.stage=name; logLine("STAGE="..name) end
local function value(name,v) logLine(name.."="..tostring(v)) end
local function normalize(v) return string.lower((tostring(v or ""):gsub("%s+",""))) end
local function compact(v) return string.lower((tostring(v or ""):gsub("[^%w]",""))) end
local function contains(v,t) return string.find(normalize(v),normalize(t),1,true)~=nil end
local function pathKey(v) return string.lower(tostring(v or ""):gsub("\\","/")) end
local function basename(path) local p=tostring(path or ""):gsub("\\","/"); return p:match("([^/]+)$") or p end
local function stem(path) return (basename(path):gsub("%.[^%.]+$","")) end
local function numberEquals(v,e) local n=tonumber(v); return n and math.abs(n-e)<0.001 end
local function tracebackHandler(err)
    if debug and type(debug.traceback)=="function" then return debug.traceback(tostring(err),2) end
    return tostring(err)
end
local function fail(message) append(state.errors,"stage="..state.stage.." | "..message); error(message,0) end

local function safeString(v)
    local ok,result=pcall(function()return tostring(v)end)
    return ok and result or "<tostring failed>"
end
local function dumpRawCollection(label,collection)
    logLine(label.." RAW BEGIN");value(label..".type",type(collection))
    if type(collection)=="table"then
        local diagnosticCount=0
        local ok,err=pcall(function()
            for key,item in pairs(collection)do
                diagnosticCount=diagnosticCount+1
                local prefix=label..".entry["..diagnosticCount.."]"
                local sequence=type(key)=="number"and key>=1 and key%1==0
                value(prefix..".key_type",type(key));value(prefix..".key",safeString(key))
                value(prefix..".value_type",type(item));value(prefix..".value",safeString(item))
                value(prefix..".is_sequence_entry",sequence);value(prefix..".is_userdata",type(item)=="userdata")
                if type(key)=="string"and key:sub(1,2)=="__"then value(prefix..".classification","BRIDGE_METADATA")
                elseif sequence then value(prefix..".classification","SEQUENCE_CANDIDATE")
                else value(prefix..".classification","NON_SEQUENCE_AUXILIARY")end
            end
        end)
        value(label..".diagnostic_entry_count",diagnosticCount);value(label..".iterate_ok",ok)
        if not ok then value(label..".iterate_error",err)end
    end
    logLine(label.." RAW END")
end
local function validatedSequenceItems(collection,validator,label)
    if type(collection)~="table"then fail(label.." did not return a Lua table.")end
    local validated={};local count=0
    for index,item in ipairs(collection)do
        local valid,reason=validator(item)
        value(label..".sequence["..index.."].value_type",type(item));value(label..".sequence["..index.."].validated",valid)
        if not valid then fail(label.." sequence entry is invalid: "..tostring(reason))end
        count=count+1;validated[count]=item
    end
    return validated,count
end

local function loadProfile()
    stage("Runtime Profile")
    local loader,err=loadfile(PROFILE_PATH); if not loader then fail("Cannot load runtime profile: "..tostring(err)) end
    local ok,p=pcall(loader); if not ok then fail("Runtime profile error: "..tostring(p)) end
    if type(p)~="table" or tonumber(p.schema_version)~=2 then fail("Invalid runtime profile schema.") end
    if p.mode~="test" and p.mode~="batch" then fail("AutoGrade requires mode='test' or mode='batch'.") end
    if not p.project or tostring(p.project.name or "")=="" then fail("Missing project.name.") end
    if not p.batch or type(p.batch.source_files)~="table" or #p.batch.source_files<1 then fail("Missing source files.") end
    if normalize(p.batch.gamma)~=normalize("S-Log3") or normalize(p.batch.primaries)~=normalize("Sony S-Gamut3.Cine") then
        fail("Source is not confirmed Sony S-Gamut3.Cine / S-Log3.")
    end
    if p.batch.homogeneous_metadata_verified~=true then fail("Batch homogeneity was not explicitly verified.")end
    if not p.look or p.look.approved~=true or tostring(p.look.reference_timeline or "")=="" then
        fail("A human-approved reference_timeline is required; Neutral Safe has no permanent built-in parameters.")
    end
    if not p.authorization then fail("Missing authorization table.") end
    if p.mode=="test" and p.authorization.test_approved~=true then fail("Test is not authorized.") end
    if p.mode=="batch" and p.authorization.batch_approved~=true then fail("Batch is not authorized.") end
    if p.authorization.start_rendering~=true then fail("start_rendering is not explicitly authorized.") end
    if not p.paths or tostring(p.paths.input_dir or "")=="" or tostring(p.paths.output_dir or "")=="" then fail("Missing paths.") end
    if pathKey(p.paths.input_dir)==pathKey(p.paths.output_dir) then fail("Input and output paths must differ.") end
    return p
end

local function acquireObjects(profile)
    stage("Resolve")
    local appObject=rawget(_G,"app"); if not appObject then fail("Internal app is unavailable.") end
    local resolveObject=appObject:GetResolve(); if not resolveObject then fail("app:GetResolve returned nil.") end
    local manager=resolveObject:GetProjectManager(); if not manager then fail("GetProjectManager returned nil.") end
    local project=manager:GetCurrentProject(); if not project then fail("No current project.") end
    if project:GetName()~=profile.project.name then fail("Current project is not the profile target.") end
    return resolveObject,manager,project
end

local function verifyProject(project,p)
    stage("Project Preflight")
    local fps=tonumber(p.batch.frame_rate); local width=tonumber(p.batch.width); local height=tonumber(p.batch.height)
    local checks={
        {"timelinePlaybackFrameRate",function(v)return numberEquals(v,fps)end},
        {"timelineFrameRate",function(v)return numberEquals(v,fps)end},
        {"timelineResolutionWidth",function(v)return tonumber(v)==width end},
        {"timelineResolutionHeight",function(v)return tonumber(v)==height end},
        {"colorScienceMode",function(v)return contains(v,"color")and contains(v,"managed")end},
        {"isAutoColorManage",function(v)return tostring(v)=="0"or normalize(v)=="false"end},
        {"colorSpaceInput",function(v)return contains(v,"s-gamut3.cine")end},
        {"colorSpaceInputGamma",function(v)return contains(v,"s-log3")end},
        {"colorSpaceTimeline",function(v)return contains(v,"davinci")and(contains(v,"widegamut")or contains(v,"wg"))end},
        {"colorSpaceTimelineGamma",function(v)return contains(v,"intermediate")end},
        {"colorSpaceOutput",function(v)return contains(v,"rec.709")or contains(v,"rec709")end},
        {"colorSpaceOutputGamma",function(v)return contains(v,"2.4")end}
    }
    for _,entry in ipairs(checks)do local actual=project:GetSetting(entry[1]); value("project."..entry[1],actual); if not entry[2](actual)then fail("Project preflight mismatch: "..entry[1])end end
end

local function clipPath(clip)
    local p=clip:GetClipProperty("File Path"); if p and tostring(p)~=""then return tostring(p)end
    for k,v in pairs(clip:GetClipProperty()or{})do if compact(k)=="filepath"then return tostring(v or "")end end
    return ""
end
local function validatedTimelineItem(timeline,expectedPath)
    local callOk,rawItems=pcall(function()return timeline:GetItemListInTrack("video",1)end)
    value("timeline_item_list.call_ok",callOk);value("timeline_item_list.return_type",type(rawItems))
    if not callOk then fail("GetItemListInTrack(video, 1) failed: "..tostring(rawItems))end
    rawItems=rawItems or{};dumpRawCollection("TIMELINE ITEM LIST",rawItems)
    local items,count=validatedSequenceItems(rawItems,function(item)
        if type(item)~="userdata"then return false,"expected TimelineItem userdata"end
        local nameOk,itemName=pcall(function()return item:GetName()end)
        if not nameOk then return false,"TimelineItem:GetName failed: "..tostring(itemName)end
        local poolOk,poolItem=pcall(function()return item:GetMediaPoolItem()end)
        if not poolOk or type(poolItem)~="userdata"then return false,"GetMediaPoolItem did not return MediaPoolItem userdata"end
        return true
    end,"timeline_item_list")
    value("validated_video_item_count",count)
    if count~=1 then fail("Timeline must contain exactly one validated video item: "..timeline:GetName())end
    local poolItem=items[1]:GetMediaPoolItem()
    if expectedPath and pathKey(clipPath(poolItem))~=pathKey(expectedPath)then fail("Timeline source mismatch.")end
    return items[1]
end
local function rootClips(project)return project:GetMediaPool():GetRootFolder():GetClipList()or{}end
local function findClip(project,fullPath)for _,c in ipairs(rootClips(project))do if pathKey(clipPath(c))==pathKey(fullPath)then return c end end end
local function importClip(project,fullPath)
    local existing=findClip(project,fullPath); if existing then return existing end
    local imported=project:GetMediaPool():ImportMedia({fullPath})or{};dumpRawCollection("IMPORT MEDIA RESULT",imported)
    local items,count=validatedSequenceItems(imported,function(item)
        if type(item)~="userdata"then return false,"expected imported MediaPoolItem userdata"end
        return true
    end,"import_media_result")
    if count~=1 then fail("ImportMedia must return exactly one validated MediaPoolItem: "..fullPath)end
    return items[1]
end
local function verifyClipInput(project,clip,p)
    local evidence={}
    local function collect(source,actual)
        local text=tostring(actual or ""); value("clip_input."..source,text)
        if text~=""and normalize(text)~="project"and text~="项目"then evidence[#evidence+1]=text end
    end
    local directOk,direct=pcall(function()return clip:GetClipProperty("Input Color Space")end)
    value("clip_input.direct.call_ok",directOk);if directOk then collect("direct",direct)end
    local snapshotOk,properties=pcall(function()return clip:GetClipProperty()end)
    value("clip_input.snapshot.call_ok",snapshotOk)
    if snapshotOk and type(properties)=="table"then
        for key,actual in pairs(properties)do
            if type(key)=="string"and key:sub(1,2)~="__"and contains(key,"input")and contains(key,"color")and contains(key,"space")then
                collect("snapshot",actual)
            end
        end
    end
    for _,actual in ipairs(evidence)do
        if not(contains(actual,"s-gamut3.cine")and contains(actual,"s-log3"))then
            fail("Per-clip Input Color Space conflicts with the verified batch for "..tostring(clip:GetName()))
        end
    end
    if #evidence>0 then value("clip_input.policy","EXPLICIT_CLIP_MATCH");return end
    local metadataVerified=tostring(p.batch.metadata_confirmation or "")~=""
        and p.batch.homogeneous_metadata_verified==true
        and normalize(p.batch.gamma)==normalize("S-Log3")
        and normalize(p.batch.primaries)==normalize("Sony S-Gamut3.Cine")
    local projectVerified=contains(project:GetSetting("colorSpaceInput"),"s-gamut3.cine")
        and contains(project:GetSetting("colorSpaceInputGamma"),"s-log3")
        and(tostring(project:GetSetting("isAutoColorManage"))=="0"or normalize(project:GetSetting("isAutoColorManage"))=="false")
    if not metadataVerified or not projectVerified then fail("Effective Input Color Space is unverified for "..tostring(clip:GetName()))end
    append(state.warnings,"Per-clip Input Color Space is unavailable for "..tostring(clip:GetName()).."; using verified homogeneous metadata plus verified project input.")
    value("clip_input.policy","VERIFIED_PROJECT_DEFAULT")
end
local function findTimeline(project,name)
    for i=1,project:GetTimelineCount()do local t=project:GetTimelineByIndex(i);if t and t:GetName()==name then return t end end
end
local function oneItem(timeline,expectedPath)return validatedTimelineItem(timeline,expectedPath)end

local function selectedFiles(p)
    local selected={}
    local allowed={};for _,name in ipairs(p.batch.source_files)do allowed[normalize(name)]=true end
    if p.mode=="test" then
        local requested=(p.selection and p.selection.test_files)or{}
        if #requested<1 then fail("selection.test_files is required for representative testing.")end
        local limit=math.min(tonumber(p.authorization.max_test_clips)or 3,3)
        if #requested>limit then fail("Test selection exceeds the maximum.")end
        for _,name in ipairs(requested)do
            if not allowed[normalize(name)]then fail("Test file is not in the confirmed batch manifest: "..tostring(name))end
            append(selected,name)
        end
    else
        local offset=tonumber((p.selection and p.selection.batch_offset)or 1)or 1
        local limit=math.min(tonumber(p.authorization.max_batch_size)or 10,10)
        for index=offset,math.min(#p.batch.source_files,offset+limit-1)do append(selected,p.batch.source_files[index])end
    end
    return selected
end

local function referenceItem(project,p)
    stage("Approved Reference Grade")
    local timeline=findTimeline(project,p.look.reference_timeline);if not timeline then fail("Reference timeline is missing.")end
    local item=oneItem(timeline);local expected=tonumber(p.look.expected_node_count)or 2
    local count=item:GetNodeGraph():GetNumNodes();value("reference.node_count",count)
    if count~=expected then fail("Reference node count changed.")end
    return item
end

local function createTargets(project,p,files)
    stage("Target Timelines")
    local entries={};local inputRoot=tostring(p.paths.input_dir):gsub("[\\/]$","")
    for _,name in ipairs(files)do
        local fullPath=inputRoot.."/"..name;local clip=importClip(project,fullPath)
        verifyClipInput(project,clip,p)
        local timelineName="AUTO_"..stem(name).."_"..tostring(p.look.name or "NeutralSafe"):gsub("[^%w]","")
        local timeline=findTimeline(project,timelineName)
        if not timeline then timeline=project:GetMediaPool():CreateTimelineFromClips(timelineName,{clip})end
        if not timeline then fail("Could not create target timeline: "..timelineName)end
        local item=oneItem(timeline,fullPath)
        entries[#entries+1]={name=name,timeline=timeline,item=item}
    end
    return entries
end

local function applyReference(project,reference,entries,p)
    stage("Copy Approved Grade")
    local targets={};for _,entry in ipairs(entries)do targets[#targets+1]=entry.item end
    local referenceTimeline=findTimeline(project,p.look.reference_timeline);project:SetCurrentTimeline(referenceTimeline)
    if not reference:CopyGrades(targets)then fail("Official CopyGrades failed.")end
    local expected=tonumber(p.look.expected_node_count)or 2
    for _,entry in ipairs(entries)do if entry.item:GetNodeGraph():GetNumNodes()~=expected then fail("Copied node count mismatch: "..entry.name)end end
end

local function chooseMp4H264(project)
    local formatName=nil;for name,ext in pairs(project:GetRenderFormats()or{})do if compact(name)=="mp4"or compact(ext)=="mp4"then formatName=name;break end end
    if not formatName then fail("MP4 is unavailable.")end
    local codecName=nil;for desc,name in pairs(project:GetRenderCodecs(formatName)or{})do if contains(desc,"h.264")or contains(name,"h264")then codecName=name;break end end
    if not codecName then fail("H.264 is unavailable for MP4.")end
    project:SetCurrentRenderFormatAndCodec(formatName,codecName);local actual=project:GetCurrentRenderFormatAndCodec()or{}
    if compact(actual.format)~=compact(formatName)or not contains(compact(actual.codec),"h264")then fail("Render format readback failed.")end
end
local function outputExists(resolveObject,dir,fileName)
    for _,p in ipairs(resolveObject:GetMediaStorage():GetFileList(dir)or{})do if normalize(basename(p))==normalize(fileName)then return true end end;return false
end
local function safeBase(resolveObject,dir,base)
    if not outputExists(resolveObject,dir,base..".mp4")then return base end
    local stamp=os.date("%Y%m%d_%H%M%S");local candidate=base.."_"..stamp;local number=2
    while outputExists(resolveObject,dir,candidate..".mp4")do candidate=base.."_"..stamp.."_"..tostring(number);number=number+1 end
    return candidate
end

local function queueAndRender(resolveObject,project,p,entries)
    stage("Render Queue")
    if #(project:GetRenderJobList()or{})~=0 then fail("Render queue must be empty.")end
    chooseMp4H264(project);project:SetCurrentRenderMode(0);if tonumber(project:GetCurrentRenderMode())~=0 then fail("Individual Clips mode failed.")end
    local ids={};local out=tostring(p.paths.output_dir);local suffix=tostring(p.output.suffix or "_Rec709_NeutralSafe")
    for _,entry in ipairs(entries)do
        project:SetCurrentTimeline(entry.timeline);local base=safeBase(resolveObject,out,stem(entry.name)..suffix)
        local settings={
            SelectAllFrames=true,TargetDir=out,CustomName=base,ExportVideo=true,ExportAudio=true,
            FormatWidth=tonumber(p.batch.width),FormatHeight=tonumber(p.batch.height),FrameRate=tonumber(p.batch.frame_rate),
            VideoQuality=tostring(p.output.quality or "Best"),AudioCodec=tostring(p.output.audio_codec or "aac"),
            AudioSampleRate=tonumber(p.output.audio_sample_rate or 48000),ReplaceExistingFilesInPlace=false
        }
        for key,v in pairs(settings)do local one={};one[key]=v;project:SetRenderSettings(one)end
        local id=project:AddRenderJob();if not id then fail("AddRenderJob failed: "..entry.name)end
        append(ids,tostring(id));append(state.jobs,tostring(id).." | "..entry.timeline:GetName());append(state.outputs,out.."/"..base..".mp4")
    end
    if #ids~=#entries then fail("Job count mismatch.")end
    local queued=project:GetRenderJobList()or{};if #queued~=#entries then fail("Queued job list count mismatch.")end
    for _,job in ipairs(queued)do
        local id=job.JobId or job.RenderJobId
        local geometry=tonumber(job.FormatWidth)==tonumber(p.batch.width)and tonumber(job.FormatHeight)==tonumber(p.batch.height)
        local fps=numberEquals(job.FrameRate,tonumber(p.batch.frame_rate))
        local media=compact(job.VideoFormat)=="mp4"and contains(compact(job.VideoCodec),"h264")
        local audio=job.IsExportAudio==true and normalize(job.AudioCodec)=="aac"and tonumber(job.AudioSampleRate)==tonumber(p.output.audio_sample_rate or 48000)
        local mode=contains(job.RenderMode,"individual")
        local target=pathKey(job.TargetDir)==pathKey(out)
        if not(id and geometry and fps and media and audio and mode and target)then fail("Queued render job verification failed.")end
    end
    if not project:StartRendering(ids,true)then fail("StartRendering failed.")end
    resolveObject:OpenPage("deliver");state.status="RENDERING_AUTHORIZED_"..string.upper(p.mode)
end

local function writeReport(trace)
    local lines={"# Sony S-Log3 AutoGrade report","","- Status: `"..state.status.."`","- Last stage: `"..state.stage.."`","","## Jobs",""}
    if #state.jobs==0 then append(lines,"- None")end;for _,v in ipairs(state.jobs)do append(lines,"- `"..v.."`")end
    append(lines,"");append(lines,"## Outputs");append(lines,"");if #state.outputs==0 then append(lines,"- None")end;for _,v in ipairs(state.outputs)do append(lines,"- `"..v.."`")end
    append(lines,"");append(lines,"## Errors");append(lines,"");if #state.errors==0 then append(lines,"- None")end;for _,v in ipairs(state.errors)do append(lines,"- "..v:gsub("[\r\n]"," "))end
    if trace and trace~=""then append(lines,"");append(lines,"```"..trace.."```")end
    local h=io.open(REPORT_PATH,"wb");if h then h:write(table.concat(lines,"\n"));h:close()end
end

local function main()
    local p=loadProfile();local resolveObject,manager,project=acquireObjects(p);verifyProject(project,p)
    local files=selectedFiles(p);local reference=referenceItem(project,p);local entries=createTargets(project,p,files)
    applyReference(project,reference,entries,p);if manager:SaveProject()~=true then fail("SaveProject failed before render.")end
    queueAndRender(resolveObject,project,p,entries)
end
local ok,trace=xpcall(main,tracebackHandler)
if not ok then state.status="ERROR_STOPPED";logLine("ERROR");value("error.stage",state.stage);value("error.traceback",trace)else logLine("SUCCESS")end
writeReport(ok and ""or trace);logLine("STOP");value("final.status",state.status)
