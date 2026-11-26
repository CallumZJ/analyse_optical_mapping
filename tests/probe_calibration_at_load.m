function probe_calibration_at_load()
%PROBE_CALIBRATION_AT_LOAD Calibration after the cut; the pixel size of each view on the Conduction Velocity tab
% Collin Snitchler
% 24.11.2026
% Purpose: a calibration recording loaded with the data can be calibrated
%          right after the cut (rabbit_calibration_scale), and its pixel
%          size of each view (View1-View4) fills the Conduction Velocity
%          tab, where the CV map measures each view with its own size
%          (rabbit_cv_map). Needs no pyCamSet: the calibration folder the
%          window would leave is made here from a known rig, and the
%          window's end is played through the Reconstruction tab's own
%          reconstruction_calibration_window_done.
%
%   B  Scale from calibration...: off without a recording or without four views
%   L  one field for single-view data, four for the rabbit regions; switching
%      between them clears the sizes and says so, never carries them over
%   O  the question after the cut: none without a calibration recording;
%      "cannot yet" without cut images; Later opens nothing
%   E  the edge is never filled in for the user: the window lists the
%      calibration recording with an empty edge, and Run refuses it
%   D  a calibration made from the early window counts as run in the
%      Reconstruction tab: chosen there, kept in tab-state.json, History names the verdict
%   F  the sizes: asked with the typed edge, No leaves them, Yes fills one per
%      view with its source; WARNED says so; FAILED fills nothing; one
%      "All four from calibration" label, the unit names the binning, and the
%      tab's controls do not overlap; the
%      selected run's heart surface against the cube, only from a record of
%      the same calibration
%   P  the CV map: each view with its own size; single-view data with one
%      size; the mean + 3 SD cut only with Remove local outliers on
%   I  Input Scale: four fields, filled with the values now; only the edited one changes
%   M  Measure length: only the view the line is in; a line across two views is refused
%   K  later: binning and its Undo, another calibration recording
%   R  a second cut with a calibration chosen already: used without a new run
%   T  no "tile" in what the user reads
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_calibration_at_load"

assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');   % the app must stay hidden
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));

pass = 0; fail = 0;
    function check(id, ok, detail)
        fprintf('%s: %s -> %s\n', id, detail, char(70 + 14 * logical(ok)));
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end

root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
setappdata(groot, 'om_headless_dialogs', []);
setappdata(groot, 'om_headless_queue', struct());
T = rabbit_calibration_scale.TAG;
tile_word = '(?i)\<tiles?\>';
user_text = {};     % everything the user reads here, checked for "tile" at the end (T1)

%% the app, with no recording
a = analyse_optical_mapping();
app_cleanup = onCleanup(@() delete(a));
rabbit_calibration_scale.show(a);
g = a.GridLayout22;
btn = findall(g, 'Tag', [T 'Button']);
lbl = findall(g, 'Tag', [T 'Line']);
check('B1', isscalar(btn) && strcmp(char(btn.Enable), 'off') && contains(lbl.Text, 'not set'), ...
    'no recording: the button is off and the size is said to be not set');

%% single-view data
dsroot = fullfile(root, 'ds');
mkdir(dsroot);
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(dsroot, 'om');
assert(ok, err);
a.bind_reconstruction_tab_for_test(tab);
H = 40; Wr = 30;
a.data.rabbit_panoramic = 0;
a.data.regions = 1;
a.data.region_bounds = [1 1 H 4 * Wr H 4 * Wr];
a.processed_data.height = H;
a.processed_data.width = 4 * Wr;
a.processed_data.region_widths = 4 * Wr;
a.processed_data.binning = 1;
a.processed_data.scale = 1;
rabbit_calibration_scale.regions_changed(a);
rabbit_calibration_scale.show(a);
headless_push('inputdlg', {'125'});
feval(a.InputScaleButton.ButtonPushedFcn, a.InputScaleButton, []);
[S1, V1, why1] = rabbit_calibration_scale.pixel_map(a);
act1 = 0.5 * repmat(1:4 * Wr, H, 1);    % 0.5 ms per pixel along the columns
cv1 = rabbit_cv_map.bayly(act1, S1, V1, 0.5, 6);
check('L1', strcmp(char(field(g, T, 'View', 1).Visible), 'on') && strcmp(char(field(g, T, 'View', 2).Visible), 'off') && ...
    a.processed_data.scale == 125 && isempty(why1) && all(S1(:) == 125) && all(V1(:) == 1) && ...
    abs(median(cv1(:, :, 3), 'all', 'omitnan') - 2 * 125 / 1000) < 1e-9 && strcmp(char(btn.Enable), 'off'), ...
    'single-view data: one field, one size for the whole map in the CV map, no calibration button');
user_text = [user_text, {lbl.Text}, reshape(cellstr(field(g, T, 'View', 1).Tooltip), 1, [])];

%% the rabbit regions: the single value is not carried over
b_cols = [624; 1125; 1; 1652];          % canvas regions 1-4 are View2, View3, View1, View4
a.data.rabbit_panoramic = 1;
a.data.regions = 4;
a.data.region_bounds = [ones(4, 1), b_cols, H * ones(4, 1), b_cols + Wr - 1, H * ones(4, 1), Wr * ones(4, 1)];
a.processed_data.region_widths = Wr * ones(4, 1);
go = rabbit_calibration_scale.regions_changed(a);
d = last_dialog('Pixel size cleared');
[v, src] = rabbit_calibration_scale.views(a);
check('L2', ~go && ~isempty(d) && contains(d.message, 'cleared') && all(v == 1) && all(strcmp(src, 'not set')) && ...
    all(arrayfun(@(k) strcmp(char(field(g, T, 'View', k).Visible), 'on'), 1:4)), ...
    'rabbit regions: four fields; the single 125 was cleared and the user told, not spread over the views');

%% the question after the cut
n0 = n_dialogs('Rig calibration');
rabbit_calibration_scale.offer_after_cut(a);
check('O1', n_dialogs('Rig calibration') == n0, 'no calibration recording: nothing is asked');
cube = fullfile(root, 'cube.tif');
imwrite(zeros(20, 60, 'uint16'), cube);
a.data.calibration_source = cube;
a.data.calibration_loaded = true;
rabbit_calibration_scale.offer_after_cut(a);
d = last_dialog('Rig calibration');
check('O2', ~isempty(d) && strcmp(d.kind, 'uialert') && contains(d.message, 'cannot be calibrated yet') && ...
    isempty(a.recon.reconstruction_calibration_window), 'no cut images: said, and no window');
cut_dir = fullfile(root, 'cut_tiffs_reconstruction_rec');
mkdir(cut_dir);
roi = fullfile(root, 'regions_om.json');
write_text(roi, '{}');
a.recon.ReconstructionImagesField.Value = cut_dir;
a.recon.ReconstructionRoiField.Value = roi;
rabbit_calibration_scale.offer_after_cut(a);
d = last_dialog('Rig calibration');
check('O3', strcmp(d.kind, 'uiconfirm') && strcmp(d.answer, 'Later') && contains(d.message, 'not run again') && ...
    isempty(a.recon.reconstruction_calibration_window), 'the question; Later (the default) opens nothing');
user_text{end + 1} = d.message;

%% the empty-edge rule in the window the early path opens
b4 = [1 1 20 15; 1 16 20 30; 1 31 20 45; 1 46 20 60];
w = rabbit_calibration_dialog(tab, b4, 8000, @() [], [], [20 60], '', roi, [], {cube});
dt = w.Table.Data;
sp = w.make_spec();
[s_ok, s_err] = rabbit_calibration.check_spec(sp);
check('E1', size(dt, 1) == 1 && strcmp(dt{1, 2}, 'fit') && isempty(dt{1, 5}) && isnan(sp.recordings(1).edge_mm) && ...
    ~s_ok && contains(s_err, 'no default') && strcmp(char(w.Figure.Visible), 'off'), ...
    'the cube recording is listed with an empty edge, and Run refuses it');

%% the window's end: a PASSED calibration with the 30 mm run's sizes at the cube
f = 8000;
mm = [0.1254 0.1298 0.1291 0.1306];      % View1..View4, mm per pixel at the cube
cal_ok = make_calibration(tab.calibration_root(), 'cal_cube', f, mm * f, 'PASSED', true, cube, 30);
a.recon.reconstruction_calibration_window = w;
w.LastOk = true;
w.LastDir = cal_ok;
headless_push('uiconfirm', 'No, leave them');
a.recon.reconstruction_calibration_window_done(@(x) rabbit_calibration_scale.after_window(a, x));
dd = a.recon.ReconstructionCalibrationDropDown;
st = jsondecode(fileread(fullfile(dsroot, 'om.matom', 'reconstruction', 'tab-state.json')));
check('D1', strcmp(dd.Value, 'cal_cube') && isfield(st, 'sfm') && strcmp(st.sfm.calibration, 'cal_cube') && ...
    contains(a.history_field.Value{end}, 'PASSED') && contains(a.recon.Step2StatusChip.Text, 'cal_cube'), ...
    'the early calibration is chosen in the Reconstruction tab and kept in its tab state');
d = last_dialog(rabbit_calibration_scale.TITLE);
v = rabbit_calibration_scale.views(a);
check('F1', ~isempty(d) && contains(d.message, '30 mm') && contains(d.message, 'not at the heart surface') && ...
    contains(d.message, 'View4 130.6') && all(v == 1), 'the edge and the four sizes are shown first; No leaves them');
user_text{end + 1} = d.message;

headless_push('uiconfirm', 'Yes, the edge is 30 mm');
ok = rabbit_calibration_scale.fill(a, cal_ok);
[v, src] = rabbit_calibration_scale.views(a);
want = 1000 * mm;
check('F2', ok && max(abs(v - want)) < 1e-9 && all(strcmp(src, 'calibration cal_cube')) && ...
    max(abs(arrayfun(@(k) field(g, T, 'View', k).Value, 1:4) - want)) < 1e-9 && ...
    strcmp(field(g, T, 'Source', 2).Text, 'calibration cal_cube') && contains(lbl.Text, 'edge 30 mm (as typed)') && ...
    contains(lbl.Text, 'not the') && contains(a.history_field.Value{end}, 'View1 125.4'), ...
    sprintf('%s | %s', mat2str(v, 5), lbl.Text));
user_text = [user_text, {lbl.Text}, reshape(cellstr(lbl.Tooltip), 1, []), a.history_field.Value(end)];
% one source label with the full id and
% verdict instead of four truncated copies; the unit names the binning; the
% Conduction Velocity tab's controls do not overlap (with the slowest-speed
% line beside Time max, rabbit_cv_map.controls)
all4 = findall(g, 'Tag', [T 'SourceAll']);
unit = findall(g, 'Tag', [T 'Unit']);
rabbit_cv_map.controls(a);
fig = a.opticalmappingUIFigure;                  % laid out at 1536 x 864, the tab
fig.Position(3:4) = [1536 864];                  % in the lower third
a.TabGroup.Visible = 'on';
a.TabGroup.SelectedTab = a.ConductionVelocityTab;
a.TabGroup.Position = [1 1 1534 288];
drawnow; pause(1);
exportapp(fig, fullfile(root, 'cv_tab.png'));    % lays the hidden window out, as it is drawn
ovl = ui_control_overlaps(a.GridLayout22);
check('F5', isscalar(all4) && strcmp(char(all4.Visible), 'on') && ...
    strcmp(all4.Text, 'All four from calibration cal_cube (PASSED)') && ...
    all(arrayfun(@(k) strcmp(char(field(g, T, 'Source', k).Visible), 'off'), 1:4)) && ...
    strcmp(unit.Text, sprintf('%s per binned pixel (binning 1)', rabbit_calibration_scale.um())) &&~contains(lbl.Text, 'cal_cube') && ...
    isempty(ovl), sprintf('"%s" | "%s" | "%s" | %d overlap(s)%s', all4.Text, unit.Text, lbl.Text, numel(ovl), ...
    strjoin(arrayfun(@(o) sprintf(' [%s / %s]', o.a, o.b), ovl, 'UniformOutput', false), '')));
user_text = [user_text, {all4.Text, unit.Text}];

%% the heart surface of the run selected in the
% Reconstruction tab against the cube, from its pixel_size.json of the same
% calibration (views listed out of order, as a run writes them, matched by
% tile); none without a run, nor for another calibration's record
rid = '20261125T090000_f17f17f1';
run_metric = fullfile(dsroot, 'om.matom', 'reconstruction', 'runs', rid, 'outputs', 'metric');
mkdir(run_metric);
heart = mm .* (1 + [-0.010 -0.006 -0.005 -0.002]);   % View1..View4: 1.0, 0.6, 0.5, 0.2 % smaller
order = [2 3 1 4];
pv = struct('view', arrayfun(@(k) sprintf('view%d', k), order, 'UniformOutput', false), ...
    'tile', arrayfun(@(k) sprintf('tile%d', k), order, 'UniformOutput', false), ...
    'median_mm_per_px', num2cell(heart(order)));
write_text(fullfile(run_metric, 'pixel_size.json'), jsonencode(struct('schema', rabbit_calibration.PIXEL_SCHEMA, ...
    'units', 'mm', 'calibration_id', 'cal_cube', 'views', pv, 'om_pixel_same_size', true)));
rabbit_calibration_scale.show(a);
check('F6a', contains(lbl.Text, 'At the cube''s depth, not the heart surface.') && ~contains(lbl.Text, 'smaller'), ...
    sprintf('no run selected: "%s"', lbl.Text));
% the run is one of the tab's (tab-state.json), as a selectable run must be
st_file = fullfile(dsroot, 'om.matom', 'reconstruction', 'tab-state.json');
st6 = jsondecode(fileread(st_file));
st6.runs = struct('id', rid, 'status', 'COMPLETED', 'created_at', '2026-11-25T09:00:00');
write_text(st_file, jsonencode(st6, 'PrettyPrint', true));
[ok6, err6] = tab.load_state(dsroot, 'om');
assert(ok6, err6);
write_text(fullfile(dsroot, 'om.matom', 'reconstruction', 'runs', rid, 'manifest.json'), jsonencode(struct('run_id', rid)));
a.recon.ReconstructionDatasetField.Value = fullfile(dsroot, 'om.matom');
a.recon.ReconstructionRunList.Items = {[rid ' [succeeded]']};
a.recon.ReconstructionRunList.Value = [rid ' [succeeded]'];
rabbit_calibration_scale.show(a);
tip6 = strjoin(cellstr(lbl.Tooltip), ' ');
want6 = sprintf('At the cube''s depth; on this run''s heart surface about 0.2%s1.0 %% smaller.', char(8211));
check('F6b', strcmp(lbl.Text, ['Cube edge 30 mm (as typed). ' want6]) && contains(tip6, rid) && ...
    contains(tip6, strrep('View1 -1.0 %, View2 -0.6 %, View3 -0.5 %, View4 -0.2 %', '-', char(8722))), ...   % U+2212
    sprintf('"%s" | %s', lbl.Text, tip6));
user_text = [user_text, {lbl.Text, tip6}];
% with that run selected, Scale from calibration...
% also offers "Use the heart-surface sizes of run <id>"; the default stays
% "No, leave them" and the cube's depth stays "Yes, the edge is 30 mm";
% the option fills the heart sizes, names the run in the sources, the label,
% History and the CV map's History line
heart_opt = sprintf('Use the heart-surface sizes of run %s', rid);
ok6d0 = rabbit_calibration_scale.fill(a, cal_ok);       % no answer queued: the default
d6 = last_dialog(rabbit_calibration_scale.TITLE);
v6d0 = rabbit_calibration_scale.views(a);
headless_push('uiconfirm', heart_opt);
ok6d = rabbit_calibration_scale.fill(a, cal_ok);
[v6, src6] = rabbit_calibration_scale.views(a);
src_want = sprintf('calibration cal_cube, heart surface of run %s', rid);
hist6 = a.history_field.Value{end};
lbl6 = lbl.Text;
all6 = all4.Text;
check('F6d', ~ok6d0 && max(abs(v6d0 - want)) < 1e-9 && strcmp(d6.answer, 'No, leave them') && contains(d6.message, rid) && ...
    contains(d6.message, ['"' heart_opt '"']) && ok6d && max(abs(v6 - 1000 * heart)) < 1e-9 && all(strcmp(src6, src_want)) && ...
    contains(lbl6, sprintf('On the heart surface of run %s.', rid)) && ~contains(lbl6, 'cube''s depth') && ...
    strcmp(all6, sprintf('All four from calibration cal_cube (PASSED), heart surface of run %s', rid)) && ...
    contains(hist6, sprintf('on the heart surface of run %s', rid)) && contains(hist6, 'View1 124.1') && ...
    contains(rabbit_calibration_scale.history_scale(a), src_want) && ...
    startsWith(rabbit_calibration_scale.history_scale(a), sprintf('Pixel size (%sm/pixel, %s): View1 ', char(956), src_want)), ...   % one source named once
    sprintf('%s | "%s" | "%s" | %s', mat2str(v6, 5), lbl6, all6, hist6));
user_text = [user_text, {d6.message, lbl6, all6, hist6}];
headless_push('uiconfirm', 'Yes, the edge is 30 mm');  % the cube's sizes again for the rest
assert(rabbit_calibration_scale.fill(a, cal_ok), 'the cube sizes could not be set again');
write_text(fullfile(run_metric, 'pixel_size.json'), jsonencode(struct('schema', rabbit_calibration.PIXEL_SCHEMA, ...
    'units', 'mm', 'calibration_id', 'cal_other', 'views', pv, 'om_pixel_same_size', true)));
rabbit_calibration_scale.show(a);
check('F6c', contains(lbl.Text, 'At the cube''s depth, not the heart surface.') && ~contains(lbl.Text, 'smaller') && ...
    ~contains(strjoin(cellstr(lbl.Tooltip), ' '), rid), sprintf('another calibration''s record: "%s"', lbl.Text));
a.recon.ReconstructionRunList.Items = {};               % no run selected for the rest

%% the CV map, each view with its own size
[S, V, why] = rabbit_calibration_scale.pixel_map(a);
col_view = V(1, :);
act = 0.5 * repmat(mod(0:4 * Wr - 1, Wr) + 1, H, 1);   % a plane wave in each view, 0.5 ms per pixel
cv = rabbit_cv_map.bayly(act, S, V, 0.5, 6);
got = zeros(1, 4); expect = zeros(1, 4);
for k = 1:4
    c = (k - 1) * Wr + (1:Wr);
    view_k = col_view(c(1));
    got(k) = median(cv(:, c, 3), 'all', 'omitnan');
    expect(k) = 2 * want(view_k) / 1000;                % 2 pixels/ms
end
check('P1', isempty(why) && isequal(col_view(1:Wr:end), [2 3 1 4]) && max(abs(got - expect)) < 1e-9, ...
    sprintf('per view %s m/s, expected %s', mat2str(got, 5), mat2str(expect, 5)));
cvn = rabbit_cv_map.nearest(act, S, V, 500);
seam = cvn(:, Wr:Wr + 1, 3);
check('P2', all(isnan(seam(:))) && abs(median(cvn(:, Wr + 2:2 * Wr - 1, 3), 'all', 'omitnan') - 2 * want(3) / 1000) < 1e-9, ...
    'nearest neighbour: no point across a seam; View3 with its own size');

%% the mean + 3 SD cut of Bayly follows Remove local outliers
act_x = 0.5 * repmat(1:4 * Wr, H, 1);                      % 2 pixels/ms everywhere
r0 = 20; c0 = 60; pr = r0 - 3:r0 + 3; pc = c0 - 3:c0 + 3;
act_x(pr, pc) = 0.5 * c0 + 0.005 * (repmat(pc, 7, 1) - c0);   % one 7 x 7 patch 100 times faster
S_x = 125 * ones(H, 4 * Wr); V_x = ones(H, 4 * Wr);
cv_off = rabbit_cv_map.bayly(act_x, S_x, V_x, 0.5, 6, false);
cv_on = rabbit_cv_map.bayly(act_x, S_x, V_x, 0.5, 6, true);
cv_def = rabbit_cv_map.bayly(act_x, S_x, V_x, 0.5, 6);
check('P3', abs(cv_off(r0, c0, 3) - 25) < 1e-6 && isnan(cv_on(r0, c0, 3)) && isequaln(cv_def, cv_off) && ...
    abs(median(cv_on(:, :, 3), 'all', 'omitnan') - 0.25) < 1e-9, ...
    sprintf('the extreme value: %.4g m/s with removal off, %.4g with it on (map median %.4g)', ...
    cv_off(r0, c0, 3), cv_on(r0, c0, 3), median(cv_on(:, :, 3), 'all', 'omitnan')));

%% Input Scale: four fields filled with the values now; only the edited one changes
before = rabbit_calibration_scale.views(a);
answer = arrayfun(@(x) num2str(x, 6), before, 'UniformOutput', false);
answer{3} = '140';
headless_push('inputdlg', answer);
feval(a.InputScaleButton.ButtonPushedFcn, a.InputScaleButton, []);
[v, src] = rabbit_calibration_scale.views(a);
check('I1', v(3) == 140 && isequal(v([1 2 4]), before([1 2 4])) && strcmp(src{3}, 'typed') && ...
    strcmp(src{1}, 'calibration cal_cube') && strcmp(field(g, T, 'Source', 3).Text, 'typed') && ...
    strcmp(char(field(g, T, 'Source', 3).Visible), 'on') && ...                   % mixed sources,
    strcmp(char(findall(g, 'Tag', [T 'SourceAll']).Visible), 'off') && ...        % the four labels again
    contains(lbl.Text, 'From calibration cal_cube') && ...
    contains(a.history_field.Value{end}, 'View3 140'), sprintf('%s | %s', mat2str(v, 5), strjoin(src, ', ')));

%% Measure length: only its own view; across two views refused
before = rabbit_calibration_scale.views(a);
which = rabbit_calibration_scale.measured(a, 200, [35; 50]);     % inside canvas region 2: View3
[v, src] = rabbit_calibration_scale.views(a);
check('M1', strcmp(which, 'View3') && v(3) == 200 && isequal(v([1 2 4]), before([1 2 4])) && strcmp(src{3}, 'measured'), ...
    mat2str(v, 5));
before = v;
which = rabbit_calibration_scale.measured(a, 300, [25; 40]);     % from View2 into View3
d = last_dialog('Measure length');
check('M2', isempty(which) && isequal(rabbit_calibration_scale.views(a), before) && contains(d.message, 'crosses'), d.message);
user_text{end + 1} = d.message;

%% later: binning, another calibration recording
before = rabbit_calibration_scale.views(a);
a.processed_data.binning = 2;
rabbit_calibration_scale.binning_changed(a);
check('K1', max(abs(rabbit_calibration_scale.views(a) - 2 * before)) < 1e-9 && contains(a.history_field.Value{end}, 'binning 2') && ...
    strcmp(findall(g, 'Tag', [T 'Unit']).Text, sprintf('%s per binned pixel (binning 2)', rabbit_calibration_scale.um())), ...
    'binning 2: every view doubles; the unit says binning 2');
a.processed_data.binning = 1;
rabbit_calibration_scale.binning_changed(a);
check('K2', max(abs(rabbit_calibration_scale.views(a) - before)) < 1e-9, 'Undo of the binning: back');
other = fullfile(root, 'cube2.tif');
imwrite(zeros(20, 60, 'uint16'), other);
a.data.calibration_source = other;
go = rabbit_calibration_scale.before_cv_map(a);    % default: Cancel
d = last_dialog(rabbit_calibration_scale.TITLE);
check('K3', ~go && contains(d.message, 'cube2.tif') && contains(d.message, 'View1'), ...
    'another calibration recording: asked before the CV map, Cancel stops it');
a.data.calibration_source = cube;

%% WARNED, FAILED
cal_w = make_calibration(tab.calibration_root(), 'cal_cube_01', f, mm * f, 'WARNED', true, cube, 30);
headless_push('uiconfirm', 'Yes, the edge is 30 mm');
rabbit_calibration_scale.fill(a, cal_w);
d = dialog_titled(rabbit_calibration_scale.TITLE, 'uiconfirm');
% the verdict is in the one source label now
all4 = findall(g, 'Tag', [T 'SourceAll']);
check('F3', contains(d.message, 'WARNED') && strcmp(all4.Text, 'All four from calibration cal_cube_01 (WARNED)'), ...
    all4.Text);
before = rabbit_calibration_scale.views(a);
cal_f = make_calibration(tab.calibration_root(), 'cal_cube_02', f, mm * f, 'FAILED', false, cube, 30);
ok = rabbit_calibration_scale.fill(a, cal_f);
d = last_dialog(rabbit_calibration_scale.TITLE);
check('F4', ~ok && isequal(rabbit_calibration_scale.views(a), before) && strcmp(d.kind, 'uialert') && ...
    contains(d.message, 'did not pass'), d.message);

%% a second cut, with a calibration chosen already: no new run
a.recon.reconstruction_refresh_calibrations();
dd.Value = 'cal_cube';
a.recon.reconstruction_calibration_window = [];
headless_push('uiconfirm', 'Use cal_cube');
headless_push('uiconfirm', 'Yes, the edge is 30 mm');
rabbit_calibration_scale.offer_after_cut(a);
check('R1', max(abs(rabbit_calibration_scale.views(a) - want)) < 1e-9 && isempty(a.recon.reconstruction_calibration_window), ...
    'the chosen calibration fills the sizes; no window is opened');

%% back to single-view data: the four sizes are not folded into one
a.data.rabbit_panoramic = 0;
a.data.regions = 1;
a.data.region_bounds = [1 1 H 4 * Wr H 4 * Wr];
a.processed_data.region_widths = 4 * Wr;
go = rabbit_calibration_scale.regions_changed(a);
d = last_dialog('Pixel size cleared');
check('L3', ~go && contains(d.message, 'one value for the whole map') && a.processed_data.scale == 1 && ...
    ~isfield(a.processed_data, 'scale_views') && strcmp(char(field(g, T, 'View', 2).Visible), 'off'), ...
    'four views to single view: cleared and told');
user_text{end + 1} = d.message;

%% no "tile" in what the user reads
[~, c] = make_result(f, mm * f, 30);
c.cameras(2).rmse_px = 3;                                   % a view that fails
vd = rabbit_calibration.verdict(c);
lines = rabbit_calibration.summary_lines(c, vd);
user_text = [user_text, lines(:)', {rabbit_calibration.view_words('the camera set was made on other tiles; tile2')}];
dl = getappdata(groot, 'om_headless_dialogs');
user_text = [user_text, {dl.message}, a.history_field.Value(:)'];
hits = user_text(~cellfun(@isempty, regexp(user_text, tile_word, 'once')));
check('T1', isempty(hits) && any(contains(lines, 'View2: 3.00 px')), strjoin(hits, ' | '));

w.close_window();
fprintf('PROBE_CALIBRATION_AT_LOAD RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    fprintf('PROBE_FAIL probe_calibration_at_load\n');
    error('probe_calibration_at_load:Failed', '%d check(s) failed.', fail);
end
fprintf('PROBE_OK probe_calibration_at_load %d/0\n', pass);
end

function h = field(g, T, kind, k)
h = findall(g, 'Tag', sprintf('%s%s%d', T, kind, k));
end

function n = n_dialogs(title)
dl = getappdata(groot, 'om_headless_dialogs');
n = 0;
if ~isempty(dl), n = nnz(strcmp({dl.title}, title)); end
end

function d = last_dialog(title)
d = [];
dl = getappdata(groot, 'om_headless_dialogs');
if isempty(dl), return; end
k = find(strcmp({dl.title}, title), 1, 'last');
if ~isempty(k), d = dl(k); end
end

function d = dialog_titled(title, kind)
d = struct('message', '');
dl = getappdata(groot, 'om_headless_dialogs');
if isempty(dl), return; end
k = find(strcmp({dl.title}, title) & strcmp({dl.kind}, kind), 1, 'last');
if ~isempty(k), d = dl(k); end
end

function [cams, res] = make_result(f, depths, edge)
% calibration.json (rabbit_calibration.result.v1) of a known rig: View k at depths(k)
cams = struct('tile', {}, 'focal_px', {}, 'k1', {}, 'pp_tile_px', {}, 'R_world_to_cam', {}, ...
    't_world_to_cam_mm', {}, 'centre_mm', {}, 'axis_world', {}, 'det_R', {}, 'points', {}, 'images', {}, ...
    'rmse_px', {}, 'depth_at_target_mm', {}, 'mm_per_px_at_target', {});
for k = 1:4
    c = cosd(90 * (k - 1)); s = sind(90 * (k - 1));
    R = [c 0 s; 0 1 0; -s 0 c];
    t = [0; 0; depths(k)];
    cams(k) = struct('tile', sprintf('tile%d', k), 'focal_px', f, 'k1', 0, 'pp_tile_px', [200; 200], ...
        'R_world_to_cam', R, 't_world_to_cam_mm', t, 'centre_mm', -R' * t, 'axis_world', R(3, :)', 'det_R', 1, ...
        'points', 2500, 'images', 80, 'rmse_px', 0.9, 'depth_at_target_mm', depths(k), ...
        'mm_per_px_at_target', depths(k) / f);
end
res = struct('schema', rabbit_calibration.RESULT_SCHEMA, 'lens', struct('focal_px', f, 'k1', 0), ...
    'target', struct('type', 'PuzzleBoardCube', 'n_points', 7, 'edge_mm', edge), 'cameras', cams, 'rig', struct(), ...
    'residual', struct('rmse_px', 0.9, 'median_px', 0.7, 'p95_px', 1.8), ...
    'observations', struct('detected', 13000, 'used', 12000, 'kept_fraction', 0.92), ...
    'holdout', struct('name', 'other cube', 'frames_used', 40, 'scale_error_percent', 0.1, ...
    'scale_se_percent', 0.1, 'residual_mm_median', 0.1));
end

function cal_dir = make_calibration(cal_root, id, f, depths, status, metric, recording, edge)
% A calibration folder as run_calibration leaves it: spec.json, calibration.json and verdict.json
cal_dir = fullfile(cal_root, id);
mkdir(cal_dir);
[~, res] = make_result(f, depths, edge);
write_text(fullfile(cal_dir, 'calibration.json'), jsonencode(res));
write_text(fullfile(cal_dir, 'verdict.json'), jsonencode(struct('schema', rabbit_calibration.VERDICT_SCHEMA, ...
    'status', status, 'metric_allowed', metric, 'failures', {{}}, 'warnings', {{}}, 'size_note', '')));
spec = rabbit_calibration.default_spec();
spec.recordings = struct('path', recording, 'role', 'fit', 'type', 'PuzzleBoardCube', 'n_points', 7, ...
    'edge_mm', edge, 'size_source', '');
write_text(fullfile(cal_dir, 'spec.json'), jsonencode(spec));
end

function write_text(path, txt)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Could not write %s.', path);
fprintf(fid, '%s', txt);
fclose(fid);
end
