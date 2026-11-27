function probe_confidence_classes
%% Probe: confidence class per face and the Visualise checkbox for low-confidence fills
% Collin Snitchler
% 23.11.2026
% Each projection saves a class per face (1 DIRECT, 2 OVERLAP, 3 EDGE at
% RHYTHM's 0.55, 4 low confidence, 5 unassigned) in <stem>_confidence.mat,
% and Visualise has "Low-confidence fills" to hide class 4 in the
% activation, OM video and conduction velocity panels. Driven through the
% app's Reproject run button, headless, on a copy of a completed run.
%   K1  0.55: class files for the map and the CV, no class-4 face, the
%       manifest defines the classes and says 0 still means unassigned in
%       the values; the checkbox is disabled and says why
%   K2  0.30: the class-4 faces are the faces gained against 0.55, and
%       classes 1-3 are those of 0.55
%   K3  0.30: the checkbox starts unticked (low-confidence fills off by
%       default below 0.55); ticked, in all three panels only the vertices
%       of class-4 faces change, each panel has some; the captions say how
%       many faces are hidden, then shown; unticked again, the colours are
%       as before
%   K4  a projection without class files: the checkbox is disabled and
%       says to redo the projection
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_confidence_classes" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_confidence_classes', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
out_dir = fullfile(run_dir, 'outputs', 'reprojection');
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset, a map, frames and a CV map (as probe_cv_projection)
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
map = 20 + 30 * rand(size(om_image));
frames = repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, []);
rng(11, 'twister');
speed = 0.2 + 0.8 * rand(size(map));
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
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.processed_data.CV_map = cat(3, speed * 0.6, speed * 0.8, speed);
app.CV_method.Value = app.CV_method.Items{1};
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};

%% K1
app.recon.ReconstructionEdgeWeightField.Value = 0.55;
redo(app);
c55 = read_class(fullfile(out_dir, 'activation_confidence.mat'));
cv55 = read_class(fullfile(out_dir, 'cv_confidence.mat'));
mj = jsondecode(fileread(fullfile(out_dir, 'reprojection_manifest.json')));
cc = mj.confidence_classes;
[cb, fig] = checkbox(tab, run_id);
k1 = ~isempty(c55) && ~isempty(cv55) && ~any(c55 == 4) && ~any(cv55 == 4) && numel(cc.classes) == 5 && ...
    strcmp(cc.classes(4).name, 'LOW_CONFIDENCE') && strcmp(cc.classes(5).name, 'UNASSIGNED') && ...
    contains(cc.note, '0 still means unassigned') && isequal(cc.counts(:)', histc_5(c55)) && ...
    strcmp(cc.file, 'activation_confidence.mat') && isscalar(cb) && strcmp(cb.Enable, 'off') && ...
    contains(cb.TooltipString, '0.55');
results = add(results, 'K1 0.55: class files, no class 4, classes defined, checkbox disabled', k1, ...
    sprintf('counts %s | cv counts %s | enable %s | %s', mat2str(histc_5(c55)), mat2str(histc_5(cv55)), ...
    cb_field(cb, 'Enable'), cb_field(cb, 'TooltipString')));
close(fig, 'force');
v55 = read_cdf_values(fullfile(out_dir, 'activation_projected.cdf'));

%% K2
app.recon.ReconstructionEdgeWeightField.Value = 0.30;
redo(app);
c30 = read_class(fullfile(out_dir, 'activation_confidence.mat'));
cv30 = read_class(fullfile(out_dir, 'cv_confidence.mat'));
v30 = read_cdf_values(fullfile(out_dir, 'activation_projected.cdf'));
gained = (v30 ~= 0) & ~(v55 ~= 0);
k2 = nnz(c30 == 4) > 0 && nnz(c30 == 4) == nnz(gained) && isequal(find(c30 == 4), find(gained)) && ...
    isequal(c30(c30 <= 3), c55(c30 <= 3)) && nnz(cv30 == 4) > 0;
results = add(results, 'K2 0.30: class 4 = the faces gained against 0.55, classes 1-3 unchanged', k2, ...
    sprintf('class 4: %d, gained: %d, cv class 4: %d', nnz(c30 == 4), nnz(gained), nnz(cv30 == 4)));

%% K3
[cb, fig] = checkbox(tab, run_id);
detail = 'no enabled checkbox';
k3 = false;
if isscalar(cb) && strcmp(cb.Enable, 'on') && cb.Value == 0
    faces = getappdata(fig, 'reconstruction_activation').handle.Faces;
    act_v = unique(faces(c30 == 4, :));
    cv_v = unique(faces(cv30 == 4, :));
    tags = {'panel_projected', 'panel_video', 'panel_cv'};
    allowed = {act_v, act_v, cv_v};
    before = cellfun(@(tg) panel_colours(fig, tg), tags, 'UniformOutput', false);
    subs = cellfun(@(tg) strjoin(cellstr(findobj(fig, 'Type', 'axes', 'Tag', tg).Subtitle.String), ' '), tags, ...
        'UniformOutput', false);
    cb.Value = 1;
    cb.Callback(cb, []);
    after = cellfun(@(tg) panel_colours(fig, tg), tags, 'UniformOutput', false);
    subs_shown = cellfun(@(tg) strjoin(cellstr(findobj(fig, 'Type', 'axes', 'Tag', tg).Subtitle.String), ' '), tags, ...
        'UniformOutput', false);
    cb.Value = 0;
    cb.Callback(cb, []);
    again = cellfun(@(tg) panel_colours(fig, tg), tags, 'UniformOutput', false);
    parts = cell(1, 3);
    k3 = true;
    for k = 1:3
        changed = find(any(abs(after{k} - before{k}) > 1e-12, 2));
        only = all(ismember(changed, allowed{k}));
        k3 = k3 && ~isempty(changed) && only && contains(subs{k}, 'faces hidden') && ...
            contains(subs_shown{k}, 'steep-angle rim faces shown') && isequal(again{k}, before{k});
        parts{k} = sprintf('%s: %d vertices changed, only class-4 vertices %d, back %d', tags{k}, ...
            numel(changed), only, isequal(again{k}, before{k}));
    end
    detail = strjoin(parts, ' | ');
end
results = add(results, 'K3 unticked by default; ticked, only class-4 vertices change in all three panels, captions say so; unticked restores', ...
    k3, detail);
close(fig, 'force');

%% K4
delete(fullfile(out_dir, 'activation_confidence.mat'));
delete(fullfile(out_dir, 'cv_confidence.mat'));
[cb, fig] = checkbox(tab, run_id);
results = add(results, 'K4 no class files: checkbox disabled, says to redo the projection', ...
    isscalar(cb) && strcmp(cb.Enable, 'off') && contains(cb.TooltipString, 'Redo the projection'), ...
    sprintf('%s | %s', cb_field(cb, 'Enable'), cb_field(cb, 'TooltipString')));
close(fig, 'force');

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_CONFIDENCE_CLASSES RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_confidence_classes:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function redo(app)
% Reproject run on the selected COMPLETED run: Redo projection, map and video
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();
end


function [cb, fig] = checkbox(tab, run_id)
% Visualise the run; the low-confidence checkbox
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
cb = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
end


function c = panel_colours(fig, tag)
% The vertex colours of a panel's patch. The CV panel: its drawn vertex
% values, since its automatic colour range follows the faces shown),
% so every colour moves a little when the fills are toggled
ax = findobj(fig, 'Type', 'axes', 'Tag', tag);
h = findobj(ax, 'Type', 'patch');
c = double(h(1).FaceVertexCData);
if strcmp(tag, 'panel_cv')
    d = getappdata(fig, 'reconstruction_cv');
    c = double(d.values(:, 1));
    c(isnan(c)) = -1;
end
end


function c = read_class(p)
c = [];
if isfile(p)
    w = load(p, 'face_class');
    c = double(w.face_class(:));
end
end


function n = histc_5(c)
n = arrayfun(@(k) nnz(c == k), 1:5);
end


function s = cb_field(cb, name)
s = '';
if isscalar(cb), s = char(cb.(name)); end
end


function v = read_cdf_values(p)
% The projected values of an activation_projected.cdf (float32 after its 8 header lines)
fid = fopen(p, 'rb');
c = onCleanup(@() fclose(fid));
for k = 1:8, fgetl(fid); end
v = fread(fid, Inf, 'float32');
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
