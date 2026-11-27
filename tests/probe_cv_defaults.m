function probe_cv_defaults
%% Probe: the Bayly defaults of the Conduction Velocity tab (3x3 median of the activation times, two-frame time window)
% Collin Snitchler
% 24.11.2026
% The defaults: Bayly runs on the activation map after
% a 3 x 3 median (NaN ignored, within the tissue, never across a view seam),
% and the time window is two frame intervals (2000/fps ms; at least 10 ms)
% until a value is
% typed. Both are settings on the tab (rabbit_cv_map.controls).
%   D1  a synthetic planar wave at 0.5 m/s with 4 ms of activation-time
%       noise reads 0.45-0.55 m/s with the defaults (and further off without)
%   D2  the median never mixes values across a view seam, nor takes values
%       from outside the tissue, and leaves pixels without a time empty
%   D3  through the app (CV map button): the checkbox ticked and the window
%       at 2 frames by default, the label says so, History names both
%   D4  unticked, with the window typed at 6 ms, the app gives the old map
%       (rabbit_cv_map.bayly on the map as it is), bit for bit
%   D5  a typed window is kept when the recording is loaded again
%   D6  a workspace saved without CV settings loads with the old ones (no
%       smoothing, 6 ms) and a History line, and its CV map is made again
%       with them; a recording loaded next gets the defaults; a workspace
%       with its own settings keeps them
%   D7  the slowest speed fully resolved beside
%       Time max, "Lower/Upper colour limit", the file's name only (it was
%       cut from the left); the Activation Map
%       tab's limits typed while the CV map is shown leave its colours at
%       the CV tab's limits, the colour bar "CV (m/s)", with room for its
%       labels inside the window
%   D8  CV mean: median, IQR, 5th-95th, the count
%       above 3 m/s, then the mean, then the rhythm lines
%   D9  the colour bar under the CV arrows says
%       what its colours are after New zero and the isolines on and off
%       (the activation map, the arrows named) and after the CV map again
%   D1b, D7b Nearest Neighbour reads further off on D1's noisy
%       wave; the method's tooltip prefers Bayly, as Help does
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_cv_defaults"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');   % the app must stay hidden
repo_dir = fileparts(fileparts(mfilename('fullpath')));    % the repository folder (this file is in tests/)
addpath(repo_dir);                                          % the app and its helpers
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));   % dialog stand-ins
pass = 0; fail = 0;                                         % check counters
    function check(id, ok, detail)
        tag = 'FAIL';
        if ok, tag = 'PASS'; end
        fprintf('%s %s: %s\n', tag, id, detail);
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end

%% D1: a planar wave, 0.5 m/s, 4 ms noise, 258 um/pixel, 204 fps, Bayly 3 mm
fps = 204.0136;
rng(5, 'twister');                                          % repeatable noise
H = 70; W = 70;
[c, r] = meshgrid(1:W, 1:H);
d_mm = (r * cos(0.5) + c * sin(0.5)) * 0.258;              % distance along the wave, mm
T0 = 60 + (d_mm - min(d_mm(:))) / 0.5;                      % 0.5 mm/ms
act = T0 + 4 * randn(H, W);                                 % activation-time noise, 4 ms SD
S = 258 * ones(H, W); V = ones(H, W);
inner = @(cv) median(reshape(cv(13:end - 12, 13:end - 12, 3), [], 1), 'omitnan');
v_def = inner(rabbit_cv_map.bayly(rabbit_cv_map.median3(act, V), S, V, 3, rabbit_cv_map.two_frames(fps)));
v_old = inner(rabbit_cv_map.bayly(act, S, V, 3, 6));
check('D1', v_def >= 0.45 && v_def <= 0.55, sprintf('0.5 m/s wave, 4 ms noise: %.3f m/s with the defaults, %.3f without', v_def, v_old));
% Help and the method's tooltip call Nearest Neighbour noise-sensitive
% and prefer Bayly; on the same noisy wave it reads further from 0.5 m/s
v_nn = inner(rabbit_cv_map.nearest(act, S, V, fps));
check('D1b', abs(v_nn - 0.5) > abs(v_def - 0.5), sprintf('0.5 m/s wave, 4 ms noise: Nearest Neighbour %.3f m/s, Bayly defaults %.3f', v_nn, v_def));

%% D2: the median within one view and within the tissue
a2 = [10 * ones(5, 4), 100 * ones(5, 4)];                  % two views, 90 ms apart
a2(3, 2) = 13;                                              % one value off in view 1
a2(2, 7) = NaN;                                             % a pixel outside the tissue in view 2
V2 = [ones(5, 4), 2 * ones(5, 4)];
m2 = rabbit_cv_map.median3(a2, V2);
own = all(m2(:, 1:4) == 10, 'all');                        % the 13 is smoothed away, nothing from view 2
seam_ok = all(m2(:, 4) == 10) && all(m2(~isnan(a2) & V2 == 2) == 100) && isnan(m2(2, 7));
V3 = V2; V3(:, 4) = 0;                                      % a column with no view: left out
m3 = rabbit_cv_map.median3(a2, V3);
check('D2', own && seam_ok && all(isnan(m3(:, 4))) && all(m3(:, 3) == 10), ...
    sprintf('seam columns %s | %s', mat2str(m2(:, 4)'), mat2str(m2(:, 5)')));

%% The app: a synthetic recording at 204 fps
root = tempname;                                            % throw-away folder for the recording
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
stack = 1000 + 100 * rand(H, W, 30);                        % the app loads the variable 'stack'
rec = fullfile(root, 'synthetic_recording.mat');
save(rec, 'stack');
a = analyse_optical_mapping;                                % start the app (hidden)
app_cleanup = onCleanup(@() delete(a));
headless_push('uigetfile', rec);                            % File selector
headless_push('inputdlg', {num2str(fps, 10)});              % Enter fps
headless_push('uiconfirm', 'Continue');                     % no regions
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
box = findall(a.GridLayout22, 'Tag', 'CvSmoothCheckBox');
% max(2000/fps, 10 ms): 10 ms at 204 fps (9.80 before)
D3a = isscalar(box) && box.Value && abs(a.timemax.Value - max(2000 / fps, 10)) < 1e-9 && a.timemax.Value == 10 && ...
    strcmp(a.TimemaxmsEditFieldLabel.Text, 'Time max (ms)') && contains(strjoin(cellstr(a.timemax.Tooltip), ' '), '2 frames') && ...   % R14: the default in the tooltip
    a.distancemax.Value == 3 && ...
    rabbit_cv_map.default_window(1000) == 10 && abs(rabbit_cv_map.default_window(100) - 20) < 1e-12;
% the time window's tooltip gives the formula and the value shown
tw3 = strjoin(cellstr(a.timemax.Tooltip), ' ');
check('D3t', contains(tw3, sprintf('max(2 frames, 10 ms) = max(2000 / %.4g fps, 10 ms) = 10.0 ms at %.4g fps', fps, fps)), tw3);
a.processed_data.scale = 258;                               % um/pixel, one value (single-view data)
a.CV_method.Value = 'Bayly Method';
    function cv = press(map)
        a.processed_data.activation_map = map;
        a.display.image_handle.Parent.CLim = [0, max(map(:))];
        headless_push('uiconfirm', 'Yes');                  % the activation map is made
        feval(a.CV_map.ButtonPushedFcn, a.CV_map, []);
        cv = a.processed_data.CV_map;
    end
cv_app = press(act);
h = a.history_field.Value{end};
ref = rabbit_cv_map.bayly(rabbit_cv_map.median3(act, V), S, V, 3, max(2000 / fps, 10));
check('D3', D3a && isequaln(cv_app, ref) && contains(h, sprintf('Smoothing: 3%s3 median', char(215))) && ...
    contains(h, '(2 frames, at least 10 ms)') && a.processed_data.CV_settings.smooth_activation, ...
    sprintf('%s | label "%s"', h, a.TimemaxmsEditFieldLabel.Text));

%% D4: unticked, 6 ms typed: the old result
box.Value = false;
a.timemax.Value = 6;
feval(a.timemax.ValueChangedFcn, a.timemax, []);            % as typed in the field
cv_app = press(act);
h = a.history_field.Value{end};
ref = rabbit_cv_map.bayly(act, S, V, 3, 6);
check('D4', isequaln(cv_app, ref) && contains(h, 'Smoothing: none') && contains(h, '6 ms (typed)') && ...
    strcmp(a.TimemaxmsEditFieldLabel.Text, 'Time max (ms)'), h);

%% D7: the CV tab's wording
% the method dropdown's tooltip prefers Bayly, Nearest Neighbour noise-sensitive
tip7 = strjoin(cellstr(a.CV_method.Tooltip), ' ');
check('D7b', contains(tip7, 'Bayly Method (preferred)') && contains(tip7, 'noise-sensitive, and Bayly is preferred'), tip7);
% beside Time max: the slowest speed fully resolved, distance max / time max
slow = findall(a.GridLayout22, 'Tag', 'CvSlowestSpeedLabel');
slow_words = sprintf('slowest speed fully resolved %s distance max / time max = ', char(8776));
s_6 = '';
if isscalar(slow), s_6 = slow.Text; end
a.distancemax.Value = 1.5;
feval(a.distancemax.ValueChangedFcn, a.distancemax, []);   % as typed in the field
s_15 = '';
if isscalar(slow), s_15 = slow.Text; end
a.distancemax.Value = 3;
feval(a.distancemax.ValueChangedFcn, a.distancemax, []);
% on the tab, "= 0.5 m/s"
% is held together by non-breaking spaces, so "m/s" never wraps alone
nb = char(160);
on_tab = @(v) [slow_words(1:end - 3) nb '=' nb v nb 'm/s'];
slow_ok = strcmp(s_6, on_tab('0.5')) && strcmp(s_15, on_tab('0.25')) && ...
    strcmp(rabbit_cv_map.slowest_text(3, 2000 / fps), [slow_words '0.31 m/s']);
% the CV tab's limit fields colour the map: "colour limit", not "Y limit"
limits_ok = strcmp(a.LowerYlimitEditFieldLabel_2.Text, 'Lower colour limit') && ...
    strcmp(a.UpperYlimitEditFieldLabel_2.Text, 'Upper colour limit');
% the Activation Map tab's limits typed while the CV
% map is shown are kept in their fields only; the CV map keeps the CV tab's
% colour limits and the colour bar "CV (m/s)" (it was coloured 50.66-147.47:
% black)
cv_clim = [a.lowerylimit_traces.Value, a.upperylimit_traces.Value];
a.lowerylimit.Value = 50.66; a.upperylimit.Value = 147.47;
feval(a.upperylimit.ValueChangedFcn, a.upperylimit, []);
clim_act = a.display.image_handle.Parent.CLim;
bar_act = cellstr(a.display.colourbar_handle.Label.String);
feval(a.upperylimit_traces.ValueChangedFcn, a.upperylimit_traces, []);
bar_cv = cellstr(a.display.colourbar_handle.Label.String);
% and room for the colour bar's tick labels and label inside the window (B1)
cbp = getpixelposition(a.display.colourbar_handle, true);
room_ok = cbp(1) + cbp(3) + 70 <= a.opticalmappingUIFigure.Position(3) + 1;
bar_ok = room_ok && isequal(clim_act, cv_clim) && isequal(bar_act, {'CV (m/s)'}) && isequal(bar_cv, {'CV (m/s)'}) && ...
    a.upperylimit.Value == 147.47 && a.lowerylimit.Value == 50.66;
% the file's name only (it was the path cut from the left, after an ellipsis)
tip = char(strjoin(cellstr(a.tool_tip.Value), ' '));
file_ok = contains(tip, 'File name: synthetic_recording.mat') && ~contains(tip, char(8230));
check('D7', slow_ok && limits_ok && bar_ok && file_ok, sprintf(['slowest "%s" / "%s" %d | limits "%s"/"%s" | ' ...
    'bar "%s" then "%s", CLim %s (CV fields %s) | %s'], s_6, s_15, slow_ok, a.LowerYlimitEditFieldLabel_2.Text, ...
    a.UpperYlimitEditFieldLabel_2.Text, strjoin(bar_act, ' / '), strjoin(bar_cv, ' / '), mat2str(clim_act, 4), ...
    mat2str(cv_clim, 4), tip));

%% D9: every path that changes the main view
% under the CV arrows leaves a colour bar that says what its colours are:
% New zero and the isolines on the Activation Map tab put the activation map
% under the arrows (its label, the arrows named); the CV map made again has
% its own title
want_act = {'Activation time (ms)', 'magenta arrows: conduction velocity direction (CV map)'};
bar_of = @() reshape(cellstr(a.display.colourbar_handle.Label.String), 1, []);   % its lines, as a row
cv_shown = @(x) ~isempty(x.display.quiver_handle) && all(isvalid(x.display.quiver_handle));   % the arrows are on
headless_push('inputdlg', {'0'});
feval(a.newzeromap.ButtonPushedFcn, a.newzeromap, []);
bar_zero = bar_of();
arrows = cv_shown(a);
a.mapisolines.Value = true;
feval(a.mapisolines.ValueChangedFcn, a.mapisolines, []);
bar_iso_on = bar_of();
a.mapisolines.Value = false;
feval(a.mapisolines.ValueChangedFcn, a.mapisolines, []);
bar_iso_off = bar_of();
press(act);
bar_again = bar_of();
check('D9', arrows && isequal(bar_zero, want_act) && isequal(bar_iso_on, want_act) && isequal(bar_iso_off, want_act) && ...
    isequal(bar_again, {'CV (m/s)'}) && cv_shown(a), ...
    sprintf('arrows %d | New zero "%s" | isolines on "%s", off "%s" | CV again "%s"', arrows, strjoin(bar_zero, ' / '), ...
    strjoin(bar_iso_on, ' / '), strjoin(bar_iso_off, ' / '), strjoin(bar_again, ' / ')));

%% D8: CV mean leads with the median, IQR and 5th-95th, then the count above 3 m/s; the mean last
sp = a.processed_data.CV_map(:, :, 3);
sp = sp(isfinite(sp));
n_dl = numel(getappdata(groot, 'om_headless_dialogs'));
feval(a.CVmean.ButtonPushedFcn, a.CVmean, []);
dl = getappdata(groot, 'om_headless_dialogs');
msg = '';
if numel(dl) > n_dl, msg = dl(end).message; end
q = prctile(sp, [25 75]);
% the outlier rule's thresholds, 1.5 and 5 m/s, no 3 m/s
want_fast = sprintf('Above 1.5 m/s: %d of %d (%.1f %%); above 5 m/s: %d', nnz(sp > 1.5), numel(sp), ...
    100 * nnz(sp > 1.5) / numel(sp), nnz(sp > 5));
at = @(w) min([strfind(msg, w), Inf]);
order_ok = at('Median: ') == 1 && at('Median: ') < at('IQR') && at('IQR') < at(sprintf('5th%s95th', char(8211))) && ...
    at(sprintf('5th%s95th', char(8211))) < at('Above 1.5 m/s') && at('Above 1.5 m/s') < at('Absolute mean') && ...
    isfinite(at('Absolute mean')) && at('Absolute mean') < at('Rhythm:');
check('D8', order_ok && contains(msg, sprintf('IQR %.3f%s%.3f', q(1), char(8211), q(2))) && contains(msg, want_fast) && ...
    ~contains(msg, 'mm/ms') && contains(msg, 'Absolute mean: ') && contains(msg, ' m/s, std '), ...
    strrep(msg, newline, ' | '));

%% D5: the typed window stays when a recording is loaded again
headless_push('uigetfile', rec);
headless_push('inputdlg', {num2str(fps, 10)});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
s = rabbit_cv_map.settings(a);
check('D5', a.timemax.Value == 6 && strcmp(s.time_max_source, 'typed'), ...
    sprintf('%g ms, %s', a.timemax.Value, s.time_max_source));

%% D6: workspaces, in a second app
delete(a);
b = analyse_optical_mapping;
b_cleanup = onCleanup(@() delete(b));
headless_push('uigetfile', rec);
headless_push('inputdlg', {num2str(fps, 10)});
headless_push('uiconfirm', 'Continue');
feval(b.LoadfileMenu.MenuSelectedFcn, b.LoadfileMenu, []);
b.processed_data.scale = 258;
b.CV_method.Value = 'Bayly Method';
b.processed_data.activation_map = act;
b.display.image_handle.Parent.CLim = [0, max(act(:))];
headless_push('uiconfirm', 'Yes');
feval(b.CV_map.ButtonPushedFcn, b.CV_map, []);
b.SavetoEditField.Value = [root filesep];
feval(b.saveworkspace.MenuSelectedFcn, b.saveworkspace, []);
ws = dir(fullfile(root, '*_workspace_*.mat'));
ws = fullfile(root, ws(1).name);
W1 = load(ws);
W1.processed_data_int = rmfield(W1.processed_data_int, 'CV_settings');   % as saved before 24.11.2026
ws_old = fullfile(root, 'old_workspace.mat');
save(ws_old, '-struct', 'W1', '-v7.3');
W2 = load(ws);
W2.processed_data_int.CV_settings.smooth_activation = false;              % a workspace's own settings
W2.processed_data_int.CV_settings.time_max_ms = 7.5;
W2.processed_data_int.CV_settings.time_max_source = 'typed';
ws_new = fullfile(root, 'new_workspace.mat');
save(ws_new, '-struct', 'W2', '-v7.3');
box_b = findall(b.GridLayout22, 'Tag', 'CvSmoothCheckBox');
% an old workspace: no smoothing, 6 ms, and History says so; making its CV map again keeps them
headless_push('uigetfile', ws_old);
feval(b.loadworkspace.MenuSelectedFcn, b.loadworkspace, []);
hist_old = b.history_field.Value;
old_ok = ~box_b.Value && b.timemax.Value == 6 && strcmp(b.TimemaxmsEditFieldLabel.Text, 'Time max (ms)') && ...
    any(startsWith(hist_old, 'Workspace from before the CV defaults changed: CV settings kept as they were (no smoothing, 6 ms).'));
b.display.image_handle.Parent.CLim = [0, max(b.processed_data.activation_map(:))];
headless_push('uiconfirm', 'Yes');
feval(b.CV_map.ButtonPushedFcn, b.CV_map, []);
h_old = b.history_field.Value{find(startsWith(b.history_field.Value, 'CV map generated'), 1, 'last')};
old_ok = old_ok && ~box_b.Value && b.timemax.Value == 6 && contains(h_old, 'Smoothing: none') && ...
    contains(h_old, '6 ms (kept from the workspace)');
% a new analysis after it: the defaults
headless_push('uigetfile', rec);
headless_push('inputdlg', {num2str(fps, 10)});
headless_push('uiconfirm', 'Continue');
feval(b.LoadfileMenu.MenuSelectedFcn, b.LoadfileMenu, []);
fresh_ok = box_b.Value && abs(b.timemax.Value - max(2000 / fps, 10)) < 1e-9 && ...
    contains(strjoin(cellstr(b.timemax.Tooltip), ' '), '2 frames');   % R14: the default in the tooltip
fresh_txt = sprintf('box %d, %g ms, "%s"', box_b.Value, b.timemax.Value, b.TimemaxmsEditFieldLabel.Text);
% a workspace with its own settings keeps them, and History says nothing about old defaults
headless_push('uigetfile', ws_new);
feval(b.loadworkspace.MenuSelectedFcn, b.loadworkspace, []);
s_new = rabbit_cv_map.settings(b);
new_ok = ~box_b.Value && b.timemax.Value == 7.5 && strcmp(s_new.time_max_source, 'typed') && ...
    ~any(startsWith(b.history_field.Value, 'Workspace from before the CV defaults changed'));
check('D6', old_ok && fresh_ok && new_ok, sprintf('old %d (%s), fresh %d (%s), own settings %d (%g ms, %s)', old_ok, h_old, ...
    fresh_ok, fresh_txt, new_ok, b.timemax.Value, s_new.time_max_source));

fprintf('\nPROBE_CV_DEFAULTS RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('probe_cv_defaults:Failed', '%d check(s) failed.', fail);
end
fprintf('PROBE_OK probe_cv_defaults %d/0\n', pass);
end
