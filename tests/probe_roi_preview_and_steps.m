function probe_roi_preview_and_steps
%% Probe: the ROI editor's reconstruction preview, and the Steps list
% Collin Snitchler
% 02.11.2026
%   L1-L3 load_stack_preview gives what load_stack gives (FITS, multi-page
%         TIFF, frames folder), with frame 1 only in memory
%   G1    crop: the preview is the mapped window, rows in stored order
%   G2    a box on the preview holds exactly the pixels the cut takes
%   G3    scale mapping: right size, each pixel the max of its block
%   G4    same frame: unchanged; no mapping: not shown, and the reason
%         says why; a window that sticks out: the part inside
%         shown, NaN elsewhere
%   E1    the editor shows the reconstruction and names the file (in
%         colour by default since 19.11.2026; the grey view as before)
%   E2    the optical mapping fallback without a stack
%   E3    a frame that cannot be placed falls back and says so
%   E4    the calibration combination still works on the preview
%   E5    the row-flip note appears for a FITS recording, with the numbers
%   E6    Load ROI JSON: the named file is shown and the ROIs stay; a missing
%         file is stated, and no earlier projection is left on show
%   E7    Save ROI JSON offers the next free name
%   S1-S6 Steps list: scrolling, fixed row height, one button per step, full
%         names, 8 and 10 steps, a press selects, the rebuilt list keeps all,
%         the chosen step is scrolled into view, the state on its own line
%   H1    Run control headers wrap, on their scrolling list
% Needs OM_APP_HEADLESS=1 (no windows). No data files.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_roi_preview_and_steps" -noFigureWindows
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
pass = 0; fail = 0;
root = tempname(tempdir);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));

    function check(id, ok, detail)
        fprintf('%s: %s -> %s\n', id, detail, char(70 + 14 * logical(ok)));
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end

%% the loaders agree
H = 16; W = 24; N = 230;
stack = uint16(zeros(H, W, N));
for f = 1:N
    stack(:, :, f) = uint16(mod((1:H)' * (1:W) * f, 4001));
end
fits = fullfile(root, 'stack.fits');
fitswrite(double(stack), fits);
a = rabbit_stack_io.load_stack(fits);
b = rabbit_stack_io.load_stack_preview(fits);
check('L1', isequal(a.mip, b.mip) && isequal(a.stack(:, :, 1), b.stack) && b.n_frames == N && ...
    b.height == H && b.width == W && size(b.stack, 3) == 1, sprintf('FITS: same MIP over %d frames, one frame kept', N));
tif = fullfile(root, 'stack.tif');
folder = fullfile(root, 'frames');
mkdir(folder);
for f = 1:5
    if f == 1, mode = 'overwrite'; else, mode = 'append'; end
    imwrite(stack(:, :, f), tif, 'WriteMode', mode);
    imwrite(stack(:, :, f), fullfile(folder, sprintf('f%d.tif', f)));
end
a = rabbit_stack_io.load_stack(tif);
b = rabbit_stack_io.load_stack_preview(tif);
check('L2', isequal(a.mip, b.mip) && b.n_frames == 5, 'multi-page TIFF');
a = rabbit_stack_io.load_stack(folder);
b = rabbit_stack_io.load_stack_preview(folder);
check('L3', isequal(a.mip, b.mip) && b.n_frames == 5, 'frames folder');

%% geometry
omH = 4; omW = 10;
big = single((1:12)' * 1000 + (1:20));
crop = struct('type', 'crop', 'camera_stationary', true, ...
    'om_window_in_rec', struct('off', 3, 'cols_off', 2), 'scale', struct('vertical', 1, 'horizontal', 1));
img = rabbit_stack_io.mip_in_editor_frame(big, omH, omW, crop);
check('G1', isequal(img, big(4:7, 3:12)) && img(1, 1) == 4003 && img(end, 1) == 7003, ...
    sprintf('rows 4 to 7, first %d, last %d, not flipped', img(1, 1), img(end, 1)));
box = [2 3 4 8];
mb = rabbit_stack_io.map_bounds_across_fov(box, crop);
check('G2', isequal(img(box(1):box(3), box(2):box(4)), big(mb(1):mb(3), mb(2):mb(4))), ...
    sprintf('box %s = cut %s', mat2str(box), mat2str(mb)));
scale = struct('type', 'scale', 'camera_stationary', true, ...
    'om_window_in_rec', struct('off', 0), 'scale', struct('vertical', 2, 'horizontal', 2));
big2 = single(magic(40));
img2 = rabbit_stack_io.mip_in_editor_frame(big2(1:8, 1:20), 4, 10, scale);
sub = big2(3:4, 5:6);
check('G3', isequal(size(img2), [4 10]) && img2(2, 3) == max(sub(:)), 'scale 2: blocks of 2 x 2');
same = rabbit_stack_io.mip_in_editor_frame(img, omH, omW, []);
[none, why1] = rabbit_stack_io.mip_in_editor_frame(big, omH, omW, []);
far = crop;
far.om_window_in_rec.off = 10;
[out, why2, cov2] = rabbit_stack_io.mip_in_editor_frame(big, omH, omW, far);
check('G4', isequal(same, img) && isempty(none) && contains(why1, 'no position') && isempty(why2) && ...
    isequal(find(any(cov2, 2))', [1 2]) && isequal(out(1:2, :), big(11:12, 3:12)) && all(isnan(out(3:4, :)), 'all'), ...
    sprintf('"%s"; rows %s covered', why1, mat2str(find(any(cov2, 2))')));

%% the editor
hE = 60; wE = 200;
om = single(zeros(hE, wE, 3));
om(21:40, 11:40, :) = 5;
om(21:40, 61:90, :) = 5;
om(21:40, 111:140, :) = 5;
om(21:40, 161:190, :) = 5;
rec_mip = single(rand(120, wE) * 100);
rec_mip(1:30, :) = 0;
rec_path = fullfile(root, 'rec.fits');
fitswrite(double(rec_mip), rec_path);
mapping = struct('type', 'crop', 'camera_stationary', true, ...
    'om_window_in_rec', struct('off', 30, 'cols_off', 0), 'scale', struct('vertical', 1, 'horizontal', 1));
app = om_app_double();
app.file_info = struct('file', 'om.fits', 'name', 'om.fits', 'path', root, 'type', '.fits');
base = struct('image_stack', om, 'height', hE, 'width', wE, 'calibration_mip', [], ...
    'reconstruction_mip', [], 'reconstruction_path', '', 'reconstruction_loaded', false, ...
    'reconstruction_fov_mapping', [], 'calibration_fov_mapping', [], 'rotation', 3, 'rabbit_panoramic', 1);
app.data = base;
app.data.reconstruction_mip = rec_mip;
app.data.reconstruction_path = rec_path;
app.data.reconstruction_mip_source = rec_path;
app.data.reconstruction_mip_frames = 400;
app.data.reconstruction_fov_mapping = mapping;
ed = rabbit_panoramic_editor(app);
closer = onCleanup(@() delete(ed));
expected = rec_mip(31:90, 1:wE);
check('E1a', strcmp(ed.ShowDropdown.Value, 'colour') && size(ed.ImageTop.CData, 3) == 3 && ...
    max(abs(ed.ImageTop.CData(:, :, 2) - rabbit_stack_io.normalize_mip(expected)), [], 'all') < 1e-6, ...
    'colour by default: the reconstruction in green');
ed.choose_show('reconstruction');
check('E1', isequal(ed.ImageTop.CData, expected) && isequal(ed.ImageBottom.CData, fliplr(expected)) && ...
    contains(ed.AxesTop.Title.String, 'rec.fits') && contains(ed.PreviewLabel.Text, 'all 400 frames') && ...
    contains(ed.PreviewLabel.Text, 'rec.fits'), ed.PreviewLabel.Text);
m = ed.main_app; ed.write_src_bounds();
s = m.data.region_bounds_src;
check('E6', isequal(sign(diff(s([3 1 2 4], 2)))', [1 1 1]), sprintf('view1, view2, view3, view4 run left to right in the source: %s', mat2str(s(:, 2)')));
tp = ed.ROIs.view2.Position; tq = ed.ROIs.view3.Position; bp = ed.ROIs.view4.Position; bq = ed.ROIs.view1.Position;
check('E7', tp(1) > wE / 4 && tp(1) + tp(3) < wE / 2 && tq(1) > wE / 2 && tq(1) + tq(3) < 3 * wE / 4 && ...
    bp(1) + bp(3) < wE / 4 && bq(1) > 3 * wE / 4, 'view2 mid-left and view3 mid-right on top, view4 far left and view1 far right below');
ed.note_old_view_labels([1 1 9 9; 1 5 9 9; 1 10 9 9; 1 15 9 9]);
check('E8', contains(ed.StatusLabel.Text, 'as older versions of the app did'), ed.StatusLabel.Text);
check('E5', contains(ed.PreviewLabel.Text, 'upside down') && contains(ed.PreviewLabel.Text, 'Rows off centre: view1 '), ...
    'row-flip note present');
ed.delete();

app.data = base;
ed2 = rabbit_panoramic_editor(app);
check('E2', isequal(ed2.ImageTop.CData, max(om, [], 3)) && contains(ed2.PreviewLabel.Text, 'optical mapping recording') && ...
    ~contains(ed2.PreviewLabel.Text, 'upside down'), ed2.PreviewLabel.Text);
ed2.delete();

app.data = base;
app.data.reconstruction_mip = rec_mip;
app.data.reconstruction_path = rec_path;
ed3 = rabbit_panoramic_editor(app);
check('E3', isequal(ed3.ImageTop.CData, max(om, [], 3)) && contains(ed3.PreviewLabel.Text, 'not shown') && ...
    contains(ed3.PreviewLabel.Text, 'no position'), ed3.PreviewLabel.Text);
ed3.delete();

app.data = base;
app.data.reconstruction_mip = rec_mip;
app.data.reconstruction_path = rec_path;
app.data.reconstruction_fov_mapping = mapping;
cal = single(zeros(120, wE));
cal(40:50, 20:30) = 7;
app.data.calibration_mip = cal;
app.data.calibration_fov_mapping = mapping;
ed4 = rabbit_panoramic_editor(app);
ed4.choose_show('combined');
check('E4', isequal(ed4.ImageTop.CData, rabbit_stack_io.combined_display(expected, cal(31:90, :))) && ...
    contains(ed4.AxesTop.Title.String, 'calibration'), ed4.AxesTop.Title.String);
ed4.delete();

% Load ROI JSON: first the OM display, then the JSON names the file
app.data = base;
ed5 = rabbit_panoramic_editor(app);
roi_json = fullfile(root, 'roi.json');
bounds = [5 10 50 50; 5 60 50 100; 5 110 50 150; 5 160 50 195];
payload = struct('schema_version', 1, 'region_bounds_src', bounds, 'regions', 4, 'rotation', 3, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', hE, 'width', wE), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, 'reconstruction_path', rec_path, ...
    'fov_mapping', mapping);
rabbit_stack_io.save_roi_json(roi_json, payload);
headless_push('uigetfile', roi_json);
ed5.load_roi_json();
ed5.write_src_bounds();
ed5.choose_show('reconstruction');
check('E6a', max(abs(ed5.ImageTop.CData(:) - expected(:))) < 1e-3, 'the file named in the ROI JSON is shown');
check('E6b', isequal(app.data.region_bounds_src, bounds) && isfield(ed5.ROIs, 'view2') && isvalid(ed5.ROIs.view2), ...
    'the ROIs survive the new picture');
payload.reconstruction_path = fullfile(root, 'gone.fits');
rabbit_stack_io.save_roi_json(roi_json, payload);
headless_push('uigetfile', roi_json);
ed5.load_roi_json();
check('E6c', isequal(ed5.ImageTop.CData, max(om, [], 3)) && contains(ed5.PreviewLabel.Text, 'gone.fits') && ...
    contains(ed5.PreviewLabel.Text, 'not found'), ed5.PreviewLabel.Text);
headless_push('uiputfile', fullfile(root, 'cut_locations_per_view.json'));
ed5.save_roi_json();
next_name = rabbit_stack_io.next_free_path(fullfile(root, 'cut_locations_per_view'), '.json');
payload.reconstruction_path = rec_path;
rabbit_stack_io.save_roi_json(roi_json, payload);
headless_push('uigetfile', roi_json);
ed5.load_roi_json();
shown_again = ed5.ReconstructionShown;
payload.reconstruction_path = '';
rabbit_stack_io.save_roi_json(roi_json, payload);
headless_push('uigetfile', roi_json);
ed5.load_roi_json();
check('E6d', shown_again && ~ed5.ReconstructionShown && isequal(ed5.ImageTop.CData, max(om, [], 3)), ...
    'a ROI file that names no stack leaves no reconstruction picture on show');
check('E7', isfile(fullfile(root, 'cut_locations_per_view.json')) && ...
    endsWith(next_name, 'cut_locations_per_view_01.json'), next_name);
ed5.delete();

%% Steps list
app = analyse_optical_mapping();
close_app = onCleanup(@() delete(app));
grid = app.recon.StageRowsGrid;
rows = @() findall(grid, 'Type', 'uibutton');
n0 = numel(app.recon.ReconstructionStageList.Items);
h = cell2mat(grid.RowHeight);
check('S1', strcmp(char(grid.Scrollable), 'on') && strcmp(char(app.recon.ReconstructionStageList.Visible), 'off') && ...
    numel(rows()) == n0 && all(h == h(1)) && h(1) >= 22 && h(1) <= 30 && ...
    numel(findall(grid, 'Type', 'uilabel')) == n0, sprintf('%d one-line tiles of %d px with chips, scrolling', n0, h(1)));
app.recon.ReconstructionSparseSourceDropDown.Value = 'built';
app.recon.reconstruction_sparse_source_changed();
app.recon.ReconstructionDenseDropDown.Value = 'both';   % "APDe-MVS + COLMAP"
app.recon.reconstruction_dense_changed();
n10 = numel(app.recon.ReconstructionStageList.Items);
b = rows();
b_order = sort_by_row(b);
txt = cellfun(@(x) strjoin(cellstr(x), ' '), {b_order.Text}, 'UniformOutput', false);
check('S2', n10 == 10 && numel(b) == 10 && numel(grid.RowHeight) == 10 && contains(txt{2}, ...
    'Sparse model (COLMAP structure from motion)') && startsWith(txt{10}, '10  ') && ...
    contains(txt{7}, 'Dense cloud (COLMAP fusion, for the visibility check)'), sprintf('10 steps; row 2: %s; row 7: %s', txt{2}, txt{7}));
app.recon.ReconstructionDenseDropDown.Value = 'colmap';
app.recon.reconstruction_dense_changed();
b = rows();
check('S3', numel(b) == 8 && numel(grid.RowHeight) == 8, sprintf('back to %d rows', numel(b)));
b_order = sort_by_row(b);
feval(b_order(3).ButtonPushedFcn, b_order(3), []);
stages = app.recon.ReconstructionStageList.ItemsData;
check('S4', strcmp(app.recon.ReconstructionStageList.Value, stages{3}) && strcmp(char(b_order(3).FontWeight), 'bold') && ...
    strcmp(char(b_order(1).FontWeight), 'normal'), sprintf('pressed row 3: %s', app.recon.ReconstructionStageList.Value));
fig_app = app.opticalmappingUIFigure;
set(app.TabGroup, 'Position', [1 0 fig_app.Position(3) floor(fig_app.Position(4) / 3)], 'Visible', 'on');
app.TabGroup.SelectedTab = app.recon.ReconstructionTab;
app.recon.ReconstructionStageList.Value = stages{7};
drawnow;
pause(1);    % the tab must be laid out before it can scroll
% A pause alone did not always do it: in a full-suite run the list was
% measured at its unlaid-out 100 px; drawing the window lays it
% out, as probe_reproject_redo P8b does
exportapp(fig_app, [tempname '.png']);
drawnow;
app.recon.reconstruction_stage_rows_show_chosen();
drawnow;
pause(1);
y = grid.ScrollableViewportLocation(2);
% One-line tiles: all of them normally fit, so row 7 is in view without
% scrolling; when they do not fit, the list scrolls to it
need = numel(grid.RowHeight) * (cell2mat(grid.RowHeight(1)) + grid.RowSpacing);
check('S6', y < 1 || grid.Position(4) >= need, sprintf('row 7 in view: position %.0f, %d of %d px', ...
    y, round(grid.Position(4)), round(need)));
[t, chip] = app.recon.reconstruction_stage_row_text('> RESUME HERE Step 2 of 8: Depth maps (COLMAP) [PASSED WITH WARNINGS]');
check('S5', strcmp(t, '2  Depth maps (COLMAP) (resume here)') && strcmp(chip, 'WARN'), [t ' / ' chip]);
check('H1', strcmp(char(app.recon.GridLayoutR1.Scrollable), 'on') && strcmp(char(app.recon.StepHeader2.WordWrap), 'on') && ...
    all(cell2mat(app.recon.GridLayoutR1.RowHeight) >= 58) && strcmp(app.recon.ReconstructionSparseSourceDropDown.Value, 'built') && contains(app.recon.ReconstructionStageList.Items{1}, 'Prepare images'), 'headers wrap in a scrolling list; the sparse model is built by default');

fprintf('PROBE_ROI_PREVIEW_AND_STEPS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_roi_preview_and_steps %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_roi_preview_and_steps\n');
    error('probe_roi_preview_and_steps:Failed', '%d check(s) failed.', fail);
end
end

function b = sort_by_row(b)
rows = arrayfun(@(x) x.Layout.Row, b);
[~, order] = sort(rows);
b = b(order);
end
