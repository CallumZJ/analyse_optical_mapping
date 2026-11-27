function probe_app_screenshot
%% Probe: File > Current app screenshot saves the preview and each tab, restores the tab shown and changes no value
% Collin Snitchler
% 26.11.2026
% Headless only (OM_APP_HEADLESS=1, -noFigureWindows; no window is shown).
% The window picture (title bar and menu bar) is a screen grab: here it
% must be skipped and the message must say so. Whether the real grab
% covers the title bar and menu bar at the right place and scale can only
% be checked on a real screen.
%   A1  the File menu has "Current app screenshot", right after Workspace
%   A2  Cancel in the folder dialog saves nothing and says nothing
%   A3  no data loaded: one picture per tab, named app_<time>_tab_<Title>,
%       "no data loaded: preview not saved", the hidden tabs hidden again
%   A4  a synthetic recording loaded, a tab other than the first shown:
%       one picture per tab plus the preview, named after the recording,
%       every picture different, the window skipped with the reason
%   A5  afterwards the same tab is shown, the tab group in the same place,
%       a few values unchanged, the window still hidden, no Help opened
%   A6  the folder is remembered
%   A7  a second click with the same time: new files with _2, the first
%       files unchanged; a third click through the menu overwrites nothing
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_app_screenshot"
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
cleanup = onCleanup(@() rmdir(root, 's'));
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a));
fig = a.opticalmappingUIFigure;
tg = a.TabGroup;
tabs = tg.Children;
titles = arrayfun(@(t) char(t.Title), tabs, 'UniformOutput', false);
safe = cellfun(@app_screenshot.file_part, titles, 'UniformOutput', false);

% A1 the menu
menu = findall(a.FileMenu, 'Tag', 'CurrentAppScreenshotMenu');
shown = flipud(a.FileMenu.Children);
k_ws = find(shown == a.workspace, 1);
ok = isscalar(menu) && strcmp(menu.Text, 'Current app screenshot') && ~isempty(k_ws) && ...
    numel(shown) > k_ws && shown(k_ws + 1) == menu;
results(end + 1) = struct('id', 'A1 the menu item, after Workspace', 'ok', ok, ...
    'detail', sprintf('%d found; File menu: %s', numel(menu), strjoin(arrayfun(@(m) char(m.Text), shown, 'UniformOutput', false), ' | ')));
    function click(folder)
        % the user's click, the folder chosen in the dialog ('' = Cancel)
        if ~isempty(folder), headless_push('uigetdir', folder); end
        feval(menu.MenuSelectedFcn, menu, []);
        drawnow;
    end
    % (the nested functions' own variables have names of their own: a
    % nested function shares the names it has in common with the probe)
    function alert = last_alert()
        % the last Current app screenshot message, or [] when none
        alert = [];
        all_dialogs = getappdata(groot, 'om_headless_dialogs');
        if isempty(all_dialogs), return; end
        all_dialogs = all_dialogs(strcmp({all_dialogs.kind}, 'uialert') & strcmp({all_dialogs.title}, 'Current app screenshot'));
        if ~isempty(all_dialogs), alert = all_dialogs(end); end
    end
    function names = pngs(folder)
        listing = dir(fullfile(folder, '*.png'));
        names = sort({listing.name});   % a row, as the expected names
    end

% A2 Cancel
out0 = fullfile(root, 'cancel');
mkdir(out0);
n_dialogs = numel(getappdata(groot, 'om_headless_dialogs'));
click('');
dl = getappdata(groot, 'om_headless_dialogs');
ok = isempty(pngs(out0)) && isempty(last_alert()) && numel(dl) == n_dialogs + 1 && strcmp(dl(end).kind, 'uigetdir');
results(end + 1) = struct('id', 'A2 Cancel: nothing saved, nothing said', 'ok', ok, 'detail', sprintf('%d dialogs after', numel(dl)));

% A3 no data
out1 = fullfile(root, 'no_data');
mkdir(out1);
vis0 = char(tg.Visible);
click(out1);
f = pngs(out1);
al = last_alert();
stamp = regexp(strjoin(f, ' '), '(?<=^app_)\d{8}-\d{6}', 'match', 'once');
want = sort(cellfun(@(s) sprintf('app_%s_tab_%s.png', stamp, s), safe, 'UniformOutput', false))';
ok = ~isempty(stamp) && isequal(f, want) && ~isempty(al) && contains(al.message, 'no data loaded: preview not saved') && ...
    contains(al.message, 'window: not saved (headless run') && strcmp(char(tg.Visible), vis0);
results(end + 1) = struct('id', 'A3 no data: the tabs only, said so', 'ok', ok, ...
    'detail', sprintf('files: %s; tabs visible %s (before %s); message: %s', strjoin(f, ', '), char(tg.Visible), vis0, al_text(al)));

% load a small synthetic recording (as probe_tab_switch_layout)
stack = 100 + rand(40, 120, 30);
rec = fullfile(root, 'synthetic_shot.mat');
save(rec, 'stack');
headless_push('uigetfile', rec);
headless_push('inputdlg', {'200'});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
drawnow;
% a tab other than the first, chosen as a user chooses it
pick = a.ConductionVelocityTab;
tg.SelectedTab = pick;
if ~isempty(tg.SelectionChangedFcn), tg.SelectionChangedFcn(tg, []); end
drawnow;
before = values_now(a);

% A4 with data
out2 = fullfile(root, 'with_data');
mkdir(out2);
click(out2);
f = pngs(out2);
al = last_alert();
stamp = regexp(strjoin(f, ' '), '(?<=^synthetic_shot_)\d{8}-\d{6}', 'match', 'once');
want = sort([{sprintf('synthetic_shot_%s_preview.png', stamp)}; ...
    cellfun(@(s) sprintf('synthetic_shot_%s_tab_%s.png', stamp, s), safe, 'UniformOutput', false)])';
imgs = cellfun(@(n) imread(fullfile(out2, n)), f, 'UniformOutput', false);
sizes = cellfun(@(i) mat2str(size(i)), imgs, 'UniformOutput', false);
keys = cellfun(@(i) sprintf('%d,', size(i), sum(double(i(:)))), imgs, 'UniformOutput', false);
named = all(cellfun(@(n) contains(al_text(al), n), want));
ok = ~isempty(stamp) && isequal(f, want) && numel(unique(keys)) == numel(keys) && all(cellfun(@(i) size(i, 3) == 3 && min(size(i, 1), size(i, 2)) > 10, imgs)) && ...
    named && contains(al.message, 'window: not saved (headless run') && ~contains(al.message, 'no data loaded') && ...
    ~any(contains(f, '_window'));
results(end + 1) = struct('id', 'A4 data: the preview and one picture per tab, the window skipped', 'ok', ok, ...
    'detail', sprintf('%d files (%d tabs), %d different; sizes %s; message: %s', numel(f), numel(tabs), numel(unique(keys)), ...
    strjoin(sizes, ' '), al_text(al)));

% A5 restored and unchanged
after = values_now(a);
fields = fieldnames(before);
changed = fields(~cellfun(@(n) isequal(before.(n), after.(n)), fields));
help_open = ~isempty(a.recon.reconstruction_help_figure) && isvalid(a.recon.reconstruction_help_figure);
ok = tg.SelectedTab == pick && isempty(changed) && strcmp(char(fig.Visible), 'off') && ~help_open;
results(end + 1) = struct('id', 'A5 the same tab shown, values unchanged, no window, no Help', 'ok', ok, ...
    'detail', sprintf('shown %s; changed: %s; window %s; Help open %d', char(tg.SelectedTab.Title), strjoin(changed, ', '), ...
    char(fig.Visible), help_open));

% A6 the folder remembered
grp = 'analyse_optical_mapping_AppScreenshot';
ok = ispref(grp, 'last_folder') && strcmp(getpref(grp, 'last_folder'), out2);
results(end + 1) = struct('id', 'A6 the folder is remembered', 'ok', ok, 'detail', '');

% A7 no overwrite
info0 = dir(fullfile(out2, '*.png'));
bytes0 = arrayfun(@(d) file_bytes(fullfile(out2, d.name)), info0, 'UniformOutput', false);
headless_push('uigetdir', out2);
app_screenshot.take(a, stamp);   % the same time as the first click: every name exists
headless_push('uigetdir', out2);
feval(menu.MenuSelectedFcn, menu, []);   % and once more through the menu
f2 = pngs(out2);
second = cellfun(@(n) strrep(n, '.png', '_2.png'), want, 'UniformOutput', false);
same = all(arrayfun(@(k) isequal(file_bytes(fullfile(out2, info0(k).name)), bytes0{k}), 1:numel(info0)));
ok = all(ismember(second, f2)) && numel(f2) == 3 * numel(want) && same;
results(end + 1) = struct('id', 'A7 no overwrite: _2 for the same time, the first files unchanged', 'ok', ok, ...
    'detail', sprintf('%d files after three clicks (%d each); first files unchanged %d', numel(f2), numel(want), same));

n_fail = 0;
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; n_fail = n_fail + 1; end
    fprintf('%s  %s  %s\n', tag, results(k).id, results(k).detail);
end
fprintf('%d of %d checks passed\n', numel(results) - n_fail, numel(results));
if n_fail > 0, error('probe_app_screenshot: %d failed', n_fail); end
fprintf('PROBE_OK probe_app_screenshot %d/0\n', numel(results));
end

function v = values_now(a)
% a few values and views a screenshot must not change
v.distancemax = a.distancemax.Value;
v.timemax = a.timemax.Value;
v.frame = a.display.current_frame;
v.image = a.display.image_handle.CData;
v.axes = getpixelposition(a.display.image_handle.Parent, true);
v.tabs = a.TabGroup.Position;
v.tabs_visible = char(a.TabGroup.Visible);
v.history = a.history_field.Value;
v.figure = a.opticalmappingUIFigure.Position;
v.rhythm = a.recording_rhythm().state;
end

function t = al_text(al)
if isempty(al), t = '(none)'; else, t = al.message; end
end

function b = file_bytes(file)
fid = fopen(file, 'r');
b = fread(fid, inf, '*uint8');
fclose(fid);
end
