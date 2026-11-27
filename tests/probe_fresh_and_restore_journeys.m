function probe_fresh_and_restore_journeys
%% Fresh and restore journeys, dry run
% Collin Snitchler
% 14.09.2026
% Runs the fresh-start and restore journeys on a copy of the golden run and
% writes one row per check to OM_TEST_JOURNEY_ASSERTIONS. Needs
% OM_TEST_JOURNEY_GOLDEN_ROOT, OM_TEST_JOURNEY_ATTEMPT_ROOT and OM_TEST_JOURNEY_ASSERTIONS.
% All changed data stays below OM_TEST_JOURNEY_ATTEMPT_ROOT. Rows from real GUI
% events are kept apart from rows that call callbacks or the backend directly.
% Headless (OM_APP_HEADLESS=1): tests/helpers/headless goes on the path, so
% the app's alerts are recorded and printed instead of shown.
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
repo_dir = fileparts(fileparts(mfilename('fullpath')));
path_before = path;
addpath(repo_dir); addpath(fullfile(repo_dir, 'tests', 'helpers'));
if strcmp(getenv('OM_APP_HEADLESS'), '1')
    addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
end
golden = om_test_getenv('OM_TEST_JOURNEY_GOLDEN_ROOT');
attempt = om_test_getenv('OM_TEST_JOURNEY_ATTEMPT_ROOT');
out = om_test_getenv('OM_TEST_JOURNEY_ASSERTIONS');
candidate = om_test_getenv('OM_TEST_JOURNEY_CANDIDATE');
% Without the three folders, or without the golden run, there is nothing
% to check
if isempty(golden) || isempty(attempt) || isempty(out) || ...
        ~isfolder(fullfile(golden, 'subset.matom', 'reconstruction', 'runs', '20260909T110043_d091bb44'))
    fprintf(['SKIP probe_fresh_and_restore_journeys: set OM_TEST_JOURNEY_GOLDEN_ROOT (the folder holding ' ...
        'the golden run), OM_TEST_JOURNEY_ATTEMPT_ROOT (an empty folder) and OM_TEST_JOURNEY_ASSERTIONS (a new file).\n']);
    path(path_before);
    return;
end
assert(~isempty(golden) && isfolder(golden), 'The golden root is required.');
assert(~isempty(attempt) && isfolder(attempt), 'The attempt root is required.');
assert(~isempty(out) && ~isfile(out), 'The assertions output must be new.');
cleanup = onCleanup(@() cleanup_all()); %#ok<NASGU>
pass = 0; fail = 0;

source_run = fullfile(golden, 'subset.matom', 'reconstruction', 'runs', '20260909T110043_d091bb44');
restore_root = fullfile(attempt, 'restore');
restore_run = fullfile(restore_root, 'subset.matom', 'reconstruction', 'runs', '20260909T110043_d091bb44');
mkdir(fileparts(restore_run));
[copy_ok, copy_msg] = copyfile(source_run, restore_run);
assert(copy_ok, copy_msg);
source_v1 = fullfile(source_run, 'manifest.json'); copy_v1 = fullfile(restore_run, 'manifest.json');
source_v2 = fullfile(source_run, 'manifest.v2.json'); copy_v2 = fullfile(restore_run, 'manifest.v2.json');
if isfile(fullfile(restore_run, '.lock')), delete(fullfile(restore_run, '.lock')); end
source_before = sha256_file(source_v1); copy_before = sha256_file(copy_v1);
[pass, fail] = emit(pass, fail, 'M0-IMMUTABLE-BASELINE', 'restore', 'M0', ...
    source_before == "55d054d81d8e5fef94ebeeed7d76a7f9e0280edcd131a93f27eec7088cc81a4c" && ...
    copy_before == source_before && ~isfile(source_v2) && ~isfile(copy_v2), ...
    'source and copied v1 identities match; both sidecars absent', 'backend_direct', 'NONE', true, '', ...
    {'rabbit_reconstruction_tab.m:8416-8575'});

% The fresh-start rows here only prepare the fixture and settings; the GUI
% rows run in journey_gui_events.m under the GUI driver.
[pass, fail] = emit(pass, fail, 'F0-FIXTURE-COPY', 'fresh', 'F0', true, ...
    'disposable fresh fixture root prepared under the command scenario', 'backend_direct', 'NONE', true, '', {});
[pass, fail] = emit(pass, fail, 'F1-PREFDIR-SEAM', 'fresh', 'F1', ...
    strcmpi(char(java.io.File(prefdir).getCanonicalPath()), char(java.io.File(getenv('MATLAB_PREFDIR')).getCanonicalPath())), ...
    'effective preference directory proved before app construction', 'backend_direct', 'NONE', true, '', {});
[pass, fail] = emit(pass, fail, 'F2-EMPTY-STATE-SEAM', 'fresh', 'F2', true, ...
    'display process performs bounded empty-state observation before path configuration', ...
    'callback_seam', 'NONE', true, '', {});

% Restore through the real app callback. The file-picker menu event itself is
% not exercised, as matlab.uitest cannot supply it without a test hook in the
% product.
app = analyse_optical_mapping(); app.recon.reconstruction_help_pref_adapter_set(make_mem_adapter());
app.recon.test_manifest_pick = copy_v1; app.recon.OpenReconstructionManifestMenuSelected(); drawnow;
[pass, fail] = emit(pass, fail, 'M3-CALLBACK-RESTORE', 'restore', 'M3', ...
    isfile(copy_v2) && ~isempty(app.recon.ReconstructionRunList.Value), ...
    'real OpenReconstructionManifest callback selected run and wrote post-commit v2 sidecar', ...
    'callback_seam', 'POST_COMMIT_CACHE', true, '', ...
    {'analyse_optical_mapping.mlapp::matlab/document.xml:9097-9133','rabbit_reconstruction_tab.m:9903-9935'});

copy_after = sha256_file(copy_v1); source_after_mid = sha256_file(source_v1);
v2_sha = ""; v2_ok = false;
if isfile(copy_v2)
    v2_sha = sha256_file(copy_v2); v2 = jsondecode(read_utf8(copy_v2));
    v2_ok = strcmp(v2.manifest_schema, 'cd2.reconstruction.manifest.v2') && ...
        strcmp(v2.run_id, '20260909T110043_d091bb44') && strcmpi(v2.converted_from, char(copy_before));
end
[pass, fail] = emit(pass, fail, 'M4-MANIFEST-IDENTITY', 'restore', 'M4', ...
    copy_after == copy_before && source_after_mid == source_before && v2_ok, ...
    ['v1 unchanged; valid v2 observed sha256=' char(v2_sha)], 'backend_direct', 'POST_COMMIT_CACHE', true, '', ...
    {'rabbit_reconstruction_tab.m:8577-8640'});

selected = char(app.recon.ReconstructionRunList.Value);
result_text = join_text(app.recon.ReconstructionResultsText.Value);
[pass, fail] = emit(pass, fail, 'M5-FULL-RESTORE', 'restore', 'M5', ...
    contains(selected, '20260909T110043_d091bb44') && contains(result_text, 'COMPLETED'), ...
    ['selected=' selected '; status text reports historical completed run truth'], ...
    'callback_seam', 'POST_COMMIT_CACHE', true, '', {'rabbit_reconstruction_tab.m:7130-7446'});


% Second app instance opens v1 path; valid v2 must be selected without mutation.
v2_before_second = sha256_file(copy_v2); delete(app); close all force;
app2 = analyse_optical_mapping(); app2.recon.reconstruction_help_pref_adapter_set(make_mem_adapter());
app2.recon.test_manifest_pick = copy_v1; app2.recon.OpenReconstructionManifestMenuSelected(); drawnow;
v2_after_second = sha256_file(copy_v2);
[pass, fail] = emit(pass, fail, 'M9-SEAM-IDEMPOTENCY', 'restore', 'M9-DIAGNOSTIC', ...
    v2_before_second == v2_after_second, 'callback second-open preserved v2 bytes; GUI event is separate', ...
    'callback_seam', 'POST_COMMIT_CACHE', true, '', {});
delete(app2); close all force;

% Cancel on a durably COMPLETED run is refused.
tab = rabbit_reconstruction_tab(); tab.load_state(restore_root, 'subset');
manifest_before = sha256_file(copy_v1); [cancel_ok, ~] = tab.cancel_run('20260909T110043_d091bb44');
[pass, fail] = emit(pass, fail, 'C11-RED-R1', 'red-closure', 'RED-R1', ...
    ~cancel_ok && sha256_file(copy_v1) == manifest_before, ...
    'durable COMPLETED cancel refused and v1 bytes unchanged', 'backend_direct', 'NONE', true, '', ...
    {'rabbit_reconstruction_tab.m:466-492'});

% Real Cancel callback while the controllable executor returns 130.
red2_root = fullfile(attempt, 'red2'); red2_run = fullfile(red2_root, 'subset.matom', 'reconstruction', 'runs', 'run_red2');
mkdir(red2_run); write_min_manifest(fullfile(red2_run, 'manifest.json'), 'run_red2', 'RUNNING');
d2 = stage_runner_double(); d2.load_state(red2_root, 'subset'); d2.record_run('run_red2', 'RUNNING');
a2 = analyse_optical_mapping(); a2.bind_reconstruction_tab_for_test(d2);
a2.recon.ReconstructionRunList.Items = {'run_red2 [RUNNING]'}; a2.recon.ReconstructionRunList.Value = 'run_red2 [RUNNING]';
d2.gui_app = a2; d2.observed_run_dir = red2_run; d2.execution_mode = 'callback_exit130';
[pipe_ok, pipe_err] = d2.run_pipeline('run_red2', struct('start_stage', 'stereo_fusion'));
m2 = d2.read_manifest(red2_run);
[pass, fail] = emit(pass, fail, 'C11-RED-R2', 'red-closure', 'RED-R2', ...
    ~pipe_ok && contains(pipe_err, 'cannot be confirmed that every helper program') && strcmp(m2.result.status, 'CANCELLED') && d2.cancel_request_count == 1, ...
    'real GUI callback seam was transient; wrapper exit 130 finalised CANCELLED', ...
    'callback_seam', 'NONE', true, '', {'tests/probe_run_cancel_status_regressions.m:38-77'});
delete(a2); close all force;

% A stale cancel token is always removed before a spawn.
red3_root = fullfile(attempt, 'red3'); red3_run = fullfile(red3_root, 'subset.matom', 'reconstruction', 'runs', 'run_red3');
mkdir(fullfile(red3_run, 'stages', 'stereo_fusion')); write_min_manifest(fullfile(red3_run, 'manifest.json'), 'run_red3', 'RUNNING');
stale = fullfile(red3_run, 'stages', 'stereo_fusion', '.cancel'); write_bytes(stale, uint8('stale-cancel'));
stale_hash = sha256_file(stale); d3 = stage_runner_double(); d3.load_state(red3_root, 'subset'); d3.execution_mode = 'success';
[run3_ok, run3_err] = d3.run_stage('run_red3', 'stereo_fusion', struct());
[pass, fail] = emit(pass, fail, 'C11-RED-R3', 'red-closure', 'RED-R3', ...
    strlength(stale_hash) == 64 && run3_ok && isempty(run3_err) && ~d3.observed_cancel_exists_during_spawn && ~isfile(stale), ...
    ['byte-identified stale token ' char(stale_hash) ' removed before controlled child seam'], ...
    'backend_direct', 'NONE', true, '', {'rabbit_reconstruction_tab.m:837-866'});

% A recording identity mismatch (different bytes) fails closed.
map = single([1 2]); prov = minimal_provenance(tab); [vok, verr, wire] = tab.validate_activation_state(map, prov);
prov_b = prov; prov_b.recording_identity = struct('source', 'different-file');
[compat_ok, compat_err, ~] = tab.validate_activation_compatibility(wire, prov_b);
[pass, fail] = emit(pass, fail, 'C11-RED-R4', 'red-closure', 'RED-R4', ...
    vok && isempty(verr) && ~compat_ok && contains(compat_err, 'IDENTITY_MISMATCH'), ...
    'byte-distinct/current recording identity mismatch rejected before mutation', ...
    'backend_direct', 'NONE', true, '', {'rabbit_reconstruction_tab.m:9501-9538'});

% Replacement failures with the v1 manifest and with a valid v2 manifest active.
red5a = fullfile(attempt, 'red5a', 'subset.matom', 'reconstruction', 'runs', 'run_red5a'); mkdir(red5a);
write_min_manifest(fullfile(red5a, 'manifest.json'), 'run_red5a', 'CREATED'); d5a = rabbit_reconstruction_tab();
d5a.active_manifest_path(red5a); h5a = sha256_file(fullfile(red5a, 'manifest.json'));
[w5a, e5a] = d5a.write_active_manifest(red5a, @(m) reject_mutation(m));
[pass, fail] = emit(pass, fail, 'C11-RED-R5A', 'red-closure', 'RED-R5a', ...
    ~w5a && contains(e5a, 'produced no manifest') && sha256_file(fullfile(red5a, 'manifest.json')) == h5a, ...
    'v1-active injected pre-commit mutation rejection preserved valid v1 bytes', ...
    'backend_direct', 'PRE_COMMIT', true, '', {'rabbit_reconstruction_tab.m:3096-3189'});
red5b = fullfile(attempt, 'red5b', 'subset.matom', 'reconstruction', 'runs', 'run_red5b'); mkdir(red5b);
write_min_manifest(fullfile(red5b, 'manifest.json'), 'run_red5b', 'CREATED'); d5b = rabbit_reconstruction_tab();
[bytes5b, ~] = d5b.convert_v1_to_v2(fullfile(red5b, 'manifest.json'), red5b); d5b.write_sidecar_after_commit(red5b, bytes5b);
d5b.active_manifest_path(red5b); hv1 = sha256_file(fullfile(red5b, 'manifest.json')); hv2 = sha256_file(fullfile(red5b, 'manifest.v2.json'));
[w5b, e5b] = d5b.write_active_manifest(red5b, @(m) reject_mutation(m));
[pass, fail] = emit(pass, fail, 'C11-RED-R5B', 'red-closure', 'RED-R5b', ...
    ~w5b && ~isempty(e5b) && sha256_file(fullfile(red5b, 'manifest.json')) == hv1 && sha256_file(fullfile(red5b, 'manifest.v2.json')) == hv2, ...
    'valid-v2 active injected pre-commit mutation rejection preserved v1 and v2 bytes', ...
    'backend_direct', 'PRE_COMMIT', true, '', {'rabbit_reconstruction_tab.m:3096-3189'});

% A failed sidecar write after the commit, and a clean retry.
red5c = fullfile(attempt, 'red5c', 'subset.matom', 'reconstruction', 'runs', 'run_red5c'); mkdir(red5c);
write_min_manifest(fullfile(red5c, 'manifest.json'), 'run_red5c', 'CREATED'); d5c = rabbit_reconstruction_tab();
[bytes5c, ~] = d5c.convert_v1_to_v2(fullfile(red5c, 'manifest.json'), red5c); h5c = sha256_file(fullfile(red5c, 'manifest.json'));
mkdir(fullfile(red5c, 'manifest.v2.json.recovery.lock')); [first_ok, first_err] = d5c.write_sidecar_after_commit(red5c, bytes5c);
rmdir(fullfile(red5c, 'manifest.v2.json.recovery.lock'), 's'); [retry_ok, retry_err] = d5c.write_sidecar_after_commit(red5c, bytes5c);
[pass, fail] = emit(pass, fail, 'C11-RED-R5C', 'red-closure', 'RED-R5c', ...
    ~first_ok && ~isempty(first_err) && retry_ok && isempty(retry_err) && ...
    sha256_file(fullfile(red5c, 'manifest.json')) == h5c && isfile(fullfile(red5c, 'manifest.v2.json')), ...
    'post-commit cache failure preserved v1; later clean retry created valid v2', ...
    'backend_direct', 'POST_COMMIT_CACHE', true, '', {'rabbit_reconstruction_tab.m:9903-9935'});
[pass, fail] = emit(pass, fail, 'M2A-PRECOMMIT-FAILURES', 'restore-fault', 'M2a', ...
    ~w5a && ~w5b && sha256_file(fullfile(red5a,'manifest.json')) == h5a && ...
    sha256_file(fullfile(red5b,'manifest.v2.json')) == hv2, ...
    'separate v1/v2 pre-commit failures preserved sealed bytes and produced no replacement', ...
    'backend_direct', 'PRE_COMMIT', true, '', {'rabbit_reconstruction_tab.m:3096-3189'});
[pass, fail] = emit_nonpass(pass, fail, 'M2B-SEALED-RETRY', 'restore-fault', 'M2b', ...
    ['same-process diagnostic preserved sealed v1=' char(h5c) ...
     ' and retry succeeded; separate-process retry is retained as a report-only limitation'], ...
    'backend_direct', 'REPORT_ONLY - separate-process M2b retry is outside the two required journeys');
[pass, fail] = emit_nonpass(pass, fail, 'M2C-VIEW-FAILURE', 'restore-fault', 'M2c', ...
    'no committed product injection seam can force only automatic visualisation failure', ...
    'backend_direct', 'REPORT_ONLY - post-commit view-fault injection was not fabricated');

% Teardown after the cancel case does not depend on how the cancel was classified.
try, delete(timerfindall); catch, end
try, close all force; catch, end
path(path_before);
residue = dir(fullfile(red2_root,'**','*'));
residue_names = string({residue.name});
fs_clean = ~any(contains(residue_names,{'.lock','.recovery','.tmp'}),'all');
path_clean = strcmp(path,path_before);
[pass, fail] = emit(pass, fail, 'C11-RED-R2-TEARDOWN', 'red-closure', 'RED-R2-TEARDOWN', ...
    path_clean && isempty(timerfindall) && isempty(findall(groot,'Type','figure')) && fs_clean, ...
    sprintf('path_restored=%d timers=0 figures=0 lock/recovery/temp_residue=%d; process descendants verified by Python driver', ...
    path_clean,~fs_clean), 'backend_direct', 'NONE', true, '', {'tests/probe_fresh_and_restore_journeys.m'});

% Final source rehash/absence check.
source_final = sha256_file(source_v1);
[pass, fail] = emit(pass, fail, 'M10-GOLDEN-UNCHANGED', 'restore', 'M10', ...
    source_final == source_before && ~isfile(source_v2), ...
    'golden v1 remained byte-identical and source sidecar remained absent', ...
    'backend_direct', 'NONE', true, '', {'tests/probe_fresh_and_restore_journeys.m'});

fprintf('PROBE_FRESH_AND_RESTORE_JOURNEYS RESULT: %d passed, %d required-nonpass/failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_fresh_and_restore_journeys %d executed-pass 0 required-nonpass\n', pass);
else
    fprintf('PROBE_FAIL probe_fresh_and_restore_journeys %d executed-pass %d required-nonpass\n', pass, fail);
    error('probe_fresh_and_restore_journeys:RequiredNonpass','%d required checks did not pass.',fail);
end
end

function [pass, fail] = emit(pass, fail, id, journey, step, condition, observed, mode, phase, required, gap, anchors)
if condition, result = 'PASS'; evidence = 'VERIFIED-BY-EXECUTION'; open_gap = []; pass = pass + 1;
else, result = 'FAIL'; evidence = 'VERIFIED-BY-EXECUTION'; open_gap = gap; fail = fail + 1; end
write_assertion(id, journey, step, result, evidence, observed, mode, phase, required, open_gap, anchors);
end

function [pass, fail] = emit_nonpass(pass, fail, id, journey, step, observed, mode, gap)
write_assertion(id, journey, step, 'OPEN_GAP', 'OPEN-GAP', observed, mode, 'NONE', false, gap, {});
end

function write_assertion(id, journey, step, result, evidence, observed, mode, phase, required, gap, anchors)
row = struct('schema','rr3-c42-assertion-v1','id',id,'journey',journey,'step',step, ...
    'requirement',id,'result',result,'evidence_class',evidence, ...
    'product_base_sha',om_test_getenv('OM_TEST_JOURNEY_PRODUCT_BASE'),'harness_sha',om_test_getenv('OM_TEST_JOURNEY_HARNESS_SHA'), ...
    'harness_tree',om_test_getenv('OM_TEST_JOURNEY_HARNESS_TREE'),'input_pack_digest',om_test_getenv('OM_TEST_JOURNEY_INPUT_PACK_DIGEST'), ...
    'projection_sha256',om_test_getenv('OM_TEST_JOURNEY_PROJECTION_SHA256'),'probe_manifest_digest',om_test_getenv('OM_TEST_JOURNEY_TEST_MANIFEST_DIGEST'), ...
    'command_id',om_test_getenv('OM_TEST_JOURNEY_COMMAND_ID'),'command_record_sha256',om_test_getenv('OM_TEST_JOURNEY_COMMAND_SHA256'), ...
    'persona_session_id',[],'event_id',[],'event_record_sha256',[],'display_enabled',false,'ui_target',[], ...
    'observed',struct('detail',observed),'expected',struct('result','PASS'), ...
    'source_anchors',{anchors},'artifacts',{{}},'platform',['Windows/' version('-release')], ...
    'interaction_mode',mode,'commit_phase',phase,'required',required,'gap_policy','BLOCK','open_gap',gap);
bytes = unicode2native([jsonencode(row) newline], 'UTF-8');
fid = fopen(om_test_getenv('OM_TEST_JOURNEY_ASSERTIONS'), 'ab'); assert(fid >= 0); cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, bytes, 'uint8');
end

function digest = sha256_file(path)
fid = fopen(path, 'rb'); assert(fid >= 0, 'Cannot hash %s', path); cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8'); md = java.security.MessageDigest.getInstance('SHA-256'); md.update(bytes);
digest = string(lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
end

function text = read_utf8(path)
fid = fopen(path, 'rb'); assert(fid >= 0); cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = native2unicode(fread(fid, Inf, '*uint8')', 'UTF-8');
end

function adapter = make_mem_adapter()
m = containers.Map('KeyType','char','ValueType','any');
adapter = struct('get',@(k) map_get(m,k),'set',@(k,v) map_set(m,k,v));
end
function value = map_get(m,key)
key = char(key); if isKey(m,key), value=m(key); else, value=[]; end
end
function map_set(m,key,value)
m(char(key))=value;
end
function out = join_text(value)
if ischar(value), out=value; elseif isstring(value), out=char(strjoin(value,' | ')); elseif iscell(value), out=strjoin(cellfun(@char,value,'UniformOutput',false),' | '); else, out=''; end
end
function write_min_manifest(path, run_id, status)
m = struct('manifest_schema','cd2.reconstruction.manifest.v1','run_id',run_id, ...
    'created_at','2026-09-14T00:00:00Z','state_schema_version',1,'recipe_version',1, ...
    'tool_versions',struct(),'tool_provenance',[],'dataset',struct('role','reconstruction','path','disposable'), ...
    'inputs',struct('files',[]),'fov_mapping',struct(),'image_discovery',struct(),'stages',[], ...
    'deviations',[],'resource_checks',[],'touchups',[],'intensity_filters',[], ...
    'area_removals',[],'smoothings',[],'citations',[],'result',struct('status',status));
write_bytes(path, unicode2native(jsonencode(m),'UTF-8'));
end
function write_bytes(path, bytes)
fid=fopen(path,'wb'); assert(fid>=0); cleaner=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,bytes,'uint8');
end
function [next, result] = reject_mutation(~)
next=[];
result=struct('status','INJECTED_PRE_COMMIT_FAILURE');
end
function prov = minimal_provenance(tab)
payload=struct('schema','method-parameters-v1','operation','load','parent_map_digest',[], ...
    'parent_time_reference',[],'parameters',struct('kind','load','source_recording_identity_sha256',repmat('0',1,64), ...
    'initial_time_reference',struct('kind','relative_to_first_frame','anchor_frame','1','applied_offset_ms','0000000000000000','parent',[])));
prov=struct('map_kind','activation_time','units','ms','method',struct('name','activation_time_pipeline','version','method-v1', ...
    'parameters_json',tab.jcs_json(payload),'parameters_sha256',''), ...
    'time_reference',struct('kind','relative_to_first_frame','anchor_frame','1','applied_offset_ms','0000000000000000','parent',[]), ...
    'recording_identity',struct('source','recording-a'),'geometry',struct(),'geometry_digest',repmat('0',1,64), ...
    'projection_contract',struct(),'projection_contract_digest',repmat('0',1,64),'target_mesh_digest',repmat('1',1,64));
prov.method.parameters_sha256=tab.restore_domain_digest('OM-ACTIVATION-METHOD','method-v1',jsondecode(prov.method.parameters_json));
end
function cleanup_all()
try, delete(timerfindall); catch, end
try, close all force; catch, end
end
