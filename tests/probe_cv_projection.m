function probe_cv_projection
%% Probe: the conduction velocity map is projected and shown with the activation map
% Collin Snitchler
% 20.11.2026
% The user wanted the conduction velocity on the mesh in the bottom row of
% Visualise. With a CV map from the Conduction Velocity tab, the projection
% step now projects its speed as it does the activation map; without one,
% nothing changes. Driven through the app's Reproject run button, headless,
% on a copy of a completed run.
%   C1  no CV map: the activation outputs are byte for byte those of the
%       code before (OM_EDGE_BASELINE), no CV file is written, the run
%       manifest says why, and the viewer's CV panel says what to do
%   C2  with a CV map: cv_projected.cdf/.ply and cv_reprojection_manifest.
%       json are written, the activation outputs are still byte for byte
%       as before, and both manifests record the CV source and parameters
%   C3  Visualise: the CV panel is in the bottom row with a colour bar in
%       m/s, its coverage and range
%   C4  a CV map of another size: a warning, the step still completes, no
%       CV file
%   C5  a redo keeps the earlier CV files with the earlier projection
%   C6  a CV map made with an activation cut
%       (CV_settings.activation_cut_ms, the CV tab's "Leave out ..."
%       ticked): faces whose projected activation is above it get no CV,
%       the CV manifest and the run's CV record say how many; without a
%       cut (C2, the default) no activation_cut is recorded; the Results
%       CV row and the Visualise CV caption say how many faces it left
%       without CV
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM,
% OM_REDO_RUN and OM_EDGE_BASELINE as probe_edge_threshold.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_cv_projection" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
base_dir = getenv('OM_EDGE_BASELINE');
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_cv_projection', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
out_dir = fullfile(run_dir, 'outputs', 'reprojection');
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset, the map and frames of probe_edge_threshold
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
map = 20 + 30 * rand(size(om_image));
n_frames = 6;
frames = repmat(om_image, 1, 1, n_frames) .* reshape(linspace(0.9, 1.1, n_frames), 1, 1, []);
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
select_run(app, run_id);

%% C1
app.processed_data.CV_map = [];
redo(app);
same = cmp_outputs(out_dir, base_dir);
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
cv_rec = m.result.reprojection.cv;
extra = tab.viewer_extra_panels(run_id, tab_panels(tab, run_id));
pcv = extra(strcmp({extra.role_id}, 'cv'));
results = add(results, 'C1 no CV map: activation as before, no CV file, the panel says what to do', ...
    same.cdf && same.ply && same.video && ~isfile(fullfile(out_dir, 'cv_projected.ply')) && ...
    contains(cv_rec.status, 'no conduction velocity map') && strcmp(pcv.render_status, 'NOT_YET_PRODUCED') && ...
    contains(pcv.render_detail, 'Conduction Velocity tab'), ...
    sprintf('cdf %d ply %d video %d | %s | %s: %s', same.cdf, same.ply, same.video, cv_rec.status, ...
    pcv.render_status, pcv.render_detail));

%% C2
rng(11, 'twister');
speed = 0.2 + 0.8 * rand(size(map));
speed(rand(size(map)) < 0.1) = NaN;
cv = cat(3, speed * 0.6, speed * 0.8, speed);
app.processed_data.CV_map = cv;
app.CV_method.Value = app.CV_method.Items{1};
redo(app);
same = cmp_outputs(out_dir, base_dir);
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
cv_rec = m.result.reprojection.cv;
cvm = jsondecode(fileread(fullfile(out_dir, 'cv_reprojection_manifest.json')));
src = m.reprojection_source.conduction_velocity;
st = m.stages(strcmp({m.stages.name}, 'reprojection'));
arts = st.artifacts;
if iscell(arts), arts = [arts{:}]; end
art_paths = strjoin(cellstr(string({arts.path})), ' ');
n_assigned_c2 = cv_rec.n_assigned;
no_cut_c2 = ~isfield(cvm, 'activation_cut') && ~isfield(cv_rec, 'activation_cut');   % no cut by default (C6)
results = add(results, 'C2 with a CV map: CV files, activation still as before, both manifests record it', ...
    no_cut_c2 && same.cdf && same.ply && same.video && isfile(fullfile(out_dir, 'cv_projected.cdf')) && ...
    isfile(fullfile(out_dir, 'cv_projected.ply')) && cv_rec.n_assigned > 0 && ...
    startsWith(cv_rec.status, 'projected') && strcmp(src.parameters.method, app.CV_method.Items{1}) && ...
    strcmp(cvm.quantity, 'conduction velocity speed') && contains(cvm.units, 'm/s') && ...
    contains(art_paths, 'cv_projected.ply'), ...
    sprintf('cdf %d ply %d video %d | %s | %s', same.cdf, same.ply, same.video, cv_rec.status, cvm.quantity));

%% C3
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
detail = v_err;
c3 = false;
if v_ok
    ax = findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv');
    act = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
    if isscalar(ax) && isscalar(act)
        cb = ax.Colorbar;
        % The caption draws the median and the range; the (i) tooltip has the range in full
        drawn = strjoin(cellstr(ax.Subtitle.String), ' | ');
        sub = [drawn ' |' get(findobj(fig, 'Tag', 'ReconstructionPanelInfo_cv'), 'TooltipString')];
        bottom = abs(ax.Position(2) - act.Position(2)) < 1e-6;
        c3 = ~isempty(cb) && contains(cb.YLabel.String, 'm/s') && contains(strrep(sub, ' | ', ' '), 'm/s') && ...
            contains(drawn, 'median') && contains(lower(sub), 'colour') && bottom;   % the colour range in (i) with Panel details off
        detail = sprintf('%s | colour bar "%s" | same row as activation %d', sub, cb.YLabel.String, bottom);
    end
    close(fig, 'force');
end
results = add(results, 'C3 Visualise: CV panel in the bottom row, colour bar m/s, median and range drawn', c3, detail);

%% C4
app.processed_data.CV_map = cv(1:end - 1, :, :);
before = dir(fullfile(run_dir, 'outputs'));
redo(app);
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
st = m.stages(strcmp({m.stages.name}, 'reprojection'));
warn_txt = strjoin(cellstr(string(st.warnings)), ' ');
results = add(results, 'C4 a CV map of another size: warned, step completes, no CV file', ...
    any(strcmp(st.status, {'PASSED', 'WARNED'})) && strcmp(m.result.status, 'COMPLETED') && ...
    contains(warn_txt, 'Conduction velocity not projected') && ~isfile(fullfile(out_dir, 'cv_projected.ply')), ...
    sprintf('%s | %s', st.status, warn_txt));

%% C5
d = dir(fullfile(run_dir, 'outputs', 'reprojection_*'));
kept = arrayfun(@(e) isfile(fullfile(e.folder, e.name, 'cv_projected.ply')), d);
results = add(results, 'C5 the earlier CV files are kept with the earlier projection', any(kept), ...
    strjoin({d(kept).name}, ', '));

%% C6
% the map is 20-50 ms; a cut at 35 ms leaves out
% the faces whose projected activation is above it, in the CV only
app.processed_data.CV_map = cv;
s6 = rabbit_cv_map.settings(app);
s6.activation_cut_ms = 35;
s6.activation_cut_source = 'probe';
app.processed_data.CV_settings = s6;
redo(app);
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
cv_rec = m.result.reprojection.cv;
cvm = jsondecode(fileread(fullfile(out_dir, 'cv_reprojection_manifest.json')));
cut6 = struct('cut_ms', NaN, 'n_faces_left_out', 0);
if isfield(cvm, 'activation_cut'), cut6 = cvm.activation_cut; end
same = cmp_outputs(out_dir, base_dir);
% the Results CV row and the Visualise CV caption say how
% many faces the cut left without CV
want6 = rabbit_reconstruction_tab.cv_cut_words(cvm);
said6 = ~isempty(want6) && startsWith(want6, sprintf('%s face', tab.format_count(cut6.n_faces_left_out))) && ...
    contains(want6, 'left without CV by the activation cut (above 35 ms)');
res6 = regexprep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), '\s+', ' ');
said6 = said6 && contains(res6, want6);
[v6, ~, fig6] = tab.visualise_artifacts(run_id);
if v6
    ax6 = findobj(fig6, 'Type', 'axes', 'Tag', 'panel_cv');
    cap6 = '';
    if isscalar(ax6)
        cap6 = [strjoin(cellstr(ax6.Subtitle.String), ' ') ' ' ...
            get(findobj(fig6, 'Tag', 'ReconstructionPanelInfo_cv'), 'TooltipString')];
    end
    said6 = said6 && contains(regexprep(cap6, '\s+', ' '), want6);
    close(fig6, 'force');
else
    said6 = false;
end
results = add(results, 'C6 a CV map with an activation cut: faces above it get no CV, recorded; activation as before', ...
    cut6.cut_ms == 35 && cut6.n_faces_left_out > 0 && isfield(cv_rec, 'activation_cut') && ...
    cv_rec.n_assigned == n_assigned_c2 - cut6.n_faces_left_out && same.cdf && same.ply && same.video && said6, ...
    sprintf('cut %g ms: %d faces left out; assigned %d (without the cut %d) | activation same %d %d %d | said %d "%s"', ...
    cut6.cut_ms, cut6.n_faces_left_out, cv_rec.n_assigned, n_assigned_c2, same.cdf, same.ply, same.video, said6, want6));
app.processed_data = rmfield(app.processed_data, 'CV_settings');

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_CV_PROJECTION RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_cv_projection:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function panels = tab_panels(tab, run_id)
[~, ~, panels] = tab.visualisation_panel_model(run_id);
end


function redo(app)
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();
end


function s = cmp_outputs(out_dir, base_dir)
s = struct('cdf', false, 'ply', false, 'video', false);
s.cdf = isequal(cdf_without_date(fullfile(out_dir, 'activation_projected.cdf')), cdf_without_date(fullfile(base_dir, 'activation_projected.cdf')));
s.ply = strcmp(file_hash(fullfile(out_dir, 'activation_projected.ply')), file_hash(fullfile(base_dir, 'activation_projected.ply')));
a = load(fullfile(out_dir, 'om_video_projected.mat'));
b = load(fullfile(base_dir, 'om_video_projected.mat'));
s.video = isequaln(a, b);
end


function select_run(app, rid)
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, rid), 1)};
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
