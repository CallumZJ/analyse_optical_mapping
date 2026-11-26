function probe_projection_records
%% Probe: the per-view records of a projection and their texts
% Collin Snitchler
% 25.11.2026
% The Results box prints them (probe_results_box R30). Without a projection run (the functions themselves, and
% write_manifest on a small result):
%   V1  R9: without ViewCameras, ROI row k takes the image named _view<k>
%       (positional, as the frame check reads the names), not the view
%       VIEW_ORDER{k}; view_camera_per_roi_row records it
%   C1  the surface speed record names the steep faces left out
%       (correction above 1.5x) and the unbinned pixel; the CV manifest has
%       surface_speed.steep_faces_left_out, correction_cap, basis
%   D1  a view whose directly seen faces spread 3x its 2-D IQR warns,
%       with the WARN text; activation_consistency has views, iqr_3d_direct_ms,
%       iqr_2d_ms, ratio, warn, basis, View1 to View4; and
%       iqr_2d_smoothed_ms, the 2-D IQR after the CV step's 3x3 median
%   F1  mesh_outside_om (views, fraction, warn, basis) and its text
%       'mesh outside the OM outline V1 7 % · ...'; an outline match within
%       0.01 of a limit is printed to 3 decimals
%   G1  S8: view_geometry_suspect in the manifest, its WARN and
%       Next texts when two or more per-view checks fire for one view
%   F2  S3: frame_check.mesh_outside_om in ROI-row order (with
%       mesh_outside_om_order, roi_row_view), the manifest's top-level
%       mesh_outside_om View1 to View4; an older record read as before
%   E1  a pacing site from the Paced dialog (two fields), in the
%       Rhythm line and the record (pacing_site); the beats found by Average
%       beats (note_beats) against the stated cycle: detected_interval_ms,
%       cycle_mismatch_pct, cycle_mismatch_warn and the WARN line above 10 %
%   E3  S14: the Paced dialog's pacing site is a drop-down of
%       the sites (default not known), "Blank: not known." said once
%   E2  S1: cycle_check and rhythm_row_text in the record, also
%       when no interval is known; of_app keeps the beats of Average beats
%       when app.data was put back without them; a new recording clears them
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_projection_records"
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

%% V1 (R9)
names = {};
for f = [3 1]
    for k = [4 2 3 1]
        names{end + 1} = sprintf('cut_view%d_frame_%03d.png', k, f); %#ok<AGROW>
    end
end
imgs = struct('name', names, 'camera_id', num2cell(1:numel(names)));
[~, used] = rabbit_rhythm_reproject.resolve_view_cameras(imgs, []);
rec = rabbit_rhythm_reproject.camera_per_roi_row(used);
want = arrayfun(@(k) sprintf('cut_view%d_frame_001.png', k), 1:4, 'UniformOutput', false);
results(end + 1) = struct('id', 'V1 R9 ROI row k takes _view<k>', 'ok', isequal(used(:)', want) && ...
    isequal([rec.per_row.roi_view_in_name], 1:4) && startsWith(rec.convention, 'positional'), 'detail', strjoin(used, ', '));

%% C1
speed = [0.5; 0.6; 0.7; 0.8; NaN];
surface = [0.55; 0.66; NaN; 0.88; NaN];
r = rabbit_rhythm_reproject.surface_speed_record(speed, surface, [0.125 0.13 0.129 0.131], 2, 7);
m = manifest(root, struct('quantity', 'cv_speed', 'cv_direction', struct('surface_speed', r)));
ok_c = r.steep_faces_left_out == 7 && r.correction_cap == 1.5 && ...
    strcmp(r.steep_text, sprintf('surface speed left out on 7 steep faces (correction > 1.5%s)', char(215))) && ...
    strcmp(r.pixel_mm_is, 'mm per unbinned OM pixel (the CV map''s binned pixel / 2), the frame of the Jacobian') && ...
    isfield(m, 'surface_speed') && m.surface_speed.steep_faces_left_out == 7 && m.surface_speed.correction_cap == 1.5 && ...
    strcmp(m.surface_speed.basis, 'faces whose tilt correction (surface / image-plane speed) is above 1.5x') && ...
    abs(r.median_surface - 0.66) < 1e-12;
% a count of thousands is recorded with commas, as the app prints counts
r_k = rabbit_rhythm_reproject.surface_speed_record(speed, surface, [0.125 0.13 0.129 0.131], 2, 7508);
ok_c = ok_c && strcmp(r_k.steep_text, sprintf('surface speed left out on 7,508 steep faces (correction > 1.5%s)', char(215)));
results(end + 1) = struct('id', 'C1 steep faces and the unbinned pixel in the records', 'ok', ok_c, 'detail', r.steep_text);

%% D1
rng(5, 'twister');
views = {10 + 10 * rand(50), 10 + 10 * rand(50), 10 + 10 * rand(50), 10 + 10 * rand(50)};   % each 2-D IQR about 5 ms
n = 400;
viewi = zeros(n, 5);
viewi(:, end) = repmat((1:4)', n / 4, 1);                  % DIRECT faces, ROI rows 1-4 in turn
dataProj = 10 + 10 * rand(n, 1);
dataProj(viewi(:, end) == 4) = 10 + 30 * rand(n / 4, 1);   % ROI row 4 spreads 3x
ac = rabbit_rhythm_reproject.activation_consistency(views, dataProj, viewi, true(n, 1), [2 3 1 4]);
m = manifest(root, struct('activation_consistency', ac));
w4 = ac.warn(strcmp(ac.views, 'View4'));
ok_d = isequal(ac.views, {'View1', 'View2', 'View3', 'View4'}) && numel(ac.iqr_3d_direct_ms) == 4 && ...
    numel(ac.iqr_2d_ms) == 4 && numel(ac.ratio) == 4 && islogical(ac.warn) && isequal(ac.warn, [false false false true]) && ...
    w4 && isscalar(ac.warnings) && startsWith(ac.warnings{1}, 'WARN Activation  View4: directly seen faces spread ') && ...
    isfield(m, 'activation_consistency') && isequal(m.activation_consistency.warn(:)', [false false false true]);
% both 2-D IQRs, as projected
% and after the CV step's 3x3 median (which narrows a noisy map's IQR), named
% in the WARN text and recorded per view
i2s = ac.iqr_2d_smoothed_ms;
ok_d = ok_d && numel(i2s) == 4 && all(isfinite(i2s)) && all(i2s < ac.iqr_2d_ms) && ...
    contains(ac.warnings{1}, sprintf(['in its 2-D map as projected (unsmoothed; %d ms after the CV step''s 3%s3 median); ' ...
    'this view''s projection does not reproduce its map'], round(i2s(4)), char(215))) && ...
    numel(m.activation_consistency.iqr_2d_smoothed_ms) == 4 && ...
    max(abs(m.activation_consistency.iqr_2d_smoothed_ms(:)' - i2s)) < 1e-9 && ...
    abs(i2s(4) - diff(prctile(reshape(rabbit_cv_map.median3(views{4}, ones(50)), [], 1), [25 75]))) < 1e-9;
results(end + 1) = struct('id', 'D1 per-view consistency', 'ok', ok_d, 'detail', strjoin(ac.warnings, ' | '));

%% F1
fo = [0.07 0.12 0.13 0.26];
t = rabbit_rhythm_reproject.mesh_outside_text(fo);
% a view, its value and its %
% are joined by non-breaking spaces, so a wrapped row never parts "V4 26 %"
nb = char(160);
% the limit, and the causes without asserting pose or scale
want_t = sprintf(['mesh outside the OM outline V1%s7%s%% %s V2%s12%s%% %s V3%s13%s%% %s V4%s26%s%% (warn > 10 %%; ' ...
    'mesh larger than the OM outline: pose, scale or the OM tissue outline; not missing mesh)'], nb, nb, char(183), ...
    nb, nb, char(183), nb, nb, char(183), nb, nb);
m = manifest(root, struct('frame_check', struct('mesh_outside_om', fo)));
lst = rabbit_rhythm_reproject.outline_match_list([0.795 0.85 0.55 0.6], [0.8 0.6]);
ok_f = strcmp(t, want_t) && isempty(rabbit_rhythm_reproject.mesh_outside_text([0.05 0.1 0.02 0.09])) && ...
    isfield(m, 'mesh_outside_om') && isequal(m.mesh_outside_om.views(:)', {'View1', 'View2', 'View3', 'View4'}) && ...
    max(abs(m.mesh_outside_om.fraction(:)' - fo)) < 1e-12 && isequal(m.mesh_outside_om.warn(:)', [false true true true]) && ...
    strcmp(m.mesh_outside_om.basis, 'share of the projected mesh silhouette outside the OM tissue outline') && ...
    strcmp(lst, '0.795, 0.85, 0.55, 0.600');
results(end + 1) = struct('id', 'F1 mesh outside the OM outline', 'ok', ok_f, 'detail', [t ' | ' lst]);

%% F2: frame_check.mesh_outside_om in ROI-row order, the manifest's top level View1 to View4
% ROI rows 1-4 are View2, View3, View1, View4; a record made before S3
% (no mesh_outside_om_order) is already View1 to View4
fc = struct('mesh_outside_om', [0.12 0.13 0.07 0.26], 'mesh_outside_om_order', 'roi_row', 'roi_row_view', [2 3 1 4], ...
    'pose_iou', [0.9 0.8 0.85 0.7]);
m2 = manifest(root, struct('frame_check', fc));
old = rabbit_rhythm_reproject.mesh_outside_by_view(struct('mesh_outside_om', fo));
ok_f2 = max(abs(m2.mesh_outside_om.fraction(:)' - fo)) < 1e-12 && isequal(m2.mesh_outside_om.warn(:)', [false true true true]) && ...
    isequal(m2.mesh_outside_om.views(:)', {'View1', 'View2', 'View3', 'View4'}) && strcmp(m2.mesh_outside_om.text, want_t) && ...
    max(abs(old - fo)) < 1e-12;
results(end + 1) = struct('id', 'F2 S3 mesh_outside_om ROI order in frame_check, View order at the top', 'ok', ok_f2, ...
    'detail', mat2str(m2.mesh_outside_om.fraction(:)'));

%% G1: view_geometry_suspect, two or more per-view checks of one view
% ROI rows 1-4 are View2, View3, View1, View4; View4: camera-image match 0.71,
% mesh outside 26 %, faces spread 3.3x; View2: mesh outside 12 % only (one check)
ac_g = struct('views', {{'View1', 'View2', 'View3', 'View4'}}, 'ratio', [1.1 1.2 1.0 3.3], 'warn', [false false false true]);
fc_g = struct('mesh_outside_om', [0.12 0.13 0.07 0.26], 'mesh_outside_om_order', 'roi_row', 'roi_row_view', [2 3 1 4], ...
    'pose_iou', [0.81 0.78 0.88 0.71]);
mg = manifest(root, struct('frame_check', fc_g, 'activation_consistency', ac_g));
g = mg.view_geometry_suspect;
want_g = sprintf(['WARN View4  geometry suspect: camera-image match 0.71, mesh outside its outline 26 %%, directly ' ...
    'seen faces spread 3.3%s its 2-D map.'], char(215));
gw = cellstr(g.warnings); gn = cellstr(g.next);
ok_g = isequal(g.suspect(:)', [false false false true]) && isequal(g.n_flags(:)', [0 1 1 3]) && ...
    max(abs(g.camera_image_match(:)' - [0.88 0.81 0.78 0.71])) < 1e-12 && isscalar(gw) && strcmp(gw{1}, want_g) && ...
    strcmp(gn{1}, 'Next: treat View4''s 3-D values as unreliable; use its 2-D map.') && ...
    isequal(cellstr(g.suspect_views), {'View4'});
% no view with two: the record says so, no warning; without any check: no record
mg2 = manifest(root, struct('frame_check', struct('mesh_outside_om', [0.12 0.13 0.07 0.26])));
ok_g = ok_g && ~any(mg2.view_geometry_suspect.suspect) && isempty(mg2.view_geometry_suspect.warnings) && ...
    isempty(rabbit_rhythm_reproject.view_geometry_suspect(struct()));
results(end + 1) = struct('id', 'G1 S8 view_geometry_suspect', 'ok', ok_g, 'detail', [gw{1} ' ' gn{1}]);

%% E1, through the app's dialog
stack = 100 + rand(20, 20, 50); %#ok<NASGU>
recf = fullfile(root, 'synthetic_rhythm.mat');
save(recf, 'stack');
a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', recf);
headless_push('inputdlg', {'200'});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
headless_push('uiconfirm', 'Paced...');
headless_push('inputdlg', {'500', 'rv epicardium'});
rabbit_recording_rhythm.ask(a);
r1 = a.recording_rhythm();
line1 = rabbit_recording_rhythm.line_of(r1);
s1 = rabbit_recording_rhythm.record(r1);
rabbit_recording_rhythm.note_beats(a, (0:8) * 0.6);         % beats 600 ms apart: 20 % off the 500 ms cycle
r2 = a.recording_rhythm();
s2 = rabbit_recording_rhythm.record(r2);
w2 = rabbit_recording_rhythm.cycle_warning(r2);
hist = a.history_field.Value;
rabbit_recording_rhythm.note_beats(a, (0:8) * 0.549);       % 9.8 % off: no warning
s3 = rabbit_recording_rhythm.record(a.recording_rhythm());
bad_site = false;
try
    rabbit_recording_rhythm.make('paced', 500, 'ms', 'as stated', 'septum');
catch ME
    bad_site = strcmp(ME.identifier, 'analyse_om:Rhythm:BadSite');
end
ok_e = strcmp(r1.pacing_site, 'RV epicardium') && ...
    strcmp(line1, 'Rhythm: Paced, 500 ms cycle, pacing site RV epicardium (as stated)') && ...
    strcmp(s1.pacing_site, 'RV epicardium') && isempty(s1.detected_interval_ms) && isempty(s1.cycle_mismatch_pct) && ...
    isequal(s1.cycle_mismatch_warn, false) && abs(s2.detected_interval_ms - 600) < 1e-9 && ...
    abs(s2.cycle_mismatch_pct - 20) < 1e-9 && isequal(s2.cycle_mismatch_warn, true) && ...
    startsWith(w2, 'WARN Rhythm  stated cycle 500 ms, detected 600 ms (beat interval from Average beats, median of 8 intervals)') && ...
    any(strcmp(hist, w2)) && any(contains(rabbit_recording_rhythm.cv_lines(r2, []), 'WARN Rhythm')) && ...
    abs(s3.cycle_mismatch_pct - 9.8) < 1e-6 && isequal(s3.cycle_mismatch_warn, false) && bad_site && ...
    ~isfield(rabbit_recording_rhythm.record(rabbit_recording_rhythm.make('sinus')), 'pacing_site');
results(end + 1) = struct('id', 'E1 pacing site and the cycle check', 'ok', ok_e, 'detail', [line1 ' | ' w2]);

%% E2: the check in words in the record, and the beats kept when app.data loses them
% s1: paced with a cycle, no beats found yet; s2: 20 % off; s3: agrees
rowp = 'Paced, 500 ms cycle, pacing site RV epicardium (as stated';
ok_e2 = strcmp(s1.cycle_check, 'not run: Average beats not run on this recording in this session') && ...
    strcmp(s1.rhythm_row_text, [rowp '); beat interval not checked (Average beats not run on this recording in this session)']) && ...
    strcmp(s2.cycle_check, 'differs by more than 10 %') && ...
    strcmp(s2.rhythm_row_text, [rowp '; Average beats found 600 ms, 20 % different)']) && ...
    strcmp(s3.cycle_check, 'agrees') && strcmp(s3.rhythm_row_text, [rowp '; Average beats found 549 ms, agrees)']);
sn = rabbit_recording_rhythm.record(rabbit_recording_rhythm.make('sinus'));
ok_e2 = ok_e2 && strcmp(sn.cycle_check, 'not applicable: not paced') && strcmp(sn.rhythm_row_text, 'Sinus rhythm (as stated)');
% app.data put back without beat_interval (a checkpoint made before the pacing site was recorded), the
% beat times of Average beats still in the app: of_app takes their interval
a.data = rmfield(a.data, 'beat_interval');
a.activation_times = (0:6) * 0.5;
s4 = rabbit_recording_rhythm.record(rabbit_recording_rhythm.of_app(a));
s5 = rabbit_recording_rhythm.record(rabbit_recording_rhythm.of(a.data));
ok_e2 = ok_e2 && abs(s4.detected_interval_ms - 500) < 1e-9 && strcmp(s4.cycle_check, 'agrees') && ...
    s4.detected_beats == 7 && strcmp(s5.cycle_check, 'not run: Average beats not run on this recording in this session');
% a new recording: the last recording's beat times are not kept
headless_push('uigetfile', recf);
headless_push('inputdlg', {'200'});
headless_push('uiconfirm', 'Continue');
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
ok_e2 = ok_e2 && isempty(a.activation_times) && isempty(rabbit_recording_rhythm.of_app(a).detected);
results(end + 1) = struct('id', 'E2 S1 cycle_check and rhythm_row_text; of_app', 'ok', ok_e2, ...
    'detail', [s1.rhythm_row_text ' | ' s3.rhythm_row_text ' | ' s4.cycle_check]);

%% E3: the Paced dialog's site is a drop-down of the sites; "Blank: not known." once
[dlg, ctl] = rabbit_recording_rhythm.paced_dialog_figure('500', '', false);
words_e3 = {ctl.cycle_label.Text, ctl.site_label.Text};
n_blank = sum(cellfun(@(s) numel(strfind(s, 'Blank: not known.')), words_e3));
ok_e3 = isa(ctl.site, 'matlab.ui.control.DropDown') && isequal(ctl.site.Items, rabbit_recording_rhythm.PACING_SITES()) && ...
    isequal(ctl.site.Items, {'RV epicardium', 'LV epicardium', 'apex', 'base', 'atrium', 'other', 'not known'}) && ...
    strcmp(ctl.site.Value, 'not known') && strcmp(ctl.cycle.Value, '500') && n_blank == 1;
delete(dlg);
[dlg, ctl] = rabbit_recording_rhythm.paced_dialog_figure('', 'apex', false);
ok_e3 = ok_e3 && strcmp(ctl.site.Value, 'apex');
delete(dlg);
results(end + 1) = struct('id', 'E3 S14 Paced dialog: site drop-down, one "Blank: not known."', 'ok', ok_e3, ...
    'detail', strjoin(words_e3, ' | '));

%% Report
n_fail = 0;
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; n_fail = n_fail + 1; end
    fprintf('%s  %s  %s\n', tag, results(k).id, results(k).detail);
end
fprintf('%d of %d checks passed\n', numel(results) - n_fail, numel(results));
if n_fail > 0, error('probe_projection_records: %d failed', n_fail); end
fprintf('PROBE_OK probe_projection_records %d/0\n', numel(results));
end

function m = manifest(root, extra)
%% write_manifest on a small result with the given fields, read back
res = struct('view_names_used', {{'a_view1', 'a_view2', 'a_view3', 'a_view4'}}, 'rotation', 3, ...
    'stats', struct('colmapDir', 'c', 'meshFile', 'm.ply', 'nFaces', 10, 'nAssigned', 5, ...
    'nAssignedPerView', [1 1 1 2], 'nDirectOverlapEdge', [5 0 0], 'nViews', 4, 'nFrames', 0));
for f = fieldnames(extra)'
    res.(f{1}) = extra.(f{1});
end
p = fullfile(root, 'manifest.json');
rabbit_rhythm_reproject.write_manifest(p, res);
m = jsondecode(fileread(p));
end
