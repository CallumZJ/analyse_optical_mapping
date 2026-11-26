function probe_om_alignment_image
%% Probe: the projection check uses the OM frame as cut, not the processed one
% Collin Snitchler
% 03.11.2026
% Assisted area segmentation sets the OM pixels outside its polygons to
% NaN, and the projection check took the heart outline from the mean of
% the processed stack, so the outline rule split the heart itself (July:
% outline match 0.76, 0.67, 0.66, 0.91, step 8 stopped).
% rabbit_rhythm_reproject.om_image_from_app now gives the first loaded
% frame as the regions cut it. This probe replays the GUI steps headless on
% a copy of a dataset whose run failed at step 8 that way (its OM FITS
% may be cut to the frames that run loaded: File > Load file partially
% cannot be driven headless): File > Load file, Define regions (4, Left, Rabbit panoramic, reconstruction stack,
% ROI JSON), Cut TIFF copies (No), the segmentation of the failed run (its
% kept area, read from its saved OM image), clip time, Gaussian 5x5 sigma
% 1, Butterworth 30 Hz order 5, Select ROI, Local max normalisation,
% Invert data, Generate map, then Resume on the run (step 8 only).
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder and:
%   OM_ALIGN_OM    OM FITS inside the dataset copy (<stem>.matom next to it)
%   OM_ALIGN_REC   reconstruction FITS (taller frames, same camera)
%   OM_ALIGN_ROI   ROI JSON
%   OM_ALIGN_RUN   run id of the copy's run that failed at step 8
% Usage: matlab -batch "addpath('<repo>/tests'); probe_om_alignment_image" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
om_file = getenv('OM_ALIGN_OM');
rec_file = getenv('OM_ALIGN_REC');
roi_file = getenv('OM_ALIGN_ROI');
run_id = getenv('OM_ALIGN_RUN');
[om_dir, om_stem] = fileparts(om_file);
run_dir = fullfile(om_dir, [om_stem '.matom'], 'reconstruction', 'runs', run_id);
if isempty(om_file) || isempty(run_id) || ~(isfile(om_file) && isfile(rec_file) && isfile(roi_file) && isfolder(run_dir))
    fprintf('SKIP probe_om_alignment_image: set OM_ALIGN_OM, OM_ALIGN_REC, OM_ALIGN_ROI and OM_ALIGN_RUN.\n');
    return;
end
% The probe resumes the run (step 8), so it works on a copy under tempdir:
% the three files and <stem>.matom; the given ones are only read. The copy
% is removed when the probe ends, also after an error or a half-finished copy
scratch = [tempname '_probe_om_alignment_image'];
scratch_cleanup = onCleanup(@() rmdir_if_there(scratch)); %#ok<NASGU>
mkdir(scratch);
copyfile(fullfile(om_dir, [om_stem '.matom']), fullfile(scratch, [om_stem '.matom']));
[om_file, rec_file, roi_file] = deal(copy_into(om_file, scratch), copy_into(rec_file, scratch), copy_into(roi_file, scratch));
om_dir = scratch;
run_dir = fullfile(om_dir, [om_stem '.matom'], 'reconstruction', 'runs', run_id);
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
kept = isfinite(saved.om_image);
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% 1. Load, regions, no cut
headless_push('uigetfile', om_file);              % File selector
headless_push('uiconfirm', 'Define regions');     % Define regions or continue?
headless_push('uigetfile', rec_file);             % Load reconstruction stack...
headless_push('uiconfirm', 'Use it');  % Line up the reconstruction recording
headless_push('uigetfile', roi_file);             % Load ROI JSON...
headless_push('uiconfirm', 'No');                 % Cut TIFF copies?
app = analyse_optical_mapping();
cleanup = onCleanup(@() close_app(app)); %#ok<NASGU>
setappdata(groot, 'align_step', 'region dialog');
t = timer('Period', 0.5, 'ExecutionMode', 'fixedSpacing', 'BusyMode', 'drop', ...
    'TasksToExecute', 2400, 'TimerFcn', @(~, ~) drive_dialogs(app));
start(t);
feval(app.LoadfileMenu.MenuSelectedFcn, app.LoadfileMenu, []);
stop(t); delete(t);
cut_frame = app.first_processed_frame;
results = add(results, 'regions-applied', isequal(size(cut_frame), size(kept)) && all(isfinite(cut_frame(:))), ...
    sprintf('canvas %s, kept area %s', mat2str(size(cut_frame)), mat2str(size(kept))));

fprintf('probe: regions done\n');
%% 2. Segmentation of the failed run: the app's own Keep area arithmetic
mask = double(kept);
mask(mask == 0) = NaN;
app.processed_data.keep_area_poly = mask;
app.processed_data.image_stack{1} = app.processed_data.image_stack{1} .* mask;
app.history.current = [app.history.current, 'Background extracted with assisted area segmentation'];

fprintf('probe: segmentation applied\n');
%% 3. Processing, viewing, map (the guide's settings)
headless_push('inputdlg', {'0.166', '0.774'});
feval(app.clipdata.ButtonPushedFcn, app.clipdata, []);
app.spatialFilterType.Value = '2';
feval(app.spatialFilterType.ValueChangedFcn, app.spatialFilterType, []);
app.spatialkernelsize.Value = '5';
app.gaussiansigma.Value = 1;
feval(app.spatialfilter.ButtonPushedFcn, app.spatialfilter, []);
app.TemporalFilterType.Value = '1';
feval(app.TemporalFilterType.ValueChangedFcn, app.TemporalFilterType, []);
app.cutofffrequency.Value = 30;
app.filterorder.Value = 5;
feval(app.temporalfilter.ButtonPushedFcn, app.temporalfilter, []);
H = app.processed_data.height; W = app.processed_data.width;
headless_push('drawrectangle', round([0.30 * W, 0.35 * H, 0.10 * W, 0.30 * H]));
feval(app.signalregion.ButtonPushedFcn, app.signalregion, []);
app.localnormalise.Value = true;
feval(app.localnormalise.ValueChangedFcn, app.localnormalise, []);
app.invertdata.Value = true;
feval(app.invertdata.ValueChangedFcn, app.invertdata, []);
app.maptype.Value = '1';
if ~isempty(app.maptype.ValueChangedFcn), feval(app.maptype.ValueChangedFcn, app.maptype, []); end
app.mapmethod.Value = '1';
app.mappercentage.Value = 100;
headless_push('uiconfirm', 'Yes');   % average beats first?
feval(app.generatemap.ButtonPushedFcn, app.generatemap, []);
am = app.processed_data.activation_map;
results = add(results, 'activation-map', isequal(size(am), size(kept)) && any(isfinite(am(:))), mat2str(size(am)));

fprintf('probe: map made\n');
%% 4. The OM image the check gets
old = mean(double(app.processed_data.image_stack{1}), 3, 'omitnan');
img = rabbit_rhythm_reproject.om_image_from_app(app);
results = add(results, 'old-image-was-masked', mean(~isfinite(old(:))) > 0.5, ...
    sprintf('%.1f %% NaN in the processed mean', 100 * mean(~isfinite(old(:)))));
results = add(results, 'image-is-cut-frame', isequal(img, double(cut_frame)), ...
    sprintf('%.1f %% NaN', 100 * mean(~isfinite(img(:)))));
mirrored = app.history.current;
app.history.current = [mirrored, 'Image mirrored'];
fb = rabbit_rhythm_reproject.om_image_from_app(app);
app.history.current = mirrored;
results = add(results, 'mirror-falls-back-without-nan', ~isequal(fb, double(cut_frame)) && all(isfinite(fb(:))), ...
    sprintf('%.1f %% NaN', 100 * mean(~isfinite(fb(:)))));

fprintf('probe: image checks done\n');
for k = 1:numel(results)
    fprintf('probe: %s %d %s\n', results(k).id, results(k).ok, results(k).detail);
end
%% 5. Resume the failed run (step 8 only): what the Resume button calls
% The run list and progress window are left out (they wait on figures
% headless); the pipeline gets the options the Resume button passes.
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(om_dir, om_stem);
results = add(results, 'tab-state-loaded', ok, err);
[ok, err] = tab.resume_run(run_id);
results = add(results, 'resume-accepted', ok, err);
if ok
    tab.commit_run_status(run_id, 'RUNNING');
    fprintf('probe: running step 8\n');
    [ok, err] = tab.run_pipeline(run_id, struct('start_stage', 'reprojection', ...
        'om_rows_flipped', strcmpi(app.file_info.type, '.fits'), ...
        'view_numbering', app.recon.ReconstructionViewNumberingDropDown.Value, ...
        'activation_map', app.processed_data.activation_map, ...
        'om_image', rabbit_rhythm_reproject.om_image_from_app(app), ...
        'om_pose_frame', app.recon.ReconstructionOmPoseFrameDropDown.Value, ...
        'activation_source', 'probe_om_alignment_image (headless)', ...
        'analysis_parameters', struct('note', 'GUI defaults; probe_om_alignment_image')));
    log = fileread(fullfile(run_dir, 'logs', 'reprojection.log'));
    lines = strsplit(strtrim(log), newline);
    results = add(results, 'step8-not-failed', ok && ~contains(lines{end}, 'FAILED'), ...
        sprintf('%s | %s', err, lines{end}));
end

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nprobe_om_alignment_image: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_om_alignment_image:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end

function drive_dialogs(app)
%% Answer the region dialog and the ROI editor as the user would
try
    switch getappdata(groot, 'align_step')
        case 'region dialog'
            cb = findall(groot, 'Type', 'uicheckbox', 'Text', 'Rabbit panoramic system');
            if isempty(cb), return; end
            fig = ancestor(cb(1), 'figure');
            n = findall(fig, 'Type', 'uinumericeditfield');
            n.Value = 4;
            feval(n.ValueChangedFcn, n, []);
            side = findall(fig, 'Type', 'uidropdown');
            side.Value = side.ItemsData{strcmp(side.Items, 'Left')};
            cb.Value = true;
            feval(cb.ValueChangedFcn, cb, []);
            b = findall(fig, 'Type', 'uibutton', 'Text', 'Load reconstruction stack...');
            feval(b.ButtonPushedFcn, b, []);
            ok = findall(fig, 'Type', 'uibutton', 'Text', 'OK');
            setappdata(groot, 'align_step', 'editor');
            feval(ok.ButtonPushedFcn, ok, []);
        case 'editor'
            if ~isappdata(app.opticalmappingUIFigure, 'om_headless_waiting') || ...
                    ~getappdata(app.opticalmappingUIFigure, 'om_headless_waiting')
                return;
            end
            ed = findall(groot, 'Type', 'figure', 'Name', 'Rabbit panoramic ROI editor');
            if isempty(ed), return; end
            press(ed, 'Load ROI JSON...');
            setappdata(groot, 'align_step', 'done');
            press(ed, 'Regions Selected');
    end
catch ME
    fprintf('driver error: %s\n', ME.message);
    setappdata(groot, 'align_step', 'failed');
    uiresume(app.opticalmappingUIFigure);
    delete(findall(groot, 'Type', 'figure', 'Name', 'Define regions'));
end
end

function press(fig, text)
b = findall(fig, 'Type', 'uibutton', 'Text', text);
feval(b.ButtonPushedFcn, b, []);
end

function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', char(detail));
end

function close_app(app)
if isvalid(app)
    delete(app);
end
end


function p = copy_into(file, folder)
% A copy of file in folder, under the same name
[~, name, ext] = fileparts(file);
p = fullfile(folder, [name ext]);
copyfile(file, p);
end


function rmdir_if_there(p)
if ~isfolder(p), return; end
try
    rmdir(p, 's');
catch ME
    warning('probe_om_alignment_image:Cleanup', 'Could not remove %s: %s', p, ME.message);
end
end
