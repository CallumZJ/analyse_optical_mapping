function probe_cv_surface_speed
%% Probe: the tilt-corrected CV surface speed, stored and shown next to the image-plane speed
% Collin Snitchler
% 25.11.2026
% cv_speed_surface = 1/|A'g|,
% with the same Jacobian as the CV direction's lifting (F6), stored next to
% the image-plane speed; the captions and the Results CV row give both; the
% image-plane speed stays the colour. The synthetic check of the formula is
% probe_cv_direction_lift D5. Driven through the app's Redo projection,
% headless, on a copy of a completed run, with a CV map as probe_cv_range.
%   G1  cv_direction.mat holds speed_surface (faces x 1, m/s) next to speed;
%       it is finite only on assigned faces with a direction; the manifest's
%       cv_direction.surface_speed gives the pixel size and the medians of
%       the faces with both; cv_projected.cdf is the image-plane speed
%   G2  the factor surface / image plane is the run's heart pixel size
%       (pixel_size.json) / the 0.258 mm the probe gave (per unbinned
%       pixel), times a tilt part
%       of 1 or more (5th percentile above 0.9, median 1-1.3)
%   G3  the Results CV row: "...; image-plane speed (...); surface speed
%       (tilt-corrected) median X m/s (IQR a-b)" with X, a, b recounted
%       per vertex from speed_surface (as the image-plane median)
%   G4  the Visualise CV caption: "surface speed (tilt-corrected): median X
%       m/s (IQR a-b); colours: image plane" over the faces shown; the CV
%       panel's colours are the image-plane speed's
%   G6  with the near-simultaneous rule firing in the CV projection's
%       record: "apparent surface speed (tilt-corrected)" in the Results CV
%       row and the caption, and the 3-D CV colour bar reads "apparent
%       speed (m/s), not CV"
%   G7  "surface speed rests on the OM pose (uncertain up to N°)" in the
%       Results CV row and the CV caption exactly when the run's frame check
%       found the pose ambiguous
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_cv_surface_speed" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_cv_surface_speed', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset, a map, frames and a CV map (as probe_cv_range)
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
tab = rabbit_reconstruction_tab();
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
app.processed_data.height = size(map, 1);
app.processed_data.width = size(map, 2);
app.processed_data.scale = 258;               % um per pixel, one size (single-view layout)
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.processed_data.CV_map = cat(3, speed * 0.6, speed * 0.8, speed);
app.processed_data.CV_settings = rabbit_cv_map.settings(app);   % as the CV map button keeps them (G5)
app.CV_method.Value = app.CV_method.Items{1};
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();

%% G1
rp = fullfile(run_dir, 'outputs', 'reprojection');
% The map's binning against the regions (the projection unbins a binned map
% over its blocks, so the pixel size is per unbinned pixel: 0.258 / om_bin)
payload = rabbit_stack_io.load_roi_json(fullfile(run_dir, 'inputs', 'roi.json'), [], []);
rot = 0;
if isfield(payload, 'rotation'), rot = payload.rotation; end
[~, ~, ~, om_bin] = rabbit_rhythm_reproject.split_canvas(map, payload.region_bounds_src, rot);
px = 0.258 / om_bin;
w = load(fullfile(rp, 'cv_direction.mat'));
cvm = jsondecode(fileread(fullfile(rp, 'cv_reprojection_manifest.json')));
fv = read_cdf_values(fullfile(rp, 'cv_projected.cdf'));
have_dir = all(isfinite(w.direction), 2);
ss = double(w.speed_surface(:));
img = double(w.speed(:));
both = isfinite(ss) & isfinite(img);
rec = struct();
if isfield(cvm, 'cv_direction') && isfield(cvm.cv_direction, 'surface_speed'), rec = cvm.cv_direction.surface_speed; end
g1 = isfield(w, 'speed_surface') && numel(ss) == numel(fv) && any(both) && all(have_dir(isfinite(ss))) && ...
    all(isfinite(img(isfinite(ss)))) && isfield(rec, 'median_surface') && ...
    abs(rec.median_surface - median(ss(both))) < 1e-9 && abs(rec.median_image_plane - median(img(both))) < 1e-9 && ...
    max(abs(double(rec.pixel_mm(:)) - px)) < 1e-12 && isequaln(single(fv(both)), single(img(both)));
results = add(results, 'G1 speed_surface stored next to speed; the manifest record; the .cdf stays image plane', g1, ...
    sprintf('%d faces with both; medians image %.4f, surface %.4f m/s; pixel_mm %s (binning %d)', nnz(both), median(img(both)), ...
    median(ss(both)), mat2str(double(rec.pixel_mm(:)'), 4), om_bin));

%% G2
% The factor surface / image plane holds the tilt and the true pixel size on
% the heart: the probe gives the CV map 0.258 mm pixels (px per unbinned
% pixel), while the run measured its pixels on the heart surface
% (outputs/metric/pixel_size.json, mm per unbinned OM pixel). Divided by
% heart / px, what is left is the tilt, which only makes a wave faster on the
% surface than in the image: about 1 or more
f = ss(both) ./ img(both);
ps = jsondecode(fileread(fullfile(run_dir, 'outputs', 'metric', 'pixel_size.json')));
heart = mean([ps.views.median_mm_per_px]);
t = f / (heart / px);
q = prctile(t, [5 50 95]);
results = add(results, 'G2 the factor is the heart pixel size / 0.258 times a tilt of 1 or more', ...
    q(1) > 0.9 && q(2) >= 1 && q(2) < 1.3, sprintf(['factor 5/50/95 %%: %s; heart pixel %.4f mm; tilt part ' ...
    '5/50/95 %%: %s'], mat2str(prctile(f, [5 50 95]), 4), heart, mat2str(q, 4)));

%% G3
mesh = rabbit_rhythm_reproject.read_ply_mesh(fullfile(rp, 'cv_projected.ply'));
use = isfinite(ss) & ss > 0;
fc = mesh.faces(use, :);
sv = accumarray(fc(:), repmat(ss(use), 3, 1), [size(mesh.pts, 1) 1]);
cv = accumarray(fc(:), 1, [size(mesh.pts, 1) 1]);
vv = sv(cv > 0) ./ cv(cv > 0);
qv = prctile(vv, [25 50 75]);
want3 = sprintf('surface speed (tilt-corrected) median %.2f m/s (IQR %.2f%s%.2f)', qv(2), qv(1), char(8211), qv(3));
% the surface and image-plane medians on one face set,
% the faces that have a surface speed; their count named; a lower bound
iv = tab.viewer_read_cdf(fullfile(rp, 'cv_projected.cdf'));
on3 = use & isfinite(iv(:)) & iv(:) > 0;
qf = prctile(ss(on3), [25 50 75]);
want3 = sprintf(['surface speed (tilt-corrected) median %.2f m/s (IQR %.2f%s%.2f) on the %s faces that have one ' ...
    '(image plane on the same faces %.2f)'], qf(2), qf(1), char(8211), qf(3), tab.format_count(nnz(on3)), ...
    median(iv(on3)));
flat = regexprep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), '\s+', ' ');
results = add(results, 'G3 the Results CV row gives the surface speed after the image-plane one', ...
    contains(flat, want3) && strfind(flat, 'image-plane speed') < strfind(flat, want3), want3);

%% G4
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
fig_cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
fd = tab.viewer_face_entry(fig, 'cv');
shown = tab.viewer_faces_shown(fig, fd);
s4 = ss(shown);
s4 = s4(isfinite(s4));
q4 = prctile(s4, [25 50 75]);
want4 = sprintf('surface speed (tilt-corrected): median %.2f m/s (IQR %.2f%s%.2f); colours: image plane', q4(2), q4(1), ...
    char(8211), q4(3));
ax_c = findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv');
d = getappdata(fig, 'reconstruction_cv');
[~, caveats] = tab.viewer_cv_caption(fig, struct('source_path', fullfile(rp, 'cv_projected.cdf'), 'info', struct('scalar', [])));
cap = [strjoin(cellstr(ax_c.Subtitle.String), ' ') ' ' get(findobj(fig, 'Tag', 'ReconstructionPanelDetailsText_cv'), 'String')'];
results = add(results, 'G4 the CV caption gives the surface speed over the faces shown; colours stay image plane', ...
    any(strcmp(caveats, want4)) && isstruct(d) && isfield(d, 'values') && ...
    max(abs(prctile(double(fd.values(shown & isfinite(fd.values(:)) & fd.values(:) > 0)), [1 99]) - ax_c.CLim)) < 1e-9, ...   % B8: faces shown
    sprintf('%s | %s', want4, strjoin(caveats, ' / ')));
if isempty(cap), cap = ''; end %#ok<NASGU>

%% G5
% The CV map's settings in the CV projection's record under the names the
% captions read: cv_smoothing_3x3, cv_time_max_ms,
% cv_distance_max_mm, with the values in use (the CV map here was put in
% directly, so they are the tab's settings now)
st = rabbit_cv_map.settings(app);
ok5 = isfield(cvm, 'cv_smoothing_3x3') && isequal(logical(cvm.cv_smoothing_3x3), logical(st.smooth_activation)) && ...
    isfield(cvm, 'cv_time_max_ms') && abs(cvm.cv_time_max_ms - st.time_max_ms) < 1e-9 && ...
    isfield(cvm, 'cv_distance_max_mm') && abs(cvm.cv_distance_max_mm - st.distance_max_mm) < 1e-9;
old_rec = rmfield(cvm, intersect(fieldnames(cvm), {'cv_smoothing_3x3', 'cv_time_max_ms', 'cv_distance_max_mm'}));
ok5 = ok5 && isempty(rabbit_reconstruction_tab.simultaneous_from_record(old_rec)) == isempty(rabbit_reconstruction_tab.simultaneous_from_record(cvm));
results = add(results, 'G5 the CV settings in the CV projection''s record (cv_smoothing_3x3, cv_time_max_ms, cv_distance_max_mm)', ...
    ok5, sprintf('%d / %g ms / %g mm', cvm.cv_smoothing_3x3, cvm.cv_time_max_ms, cvm.cv_distance_max_mm));

%% G6 (R5)
mj = fullfile(rp, 'cv_reprojection_manifest.json');
mj_text = fileread(mj);
sim_rec = jsondecode(mj_text);
sim_rec.activation_spread = struct('views', {{'View1'; 'View2'; 'View3'; 'View4'}}, 'iqr_ms', [4.8; 5.2; 4.2; 4.9], ...
    'warn_below_ms', [7.4; 9.5; 8.1; 8.0], 'basis', 'probe');
fid = fopen(mj, 'w', 'n', 'UTF-8'); fwrite(fid, jsonencode(sim_rec), 'char'); fclose(fid);
flat6 = regexprep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), '\s+', ' ');
[~, cav6] = tab.viewer_cv_caption(fig, struct('source_path', fullfile(rp, 'cv_projected.cdf'), 'info', struct('scalar', [])));
[v6_ok, ~, fig6] = tab.visualise_artifacts(run_id);
bar6 = '';
if v6_ok
    ax6 = findobj(fig6, 'Type', 'axes', 'Tag', 'panel_cv');
    bar6 = char(string(ax6.Colorbar.Label.String));
    delete(fig6);
end
fid = fopen(mj, 'w', 'n', 'UTF-8'); fwrite(fid, mj_text, 'char'); fclose(fid);
results = add(results, 'G6 near-simultaneous: apparent surface speed in Results and caption; CV bar "apparent speed (m/s), not CV"', ...
    contains(flat6, 'apparent surface speed (tilt-corrected) median') && ...
    any(startsWith(cav6, 'apparent surface speed (tilt-corrected): median')) && strcmp(bar6, 'apparent speed (m/s), not CV') && ...
    strcmp(char(string(ax_c.Colorbar.Label.String)), 'conduction velocity (m/s)'), bar6);

%% G7 (Q7)
m7 = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
pw7 = rabbit_reconstruction_tab.surface_pose_words(tab.report_frame_check(m7));
flat7 = regexprep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), '\s+', ' ');
[~, cav7] = tab.viewer_cv_caption(fig, struct('source_path', fullfile(rp, 'cv_projected.cdf'), 'info', struct('scalar', [])));
unit7 = strcmp(rabbit_reconstruction_tab.surface_pose_words(struct('ambiguous_frames', [37 67], ...
    'ambiguous_turn_deg', [18.2 13.1])), sprintf('surface speed rests on the OM pose (uncertain up to 18%s)', char(176)));
if isempty(pw7)
    ok7 = unit7 && ~contains(flat7, 'rests on the OM pose') && ~any(contains(cav7, 'rests on the OM pose'));
else
    ok7 = unit7 && contains(flat7, pw7) && any(strcmp(cav7, pw7));
end
results = add(results, 'G7 the surface speed rests on the OM pose, named when the pose is ambiguous (Q7)', ok7, ...
    sprintf('pose words "%s"', pw7));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_CV_SURFACE_SPEED RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_cv_surface_speed:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_cv_surface_speed %d/0\n', n_pass);
end


function v = read_cdf_values(p)
% The float32 values of a RHYTHM .cdf written by write_cdf (8 header lines)
fid = fopen(p, 'r');
c = onCleanup(@() fclose(fid));
for k = 1:8, fgetl(fid); end
v = double(fread(fid, Inf, 'float32'));
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
