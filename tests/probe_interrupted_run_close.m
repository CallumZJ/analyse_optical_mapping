function probe_interrupted_run_close
%% Probe: closing a RUNNING run whose owner is provably gone
% Collin Snitchler
% 02.11.2026
% After a crash a manifest stays RUNNING with a dead lock, and Cancel could
% not clear it: nothing wrote CANCELLED, the run showed CANCELLING for the
% session, and every action in the dataset folder stayed blocked.
% close_interrupted_run writes INTERRUPTED only with proof, and says nothing
% about the helper programs. The runs are made here; no fixture is needed.
%   B1  dead lock: manifest and tab state INTERRUPTED, survives a new tab
%   B2  the record leaves child processes NOT_CHECKED and is never CANCELLED
%   B3  a run that crashed in its first step (no stage records) still opens
%   B4  a half-written PLY left by the crash does not make the run unreadable
%   B5  a stage record left RUNNING is closed, and Resume finds that stage
%   B6  LIVE lock is refused and nothing changes
%   B7  lock with no process id is refused and nothing changes
%   B8  lock of another computer is UNAVAILABLE, refused, nothing changes
%   B9  no lock, or the lock of another run, proves nothing: refused
%   B10 COMPLETED, FAILED and CANCELLED are refused and unchanged
%   B11 failed manifest write: STATE NOT CONFIRMED, run still RUNNING
%   B12 failed tab-state write is reported, and a repeat finishes the close
%   B13 a run in its v2 sidecar closes and stays valid
%   B14 Resume takes the lock over: the resumed run is LIVE, not closable
%   B15 a second interruption keeps the first record
%   B16 liveness that gets no answer from tasklist is UNAVAILABLE (Windows)
%   G1  Cancel on a dead-lock run closes it; nothing stays blocked
%   G2  'Keep it' changes nothing
%   G3  a pending request whose owner died no longer shows CANCELLING
%   G4  two interrupted runs: closing one still blocks, closing both frees
%   G5  Cancel on an UNAVAILABLE lock writes nothing and sets no pending
%   G6  Refresh finishes a close whose tab-state write failed
%   G7  Cancel while this session's pipeline runs stays a stop request,
%       even when the lock names a dead process
% Usage: set OM_APP_HEADLESS=1, then
%   matlab -batch "addpath('<repo>/tests'); probe_interrupted_run_close" -noFigureWindows
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests'));
addpath(fullfile(repo_dir, 'tests', 'helpers'));
if strcmp(getenv('OM_APP_HEADLESS'), '1')
    addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
end

root = tempname(tempdir);
mkdir(root);
cleanup = onCleanup(@() remove_root(root)); %#ok<NASGU>
stem = 'subset';
runs_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs');
mkdir(runs_dir);
order = rabbit_reconstruction_tab().driver_stage_order();
tab = tab_failure_doubles();
tab.load_state(root, stem);
dead = dead_pid(tab, runs_dir);
s = struct('pass', 0, 'fail', 0);

% ---- B1 B2: the transition and its record ----
rid = 'run_b1';
make_run(tab, runs_dir, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
[ok, err] = tab.close_interrupted_run(rid);
m = read_disk(runs_dir, rid);
tab2 = rabbit_reconstruction_tab();
tab2.load_state(root, stem);
[conf_ok, conf_err] = tab2.confirm_run_status(rid, 'INTERRUPTED');
s = check(s, 'B1 dead lock closes in both stores and survives a new tab', ...
    ok && isempty(err) && strcmp(m.result.status, 'INTERRUPTED') && conf_ok, [err conf_err]);
rec = m.result.interruptions(end);
s = check(s, 'B2 record leaves the children unchecked and never says cancelled', ...
    strcmp(rec.child_processes, 'NOT_CHECKED') && rec.lock_pid == dead && ...
    contains(rec.note, 'cannot be confirmed') && ~contains(fileread(manifest_of(runs_dir, rid)), 'CANCELLED'), '');

% ---- B3 B4: what a crash leaves must stay readable ----
rid = 'run_b3';
make_run(tab, runs_dir, rid, {}, lock_text(dead, rid));
[ok, err] = tab.close_interrupted_run(rid);
[o_ok, o_err, info] = rabbit_reconstruction_tab().open_manifest(manifest_of(runs_dir, rid));
s = check(s, 'B3 no stage records: closes and opens as INTERRUPTED', ...
    ok && o_ok && strcmp(info.result_status, 'INTERRUPTED'), [err o_err]);

rid = 'run_b4';
make_run(tab, runs_dir, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
mkdir(fullfile(runs_dir, rid, 'outputs'));
write_text(fullfile(runs_dir, rid, 'outputs', 'fused-geometric.ply'), sprintf('ply\nformat ascii 1.0\nelement vert'));
[ok, err] = tab.close_interrupted_run(rid);
s = check(s, 'B4 half-written PLY does not make the run unreadable', ok, err);

% ---- B5: stage record left RUNNING ----
rid = 'run_b5';
make_run(tab, runs_dir, rid, {order{1}, 'PASSED'; order{2}, 'RUNNING'}, lock_text(dead, rid));
[ok, err] = tab.close_interrupted_run(rid);
m = read_disk(runs_dir, rid);
[ns_ok, ~, next] = tab.next_stage_to_run(rid);
s = check(s, 'B5 RUNNING stage is closed and Resume finds it', ok && ns_ok && strcmp(next, order{2}) && ...
    strcmp(m.stages(2).status, 'FAILED') && contains(strjoin(cellstr(m.stages(2).warnings), ' '), 'interrupted'), err);

% ---- B6-B10: refusals change nothing ----
s = refused(s, 'B6 LIVE lock', tab, runs_dir, 'run_b6', lock_text(feature('getpid'), 'run_b6'), {}, 'RUNNING');
s = refused(s, 'B7 lock without a process id', tab, runs_dir, 'run_b7', sprintf('timestamp=x\nrun_id=run_b7\n'), {}, 'RUNNING');
s = refused(s, 'B8 lock of another computer', tab, runs_dir, 'run_b8', ...
    sprintf('pid=%d\nhost=NOT-THIS-COMPUTER\ntimestamp=x\nrun_id=run_b8\n', dead), {}, 'RUNNING');
s = check(s, 'B8 lock of another computer is UNAVAILABLE', ...
    strcmp(tab.run_inspect_lock_liveness(fullfile(runs_dir, 'run_b8')), 'UNAVAILABLE'), '');
s = refused(s, 'B9 no lock', tab, runs_dir, 'run_b9a', '', {}, 'RUNNING');
s = refused(s, 'B9 lock of another run', tab, runs_dir, 'run_b9b', lock_text(dead, 'run_other'), {}, 'RUNNING');
s = refused(s, 'B10 COMPLETED', tab, runs_dir, 'run_b10a', lock_text(dead, 'run_b10a'), {order{1}, 'PASSED'}, 'COMPLETED');
s = refused(s, 'B10 FAILED', tab, runs_dir, 'run_b10b', lock_text(dead, 'run_b10b'), {order{1}, 'FAILED'}, 'FAILED');
s = refused(s, 'B10 CANCELLED', tab, runs_dir, 'run_b10c', lock_text(dead, 'run_b10c'), {order{1}, 'CANCELLED'}, 'CANCELLED');

% ---- B11 B12: injected store failures ----
rid = 'run_b11';
make_run(tab, runs_dir, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
tab.fail_on = {'write_active_manifest'};
[ok, err] = tab.close_interrupted_run(rid);
tab.fail_on = {};
m = read_disk(runs_dir, rid);
s = check(s, 'B11 failed manifest write is STATE NOT CONFIRMED, still RUNNING', ...
    ~ok && contains(err, 'STATE NOT CONFIRMED') && strcmp(m.result.status, 'RUNNING'), err);

rid = 'run_b12';
make_run(tab, runs_dir, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
tab.fail_on = {'commit_state_candidate'};
[ok, err] = tab.close_interrupted_run(rid);
tab.fail_on = {};
m = read_disk(runs_dir, rid);
[ok2, err2] = tab.close_interrupted_run(rid);
[conf_ok, conf_err] = tab.confirm_run_status(rid, 'INTERRUPTED');
m2 = read_disk(runs_dir, rid);
s = check(s, 'B12 failed tab-state write is reported, a repeat finishes without a second record', ...
    ~ok && contains(err, 'STATE NOT CONFIRMED') && strcmp(m.result.status, 'INTERRUPTED') && ...
    ok2 && conf_ok && numel(m2.result.interruptions) == 1, [err2 conf_err]);

% ---- B13: v2 sidecar ----
rid = 'run_b13';
make_run(tab, runs_dir, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
v1 = manifest_of(runs_dir, rid);
tab3 = rabbit_reconstruction_tab();
tab3.load_state(root, stem);
[o_ok, o_err, info] = tab3.open_manifest(v1);
[w_ok, w_err] = tab3.write_sidecar_after_commit(fullfile(runs_dir, rid), info.sidecar_pending_bytes);
[ok, err] = tab3.close_interrupted_run(rid);
v2 = fullfile(runs_dir, rid, 'manifest.v2.json');
[o2_ok, o2_err, info2] = rabbit_reconstruction_tab().open_manifest(v2);
s = check(s, 'B13 run in its v2 sidecar closes and stays valid', o_ok && w_ok && ok && o2_ok && ...
    strcmp(info2.result_status, 'INTERRUPTED'), [o_err w_err err o2_err]);
tab.load_state(root, stem);

% ---- B14 B15: Resume owns the run ----
rid = 'run_b14';
make_run(tab, runs_dir, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
tab.close_interrupted_run(rid);
[c_ok, c_err] = tab.commit_run_status(rid, 'RUNNING');
state = tab.run_inspect_lock_liveness(fullfile(runs_dir, rid));
[ok, err] = tab.close_interrupted_run(rid);
m = read_disk(runs_dir, rid);
s = check(s, 'B14 Resume takes the lock over; a live resumed run cannot be closed', ...
    c_ok && strcmp(state, 'LIVE') && ~ok && strcmp(m.result.status, 'RUNNING'), [c_err err]);

write_text(fullfile(runs_dir, rid, '.lock'), lock_text(dead, rid));
[ok, err] = tab.close_interrupted_run(rid);
m = read_disk(runs_dir, rid);
s = check(s, 'B15 a second interruption keeps the first record', ...
    ok && numel(m.result.interruptions) == 2, err);

% ---- B16: no answer is not an answer ----
if ispc
    rid = 'run_b16';
    make_run(tab, runs_dir, rid, {}, lock_text(dead, rid));
    old_path = getenv('PATH');
    setenv('PATH', '');
    state = tab.run_inspect_lock_liveness(fullfile(runs_dir, rid));
    [ok, err] = tab.close_interrupted_run(rid);
    setenv('PATH', old_path);
    m = read_disk(runs_dir, rid);
    s = check(s, 'B16 tasklist failing is UNAVAILABLE, not dead', ...
        strcmp(state, 'UNAVAILABLE') && ~ok && strcmp(m.result.status, 'RUNNING'), err);
end

% ---- GUI, in a dataset of its own so g.stale_running starts false ----
root2 = fullfile(root, 'gui');
mkdir(root2);
runs2 = fullfile(root2, [stem '.matom'], 'reconstruction', 'runs');
mkdir(runs2);
tab = stage_runner_double();
tab.load_state(root2, stem);
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root2, stem);

rid = 'run_g1';
make_run(tab, runs2, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
select_run(app, rid);
g0 = app.recon.reconstruction_gate_state();
headless_push('uiconfirm', 'Close the run');
app.recon.ReconstructionCancelButtonPushed();
g1 = app.recon.reconstruction_gate_state();
txt = strjoin(app.recon.ReconstructionResultsText.Value, ' ');
s = check(s, 'G1 Cancel closes a dead-lock run and nothing stays blocked', ...
    g0.stale_running && g0.cancel_ok && ~g1.stale_running && ~g1.active_run_or_stale && ~g1.cancelling && ...
    isempty(app.recon.cancel_pending_run_id) && strcmp(read_disk(runs2, rid).result.status, 'INTERRUPTED') && ...
    contains(txt, 'status: INTERRUPTED') && contains(txt, 'cannot be confirmed') && ...
    tab.cancel_request_count == 0, txt);

rid = 'run_g2';
make_run(tab, runs2, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
select_run(app, rid);
headless_push('uiconfirm', 'Keep it');
app.recon.ReconstructionCancelButtonPushed();
s = check(s, 'G2 Keep it changes nothing', strcmp(read_disk(runs2, rid).result.status, 'RUNNING') && ...
    isempty(app.recon.cancel_pending_run_id), '');

rid3 = 'run_g3';
make_run(tab, runs2, rid3, {order{1}, 'PASSED'}, lock_text(dead, rid3));
select_run(app, rid3);
app.recon.cancel_pending_run_id = rid3;
g3 = app.recon.reconstruction_gate_state();
app.recon.reconstruction_render_status(rid3);
txt = strjoin(app.recon.ReconstructionResultsText.Value, ' ');
headless_push('uiconfirm', 'Close the run');
app.recon.ReconstructionCancelButtonPushed();
s = check(s, 'G3 a request whose owner died stops showing CANCELLING and can close', ...
    ~g3.cancelling && g3.cancel_ok && ~contains(txt, 'CANCELLING') && isempty(app.recon.cancel_pending_run_id) && ...
    strcmp(read_disk(runs2, rid3).result.status, 'INTERRUPTED'), txt);

select_run(app, 'run_g2');
g4a = app.recon.reconstruction_gate_state();
rid = 'run_g4';
make_run(tab, runs2, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
select_run(app, rid);
headless_push('uiconfirm', 'Close the run');
app.recon.ReconstructionCancelButtonPushed();
g4b = app.recon.reconstruction_gate_state();
select_run(app, 'run_g2');
headless_push('uiconfirm', 'Close the run');
app.recon.ReconstructionCancelButtonPushed();
g4c = app.recon.reconstruction_gate_state();
s = check(s, 'G4 closing one of two still blocks, closing both frees the folder', ...
    g4a.stale_running && g4b.stale_running && ~g4c.stale_running, '');

rid = 'run_g5';
make_run(tab, runs2, rid, {order{1}, 'PASSED'}, sprintf('pid=%d\nhost=NOT-THIS-COMPUTER\ntimestamp=x\nrun_id=%s\n', dead, rid));
select_run(app, rid);
app.recon.ReconstructionCancelButtonPushed();
g5 = app.recon.reconstruction_gate_state();
s = check(s, 'G5 UNAVAILABLE lock writes nothing and sets no pending request', ...
    strcmp(read_disk(runs2, rid).result.status, 'RUNNING') && isempty(app.recon.cancel_pending_run_id) && ...
    g5.unavailable_run && ~g5.cancel_ok && tab.cancel_request_count == 0, '');
delete(app);
clear app_cleanup;

% G6 and G7 need the failure and executor seams, in clean datasets
root3 = fullfile(root, 'gui3');
mkdir(root3);
runs3 = fullfile(root3, [stem '.matom'], 'reconstruction', 'runs');
mkdir(runs3);
tab = tab_failure_doubles();
tab.load_state(root3, stem);
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root3, stem);
rid = 'run_g6';
make_run(tab, runs3, rid, {order{1}, 'PASSED'}, lock_text(dead, rid));
select_run(app, rid);
tab.fail_on = {'commit_state_candidate'};
headless_push('uiconfirm', 'Close the run');
app.recon.ReconstructionCancelButtonPushed();
tab.fail_on = {};
g6a = app.recon.reconstruction_gate_state();
app.recon.ReconstructionRefreshButtonPushed();
g6b = app.recon.reconstruction_gate_state();
[conf_ok, conf_err] = tab.confirm_run_status(rid, 'INTERRUPTED');
s = check(s, 'G6 Refresh finishes a close whose tab-state write failed', ...
    g6a.state_unconfirmed && ~g6b.state_unconfirmed && ~g6b.active_run_or_stale && conf_ok, conf_err);
delete(app);
clear app_cleanup;

root4 = fullfile(root, 'gui4');
mkdir(root4);
runs4 = fullfile(root4, [stem '.matom'], 'reconstruction', 'runs');
mkdir(runs4);
tab = stage_runner_double();
tab.load_state(root4, stem);
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root4, stem);
rid = 'run_g7';
make_run(tab, runs4, rid, {}, lock_text(dead, rid));
select_run(app, rid);
tab.gui_app = app;
tab.observed_run_dir = fullfile(runs4, rid);
tab.execution_mode = 'callback_exit130';
tab.run_pipeline(rid, struct('start_stage', 'stereo_fusion'));
m = read_disk(runs4, rid);
s = check(s, 'G7 Cancel under this session''s pipeline stays a stop request despite a dead lock', ...
    tab.cancel_request_count == 1 && strcmp(m.result.status, 'CANCELLED') && ...
    ~isfield(m.result, 'interruptions') && ~tab.pipeline_is_running(rid), '');
delete(app);
clear app_cleanup;

fprintf('PROBE_INTERRUPTED_RUN_CLOSE RESULT: %d passed, %d failed\n', s.pass, s.fail);
if s.fail == 0
    fprintf('PROBE_OK probe_interrupted_run_close %d/0\n', s.pass);
else
    fprintf('PROBE_FAIL probe_interrupted_run_close\n');
    error('probe_interrupted_run_close:Failed', '%d check(s) failed.', s.fail);
end
end


function s = check(s, label, tf, detail)
if tf
    s.pass = s.pass + 1;
    fprintf('PASS %s\n', label);
else
    s.fail = s.fail + 1;
    fprintf('FAIL: %s [%s]\n', label, detail);
end
end


function s = refused(s, label, tab, runs_dir, rid, lock, stages, status)
% The close is refused, and the manifest and the tab state stay as they were
make_run(tab, runs_dir, rid, stages, lock, status);
before = fileread(manifest_of(runs_dir, rid));
[ok, err] = tab.close_interrupted_run(rid);
[conf_ok, conf_err] = tab.confirm_run_status(rid, status);
s = check(s, [label ' is refused and nothing changes'], ~ok && ~isempty(err) && ...
    ~contains(err, 'STATE NOT CONFIRMED') && strcmp(before, fileread(manifest_of(runs_dir, rid))) && conf_ok, ...
    [err ' ' conf_err]);
end


function make_run(tab, runs_dir, rid, stages, lock, status)
% A run folder a crash could have left: a v1 manifest, its lock, its tab-state record
if nargin < 6, status = 'RUNNING'; end
run_dir = fullfile(runs_dir, rid);
mkdir(run_dir);
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = rid;
m.dataset = struct('role', 'reconstruction', 'path', fileparts(fileparts(fileparts(runs_dir))));
m.inputs = struct('files', []);
recs = {};
for k = 1:size(stages, 1)
    recs{end+1} = struct('name', stages{k, 1}, 'status', stages{k, 2}, ...
        'started_at', '2026-10-15T12:00:00', 'finished_at', '2026-10-15T12:01:00'); %#ok<AGROW>
end
m.stages = recs;
m.result = struct('status', status);
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m, 'PrettyPrint', true));
if ~isempty(lock)
    write_text(fullfile(run_dir, '.lock'), lock);
end
[ok, err] = tab.record_run(rid, status);
assert(ok, err);
end


function select_run(app, rid)
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, rid), 1)};
end


function txt = lock_text(pid, rid)
% A lock as locks were written before they named the computer
txt = sprintf('pid=%d\ntimestamp=2026-10-15T12:00:00\nrun_id=%s\n', pid, rid);
end


function pid = dead_pid(tab, runs_dir)
% A process id that no process has
probe_dir = fullfile(runs_dir, 'pid_search');
mkdir(probe_dir);
for pid = 4000000:-4:3999000
    write_text(fullfile(probe_dir, '.lock'), lock_text(pid, 'pid_search'));
    if strcmp(tab.run_inspect_lock_liveness(probe_dir), 'STALE')
        rmdir(probe_dir, 's');
        return;
    end
end
error('probe_interrupted_run_close:NoPid', 'No unused process id found.');
end


function p = manifest_of(runs_dir, rid)
p = fullfile(runs_dir, rid, 'manifest.json');
end


function m = read_disk(runs_dir, rid)
% The manifest on disk, without the tab's pins
run_dir = fullfile(runs_dir, rid);
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
end


function write_text(path, text)
fid = fopen(path, 'wb');
fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
fclose(fid);
end


function remove_root(root)
if isfolder(root), rmdir(root, 's'); end
end
