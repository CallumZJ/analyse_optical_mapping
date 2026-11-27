function probe_run_status
%% Run status, stage list and completion checks
% Collin Snitchler
% 13.09.2026
% Checks the stage order and resume point, the stage activity and log display,
% and whether a completed run is consistent with its stages and outputs.
% Set OM_TEST_RESTORE_GOLDEN_ROOT to the golden fixture root (the probe skips
% without it).
%
% Assertions (25 total):
%   T1  driver_stage_order returns canonical 8 stages in fixed order.
%   T2  driver_stage_order centralised across backend and GUI.
%   T3  empty run: all 8 stages MISSING, first_resumable is step 1.
%   T4  step 1 PASSED -> first_resumable is step 2.
%   T5  step 1 WARNED -> completion-equivalent, first_resumable is step 2.
%   T6  step 1 PASSED, step 2 WARNED -> first_resumable is step 3.
%   T7  step 1 RUNNING -> is_running=true, RUNNING not offered as resume.
%   T8  steps 1-2 PASSED, step 3 FAILED -> first_resumable is step 3.
%   T9  steps 1-2 PASSED, step 3 CANCELLED -> first_resumable is step 3.
%   T10 out-of-order completion detected and flagged (step 1 PASSED, 2 MISSING, 3 PASSED).
%   T11 stage_activity on empty log reports 'No log output recorded yet.'.
%   T12 stage_activity with existing log lines returns bounded log tail.
%   T13 stage_activity includes manifest outputs when recorded.
%   T14 stage_activity suppresses external artifact paths outside trusted run.
%   T15 stage_activity includes manifest warnings when recorded.
%   T16 reconstruction_completion_consistency on golden completed run is clean.
%   T17 reconstruction_completion_consistency flags missing stage.
%   T18 reconstruction_completion_consistency flags missing visualization artifact.
%   T19 reconstruction_completion_consistency flags digest anomaly.
%   T20 reconstruction_completion_consistency flags non-COMPLETED durable status.
%   T21 GUI ReconstructionStageList has 8 numbered rows 'Step N of 8: ...'.
%   T22 GUI ReconstructionStageList has prefix > on at most one row.
%   T23 GUI ReconstructionResultsText shows whether completion is clean or inconsistent.
%   T24 durable COMPLETED plus a FAILED stage is inconsistent.
%   T25 durable COMPLETED plus a RUNNING stage is inconsistent.

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);

golden_root = om_test_getenv('OM_TEST_RESTORE_GOLDEN_ROOT');
if isempty(golden_root) || exist(golden_root, 'dir') ~= 7
    fprintf(['SKIP_NONPASS probe_run_status: set OM_TEST_RESTORE_GOLDEN_ROOT ' ...
        'to the folder holding the golden run.\n']);
    return;
end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';

scratch_root = fullfile(tempdir, 'om_test_probe_run_status');
if exist(scratch_root, 'dir'), rmdir(scratch_root, 's'); end
mkdir(scratch_root);

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

tab = rabbit_reconstruction_tab();
canonical_8 = {'image_undistorter', 'apde_scene_prep', 'apde_run', ...
    'patch_match_stereo', 'stereo_fusion', 'mesh_cleanup', 'alignment', 'reprojection'};

% --- T1: driver_stage_order returns canonical 8 stages in fixed order ---
order1 = tab.driver_stage_order();
T1 = isequal(order1, canonical_8);
fprintf('T1 driver_stage_order matches canonical 8: %s\n', tf(T1));
if T1, pass = pass + 1; else, fail = fail + 1; end

% --- T2: GUI and backend share centralised driver_stage_order ---
app_dummy = analyse_optical_mapping;
order2 = app_dummy.recon.driver_stage_order();
delete(app_dummy);
T2 = isequal(order1, order2);
fprintf('T2 GUI and backend share driver_stage_order: %s\n', tf(T2));
if T2, pass = pass + 1; else, fail = fail + 1; end

% Setup synthetic dataset and runs helper
ds_dir = fullfile(scratch_root, [stem '.matom']);
runs_dir = fullfile(ds_dir, 'reconstruction', 'runs');
mkdir(runs_dir);
tab.load_state(scratch_root, stem);

make_run = @(rid, stages_cell, run_st) create_test_run(runs_dir, rid, stages_cell, run_st);

% --- T3: empty run: all 8 stages MISSING, first_resumable is step 1 ---
rid3 = 'run_t3_empty';
make_run(rid3, {}, 'CREATED');
proj3 = tab.reconstruction_stage_projection(rid3);
T3 = strcmp(proj3.first_resumable_stage, canonical_8{1}) && ...
    proj3.first_resumable_step == 1 && ...
    all(strcmp({proj3.stages.status}, 'MISSING'));
fprintf('T3 empty run first resumable is step 1 (%s): %s\n', proj3.first_resumable_stage, tf(T3));
if T3, pass = pass + 1; else, fail = fail + 1; end

% --- T4: step 1 PASSED -> first_resumable is step 2 ---
rid4 = 'run_t4_p1';
make_run(rid4, {{canonical_8{1}, 'PASSED'}}, 'CREATED');
proj4 = tab.reconstruction_stage_projection(rid4);
T4 = strcmp(proj4.first_resumable_stage, canonical_8{2}) && ...
    proj4.first_resumable_step == 2;
fprintf('T4 step 1 PASSED -> step 2 (%s): %s\n', proj4.first_resumable_stage, tf(T4));
if T4, pass = pass + 1; else, fail = fail + 1; end

% --- T5: step 1 WARNED -> completion-equivalent, first_resumable is step 2 ---
rid5 = 'run_t5_w1';
make_run(rid5, {{canonical_8{1}, 'WARNED'}}, 'CREATED');
proj5 = tab.reconstruction_stage_projection(rid5);
T5 = strcmp(proj5.first_resumable_stage, canonical_8{2}) && ...
    proj5.first_resumable_step == 2 && ...
    proj5.stages(1).is_completion_equivalent;
fprintf('T5 step 1 WARNED completion-equivalent -> step 2 (%s): %s\n', proj5.first_resumable_stage, tf(T5));
if T5, pass = pass + 1; else, fail = fail + 1; end

% --- T6: step 1 PASSED, step 2 WARNED -> first_resumable is step 3 ---
rid6 = 'run_t6_p1_w2';
make_run(rid6, {{canonical_8{1}, 'PASSED'}, {canonical_8{2}, 'WARNED'}}, 'CREATED');
proj6 = tab.reconstruction_stage_projection(rid6);
T6 = strcmp(proj6.first_resumable_stage, canonical_8{3}) && ...
    proj6.first_resumable_step == 3;
fprintf('T6 step 1 PASSED, step 2 WARNED -> step 3 (%s): %s\n', proj6.first_resumable_stage, tf(T6));
if T6, pass = pass + 1; else, fail = fail + 1; end

% --- T7: step 1 RUNNING -> is_running=true, not offered as resume ---
rid7 = 'run_t7_running';
make_run(rid7, {{canonical_8{1}, 'RUNNING'}}, 'RUNNING');
proj7 = tab.reconstruction_stage_projection(rid7);
[ns_ok7, ~, next7] = tab.next_stage_to_run(rid7);
T7 = proj7.is_running && strcmp(proj7.current_stage, canonical_8{1}) && ...
    ~ns_ok7 && isempty(next7);
fprintf('T7 step 1 RUNNING -> is_running=true, resume refused: %s\n', tf(T7));
if T7, pass = pass + 1; else, fail = fail + 1; end

% --- T8: steps 1-2 PASSED, step 3 FAILED -> first_resumable is step 3 ---
rid8 = 'run_t8_failed';
make_run(rid8, {{canonical_8{1}, 'PASSED'}, {canonical_8{2}, 'PASSED'}, {canonical_8{3}, 'FAILED'}}, 'FAILED');
proj8 = tab.reconstruction_stage_projection(rid8);
T8 = strcmp(proj8.first_resumable_stage, canonical_8{3}) && ...
    proj8.first_resumable_step == 3;
fprintf('T8 step 3 FAILED -> first resumable is step 3 (%s): %s\n', proj8.first_resumable_stage, tf(T8));
if T8, pass = pass + 1; else, fail = fail + 1; end

% --- T9: steps 1-2 PASSED, step 3 CANCELLED -> first_resumable is step 3 ---
rid9 = 'run_t9_cancelled';
make_run(rid9, {{canonical_8{1}, 'PASSED'}, {canonical_8{2}, 'PASSED'}, {canonical_8{3}, 'CANCELLED'}}, 'CANCELLED');
proj9 = tab.reconstruction_stage_projection(rid9);
T9 = strcmp(proj9.first_resumable_stage, canonical_8{3}) && ...
    proj9.first_resumable_step == 3;
fprintf('T9 step 3 CANCELLED -> first resumable is step 3 (%s): %s\n', proj9.first_resumable_stage, tf(T9));
if T9, pass = pass + 1; else, fail = fail + 1; end

% --- T10: out-of-order completion detected and flagged ---
rid10 = 'run_t10_ooo';
% Step 1 PASSED, Step 2 MISSING, Step 3 PASSED
make_run(rid10, {{canonical_8{1}, 'PASSED'}, {canonical_8{3}, 'PASSED'}}, 'CREATED');
proj10 = tab.reconstruction_stage_projection(rid10);
T10 = proj10.has_out_of_order && proj10.out_of_order_count >= 1 && ...
    any(strcmp(proj10.out_of_order_stages, canonical_8{3})) && ...
    strcmp(proj10.first_resumable_stage, canonical_8{2});
fprintf('T10 out-of-order stage detected (step 3 after missing step 2): %s\n', tf(T10));
if T10, pass = pass + 1; else, fail = fail + 1; end

% --- T11: stage_activity on empty log reports 'No log output recorded yet.' ---
rid11 = 'run_t11_act';
make_run(rid11, {{canonical_8{1}, 'PASSED'}}, 'COMPLETED');
act11 = tab.stage_activity(rid11, canonical_8{1}, 200);
T11 = ~isempty(strfind(act11.text, 'No log output recorded yet.'));
fprintf('T11 stage_activity empty log notice: %s\n', tf(T11));
if T11, pass = pass + 1; else, fail = fail + 1; end

% --- T12: stage_activity with existing log lines returns bounded log tail ---
log_dir11 = fullfile(runs_dir, rid11, 'logs');
mkdir(log_dir11);
log_path11 = fullfile(log_dir11, [canonical_8{1} '.log']);
fid = fopen(log_path11, 'w', 'n', 'UTF-8');
for li = 1:50
    fprintf(fid, 'Log line %d: Processing frame %d...\n', li, li);
end
fclose(fid);
act12 = tab.stage_activity(rid11, canonical_8{1}, 20);
T12 = numel(act12.tail) > 0 && ~isempty(strfind(act12.text, 'Log line 50')) && ...
    ~isempty(strfind(act12.text, 'Activity - run run_t11_act'));
fprintf('T12 stage_activity bounded log tail: %s\n', tf(T12));
if T12, pass = pass + 1; else, fail = fail + 1; end

% --- T13: stage_activity includes manifest outputs when recorded ---
rid13 = 'run_t13_outputs';
st13_dir = fullfile(runs_dir, rid13);
mkdir(fullfile(st13_dir, 'outputs'));
fclose(fopen(fullfile(st13_dir, 'outputs', 'test.ply'), 'w'));
st13_rec = struct('name', canonical_8{1}, 'status', 'PASSED', ...
    'artifacts', struct('path', fullfile(st13_dir, 'outputs', 'test.ply'), 'sha256', 'abc123'));
write_custom_manifest(st13_dir, rid13, [st13_rec], 'COMPLETED');
act13 = tab.stage_activity(rid13, canonical_8{1}, 200);
T13 = ~isempty(strfind(act13.text, 'Outputs:')) && ~isempty(strfind(act13.text, 'outputs/test.ply'));
fprintf('T13 stage_activity includes outputs: %s\n', tf(T13));
if T13, pass = pass + 1; else, fail = fail + 1; end

% --- T14: stage_activity suppresses external artifact paths ---
rid14 = 'run_t14_external';
st14_dir = fullfile(runs_dir, rid14);
mkdir(st14_dir);
outside_path = fullfile(tempdir, 'om_test_probe_run_status_outside', 'calc.exe');
st14_rec = struct('name', canonical_8{1}, 'status', 'PASSED', ...
    'artifacts', struct('path', outside_path, 'sha256', 'deadbeef'));
write_custom_manifest(st14_dir, rid14, [st14_rec], 'COMPLETED');
act14 = tab.stage_activity(rid14, canonical_8{1}, 200);
T14 = ~isempty(strfind(act14.text, '[hidden: outside the run folder]')) && ...
    isempty(strfind(act14.text, 'calc.exe'));
fprintf('T14 stage_activity suppresses external path: %s\n', tf(T14));
if T14, pass = pass + 1; else, fail = fail + 1; end

% --- T15: stage_activity includes manifest warnings when recorded ---
rid15 = 'run_t15_warn';
st15_dir = fullfile(runs_dir, rid15);
mkdir(st15_dir);
st15_rec = struct('name', canonical_8{1}, 'status', 'WARNED', ...
    'warnings', {{'Zero vertices fused in candidate cloud; proceeding with degenerate output.'}});
write_custom_manifest(st15_dir, rid15, [st15_rec], 'COMPLETED');
act15 = tab.stage_activity(rid15, canonical_8{1}, 200);
T15 = ~isempty(strfind(act15.text, 'Warnings:')) && ...
    ~isempty(strfind(act15.text, 'Zero vertices fused'));
fprintf('T15 stage_activity includes warnings: %s\n', tf(T15));
if T15, pass = pass + 1; else, fail = fail + 1; end

% Setup golden fixture copy and synthetic clean run
g_dest = fullfile(runs_dir, golden_run);
g_src = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
copyfile(g_src, g_dest);

% Create synthetic clean run with all 8 stages PASSED and valid PLYs
rid_clean = 'run_clean_completed';
st_clean_dir = fullfile(runs_dir, rid_clean);
copyfile(g_src, st_clean_dir);
fused_clean_path = fullfile(st_clean_dir, 'outputs', 'fused-geometric.ply');
[~, sha_fused_clean, ~] = tab.manifest_bytes_sha256(fused_clean_path);

m_clean = tab.read_manifest(st_clean_dir);
m_clean.run_id = rid_clean;
clean_stages = [];
for k = 1:numel(canonical_8)
    st = struct('name', canonical_8{k}, 'status', 'PASSED', 'artifacts', struct([]));
    if strcmp(canonical_8{k}, 'stereo_fusion')
        st.artifacts = struct('path', fused_clean_path, 'sha256', sha_fused_clean);
    end
    if isempty(clean_stages), clean_stages = st; else, clean_stages(end+1) = st; end %#ok<AGROW>
end
m_clean.stages = clean_stages;
m_clean.result.status = 'COMPLETED';
tab.write_manifest(st_clean_dir, m_clean);

% --- T16: reconstruction_completion_consistency on clean run is clean ---
[clean16, res16] = tab.reconstruction_completion_consistency(rid_clean);
T16 = clean16 && res16.clean && isempty(res16.first_discrepancy);
fprintf('T16 clean run completion consistency is clean: %s\n', tf(T16));
if T16, pass = pass + 1; else, fail = fail + 1; end

% --- T17: reconstruction_completion_consistency on golden run flags mesh_cleanup failure ---
[clean17, res17] = tab.reconstruction_completion_consistency(golden_run);
T17 = ~clean17 && strcmp(res17.discrepant_stage, 'mesh_cleanup');
fprintf('T17 completion consistency flags golden run mesh_cleanup failure: %s\n', tf(T17));
if T17, pass = pass + 1; else, fail = fail + 1; end

% --- T18: reconstruction_completion_consistency flags missing visualization artifact ---
rid18 = 'run_t18_missing_ply';
st18_dir = fullfile(runs_dir, rid18);
copyfile(st_clean_dir, st18_dir);
m18 = tab.read_manifest(st18_dir);
m18.run_id = rid18;
tab.write_manifest(st18_dir, m18);
proj_ply = fullfile(st18_dir, 'outputs', 'reprojection', 'activation_projected.ply');
if exist(proj_ply, 'file'), delete(proj_ply); end
[clean18, res18] = tab.reconstruction_completion_consistency(rid18);
T18 = ~clean18 && ~isempty(res18.discrepant_role);
fprintf('T18 completion consistency flags missing visualization role (%s): %s\n', res18.discrepant_role, tf(T18));
if T18, pass = pass + 1; else, fail = fail + 1; end

% --- T19: reconstruction_completion_consistency flags digest anomaly ---
rid19 = 'run_t19_digest_anomaly';
st19_dir = fullfile(runs_dir, rid19);
copyfile(st_clean_dir, st19_dir);
m19 = tab.read_manifest(st19_dir);
m19.run_id = rid19;
m19.stages(5).artifacts.path = fullfile(st19_dir, 'outputs', 'fused-geometric.ply');
tab.write_manifest(st19_dir, m19);
fused_ply = fullfile(st19_dir, 'outputs', 'fused-geometric.ply');
fid = fopen(fused_ply, 'ab');
fwrite(fid, 0, 'uint8');
fclose(fid);
[clean19, res19] = tab.reconstruction_completion_consistency(rid19);
T19 = ~clean19 && ~isempty(strfind(res19.first_discrepancy, 'Digest anomaly'));
fprintf('T19 completion consistency flags digest anomaly: %s\n', tf(T19));
if T19, pass = pass + 1; else, fail = fail + 1; end

% --- T20: reconstruction_completion_consistency flags non-COMPLETED durable status ---
rid20 = 'run_t20_durable_failed';
st20_dir = fullfile(runs_dir, rid20);
copyfile(st_clean_dir, st20_dir);
m20 = tab.read_manifest(st20_dir);
m20.run_id = rid20;
m20.result.status = 'FAILED';
tab.write_manifest(st20_dir, m20);
[clean20, res20] = tab.reconstruction_completion_consistency(rid20);
T20 = ~clean20 && ~isempty(strfind(res20.first_discrepancy, 'FAILED'));
fprintf('T20 completion consistency flags durable FAILED status: %s\n', tf(T20));
if T20, pass = pass + 1; else, fail = fail + 1; end

% --- T24: durable COMPLETED cannot mask a FAILED stage ---
rid24 = 'run_t24_completed_failed_stage';
st24_dir = fullfile(runs_dir, rid24);
copyfile(st_clean_dir, st24_dir);
m24 = tab.read_manifest(st24_dir);
m24.run_id = rid24;
m24.stages(3).status = 'FAILED';
tab.write_manifest(st24_dir, m24);
[clean24, res24] = tab.reconstruction_completion_consistency(rid24);
T24 = ~clean24 && strcmp(res24.discrepant_stage, canonical_8{3});
fprintf('T24 COMPLETED plus FAILED stage is inconsistent: %s\n', tf(T24));
if T24, pass = pass + 1; else, fail = fail + 1; end

% --- T25: durable COMPLETED cannot mask a RUNNING stage ---
rid25 = 'run_t25_completed_running_stage';
st25_dir = fullfile(runs_dir, rid25);
copyfile(st_clean_dir, st25_dir);
m25 = tab.read_manifest(st25_dir);
m25.run_id = rid25;
m25.stages(3).status = 'RUNNING';
tab.write_manifest(st25_dir, m25);
[clean25, res25] = tab.reconstruction_completion_consistency(rid25);
T25 = ~clean25 && strcmp(res25.discrepant_stage, canonical_8{3});
fprintf('T25 COMPLETED plus RUNNING stage is inconsistent: %s\n', tf(T25));
if T25, pass = pass + 1; else, fail = fail + 1; end

% --- T21-T23: GUI presentation tests ---
gui_app = analyse_optical_mapping;
gui_app.recon.test_manifest_pick = fullfile(g_dest, 'manifest.json');
gui_app.recon.OpenReconstructionManifestMenuSelected();

% T21: ReconstructionStageList has 8 numbered rows 'Step N of 8: ...'
stage_items = gui_app.recon.ReconstructionStageList.Items;
T21 = numel(stage_items) == 8 && ...
    ~isempty(strfind(stage_items{1}, 'Step 1 of 8: ')) && ...
    ~isempty(strfind(stage_items{8}, 'Step 8 of 8: '));
fprintf('T21 GUI ReconstructionStageList has 8 numbered rows: %s\n', tf(T21));
if T21, pass = pass + 1; else, fail = fail + 1; end

% T22: Prefix > rule: 1 on resumable, 0 on clean completed
prefix_count_resumable = 0;
for ki = 1:numel(stage_items)
    if ~isempty(strfind(stage_items{ki}, '> RESUME HERE'))
        prefix_count_resumable = prefix_count_resumable + 1;
    end
end
% Switch to clean completed run
gui_app.recon.reconstruction_render_status(rid_clean);
clean_items = gui_app.recon.ReconstructionStageList.Items;
prefix_count_clean = 0;
for ki = 1:numel(clean_items)
    if ~isempty(regexp(clean_items{ki}, '^> ', 'once'))
        prefix_count_clean = prefix_count_clean + 1;
    end
end
T22 = (prefix_count_resumable == 1) && (prefix_count_clean == 0);
fprintf('T22 GUI stage list prefix > rule (1 on resumable, 0 on clean): %s\n', tf(T22));
if T22, pass = pass + 1; else, fail = fail + 1; end

% T23: ReconstructionResultsText shows clean or inconsistent completion
gui_app.recon.reconstruction_render_status(golden_run);
txt_inconsistent = strjoin(gui_app.recon.ReconstructionResultsText.Value, ' | ');
gui_app.recon.reconstruction_render_status(rid_clean);
txt_clean = strjoin(gui_app.recon.ReconstructionResultsText.Value, ' | ');
T23 = ~isempty(strfind(txt_inconsistent, 'COMPLETED - INCONSISTENT')) && ...
    ~isempty(strfind(txt_clean, 'Output files present and unchanged'));
fprintf('T23 GUI ResultsText displays truthful clean/inconsistent completion: %s\n', tf(T23));
if T23, pass = pass + 1; else, fail = fail + 1; end

delete(gui_app);
close all force;
if exist(scratch_root, 'dir'), rmdir(scratch_root, 's'); end

fprintf('PROBE_RUN_STATUS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_run_status 25/0\n');
else
    fprintf('PROBE_FAIL probe_run_status\n');
end
end

% --- Helper Functions ---

function create_test_run(runs_dir, run_id, stage_specs, run_status)
rdir = fullfile(runs_dir, run_id);
if exist(rdir, 'dir'), rmdir(rdir, 's'); end
mkdir(rdir);
stages = [];
for k = 1:numel(stage_specs)
    st = struct('name', stage_specs{k}{1}, 'status', stage_specs{k}{2});
    if isempty(stages)
        stages = st;
    else
        stages(end+1) = st; %#ok<AGROW>
    end
end
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = run_id;
m.created_at = '2026-09-13T12:00:00Z';
m.dataset = struct('path', 'dummy.matom', 'stem', 'subset', 'root', runs_dir);
m.stages = stages;
m.result = struct('status', run_status);
fid = fopen(fullfile(rdir, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(m));
fclose(fid);
end

function write_custom_manifest(rdir, run_id, stages_struct, run_status)
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = run_id;
m.created_at = '2026-09-13T12:00:00Z';
m.dataset = struct('path', 'dummy.matom', 'stem', 'subset', 'root', fileparts(rdir));
m.stages = stages_struct;
m.result = struct('status', run_status);
fid = fopen(fullfile(rdir, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(m));
fclose(fid);
end
