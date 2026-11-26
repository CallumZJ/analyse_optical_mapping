function probe_activation_zero
%% Probe: the activation map's method and zero, recorded with the map and its projection, and the colour-bar label
% Collin Snitchler
% 25.11.2026
% the label says "activation (ms from
% start of averaged window)" only when that is true: the df/dt and peak
% methods of Generate map without New zero; otherwise "activation (ms)".
%   Z1  rabbit_activation_zero: df/dt and peak are "start of averaged
%       window", cross-correlation, mid-point and the Traces tab's map
%       "earliest activation"; New zero adds up; the label rule; a record
%       read back through JSON is the same; no record: "activation (ms)"
%   Z2  the app: New zero (the Activation Map tab's button) moves the
%       record's zero; a map without a record stays without one
%   Z2b beside the record, the map's maximum
%       (processed_data.activation_max), moved by New zero, removed with
%       the record
%   Z3  Redo projection records the app's record in reprojection_manifest.json
%       (activation_zero), and Visualise labels the activation colour bar
%       from it: df/dt "activation (ms from start of averaged window)";
%       after New zero, and for cross-correlation, "activation (ms)"
% Generate map itself sets the record (the .mlapp); it is run on real data
% by a check on a real run outside the repository, not here.
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_activation_zero" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
start_label = 'activation (ms from start of averaged window)';

%% Z1
r_d = rabbit_activation_zero.make('df/dt');
r_p = rabbit_activation_zero.make('peak');
r_x = rabbit_activation_zero.make('cross-correlation');
r_m = rabbit_activation_zero.make('mid-point');
r_t = rabbit_activation_zero.make('traces');
back = rabbit_activation_zero.check(jsondecode(jsonencode(r_d)));
r_n = r_d; r_n.new_zero_ms = 5;
z1 = strcmp(r_d.zero, 'start of averaged window') && strcmp(r_p.zero, 'start of averaged window') && ...
    all(cellfun(@(r) strcmp(r.zero, 'earliest activation'), {r_x, r_m, r_t})) && ...
    strcmp(rabbit_activation_zero.label(r_d), start_label) && strcmp(rabbit_activation_zero.label(r_p), start_label) && ...
    all(cellfun(@(r) strcmp(rabbit_activation_zero.label(r), 'activation (ms)'), {r_x, r_m, r_t, r_n, []})) && ...
    isequal(back, r_d) && isempty(rabbit_activation_zero.check(struct('method', 'df/dt')));
results = add(results, 'Z1 methods, zeros and the label rule; through JSON', z1, sprintf('%s | %s', ...
    rabbit_activation_zero.label(r_d), rabbit_activation_zero.label(r_x)));

%% The app with the run's dataset (as probe_cv_range)
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_activation_zero', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), report(results); return; end   % SKIP printed; Z1 is reported
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
map = 20 + 30 * rand(size(om_image));
frames = repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, []);
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
app.processed_data.image_stack = {frames};
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};

%% Z2: New zero on the Activation Map tab, in an app with a (synthetic) recording loaded
stack = 1000 + 100 * rand(40, 30, 30); %#ok<NASGU>    % the app loads the variable 'stack'
rec = fullfile(root, 'synthetic_recording.mat');
save(rec, 'stack');
b = analyse_optical_mapping;
b_cleanup = onCleanup(@() delete(b)); %#ok<NASGU>
headless_push('uigetfile', rec);
headless_push('inputdlg', {'204.0136'});
headless_push('uiconfirm', 'Continue');
feval(b.LoadfileMenu.MenuSelectedFcn, b.LoadfileMenu, []);
m2 = repmat(linspace(10, 40, 30), 40, 1);
% New zero redraws the shown map and reads its colour bar: a map shown
set(b.display.image_handle, 'CData', m2);
b.display.colourbar_handle = colorbar(b.display.image_handle.Parent);
b.processed_data.activation_map = m2;
rabbit_activation_zero.forget(b);
headless_push('inputdlg', {'3'});
feval(b.newzeromap.ButtonPushedFcn, b.newzeromap, []);
none_after = isempty(rabbit_activation_zero.of(b));
b.processed_data.activation_map = m2;
rabbit_activation_zero.mark(b, 'df/dt');
headless_push('inputdlg', {'5'});
feval(b.newzeromap.ButtonPushedFcn, b.newzeromap, []);
r2 = rabbit_activation_zero.of(b);
% m2's maximum is 40 ms; New zero 5 moves it to 35
max2 = rabbit_activation_zero.max_of(b);
rabbit_activation_zero.forget(b);
max2_gone = ~isfield(b.processed_data, 'activation_max') && isnan(rabbit_activation_zero.max_of(b));
results = add(results, 'Z2b the map''s maximum is kept beside the record, moved by New zero', ...
    abs(max2 - 35) < 1e-12 && max2_gone, sprintf('after New zero 5: %g ms; after forget: none %d', max2, max2_gone));
results = add(results, 'Z2 New zero moves the recorded zero; no record stays none', none_after && ~isempty(r2) && ...
    r2.new_zero_ms == 5 && strcmp(r2.method, 'df/dt') && max(abs(b.processed_data.activation_map(:) - (m2(:) - 5))) < 1e-12, ...
    sprintf('after New zero 5: %s', jsonencode(r2)));

%% Z3: Redo projection records it; Visualise labels from it
label = cell(1, 3);
recs = cell(1, 3);
cases = {'df/dt', 0; 'df/dt', 5; 'cross-correlation', 0};
for k = 1:3
    app.processed_data.activation_map = map;
    rabbit_activation_zero.mark(app, cases{k, 1});
    if cases{k, 2} ~= 0, rabbit_activation_zero.new_zero(app, cases{k, 2}); end
    headless_push('uiconfirm', 'Redo projection');
    headless_push('uiconfirm', 'Map only');
    app.recon.ReconstructionReprojectButtonPushed();
    pm = jsondecode(fileread(fullfile(run_dir, 'outputs', 'reprojection', 'reprojection_manifest.json')));
    recs{k} = [];
    if isfield(pm, 'activation_zero'), recs{k} = rabbit_activation_zero.check(pm.activation_zero); end
    [v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
    assert(v_ok, v_err);
    % The activation panel's colour bar: the one whose label starts "activation"
    cbs = findall(fig, 'Type', 'ColorBar');
    labs = arrayfun(@(c) char(string(c.Label.String)), cbs, 'UniformOutput', false);
    hit = labs(startsWith(labs, 'activation'));
    label{k} = strjoin(hit, ' / ');
    delete(fig);
end
z3 = isequal(recs{1}, rabbit_activation_zero.make('df/dt')) && recs{2}.new_zero_ms == 5 && ...
    strcmp(recs{3}.zero, 'earliest activation') && strcmp(label{1}, start_label) && ...
    strcmp(label{2}, 'activation (ms)') && strcmp(label{3}, 'activation (ms)');
results = add(results, 'Z3 the projection records the zero; the colour bar says it only when true', z3, ...
    sprintf('labels: "%s" | "%s" | "%s"; records: %s | %s | %s', label{:}, jsonencode(recs{1}), jsonencode(recs{2}), ...
    jsonencode(recs{3})));

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
fprintf('\nPROBE_ACTIVATION_ZERO RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_activation_zero:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_activation_zero %d/0\n', n_pass);
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
