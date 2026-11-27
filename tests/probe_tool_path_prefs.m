function probe_tool_path_prefs
%% Probe: last used tool paths (MATLAB preferences) and their precedence
% Collin Snitchler
% 14.10.2026
% Checks the step 3 tool paths of the Reconstruction tab:
%   P1  an existing path is stored as the last used path and read back
%   P2  a path that does not exist is not stored; the last good one stays
%   P3  an empty path forgets the stored one
%   P4  precedence: typed > dataset (if it exists) > last used (if it
%       exists) > OM_* environment variable (if it exists) > empty
%   P5  a dataset path that no longer exists is passed over with a note,
%       and shown only when nothing else exists
%   P6  a new backend takes its defaults from the last used paths
%   P7  an unknown tool name is refused
%   G1  opening a dataset without saved paths shows the last used paths
%       and the environment default, and saves them for the dataset
%   G2  a saved path that no longer exists is replaced by the last used
%       one, and the step 3 header says so
%   G3  a path typed in the field is stored and wins on the next dataset
%       over that dataset's own saved path
%   G4  Browse... (file and folder) fills the field and stores the path
%   G5  the COLMAP models folder is saved in tab-state.json
%   G6  a stale path with nothing else to show gives the "was not found
%       at" message at Check tools
% The probe changes MATLAB preferences, so it refuses to run unless
% MATLAB_PREFDIR names a throw-away preference folder (and prefdir is that
% folder). Needs OM_APP_HEADLESS=1 for the G checks.
% Usage (set MATLAB_PREFDIR to a new empty folder first):
%   matlab -batch "addpath('<repo>/tests'); probe_tool_path_prefs" -noFigureWindows
pref_env = getenv('MATLAB_PREFDIR');
assert(~isempty(pref_env) && strcmpi(canon(prefdir), canon(pref_env)), ...
    'probe_tool_path_prefs:RealPrefs', ...
    'Set MATLAB_PREFDIR to a throw-away folder: this probe changes MATLAB preferences.');
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

grp = rabbit_reconstruction_tab.tool_pref_group();
if ispref(grp), rmpref(grp); end
env_names = rabbit_reconstruction_tab.tool_path_names();
env_before = cellfun(@getenv, env_names(:, 2), 'UniformOutput', false);
for k = 1:size(env_names, 1), setenv(env_names{k, 2}, ''); end
work = fullfile(tempdir, ['probe_tool_prefs_' char(java.util.UUID.randomUUID())]);
mkdir(work);
cleanup = onCleanup(@() tidy(work, grp, env_names, env_before)); %#ok<NASGU>
results = struct('id', {}, 'ok', {}, 'detail', {});

% Throw-away "tools": the checks only need the files and folders to exist
fake = @(name) make_file(fullfile(work, 'tools', name));
a_exe = fake(fullfile('a', 'colmap.exe'));
b_exe = fake(fullfile('b', 'colmap.exe'));
c_exe = fake(fullfile('c', 'colmap.exe'));
gone = fullfile(work, 'tools', 'moved', 'colmap.exe');
models_dir = fullfile(work, 'tools', 'models');
mkdir(models_dir);

%% P1-P3 store, refuse, forget
ok1 = rabbit_reconstruction_tab.remember_tool_path('colmap_exe', b_exe);
results = add(results, 'P1-round-trip', ok1 && ...
    strcmp(rabbit_reconstruction_tab.last_used_tool_path('colmap_exe'), b_exe) && ...
    strcmp(getpref(grp, 'colmap_exe'), b_exe), rabbit_reconstruction_tab.last_used_tool_path('colmap_exe'));
ok2 = rabbit_reconstruction_tab.remember_tool_path('colmap_exe', gone);
results = add(results, 'P2-missing-not-stored', ~ok2 && ...
    strcmp(rabbit_reconstruction_tab.last_used_tool_path('colmap_exe'), b_exe), ...
    rabbit_reconstruction_tab.last_used_tool_path('colmap_exe'));
ok3 = rabbit_reconstruction_tab.remember_tool_path('colmap_exe', '');
results = add(results, 'P3-empty-forgets', ok3 && ~ispref(grp, 'colmap_exe') && ...
    isempty(rabbit_reconstruction_tab.last_used_tool_path('colmap_exe')), '');

%% P4, P5 precedence
rabbit_reconstruction_tab.remember_tool_path('colmap_exe', b_exe);
setenv('OM_COLMAP_EXE', c_exe);
r = @(typed, saved) resolve3('colmap_exe', typed, saved);
[p, s, n] = r(gone, a_exe);
results = add(results, 'P4-typed-wins', strcmp(p, gone) && strcmp(s, 'typed') && isempty(n), [s ' ' p]);
[p, s, n] = r('', a_exe);
results = add(results, 'P4-dataset-before-last-used', strcmp(p, a_exe) && strcmp(s, 'dataset') && isempty(n), [s ' ' p]);
[p, s, n] = r('', gone);
results = add(results, 'P5-stale-dataset-passed-over', strcmp(p, b_exe) && strcmp(s, 'last used') && ...
    contains(n, 'no longer exists') && contains(n, gone), [s ' ' p ' | ' n]);
[p, s] = r('', '');
results = add(results, 'P4-last-used-before-environment', strcmp(p, b_exe) && strcmp(s, 'last used'), [s ' ' p]);
delete(b_exe);
[p, s] = r('', gone);
results = add(results, 'P4-environment-when-last-used-is-gone', strcmp(p, c_exe) && strcmp(s, 'environment'), [s ' ' p]);
setenv('OM_COLMAP_EXE', '');
[p, s] = r('', gone);
results = add(results, 'P5-stale-shown-when-nothing-exists', strcmp(p, gone) && strcmp(s, 'missing'), [s ' ' p]);
rabbit_reconstruction_tab.remember_tool_path('colmap_exe', '');
[p, s] = r('', '');
results = add(results, 'P4-empty-last', isempty(p) && strcmp(s, 'none'), [s ' ' p]);

%% P6 constructor defaults, P7 unknown tool
b_exe = fake(fullfile('b', 'colmap.exe'));
rabbit_reconstruction_tab.remember_tool_path('colmap_exe', b_exe);
setenv('OM_COLMAP_MODELS', models_dir);
t = rabbit_reconstruction_tab();
results = add(results, 'P6-constructor-defaults', strcmp(t.colmap_exe, b_exe) && ...
    strcmp(t.colmap_models_dir, models_dir) && isempty(t.apd_exe), ...
    sprintf('%s | %s | %s', t.colmap_exe, t.colmap_models_dir, t.apd_exe));
try
    rabbit_reconstruction_tab.remember_tool_path('not_a_tool', b_exe);
    p7 = false;
catch ME
    p7 = strcmp(ME.identifier, 'rabbit_reconstruction_tab:UnknownTool');
end
results = add(results, 'P7-unknown-tool-refused', p7, '');

%% G1 a new dataset shows the last used and environment paths
app = analyse_optical_mapping();
app_cleanup = onCleanup(@() close_app(app)); %#ok<NASGU>
ds1 = open_dataset(app, work, 'ds1', []);
st1 = read_state(ds1);
results = add(results, 'G1-new-dataset-defaults', strcmp(app.recon.ReconstructionColmapField.Value, b_exe) && ...
    strcmp(app.recon.ReconstructionModelsField.Value, models_dir) && isempty(app.recon.ReconstructionApdField.Value) && ...
    strcmp(st1.tool_paths.colmap_exe, b_exe) && strcmp(st1.tool_paths.colmap_models_dir, models_dir), ...
    sprintf('%s | %s', app.recon.ReconstructionColmapField.Value, app.recon.ReconstructionModelsField.Value));

%% G2 a saved path that no longer exists
open_dataset(app, work, 'ds2', struct('colmap_exe', gone));
% The header says the state; the replaced path is named in its tooltip
hdr = strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' ');
results = add(results, 'G2-stale-saved-replaced-with-note', strcmp(app.recon.ReconstructionColmapField.Value, b_exe) && ...
    contains(hdr, 'no longer exists') && contains(hdr, 'COLMAP exe'), ...
    sprintf('%s | %s', app.recon.ReconstructionColmapField.Value, hdr));

%% G3 typed in the field: stored, and wins over another dataset's saved path
f = app.recon.ReconstructionColmapField;
f.Value = c_exe;
feval(f.ValueChangedFcn, f, []);
results = add(results, 'G3-typed-stored', strcmp(rabbit_reconstruction_tab.last_used_tool_path('colmap_exe'), c_exe), ...
    rabbit_reconstruction_tab.last_used_tool_path('colmap_exe'));
open_dataset(app, work, 'ds3', struct('colmap_exe', a_exe));
results = add(results, 'G3-typed-wins-over-dataset', strcmp(app.recon.ReconstructionColmapField.Value, c_exe), ...
    app.recon.ReconstructionColmapField.Value);

%% G4 Browse... for a file and for the models folder
run_py = fake(fullfile('apde', 'run.py'));
headless_push('uigetfile', run_py);
feval(app.recon.ReconstructionRunPyBrowseButton.ButtonPushedFcn, app.recon.ReconstructionRunPyBrowseButton, []);
models2 = fullfile(work, 'tools', 'models2');
mkdir(models2);
headless_push('uigetdir', models2);
feval(app.recon.ReconstructionModelsBrowseButton.ButtonPushedFcn, app.recon.ReconstructionModelsBrowseButton, []);
results = add(results, 'G4-browse-file-and-folder', strcmp(app.recon.ReconstructionRunPyField.Value, run_py) && ...
    strcmp(rabbit_reconstruction_tab.last_used_tool_path('apde_run_py'), run_py) && ...
    strcmp(app.recon.ReconstructionModelsField.Value, models2) && ...
    strcmp(rabbit_reconstruction_tab.last_used_tool_path('colmap_models_dir'), models2), ...
    sprintf('%s | %s', app.recon.ReconstructionRunPyField.Value, app.recon.ReconstructionModelsField.Value));
% nothing queued: the stand-in answers Cancel
feval(app.recon.ReconstructionApdBrowseButton.ButtonPushedFcn, app.recon.ReconstructionApdBrowseButton, []);
results = add(results, 'G4-browse-cancel-changes-nothing', isempty(app.recon.ReconstructionApdField.Value), ...
    app.recon.ReconstructionApdField.Value);

%% G5 the models folder is saved for the dataset
st3 = read_state(fullfile(work, 'ds3.matom'));
results = add(results, 'G5-models-folder-saved', isfield(st3.tool_paths, 'colmap_models_dir') && ...
    strcmp(st3.tool_paths.colmap_models_dir, models2), jsonencode(st3.tool_paths));

%% G6 a stale path and nothing else: Check tools says it was not found
close_app(app);
rabbit_reconstruction_tab.remember_tool_path('colmap_exe', '');
app = analyse_optical_mapping();
app_cleanup = onCleanup(@() close_app(app)); %#ok<NASGU>
open_dataset(app, work, 'ds4', struct('colmap_exe', gone));
feval(app.recon.ReconstructionCheckToolsButton.ButtonPushedFcn, app.recon.ReconstructionCheckToolsButton, []);
results = add(results, 'G6-stale-only-message', strcmp(app.recon.ReconstructionColmapField.Value, gone) && ...
    contains(strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '), 'was not found at') && ...
    contains(strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '), 'COLMAP exe field'), ...
    strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nprobe_tool_path_prefs: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_tool_path_prefs:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end

function [p, s, n] = resolve3(tool, typed, saved)
[p, s, n] = rabbit_reconstruction_tab.resolve_tool_path(tool, typed, saved);
end

function ds = open_dataset(app, root, stem, saved)
%% Bind the app to a dataset, as File > Load file does, with optional saved tool paths
ds = fullfile(root, [stem '.matom']);
if ~isempty(saved)
    st_dir = fullfile(ds, 'reconstruction');
    mkdir(st_dir);
    s = struct('state_schema_version', 1, 'recipe_version', 1, 'tool_paths', saved, 'runs', {{}});
    write_text(fullfile(st_dir, 'tab-state.json'), jsonencode(s));
end
app.file_info = struct('file', fullfile(root, [stem '.fits']), 'path', root, 'name', [stem '.fits'], 'type', '.fits');
app.recon.reconstruction_refresh();
end

function s = read_state(ds)
s = jsondecode(fileread(fullfile(ds, 'reconstruction', 'tab-state.json')));
end

function p = make_file(p)
if ~isfolder(fileparts(p)), mkdir(fileparts(p)); end
write_text(p, 'x');
end

function write_text(p, txt)
fid = fopen(p, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Could not write %s', p);
fwrite(fid, txt, 'char*1');
fclose(fid);
end

function results = add(results, id, ok, detail)
results(end+1) = struct('id', id, 'ok', logical(ok), 'detail', char(detail));
end

function close_app(app)
if isvalid(app), delete(app); end
end

function c = canon(p)
c = char(java.io.File(char(p)).getCanonicalPath());
end

function tidy(work, grp, env_names, env_before)
if ispref(grp), rmpref(grp); end
for k = 1:size(env_names, 1), setenv(env_names{k, 2}, env_before{k}); end
if isfolder(work), rmdir(work, 's'); end
end
