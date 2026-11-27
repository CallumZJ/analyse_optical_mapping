function probe_repeat_outputs
%% Probe: doing a process again makes the next free name and replaces nothing
% Collin Snitchler
% 02.11.2026
% A dataset that has been through a step before must not block the step:
%   N1-N6  the naming rule: free, taken, _01 taken, a gap, a file, _99 to _100,
%          several names sharing one number, extensions, dots in names
%   C1     a repeat cut goes to _01, the earlier folder is unchanged
%   C2     the two folders of one cut keep the same number, also when only
%          one of them was taken (cut_inline, the folder dialog answered)
%   C3     the folder made is recorded, and the cut tells the user
%   F1-F2  find_cut_folder: the folder made first, else the newest that fits
%          the ROIs, else none (a later cut then takes the next free name)
%   M1     the masks tool reads the numbered cut and a repeat makes _01
%   R1     Reproject from files keeps an earlier projection
%   D1-D5  dataset folders: the recording of a folder, the next name, the
%          folders of a recording, the run count, row flip through <stem>_01
%   A1-A5  the app: Step 1 choice, a new folder leaves the runs alone, the
%          activation map still belongs, the question before a run (keep,
%          new, cancel), a run opened from <stem>_01.matom
% Needs OM_APP_HEADLESS=1 (no windows). No data files.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_repeat_outputs" -noFigureWindows
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
pass = 0; fail = 0;
root = tempname(tempdir);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));

    function check(id, ok, detail)
        fprintf('%s: %s -> %s\n', id, detail, char(70 + 14 * logical(ok)));
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end

%% naming rule
n = fullfile(root, 'names');
mkdir(n);
next = @(b) rabbit_stack_io.next_free_suffix(n, b);
s1 = next('a');
mkdir(fullfile(n, 'a'));
s2 = next('a');
check('N1', isempty(s1) && strcmp(s2, '_01'), sprintf('free "%s", taken "%s"', s1, s2));
mkdir(fullfile(n, 'a_01'));
check('N2', strcmp(next('a'), '_02'), next('a'));
mkdir(fullfile(n, 'a_03'));
mkdir(fullfile(n, 'a_02'));
rmdir(fullfile(n, 'a_01'));
check('N3', strcmp(next('a'), '_01'), sprintf('gap at _01: %s', next('a')));
write_text(fullfile(n, 'b'), 'x');
check('N4', strcmp(next('b'), '_01'), sprintf('a file counts as taken: %s', next('b')));
mkdir(fullfile(n, 'c'));
for k = 1:99
    mkdir(fullfile(n, sprintf('c_%02d', k)));
end
check('N5', strcmp(next('c'), '_100'), sprintf('after _99: %s', next('c')));
mkdir(fullfile(n, 'p'));
mkdir(fullfile(n, 'q'));
mkdir(fullfile(n, 'q_01'));
pair = rabbit_stack_io.next_free_suffix(n, {'p', 'q'});
single_q = rabbit_stack_io.next_free_suffix(n, {'p', 'free'});
write_text(fullfile(n, 'r.json'), '{}');
j1 = rabbit_stack_io.next_free_suffix(n, 'r', '.json');
d1 = rabbit_stack_io.next_free_path(fullfile(n, 'v1.5'));
mkdir(d1);
d2 = rabbit_stack_io.next_free_path([fullfile(n, 'v1.5') filesep]);
check('N6', strcmp(pair, '_02') && strcmp(single_q, '_01') && strcmp(j1, '_01') && ...
    endsWith(d2, 'v1.5_01'), sprintf('pair %s, one taken %s, json %s, dotted %s', pair, single_q, j1, d2));

%% a repeat cut
c = fullfile(root, 'cuts');
mkdir(c);
app = om_app_double();
app.file_info = struct('file', 'om.fits', 'name', 'om.fits', 'path', c, 'type', '.fits');
stack = uint16(reshape(1:40 * 60 * 3, 40, 60, 3));
app.data = struct('image_stack', stack, 'height', 40, 'width', 60, 'rabbit_panoramic', 1, ...
    'region_bounds_src', [1 1 40 10; 1 12 40 22; 1 24 40 34; 1 36 40 46], 'cut_output_root', c);
bounds = app.data.region_bounds_src;
ok1 = rabbit_cut_tiffs.cut_om(app, bounds, [40 60]);
base = fullfile(c, 'cut_tiffs_om_om');
marker = fullfile(base, 'marker.txt');
write_text(marker, 'earlier cut');
before = dir(base);
ok2 = rabbit_cut_tiffs.cut_om(app, bounds, [40 60]);
after = dir(base);
check('C1', ok1 && ok2 && isfolder([base '_01']) && numel(before) == numel(after) && ...
    strcmp(strtrim(fileread(marker)), 'earlier cut') && ...
    numel(dir(fullfile([base '_01'], '*.tiff'))) == 12, ...
    sprintf('second cut in %s, first left alone', app.data.cut_folders_made.om.path));
check('C3a', strcmp(app.data.cut_folders_made.om.path, [base '_01']), app.data.cut_folders_made.om.path);

% one cut, two folders, only the reconstruction name taken
p = fullfile(root, 'pair');
mkdir(p);
rec = fullfile(root, 'rec.tif');
for k = 1:2
    imwrite(uint16(k * ones(80, 60)), rec, 'WriteMode', pick(k == 1, 'overwrite', 'append'));
end
mkdir(fullfile(p, 'cut_tiffs_reconstruction_rec'));
app2 = om_app_double();
app2.file_info = struct('file', 'om.fits', 'name', 'om.fits', 'path', p, 'type', '.fits');
app2.data = app.data;
app2.data = rmfield(app2.data, {'cut_folders_made', 'cut_output_root'});
app2.data.reconstruction_path = rec;
app2.data.reconstruction_fov_mapping = struct('type', 'crop', 'camera_stationary', true, ...
    'om_window_in_rec', struct('off', 20, 'cols_off', 0), 'scale', struct('vertical', 1, 'horizontal', 1));
headless_push('uigetdir', p);
ok = rabbit_cut_tiffs.cut_inline(app2);
check('C2', ok && isfolder(fullfile(p, 'cut_tiffs_om_om_01')) && isfolder(fullfile(p, 'cut_tiffs_reconstruction_rec_01')) && ...
    ~isfolder(fullfile(p, 'cut_tiffs_om_om')), 'both folders _01 though only the reconstruction name was taken');
headless_push('uigetdir', p);
ok = rabbit_cut_tiffs.cut_inline(app2);
check('C2b', ok && isfolder(fullfile(p, 'cut_tiffs_om_om_02')) && isfolder(fullfile(p, 'cut_tiffs_reconstruction_rec_02')), ...
    app2.data.cut_folders_made.reconstruction.path);
src = fileread(which('rabbit_cut_tiffs'));
check('C3b', contains(src, 'TIFF copies made') && ~contains(src, 'rmdir(out_root') && ~contains(src, 'existing_outputs'), ...
    'the cut tells the folder, and has no code that removes an output folder');

%% consumers find the folder actually made
b4 = app2.data.region_bounds_src;
stem = 'rec';
f1 = rabbit_cut_tiffs.find_cut_folder(app2, 'reconstruction', stem, b4);
app3 = om_app_double();
app3.file_info = app2.file_info;
app3.data = rmfield(app2.data, 'cut_folders_made');
f2 = rabbit_cut_tiffs.find_cut_folder(app3, 'reconstruction', stem, b4);
check('F1', strcmp(f1, fullfile(p, 'cut_tiffs_reconstruction_rec_02')) && strcmp(f2, f1), ...
    sprintf('made folder %s; after a restart %s', f1, f2));
wrong = b4;
wrong(:, 3) = wrong(:, 3) - 5;
f3 = rabbit_cut_tiffs.find_cut_folder(app3, 'reconstruction', stem, wrong);
b_old = b4;
mkdir(fullfile(p, 'cut_tiffs_reconstruction_rec_03'));   % newest number, no images: passed over
f4 = rabbit_cut_tiffs.find_cut_folder(app3, 'reconstruction', stem, b_old);
check('F2', isempty(f3) && strcmp(f4, f1), sprintf('no cut of other ROI sizes ("%s"); empty _03 passed over: %s', f3, f4));

%% masks: the numbered cut, and a repeat keeps the first masks
js = fullfile(root, 'roi.json');
payload = struct('schema_version', 1, 'region_bounds_src', b4, 'regions', 4, 'rotation', 3, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', 40, 'width', 60), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, 'reconstruction_path', rec, ...
    'fov_mapping', app2.data.reconstruction_fov_mapping);
rabbit_stack_io.save_roi_json(js, payload);
m = rabbit_segmentation_masks([], js, app3);
r1 = m.apply('Threshold', 0.5, 'Sigma', 1);
r2 = m.apply('Threshold', 0.5, 'Sigma', 1);
check('M1', r1.ok && r2.ok && endsWith(r1.mask_root, 'masks_reconstruction_rec') && ...
    endsWith(r2.mask_root, 'masks_reconstruction_rec_01') && isfolder(r1.mask_root) && ...
    strcmp(fileparts(r1.written{1}), r1.mask_root) && strcmp(fileparts(r1.sources{1}), f1), ...
    sprintf('%s, then %s, from %s', r1.mask_root, r2.mask_root, fileparts(r1.sources{1})));
txt = fileread(which('rabbit_segmentation_preview'));
check('M2', contains(txt, 'find_cut_folder') && contains(fileread(which('rabbit_segmentation_masks')), 'find_cut_folder'), ...
    'preview and masks both look the cut up');

%% Reproject from files
o = fullfile(root, 'proj');
mkdir(o);
o1 = rabbit_rhythm_reproject.free_output_folder(o);
mkdir(o1);
write_text(fullfile(o1, 'activation_projected.ply'), 'old');
o2 = rabbit_rhythm_reproject.free_output_folder(o);
check('R1', strcmp(o1, fullfile(o, 'reprojection')) && strcmp(o2, fullfile(o, 'reprojection_01')), ...
    sprintf('a folder of its own: %s, then %s', o1, o2));

%% dataset folders
d = fullfile(root, 'ds');
mkdir(d);
tab = 'rabbit_reconstruction_tab';
write_text(fullfile(d, 'rec.fits'), 'x');
write_text(fullfile(d, 'foo.fits'), 'x');
write_text(fullfile(d, 'foo_01.fits'), 'x');
rs = @(s) feval([tab '.recording_stem'], d, s);
check('D1', strcmp(rs('rec'), 'rec') && strcmp(rs('rec_01'), 'rec') && strcmp(rs('rec_123'), 'rec') && ...
    strcmp(rs('foo_01'), 'foo_01') && strcmp(rs('other_01'), 'other_01') && strcmp(rs('rec_1'), 'rec_1'), ...
    'numbered folder -> recording; own recording wins; unknown stays');
n1 = rabbit_reconstruction_tab.next_dataset_stem(d, 'rec');
n2 = rabbit_reconstruction_tab.next_dataset_stem(d, 'foo');
mkdir(fullfile(d, 'rec.matom'));
mkdir(fullfile(d, 'rec_01.matom'));
mkdir(fullfile(d, 'rec_03.matom'));
mkdir(fullfile(d, 'rec_x.matom'));
n3 = rabbit_reconstruction_tab.next_dataset_stem(d, 'rec');
check('D2', strcmp(n1, 'rec_01') && strcmp(n2, 'foo_02') && strcmp(n3, 'rec_02'), ...
    sprintf('%s; %s skips the recording foo_01; gap %s', n1, n2, n3));
st = rabbit_reconstruction_tab.dataset_stems(d, 'rec');
check('D3', isequal(st, {'rec', 'rec_01', 'rec_03'}), strjoin(st, ', '));
mkdir(fullfile(d, 'rec.matom', 'reconstruction', 'runs', 'a'));
mkdir(fullfile(d, 'rec.matom', 'reconstruction', 'runs', 'b'));
check('D4', rabbit_reconstruction_tab.dataset_run_count(d, 'rec') == 2 && ...
    rabbit_reconstruction_tab.dataset_run_count(d, 'rec_01') == 0, 'runs counted');
t = rabbit_reconstruction_tab();
t.load_state(d, 'rec_01');
[flip1, why1] = t.om_row_flip(struct(), fullfile(d, 'none.json'));
check('D5', flip1 == true, sprintf('row flip through rec_01.matom: %s', why1));

%% the app
g = fullfile(root, 'gui');
mkdir(g);
write_text(fullfile(g, 'case.fits'), 'x');
ids = {'20261102T120000_0a0a0a0a'};
rec_dir = fullfile(g, 'case.matom', 'reconstruction');
make_run(fullfile(rec_dir, 'runs', ids{1}), ids{1}, g);
state = struct('state_schema_version', 1, 'recipe_version', 1, 'runs', ...
    struct('id', ids{1}, 'status', 'FAILED', 'created_at', '2026-11-02T12:00:00'));
write_text(fullfile(rec_dir, 'tab-state.json'), jsonencode(state, 'PrettyPrint', true));
a = analyse_optical_mapping();
close_a = onCleanup(@() delete(a));
a.file_info.path = [g filesep];
a.file_info.file = 'case.fits';
a.file_info.name = 'case';
a.file_info.type = '.fits';
a.recon.reconstruction_refresh();
dd = a.recon.ReconstructionDatasetFolderDropDown;
check('A1', numel(dd.Items) == 2 && contains(dd.Items{1}, 'case.matom (1 run)') && ...
    contains(dd.Items{2}, 'case_01.matom') && strcmp(char(dd.Enable), 'on') && strcmp(dd.Value, 'case'), ...
    strjoin(dd.Items, ' / '));
state_before = fileread(fullfile(rec_dir, 'tab-state.json'));
dd.Value = 'case_01';
feval(dd.ValueChangedFcn, dd, []);
exp_ds = fullfile(a.file_info.path, 'case_01.matom');
check('A2', strcmp(a.recon.ReconstructionDatasetField.Value, exp_ds) && ...
    isfile(fullfile(g, 'case_01.matom', 'reconstruction', 'tab-state.json')) && ...
    strcmp(fileread(fullfile(rec_dir, 'tab-state.json')), state_before) && ...
    isfolder(fullfile(rec_dir, 'runs', ids{1})) && isempty(a.recon.ReconstructionRunList.Items), ...
    sprintf('bound to %s; earlier run and tab state unchanged', a.recon.ReconstructionDatasetField.Value));
a.processed_data.activation_map = ones(4);
check('A3', a.recon.reconstruction_map_matches_dataset(), 'the activation map still belongs in case_01.matom');
dd.Value = 'case';
feval(dd.ValueChangedFcn, dd, []);
items = a.recon.ReconstructionRunList.Items;
check('A4', strcmp(a.recon.ReconstructionDatasetField.Value, fullfile(a.file_info.path, 'case.matom')) && ...
    numel(items) == 1 && contains(items{1}, ids{1}), 'back in case.matom: the earlier run is listed');
go1 = a.recon.reconstruction_offer_new_dataset_folder();
kept = strcmp(a.recon.ReconstructionDatasetField.Value, fullfile(a.file_info.path, 'case.matom'));
headless_push('uiconfirm', 'Cancel');
go2 = a.recon.reconstruction_offer_new_dataset_folder();
headless_push('uiconfirm', 'Start new folder');
go3 = a.recon.reconstruction_offer_new_dataset_folder();
dlg = getappdata(groot, 'om_headless_dialogs');
asked = dlg(strcmp({dlg.title}, 'Reconstruction run'));
% go3 is false: the run gate is asked again after the new folder and no
% inputs are set here; the folder itself is bound
check('A5', go1 && kept && ~go2 && ~go3 && numel(asked) == 4 && strcmp(asked(1).answer, 'Add to this folder') && ...
    strcmp(a.recon.ReconstructionDatasetField.Value, fullfile(a.file_info.path, 'case_02.matom')), ...
    sprintf('default keeps, Cancel stops, new gives %s; asked: %s', a.recon.ReconstructionDatasetField.Value, asked(1).message));
go4 = a.recon.reconstruction_offer_new_dataset_folder();
check('A6', go4 && numel(getappdata(groot, 'om_headless_dialogs')) == numel(dlg), ...
    'a folder without runs is not asked about');
% a run kept in a further folder opens from its manifest
id2 = '20261102T130000_0b0b0b0b';
rec2 = fullfile(g, 'case_01.matom', 'reconstruction');
make_run(fullfile(rec2, 'runs', id2), id2, g);
state.runs = struct('id', id2, 'status', 'FAILED', 'created_at', '2026-11-02T13:00:00');
write_text(fullfile(rec2, 'tab-state.json'), jsonencode(state, 'PrettyPrint', true));
a.recon.test_manifest_pick = fullfile(rec2, 'runs', id2, 'manifest.json');
a.recon.OpenReconstructionManifestMenuSelected();
check('A7', strcmp(a.recon.reconstruction_selected_run_id(), id2) && endsWith(a.recon.ReconstructionDatasetField.Value, 'case_01.matom') && ...
    strcmp(a.recon.ReconstructionDatasetFolderDropDown.Value, 'case_01'), ...
    sprintf('run %s open from %s', a.recon.reconstruction_selected_run_id(), a.recon.ReconstructionDatasetField.Value));

fprintf('PROBE_REPEAT_OUTPUTS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_repeat_outputs %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_repeat_outputs\n');
    error('probe_repeat_outputs:Failed', '%d check(s) failed.', fail);
end
end

function v = pick(c, a, b)
if c, v = a; else, v = b; end
end

function write_text(path, txt)
f = fopen(path, 'w', 'n', 'UTF-8');
fwrite(f, txt, 'char');
fclose(f);
end

function make_run(run_dir, run_id, root)
% A FAILED run with a dense cloud and a mesh (no reprojection), v1 manifest
out_dir = fullfile(run_dir, 'outputs');
mkdir(out_dir);
write_text(fullfile(out_dir, 'fused-geometric.ply'), sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 0\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n']));
write_text(fullfile(out_dir, 'mesh-cleanup.ply'), sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 1\nproperty list uchar int vertex_indices\nend_header\n10 0 0\n11 0 0\n10 1 0\n3 0 1 2\n']));
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = run_id;
m.dataset = struct('role', 'reconstruction', 'path', root);
m.inputs = struct('files', []);
m.stages = struct('name', {'mesh_cleanup', 'alignment'}, 'status', {'WARNED', 'FAILED'}, ...
    'started_at', {'2026-10-15T12:00:00', '2026-10-15T12:01:00'}, ...
    'finished_at', {'2026-10-15T12:01:00', '2026-10-15T12:02:00'});
m.result = struct('status', 'FAILED');
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m, 'PrettyPrint', true));
end
