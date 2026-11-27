function probe_reproject_redo
%% Probe: Reproject run redoes the projection of a COMPLETED run
% Collin Snitchler
% 20.11.2026
% The user's run was projected with "Map only"; adding the OM video took a
% new run (about 85 min, sparse model again). Reproject run now redoes the
% projection step of a COMPLETED run whose steps all passed: it asks first,
% keeps the earlier outputs/reprojection in outputs/reprojection_NN and
% reuses the sparse model, mesh and cameras. Driven through the app's own
% button callback, headless, on a copy of a completed run.
%   P1  a COMPLETED run with a map loaded: Reproject run is on, and the
%       earlier projection would go to outputs/reprojection_01
%   P2  Cancel at "Redo the projection?": nothing on disk changes
%   P3  Redo, then Cancel at the video question: nothing on disk changes
%   P4  Redo with "Map and video": COMPLETED in both stores, the OM video
%       is in outputs/reprojection, the earlier files are unchanged in
%       outputs/reprojection_01 (with the earlier log), the manifest keeps
%       the earlier step record, and the results say where it is kept.
%       "unchanged" is the data files byte for byte, and the
%       records text-exact except their cdf, ply and video paths, which
%       name the same files in the kept folder (as in P8)
%   P5  the redone run opens (open_manifest) and its video is the viewer's
%   P6  a second redo would keep the projection in outputs/reprojection_02
%   P7  a FAILED run is not redone (can_redo_reprojection says why)
%   P4b after the redo the Results box's tooltip is its
%       own text with the folder below it, and its own text alone again
%       when the run is shown again
%   P8  Step 2's Pacing cycle: blank by default and not recorded; 0, a
%       negative number and text refused with a message; a value given
%       before Redo projection recorded in that projection's record
%       (reprojection_manifest.json, and the run's), the earlier record in
%       outputs/reprojection_02 unchanged; the Results read it
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder and:
%   OM_REDO_DS    folder holding a copy of <stem>.matom with a COMPLETED run
%                 (not the original: the probe copies it once more, under
%                 tempdir, and works on that copy only)
%   OM_REDO_STEM  dataset stem (the .matom name without .matom)
%   OM_REDO_RUN   run id of the COMPLETED run
% Usage: matlab -batch "addpath('<repo>/tests'); probe_reproject_redo" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_reproject_redo', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
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
before = snapshot(run_dir);

%% P1
g = app.recon.reconstruction_gate_state();
[can, why, arch] = tab.can_redo_reprojection(run_id);
results = add(results, 'P1 COMPLETED run: Reproject run on, earlier kept in reprojection_01', ...
    g.reproject_ok && can && strcmp(arch, 'outputs/reprojection_01'), sprintf('%d %d %s %s %s', g.reproject_ok, can, arch, why, g.reproject_tip));

%% P2
headless_push('uiconfirm', 'Cancel');
app.recon.ReconstructionReprojectButtonPushed();
d = last_dialogs(1);
results = add(results, 'P2 Cancel at the redo question: nothing changes', ...
    contains(d{1}, 'Redo the projection') && isequal(snapshot(run_dir), before), strjoin(d, ' | '));

%% P3
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Cancel');
app.recon.ReconstructionReprojectButtonPushed();
d = last_dialogs(2);
results = add(results, 'P3 Redo, then Cancel at the video question: nothing changes', ...
    contains(d{2}, 'Also project the OM video') && isequal(snapshot(run_dir), before), strjoin(d, ' | '));

%% P4
old_files = containers.Map(before.reprojection_files, before.reprojection_hashes);
old_text = manifest_texts(fullfile(run_dir, 'outputs', 'reprojection'));   % F7: compared below
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
[conf_ok, conf_err] = tab.confirm_run_status(run_id, 'COMPLETED');
kept = hash_dir(fullfile(run_dir, 'outputs', 'reprojection_01'));
% the data files byte for byte; each record differs only in its
% cdf, ply and video paths, which now name the files in the kept folder
kept_same = kept_unchanged(kept, old_files, old_text, fullfile(run_dir, 'outputs', 'reprojection_01'));
hist = m.redone_reprojections;
if iscell(hist), hist = hist{1}; end
txt = strjoin(app.recon.ReconstructionResultsText.Value, ' ');
rec = m.stages(strcmp({m.stages.name}, 'reprojection'));
results = add(results, 'P4 redo with video: COMPLETED, video made, earlier kept unchanged', ...
    conf_ok && isfile(fullfile(run_dir, 'outputs', 'reprojection', 'om_video_projected.mat')) && kept_same && ...
    isKey(kept, 'reprojection.log') && strcmp(hist(1).kept_in, 'outputs/reprojection_01') && ...
    strcmp(hist(1).stage_record.name, 'reprojection') && numel(rec) == 1 && ...
    any(strcmp(rec.status, {'PASSED', 'WARNED'})) && contains(txt, 'kept in outputs\reprojection_01'), ...   % backslashes on screen
    sprintf('%s | %s | kept_same %d | %s', conf_err, strjoin(last_dialogs(3), ' | '), kept_same, txt));

%% P4b
tip_redo = cellstr(app.recon.ReconstructionResultsText.Tooltip);
app.recon.reconstruction_render_status(run_id);
tip_again = cellstr(app.recon.ReconstructionResultsText.Tooltip);
own = app.recon.reconstruction_results_tooltip();
results = add(results, 'P4b the Results tooltip keeps its own text, the folder below it, put back on a redraw', ...
    numel(tip_redo) == 2 && strcmp(tip_redo{1}, own{1}) && startsWith(tip_redo{2}, 'Projection done again into ') && ...
    contains(tip_redo{2}, 'reprojection') && isequal(tip_again, own), strjoin([tip_redo(:)', {'||'}, tip_again(:)'], ' | '));

%% P5
[o_ok, o_err] = rabbit_reconstruction_tab().open_manifest(fullfile(run_dir, 'manifest.json'));
v = load(fullfile(run_dir, 'outputs', 'reprojection', 'om_video_projected.mat'));
vn = fieldnames(v);
results = add(results, 'P5 the redone run opens and holds the video', o_ok && ~isempty(vn), ...
    sprintf('%s | %s', o_err, strjoin(vn, ',')));

%% P6
[can2, ~, arch2] = tab.can_redo_reprojection(run_id);
results = add(results, 'P6 a second redo keeps it in reprojection_02', can2 && strcmp(arch2, 'outputs/reprojection_02'), arch2);

%% P8
% Step 2's Pacing cycle: blank by default and not recorded
% (P4's redo); 0, a negative number and text are refused with a message and
% the field goes back; a value given before Redo projection is recorded in
% that projection's record (and the run's), not in the earlier ones; the
% Results read it
fld = app.recon.ReconstructionPacingCycleField;
pm4 = jsondecode(fileread(fullfile(run_dir, 'outputs', 'reprojection', 'reprojection_manifest.json')));
blank_ok = isempty(fld.Value) && ~isfield(pm4, 'pacing_cycle_ms') && ~isfield(m.result.reprojection, 'pacing_cycle_ms') && ...
    isempty(tab.report_cycle_length(run_dir, m));
bad = {'0', '-5', 'abc'};
refused = true;
for k = 1:numel(bad)
    n0 = numel(getappdata(groot, 'om_headless_dialogs'));
    fld.Value = bad{k};
    fld.ValueChangedFcn(fld, struct('Value', bad{k}, 'PreviousValue', ''));
    dl = getappdata(groot, 'om_headless_dialogs');
    told = numel(dl) > n0 && contains(dl(end).message, 'is not a pacing cycle') && contains(dl(end).message, '500 ms');
    refused = refused && isempty(fld.Value) && told;
end
threw = false;
try
    rabbit_rhythm_reproject.check_pacing_cycle('0');
catch ME
    threw = strcmp(ME.identifier, 'analyse_om:Reprojection:BadPacingCycle');
end
fld.Value = '500';
fld.ValueChangedFcn(fld, struct('Value', '500', 'PreviousValue', ''));
kept_value = strcmp(fld.Value, '500');
prev_text = manifest_texts(fullfile(run_dir, 'outputs', 'reprojection'));
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map only');
app.recon.ReconstructionReprojectButtonPushed();
m8 = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
pm8 = jsondecode(fileread(fullfile(run_dir, 'outputs', 'reprojection', 'reprojection_manifest.json')));
old8 = fullfile(run_dir, 'outputs', 'reprojection_02', 'reprojection_manifest.json');
recorded = isfield(pm8, 'pacing_cycle_ms') && pm8.pacing_cycle_ms == 500 && ...
    isfield(m8.result.reprojection, 'pacing_cycle_ms') && m8.result.reprojection.pacing_cycle_ms == 500;
old_same = isfile(old8) && only_paths_moved(prev_text('reprojection_manifest.json'), fileread(old8), fileparts(old8)) && ...
    ~isfield(jsondecode(fileread(old8)), 'pacing_cycle_ms');
read_back = isequal(tab.report_cycle_length(run_dir, m8), 500);
fld.Value = '';
% Step 2 open: the field and its label in row 12 of the step, no control over another
fig = app.opticalmappingUIFigure;
app.TabGroup.Visible = 'on';
app.TabGroup.SelectedTab = app.recon.ReconstructionTab;
app.recon.reconstruction_set_accordion(2, false);
drawnow;
exportapp(fig, [tempname '.png']);   % lays the window out, as it is drawn
over = ui_control_overlaps(app.recon.ReconstructionTab);
tidy = isempty(over) && fld.Layout.Row == 12 && app.recon.ReconstructionPacingCycleLabel.Layout.Row == 12 && ...
    app.recon.Step2StatusChip.Layout.Row == 13 && fld.Position(3) > 40;
results = add(results, 'P8b Step 2 with the Pacing cycle row: no overlapping controls', tidy, ...
    strjoin(arrayfun(@(e) sprintf('%s: %s x %s', e.container, e.a, e.b), over, 'UniformOutput', false), '; '));
results = add(results, ['P8 Pacing cycle: blank not recorded; 0, negative and text refused; a value recorded in ' ...
    'the new projection record only; Results read it'], blank_ok && refused && threw && kept_value && recorded && ...
    old_same && read_back, sprintf('blank %d refused %d threw %d kept %d recorded %d earlier unchanged %d read %d', ...
    blank_ok, refused, threw, kept_value, recorded, old_same, read_back));

%% P7
[ok7, err7] = tab.commit_run_status(run_id, 'FAILED');
[can3, why3] = tab.can_redo_reprojection(run_id);
results = add(results, 'P7 a FAILED run is not redone', ok7 && ~can3 && contains(why3, 'FAILED'), [err7 ' ' why3]);

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_REPROJECT_REDO RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_reproject_redo:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function select_run(app, rid)
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, rid), 1)};
end


function s = snapshot(run_dir)
% What a redo changes: the manifest, the tab state, the outputs folders
s = struct();
s.manifest = file_hash(fullfile(run_dir, 'manifest.json'));
s.state = file_hash(fullfile(fileparts(fileparts(run_dir)), 'tab-state.json'));
d = dir(fullfile(run_dir, 'outputs'));
s.outputs = sort({d([d.isdir] & ~startsWith({d.name}, '.')).name});
h = hash_dir(fullfile(run_dir, 'outputs', 'reprojection'));
s.reprojection_files = sort(keys(h));
s.reprojection_hashes = values(h, s.reprojection_files);
s.lock = isfile(fullfile(run_dir, 'run.lock'));
end


function t = manifest_texts(folder)
% The projection records' texts, by file name
t = containers.Map();
for n = {'reprojection_manifest.json', 'cv_reprojection_manifest.json'}
    p = fullfile(folder, n{1});
    if isfile(p), t(n{1}) = fileread(p); end
end
end


function ok = kept_unchanged(kept, old_files, old_text, folder)
% Every file kept; the data files byte-identical; each record (manifest)
% differs from the earlier one only in its cdf, ply and video paths, which
% now name the same files in the kept folder
ok = all(isKey(kept, keys(old_files)));
for k = keys(old_files)
    if ~ok, return; end
    if isKey(old_text, k{1})
        ok = only_paths_moved(old_text(k{1}), fileread(fullfile(folder, k{1})), folder);
    else
        ok = strcmp(kept(k{1}), old_files(k{1}));
    end
end
end


function ok = only_paths_moved(old_txt, new_txt, folder)
% new_txt is old_txt with each cdf, ply and video path that names a file of
% folder set to that file there, and nothing else changed (text-exact)
old = jsondecode(old_txt);
new = jsondecode(new_txt);
ok = true;
n_moved = 0;
for f = {'cdf', 'ply', 'video'}
    if ~isfield(old, f{1}) || isempty(old.(f{1})), continue; end
    [~, nm, ex] = fileparts(strrep(char(old.(f{1})), '\', '/'));
    want = fullfile(folder, [nm ex]);
    if ~isfile(want), continue; end
    ok = ok && isfield(new, f{1}) && strcmp(char(new.(f{1})), want);
    new_txt = strrep(new_txt, jsonencode(want), jsonencode(char(old.(f{1}))));
    n_moved = n_moved + 1;
end
ok = ok && n_moved >= 2 && strcmp(new_txt, old_txt);
end


function h = hash_dir(folder)
h = containers.Map();
d = dir(fullfile(folder, '*'));
d = d(~[d.isdir]);
for k = 1:numel(d)
    h(d(k).name) = file_hash(fullfile(folder, d(k).name));
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


function msgs = last_dialogs(n)
dl = getappdata(groot, 'om_headless_dialogs');
msgs = {};
if isempty(dl), return; end
dl = dl(max(1, end - n + 1):end);
msgs = arrayfun(@(e) sprintf('[%s/%s] %s', e.kind, e.answer, e.message), dl, 'UniformOutput', false);
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
