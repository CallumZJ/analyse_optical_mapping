function probe_edge_threshold
%% Probe: the edge faces' minimum edge weight is a setting of the projection
% Collin Snitchler
% 20.11.2026
% The apex of the July heart stays grey: it is on the rim of all four
% views, so no camera sees it directly, and RHYTHM's EDGE rule (minimum edge
% weight 0.55, dataProjection02 minedgeEDGE) keeps most of it out. Step 4
% now has "Edge faces: minimum edge weight" (default 0.55). Driven through
% the app's Reproject run button, headless, on a copy of a completed run.
%   E1  0.55: the projected .cdf (but for its date line) and .ply are byte
%       for byte those of the code before the setting, and the video holds the same values
%       (OM_EDGE_BASELINE)
%   E2  0.30: more faces are assigned and none of the 0.55 faces is lost
%   E3  0.30: the run manifest and reprojection_manifest.json record the
%       deviation (old 0.55, new 0.30, why), the step warns, and the copy of
%       dataProjection02 is named; the vendored file is unchanged
%   E4  the viewer's captions name the threshold and the edge faces
%   E5  Redo projection at 0.55 again: no deviation is left, and the
%       results are those of E1
%   E6  a value outside 0.1-0.9 is refused
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder and:
%   OM_REDO_DS, OM_REDO_STEM, OM_REDO_RUN  as probe_reproject_redo (a copy
%                 of a COMPLETED run; it is copied once more and that is used)
%   OM_EDGE_BASELINE  folder of a projection made by the code before the
%                 setting with this probe's map and frames (OM_EDGE_MODE=
%                 baseline writes it, run with that code on the path)
%   OM_EDGE_REPO  optional: the app folder to run (default: this probe's)
% Usage: matlab -batch "addpath('<repo>/tests'); probe_edge_threshold" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = getenv('OM_EDGE_REPO');
if isempty(repo), repo = fileparts(fileparts(mfilename('fullpath'))); end
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
baseline_mode = strcmp(getenv('OM_EDGE_MODE'), 'baseline');
base_dir = getenv('OM_EDGE_BASELINE');
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_edge_threshold', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset, a map and OM frames on the run's canvas
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
out_dir = fullfile(run_dir, 'outputs', 'reprojection');

if baseline_mode
    redo(app, 'Map and video');
    assert(isfile(fullfile(out_dir, 'om_video_projected.mat')), 'The baseline projection failed.');
    if ~isfolder(base_dir), mkdir(base_dir); end
    copyfile(fullfile(out_dir, '*'), base_dir);
    fprintf('\nPROBE_EDGE_THRESHOLD BASELINE written to %s\n', base_dir);
    return;
end
vendored = which('dataProjection02');
vendored_hash = file_hash(vendored);

%% E1
app.recon.ReconstructionEdgeWeightField.Value = 0.55;
redo(app, 'Map and video');
same = cmp_outputs(out_dir, base_dir);
mj55 = jsondecode(fileread(fullfile(out_dir, 'reprojection_manifest.json')));
proj55 = read_cdf_values(fullfile(out_dir, 'activation_projected.cdf'));
results = add(results, 'E1 0.55: .cdf and .ply byte for byte as before, same video values', ...
    same.cdf && same.ply && same.video && strcmp(mj55.rhythm.function, 'dataProjection02 (vendored, unmodified)'), ...
    sprintf('cdf %d ply %d video %d | %s', same.cdf, same.ply, same.video, mj55.rhythm.function));

%% E2
app.recon.ReconstructionEdgeWeightField.Value = 0.30;
redo(app, 'Map and video');
proj30 = read_cdf_values(fullfile(out_dir, 'activation_projected.cdf'));
mj30 = jsondecode(fileread(fullfile(out_dir, 'reprojection_manifest.json')));
got55 = proj55 ~= 0; got30 = proj30 ~= 0;
results = add(results, 'E2 0.30: more faces assigned, none of the 0.55 ones lost', ...
    nnz(got30) > nnz(got55) && ~any(got55 & ~got30), ...
    sprintf('0.55: %d (edge %d), 0.30: %d (edge %d)', nnz(got55), mj55.coverage.n_direct_overlap_edge(3), ...
    nnz(got30), mj30.coverage.n_direct_overlap_edge(3)));

%% E3
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
dev = m.deviations;
if iscell(dev), dev = [dev{:}]; end
k = find(strcmp({dev.parameter}, 'minedgeEDGE'));
st = m.stages(strcmp({m.stages.name}, 'reprojection'));
warn_txt = strjoin(cellstr(string(st.warnings)), ' ');
md = mj30.deviations;
results = add(results, 'E3 0.30 recorded as a deviation in both manifests, warned, copy named', ...
    isscalar(k) && dev(k).old == 0.55 && dev(k).new == 0.30 && contains(dev(k).rationale, 'apex') && ...
    m.result.reprojection.min_edge_edge == 0.30 && md(1).new == 0.30 && mj30.edge_thresholds.min_edge_edge == 0.30 && ...
    contains(warn_txt, 'Edge threshold 0.30 (RHYTHM 0.55)') && contains(mj30.rhythm.function, 'minedgeEDGE = 0.30') && ...
    strcmp(file_hash(vendored), vendored_hash), ...
    sprintf('%s | %s', warn_txt, mj30.rhythm.function));

%% E4
pv = struct('source_path', fullfile(out_dir, 'activation_projected.ply'));
line_a = tab.viewer_edge_line(pv);
results = add(results, 'E4 the captions name the threshold and the edge faces', ...
    contains(line_a, 'edge weight 0.30 (RHYTHM default 0.55)') && contains(line_a, 'Direct / overlap / edge faces'), line_a);   % one name for the setting

%% E5
app.recon.ReconstructionEdgeWeightField.Value = 0.55;
redo(app, 'Map and video');
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
dev = m.deviations;
if iscell(dev), dev = [dev{:}]; end
left = ~isempty(dev) && any(strcmp({dev.parameter}, 'minedgeEDGE'));
same = cmp_outputs(out_dir, base_dir);
line_b = tab.viewer_edge_line(pv);
results = add(results, 'E5 back at 0.55: no deviation left, results as E1', ...
    ~left && same.cdf && same.ply && same.video && ~contains(line_b, 'edge threshold'), ...
    sprintf('left %d cdf %d ply %d video %d | %s', left, same.cdf, same.ply, same.video, line_b));

%% E6
refused = '';
try
    rabbit_rhythm_reproject.check_min_edge_edge(0.05);
catch ME
    refused = ME.identifier;
end
results = add(results, 'E6 0.05 is refused', strcmp(refused, 'analyse_om:Reprojection:BadMinEdge'), refused);

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_EDGE_THRESHOLD RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_edge_threshold:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function redo(app, video_choice)
% Reproject run on the selected COMPLETED run: Redo projection, then the video question
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', video_choice);
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


function v = read_cdf_values(p)
% The projected values of an activation_projected.cdf (float32 after its 8 header lines)
fid = fopen(p, 'rb');
c = onCleanup(@() fclose(fid));
for k = 1:8, fgetl(fid); end
v = fread(fid, Inf, 'float32');
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
