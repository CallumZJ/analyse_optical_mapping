function probe_step2_autofill
%% Probe: the cut fills in the Reconstruction tab's step 2 and the calibration window's list
% Collin Snitchler
% 20.11.2026
% The user: the reconstruction path given when loading and cutting was not
% in the Reconstruction tab, it was unclear which ROI file to give there,
% and the calibration recording was not listed in the calibration window.
%   A1  the cut writes the regions file next to the cut folders,
%       regions_<recording>.json, the next free name on a second cut; it
%       reads back with the bounds, source size, reconstruction path and
%       line-ups of the region dialog
%   A2  after the cut, step 2 holds the cut reconstruction folder and that
%       regions file, and the dataset's tab state keeps them
%   A3  after a restart (empty fields, no cut in this session) step 2 is
%       filled from the tab state
%   A4  the calibration window lists the region dialog's calibration
%       recording already, to fit
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_step2_autofill"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');   % the app must stay hidden
repo_dir = fileparts(fileparts(mfilename('fullpath')));    % the repository folder (this file is in tests/)
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

%% A1 the regions file
d = om_app_double();
d.file_info = struct('file', fullfile(root, 'om.mat'), 'name', 'om.mat', 'path', root, 'type', '.mat');
b4 = [1 1 20 15; 1 16 20 30; 1 31 20 45; 1 46 20 60];
rec_path = fullfile(root, 'rec.fits');
map = struct('type', 'crop', 'camera_stationary', true, 'om_window_in_rec', struct('off', 7, 'cols_off', 0), ...
    'scale', struct('vertical', 1, 'horizontal', 1));
d.data = struct('region_bounds_src', b4, 'cut_output_root', root, 'reconstruction_path', rec_path, ...
    'reconstruction_fov_mapping', map, 'calibration_fov_mapping', [], 'rotation', 3, 'rabbit_panoramic', 1);
p1 = rabbit_cut_tiffs.write_roi_file(d, [20 60]);
p2 = rabbit_cut_tiffs.write_roi_file(d, [20 60]);
rt = rabbit_stack_io.load_roi_json(p1, 20, 60);
record('A1 regions_<recording>.json, the next free name, reads back', ...
    strcmp(p1, fullfile(root, 'regions_om.json')) && strcmp(p2, fullfile(root, 'regions_om_01.json')) && ...
    isequal(double(rt.region_bounds_src), b4) && strcmp(rt.reconstruction_path, rec_path) && ...
    rt.fov_mapping.om_window_in_rec.off == 7, sprintf('%s, %s', p1, p2));

%% A2 step 2 after the cut, kept in the tab state
rng(3, 'twister');
stack = 1000 + 100 * rand(20, 60, 50);                      % a small recording
rec = fullfile(root, 'om.mat');
save(rec, 'stack');
a = analyse_optical_mapping;                                % start the app (hidden)
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', rec);                            % File selector
headless_push('inputdlg', {'500'});                         % Enter fps
headless_push('uiconfirm', 'Continue');                     % no regions
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
cut_dir = fullfile(root, 'cut_tiffs_reconstruction_rec');
mkdir(cut_dir);
a.data.cut_folders_made = struct('reconstruction', struct('stem', 'rec', 'path', cut_dir));
a.data.cut_roi_json = p1;
a.recon.reconstruction_fill_from_cut();
sf = dir(fullfile(root, '**', 'tab-state.json'));         % the dataset's tab state, on disk
has_tab = ~isempty(sf);
st = struct();
if has_tab, st = jsondecode(fileread(fullfile(sf(1).folder, sf(1).name))); end
record('A2 step 2 holds the cut folder and the regions file; the tab state keeps them', ...
    strcmp(a.recon.ReconstructionImagesField.Value, cut_dir) && strcmp(a.recon.ReconstructionRoiField.Value, p1) && ...
    has_tab && isfield(st, 'step2_inputs') && strcmp(st.step2_inputs.images_dir, cut_dir) && ...
    strcmp(st.step2_inputs.roi_json, p1) && strcmp(a.recon.ReconstructionRoiLabel.Text, 'Regions file (written by the cut)'), ...
    sprintf('tab bound %d; %s | %s', has_tab, a.recon.ReconstructionImagesField.Value, a.recon.ReconstructionRoiField.Value));

%% A3 after a restart: from the tab state
a.data = rmfield(a.data, {'cut_folders_made', 'cut_roi_json'});
a.recon.ReconstructionImagesField.Value = '';
a.recon.ReconstructionRoiField.Value = '';
if has_tab
    a.recon.reconstruction_restore_step2_inputs(jsondecode(fileread(fullfile(sf(1).folder, sf(1).name))));
end
record('A3 a restart fills step 2 from the tab state', strcmp(a.recon.ReconstructionImagesField.Value, cut_dir) && ...
    strcmp(a.recon.ReconstructionRoiField.Value, p1), sprintf('%s | %s', a.recon.ReconstructionImagesField.Value, a.recon.ReconstructionRoiField.Value));

%% A4 the calibration window lists the region dialog's calibration recording
cal = fullfile(root, 'cube.tif');
imwrite(zeros(20, 60, 'uint16'), cal);
tab = struct('pycamset_python', '', 'pycamset_checkout', '');
w = rabbit_calibration_dialog(tab, b4, 8000, @() [], [], [20 60], '', p1, [], {cal, fullfile(root, 'missing.tif')});
w_cleanup = onCleanup(@() delete(w.Figure)); %#ok<NASGU>
dt = w.Table.Data;
record('A4 the calibration recording is listed, to fit; a missing one is left out', ...
    size(dt, 1) == 1 && strcmp(dt{1, 1}, cal) && strcmp(dt{1, 2}, 'fit'), sprintf('%d rows', size(dt, 1)));

fprintf('\nPROBE_STEP2_AUTOFILL RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function record(name, ok, detail)
        if ok
            fprintf('PASS %s\n', name); pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail); fail = fail + 1;
        end
    end
end
