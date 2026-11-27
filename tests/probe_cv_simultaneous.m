function probe_cv_simultaneous
%% Probe: the near-simultaneous activation warning (CV tab, History, CV caption; the Results row is probe_results_box R18)
% Collin Snitchler
% 24.11.2026
% The rule: when a view's activation IQR (25-75 %), over its own pixels of the
% activation map the CV step used, is below SIMULTANEOUS_IQR_MS (10 ms), CV
% there is an apparent speed. The warning names only those views, in
% View1-View4 order, in whole ms, with the same words everywhere. Display
% only: nothing computed changes. The CV tab
% alert, History and Results say it in plain words ("Most of each view
% activates at almost the same moment ..."); the Visualise caption keeps the
% short form (simultaneous_warning(..., 'short')).
%   S1  a synthetic four-view map, View2 and View3 activating over about
%       12 ms (5-95 %): the exact words; over 40 ms in every view: no warning
%   S2  salt and pepper: 11 % of the pixels of every view far off (+300 ms,
%       as wrong-peak pixels) change neither result; the 5-95 % spread
%       would have missed the 12 ms views
%   S5  single-view data: one IQR over the whole map, no view named
%   S3  through the app (CV map button): the warning in a CV map alert and
%       in History, the IQRs kept with the CV map; none at 40 ms; the CV
%       map itself is the same with or without the warning
%   S6  each view's limit is its size / 3 mm/ms
%       (sqrt(pixels with a time) x pixel size), recorded per view and named
%       in the words; without pixel sizes (and in older records) 10 ms
%   S4  the CV projection's record (as write_manifest writes it, through
%       JSON) gives the same words, and the Visualise CV caption shows them
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_cv_simultaneous"
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
words = @(list) ['Activation nearly simultaneous (middle half within 10 ms: ' list '): CV here is an apparent ' ...
    'speed, not conduction speed'];   % the short form, kept for the Visualise captions
% the plain words of the CV tab alert, History and
% Results; who: the views hit; vals: their IQRs (ms), given as a range
    function t = plain(who, vals)
        lo = round(min(vals)); hi = round(max(vals));
        within = sprintf('%d', lo);
        if hi > lo, within = sprintf('%d%s%d', lo, char(8211), hi); end
        t = sprintf(['%s at almost the same moment (middle half of pixels within %s ms, under 10 ms). ' ...
            'Speeds from such small time differences are not true conduction velocities %s typical of ' ...
            'sinus rhythm. Do not report them as CV; use a paced recording.'], who, within, char(8212));
    end

%% S1: four views, 30 columns each; a ramp along the columns sets each view's spread
H = 40; Wr = 30;
ramp = @(spread) repmat(linspace(0, spread / 0.9, Wr), H, 1);   % 5-95 % about the given spread
act = [ramp(40), ramp(12), ramp(12.6), ramp(40)] + 50;
V = repelem(1:4, 1, Wr) .* ones(H, 1);
[s, names] = rabbit_cv_map.view_spreads(act, V);
iqr_of = @(x) diff(prctile(x(:), [25 75]));
w = rabbit_reconstruction_tab.simultaneous_warning(names, s);
want_short = words(sprintf('View2 %d ms, View3 %d ms', round(iqr_of(ramp(12))), round(iqr_of(ramp(12.6)))));
want = plain('In View2 and View3, most of each view activates', [iqr_of(ramp(12)), iqr_of(ramp(12.6))]);
w_short = rabbit_reconstruction_tab.simultaneous_warning(names, s, 'short');
all40 = [ramp(40), ramp(40), ramp(40), ramp(40)] + 50;
w40 = rabbit_reconstruction_tab.simultaneous_warning(names, rabbit_cv_map.view_spreads(all40, V));
check('S1', strcmp(w, want) && strcmp(w_short, want_short) && isempty(w40) && rabbit_reconstruction_tab.SIMULTANEOUS_IQR_MS == 10 && ...
    abs(s(2) - iqr_of(ramp(12))) < 1e-9, sprintf('IQR %s | "%s"', mat2str(s, 4), w));

%% S2: salt and pepper, 11 % of each view's pixels 300 ms late
rng(7, 'twister');
salt = rand(H, 4 * Wr) < 0.11;
act_s = act; act_s(salt) = act_s(salt) + 300;
all40_s = all40; all40_s(salt) = all40_s(salt) + 300;
[ss, ~] = rabbit_cv_map.view_spreads(act_s, V);
w_s = rabbit_reconstruction_tab.simultaneous_warning(names, ss);
q595 = arrayfun(@(k) diff(prctile(act_s(V == k), [5 95])), 1:4);
check('S2', ~isempty(regexp(w_s, '^In View2 and View3, most of each view activates at almost the same moment \(middle half of pixels within \d+(\S\d+)? ms, under 10 ms\)', 'once')) && ...
    isempty(rabbit_reconstruction_tab.simultaneous_warning(names, rabbit_cv_map.view_spreads(all40_s, V))) && all(q595(2:3) > 20), ...
    sprintf('IQR with salt %s, 5-95 %% with salt %s | "%s"', mat2str(ss, 4), mat2str(q595, 4), w_s));

%% S5: single-view data
[s1, n1] = rabbit_cv_map.view_spreads(ramp(12), ones(H, Wr));
w1 = rabbit_reconstruction_tab.simultaneous_warning(n1, s1);
check('S5', strcmp(w1, plain('Most of the map activates', iqr_of(ramp(12)))) && isscalar(s1) && ...
    isempty(rabbit_reconstruction_tab.simultaneous_warning(n1, rabbit_cv_map.view_spreads(ramp(40), ones(H, Wr)))), w1);

%% S3: through the app, single-view data (the whole map), Bayly with the defaults
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
stack = 1000 + 100 * rand(H, Wr, 30);                       % the app loads the variable 'stack'
rec = fullfile(root, 'synthetic_recording.mat');
save(rec, 'stack');
a = analyse_optical_mapping;                                % start the app (hidden)
app_cleanup = onCleanup(@() delete(a));
headless_push('uigetfile', rec);
headless_push('inputdlg', {'204.0136'});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
a.processed_data.scale = 258;
a.CV_method.Value = 'Bayly Method';
    function [cv, alerts] = press(map)
        setappdata(groot, 'om_headless_dialogs', []);
        a.processed_data.activation_map = map;
        a.display.image_handle.Parent.CLim = [0, max(map(:))];
        headless_push('uiconfirm', 'Yes');
        feval(a.CV_map.ButtonPushedFcn, a.CV_map, []);
        cv = a.processed_data.CV_map;
        dl = getappdata(groot, 'om_headless_dialogs');
        alerts = {};
        if ~isempty(dl), alerts = {dl(strcmp({dl.title}, 'CV map') & strcmp({dl.kind}, 'uialert')).message}; end
    end
% the limit is the map's size / 3 mm/ms,
% sqrt(1200 pixels) x 0.258 mm / 3 = 2.98 ms here, so the 4 ms ramp (IQR
% about 2.2 ms) warns and the 40 ms one does not
[cv12, al12] = press(ramp(4) + 50);
h12 = a.history_field.Value(end);
rec12 = a.processed_data.CV_activation_spread;
[cv40, al40] = press(ramp(40) + 50);
ref12 = rabbit_cv_map.bayly(rabbit_cv_map.median3(ramp(4) + 50, ones(H, Wr)), 258 * ones(H, Wr), ones(H, Wr), 3, ...
    rabbit_cv_map.default_window(204.0136));   % 10 ms
check('S3', isscalar(al12) && startsWith(al12{1}, 'Most of the map activates at almost the same moment (middle half of pixels within ') && ...
    endsWith(al12{1}, 'Do not report them as CV; use a paced recording.') && strcmp(h12{1}, al12{1}) && ...
    strcmp(rec12.warning, al12{1}) && isempty(al40) && isempty(a.processed_data.CV_activation_spread.warning) && ...
    isequaln(cv12, ref12) && ~isempty(cv40), sprintf('%s | IQR %.3g ms', strjoin(al12, ' '), rec12.iqr_ms));

%% S6: each view's limit is its size / 3 mm/ms
% (L = sqrt(pixels with a time) x pixel size), in the record and the words;
% one fixed 10 ms without pixel sizes (and in an older record)
Sv = repelem([250 260 255 262], 1, Wr) .* ones(H, 1);
act6 = [ramp(40), ramp(4), ramp(4), ramp(40)] + 50;
act6(1:10, 1:Wr) = NaN;                                    % View1 has fewer pixels with a time
c6 = rabbit_cv_map.simultaneous_check(act6, V, Sv);
n6 = [30 * Wr, 40 * Wr, 40 * Wr, 40 * Wr];
want_lim = sqrt(n6) .* [0.250 0.260 0.255 0.262] / 3;
iqr4 = iqr_of(ramp(4));
w6 = sprintf(['In View2 and View3, most of each view activates at almost the same moment (middle half of pixels ' ...
    'within %d ms, under %s%s%s ms, the time the middle half of each view takes at 1.5 m/s (view size / 3)). ' ...
    'Speeds from such small time differences are not true ' ...
    'conduction velocities %s typical of sinus rhythm. Do not report them as CV; use a paced recording.'], ...
    round(iqr4), num2str(want_lim(3), 2), char(8211), num2str(want_lim(2), 2), char(8212));
legacy = rabbit_cv_map.simultaneous_check(act6, V);
rec6 = rabbit_reconstruction_tab.simultaneous_from_record(jsondecode(jsonencode(struct('activation_spread', c6))));
short6 = rabbit_reconstruction_tab.simultaneous_from_record(jsondecode(jsonencode(struct('activation_spread', c6))), 'short');
check('S6', max(abs(c6.warn_below_ms - want_lim)) < 1e-9 && isequal(c6.n_px, n6) && strcmp(c6.warning, w6) && ...
    strcmp(rec6, w6) && all(legacy.warn_below_ms == 10) && contains(legacy.warning, 'under 10 ms') && ...
    contains(short6, ['under the time the middle half of each view takes at 1.5 m/s, view size / 3): CV here is ' ...
    'an apparent speed']) && ~contains(short6, 'mm/ms'), ...   % the Visualise short form too
    sprintf('limits %s ms | "%s"', mat2str(c6.warn_below_ms, 3), c6.warning));

%% S4: the projection's record, through JSON, and the Visualise CV caption
out = fullfile(root, 'outputs', 'reprojection');
mkdir(out);
m = struct('activation_spread', struct('views', {names}, 'iqr_ms', s, 'warn_below_ms', 10, 'basis', 'probe'));
fid = fopen(fullfile(out, 'cv_reprojection_manifest.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(m));
fclose(fid);
from_rec = rabbit_reconstruction_tab.simultaneous_from_record(jsondecode(fileread(fullfile(out, 'cv_reprojection_manifest.json'))));
m1 = struct('activation_spread', struct('views', {n1}, 'iqr_ms', s1, 'warn_below_ms', 10, 'basis', 'probe'));
from_rec1 = rabbit_reconstruction_tab.simultaneous_from_record(jsondecode(jsonencode(m1)));
tab = rabbit_reconstruction_tab();
fig = uifigure('Visible', 'off');
fig_cleanup = onCleanup(@() delete(fig));
p = struct('source_path', fullfile(out, 'cv_projected.cdf'), 'info', struct('scalar', [0.5; 0.6; 0.7]));
[~, caveats] = tab.viewer_cv_caption(fig, p);
check('S4', strcmp(from_rec, want) && strcmp(from_rec1, w1) && any(strcmp(caveats, want_short)), ...   % the caption keeps the short form
    sprintf('%s | caption: %s', from_rec, strjoin(caveats, ' / ')));

fprintf('\nPROBE_CV_SIMULTANEOUS RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('probe_cv_simultaneous:Failed', '%d check(s) failed.', fail);
end
fprintf('PROBE_OK probe_cv_simultaneous %d/0\n', pass);
end
