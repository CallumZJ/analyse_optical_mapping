function probe_cv_arrows
%% Probe: CV direction on the mesh, its arrows in Visualise, and the recorded colour ranges
% Collin Snitchler
% 23.11.2026
% The user wanted the conduction velocity direction on the mesh as arrows
% in the Visualise window, and Visualise to start with the colour ranges
% the maps were shown with in the app. The lifting is checked on a
% synthetic camera, the rest headless through the app's Reproject run
% button on a copy of a completed run, with a CV field of one direction on
% the canvas (row 0.6, column 0.8).
%   U1  lifting: on a pinhole camera and a tilted plane, the image gradient
%       of a wave along a plane direction lifts back to that direction
%       (a gradient, pulled back with A'; it was the image of
%       the direction, a displacement)
%   U2  lifting with distortion, shift and unequal scales; an edge-on
%       plane gives no direction
%   U3  a left-right (up-down) flipped view negates the x (y) component
%       and mirrors the view's vectors
%   A1  the canvas-to-view axes of each view agree with om_camera_views
%       (its own implementation of the flips)
%   E0  the CV direction does not change the speed files: run() with and
%       without CvComponents writes the same cv_projected.cdf/.ply
%   E1  cv_direction.mat: unit directions tangent to the faces, for most
%       assigned faces; both manifests record it
%   E2  faces with one view: the direction follows that view's vector (the
%       canvas vector turned with the tile) pulled back as a gradient
%   V1  Visualise: 300-600 arrows, tangent to the faces, and the
%       "Show CV arrows" checkbox hides and shows them
%   V2  the low-confidence checkbox hides the arrows on class-4 faces only
%   D1  display_limits from the stage options are in both manifests
%   D2  Visualise starts with them: the range fields and the axes' CLim
%   D3  typing auto gives the 1st-99th percentile of the faces shown (CV)
%       and the automatic
%       activation range again
%   D4  a projection without display_limits (one made before they were
%       recorded) stays on auto
%   V4  arrows 0.4 to 1 x the spacing over the colour range, none outside
%       it
%   V3  a projection without cv_direction.mat: the checkbox is disabled and
%       says to redo the projection, and the caption says so
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_cv_arrows" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests'));
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
results = struct('id', {}, 'ok', {}, 'detail', {});

%% U1 pinhole camera, tilted plane
f_px = 2000; cx = 320; cy = 240; tz = 100;
cm = struct('id', 1, 'model', 'PINHOLE', 'width', 640, 'height', 480, 'params', [f_px f_px cx cy]);
[par, pos] = rabbit_rhythm_reproject.colmap_to_rhythm(cm, [1 0 0 0], [0 0 tz], 1);
n = [0 sind(50) -cosd(50)];
t1 = [1 0 0];
t2 = cross(n, t1); t2 = t2 / norm(t2);
ang = (0:30:330)';
T = cosd(ang) * t1 + sind(ang) * t2;          % expected directions in the plane
C = repmat(4 * t1 - 6 * t2, numel(ang), 1);   % the point they start from
X = C(:, 1); Y = C(:, 2); Z = C(:, 3) + tz;   % camera coordinates (R = I)
% the image CV vector is the image gradient of the activation
% time of a wave running along T on the plane. With the pinhole Jacobian J
% (d/dp of (f X / Z + cx, f Y / Z + cy)) and A = J * [t1 t2], A' * g gives T's
% plane coordinates, so g = (A') \ [T.t1; T.t2]. (The check used the image of
% T, J * T, a displacement, before.)
Jp = @(i) [f_px ./ Z(i), 0, -f_px * X(i) ./ Z(i) .^ 2; 0, f_px ./ Z(i), -f_px * Y(i) ./ Z(i) .^ 2];
v = zeros(numel(ang), 2);
for i = 1:numel(ang)
    J = Jp(i);
    v(i, :) = ((J * [t1' t2'])' \ [T(i, :) * t1'; T(i, :) * t2'])';
end
[Jx, Jy] = rabbit_rhythm_reproject.projection_jacobian(C, par, pos, [0 0], [1 1], 1e-4);
d = rabbit_rhythm_reproject.lift_direction(Jx, Jy, repmat(n, numel(ang), 1), v);
err1 = max(acosd(min(1, sum(d .* T, 2))));
tan1 = max(abs(d * n'));
results = add(results, 'U1 pinhole, plane tilted 50 deg: lifted = true direction', ...
    err1 < 0.01 && tan1 < 1e-9, sprintf('max angle %.2g deg, max |d.n| %.1g', err1, tan1));

%% U2 distortion, shift and unequal scales; edge-on plane
cm2 = struct('id', 1, 'model', 'OPENCV', 'width', 640, 'height', 480, ...
    'params', [f_px f_px cx cy -0.2 0.05 1e-3 -1e-3]);
[par2, pos2] = rabbit_rhythm_reproject.colmap_to_rhythm(cm2, [0.98 0.1 -0.15 0.05] / norm([0.98 0.1 -0.15 0.05]), ...
    [2 -3 tz], 1);
sh = [5 -7]; sc = [1.3 0.8];
eps_ = 1e-6;
% The Jacobian of the projection itself by central differences (the lifting's
% own is computed apart), then the gradient as in U1
v2 = zeros(numel(ang), 2);
for i = 1:numel(ang)
    J = zeros(2, 3);
    for a = 1:3
        e3 = zeros(1, 3); e3(a) = eps_;
        [xp, yp] = rabbit_rhythm_reproject.rhythm_pred(C(i, :) + e3, par2, pos2, sh, sc);
        [xm, ym] = rabbit_rhythm_reproject.rhythm_pred(C(i, :) - e3, par2, pos2, sh, sc);
        J(:, a) = [xp - xm; yp - ym] / (2 * eps_);
    end
    v2(i, :) = ((J * [t1' t2'])' \ [T(i, :) * t1'; T(i, :) * t2'])';
end
[Jx, Jy] = rabbit_rhythm_reproject.projection_jacobian(C, par2, pos2, sh, sc, 1e-4);
d2 = rabbit_rhythm_reproject.lift_direction(Jx, Jy, repmat(n, numel(ang), 1), v2);
err2 = max(acosd(min(1, sum(d2 .* T, 2))));
% The plane x = 0 holds the ray from the camera (0, 0, -100) to the origin
[Jx, Jy] = rabbit_rhythm_reproject.projection_jacobian([0 0 0], par, pos, [0 0], [1 1], 1e-4);
d_edge = rabbit_rhythm_reproject.lift_direction(Jx, Jy, [1 0 0], [0 1]);
results = add(results, 'U2 distortion, shift, unequal scales: recovered; edge-on plane: none', ...
    err2 < 0.05 && all(isnan(d_edge)), sprintf('max angle %.2g deg, edge-on %s', err2, mat2str(d_edge, 3)));

%% The app on a copy of the run
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_cv_arrows', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), report(results); return; end   % SKIP printed; the checks so far are reported
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
out_dir = fullfile(run_dir, 'outputs', 'reprojection');
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
map = 20 + 30 * rand(size(om_image));
frames = repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, []);
rng(11, 'twister');
speed = 0.2 + 0.8 * rand(size(map));
speed(rand(size(map)) < 0.1) = NaN;
v0 = [0.6; 0.8];                               % canvas [row; column] direction
cv = cat(3, speed * v0(1), speed * v0(2), speed);
tab = tab_display_limits_double();
[ok, err] = tab.load_state(root, stem);
assert(ok, err);
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root, stem);
recording = rabbit_reconstruction_tab.recording_stem(root, stem);
app.file_info.path = root;
app.file_info.name = [recording '.fits'];
app.file_info.type = '.fits';
app.processed_data.activation_map = map;
app.processed_data.image_stack = {frames};
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.processed_data.CV_map = cv;
app.CV_method.Value = app.CV_method.Items{1};
app.recon.ReconstructionEdgeWeightField.Value = 0.30;
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
limits = struct('activation', [5 45], 'cv', [0.3 0.9]);
tab.display_limits = limits;
redo(app);
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
cvm = jsondecode(fileread(fullfile(out_dir, 'cv_reprojection_manifest.json')));
am = jsondecode(fileread(fullfile(out_dir, 'reprojection_manifest.json')));
w = load(fullfile(out_dir, 'cv_direction.mat'));
cls = read_class(fullfile(out_dir, 'cv_confidence.mat'));

%% U3 flips of a view turn its vectors
roi = m.reprojection_source.roi_json;
payload = rabbit_stack_io.load_roi_json(roi, [], []);
bounds = payload.region_bounds_src;
rot = payload.rotation;
cv_rc = cv(:, :, 1:2);
c0 = rabbit_rhythm_reproject.cv_view_components(cv_rc, bounds, rot, false, {'none', 'none', 'none', 'none'});
c1 = rabbit_rhythm_reproject.cv_view_components(cv_rc, bounds, rot, false, {'lr', 'none', 'none', 'ud'});
u3 = isequaln(c1{1}(:, :, 1), -fliplr(c0{1}(:, :, 1))) && isequaln(c1{1}(:, :, 2), fliplr(c0{1}(:, :, 2))) && ...
    isequaln(c1{4}(:, :, 2), -flipud(c0{4}(:, :, 2))) && isequaln(c1{4}(:, :, 1), flipud(c0{4}(:, :, 1))) && ...
    isequaln(c1{2}, c0{2});
results = add(results, 'U3 left-right flip negates x, up-down flip negates y', u3, '');

%% A1 canvas-to-view axes against om_camera_views
M = cvm.cv_direction.canvas_from_view;
[hh, ww] = size(map);
[Cc, Rc] = meshgrid(1:ww, 1:hh);
split = rabbit_rhythm_reproject.split_canvas(Rc, bounds, rot);
cam_hw = cell2mat(cellfun(@size, split(:), 'UniformOutput', false));
flip_rows = logical(cvm.flip_rows(:)');
view_flips = cellstr(cvm.view_flips);
rv = rabbit_rhythm_reproject.om_camera_views(Rc, bounds, rot, flip_rows, view_flips, zeros(4, 2), cam_hw);
cvv = rabbit_rhythm_reproject.om_camera_views(Cc, bounds, rot, flip_rows, view_flips, zeros(4, 2), cam_hw);
a1 = true;
parts = cell(1, 4);
for k = 1:4
    % Over 8 pixels, as a binned canvas repeats each value over a block
    y = round(cam_hw(k, 1) / 2); x = round(cam_hw(k, 2) / 2); s8 = 8;
    Mk = sign([rv{k}(y, x + s8) - rv{k}(y, x), rv{k}(y + s8, x) - rv{k}(y, x); ...
        cvv{k}(y, x + s8) - cvv{k}(y, x), cvv{k}(y + s8, x) - cvv{k}(y, x)]);
    a1 = a1 && isequal(Mk, M(:, :, k));
    parts{k} = sprintf('%s %s', mat2str(Mk), mat2str(M(:, :, k)));
end
results = add(results, 'A1 canvas-to-view axes match om_camera_views', a1, strjoin(parts, ' | '));

%% E0 the speed files do not depend on the direction
shifts = zeros(4, 2);
if isfield(cvm, 'shifts') && ~isempty(cvm.shifts), shifts = reshape(cvm.shifts, 4, 2); end
pre = shifts;                                  % the shifts before run() turns them for flips
pre(contains(view_flips, 'lr'), 1) = -pre(contains(view_flips, 'lr'), 1);
pre(contains(view_flips, 'ud'), 2) = -pre(contains(view_flips, 'ud'), 2);
args = {'Quantity', 'cv_speed', 'ColmapDir', cvm.colmap_dir, 'MeshFile', cvm.mesh_file, ...
    'ViewCameras', cellstr(cvm.view_cameras), 'FlipRows', flip_rows, 'ViewFlips', view_flips, ...
    'Shifts', pre, 'MinEdgeEdge', 0.30};
if isfield(cvm, 'fov_mapping') && ~isempty(cvm.fov_mapping), args = [args, {'FovMapping', cvm.fov_mapping}]; end
o1 = fullfile(root, 'e0_speed'); o2 = fullfile(root, 'e0_direction');
rabbit_rhythm_reproject.run(speed, roi, args{:}, 'OutDir', o1);
rabbit_rhythm_reproject.run(speed, roi, args{:}, 'OutDir', o2, 'CvComponents', cv_rc);
same_cdf = isequal(cdf_without_date(fullfile(o1, 'cv_projected.cdf')), cdf_without_date(fullfile(o2, 'cv_projected.cdf')));
same_ply = strcmp(file_hash(fullfile(o1, 'cv_projected.ply')), file_hash(fullfile(o2, 'cv_projected.ply')));
same_cls = isequal(read_class(fullfile(o1, 'cv_confidence.mat')), read_class(fullfile(o2, 'cv_confidence.mat')));
as_tab = isequal(cdf_without_date(fullfile(o2, 'cv_projected.cdf')), cdf_without_date(fullfile(out_dir, 'cv_projected.cdf')));
results = add(results, 'E0 with and without the direction: same cv_projected.cdf/.ply and classes', ...
    same_cdf && same_ply && same_cls && ~isfile(fullfile(o1, 'cv_direction.mat')) && isfile(fullfile(o2, 'cv_direction.mat')), ...
    sprintf('cdf %d ply %d classes %d (same as the tab''s projection: %d)', same_cdf, same_ply, same_cls, as_tab));

%% E1 tangent unit directions for most assigned faces
mesh = rabbit_rhythm_reproject.read_ply_mesh(cvm.mesh_file);
[cells, cen, nrm] = rabbit_rhythm_reproject.build_mesh_topology(mesh.pts, mesh.faces);
D = double(w.direction);
has = all(isfinite(D), 2);
unit = max(abs(vecnorm(D(has, :), 2, 2) - 1));
tang = max(abs(sum(D(has, :) .* nrm(has, :), 2)));
n_ass = nnz(isfinite(w.speed));
rec = m.result.reprojection.cv.direction;
e1 = nnz(has) > 0.9 * n_ass && unit < 1e-9 && tang < 1e-6 && all(isfinite(w.speed(has))) && ...
    startsWith(rec.status, 'projected') && strcmp(cvm.cv_direction.file, 'cv_direction.mat') && ...
    numel(cvm.cv_direction.approximations) >= 3 && contains(cvm.note, 'surface');
results = add(results, 'E1 unit directions tangent to the faces, recorded in both manifests', e1, ...
    sprintf('%d of %d assigned faces, max |len-1| %.1g, max |d.n| %.1g | %s', nnz(has), n_ass, unit, tang, rec.status));

%% E2 single-view faces image onto the view's vector
cam = rabbit_rhythm_reproject.read_colmap_cameras(cvm.colmap_dir);
imgs = rabbit_rhythm_reproject.read_colmap_images(cvm.colmap_dir);
vcam = rabbit_rhythm_reproject.resolve_view_cameras(imgs, cellstr(cvm.view_cameras));
vw = double(w.view_weights);
worst = 0;
n_chk = 0;
e = vecnorm(mesh.pts(cells(:, 1), :) - mesh.pts(cells(:, 2), :), 2, 2);
for k = 1:4
    f = find(has & vw(:, k) > 0.999);
    if isempty(f), continue; end
    [p_k, q_k] = rabbit_rhythm_reproject.colmap_to_rhythm(rabbit_rhythm_reproject.find_camera(cam, vcam{k}), ...
        vcam{k}.qvec, vcam{k}.tvec, 1);
    [Jx, Jy] = rabbit_rhythm_reproject.projection_jacobian(cen(f, :), p_k, q_k, shifts(k, :), [1 1], ...
        1e-3 * median(e));
    % the view's vector is an image gradient; on the face it
    % pulls back to the in-plane part of vx * Jx + vy * Jy, which the
    % lifted direction must follow
    want = (M(:, :, k)' * v0)';
    w3 = want(1) * Jx + want(2) * Jy;
    w3 = w3 - sum(w3 .* nrm(f, :), 2) .* nrm(f, :);
    c = sum(w3 .* D(f, :), 2) ./ vecnorm(w3, 2, 2);
    worst = max(worst, max(acosd(min(1, c))));
    n_chk = n_chk + numel(f);
end
results = add(results, 'E2 single-view faces image onto their view''s CV vector', n_chk > 100 && worst < 1, ...
    sprintf('%d faces, worst angle %.3g deg', n_chk, worst));

%% D1 display limits in the manifests
d1 = isfield(am, 'display_limits') && isequal(am.display_limits.activation(:)', limits.activation) && ...
    isequal(am.display_limits.cv(:)', limits.cv) && isfield(cvm, 'display_limits') && ...
    isequal(cvm.display_limits.cv(:)', limits.cv);
results = add(results, 'D1 display_limits recorded in both manifests', d1, jsonencode(am.display_limits));

%% V1, V2, D2, D3 in Visualise
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
st = getappdata(fig, 'reconstruction_cv_arrows');
q = findobj(fig, 'Tag', 'ReconstructionCvArrows');
ql = findobj(fig, 'Tag', 'ReconstructionCvArrowsLow');
cba = findobj(fig, 'Tag', 'ReconstructionCvArrowsShow');
n_arrows = numel(q.XData) + numel(ql.XData);
U = [[q.UData(:); ql.UData(:)], [q.VData(:); ql.VData(:)], [q.WData(:); ql.WData(:)]];
shown = [st.faces_shown(~st.low_shown); st.faces_shown(st.low_shown)];
% Against the projection's face normals (double), and the viewer's own
% (from the PLY's single-precision vertices, so only to about 1e-4)
tang_v = max(abs(sum(U ./ vecnorm(U, 2, 2) .* nrm(shown, :), 2)));
tang_ply = max(abs(sum(U ./ vecnorm(U, 2, 2) .* st.N(shown, :), 2)));
cba.Value = 0; cba.Callback(cba, []);
off = strcmp(q.Visible, 'off') && strcmp(ql.Visible, 'off');
cba.Value = 1; cba.Callback(cba, []);
% At 0.30 the low-confidence fills start hidden, and their arrows with them
cb0 = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
on = strcmp(q.Visible, 'on') && strcmp(ql.Visible, 'off') && isscalar(cb0) && cb0.Value == 0;
results = add(results, 'V1 300-600 arrows tangent to the faces; the checkbox hides and shows them', ...
    n_arrows >= 300 && n_arrows <= 600 && tang_v < 1e-6 && tang_ply < 1e-3 && strcmp(cba.Enable, 'on') && off && on, ...
    sprintf('%d arrows, max |u.n| %.1g (viewer mesh %.1g), off %d on %d', n_arrows, tang_v, tang_ply, off, on));
% V2 at the highest density, so that some arrows sit on class-4 faces
dens = findobj(fig, 'Tag', 'ReconstructionCvArrowDensity');
dens.Value = 3; dens.Callback(dens, []);
st = getappdata(fig, 'reconstruction_cv_arrows');
q = findobj(fig, 'Tag', 'ReconstructionCvArrows');
ql = findobj(fig, 'Tag', 'ReconstructionCvArrowsLow');
cb = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
cb.Value = 0; cb.Callback(cb, []);
hid = strcmp(ql.Visible, 'off') && strcmp(q.Visible, 'on');
clean = ~any(cls(st.faces_shown(~st.low_shown)) == 4) && all(cls(st.faces_shown(st.low_shown)) == 4);
cb.Value = 1; cb.Callback(cb, []);
back = strcmp(ql.Visible, 'on');
results = add(results, 'V2 low-confidence unticked: the class-4 arrows hidden, the others kept', ...
    nnz(st.low_shown) > 0 && hid && clean && back, sprintf('%d of %d arrows on class-4 faces; hidden %d, others clean %d, back %d', ...
    nnz(st.low_shown), numel(st.faces_shown), hid, clean, back));
% D2 the recorded ranges are the defaults
fa = findobj(fig, 'Tag', 'ReconstructionActivationLimits');
fc = findobj(fig, 'Tag', 'ReconstructionCvLimits');
ax_a = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
ax_c = findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv');
d2 = strcmp(fa.String, '5 45') && strcmp(fc.String, '0.3 0.9') && isequal(ax_a.CLim, limits.activation) && ...
    max(abs(ax_c.CLim - limits.cv)) < 1e-12;
results = add(results, 'D2 Visualise starts with the recorded ranges', d2, ...
    sprintf('fields "%s" "%s", CLim %s %s', fa.String, fc.String, mat2str(ax_a.CLim), mat2str(ax_c.CLim)));
% D3 auto again
dc = getappdata(fig, 'reconstruction_cv');
da = getappdata(fig, 'reconstruction_activation');
% over the faces shown (the low-confidence fills are
% shown again here), by their face values, not the vertices
fdd = getappdata(fig, 'reconstruction_face_data');
s = fdd.cv.values(fdd.cv.assigned & isfinite(fdd.cv.values) & fdd.cv.values > 0);
want_cv = prctile(s, [1 99]);
fc.String = 'auto'; fc.Callback(fc, []);
fa.String = 'auto'; fa.Callback(fa, []);
st = getappdata(fig, 'reconstruction_cv_arrows');
d3 = max(abs(ax_c.CLim - want_cv)) < 1e-12 && isequal(ax_a.CLim, da.auto) && max(abs(st.lim - want_cv)) < 1e-12;
results = add(results, 'D3 auto gives the 1st-99th percentile of the faces shown (CV) and the automatic activation range', d3, ...
    sprintf('CV %s (want %s), activation %s (auto %s)', mat2str(ax_c.CLim, 4), mat2str(want_cv, 4), ...
    mat2str(ax_a.CLim, 4), mat2str(da.auto, 4)));
% V4: every arrow is 0.4 to 1 x the spacing, its
% length rising with the speed over the colour range, and none is on a face
% outside that range; the caption names the length rule
q = findobj(fig, 'Tag', 'ReconstructionCvArrows');
ql = findobj(fig, 'Tag', 'ReconstructionCvArrowsLow');
L = vecnorm([[q.UData(:); ql.UData(:)], [q.VData(:); ql.VData(:)], [q.WData(:); ql.WData(:)]], 2, 2);
idx = [st.faces_shown(~st.low_shown); st.faces_shown(st.low_shown)];
sp = st.S(idx);
want_len = st.spacing * min(max(0.4 + 0.6 * (sp - st.lim(1)) / (st.lim(2) - st.lim(1)), 0.4), 1);
in_range = all(sp >= st.lim(1) & sp <= st.lim(2));
n_cand_out = nnz(st.S(st.cand) < st.lim(1) | st.S(st.cand) > st.lim(2));
cap = strjoin(cellstr(getappdata(fig, 'reconstruction_subtitle_lines').cv), ' ');
tipc = get(findobj(fig, 'Tag', 'ReconstructionPanelInfo_cv'), 'TooltipString');
v4 = ~isempty(L) && max(abs(L - want_len)) < 1e-6 * st.spacing && min(L) >= 0.4 * st.spacing * (1 - 1e-9) && ...
    max(L) <= st.spacing * (1 + 1e-9) && in_range && ...
    (contains(cap, ['length 0.4' char(8211) '1 ' char(215) ' spacing']) || ...   % "Arrows: ...; length 0.4-1 x spacing; ..."
    contains(tipc, ['length 0.4' char(8211) '1 ' char(215) ' spacing']));
results = add(results, 'V4 arrows 0.4-1 x spacing over the colour range, none outside it', v4, ...
    sprintf('%d arrows, length %.2f-%.2f x spacing, all in range %d (%d candidate faces outside)', numel(L), ...
    min(L) / st.spacing, max(L) / st.spacing, in_range, n_cand_out));
close(fig, 'force');

%% D4 and V3: a projection without display limits; then without cv_direction.mat
% The app's callbacks now pass the app's own limits, so a projection made
% before display_limits existed is imitated: the field is taken out of
% both manifests after the projection
tab.display_limits = [];
redo(app);
for mf = {'reprojection_manifest.json', 'cv_reprojection_manifest.json'}
    mp = fullfile(out_dir, mf{1});
    mm = jsondecode(fileread(mp));
    if isfield(mm, 'display_limits'), mm = rmfield(mm, 'display_limits'); end
    fid = fopen(mp, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(mm));
    fclose(fid);
end
am = jsondecode(fileread(fullfile(out_dir, 'reprojection_manifest.json')));
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
fa = findobj(fig, 'Tag', 'ReconstructionActivationLimits');
fc = findobj(fig, 'Tag', 'ReconstructionCvLimits');
dc = getappdata(fig, 'reconstruction_cv');
da = getappdata(fig, 'reconstruction_activation');
ax_a = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
ax_c = findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv');
d4 = ~isfield(am, 'display_limits') && strcmp(fa.String, 'auto') && strcmp(fc.String, 'auto') && ...
    isequal(ax_a.CLim, da.auto) && max(abs(ax_c.CLim - dc.auto)) < 1e-12;
results = add(results, 'D4 without display_limits: auto', d4, sprintf('fields "%s" "%s"', fa.String, fc.String));
close(fig, 'force');
delete(fullfile(out_dir, 'cv_direction.mat'));
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
cba = findobj(fig, 'Tag', 'ReconstructionCvArrowsShow');
ax_c = findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv');
% The caption and the (i) tooltip (where this goes when line 2 is full)
sub = [strjoin(cellstr(ax_c.Subtitle.String), ' ') get(findobj(fig, 'Tag', 'ReconstructionPanelInfo_cv'), 'TooltipString')];
v3 = isscalar(cba) && strcmp(cba.Enable, 'off') && cba.Value == 0 && contains(cba.TooltipString, 'Redo projection...') && ...   % the button's name
    isempty(findobj(fig, 'Tag', 'ReconstructionCvArrows')) && contains(sub, 'Direction not projected');
results = add(results, 'V3 without cv_direction.mat: checkbox disabled, says to redo the projection', v3, ...
    sprintf('%s | %s', cb_field(cba, 'Enable'), cb_field(cba, 'TooltipString')));
close(fig, 'force');

%% Summary
report(results);
end


function report(results)
% Every check's line and the counts; an error when one failed
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_CV_ARROWS RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_cv_arrows:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function redo(app)
% Reproject run on the selected COMPLETED run: Redo projection, map and video
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();
end


function c = read_class(p)
c = [];
if isfile(p)
    w = load(p, 'face_class');
    c = double(w.face_class(:));
end
end


function s = cb_field(cb, name)
s = '';
if isscalar(cb), s = char(cb.(name)); end
end


function b = cdf_without_date(p)
% The bytes of a .cdf without its date= header line (the day it was written)
b = [];
if ~isfile(p), return; end
fid = fopen(p, 'rb');
b = fread(fid, Inf, '*uint8')';
fclose(fid);
k = strfind(char(b), 'date=');
if ~isempty(k)
    e = k(1) + find(b(k(1):end) == 10, 1) - 1;
    b(k(1):e) = [];
end
end


function x = file_hash(p)
x = '';
if ~isfile(p), return; end
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(p, 'rb');
bytes = fread(fid, Inf, '*uint8');
fclose(fid);
x = sprintf('%02x', typecast(md.digest(bytes), 'uint8'));
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
