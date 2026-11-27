function probe_run_records_and_upstream_checks
%% Probe: run records and upstream checks of the tab and the reprojection
% Collin Snitchler
% 15.10.2026
% Checks, without COLMAP, a GPU or the OM data:
%   T1 a tab-state whose run record has the older format (run_id,
%      run_path, no id; the September 2026 runs) loads; Run's record_run
%      works on it; the older record is kept unchanged under legacy_runs
%      and named in the state notice; the run list sees only the new run
%   T2 start_run: when the run cannot be recorded as started (the
%      tab-state cannot be written), no exception escapes, no run folder
%      is left behind (no orphan RUNNING run) and the message says so in
%      words; with the tab-state writable again the run starts
%   T3 verify_upstream_artifacts: a recorded output of an earlier step
%      that changed (or vanished) stops the next step with a plain
%      message; an unchanged one passes; a folder placeholder record
%      (size-...) is skipped
%   T4 the OM image of the frame choice is saved and its values hashed;
%      a re-run without an image uses the saved one, a different image
%      is named
%   T5 the "OM pose frame" setting: Automatic/empty/0/text -> automatic,
%      a whole number -> that frame; frame_check_record carries how the
%      frame was chosen and the frames that match as well, and the
%      chosen frame's turn from the best match
%   T6 tile_transform_flips inside a run takes the run's own file first
%      and names a loose copy that differs
% Usage: matlab -batch "addpath('<repo>/tests'); probe_run_records_and_upstream_checks" -noFigureWindows

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));
work = tempname;
mkdir(work);
cleanup = onCleanup(@() remove_tree(work));

%% T1 an older run record in tab-state.json
root1 = fullfile(work, 'ds1');
recon1 = fullfile(root1, 'rec.matom', 'reconstruction');
mkdir(fullfile(recon1, 'runs', '20260915T040000_julysfm'));
old_rec = struct('run_id', '20260915T040000_julysfm', ...
    'run_path', 'X:/data/rec.matom/reconstruction/runs/20260915T040000_julysfm', ...
    'status', 'REJECTED_FOR_METRIC_USE', 'tag', 'first-successful', ...
    'pending', {{'APDe-MVS refinement', 'RHYTHM reprojection'}});
write_txt(fullfile(recon1, 'tab-state.json'), jsonencode(struct('state_schema_version', 1, ...
    'recipe_version', 1, 'runs', {{old_rec}}), 'PrettyPrint', true));
tab = rabbit_reconstruction_tab();
[ok_load, err_load] = tab.load_state(root1, 'rec');
note1 = tab.get_state_notice();
e_rec = '';
try
    [ok_rec, err_rec] = tab.record_run('20261015T120000_aaaaaaaa', 'RUNNING');
catch ME
    ok_rec = false;
    err_rec = '';
    e_rec = ME.message;
end
disk = jsondecode(fileread(fullfile(recon1, 'tab-state.json')));
leg = disk.legacy_runs;
if iscell(leg), leg = leg{1}; end
T1 = ok_load && isempty(err_load) && ok_rec && isempty(err_rec) && isempty(e_rec) && ...
    numel(disk.runs) == 1 && strcmp(disk.runs(1).id, '20261015T120000_aaaaaaaa') && ...
    strcmp(leg.run_id, old_rec.run_id) && strcmp(leg.run_path, old_rec.run_path) && ...
    strcmp(leg.status, old_rec.status) && numel(leg.pending) == 2 && ...
    contains(note1, '20260915T040000_julysfm') && contains(note1, 'legacy_runs');
% loading again keeps one copy of the older record
tab1b = rabbit_reconstruction_tab();
tab1b.load_state(root1, 'rec');
[~] = tab1b.record_run('20261015T120000_aaaaaaaa', 'FAILED');
disk2 = jsondecode(fileread(fullfile(recon1, 'tab-state.json')));
T1 = T1 && numel(disk2.legacy_runs) == 1 && numel(disk2.runs) == 1 && strcmp(disk2.runs(1).status, 'FAILED');
fprintf('T1: load %d, record %d (%s%s); legacy kept %d; notice: %s -> %s\n', ok_load, ok_rec, err_rec, e_rec, ...
    numel(disk2.legacy_runs), note1, tf(T1));
[pass, fail] = tally(T1, pass, fail);

%% T2 start_run leaves nothing behind when the start cannot be recorded
root2 = fullfile(work, 'ds2');
tab2 = rabbit_reconstruction_tab();
tab2.load_state(root2, 'rec');
recon2 = fullfile(root2, 'rec.matom', 'reconstruction');
blocker = fullfile(recon2, 'tab-state.json.tmp');
mkdir(blocker);   % write_state cannot open its temporary file
id2 = tab2.new_run_id();
e2 = '';
try
    [ok2, err2, dir2, kept2] = tab2.start_run(id2, struct());
catch ME
    ok2 = true; err2 = ''; dir2 = ''; kept2 = true;
    e2 = ME.message;
end
left2 = isfolder(fullfile(recon2, 'runs', id2));
rmdir(blocker);
id3 = tab2.new_run_id();
[ok3, err3, dir3, kept3] = tab2.start_run(id3, struct());
m3 = tab2.read_manifest(dir3);
st3 = jsondecode(fileread(fullfile(recon2, 'tab-state.json')));
T2 = isempty(e2) && ~ok2 && ~kept2 && ~left2 && isempty(dir2) && contains(err2, 'no step ran') && ...
    ok3 && isempty(err3) && ~kept3 && isfolder(dir3) && strcmp(m3.result.status, 'RUNNING') && ...
    any(strcmp({st3.runs.id}, id3)) && ~any(strcmp({st3.runs.id}, id2));
fprintf('T2: blocked: ok %d kept %d folder left %d (%s%s); unblocked: ok %d -> %s\n', ok2, kept2, left2, ...
    err2, e2, ok3, tf(T2));
[pass, fail] = tally(T2, pass, fail);

%% T3 the recorded outputs of earlier steps are re-checked
run3 = dir3;
mkdir(fullfile(run3, 'stages', 'image_undistorter', 'dense', 'sparse'));
cam = fullfile(run3, 'stages', 'image_undistorter', 'dense', 'sparse', 'cameras.bin');
write_txt(cam, 'cameras v1');
fused = fullfile(run3, 'outputs', 'fused-geometric.ply');
write_txt(fused, 'ply v1');
arts_u = tab2.artifact_tree(fileparts(cam), run3);
m3.stages = struct('name', {'image_undistorter', 'patch_match_stereo', 'stereo_fusion'}, ...
    'status', {'PASSED', 'PASSED', 'WARNED'}, ...
    'artifacts', {arts_u, struct('path', fullfile(run3, 'stages', 'depth'), 'sha256', 'size-0size-0'), ...
    struct('path', fused, 'sha256', sha256_text('ply v1'))});
order = rabbit_reconstruction_tab.driver_stage_order();
[ok_a, err_a] = tab2.verify_upstream_artifacts(run3, 'mesh_cleanup', order, m3);
write_txt(fused, 'ply edited');
[ok_b, err_b] = tab2.verify_upstream_artifacts(run3, 'mesh_cleanup', order, m3);
write_txt(fused, 'ply v1');
delete(cam);
[ok_c, err_c] = tab2.verify_upstream_artifacts(run3, 'mesh_cleanup', order, m3);
[ok_d, ~] = tab2.verify_upstream_artifacts(run3, 'patch_match_stereo', order, m3);
T3 = ok_a && isempty(err_a) && ~ok_b && contains(err_b, 'fused-geometric.ply') && contains(err_b, 'changed') && ...
    ~ok_c && contains(err_c, 'cameras.bin') && contains(err_c, 'missing') && ~ok_d && ...
    strcmp(arts_u(1).path, 'stages/image_undistorter/dense/sparse/cameras.bin');
fprintf('T3: unchanged %d; edited cloud -> %s; missing model file -> %s -> %s\n', ok_a, err_b, err_c, tf(T3));
[pass, fail] = tally(T3, pass, fail);

%% T4 the OM image is kept with the run and hashed
img = magic(6);
[img_a, rec_a, note_a] = tab2.reprojection_om_image(run3, struct(), img);
m4 = tab2.read_manifest(run3);
m4.reprojection_source = struct('frame_check', struct('om_image', rec_a));
tab2.write_manifest(run3, m4);
[img_b, rec_b, note_b] = tab2.reprojection_om_image(run3, struct(), []);
[~, rec_c, note_c] = tab2.reprojection_om_image(run3, struct(), img + 1);
T4 = isequal(img_a, img) && isempty(note_a) && numel(rec_a.values_sha256) == 64 && ...
    isequal(rec_a.size, [6 6]) && exist(fullfile(run3, 'stages', 'reprojection', 'om_frame_image.mat'), 'file') == 2 && ...
    isequal(img_b, img) && strcmp(rec_b.values_sha256, rec_a.values_sha256) && contains(note_b, 'earlier projection was used') && ...
    ~strcmp(rec_c.values_sha256, rec_a.values_sha256) && contains(note_c, 'differs');
fprintf('T4: saved %s; re-run without image: %s; other image: %s -> %s\n', rec_a.values_sha256(1:12), note_b, ...
    note_c, tf(T4));
[pass, fail] = tally(T4, pass, fail);

%% T5 the OM pose frame setting and the frame-check record
vals = {'Automatic', '', 0, 'abc', 'auto', '67', 67, 3.5, -2};
want = {[], [], [], [], [], 67, 67, [], []};
got5 = cellfun(@(v) tab2.om_pose_frame_value(struct('om_pose_frame', v)), vals, 'UniformOutput', false);
chk = struct('verdict', 'WARN', 'frame', 1, 'view_cameras', {{'a', 'b', 'c', 'd'}}, 'summary', 's', ...
    'per_view', struct('pose_iou', {0.9, 0.9, 0.9, 0.9}, 'mesh_iou', 0.8, 'covered', 0.85), ...
    'chosen_by', 'automatic', 'requested_frame', [], 'best_score_frame', 1, ...
    'ambiguous_frames', [5 67], 'ambiguous_turn_deg', [16.3 13.1], 'om_image', rec_a);
rec5 = tab2.frame_check_record(chk);
L = rabbit_rhythm_reproject.frame_check_limits();
T5 = isequal(got5, want) && isequal(rec5.ambiguous_frames, [5 67]) && strcmp(rec5.chosen_by, 'automatic') && ...
    strcmp(rec5.om_image.values_sha256, rec_a.values_sha256) && L.ambiguity_margin == 0.05 && L.ambiguity_deg == 10;
% the chosen frame's turn from the best match is
% carried and printed ("frame 3, 5.5 deg away"); an older record without it
% prints as before
chk.best_score_frame = 3;
chk.best_turn_deg = 5.5;
chk.summary = 'Frame 1 chosen for the cameras: the earliest frame within 0.05 of the best match (frame 3)';
rec5b = tab2.frame_check_record(chk);
row5b = tab2.pose_row_words(rec5b);
row5c = tab2.pose_row_words(rmfield(rec5b, 'best_turn_deg'));
T5 = T5 && isequal(rec5b.best_turn_deg, 5.5) && ...
    startsWith(row5b, sprintf('OM pose: frame 1 used (earliest within 0.05 of the best match, frame 3, 5.5%s away); ', char(176))) && ...
    startsWith(row5c, 'OM pose: frame 1 used (earliest within 0.05 of the best match, frame 3); ');
fprintf('T5: setting values %s; record has ambiguous frames %s -> %s\n', ...
    strjoin(cellfun(@(x) mat2str(x), got5, 'UniformOutput', false), ' '), mat2str(rec5.ambiguous_frames), tf(T5));
[pass, fail] = tally(T5, pass, fail);

%% T6 inside a run the run's own transform comes first
run6 = fullfile(work, 'runs', 'r6');
ds6 = fullfile(run6, 'stages', 'image_undistorter', 'dense', 'sparse');
mkdir(ds6);
mkdir(fullfile(run6, 'stages', 'sparse_build'));
write_txt(fullfile(run6, 'manifest.json'), jsonencode(struct('pipeline', struct('sparse_source', 'built'))));
T = struct('schema', 'rabbit_sfm_build.om_tile_transform.v2', 'views', struct( ...
    'roi_row', {1, 2, 3, 4}, 'flip_lr', {true, false, false, true}, 'flip_ud', {false, false, false, true}));
pinned = fullfile(run6, 'stages', 'sparse_build', 'om_tile_transform.json');
write_txt(pinned, jsonencode(T));
T.views(1).flip_lr = false;
write_txt(fullfile(ds6, 'om_tile_transform.json'), jsonencode(T));
[f6, n6, i6] = rabbit_rhythm_reproject.tile_transform_flips(ds6);
T6 = strcmp(i6.path, pinned) && strcmp(f6{1}, 'lr') && contains(n6, 'differs from the run''s own file');
fprintf('T6: used %s; flips %s; note mentions the differing copy %d -> %s\n', i6.path, strjoin(f6, ','), ...
    contains(n6, 'differs'), tf(T6));
[pass, fail] = tally(T6, pass, fail);

fprintf('PROBE_RUN_RECORDS_AND_UPSTREAM_CHECKS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_run_records_and_upstream_checks %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_run_records_and_upstream_checks\n');
    error('probe_run_records_and_upstream_checks:Failed', '%d check(s) failed.', fail);
end
end


function [pass, fail] = tally(ok, pass, fail)
if ok, pass = pass + 1; else, fail = fail + 1; end
end

function write_txt(path, txt)
fid = fopen(path, 'w', 'n', 'UTF-8');
fwrite(fid, txt, 'char');
fclose(fid);
end

function h = sha256_text(txt)
md = java.security.MessageDigest.getInstance('SHA-256');
d = typecast(int8(md.digest(uint8(txt))), 'uint8');
h = lower(reshape(dec2hex(d, 2)', 1, []));
end

function remove_tree(p)
% the run snapshot is read-only: give write access back, then remove
try
    fileattrib(fullfile(p, '*'), '+w', '', 's');
catch
end
try
    rmdir(p, 's');
catch
end
end
