function probe_calibration_cut_views
%% Probe: the calibration cut is a view1..view4 folder the calibration takes as it is
% Collin Snitchler
% 20.11.2026
% The user: the calibration cut should be in one folder per view, for
% pyCamSet, and the calibration window should list that folder, not the
% FITS file.
%   V1  the cut writes view1..view4 by place in the frame (view1 leftmost,
%       whatever the regions file's row order), the outer two flipped, and
%       cut_locations_per_view.json with each view's margins
%   V2  the calibration tiles made from that folder equal those made from
%       the recording itself, pixel for pixel
%   V3  the folder is placed as the reconstruction frame, and the note says
%       it is not shifted again
%   V4  the regions file names the folder (calibration_cut_folder); its
%       calibration_path stays the recording
%   V5  Calibrate... lists the cut folder; without a cut, the recording
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_calibration_cut_views"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
fig = uifigure('Visible', 'off');
fig_cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>

H = 40; W = 60; n = 5;
[cc, rr] = meshgrid(1:W, 1:H);
cal = fullfile(root, 'cube.tif');                           % every pixel its own value
for f = 1:n
    imwrite(uint16(rr * 100 + cc + 5000 * f), cal, 'WriteMode', pick(f == 1, 'overwrite', 'append'));
end
rb = [3 12 38 22; 2 24 39 34; 1 1 40 10; 4 36 37 46];       % the regions file's order: view2;view3;view1;view4
app = cut_app_double();
app.opticalmappingUIFigure = fig;
app.file_info = struct('file', 'om.fits', 'name', 'om.fits', 'path', root, 'type', '.fits');
app.data = struct('image_stack', uint16(rr * 100 + cc), 'height', H, 'width', W, 'rabbit_panoramic', 1, ...
    'region_bounds_src', rb, 'calibration_source', cal, 'calibration_fov_mapping', [], 'calibration_mip', []);
headless_push('uigetdir', root);
ok = rabbit_cut_tiffs.cut_inline(app);
folder = '';
if isfield(app.data.cut_folders_made, 'calibration'), folder = app.data.cut_folders_made.calibration.path; end

%% V1
js = fullfile(folder, 'cut_locations_per_view.json');
cuts = [];
if exist(js, 'file') == 2, cuts = jsondecode(fileread(js)); end
v1 = dir(fullfile(folder, 'view1', '*.tiff'));
first = [];
if ~isempty(v1), first = imread(fullfile(folder, 'view1', v1(1).name)); end
want = fliplr(uint16(rr(1:40, 1:10) * 100 + cc(1:40, 1:10) + 5000));   % the leftmost region, frame 1, flipped
record('V1 view1..view4 by place, outer flipped, with the margins', ok && ~isempty(cuts) && numel(cuts) == 4 && ...
    all(arrayfun(@(q) isfolder(fullfile(folder, sprintf('view%d', q))), 1:4)) && numel(v1) == n && ...
    isequal(first, want) && strcmp(cuts(1).view, 'view1') && cuts(1).roi_row == 3 && cuts(1).left == W - 10 && ...
    cuts(1).right == 0 && cuts(2).roi_row == 1 && cuts(2).left == 11 && cuts(2).top == 2 && cuts(2).bottom == 2, ...
    sprintf('ok %d, folder %s', ok, folder));

%% V2
windows = rabbit_calibration.tile_windows(rb, W);
t_rec = fullfile(root, 'tiles_rec'); t_cut = fullfile(root, 'tiles_cut');
rabbit_calibration.write_tiles(cal, t_rec, windows);
rabbit_calibration.write_tiles(folder, t_cut, windows);
same = true; why = '';
for k = 1:4
    for f = 0:n - 1
        a = imread(fullfile(t_rec, rabbit_calibration.TILES{k}, sprintf('frame_%04d.tiff', f)));
        b = imread(fullfile(t_cut, rabbit_calibration.TILES{k}, sprintf('frame_%04d.tiff', f)));
        % the cut folder holds the regions only: compare inside them
        m = b > 0;
        if ~isequal(size(a), size(b)) || ~isequal(a(m), b(m)) || nnz(m) == 0
            same = false; why = sprintf('tile %d frame %d', k, f);
        end
    end
end
record('V2 tiles from the folder equal those from the recording (inside the regions)', same, why);

%% V3
[p, err] = rabbit_calibration.placement('', [H W], folder);
record('V3 placed as the reconstruction frame, not shifted again', isempty(err) && isequal(p.offset, [0 0]) && ...
    contains(p.note, 'not shifted again'), sprintf('%s | %s', err, p.note));

%% V4
rj = jsondecode(fileread(app.data.cut_roi_json));
record('V4 the regions file names the folder; calibration_path stays the recording', ...
    strcmp(rj.calibration_cut_folder, folder), rj.calibration_cut_folder);

%% V5 the calibration window lists the folder, not the recording
a = analyse_optical_mapping;                                % the app (hidden)
a_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
a.data.calibration_source = cal;
a.data.cut_folders_made = struct('calibration', struct('stem', 'cube', 'path', folder));
listed = a.recon.reconstruction_calibration_prefill();
a.data.cut_folders_made = struct();
listed2 = a.recon.reconstruction_calibration_prefill();
record('V5 Calibrate... lists the cut folder; without a cut, the recording', isequal(listed, {folder}) && ...
    isequal(listed2, {cal}), sprintf('%s | %s', strjoin(listed, ','), strjoin(listed2, ',')));

fprintf('\nPROBE_CALIBRATION_CUT_VIEWS RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function record(name, ok, detail)
        if ok
            fprintf('PASS %s\n', name); pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail); fail = fail + 1;
        end
    end
end

function v = pick(c, a, b)
if c, v = a; else, v = b; end
end
