-- Sony SLog3 Production Batch.lua
-- One-trigger, one-clip-at-a-time production of immutable-DRX DNxHR masters.
-- Real paths, manifests, hashes, and authorization live only in ignored runtime.lua.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ROOT = TEMP_ROOT .. "/SonySLog3AutoGrade"
local RUNTIME_PATH = ROOT .. "/runtime.lua"
local LOG_PATH = ROOT .. "/production_batch.log"
local REPORT_PATH = ROOT .. "/production_batch_report.md"
local EMERGENCY_PATH = TEMP_ROOT .. "/SonySLog3AutoGrade_production_emergency.log"

local state = {status="STARTING",stage="bootstrap",project="",success=0,failed=0,skipped=0,review=0,clips={},errors={}}

local function append(path,text)local h=io.open(path,"ab");if not h then return false end;h:write(text);h:close();return true end
local function log(text)if not append(LOG_PATH,tostring(text or "").."\n")then append(EMERGENCY_PATH,tostring(text or "").."\n")end end
local function value(key,v)log(key.."="..tostring(v))end
local function stage(name)state.stage=name;log("STAGE="..name)end
local function fail(message)error(tostring(message),0)end
local function traceback(value)if debug and debug.traceback then return debug.traceback(tostring(value),2)end;return tostring(value)end
local function normalize(v)return string.lower(tostring(v or ""):gsub("%s+",""))end
local function pathKey(v)return string.lower(tostring(v or ""):gsub("\\","/"))end
local function contains(v,part)return normalize(v):find(normalize(part),1,true)~=nil end
local function numberEquals(a,b)local x,y=tonumber(a),tonumber(b);return x and y and math.abs(x-y)<0.001 end
local function fileSize(path)local h=io.open(path,"rb");if not h then return nil end;local n=h:seek("end");h:close();return n end
local function isSha(v)local s=tostring(v or "");return #s==64 and s:match("^[0-9A-Fa-f]+$")~=nil end
local function quote(v)return '"'..tostring(v):gsub('"','\\"')..'"'end
local function psLiteral(v)return "'"..tostring(v):gsub("'","''").."'"end
local function jsonEscape(v)
    return tostring(v or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\r","\\r"):gsub("\n","\\n")
end
local function writeJson(path,values)
    local keys={};for key in pairs(values)do keys[#keys+1]=key end;table.sort(keys)
    local lines={"{"};for index,key in ipairs(keys)do
        local v=values[key];local encoded
        if type(v)=="number"then encoded=tostring(v)elseif type(v)=="boolean"then encoded=v and "true"or"false"else encoded='"'..jsonEscape(v)..'"'end
        lines[#lines+1]='  "'..jsonEscape(key)..'": '..encoded..(index<#keys and ","or"")
    end;lines[#lines+1]="}"
    local h=io.open(path,"wb");if not h then fail("Cannot write worker config: "..path)end;h:write(table.concat(lines,"\n"));h:close()
end
local function readResult(path)
    local h=io.open(path,"rb");if not h then return nil end;local result={}
    for line in h:lines()do local key,v=line:match("^([^=]+)=(.*)$");if key then result[key]=v end end;h:close();return result
end
local function commandSucceeded(a,_,c)return a==true or a==0 or c==0 end
local function runWorker(profile,action,clip,extra)
    local token=tostring(clip.stem).."_"..string.lower(action)
    local configPath=ROOT.."/production_"..token..".json"
    local resultPath=ROOT.."/production_"..token..".result"
    os.remove(resultPath)
    local values={
        result_path=resultPath,ffmpeg_path=profile.production.ffmpeg_path,ffprobe_path=profile.production.ffprobe_path,
        stem=clip.stem,source_path=clip.source_path,working_path=clip.working_path,working_root=profile.production.working_root,
        final_path=clip.final_path,report_dir=profile.production.report_dir,
        expected_frames=clip.frames,expected_duration=clip.duration,
        protected_working_path=profile.production.protected_working_path,
        final_dir=profile.production.final_dir
    }
    for key,v in pairs(extra or{})do values[key]=v end
    writeJson(configPath,values)
    local cmd="powershell.exe -NoProfile -ExecutionPolicy Bypass -File "..quote(profile.production.worker_path)
        .." -Action "..quote(action).." -ConfigPath "..quote(configPath)
    local a,b,c=os.execute(cmd);value("worker."..token..".return1",a);value("worker."..token..".return2",b);value("worker."..token..".return3",c)
    local result=readResult(resultPath)
    if not commandSucceeded(a,b,c)or not result or result.status~="PASS"then
        fail("Worker "..action.." failed for "..clip.stem..": "..tostring(result and result.error or "no result"))
    end
    return result
end
local function waitSecond()if type(bmd)=="table"and type(bmd.wait)=="function"then bmd.wait(1000)else os.execute('powershell.exe -NoProfile -Command "Start-Sleep -Seconds 1"')end end
local function validatedItems(raw,validator)
    local result={};if type(raw)~="table"then return result end
    for _,item in ipairs(raw)do local ok=validator(item);if ok then result[#result+1]=item end end;return result
end
local function clipPath(item)
    local ok,v=pcall(function()return item:GetClipProperty("File Path")end);return ok and tostring(v or "")or""
end
local function findTimeline(project,name)
    for i=1,project:GetTimelineCount()do local t=project:GetTimelineByIndex(i);if t and tostring(t:GetName())==name then return t end end
end
local function exactTimelineItem(timeline,path)
    if tonumber(timeline:GetTrackCount("video"))~=1 then fail("Timeline must have exactly one video track.")end
    local items=validatedItems(timeline:GetItemListInTrack("video",1)or{},function(item)
        if type(item)~="userdata"then return false end
        local ok,pool=pcall(function()return item:GetMediaPoolItem()end);return ok and type(pool)=="userdata"
    end)
    if #items~=1 then fail("Timeline must have exactly one validated video item.")end
    if pathKey(clipPath(items[1]:GetMediaPoolItem()))~=pathKey(path)then fail("Timeline working source mismatch.")end
    if tonumber(timeline:GetTrackCount("audio"))~=1 then fail("Timeline must have exactly one audio track.")end
    local audio=validatedItems(timeline:GetItemListInTrack("audio",1)or{},function(item)
        if type(item)~="userdata"then return false end
        local ok,pool=pcall(function()return item:GetMediaPoolItem()end);return ok and type(pool)=="userdata"
    end)
    if #audio~=1 or pathKey(clipPath(audio[1]:GetMediaPoolItem()))~=pathKey(path)then fail("Timeline must contain one exact linked audio source.")end
    return items[1]
end
local function verifyFormat(project,p)
    for _,check in ipairs({
        {"timelinePlaybackFrameRate",p.batch.frame_rate},{"timelineFrameRate",p.batch.frame_rate},
        {"timelineResolutionWidth",p.batch.width},{"timelineResolutionHeight",p.batch.height}
    })do local actual=project:GetSetting(check[1]);value("project."..check[1],actual);if not numberEquals(actual,check[2])then fail("Project format mismatch: "..check[1])end end
end
local function setRead(project,key,candidates,validator)
    for _,candidate in ipairs(candidates)do
        local ok=project:SetSetting(key,candidate);local actual=project:GetSetting(key)
        value("setting."..key..".requested",candidate);value("setting."..key..".set",ok);value("setting."..key..".read",actual)
        if ok==true and validator(actual)then return end
    end;fail("RCM setting failed: "..key)
end
local function configureRcm(project)
    setRead(project,"colorScienceMode",{"davinciYRGBColorManagedv2","davinciYRGBColorManaged"},function(v)return contains(v,"managed")end)
    setRead(project,"rcmPresetMode",{"Custom"},function(v)return contains(v,"custom")end)
    setRead(project,"isAutoColorManage",{"0"},function(v)return tostring(v)=="0"or normalize(v)=="false"end)
    setRead(project,"colorSpaceInput",{"Sony S-Gamut3.Cine"},function(v)return contains(v,"s-gamut3.cine")end)
    setRead(project,"colorSpaceInputGamma",{"S-Log3"},function(v)return contains(v,"s-log3")end)
    setRead(project,"colorSpaceTimeline",{"DaVinci WG","DaVinci Wide Gamut"},function(v)return contains(v,"davinci")and(contains(v,"wg")or contains(v,"widegamut"))end)
    setRead(project,"colorSpaceTimelineGamma",{"DaVinci Intermediate"},function(v)return contains(v,"intermediate")end)
    setRead(project,"colorSpaceOutput",{"Rec.709"},function(v)return contains(v,"rec.709")or contains(v,"rec709")end)
    setRead(project,"colorSpaceOutputGamma",{"Gamma 2.4"},function(v)return contains(v,"2.4")end)
    log("RCM=ALL_MATCH")
end
local function renderQueueCount(project)
    local count=0;for _,job in ipairs(project:GetRenderJobList()or{})do if type(job)=="table"or type(job)=="userdata"then count=count+1 end end;return count
end
local function bootstrap(resolve,manager,p)
    stage("Production Project Bootstrap")
    runWorker(p,"ArtifactGate",p.production.clips[1],{artifact_path=p.project.template_path,expected_size=p.project.template_size,expected_sha256=p.project.template_sha256})
    if manager:GotoRootFolder()~=true then fail("Could not enter Project Library root folder.")end
    for _,name in ipairs(manager:GetProjectListInCurrentFolder()or{})do
        if tostring(name)==p.project.name then fail("Unique production project already exists; overwrite/reuse forbidden.")end
    end
    local current=manager:GetCurrentProject();if current then manager:SaveProject()end
    if manager:ImportProject(p.project.template_path,p.project.name)~=true then fail("ImportProject failed.")end
    if not manager:LoadProject(p.project.name)then fail("LoadProject failed after DRP import.")end
    local project=manager:GetCurrentProject();if not project or tostring(project:GetName())~=p.project.name then fail("Production project identity mismatch.")end
    verifyFormat(project,p)
    local root=project:GetMediaPool():GetRootFolder()
    local rootClips=validatedItems(root:GetClipList()or{},function(item)return type(item)=="userdata"end)
    local rootFolders=validatedItems(root:GetSubFolderList()or{},function(item)return type(item)=="userdata"end)
    if #rootClips~=0 or #rootFolders~=0 or tonumber(project:GetTimelineCount())~=0 or renderQueueCount(project)~=0 then fail("Imported production template is not blank.")end
    configureRcm(project);verifyFormat(project,p)
    if manager:SaveProject()~=true then fail("SaveProject failed after production bootstrap.")end
    state.project=p.project.name;return project
end
local function importWorking(project,path)
    local imported=validatedItems(project:GetMediaPool():ImportMedia({path})or{},function(item)return type(item)=="userdata"end)
    if #imported~=1 then fail("ImportMedia did not return exactly one item.")end
    if pathKey(clipPath(imported[1]))~=pathKey(path)then fail("Imported MediaPoolItem path mismatch.")end
    return imported[1]
end
local function createAndGrade(project,clip,p)
    local name="GRADE_"..clip.stem.."_NEUTRAL_SAFE"
    if findTimeline(project,name)then fail("Target timeline already exists: "..name)end
    local poolItem=importWorking(project,clip.working_path)
    local timeline=project:GetMediaPool():CreateTimelineFromClips(name,{poolItem});if not timeline then fail("CreateTimelineFromClips failed.")end
    local item=exactTimelineItem(timeline,clip.working_path)
    local graph=item:GetNodeGraph();if not graph then fail("GetNodeGraph failed.")end
    if graph:ResetAllGrades()~=true then fail("ResetAllGrades failed on new production target.")end
    local before=tonumber(graph:GetNumNodes())or-1
    if before<1 then fail("New production target has no default node graph.")end
    local applied=graph:ApplyGradeFromDRX(p.look.reference_drx_path,0);value("clip."..clip.stem..".ApplyGradeFromDRX",applied)
    if applied~=true then fail("ApplyGradeFromDRX failed.")end
    local after=tonumber(graph:GetNumNodes())or-1
    value("clip."..clip.stem..".nodes_before",before);value("clip."..clip.stem..".nodes_after",after)
    if after<1 then fail("Applied grade produced no valid node graph.")end
    return timeline,poolItem
end
local function presetVisible(project,name)
    for _,v in ipairs(project:GetRenderPresetList()or{})do if tostring(v)==name then return true end end
    return false
end
local function renderOne(project,manager,clip,timeline,p)
    if renderQueueCount(project)~=0 then fail("Render queue must be empty before each clip.")end
    if not presetVisible(project,p.render_preset.name)then fail("SYSTEMIC: verified render preset is not visible.")end
    if project:SetCurrentTimeline(timeline)~=true then fail("SetCurrentTimeline failed.")end
    if project:LoadRenderPreset(p.render_preset.name)~=true then fail("SYSTEMIC: LoadRenderPreset failed.")end
    local current=project:GetCurrentRenderFormatAndCodec()or{}
    if tostring(current.format)~=p.render_preset.expected_format_id or tostring(current.codec)~=p.render_preset.expected_codec_id then fail("SYSTEMIC: render preset format/codec mismatch.")end
    if tonumber(project:GetCurrentRenderMode())~=1 then fail("SYSTEMIC: render preset is not Single Clip.")end
    if project:SetRenderSettings({SelectAllFrames=true,TargetDir=p.production.final_dir,CustomName=clip.output_basename})~=true then fail("Task-only SetRenderSettings failed.")end
    local job=project:AddRenderJob();if not job then fail("AddRenderJob failed.")end
    if manager:SaveProject()~=true then fail("SaveProject failed before render.")end
    if project:StartRendering({job},false)~=true then fail("StartRendering failed.")end
    local started=os.time();while project:IsRenderingInProgress()==true do
        if os.difftime(os.time(),started)>tonumber(p.production.render_timeout_seconds)then fail("Render timeout.")end;waitSecond()
    end
    local status=project:GetRenderJobStatus(job)or{};local name=tostring(status.JobStatus or status.jobStatus or"")
    value("clip."..clip.stem..".render_status",name)
    if normalize(name)~="complete"and normalize(name)~="completed"then fail("Render Job did not complete.")end
    if project:DeleteRenderJob(tostring(job))~=true then fail("Completed render job cleanup failed.")end
    return job
end
local function outputPolicy(p,clip)
    local result=runWorker(p,"InspectFinal",clip)
    if result.output_policy=="NEW"then return "NEW"end
    if result.output_policy=="SKIP_VERIFIED_EXISTING"then return "SKIP_VERIFIED_EXISTING"end
    if result.output_policy~="RETRY_NON_OVERWRITE"then fail("Unknown output policy for "..clip.stem)end
    local retry=clip.stem.."_NEUTRAL_SAFE_MASTER_RETRY_"..os.date("%Y%m%d_%H%M%S")
    clip.output_basename=retry;clip.final_path=p.production.final_dir.."/"..retry..".mov";return "RETRY_NON_OVERWRITE"
end
local function processClip(project,manager,p,clip)
    stage("Output Policy")
    local policy=outputPolicy(p,clip);value("clip."..clip.stem..".output_policy",policy)
    if policy=="SKIP_VERIFIED_EXISTING"then state.skipped=state.skipped+1;state.clips[#state.clips+1]=clip.stem.." | SKIP_VERIFIED_EXISTING";return end
    local rate=tonumber(p.production.estimated_bytes_per_second)
    local required=math.floor(rate*tonumber(clip.duration)*2+15*1024*1024*1024)
    stage("Per-Clip Disk Gate")
    runWorker(p,"DiskGate",clip,{required_free_bytes=required})
    stage("Compatibility Transcode")
    runWorker(p,"Transcode",clip)
    stage("Resolve Import and Grade")
    local timeline=createAndGrade(project,clip,p)
    stage("Master Render")
    renderOne(project,manager,clip,timeline,p)
    stage("Final Postflight")
    local result=runWorker(p,"VerifyFinal",clip)
    stage("Verified Working Cleanup")
    runWorker(p,"DeleteWorking",clip)
    state.success=state.success+1
    state.clips[#state.clips+1]=clip.stem.." | PASS | "..tostring(result.final_path).." | "..tostring(result.final_sha256)
        .." | "..tostring(result.final_profile).." | "..tostring(result.final_pix_fmt)
        .." | "..tostring(result.final_width).."x"..tostring(result.final_height)
        .." | "..tostring(result.final_fps).." fps | "..tostring(result.final_frames).." frames | "..tostring(result.final_duration).." s"
    if manager:SaveProject()~=true then fail("SaveProject failed after clip completion.")end
end
local function writeReport()
    local lines={"# Sony S-Log3 production batch report","","- Status: `"..state.status.."`","- Project: `"..state.project.."`","- Success: `"..state.success.."`","- Failed: `"..state.failed.."`","- Skipped: `"..state.skipped.."`","- ReviewNeeded: `"..state.review.."`","","## Clips",""}
    for _,line in ipairs(state.clips)do lines[#lines+1]="- `"..line.."`"end
    lines[#lines+1]="";lines[#lines+1]="## Errors";lines[#lines+1]=""
    if #state.errors==0 then lines[#lines+1]="- None"else for _,e in ipairs(state.errors)do lines[#lines+1]="- "..e:gsub("[\r\n]"," ")end end
    lines[#lines+1]="";lines[#lines+1]="- FINAL DELIVERY H264 DISPLAY QC: `PENDING`"
    local h=io.open(REPORT_PATH,"wb");if h then h:write(table.concat(lines,"\n"));h:close()end
end
local function main()
    stage("Runtime")
    local loader,err=loadfile(RUNTIME_PATH);if not loader then fail("Cannot load runtime: "..tostring(err))end
    local ok,p=pcall(loader);if not ok or type(p)~="table"then fail("Runtime invalid: "..tostring(p))end
    state.profile=p
    value("deployment.production_commit",p.deployment and p.deployment.production_commit or"UNKNOWN")
    value("deployment.production_batch_sha256",p.deployment and p.deployment.production_batch_sha256 or"UNKNOWN")
    value("deployment.production_worker_sha256",p.deployment and p.deployment.production_worker_sha256 or"UNKNOWN")
    if p.mode~="production_batch"or not p.authorization or p.authorization.batch_approved~=true or p.authorization.start_rendering~=true then fail("Production authorization gate missing.")end
    if not p.production or #p.production.clips<1 or #p.production.clips~=tonumber(p.production.expected_clip_count)then fail("Production manifest count does not match explicit authorization.")end
    if p.batch.homogeneous_metadata_verified~=true or normalize(p.batch.gamma)~="s-log3"or normalize(p.batch.primaries)~="sonys-gamut3.cine"then fail("SYSTEMIC: verified homogeneous Sony input policy missing.")end
    log("INPUT_COLOR_POLICY=FROM_VERIFIED_ORIGINAL_SOURCE_METADATA")
    if not isSha(p.look.reference_drx_sha256)or fileSize(p.look.reference_drx_path)~=tonumber(p.look.reference_drx_size)then fail("SYSTEMIC: locked DRX declaration invalid.")end
    runWorker(p,"ArtifactGate",p.production.clips[1],{artifact_path=p.look.reference_drx_path,expected_size=p.look.reference_drx_size,expected_sha256=p.look.reference_drx_sha256})
    runWorker(p,"ArtifactGate",p.production.clips[1],{artifact_path=p.render_preset.export_path,expected_size=p.render_preset.export_size,expected_sha256=p.render_preset.sha256})
    runWorker(p,"PrepareDirectories",p.production.clips[1])
    runWorker(p,"DiskGate",p.production.clips[1],{required_free_bytes=p.production.initial_required_free_bytes})
    local appObject=rawget(_G,"app");local resolve=appObject and appObject:GetResolve()or nil;local manager=resolve and resolve:GetProjectManager()or nil
    if not manager then fail("SYSTEMIC: Resolve internal objects unavailable.")end
    local project=bootstrap(resolve,manager,p)
    local previousClass=nil;local consecutive=0
    for index,clip in ipairs(p.production.clips)do
        local subBatchSize=tonumber(p.production.sub_batch_size) or 10
        value("batch.index",index);value("batch.sub_batch",math.floor((index-1)/subBatchSize)+1)
        local clipOk,clipError=xpcall(function()processClip(project,manager,p,clip)end,traceback)
        if not clipOk then
            local message=tostring(clipError)
            local class=state.stage
            state.failed=state.failed+1;state.review=state.review+1;state.errors[#state.errors+1]=clip.stem.." | "..message;state.clips[#state.clips+1]=clip.stem.." | REVIEW_NEEDED"
            value("clip."..clip.stem..".error",message)
            if renderQueueCount(project)>0 then pcall(function()project:DeleteAllRenderJobs()end)end
            if message:find("SYSTEMIC:",1,true)or message:find("Disk gate failed",1,true)then fail(message)end
            if class==previousClass then consecutive=consecutive+1 else previousClass=class;consecutive=1 end
            if consecutive>=2 then fail("SYSTEMIC: two consecutive failures at "..class)end
        else previousClass=nil;consecutive=0 end
        state.status="RUNNING_"..tostring(index).."_OF_"..tostring(#p.production.clips)
        writeReport()
        if index%subBatchSize==0 or index==#p.production.clips then
            log("SUB_BATCH_"..tostring(math.floor((index-1)/subBatchSize)+1).."=COMPLETED")
            if manager:SaveProject()~=true then fail("SaveProject failed at sub-batch boundary.")end
        end
    end
    state.status=state.failed==0 and "FULL_PRODUCTION_BATCH_PASS"or"FULL_PRODUCTION_BATCH_COMPLETED_WITH_REVIEW"
    resolve:OpenPage("edit");manager:SaveProject()
end

log("");log("============================================================");log("PRODUCTION BATCH START");value("timestamp",os.date("%Y-%m-%d %H:%M:%S %z"))
local ok,err=xpcall(main,traceback);if not ok then state.status="SYSTEMIC_ERROR_STOPPED";state.errors[#state.errors+1]=tostring(err);value("error",err)end
writeReport();log("STOP");value("final.status",state.status)
if state.profile and state.profile.production and state.profile.production.report_path then
    local published,publishError=pcall(function()
        runWorker(state.profile,"PublishReport",state.profile.production.clips[1],{source_report=REPORT_PATH,destination_report=state.profile.production.report_path})
    end)
    value("report.publish",published and "PASS"or("FAIL: "..tostring(publishError)))
end
