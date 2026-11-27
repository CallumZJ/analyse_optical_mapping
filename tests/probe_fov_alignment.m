function probe_fov_alignment
%% Probe: recordings whose camera area of interest differs
% Collin Snitchler
% 19.11.2026
% The optical mapping, reconstruction and calibration recordings come from
% one camera that does not move, but the camera's area of interest (the
% FITS frame size and position) may change between them. Checks:
%   M1-M6 measure_fov_offset finds the optical-mapping frame in another
%         frame to the pixel: inside it, around it (the other frame
%         smaller), partly outside, the same size but shifted, shifted
%         sideways; a flat frame gives no match
%   V1    validate_fov_mapping takes negative whole offsets, refuses others
%   P1-P3 mip_in_editor_frame of a partly covering frame: the covered part
%         equals the cut's pixels, NaN and false elsewhere; none covered
%         says why
%   B1    boxes_outside names the boxes that leave a frame
%   O1    overlap_text for whole, partial and no overlap
%   X1-X2 the cut maps the boxes with a negative offset and takes the same
%         pixels; a box outside the smaller frame is refused
%   X3    a same-size recording with a recorded shift is cut shifted
%   X4    cut_from_roi cuts the calibration with calibration_fov_mapping,
%         not with the reconstruction's fov_mapping; X5 not with one saved
%         without the calibration's name, for another frame size
%   E1-E5 ROI editor: colour view by default with each recording in its
%         channel, outline of the partly covering frame, the grey views on
%         offer, the box check, and Regions Selected asks before keeping a
%         box outside a recording (Go back keeps the editor open)
%   K1    read_binning reads VBIN/HBIN of a FITS header; binning_mismatch
%         refuses a recording with another binning
%   D1    the calibration window: a typed position (asked again after a
%         mistake), a measured one, a cancelled one, a same-size one kept
%   F1-F5 still pixels give the position while the heart moves; the load
%         dialog's question (measured, typed, same position, cancelled);
%         the position's source survives JSON; cut folders of another
%         position are not reused; another recording of the same size lends
%         its alignment
%   C1-C6 calibration: a recording with a smaller frame is placed in the
%         reconstruction frame (measured), its tiles equal the
%         reconstruction-frame tiles where it has pixels and are zero
%         elsewhere; check_frames takes it with its offset, refuses it
%         without one, refuses one that misses a tile, and refuses a cut
%         folder of another frame; C6 a recording that does not match well
%         enough needs its position typed in
% Needs OM_APP_HEADLESS=1 (no windows). No data files.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_fov_alignment" -noFigureWindows
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

%% M: measuring the position (a textured sensor, crops of known position)
rng(7);
sensor = imgaussfilt(rand(300, 500), 2) * 1000;   % smooth texture, like a lit rig
om = sensor(101:180, 61:420);                     % the optical mapping frame: 80 x 360
cases = {'M1 inside', sensor(41:260, 21:470), [60 40]; ...
    'M2 around it', sensor(121:160, 101:380), [-20 -40]; ...
    'M3 partly outside', sensor(121:280, 41:460), [-20 20]; ...
    'M4 same size, shifted', sensor(91:170, 61:420), [10 0]; ...
    'M5 shifted sideways', sensor(101:180, 81:440), [0 -20]};
for k = 1:size(cases, 1)
    e = rabbit_stack_io.measure_fov_offset(om, cases{k, 2});
    check(cases{k, 1}(1:2), isequal([e.off e.cols_off], cases{k, 3}) && e.ncc > 0.999, ...
        sprintf('%s: expected %s, got %s, score %.4f, overlap %.2f', cases{k, 1}, mat2str(cases{k, 3}), ...
        mat2str([e.off e.cols_off]), e.ncc, e.overlap));
end
e = rabbit_stack_io.measure_fov_offset(zeros(80, 360), sensor);
check('M6', ~isfinite(e.ncc), 'a flat frame gives no match');

%% V: negative offsets in a mapping
m = rabbit_stack_io.offset_mapping(-20, -40, 'probe');
v = rabbit_stack_io.validate_fov_mapping(m);
bad = m; bad.om_window_in_rec.off = 2.5;
threw = false;
try
    rabbit_stack_io.validate_fov_mapping(bad);
catch ME
    threw = contains(ME.message, 'whole number');
end
check('V1', v.om_window_in_rec.off == -20 && v.om_window_in_rec.cols_off == -40 && threw, ...
    'negative whole offsets kept, 2.5 refused');

%% P: the editor picture of a frame that covers part of the optical mapping frame
small = cases{2, 2};                               % 40 x 280, the OM frame starts 20 rows above it
mp = rabbit_stack_io.offset_mapping(-20, -40, 'probe');
[img, why, cover] = rabbit_stack_io.mip_in_editor_frame(small, 80, 360, mp);
check('P1', isempty(why) && isequal(size(img), [80 360]) && isequal(find(any(cover, 2))', 21:60) && ...
    isequal(find(any(cover, 1)), 41:320) && all(isnan(img(~cover))) && ...
    max(abs(double(img(21:60, 41:320)) - small), [], 'all') < 1e-3, ...
    'rows 21 to 60 and columns 41 to 320 covered, NaN elsewhere');
box = [25 50 55 300];
mb = rabbit_stack_io.map_bounds_across_fov(box, mp);
check('P2', max(abs(double(img(box(1):box(3), box(2):box(4))) - small(mb(1):mb(3), mb(2):mb(4))), [], 'all') < 1e-3, ...
    sprintf('box %s takes the cut pixels %s', mat2str(box), mat2str(mb)));
far = rabbit_stack_io.offset_mapping(500, 0, 'probe');
[none, why2] = rabbit_stack_io.mip_in_editor_frame(small, 80, 360, far);
check('P3', isempty(none) && contains(why2, 'lies outside'), why2);

%% B, O: boxes and overlap in words
[out, txt] = rabbit_stack_io.boxes_outside([25 50 55 300; 1 1 80 100; 30 300 50 330], mp, [40 280], 'reconstruction');
check('B1', isequal(out', [false true true]) && contains(txt, 'ROI 2') && contains(txt, 'ROI 3') && ...
    ~contains(txt, 'ROI 1 '), txt);
t1 = rabbit_stack_io.overlap_text(80, 360, 220, 450, 60, 40);
t2 = rabbit_stack_io.overlap_text(80, 360, 40, 280, -20, -40);
t3 = rabbit_stack_io.overlap_text(80, 360, 40, 280, 100, 0);
check('O1', contains(t1, 'whole') && contains(t2, 'rows 21 to 60 and columns 41 to 320') && contains(t3, 'no part'), ...
    sprintf('"%s" / "%s" / "%s"', t1, t2, t3));

%% X: the cut with a negative offset
app = om_app_double();
app.file_info = struct('file', 'om.tif', 'name', 'om.tif', 'path', root, 'type', '.tif');
stack = uint16(repmat(round(small), 1, 1, 2));
bounds = [25 50 55 100; 25 110 55 160; 25 170 55 220; 25 230 55 300];
mbs = rabbit_stack_io.map_bounds_across_fov(bounds, mp);
[ok, out_root] = rabbit_cut_tiffs.cut_stack(app, 'reconstruction', stack, 40, 280, 2, 'rec', 'rec.tif', ...
    mbs, [80 360], [], fullfile(root, 'cut1'), mp);
c1 = imread(fullfile(out_root, rabbit_cut_tiffs.frame_output_name('reconstruction', 'rec', 'rec.tif', 1, 1)));
check('X1', ok && isequal(c1, stack(mbs(1, 1):mbs(1, 3), mbs(1, 2):mbs(1, 4), 1)) && mbs(1, 1) == 5, ...
    sprintf('the first box is cut from rows %d to %d of the smaller frame', mbs(1, 1), mbs(1, 3)));
mbad = rabbit_stack_io.map_bounds_across_fov([1 50 30 100; bounds(2:4, :)], mp);
ok2 = true;   % assigned by evalc below (a nested-function workspace is static)
said = evalc(['ok2 = rabbit_cut_tiffs.cut_stack(app, ''reconstruction'', stack, 40, 280, 2, ''rec'', ''rec.tif'', ' ...
    'mbad, [80 360], [], fullfile(root, ''cut2''), mp);']);
check('X2', ~ok2 && ~isfolder(fullfile(root, 'cut2')) && contains(said, 'area of interest'), ...
    'a box above the smaller frame is refused, nothing written');
% X3, X4: the dataset cuts read the mapping of their own recording
om_stack = single(repmat(sensor(101:180, 61:420), 1, 1, 2));
rec_same = sensor(91:170, 61:420);                    % same size, shifted 10 rows
cal_big = sensor(41:260, 21:470);                     % larger, offset 60, 40
rec_file = fullfile(root, 'rec_same.tif');
cal_file = fullfile(root, 'cal_big.tif');
for f = 1:2
    mode = 'overwrite'; if f > 1, mode = 'append'; end
    imwrite(uint16(round(rec_same)), rec_file, 'WriteMode', mode);
    imwrite(uint16(round(cal_big)), cal_file, 'WriteMode', mode);
end
app2 = om_app_double();
app2.file_info = struct('file', 'om.tif', 'name', 'om.tif', 'path', root, 'type', '.tif');
app2.data = struct('image_stack', om_stack, 'height', 80, 'width', 360, 'calibration_source', cal_file, ...
    'reconstruction_path', rec_file, 'calibration_mip', [], 'reconstruction_mip', [], ...
    'reconstruction_fov_mapping', rabbit_stack_io.offset_mapping(10, 0, 'probe'), ...
    'calibration_fov_mapping', rabbit_stack_io.offset_mapping(60, 40, 'probe'));
roi_json = fullfile(root, 'roi.json');
rabbit_stack_io.save_roi_json(roi_json, struct('schema_version', 1, 'region_bounds_src', bounds, 'regions', 4, ...
    'rotation', 3, 'rabbit_panoramic', true, 'source_dims', struct('height', 80, 'width', 360), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, 'reconstruction_path', rec_file, ...
    'fov_mapping', app2.data.reconstruction_fov_mapping, ...
    'calibration_fov_mapping', app2.data.calibration_fov_mapping, 'calibration_path', cal_file));
okc5 = true;   % assigned by evalc below
[okr, rroot] = rabbit_cut_tiffs.cut_from_roi(app2, roi_json, 'reconstruction', 'OutputRoot', fullfile(root, 'cr'));
[okc, croot] = rabbit_cut_tiffs.cut_from_roi(app2, roi_json, 'calibration', 'OutputRoot', fullfile(root, 'cc'));
r1 = imread(fullfile(rroot, rabbit_cut_tiffs.frame_output_name('reconstruction', 'rec_same', rec_file, 1, 1)));
% the calibration cut is one folder per view, by place in the frame, the
% outer two flipped
[~, by_col] = sort(bounds(:, 2)); place_of = zeros(1, 4); place_of(by_col) = 1:4;
q1 = imread(fullfile(croot, sprintf('view%d', place_of(1)), ...
    rabbit_cut_tiffs.frame_output_name('calibration', 'cal_big', cal_file, place_of(1), 1)));
if any(place_of(1) == [1 4]), q1 = fliplr(q1); end
want = uint16(round(sensor(101 + bounds(1, 1) - 1:101 + bounds(1, 3) - 1, 61 + bounds(1, 2) - 1:61 + bounds(1, 4) - 1)));
check('X3', okr && isequal(r1, want), 'the same-size reconstruction is cut 10 rows down: the same sensor pixels');
check('X4', okc && isequal(q1, want), 'the calibration is cut with its own mapping: the same sensor pixels');
roi_old = fullfile(root, 'roi_old.json');             % saved before the calibration was named
rabbit_stack_io.save_roi_json(roi_old, rmfield(rabbit_stack_io.load_roi_json(roi_json, [], []), 'calibration_path'));
said5 = evalc('okc5 = rabbit_cut_tiffs.cut_from_roi(app2, roi_old, ''calibration'', ''OutputRoot'', fullfile(root, ''cc5''));');
check('X5', ~okc5 && contains(said5, 'not for this recording'), 'a calibration position that names no recording is not applied to another frame size');

%% E: the ROI editor
hE = 80; wE = 360;
omv = single(zeros(hE, wE, 2));
omv(21:60, 21:80, :) = 5; omv(21:60, 111:170, :) = 5; omv(21:60, 201:260, :) = 5; omv(21:60, 281:340, :) = 5;
rec_small = single(small);                           % covers rows 21 to 60 only
rec_path = fullfile(root, 'rec_small.tif');
imwrite(uint16(round(small)), rec_path);
app3 = om_app_double();
app3.file_info = struct('file', 'om.tif', 'name', 'om.tif', 'path', root, 'type', '.tif');
app3.data = struct('image_stack', omv, 'height', hE, 'width', wE, 'calibration_mip', single(cal_big), ...
    'reconstruction_mip', rec_small, 'reconstruction_path', rec_path, 'reconstruction_mip_source', rec_path, ...
    'reconstruction_mip_frames', 1, 'reconstruction_loaded', true, ...
    'reconstruction_fov_mapping', mp, 'calibration_fov_mapping', rabbit_stack_io.offset_mapping(60, 40, 'probe'), ...
    'rotation', 3, 'rabbit_panoramic', 1);
ed = rabbit_panoramic_editor(app3);
closer = onCleanup(@() delete(ed));
cd_ = ed.ImageTop.CData;
g = rabbit_stack_io.normalize_mip(rec_small);
check('E1', size(cd_, 3) == 3 && strcmp(ed.ShowDropdown.Value, 'colour') && ...
    max(abs(cd_(21:60, 41:320, 2) - g), [], 'all') < 1e-6 && all(cd_([1:20 61:80], :, 2) == 0, 'all') && ...
    any(cd_(:, :, 1) > 0, 'all') && any(cd_(:, :, 3) > 0, 'all'), ...
    'colour: calibration red, reconstruction green (dark outside its frame), optical mapping blue');
check('E2', numel(ed.OutlineLines) == 2 && all(isgraphics(ed.OutlineLines)), ...
    'the partly covering reconstruction frame is outlined on both panels');
ed.choose_show('reconstruction');
r_cd = ed.ImageTop.CData;
check('E3', size(r_cd, 3) == 1 && max(abs(r_cd(21:60, 41:320) - rec_small), [], 'all') < 1e-3 && ...
    all(ismember({'colour', 'om', 'reconstruction', 'calibration', 'combined'}, ed.ShowDropdown.ItemsData)), ...
    'the grey reconstruction view and every view on offer');
[okb, txt] = ed.check_boxes();
check('E4', ~okb && contains(txt, 'reconstruction') && contains(ed.CoverageLabel.Text, 'cannot be cut') && ...
    isequal(ed.CoverageLabel.FontColor, [0.8 0 0]), txt);
headless_push('uiconfirm', 'Go back to the boxes');
ed.confirm_edit();
held = ~ed.fired;
headless_push('uiconfirm', 'Keep them');
ed.confirm_edit();
check('E5', held && ed.fired, 'Regions Selected asks: Go back keeps the editor, Keep them goes on');
ed.delete();

%% K: binning from the FITS header
kf = fullfile(root, 'binned.fits');
fptr = matlab.io.fits.createFile(kf);
matlab.io.fits.createImg(fptr, 'int16', [10 12]);
matlab.io.fits.writeImg(fptr, int16(ones(10, 12)));
matlab.io.fits.writeKey(fptr, 'VBIN', 2, 'Vertical binning');
matlab.io.fits.writeKey(fptr, 'HBIN', 2, 'Horizontal binning');
matlab.io.fits.closeFile(fptr);
b = rabbit_stack_io.read_binning(kf);
nb = rabbit_stack_io.read_binning(rec_path);
mm = rabbit_stack_io.binning_mismatch([1 1], b, 'reconstruction');
check('K1', isequal(b, [2 2]) && all(isnan(nb)) && contains(mm, '2 x 2') && ...
    isempty(rabbit_stack_io.binning_mismatch([1 1], nb, 'reconstruction')), mm);

%% C: calibration recordings of another frame
H = 60; W = 300;
full = imgaussfilt(rand(H, W), 1.5) * 3000 + 100;       % the still rig
nfr = 8;
rec_frame = fullfile(root, 'rec_frame.tif');
cal_crop = fullfile(root, 'cal_crop.tif');
for f = 1:nfr
    mode = 'overwrite'; if f > 1, mode = 'append'; end
    a = full; a(10:30, 20 * f + (1:25)) = 9000;           % a heart that moves
    b = full; b(30:50, 280 - 25 * f + (1:20)) = 7000;     % a cube that moves elsewhere
    imwrite(uint16(round(a)), rec_frame, 'WriteMode', mode);
    imwrite(uint16(round(b(16:55, :))), cal_crop, 'WriteMode', mode);   % 40 rows from row 16
end
[place, perr] = rabbit_calibration.placement(rec_frame, [H W], cal_crop);
check('C1', isempty(perr) && strcmp(place.source, 'measured') && isequal(place.offset, [15 0]) && ...
    place.trusted && contains(place.note, 'shifted 15 px down'), sprintf('%s %s (%s)', mat2str(place.offset), place.note, place.why));
win = [1 60; 61 150; 151 240; 241 300];
tdir = fullfile(root, 'ctiles');
[nf, Hc] = rabbit_calibration.write_tiles(cal_crop, tdir, win, [], struct('offset', [15 0], 'frame_hw', [H W]));
t2 = imread(fullfile(tdir, 'tile2', 'frame_0000.tiff'));
t1 = imread(fullfile(tdir, 'tile1', 'frame_0001.tiff'));
cs = imread(cal_crop, 2);
c1 = imread(cal_crop, 1);
check('C2', nf == nfr && Hc == H && isequal(size(t2), [H 90]) && isequal(t2(16:55, :), c1(:, 61:150)) && ...
    all(t2([1:15 56:60], :) == 0, 'all') && isequal(t1(16:55, :), fliplr(cs(:, 1:60))), ...
    'tiles in the reconstruction frame: its rows where the recording has pixels, zero elsewhere');
spec = rabbit_calibration.default_spec();
spec.frame_hw = [H W]; spec.roi_hw = [H W];
spec.roi_bounds = [1 1 60 50; 1 70 60 140; 1 160 60 230; 1 250 60 300];
spec.recordings = struct('path', {cal_crop}, 'role', {'fit'}, 'frame_offset', {[15 0]}, 'offset_note', {'x'});
[okf, ferr] = rabbit_calibration.check_frames(spec);
spec2 = spec; spec2.recordings(1).frame_offset = [];
[okf2, ferr2] = rabbit_calibration.check_frames(spec2);
spec3 = spec; spec3.recordings(1).frame_offset = [0 -250];   % shows only columns 1 to 50
[okf3, ferr3] = rabbit_calibration.check_frames(spec3);
check('C3', okf && ~okf2 && contains(ferr2, 'position') && ~okf3 && contains(ferr3, 'View2'), ...
    sprintf('%s | %s | %s', ferr, ferr2, ferr3));
cutf = fullfile(root, 'cutf');
for k = 1:4, mkdir(fullfile(cutf, sprintf('view%d', k))); end
locs = struct('view', {'view1', 'view2', 'view3', 'view4'}, 'top', {5, 5, 5, 5}, 'bottom', {15, 15, 15, 15}, ...
    'left', {0, 0, 0, 0}, 'right', {270, 270, 270, 270});
for k = 1:4, imwrite(uint8(ones(20, 30)), fullfile(cutf, sprintf('view%d', k), 'f_0000.tiff')); end
fid = fopen(fullfile(cutf, 'cut_locations_per_view.json'), 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(locs), 'char');
fclose(fid);
[~, cerr] = rabbit_calibration.placement(rec_frame, [H W], cutf);
check('C4', contains(cerr, 'cut folder'), cerr);
[place5, perr5] = rabbit_calibration.placement(rec_frame, [H W], rec_frame);
check('C5', isempty(perr5) && strcmp(place5.source, 'same frame') && isequal(place5.offset, [0 0]), place5.note);
other = fullfile(root, 'other.tif');                 % another scene, another size: no trusted match
for f = 1:nfr
    mode = 'overwrite'; if f > 1, mode = 'append'; end
    imwrite(uint16(round(imgaussfilt(rand(45, W), 1.5) * 3000 + 100)), other, 'WriteMode', mode);
end
[place6, perr6] = rabbit_calibration.placement(rec_frame, [H W], other);
check('C6', isempty(perr6) && isempty(place6.source) && ~place6.same_size && ~isempty(place6.why), place6.why);

%% D: the calibration window's questions
fake = struct('pycamset_python', '', 'pycamset_checkout', '', 'set_tool_path', @(varargin) [], ...
    'calibration_root', @() root, 'record_calibration_failure', @(varargin) [], 'cancel_calibration', @() []);
win_bounds = spec.roi_bounds;
w = rabbit_calibration_dialog(fake, win_bounds, 8000, @() [], [H W], [H W], rec_frame);
headless_push('inputdlg', {'x', '1'});                % a mistake: asked again
headless_push('inputdlg', {'15', '0'});
okd1 = w.add_row(other, 'fit', 'PuzzleBoardCube', 7, 30, 'x');
okd2 = w.add_row(cal_crop, 'holdout', 'PuzzleBoardCube', 7, 30, 'x');
headless_push('inputdlg', {});                        % Cancel: not added
okd3 = w.add_row(other, 'holdout', 'PuzzleBoardCube', 7, 30, 'x');
same_other = fullfile(root, 'same_other.tif');
for f = 1:nfr
    mode = 'overwrite'; if f > 1, mode = 'append'; end
    imwrite(uint16(round(imgaussfilt(rand(H, W), 1.5) * 3000 + 100)), same_other, 'WriteMode', mode);
end
okd4 = w.add_row(same_other, 'holdout', 'PuzzleBoardCube', 7, 30, 'x');   % default answer: They line up
sp = w.make_spec();
check('D1', okd1 && okd2 && ~okd3 && okd4 && numel(sp.recordings) == 3 && ...
    isequal(sp.recordings(1).frame_offset, [15 0]) && strcmp(sp.recordings(1).offset_source, 'typed') && ...
    isequal(sp.recordings(2).frame_offset, [15 0]) && strcmp(sp.recordings(2).offset_source, 'measured') && ...
    isequal(sp.recordings(3).frame_offset, [0 0]) && strcmp(sp.recordings(3).offset_source, 'same frame'), ...
    strjoin(w.Table.Data(:, 6)', ' | '));
w.close_window();

%% F: the measurement on still pixels, and the load dialog's question
om_hw = [40 200];
sensor2 = imgaussfilt(rand(120, 260), 2) * 1000;
om_st = zeros(40, 200, 12, 'single');
rec_st = zeros(100, 240, 12, 'single');
for f = 1:12
    s = sensor2;
    s(30 + (1:20), 10 * f + (1:30)) = 4000;            % the heart moves across the rig
    rec_st(:, :, f) = s(11:110, 11:250);
    s2 = sensor2;
    s2(40 + (1:15), 100 + (1:25)) = 3000 + 50 * f;      % the OM heart stays, its brightness changes
    om_st(:, :, f) = s2(41:80, 31:230);
end
est = rabbit_fov_position.measure(om_st, rec_st);
check('F1', est.trusted && isequal([est.off est.cols_off], [30 20]) && isequal(est.halves, [30 20; 30 20]), ...
    sprintf('%s, halves %s, score %.3f', mat2str([est.off est.cols_off]), mat2str(est.halves), est.ncc));
fig = uifigure('Visible', 'off');
figc = onCleanup(@() delete(fig));
r1 = rabbit_fov_position.ask_om_position(fig, 'reconstruction', om_hw, [100 240], est);   % default: use it
bad = est; bad.trusted = false; bad.why = 'test';
headless_push('inputdlg', {'30', 'x'});
headless_push('inputdlg', {'30', '20'});
r2 = rabbit_fov_position.ask_om_position(fig, 'calibration', om_hw, [100 240], bad);      % default: Enter the shift
r3 = rabbit_fov_position.ask_om_position(fig, 'calibration', om_hw, om_hw, bad);          % default: They line up
headless_push('uiconfirm', 'Enter the shift...');
headless_push('inputdlg', {});
headless_push('uiconfirm', 'Cancel');
r4 = rabbit_fov_position.ask_om_position(fig, 'calibration', om_hw, [100 240], bad);
check('F2', r1.ok && strcmp(r1.mapping.position_source, 'measured') && r1.mapping.om_window_in_rec.off == 30 && ...
    r2.ok && strcmp(r2.mapping.position_source, 'typed') && isequal([r2.mapping.om_window_in_rec.off r2.mapping.om_window_in_rec.cols_off], [30 20]) && ...
    r3.ok && isempty(r3.mapping) && ~r4.ok, 'measured, typed after a mistake, same position, cancelled after a cancelled typing');
% F5: a recording of another loaded recording's size reuses its alignment (default when not sure)
alt = struct('label', 'Same area as the reconstruction recording', 'mapping', rabbit_stack_io.offset_mapping(30, 20, 'rec'), ...
    'note', 'It has the size of the reconstruction recording.');
r5 = rabbit_fov_position.ask_om_position(fig, 'calibration', om_hw, [100 240], bad, alt);
check('F5', r5.ok && isequal([r5.mapping.om_window_in_rec.off r5.mapping.om_window_in_rec.cols_off], [30 20]), ...
    'not sure of its own match: the reconstruction recording''s alignment is offered first and taken');
j = jsondecode(jsonencode(r2.mapping));
v = rabbit_stack_io.validate_fov_mapping(j);
check('F3', strcmp(v.position_source, 'typed') && isfield(v, 'match_score'), 'how the position was found is kept');
% F4: the cut folder reuse compares the frame position
cf = fullfile(root, 'cf');
mkdir(cf);
fid = fopen(fullfile(cf, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(struct('fov_mapping', rabbit_stack_io.offset_mapping(10, 0, 'x'))), 'char');
fclose(fid);
check('F4', rabbit_cut_tiffs.same_position(cf, rabbit_stack_io.offset_mapping(10, 0, 'y')) && ...
    ~rabbit_cut_tiffs.same_position(cf, rabbit_stack_io.offset_mapping(12, 0, 'y')) && ...
    ~rabbit_cut_tiffs.same_position(cf, []), 'a folder cut at another position is not reused');

fprintf('RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_fov_alignment %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_fov_alignment %d/%d\n', pass, fail);
    error('probe_fov_alignment: %d check(s) failed', fail);
end
end
