function probe_cv_outliers
%% Probe: the paced CV outlier warning (CV tab alert, History, Visualise CV caption; the Results row is probe_results_box R24)
% Collin Snitchler
% 25.11.2026
% For a recording marked Paced, when more than 5 % of the
% CV values are above 1.5 m/s, or more than 1 % above 5 m/s: "WARN CV  <x> %
% of <basis> > 1.5 m/s (surface speed <y> %), 99th percentile <p> m/s, max <m>
% m/s: outliers present; quote the median and IQR, and look at the red
% patches on the CV map before removing anything (Remove local outliers with
% "median ± 3 MAD, edges too" can reach edges)" (the bracket only with
% surface speeds). Display only: nothing computed changes.
%   O1  the rule: 6 % above 1.5 m/s warns with the exact words; 5 % (not
%       more) and max 4.9 m/s does not; one value of 5.1 m/s in 1000 no
%       longer warns, 2 % above 5 m/s does; the surface speed's share
%       in brackets when given; Sinus rhythm and Not stated never warn; NaN
%       and 0 are no values
%   O2  through the app (CV map button), marked Paced, a map whose CV is
%       above 5 m/s: the words in History and in the one CV map alert
%       (with the near-simultaneous warning there too); marked Sinus
%       rhythm, the same map: neither; the CV map the same both times
%   O3  the Visualise CV caption of a projection whose record says Paced
%       carries the words; Sinus rhythm: not
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_cv_outliers"
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
% the words: share, 99th percentile p, max y
words = @(x, y, p) sprintf(['%.1f %% of values > 1.5 m/s, 99th percentile %.1f m/s, max %.1f m/s: outliers ' ...
    'present; quote the median and IQR, and look at the red patches on the 2-D CV map (white faces on the 3-D CV panel) before removing anything ' ...
    '(Remove local outliers with "median %s 3 MAD, edges too" can reach edges)'], x, p, y, char(177));
p99 = @(v) prctile(v(isfinite(v) & v > 0), 99);
% each place names what its share is of
words_b = @(x, y, p, b) strrep(words(x, y, p), '% of values >', ['% of ' b ' >']);
paced = rabbit_recording_rhythm.make('paced', 500);
sinus = rabbit_recording_rhythm.make('sinus');
none = rabbit_recording_rhythm.not_stated();
W = @(s, r) rabbit_reconstruction_tab.cv_outlier_warning(s, r);

%% O1: the rule
s6 = [repmat(0.7, 94, 1); repmat(2, 6, 1)];                % 6 % above 1.5 m/s, max 2
s5 = [repmat(0.7, 95, 1); repmat(4.9, 5, 1)];              % 5 %, max 4.9: no warning
s1 = [repmat(0.7, 999, 1); 5.1];                           % one value above 5 m/s
s6n = [s6; NaN(20, 1); zeros(20, 1)];                      % NaN and 0 are no values
s2 = [repmat(0.7, 98, 1); 6; 7];                           % 2 % above 5 m/s (and 2 % above 1.5)
surf = [repmat(0.8, 90, 1); repmat(2, 10, 1)];             % its surface speeds: 10 % above 1.5 m/s
w_s = rabbit_reconstruction_tab.cv_outlier_warning(s6, paced, '', surf);
check('O1', strcmp(W(s6, paced), words(6, 2, p99(s6))) && isempty(W(s5, paced)) && isempty(W(s1, paced)) && ...
    strcmp(W(s2, paced), words(2, 7, p99(s2))) && strcmp(w_s, strrep(words(6, 2, p99(s6)), '1.5 m/s, 99th', ...
    '1.5 m/s (surface speed 10.0 %), 99th')) && ...
    isempty(W(s6, sinus)) && isempty(W(s1, none)) && strcmp(W(s6n, paced), words(6, 2, p99(s6))) && isempty(W([], paced)) && ...
    rabbit_reconstruction_tab.CV_OUTLIER_SPEED_M_S == 1.5 && rabbit_reconstruction_tab.CV_OUTLIER_SHARE_PCT == 5 && ...
    rabbit_reconstruction_tab.CV_OUTLIER_MAX_M_S == 5 && rabbit_reconstruction_tab.CV_OUTLIER_MAX_SHARE_PCT == 1, ...
    sprintf('"%s" | "%s"', W(s6, paced), w_s));

%% O2: through the app, single-view data, Bayly with the defaults
H = 40; Wd = 30;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
stack = 1000 + 100 * rand(H, Wd, 30);                       % the app loads the variable 'stack'
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
% A plane wave crossing the map in 4 ms: about 1.9 mm in 4 ms per 30 px, so
% CV of the order of 2 m/s, every value above 1.5 m/s
map = repmat(linspace(0, 4, Wd), H, 1) + 50;
    function [cv, alerts, hist] = press(r)
        a.set_recording_rhythm(r{:});
        setappdata(groot, 'om_headless_dialogs', []);
        n0 = numel(a.history_field.Value);
        a.processed_data.activation_map = map;
        a.display.image_handle.Parent.CLim = [0, max(map(:))];
        headless_push('uiconfirm', 'Yes');
        feval(a.CV_map.ButtonPushedFcn, a.CV_map, []);
        cv = a.processed_data.CV_map;
        dl = getappdata(groot, 'om_headless_dialogs');
        alerts = {};
        if ~isempty(dl), alerts = {dl(strcmp({dl.title}, 'CV map') & strcmp({dl.kind}, 'uialert')).message}; end
        hist = a.history_field.Value(n0 + 1:end);
    end
[cv_p, al_p, h_p] = press({'Paced', 500});
sp = cv_p(:, :, 3);
sp = sp(isfinite(sp) & sp > 0);
want = ['WARN CV  ' words_b(100 * mean(sp > 1.5), max(sp), p99(sp), '2-D map pixels')];
[cv_s, al_s, h_s] = press({'Sinus rhythm'});
check('O2', ~isempty(sp) && isscalar(al_p) && contains(al_p{1}, want) && startsWith(al_p{1}, 'Most of the map activates') && ...
    any(strcmp(h_p, want)) && ~any(contains(h_s, 'WARN CV')) && ~any(contains(al_s, 'WARN CV')) && isequaln(cv_p, cv_s), ...
    sprintf('alert: %s | %d values, median %.2f m/s', strrep(strjoin(al_p, ' '), newline, ' / '), numel(sp), median(sp)));

%% O3: the Visualise CV caption, from the projection's record
out = fullfile(root, 'outputs', 'reprojection');
mkdir(out);
tab = rabbit_reconstruction_tab();
vals = [repmat(0.7, 90, 1); repmat(2, 10, 1)];
cap = cell(1, 2);
states = {paced, sinus};
for k = 1:2
    m = struct('recording_rhythm', rabbit_recording_rhythm.record(states{k}));
    fid = fopen(fullfile(out, 'cv_reprojection_manifest.json'), 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(m));
    fclose(fid);
    fig = uifigure('Visible', 'off');
    p = struct('source_path', fullfile(out, 'cv_projected.cdf'), 'info', struct('scalar', vals));
    [~, cap{k}] = tab.viewer_cv_caption(fig, p);
    delete(fig);
end
% the caption's sentence is a WARN (S10) and, paced, sends
% the reader to the Results box for what to report (T1)
want_o3 = ['WARN ' strrep(words_b(10, 2, p99(vals), 'faces shown'), 'quote the median and IQR', ...
    'for reporting, use the Results box')];   % the 2-D map and the 3-D panel named in the words
check('O3', any(strcmp(cap{1}, want_o3)) && ~any(contains(cap{2}, 'outliers present')), ...
    sprintf('paced: %s | sinus: %s', strjoin(cap{1}, ' / '), strjoin(cap{2}, ' / ')));

fprintf('\nPROBE_CV_OUTLIERS RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('probe_cv_outliers:Failed', '%d check(s) failed.', fail);
end
fprintf('PROBE_OK probe_cv_outliers %d/0\n', pass);
end
