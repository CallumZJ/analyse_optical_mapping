function probe_activation_relative
%% Probe: Visualise's "Relative to earliest (1st percentile)" activation option
% Collin Snitchler
% 25.11.2026
% an activation option
% "Relative to earliest (1st percentile)", OFF by default; caption when on:
% "0 = earliest 1 % of faces". Display only. Driven through the app's Redo
% projection, headless, on a copy of a completed run (as probe_cv_range).
%   E1  the checkbox is under the activation panel, unticked; the drawn
%       values are the projected ones; no "0 = earliest" in the caption
%   E2  ticked: every drawn value minus the 1st percentile of the assigned
%       faces' values; the automatic range moves with it; the colour bar
%       says "activation (ms, 0 = earliest 1 % of faces)"; the caption
%       says "0 = earliest 1 % of faces"
%   E3  the low-confidence checkbox toggled while it is on keeps the
%       offset; unticked again: the projected values, the range, the colour
%       bar label from the record and no "0 = earliest" come back
%   E4  the saved files do not change (activation_projected.cdf)
%   E5  a typed range is shifted by the zero when ticked, the shifted
%       values written into the Range box, and the caption says "range
%       shifted with the zero"; unticked, the typed text comes back
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_activation_relative" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_activation_relative', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset and a map; projected with a lowered edge weight (class-4 faces)
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
app.processed_data.activation_map = map;
app.processed_data.image_stack = {frames};
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
rabbit_activation_zero.mark(app, 'df/dt');
app.recon.ReconstructionEdgeWeightField.Value = 0.3;
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map only');
app.recon.ReconstructionReprojectButtonPushed();
cdf = fullfile(run_dir, 'outputs', 'reprojection', 'activation_projected.cdf');
cdf_before = fileread(cdf);
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
fig_cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
ax = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
box = findobj(fig, 'Tag', 'ReconstructionActivationRelative');
low = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
d0 = getappdata(fig, 'reconstruction_activation');
clim0 = ax.CLim;
fd = tab.viewer_face_entry(fig, 'projected');
p1 = prctile(double(fd.values(fd.assigned(:) & isfinite(fd.values(:)))), 1);
    function t = caption()
        [~, cav] = tab.viewer_activation_caption(fig, struct('activation_semantics', 'CANONICAL', ...
            'source_path', cdf, 'info', struct()));
        t = strjoin(cav, ' / ');
    end
    function t = bar_label()
        t = char(string(ax.Colorbar.Label.String));
    end

%% E1
cap0 = caption();
results = add(results, 'E1 the option is there, off; values as projected; no "0 = earliest"', isscalar(box) && ...
    get(box, 'Value') == 0 && contains(get(box, 'String'), 'Relative to earliest (1st percentile)') && ...
    ~contains(cap0, '0 = earliest') && strcmp(bar_label(), 'activation (ms from start of averaged window)'), ...
    sprintf('label "%s"; 1st percentile %.3f ms', bar_label(), p1));

%% E2
set(box, 'Value', 1);
box.Callback(box, []);
d1 = getappdata(fig, 'reconstruction_activation');
cap1 = caption();
same_nan = isequal(isnan(d1.values), isnan(d0.values));
shift_ok = same_nan && max(abs(d1.values(~isnan(d0.values)) - (d0.values(~isnan(d0.values)) - p1))) < 1e-9;
results = add(results, 'E2 on: values minus the 1st percentile; range, colour bar and caption follow', shift_ok && ...
    max(abs(ax.CLim - (clim0 - p1))) < 1e-9 && strcmp(bar_label(), 'activation (ms, 0 = earliest 1 % of faces)') && ...
    contains(cap1, '0 = earliest 1 % of faces'), sprintf('CLim %s -> %s; %s', mat2str(clim0, 4), mat2str(ax.CLim, 4), cap1));

%% E3
low_ok = true;
if isscalar(low) && strcmp(get(low, 'Enable'), 'on')
    v_before = get(low, 'Value');
    set(low, 'Value', 1 - v_before);
    low.Callback(low, []);
    d2 = getappdata(fig, 'reconstruction_activation');
    st = getappdata(fig, 'reconstruction_confidence');
    st = st(strcmp({st.role}, 'projected'));
    want = st.hidden;
    if 1 - v_before == 1, want = st.all; end
    low_ok = isequaln(d2.values, want - p1);
    set(low, 'Value', v_before);
    low.Callback(low, []);
end
set(box, 'Value', 0);
box.Callback(box, []);
d3 = getappdata(fig, 'reconstruction_activation');
results = add(results, 'E3 the low-confidence toggle keeps the offset; off again restores values, range, label', low_ok && ...
    isequaln(d3.values, d0.values) && max(abs(ax.CLim - clim0)) < 1e-9 && ...
    strcmp(bar_label(), 'activation (ms from start of averaged window)') && ~contains(caption(), '0 = earliest'), ...
    sprintf('low-confidence checked: %d; label "%s"', isscalar(low) && strcmp(get(low, 'Enable'), 'on'), bar_label()));

%% E4
results = add(results, 'E4 the saved files do not change', strcmp(fileread(cdf), cdf_before), '');

%% E5 (R3)
lim_box = findobj(fig, 'Tag', 'ReconstructionActivationLimits');
typed = sprintf('%g %g', round(p1 + 10), round(p1 + 60));
set(lim_box, 'String', typed);
lim_box.Callback(lim_box, []);
want = round(str2num(typed) - p1, 2); %#ok<ST2NM>
set(box, 'Value', 1);
box.Callback(box, []);
on_txt = get(lim_box, 'String');
cap5 = caption();
ok5 = max(abs(str2num(on_txt) - want)) < 1e-9 && max(abs(ax.CLim - want)) < 1e-9 && ...
    contains(cap5, 'range shifted with the zero'); %#ok<ST2NM>
set(box, 'Value', 0);
box.Callback(box, []);
ok5 = ok5 && strcmp(get(lim_box, 'String'), typed) && max(abs(ax.CLim - str2num(typed))) < 1e-9 && ...
    ~contains(caption(), 'range shifted'); %#ok<ST2NM>
results = add(results, 'E5 a typed range moves with the zero, into the box; caption names it; back on untick', ok5, ...
    sprintf('typed "%s", ticked "%s", back "%s"', typed, on_txt, get(lim_box, 'String')));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_ACTIVATION_RELATIVE RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_activation_relative:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_activation_relative %d/0\n', n_pass);
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
