function probe_rabbit_gui_walk
%% Probe: the rabbit panoramic GUI walk, headless, on real recordings
% Collin Snitchler
% 14.10.2026
% Replays the steps a user takes in the app for a rabbit panoramic
% recording, pressing the same buttons and menus (their callbacks), with the
% dialog answers queued for the headless stand-ins in tests/helpers/headless:
%   File > Load file (optical mapping FITS) -> Define regions (4, Left,
%   Rabbit panoramic system) -> Load reconstruction stack (first the OM
%   recording itself, which is refused, then the taller FITS from the same
%   camera) -> ROI editor (Load ROI JSON, Save ROI JSON, Regions
%   Selected) -> Cut TIFF copies (Yes, into a chosen folder) -> Processing
%   (clip time, Gaussian 5x5 sigma 1, Butterworth 30 Hz order 5, Select ROI)
%   -> Viewing (Local max normalisation, Invert data) -> Activation map
%   (Activation time, df/dt, 100 %) -> Reconstruction tab steps 1-3 (a stale
%   COLMAP path first, then the real tools). Run is not pressed.
% Needs OM_APP_HEADLESS=1 and these environment variables:
%   OM_RABBIT_WALK_OM    optical mapping FITS (a copy; the dataset folder
%                        <stem>.matom is written next to it)
%   OM_RABBIT_WALK_REC   reconstruction FITS (taller frames, same camera)
%   OM_RABBIT_WALK_ROI   ROI JSON to load in the editor
%   OM_RABBIT_WALK_OUT   new or empty folder for the saved ROI JSON and cuts
%   OM_RABBIT_WALK_CLIP  optional 'start,end' times in s (default 0.166,0.774,
%                        frames 35-159 at 204 fps)
%   OM_COLMAP_EXE, OM_APD_EXE, OM_APDE_RUN_PY, OM_APDE_PYTHON: the tools
% Optional: OM_RABBIT_WALK_CALIBRATION, a JSON list of recordings
% {path, role, type, n_points, edge_mm, size_source}, with OM_PYCAMSET_PYTHON
% and OM_PYCAMSET_CHECKOUT: the walk goes on through Calibrate... (the real
% window) and pyCamSet. OM_RABBIT_WALK_RUN=1 then presses Run too, with the
% calibration chosen, and checks the run ends in mm; expect about 50 min.
% Optional: OM_RABBIT_WALK_STALE_COLMAP, a COLMAP path that no longer
% exists, saved in the dataset's tab state before loading, as a moved or
% deleted install leaves it; OM_RABBIT_WALK_BROKEN_APD, an APD.exe copied
% away from its DLLs, checked before the working one.
% The walk types tool paths, which the app keeps as the last used paths in
% the MATLAB preferences, so MATLAB_PREFDIR must name a throw-away folder.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_rabbit_gui_walk" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')) && strcmpi(char(java.io.File(prefdir).getCanonicalPath()), ...
    char(java.io.File(getenv('MATLAB_PREFDIR')).getCanonicalPath())), ...
    'Set MATLAB_PREFDIR to a throw-away folder: the walk changes MATLAB preferences.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
om_file = getenv('OM_RABBIT_WALK_OM');
rec_file = getenv('OM_RABBIT_WALK_REC');
roi_file = getenv('OM_RABBIT_WALK_ROI');
out = getenv('OM_RABBIT_WALK_OUT');
if isempty(om_file) || isempty(out) || ~(isfile(om_file) && isfile(rec_file) && isfile(roi_file))
    fprintf('SKIP probe_rabbit_gui_walk: set OM_RABBIT_WALK_OM, OM_RABBIT_WALK_REC, OM_RABBIT_WALK_ROI and OM_RABBIT_WALK_OUT.\n');
    return;
end
if ~isfolder(out), mkdir(out); end
assert(numel(dir(out)) <= 2, 'OM_RABBIT_WALK_OUT must be new or empty.');
clip = strsplit(getenv('OM_RABBIT_WALK_CLIP'), ',');
if numel(clip) ~= 2, clip = {'0.166', '0.774'}; end
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
[om_dir, om_stem] = fileparts(om_file);

% Stale tool path saved for the dataset, as a moved COLMAP install leaves it
stale = getenv('OM_RABBIT_WALK_STALE_COLMAP');
if ~isempty(stale)
    st_dir = fullfile(om_dir, [om_stem '.matom'], 'reconstruction');
    if ~isfolder(st_dir), mkdir(st_dir); end
    s = struct('state_schema_version', 1, 'recipe_version', 1, ...
        'tool_paths', struct('colmap_exe', stale, 'apd_exe', getenv('OM_APD_EXE'), ...
        'apde_run_py', getenv('OM_APDE_RUN_PY'), 'apde_python_env', getenv('OM_APDE_PYTHON')), ...
        'runs', {{}});
    write_text(fullfile(st_dir, 'tab-state.json'), jsonencode(s, 'PrettyPrint', true));
end

%% 1. File > Load file, Define regions, reconstruction stack, ROI editor, cut
saved_roi = fullfile(out, 'cut_locations_per_view_saved.json');
cut_root = fullfile(out, 'cut');
mkdir(cut_root);
headless_push('uigetfile', om_file);              % File selector
headless_push('uiconfirm', 'Define regions');     % Define regions or continue?
headless_push('uigetfile', om_file);              % Load reconstruction stack... (wrong file: refused)
headless_push('uigetfile', rec_file);             % Load reconstruction stack...
headless_push('uiconfirm', 'Use it');  % Line up the reconstruction recording
% OM_RABBIT_WALK_CAL_STACK (optional): a calibration recording
% loaded in the region dialog too, for the editor's colour view; one of
% the reconstruction recording's size takes its alignment
cal_stack = getenv('OM_RABBIT_WALK_CAL_STACK');
% OM_RABBIT_WALK_CAL_STACK_SHIFT (optional): 'down,right', the
% shift typed for it against the optical mapping image (a recording of
% another size, as a visiting lab has)
cal_shift = str2num(getenv('OM_RABBIT_WALK_CAL_STACK_SHIFT')); %#ok<ST2NM>
if ~isempty(cal_stack)
    headless_push('uigetfile', cal_stack);        % Load calibration stack...
    if isempty(cal_shift)
        headless_push('uiconfirm', 'Same area as the reconstruction recording');   % Line up the calibration recording
    else
        headless_push('uiconfirm', 'Enter the shift...');
        headless_push('inputdlg', {num2str(cal_shift(1)), num2str(cal_shift(2))});
    end
end
headless_push('uigetfile', roi_file);             % Load ROI JSON...
headless_push('uiputfile', saved_roi);            % Save ROI JSON...
headless_push('uiconfirm', 'Yes');                % Cut TIFF copies?
headless_push('uigetdir', cut_root);              % folder for the TIFF copies
if ~isempty(cal_stack)
    headless_push('uiconfirm', 'Later');          % Calibrate the rig now? (asked after the cut when a calibration recording is loaded)
end
app = analyse_optical_mapping();
cleanup = onCleanup(@() close_app(app)); %#ok<NASGU>
setappdata(groot, 'walk_step', 'region dialog');
setappdata(groot, 'walk_log', {});
t = timer('Period', 0.5, 'ExecutionMode', 'fixedSpacing', 'BusyMode', 'drop', ...
    'TasksToExecute', 2400, 'TimerFcn', @(~, ~) drive_dialogs(app, rec_file));
start(t);
t_load = tic;
try
    feval(app.LoadfileMenu.MenuSelectedFcn, app.LoadfileMenu, []);
    load_err = '';
catch ME
    load_err = getReport(ME, 'basic');
end
stop(t); delete(t);
results = add(results, 'load-and-regions-ran', isempty(load_err), ...
    sprintf('%s (%.0f s)', load_err, toc(t_load)));
walk_log = getappdata(groot, 'walk_log');
results = add(results, 'region-dialog-driven', any(strcmp(walk_log, 'region OK pressed')), strjoin(walk_log, '; '));
dlg = getappdata(groot, 'om_headless_dialogs');
fov = dlg(strcmp({dlg.kind}, 'uiconfirm') & startsWith({dlg.title}, 'Line up the reconstruction'));
% OM_RABBIT_WALK_REC_OFFSET: the row offset expected for the reconstruction
% stack (default 192, the July recordings; another for a cropped copy). The
% measurement is good to 1 px (the still pixels of 30 frames give
% 193 for July, frame 1 alone gave 192)
want_off = str2double(getenv('OM_RABBIT_WALK_REC_OFFSET'));
if ~isfinite(want_off), want_off = 192; end
results = add(results, 'stack-accepted-with-measured-position', ...
    app.data.reconstruction_loaded && ~isempty(app.data.reconstruction_fov_mapping) && ...
    abs(app.data.reconstruction_fov_mapping.om_window_in_rec.off - want_off) <= 1 && numel(fov) == 1, ...
    sprintf('offset %s; question: %s', mat2str(get_off(app)), joined({fov.message})));
wrong = dlg(strcmp({dlg.kind}, 'uialert') & strcmp({dlg.title}, 'Optical mapping recording chosen'));
if ~isempty(cal_stack)
    cq = dlg(strcmp({dlg.kind}, 'uiconfirm') & startsWith({dlg.title}, 'Line up the calibration'));
    % lined up as the reconstruction recording is (the same frame size)
    same = isequal(app.data.calibration_fov_mapping, app.data.reconstruction_fov_mapping) || ...
        (isstruct(app.data.calibration_fov_mapping) && isstruct(app.data.reconstruction_fov_mapping) && ...
        app.data.calibration_fov_mapping.om_window_in_rec.off == app.data.reconstruction_fov_mapping.om_window_in_rec.off);
    if ~isempty(cal_shift)
        % typed against the optical mapping image: the mapping holds it
        same = isstruct(app.data.calibration_fov_mapping) && ...
            app.data.calibration_fov_mapping.om_window_in_rec.off == cal_shift(1);
    end
    results = add(results, 'calibration-stack-loaded-lined-up', app.data.calibration_loaded && same && ...
        numel(cq) == 1, joined({cq.message}));
end
results = add(results, 'om-file-refused-as-reconstruction-stack', numel(wrong) == 1 && ...
    contains(wrong(1).message, 'is the optical mapping recording'), joined({wrong.message}));
errs = dlg(strcmp({dlg.kind}, 'uialert') & ~strcmp({dlg.title}, 'Optical mapping recording chosen') & ...
    ~strcmp({dlg.title}, 'TIFF copies made'));
results = add(results, 'no-alerts-during-load', isempty(errs), joined(strcat({errs.title}, ': ', {errs.message})));
roi_in = rabbit_stack_io.load_roi_json(roi_file, 400, 2000);
results = add(results, 'editor-loaded-roi-json', isequal(app.data.region_bounds_src, roi_in.region_bounds_src), ...
    mat2str(app.data.region_bounds_src));
ok_saved = isfile(saved_roi);
if ok_saved
    rs = rabbit_stack_io.load_roi_json(saved_roi, 400, 2000);
    ok_saved = isequal(rs.region_bounds_src, roi_in.region_bounds_src) && ...
        ~isempty(rs.fov_mapping) && rs.fov_mapping.om_window_in_rec.off == want_off && ...
        strcmp(rs.reconstruction_path, roi_in.reconstruction_path);
end
results = add(results, 'editor-saved-roi-json', ok_saved, saved_roi);
results = add(results, 'regions-applied', app.processed_data.cropped == 1 && ...
    size(app.data.region_bounds, 1) == 4, mat2str(app.data.region_bounds));
om_cut = fullfile(cut_root, ['cut_tiffs_om_' om_stem]);
[~, rec_stem] = fileparts(rec_file);
rec_cut = fullfile(cut_root, ['cut_tiffs_reconstruction_' rec_stem]);
n_om = numel(dir(fullfile(om_cut, '*.tiff')));
n_rec = numel(dir(fullfile(rec_cut, '*.tiff')));
results = add(results, 'cut-into-chosen-folder', n_om == 4 * app.data.n_frames && n_rec == 400 && ...
    ~isfolder(fullfile(om_dir, ['cut_tiffs_om_' om_stem])), sprintf('om %d tiffs, rec %d tiffs', n_om, n_rec));
if isfile(fullfile(rec_cut, 'manifest.json')) && isfile(fullfile(om_cut, 'manifest.json'))
    mr = jsondecode(fileread(fullfile(rec_cut, 'manifest.json')));
    mo = jsondecode(fileread(fullfile(om_cut, 'manifest.json')));
    exp_b = roi_in.region_bounds_src; exp_b(:, [1 3]) = exp_b(:, [1 3]) + want_off;
    results = add(results, 'rec-cut-uses-offset', isequal(mr.roi_bounds.bounds, exp_b), mat2str(mr.roi_bounds.bounds));
    results = add(results, 'om-cut-keeps-counts', strcmp(mo.files(1).policy, 'whole_number_uint16'), mo.files(1).policy);
    first = imread(fullfile(om_cut, sprintf('%s_view1_frame_0001.tiff', om_stem)));
    raw = app.data.image_stack(roi_in.region_bounds_src(1, 1):roi_in.region_bounds_src(1, 3), ...
        roi_in.region_bounds_src(1, 2):roi_in.region_bounds_src(1, 4), 1);
    results = add(results, 'om-cut-equals-loaded-frame', isa(first, 'uint16') && isequal(double(first), raw), class(first));
else
    results = add(results, 'cut-manifests', false, 'manifest.json missing');
end
% The same cut again into the same folder: both folders get _01, the first
% cut stays, and the alert names what was made
first_hash = dir(fullfile(om_cut, '*.tiff'));
headless_push('uigetdir', cut_root);
rabbit_cut_tiffs.cut_inline(app);
d = getappdata(groot, 'om_headless_dialogs');
made = d(strcmp({d.title}, 'TIFF copies made'));
same_old = numel(dir(fullfile(om_cut, '*.tiff'))) == numel(first_hash);
first_new = fullfile([om_cut '_01'], sprintf('%s_view1_frame_0001.tiff', om_stem));
same_new = isfile(first_new) && isequal(imread(first_new), ...
    imread(fullfile(om_cut, sprintf('%s_view1_frame_0001.tiff', om_stem))));
results = add(results, 'repeat-cut-numbered', numel(dir(fullfile([om_cut '_01'], '*.tiff'))) == n_om && ...
    numel(dir(fullfile([rec_cut '_01'], '*.tiff'))) == n_rec && same_old && same_new && numel(made) == 2 && ...
    contains(made(end).message, [rec_stem '_01']) && strcmp(app.data.cut_folders_made.reconstruction.path, [rec_cut '_01']), ...
    joined({made.message}));

try
%% 2. Processing
n0 = app.data.n_frames;
headless_push('inputdlg', clip);
feval(app.clipdata.ButtonPushedFcn, app.clipdata, []);
d = getappdata(groot, 'om_headless_dialogs');
hist = app.history_field.Value;
results = add(results, 'clip-time', app.processed_data.n_frames == 125 && ...
    contains(hist{end}, 'frame 35') && contains(hist{end}, 'frame 159'), ...
    sprintf('%d of %d frames kept; %s; asked: %s', app.processed_data.n_frames, n0, hist{end}, d(end).message));
app.spatialFilterType.Value = '2';
feval(app.spatialFilterType.ValueChangedFcn, app.spatialFilterType, []);
app.spatialkernelsize.Value = '5';
app.gaussiansigma.Value = 1;
feval(app.spatialfilter.ButtonPushedFcn, app.spatialfilter, []);
results = add(results, 'spatial-gaussian-5x5-sigma1', contains(app.history.current, 'GAUSS(5x5, sigma=1.0)'), app.history.current);
app.TemporalFilterType.Value = '1';
feval(app.TemporalFilterType.ValueChangedFcn, app.TemporalFilterType, []);
app.cutofffrequency.Value = 30;
app.filterorder.Value = 5;
feval(app.temporalfilter.ButtonPushedFcn, app.temporalfilter, []);
results = add(results, 'temporal-butterworth-30hz-order5', contains(app.history.current, 'BUTTERWORTH(cutoff30, order=5)'), app.history.current);
app.signalregiontype.Value = 'Rectangle';
H = app.processed_data.height; W = app.processed_data.width;
rect = round([0.30 * W, 0.35 * H, 0.10 * W, 0.30 * H]);   % on the heart in the second view
headless_push('drawrectangle', rect);
feval(app.signalregion.ButtonPushedFcn, app.signalregion, []);
results = add(results, 'select-roi-rectangle', size(app.processed_data.signals, 1) == 1, mat2str(rect));

%% 2b. Assisted area segmentation, default values, before Local max
% normalisation and Invert data. A timer presses
% Confirm area in its window once the window is up.
confirm_t = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, 'StartDelay', 2, ...
    'TimerFcn', @(t, ~) confirm_segmentation(t, app));
start(confirm_t);
main_axes = findall(app.opticalmappingUIFigure, 'Type', 'axes');   % the main window's axes
cmap0 = arrayfun(@(x) {colormap(x)}, main_axes);   % their colour maps before (R4-2)
feval(app.AssistedareasegmentationButton.ButtonPushedFcn, app.AssistedareasegmentationButton, []);
stop(confirm_t); delete(confirm_t);
main_axes = main_axes(isvalid(main_axes));
results = add(results, 'segmentation-keeps-main-colour-map', ...
    isequal(arrayfun(@(x) {colormap(x)}, main_axes), cmap0(1:numel(main_axes))), '');
kp = app.processed_data.keep_area_poly;
results = add(results, 'assisted-area-segmentation', isfield(app.processed_data, 'segmented') && ...
    app.processed_data.segmented && any(isnan(kp(:))), sprintf('%d of %d px kept', nnz(~isnan(kp)), numel(kp)));

%% 3. Viewing
app.localnormalise.Value = true;
feval(app.localnormalise.ValueChangedFcn, app.localnormalise, []);
results = add(results, 'local-max-normalisation', app.display.normalisation == 3, '');
app.invertdata.Value = true;
feval(app.invertdata.ValueChangedFcn, app.invertdata, []);
results = add(results, 'invert-data', app.display.inversion == 1, '');

%% 4. Activation map
app.maptype.Value = '1';
if ~isempty(app.maptype.ValueChangedFcn), feval(app.maptype.ValueChangedFcn, app.maptype, []); end
app.mapmethod.Value = '1';
app.mappercentage.Value = 100;
headless_push('uiconfirm', 'Yes');   % average beats first?
n_dlg = numel(getappdata(groot, 'om_headless_dialogs'));
feval(app.generatemap.ButtonPushedFcn, app.generatemap, []);
d = getappdata(groot, 'om_headless_dialogs');
am = app.processed_data.activation_map;
md = java.security.MessageDigest.getInstance('SHA-256');   % the map's hash as in guide 11.3
md.update(typecast(double(am(:)), 'uint8'));
am_sha = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'))', 1, []));
results = add(results, 'activation-map', ~isempty(am) && any(isfinite(am(:))), ...
    sprintf('map %s, %d finite px, range %.2f-%.2f ms, sha256 %s; dialogs: %s', mat2str(size(am)), nnz(isfinite(am)), ...
    min(am(isfinite(am))), max(am(isfinite(am))), am_sha, ...
    joined(strcat({d(n_dlg + 1:end).title}, ': ', {d(n_dlg + 1:end).message}))));

%% 5. Reconstruction tab, steps 1-3 (Run is not pressed)
exp_ds = fullfile(om_dir, [om_stem '.matom']);
results = add(results, 'step1-dataset', strcmp(app.recon.ReconstructionDatasetField.Value, exp_ds), ...
    [app.recon.ReconstructionDatasetField.Value ' | ' app.recon.StepHeader1.Text]);
headless_push('uigetdir', rec_cut);
feval(app.recon.ReconstructionImagesButton.ButtonPushedFcn, app.recon.ReconstructionImagesButton, []);
headless_push('uigetfile', saved_roi);
feval(app.recon.ReconstructionRoiButton.ButtonPushedFcn, app.recon.ReconstructionRoiButton, []);
results = add(results, 'step2-images-and-roi', strcmp(app.recon.ReconstructionImagesField.Value, rec_cut) && ...
    strcmp(app.recon.ReconstructionRoiField.Value, saved_roi), ...
    sprintf('%s | sparse model: "%s" | %s', app.recon.StepHeader2.Text, app.recon.ReconstructionSparseField.Value, app.recon.Step2StatusChip.Text));
% a rabbit panoramic dataset builds its sparse model by
% default, so images + ROI file + the default recipe complete step 2; on
% the COLMAP fused cloud (default) the run has no APDe-MVS steps (8 steps)
g2 = app.recon.reconstruction_gate_state();
results = add(results, 'step2-builds-sparse-model', ...
    strcmp(app.recon.ReconstructionSparseSourceDropDown.Value, 'built') && g2.step2_ok && ...
    numel(app.recon.ReconstructionStageList.Items) == 8 && ...
    contains(app.recon.ReconstructionStageList.Items{1}, 'Prepare images for the sparse model'), ...
    sprintf('%s | %s | %d steps listed', app.recon.ReconstructionSparseSourceDropDown.Value, g2.step2_note, ...
    numel(app.recon.ReconstructionStageList.Items)));
if ~isempty(stale)
    % a saved path that no longer exists is passed over for the
    % OM_COLMAP_EXE one, with a note in the step 3 header; typed in the
    % field, it is used, and Check tools says it was not found
    results = add(results, 'step3-stale-path-passed-over', ...
        strcmp(app.recon.ReconstructionColmapField.Value, getenv('OM_COLMAP_EXE')) && ...
        contains(strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '), 'no longer exists'), ...
        sprintf('%s | %s', app.recon.ReconstructionColmapField.Value, app.recon.StepHeader3.Text));
    f = app.recon.ReconstructionColmapField;
    f.Value = stale;
    feval(f.ValueChangedFcn, f, []);
    feval(app.recon.ReconstructionCheckToolsButton.ButtonPushedFcn, app.recon.ReconstructionCheckToolsButton, []);
    results = add(results, 'step3-stale-path-message', contains(strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '), 'was not found at') && ...
        contains(strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '), 'COLMAP exe field'), strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '));
end
broken_apd = getenv('OM_RABBIT_WALK_BROKEN_APD');
if ~isempty(broken_apd)
    f = app.recon.ReconstructionColmapField;
    f.Value = getenv('OM_COLMAP_EXE');
    feval(f.ValueChangedFcn, f, []);
    f = app.recon.ReconstructionApdField;
    f.Value = broken_apd;
    feval(f.ValueChangedFcn, f, []);
    % A built run on the dense cloud "COLMAP" has no APDe-MVS steps, so
    % Check tools checks APD.exe only with "APDe-MVS + COLMAP" chosen
    d = app.recon.ReconstructionDenseDropDown;
    d.Value = 'both';
    feval(d.ValueChangedFcn, d, []);
    feval(app.recon.ReconstructionCheckToolsButton.ButtonPushedFcn, app.recon.ReconstructionCheckToolsButton, []);
    results = add(results, 'step3-apd-without-dlls-message', contains(strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '), 'DLL it needs is missing'), strjoin(cellstr(app.recon.StepHeader3.Tooltip), ' '));
    d.Value = 'colmap';
    feval(d.ValueChangedFcn, d, []);
end
tools = {'ReconstructionColmapField', 'OM_COLMAP_EXE'; 'ReconstructionApdField', 'OM_APD_EXE'; ...
    'ReconstructionRunPyField', 'OM_APDE_RUN_PY'; 'ReconstructionPythonField', 'OM_APDE_PYTHON'};
for k = 1:size(tools, 1)
    f = app.recon.(tools{k, 1});
    f.Value = getenv(tools{k, 2});
    feval(f.ValueChangedFcn, f, []);
end
feval(app.recon.ReconstructionCheckToolsButton.ButtonPushedFcn, app.recon.ReconstructionCheckToolsButton, []);
results = add(results, 'step3-check-tools', strcmp(app.recon.StepHeader3.Text, ['3  Tools ' char(8212) ' checked']), app.recon.StepHeader3.Text);
saved_state = jsondecode(fileread(fullfile(exp_ds, 'reconstruction', 'tab-state.json')));
results = add(results, 'step3-paths-saved', strcmp(saved_state.tool_paths.colmap_exe, getenv('OM_COLMAP_EXE')), ...
    saved_state.tool_paths.colmap_exe);
results = add(results, 'step4-run-state', true, sprintf('%s | Run enabled: %s', app.recon.StepHeader4.Text, ...
    char(app.recon.ReconstructionRunButton.Enable)));

%% 6. Calibration (optional)
cal_json = getenv('OM_RABBIT_WALK_CALIBRATION');
if ~isempty(cal_json)
    list = jsondecode(cal_json);
    b = app.recon.ReconstructionCalibrateButton;
    results = add(results, 'calibrate-button-on', strcmp(char(b.Enable), 'on'), char(b.Enable));
    feval(b.ButtonPushedFcn, b, []);
    w = app.recon.reconstruction_calibration_window;
    results = add(results, 'calibration-window', isvalid(w) && w.FocalField.Value == 8000, ...
        sprintf('focal %g px', w.FocalField.Value));
    feval(w.RunButton.ButtonPushedFcn, w.RunButton, []);
    d = getappdata(groot, 'om_headless_dialogs');
    results = add(results, 'calibration-needs-recordings', contains(d(end).message, 'recording'), d(end).message);
    w.PythonField.Value = getenv('OM_PYCAMSET_PYTHON');
    w.CheckoutField.Value = getenv('OM_PYCAMSET_CHECKOUT');
    % OM_RABBIT_WALK_CAL_TYPED (optional): the shift typed in
    % for each recording, as 'down,right;...' in pixels, queued for the
    % window's question when it cannot line the recording up itself
    typed = str2num(getenv('OM_RABBIT_WALK_CAL_TYPED')); %#ok<ST2NM>
    % The window lists the cut's calibration folder already;
    % the walk adds its own list, so that one is taken out first
    prefilled = size(w.Table.Data, 1);
    w.Table.Data = cell(0, size(w.Table.Data, 2));
    w.Places = {};
    results = add(results, 'calibration-window-lists-the-cut', prefilled <= 1, sprintf('%d row(s) listed', prefilled));
    for k = 1:numel(list)
        q = list(k);
        edge = q.edge_mm;
        if k == 1, edge = []; end   % the first try leaves the size out
        n_q = numel(getappdata(groot, 'om_headless_dialogs'));
        if size(typed, 1) >= k
            headless_push('inputdlg', {num2str(typed(k, 1)), num2str(typed(k, 2))});
        end
        w.add_row(q.path, q.role, q.type, q.n_points, edge, q.size_source);
        dk = getappdata(groot, 'om_headless_dialogs');
        if size(typed, 1) >= k && ~any(strcmp({dk(n_q + 1:end).kind}, 'inputdlg'))
            headless_pop('inputdlg');   % not asked: the queued answer is not left for a later question
        end
    end
    % OM_RABBIT_WALK_CAL_OFFSETS (optional): the expected
    % frame position of each recording in the reconstruction frame, as
    % 'row,column;row,column;...' (0-based), for copies cut to another
    % area of interest
    want = getenv('OM_RABBIT_WALK_CAL_OFFSETS');
    if ~isempty(want)
        exp_off = str2num(want); %#ok<ST2NM>
        got = cell2mat(cellfun(@(p) reshape(p.offset, 1, 2), w.Places(:), 'UniformOutput', false));
        results = add(results, 'calibration-recordings-placed', isequal(got, exp_off), ...
            sprintf('%s | %s', mat2str(got), strjoin(w.Table.Data(:, 6)', ' | ')));
    end
    % With the region dialog's typed line-up, the first recording is placed
    % from it, not asked
    if ~isempty(cal_shift)
        results = add(results, 'calibration-placed-from-region-dialog', ...
            strcmp(w.Places{1}.source, 'region dialog'), sprintf('%s: %s', w.Places{1}.source, w.Places{1}.note));
    end
    feval(w.RunButton.ButtonPushedFcn, w.RunButton, []);
    d = getappdata(groot, 'om_headless_dialogs');
    results = add(results, 'calibration-needs-the-size', contains(d(end).message, 'no default'), d(end).message);
    data = w.Table.Data;
    data{1, 5} = list(1).edge_mm;
    w.Table.Data = data;
    t0 = tic;
    feval(w.RunButton.ButtonPushedFcn, w.RunButton, []);
    v = jsondecode(fileread(fullfile(w.LastDir, 'verdict.json')));
    results = add(results, 'calibration-verdict', w.LastOk && v.metric_allowed, sprintf('%s in %.0f s: %s', v.status, ...
        toc(t0), strjoin(w.ResultsArea.Value, ' | ')));
    results = add(results, 'calibration-tiles-removed', ~isfolder(fullfile(w.LastDir, 'tiles')) && ...
        isfile(fullfile(w.LastDir, 'cameras.camset')), w.LastDir);
    feval(w.CloseButton.ButtonPushedFcn, w.CloseButton, []);
    [~, cal_id] = fileparts(w.LastDir);
    dd = app.recon.ReconstructionCalibrationDropDown;
    results = add(results, 'calibration-offered', any(strcmp(dd.ItemsData, cal_id)), strjoin(dd.Items, ' | '));
    dd.Value = cal_id;
    feval(dd.ValueChangedFcn, dd, []);
    % OM_RABBIT_WALK_PYCAMSET_GUI=1 (optional): Open in
    % pyCamSet... on this calibration (the GUI is built and closed again:
    % OM_PYCAMSET_GUI_DRY_RUN), then Link camera set... with the
    % calibration's own camera set, which must come back as a passed
    % calibration and be chosen
    if strcmp(getenv('OM_RABBIT_WALK_PYCAMSET_GUI'), '1')
        setenv('OM_PYCAMSET_GUI_DRY_RUN', '1');
        gb = app.recon.ReconstructionPycamsetGuiButton;
        feval(gb.ButtonPushedFcn, gb, []);
        gdirs = dir(fullfile(w.LastDir, '..', 'pycamset_gui', [cal_id '*']));
        glog = '';
        if ~isempty(gdirs)
            gl = fullfile(gdirs(end).folder, gdirs(end).name, 'pycamset_gui.log');
            t1 = tic;
            while toc(t1) < 120 && ~(isfile(gl) && contains(fileread(gl), 'PYCAMSET_GUI_READY')), pause(2); end
            if isfile(gl), glog = strtrim(fileread(gl)); end
        end
        results = add(results, 'pycamset-gui-opens-at-phase-1', contains(glog, 'tab="Phase 1') && contains(glog, '"type": "PuzzleBoardCube"'), glog);
        headless_push('uigetfile', fullfile(w.LastDir, 'cameras.camset'));
        cb = app.recon.ReconstructionCamsetButton;
        feval(cb.ButtonPushedFcn, cb, []);
        results = add(results, 'camset-linked-and-chosen', contains(dd.Value, '_camset_') && ...
            strcmp(app.recon.ReconstructionCamsetField.Value, fullfile(w.LastDir, 'cameras.camset')), ...
            sprintf('%s | %s', dd.Value, strjoin(dd.Items, ' | ')));
    end
end

%% 7. Run with the calibration (optional)
if strcmp(getenv('OM_RABBIT_WALK_RUN'), '1')
    % Same numbers, same rig: the first frame's camera positions decide
    % OM_RABBIT_WALK_SEEDED=1 (optional): the dataset folder
    % already holds a run (the known-turns check), so the app first asks
    % whether to add to it
    if strcmp(getenv('OM_RABBIT_WALK_SEEDED'), '1')
        headless_push('uiconfirm', 'Add to this folder');
    end
    headless_push('uiconfirm', 'Map only');
    t0 = tic;
    feval(app.recon.ReconstructionRunButton.ButtonPushedFcn, app.recon.ReconstructionRunButton, []);
    rid = app.recon.reconstruction_selected_run_id();
    run_dir = fullfile(exp_ds, 'reconstruction', 'runs', rid);
    run_tab = rabbit_reconstruction_tab();
    [st_ok, st_err] = run_tab.load_state(om_dir, om_stem);
    assert(st_ok, st_err);
    m = run_tab.read_manifest(run_dir);
    results = add(results, 'run-finished', strcmp(m.result.status, 'COMPLETED'), ...
        sprintf('%s in %.1f min, run %s', m.result.status, toc(t0) / 60, rid));
    results = add(results, 'run-results-text', true, strjoin(app.recon.ReconstructionResultsText.Value, ' | '));
    ms = run_tab.run_metric(run_dir);
    if ~isempty(cal_json)
        results = add(results, 'run-in-mm', ~isempty(ms) && ms.applied, jsonencode(ms));
        ps = fullfile(run_dir, 'outputs', 'metric', 'pixel_size.json');
        results = add(results, 'run-pixel-size', isfile(ps), fileread_or_empty(ps));
    else
        results = add(results, 'run-in-model-units', isempty(ms), 'no calibration record');
    end
end

catch ME
    results = add(results, 'walk-aborted', false, getReport(ME, 'basic'));
end

%% Summary
d = getappdata(groot, 'om_headless_dialogs');
fprintf('\nDialogs seen (%d):\n', numel(d));
for k = 1:numel(d)
    fprintf('  [%s] %s: %s -> %s\n', d(k).kind, d(k).title, d(k).message, d(k).answer);
end
n_pass = sum([results.ok]);
fprintf('\n');
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nprobe_rabbit_gui_walk: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
write_text(fullfile(out, 'walk_results.json'), jsonencode(struct('results', results, 'dialogs', d), 'PrettyPrint', true));
if n_pass ~= numel(results)
    error('probe_rabbit_gui_walk:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end

function t = fileread_or_empty(p)
t = '';
if isfile(p), t = fileread(p); end
end

function drive_dialogs(app, rec_file) %#ok<INUSD>
%% Answer the region dialog and the ROI editor as the user would
% Runs on a timer while the app waits in uiwait (headless stand-in).
try
    step = getappdata(groot, 'walk_step');
    switch step
        case 'region dialog'
            cb = findall(groot, 'Type', 'uicheckbox', 'Text', 'Rabbit panoramic system');
            if isempty(cb), return; end
            fig = ancestor(cb(1), 'figure');
            % The dialog makes its Load buttons after the check box: wait
            % until it is complete (a fast load once raced past it)
            if isempty(findall(fig, 'Type', 'uibutton', 'Text', 'Load calibration stack...')) || ...
                    isempty(findall(fig, 'Type', 'uibutton', 'Text', 'Load reconstruction stack...')) || ...
                    isempty(findall(fig, 'Type', 'uilabel'))
                return;
            end
            n = findall(fig, 'Type', 'uinumericeditfield');
            n.Value = 4;
            feval(n.ValueChangedFcn, n, []);
            side = findall(fig, 'Type', 'uidropdown');
            side.Value = side.ItemsData{strcmp(side.Items, 'Left')};
            cb.Value = true;
            feval(cb.ValueChangedFcn, cb, []);
            b = findall(fig, 'Type', 'uibutton', 'Text', 'Load reconstruction stack...');
            feval(b.ButtonPushedFcn, b, []);   % the OM recording itself: refused
            feval(b.ButtonPushedFcn, b, []);   % the reconstruction recording
            if ~isempty(getenv('OM_RABBIT_WALK_CAL_STACK'))
                bc = findall(fig, 'Type', 'uibutton', 'Text', 'Load calibration stack...');
                feval(bc.ButtonPushedFcn, bc, []);   % the calibration recording
            end
            label = findall(fig, 'Type', 'uilabel');
            log_step(sprintf('dialog labels: %s', strjoin(string({label.Text}), ' | ')));
            ok = findall(fig, 'Type', 'uibutton', 'Text', 'OK');
            setappdata(groot, 'walk_step', 'editor');
            log_step('region OK pressed');
            feval(ok.ButtonPushedFcn, ok, []);
        case 'editor'
            % Wait until define_regions waits for the editor, so the editor
            % is complete before its buttons are pressed
            if ~isappdata(app.opticalmappingUIFigure, 'om_headless_waiting') || ...
                    ~getappdata(app.opticalmappingUIFigure, 'om_headless_waiting')
                return;
            end
            ed = findall(groot, 'Type', 'figure', 'Name', 'Rabbit panoramic ROI editor');
            if isempty(ed), return; end
            press(ed, 'Load ROI JSON...');
            press(ed, 'Save ROI JSON...');
            setappdata(groot, 'walk_step', 'done');
            log_step('editor Regions Selected pressed');
            press(ed, 'Regions Selected');
    end
catch ME
    log_step(['driver error: ' ME.message]);
    setappdata(groot, 'walk_step', 'failed');
    uiresume(app.opticalmappingUIFigure);
    delete(findall(groot, 'Type', 'figure', 'Name', 'Define regions'));
end
end

function press(fig, text)
b = findall(fig, 'Type', 'uibutton', 'Text', text);
feval(b.ButtonPushedFcn, b, []);
end

function log_step(msg)
l = getappdata(groot, 'walk_log');
l{end + 1} = msg;
setappdata(groot, 'walk_log', l);
fprintf('walk: %s\n', msg);
end

function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', char(detail));
end

function s = joined(c)
if isempty(c), s = ''; else, s = strjoin(cellstr(c), ' || '); end
end

function off = get_off(app)
off = [];
m = app.data.reconstruction_fov_mapping;
if ~isempty(m), off = m.om_window_in_rec.off; end
end

function write_text(path, txt)
f = fopen(path, 'w', 'n', 'UTF-8');
fprintf(f, '%s\n', txt);
fclose(f);
end

function confirm_segmentation(t, ~)
% Presses Confirm area in the assisted segmentation window, as a user
% keeping the default values would, once the window has finished starting
% (its reconstruction checkbox is made at the end of its start-up), then
% stops its timer
ready = findall(groot, 'Type', 'uicheckbox', 'Text', 'Apply these settings to the reconstruction images');
if isempty(ready), return; end
b = findall(ancestor(ready(1), 'figure'), 'Type', 'uibutton');
b = b(startsWith(string(get(b, {'Text'})), 'Confirm area'));   % its text ends with an icon
if isempty(b), return; end
stop(t);
feval(b(1).ButtonPushedFcn, b(1), []);
end

function close_app(app)
if isvalid(app)
    delete(app);
end
end
