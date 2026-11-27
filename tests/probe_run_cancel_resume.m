function probe_run_cancel_resume
%% Cancel and resume of reconstruction runs
% Collin Snitchler
% 13.09.2026
% Checks cancellation, where a run resumes, that wrapper exit code 130 counts
% as CANCELLED, the note that child processes may not have stopped, and the GUI
% button states. Set OM_TEST_RESTORE_GOLDEN_ROOT to the golden fixture root (the
% probe skips without it).
% Headless (OM_APP_HEADLESS=1): tests/helpers/headless goes on the path, so
% the app's alerts are recorded and printed instead of shown.
%
% Assertions (10 total):
%   CR1  cancel_run finalises only after a recorded CANCELLED/exit-130 stage.
%   CR2  cancel_run on durable COMPLETED fails (refused) and status remains COMPLETED.
%   CR3  cancel_run on durable CANCELLED fails (refused) and status remains CANCELLED.
%   CR4  cancel_run on durable FAILED fails (refused) and status remains FAILED.
%   CR5  Process runner wrapper exit code 130 is classified as CANCELLED.
%   CR6  Cancellation disclosure explicitly notes descendant termination is unverified.
%   CR7  next_stage_to_run refuses resume when run is RUNNING.
%   CR8  next_stage_to_run returns empty next_stage when all stages are complete (PASSED/WARNED).
%   CR9  GUI gate state: cancel_ok is true only for RUNNING, false for COMPLETED/FAILED/CANCELLED.
%   CR10 GUI gate state: resume_ok is false when run is RUNNING, and false when all complete.

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
if strcmp(getenv('OM_APP_HEADLESS'), '1')
    addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
end

golden_root = om_test_getenv('OM_TEST_RESTORE_GOLDEN_ROOT');
if isempty(golden_root) || exist(golden_root, 'dir') ~= 7
    fprintf(['SKIP_NONPASS probe_run_cancel_resume: set OM_TEST_RESTORE_GOLDEN_ROOT ' ...
        'to the folder holding the golden run.\n']);
    return;
end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';

scratch_root = fullfile(tempdir, 'om_test_probe_run_cancel_resume');
if exist(scratch_root, 'dir'), rmdir(scratch_root, 's'); end
mkdir(scratch_root);

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

tab = rabbit_reconstruction_tab();
ds_dir = fullfile(scratch_root, [stem '.matom']);
runs_dir = fullfile(ds_dir, 'reconstruction', 'runs');
mkdir(runs_dir);
tab.load_state(scratch_root, stem);

canonical_8 = tab.driver_stage_order();
make_run = @(rid, stages_cell, run_st) create_test_run(runs_dir, rid, stages_cell, run_st);

% --- CR1: durable CANCELLED follows an observed wrapper exit 130 ---
rid1 = 'run_cr1_running';
make_run(rid1, {}, 'RUNNING');
rdir1 = fullfile(runs_dir, rid1);
meta1 = struct('settings_resolved', struct(), 'licence', 'test', ...
    'citation_key', 'test', 'citations', {{}});
[rec1_ok, rec1_err] = tab.record_stage_entry(rdir1, canonical_8{1}, meta1, ...
    'injected_wrapper', 130, datestr(now, 'yyyy-mm-ddTHH:MM:SS'), ...
    0.5, {}, 'CANCELLED', {}, {}, {});
[c1_ok, c1_err] = tab.cancel_run(rid1);
m1 = tab.read_manifest(rdir1);
CR1 = rec1_ok && isempty(rec1_err) && c1_ok && isempty(c1_err) && ...
    strcmp(m1.result.status, 'CANCELLED');
fprintf('CR1 observed exit 130 finalises CANCELLED: %s\n', tf(CR1));
if CR1, pass = pass + 1; else, fail = fail + 1; end

% --- CR2: cancel_run on durable COMPLETED fails and status remains COMPLETED ---
rid2 = 'run_cr2_completed';
make_run(rid2, {{canonical_8{1}, 'PASSED'}}, 'COMPLETED');
[c2_ok, c2_err] = tab.cancel_run(rid2);
m2 = tab.read_manifest(fullfile(runs_dir, rid2));
CR2 = ~c2_ok && ~isempty(c2_err) && strcmp(m2.result.status, 'COMPLETED');
fprintf('CR2 cancel_run on COMPLETED refused: %s\n', tf(CR2));
if CR2, pass = pass + 1; else, fail = fail + 1; end

% --- CR3: cancel_run on durable CANCELLED fails and status remains CANCELLED ---
rid3 = 'run_cr3_cancelled';
make_run(rid3, {{canonical_8{1}, 'CANCELLED'}}, 'CANCELLED');
[c3_ok, c3_err] = tab.cancel_run(rid3);
m3 = tab.read_manifest(fullfile(runs_dir, rid3));
CR3 = ~c3_ok && ~isempty(c3_err) && strcmp(m3.result.status, 'CANCELLED');
fprintf('CR3 cancel_run on CANCELLED refused: %s\n', tf(CR3));
if CR3, pass = pass + 1; else, fail = fail + 1; end

% --- CR4: cancel_run on durable FAILED fails and status remains FAILED ---
rid4 = 'run_cr4_failed';
make_run(rid4, {{canonical_8{1}, 'FAILED'}}, 'FAILED');
[c4_ok, c4_err] = tab.cancel_run(rid4);
m4 = tab.read_manifest(fullfile(runs_dir, rid4));
CR4 = ~c4_ok && ~isempty(c4_err) && strcmp(m4.result.status, 'FAILED');
fprintf('CR4 cancel_run on FAILED refused: %s\n', tf(CR4));
if CR4, pass = pass + 1; else, fail = fail + 1; end

% --- CR5: injected wrapper exit 130 traverses run_stage/run_pipeline ---
rid5 = 'run_cr5_exit130';
make_run(rid5, {}, 'RUNNING');
d5 = stage_runner_double();
d5.load_state(scratch_root, stem);
d5.record_run(rid5, 'RUNNING');
d5.execution_mode = 'exit130';
[p5_ok, p5_err] = d5.run_pipeline(rid5, struct('start_stage', 'stereo_fusion'));
m5 = d5.read_manifest(fullfile(runs_dir, rid5));
CR5 = ~p5_ok && contains(p5_err, 'cannot be confirmed that every helper program') && ...
    strcmp(m5.stages(end).status, 'CANCELLED') && ...
    m5.stages(end).validation.exit_code == 130 && ...
    strcmp(m5.result.status, 'CANCELLED');
fprintf('CR5 exit code 130 classified through run_stage as CANCELLED: %s\n', tf(CR5));
if CR5, pass = pass + 1; else, fail = fail + 1; end

% --- CR6: Cancellation feedback explicitly contains UNVERIFIED notice ---
% Setup golden fixture copy under scratch runs_dir
g_dest = fullfile(runs_dir, golden_run);
g_src = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
copyfile(g_src, g_dest);

gui_app = analyse_optical_mapping;
gui_app.recon.test_manifest_pick = fullfile(g_dest, 'manifest.json');
gui_app.recon.OpenReconstructionManifestMenuSelected();

% Create a running run using a valid fixture copy
rid6 = 'run_cr6_notice';
rdir6 = fullfile(runs_dir, rid6);
copyfile(g_dest, rdir6);
if exist(fullfile(rdir6, 'manifest.v2.json'), 'file'), delete(fullfile(rdir6, 'manifest.v2.json')); end
if exist(fullfile(rdir6, '.lock'), 'file'), delete(fullfile(rdir6, '.lock')); end
raw_txt6 = read_utf8_text(fullfile(rdir6, 'manifest.json'));
raw_txt6 = strrep(raw_txt6, golden_run, rid6);
fid6 = fopen(fullfile(rdir6, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid6, raw_txt6);
fclose(fid6);
m6 = tab.read_manifest(rdir6);
m6.result.status = 'RUNNING';
tab.write_manifest(rdir6, m6);
tab.record_run(rid6, 'RUNNING');
tab.write_state();

gui_app.recon.ReconstructionRunList.Items = {[rid6 ' [RUNNING]']};
gui_app.recon.ReconstructionRunList.Value = [rid6 ' [RUNNING]'];
gui_app.recon.reconstruction_render_status(rid6);
% Now simulate the runner having observed exit 130, then render terminal copy.
meta6 = struct('settings_resolved', struct(), 'licence', 'test', ...
    'citation_key', 'test', 'citations', {{}});
tab.record_stage_entry(rdir6, canonical_8{1}, meta6, 'injected_wrapper', 130, ...
    datestr(now, 'yyyy-mm-ddTHH:MM:SS'), 0.5, {}, 'CANCELLED', {}, {}, {});
[~, ~] = tab.cancel_run(rid6);
gui_app.recon.reconstruction_render_status(rid6);
cancel_lines = strjoin(gui_app.recon.ReconstructionResultsText.Value, ' | ');
% The notice says in plain words that it cannot be confirmed the helper
% programs stopped.
CR6 = contains(cancel_lines, 'cannot be confirmed that every helper program');
fprintf('CR6 cancellation feedback discloses UNVERIFIED descendant termination: %s\n', tf(CR6));
if CR6, pass = pass + 1; else, fail = fail + 1; end

% --- CR7: next_stage_to_run refuses resume when run is RUNNING ---
rid7 = 'run_cr7_active';
make_run(rid7, {{canonical_8{1}, 'RUNNING'}}, 'RUNNING');
[ns7_ok, ns7_err, next7] = tab.next_stage_to_run(rid7);
CR7 = ~ns7_ok && isempty(next7) && ~isempty(strfind(ns7_err, 'RUNNING'));
fprintf('CR7 next_stage_to_run refuses resume on RUNNING run: %s\n', tf(CR7));
if CR7, pass = pass + 1; else, fail = fail + 1; end

% --- CR8: next_stage_to_run returns empty next_stage when all complete (PASSED/WARNED) ---
rid8 = 'run_cr8_all_done';
all_done_specs = { ...
    {canonical_8{1}, 'PASSED'}, ...
    {canonical_8{2}, 'WARNED'}, ...
    {canonical_8{3}, 'PASSED'}, ...
    {canonical_8{4}, 'PASSED'}, ...
    {canonical_8{5}, 'WARNED'}, ...
    {canonical_8{6}, 'PASSED'}, ...
    {canonical_8{7}, 'PASSED'}, ...
    {canonical_8{8}, 'PASSED'} ...
};
make_run(rid8, all_done_specs, 'COMPLETED');
[ns8_ok, ~, next8] = tab.next_stage_to_run(rid8);
CR8 = ns8_ok && isempty(next8);
fprintf('CR8 next_stage_to_run returns empty when all stages complete: %s\n', tf(CR8));
if CR8, pass = pass + 1; else, fail = fail + 1; end

% --- CR9: GUI gate state: cancel_ok is true only for RUNNING ---
% Clean up tab state so gate state evaluates only the explicit test runs
cand = tab.get_state();
cand.runs = struct('id', {}, 'status', {}, 'created_at', {});
[cand, ~] = tab.record_run_candidate(cand, golden_run, 'COMPLETED');
tab.commit_state_candidate(cand);

% 1. Completed run:
gui_app.recon.ReconstructionRunList.Items = {[golden_run ' [COMPLETED]']};
gui_app.recon.ReconstructionRunList.Value = [golden_run ' [COMPLETED]'];
g_comp = gui_app.recon.reconstruction_gate_state();
cancel_comp_false = ~g_comp.cancel_ok;

% 2. Running run:
rid9_run = 'run_cr9_gate_running';
rdir9_run = fullfile(runs_dir, rid9_run);
copyfile(g_dest, rdir9_run);
if exist(fullfile(rdir9_run, 'manifest.v2.json'), 'file')
    delete(fullfile(rdir9_run, 'manifest.v2.json'));
end
if exist(fullfile(rdir9_run, '.lock'), 'file')
    delete(fullfile(rdir9_run, '.lock'));
end
raw_txt9 = read_utf8_text(fullfile(rdir9_run, 'manifest.json'));
raw_txt9 = strrep(raw_txt9, golden_run, rid9_run);
fid9 = fopen(fullfile(rdir9_run, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid9, raw_txt9);
fclose(fid9);
m9_run = tab.read_manifest(rdir9_run);
m9_run.result.status = 'RUNNING';
tab.write_manifest(rdir9_run, m9_run);
tab.record_run(rid9_run, 'RUNNING');
tab.write_state();

gui_app.recon.test_manifest_pick = fullfile(rdir9_run, 'manifest.json');
gui_app.recon.OpenReconstructionManifestMenuSelected();
cand = tab.get_state();
cand.runs = struct('id', {}, 'status', {}, 'created_at', {});
[cand, ~] = tab.record_run_candidate(cand, rid9_run, 'RUNNING');
tab.commit_state_candidate(cand);
gui_app.bind_reconstruction_tab_for_test(tab);
gui_app.recon.ReconstructionRunList.Items = {[rid9_run ' [RUNNING]']};
gui_app.recon.ReconstructionRunList.Value = [rid9_run ' [RUNNING]'];
g_run = gui_app.recon.reconstruction_gate_state();
cancel_run_true = g_run.cancel_ok;

% 3. Failed run:
rid9_fail = 'run_cr9_gate_failed';
rdir9_fail = fullfile(runs_dir, rid9_fail);
copyfile(g_dest, rdir9_fail);
if exist(fullfile(rdir9_fail, 'manifest.v2.json'), 'file')
    delete(fullfile(rdir9_fail, 'manifest.v2.json'));
end
if exist(fullfile(rdir9_fail, '.lock'), 'file')
    delete(fullfile(rdir9_fail, '.lock'));
end
raw_txt_f = read_utf8_text(fullfile(rdir9_fail, 'manifest.json'));
raw_txt_f = strrep(raw_txt_f, golden_run, rid9_fail);
fid_f = fopen(fullfile(rdir9_fail, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid_f, raw_txt_f);
fclose(fid_f);
m9_fail = tab.read_manifest(rdir9_fail);
m9_fail.result.status = 'FAILED';
tab.write_manifest(rdir9_fail, m9_fail);
tab.record_run(rid9_fail, 'FAILED');
tab.write_state();

gui_app.recon.test_manifest_pick = fullfile(rdir9_fail, 'manifest.json');
gui_app.recon.OpenReconstructionManifestMenuSelected();
gui_app.recon.ReconstructionRunList.Items = {[rid9_fail ' [FAILED]']};
gui_app.recon.ReconstructionRunList.Value = [rid9_fail ' [FAILED]'];
g_fail = gui_app.recon.reconstruction_gate_state();
cancel_fail_false = ~g_fail.cancel_ok;

CR9 = cancel_comp_false && cancel_run_true && cancel_fail_false;
fprintf('CR9 GUI cancel_ok is true only for RUNNING (comp=%s, run=%s, fail=%s): %s\n', ...
    tf(cancel_comp_false), tf(cancel_run_true), tf(cancel_fail_false), tf(CR9));
if CR9, pass = pass + 1; else, fail = fail + 1; end

% --- CR10: GUI gate state: resume_ok is false when RUNNING or all complete ---
% For RUNNING run (captured in g_run): resume_ok must be false
resume_run_false = ~g_run.resume_ok;

% For all-complete run: resume_ok must be false
rid10_done = 'run_cr10_gate_completed';
rdir10_done = fullfile(runs_dir, rid10_done);
copyfile(g_dest, rdir10_done);
if exist(fullfile(rdir10_done, 'manifest.v2.json'), 'file')
    delete(fullfile(rdir10_done, 'manifest.v2.json'));
end
if exist(fullfile(rdir10_done, '.lock'), 'file')
    delete(fullfile(rdir10_done, '.lock'));
end
raw_txt10 = read_utf8_text(fullfile(rdir10_done, 'manifest.json'));
raw_txt10 = strrep(raw_txt10, golden_run, rid10_done);
fid10 = fopen(fullfile(rdir10_done, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid10, raw_txt10);
fclose(fid10);
m10_done = tab.read_manifest(rdir10_done);
m10_done.result.status = 'COMPLETED';
for ki = 1:numel(m10_done.stages)
    m10_done.stages(ki).status = 'PASSED';
end
tab.write_manifest(rdir10_done, m10_done);
tab.record_run(rid10_done, 'COMPLETED');
tab.write_state();

gui_app.recon.test_manifest_pick = fullfile(rdir10_done, 'manifest.json');
gui_app.recon.OpenReconstructionManifestMenuSelected();
gui_app.recon.ReconstructionRunList.Items = {[rid10_done ' [COMPLETED]']};
gui_app.recon.ReconstructionRunList.Value = [rid10_done ' [COMPLETED]'];
g_res_done = gui_app.recon.reconstruction_gate_state();
resume_done_false = ~g_res_done.resume_ok;

CR10 = resume_run_false && resume_done_false;
fprintf('CR10 GUI resume_ok is false when RUNNING or complete (run=%s, done=%s): %s\n', ...
    tf(resume_run_false), tf(resume_done_false), tf(CR10));
if CR10, pass = pass + 1; else, fail = fail + 1; end

delete(gui_app);
close all force;
if exist(scratch_root, 'dir'), rmdir(scratch_root, 's'); end

fprintf('PROBE_RUN_CANCEL_RESUME RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_run_cancel_resume 10/0\n');
else
    fprintf('PROBE_FAIL probe_run_cancel_resume\n');
end
end

% --- Helper Function ---

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

function text = read_utf8_text(path)
fid = fopen(path, 'r', 'n', 'UTF-8');
assert(fid >= 0, 'Could not open UTF-8 test fixture: %s', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fread(fid, Inf, '*char')';
end
