function probe_tab_switch_layout
%% Probe: switching tabs never resizes the image axes, and the tabs keep their height (only Reconstruction is taller)
% Collin Snitchler
% 26.11.2026
% The History tab once covered the bottom of the image axes. Headless, a synthetic recording loaded:
%   W1  each tab chosen as a user chooses it (the tab group's
%       SelectionChangedFcn), History last: the image axes keep their
%       position and size, and the tab group its height
%   W2  Reconstruction (which takes the window's height, in front of the
%       image) and then History: the tab group's height is back, the image
%       axes unchanged
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_tab_switch_layout"
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
stack = 100 + rand(40, 120, 30); %#ok<NASGU>
rec = fullfile(root, 'synthetic_tabs.mat');
save(rec, 'stack');
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', rec);
headless_push('inputdlg', {'200'});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
drawnow;
tg = a.TabGroup;
ax = a.display.image_handle.Parent;
    function choose(tab)
        % as a user's click: the selection, then the group's callback
        tg.SelectedTab = tab;
        if ~isempty(tg.SelectionChangedFcn)
            tg.SelectionChangedFcn(tg, []);
        end
        drawnow;
    end
% the start: as the load leaves it (the tab group a third of the window)
start_tab = tg.SelectedTab;
ax_pos = getpixelposition(ax, true);
tg_pos = tg.Position;
tabs = tg.Children;
names = arrayfun(@(t) char(t.Title), tabs, 'UniformOutput', false);
recon = tabs(strcmp(names, 'Reconstruction/Reprojection'));
hist_tab = a.HistoryTab;
moved = {};
for k = 1:numel(tabs)
    % a user cannot choose the tab already shown (no SelectionChanged)
    if any(tabs(k) == recon) || tabs(k) == hist_tab || tabs(k) == start_tab, continue; end
    choose(tabs(k));
    if any(abs(getpixelposition(ax, true) - ax_pos) > 0.5) || any(abs(tg.Position - tg_pos) > 0.5)
        moved{end + 1} = sprintf('%s (axes %s, tabs %s)', names{k}, mat2str(round(getpixelposition(ax, true))), ...
            mat2str(tg.Position)); %#ok<AGROW>
    end
end
choose(hist_tab);
ok1 = isempty(moved) && all(abs(getpixelposition(ax, true) - ax_pos) <= 0.5) && all(abs(tg.Position - tg_pos) <= 0.5);
results(end + 1) = struct('id', 'W1 a tab switch keeps the image axes and the tab height', 'ok', ok1, ...
    'detail', sprintf('axes %s, tabs %s, History tabs %s; moved on: %s', mat2str(round(ax_pos)), mat2str(tg_pos), ...
    mat2str(tg.Position), strjoin(moved, ', ')));
ok2 = false; det2 = 'no Reconstruction tab';
if isscalar(recon)
    choose(recon);
    tall = tg.Position(4);
    choose(hist_tab);
    ok2 = tall > tg_pos(4) && all(abs(tg.Position - tg_pos) <= 0.5) && all(abs(getpixelposition(ax, true) - ax_pos) <= 0.5);
    det2 = sprintf('Reconstruction height %g, then History %s (before %s)', tall, mat2str(tg.Position), mat2str(tg_pos));
end
results(end + 1) = struct('id', 'W2 Reconstruction then History: the height back', 'ok', ok2, 'detail', det2);
n_fail = 0;
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; n_fail = n_fail + 1; end
    fprintf('%s  %s  %s\n', tag, results(k).id, results(k).detail);
end
fprintf('%d of %d checks passed\n', numel(results) - n_fail, numel(results));
if n_fail > 0, error('probe_tab_switch_layout: %d failed', n_fail); end
fprintf('PROBE_OK probe_tab_switch_layout %d/0\n', numel(results));
end
