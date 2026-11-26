function probe_rhythm_marker
%% Probe: the loaded recording is marked Sinus rhythm, Paced (with its cycle) or Not stated
% Collin Snitchler
% 25.11.2026
% File > Recording rhythm marks the loaded recording; Step 2's Pacing cycle
% shows and edits the same cycle; the marker is kept with the workspace and
% recorded with each projection (recording_rhythm). Display and labelling
% only. Driven headless through the app's own callbacks.
%   R1  default: a newly loaded recording is Not stated; History and the
%       top line say so; File > Recording rhythm... follows Load file
%       partially; Step 2 is blank; no question is asked headless
%   R2  the question is put once per recording while Not stated (first
%       CV map or projection), with the options Sinus rhythm / Paced... /
%       Not stated, and again after a new load; never with
%       OM_APP_HEADLESS=1
%   R3  Paced with a cycle (the question, "Paced...", "2 Hz"): 500 ms (2
%       Hz) in History, the top line and Step 2; typing 400 in Step 2
%       changes the marker (one value); the projection's record gets it
%       (recording_rhythm) and Results read it back in their own row
%       layout; a projection made before the marker with only a pacing
%       cycle reads "as recorded with the run"
%   R3b (with OM_REDO_DS, OM_REDO_STEM, OM_REDO_RUN as probe_reproject_redo)
%       a real Redo projection records it in reprojection_manifest.json and
%       the run manifest, and the Results box shows the Rhythm row
%   R4  workspaces: save_workspace keeps the marker; a workspace saved
%       before the marker existed loads as Not stated
%   R5  mismatch, on the near-simultaneous warning's own basis (each view's
%       IQR against SIMULTANEOUS_IQR_MS): marked Paced and every view
%       nearly simultaneous gives a caution with the CV map's warning (alert
%       and History), in Results and in the Visualise CV caption; none for
%       a wider map or for Sinus rhythm (which says "apparent speed"); the
%       CV map is the same marked or not
%   R6  headless/batch: set_recording_rhythm sets it without a dialog; a
%       bad cycle or state is refused; Sinus rhythm (no cycle) makes Step 2
%       not editable; Not stated again clears it
% Needs OM_APP_HEADLESS=1 and MATLAB_PREFDIR set to a throw-away folder.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_rhythm_marker" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
tmp = tempname;
mkdir(tmp);
tmp_cleanup = onCleanup(@() rmdir(tmp, 's'));
RR = 'rabbit_recording_rhythm';
H = 40; Wr = 30;
ramp = @(spread) repmat(linspace(0, spread / 0.9, Wr), H, 1) + 50;   % 5-95 % about the given spread

app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app));
fld = app.recon.ReconstructionPacingCycleField;

%% R1 a newly loaded recording is Not stated
load_synthetic(app, tmp, H, Wr);
r0 = app.recording_rhythm();
menu = findall(app.FileMenu, 'Tag', 'RecordingRhythmMenu');
shown = flipud(app.FileMenu.Children);
k_part = find(shown == app.LoadfilepartiallyMenu, 1);
menu_ok = isscalar(menu) && ~isempty(k_part) && numel(shown) > k_part && shown(k_part + 1) == menu;
hist = app.history_field.Value;
top = char(strjoin(cellstr(app.tool_tip.Value), ' '));
n0 = numel(getappdata(groot, 'om_headless_dialogs'));
feval([RR '.ask_once'], app);
asked = numel(getappdata(groot, 'om_headless_dialogs')) > n0;
results = add(results, ['R1 a new recording is Not stated: History, top line, menu after Load file partially, ' ...
    'Step 2 blank, no question headless'], strcmp(r0.state, 'not_stated') && ...
    any(strcmp(hist, 'Rhythm: Not stated (mark it with File > Recording rhythm)')) && ...
    contains(top, 'Rhythm: Not stated (File > Recording rhythm)') && isempty(fld.Value) && ...
    strcmp(fld.Editable, 'on') && ~asked && menu_ok, sprintf('state %s | top "...%s" | asked %d | menu %d', ...
    r0.state, top(max(1, end - 60):end), asked, menu_ok));

%% R2 the question once per recording (first CV map or projection), never headless
setenv('OM_APP_HEADLESS', '0');   % only for ask_once's own gate: the dialogs are still the stand-ins
restore_env = onCleanup(@() setenv('OM_APP_HEADLESS', '1'));
setappdata(groot, 'om_headless_dialogs', []);
headless_push('uiconfirm', 'Not stated');
feval([RR '.ask_once'], app);
feval([RR '.ask_once'], app);   % asked already: no second question
n_first = n_questions();
dl = getappdata(groot, 'om_headless_dialogs');
first_msg = '';
if ~isempty(dl), first_msg = dl(end).message; end
rabbit_recording_rhythm.reset(app);   % a new recording
headless_push('uiconfirm', 'Not stated');
feval([RR '.ask_once'], app);
n_new = n_questions();
app.set_recording_rhythm('Sinus rhythm');
feval([RR '.ask_once'], app);   % marked: no question
n_marked = n_questions();
setenv('OM_APP_HEADLESS', '1');
clear restore_env
rabbit_recording_rhythm.reset(app);
feval([RR '.ask_once'], app);
n_headless = n_questions();
results = add(results, 'R2 asked once per recording while Not stated, again after a new load, never headless', ...
    n_first == 1 && n_new == 2 && n_marked == 2 && n_headless == 2 && contains(first_msg, 'sinus rhythm or paced'), ...
    sprintf('questions: first %d, new load %d, marked %d, headless %d | "%s"', n_first, n_new, n_marked, n_headless, ...
    strrep(first_msg, newline, ' / ')));

%% R3 Paced with a cycle: question -> marker -> Step 2 -> projection record -> Results
headless_push('uiconfirm', 'Paced...');
headless_push('inputdlg', {'2 Hz'});
rabbit_recording_rhythm.ask(app);
r2 = app.recording_rhythm();
hist = app.history_field.Value;
top = char(strjoin(cellstr(app.tool_tip.Value), ' '));
marked = strcmp(r2.state, 'paced') && abs(r2.pacing_cycle_ms - 500) < 1e-9 && r2.pacing_hz == 2 && ...
    strcmp(r2.stated_as, 'Hz') && strcmp(hist{end}, 'Rhythm marked: Paced, 500 ms cycle, 2 Hz, pacing site not known (as stated)') && ...
    contains(top, 'Rhythm: Paced, 500 ms cycle, 2 Hz, pacing site not known (as stated)');
step2_val = fld.Value;
step2_shows = strcmp(step2_val, '500') && isequal(app.recon.reconstruction_pacing_cycle_value(), 500);
fld.Value = '400';
fld.ValueChangedFcn(fld, struct('Value', '400', 'PreviousValue', '500'));
r2b = app.recording_rhythm();
step2_edits = strcmp(r2b.state, 'paced') && r2b.pacing_cycle_ms == 400 && strcmp(r2b.source, 'Step 2') && ...
    contains(app.history_field.Value{end}, 'Paced, 400 ms cycle, pacing site not known (as stated in Step 2)');
app.set_recording_rhythm('Paced', 500);
rec = app.recon.reconstruction_recording_rhythm();
tab = rabbit_reconstruction_tab();
passed = tab.reprojection_recording_rhythm(struct('recording_rhythm', rec, 'pacing_cycle_ms', 500));
run_dir = fake_run(tmp, 'run', struct('pacing_cycle_ms', 500, 'recording_rhythm', passed));
rr = tab.report_rhythm(run_dir, struct());
row = tab.results_row(struct('tag', '', 'label', 'Rhythm', 'text', rabbit_recording_rhythm.words(rr), 'limit', ''));
cyc = tab.report_cycle_length(run_dir, struct());
recorded = isequal(passed, rec) && strcmp(rec.state, 'paced') && rec.pacing_cycle_ms == 500 && ...
    ~isfield(rec, 'asked') && ~isfield(rec, 'suggestion') && strcmp(rr.state, 'paced') && rr.pacing_cycle_ms == 500 && ...
    isequal(cyc, 500) && strcmp(strtrim(row{1}), 'Rhythm      Paced, 500 ms cycle, pacing site not known (as stated)') && ...
    all(cellfun(@numel, row) <= rabbit_reconstruction_tab.RESULTS_WIDTH);
old_dir = fake_run(tmp, 'old', struct('pacing_cycle_ms', 500));
legacy = strcmp(rabbit_recording_rhythm.words(tab.report_rhythm(old_dir, struct())), ...
    'Paced, 500 ms cycle, pacing site not known (as recorded with the run)');
none_dir = fake_run(tmp, 'none', struct('n_faces', 1));
none_ok = strcmp(rabbit_recording_rhythm.words(tab.report_rhythm(none_dir, struct())), 'Not stated');
results = add(results, ['R3 Paced with a cycle: marker, History, top line, Step 2 shows and edits it, ' ...
    'the projection record and Results read it'], marked && step2_shows && step2_edits && recorded && legacy && none_ok, ...
    sprintf('marked %d step2 "%s" edits %d recorded %d (row "%s") legacy %d none %d', ...
    marked, step2_val, step2_edits, recorded, strtrim(row{1}), legacy, none_ok));

%% R3b a real Redo projection (optional inputs)
src_root = getenv('OM_REDO_DS');
if isempty(src_root)
    fprintf('SKIP R3b: set OM_REDO_DS, OM_REDO_STEM and OM_REDO_RUN (as for probe_reproject_redo) to run it\n');
else
    results = add_redo(results, getenv('OM_REDO_STEM'), getenv('OM_REDO_RUN'));
end

%% R4 workspaces
app.set_recording_rhythm('Paced', 500);
app.SavetoEditField.Value = [tmp filesep];
app.file_info.name = 'probe';
try
    before = dir(fullfile(tmp, '*.mat'));
    app.saveworkspace.MenuSelectedFcn(app.saveworkspace, []);
    after = dir(fullfile(tmp, '*.mat'));
    ws = fullfile(tmp, setdiff({after.name}, {before.name}));
    ws = ws{1};
    saved = load(ws, 'data_int');
    kept = isfield(saved.data_int, 'rhythm') && strcmp(saved.data_int.rhythm.state, 'paced') && ...
        saved.data_int.rhythm.pacing_cycle_ms == 500;
    % The same workspace as one saved before the marker existed
    old_ws = fullfile(tmp, 'old_workspace.mat');
    copyfile(ws, old_ws);
    mf = matfile(old_ws, 'Writable', true);
    mf.data_int = rmfield(saved.data_int, 'rhythm');
    clear mf;
    headless_push('uigetfile', old_ws);
    app.loadworkspace.MenuSelectedFcn(app.loadworkspace, []);
    ro = app.recording_rhythm();
    old_ok = strcmp(ro.state, 'not_stated') && ...
        any(contains(app.history_field.Value, 'Rhythm (from the workspace): Not stated')) && isempty(fld.Value);
    headless_push('uigetfile', ws);
    app.loadworkspace.MenuSelectedFcn(app.loadworkspace, []);
    rw = app.recording_rhythm();
    new_ok = strcmp(rw.state, 'paced') && rw.pacing_cycle_ms == 500 && strcmp(fld.Value, '500');
    detail = sprintf('kept %d old %d new %d (%s)', kept, old_ok, new_ok, ws);
catch ME
    kept = false; old_ok = false; new_ok = false;
    detail = ME.message;
end
results = add(results, 'R4 workspaces: the marker is saved; an old workspace loads as Not stated', ...
    kept && old_ok && new_ok, detail);

%% R5 the mismatch caution, on the near-simultaneous warning's basis (display only)
% a fresh recording: the workspace above changed the map's size
load_synthetic(app, tmp, H, Wr);
app.processed_data.scale = 258;
app.CV_method.Value = 'Bayly Method';
app.set_recording_rhythm('Not stated');
[cv_unset, al_unset] = press_cv(app, ramp(4));
app.set_recording_rhythm('Paced', 500);
[cv_paced, al_paced] = press_cv(app, ramp(4));
hist = app.history_field.Value;
% the limit is the map's size / 3 mm/ms, named per view;
% said in physics words
caution_words = ['Caution: Marked as paced, but every view activates nearly simultaneously (middle half within ' ...
    'the time it takes at 1.5 m/s, view size / 3: the map '];
cv_ok = isscalar(al_paced) && startsWith(al_paced{1}, 'Most of the map activates at almost the same moment') && ...   % plain words
    contains(al_paced{1}, caution_words) && any(startsWith(hist, caution_words)) && ...
    isscalar(al_unset) && ~contains(al_unset{1}, 'Caution') && isequaln(cv_unset, cv_paced);
[~, al_wide] = press_cv(app, ramp(60));
wide_ok = isempty(al_wide) && isempty(rabbit_recording_rhythm.mismatch(app.recording_rhythm(), ...
    app.processed_data.CV_activation_spread));
% CV mean: the rhythm lines
press_cv(app, ramp(4));
n0 = numel(getappdata(groot, 'om_headless_dialogs'));
app.CVmean.ButtonPushedFcn(app.CVmean, []);
dl = getappdata(groot, 'om_headless_dialogs');
mean_msg = '';
if numel(dl) > n0, mean_msg = dl(end).message; end
mean_ok = contains(mean_msg, 'Rhythm: Paced, 500 ms cycle, pacing site not known (as stated)') && contains(mean_msg, caution_words);
% the median leads, the mean comes after the
% count above 3 m/s, and the rhythm lines stay after them
at = @(w) min([strfind(mean_msg, w), Inf]);   % first position, Inf when absent
mean_ok = mean_ok && startsWith(mean_msg, 'Median: ') && isfinite(at('Above 1.5 m/s')) && ...
    at('Above 1.5 m/s') < at('Absolute mean') && at('Absolute mean') < at('Rhythm: Paced');
% Results and the Visualise CV caption, from the records
spread = app.processed_data.CV_activation_spread;
mm_dir = fake_run(tmp, 'mismatch', struct('recording_rhythm', rabbit_recording_rhythm.record(app.recording_rhythm(), spread)));
write_text(fullfile(mm_dir, 'outputs', 'reprojection', 'cv_reprojection_manifest.json'), ...
    jsonencode(struct('activation_spread', spread)));
[rm, sm] = tab.report_rhythm(mm_dir, struct());
results_caution = rabbit_recording_rhythm.mismatch(rm, sm);
fig = uifigure('Visible', 'off', 'UserData', struct('run_id', 'probe', 'run_dir', mm_dir));
fig_cleanup = onCleanup(@() delete(fig));
p = struct('source_path', fullfile(mm_dir, 'outputs', 'reprojection', 'cv_projected.cdf'), ...
    'info', struct('scalar', [0.5; 0.6; 0.7]));
[~, caveats] = tab.viewer_cv_caption(fig, p);
caption_ok = any(strcmp(caveats, 'Rhythm: Paced, 500 ms cycle, pacing site not known (as stated)')) && any(startsWith(caveats, caution_words));
app.set_recording_rhythm('Sinus rhythm');
lines = rabbit_recording_rhythm.cv_lines(app.recording_rhythm(), spread);
sinus_ok = numel(lines) == 2 && contains(lines{2}, 'CV is an apparent speed, not conduction speed') && ...
    contains(lines{2}, 'middle half within the time it takes at 1.5 m/s, view size / 3') && ...
    isempty(rabbit_recording_rhythm.mismatch(app.recording_rhythm(), spread));
results = add(results, ['R5 marked Paced but every view nearly simultaneous (IQR basis): a caution with the CV ' ...
    'warning, in CV mean, Results and the CV caption; none wider or for Sinus rhythm; the CV map unchanged'], ...
    cv_ok && wide_ok && mean_ok && startsWith(['Caution: ' results_caution], caution_words) && caption_ok && sinus_ok, ...
    sprintf('cv %d wide %d mean %d results "%s" caption %d sinus %d | "%s"', cv_ok, wide_ok, mean_ok, ...
    results_caution, caption_ok, sinus_ok, strrep(strjoin(al_paced, ' '), newline, ' / ')));

%% R6 headless / batch
n0 = numel(getappdata(groot, 'om_headless_dialogs'));
app.set_recording_rhythm('Paced', '2 Hz');
hz_ok = app.recording_rhythm().pacing_cycle_ms == 500 && strcmp(fld.Value, '500');
threw = false;
try
    app.set_recording_rhythm('Paced', 'fast');
catch ME
    threw = strcmp(ME.identifier, 'analyse_om:Rhythm:BadCycle') && contains(ME.message, '2 Hz');
end
unchanged = app.recording_rhythm().pacing_cycle_ms == 500;
bad_state = false;
try
    app.set_recording_rhythm('irregular');
catch ME
    bad_state = strcmp(ME.identifier, 'analyse_om:Rhythm:BadState');
end
app.set_recording_rhythm('Sinus rhythm', 500);   % no cycle for sinus rhythm
rs = app.recording_rhythm();
sinus_locked = strcmp(fld.Editable, 'off') && isempty(fld.Value) && isempty(rs.pacing_cycle_ms) && ...
    isempty(app.recon.reconstruction_pacing_cycle_value());
app.set_recording_rhythm('Not stated');
cleared = strcmp(app.recording_rhythm().state, 'not_stated') && strcmp(fld.Editable, 'on') && isempty(fld.Value);
no_dialogs = numel(getappdata(groot, 'om_headless_dialogs')) == n0;
results = add(results, ['R6 headless: set_recording_rhythm without a dialog; bad cycle and state refused; ' ...
    'Sinus rhythm has no cycle and locks Step 2; Not stated clears it'], hz_ok && threw && unchanged && bad_state && ...
    sinus_locked && cleared && no_dialogs, sprintf('hz %d threw %d unchanged %d state %d sinus %d cleared %d no dialogs %d', ...
    hz_ok, threw, unchanged, bad_state, sinus_locked, cleared, no_dialogs));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_RHYTHM_MARKER RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_rhythm_marker:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_rhythm_marker %d/0\n', n_pass);
end


function load_synthetic(app, folder, H, W)
% File > Load file with a small synthetic recording (the variable 'stack')
stack = 1000 + 100 * rand(H, W, 30);
rec = fullfile(folder, sprintf('synthetic_%s.mat', char(datetime('now', 'Format', 'HHmmssSSS'))));
save(rec, 'stack');
headless_push('uigetfile', rec);
headless_push('inputdlg', {'204.0136'});
headless_push('uiconfirm', 'Continue');
feval(app.LoadfileMenu.MenuSelectedFcn, app.LoadfileMenu, []);
end


function n = n_questions()
% The rhythm questions put so far (headless stand-ins record them)
dl = getappdata(groot, 'om_headless_dialogs');
n = 0;
if ~isempty(dl), n = nnz(strcmp({dl.title}, 'Recording rhythm') & strcmp({dl.kind}, 'uiconfirm')); end
end


function [cv, alerts] = press_cv(app, map)
% The CV map button, as the user presses it (Bayly, the tab's defaults)
setappdata(groot, 'om_headless_dialogs', []);
app.processed_data.activation_map = map;
app.display.image_handle.Parent.CLim = [0, max(map(:))];
headless_push('uiconfirm', 'Yes');
feval(app.CV_map.ButtonPushedFcn, app.CV_map, []);
cv = app.processed_data.CV_map;
dl = getappdata(groot, 'om_headless_dialogs');
alerts = {};
if ~isempty(dl), alerts = {dl(strcmp({dl.title}, 'CV map') & strcmp({dl.kind}, 'uialert')).message}; end
end


function run_dir = fake_run(root, name, pm)
% A run folder with only a projection record (reprojection_manifest.json)
run_dir = fullfile(root, name, 'run');
mkdir(fullfile(run_dir, 'outputs', 'reprojection'));
write_text(fullfile(run_dir, 'outputs', 'reprojection', 'reprojection_manifest.json'), jsonencode(pm));
end


function write_text(path, txt)
fid = fopen(path, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', txt);
fclose(fid);
end


function results = add_redo(results, stem, run_id)
% Redo projection of a COMPLETED run's copy, marked Paced 500 ms (a copy of
% the copy, under tempdir, as probe_reproject_redo)
[root, cleanup] = om_redo_copy('probe_rhythm_marker', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
om_image(~isfinite(om_image)) = min(om_image(isfinite(om_image)));
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app));
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(root, stem);
assert(ok, err);
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root, stem);
app.file_info.path = root;
app.file_info.name = [rabbit_reconstruction_tab.recording_stem(root, stem) '.fits'];
app.file_info.type = '.fits';
rng(7, 'twister');
app.processed_data.activation_map = 20 + 30 * rand(size(om_image));
app.processed_data.image_stack = {repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, [])};
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.set_recording_rhythm('Paced', 500);
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map only');
app.recon.ReconstructionReprojectButtonPushed();
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
pm = jsondecode(fileread(fullfile(run_dir, 'outputs', 'reprojection', 'reprojection_manifest.json')));
txt = strjoin(app.recon.ReconstructionResultsText.Value, newline);
ok = isfield(pm, 'recording_rhythm') && strcmp(pm.recording_rhythm.state, 'paced') && ...
    pm.recording_rhythm.pacing_cycle_ms == 500 && pm.pacing_cycle_ms == 500 && ...
    isfield(m.result.reprojection, 'recording_rhythm') && ...
    contains(txt, 'Rhythm      Paced, 500 ms cycle, pacing site not known (as stated)');
results = add(results, 'R3b a real Redo projection records the marker; Results show it', ok, ...
    strrep(txt, newline, ' / '));
end


function results = add(results, id, ok, detail)
results(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
