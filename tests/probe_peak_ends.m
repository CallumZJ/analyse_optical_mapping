function probe_peak_ends
%% Probe: Beat by Beat Maps, Peaks method: a peak on either end of a beat gives no time (NaN)
% Collin Snitchler
% 26.11.2026
% Headless, a synthetic recording of three beats
% (30 x 30 pixels, 1000 fps), the ROI in the middle:
%   P1  pixels whose signal rises through every beat window (their maximum
%       on its last frame) have no activation time; they had a time clamped
%       to the window's end before S6
%   P2  pixels whose signal falls through every window (maximum on its
%       first frame) have no activation time, as before
%   P3  the pixels with a real upstroke all have a time
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_peak_ends"
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
% three action potentials crossing the field (as probe_export_visuals)
[r, c] = ndgrid(1:30, 1:30);
fps = 1000; n = 900; t = (0:n - 1) / fps;
stack = 100 * ones(30, 30, n);
for b = 0:2
    t0 = 0.1 + 0.3 * b + 0.0005 * (r + c);
    for k = 1:n
        x = max(t(k) - t0, 0);
        stack(:, :, k) = stack(:, :, k) + 1000 * (t(k) > t0) .* exp(-x / 0.08) .* (1 - exp(-x / 0.003));
    end
end
rising = 1:4;                       % rows whose signal only rises: the maximum on each window's last frame
falling = 27:30;                    % rows whose signal only falls: the maximum on each window's first frame
for k = 1:n
    stack(rising, :, k) = 100 + 2000 * t(k);
    stack(falling, :, k) = 2000 - 2000 * t(k);
end
rec = fullfile(root, 'synthetic_peak_ends.mat');
save(rec, 'stack');
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', rec);
headless_push('inputdlg', {num2str(fps)});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
a.signalregiontype.Value = 'Rectangle';
headless_push('drawrectangle', [12 12 6 6]);
feval(a.signalregion.ButtonPushedFcn, a.signalregion, []);
a.localnormalise.Value = true;      % local normalisation first, as the guide does (image_stack{3})
feval(a.localnormalise.ValueChangedFcn, a.localnormalise, []);
a.mapmethod_bbb.Value = '2';        % Peaks
threw = '';
try
    feval(a.generatebeatmaps.ButtonPushedFcn, a.generatebeatmaps, []);
catch ME
    threw = ME.message;
    for s = ME.stack(1:min(3, end))'
        threw = sprintf('%s | %s:%d', threw, s.name, s.line);
    end
end
am = a.processed_data.activation_map;
nb = size(am, 3);
mid = am(8:23, :, :);
rise = am(rising, :, :);
fall = am(falling, :, :);
ok_run = isempty(threw) && nb >= 1;
results(end + 1) = struct('id', 'P1 peak on a beat''s last frame: no time', 'ok', ok_run && all(isnan(rise(:))), ...
    'detail', sprintf('%s %d beats; rising rows with a time: %d of %d', threw, nb, nnz(isfinite(rise)), numel(rise)));
results(end + 1) = struct('id', 'P2 peak on a beat''s first frame: no time', 'ok', ok_run && all(isnan(fall(:))), ...
    'detail', sprintf('falling rows with a time: %d of %d', nnz(isfinite(fall)), numel(fall)));
results(end + 1) = struct('id', 'P3 the upstroke pixels have a time', 'ok', ok_run && all(isfinite(mid(:))), ...
    'detail', sprintf('middle rows with a time: %d of %d', nnz(isfinite(mid)), numel(mid)));
n_fail = 0;
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; n_fail = n_fail + 1; end
    fprintf('%s  %s  %s\n', tag, results(k).id, results(k).detail);
end
fprintf('%d of %d checks passed\n', numel(results) - n_fail, numel(results));
if n_fail > 0, error('probe_peak_ends: %d failed', n_fail); end
fprintf('PROBE_OK probe_peak_ends %d/0\n', numel(results));
end
