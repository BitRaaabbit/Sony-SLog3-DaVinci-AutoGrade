-- Sony SLog3 Production Batch.lua
-- One-trigger, one-clip-at-a-time production of immutable-DRX DNxHR masters.
-- Real paths, manifests, hashes, and authorization live only in ignored runtime.lua.

local TEMP_ROOT = (os.getenv("TEMP") or "."):gsub("\\", "/")
local ROOT = TEMP_ROOT .. "/SonySLog3AutoGrade"
local RUNTIME_PATH = ROOT .. "/runtime.lua"
local LOG_PATH = ROOT .. "/production_batch.log"
local REPORT_PATH = ROOT .. "/production_batch_report.md"
local EMERGENCY_PATH = TEMP_ROOT .. "/SonySLog3AutoGrade_production_emergency.log"
local RESUME_STATE_PATH = ROOT .. "/production_resume_state.lua"

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
local function fileSize(path)
    if type(bmd)=="table"and type(bmd.readdir)=="function"then
        local ok,entries=pcall(function()return bmd.readdir(path)end)
        if ok and type(entries)=="table"then
            for _,entry in ipairs(entries)do if type(entry)=="table"and entry.IsDir~=true and tonumber(entry.Size)then return tonumber(entry.Size)end end
        end
    end
    local h=io.open(path,"rb");if not h then return nil end;local n=h:seek("end");h:close();return n
end
local function isSha(v)local s=tostring(v or "");return #s==64 and s:match("^[0-9A-Fa-f]+$")~=nil end
local function quoteLua(v)return string.format("%q",tostring(v or ""))end
local function waitSecond()
    if type(bmd)=="table"and type(bmd.wait)=="function"then bmd.wait(1000);return end
    local untilTime=os.clock()+1;while os.clock()<untilTime do end
end
local function loadPreparedManifest(p)
    local path=tostring(p.production.prepared_manifest_path or "")
    local loader,loadError=loadfile(path);if not loader then fail("SYSTEMIC: cannot load prepared working manifest: "..tostring(loadError))end
    local ok,manifest=pcall(loader);if not ok or type(manifest)~="table"then fail("SYSTEMIC: prepared working manifest is invalid: "..tostring(manifest))end
    if manifest.status~="EXTERNAL_PRETRANSCODE_PASS"or tonumber(manifest.total)~=#p.production.clips or tonumber(manifest.success)~=#p.production.clips or tonumber(manifest.review_needed)~=0 then
        fail("SYSTEMIC: prepared working manifest summary is not an all-PASS batch.")
    end
    if not isSha(p.production.prepared_manifest_sha256)then fail("SYSTEMIC: prepared manifest SHA-256 attestation is missing.")end
    local byStem={}
    for _,entry in ipairs(manifest.entries or{})do
        local stem=tostring(entry.stem or "")
        if stem==""or byStem[stem]then fail("SYSTEMIC: prepared manifest has missing/duplicate stem.")end
        if entry.working_preflight_status~="PASS"or not isSha(entry.working_sha256)or tonumber(entry.working_size or 0)<=0 then fail("SYSTEMIC: prepared working entry is not PASS: "..stem)end
        if tostring(entry.codec)~="dnxhd"or tostring(entry.profile)~="DNXHR HQX"or tostring(entry.pix_fmt)~="yuv422p10le"then fail("SYSTEMIC: prepared working codec mismatch: "..stem)end
        if tonumber(entry.width)~=tonumber(p.batch.width)or tonumber(entry.height)~=tonumber(p.batch.height)or not numberEquals(entry.fps,p.batch.frame_rate)then fail("SYSTEMIC: prepared working format mismatch: "..stem)end
        byStem[stem]=entry
    end
    for _,clip in ipairs(p.production.clips)do
        local entry=byStem[tostring(clip.stem)];if not entry then fail("SYSTEMIC: prepared manifest missing clip: "..tostring(clip.stem))end
        if tostring(entry.canonical_original_path or "")==""or tostring(clip.canonical_source_path or "")==""then fail("SYSTEMIC: canonical original identity is missing: "..clip.stem)end
        if pathKey(entry.canonical_original_path)~=pathKey(clip.canonical_source_path)or tonumber(entry.frames)~=tonumber(clip.frames)or not numberEquals(entry.duration,clip.duration)then fail("SYSTEMIC: prepared manifest canonical original identity mismatch: "..clip.stem)end
        if pathKey(entry.final_path)~=pathKey(clip.final_path)then fail("SYSTEMIC: prepared manifest final-path identity mismatch: "..clip.stem)end
        if entry.final_preflight_status~="ABSENT"and entry.final_preflight_status~="EXISTS"then fail("SYSTEMIC: prepared manifest final-path status is invalid: "..clip.stem)end
        clip.working_path=tostring(entry.working_path);clip.working_sha256=tostring(entry.working_sha256);clip.working_size=tonumber(entry.working_size)
        clip.working_preflight_status="PASS";clip.final_preflight_status=tostring(entry.final_preflight_status or "")
    end
    log("PREPARED_WORKING_MANIFEST=ALL_PASS")
end
local function loadResumeState()
    local loader=loadfile(RESUME_STATE_PATH);if not loader then return {schema_version=1,grades={},outputs={}}end
    local ok,result=pcall(loader)
    if not ok or type(result)~="table"or tonumber(result.schema_version)~=1 then fail("SYSTEMIC: private production resume state is invalid.")end
    result.grades=type(result.grades)=="table"and result.grades or{}
    result.outputs=type(result.outputs)=="table"and result.outputs or{}
    return result
end
local function saveResumeState(resume)
    local lines={"return {","  schema_version = 1,","  grades = {"}
    local gradeKeys={};for stem in pairs(resume.grades or{})do gradeKeys[#gradeKeys+1]=stem end;table.sort(gradeKeys)
    for _,stem in ipairs(gradeKeys)do local g=resume.grades[stem];lines[#lines+1]="    ["..quoteLua(stem).."] = { timeline_name="..quoteLua(g.timeline_name)..", working_path="..quoteLua(g.working_path)..", working_sha256="..quoteLua(g.working_sha256)..", reference_drx_sha256="..quoteLua(g.reference_drx_sha256)..", node_count="..tostring(tonumber(g.node_count)or-1).." },"end
    lines[#lines+1]="  },";lines[#lines+1]="  outputs = {"
    local outputKeys={};for stem in pairs(resume.outputs or{})do outputKeys[#outputKeys+1]=stem end;table.sort(outputKeys)
    for _,stem in ipairs(outputKeys)do local o=resume.outputs[stem];lines[#lines+1]="    ["..quoteLua(stem).."] = { path="..quoteLua(o.path)..", size="..tostring(tonumber(o.size)or-1)..", status="..quoteLua(o.status).." },"end
    lines[#lines+1]="  }";lines[#lines+1]="}"
    local h=io.open(RESUME_STATE_PATH,"wb");if not h then fail("SYSTEMIC: cannot write private production resume state.")end
    h:write(table.concat(lines,"\n"),"\n");h:close()
end
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
local function verifyRcmReadOnly(project,prefix,successLine)
    local checks={
        {"colorScienceMode",function(v)return contains(v,"color")and contains(v,"managed")end},
        {"rcmPresetMode",function(v)return contains(v,"custom")end},
        {"isAutoColorManage",function(v)return tostring(v)=="0"or normalize(v)=="false"end},
        {"separateColorSpaceAndGamma",function(v)return tostring(v)=="1"or normalize(v)=="true"end},
        {"colorSpaceInput",function(v)return contains(v,"s-gamut3.cine")end},
        {"colorSpaceInputGamma",function(v)return contains(v,"s-log3")end},
        {"colorSpaceTimeline",function(v)return contains(v,"davinci")and(contains(v,"wg")or contains(v,"widegamut"))end},
        {"colorSpaceTimelineGamma",function(v)return contains(v,"intermediate")end},
        {"colorSpaceOutput",function(v)return contains(v,"rec.709")or contains(v,"rec709")end},
        {"colorSpaceOutputGamma",function(v)return contains(v,"2.4")end}
    }
    for _,entry in ipairs(checks)do
        local key,validator=entry[1],entry[2]
        local readCallOk,actual=pcall(function()return project:GetSetting(key)end)
        local matched=readCallOk and validator(actual)
        value(prefix.."."..key..".read_call_ok",readCallOk)
        value(prefix.."."..key..".read_back",actual)
        value(prefix.."."..key..".compare",matched and "MATCH"or"MISMATCH")
        if not matched then fail("Read-only RCM verification failed for "..key.."; actual="..tostring(actual))end
    end
    log(successLine)
end
local function renderJobs(project)
    local jobs={}
    for _,job in ipairs(project:GetRenderJobList()or{})do
        if type(job)=="table"and tostring(job.JobId or "")~=""then jobs[#jobs+1]=job end
    end
    return jobs
end
local function renderQueueCount(project)
    return #renderJobs(project)
end
local function renderStatusText(status)
    if type(status)=="table"then return tostring(status.JobStatus or status.jobStatus or"")end
    return tostring(status or"")
end
local function clearCloneRenderQueue(project)
    local jobs=renderJobs(project)
    value("clone.render_queue_count_before",#jobs)
    if project:IsRenderingInProgress()==true then fail("SYSTEMIC: cloned project reports rendering in progress.")end
    for index,job in ipairs(jobs)do
        local statusInfo=project:GetRenderJobStatus(tostring(job.JobId))or{}
        local status=tostring(statusInfo.JobStatus or statusInfo.jobStatus or job.JobStatus or job.jobStatus or "")
        value("clone.render_job."..index..".id",job.JobId)
        value("clone.render_job."..index..".status",status)
        local normalized=normalize(status)
        if normalized:find("rendering",1,true)or normalized:find("active",1,true)or normalized:find("inprogress",1,true)then
            fail("SYSTEMIC: cloned project contains an active Render Job.")
        end
    end
    if #jobs>0 and project:DeleteAllRenderJobs()~=true then fail("SYSTEMIC: DeleteAllRenderJobs failed in production clone.")end
    local remaining=renderQueueCount(project);value("clone.render_queue_count_after",remaining)
    if remaining~=0 then fail("SYSTEMIC: production clone Render Queue is not empty after cleanup.")end
    log("PRODUCTION_CLONE_RENDER_QUEUE=EMPTY")
end
local function clearInactiveResumeRenderQueue(project)
    if project:IsRenderingInProgress()==true then fail("SYSTEMIC: existing production project is still rendering.")end
    local jobs=renderJobs(project);value("resume.render_queue_count_before",#jobs)
    for index,job in ipairs(jobs)do
        local callOk,statusInfo=pcall(function()return project:GetRenderJobStatus(tostring(job.JobId))end)
        value("resume.render_job."..index..".status_call_ok",callOk)
        value("resume.render_job."..index..".status_raw",callOk and renderStatusText(statusInfo)or statusInfo)
    end
    if #jobs>0 and project:DeleteAllRenderJobs()~=true then fail("SYSTEMIC: inactive resume Render Queue cleanup failed.")end
    if renderQueueCount(project)~=0 then fail("SYSTEMIC: resume Render Queue is not empty after cleanup.")end
    log("PRODUCTION_RESUME_RENDER_QUEUE=EMPTY")
end
local function bootstrap(resolve,manager,p)
    stage("Verified Reference Project Clone Bootstrap")
    if tostring(p.project.bootstrap_method)~="verified_reference_project_clone"then fail("SYSTEMIC: production bootstrap method is not verified_reference_project_clone.")end
    local referenceName=tostring(p.project.reference_project_name or "")
    if referenceName==""or referenceName==tostring(p.project.name)then fail("SYSTEMIC: invalid reference/production project identity declaration.")end
    if manager:GotoRootFolder()~=true then fail("Could not enter Project Library root folder.")end
    local referenceVisible,productionVisible=false,false
    for _,name in ipairs(manager:GetProjectListInCurrentFolder()or{})do
        if tostring(name)==referenceName then referenceVisible=true end
        if tostring(name)==p.project.name then productionVisible=true end
    end
    if productionVisible then
        if p.project.allow_load_existing~=true or p.project.resume_existing_production~=true then fail("Existing production project is not explicitly authorized for safe resume.")end
        local project=manager:LoadProject(p.project.name)
        if not project or tostring(project:GetName())~=tostring(p.project.name)then fail("SYSTEMIC: exact existing production project could not be loaded.")end
        verifyFormat(project,p)
        verifyRcmReadOnly(project,"production_resume_rcm","PRODUCTION_RESUME_RCM=ALL_MATCH")
        clearInactiveResumeRenderQueue(project)
        state.project=p.project.name;log("REUSE_EXISTING_PRODUCTION_PROJECT");return project
    end
    if not referenceVisible then fail("SYSTEMIC: exact verified Reference Project is not visible in Project Library root.")end
    local current=manager:GetCurrentProject();if current then manager:SaveProject()end
    local reference=manager:LoadProject(referenceName)
    if not reference or tostring(reference:GetName())~=referenceName then fail("SYSTEMIC: could not load exact verified Reference Project.")end
    verifyFormat(reference,p)
    verifyRcmReadOnly(reference,"reference_project_rcm","REFERENCE_PROJECT_RCM=VERIFIED")
    if manager:SaveProject()~=true then fail("SYSTEMIC: SaveProject failed for verified Reference Project.")end
    local seedPath=tostring(p.production.seed_dir).."/SonySLog3_Verified_Production_Seed_"..os.date("%Y%m%d_%H%M%S")..".drp"
    if fileSize(seedPath)~=nil then fail("SYSTEMIC: production seed DRP collision.")end
    local exportOk=manager:ExportProject(referenceName,seedPath,true)
    value("production_seed.export_return",exportOk);value("production_seed.path",seedPath)
    if exportOk~=true or not fileSize(seedPath)or fileSize(seedPath)<=0 then fail("SYSTEMIC: verified Reference Project ExportProject failed.")end
    value("production_seed.size",fileSize(seedPath))
    if manager:GotoRootFolder()~=true then fail("Could not return to Project Library root folder.")end
    if manager:ImportProject(seedPath,p.project.name)~=true then fail("ImportProject failed for verified production seed.")end
    if not manager:LoadProject(p.project.name)then fail("LoadProject failed after DRP import.")end
    local project=manager:GetCurrentProject();if not project or tostring(project:GetName())~=p.project.name then fail("Production project identity mismatch.")end
    verifyFormat(project,p)
    verifyRcmReadOnly(project,"production_rcm_inherited","PRODUCTION_RCM_INHERITED_VERIFY=ALL_MATCH")
    clearCloneRenderQueue(project)
    if manager:SaveProject()~=true then fail("SaveProject failed after production clone bootstrap.")end
    state.project=p.project.name;return project
end
local function importWorking(project,path)
    local imported=validatedItems(project:GetMediaPool():ImportMedia({path})or{},function(item)return type(item)=="userdata"end)
    if #imported~=1 then fail("ImportMedia did not return exactly one item.")end
    if pathKey(clipPath(imported[1]))~=pathKey(path)then fail("Imported MediaPoolItem path mismatch.")end
    return imported[1]
end
local function createAndGrade(project,clip,p,resume)
    local name="PROD_"..clip.stem.."_NEUTRAL_SAFE"
    local existing=findTimeline(project,name)
    if existing then
        local attestation=resume.grades[clip.stem]
        if type(attestation)~="table"or tostring(attestation.timeline_name)~=name or pathKey(attestation.working_path)~=pathKey(clip.working_path)or tostring(attestation.working_sha256)~=tostring(clip.working_sha256)or tostring(attestation.reference_drx_sha256)~=tostring(p.look.reference_drx_sha256)then fail("Existing production timeline lacks an exact private grade attestation: "..name)end
        local item=exactTimelineItem(existing,clip.working_path);local graph=item:GetNodeGraph();local nodes=graph and tonumber(graph:GetNumNodes())or-1
        if nodes<1 or nodes~=tonumber(attestation.node_count)then fail("Existing production timeline grade graph does not match its attestation: "..name)end
        value("clip."..clip.stem..".resume_nodes",nodes);log("REUSE_EXISTING_PROD_TIMELINE="..clip.stem)
        return existing,item:GetMediaPoolItem()
    end
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
    resume.grades[clip.stem]={timeline_name=name,working_path=clip.working_path,working_sha256=clip.working_sha256,reference_drx_sha256=p.look.reference_drx_sha256,node_count=after};saveResumeState(resume)
    return timeline,poolItem
end
local function presetVisible(project,name)
    for _,v in ipairs(project:GetRenderPresetList()or{})do if tostring(v)==name then return true end end
    return false
end
local function waitForStableOutput(path,p,stem)
    local required=tonumber(p.production.output_stability_checks)or 3
    local interval=tonumber(p.production.output_stability_interval_seconds)or 2
    local timeout=tonumber(p.production.output_stability_timeout_seconds)or 120
    local started=os.time();local last=nil;local stable=0
    while os.difftime(os.time(),started)<=timeout do
        local size=fileSize(path);value("clip."..stem..".output_size_observed",size or"MISSING")
        if size and size>0 then if size==last then stable=stable+1 else stable=0;last=size end else stable=0;last=nil end
        if stable>=required then log("RESOLVE_RENDER_OUTPUT_READY="..stem);return size end
        for _=1,interval do waitSecond()end
    end
    fail("Rendered output did not become present and size-stable before timeout.")
end
local function renderOne(project,manager,clip,timeline,p,resume)
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
    local statusCallOk,status=pcall(function()return project:GetRenderJobStatus(job)end)
    local name=statusCallOk and renderStatusText(status)or""
    value("clip."..clip.stem..".render_status_call_ok",statusCallOk);value("clip."..clip.stem..".render_status_raw",statusCallOk and name or status)
    log("RENDER_JOB_STATUS=DIAGNOSTIC_ONLY")
    local outputSize=waitForStableOutput(clip.final_path,p,clip.stem)
    resume.outputs[clip.stem]={path=clip.final_path,size=outputSize,status="RENDER_COMPLETED_PENDING_EXTERNAL_POSTFLIGHT"};saveResumeState(resume)
    if project:DeleteRenderJob(tostring(job))~=true then
        value("clip."..clip.stem..".DeleteRenderJob",false)
        if project:DeleteAllRenderJobs()~=true or renderQueueCount(project)~=0 then fail("SYSTEMIC: completed render job cleanup failed.")end
    end
    return job
end
local function verifiedFinal(p,clip)
    local verified=type(p.production.verified_finals)=="table"and p.production.verified_finals[clip.stem]or nil
    if type(verified)~="table"or tostring(verified.status)~="PASS"then return false end
    if pathKey(verified.path)~=pathKey(clip.final_path)or not isSha(verified.sha256)or tonumber(verified.size or 0)<=0 or tonumber(verified.frames)~=tonumber(clip.frames)or not numberEquals(verified.duration,clip.duration)then fail("SYSTEMIC: external verified Final attestation mismatch: "..clip.stem)end
    local actual=fileSize(clip.final_path);if actual~=tonumber(verified.size)then fail("SYSTEMIC: externally verified Final size changed: "..clip.stem)end
    return true
end
local function outputPolicy(p,clip)
    if verifiedFinal(p,clip)then log("SKIP_VERIFIED_FINAL="..clip.stem);return"SKIP_VERIFIED_FINAL"end
    if fileSize(clip.final_path)~=nil then fail("Unverified final target exists; overwrite forbidden: "..clip.final_path)end
    return "NEW"
end
local function processClip(project,manager,p,clip,resume)
    stage("Output Policy")
    local policy=outputPolicy(p,clip);value("clip."..clip.stem..".output_policy",policy)
    if policy=="SKIP_VERIFIED_FINAL"then state.skipped=state.skipped+1;state.success=state.success+1;state.clips[#state.clips+1]=clip.stem.." | EXTERNAL_FINAL_PASS | "..tostring(clip.final_path);return end
    if clip.working_preflight_status~="PASS"then fail("SYSTEMIC: clip is not externally prepared: "..clip.stem)end
    stage("Resolve Import and Grade")
    local timeline=createAndGrade(project,clip,p,resume)
    stage("Master Render")
    renderOne(project,manager,clip,timeline,p,resume)
    stage("Resolve Render Complete / External Postflight Pending")
    value("clip."..clip.stem..".external_postflight","PENDING")
    state.success=state.success+1
    state.clips[#state.clips+1]=clip.stem.." | RENDER_COMPLETED_PENDING_EXTERNAL_POSTFLIGHT | "..tostring(clip.final_path)
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
    if p.production.external_artifact_preflight_status~="PASS"then fail("SYSTEMIC: external DRX/render-preset artifact preflight is missing.")end
    if p.look.reference_drx_sha256~=p.production.prepared_reference_drx_sha256 or p.render_preset.sha256~=p.production.prepared_render_preset_sha256 then fail("SYSTEMIC: prepared artifact SHA-256 attestations do not match runtime assets.")end
    loadPreparedManifest(p)
    local resume=loadResumeState()
    local appObject=rawget(_G,"app");local resolve=appObject and appObject:GetResolve()or nil;local manager=resolve and resolve:GetProjectManager()or nil
    if not manager then fail("SYSTEMIC: Resolve internal objects unavailable.")end
    local project=bootstrap(resolve,manager,p)
    for index,clip in ipairs(p.production.clips)do
        local subBatchSize=tonumber(p.production.sub_batch_size) or 10
        value("batch.index",index);value("batch.sub_batch",math.floor((index-1)/subBatchSize)+1)
        local clipOk,clipError=xpcall(function()processClip(project,manager,p,clip,resume)end,traceback)
        if not clipOk then
            local message=tostring(clipError)
            local class=state.stage
            state.failed=state.failed+1;state.review=state.review+1;state.errors[#state.errors+1]=clip.stem.." | "..message;state.clips[#state.clips+1]=clip.stem.." | REVIEW_NEEDED"
            value("clip."..clip.stem..".error",message)
            if renderQueueCount(project)>0 then pcall(function()project:DeleteAllRenderJobs()end)end
            if message:find("SYSTEMIC:",1,true)then fail(message)end
        end
        state.status="RUNNING_"..tostring(index).."_OF_"..tostring(#p.production.clips)
        writeReport()
        if index%subBatchSize==0 or index==#p.production.clips then
            log("SUB_BATCH_"..tostring(math.floor((index-1)/subBatchSize)+1).."=COMPLETED")
            if manager:SaveProject()~=true then fail("SaveProject failed at sub-batch boundary.")end
        end
    end
    state.status=state.failed==0 and "RESOLVE_PRODUCTION_RENDER_PASS_PENDING_EXTERNAL_POSTFLIGHT"or"RESOLVE_PRODUCTION_RENDER_COMPLETED_WITH_REVIEW"
    resolve:OpenPage("edit");manager:SaveProject()
end

log("");log("============================================================");log("PRODUCTION BATCH START");value("timestamp",os.date("%Y-%m-%d %H:%M:%S %z"))
local ok,err=xpcall(main,traceback);if not ok then state.status="SYSTEMIC_ERROR_STOPPED";state.errors[#state.errors+1]=tostring(err);value("error",err)end
writeReport();log("STOP");value("final.status",state.status)
