function probe_rhythm_pure
%% Probe: reprojection through RHYTHM's own dataProjection02
% Collin Snitchler
% 06.10.2026
% Builds a closed box mesh, four pinhole cameras looking at it from the
% four sides (ROI order view2;view3;view1;view4) and a 4-view activation
% canvas whose value in each view is a known linear ramp, then runs
% rabbit_rhythm_reproject.run with the default method. Checks that:
%   - the vendored RHYTHM files are byte-identical before and after;
%   - the default path calls dataProjection02 itself, leaves no figure,
%     restores the current folder and writes nothing into it;
%   - each side of the box is assigned to the camera facing it, with the
%     ramp value at the projected face centre;
%   - a frame stack is projected as a per-face time series;
%   - the projected PLY gives a vertex the mean of its assigned faces
%     only (NaN when it has none), never averaging in unassigned zeros;
%   - the reimplementation stays selectable, and how far it agrees.
%   - views mirrored for the sparse model (ViewFlips) project like
%     unmirrored ones, and a shift on a flipped axis is turned round
%    .
% Usage: matlab -batch "addpath('<repo>/tests'); probe_rhythm_pure"
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0;
fail = 0;

%% Vendored RHYTHM files (sha256 as listed in third_party/RHYTHM/NOTICE.md)
vendored = { ...
    'Common_files/configc.m', 'f717cc79b1726fe17dfb3a4abd12ea83f875436e05c27053f3824d0777016f5b'; ...
    'Common_files/imdist.m', '7c761621383ac633ad83bd1fe7e884733548c6ef87d85365a31141edc9f9fd97'; ...
    'Common_files/pred.m', 'd3b1c8e30fea16a76566aadf679fc315be3d83edadbdc1fe53139950e0e96d3a'; ...
    'ORIENT_files/checkpoly.m', '98f337fb3285e9c1ccd41da5f15b3de70da7881d9d326a86775ffeb2e5e0318a'; ...
    'ORIENT_files/conefilt.m', '685e0c8f76e75d6e003a266ff60d141cef894dd54f093d7a872a541dc4a62fe7'; ...
    'ORIENT_files/convex_intersect.m', 'f8c29637d928af5302b7d5394d253aae830939a596566b7e0a736cbc388b078a'; ...
    'ORIENT_files/dataProjection02.m', '289ba0fb10a61a82c08cc37e28d6fd9c1e3ae4dae8c946eb70c59bfa7189b885'; ...
    'ORIENT_files/line_intersect.m', '377a1ecda4df1d45c7602421c7308642b4866aca9cc880e54acc78031e8041b7'; ...
    'ORIENT_files/smoothregionbdr.m', '1dc2a829cef8548d5308fde2a355e4433a5c0768cd01be1d591b1b6d19fb5ff7'};
src_root = fullfile(repo_dir, 'third_party', 'RHYTHM', 'Source Code', 'MATLAB');
record('V1 vendored RHYTHM files match the pinned hashes (before)', ...
    vendored_ok(src_root, vendored), sprintf('%d files', size(vendored, 1)));

%% Synthetic scene: 400x400 views (binned 4x4), coarse 12x12 box sides
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
sc = build_scene(root, 'coarse', 12, 400, 1500);
canvas = sc.canvas; json_path = sc.json_path; colmap_dir = sc.colmap_dir;
mesh_path = sc.mesh_path; views = sc.views; names = sc.names;
pts = sc.pts; faces = sc.faces; normal = sc.normal;
expected_view = sc.expected_view; expected = sc.expected; inner = sc.inner;

%% Default method: dataProjection02 itself
frames = cat(3, canvas, 2 * canvas, 3 * canvas);
out_dir = fullfile(root, 'out');
here = pwd;
listing0 = dir(here);
figs0 = findall(0, 'type', 'figure');
tic;
r = rabbit_rhythm_reproject.run(canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1, 'Frames', frames, 'Fps', 8, ...
    'OutDir', out_dir);
t_rhythm = toc;
figs1 = findall(0, 'type', 'figure');
listing1 = dir(here);
record('P1 default method is RHYTHM dataProjection02', ...
    strcmp(r.method, 'rhythm') && isempty(r.method_note) && ...
    contains(r.rhythm.log, 'Projection and mapping'), ...
    sprintf('method=%s %.1f s', r.method, t_rhythm));
record('P2 views are binned to 100x100 with the RHYTHM camera', ...
    isequal(size(r.rhythm.masks), [100 100 4]) && ...
    strcmp(r.rhythm.camera, 'brainvision_ultimaL') && ...
    isequal(r.rhythm.bins(1).source_px_per_rhythm_px, [4 4]), ...
    sprintf('masks %s', mat2str(size(r.rhythm.masks))));
record('P3 RHYTHM figures closed, folder restored, nothing written to it', ...
    numel(figs1) == numel(figs0) && strcmp(pwd, here) && ...
    numel(listing1) == numel(listing0), ...
    sprintf('figures %d->%d files %d->%d', numel(figs0), numel(figs1), ...
    numel(listing0), numel(listing1)));
record('P4 view cameras resolved by view number (row 1 is view2)', ...
    isequal(r.view_names_used(:)', names), strjoin(r.view_names_used, ' '));

assigned_view = r.viewi(:, end);
side_ok = mean(assigned_view(inner) == expected_view(inner));
record('P5 inner side faces are assigned to the camera facing them', ...
    side_ok == 1 && all(r.mask(inner)), sprintf('%.4f of %d', side_ok, nnz(inner)));
err = abs(r.dataProj(inner) - expected(inner));
record('P6 projected values match the ramp at the face centre', ...
    median(err) < 0.3 && prctile(err, 99) < 1.0, ...
    sprintf('median %.3f p99 %.3f max %.3f', median(err), prctile(err, 99), max(err)));
topbot = abs(normal(:, 3)) > 0.99;
record('P7 top and bottom (grazing in every view) are never a DIRECT view', ...
    ~any(ismember(r.viewi(topbot, end), 1:4)) && all(r.dataProj(~r.mask) == 0), ...
    sprintf('%.3f unassigned, rest EDGE', mean(~r.mask(topbot))));
ser = r.series(r.mask, :);
lin = abs(ser - r.dataProj(r.mask) * [1 2 3]);
record('P8 frame stack projected as a per-face time series', ...
    isequal(size(r.series), [size(faces, 1) 3]) && max(lin(:)) < 1e-9 && ...
    all(isnan(r.series(~r.mask, 1))), sprintf('max deviation %.2g', max(lin(:))));
v = load(r.video_path);
record('P9 video MAT saved for the viewer', ...
    isequal(size(v.face_series), [size(faces, 1) 3]) && ...
    isequal(size(v.vertex_series), [size(pts, 1) 3]) && v.fps == 8 && ...
    isequal(v.faces, faces), r.video_path);

%% NaN pixels are left out, not spread
nan_canvas = canvas;
nan_canvas(:, 1:40) = NaN;   % a strip of view2 (rotated into the canvas)
r_nan = rabbit_rhythm_reproject.run(nan_canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1);
in_range = true;
for k = 1:4
    sel = r_nan.mask & r_nan.viewi(:, end) == k;
    in_range = in_range && all(r_nan.dataProj(sel) >= min(views{k}(:)) & ...
        r_nan.dataProj(sel) <= max(views{k}(:)));
end
record('P10 NaN source pixels never produce NaN or out-of-range values', ...
    all(isfinite(r_nan.dataProj)) && in_range, sprintf('%d assigned', nnz(r_nan.mask)));

%% The projected PLY never averages unassigned faces in as 0
% Two faces share vertices 2 and 3; only face 1 is assigned (12 ms), so
% vertices 1-3 carry 12 and vertex 4 (only in the unassigned face) NaN.
two = struct('pts', [0 0 0; 1 0 0; 0 1 0; 1 1 0], 'faces', [1 2 3; 2 4 3]);
two_ply = [tempname '.ply'];
rabbit_rhythm_reproject.write_projected_ply(two_ply, two, [12; 0], [true; false]);
two_txt = fileread(two_ply);
delete(two_ply);
two_body = regexp(two_txt, 'end_header\s*(.*)', 'tokens', 'once');
two_vals = sscanf(two_body{1}, '%f');
two_act = two_vals(4:4:16)';
record('P13 projected PLY: assigned faces only, NaN where no face is assigned', ...
    isequaln(two_act, [12 12 12 NaN]), mat2str(two_act));

%% Rotation 1 and 3 canvases: regions_chosen's slot order
% Unequal regions (the real 2026-07-31 sizes), assembled as the app does:
% sorted by first column, then rotation 3 swaps slots 3 and 4 and rotation
% 1 takes the order 4 3 1 2. split_canvas must return each ROI row's crop.
b_real = [1 1 400 428; 29 618 381 969; 44 1126 377 1477; 42 1666 400 1957];
frame = reshape(1:400 * 2000, 400, 2000);
split_ok = true;
for rot = [1 3]
    c = app_canvas(frame, b_real, rot);
    sv = rabbit_rhythm_reproject.split_canvas(c, b_real, rot);
    for k = 1:4
        crop = frame(b_real(k, 1):b_real(k, 3), b_real(k, 2):b_real(k, 4));
        split_ok = split_ok && isequal(sv{k}, crop);
    end
end
record('P14 rotation 1/3 canvases split back to each ROI row''s crop', split_ok, '');

%% FlipRows turns each view the right way up before projection
w_scene = size(views{1}, 2);
h_scene = size(views{1}, 1);
bounds_scene = [1 1 h_scene w_scene; 1 w_scene+1 h_scene 2*w_scene; ...
    1 2*w_scene+1 h_scene 3*w_scene; 1 3*w_scene+1 h_scene 4*w_scene];
flip_canvas = assemble_canvas(cellfun(@flipud, views, 'UniformOutput', false), bounds_scene);
r_flip = rabbit_rhythm_reproject.run(flip_canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1, 'FlipRows', true);
record('P15 FlipRows on an upside-down canvas gives the same projection', ...
    isequal(r_flip.mask, r.mask) && max(abs(r_flip.dataProj - r.dataProj)) < 1e-9, ...
    sprintf('%d assigned', nnz(r_flip.mask)));

%% ViewFlips: views whose SfM images were mirrored
% The cameras image views{k}; a canvas holding views 1 and 4 left-right
% mirrored and view 2 upside down (as the OM data of mirrored views is,
% relative to the flipped SfM images) with ViewFlips lr/ud/none/lr must
% give the same projection, including the frame series (P18-P19; the
% shift rule is P20, on the dense scene below).
vf_views = views;
vf_views{1} = fliplr(views{1}); vf_views{2} = flipud(views{2}); vf_views{4} = fliplr(views{4});
vf_canvas = assemble_canvas(vf_views, bounds_scene);
vf_frames = cat(3, vf_canvas, 2 * vf_canvas, 3 * vf_canvas);
r_vf = rabbit_rhythm_reproject.run(vf_canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1, 'Frames', vf_frames, 'Fps', 8, ...
    'ViewFlips', {'lr', 'ud', 'none', 'lr'});
series_ok = isequal(isnan(r_vf.series), isnan(r.series)) && ...
    max(abs(r_vf.series(~isnan(r.series)) - r.series(~isnan(r.series)))) < 1e-9;
record('P18 ViewFlips undo mirrored views (map and frames)', ...
    isequal(r_vf.mask, r.mask) && max(abs(r_vf.dataProj - r.dataProj)) < 1e-9 && ...
    series_ok && isequal(r_vf.view_flips, {'lr', 'ud', 'none', 'lr'}), ...
    sprintf('%d assigned', nnz(r_vf.mask)));
r_nf = rabbit_rhythm_reproject.run(vf_canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1);
record('P19 without ViewFlips the mirrored canvas projects differently', ...
    max(abs(r_nf.dataProj(inner) - r.dataProj(inner))) > 1, '');

%% Frames with missing data do not blank the map
% Frame 2 entirely NaN (a dropped frame) and one NaN pixel in frame 3: the
% map keeps its faces, frame 2 is NaN in the series, the others as before.
gap_frames = frames;
gap_frames(:, :, 2) = NaN;
gap_frames(200, 200, 3) = NaN;
r_gap = rabbit_rhythm_reproject.run(canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1, 'Frames', gap_frames, 'Fps', 8, ...
    'OutDir', fullfile(root, 'out_gap'));
keep = r.mask & r_gap.mask;
dev = abs(r_gap.series(keep, [1 3]) - r.series(keep, [1 3]));
record('P16 an all-NaN frame is left out of the mask and is NaN in the series', ...
    nnz(r_gap.mask) >= 0.99 * nnz(r.mask) && all(isnan(r_gap.series(:, 2))) && ...
    median(dev(:)) < 1e-9 && contains(r_gap.method_note, '1 of 3 OM frames'), ...
    sprintf('assigned %d vs %d; note: %s', nnz(r_gap.mask), nnz(r.mask), r_gap.method_note));
% A strip of NaN in one frame removes more than 5 % of the map: noted
strip_frames = frames;
strip_frames(:, 1:200, 1) = NaN;
r_strip = rabbit_rhythm_reproject.run(canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1, 'Frames', strip_frames, 'Fps', 8, ...
    'OutDir', fullfile(root, 'out_strip'));
record('P17 a mask that removes more than 5 % of the map is noted', ...
    contains(r_strip.method_note, 'activation map''s pixels are left out'), r_strip.method_note);

%% Reimplementation (fallback) against RHYTHM
% The reimplementation draws each view's silhouette from rounded face
% centroids at the native view resolution, so it needs a mesh denser than
% the view pixels: on the coarse box it assigns nothing. It is compared on
% a dense box imaged at 100x100, where binning is the identity.
r_re = rabbit_rhythm_reproject.run(canvas, json_path, 'ColmapDir', colmap_dir, ...
    'MeshFile', mesh_path, 'UnitScale', 1, 'Method', 'reimplementation');
record('P11 reimplementation selectable (coarse mesh: sparse silhouette)', ...
    strcmp(r_re.method, 'reimplementation'), sprintf('%d assigned', nnz(r_re.mask)));
sd = build_scene(root, 'dense', 45, 100, 337.5);
tic;
r_a = rabbit_rhythm_reproject.run(sd.canvas, sd.json_path, 'ColmapDir', sd.colmap_dir, ...
    'MeshFile', sd.mesh_path, 'UnitScale', 1);
t_a = toc;
tic;
r_b = rabbit_rhythm_reproject.run(sd.canvas, sd.json_path, 'ColmapDir', sd.colmap_dir, ...
    'MeshFile', sd.mesh_path, 'UnitScale', 1, 'Method', 'reimplementation');
t_b = toc;
both = r_a.mask & r_b.mask;
overlap = nnz(both) / max(1, nnz(r_a.mask | r_b.mask));
same_view = mean(r_a.viewi(both, end) == r_b.viewi(both, end));
mad = median(abs(r_a.dataProj(both) - r_b.dataProj(both)));
err_a = median(abs(r_a.dataProj(sd.inner) - sd.expected(sd.inner)));
err_b = median(abs(r_b.dataProj(sd.inner) - sd.expected(sd.inner)));
record('P12 RHYTHM and reimplementation agree on a dense mesh at 100x100', ...
    strcmp(r_a.method, 'rhythm') && overlap > 0.9 && mad < 0.05 && ...
    err_a < 0.05 && err_b < 0.05, ...
    sprintf(['faces %d, assigned overlap %.3f, same view %.3f, median |diff| %.4f, ' ...
    'median error RHYTHM %.4f reimpl %.4f, %.1f s vs %.1f s'], size(sd.faces, 1), ...
    overlap, same_view, mad, err_a, err_b, t_a, t_b));

% P20 on the dense 100x100 scene (binning is the identity there): view 1
% flipped left-right, its OM tile 3 columns right of the camera's tile
% (Shifts dx = +3 in tile terms); the adapter must turn the shift round.
wd = size(sd.views{1}, 2); hd = size(sd.views{1}, 1);
bounds_d = [1 1 hd wd; 1 wd+1 hd 2*wd; 1 2*wd+1 hd 3*wd; 1 3*wd+1 hd 4*wd];
ref_views = sd.views; ref_views{1} = fliplr(sd.views{1});
sh_views = ref_views; sh_views{1} = circshift(ref_views{1}, [0 3]);
shifts = zeros(4, 2); shifts(1, 1) = 3;
vf4 = {'lr', 'none', 'none', 'none'};
r_ref = rabbit_rhythm_reproject.run(assemble_canvas(ref_views, bounds_d), sd.json_path, ...
    'ColmapDir', sd.colmap_dir, 'MeshFile', sd.mesh_path, 'UnitScale', 1, 'ViewFlips', vf4);
r_sh = rabbit_rhythm_reproject.run(assemble_canvas(sh_views, bounds_d), sd.json_path, ...
    'ColmapDir', sd.colmap_dir, 'MeshFile', sd.mesh_path, 'UnitScale', 1, ...
    'Shifts', shifts, 'ViewFlips', vf4);
sel1 = r_ref.mask & r_sh.mask & r_ref.viewi(:, end) == 1 & sd.inner;
record('P20 a shift on a flipped axis is turned round', ...
    nnz(sel1) > 0 && median(abs(r_sh.dataProj(sel1) - r_ref.dataProj(sel1))) < 0.05 && ...
    median(abs(r_ref.dataProj(sel1) - sd.expected(sel1))) < 0.05, ...
    sprintf('%d view-1 faces, median |diff| %.4f', nnz(sel1), ...
    median(abs(r_sh.dataProj(sel1) - r_ref.dataProj(sel1)))));

record('V2 vendored RHYTHM files match the pinned hashes (after)', ...
    vendored_ok(src_root, vendored), sprintf('%d files', size(vendored, 1)));

fprintf('PROBE_RHYTHM_PURE RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0
    error('PROBE_FAIL probe_rhythm_pure');
end
fprintf('PROBE_OK probe_rhythm_pure %d/0\n', pass);

    function record(name, condition, detail)
        if condition
            pass = pass + 1;
            result = 'PASS';
        else
            fail = fail + 1;
            result = 'FAIL';
        end
        fprintf('%s %s %s\n', name, result, detail);
    end
end

function sc = build_scene(root, tag, n_side, w, f)
% Box mesh (n_side x n_side squares per side, tilted 0.5 deg about a
% generic axis so no two views tie exactly in normal angle, which
% dataProjection02's view choice at line 156 cannot resolve), four
% w x w pinhole cameras with focal length f at 300 mm on the +/-x and
% +/-y axes, the 4-view canvas of per-view ramps 100*k + 0.2*col +
% 0.1*row, the ROI JSON and the expected face values.
half = 20;
d = 300;
h = w;
cx = w / 2; cy = h / 2;
centres = [0 d 0; -d 0 0; d 0 0; 0 -d 0];   % ROI rows 1-4
% ROI row k's camera image is named view<k> (the
% positional convention of the cut and the frame check); this fixture
% named row k's image after VIEW_ORDER{k} (row 1 'view2/...'), the old default
names = {'view1/view1_0001.tiff', 'view2/view2_0001.tiff', ...
    'view3/view3_0001.tiff', 'view4/view4_0001.tiff'};
[pts, faces] = box_mesh(half, n_side);
ax = [1 2 3] / norm([1 2 3]);
th = 0.5 * pi / 180;
K = [0 -ax(3) ax(2); ax(3) 0 -ax(1); -ax(2) ax(1) 0];
pts = pts * (eye(3) + sin(th) * K + (1 - cos(th)) * K * K)';
folder = fullfile(root, tag);
mkdir(folder);
sc.mesh_path = fullfile(folder, 'box.ply');
write_ply(sc.mesh_path, pts, faces);
R = cell(4, 1); t = cell(4, 1);
for k = 1:4
    R{k} = look_at_rotation(centres(k, :));
    t{k} = -R{k} * centres(k, :)';
end
sc.colmap_dir = fullfile(folder, 'model');
mkdir(sc.colmap_dir);
write_colmap_txt(sc.colmap_dir, f, w, h, cx, cy, R, t, names);
[cc, rr] = meshgrid(1:w, 1:h);
views = cell(4, 1);
for k = 1:4, views{k} = 100 * k + 0.2 * cc + 0.1 * rr; end
bounds = [1 1 h w; 1 w+1 h 2*w; 1 2*w+1 h 3*w; 1 3*w+1 h 4*w];
sc.canvas = assemble_canvas(views, bounds);
sc.json_path = fullfile(folder, 'roi.json');
rabbit_stack_io.save_roi_json(sc.json_path, struct('schema_version', 1, ...
    'region_bounds_src', bounds, 'regions', 4, 'rotation', 0, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', h, 'width', 4 * w), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, ...
    'view_order', {{'view2', 'view3', 'view1', 'view4'}}));
% Expected value of every side face: the ramp of the view facing it, at
% the pinhole projection of the face centre.
centroid = (pts(faces(:, 1), :) + pts(faces(:, 2), :) + pts(faces(:, 3), :)) / 3;
normal = cross(pts(faces(:, 2), :) - pts(faces(:, 1), :), ...
    pts(faces(:, 3), :) - pts(faces(:, 1), :), 2);
normal = normal ./ sqrt(sum(normal .^ 2, 2));
expected_view = zeros(size(faces, 1), 1);
expected = NaN(size(faces, 1), 1);
for k = 1:4
    facing = normal * (centres(k, :)' / d) > 0.99;
    pc = (R{k} * centroid(facing, :)' + t{k})';
    X = f * pc(:, 1) ./ pc(:, 3) + cx;
    Y = f * pc(:, 2) ./ pc(:, 3) + cy;
    expected_view(facing) = k;
    % X, Y are COLMAP pixel coordinates (0-based, pixel k centred at
    % k + 0.5); the ramp is written on 1-based column/row indices, whose
    % pixel j is centred at COLMAP j - 0.5
    expected(facing) = 100 * k + 0.2 * (X + 0.5) + 0.1 * (Y + 0.5);
end
% Inner faces: at least two rows of faces away from a box edge (the cone
% edge weight is intentionally soft at the silhouette).
in_plane = abs(centroid) .* (1 - abs(round(normal)));
sc.inner = expected_view > 0 & max(in_plane, [], 2) < half - 2 * (2 * half / n_side);
sc.views = views;
sc.names = names;
sc.pts = pts;
sc.faces = faces;
sc.normal = normal;
sc.expected_view = expected_view;
sc.expected = expected;
end

function ok = vendored_ok(src_root, vendored)
ok = true;
for k = 1:size(vendored, 1)
    parts = strsplit(vendored{k, 1}, '/');
    ok = ok && strcmp(sha256_file(fullfile(src_root, parts{:})), vendored{k, 2});
end
end

function [pts, faces] = box_mesh(half, n)
% Closed axis-aligned box, n x n squares per side, outward winding.
g = linspace(-half, half, n + 1);
pts = zeros(0, 3);
faces = zeros(0, 3);
axes_ = {[1 0 0], [0 1 0], [0 0 1]};
for a = 1:3
    for sgn = [-1 1]
        nrm = sgn * axes_{a};
        u = axes_{mod(a, 3) + 1};
        v = cross(nrm, u);
        [U, V] = meshgrid(g, g);
        P = half * nrm + U(:) * u + V(:) * v;
        base = size(pts, 1);
        pts = [pts; P]; %#ok<AGROW>
        idx = reshape(1:(n + 1)^2, n + 1, n + 1) + base;
        for i = 1:n
            for j = 1:n
                a1 = idx(i, j); b1 = idx(i, j + 1);
                c1 = idx(i + 1, j + 1); d1 = idx(i + 1, j);
                faces(end + 1, :) = [a1 b1 c1]; %#ok<AGROW>
                faces(end + 1, :) = [a1 c1 d1]; %#ok<AGROW>
            end
        end
    end
end
% Merge the shared edge vertices so the mesh is closed.
[pts, ~, map] = unique(round(pts * 1e6) / 1e6, 'rows', 'stable');
faces = map(faces);
end

function canvas = app_canvas(frame, bounds_src, rotation)
% regions_chosen + apply_regions in analyse_optical_mapping (4 regions,
% any rotation), on one frame in the app's orientation.
rb = sortrows([bounds_src, bounds_src(:, 3:4) - bounds_src(:, 1:2) + 1], 2);
if rotation == 3
    rb = rb([1 2 4 3], :);
elseif rotation == 1
    rb = rb([4 3 1 2], :);
end
if any(rotation == [0 2])
    rh = rb(:, 5); rw = rb(:, 6);
else
    rh = rb(:, 6); rw = rb(:, 5);
end
H = max(rh);
canvas = zeros(H, sum(rw));
start = 1;
for k = 1:4
    x = frame(rb(k, 1):rb(k, 3), rb(k, 2):rb(k, 4));
    if k == 1
        tile = rot90(x);
    elseif k == 2 || k == 4
        tile = fliplr(rot90(fliplr(flipud(x))));
    else
        tile = fliplr(rot90(fliplr(x)));
    end
    r0 = 1 + floor((H - rh(k)) / 2);
    canvas(r0:r0 + rh(k) - 1, start:start + rw(k) - 1) = tile;
    start = start + rw(k);
end
end

function canvas = assemble_canvas(views_src, bounds)
% apply_regions in analyse_optical_mapping, rotation 0.
hh = bounds(:, 3) - bounds(:, 1) + 1;
ww = bounds(:, 4) - bounds(:, 2) + 1;
H = max(hh);
canvas = zeros(H, sum(ww));
start = 1;
for k = 1:4
    crows = 1 + floor((H - hh(k)) / 2) : floor((H - hh(k)) / 2) + hh(k);
    ccols = start : start + ww(k) - 1;
    src = views_src{k};
    switch k
        case 1, tile = rot90(src);
        case 2, tile = fliplr(rot90(fliplr(flipud(src))));
        case 3, tile = fliplr(rot90(fliplr(src)));
        case 4, tile = fliplr(rot90(fliplr(flipud(src))));
    end
    canvas(crows, ccols) = tile;
    start = start + ww(k);
end
end

function R = look_at_rotation(c)
% World-to-camera rotation for a camera at c looking at the origin.
z = -c(:) / norm(c);
x = cross([0; 0; 1], z);
x = x / norm(x);
y = cross(z, x);
R = [x'; y'; z'];
end

function write_colmap_txt(folder, f, w, h, cx, cy, R, t, names)
fid = fopen(fullfile(folder, 'cameras.txt'), 'w');
fprintf(fid, '# Camera list\n1 SIMPLE_PINHOLE %d %d %.10g %.10g %.10g\n', w, h, f, cx, cy);
fclose(fid);
fid = fopen(fullfile(folder, 'images.txt'), 'w');
fprintf(fid, '# Image list\n');
for k = 1:numel(names)
    q = rotm_to_quat(R{k});
    fprintf(fid, '%d %.15g %.15g %.15g %.15g %.15g %.15g %.15g 1 %s\n\n', ...
        k, q, t{k}, names{k});
end
fclose(fid);
end

function q = rotm_to_quat(R)
tr = trace(R);
if tr > 0
    s = 2 * sqrt(tr + 1);
    q = [s / 4, (R(3, 2) - R(2, 3)) / s, (R(1, 3) - R(3, 1)) / s, (R(2, 1) - R(1, 2)) / s];
elseif R(1, 1) > R(2, 2) && R(1, 1) > R(3, 3)
    s = 2 * sqrt(1 + R(1, 1) - R(2, 2) - R(3, 3));
    q = [(R(3, 2) - R(2, 3)) / s, s / 4, (R(1, 2) + R(2, 1)) / s, (R(1, 3) + R(3, 1)) / s];
elseif R(2, 2) > R(3, 3)
    s = 2 * sqrt(1 + R(2, 2) - R(1, 1) - R(3, 3));
    q = [(R(1, 3) - R(3, 1)) / s, (R(1, 2) + R(2, 1)) / s, s / 4, (R(2, 3) + R(3, 2)) / s];
else
    s = 2 * sqrt(1 + R(3, 3) - R(1, 1) - R(2, 2));
    q = [(R(2, 1) - R(1, 2)) / s, (R(1, 3) + R(3, 1)) / s, (R(2, 3) + R(3, 2)) / s, s / 4];
end
q = q / norm(q);
end

function write_ply(path, pts, faces)
fid = fopen(path, 'w');
fprintf(fid, ['ply\nformat ascii 1.0\nelement vertex %d\nproperty float x\n' ...
    'property float y\nproperty float z\nelement face %d\n' ...
    'property list uchar int vertex_indices\nend_header\n'], size(pts, 1), size(faces, 1));
fprintf(fid, '%.9g %.9g %.9g\n', pts');
fprintf(fid, '3 %d %d %d\n', (faces - 1)');
fclose(fid);
end

function h = sha256_file(path)
fid = fopen(path, 'rb');
assert(fid >= 0, 'Cannot read %s.', path);
bytes = fread(fid, Inf, '*uint8');
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
digest = typecast(int8(md.digest(bytes)), 'uint8');
h = lower(reshape(dec2hex(digest, 2)', 1, []));
end
