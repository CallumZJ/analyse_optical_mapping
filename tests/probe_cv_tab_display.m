function probe_cv_tab_display
%% Probe: the CV tab's display and outlier choices
% Collin Snitchler
% 25.11.2026
% Through the app (a synthetic recording, a plane wave as the activation map,
% the CV map button):
%   T1  B14: the arrows have a direction and a length of 0.4-1 x the
%       spacing (10 px) from the speed over the colour range; no arrow
%       outside the colour range
%   T2  B9: the CV histogram spans the CV map's display range, its title
%       "<n> values above <x> m/s not shown"
%   T3  B13, W10: the Remove local outliers tooltip names the method; the
%       arrows' tooltip their length; "Distance max (mm)" with the
%       half-width in its tooltip (the long label was cut);
%       the colour limits' tooltip names the basis
%   T4  B7: the CV settings keep the activation map's hash; after the
%       activation map changes, the CV map is not projected (app_cv_speed
%       and the Reconstruction tab's reconstruction_cv_map say why)
%   T6  R1: the CV settings keep the pixel sizes and
%       their sources; after a size changes the CV map is not projected
%       ("made with other pixel sizes"); the surface lifting and the
%       record take the kept sizes
%   T7  R14: "Time max (ms)" (its default in the
%       tooltip); the SET LIMITS panel's last two rows take their controls'
%       height, so New zero is not cut
%   T8  R5: the colour bar reads "CV (m/s)", and
%       "apparent speed (m/s), not CV" for a map whose views activate
%       nearly simultaneously
%   T9  CV mean's message ends with the note on
%       red streaks along a view seam or edge, and CV mean's tooltip has it
%   T10 S4: the CV settings keep the method and the
%       outlier test at CV map time; the records use them; after the
%       method changes the CV map is not projected
%   T5  the outlier test, mean +- 2 SD by default; median +- 3 MAD,
%       edges too, blanks an outlier at the tissue's edge that the 2 SD
%       test cannot test, and History names the method
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_cv_tab_display"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
pass = 0; fail = 0;
    function check(id, ok, detail)
        tag = 'FAIL';
        if ok, tag = 'PASS'; end
        fprintf('%s %s: %s\n', tag, id, detail);
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end
H = 60; W = 60;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
stack = 1000 + 100 * rand(H, W, 30); %#ok<NASGU>
rec = fullfile(root, 'synthetic_recording.mat');
save(rec, 'stack');
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a));
headless_push('uigetfile', rec);
headless_push('inputdlg', {'204.0136'});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
a.processed_data.scale = 258;
a.CV_method.Value = 'Bayly Method';
[cc, rr] = meshgrid(1:W, 1:H);
rng(3, 'twister');
map = 50 + (0.6 * cc + 0.3 * rr) * 0.258 / 0.6 + 0.2 * randn(H, W);   % about 0.6 m/s, with noise
    function press(m)
        a.processed_data.activation_map = m;
        a.display.image_handle.Parent.CLim = [0, max(m(:))];
        headless_push('uiconfirm', 'Yes');
        feval(a.CV_map.ButtonPushedFcn, a.CV_map, []);
    end
press(map);

%% T1
q = a.display.quiver_handle;
lim = a.display.image_handle.Parent.CLim;
L = hypot(q.UData, q.VData);
sp = a.processed_data.CV_map(:, :, 3);
s_at = sp(sub2ind([H W], q.YData, q.XData));
inside = isfinite(s_at) & s_at >= lim(1) & s_at <= lim(2);
check('T1', isgraphics(q) && all(L(inside) >= 4 - 1e-9 & L(inside) <= 10 + 1e-9) && all(isnan(L(~inside))) && ...
    any(inside) && strcmp(q.AutoScale, 'off'), sprintf('%d arrows, length %.2f-%.2f px, %d outside the colours', ...
    nnz(inside), min(L(inside)), max(L(inside)), nnz(~inside & isfinite(s_at))));

%% T2
hax = a.UIAxesHistogram_traces;
dl = rabbit_cv_map.display_range(a.processed_data.CV_map);
n_above = nnz(sp(:) > dl(2));
want_t = sprintf('%d values above %s m/s not shown', n_above, num2str(dl(2), 3));
check('T2', max(abs(hax.XLim - dl)) < 1e-9 && strcmp(char(string(hax.Title.String)), want_t), ...
    sprintf('XLim %s | "%s"', mat2str(hax.XLim, 4), char(string(hax.Title.String))));

%% T3
tip_out = strjoin(cellstr(a.CVoutlierexclusion.Tooltip), ' ');
tip_arrow = strjoin(cellstr(a.IncludequiversButton.Tooltip), ' ');
tip_lim = strjoin(cellstr(a.upperylimit_traces.Tooltip), ' ');
check('T3', startsWith(tip_out, 'Blanks each CV pixel more than 2 SD from the mean of its distance-max window') && ...
    contains(tip_out, ['"median ' char(177) ' 3 MAD, edges too" chosen beside it']) && ...   % the median/MAD choice
    contains(tip_arrow, 'arrow length 0.4') && strcmp(a.DistancemaxmmEditFieldLabel.Text, 'Distance max (mm)') && ...
    contains(strjoin(cellstr(a.DistancemaxmmEditFieldLabel.Tooltip), ' '), 'half-width of the square fit window') && ...
    contains(tip_lim, '99th percentile'), ...   % the short label, the half-width in the tooltip
    sprintf('"%s" | "%s" | "%s"', tip_out, tip_arrow, tip_lim));

%% T4
h0 = a.processed_data.CV_settings.activation_sha256;
ok_now = isempty(rabbit_cv_map.stale(a));
a.processed_data.activation_map = map + 1;               % as New zero or a filter would
why = rabbit_cv_map.stale(a);
[sp_app, why_app] = rabbit_rhythm_reproject.app_cv_speed(a, map);
n0 = numel(a.history_field.Value);
cv_tab = a.recon.reconstruction_cv_map();
check('T4', ~isempty(h0) && ok_now && strcmp(why, 'The CV map was made from an earlier activation map; make the CV map again.') && ...
    isempty(sp_app) && strcmp(why_app, why) && isempty(cv_tab) && numel(a.history_field.Value) == n0 + 1 && ...
    contains(a.history_field.Value{end}, why), sprintf('"%s" | History "%s"', why, a.history_field.Value{end}));
a.processed_data.activation_map = map;

%% T6
s6 = a.processed_data.CV_settings;
kept = isfield(s6, 'pixel_um_views') && isequal(s6.pixel_um_views, 258) && isfield(s6, 'pixel_sources') && ...
    iscell(s6.pixel_sources) && isscalar(s6.pixel_sources);
fresh = isempty(rabbit_cv_map.stale(a));
a.processed_data.scale = 250;                              % as Input Scale would, after the CV map
why6 = rabbit_cv_map.stale(a);
[sp6, why6_app] = rabbit_rhythm_reproject.app_cv_speed(a, map);
S6 = rabbit_rhythm_reproject.app_cv_pixel_um(a);           % the surface lifting's sizes: the CV map's own
rec6 = rabbit_cv_map.record_fields(a.processed_data.CV_settings);
a.processed_data.scale = 258;
check('T6', kept && fresh && strcmp(why6, 'The CV map was made with other pixel sizes; make the CV map again.') && ...
    isempty(sp6) && strcmp(why6_app, why6) && all(S6(:) == 258) && isequal(rec6.cv_pixel_um_views, 258) && ...
    isempty(rabbit_cv_map.stale(a)), sprintf('"%s" | kept %s | surface sizes %s', why6, mat2str(s6.pixel_um_views), ...
    mat2str(unique(S6(:))')));

%% T7
rh = a.GridLayout8_2.RowHeight;
check('T7', strcmp(a.TimemaxmsEditFieldLabel.Text, 'Time max (ms)') && ...
    contains(strjoin(cellstr(a.timemax.Tooltip), ' '), '10 ms') && isequal(rh(5:6), {'fit', 'fit'}), ...
    sprintf('"%s" | rows %s', a.TimemaxmsEditFieldLabel.Text, strjoin(cellfun(@char, cellfun(@string, rh, ...
    'UniformOutput', false), 'UniformOutput', false), ' ')));

%% T8
lab_wave = char(a.display.colourbar_handle.Label.String);
press(50 + 0.001 * cc + 0.0005 * rr);                      % the whole map within a fraction of a ms
lab_flat = char(a.display.colourbar_handle.Label.String);
press(map);
check('T8', strcmp(lab_wave, 'CV (m/s)') && strcmp(lab_flat, 'apparent speed (m/s), not CV') && ...
    strcmp(char(a.display.colourbar_handle.Label.String), 'CV (m/s)'), sprintf('"%s" | "%s"', lab_wave, lab_flat));

%% T9
n9 = numel(getappdata(groot, 'om_headless_dialogs'));
a.CVmean.ButtonPushedFcn(a.CVmean, []);
d9 = getappdata(groot, 'om_headless_dialogs');
m9 = '';
if numel(d9) > n9, m9 = d9(end).message; end
% and in a tooltip by the CV map (the colour bar and axes take none): CV mean's
tt9 = strjoin(cellstr(a.CVmean.Tooltip), ' ');
check('T9', endsWith(strtrim(m9), ['Note: red streaks along a view seam or edge are fitting artefacts, not ' ...
    'fast tissue.']) && contains(tt9, 'Red streaks along a view seam or edge are fitting artefacts, not fast tissue.'), ...
    [strrep(m9, newline, ' / ') ' | tooltip: ' tt9]);

%% T5
% A pixel two in from the tissue's edge, far too fast: the 2 SD window
% reaches outside the tissue (missing values), so it is never tested
cv = nan(H, W, 3);
cv(:, :, 1) = 0.5; cv(:, :, 2) = 0; cv(:, :, 3) = 0.5 + 0.01 * randn(H, W);
cv(:, 1:5, :) = NaN;                                       % outside the tissue
cv(30, 7, 3) = 20;
[c_sd, n_sd] = rabbit_cv_map.remove_local_outliers(cv, 11, ones(H, W));
[c_mad, n_mad] = rabbit_cv_map.remove_local_outliers_mad(cv, 11, ones(H, W));
dd = findall(a.GridLayout22, 'Tag', 'CvOutlierMethodDropDown');
default_sd = isscalar(dd) && strcmp(dd.Value, 'sd') && strcmp(rabbit_cv_map.outlier_method(a), 'sd');
dd.Value = 'mad';
a.CVoutlierexclusion.Value = 1;
press(map);
h_mad = a.history_field.Value{end};
dd.Value = 'sd';
a.CVoutlierexclusion.Value = 0;
check('T5', default_sd && isfinite(c_sd(30, 7, 3)) && isnan(c_mad(30, 7, 3)) && n_mad >= 1 && ...
    contains(strjoin(a.history_field.Value(max(1, end - 4):end), ' '), 'Remove local outliers (median'), ...
    sprintf('2 SD blanked %d (edge pixel kept: %d), MAD blanked %d | %s', n_sd, isfinite(c_sd(30, 7, 3)), n_mad, h_mad));

%% T10: the method and the outlier test kept at CV map time
% the MAD map just made (T5): its settings keep the method and the test, though
% the tab has been set back since; the records use them; a method change refuses
s10 = a.processed_data.CV_settings;
rec10 = rabbit_cv_map.record_fields(s10);
prm10 = a.recon.reconstruction_cv_parameters();
want_mad = sprintf('median %s 3 MAD, edges too', char(177));
ok10 = isfield(s10, 'method') && strcmp(s10.method, 'Bayly Method') && strcmp(s10.outlier_test, want_mad) && ...
    strcmp(rec10.cv_method, 'Bayly Method') && strcmp(rec10.cv_outlier_test, want_mad) && ...
    strcmp(prm10.method, 'Bayly Method') && strcmp(prm10.cv_outlier_test, want_mad) && isempty(rabbit_cv_map.stale(a));
a.CV_method.Value = 'Nearest Neighbour';                   % changed after the CV map
why10 = rabbit_cv_map.stale(a);
[sp10, why10_app] = rabbit_rhythm_reproject.app_cv_speed(a, map);
prm10b = a.recon.reconstruction_cv_parameters();
ok10 = ok10 && strcmp(why10, ['The CV map was made with another method (Bayly Method; the CV tab now says Nearest ' ...
    'Neighbour); make the CV map again.']) && isempty(sp10) && strcmp(why10_app, why10) && ...
    strcmp(prm10b.method, 'Bayly Method');
press(map);                                                % a nearest-neighbour map, outliers off
s10n = a.processed_data.CV_settings;
ok10 = ok10 && strcmp(s10n.method, 'Nearest Neighbour') && strcmp(s10n.outlier_test, 'none') && ...
    isempty(rabbit_cv_map.stale(a));
a.CV_method.Value = 'Bayly Method';
a.CVoutlierexclusion.Value = 1;
press(map);                                                % Bayly, outliers on, mean +- 2 SD
ok10 = ok10 && strcmp(a.processed_data.CV_settings.outlier_test, sprintf('mean %s 2 SD', char(177)));
a.CVoutlierexclusion.Value = 0;
check('T10', ok10, sprintf('"%s" | %s / %s | "%s"', s10.method, s10.outlier_test, s10n.outlier_test, why10));

fprintf('\nPROBE_CV_TAB_DISPLAY RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('probe_cv_tab_display:Failed', '%d check(s) failed.', fail);
end
fprintf('PROBE_OK probe_cv_tab_display %d/0\n', pass);
end
