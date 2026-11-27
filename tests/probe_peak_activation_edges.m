function probe_peak_activation_edges
%% Probe: the Peak activation method fits each pixel's own peak, also near the start and end of the recording
% Collin Snitchler
% 25.11.2026
% with the peak within 10 frames of either end, the
% Peak method shortened its window but kept the polynomial (and time grid)
% of the pixel before, so such a pixel took its neighbour's time. Headless,
% on a synthetic recording (20 x 20 pixels, 60 frames at 1000 fps, one
% Gaussian bump per pixel whose peak runs from frame 3 to frame 58 across
% the columns), the map is made with the Peak method as a user makes it:
%   P1  every pixel's time is the vertex of a quadratic fitted to its own
%       normalised signal over the window the method uses (10 frames each
%       side, cut at the recording's ends), within 0.01 ms
%   P2  the pixels whose peak lies within 10 frames of an end differ from
%       the pixel before them (each has its own time, not its neighbour's)
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_peak_activation_edges"
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

%% A synthetic recording: each column peaks at its own frame
fps = 1000; n = 60;
[~, c] = ndgrid(1:20, 1:20);
centre = 3 + (c - 1) * (55 / 19) + 0.3;   % frames 3.3 to 58.3, off the frame grid
stack = zeros(20, 20, n);
for k = 1:n
    stack(:, :, k) = 100 + 1000 * exp(-((k - centre) / 4) .^ 2);
end
rec = fullfile(root, 'synthetic_peaks.mat');
save(rec, 'stack');
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', rec);
headless_push('inputdlg', {num2str(fps)});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
a.signalregiontype.Value = 'Rectangle';
headless_push('drawrectangle', [5 5 6 6]);
feval(a.signalregion.ButtonPushedFcn, a.signalregion, []);
a.localnormalise.Value = true;
feval(a.localnormalise.ValueChangedFcn, a.localnormalise, []);
a.maptype.Value = '1';
if ~isempty(a.maptype.ValueChangedFcn), feval(a.maptype.ValueChangedFcn, a.maptype, []); end
a.mapmethod.Value = '2';   % Peak
headless_push('uiconfirm', 'Yes');
feval(a.generatemap.ButtonPushedFcn, a.generatemap, []);
act = a.processed_data.activation_map;

%% The expected time of each pixel, fitted here on its own signal
st = a.processed_data.image_stack{3};
time = a.processed_data.signals{1, 1};
want = nan(size(act));
edge = false(size(act));
for m = 1:size(st, 1)
    for q = 1:size(st, 2)
        s = reshape(st(m, q, :), 1, []);
        [~, i] = max(s);
        if i == 1, continue; end
        d1 = min(10, i - 1);
        d2 = min(10, numel(time) - i);
        edge(m, q) = d1 < 10 || d2 < 10;
        p = polyfit(time(i - d1:i + d2), s(i - d1:i + d2), 2);
        g = linspace(time(i - d1), time(i + d2), 10000);
        [~, j] = max(polyval(p, g));
        want(m, q) = 1000 * g(j);
    end
end
ok = isfinite(want);
err = max(abs(act(ok) - want(ok)));
results = add(results, struct('id', 'P1 every pixel''s time from its own fit (edges included)', ...
    'ok', isequal(size(act), size(want)) && all(isfinite(act(ok))) && err < 0.01 && any(edge(:)), ...
    'detail', sprintf('max |difference| %.4g ms; %d pixels near an end', err, nnz(edge))));
% P2: along a row, a pixel near an end has its own time, not the one before it
row = act(10, :);
e = find(edge(10, :));
e = e(e > 1);
same = arrayfun(@(k) abs(row(k) - row(k - 1)) < 1e-9, e);
results = add(results, struct('id', 'P2 a pixel near an end does not repeat its neighbour''s time', ...
    'ok', ~isempty(e) && ~any(same), 'detail', mat2str(round(row, 2))));

%% Report
n_fail = 0;
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; n_fail = n_fail + 1; end
    fprintf('%s  %s  %s\n', tag, results(k).id, results(k).detail);
end
fprintf('%d of %d checks passed\n', numel(results) - n_fail, numel(results));
if n_fail > 0, error('probe_peak_activation_edges: %d failed', n_fail); end
end

function results = add(results, r)
results(end + 1) = r;
end
