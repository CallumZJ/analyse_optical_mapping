function probe_export_visuals
%% Probe: every data visual saves as PNG, JPG and PDF, and its data as CSV
% Collin Snitchler
% 23.11.2026
% The user: every data visual (maps, APD graphs, traces, histograms, each
% Visualise panel and the whole Visualise window) can be saved as PNG, JPG
% and PDF, and graphs also as CSV (om_export.m). Headless, on a synthetic
% recording (30 x 30 pixels, 900 frames at 1000 fps, three beats crossing
% the field), pressing the buttons a user presses:
%   X1  each visual has the save button on its axes toolbar and the
%       right-click items, and both call om_export.save_dialog
%   X2  each visual saves as PNG, JPG and PDF (the file opens, has a sane
%       size; PDF starts with %PDF), also through the file dialog
%   X3  each graph's CSV is exactly the plotted XData / YData (one header
%       row with units, NaN = empty); a map's CSV is the shown matrix with
%       no header and NaN as the text NaN, its default name has the
%       quantity and unit
%   X4  main view: the saved picture has the colour map shown on screen and
%       the colour bar label of the map type (repolarisation included); a
%       beat-by-beat map saves its shown beat; Save image still writes its
%       PNG, CSV and log file
%   X5  the button survives imshow, cla and plot; the hidden toolbars
%       (APD trace, histograms, Visualise panels) have the save button only
%   X6  Visualise (needs OM_REDO_DS, OM_REDO_STEM, OM_REDO_RUN as
%       probe_cv_range; skipped without them): each panel saves with its
%       captions (Panel details give a taller picture), "Save..." saves the
%       window as PNG, JPG and PDF, and the panel's toolbar corner does not
%       cover its (i) button or colour bar
%   X8  each toolbar shows the buttons it showed before (base a987146:
%       MATLAB's default buttons for what is drawn, or none where the
%       toolbar was hidden), plus the save button; MATLAB's export button
%       appears nowhere it was not
%   X9  the main view's save button and right-click menu write save_image's
%       log file, as the Save image button does
%   X10 an image PDF (main view, reference frame, Visualise panels and
%       window) is cropped as its PNG: the page (MediaBox) has the PNG's
%       aspect within 10 %
%   X11 isochrones (CV map, Automatic; activation map): the saved picture
%       has the filled contours shown on screen, the CSV is the map they
%       are drawn from (not the image set to zero), named with its unit
%   X12 a map with empty (NaN) rows and columns at its edges reads back
%       with readmatrix at its size and with its values
%   X13 outside a git checkout (GIT_DIR to nowhere) the save button saves
%       the picture with its log file (commit "unknown") and reports no
%       failure; a log file that cannot be written does not turn a written
%       picture into "Could not save"
%   X14 the CV map's histogram bins the speed only, on screen (its data
%       count is the number of finite speed pixels; it binned all three
%       layers of CV_map before 24.11.2026) and in its CSV; the
%       beat-by-beat histogram's column names say all beats
%   X15 Visualise "Save..." prints no "UI components" warning and puts the
%       warning's state back; a panel's picture keeps the colour bar where
%       it is on screen, next to the axes (Panel details on)
%   X16 a histogram's picture has an x label with the unit (none on screen)
%   X18 Visualise saves: each panel has a "Save
%       panel..." button (always shown, by its (i), clear of the caption,
%       the (i) and the colour bar) and its right-click item, and no axes
%       toolbar (its "..." covered the caption); default names
%       <run id>_<panel> and <run id>_visualise; the first save opens in
%       the run folder's exports folder (removed again when the dialog is
%       cancelled with nothing in it), later ones in the last folder; the
%       status line says "Saved: <path>"; every picture has the footer
%       line (run, units, colours, date): a taller picture; PDF is named
%       "PDF (image, 300 dpi)" for panels and the window, "PDF (vector)"
%       for graphs; the window has no MATLAB menu bar or toolbar
%   X17 saving the restitution curve's CSV before it is drawn says that
%       there is nothing to save yet (no file, no "Could not save"), at
%       once: no file dialog is asked for (the queued answer stays unused
%       and no uiputfile is recorded); "Nothing to save yet" is printed
%       and shown once, not twice
%   X19 the Visualise window's saved footer with Panel details on: the
%       caption blocks in two columns under their panel rows; a panel's own
%       footer in one column
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_export_visuals"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
results = struct('id', {}, 'ok', {}, 'detail', {});
root = tempname;
mkdir(root);
out = fullfile(root, 'out');
mkdir(out);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

%% The main app with a synthetic recording
[r, c] = ndgrid(1:30, 1:30);
fps = 1000; n = 900; t = (0:n - 1) / fps;
stack = 100 * ones(30, 30, n);
for b = 0:2
    t0 = 0.1 + 0.3 * b + 0.0005 * (r + c);   % the wave crosses the field in 30 ms
    for k = 1:n
        x = max(t(k) - t0, 0);
        stack(:, :, k) = stack(:, :, k) + 1000 * (t(k) > t0) .* exp(-x / 0.08) .* (1 - exp(-x / 0.003));
    end
end
rng(1, 'twister');
stack = stack + 5 * rand(size(stack));
rec = fullfile(root, 'synthetic_recording.mat');
save(rec, 'stack');
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', rec);
headless_push('inputdlg', {num2str(fps)});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
a.SavetoEditField.Value = [out filesep];
a.signalregiontype.Value = 'Rectangle';
headless_push('drawrectangle', [10 10 6 6]);
feval(a.signalregion.ButtonPushedFcn, a.signalregion, []);
X = a.export_axes_for_test();

%% Frame view and signals
results = add(results, buttons_ok('main view (frame)', X.main_display_axes, true));
results = add(results, files_ok('main view (frame)', X.main_display_axes, fullfile(out, 'frame'), true));
frame = a.processed_data.image_stack{a.display.normalisation}(:, :, a.display.current_frame);
results = add(results, matrix_csv_ok('main view (frame) CSV', X.main_display_axes, fullfile(out, 'frame.csv'), frame, 'synthetic_recording_frame-1_signal_au'));
results = add(results, buttons_ok('ROI signals', X.signal_display_axes, true));
results = add(results, files_ok('ROI signals', X.signal_display_axes, fullfile(out, 'signals'), true));
call = getappdata(groot, 'om_headless_last_uiputfile');   % X18: a graph's PDF is vector
results = add(results, struct('id', 'X18 a graph''s file dialog names PDF (vector)', 'ok', numel(call) >= 1 && ...
    any(strcmp(call{1}(:, 2), 'PDF (vector) (*.pdf)')), 'detail', ''));
sig_lines = flipud(findobj(X.signal_display_axes, '-depth', 1, 'Type', 'line'));
results = add(results, table_csv_ok('ROI signals CSV', fullfile(out, 'signals.csv'), {'time_s', 'roi1_signal_au'}, ...
    {sig_lines(1).XData, sig_lines(1).YData}));
results = add(results, overlay_ok(out));

%% Activation map (local normalisation first, as the guide does)
a.localnormalise.Value = true;
feval(a.localnormalise.ValueChangedFcn, a.localnormalise, []);
a.maptype.Value = '1';
if ~isempty(a.maptype.ValueChangedFcn), feval(a.maptype.ValueChangedFcn, a.maptype, []); end
a.mapmethod.Value = '1';
a.mappercentage.Value = 100;
headless_push('uiconfirm', 'Yes');   % no averaged beats: generate anyway
feval(a.generatemap.ButtonPushedFcn, a.generatemap, []);
X = a.export_axes_for_test();
img = a.display.image_handle;
results = add(results, struct('id', 'X0 activation map generated', 'ok', a.display.map == 1 && ...
    isequal(size(img.CData), [30 30]) && any(isfinite(img.CData(:))), 'detail', mat2str(size(img.CData))));
results = add(results, buttons_ok('activation map', X.main_display_axes, true));
img.CData(1:3, 1:3) = NaN;   % shown "no data" pixels, for the empty CSV cells
on_screen = parula(257);     % a colour map other than [0 0 0; jet]
X.main_display_axes.Colormap = on_screen;
capture_start();
results = add(results, files_ok('activation map', X.main_display_axes, fullfile(out, 'activation'), true));
cap = capture_stop();
results = add(results, struct('id', 'X4 activation map: saved with the colour map shown and its colour bar label', ...
    'ok', ~isempty(cap) && isequal(cap.cmap, on_screen) && strcmp(cap.label, 'Activation time (ms)'), ...
    'detail', capture_text(cap)));
results = add(results, matrix_csv_ok('activation map CSV', X.main_display_axes, fullfile(out, 'activation.csv'), ...
    double(img.CData), 'synthetic_recording_activation_ms'));
% Save image: the button's own PNG, CSV and log file
before = {dir(out).name};
threw = '';
try
    feval(a.saveimage.ButtonPushedFcn, a.saveimage, []);
catch ME
    threw = ME.message;
end
png = fullfile(out, 'synthetic_recording_activation_map_1.png');
csv = fullfile(out, 'synthetic_recording_activation_map_1.csv');
[m_ok, m_txt] = read_matrix_csv(csv, double(img.CData));
new_files = setdiff({dir(out).name}, before);
new_logs = new_files(endsWith(new_files, '.dat'));
results = add(results, struct('id', 'X4 Save image: PNG, matrix CSV (NaN as text) and log file as before', ...
    'ok', isempty(threw) && image_ok(png) && m_ok && numel(new_logs) == 1 && ...
    startsWith(new_logs{1}, 'synthetic_recording_log_file_activation_map_') && log_ok(fullfile(out, new_logs{1})), ...
    'detail', sprintf('%s | new: %s | %s', threw, strjoin(new_files, ', '), m_txt)));
% X12: empty rows and columns at the map's edges (as on a real map) read
% back at the map's size
shown = img.CData;
img.CData(:, [1 2 end]) = NaN;
img.CData([1 end], :) = NaN;
om_export.save_to(X.main_display_axes, fullfile(out, 'activation_nan_edges.csv'));
rm = readmatrix(fullfile(out, 'activation_nan_edges.csv'));
results = add(results, struct('id', 'X12 a map with empty edges: readmatrix gives its size and values', ...
    'ok', isequal(size(rm), size(img.CData)) && isequaln(rm, double(img.CData)), ...
    'detail', sprintf('readmatrix %s, map %s', mat2str(size(rm)), mat2str(size(img.CData)))));
img.CData = shown;
% X10: the main view's PDF (an image PDF) has its PNG's aspect
results = add(results, aspect_ok('main view (activation map)', fullfile(out, 'activation')));
% X13: outside a git checkout, the save button still saves with a log file
results = add(results, no_git_ok(a, X.main_display_axes, out));
% X9: the save button and the right-click menu (save_to, as both call it
% after the dialog) write the same log file, next to the chosen file
menu_dir = fullfile(out, 'menu_route');
mkdir(menu_dir);
om_export.save_to(X.main_display_axes, fullfile(menu_dir, 'activation.png'));
om_export.save_to(X.main_display_axes, fullfile(menu_dir, 'activation.csv'));
headless_push('uiputfile', fullfile(menu_dir, 'activation_dialog.pdf'));
om_export.save_dialog(X.main_display_axes, 'image');
logs = {dir(fullfile(menu_dir, '*.dat')).name};
want = arrayfun(@(k) sprintf('synthetic_recording_log_file_activation_map_%d.dat', k), 1:3, 'UniformOutput', false);
results = add(results, struct('id', 'X9 main view: picture, CSV and dialog routes each write save_image''s log file', ...
    'ok', isequal(sort(logs), want) && all(cellfun(@(f) log_ok(fullfile(menu_dir, f)), logs)), ...
    'detail', strjoin(logs, ', ')));

%% Histograms (drawn with the map)
hist_names = {'UIAxesHistogram', 'UIAxesHistogram_bbb', 'UIAxesHistogram_traces'};
for k = 1:numel(hist_names)
    ax = X.(hist_names{k});
    hh = findobj(ax, 'Type', 'histogram');
    results = add(results, buttons_ok(hist_names{k}, ax, true, 1));
    results = add(results, files_ok(hist_names{k}, ax, fullfile(out, hist_names{k}), true));
    % X10 for the histograms too: their vector PDF page is a few % taller
    % than the PNG (the page is cropped to the text boxes, the PNG to the
    % drawn pixels; on a picture 58 pt high that is 2-4 %)
    results = add(results, aspect_ok(hist_names{k}, fullfile(out, hist_names{k})));
    if isempty(hh)
        results = add(results, struct('id', ['X3 ' hist_names{k} ' CSV'], 'ok', false, 'detail', 'no histogram drawn'));
    else
        e = hh(1).BinEdges;
        results = add(results, table_csv_ok([hist_names{k} ' CSV'], fullfile(out, [hist_names{k} '.csv']), ...
            {'bin_lower_activation_ms', 'bin_upper_activation_ms', 'count'}, {e(1:end - 1), e(2:end), hh(1).Values}));
    end
end
capture_start();
om_export.save_to(X.UIAxesHistogram, fullfile(out, 'hist_label.png'));
cap = capture_stop();
results = add(results, struct('id', 'X16 a histogram''s picture has an x label with the unit (none on screen)', ...
    'ok', ~isempty(cap) && strcmp(cap.xlabel, 'Activation time (ms)') && isempty(X.UIAxesHistogram.XLabel.String), ...
    'detail', capture_text(cap)));

%% Isochrones on the activation map (map tab): filled contours over an
% image set to zero
act = a.processed_data.activation_map;
a.lowerylimit.Value = ceil(min(act(:))); a.upperylimit.Value = floor(max(act(:))) - 1;   % levels inside the map's range (the ticks must increase)
a.IsochroneSeparationmsEditField.Value = 5;
a.mapisochronesbutton.Value = 1;
feval(a.mapisochronesbutton.ValueChangedFcn, a.mapisochronesbutton, []);
results = add(results, isochrones_ok('activation map', a, X.main_display_axes, act, 'synthetic_recording_activation_ms', out));
a.mapisochronesbutton.Value = 0;
feval(a.mapisochronesbutton.ValueChangedFcn, a.mapisochronesbutton, []);

%% CV map (from the activation map)
a.display.image_handle.CData = a.processed_data.activation_map;   % as generated
threw = '';
try
    headless_push('uiconfirm', 'Yes');   % the activation map exists
    feval(a.CV_map.ButtonPushedFcn, a.CV_map, []);
catch ME
    threw = ME.message;
end
cv_ok = isempty(threw) && isfield(a.display, 'quiver_handle') && ~isempty(a.display.quiver_handle) && all(isvalid(a.display.quiver_handle));
results = add(results, struct('id', 'X0 CV map generated (quivers shown)', 'ok', cv_ok, 'detail', threw));
if cv_ok
    capture_start();
    results = add(results, files_ok('CV map', X.main_display_axes, fullfile(out, 'cv'), true));
    cap = capture_stop();
    results = add(results, struct('id', 'X4 CV map: its colour bar label', 'ok', ~isempty(cap) && ...
        strcmp(cap.label, 'Conduction velocity (mm/ms)'), 'detail', capture_text(cap)));
    results = add(results, matrix_csv_ok('CV map CSV', X.main_display_axes, fullfile(out, 'cv.csv'), ...
        double(a.display.image_handle.CData), 'synthetic_recording_cv_speed_m_per_s'));
    % X14: the histogram's CSV over the speed only
    cv = a.processed_data.CV_map;
    hh = findobj(X.UIAxesHistogram, 'Type', 'histogram');
    on_screen_n = sum(hh(1).Values);
    om_export.save_to(X.UIAxesHistogram, fullfile(out, 'hist_cv.csv'));
    T = readmatrix(fullfile(out, 'hist_cv.csv'));
    hdr = readlines(fullfile(out, 'hist_cv.csv'));
    speed = cv(:, :, 3);
    % the histogram bins the speeds within the CV
    % map's display range ([0, 99th percentile], rabbit_cv_map.display_range)
    % and its title counts the ones above; those within are the reference
    lim14 = rabbit_cv_map.display_range(cv);
    in14 = isfinite(speed) & speed >= lim14(1) & speed <= lim14(2);
    n_above14 = nnz(isfinite(speed) & speed > lim14(2));
    [n_want, e_want] = histcounts(speed(in14), 'BinLimits', lim14);
    hist_ok = nnz(in14) + n_above14 == nnz(isfinite(speed));
    for hn = hist_names   % the three histogram axes update_histogram_map draws
        hk = findobj(X.(hn{1}), 'Type', 'histogram');
        hist_ok = hist_ok && ~isempty(hk) && sum(hk(1).Values) == nnz(in14) && isequaln(hk(1).Data(:), speed(in14)) && ...
            strcmp(char(string(X.(hn{1}).Title.String)), sprintf('%d values above %s m/s not shown', n_above14, num2str(lim14(2), 3)));
    end
    results = add(results, struct('id', 'X14 CV histogram on screen: the speed only, within its display range (B9), the rest counted', ...
        'ok', hist_ok && on_screen_n == nnz(in14), 'detail', sprintf('on screen %d values, speed %d in range + %d above of %d finite', ...
        on_screen_n, nnz(in14), n_above14, nnz(isfinite(speed)))));
    % the saved picture (om_export draws the histogram again from its
    % bins): its counts sum to the finite speed pixels too
    capture_start();
    om_export.save_to(X.UIAxesHistogram, fullfile(out, 'hist_cv.png'));
    cap = capture_stop();
    results = add(results, struct('id', 'X14 CV histogram picture: its bin counts sum to the finite speed pixels', ...
        'ok', ~isempty(cap) && cap.hist_n == nnz(in14) && image_ok(fullfile(out, 'hist_cv.png')), ...
        'detail', sprintf('picture %d, speed %d in range', capture_field(cap, 'hist_n'), nnz(in14))));
    results = add(results, struct('id', 'X14 CV histogram CSV: the speed only', ...
        'ok', strcmp(hdr(1), "bin_lower_cv_speed_m_per_s,bin_upper_cv_speed_m_per_s,count") && ...
        sum(T(:, 3)) == nnz(in14) && isequal(T(:, 3)', n_want) && isequal(T(:, 1)', e_want(1:end - 1)), ...
        'detail', sprintf('CSV %d values, speed %d in range, on screen %d values (all layers %d finite)', sum(T(:, 3)), ...
        nnz(in14), on_screen_n, nnz(isfinite(cv)))));
    % X11: isochrones (Automatic) over the CV map
    a.isochrone_method.Value = 'Automatic';
    a.IsochronesButton.Value = 1;
    feval(a.IsochronesButton.ValueChangedFcn, a.IsochronesButton, []);
    results = add(results, isochrones_ok('CV map (Automatic)', a, X.main_display_axes, speed, 'synthetic_recording_cv_speed_m_per_s', out));
    a.IsochronesButton.Value = 0;
    feval(a.IsochronesButton.ValueChangedFcn, a.IsochronesButton, []);
end

%% Repolarisation map (no colour bar label in saved pictures before)
a.maptype.Value = '6';
if ~isempty(a.maptype.ValueChangedFcn), feval(a.maptype.ValueChangedFcn, a.maptype, []); end
threw = '';
try
    headless_push('uiconfirm', 'Yes');
    feval(a.generatemap.ButtonPushedFcn, a.generatemap, []);
catch ME
    threw = ME.message;
end
pct = a.apdpercentage.Value;
capture_start();
results = add(results, files_ok('repolarisation map', X.main_display_axes, fullfile(out, 'repol'), true));
cap = capture_stop();
results = add(results, struct('id', 'X4 repolarisation map: colour bar label with its unit', 'ok', isempty(threw) && ...
    ~isempty(cap) && strcmp(cap.label, sprintf('Repolarisation time, %d%% (ms)', pct)), ...
    'detail', [threw ' | ' capture_text(cap)]));
results = add(results, matrix_csv_ok('repolarisation map CSV', X.main_display_axes, fullfile(out, 'repol.csv'), ...
    double(a.display.image_handle.CData), sprintf('synthetic_recording_repolarisation%d_ms', pct)));

%% APD trace of the ROI
threw = '';
try
    feval(a.ComputeAPDBCLanddVdtmaxButton.ButtonPushedFcn, a.ComputeAPDBCLanddVdtmaxButton, []);
catch ME
    threw = ME.message;
end
ax = X.APDAxes;
kids = flipud(ax.Children);
tr = kids(find(strcmp(get(kids, 'Type'), 'line'), 1));
marks = cell2mat(get(kids(strcmp(get(kids, 'Type'), 'constantline')), 'Value'))';
rmp = findobj(ax, 'Type', 'line', 'LineStyle', ':');
results = add(results, buttons_ok('APD trace', ax, true, 1));
results = add(results, files_ok('APD trace', ax, fullfile(out, 'apd'), true));
if isempty(tr)
    results = add(results, struct('id', 'X3 APD trace CSV', 'ok', false, 'detail', ['no trace: ' threw]));
else
    rmp_y = arrayfun(@(h) h.YData(1), flipud(rmp))';
    results = add(results, table_csv_ok('APD trace CSV', fullfile(out, 'apd.csv'), ...
        {'time_ms', 'signal_au', 'activation_time_ms', 'repolarisation_time_ms', 'resting_level_au'}, ...
        {tr.XData, tr.YData, marks(1:2:end), marks(2:2:end), rmp_y}));
end

%% Beat-by-beat activation maps (3D map: the shown beat is saved)
threw = '';
try
    feval(a.generatebeatmaps.ButtonPushedFcn, a.generatebeatmaps, []);
catch ME
    threw = ME.message;
end
am = a.processed_data.activation_map;
bbb_ok = isempty(threw) && size(am, 3) > 1;
results = add(results, struct('id', 'X0 beat-by-beat maps generated', 'ok', bbb_ok, 'detail', [threw ' ' mat2str(size(am))]));
if bbb_ok
    capture_start();
    results = add(results, files_ok('beat-by-beat map, beat 1', X.main_display_axes, fullfile(out, 'bbb1'), true));
    cap = capture_stop();
    results = add(results, matrix_csv_ok('beat-by-beat map CSV, beat 1', X.main_display_axes, fullfile(out, 'bbb1.csv'), ...
        am(:, :, 1), 'synthetic_recording_bbb_activation_beat1_ms'));
    % X14: the beat-by-beat histogram holds every beat, and says so
    om_export.save_to(X.UIAxesHistogram_bbb, fullfile(out, 'hist_bbb.csv'));
    hdr = readlines(fullfile(out, 'hist_bbb.csv'));
    T = readmatrix(fullfile(out, 'hist_bbb.csv'));
    results = add(results, struct('id', 'X14 beat-by-beat histogram CSV: column names say all beats', ...
        'ok', strcmp(hdr(1), "bin_lower_bbb_activation_all_beats_ms,bin_upper_bbb_activation_all_beats_ms,count") && ...
        sum(T(:, 3)) == nnz(isfinite(am)), 'detail', sprintf('%s; %d values, %d finite over all beats', hdr(1), sum(T(:, 3)), nnz(isfinite(am)))));
    feval(a.nextframe_2.ButtonPushedFcn, a.nextframe_2, []);
    om_export.save_to(X.main_display_axes, fullfile(out, 'bbb2.csv'));
    results = add(results, matrix_csv_ok('beat-by-beat map CSV, beat 2', X.main_display_axes, fullfile(out, 'bbb2.csv'), ...
        am(:, :, 2), 'synthetic_recording_bbb_activation_beat2_ms'));
    threw = '';
    try
        feval(a.saveimage.ButtonPushedFcn, a.saveimage, []);
    catch ME
        threw = ME.message;
    end
    [m_ok, m_txt] = read_matrix_csv(fullfile(out, 'synthetic_recording_bbb_activation_map_beat2_1.csv'), am(:, :, 2));
    results = add(results, struct('id', 'X4 beat-by-beat: Save image saves the shown beat; label Activation time (ms)', ...
        'ok', isempty(threw) && m_ok && image_ok(fullfile(out, 'synthetic_recording_bbb_activation_map_beat2_1.png')) && ...
        ~isempty(cap) && strcmp(cap.label, 'Activation time (ms)'), 'detail', [threw ' | ' m_txt ' | ' capture_text(cap)]));
end

%% The button survives the main view being redrawn
X = a.export_axes_for_test();
imgs = findobj(X.main_display_axes, 'Type', 'image');
results = add(results, struct('id', 'X5 main view: button and menu after the maps were drawn', ...
    'ok', om_export.has_button(X.main_display_axes) && ~isempty(imgs) && isequal(imgs(1).ContextMenu, X.main_display_axes.ContextMenu), ...
    'detail', sprintf('%d images', numel(imgs))));
cla(X.main_display_axes);
imshow(rand(5), 'Parent', X.main_display_axes);
plot(X.APDAxes, 1:3);
results = add(results, struct('id', 'X5 button after cla + imshow (main view) and plot (APD trace)', ...
    'ok', om_export.has_button(X.main_display_axes) && om_export.has_button(X.APDAxes) && ...
    numel(X.APDAxes.Toolbar.Children) == 1, 'detail', ''));

%% Beat averaging window (the beat periods, then the beat signals)
a.averaging.beat_locations = [60 360 660];
threw = '';
try
    ba = beat_averaging(a);
    ba_cleanup = onCleanup(@() delete(ba)); %#ok<NASGU>
catch ME
    threw = ME.message; ba = [];
end
if isempty(ba)
    results = add(results, struct('id', 'X0 beat averaging window', 'ok', false, 'detail', threw));
else
    ax = ba.UIAxes;
    results = add(results, buttons_ok('beat periods', ax, true));
    results = add(results, files_ok('beat periods', ax, fullfile(out, 'beat_periods'), true));
    ln = findobj(ax, 'Type', 'line');
    results = add(results, table_csv_ok('beat periods CSV', fullfile(out, 'beat_periods.csv'), ...
        {'beat_number', 'beat_period_ms'}, {ln(1).XData, ln(1).YData}));
    feval(ba.okbeats.ButtonPushedFcn, ba.okbeats, []);
    ln = flipud(findobj(ax, '-depth', 1, 'Type', 'line'));
    results = add(results, buttons_ok('beat signals (after cla and plot)', ax, true));
    results = add(results, files_ok('beat signals', ax, fullfile(out, 'beats'), true));
    ids = []; tx = []; ty = [];
    for k = 1:numel(ln)
        ids = [ids; repmat(str2double(ln(k).DisplayName), numel(ln(k).XData), 1)]; %#ok<AGROW>
        tx = [tx; ln(k).XData(:)]; ty = [ty; ln(k).YData(:)]; %#ok<AGROW>
    end
    results = add(results, table_csv_ok('beat signals CSV (long format)', fullfile(out, 'beats.csv'), ...
        {'beat', 'time_ms', 'signal_au'}, {ids, tx, ty}));
    delete(ba);
end

%% APD restitution window: the ROI signal and the restitution curve
threw = '';
try
    ar = APD_restitution;
    ar_cleanup = onCleanup(@() delete(ar)); %#ok<NASGU>
catch ME
    threw = ME.message; ar = [];
end
if isempty(ar)
    results = add(results, struct('id', 'X0 APD restitution window', 'ok', false, 'detail', threw));
else
    results = add(results, nothing_yet_ok(ar.restitution_curve_UIAxes, fullfile(out, 'rest_curve_empty.csv')));
    tt = (0:499) / 500; yy = sin(2 * pi * 3 * tt); yy(5) = NaN;
    h1 = plot(ar.ROI_signal_UIAxes, tt, yy);   % as plot_ROI_signal draws it
    results = add(results, buttons_ok('restitution ROI signal', ar.ROI_signal_UIAxes, true, 1));
    results = add(results, files_ok('restitution ROI signal', ar.ROI_signal_UIAxes, fullfile(out, 'rest_signal'), true));
    results = add(results, table_csv_ok('restitution ROI signal CSV', fullfile(out, 'rest_signal.csv'), ...
        {'time_s', 'signal_au'}, {h1.XData, h1.YData}));
    bcl = [300 250 200 150]; apd = [180 170 155 140] + 0.1; sd = [5 4 3.5 6];
    h2 = errorbar(ar.restitution_curve_UIAxes, bcl, apd, sd, 'd');   % as APD vs BCL draws it
    ar.restitution_curve_UIAxes.XLabel.String = 'BCL (ms)';
    ar.ErrorbartypeDropDown.Value = '1';
    results = add(results, buttons_ok('restitution curve', ar.restitution_curve_UIAxes, true, 1));
    results = add(results, files_ok('restitution curve', ar.restitution_curve_UIAxes, fullfile(out, 'rest_curve'), true));
    results = add(results, table_csv_ok('restitution curve CSV', fullfile(out, 'rest_curve.csv'), ...
        {'bcl_ms', 'apd_ms', 'apd_sd_ms'}, {h2.XData, h2.YData, h2.YPositiveDelta}));
    delete(ar);
end

%% Open part of a file (ECG trace) and the reference recording window
threw = '';
try
    of = open_file_partially(a);
    of_cleanup = onCleanup(@() delete(of)); %#ok<NASGU>
catch ME
    threw = ME.message; of = [];
end
if isempty(of)
    results = add(results, struct('id', 'X0 open part of a file window', 'ok', false, 'detail', threw));
else
    of.UIAxes.Visible = 'on';
    h3 = plot(of.UIAxes, (0:999) / 1000, cos((0:999) / 50), 'r');   % as plot_ECG draws it
    results = add(results, buttons_ok('ECG trace', of.UIAxes, true));
    results = add(results, files_ok('ECG trace', of.UIAxes, fullfile(out, 'ecg'), true));
    results = add(results, table_csv_ok('ECG trace CSV', fullfile(out, 'ecg.csv'), {'time_s', 'ecg_signal_au'}, ...
        {h3.XData, h3.YData}));
    delete(of);
end
threw = '';
try
    a.processed_data.keep_area_poly = ones(30, 30);
    a.first_processed_frame = a.processed_data.image_stack{1}(:, :, 1);
    orr = open_reference_recording(a);
    orr_cleanup = onCleanup(@() delete(orr)); %#ok<NASGU>
catch ME
    threw = ME.message; orr = [];
end
if isempty(orr)
    results = add(results, struct('id', 'X0 reference recording window', 'ok', false, 'detail', threw));
else
    ax = findall(orr.normalise_referenceUIFigure, 'Type', 'axes');
    ax = ax(arrayfun(@(h) isappdata(h, 'om_export'), ax));
    results = add(results, struct('id', 'X1 reference recording: the working frame axes has a spec', 'ok', numel(ax) == 1, ...
        'detail', sprintf('%d axes', numel(ax))));
    if ~isempty(ax)
        results = add(results, buttons_ok('working frame', ax(1), false));
        results = add(results, files_ok('working frame', ax(1), fullfile(out, 'working'), false));
        results = add(results, aspect_ok('reference recording working frame', fullfile(out, 'working')));
    end
    delete(orr);
end

%% Segmentation preview (needs a rabbit panoramic recording): its wiring
% and the title it borrows from the window's label
src = fileread(fullfile(repo, 'rabbit_segmentation_preview.m'));
f = uifigure('Visible', 'off');
ax = uiaxes(f);
lbl = uilabel(f, 'Text', 'cut_view2 (view 2)');
om_export.attach(ax, struct('name', 'preview', 'content', 'image', 'title', @() lbl.Text));   % as build_figure
imshow(rand(20), 'Parent', ax);   % as rerender
[tb_ok, tb_detail] = toolbar_set_ok(ax, true);   % MATLAB's default toolbar was shown here before
results = add(results, struct('id', 'X8 segmentation preview: the earlier toolbar buttons plus save', 'ok', tb_ok, 'detail', tb_detail));
png = fullfile(out, 'preview.png');
om_export.save_to(ax, png);
results = add(results, struct('id', 'X2 segmentation preview: attached in build_figure; saved with the label as title, title put back', ...
    'ok', contains(src, 'om_export.attach(ax, struct(''name'', @() [''segmentation_preview_''') && image_ok(png) && ...
    isempty(ax.Title.String), 'detail', ''));
delete(f);

%% Visualise
src_root = getenv('OM_REDO_DS'); stem = getenv('OM_REDO_STEM'); run_id = getenv('OM_REDO_RUN');
if isempty(src_root) || ~isfolder(fullfile(src_root, [stem '.matom'], 'reconstruction', 'runs', run_id))
    fprintf('PROBE_SKIP X6 Visualise: OM_REDO_DS, OM_REDO_STEM and OM_REDO_RUN not set\n');
else
    results = visualise_checks(results, a, stem, run_id, out);
end

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_EXPORT_VISUALS RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_export_visuals:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function results = visualise_checks(results, app, stem, run_id, out)
% A copy of the run, a CV map and a reprojection (as probe_cv_range), then Visualise
[root, cleanup] = om_redo_copy('probe_export_visuals', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
map = 20 + 30 * rand(size(om_image));
frames = repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, []);
speed = 0.2 + 0.8 * rand(size(map));
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(root, stem);
assert(ok, err);
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
app.processed_data.CV_map = cat(3, speed * 0.6, speed * 0.8, speed);
% The stand-in CV map counts as made from this activation map (the CV settings kept from the earlier CV map press hold that map's
% hash, and a CV map made from another activation map is not projected, so
% the window had no CV panel and X15/X18 fell back to the sparse panel)
app.processed_data.CV_settings.activation_sha256 = rabbit_cv_map.map_hash(map);
app.CV_method.Value = app.CV_method.Items{1};
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
results = add(results, struct('id', 'X0 Visualise opened', 'ok', v_ok, 'detail', v_err));
if ~v_ok, return; end
fig_cleanup = onCleanup(@() close(fig, 'force')); %#ok<NASGU>
panels = findobj(fig, 'Type', 'axes', '-regexp', 'Tag', '^panel_');
results = visualise_save_routes(results, fig, panels, run_dir, run_id, out);
for k = 1:numel(panels)
    ax = panels(k);
    role = extractAfter(ax.Tag, 'panel_');
    results = add(results, panel_button_ok(fig, ax, role));
    results = add(results, files_ok(['Visualise panel ' role], ax, fullfile(out, ['panel_' role]), false));
    results = add(results, aspect_ok(['Visualise panel ' role], fullfile(out, ['panel_' role])));
end
% Panel details: longer captions, so a taller picture of the same panel.
% The CV panel (the first found here): with Panel details its picture is
% taller and has more caption lines (1.2x taller was too strict: 1100 vs 922 px)
ax = findobj(panels, 'flat', 'Tag', 'panel_cv');
% the CV panel must be there (B7 hid it silently: the checks below then ran
% on the sparse panel)
results = add(results, struct('id', 'X15 Visualise has its CV panel', 'ok', ~isempty(ax), 'detail', ''));
if isempty(ax), ax = panels(1); end
ax = ax(1);
off_png = fullfile(out, 'details_off.png');
on_png = fullfile(out, 'details_on.png');
om_export.save_to(ax, off_png);
pd = findobj(fig, 'Tag', 'ReconstructionPanelDetails');
pd.Value = 1; pd.Callback(pd, []);
capture_start();
om_export.save_to(ax, on_png);
cap = capture_stop();
results = add(results, window_footer_columns(tab, fig));   % X19
% X15: the colour bar next to the axes as on screen (it sat over the
% captions' ends when left to place itself)
screen_off = [];
if ~isempty(ax.Colorbar)
    pa = getpixelposition(ax); pc = getpixelposition(ax.Colorbar);
    screen_off = [pc(1:2) - pa(1:2), pc(3:4)];
end
% a panel is saved from the axes as drawn (no copy),
% so its colour bar is where it is on screen; a copy, when one is made,
% must still place it so
cb_pic = capture_field(cap, 'cb_off');
results = add(results, struct('id', 'X15 Visualise panel (Panel details): colour bar placed as on screen', ...
    'ok', ~isempty(screen_off) && (isempty(cb_pic) || max(abs(cb_pic - screen_off)) <= 2), ...
    'detail', sprintf('screen %s, picture %s', mat2str(round(screen_off)), mat2str(round(capture_field(cap, 'cb_off'))))));
% On screen, Panel details are in a box under the panel (the axes keep at
% least 70 % of their height); the picture has them under the panel, in
% its footer (since 24.11.2026)
box = findobj(fig, 'Tag', 'ReconstructionPanelDetailsText_cv');
sub_on = numel(cellstr(box.String));
h_on = getpixelposition(ax) * [0; 0; 0; 1];
box_px = getpixelposition(box);   % with Panel details on
% the axes' height without details that the layout used for the cap
hp = getappdata(fig, 'reconstruction_axes_h_plain');
h_cap = hp(strcmp(getappdata(fig, 'reconstruction_viewer_order'), 'cv'));
pd.Value = 0; pd.Callback(pd, []);
h_off = getpixelposition(ax) * [0; 0; 0; 1];
% the box is as high as its lines (12 px a line
% and 10 px), at most 45 % of the axes' height, so the axes keep about 50 %
% and at most a fifth of the panel's cell (it scrolls)
cells_x = getappdata(fig, 'reconstruction_cells');
fpx = getpixelposition(fig);
cell_h = cells_x(strcmp(getappdata(fig, 'reconstruction_viewer_order'), 'cv'), 4) * fpx(4);
box_ok = box_px(4) >= min([numel(cellstr(box.String)) * 12 + 10, 0.45 * h_off, max(30, 0.2 * cell_h)]) - 2;   % tall enough for its lines
results = add(results, struct('id', 'X18 Panel details on screen: a box of the full caption, as high as its lines, axes at least 50 % as high', ...
    'ok', strcmp(box.Visible, 'off') && numel(cellstr(box.String)) > 3 && h_on >= 0.5 * h_off - 1 && box_ok, ...
    'detail', sprintf('axes %.0f vs %.0f px, box %d lines, %.0f px (cap %.0f)', h_on, h_off, numel(cellstr(box.String)), box_px(4), 0.45 * h_cap)));
sub_off = numel(cellstr(ax.Subtitle.String));
i_off = imread(off_png); i_on = imread(on_png);
results = add(results, struct('id', 'X6 Visualise panel saved with Panel details: the full captions (taller picture)', ...
    'ok', size(i_on, 1) > size(i_off, 1) && sub_on > sub_off, ...
    'detail', sprintf('%d vs %d px high, %d (box) vs %d caption lines', size(i_on, 1), size(i_off, 1), sub_on, sub_off)));
% A panel's picture is that panel, not the whole window: the window's
% title and notes (annotations spanning the window) are left out, so the
% picture is much narrower than the window at 300 dpi
fig_px = getpixelposition(fig);
win_w = fig_px(3) * 300 / 96;
results = add(results, struct('id', 'X7 a Visualise panel''s picture is the panel only (not the window''s width)', ...
    'ok', size(i_off, 2) < 0.6 * win_w && size(i_on, 2) < 0.6 * win_w, ...
    'detail', sprintf('panel %d / %d px wide, window %.0f px at 300 dpi', size(i_off, 2), size(i_on, 2), win_w)));
% The whole window through its Save... button
btn = findobj(fig, 'Tag', 'ReconstructionViewerSave');
ok_w = strcmp(btn.String, 'Save...');
txt = {};
warn_id = 'MATLAB:print:ExportappForUIFigureWithUIControl';
state_before = warning('query', warn_id);
warned = false;
for e = {'.png', '.jpg', '.pdf'}
    pth = fullfile(out, ['window' e{1}]);
    headless_push('uiputfile', pth);
    printed = evalc('btn.Callback(btn, []);');   % lastwarn is set even for a warning turned off: read what is printed
    warned = warned || contains(printed, 'UI components');
    if strcmp(e{1}, '.pdf'), good = pdf_ok(pth); else, good = image_ok(pth); end
    ok_w = ok_w && good;
    txt{end + 1} = sprintf('%s %d', e{1}, good); %#ok<AGROW>
end
results = add(results, struct('id', 'X6 Visualise "Save..." saves the window as PNG, JPG and PDF', 'ok', ok_w, ...
    'detail', strjoin(txt, ', ')));
state_after = warning('query', warn_id);
results = add(results, struct('id', 'X15 Visualise "Save...": no "UI components" warning, its state put back', ...
    'ok', ~warned && strcmp(state_before.state, state_after.state), ...
    'detail', sprintf('warned %d, state %s -> %s', warned, state_before.state, state_after.state)));
results = add(results, aspect_ok('Visualise window', fullfile(out, 'window')));
end


function r = window_footer_columns(tab, fig)
% X19: with Panel details on, the
% window's saved footer has one caption block per panel under its own
% column: tile t of row ceil(t / n_cols) in column t - (row - 1) * n_cols of
% that row's columns (as many as the row has panels; it was two, zig-zag);
% the first row's blocks above the second row's; a panel's own footer has
% no columns (as before)
order = getappdata(fig, 'reconstruction_viewer_order');
panels = getappdata(fig, 'reconstruction_viewer_panels');
foot = cellstr(tab.viewer_export_footer(fig, ''));
% one block per panel, under its own column (row 1
% four columns, row 2 three), on the grid om_export.footer_grid draws
G = om_export.footer_grid(foot, 2000);   % wide: the title lines are not wrapped
n_rows = 1 + (numel(order) > 3);
n_cols = ceil(numel(order) / n_rows);
per_row = arrayfun(@(r) min(n_cols, numel(order) - (r - 1) * n_cols), 1:n_rows);
L = G{1};
R = {};
if numel(G) > 1, R = [G{2:end}]; end
ok = all(cellfun(@numel, G) == numel(G{1})) && any(contains(foot, char(9))) && ~isempty(order);
where = zeros(numel(order), 2);   % [row in the footer, column] of each title found
bad = {};
for t = 1:numel(order)
    p = panels(strcmp({panels.role_id}, order{t}));
    if isempty(p) || isempty(tab.viewer_detail_lines(fig, order{t})), continue; end
    head = [tab.viewer_title(p(1)) ':'];
    row = ceil(t / n_cols);
    c = t - (row - 1) * n_cols;
    slot = 1 + (c - 1) * numel(G) / per_row(row);
    hit = find(strcmp(G{slot}, head), 1);
    other = any(cellfun(@(g) any(strcmp(g, head)), G([1:slot - 1, slot + 1:end])));
    if isempty(hit) || other
        bad{end + 1} = sprintf('%s not in slot %d of %d', order{t}, slot, numel(G)); %#ok<AGROW>
        continue;
    end
    where(t, :) = [hit, row];
end
found = where(:, 1) > 0;
if any(where(found, 2) == 2) && any(where(found, 2) == 1)
    % the second row's blocks start below the end of the first row's
    ok = ok && min(where(where(:, 2) == 2, 1)) > max(where(where(:, 2) == 1, 1));
end
ok = ok && isempty(bad) && nnz(found) >= 2 && any(~cellfun(@isempty, R));
% a single panel's footer: one column, as before
single = cellstr(tab.viewer_export_footer(fig, order{find(found, 1)}));
ok = ok && ~any(contains(single, char(9)));
% drawn: the footer strip under a picture, as Save... draws it (two columns)
png = [tempname '.png'];
imwrite(uint8(255 * ones(300, 1200, 3)), png);
om_export.append_footer(png, foot);
im = imread(png);
delete(png);
ok = ok && size(im, 1) > 300 && size(im, 2) >= 1200;
r = struct('id', 'X19 Visualise window saved with Panel details: one caption block per panel, under its own column', ...
    'ok', ok, 'detail', sprintf('%d panels, %d x %d, %d footer lines (%d tab rows), %s', numel(order), n_rows, n_cols, ...
    numel(L), nnz(contains(foot, char(9))), strjoin(bad, '; ')));
end


function t = ternary_tip(has_csv)
% The toolbar button's tooltip: CSV named only where there is one
if has_csv, t = om_export.CSV_TOOLTIP; else, t = om_export.TOOLTIP; end
end


function r = panel_button_ok(fig, ax, role)
% X18: Save panel... by the (i), always shown, calling the panel's save;
% the right-click item; no axes toolbar; the button clear of the
% caption (title and subtitle extents), the (i) and the colour bar
b = findobj(fig, 'Tag', ['ReconstructionPanelSave_' role]);
info = findobj(fig, 'Tag', ['ReconstructionPanelInfo_' role]);
mi = findobj(ax.ContextMenu, 'Tag', 'om_export_image');
mc = findobj(ax.ContextMenu, 'Tag', 'om_export_csv');
ok = isscalar(b) && isscalar(info) && strcmp(b.String, 'Save panel...') && strcmp(b.Visible, 'on') && ...
    strcmp(b.TooltipString, 'Save this panel as PNG, JPG or PDF...') && ...
    contains(func2str(b.Callback), 'om_export.save_dialog(ax,''image'')') && ~isempty(mi) && isempty(mc) && ...
    strcmp(ax.Toolbar.Visible, 'off');
hits = {};
if ok
    pb = getpixelposition(b, true);
    p_i = getpixelposition(info, true);
    if overlap(pb, p_i), hits{end + 1} = '(i)'; end
    if ~isempty(ax.Colorbar) && overlap(pb, getpixelposition(ax.Colorbar, true)), hits{end + 1} = 'colour bar'; end
    pa = getpixelposition(ax, true);
    names = {'title', 'caption'};
    parts = {ax.Title, ax.Subtitle};
    for q = 1:2
        st = parts{q};
        if isempty(st.String), continue; end
        u = st.Units; st.Units = 'pixels'; e = st.Extent; st.Units = u;
        if overlap(pb, [pa(1:2) + e(1:2), e(3:4)]), hits{end + 1} = names{q}; end %#ok<AGROW>
    end
    ok = isempty(hits) && pb(1) + pb(3) <= p_i(1) && abs(pb(2) - p_i(2)) < 2;
end
r = struct('id', ['X18 Visualise panel ' role ': Save panel... by the (i), right-click item, no axes toolbar, clear of the caption'], ...
    'ok', ok, 'detail', strjoin(hits, ', '));
end


function results = visualise_save_routes(results, fig, panels, run_dir, run_id, out)
% X18: names, folders, footer, status line, PDF labels, no MATLAB menus
ax = findobj(panels, 'flat', 'Tag', 'panel_projected');
setappdata(groot, 'reconstruction_export_folder', '');
spec = getappdata(ax, 'om_export');
exports = fullfile(run_dir, 'exports');
name_ok = strcmp(spec.name(), [run_id '_activation']);
% a cancelled dialog leaves no empty exports folder behind
q = getappdata(groot, 'om_headless_queue');
q.uiputfile = {};
setappdata(groot, 'om_headless_queue', q);
om_export.save_dialog(ax, 'image');
cancel_ok = ~isfolder(exports);
call = getappdata(groot, 'om_headless_last_uiputfile');
first_ok = numel(call) >= 3 && strcmp(call{3}, fullfile(exports, [run_id '_activation.png']));
pdf_panel = numel(call) >= 1 && any(strcmp(call{1}(:, 2), 'PDF (image, 300 dpi) (*.pdf)'));
p = fullfile(out, 'x18_activation.png');
headless_push('uiputfile', p);
om_export.save_dialog(ax, 'image');
st = findobj(fig, 'Tag', 'ReconstructionViewerStatus');
% cut from the left on the line, in full in the tooltip
status_ok = isscalar(st) && strcmp(st.String, ['Saved: ' rabbit_reconstruction_tab.display_path(p, 90)]) && ...
    strcmp(st.TooltipString, ['Saved: ' rabbit_reconstruction_tab.display_path(p)]);
next_ok = strcmp(spec.folder(), out);
% the footer: on every picture, whatever Panel details shows
foot = spec.footer();
foot = foot{end};   % Panel details off: the one line
foot_ok = startsWith(foot, ['Run ' run_id]) && contains(foot, 'colours ') && ...
    ~isempty(regexp(foot, 'saved \d{4}-\d{2}-\d{2} \d{2}:\d{2}', 'once')) && ...
    (contains(foot, 'percentile, auto)') || contains(foot, '(typed)') || ...
    contains(foot, '(recorded with the projection, ') || ...   % was "typed on the ... tab"
    contains(foot, '(from the app''s limits)'));
plain = fullfile(out, 'x18_plain.png');
with_foot = fullfile(out, 'x18_footer.png');
om_export.save_figure_part(ax, plain, 'image');
om_export.save_figure_part(ax, with_foot, 'image', foot);
taller = size(imread(with_foot), 1) > size(imread(plain), 1) && size(imread(p), 2) >= size(imread(plain), 2);
% the window: its default name, footer, no MATLAB menu bar or toolbar
btn = findobj(fig, 'Tag', 'ReconstructionViewerSave');
pw = fullfile(out, 'x18_window.png');
headless_push('uiputfile', pw);
btn.Callback(btn, []);
call = getappdata(groot, 'om_headless_last_uiputfile');
win_ok = numel(call) >= 3 && strcmp(call{3}, fullfile(out, [run_id '_visualise.png'])) && ...
    any(strcmp(call{1}(:, 2), 'PDF (image, 300 dpi) (*.pdf)')) && strcmp(st.String, ['Saved: ' rabbit_reconstruction_tab.display_path(pw, 90)]) && ...
    image_ok(pw) && strcmp(fig.MenuBar, 'none') && strcmp(fig.ToolBar, 'none');
results = add(results, struct('id', ['X18 Visualise saves: <run id>_<panel> names, exports folder first, last folder ' ...
    'next, "Saved:" status, footer line, PDF (image, 300 dpi), no MATLAB menus'], ...
    'ok', name_ok && cancel_ok && first_ok && pdf_panel && status_ok && next_ok && foot_ok && taller && win_ok, ...
    'detail', sprintf('name %d cancel %d first %d pdf %d status %d next %d footer %d taller %d window %d | %s', ...
    name_ok, cancel_ok, first_ok, pdf_panel, status_ok, next_ok, foot_ok, taller, win_ok, foot)));
setappdata(groot, 'reconstruction_export_folder', '');
end


function r = buttons_ok(name, ax, has_csv, n_buttons)
% X1: the toolbar button and the right-click items call om_export.save_dialog
if nargin < 4, n_buttons = []; end
detail = '';
ok = ~isempty(ax) && isgraphics(ax) && om_export.has_button(ax);
if ok
    b = findobj(ax.Toolbar.Children, 'Tag', om_export.BUTTON_TAG);
    cm = ax.ContextMenu;
    mi = findobj(cm, 'Tag', 'om_export_image');
    mc = findobj(cm, 'Tag', 'om_export_csv');
    fb = func2str(b.ButtonPushedFcn);
    ok = contains(fb, 'om_export.save_dialog(ax,''any'')') && ~isempty(mi) && ...
        contains(func2str(mi.MenuSelectedFcn), 'om_export.save_dialog(ax,''image'')') && ...
        (has_csv == ~isempty(mc)) && (~has_csv || contains(func2str(mc.MenuSelectedFcn), 'om_export.save_dialog(ax,''csv'')')) && ...
        strcmp(b.Tooltip, ternary_tip(has_csv));
    if ~isempty(n_buttons)
        ok = ok && numel(ax.Toolbar.Children) == n_buttons;
    end
    detail = sprintf('%d toolbar buttons; %s', numel(ax.Toolbar.Children), fb);
    % X8: the toolbar shows the buttons it showed before (base a987146),
    % plus the save button. Read at a987146 on these visuals (headless,
    % the same flows): MATLAB's default toolbar on the main view, the
    % signal axes, the beat averaging plot, the ECG trace, the reference
    % recording's frames and the segmentation preview; no toolbar
    % (Toolbar.Visible off) on the APD trace, the histograms, both
    % restitution graphs and the Visualise panels. Those are the ones
    % called here with n_buttons = 1.
    [tb_ok, tb_detail] = toolbar_set_ok(ax, isempty(n_buttons));
    ok = ok && tb_ok;
    detail = [detail ' | ' tb_detail];
end
r = struct('id', ['X1/X8 ' name ': toolbar save button and right-click items; the earlier buttons plus save'], ...
    'ok', ok, 'detail', detail);
end


function [ok, detail] = toolbar_set_ok(ax, default_before)
% The shown toolbar buttons equal what was shown before plus the save
% button. Before = MATLAB's default toolbar for what this axes draws (read
% on a copy of it with its own default toolbar), or no buttons.
shown = shown_tags(ax.Toolbar);
before = {};
if default_before
    f = figure('Visible', 'off');
    c = copyobj(ax, f);
    drawnow;   % MATLAB decides the default buttons from what is drawn
    ref = axtoolbar(c, 'default');
    drawnow;
    before = shown_tags(ref);
    delete(f);
end
want = sort([before, {om_export.BUTTON_TAG}]);
ok = isequal(sort(shown), want) && (default_before || ~any(strcmp(shown, 'export')));
detail = sprintf('shown [%s], before [%s]', strjoin(shown, ','), strjoin(before, ','));
end


function tags = shown_tags(tb)
% Tags of the toolbar's visible buttons
tags = {};
for k = 1:numel(tb.Children)
    if strcmp(tb.Children(k).Visible, 'on')
        tags{end + 1} = tb.Children(k).Tag; %#ok<AGROW>
    end
end
end


function r = files_ok(name, ax, stem, has_csv)
% X2: PNG, JPG, PDF (and CSV) through save_to, and PNG through the file dialog
txt = {};
ok = true;
for e = {'.png', '.jpg', '.pdf'}
    p = [stem e{1}];
    try
        om_export.save_to(ax, p);
        if strcmp(e{1}, '.pdf'), good = pdf_ok(p); else, good = image_ok(p); end
    catch ME
        good = false; txt{end + 1} = ME.message; %#ok<AGROW>
    end
    ok = ok && good;
    txt{end + 1} = sprintf('%s %d', e{1}, good); %#ok<AGROW>
end
if has_csv
    try
        om_export.save_to(ax, [stem '.csv']);
        ok = ok && isfile([stem '.csv']);
    catch ME
        ok = false; txt{end + 1} = ME.message;
    end
end
p = [stem '_dialog.png'];
headless_push('uiputfile', p);
[got, err] = om_export.save_dialog(ax, 'any');
ok = ok && strcmp(got, p) && isempty(err) && image_ok(p);
txt{end + 1} = sprintf('dialog %d %s', image_ok(p), err);
r = struct('id', ['X2 ' name ': PNG, JPG, PDF' csv_word(has_csv)], 'ok', ok, 'detail', strjoin(txt, ', '));
end


function ok = log_ok(p)
% save_log_file wrote it: it names the notes and the history
ok = isfile(p) && contains(fileread(p), 'history', 'IgnoreCase', true);
end


function w = csv_word(has_csv)
w = '';
if has_csv, w = ' and CSV'; end
end


function ok = image_ok(p)
% the picture opens and is a sane size
ok = false;
if ~isfile(p), return; end
try
    I = imread(p);
    d = dir(p);
    ok = size(I, 1) >= 50 && size(I, 2) >= 50 && size(I, 1) <= 20000 && d.bytes > 500;
catch
end
end


function ok = pdf_ok(p)
% the file starts with %PDF and is a sane size
ok = false;
if ~isfile(p), return; end
fid = fopen(p, 'r');
head = fread(fid, 4, '*char')';
fclose(fid);
d = dir(p);
ok = strcmp(head, '%PDF') && d.bytes > 1000;
end


function r = table_csv_ok(name, p, header, cols)
% X3: one header row, then exactly the given columns (NaN = empty cell)
ok = false; detail = '';
if isfile(p)
    lines = readlines(p, 'EmptyLineRule', 'skip');
    got_header = cellstr(split(lines(1), ','))';
    body = lines(2:end);
    n = max(cellfun(@numel, cols));
    ok = isequal(got_header, header) && numel(body) == n && ~any(contains(body, 'NaN'));
    for k = 1:numel(cols)
        v = double(cols{k}(:));
        cells = arrayfun(@(s) field(s, k), body);
        want = nan(n, 1); want(1:numel(v)) = v;
        ok = ok && isequaln(str2double(cells), want);
    end
    detail = sprintf('header [%s], %d rows', strjoin(got_header, ', '), numel(body));
end
r = struct('id', ['X3 ' name ': exactly the plotted data'], 'ok', ok, 'detail', detail);
end


function s = field(line, k)
parts = split(line, ',');
s = "";
if k <= numel(parts), s = parts(k); end
end


function r = matrix_csv_ok(name, ax, p, M, default_name)
% X3: a map's CSV is the plain matrix (no header, NaN as text) under a
% default name with the quantity and unit
[ok, detail] = read_matrix_csv(p, M);
spec = getappdata(ax, 'om_export');
got_name = spec.csv_name();
ok = ok && strcmp(got_name, default_name);
r = struct('id', ['X3 ' name ': the shown matrix, no header, named ' default_name], 'ok', ok, ...
    'detail', [detail ' | default name ' got_name]);
end


function [ok, detail] = read_matrix_csv(p, M)
ok = false; detail = 'missing';
if ~isfile(p), return; end
lines = readlines(p, 'EmptyLineRule', 'skip');
rows = numel(lines);
G = nan(rows, size(M, 2));
for k = 1:rows
    v = str2double(split(lines(k), ','))';
    G(k, 1:numel(v)) = v;
end
cells = split(lines(1), ',');
first = str2double(cells);
header_free = ~any(isnan(first) & strlength(cells) > 0 & cells ~= "NaN");
all_cells = split(join(lines, ','), ',');
rm = readmatrix(p);
ok = isequaln(G, double(M)) && header_free && ~any(strlength(all_cells) == 0) && ...
    nnz(all_cells == "NaN") == nnz(isnan(M)) && isequaln(rm, double(M));
detail = sprintf('%d x %d, %d NaN cells, readmatrix %s', rows, size(M, 2), nnz(isnan(M)), mat2str(size(rm)));
end


function r = overlay_ok(out)
% Overlaid axes (the BioPAC trace over the ROI signals): one picture of
% both, and a CSV with a time column for each time base
f = uifigure('Visible', 'off');
a1 = axes(f, 'Units', 'pixels', 'Position', [60 60 300 200]);
h1 = plot(a1, (0:99) / 100, rand(1, 100));
a2 = axes(f, 'Units', 'pixels', 'Position', [60 60 300 200], 'Color', 'none');
h2 = plot(a2, (0:149) / 150, rand(1, 150) * 5 + 8.5, 'r');
series = struct('h', {h1, h2}, 'x', {'time_s', 'biopac_time_s'}, 'y', {'roi1_signal_au', 'biopac_plotted_au'}, 'err', {'', ''});
spec = struct('name', 'signals', 'targets', @() [a1 a2], 'csv', @(p) om_export.write_series(p, series));
om_export.attach(a1, spec);
om_export.attach(a2, spec);
p = fullfile(out, 'overlay');
om_export.save_to(a2, [p '.png']);
om_export.save_to(a2, [p '.pdf']);
om_export.save_to(a2, [p '.csv']);
r = table_csv_ok('overlaid signal + BioPAC axes CSV (own time base)', [p '.csv'], ...
    {'time_s', 'roi1_signal_au', 'biopac_time_s', 'biopac_plotted_au'}, {h1.XData, h1.YData, h2.XData, h2.YData});
r.ok = r.ok && image_ok([p '.png']) && pdf_ok([p '.pdf']);
delete(f);
end


function r = aspect_ok(name, stem)
% X10: the PDF page (MediaBox) has the PNG's aspect within 10 %
png = [stem '.png']; pdf = [stem '.pdf'];
ok = false; detail = 'missing';
if isfile(png) && isfile(pdf)
    I = imread(png);
    box = pdf_mediabox(pdf);
    if numel(box) == 4
        a_png = size(I, 2) / size(I, 1);
        a_pdf = (box(3) - box(1)) / (box(4) - box(2));
        ok = abs(a_pdf / a_png - 1) <= 0.10;
        detail = sprintf('PNG %d x %d (%.3f), PDF page %.0f x %.0f pt (%.3f)', size(I, 2), size(I, 1), a_png, ...
            box(3) - box(1), box(4) - box(2), a_pdf);
    else
        detail = 'no MediaBox found';
    end
end
r = struct('id', ['X10 ' name ': the PDF page has the PNG''s aspect'], 'ok', ok, 'detail', detail);
end


function box = pdf_mediabox(p)
% The first page's MediaBox [x0 y0 x1 y1] in points, or []
fid = fopen(p, 'r');
txt = fread(fid, Inf, '*char')';
fclose(fid);
tok = regexp(txt, '/MediaBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]', 'tokens', 'once');
box = str2double(tok);
end


function r = isochrones_ok(name, a, ax, map, csv_name, out)
% X11: picture with the filled contours shown, CSV = the map, its name
stem = fullfile(out, ['iso_' regexprep(name, '\W', '_')]);
n_screen = numel(findobj(ax, '-depth', 1, 'Type', 'contour', 'Fill', 'on'));
capture_start();
om_export.save_to(ax, [stem '.png']);
cap = capture_stop();
om_export.save_to(ax, [stem '.csv']);
[ok_csv, txt] = read_matrix_csv([stem '.csv'], map);
spec = getappdata(ax, 'om_export');
got = spec.csv_name();
shown_zero = all(a.display.image_handle.CData(:) == 0);
ok = n_screen > 0 && ~isempty(cap) && cap.n_filled == n_screen && ok_csv && strcmp(got, csv_name);
r = struct('id', ['X11 isochrones on the ' name ': picture with the contours, CSV of the map, named ' csv_name], ...
    'ok', ok, 'detail', sprintf('%d contours on screen (image set to zero %d), %s | CSV %s | name %s', n_screen, ...
    shown_zero, capture_text(cap), txt, got));
end


function r = no_git_ok(a, ax, out)
% X13: GIT_DIR to nowhere, as outside a git checkout; then a log file that
% cannot be written
d = fullfile(out, 'no_git');
mkdir(d);
old = getenv('GIT_DIR');
setenv('GIT_DIR', fullfile(out, 'no_such_git_dir'));
restore = onCleanup(@() setenv('GIT_DIR', old)); %#ok<NASGU>
n0 = numel(getappdata(groot, 'om_headless_dialogs'));
headless_push('uiputfile', fullfile(d, 'map.png'));
[got, err] = om_export.save_dialog(ax, 'image');
logs = dir(fullfile(d, '*.dat'));
log_txt = '';
if ~isempty(logs), log_txt = fileread(fullfile(d, logs(1).name)); end
ok1 = strcmp(got, fullfile(d, 'map.png')) && isempty(err) && isfile(got) && numel(logs) == 1 && ...
    contains(log_txt, 'Current git commit: ,unknown') && contains(log_txt, 'history', 'IgnoreCase', true);
% the log file's folder does not exist (a recording name with a folder in it)
name = a.file_info.name;
a.file_info.name = ['no_such_folder' filesep 'x'];
headless_push('uiputfile', fullfile(d, 'map2.png'));
[got2, err2] = om_export.save_dialog(ax, 'image');
a.file_info.name = name;
dl = getappdata(groot, 'om_headless_dialogs');
msgs = {};
if numel(dl) > n0, msgs = {dl(n0 + 1:end).message}; end
failed = any(contains(msgs, 'Could not save'));
warned = any(contains(msgs, 'log file could not be written'));
ok2 = isempty(err2) && isfile(got2) && warned;
r = struct('id', 'X13 outside a git checkout: picture and log file (commit unknown), no failure reported', ...
    'ok', ok1 && ok2 && ~failed, 'detail', sprintf('%s | %s | logs %d | messages: %s', err, err2, numel(logs), ...
    strjoin(msgs, ' / ')));
end


function r = nothing_yet_ok(ax, p)
% X17: the CSV of an empty graph: no file, "nothing to save yet", and no
% file dialog asked for (the queued answer is still there afterwards)
n0 = numel(getappdata(groot, 'om_headless_dialogs'));
headless_push('uiputfile', p);
err = '';
printed = evalc('[~, err] = om_export.save_dialog(ax, ''csv'');');
dl = getappdata(groot, 'om_headless_dialogs');
msgs = {}; kinds = {}; told_as = {};
if numel(dl) > n0
    msgs = {dl(n0 + 1:end).message}; kinds = {dl(n0 + 1:end).kind};
    told_as = strcat({dl(n0 + 1:end).title}, {' - '}, msgs);   % title and message, as shown
end
[unused, left] = headless_pop('uiputfile');   % drained, so later checks start clean
no_dialog = unused && strcmp(left, p) && ~any(strcmp(kinds, 'uiputfile'));
told = contains(printed, 'Nothing to save yet') || any(contains(told_as, 'Nothing to save yet'));
% the prefix once (it was printed and shown twice: "Nothing to save yet:
% Nothing to save yet: ...")
once = numel(strfind(printed, 'Nothing to save yet')) <= 1 && ...
    all(cellfun(@(t) numel(strfind(t, 'Nothing to save yet')) <= 1, told_as));
ok = ~isfile(p) && contains(err, 'Nothing to save yet') && told && once && ~any(contains(msgs, 'Could not save')) && no_dialog;
r = struct('id', 'X17 restitution curve CSV before a curve is drawn: "nothing to save yet" (once), no file dialog', 'ok', ok, ...
    'detail', sprintf('err "%s" | printed "%s" | dialog asked %d | dialogs %s', err, strtrim(printed), ~no_dialog, ...
    strjoin(msgs, ' / ')));
end


function o = overlap(a, b)
% True when two [x y w h] rectangles overlap
o = a(1) < b(1) + b(3) && b(1) < a(1) + a(3) && a(2) < b(2) + b(4) && b(2) < a(2) + a(4);
end


function capture_start()
% Record the hidden figure the main view is rebuilt in, when it is deleted
setappdata(groot, 'probe_export_capture', []);
set(groot, 'DefaultFigureDeleteFcn', @capture_figure);
end


function cap = capture_stop()
set(groot, 'DefaultFigureDeleteFcn', '');
cap = getappdata(groot, 'probe_export_capture');
end


function capture_figure(f, ~)
% The first figure deleted that has an axes (not om_export's PDF page):
% colour bar label, colour map, filled contours, x label, and the colour
% bar's place next to the axes [x y w h] in pixels
cb = findall(f, 'Type', 'colorbar');
ax = findall(f, 'Type', 'axes');
if any(strcmp(f.Tag, {'om_export_pdf_page', 'om_export_footer'})) || isempty(ax) || ~isempty(getappdata(groot, 'probe_export_capture'))
    return;
end
c = struct('label', '', 'cmap', ax(1).Colormap, 'n_filled', numel(findall(f, 'Type', 'contour', 'Fill', 'on')), ...
    'xlabel', char(ax(1).XLabel.String), 'cb_off', [], 'n_sub', numel(cellstr(ax(1).Subtitle.String)), ...
    'hist_n', sum(arrayfun(@(h) sum(h.Values), findall(f, 'Type', 'histogram'))));
if ~isempty(cb)
    c.label = char(cb(1).Label.String);
    pa = getpixelposition(ax(1)); pc = getpixelposition(cb(1));
    c.cb_off = [pc(1:2) - pa(1:2), pc(3:4)];
end
setappdata(groot, 'probe_export_capture', c);
end


function v = capture_field(cap, name)
v = [];
if ~isempty(cap), v = cap.(name); end
end


function txt = capture_text(cap)
if isempty(cap)
    txt = 'no saved figure seen';
else
    txt = sprintf('label "%s", colour map %d x 3, %d filled contours, x label "%s"', cap.label, size(cap.cmap, 1), ...
        cap.n_filled, cap.xlabel);
end
end


function results = add(results, r)
results(end + 1) = r;
end
