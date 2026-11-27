function probe_cv_methods
%% Probe: the CV tab's two methods on synthetic plane waves
% Collin Snitchler
% 25.11.2026
%   N1  B5: nearest neighbour, v = g/|g|^2: plane waves at 0, 45 and 90
%       degrees, 0.5 m/s on 0.258 mm pixels, read 0.5 m/s (median of the
%       inner pixels within 1 %), along the wave (within 1 degree), with
%       layer 1 the row and layer 2 the column component, as Bayly
%   N2  B5: a 0.7 m/s wave (0.37 ms per pixel, below the old tenth-of-a-frame
%       threshold at 204 fps) reads 0.7 m/s, not 0
%   N3  B6: Bayly gives no value where its points lie on fewer than 3 rows
%       or 3 columns (a map two pixels high), with no singular-matrix
%       warning; on a full plane wave the solve A\t gives the old normal-
%       equation result (within 1e-9 m/s)
% No dataset needed. Usage: matlab -batch "addpath('<repo>/tests'); probe_cv_methods" -noFigureWindows
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
results = struct('id', {}, 'ok', {}, 'detail', {});
px = 0.258;                        % mm per pixel
S = 1000 * px * ones(41, 41);
V = ones(41, 41);
[c, r] = meshgrid(1:41, 1:41);
inner = r > 3 & r < 39 & c > 3 & c < 39;

%% N1
ok1 = true; txt1 = {};
for ang = [0 45 90]
    speed = 0.5;                    % mm/ms
    % t = (x cos + y sin) * px / speed, x along columns, y along rows
    act = ((c - 21) * cosd(ang) + (r - 21) * sind(ang)) * px / speed + 50;
    cv = rabbit_cv_map.nearest(act, S, V, 204.0136);
    sp = cv(:, :, 3);
    m = median(sp(inner), 'omitnan');
    dirn = atan2d(median(cv(:, :, 1), 'all', 'omitnan'), median(cv(:, :, 2), 'all', 'omitnan'));   % rows (y), columns (x)
    ok1 = ok1 && abs(m / speed - 1) < 0.01 && abs(mod(dirn - ang + 180, 360) - 180) < 1;
    txt1{end + 1} = sprintf('%d deg: %.4f m/s at %.2f deg', ang, m, dirn); %#ok<AGROW>
end
results = add(results, 'N1 nearest neighbour: 0, 45, 90 degrees read 0.5 m/s along the wave', ok1, strjoin(txt1, '; '));

%% N2
act = (c - 21) * px / 0.7 + 50;
cv = rabbit_cv_map.nearest(act, S, V, 204.0136);
m2 = median(cv(:, :, 3), 'all', 'omitnan');
results = add(results, 'N2 nearest neighbour: 0.7 m/s reads 0.7 m/s, not 0', abs(m2 / 0.7 - 1) < 0.01 && ...
    nnz(cv(:, :, 3) == 0) == 0, sprintf('%.4f m/s, %d zeros', m2, nnz(cv(:, :, 3) == 0)));

%% N3
thin = repmat(linspace(0, 10, 41), 2, 1) + 50;
lastwarn('');
cv_thin = rabbit_cv_map.bayly(thin, 258 * ones(2, 41), ones(2, 41), 3, 100);
[wmsg, wid] = lastwarn();
act = ((c - 21) * cosd(30) + (r - 21) * sind(30)) * px / 0.5 + 50;
cv_new = rabbit_cv_map.bayly(act, S, V, 1.5, 100);
cv_old = old_bayly(act, S, V, 1.5, 100);
d = max(abs(cv_new(:, :, 3) - cv_old(:, :, 3)), [], 'all', 'omitnan');
results = add(results, 'N3 Bayly: no value on fewer than 3 rows, no singular warning; A\t equals the old solve', ...
    all(isnan(cv_thin(:)) | cv_thin(:) == 0) && ~any(isfinite(cv_thin(:, :, 3)), 'all') && ...
    ~contains(wid, 'singular', 'IgnoreCase', true) && d < 1e-9 && isequal(isnan(cv_new), isnan(cv_old)), ...
    sprintf('thin map values %d; warning "%s"; largest difference %.3g m/s', nnz(isfinite(cv_thin(:, :, 3))), wmsg, d));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_CV_METHODS RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_cv_methods:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_cv_methods %d/0\n', n_pass);
end


function cv = old_bayly(act, S, V, distance_max_mm, time_max_ms)
% The Bayly fit before B6 (normal equations, no degeneracy test), for N3
[H, W] = size(act);
cv = nan(H, W, 3);
[row, col] = find(~isnan(act) & V > 0);
idx = sub2ind([H W], row, col);
vk = V(idx);
t = act(idx);
for k = 1:numel(row)
    dxy = 1000 * distance_max_mm / S(idx(k));
    wf = find(vk == vk(k) & abs(row - row(k)) < dxy & abs(col - col(k)) < dxy);
    times = t(wf);
    keep = abs(times - t(k)) < time_max_ms;
    wf = wf(keep); times = times(keep);
    if numel(times) >= 6
        r = row(wf) - row(k); c = col(wf) - col(k);
        A = [r.^2, c.^2, r.*c, r, c, ones(size(r))];
        p = (A' * A) \ (A' * times);
        cv(row(k), col(k), 1) = p(4) / (p(4)^2 + p(5)^2);
        cv(row(k), col(k), 2) = p(5) / (p(4)^2 + p(5)^2);
    end
end
cv(:, :, 3) = sqrt(cv(:, :, 1).^2 + cv(:, :, 2).^2);
cv = cv .* (S / 1000);
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
