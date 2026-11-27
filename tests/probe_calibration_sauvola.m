function probe_calibration_sauvola
%% Probe: Sauvola pre-processing of Ccube calibration tiles
% Collin Snitchler
% 19.11.2026
%   S1 rabbit_sauvola equals a direct per-pixel evaluation of Sauvola's
%      threshold (mirrored border, R = 127.5) for k 0 and 0.2, odd and even
%      windows, uint16 input scaled to 0-255
%   S2 a flat image gives all zeros; a 3-D image and a too small image are refused
%   S3 the default spec binarises Ccube tiles in make_job and flags them;
%      PuzzleBoardCube tiles are left alone; no pre-processing leaves all
%   S4 the summary names the pre-processing
%   S5 the calibration window's box is ticked by default; unticked, the spec
%      has no pre-processing
% Needs OM_APP_HEADLESS=1 (no windows). No data files.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_calibration_sauvola" -noFigureWindows
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
pass = 0; fail = 0;
root = tempname(tempdir);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));

    function check(id, ok, detail)
        fprintf('%s: %s -> %s\n', id, detail, char(70 + 14 * logical(ok)));
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end

%% S1 against a direct evaluation
rng(11);
img = uint16(round(imgaussfilt(rand(23, 31), 1.2) * 40000 + 900));
ok1 = true;
for c = {{7, 0}, {7, 0.2}, {6, 0}, {9, 0.05}}
    w = c{1}{1}; k = c{1}{2};
    got = rabbit_sauvola(img, w, k);
    want = direct(img, w, k);
    ok1 = ok1 && isequal(got, want) && isa(got, 'uint8');
end
check('S1', ok1, 'equals the direct per-pixel threshold for 4 window/k pairs');

%% S2 edge cases
flat = rabbit_sauvola(ones(10, 10) * 5, 7, 0);
e3 = false; es = false;
try, rabbit_sauvola(ones(10, 10, 2), 7, 0); catch ME, e3 = strcmp(ME.identifier, 'analyse_om:Calibration:Not2D'); end
try, rabbit_sauvola(ones(3, 10), 7, 0); catch ME, es = strcmp(ME.identifier, 'analyse_om:Calibration:Small'); end
check('S2', ~any(flat(:)) && e3 && es, 'flat image all zero; 3-D and too small refused');

%% S3 make_job
spec = rabbit_calibration.default_spec();
spec.recordings = struct('path', {'cube.fits', 'pb.fits'}, 'role', {'fit', 'holdout'}, ...
    'type', {'Ccube', 'PuzzleBoardCube'}, 'n_points', {6, 7}, 'edge_mm', {30, 30}, 'size_source', {'x', 'x'});
spec.windows = [1 20; 21 40; 41 60; 61 80];
spec.lens_centre_frame_px = [39.5 11];
tiles = fullfile(root, 'tiles');
for r = 1:2
    for t = 1:4
        d = fullfile(tiles, sprintf('rec%02d', r), sprintf('tile%d', t));
        mkdir(d);
        imwrite(img(:, 1:20), fullfile(d, 'frame_0000.tiff'), 'tiff', 'Compression', 'none');
    end
end
job = rabbit_calibration.make_job(spec, root, tiles, [1 1], '', '');
b1 = imread(fullfile(tiles, 'rec01', 'tile2', 'frame_0000.tiff'));
b2 = imread(fullfile(tiles, 'rec02', 'tile2', 'frame_0000.tiff'));
check('S3a', job.recordings{1}.preprocessed && ~job.recordings{2}.preprocessed && ...
    isequal(b1, rabbit_sauvola(img(:, 1:20), 7, 0)) && isequal(b2, img(:, 1:20)) && ...
    strcmp(job.preprocess.type, 'sauvola') && job.preprocess.window == 7, ...
    'Ccube tiles binarised and flagged, PuzzleBoardCube tiles unchanged');
spec.preprocess = [];
tiles2 = fullfile(root, 'tiles2');
d = fullfile(tiles2, 'rec01', 'tile1'); mkdir(d);
imwrite(img(:, 1:20), fullfile(d, 'frame_0000.tiff'), 'tiff', 'Compression', 'none');
job2 = rabbit_calibration.make_job(spec, root, tiles2, [1 1], '', '');
check('S3b', ~job2.recordings{1}.preprocessed && isempty(job2.preprocess) && ...
    isequal(imread(fullfile(d, 'frame_0000.tiff')), img(:, 1:20)), 'no pre-processing leaves the tiles');

%% S4 summary
c = struct('target', struct('type', 'Ccube', 'n_points', 6, 'edge_mm', 30), ...
    'residual', struct('rmse_px', 1, 'median_px', 0.8), 'observations', struct('kept_fraction', 0.9, 'detected', 100), ...
    'cameras', struct('tile', {'tile1', 'tile2', 'tile3', 'tile4'}, 'rmse_px', 1, 'points', 600, 'images', 30, ...
    'mm_per_px_at_target', 0.12, 'depth_at_target_mm', 1000), 'holdout', struct('name', {}, 'frames_used', {}), ...
    'lens', struct('focal_px', 8000), 'preprocess', rabbit_calibration.default_preprocess());
v = struct('status', 'PASSED', 'metric_allowed', true, 'size_note', '', 'failures', {{}}, 'warnings', {{}});
txt = rabbit_calibration.summary_lines(c, v);
c.preprocess = [];
txt0 = rabbit_calibration.summary_lines(c, v);
check('S4', any(contains(txt, 'Sauvola binarisation (window 7 px, k 0) of the Ccube')) && ...
    any(strcmp(txt0, 'Pre-processing: none.')), strjoin(txt(2:3), ' | '));

%% S5 the window
fake = struct('pycamset_python', '', 'pycamset_checkout', '');
w = rabbit_calibration_dialog(fake, spec.windows, 8000, @() [], [], []);
closer = onCleanup(@() delete(w.Figure));
s_on = w.make_spec();
w.PreprocessBox.Value = false;
s_off = w.make_spec();
check('S5', w.PreprocessBox.Value == false && isstruct(s_on.preprocess) && strcmp(s_on.preprocess.type, 'sauvola') && ...
    isempty(s_off.preprocess), 'ticked by default; unticked gives no pre-processing');

fprintf('RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_calibration_sauvola %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_calibration_sauvola %d/%d\n', pass, fail);
    error('probe_calibration_sauvola: %d check(s) failed', fail);
end
end

function out = direct(img, w, k)
%% Sauvola's threshold evaluated pixel by pixel, with the border mirrored about the edge pixels
if mod(w, 2) == 0, w = w + 1; end
x = double(img);
x = round((x - min(x(:))) * (255 / (max(x(:)) - min(x(:)))));
[nr, nc] = size(x);
h = (w - 1) / 2;
mir = @(i, n) abs(mod(i - 1 + (n - 1), 2 * (n - 1)) - (n - 1)) + 1;   % reflect about the first and last index
out = zeros(nr, nc, 'uint8');
for r = 1:nr
    for c = 1:nc
        rr = mir(r - h:r + h, nr);
        cc = mir(c - h:c + h, nc);
        v = x(rr, cc);
        m = mean(v(:));
        s = sqrt(max(mean(v(:) .^ 2) - m ^ 2, 0));
        if x(r, c) > m * (1 + k * (s / 127.5 - 1)), out(r, c) = 255; end
    end
end
end
