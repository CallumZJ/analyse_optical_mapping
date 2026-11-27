function probe_calibration()
%PROBE_CALIBRATION Rig calibration with synthetic ground truth
% Collin Snitchler
% 02.11.2026
% Purpose: known cameras, target sizes and scales through rabbit_calibration
%          and the app's calibration controls. Needs no pyCamSet: the
%          result pyCamSet would write is made here from the known rig.
%
%   T  tile windows from ROI columns in any row order; lens centre in tiles
%   S  settings: a missing cube edge and the other refusals
%   N  folder names never reuse one that exists
%   V  verdict gates: pass, poor fit, missing view, held-out miss, no check
%   R  read_result refuses malformed results
%   M  sparse rig against calibration: known scale, any ROI row order, turned
%      world, drifted camera, wrong focal length, wrong target size
%   A  apply_to_model: scaled and read back, or left alone with the reason
%   P  pixel size on a sphere of known radius
%   C  tiles from a FITS file and a view1-view4 cut folder land where they should
%   J  the job: a stand-in Python that fails, that is cancelled, that finishes
%   G  the app: dropdown, chosen calibration at Run, window settings

pass = 0; fail = 0;
    function check(id, ok, detail)
        fprintf('%s: %s -> %s\n', id, detail, char(70 + 14 * logical(ok)));
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end

root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));

%% tile windows
bounds_new = [29 618 381 969; 44 1126 377 1477; 1 1 400 428; 42 1666 400 1957];   % view2 is the second tile
bounds_old = [1 1 400 428; 29 618 381 969; 44 1126 377 1477; 42 1666 400 1957];   % saved before 02.11.2026
w1 = rabbit_calibration.tile_windows(bounds_new, 2000);
w2 = rabbit_calibration.tile_windows(bounds_old, 2000);
check('T1', isequal(w1, w2) && w1(1, 1) == 1 && w1(4, 2) == 2000 && all(w1(2:4, 1) == w1(1:3, 2) + 1), mat2str(w1));
pp = rabbit_calibration.tile_principal_points(w1, [999.5 399.5]);
check('T2', abs(pp.tile2(1) - (999.5 - (w1(2, 1) - 1))) < 1e-9 && ...
    abs(pp.tile1(1) - ((w1(1, 2) - w1(1, 1)) - 999.5)) < 1e-9 && pp.tile4(2) == 399.5, ...
    'the lens centre lies outside the outer tiles, and they are flipped');

%% settings
s = rabbit_calibration.default_spec();
f1 = fullfile(root, 'a.fits');
fitswrite(zeros(8, 40, 2), f1);
[ok, err] = rabbit_calibration.check_spec(s);
check('S1', ~ok && contains(err, 'recording'), err);
s.recordings(1) = struct('path', f1, 'role', 'fit', 'type', 'PuzzleBoardCube', 'n_points', 7, 'edge_mm', NaN, 'size_source', 'callipers');
[ok, err] = rabbit_calibration.check_spec(s);
check('S2', ~ok && contains(err, 'no default'), err);
s.recordings(1).edge_mm = 30;
s.recordings(1).size_source = '';
[ok, err] = rabbit_calibration.check_spec(s);
check('S3', ok || ~contains(err, 'comes from'), err);   % no Edge from any more
s.recordings(1).size_source = 'callipers';
s.recordings(2) = struct('path', f1, 'role', 'fit', 'type', 'PuzzleBoardCube', 'n_points', 6, 'edge_mm', 30, 'size_source', 'x');
[ok, err] = rabbit_calibration.check_spec(s);
check('S4', ~ok && contains(err, 'same target'), err);
s.recordings(2).role = 'holdout';
[ok, err] = rabbit_calibration.check_spec(s);
check('S5', ok, err);

%% names
n = fullfile(root, 'cals');
mkdir(n);
a = rabbit_calibration.next_id(n, 'x');
mkdir(fullfile(n, a));
b = rabbit_calibration.next_id(n, 'x');
mkdir(fullfile(n, b));
c = rabbit_calibration.next_id(n, 'x');
check('N1', strcmp(a, 'cal_x') && strcmp(b, 'cal_x_01') && strcmp(c, 'cal_x_02'), c);

%% a known rig, and the result pyCamSet would give for it
f = 8000; D = 1000;
[cal_good, truth] = known_result(f, D);
v = rabbit_calibration.verdict(cal_good);
check('V1', strcmp(v.status, 'PASSED') && v.metric_allowed, strjoin(v.failures, ' '));
check('V2', contains(v.size_note, '30 mm') && contains(v.size_note, 'do not measure'), v.size_note);
q = cal_good; q.cameras(4).rmse_px = 3;
v = rabbit_calibration.verdict(q);
check('V3', strcmp(v.status, 'FAILED') && ~v.metric_allowed && contains(v.failures{1}, 'View4'), v.failures{1});
q = cal_good; q.cameras(2).images = 3;
v = rabbit_calibration.verdict(q);
check('V4', strcmp(v.status, 'FAILED') && contains(v.failures{1}, 'View2'), 'a view with too few frames');
q = cal_good; q.holdout(1).scale_error_percent = -10;
v = rabbit_calibration.verdict(q);
check('V5', strcmp(v.status, 'FAILED') && ~v.metric_allowed, 'a wrong stated size shows in the held-out cube');
q = cal_good; q.holdout.frames_rejected = 40;
v = rabbit_calibration.verdict(q);
check('V5b', strcmp(v.status, 'FAILED') && contains(v.failures{1}, '40 of 80'), v.failures{1});
q = cal_good; q.holdout.frames_rejected = 4;
txt = strjoin(rabbit_calibration.summary_lines(q, rabbit_calibration.verdict(q)), ' ');
check('V5c', strcmp(rabbit_calibration.verdict(q).status, 'PASSED') && contains(txt, '4 left out'), 'a few left out is shown, and passes');
% mm/px at the cube is measured, the distance
% follows from the stated focal length; the solve's focal length in mm, and
% the spec's lens named as the nominal one (only when the spec is given)
txt18 = strjoin(rabbit_calibration.summary_lines(q, rabbit_calibration.verdict(q), struct('lens_focal_mm', 50)), ' ');
txt18b = strjoin(rabbit_calibration.summary_lines(q, rabbit_calibration.verdict(q)), ' ');
want18 = sprintf('The solve uses %g px %s 6.5 %sm = %.1f mm.', q.lens.focal_px, char(215), char(181), q.lens.focal_px * 6.5 / 1000);
% (in um per pixel, as every pixel size)
check('V5d', contains(txt18, sprintf('%.1f %sm/px at the cube (measured); %.0f mm away (follows from the stated focal length, not measured).', ...
    1000 * q.cameras(1).mm_per_px_at_target, char(181), q.cameras(1).depth_at_target_mm)) && contains(txt18, want18) && ...
    contains(txt18, 'The spec''s lens_focal_mm 50 is the nominal lens.') && contains(txt18b, want18) && ...
    ~contains(txt18b, 'nominal') && ~contains(txt18, ' um '), txt18);
% with a focal sweep, its ends are named as the sweep's,
% where its RMSE is lowest, and not as an uncertainty
if isfield(q, 'focal_sweep')
    check('V5e', contains(txt18, 'Focal length not determined by the cube') && contains(txt18, 'mm per pixel changes'), txt18);
else
    fprintf('PROBE_SKIP V5e: this calibration has no focal sweep\n');
end
q = cal_good; q.holdout = q.holdout([]);
v = rabbit_calibration.verdict(q);
check('V6', strcmp(v.status, 'WARNED') && v.metric_allowed, 'no held-out check: allowed, and said');
q = cal_good; q.observations.kept_fraction = 0.4;
v = rabbit_calibration.verdict(q);
check('V7', strcmp(v.status, 'FAILED'), 'most points off the rig');

%% results that are not results
d = fullfile(root, 'res');
mkdir(d);
[ok, err] = rabbit_calibration.read_result(d);
check('R1', ~ok && contains(err, 'no result'), err);
write_json(fullfile(d, 'calibration.json'), struct('schema', 'other'));
[ok, err] = rabbit_calibration.read_result(d);
check('R2', ~ok, err);
write_json(fullfile(d, 'calibration.json'), cal_good);
[ok, err, c2] = rabbit_calibration.read_result(d);
check('R3', ok && numel(c2.cameras) == 4, err);
q = cal_good; q.cameras(3).det_R = -1;
write_json(fullfile(d, 'calibration.json'), q);
[ok, err] = rabbit_calibration.read_result(d);
check('R4', ~ok && contains(err, 'View3'), err);

%% the sparse rig against the calibration
scale = 137.5;                 % mm per model unit, the truth
prefixes = {'r_view3_', 'r_view1_', 'r_view2_', 'r_view4_'};   % tile order, any ROI row order
images = known_model(truth, scale, prefixes, 8);
[C, A, frames] = rabbit_calibration.model_rig(images, prefixes);
check('M1', size(C, 1) == 8 && numel(frames) == 8, sprintf('%d frames', size(C, 1)));
tc = [truth.pp];
tc = reshape(tc, 2, 4)';   % model cameras look through the same pixels here
m = rabbit_calibration.compare_rig(C, A, cal_good, tc);
check('M2', abs(m.scale_mm_per_unit / scale - 1) < 1e-9 && max(m.centre_residual_mm) < 1e-6, ...
    sprintf('scale %.6f, truth %.6f', m.scale_mm_per_unit, scale));
[apply, why] = rabbit_calibration.rig_gates(m, f, cal_good);
check('M3', apply && isempty(why), 'a rig that agrees is applied');
[apply, why] = rabbit_calibration.rig_gates(m, [8000 8000 9000 8000], cal_good);
check('M4', ~apply && contains(why{1}, 'cannot be compared'), why{1});
% the uncertainty: never zero for want of a check, and a lucky error keeps its spread
check('U1', abs(rabbit_calibration.holdout_term(cal_good) - hypot(0.1, 0.1)) < 1e-9 && ...
    abs(m.scale_uncertainty_percent - sqrt((m.baseline_spread_percent / sqrt(6)) ^ 2 + 0.02)) < 1e-9, ...
    sprintf('%.3f %%', m.scale_uncertainty_percent));
q = cal_good; q.holdout = q.holdout([]);
mn = rabbit_calibration.compare_rig(C, A, q, tc);
check('U2', isnan(mn.scale_uncertainty_percent) && contains(jsonencode(struct('x', mn.scale_uncertainty_percent)), 'null') && ...
    contains(rabbit_calibration.uncertainty_status(mn.scale_uncertainty_percent), 'not estimated'), 'no check is not estimated, not zero');
q = cal_good; q.holdout.scale_error_percent = 0; q.holdout.scale_se_percent = 0.4;
check('U3', abs(rabbit_calibration.holdout_term(q) - 0.4) < 1e-9, 'a near-zero error keeps its standard error');
q = cal_good; q.holdout.frames_used = 3;
check('U4', isnan(rabbit_calibration.holdout_term(q)), 'a check with too few frames does not count');
% the focal sweep: the rig moves back in proportion, pixels at the cube stay
q = cal_good;
fs = (0.75:0.25:2)' * f;
q.focal_sweep = struct('focal_px', fs, 'rmse_px', 0.9 * ones(size(fs)), 'depth_mm', fs / f * D .* [1 1 1 1] + 2 * (fs / f - 1) .* [1 2 3 4]);
e = rabbit_calibration.focal_effect(q, 2, 980, [200 200]);   % the tile centre is the lens centre here
i0 = find(fs == f);
check('U5', abs(e.change_percent(i0)) < 1e-12 && abs(e.max_percent - 100 * ((D * 2 + 4 - 20) / (2 * f) / (980 / f) - 1)) < 1e-9, ...
    sprintf('%.2f to %.2f %% at the surface', e.min_percent, e.max_percent));
% one axis: a surface on the tile's own axis, 6 degrees off the lens axis
qa = q;
qa.cameras(2).pp_tile_px = [200 - f * tand(6); 200];
on_axis = rabbit_calibration.focal_effect(qa, 2, 980, [200 200]);
same_axis = rabbit_calibration.focal_effect(q, 2, 980 * cosd(6), [200 200]);
check('U5b', norm(on_axis.change_percent - same_axis.change_percent) < 1e-9 && ...
    abs(on_axis.max_percent - e.max_percent) > 0.05, sprintf('%.2f against %.2f %% before the axis is corrected', on_axis.max_percent, e.max_percent));
L = rabbit_calibration.left_out(q, 'printed');
check('U6', ~L.cube_size.estimated && contains(L.cube_size.note, 'unmeasured') && L.focal_length.estimated && ...
    L.focal_length.sweep_px(1) == 6000 && numel(L.focal_length.per_view_at_target) == 4 && ...
    ~isempty(rabbit_calibration.focal_effect(q, 1, [], [])) && isempty(rabbit_calibration.focal_effect(cal_good, 1, [], [])), ...
    L.focal_length.derived);
% a camera moved between the recording and the calibration
C3 = C; C3(:, :, 2) = C3(:, :, 2) + [0.6 0 0];
m3 = rabbit_calibration.compare_rig(C3, A, cal_good, tc);
[apply, why] = rabbit_calibration.rig_gates(m3, f, cal_good);
check('M5', ~apply && contains(strjoin(why, ' '), 'moved'), strjoin(why, ' '));
% a mirror turned: same centres, different view angle
images3 = known_model(truth, scale, prefixes, 8);
for id3 = 3:4:32
    im3 = images3(id3);
    R3 = rotx_deg(3) * rabbit_calibration.quat_to_rot(im3.qvec);   % 3 degrees: over the 2.5 degree gate
    C3b = -rabbit_calibration.quat_to_rot(im3.qvec)' * im3.tvec;
    im3.qvec = rotm2q(R3); im3.tvec = -R3 * C3b;
    images3(id3) = im3;
end
[C3c, A3] = rabbit_calibration.model_rig(images3, prefixes);
m3 = rabbit_calibration.compare_rig(C3c, A3, cal_good, tc);
[apply, why] = rabbit_calibration.rig_gates(m3, f, cal_good);
check('M6', ~apply && contains(strjoin(why, ' '), 'angle'), strjoin(why, ' '));
% June 2026's rig (2.23 degrees, 1.85 %) is inside the loosened gates; just over them is not
mj = m; mj.angle_difference_deg = [1.66 -2.23 -2.02 0.76 1.86 -1.29]; mj.baseline_spread_percent = 1.85;
[apply_j, why_j] = rabbit_calibration.rig_gates(mj, f, cal_good);
mj.angle_difference_deg(2) = -2.6; mj.baseline_spread_percent = 2.1;
[apply_o, why_o] = rabbit_calibration.rig_gates(mj, f, cal_good);
check('M6b', apply_j && ~apply_o && numel(why_o) == 2, sprintf('%s | %s', strjoin(why_j, ' '), strjoin(why_o, ' ')));
% the cube was really 27 mm and 30 was stated: the calibrated rig reads 30/27 too large
cal_big = cal_good;
for k = 1:4, cal_big.cameras(k).centre_mm = cal_big.cameras(k).centre_mm * 30 / 27; end
mb = rabbit_calibration.compare_rig(C, A, cal_big, tc);
check('M7', abs(mb.scale_mm_per_unit / scale - 30 / 27) < 1e-9, ...
    'the scale follows the stated size, which is why it must be measured');

%% applying it
stage = fullfile(root, 'stage');
mkdir(fullfile(stage, 'model'));
cdir = fullfile(root, 'cal');
mkdir(cdir);
write_json(fullfile(cdir, 'calibration.json'), cal_good);
spec = struct('windows', [1 500; 501 1000; 1001 1500; 1501 2000], 'size_source', 'callipers');
write_json(fullfile(cdir, 'spec.json'), spec);
write_json(fullfile(cdir, 'verdict.json'), struct('status', 'PASSED', 'metric_allowed', true));
R = known_recipe(prefixes, f);
reader = @(dir_path) stub_reader(dir_path, images, scale, f);
run_cmd = @(line, t, label) stub_transform(line, stage);
notes = {};
    function log_note(t), notes{end+1} = t; end
[~, t0] = rabbit_calibration.tile_map(R, spec);
cal_apply = cal_good;
for k = 1:4, cal_apply.cameras(k).pp_tile_px = t0(k, :)'; end
write_json(fullfile(cdir, 'calibration.json'), cal_apply);
[r, tcm] = rabbit_calibration.apply_to_model(R, stage, cdir, 'colmap', run_cmd, reader, @log_note);
ms = jsondecode(fileread(fullfile(stage, 'metric_scale.json')));
check('A1', r.ok && r.applied && ms.applied && strcmp(ms.units, 'mm') && abs(ms.scale_mm_per_unit / scale - 1) < 1e-9, ...
    sprintf('applied, units %s', ms.units));
check('A1b', isfield(ms, 'not_included') && isfield(ms.not_included, 'cube_size') && ...
    isfield(ms.not_included, 'focal_length') && contains(ms.scale_uncertainty_status, 'held-out') && ...
    contains(ms.not_included.cube_size.note, 'unmeasured'), ms.scale_uncertainty_status);
check('A2', isfolder(fullfile(stage, 'model')) && ~isfolder(fullfile(stage, 'model_mm')) && ...
    exist(fullfile(stage, 'model', 'scaled.txt'), 'file') == 2, 'the scaled model took the place of the old one');
check('A3', abs(tcm(2, 2) - ((29 + 381) / 2 - 0.5)) < 1e-9, 'the ray goes through the tile centre in raw rows');
write_json(fullfile(cdir, 'verdict.json'), struct('status', 'FAILED', 'metric_allowed', false));
rmdir(fullfile(stage, 'model'), 's'); mkdir(fullfile(stage, 'model'));
r = rabbit_calibration.apply_to_model(R, stage, cdir, 'colmap', run_cmd, reader, @log_note);
ms = jsondecode(fileread(fullfile(stage, 'metric_scale.json')));
check('A4', r.ok && ~r.applied && ~ms.applied && strcmp(ms.units, 'model units') && ...
    exist(fullfile(stage, 'model', 'scaled.txt'), 'file') == 0, 'a failed calibration leaves the model in model units');
write_json(fullfile(cdir, 'verdict.json'), struct('status', 'PASSED', 'metric_allowed', true));
reader2 = @(dir_path) stub_reader(dir_path, images, scale, 9000);
r = rabbit_calibration.apply_to_model(R, stage, cdir, 'colmap', run_cmd, reader2, @log_note);
ms = jsondecode(fileread(fullfile(stage, 'metric_scale.json')));
check('A5', r.ok && ~r.applied && contains(strjoin(cellstr(ms.reasons), ' '), 'cannot be compared'), 'another focal length: no mm, and why');
% the prior stays 8000 and the build refined one camera by 3 %
readerd = @(dir_path) stub_reader(dir_path, images, scale, [8000 8000 8240 8000]);
r = rabbit_calibration.apply_to_model(R, stage, cdir, 'colmap', run_cmd, readerd, @log_note);
ms = jsondecode(fileread(fullfile(stage, 'metric_scale.json')));
check('A5b', r.ok && ~r.applied && contains(strjoin(cellstr(ms.reasons), ' '), '8240') && ...
    max(ms.comparison.model_focal_px) == 8240 && R.resolved.focal_prior_px == 8000, strjoin(cellstr(ms.reasons), ' '));
camsp = containers.Map('KeyType', 'int64', 'ValueType', 'any');
camsp(int64(1)) = struct('model', 'PINHOLE', 'params', [8000 8100 10 10]);
imsp = containers.Map('KeyType', 'int64', 'ValueType', 'any');
imsp(int64(1)) = struct('name', 'a_0001.tiff', 'camera_id', int64(1));
% COLMAP's output cannot be moved in: the model stays
marker = fullfile(stage, 'model', 'original.txt');
fid = fopen(marker, 'w'); fclose(fid);
run_gone = @(line, t, label) stub_vanish(stage);
r = rabbit_calibration.apply_to_model(R, stage, cdir, 'colmap', run_gone, reader, @log_note);
check('A6', ~r.ok && contains(r.err, 'scaled model') && isfile(marker) && ~isfolder(fullfile(stage, 'model_units')), r.err);
r = rabbit_calibration.apply_to_model(R, stage, cdir, 'colmap', run_cmd, reader, @log_note);
check('A7', r.ok && r.applied && numel(r.commands_run) == 1 && contains(r.commands_run{1}, 'model_transformer') && ...
    ~isfile(marker) && ~isfolder(fullfile(stage, 'model_units')), 'the command is recorded, and the old model goes only at the end');
check('A5c', isequal(rabbit_calibration.model_focals(imsp, camsp, {'a_'}), [8000 8100]), 'both focal lengths of a PINHOLE camera are read');

%% pixel size
[x, y, z] = sphere(40);
pts = 20 * unique(round([x(:), y(:), z(:)], 9), 'rows');
fv = struct('faces', convhull(pts));
cam = struct('name', 'view2', 'R', eye(3), 't', [0; 0; 1000], 'f', 8000);
P = rabbit_calibration.pixel_size(pts, fv.faces, cam, 1);
near = pts(:, 3) < -19;
check('P1', abs(P.views(1).median_depth_mm - 985) < 15 && abs(median(P.mm_per_px(near, 1)) - 980 / 8000) < 1e-3, ...
    sprintf('median %.4f mm/px', P.views(1).median_mm_per_px));
check('P2', all(isnan(P.mm_per_px(pts(:, 3) > 5, 1))) && all(P.cos_tilt(near, 1) > 0.9), 'the far side has no value; facing vertices have cos about 1');
csv = fullfile(root, 'v.csv');
rabbit_calibration.write_vertex_csv(csv, pts, P);
T = readmatrix(csv);
check('P3', size(T, 1) == size(pts, 1) && size(T, 2) == 5, sprintf('%d rows', size(T, 1)));

%% tiles
H = 30; W = 200; nf = 3;
stack = zeros(H, W, nf);
for k = 1:nf, stack(:, :, k) = repmat(1:W, H, 1) + 1000 * k; end
ff = fullfile(root, 'stack.fits');
fitswrite(stack, ff);
win = [1 40; 41 100; 101 160; 161 200];
td = fullfile(root, 'tiles');
nn = rabbit_calibration.write_tiles(ff, td, win);
t1 = imread(fullfile(td, 'tile1', 'frame_0001.tiff'));
t2 = imread(fullfile(td, 'tile2', 'frame_0000.tiff'));
check('C1', nn == nf && size(t1, 2) == 40 && t1(1, 1) == 2040 && t1(1, 40) == 2001 && t2(1, 1) == 1041, ...
    'outer tiles flipped, inner ones not');
wrong = [1 40; 41 100; 101 160; 161 300];
threw = false;
try
    rabbit_calibration.write_tiles(ff, fullfile(root, 'wrong'), wrong);
catch ME
    threw = contains(ME.message, 'line up');
end
check('C2', threw, 'a frame of another width is refused');
% a view1-view4 cut folder: tile1 (view1) from the flipped frame
cut = fullfile(root, 'cut');
for k = 1:4, mkdir(fullfile(cut, sprintf('view%d', k))); end
frame = uint8(repmat(1:W, H, 1));
flipped = fliplr(frame);
locs = struct('view', {'view1', 'view2', 'view3', 'view4'}, 'top', {2, 2, 2, 2}, 'bottom', {3, 3, 3, 3}, ...
    'left', {170, 50, 110, 5}, 'right', {10, 90, 40, 165});
for k = 1:4
    l = locs(k);
    src = frame;
    if any(k == [1 4]), src = flipped; end
    crop = src(l.top + 1:H - l.bottom, l.left + 1:W - l.right);
    imwrite(crop, fullfile(cut, sprintf('view%d', k), 'f_0000.tiff'));
end
write_json(fullfile(cut, 'cut_locations_per_view.json'), locs);
td2 = fullfile(root, 'tiles2');
rabbit_calibration.write_tiles(cut, td2, win);
frame_spec = rabbit_calibration.default_spec();
frame_spec.frame_hw = [H W];
frame_spec.roi_hw = [12 W];
frame_spec.roi_bounds = [1 1 12 40; 1 41 12 100; 1 101 12 160; 1 161 12 200];
frame_spec.recordings = struct('path', {ff, cut}, 'role', {'fit', 'holdout'});
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F1', ok && isequal(rabbit_calibration.recording_size(ff), [H W]) && ...
    isequal(rabbit_calibration.recording_size(cut), [H W]), err);
crop = fullfile(root, 'crop.fits');
fitswrite(zeros(12, W, 2), crop);
frame_spec.recordings(2).path = crop;
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F2', ~ok && contains(err, 'frames of the OM recording') && contains(err, 'position'), err);
short = fullfile(root, 'short.fits');
fitswrite(zeros(20, W, 2), short);
frame_spec.recordings(2).path = short;
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F3', ~ok && contains(err, '20x200'), err);
narrow = fullfile(root, 'narrow.fits');
fitswrite(zeros(H, 180, 2), narrow);
frame_spec.recordings(2).path = narrow;
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F4', ~ok && contains(err, '30x180'), err);
% Tile bounds are in the mapped frame: an OM frame of another width is fine
% when the bounds fit, and refused only when they do not
frame_spec.recordings(2).path = ff;
frame_spec.roi_hw = [15 100];   % scale 2, cols_off 0: OM 15x100 inside 30x200
frame_spec.roi_bounds = [1 1 30 40; 1 41 30 100; 1 101 30 160; 1 161 30 200];
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F5', ok, ['a mapped scale 2 FOV passes: ' err]);
frame_spec.roi_hw = [12 150];   % cols_off 50: OM window in the middle of the frame
frame_spec.roi_bounds = [1 51 12 80; 1 81 12 120; 1 121 12 160; 1 161 12 200];
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F5b', ok, ['a mapped column offset passes: ' err]);
% the ROI file against the bounds the images were cut with, after its mapping
roi_m = fullfile(root, 'roi_m.json');
b_om = [1 1 12 40; 1 41 12 100; 1 101 12 160; 1 161 12 200];
fov_m = rabbit_stack_io.validate_fov_mapping(struct('type', 'crop', 'camera_stationary', true, ...
    'om_window_in_rec', struct('off', 9, 'cols_off', 0), 'scale', struct('vertical', 1, 'horizontal', 1)));
write_json(roi_m, struct('schema_version', 1, 'region_bounds_src', b_om([2 3 1 4], :), 'regions', 4, 'rotation', 3, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', 12, 'width', 200), 'coordinate_origin', 'top-left', ...
    'unmirrored_coordinates', true, 'fov_mapping', fov_m));
good_b = b_om + [9 0 9 0];
e_ok = rabbit_calibration.check_roi_bounds(good_b, roi_m);
bad_b = good_b; bad_b(3, 2) = bad_b(3, 2) + 7;
e_bad = rabbit_calibration.check_roi_bounds(bad_b, roi_m);
e_un = rabbit_calibration.check_roi_bounds(b_om, roi_m);
check('F5c', isempty(e_ok) && contains(e_bad, 'cut with') && contains(e_bad, '7 pixels') && contains(e_un, '9 pixels'), ...
    [e_bad ' (ROI rows in another order pass)']);
frame_spec.roi_bounds = [];
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F5d', ~ok && contains(err, 'not known'), err);
frame_spec.roi_bounds = [1 1 12 40; 1 41 12 100; 1 101 12 160; 1 161 12 200];
% The cut margins can sum one pixel off, in one view; two pixels is wrong
cut1 = fullfile(root, 'cut1');
copyfile(cut, cut1);
l1 = locs; l1(1).left = l1(1).left + 1;
write_json(fullfile(cut1, 'cut_locations_per_view.json'), l1);
one = rabbit_calibration.recording_size(cut1);
% as July ccube1: one view a pixel over, one under, and one a row short
l3 = locs; l3(1).left = l3(1).left + 1; l3(2).right = l3(2).right - 1; l3(3).bottom = l3(3).bottom - 1;
write_json(fullfile(cut1, 'cut_locations_per_view.json'), l3);
both = rabbit_calibration.recording_size(cut1);
t3 = fullfile(root, 'tiles3');
rabbit_calibration.write_tiles(cut1, t3, win);
i3 = imfinfo(fullfile(t3, 'tile3', 'frame_0000.tiff'));
check('F5h', isequal(both, [H W]) && i3.Height == H, 'views a pixel either side of the frame pass, and tiles stay frame high');
l1(1).left = l1(1).left + 1;
write_json(fullfile(cut1, 'cut_locations_per_view.json'), l1);
threw = '';
try
    rabbit_calibration.recording_size(cut1);
catch ME
    threw = ME.identifier;
end
check('F5e', isequal(one, [H W]) && strcmp(threw, 'analyse_om:Calibration:CutSizes'), 'one pixel off the frame is allowed, two are not');
[b0, e0] = rabbit_calibration.tile_bounds(struct('resolved', struct('views', struct('bounds', {[1 1 2 2], [1 3 2 4], [], []}))));
check('F5f', isempty(b0) && contains(e0, 'manifest.json') && contains(e0, 'all four regions'), e0);
v4 = struct('bounds', {[1 1 2 2], [1 3 2 4], [1 5 2 6], [1 7 2 8]});
[b1, e1] = rabbit_calibration.tile_bounds(struct('resolved', struct('views', v4)));
check('F5g', isempty(e1) && isequal(b1(3, :), [1 5 2 6]), 'tile bounds of a resolved recipe');
frame_spec.frame_hw = [];
[ok, err] = rabbit_calibration.check_frames(frame_spec);
check('F6', ~ok && contains(err, 'not known'), err);
threw = '';
try
    rabbit_calibration.write_tiles(ff, fullfile(root, 'stopped'), win, @() true);
catch ME
    threw = ME.identifier;
end
threw2 = '';
try
    rabbit_calibration.write_tiles(cut, fullfile(root, 'stopped2'), win, @() true);
catch ME
    threw2 = ME.identifier;
end
check('F7', strcmp(threw, 'analyse_om:Calibration:Cancelled') && strcmp(threw2, threw), 'Cancel stops both tile loops');
roi_a = fullfile(root, 'roi_a.json');
write_json(roi_a, struct('schema_version', 1, 'region_bounds_src', bounds_new, 'regions', 4, 'rotation', 3, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', 400, 'width', 2000), 'coordinate_origin', 'top-left', ...
    'unmirrored_coordinates', true));
[h1, r1z, e1] = rabbit_calibration.frame_size(struct('resolved', struct('source_dims', [800 2000])), roi_a);
[h2, ~, e2] = rabbit_calibration.frame_size(struct('resolved', struct('source_dims', [])), roi_a);
check('F8', isequal(h1, [800 2000]) && isequal(r1z, [400 2000]) && isempty(e1) && isequal(h2, [400 2000]) && isempty(e2), ...
    'the cut manifest knows the frame; without a mapping the ROI file does');
a1 = imread(fullfile(td, 'tile1', 'frame_0000.tiff'));
b1 = imread(fullfile(td2, 'tile1', 'frame_0000.tiff'));
a3 = imread(fullfile(td, 'tile3', 'frame_0000.tiff'));
b3 = imread(fullfile(td2, 'tile3', 'frame_0000.tiff'));
[r1, c1] = find(b1 > 0, 1);
[r3, c3] = find(b3 > 0, 1);
check('C3', r1 == 3 && mod(double(a1(r1, c1)), 1000) == double(b1(r1, c1)) / 257 && ...
    mod(double(a3(r3, c3)), 1000) == double(b3(r3, c3)) / 257, 'a cut folder goes back to the same tile pixels');

%% session dates
d1 = fullfile(root, 'd1.fits');
d2 = fullfile(root, 'd2.fits');
fitswrite(zeros(2), d1);
fid = fitsWriteDate(d2, '2026-01-02T10:00:00');
[same, txt, unk] = rabbit_calibration.session_check(fid, fid);
check('D1', same && isempty(txt) && isempty(unk), 'the same file is the same day');
[same, txt, unk] = rabbit_calibration.session_check({fid, d2}, fid);
check('D2', ~same && contains(txt, '2026-01-02') && contains(txt, 'd2.fits') && isempty(unk), txt);
tif = fullfile(td, 'tile1', 'frame_0000.tiff');
[same, txt, unk] = rabbit_calibration.session_check({fid, tif}, fid);
check('D3', same && isempty(txt) && contains(unk, 'frame_0000.tiff is unknown') && ~contains(unk, 'rig'), unk);
[same, ~, unk] = rabbit_calibration.session_check(fid, tif);
check('D4', same && contains(unk, 'this recording is unknown'), unk);
[same, txt, unk] = rabbit_calibration.session_check({d2, tif}, fid);
check('D4b', ~same && contains(txt, '2026-01-02') && contains(unk, 'is unknown'), 'a real difference still shows beside an unknown date');
[same, txt, unk] = rabbit_calibration.session_check({'Z:\gone\a.fits'}, fid, {'2026-01-02'});
check('D4c', ~same && contains(txt, '2026-01-02') && isempty(unk), 'a recorded date holds when the drive is gone');
[same, ~, unk] = rabbit_calibration.session_check({'Z:\gone\a.fits'}, fid, {''});
check('D4d', same && contains(unk, 'a.fits is unknown'), 'an older record falls back to the file');
rr1 = struct('path', {'a', 'b'}, 'date', {'2026-01-02', ''});
rr2 = struct('path', {'a'});
check('D4e', isequal(rabbit_calibration.recording_dates(rr1), {'2026-01-02', ''}) && isequal(rabbit_calibration.recording_dates(rr2), {''}), 'dates of a record');
kept = rabbit_calibration.run_record('cal', 'abc', struct('calibration_date_note', 'differs', 'calibration_date_differs', true));
none = rabbit_calibration.run_record('cal', 'abc', struct());
check('D4f', kept.date_differs && strcmp(kept.date_note, 'differs') && ~none.date_differs && isempty(none.date_note), 'the manifest keeps the choice');
om_dated = fid;
% a cut folder takes its date from the recording it came from
dcut = fullfile(root, 'dates');
mkdir(fullfile(dcut, 'cut_tiffs_14h-16m-55s'));
copyfile(d2, fullfile(dcut, '14h-16m-55s.fits'));
mkdir(fullfile(root, 'mcut'));
write_json(fullfile(root, 'mcut', 'manifest.json'), struct('source', d2));
mkdir(fullfile(root, 'nocut'));
check('D5', strcmp(rabbit_calibration.fits_date(fullfile(dcut, 'cut_tiffs_14h-16m-55s')), '2026-01-02') && ...
    strcmp(rabbit_calibration.fits_date(fullfile(root, 'mcut')), '2026-01-02') && ...
    isempty(rabbit_calibration.fits_date(fullfile(root, 'nocut'))), 'beside it by name, from its manifest, or unknown');
% what the run's records and labels say about units
rd = fullfile(root, 'run1');
mkdir(fullfile(rd, 'stages', 'sparse_build'));
tb = rabbit_reconstruction_tab();
write_json(fullfile(rd, 'manifest.json'), struct('run_id', 'run1'));
L1 = tb.metric_lines(rd);
check('H1', contains(L1{1}, 'No calibration was used') && strcmp(tb.run_units(rd), 'model units'), L1{1});
write_json(fullfile(rd, 'manifest.json'), struct('run_id', 'run1', 'pipeline', struct('calibration', struct('id', 'cal_x'))));
L2 = tb.metric_lines(rd);
check('H2', contains(L2{1}, 'not confirmed') && strcmp(tb.run_units(rd), 'units not confirmed'), L2{1});
mf = fullfile(rd, 'stages', 'sparse_build', 'metric_scale.json');
fid2 = fopen(mf, 'w'); fprintf(fid2, '{ damaged'); fclose(fid2);
L3 = tb.metric_lines(rd);
check('H3', contains(L3{1}, 'not confirmed') && ~contains(L3{1}, 'No calibration'), L3{1});
write_json(mf, struct('schema', rabbit_calibration.METRIC_SCHEMA, 'applied', true, 'calibration_id', 'cal_x', ...
    'scale_mm_per_unit', 270, 'scale_uncertainty_percent', NaN, 'target_edge_mm', 30, 'size_source', 'printed'));
L4 = tb.metric_lines(rd);
% what the scale rests on, next to the mm claim
check('H4', contains(L4{1}, 'Scale rests on the stated 30 mm cube; no held-out check.') && ...
    contains(L4{1}, 'The cube''s own size tolerance is not measured.') && strcmp(tb.run_units(rd), 'mm'), L4{1});
% the measured parts, from the scale record's own numbers
% (baseline spread; the extremes of the focal sweep over the views), not
% combined into one figure; in Details, Results and the Visualise header
ms16 = struct('schema', rabbit_calibration.METRIC_SCHEMA, 'applied', true, 'calibration_id', 'cal_x', ...
    'scale_mm_per_unit', 270, 'scale_uncertainty_percent', NaN, 'target_edge_mm', 30, 'size_source', '', ...
    'comparison', struct('baseline_spread_percent', 0.3019), ...
    'not_included', struct('focal_length', struct('estimated', true, 'sweep_px', [6000 8000 16000], ...
    'per_view_at_target', struct('tile', {'tile1', 'tile2'}, 'min_percent', {-0.87, -1.161}, ...
    'max_percent', {0.83, 0.44}))));
write_json(mf, ms16);
% the sweep's ends, not an uncertainty interval (no RMSE recorded here);
% a true minus sign, U+2212
% "COLMAP and calibration rigs agree: baselines SD ..."
% (this record has the SD only: no range, centres or focal)
want16 = sprintf('COLMAP and calibration rigs agree: baselines SD 0.30 %%; focal length not determined by the cube; mm per pixel changes %s1.16 %% to +0.83 %% over 6000%s16000 px', char(8722), char(8211));
L16 = tb.metric_lines(rd);
S16 = strjoin(tb.report_scale(rd), ' | ');
V16 = tb.viewer_header_units(rd, 'mm');
check('H4g', contains(L16{1}, want16) && contains(S16, 'scale rests on the stated 30 mm cube; no held-out check') && ...
    contains(S16, want16) && contains(S16, 'the cube''s own size tolerance is not measured') && ...
    ~contains([L16{1} S16], '3.3 %') && ~contains([L16{1} S16], char(177)) && ...
    strcmp(V16, 'mm from rig calibration (scale rests on the stated 30 mm cube; no held-out check)') && ...
    ~contains([L16{1} S16], '1.2 %'), sprintf('%s || %s || %s', L16{1}, S16, V16));
% Details gives the heart surface's pixel
% size in the CV tab's unit, um per OM pixel at binning 1 and 2, View1 to
% View4 (the record lists them out of order), when the record says an OM
% pixel is a reconstruction pixel; otherwise mm per reconstruction pixel, and says so
rdp = fullfile(root, 'run_px');
mkdir(fullfile(rdp, 'stages', 'sparse_build'));
mkdir(fullfile(rdp, 'outputs', 'metric'));
write_json(fullfile(rdp, 'manifest.json'), struct('run_id', 'run_px'));
write_json(fullfile(rdp, 'stages', 'sparse_build', 'metric_scale.json'), ms16);
pv = struct('view', {'view2', 'view3', 'view1', 'view4'}, 'median_mm_per_px', {0.12902, 0.12844, 0.12411, 0.13052});
write_json(fullfile(rdp, 'outputs', 'metric', 'pixel_size.json'), struct('views', pv, 'om_pixel_same_size', true));
Lp = tb.metric_lines(rdp);
want_p = sprintf(['Pixel size on the heart surface (%sm per OM pixel, binning 1 / 2): View1 124.1 / 248.2, ' ...
    'View2 129.0 / 258.0, View3 128.4 / 256.9, View4 130.5 / 261.0.'], char(181));
write_json(fullfile(rdp, 'outputs', 'metric', 'pixel_size.json'), struct('views', pv, 'om_pixel_same_size', false));
Lq = tb.metric_lines(rdp);
check('H4h', numel(Lp) == 2 && strcmp(Lp{2}, want_p) && numel(Lq) == 2 && ...
    contains(Lq{2}, [char(181) 'm per reconstruction pixel']) && contains(Lq{2}, 'does not say an OM pixel is this size') && ...
    contains(Lq{2}, 'View1 124.1, View2 129.0'), sprintf('%s || %s', Lp{2}, Lq{2}));   % um everywhere
check('H4b', contains(tb.units_header('mm'), 'mm, from') && contains(tb.units_header('model units'), 'physical scale not established') && ...
    ~contains(tb.units_header('units not confirmed'), 'physical scale not established') && ...
    contains(tb.units_header('units not confirmed'), 'not confirmed'), tb.units_header('units not confirmed'));
write_json(fullfile(rd, 'manifest.json'), struct('run_id', 'run1', 'pipeline', struct('calibration', ...
    struct('id', 'cal_x', 'date_note', 'The date of cut_tiffs_x is unknown.'))));
L5 = tb.metric_lines(rd);
check('H4c', any(contains(L5, 'cut_tiffs_x is unknown')) && ~any(contains(L5, 'may have changed')) && ~any(contains(L5, 'above')), L5{end});
write_json(mf, struct('schema', rabbit_calibration.METRIC_SCHEMA, 'applied', false, 'calibration_id', 'cal_x', 'reasons', {{'Moved.'}}));
L6 = tb.metric_lines(rd);
check('H4d', contains(L6{1}, 'was not applied') && any(contains(L6, 'cut_tiffs_x is unknown')), 'in the not-applied branch too');
fid2 = fopen(mf, 'w'); fprintf(fid2, '{ damaged'); fclose(fid2);
L7 = tb.metric_lines(rd);
check('H4e', contains(L7{1}, 'not confirmed') && any(contains(L7, 'cut_tiffs_x is unknown')), 'in the unreadable branch too');
write_json(fullfile(rd, 'manifest.json'), struct('run_id', 'run1', 'pipeline', struct('calibration', struct('id', 'cal_x', 'date_note', 5))));
L8 = tb.metric_lines(rd);
check('H4f', numel(L8) == 1, 'a date note that is not text is left out');
write_json(mf, struct('schema', rabbit_calibration.METRIC_SCHEMA, 'applied', true, 'calibration_id', 'cal_x', ...
    'scale_mm_per_unit', 270, 'scale_uncertainty_percent', NaN, 'target_edge_mm', 30, 'size_source', 'printed'));
% the projection finds the record of a mm model, and refuses a damaged one
rm = fullfile(rd, 'stages', 'sparse_build', 'model');
mkdir(rm);
check('H5', rabbit_rhythm_reproject.unit_scale_for_model(rm, 1000) == 1 && ...
    rabbit_rhythm_reproject.unit_scale_for_model([rm filesep], 1000) == 1 && ...
    rabbit_rhythm_reproject.unit_scale_for_model(fullfile(rd, 'stages'), 1000) == 1000, 'beside the model or one folder up');
fid2 = fopen(mf, 'w'); fprintf(fid2, '{ damaged'); fclose(fid2);
threw = '';
try
    rabbit_rhythm_reproject.unit_scale_for_model(rm, 1000);
catch ME
    threw = ME.identifier;
end
check('H6', strcmp(threw, 'analyse_om:Reprojection:BadMetricRecord'), threw);
threw = '';
try
    rabbit_rhythm_reproject.run(zeros(4), fullfile(root, 'x.json'), 'ColmapDir', rm, 'UnitScale', 1000);
catch ME
    threw = ME.identifier;
end
check('H7', ~strcmp(threw, 'analyse_om:Reprojection:BadMetricRecord'), sprintf('a given UnitScale wins (then %s)', threw));
threw = '';
try
    rabbit_rhythm_reproject.run(zeros(4), fullfile(root, 'x.json'), 'ColmapDir', rm, 'MeshFile', fullfile(root, 'x.ply'));
catch ME
    threw = ME.identifier;
end
check('H8', strcmp(threw, 'analyse_om:Reprojection:BadMetricRecord'), threw);
roi_s = fullfile(root, 'roi_s.json');
write_json(roi_s, struct('fov_mapping', struct('scale', struct('vertical', 1, 'horizontal', 1))));
[s1, t1] = rabbit_calibration.om_pixel_note(roi_s);
write_json(roi_s, struct('fov_mapping', struct('scale', struct('vertical', 0.5, 'horizontal', 1))));
[s2, t2] = rabbit_calibration.om_pixel_note(roi_s);
[s3, t3] = rabbit_calibration.om_pixel_note(fullfile(root, 'none.json'));
check('H9', s1 && contains(t1, 'also the size') && ~s2 && contains(t2, 'not the size') && ~s3 && contains(t3, 'could not'), t2);

%% the job, with a stand-in for Python
dsroot = fullfile(root, 'ds');
mkdir(dsroot);
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(dsroot, 'case');
assert(ok, err);
co = fullfile(root, 'co');
mkdir(fullfile(co, 'pyCamSet'));
stand = fullfile(root, 'py_fail.bat');
write_text_file(stand, sprintf('@echo off\r\nexit /b 2\r\n'));
tab.set_tool_path('pycamset_python', stand);
tab.set_tool_path('pycamset_checkout', co);
spec = rabbit_calibration.default_spec();
spec.recordings(1) = struct('path', ff, 'role', 'fit', 'type', 'PuzzleBoardCube', 'n_points', 7, 'edge_mm', 30, 'size_source', 'callipers');
spec.roi_bounds = [1 1 30 40; 1 41 30 100; 1 101 30 160; 1 161 30 200];
spec.size_source = 'callipers';
spec.frame_hw = [30 200];
spec.roi_hw = [30 200];
[ok, err, d1] = tab.run_calibration(spec);
v1 = jsondecode(fileread(fullfile(d1, 'verdict.json')));
check('J1', ~ok && strcmp(v1.status, 'FAILED') && ~v1.metric_allowed && ~isfolder(fullfile(d1, 'tiles')), err);
L = tab.calibration_list();
sj = jsondecode(fileread(fullfile(d1, 'spec.json')));
check('J1b', isfield(sj.recordings, 'date') && strcmp(sj.recordings(1).date, rabbit_calibration.fits_date(ff)), 'the date goes into spec.json');
check('J2', numel(L) == 1 && ~L(1).metric_allowed, L(1).label);
[ok, err, d2] = tab.run_calibration(spec);
[~, nm] = fileparts(d2);
check('J3', ~ok && strcmp(nm, 'cal_stack_01'), 'a second try never reuses the folder');
stand2 = fullfile(root, 'py_wait.bat');
write_text_file(stand2, sprintf('@echo off\r\nping -n 60 127.0.0.1 > nul\r\n'));
tab.set_tool_path('pycamset_python', stand2);
tk = timer('StartDelay', 15, 'TimerFcn', @(s, e) cancel_tab(tab));
start(tk);
t0 = tic;
[ok, err, d3] = tab.run_calibration(spec);
delete(tk);
v3 = jsondecode(fileread(fullfile(d3, 'verdict.json')));
check('J4', ~ok && contains(err, 'cancelled') && toc(t0) < 40 && strcmp(v3.status, 'FAILED'), sprintf('%s after %.0f s', err, toc(t0)));
tab.set_tool_path('pycamset_python', fullfile(root, 'nothing.exe'));
[ok, err] = tab.run_calibration(spec);
check('J5', ~ok && contains(err, 'Python'), err);

%% the app
g_prev = getenv('OM_APP_HEADLESS');
a = analyse_optical_mapping();
closer = onCleanup(@() delete(a));
dd = a.recon.ReconstructionCalibrationDropDown;
check('G1', strcmp(dd.Value, '') && strcmp(dd.Items{1}, 'None (model units)') && ...
    strcmp(char(a.recon.ReconstructionCalibrateButton.Visible), 'on'), 'no calibration is chosen by default');
a.bind_reconstruction_tab_for_test(tab);
good = fullfile(tab.calibration_root(), 'cal_good');
mkdir(good);
write_json(fullfile(good, 'verdict.json'), struct('schema', rabbit_calibration.VERDICT_SCHEMA, 'status', 'PASSED', 'metric_allowed', true));
write_json(fullfile(good, 'spec.json'), struct('recordings', struct('path', {ff, ff})));
a.recon.reconstruction_refresh_calibrations();
check('G2', numel(dd.Items) == 2 && strcmp(dd.ItemsData{2}, 'cal_good'), strjoin(dd.Items, ' | '));
dd.Value = 'cal_good';
[cd1, go, note1] = a.recon.reconstruction_calibration_for_run();   % no OM recording is loaded: its date is unknown
check('G3', go && strcmp(cd1, good) && contains(note1, 'unknown'), note1);
write_json(fullfile(good, 'spec.json'), struct('recordings', struct('path', {'Z:\gone\a.fits'}, 'date', {'2026-01-02'})));
a.file_info = struct('path', fileparts(om_dated), 'file', [stem_of(om_dated) '.fits'], 'name', [stem_of(om_dated) '.fits']);
headless_push('uiconfirm', 'Use it');
[cd2b, go, note2, differs2] = a.recon.reconstruction_calibration_for_run();
headless_push('uiconfirm', 'Cancel');
[~, go3] = a.recon.reconstruction_calibration_for_run();
check('G3b', go && differs2 && strcmp(cd2b, good) && contains(note2, '2026-01-02') && contains(note2, 'Used after the question') && ~go3, note2);
write_json(fullfile(good, 'verdict.json'), struct('schema', rabbit_calibration.VERDICT_SCHEMA, 'status', 'FAILED', 'metric_allowed', false));
[cd1, go] = a.recon.reconstruction_calibration_for_run();
check('G4', ~go && isempty(cd1) && strcmp(dd.Value, ''), 'a calibration that no longer passes is refused at click time');
a.recon.ReconstructionSparseSourceDropDown.Value = 'supplied';
a.recon.reconstruction_show_sparse_source();
check('G5', strcmp(char(dd.Visible), 'off'), 'with an existing sparse model there is no calibration choice');
a.recon.ReconstructionSparseSourceDropDown.Value = 'built';
a.recon.reconstruction_show_sparse_source();
tabb = rabbit_reconstruction_tab();
fid = fopen(fullfile(dsroot, 'case.fits'), 'w'); fclose(fid);
assert(tabb.load_state(dsroot, 'case_01'));
check('G7', strcmp(tabb.calibration_root(), tab.calibration_root()), tabb.calibration_root());
w = rabbit_calibration_dialog(tab, spec.roi_bounds, 8000, @() [], [30 200], [30 200]);
w.add_row(ff, 'fit', 'PuzzleBoardCube', 7, [], '');
sp = w.make_spec();
check('G6', isnan(sp.recordings(1).edge_mm) && sp.focal_px == 8000 && strcmp(char(w.Figure.Visible), 'off'), 'an empty edge stays empty');
headless_push('uigetdir', cut);
w.add_cut_folder();
check('G8', strcmp(w.Table.Data{end, 1}, cut), 'a cut folder can be chosen');
w.close_window();
% a cut folder as the recording to fit: tiles are cut, pyCamSet is reached
spec_cut = spec;
spec_cut.recordings(1).path = cut;
tab.set_tool_path('pycamset_python', stand);
[ok, err, dc] = tab.run_calibration(spec_cut);
jtxt = fileread(fullfile(dc, 'job.json'));
jb = jsondecode(jtxt);
check('G9', ~ok && ~contains(err, 'Could not') && jb.recordings(1).n_frames == 1 && contains(jb.recordings(1).name, 'cut'), err);
check('G13', ~isempty(regexp(jtxt, '"recordings":\s*\[', 'once')), 'one recording is still a JSON list in the job');
% an uncaught error leaves a window that can be closed, and says what happened
fake = struct('pycamset_python', '', 'pycamset_checkout', '', 'set_tool_path', @noop, ...
    'calibration_root', @() fullfile(root, 'fake'), 'record_calibration_failure', @noop, 'cancel_calibration', @noop);
mkdir(fullfile(root, 'fake'));
fake.run_calibration = @(s) throw_only();
w = rabbit_calibration_dialog(fake, spec.roi_bounds, 8000, @() [], [30 200], [30 200]);
w.add_row(ff, 'fit', 'PuzzleBoardCube', 7, 30, 'x');
w.run();
check('G10', ~w.Running && strcmp(char(w.CloseButton.Enable), 'on') && strcmp(char(w.RunButton.Enable), 'on') && ...
    strcmp(char(w.CancelButton.Enable), 'off') && contains(w.ResultsArea.Value{1}, 'boom') && isempty(w.Timer), ...
    w.ResultsArea.Value{1});
% the table's Squares and Edge as %g in wider columns, the values still
% numbers, and the pitch label with the micro sign
tb = w.Table;
lbl = findall(w.Figure, 'Type', 'uilabel');
pitch_lbl = lbl(strcmp(get(lbl, 'Text'), ['Pixel pitch (' char(181) 'm)']));
sp14 = w.make_spec();
% the cells are text (%s of %g, "7", "30"), the spec's
% values numbers; the file table is shorter (104 px) so the results pane shows more
g14 = ancestor(tb, 'matlab.ui.container.GridLayout');
check('G14', isequal(tb.ColumnFormat(4:5), {'char', 'char'}) && tb.ColumnWidth{4} >= 80 && tb.ColumnWidth{5} >= 110 && ...
    ischar(tb.Data{end, 4}) && strcmp(tb.Data{end, 4}, '7') && isequal(g14.RowHeight{2}, 104) && ...
    sp14.recordings(end).n_points == 7 && ...
    sp14.recordings(end).edge_mm == 30 && numel(pitch_lbl) == 1 && ~any(strcmp(get(lbl, 'Text'), 'Pixel pitch (um)')), ...
    sprintf('Squares/Edge %s %s, widths %d %d; pitch label found %d', tb.ColumnFormat{4}, tb.ColumnFormat{5}, ...
    tb.ColumnWidth{4}, tb.ColumnWidth{5}, numel(pitch_lbl)));
fake.run_calibration = @(s) make_then_throw(fullfile(root, 'fake', 'cal_x'));
w2 = rabbit_calibration_dialog(fake, spec.roi_bounds, 8000, @() [], [30 200], [30 200]);
w2.add_row(ff, 'fit', 'PuzzleBoardCube', 7, 30, 'x');
w2.run();
check('G11', ~w2.Running && any(contains(w2.ResultsArea.Value, 'Verdict: FAILED')) && any(contains(w2.ResultsArea.Value, 'saved reason')), ...
    strjoin(w2.ResultsArea.Value, ' | '));
w2.close_window();
w.close_window();
check('G12', ~isvalid(w) || ~isvalid(w.Figure), 'the window closes');
% signed values in user text: U+2212 for negatives, '+' for
% positives and for zero (sprintf's own convention), the decimals asked for
st = @(x, d) rabbit_reconstruction_tab.signed_text(x, d);
check('P14', strcmp(st(-1.161, 2), [char(8722) '1.16']) && strcmp(st(0.83, 2), '+0.83') && strcmp(st(0, 2), '+0.00') && ...
    strcmp(st(-0.24, 1), [char(8722) '0.2']) && ~contains(st(-5, 0), '-'), ...
    strjoin({st(-1.161, 2), st(0.83, 2), st(0, 2), st(-0.24, 1), st(-5, 0)}, ' | '));
% the frame position line right after Run is the saved
% line's sentence, from one builder
pl = rabbit_calibration.position_line(struct('path', fullfile('x', 'cut_tiffs_calibration_14h-12m-15s.tif'), ...
    'frame_offset', [0 0], 'offset_note', 'placed by the cut from the region dialog''s line-up (not shifted again)'));
tab_code = fileread(which('rabbit_reconstruction_tab'));
cal_code = fileread(which('rabbit_calibration'));
check('P13', strcmp(pl, ['Frame position used for cut_tiffs_calibration_14h-12m-15s.tif: 0 px down, 0 px right in the ' ...
    'reconstruction image: placed by the cut from the region dialog''s line-up (not shifted again). If it is wrong, ' ...
    'correct it with Position... and calibrate again.']) && contains(tab_code, 'lines{end + 1} = rabbit_calibration.position_line(r(k));') && ...
    contains(cal_code, 'txt{end+1} = rabbit_calibration.position_line(r(k));'), pl);
fprintf('PROBE_CALIBRATION RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    fprintf('PROBE_FAIL probe_calibration\n');
    error('probe_calibration:Failed', '%d check(s) failed.', fail);
end
fprintf('PROBE_OK probe_calibration %d/0\n', pass);
end

function p = fitsWriteDate(path, date1)
% Two FITS files with stated DATE cards
for k = 1:2
    q = path;
    if k == 2, q = strrep(path, '.fits', '_b.fits'); end
    if exist(q, 'file'), delete(q); end
    fp = matlab.io.fits.createFile(q);
    matlab.io.fits.createImg(fp, 'double_img', [2 2]);
    if k == 1
        matlab.io.fits.writeKey(fp, 'DATE', date1);
    else
        matlab.io.fits.writeKey(fp, 'DATE', '2026-07-31T10:00:00');
    end
    matlab.io.fits.closeFile(fp);
end
p = strrep(path, '.fits', '_b.fits');
end

function noop(varargin)
end

function varargout = throw_only()
varargout = cell(1, nargout);
error('analyse_om:Test:Boom', 'boom');
end

function varargout = make_then_throw(folder)
mkdir(folder);
write_json(fullfile(folder, 'verdict.json'), struct('schema', rabbit_calibration.VERDICT_SCHEMA, 'status', 'FAILED', ...
    'metric_allowed', false, 'failures', {{'saved reason'}}, 'warnings', {{}}));
varargout = cell(1, nargout);
error('analyse_om:Test:Boom', 'boom after the verdict');
end

function s = stem_of(p)
[~, s] = fileparts(p);
end

function cancel_tab(tab)
tab.cancel_calibration();
end

function write_text_file(path, txt)
fid = fopen(path, 'w');
fwrite(fid, txt, 'char');
fclose(fid);
end

function write_json(path, s)
fid = fopen(path, 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(s), 'char');
fclose(fid);
end

function R = rotx_deg(d)
c = cosd(d); s = sind(d);
R = [1 0 0; 0 c -s; 0 s c];
end

function R = roty_deg(d)
c = cosd(d); s = sind(d);
R = [c 0 s; 0 1 0; -s 0 c];
end

function [c, truth] = known_result(f, D)
cams = struct('tile', {}, 'focal_px', {}, 'k1', {}, 'pp_tile_px', {}, 'R_world_to_cam', {}, ...
    't_world_to_cam_mm', {}, 'centre_mm', {}, 'axis_world', {}, 'det_R', {}, 'points', {}, 'images', {}, ...
    'rmse_px', {}, 'depth_at_target_mm', {}, 'mm_per_px_at_target', {});
truth = struct('R', {}, 't', {}, 'pp', {});
for k = 1:4
    R = roty_deg(90 * (k - 1));
    t = [0; 0; D];
    C = -R' * t;
    pp = [200; 200];
    cams(k) = struct('tile', sprintf('tile%d', k), 'focal_px', f, 'k1', 0, 'pp_tile_px', pp, ...
        'R_world_to_cam', R, 't_world_to_cam_mm', t, 'centre_mm', C, 'axis_world', R(3, :)', 'det_R', 1, ...
        'points', 2500, 'images', 80, 'rmse_px', 0.9, 'depth_at_target_mm', D, 'mm_per_px_at_target', D / f);
    truth(k) = struct('R', R, 't', t / 1, 'pp', pp);
end
c = struct('schema', rabbit_calibration.RESULT_SCHEMA, ...
    'lens', struct('focal_px', f, 'k1', 0), ...
    'target', struct('type', 'PuzzleBoardCube', 'n_points', 7, 'edge_mm', 30), ...
    'cameras', cams, 'rig', struct(), ...
    'residual', struct('rmse_px', 0.9, 'median_px', 0.7, 'p95_px', 1.8), ...
    'observations', struct('detected', 13000, 'used', 12000, 'kept_fraction', 0.92), ...
    'holdout', struct('name', 'other cube', 'frames_used', 40, 'scale_error_percent', 0.1, ...
    'scale_se_percent', 0.1, 'residual_mm_median', 0.1));
end

function images = known_model(truth, scale, prefixes, n)
% The same rig in model units, on a world turned frame by frame
images = containers.Map('KeyType', 'int64', 'ValueType', 'any');
id = 0;
for fr = 1:n
    W = roty_deg(10 * fr) * rotx_deg(5 * fr);
    tw = [fr; -fr; 2 * fr];
    for k = 1:4
        id = id + 1;
        R = truth(k).R * W;
        C = W' * (-truth(k).R' * truth(k).t / scale) + tw;
        t = -R * C;
        q = rotm2q(R);
        images(id) = struct('qvec', q, 'tvec', t, 'camera_id', k, 'name', sprintf('%s%04d.tiff', prefixes{k}, fr));
    end
end
end

function q = rotm2q(R)
% Quaternion (w x y z) of a rotation matrix
t = trace(R);
if t > 0
    s = sqrt(t + 1) * 2;
    q = [s / 4; (R(3, 2) - R(2, 3)) / s; (R(1, 3) - R(3, 1)) / s; (R(2, 1) - R(1, 2)) / s];
else
    [~, i] = max(diag(R));
    j = mod(i, 3) + 1; k = mod(j, 3) + 1;
    s = sqrt(R(i, i) - R(j, j) - R(k, k) + 1) * 2;
    q = zeros(4, 1);
    q(1) = (R(k, j) - R(j, k)) / s;
    q(i + 1) = s / 4;
    q(j + 1) = (R(j, i) + R(i, j)) / s;
    q(k + 1) = (R(k, i) + R(i, k)) / s;
end
end

function R = known_recipe(prefixes, f)
b = [1 1 400 428; 29 618 381 969; 44 1126 377 1477; 42 1666 400 1957];
order = [2 3 1 4];     % ROI rows of the new labels: row 1 is the second tile
for k = 1:4
    v(k) = struct('bounds', b(order(k), :), 'image_prefix', prefixes(order(k))); %#ok<AGROW>
    v(k).image_prefix = prefixes{order(k)};
end
R = struct('resolved', struct('views', v, 'focal_prior_px', f));
end

function [cameras, images] = stub_reader(dir_path, base, scale, focal)
cameras = containers.Map('KeyType', 'int64', 'ValueType', 'any');
if isscalar(focal), focal = focal * [1 1 1 1]; end
for k = 1:4
    cameras(int64(k)) = struct('model', 'SIMPLE_RADIAL', 'width', 400, 'height', 400, 'params', [focal(k) 200 200 0]);
end
images = containers.Map('KeyType', 'int64', 'ValueType', 'any');
ids = cell2mat(keys(base));
s = 1;
[~, nm] = fileparts(dir_path);
if strcmp(nm, 'model_mm'), s = scale; end
for k = ids
    im = base(k);
    im.tvec = im.tvec * s;
    images(k) = im;
end
end

function [ok, err, code] = stub_vanish(stage)
% COLMAP reported success, and the output folder is not there
rmdir(fullfile(stage, 'model_mm'), 's');
ok = true; err = ''; code = 0;
end

function [ok, err, code] = stub_transform(line, stage)
% What COLMAP model_transformer does for this probe: write model_mm
mm = fullfile(stage, 'model_mm');
if ~isfolder(mm), mkdir(mm); end
fid = fopen(fullfile(mm, 'scaled.txt'), 'w'); fprintf(fid, '%s\n', line); fclose(fid);
ok = true; err = ''; code = 0;
end
