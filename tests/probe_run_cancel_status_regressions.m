function probe_run_cancel_status_regressions
%% Cancellation and status persistence regressions
% Collin Snitchler
% 14.09.2026
% Exercises run_stage/run_pipeline and the GUI Cancel callback with a
% a controllable external executor; no external reconstruction process runs.

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));

scratch_root = fullfile(tempdir, ['om_test_probe_run_cancel_status_regressions_' char(java.util.UUID.randomUUID)]);
cleanup = onCleanup(@() cleanup_scratch(scratch_root)); %#ok<NASGU>
mkdir(scratch_root);
stem = 'subset';
runs_dir = fullfile(scratch_root, [stem '.matom'], 'reconstruction', 'runs');
mkdir(runs_dir);

results = false(1, 12);
labels = cell(1, 12);
idx = 0;

% The checked status transition methods must exist.
tab = stage_runner_double();
[load_ok, load_err] = tab.load_state(scratch_root, stem);
assert(load_ok, load_err);
[idx, results, labels] = record_case(idx, results, labels, ...
    'checked terminal transition API exists', ...
    ismethod(tab, 'commit_run_status') && ismethod(tab, 'confirm_run_status'));

% A cancel request alone cannot write a durable CANCELLED.
rid_direct = 'run_direct_cancel';
create_test_run(runs_dir, rid_direct, {}, 'RUNNING');
[cancel_ok, ~] = tab.cancel_run(rid_direct);
m_direct = tab.read_manifest(fullfile(runs_dir, rid_direct));
[idx, results, labels] = record_case(idx, results, labels, ...
    'cancel_run refuses without observed exit-130 stage result', ...
    ~cancel_ok && strcmp(m_direct.result.status, 'RUNNING'));

% The Cancel callback runs while the injected runner is still active, then
% run_stage records exit 130 and run_pipeline finalises the run.
rid_cb = 'run_callback_cancel';
create_test_run(runs_dir, rid_cb, {}, 'RUNNING');
tab.record_run(rid_cb, 'RUNNING');
app = analyse_optical_mapping;
if ismethod(app, 'bind_reconstruction_tab_for_test')
    app.bind_reconstruction_tab_for_test(tab);
    app.recon.ReconstructionDatasetField.Value = fullfile(scratch_root, stem);
    app.recon.ReconstructionRunList.Items = {[rid_cb ' [RUNNING]']};
    app.recon.ReconstructionRunList.Value = [rid_cb ' [RUNNING]'];
    tab.gui_app = app;
    tab.observed_run_dir = fullfile(runs_dir, rid_cb);
    tab.execution_mode = 'callback_exit130';
    [pipe_ok, pipe_err] = tab.run_pipeline(rid_cb, struct('start_stage', 'stereo_fusion'));
    m_cb = tab.read_manifest(fullfile(runs_dir, rid_cb));
    first_text = join_text(tab.observed_results_during_spawn);
    second_text = join_text(tab.observed_results_after_second);
    callback_transient = strcmp(tab.observed_status_during_spawn, 'RUNNING') && ...
        contains(first_text, 'CANCELLING') && tab.cancel_request_count == 1;
    double_transient = strcmp(tab.observed_status_after_second, 'RUNNING') && ...
        ~contains(second_text, 'status: CANCELLED') && tab.cancel_request_count == 1;
    final_cancelled = ~pipe_ok && strcmp(m_cb.result.status, 'CANCELLED') && ...
        strcmp(m_cb.stages(end).status, 'CANCELLED') && ...
        m_cb.stages(end).validation.exit_code == 130;
    truthful_copy = contains(pipe_err, 'cannot be confirmed that every helper program') && ...
        ~contains(lower(pipe_err), 'child tree terminated');
else
    callback_transient = false;
    double_transient = false;
    final_cancelled = false;
    truthful_copy = false;
end
[idx, results, labels] = record_case(idx, results, labels, ...
    'Cancel callback is transient while runner remains active', callback_transient);
[idx, results, labels] = record_case(idx, results, labels, ...
    'double Cancel remains non-terminal before runner return', double_transient);
[idx, results, labels] = record_case(idx, results, labels, ...
    'exit 130 traverses run_stage and finalises checked CANCELLED', final_cancelled);
[idx, results, labels] = record_case(idx, results, labels, ...
    'cancellation copy never confirms descendant termination', truthful_copy);

delete(app);
close all force;

% A failure to save the manifest status fails closed.
rid_mfail = 'run_manifest_failure';
create_test_run(runs_dir, rid_mfail, {}, 'RUNNING');
tab_mfail = stage_runner_double();
tab_mfail.load_state(scratch_root, stem);
tab_mfail.execution_mode = 'exit130';
tab_mfail.fail_set_status = true;
[ok_mfail, err_mfail] = tab_mfail.run_pipeline(rid_mfail, struct('start_stage', 'stereo_fusion'));
[idx, results, labels] = record_case(idx, results, labels, ...
    'manifest terminal write failure reports STATE NOT CONFIRMED', ...
    ~ok_mfail && contains(err_mfail, 'STATE NOT CONFIRMED'));

% A failure to save the tab state fails closed.
rid_sfail = 'run_state_failure';
create_test_run(runs_dir, rid_sfail, {}, 'RUNNING');
tab_sfail = stage_runner_double();
tab_sfail.load_state(scratch_root, stem);
tab_sfail.execution_mode = 'exit130';
tab_sfail.fail_record_run = true;
[ok_sfail, err_sfail] = tab_sfail.run_pipeline(rid_sfail, struct('start_stage', 'stereo_fusion'));
[idx, results, labels] = record_case(idx, results, labels, ...
    'tab-state terminal write failure reports STATE NOT CONFIRMED', ...
    ~ok_sfail && contains(err_sfail, 'STATE NOT CONFIRMED'));

% A failure to read the status back fails closed.
rid_rfail = 'run_readback_failure';
create_test_run(runs_dir, rid_rfail, {}, 'RUNNING');
tab_rfail = stage_runner_double();
tab_rfail.load_state(scratch_root, stem);
tab_rfail.execution_mode = 'exit130';
tab_rfail.fail_confirmation = true;
[ok_rfail, err_rfail] = tab_rfail.run_pipeline(rid_rfail, struct('start_stage', 'stereo_fusion'));
[idx, results, labels] = record_case(idx, results, labels, ...
    'terminal read-back failure reports STATE NOT CONFIRMED', ...
    ~ok_rfail && contains(err_rfail, 'STATE NOT CONFIRMED'));

% A timeout or ordinary failure is FAILED, never CANCELLED, and the
% stopping of child processes is not overclaimed.
rid_timeout = 'run_timeout';
create_test_run(runs_dir, rid_timeout, {}, 'RUNNING');
tab_timeout = stage_runner_double();
tab_timeout.load_state(scratch_root, stem);
tab_timeout.execution_mode = 'timeout124';
[ok_timeout, err_timeout] = tab_timeout.run_pipeline(rid_timeout, struct('start_stage', 'stereo_fusion'));
m_timeout = tab_timeout.read_manifest(fullfile(runs_dir, rid_timeout));
[idx, results, labels] = record_case(idx, results, labels, ...
    'timeout 124 remains FAILED with UNVERIFIED process-tree state', ...
    ~ok_timeout && strcmp(m_timeout.result.status, 'FAILED') && ...
    m_timeout.stages(end).validation.exit_code == 124 && contains(err_timeout, 'cannot be confirmed that every helper program'));

rid_exit = 'run_exit1';
create_test_run(runs_dir, rid_exit, {}, 'RUNNING');
tab_exit = stage_runner_double();
tab_exit.load_state(scratch_root, stem);
tab_exit.execution_mode = 'exit1';
[ok_exit, ~] = tab_exit.run_pipeline(rid_exit, struct('start_stage', 'stereo_fusion'));
m_exit = tab_exit.read_manifest(fullfile(runs_dir, rid_exit));
[idx, results, labels] = record_case(idx, results, labels, ...
    'non-cancel nonzero exit remains FAILED', ...
    ~ok_exit && strcmp(m_exit.result.status, 'FAILED') && ...
    m_exit.stages(end).validation.exit_code == 1);

% No reachable backend copy claims that a child process tree was stopped.
backend_text = read_utf8_text(fullfile(repo_dir, 'rabbit_reconstruction_tab.m'));
[idx, results, labels] = record_case(idx, results, labels, ...
    'backend contains no child-tree termination confirmation', ...
    ~contains(lower(backend_text), 'child tree terminated'));

pass_count = sum(results);
fail_count = numel(results) - pass_count;
fprintf('PROBE_RUN_CANCEL_STATUS_REGRESSIONS RESULT: %d passed, %d failed\n', pass_count, fail_count);
if fail_count == 0
    fprintf('PROBE_OK probe_run_cancel_status_regressions %d/0\n', pass_count);
else
    fprintf('PROBE_FAIL probe_run_cancel_status_regressions\n');
    failed = labels(~results);
    error('analyse_om:Reconstruction:RegressionCheck', 'Failed: %s', strjoin(failed, '; '));
end
end

function [idx, results, labels] = record_case(idx, results, labels, label, condition)
idx = idx + 1;
results(idx) = logical(condition);
labels{idx} = label;
fprintf('R%d %s: %s\n', idx, label, tf(condition));
end

function out = tf(value)
if value, out = 'PASS'; else, out = 'FAIL'; end
end

function text = join_text(value)
if ischar(value), text = value; return; end
if isstring(value), text = char(strjoin(value, ' | ')); return; end
if iscell(value), text = strjoin(cellfun(@char, value, 'UniformOutput', false), ' | '); return; end
text = '';
end

function create_test_run(runs_dir, run_id, stage_specs, run_status)
run_dir = fullfile(runs_dir, run_id);
if exist(run_dir, 'dir'), rmdir(run_dir, 's'); end
mkdir(run_dir);
stages = struct('name', {}, 'status', {});
for k = 1:numel(stage_specs)
    stages(end+1) = struct('name', stage_specs{k}{1}, 'status', stage_specs{k}{2}); %#ok<AGROW>
end
manifest = struct();
manifest.manifest_schema = 'cd2.reconstruction.manifest.v1';
manifest.run_id = run_id;
manifest.created_at = '2026-09-13T12:00:00Z';
manifest.dataset = struct('path', 'dummy.matom', 'stem', 'subset', 'root', runs_dir);
manifest.stages = stages;
manifest.result = struct('status', run_status);
fid = fopen(fullfile(run_dir, 'manifest.json'), 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Could not create synthetic manifest.');
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(manifest), 'char*1');
end

function text = read_utf8_text(path)
fid = fopen(path, 'r', 'n', 'UTF-8');
assert(fid >= 0, 'Could not open project UTF-8 text: %s', path);
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fread(fid, Inf, '*char')';
end

function cleanup_scratch(path)
if exist(path, 'dir'), rmdir(path, 's'); end
end
