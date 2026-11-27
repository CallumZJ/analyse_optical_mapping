function probe_top_line_times
%% Probe: the main window's top line gives the start and end times without -0.0 s, and an averaged beat its own length
% Collin Snitchler
% 25.11.2026
% Headless, a synthetic recording (20 x 20 pixels,
% 200 frames at 200 fps) loaded whole:
%   L1  the top line reads "Start time: 0.0 s", never "-0.0 s"
%   L2  with an averaged beat (Average beats applied: History has
%       average_beats and the stack 40 frames), the top line reads
%       "Averaged beat: 40 frames, 0.200 s (40/fps)" (one
%       beat-length definition, frames / fps) and not the recording's end time
%   L3  after an Undo of it (History without average_beats) the recording's
%       times again
%   L4  the file is named by its name only, no folders
% The averaging window itself is not driven (it waits for a user); its
% result (fewer frames, the History entry) is set as it leaves it.
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_top_line_times"
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
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
stack = 100 + rand(20, 20, 200); %#ok<NASGU>
rec = fullfile(root, 'synthetic_times.mat');
save(rec, 'stack');
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', rec);
headless_push('inputdlg', {'200'});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
top = @() char(strjoin(cellstr(a.tool_tip.Value), ' '));
t1 = top();
results(end + 1) = struct('id', 'L1 no -0.0 s', 'ok', contains(t1, 'Start time: 0.0 s') && ~contains(t1, '-0.0'), 'detail', t1);
% as the averaging window leaves the app: one beat of 40 frames
old_hist = a.history.current;
a.history.current = [old_hist, 'average_beats'];
a.processed_data.n_frames = 40;
a.tool_tip_update();
t2 = top();
want = 'Averaged beat: 40 frames, 0.200 s (40/fps)';   
results(end + 1) = struct('id', 'L2 an averaged beat''s own length', 'ok', contains(t2, want) && ~contains(t2, 'End time'), ...
    'detail', t2);
a.history.current = old_hist;                              % as Undo puts it back
a.processed_data.n_frames = 200;
a.tool_tip_update();
t3 = top();
results(end + 1) = struct('id', 'L3 the recording''s times after Undo', 'ok', contains(t3, 'End time:') && ...
    ~contains(t3, 'Averaged beat'), 'detail', t3);
results(end + 1) = struct('id', 'L4 the file''s name only', 'ok', contains(t1, 'File name: synthetic_times.mat') && ...
    ~contains(t1, char(8230)) && ~contains(t1, [filesep 'synthetic_times.mat']), 'detail', t1);
n_fail = 0;
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; n_fail = n_fail + 1; end
    fprintf('%s  %s  %s\n', tag, results(k).id, results(k).detail);
end
fprintf('%d of %d checks passed\n', numel(results) - n_fail, numel(results));
if n_fail > 0, error('probe_top_line_times: %d failed', n_fail); end
end
