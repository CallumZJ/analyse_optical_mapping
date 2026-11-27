function probe_visualise_face_csv
%% Probe: the per-face CSV from the Visualise window's Save...
% Collin Snitchler
% 25.11.2026
% A per-face CSV (activation,
% CV, CV surface speed, and each role's class and views) from the Visualise save menu,
% in om_export's graph-CSV convention (one header row of names with units,
% NaN as an empty cell). Driven through the app's Redo projection, headless,
% on a copy of a completed run, with a CV map as probe_cv_range.
%   C1  Save... offers CSV among its file types; a .csv name writes the
%       per-face data, not a picture
%   C2  the header: face, activation_ms, cv_image_plane_m_s, cv_surface_m_s,
%       activation_class, activation_views, cv_class, cv_views
%       (one class and one views column per role); one row per
%       mesh face, face = 1..n
%   C3  the values read back are the projection's: activation as projected
%       (empty where unassigned), CV image plane (cv_projected.cdf, empty
%       where none), CV surface (cv_direction.mat speed_surface), the class
%       names of activation_confidence.mat and, for the CV, of
%       cv_confidence.mat (R2)
%   C4  views: each assigned face names the views it took its value from,
%       per role (face_views of activation_confidence.mat and of
%       cv_confidence.mat, View1-View4 through the regions file), one view
%       for DIRECT faces, two or more for OVERLAP; empty for unassigned faces
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_visualise_face_csv" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_visualise_face_csv', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
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
app.processed_data.scale = 258;
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.processed_data.CV_map = cat(3, speed * 0.6, speed * 0.8, speed);
app.CV_method.Value = app.CV_method.Items{1};
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map only');
app.recon.ReconstructionReprojectButtonPushed();
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
fig_cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>

%% C1: Save... with a .csv name
out = fullfile(root, 'faces.csv');
headless_push('uiputfile', out);
tab.viewer_save_image(fig);
call = getappdata(groot, 'om_headless_last_uiputfile');
filters = call{1};
results = add(results, 'C1 Save... offers CSV and writes the per-face data for a .csv name', ...
    any(strcmp(filters(:, 1), '*.csv')) && exist(out, 'file') == 2, strjoin(filters(:, 2)', ' | '));

%% C2
txt = splitlines(string(fileread(out)));
txt = txt(strlength(txt) > 0);
rp = fullfile(run_dir, 'outputs', 'reprojection');
fa = read_cdf_values(fullfile(rp, 'activation_projected.cdf'));
n = numel(fa);
want_head = "face,activation_ms,cv_image_plane_m_s,cv_surface_m_s,activation_class,activation_views,cv_class,cv_views";   % R2
cells = split(txt(2:end), ',');
results = add(results, 'C2 header with units, one row per face, face = 1..n', txt(1) == want_head && ...
    size(cells, 1) == n && isequal(str2double(cells(:, 1)), (1:n)'), sprintf('%s; %d rows, %d faces', txt(1), numel(txt) - 1, n));

%% C3
num = @(c) str2double(c);                      % '' -> NaN
conf = load(fullfile(rp, 'activation_confidence.mat'));
cls = double(conf.face_class(:));
cconf = load(fullfile(rp, 'cv_confidence.mat'));
ccls = double(cconf.face_class(:));
fv = read_cdf_values(fullfile(rp, 'cv_projected.cdf'));
w = load(fullfile(rp, 'cv_direction.mat'));
fd = tab.viewer_face_entry(fig, 'projected');
act = double(fd.values(:)); act(~fd.assigned(:)) = NaN;
cvv = fv; cvv(~(cvv > 0)) = NaN;
ss = double(w.speed_surface(:)); ss(~(ss > 0)) = NaN;
same = @(a, b) isequal(isnan(a), isnan(b)) && all(a(~isnan(a)) == b(~isnan(b)));
names = string(conf.class_names(:));
results = add(results, 'C3 activation, CV image plane and surface, class: the projection''s values; NaN empty', ...
    same(num(cells(:, 2)), act) && same(num(cells(:, 3)), cvv) && same(num(cells(:, 4)), ss) && ...
    all(cells(:, 5) == names(cls)) && all(cells(:, 7) == names(ccls)) && all(cells(isnan(act), 2) == ""), ...
    sprintf('%d activation, %d CV, %d surface values; %d faces whose CV class differs from the activation''s', ...
    nnz(~isnan(act)), nnz(~isnan(cvv)), nnz(~isnan(ss)), nnz(cls ~= ccls)));

%% C4
ok4 = views_ok(cells(:, 6), conf, cls, n) && views_ok(cells(:, 8), cconf, ccls, n);
results = add(results, 'C4 activation_views, cv_views: the views each face took that value from, View1-View4; empty when unassigned', ok4, ...
    sprintf('examples: %s', strjoin(unique(cells(cells(:, 8) ~= "", 8))', ', ')));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_VISUALISE_FACE_CSV RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_visualise_face_csv:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_visualise_face_csv %d/0\n', n_pass);
end


function v = read_cdf_values(p)
% The float32 values of a RHYTHM .cdf written by write_cdf (8 header lines)
fid = fopen(p, 'rb');
c = onCleanup(@() fclose(fid));
for k = 1:8, fgetl(fid); end
v = double(fread(fid, Inf, 'float32'));
end


function ok = views_ok(col, conf, cls, n)
% One role's views column against its confidence file (C4)
fvw = logical(conf.face_views);
nv = arrayfun(@(k) numel(strsplit(col(k), '+')) * (col(k) ~= ""), (1:n)');
ok = all(nv == sum(fvw, 2)) && all(nv(cls == 1) == 1) && all(nv(cls == 2) >= 2) && all(col(cls == 5) == "") && ...
    all(startsWith(col(nv > 0), "View")) && isfield(conf, 'view_names');
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
