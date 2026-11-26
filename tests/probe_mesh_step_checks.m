function probe_mesh_step_checks
%% Probe: mesh-step checks of the rabbit reconstruction
% Collin Snitchler
% 15.10.2026
% Checks, without COLMAP, a GPU or the OM data:
%   Q1 static_field_bands: over 12 frames of one view, a mask edge cut by
%      the field of view 15 px from the left border (still) gets a band in
%      the frames where the heart reaches it, and none in a frame where
%      the heart's outline lies more than 10 px inside it; the top, bottom
%      and right outlines of the moving heart, which come within 32 px of
%      the border in some frames, get none (the one-mask rule field_band
%      bands them); the record names the left side as the only still one;
%      a view with fewer than 8 frames, names without _view<V>_frame_<N>
%      and a band width of 0 give no band
%   Q2 filter_cameras carries those bands; membrane_cameras takes them
%   Q3 the field band is limited: 64 px is accepted, 65 px is refused by
%      the recipe check and by the mesh step's check
%   Q4 drop_posed_only repeats: removing an image without its own points
%      leaves another below the minimum, which a second image_deleter pass
%      removes (anchored, then anchored_2)
%   Q5 view_silhouette_check: a view whose masks hold far more than the
%      mesh (a panel beside the heart) is named low, with a warning; views
%      whose masks fit are not
% Usage: matlab -batch "addpath('<repo>/tests'); probe_mesh_step_checks" -noFigureWindows

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));
work = tempname;
mkdir(work);
cleanup = onCleanup(@() rmdir(work, 's'));

%% Q1 still field edge against moving outlines
h = 100; w = 120; nfr = 12;
[cc, rr] = meshgrid(1:w, 1:h);
masks = cell(1, nfr);
names = cell(1, nfr);
% The heart turns: in frames 1-6 it reaches past the field edge on the left, in frames 7-12
% it lies well inside it; its top, bottom and right outlines come within 32 px of the border
% at changing distances
cx = [30 35 40 45 50 30 69 73 77 81 85 75];
cy = [30 55 40 65 35 60 45 25 70 50 30 60];
for k = 1:nfr
    m = (cc - cx(k)) .^ 2 + (rr - cy(k)) .^ 2 <= 35 ^ 2;
    m(:, 1:15) = false;               % the field of view starts at column 16
    masks{k} = m;
    names{k} = sprintf('q_view2_frame_%04d.tiff', k);
end
[bands, rec] = rabbit_sfm_build.static_field_bands(names, masks, 32);
reach = cx - 35 <= 15;               % frames where the heart reaches the field edge
far = cx - 35 >= 27;                 % the heart's left outline more than 10 px inside the field edge
left_ok = true; others_ok = true; one_mask_other = false;
for k = 1:nfr
    b = bands{k};
    m = masks{k};
    centre = round(cy(k)) + (-6:6);    % rows whose outline the field edge cuts in a reaching frame
    if reach(k)
        left_ok = left_ok && all(all(b(centre, 1:15)));
    end
    if far(k)
        left_ok = left_ok && ~any(b(:));
    end
    % a left band ends at most 32 px from the border; any band pixel further right belongs
    % to the top, bottom or right outline
    other = cc > 32;
    others_ok = others_ok && ~any(b(:) & other(:));
    one = rabbit_sfm_build.field_band(m, 32);
    one_mask_other = one_mask_other || any(one(:) & other(:));
end
sides = rec(1).sides;
still_left = sides(strcmp({sides.side}, 'left')).still_lines;
still_other = sum([sides(~strcmp({sides.side}, 'left')).still_lines]);
[b_few, rec_few] = rabbit_sfm_build.static_field_bands(names(1:5), masks(1:5), 32);
[b_nonames, rec_nn] = rabbit_sfm_build.static_field_bands(strrep(names, '_view2_', '_x_'), masks, 32);
[b_zero] = rabbit_sfm_build.static_field_bands(names, masks, 0);
Q1 = left_ok && others_ok && one_mask_other && still_left > 0 && still_other == 0 && any(reach) && any(far) && ...
    ~any(cellfun(@(b) any(b(:)), b_few)) && contains(rec_few(1).note, 'fewer than 8') && ...
    ~any(cellfun(@(b) any(b(:)), b_nonames)) && isnan(rec_nn(1).view) && ...
    ~any(cellfun(@(b) any(b(:)), b_zero));
fprintf(['Q1 static field band: left band only where the heart reaches the field edge %s, no band on the ' ...
    'moving outlines %s (one-mask rule bands them %s); still lines left %d, other sides %d; 5 frames: %s; ' ...
    'names without a view: %s -> %s\n'], tf(left_ok), tf(others_ok), tf(one_mask_other), still_left, still_other, ...
    rec_few(1).note, rec_nn(1).note, tf(Q1));
if Q1, pass = pass + 1; else, fail = fail + 1; end

%% Q2 filter_cameras carries the bands, membrane_cameras takes them
mask_root = fullfile(work, 'masks');
mkdir(mask_root);
cameras = containers.Map('KeyType', 'int64', 'ValueType', 'any');
cameras(int64(1)) = struct('model', 'PINHOLE', 'width', w, 'height', h, 'params', [400; 400; w / 2; h / 2]);
images = struct('id', num2cell(1:nfr), 'qvec', [1 0 0 0], 'tvec', [0 0 10], 'camera_id', 1, 'name', names);
for k = 1:nfr
    imwrite(uint8(masks{k}) * 255, fullfile(mask_root, [names{k} '.png']));
end
[fc, frec] = rabbit_mesh_cleanup.filter_cameras(cameras, images, mask_root, 32);
fc0 = rabbit_mesh_cleanup.filter_cameras(cameras, images, mask_root, 0);
same = true;
has_band = cellfun(@(b) any(b(:)), bands);
for k = 1:nfr
    if has_band(k)
        same = same && isequal(fc(k).band, bands{k});
    else
        same = same && isempty(fc(k).band);
    end
end
bm = rabbit_mesh_cleanup.band_map(fc);
Q2 = numel(fc) == nfr && same && all(arrayfun(@(c) isempty(c.band), fc0)) && bm.Count == nnz(has_band) && ...
    contains(rabbit_mesh_cleanup.band_sides_text(frec), 'view 2: left');
fprintf('Q2 filter_cameras: %d cameras, bands as static_field_bands %s, %d with a band; %s -> %s\n', ...
    numel(fc), tf(same), bm.Count, rabbit_mesh_cleanup.band_sides_text(frec), tf(Q2));
if Q2, pass = pass + 1; else, fail = fail + 1; end

%% Q3 the band width is limited
D = rabbit_sfm_build.defaults();
R64 = D; R64.mesh.field_band_px = 64;
R65 = D; R65.mesh.field_band_px = 65;
ok64 = rabbit_sfm_build.validate(R64);
[ok65, err65] = rabbit_sfm_build.validate(R65);
e65 = '';
try
    rabbit_mesh_cleanup.check_band_px(65);
catch ME
    e65 = ME.identifier;
end
e64 = '';
try
    rabbit_mesh_cleanup.check_band_px(64);
catch ME
    e64 = ME.identifier;
end
Q3 = ok64 && ~ok65 && contains(err65, '64') && strcmp(e65, 'rabbit_mesh_cleanup:FieldBand') && isempty(e64) && ...
    rabbit_sfm_build.MAX_FIELD_BAND_PX == 64;
fprintf('Q3 band limit: 64 accepted %s, 65 refused (%s), mesh-step check %s -> %s\n', tf(ok64), err65, e65, tf(Q3));
if Q3, pass = pass + 1; else, fail = fail + 1; end

%% Q4 drop_posed_only repeats after a removal
bdir = fullfile(work, 'final');
mkdir(bdir);
calls = {};
ctx = struct('Rr', D, 'colmap_exe', 'colmap', 'reader', @fake_reader, ...
    'run_cmd', @fake_run, 'note', @(s) fprintf('  note: %s\n', s));
r = struct('err', '', 'commands_run', {{}}, 'exit_code', 0);
P = struct('model_dir', fullfile(work, 'model0'));
[P, r] = rabbit_sfm_build.drop_posed_only(ctx, r, P, bdir);
[~, last_dir] = fileparts(P.model_dir);
Q4 = isempty(r.err) && P.deleter_passes == 2 && isequal(sort(P.posed_only_images), {'c_view3_frame_0001', 'd_view4_frame_0001'}) && ...
    isequal(sort(P.removed_images), {'c_view3_frame_0001', 'd_view4_frame_0001'}) && strcmp(last_dir, 'anchored_2') && ...
    numel(calls) == 2 && contains(calls{2}, fullfile(bdir, 'anchored')) && ...
    isfile(fullfile(bdir, 'posed_only_images_2.txt')) && isequal(P.registered_per_view, [1 1 0 0]);
fprintf('Q4 drop_posed_only: %d passes, removed %s, model %s, per view %s -> %s\n', P.deleter_passes, ...
    strjoin(P.removed_images, ', '), last_dir, mat2str(P.registered_per_view), tf(Q4));
if Q4, pass = pass + 1; else, fail = fail + 1; end

%% Q5 per-view silhouette check
[sx, sy, sz] = sphere(40);
fv = surf2patch(sx, sy, sz, 'triangles');
V = fv.vertices;
F = fv.faces;
F = F(all(diff(sort(F, 2), 1, 2) > 0, 2), :);       % no degenerate faces at the poles
cams = struct('name', {}, 'R', {}, 't', {}, 'f', {}, 'c', {}, 'width', {}, 'height', {}, 'mask', {}, 'band', {});
for v = 1:3
    for k = 1:2
        cam = struct('name', sprintf('s_view%d_frame_%04d.tiff', v, k), 'R', eye(3), 't', [0; 0; 6], ...
            'f', [150 150], 'c', [60 50], 'width', 120, 'height', 100, 'mask', [], 'band', []);
        Xc = V * cam.R' + cam.t(:)';
        uv = [cam.f(1) * Xc(:, 1) ./ Xc(:, 3) + cam.c(1), cam.f(2) * Xc(:, 2) ./ Xc(:, 3) + cam.c(2)];
        cam.mask = rabbit_mesh_alignment.mesh_silhouette(uv, F, 100, 120);
        if v == 3
            cam.mask(1:45, :) = true;    % a bright panel above the heart in the mask
        end
        cams(end+1) = cam; %#ok<AGROW>
    end
end
chk = rabbit_mesh_cleanup.view_silhouette_check(V, F, cams, 0.6);
chk1 = rabbit_mesh_cleanup.view_silhouette_check(V, F, cams(1:2), 0.6);
Q5 = isequal(chk.views, [1 2 3]) && isequal(chk.low_views, 3) && all(chk.iou_median(1:2) > 0.95) && ...
    chk.iou_median(3) < 0.6 && contains(chk.warning, 'view 3') && isempty(chk1.low_views);
fprintf('Q5 view check: median IoU per view %s, low %s -> %s\n  %s\n', mat2str(chk.iou_median, 3), ...
    mat2str(chk.low_views), tf(Q5), chk.warning);
if Q5, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MESH_STEP_CHECKS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_mesh_step_checks %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_mesh_step_checks\n');
end

    function [ok, err, code] = fake_run(line, ~, ~)
        % COLMAP stand-in: records the command line; the reader knows the result
        calls{end+1} = line;
        ok = true; err = ''; code = 0;
    end
end


function [cams, imgs, pts] = fake_reader(folder)
% Four images a-d (views 1-4). model0: c has 5 points of its own (posed only); d has 16, of
% which 2 are seen only by c and d. Without c (anchored) those 2 points have one image left,
% so COLMAP drops them and d falls to 14 (posed only). anchored_2: a and b only.
[~, tag] = fileparts(folder);
cams = containers.Map('KeyType', 'int64', 'ValueType', 'any');
imgs = containers.Map('KeyType', 'int64', 'ValueType', 'any');
pts = containers.Map('KeyType', 'int64', 'ValueType', 'any');
nm = {'a_view1_frame_0001', 'b_view2_frame_0001', 'c_view3_frame_0001', 'd_view4_frame_0001'};
switch tag
    case 'model0'
        obs = {1:20, 1:20, [21 22 30 31 32], [1:14 21 22]};
    case 'anchored'
        obs = {1:20, 1:20, [], 1:14};
    otherwise
        obs = {1:20, 1:20, [], []};
end
for i = 1:4
    if strcmp(tag, 'anchored') && i == 3, continue; end
    if strcmp(tag, 'anchored_2') && i >= 3, continue; end
    imgs(int64(i)) = struct('name', nm{i}, 'point3D_ids', obs{i});
end
ids = unique([obs{:}]);
for p = ids
    seen = find(cellfun(@(o) any(o == p), obs));
    pts(int64(p)) = struct('image_ids', seen);
end
end
