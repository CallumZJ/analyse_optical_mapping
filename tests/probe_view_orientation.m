function probe_view_orientation
%% Probe: the Visualise window shows the heart atria up
% Collin Snitchler
% 23.11.2026
% Every 3D panel of the Visualise window is shown with the atria up: the up
% vector comes from the cameras (the app's OM panorama up in each view,
% through the view's flips and the camera's rotation), checked against the
% long axis of the mesh. Display only; a camera saved with the atria-up
% view is still restored, one saved before it is not.
%   V1  synthetic rig, regions laid out as the real recording (rotation 3)
%       with a left-right, an up-down and a 180 degree flipped view: the up
%       vector is the rig's within 1 deg
%   V2  synthetic rig without regions (image up is up): an up-down flipped
%       view reverses its up, a left-right flipped one does not; within 1 deg
%   V3  long-axis check: no warning when the model's wider end points along
%       up, a warning when its axis is 60 deg away or upside down
%   V4  the real run: every panel's CameraUpVector is the recorded up, found
%       from the cameras
%   V5  Reset view returns every panel to that view after a rotation
%   V6  a saved camera with the orientation tag is restored; one without it
%       (saved before the atria-up view) is ignored and atria up is shown
%       (saving and reopening a tagged camera: probe_visualise_captions)
%   V8  the real run: the wider end is on top, so no warning (the long
%       axis is only shown for clearly elongated models)
%   V7  no panel shows axes (their tick labels covered the
%       titles); each has one 10 mm scale bar at right angles to the line of
%       sight, labelled, and it follows the camera (again after V5's orbit)
% Needs OM_APP_HEADLESS=1 and, for V4-V6:
%   OM_REDO_DS    folder holding a copy of <stem>.matom with a COMPLETED run
%                 (the probe only reads it, without a copy of its own; without
%                 the variables V4-V6 are skipped)
%   OM_REDO_STEM  dataset stem (the .matom name without .matom)
%   OM_REDO_RUN   run id of the COMPLETED run
% Usage: matlab -batch "addpath('<repo>/tests'); probe_view_orientation" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
results = struct('id', {}, 'ok', {}, 'detail', {});
tab = rabbit_reconstruction_tab();
up0 = [0.3 -0.2 0.93];
up0 = up0 / norm(up0);

%% V1
% The real recording's regions: ROI rows 1-4, panorama rotation 3. Its
% panorama slots hold rows 3, 1, 4, 2; worked out by hand from the slot
% transforms in rabbit_rhythm_reproject.split_canvas, the panorama's up is
% +x in the region of row 3 and -x in the others
payload = struct('region_bounds_src', [1 624 368 972; 28 1125 400 1484; 1 1 400 413; 1 1652 374 1987], ...
    'rotation', 3);
flips = {'none', 'lrud', 'lr', 'ud'};
region_up = [-1 0; -1 0; 1 0; -1 0];
truth = region_up;
for k = 1:4
    if contains(flips{k}, 'lr'), truth(k, 1) = -truth(k, 1); end
    if contains(flips{k}, 'ud'), truth(k, 2) = -truth(k, 2); end
end
img_up = tab.view_image_up(payload, flips);
[imgs, rows] = synthetic_rig(up0, truth, 0.3);
[up, info] = tab.camera_up_vector(imgs, rows, img_up);
err1 = angle_deg(up, up0);
results = add(results, 'V1 synthetic rig with the panorama layout and flipped views: up within 1 deg', ...
    ~isempty(up) && err1 < 1 && max(abs(img_up(:) - truth(:))) < 1e-6, ...
    sprintf('error %.3f deg, image up %s, views %s', err1, mat2str(round(img_up, 3)), mat2str(info.rows)));

%% V2
flips2 = {'none', 'lr', 'ud', 'none'};
truth2 = [0 -1; 0 -1; 0 1; 0 -1];
img_up2 = tab.view_image_up([], flips2);
[imgs2, rows2] = synthetic_rig(up0, truth2, 0.3);
[up2, info2] = tab.camera_up_vector(imgs2, rows2, img_up2);
err2 = angle_deg(up2, up0);
% Ignoring the flip of the up-down flipped view would turn its up over
[~, info2_wrong] = tab.camera_up_vector(imgs2, rows2, repmat([0 -1], 4, 1));
results = add(results, 'V2 synthetic rig, image up: ud reverses, lr does not; up within 1 deg', ...
    ~isempty(up2) && err2 < 1 && isequal(img_up2, truth2) && max(info2.angles_deg) < 1 && ...
    info2_wrong.angles_deg(3) > 170, ...
    sprintf('error %.3f deg, views within %.2f deg; without the flip view 3 is %.1f deg off', ...
    err2, max(info2.angles_deg), info2_wrong.angles_deg(3)));

%% V3
pts_along = pear_cloud(up0);
[ax_along, ax_info] = tab.mesh_long_axis(pts_along);
[w_along, a_along] = tab.orientation_check(up0, ax_along);
tilt = rotate_about(up0, cross(up0, [1 0 0]), 60);
[ax_tilt] = tab.mesh_long_axis(pear_cloud(tilt));
[w_tilt, a_tilt] = tab.orientation_check(up0, ax_tilt);
[ax_flip] = tab.mesh_long_axis(pear_cloud(-up0));
[w_flip, a_flip] = tab.orientation_check(up0, ax_flip);
[w_small, a_small] = tab.orientation_check(up0, rotate_about(up0, cross(up0, [1 0 0]), 20));
results = add(results, 'V3 long-axis check: warns above 30 deg (tilted 60, upside down), not otherwise', ...
    ~w_along && a_along < 5 && w_tilt && abs(a_tilt - 60) < 5 && w_flip && a_flip > 170 && ...
    ~w_small && abs(a_small - 20) < 1e-6 && ax_info.width_base > ax_info.width_apex, ...
    sprintf('along %.1f (warn %d), tilted %.1f (warn %d), upside down %.1f (warn %d), 20 deg %.1f (warn %d)', ...
    a_along, w_along, a_tilt, w_tilt, a_flip, w_flip, a_small, w_small));

%% V4-V6 on the real run (the shared copy, only read)
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
% Only read: the shared copy itself, no copy of its own
[root, cleanup] = om_redo_copy('probe_view_orientation', 'OM_REDO_DS', stem, run_id, 'read'); %#ok<ASGLU>
if isempty(root), report(results); return; end   % SKIP printed; the checks so far are reported
rt = rabbit_reconstruction_tab();
[ok, err] = rt.load_state(root, stem);
assert(ok, err);

[v_ok, v_err, fig] = rt.visualise_artifacts(run_id);
assert(v_ok, v_err);
o = getappdata(fig, 'reconstruction_view_orientation');
all_axes = getappdata(fig, 'reconstruction_all_axes');
ups = cell2mat(arrayfun(@(a) get(a, 'CameraUpVector'), all_axes(:), 'UniformOutput', false));
dev = max(vecnorm(ups - o.up, 2, 2));
fprintf('Real run: up [%.4f %.4f %.4f] from %s (%d views), view %s\n', o.up, o.source, o.n_views, o.view_source);
fprintf('Real run: long axis of the %s %.1f deg from up (elongation %.2f), wider end on top %d\n', ...
    o.pca_source, o.pca_angle_deg, o.pca_elongation, o.wider_end_up);
fprintf('Real run: warning "%s"\n', o.warning);
results = add(results, 'V4 real run: every panel''s CameraUpVector is the camera up', ...
    strcmp(o.source, 'cameras') && o.n_views == 4 && numel(all_axes) == 7 && dev < 1e-9 && ...
    isequal(getappdata(fig, 'reconstruction_view_up'), o.up), ...
    sprintf('max deviation %.2g, %d panels, per-view angles %s', dev, numel(all_axes), ...
    mat2str(round([o.per_view.angle_to_up_deg], 2))));
note = findall(fig, 'Tag', 'ReconstructionOrientationNote');
results = add(results, 'V8 real run: the wider end is on top, so no warning and no orange note', ...
    o.wider_end_up && isempty(o.warning) && isscalar(note) && isequal(note.Color, [0.4 0.4 0.4]), ...
    sprintf('wider end up %d, warning "%s"', o.wider_end_up, o.warning));

%% V7 (on the V4 figure)
% no panel shows axes (their tick labels ran into the
% titles); each has one scale bar of 10 mm at right angles to the line of
% sight, labelled, which follows the camera (checked again after V5's orbit)
[decor_ok, decor] = scale_bars_ok(all_axes);
results = add(results, 'V7 no axes shown; one scale bar (10 mm, or a 1-2-5 length on a small box) per panel across the line of sight', decor_ok, decor);

%% V5
home_pos = get(all_axes(1), 'CameraPosition');
camorbit(all_axes(4), 50, 35);
drawnow;
% The scale bars follow the camera (the listener on the first panel's camera)
[orbit_ok, orbit_txt] = scale_bars_ok(all_axes);
results = add(results, 'V7b after a rotation the scale bars are across the new line of sight', orbit_ok, orbit_txt);
moved = norm(get(all_axes(1), 'CameraPosition') - home_pos) > 1e-6 && ...
    norm(get(all_axes(1), 'CameraUpVector') - o.up) > 1e-3;
reset_btn = findobj(fig, 'Tag', 'ReconstructionViewerReset');
cb = get(reset_btn, 'Callback');
cb(reset_btn, []);
drawnow;
ups = cell2mat(arrayfun(@(a) get(a, 'CameraUpVector'), all_axes(:), 'UniformOutput', false));
pos = cell2mat(arrayfun(@(a) get(a, 'CameraPosition'), all_axes(:), 'UniformOutput', false));
results = add(results, 'V5 Reset view returns every panel to the atria-up view', ...
    moved && max(vecnorm(ups - o.up, 2, 2)) < 1e-9 && max(vecnorm(pos - home_pos, 2, 2)) < 1e-6 * norm(home_pos), ...
    sprintf('moved %d, up deviation %.2g, position deviation %.2g', moved, ...
    max(vecnorm(ups - o.up, 2, 2)), max(vecnorm(pos - home_pos, 2, 2))));
lim = struct('x', xlim(all_axes(2)), 'y', ylim(all_axes(2)), 'z', zlim(all_axes(2)));
delete(fig);

%% V6
target = mean([lim.x; lim.y; lim.z], 2)';
saved_up = [0 0 1];
if abs(dot(saved_up, o.up)) > 0.9, saved_up = [0 1 0]; end
raw = struct('position', target + [40 30 20], 'target', target, 'up', saved_up, 'view_angle', 9, ...
    'limits', struct('fused', lim, 'rebuilt', lim, 'projected', lim));
[c_ok, c_err, tagged] = rt.validate_camera_state(raw);
assert(c_ok, c_err);
untagged = rmfield(tagged, 'orientation');
[ctx_ok, ctx_err, vis] = rt.resolve_visualisation_context(run_id);
assert(ctx_ok, ctx_err);
vis.camera_state = tagged;
[s1_ok, s1_err, fig1] = rt.visualise_artifacts(vis);
assert(s1_ok, s1_err);
st1 = getappdata(fig1, 'reconstruction_camera_restore_status');
ax1 = getappdata(fig1, 'reconstruction_all_axes');
restored = strcmp(st1, 'AVAILABLE') && norm(get(ax1(1), 'CameraPosition') - raw.position) < 1e-9 && ...
    norm(get(ax1(7), 'CameraUpVector') - saved_up) < 1e-9;
delete(fig1);
vis.camera_state = untagged;
[s2_ok, s2_err, fig2] = rt.visualise_artifacts(vis);
assert(s2_ok, s2_err);
st2 = getappdata(fig2, 'reconstruction_camera_restore_status');
ax2 = getappdata(fig2, 'reconstruction_all_axes');
o2 = getappdata(fig2, 'reconstruction_view_orientation');
ups2 = cell2mat(arrayfun(@(a) get(a, 'CameraUpVector'), ax2(:), 'UniformOutput', false));
ignored = strcmp(st2, 'IGNORED: saved before atria-up orientation') && ...
    max(vecnorm(ups2 - o2.up, 2, 2)) < 1e-9 && norm(get(ax2(1), 'CameraPosition') - raw.position) > 1e-3;
delete(fig2);
results = add(results, 'V6 tagged saved camera restored; untagged one ignored (atria up wins)', ...
    restored && ignored && strcmp(tagged.orientation, rt.camera_orientation_tag()), ...
    sprintf('tagged: %s; untagged: %s; tag %s', st1, st2, tagged.orientation));

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
fprintf('\nPROBE_VIEW_ORIENTATION RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_view_orientation:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_view_orientation %d/0\n', n_pass);
end


function [imgs, rows] = synthetic_rig(up, img_dirs, jitter_deg)
% Four views 90 deg apart round the vertical axis up, each looking
% horizontally at the origin. In view k the image direction img_dirs(k, :)
% ([x y], x right, y down) shows world up; the camera is rolled to make it
% so. Three images per view, each turned by up to jitter_deg about a random
% axis. Returns COLMAP-style images (qvec of the world-to-camera rotation).
rng(3, 'twister');
h = null(up(:)')';
imgs = struct('qvec', {}, 'tvec', {}, 'name', {});
rows = [];
for k = 1:4
    az = (k - 1) * pi / 2 + 0.2;
    z = cos(az) * h(1, :) + sin(az) * h(2, :);
    e = img_dirs(k, :) / norm(img_dirs(k, :));
    e_perp = [-e(2), e(1)];
    w = cross(z, up);
    x = e(1) * up + e_perp(1) * w;
    y = e(2) * up + e_perp(2) * w;
    if det([x; y; z]) < 0
        w = -w;
        x = e(1) * up + e_perp(1) * w;
        y = e(2) * up + e_perp(2) * w;
    end
    R = [x; y; z];
    for j = 1:3
        a = randn(1, 3);
        J = axis_rotation(a / norm(a), jitter_deg * (2 * rand - 1));
        Rj = R * J;
        imgs(end+1) = struct('qvec', rot_to_quat(Rj), 'tvec', [0 0 5], ...
            'name', sprintf('syn_view%d_frame_%04d.tiff', k, j)); %#ok<AGROW>
        rows(end+1) = k; %#ok<AGROW>
    end
end
end


function pts = pear_cloud(a)
% Points on a pear-shaped surface 30 long along a, 14 wide at the +a end
% and 6 at the -a end
rng(5, 'twister');
a = a(:)' / norm(a);
b = null(a)';
n = 20000;
s = (rand(n, 1) * 2 - 1) * 15;
r = 3 + 4 * (s + 15) / 30;
t = rand(n, 1) * 2 * pi;
pts = s * a + r .* cos(t) * b(1, :) + r .* sin(t) * b(2, :) + [5 -2 7];
end


function v = rotate_about(v, ax, deg)
v = (axis_rotation(ax / norm(ax), deg) * v(:))';
end


function R = axis_rotation(a, deg)
c = cosd(deg); s = sind(deg);
K = [0 -a(3) a(2); a(3) 0 -a(1); -a(2) a(1) 0];
R = eye(3) * c + s * K + (1 - c) * (a(:) * a(:)');
end


function q = rot_to_quat(R)
% Rotation matrix to [qw qx qy qz] (COLMAP order), the inverse of the tab's
% qvec2rotmat
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
end


function d = angle_deg(u, v)
if isempty(u), d = Inf; return; end
d = acosd(min(1, max(-1, dot(u / norm(u), v / norm(v)))));
end


function [ok, txt] = scale_bars_ok(all_axes)
% V7: every panel without axes, with one bar (and its label) of 10 mm at right
% angles to its line of sight
ok = true;
parts = {};
n_bars = 0;
for k = 1:numel(all_axes)
    ax = all_axes(k);
    bar = findall(ax, 'Tag', 'ReconstructionScaleBar');
    lab = findall(ax, 'Tag', 'ReconstructionScaleBarText');
    d = get(ax, 'CameraTarget') - get(ax, 'CameraPosition');
    d = d / norm(d);
    len = NaN; across = NaN;
    if isscalar(bar)
        s = [diff(bar.XData), diff(bar.YData), diff(bar.ZData)];
        len = norm(s);
        across = abs(dot(s / len, d));
    end
    % The length the rule gives for this box: 10 mm when the box is at least
    % 20 mm wide on screen, else the largest 1-2-5 length up to a quarter of it
    % (this probe's run is small: 2 mm); computed here from the limits and camera
    u = get(ax, 'CameraUpVector'); u = u - dot(u, d) * d; u = u / norm(u);
    r = cross(d, u);
    [Xg, Yg, Zg] = ndgrid(xlim(ax), ylim(ax), zlim(ax));
    a_ = ([Xg(:), Yg(:), Zg(:)] - get(ax, 'CameraTarget')) * r(:);
    span = max(a_) - min(a_);
    if span >= 20
        L = 10;
    else
        q = span / 4; s125 = [1 2 5 10] * 10 ^ floor(log10(q)); L = s125(find(s125 <= q, 1, 'last'));
    end
    round_len = abs(len - L) < 1e-9;
    if isappdata(ax, 'reconstruction_no_scale_bar')
        % a panel with nothing drawn (its placeholder text only): no bar
        this = strcmp(char(ax.Visible), 'off') && isempty(bar) && isempty(lab);
    else
        this = strcmp(char(ax.Visible), 'off') && isscalar(bar) && isscalar(lab) && round_len && ...
            across < 1e-9 && strcmp(char(lab.String), sprintf('%g mm', len));
    end
    n_bars = n_bars + isscalar(bar);
    ok = ok && this;
    parts{end + 1} = sprintf('%s: axes %s, bar %.3g mm, cos to sight %.1g', get(ax, 'Tag'), char(ax.Visible), len, across); %#ok<AGROW>
end
ok = ok && n_bars >= 4;   % the run's sparse, cloud, mesh and activation panels
txt = strjoin(parts, ' | ');
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
