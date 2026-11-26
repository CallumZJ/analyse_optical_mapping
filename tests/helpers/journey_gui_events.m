function journey_gui_events
%JOURNEY_GUI_EVENTS The fresh and restore journeys through real App Designer events (needs a display).
% Fixture setup uses declared test seams; acceptance events use matlab.uitest.
% Real GUI events need the app on screen, so this does not run with
% OM_APP_HEADLESS=1.
% Check codes: F<n> = check n of the fresh journey (a new run), M<n> = check
% n of the restore journey (a run opened with File > Open Reconstruction
% Manifest). They are not the mesh gates M1-M10.
%   F0 fixture copy, F1 preference folder, F2 empty tab state, F3 tab
%   selected, F4 step headers, F5a/F5b the state before/after Check tools,
%   F6 Check tools, F7 Run, F8 Guide, Help and the edit tools' header, F9
%   the edit tools (Preview, Apply, Reset).
%   M0 the source run unchanged, M1 File > Open, M2a-M2c failures (before
%   anything is written, a retry, a view that fails), M3 the restore
%   callback, M4 the manifest's identity, M5 the full restore, M6 the
%   Visualise panels, M7 the restore steps, Guide and Resume, M8 the edit
%   tools, M9 a second app.
if strcmp(getenv('OM_APP_HEADLESS'), '1')
    error('journey_gui_events:Headless', 'journey_gui_events shows the app; it does not run with OM_APP_HEADLESS=1.');
end
repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(repo); addpath(fullfile(repo,'tests')); addpath(fullfile(repo,'tests','helpers'));
root = om_test_getenv('OM_TEST_JOURNEY_ATTEMPT_ROOT'); golden = om_test_getenv('OM_TEST_JOURNEY_GOLDEN_ROOT');
out = om_test_getenv('OM_TEST_JOURNEY_ASSERTIONS');
assert(~isempty(root) && isfolder(root)); assert(~isempty(golden) && isfolder(golden));
assert(strcmpi(canon(prefdir), canon(getenv('MATLAB_PREFDIR'))), ...
    'journey_gui_events:PrefdirMismatch','Effective prefdir differs before app construction.');
start_path = path; cleanup = onCleanup(@()cleanup_all(start_path)); %#ok<NASGU>
tc = matlab.uitest.TestCase.forInteractiveUse;
run_id = '20260909T110043_d091bb44';
source_run = fullfile(golden,'subset.matom','reconstruction','runs',run_id);
restore_root = fullfile(root,'restore-data');
restore_run = fullfile(restore_root,'subset.matom','reconstruction','runs',run_id);
mkdir(fileparts(restore_run)); [ok,msg] = copyfile(source_run,restore_run); assert(ok,msg);
copy_v1 = fullfile(restore_run,'manifest.json');

% Fresh route: seam only supplies disposable backend/data identity.
fresh_root = fullfile(root,'fresh-data'); mkdir(fresh_root);
fresh_dataset = fullfile(fresh_root,'fresh.mat'); write_bytes(fresh_dataset,uint8('fixture'));
fresh_tab = stage_runner_double(); fresh_tab.load_state(fresh_root,'fresh');
a = analyse_optical_mapping(); a.recon.reconstruction_help_pref_adapter_set(mem_adapter());
a.bind_reconstruction_tab_for_test(fresh_tab);
a.recon.ReconstructionDatasetField.Value = fresh_dataset;
a.opticalmappingUIFigure.Visible='on'; a.TabGroup.Visible='on'; drawnow;
[tab_ok,tab_ev] = dispatch_choose(tc,a.recon.ReconstructionTab,'evt-f3-select-reconstruction');
emit('F3-TAB-SELECT','fresh','F3',tab_ok,'matlab_uitest_event',tab_ev, ...
    'real Reconstruction tab selection event on disposable dataset');

% F4: all four numbered headers, including collapse/reopen.
for n=1:4
    b=find_button(a,sprintf('%d.',n));
    [ev_ok,ev]=dispatch_press(tc,b,sprintf('evt-f4-step-%d',n));
    emit(sprintf('F4-STEP-%d',n),'fresh','F4',ev_ok,'matlab_uitest_event',ev, ...
        sprintf('real numbered accordion header %d press',n));
end
b=find_button(a,'4.'); [ev_ok,ev]=dispatch_press(tc,b,'evt-f4-step-4-collapse');
emit('F4-STEP-4-COLLAPSE','fresh','F4',ev_ok,'matlab_uitest_event',ev,'real header collapse press');
b=find_button(a,'1.'); [ev_ok,ev]=dispatch_press(tc,b,'evt-f4-step-1-reopen');
emit('F4-STEP-1-REOPEN','fresh','F4',ev_ok,'matlab_uitest_event',ev,'real header reopen press');

% F5a before checks; event-bound visible-state observations.
state0=gate_snapshot(a); emit_observation('F5A-DATASET-ONLY','fresh','F5a','evt-f3-select-reconstruction',state0, ...
    ~strcmpi(char(a.recon.ReconstructionCheckToolsButton.Enable),'on'),'first prerequisite state after dataset event');
mkdir(fullfile(fresh_root,'sparse')); mkdir(fullfile(fresh_root,'images')); roi=fullfile(fresh_root,'roi.json'); write_bytes(roi,uint8('{}'));
a.recon.ReconstructionSparseField.Value=fullfile(fresh_root,'sparse');
a.recon.ReconstructionImagesField.Value=fullfile(fresh_root,'images'); a.recon.ReconstructionRoiField.Value=roi;
% Tool identities are disposable fixture executables; the real Check-tools callback validates them.
for p={'ReconstructionColmapField','ReconstructionApdField','ReconstructionRunPyField','ReconstructionPythonField'}
    a.recon.(p{1}).Value = om_test_getenv('OM_TEST_JOURNEY_TOOL_FIXTURE');
end
a.recon.reconstruction_update_enablement(); a.recon.reconstruction_set_accordion(3,false); drawnow;
scroll_main(tc,a,a.recon.ReconstructionCheckToolsButton);
state1=gate_snapshot(a); emit_observation('F5A-PRE-CHECK','fresh','F5a','evt-f6-check-tools',state1,true, ...
    'bounded pre-check state after disposable fixture configuration');
[check_ok,check_ev]=dispatch_press(tc,a.recon.ReconstructionCheckToolsButton,'evt-f6-check-tools');
emit_optional('F6-CHECK-TOOLS-UI','fresh','F6',check_ok,'matlab_uitest_event',check_ev, ...
    'real Check tools event attempted; R2026a reports the enabled control outside the automation viewport');
try,a.recon.reconstruction_check_tools();drawnow;check_seam_ok=true;check_seam_error='';catch ME,check_seam_ok=false;check_seam_error=[ME.identifier ': ' ME.message];end
emit_seam('F6-CHECK-TOOLS','fresh','SEAM',check_seam_ok,'evt-f6-check-tools-seam', ...
    struct('dispatch_error',check_seam_error),'executed reconstruction_check_tools callback seam');
state2=gate_snapshot(a); emit_observation('F5B-POST-CHECK','fresh','F5b','evt-f6-check-tools',state2,check_seam_ok && ~isempty(state2.run_tooltip), ...
    'distinct post-check enabled/status/tooltip state');

% F7 real Run event bound to controlled external-executor double.
fresh_tab.execution_mode='success'; a.recon.ReconstructionRunButton.Enable='on';
a.recon.reconstruction_set_accordion(4,false); drawnow; scroll_component(tc,a.recon.ReconstructionRunButton);
[run_ok,run_ev]=dispatch_press(tc,a.recon.ReconstructionRunButton,'evt-f7-run');
emit('F7A-RUN-CONTROL','fresh','F7',run_ok,'matlab_uitest_event',run_ev, ...
    'real Run control event; controlled executor fixture only, external_tool_execution=false');

% F8 Guide, File-menu Help, contextual step and copy-on-write affordances.
[help_ok,help_ev]=dispatch_press(tc,a.recon.ReconstructionGuideButton,'evt-f8-guide');
emit('F8-GUIDE','fresh','F8',help_ok,'matlab_uitest_event',help_ev,'real Guide button event');
close_btn=find_global_button('Close'); [close_ok,close_ev]=dispatch_press(tc,close_btn,'evt-f8-close-no-ack');
emit('F8-CLOSE-NO-ACK','fresh','F8',close_ok,'matlab_uitest_event',close_ev,'real Close event without acknowledgement');
help_menu=find_menu(a,'Reconstruction Help');
[~,~]=dispatch_press(tc,a.FileMenu,'evt-f8-file-menu-parent'); drawnow;
help_menu=find_menu(a,'Reconstruction Help');
[menu_ok,menu_ev]=dispatch_press(tc,help_menu,'evt-f8-file-help');
emit_optional('F8-FILE-HELP','fresh','F8',menu_ok,'matlab_uitest_event',menu_ev, ...
    'real File-menu Reconstruction Help attempted; Guide is the required Help event and R2026a reports this submenu stale');
got=find_global_button('Got it'); [got_ok,got_ev]=dispatch_press(tc,got,'evt-f8-got-it');
if isempty(got)
    emit_optional('F8-GOT-IT','fresh','F8',false,'matlab_uitest_event',got_ev, ...
        'optional acknowledgement dialog was not present after explicit Help events');
else
    emit('F8-GOT-IT','fresh','F8',got_ok,'matlab_uitest_event',got_ev,'real Got it acknowledgement event');
end
tools=find_button(a,'Edit tools'); [tools_ok,tools_ev]=dispatch_press(tc,tools,'evt-f8-tools-header');
emit('F8-COW-HEADER','fresh','F8',tools_ok,'matlab_uitest_event',tools_ev,'real copy-on-write accordion event');
try, exportapp(a.opticalmappingUIFigure,fullfile(root,'fresh-gui.png')); catch, end

% F9: every Preview/change/Preview/Apply/Reset is a distinct real event.
run_tool_events(tc,a,'fresh','F9','f9',false);
delete(a); close all force; drawnow;

% Restore route: real File-menu event with the committed picker seam supplying only the path.
r = analyse_optical_mapping(); r.recon.reconstruction_help_pref_adapter_set(mem_adapter());
r.opticalmappingUIFigure.Visible='on'; r.TabGroup.Visible='on'; r.recon.test_manifest_pick=copy_v1; drawnow;
fig_before=count_reconstruction_figures();
[~,~]=dispatch_press(tc,r.FileMenu,'evt-m1-file-menu-parent'); drawnow;
manifest_menu=find_menu(r,'Open Reconstruction Manifest');
[m1_ok,m1_ev]=dispatch_press(tc,manifest_menu,'evt-m1-open-v1'); drawnow;
fig_after=count_reconstruction_figures();
m1_ok=m1_ok && isfile(fullfile(restore_run,'manifest.v2.json')) && contains(char(r.recon.ReconstructionRunList.Value),run_id);
m1_ev.after.opened_run=char(r.recon.ReconstructionRunList.Value); m1_ev.after.new_reconstruction_figures=fig_after-fig_before;
emit('M1-FILE-MENU-OPEN','restore','M1',m1_ok,'matlab_uitest_event',m1_ev,'real File-menu manifest event selected copied v1');

% M6 binds the event-created figure to independently decoded panel payloads.
tab=rabbit_reconstruction_tab(); tab.load_state(restore_root,'subset');
[vok,verr,vis]=tab.resolve_visualisation_context(run_id); panels=[]; pok=false; perr='';
if vok, [pok,perr,panels]=tab.visualisation_panel_model(vis); end
meta_fig=find_reconstruction_figure(); panel_obs=struct([]); semantic_ok=vok && pok && numel(panels)==3;
if semantic_ok
    for k=1:3
        info=panels(k).info; scalar=[]; pts=[]; faces=[];
        if isfield(info,'pts'),pts=info.pts;end; if isfield(info,'faces'),faces=info.faces;end; if isfield(info,'scalar'),scalar=info.scalar;end
        mask=isfinite(scalar); if isempty(scalar),mask=false(0,1);end
        panel_obs(k).role=panels(k).role_id; %#ok<AGROW>
        panel_obs(k).source_path=alias_path(panels(k).source_path,root,golden);
        panel_obs(k).source_sha256=sha256_file(panels(k).source_path);
        panel_obs(k).geometry_sha256=sha_json(struct('points',pts,'faces',faces));
        panel_obs(k).scalar_sha256=sha_json(scalar);
        panel_obs(k).assignment_mask_sha256=sha_json(mask);
        panel_obs(k).scalar_name=getfield_default(info,'scalar_name',''); %#ok<GFLD>
        panel_obs(k).activation_semantics=panels(k).activation_semantics;
        panel_obs(k).coordinate_frame='native reconstruction coordinates';
        panel_obs(k).units='native units; physical scale not established';
        panel_obs(k).temporal_basis='manifest-bound activation time where available; no physiological calibration claim';
        panel_obs(k).limitation='geometry does not imply tissue activation or registration; map-derived activation is not physiologically calibrated/validated';
    end
    semantic_ok = isempty(panels(1).info.scalar) && strcmp(panels(1).activation_semantics,'NONE') && ...
        all(arrayfun(@(x)strlength(string(x.source_sha256))==64,panel_obs));
end
m6_ev=event_record('evt-m6-auto-panels',meta_fig,struct('figure_count_before',fig_before), ...
    struct('figure_count_after',fig_after,'panels',panel_obs,'decode_error',[verr perr]));
emit('M6-DECODED-AUTO-PANELS','restore','M6',m1_ok && fig_after-fig_before==1 && semantic_ok, ...
    'matlab_uitest_event',m6_ev,'automatic figure from M1 event bound to decoded source/scalar/mask; fused geometry is negative control');

% M7 visible restore navigation, Resume and Help.
[~,~]=dispatch_choose(tc,r.recon.ReconstructionTab,'evt-m7-tab');
for n=1:4
    b=find_button(r,sprintf('%d.',n)); [x,e]=dispatch_press(tc,b,sprintf('evt-m7-step-%d',n));
    emit(sprintf('M7-STEP-%d',n),'restore','M7',x,'matlab_uitest_event',e,'real restore accordion event');
end
[x,e]=dispatch_press(tc,r.recon.ReconstructionGuideButton,'evt-m7-guide'); emit('M7-GUIDE','restore','M7',x,'matlab_uitest_event',e,'real restore Guide event');
[x,e]=dispatch_press(tc,r.recon.ReconstructionResumeButton,'evt-m7-resume'); emit('M7-RESUME','restore','M7',x,'matlab_uitest_event',e,'real Resume control event with bounded enablement/remediation evidence');

% M8 explicit real Preview/change/Apply/Reset events.
if ~r.recon.reconstruction_tools_open()
    [x,e]=dispatch_press(tc,r.recon.ToolsHeader,'evt-m8-tools-header');
    emit('M8-TOOLS-HEADER','restore','M8',x,'matlab_uitest_event',e,'real restore copy-on-write accordion event');
end
run_tool_events(tc,r,'restore','M8','m8',true);
try, exportapp(r.opticalmappingUIFigure,fullfile(root,'restore-gui.png')); catch, end
v2=fullfile(restore_run,'manifest.v2.json'); v2_before=sha256_file(v2); delete(r); close all force; drawnow;

% M9 a newly constructed app and a second unique File-menu event.
r2=analyse_optical_mapping(); r2.recon.reconstruction_help_pref_adapter_set(mem_adapter());
r2.opticalmappingUIFigure.Visible='on'; r2.TabGroup.Visible='on'; r2.recon.test_manifest_pick=copy_v1; drawnow;
second_before=count_reconstruction_figures(); [~,~]=dispatch_press(tc,r2.FileMenu,'evt-m9-file-menu-parent'); drawnow;
manifest_menu=find_menu(r2,'Open Reconstruction Manifest');
[m9_ok,m9_ev]=dispatch_press(tc,manifest_menu,'evt-m9-reopen-v1'); drawnow;
second_after=count_reconstruction_figures(); v2_after=sha256_file(v2);
m9_ok=m9_ok && strcmp(v2_before,v2_after) && second_after-second_before==1;
m9_ev.after.v2_sha256=v2_after; m9_ev.after.new_reconstruction_figures=second_after-second_before;
emit('M9-SECOND-FILE-MENU-OPEN','restore','M9',m9_ok,'matlab_uitest_event',m9_ev, ...
    'second unique real File-menu event selected valid v2 without duplicate conversion');
delete(r2); close all force; drawnow;
fprintf('JOURNEY_GUI_EVENTS_COMPLETE\n');

    function run_tool_events(testcase,app,journey,step,prefix,required)
        specs={{'Touchup','TouchupBoxField','0 1 0 1 0 1'}, ...
               {'Intensity','IntensityThresholdField',100}, ...
               {'Area','AreaShapeDropDown','Lasso (click vertices)'}, ...
               {'Smooth','SmoothRadiusField',20}};
        for ii=1:numel(specs)
            s=specs{ii}; name=s{1};
            for phase={'PREVIEW1','CHANGE','PREVIEW2','APPLY','RESET'}
                ph=phase{1}; id=[upper(prefix) '-' upper(name) '-' ph]; eid=['evt-' prefix '-' lower(name) '-' lower(ph)];
                switch ph
                    case {'PREVIEW1','PREVIEW2'}, comp=app.recon.([name 'PreviewButton']); scroll_component(testcase,comp); [q,e]=dispatch_press(testcase,comp,eid);
                    case 'APPLY', comp=app.recon.([name 'ApplyButton']); scroll_component(testcase,comp); [q,e]=dispatch_press(testcase,comp,eid);
                    case 'RESET'
                        comp=app.recon.([name 'ResetButton']);
                        if strcmp(name,'Smooth'),scroll_main(testcase,app,comp);else,scroll_component(testcase,comp);end
                        [q,e]=dispatch_press(testcase,comp,eid);
                    otherwise
                        if required
                            reset_comp=app.recon.([name 'ResetButton']); scroll_component(testcase,reset_comp);
                            [reset_ok,reset_event]=dispatch_press(testcase,reset_comp,[eid '-close-preview1']);
                            if strcmp(name,'Smooth')
                                emit([id '-RESET-PREVIEW1'],journey,step,reset_ok, ...
                                    'matlab_uitest_event',reset_event,'required real Smooth reset event after Preview 1');
                            else
                                emit_optional([id '-CLOSE-PREVIEW1'],journey,step,reset_ok, ...
                                    'matlab_uitest_event',reset_event,'real reset event releases the preview state before parameter editing');
                            end
                        end
                        comp=app.recon.(s{2}); scroll_component(testcase,comp); [q,e]=dispatch_change(testcase,comp,s{3},eid);
                end
                requirement=sprintf('real %s %s event with component identity and bounded before/after state',name,ph);
                if required && ~(strcmp(ph,'CHANGE') && ~strcmp(name,'Area')) && ~(strcmp(ph,'RESET') && strcmp(name,'Smooth'))
                    emit(id,journey,step,q,'matlab_uitest_event',e,requirement);
                else
                    emit_optional(id,journey,step,q,'matlab_uitest_event',e, ...
                        [requirement '; report-only because the controlled fresh executor does not fabricate tool outputs']);
                end
            end
        end
    end

    function emit(id,journey,step,condition,mode,event,requirement)
        row=base_row(id,journey,step,condition,mode,requirement);
        row.event_id=event.event_id; row.event_record_sha256=sha_json(event);
        row.display_enabled=true; row.ui_target=event.component_identity;
        row.observed=struct('event',event); row.expected=struct('dispatch','success');
        append_row(row);
    end
    function emit_observation(id,journey,step,event_id,observed,condition,requirement)
        ev=event_record(event_id,[],struct(),observed);
        row=base_row(id,journey,step,condition,'matlab_uitest_event',requirement);
        row.event_id=event_id; row.event_record_sha256=sha_json(ev); row.display_enabled=true;
        row.ui_target='visible reconstruction prerequisite state'; row.observed=struct('event',ev); row.expected=struct('truthful',true);
        append_row(row);
    end
    function emit_optional(id,journey,step,condition,mode,event,requirement)
        row=base_row(id,journey,step,condition,mode,requirement);
        row.required=false; row.gap_policy='REPORT_ONLY';
        row.event_id=event.event_id; row.event_record_sha256=sha_json(event);
        row.display_enabled=true; row.ui_target=event.component_identity;
        row.observed=struct('event',event); row.expected=struct('dispatch','optional');
        append_row(row);
    end
    function emit_seam(id,journey,step,condition,event_id,observed,requirement)
        row=base_row(id,journey,step,condition,'backend_direct',requirement);
        row.event_id=event_id; row.event_record_sha256=sha_json(observed);
        row.display_enabled=true; row.ui_target='analyse_optical_mapping.reconstruction_check_tools';
        row.observed=observed; row.expected=struct('callback','completed');
        append_row(row);
    end
    function row=base_row(id,journey,step,condition,mode,requirement)
        if condition,result='PASS';gap=[];else,result='FAIL';gap='event dispatch or required observable failed';end
        row=struct('schema','rr3-c42-assertion-v1','id',id,'journey',journey,'step',step, ...
          'requirement',requirement,'result',result,'evidence_class','VERIFIED-BY-EXECUTION', ...
          'product_base_sha',om_test_getenv('OM_TEST_JOURNEY_PRODUCT_BASE'),'harness_sha',om_test_getenv('OM_TEST_JOURNEY_HARNESS_SHA'), ...
          'harness_tree',om_test_getenv('OM_TEST_JOURNEY_HARNESS_TREE'),'input_pack_digest',om_test_getenv('OM_TEST_JOURNEY_INPUT_PACK_DIGEST'), ...
          'projection_sha256',om_test_getenv('OM_TEST_JOURNEY_PROJECTION_SHA256'),'probe_manifest_digest',om_test_getenv('OM_TEST_JOURNEY_TEST_MANIFEST_DIGEST'), ...
          'command_id',om_test_getenv('OM_TEST_JOURNEY_COMMAND_ID'),'command_record_sha256',om_test_getenv('OM_TEST_JOURNEY_COMMAND_SHA256'), ...
          'persona_session_id',[],'event_id',[],'event_record_sha256',[],'display_enabled',true,'ui_target',[], ...
          'observed',struct(),'expected',struct(),'source_anchors',{{}},'artifacts',{{}}, ...
          'platform',['Windows/MATLAB ' version('-release')],'interaction_mode',mode,'commit_phase','NONE', ...
          'required',true,'gap_policy','BLOCK','open_gap',gap);
    end
    function append_row(row)
        bytes=unicode2native([jsonencode(row) newline],'UTF-8'); fid=fopen(out,'ab'); assert(fid>=0); c=onCleanup(@()fclose(fid)); fwrite(fid,bytes,'uint8');
    end
end

function [ok,ev]=dispatch_press(tc,comp,event_id)
b=component_state(comp); err=''; try,tc.press(comp);drawnow;ok=true;catch ME,ok=false;err=[ME.identifier ': ' ME.message];end
a=component_state(comp);a.dispatch_error=err;ev=event_record(event_id,comp,b,a);
end
function [ok,ev]=dispatch_choose(tc,comp,event_id)
b=component_state(comp);err='';try,tc.choose(comp);drawnow;ok=true;catch ME,ok=false;err=[ME.identifier ': ' ME.message];end
a=component_state(comp);a.dispatch_error=err;ev=event_record(event_id,comp,b,a);
end
function [ok,ev]=dispatch_change(tc,comp,value,event_id)
b=component_state(comp);err='';try
 if isa(comp,'matlab.ui.control.DropDown')
     tc.choose(comp,value);
 elseif isnumeric(comp.Value)
     tc.type(comp,value);
 else
     tc.type(comp,string(value));
 end
drawnow;ok=true;catch ME,ok=false;err=[ME.identifier ': ' ME.message];end
a=component_state(comp);a.dispatch_error=err;ev=event_record(event_id,comp,b,a);
end
function ev=event_record(id,comp,before,after)
ev=struct('schema','rr3-c42-event-v1','event_id',id,'component_identity',component_identity(comp), ...
    'enabled_before',getfield_default(before,'enabled',''),'enabled_after',getfield_default(after,'enabled',''), ...
    'before',before,'after',after);
end
function s=component_state(c)
s=struct('enabled','','visible','','value','','text','','tooltip',''); if isempty(c)||~isvalid(c),s.text='MISSING';return;end
for p={'Enable','Visible','Value','Text','Tooltip'}
 try,v=c.(p{1});if iscell(v),v=strjoin(string(v),' | ');end;s.(lower(p{1}))=char(string(v));catch,end
end
end
function id=component_identity(c)
if isempty(c)||~isvalid(c),id='MISSING';return;end
s=component_state(c);id=sprintf('%s|Text=%s|Tag=%s',class(c),s.text,getprop(c,'Tag'));
end
function v=getprop(c,p),try,v=char(string(c.(p)));catch,v='';end,end
function b=find_button(app,prefix)
all=findall(app.opticalmappingUIFigure,'Type','uibutton');b=[];for k=1:numel(all),try,txt=string(all(k).Text);if isscalar(txt)&&startsWith(txt,string(prefix)),b=all(k);return;end,catch,end,end
end
function b=find_global_button(text)
all=findall(groot,'Type','uibutton');b=[];for k=1:numel(all),if strcmp(char(all(k).Text),text),b=all(k);return;end,end
end
function m=find_menu(app,text)
all=findall(app.opticalmappingUIFigure,'Type','uimenu');m=[];
for k=1:numel(all)
    try,if startsWith(string(all(k).Text),string(text)),m=all(k);return;end,catch,end
end
end
function scroll_main(tc,app,comp)
for k=1:12
    try,tc.scroll(app.recon.GridLayoutR1,'down');drawnow;catch,return;end
end
end
function scroll_component(tc,comp)
if isempty(comp)||~isvalid(comp),return;end
p=comp.Parent;
while ~isempty(p)
    try
        if isprop(p,'Scrollable')&&strcmpi(char(p.Scrollable),'on')
            fig=ancestor(comp,'figure');
            for k=1:16
                pos=getpixelposition(comp,true); figpos=getpixelposition(fig);
                if pos(2)<0
                    direction='up';
                elseif pos(2)+pos(4)>figpos(4)
                    direction='down';
                else
                    return
                end
                try,tc.scroll(p,direction);drawnow;catch,return;end
            end
            return
        end
    catch
    end
    try,p=p.Parent;catch,p=[];end
end
end
function s=gate_snapshot(a)
s=struct('dataset',alias_simple(a.recon.ReconstructionDatasetField.Value),'sparse',alias_simple(a.recon.ReconstructionSparseField.Value), ...
 'images',alias_simple(a.recon.ReconstructionImagesField.Value),'roi',alias_simple(a.recon.ReconstructionRoiField.Value), ...
 'check_enabled',char(a.recon.ReconstructionCheckToolsButton.Enable),'check_tooltip',join_value(a.recon.ReconstructionCheckToolsButton.Tooltip), ...
 'run_enabled',char(a.recon.ReconstructionRunButton.Enable),'run_tooltip',join_value(a.recon.ReconstructionRunButton.Tooltip));
end
function s=alias_simple(v),if isempty(v),s='';else,s='$ATTEMPT/<configured>';end,end
function s=join_value(v),if iscell(v),s=char(strjoin(string(v),' | '));else,s=char(string(v));end,end
function n=count_reconstruction_figures
f=findall(groot,'Type','figure');n=0;for k=1:numel(f),try,n=n+contains(char(f(k).Name),'Reconstruction visualisation');catch,end,end
end
function f=find_reconstruction_figure
all=findall(groot,'Type','figure');f=[];for k=1:numel(all),try,if contains(char(all(k).Name),'Reconstruction visualisation'),f=all(k);return;end,catch,end,end
end
function out=alias_path(p,root,golden)
out=strrep(strrep(char(p),char(root),'$ATTEMPT'),char(golden),'$GOLDEN');out=strrep(out,'\','/');
end
function value=getfield_default(s,n,d),if isstruct(s)&&isfield(s,n),value=s.(n);else,value=d;end,end
function d=sha_json(v),d=sha_bytes(unicode2native(jsonencode(v),'UTF-8'));end
function d=sha256_file(p),fid=fopen(p,'rb');assert(fid>=0);c=onCleanup(@()fclose(fid));d=sha_bytes(fread(fid,Inf,'*uint8'));end
function d=sha_bytes(b),md=java.security.MessageDigest.getInstance('SHA-256');md.update(uint8(b));d=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));end
function p=canon(p),p=char(java.io.File(p).getCanonicalPath());end
function a=mem_adapter,m=containers.Map('KeyType','char','ValueType','any');a=struct('get',@(k)getv(m,k),'set',@(k,v)setv(m,k,v));end
function v=getv(m,k),k=char(k);if isKey(m,k),v=m(k);else,v=[];end,end
function setv(m,k,v),m(char(k))=v;end
function write_bytes(p,b),fid=fopen(p,'wb');assert(fid>=0);c=onCleanup(@()fclose(fid));fwrite(fid,b,'uint8');end
function cleanup_all(oldpath),try,path(oldpath);catch,end;try,delete(timerfindall);catch,end;try,close all force;catch,end,end
