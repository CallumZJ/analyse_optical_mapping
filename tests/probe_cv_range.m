function probe_cv_range
%% Probe: the "CV range (m/s)" field of Visualise
% Collin Snitchler
% 23.11.2026
% The user wanted the colour range of the conduction velocity panel to be
% set like the activation map's: "auto" (1st to 99th percentile) or "lo hi",
% values outside drawn in the end colours. Colour only: no value is left
% out. Driven through the app's Reproject run button, headless, on a copy of
% a completed run, with a CV map as probe_cv_projection.
%   R1  the field starts on auto: the CV panel's CLim is the 1st to 99th
%       percentile of its values
%   R2  a typed range sets the CLim and the colours; values below and above
%       take the end colours; the activation panel does not change
%   R3  auto gives the 1st to 99th percentile again
%   R4  the caption names the range in use: "(typed)", then the 1st to
%       99th percentile again; the range itself is always drawn
%   R5  the activation panel's auto range is also the 1st to 99th
%       percentile of its drawn values, the caption says
%       "(auto)", and faces above it are drawn in the outside colour
%   R6  activation: limits recorded at projection (display_limits) come
%       before auto, typed limits before both
%   R7  the app's own automatic range ([0, max] after Generate map) counts
%       as auto: flagged at projection (activation_auto); in an older
%       record without the flag, [0, hi] with hi at or above the largest
%       projected value; a range cut below the values stays the app's
%   R8  the CV range by the same rule: the 2-D CV tab's
%       [0, 99th percentile] and the old [0, max] are the app's own, not
%       recorded (cv_auto); typed limits recorded; in Visualise a flagged
%       pair or an old [0, >= largest speed] gives the auto range
%   R9  the CV map's activation times are not
%       cut by default; the Upper Y limit cuts only when "Leave out
%       activation times above the display limit (<x> ms)" is ticked
%   R10 Remove local outliers blanks the outlier pixels only,
%       in all three layers, until a pass removes none, the window within
%       one view
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_cv_range" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_cv_range', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset, a map, frames and a CV map (as probe_cv_projection)
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
map = 20 + 30 * rand(size(om_image));
frames = repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, []);
rng(11, 'twister');
speed = 0.2 + 0.8 * rand(size(map));
speed(rand(size(map)) < 0.1) = NaN;
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(root, stem);
assert(ok, err);
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root, stem);
recording = rabbit_reconstruction_tab.recording_stem(root, stem);
app.file_info.path = root;
app.file_info.name = [recording '.fits'];
app.file_info.type = '.fits';
app.processed_data.activation_map = map;
app.processed_data.image_stack = {frames};
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.processed_data.CV_map = cat(3, speed * 0.6, speed * 0.8, speed);
app.CV_method.Value = app.CV_method.Items{1};
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();

[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
fc = findobj(fig, 'Tag', 'ReconstructionCvLimits');
ax_c = findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv');
ax_a = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
d = getappdata(fig, 'reconstruction_cv');
assert(isscalar(fc) && isscalar(ax_c) && isstruct(d) && isfield(d, 'handle'), 'No CV panel or CV range field.');
s = d.values(isfinite(d.values) & d.values > 0);
% the automatic CV range is the 1st-99th percentile of
% the face values (cv_projected.cdf) of the faces shown, not of the vertices
fd0 = tab.viewer_face_entry(fig, 'cv');
fv0 = double(fd0.values(:));
fv0 = fv0(tab.viewer_faces_shown(fig, fd0) & isfinite(fv0) & fv0 > 0);
want = prctile(fv0, [1 99]);

%% R1
results = add(results, 'R1 starts on auto: CLim = 1st-99th percentile', ...
    strcmp(fc.String, 'auto') && max(abs(ax_c.CLim - want)) < 1e-12, ...
    sprintf('"%s", CLim %s, percentiles %s', fc.String, mat2str(ax_c.CLim, 4), mat2str(want, 4)));

%% R2
act_before = ax_a.CLim;
act_col = findobj(ax_a, 'Type', 'patch').FaceVertexCData;
lim = [0.5 0.7];
fc.String = '0.5 0.7';
fc.Callback(fc, []);
col = d.handle.FaceVertexCData;
low = isfinite(d.values) & d.values < lim(1);
high = isfinite(d.values) & d.values > lim(2);
r2 = isequal(ax_c.CLim, lim) && isequal(col, tab.viewer_colours(d.values, lim, d.cmap, d.out)) && ...
    any(low) && any(high) && all(ismember(col(low, :), d.out(1, :), 'rows')) && ...
    all(ismember(col(high, :), d.out(2, :), 'rows')) && isequal(ax_a.CLim, act_before) && ...
    isequal(findobj(ax_a, 'Type', 'patch').FaceVertexCData, act_col);
results = add(results, 'R2 a typed range sets CLim and colours, own colours outside, activation unchanged', r2, ...
    sprintf('CLim %s, %d below and %d above', mat2str(ax_c.CLim), nnz(low), nnz(high)));
% The caption and the (i) tooltip (the range is drawn short; the tooltip has it in full)
drawn_typed = strjoin(cellstr(ax_c.Subtitle.String), ' ');
cap_typed = [strjoin(cellstr(ax_c.Subtitle.String), ' ') get(findobj(fig, 'Tag', 'ReconstructionPanelInfo_cv'), 'TooltipString')];
en = char(8211);   % the captions write ranges with an en dash

%% R3
fc.String = 'auto';
fc.Callback(fc, []);
results = add(results, 'R3 auto gives the 1st-99th percentile again', ...
    max(abs(ax_c.CLim - want)) < 1e-12 && isequal(d.handle.FaceVertexCData, tab.viewer_colours(d.values, want, d.cmap, d.out)), ...
    sprintf('CLim %s', mat2str(ax_c.CLim, 4)));
drawn_auto = strjoin(cellstr(ax_c.Subtitle.String), ' ');
ends = tab.viewer_range_ends(want);
cap_auto = [strjoin(cellstr(ax_c.Subtitle.String), ' ') get(findobj(fig, 'Tag', 'ReconstructionPanelInfo_cv'), 'TooltipString')];
results = add(results, 'R4 the caption names the range in use: typed, then 1st-99th percentile again', ...
    contains(cap_typed, ['0.5' en '0.7 m/s (typed)']) && ~contains(cap_typed, ['1st' en '99th percentile']) && ...
    contains(cap_auto, ['m/s (1st' en '99th percentile, auto)']) && ~contains(cap_auto, '(typed)') && ...
    ... % with Panel details off the range is in (i), not drawn
    contains(cap_typed, ['Colour range: 0.5' en '0.7 m/s']) && contains(cap_auto, ['Colour range: ' ends{1} en ends{2} ' m/s']) && ...
    ~contains(drawn_typed, 'colours 0.5') && ~contains(drawn_auto, 'colours '), ...
    sprintf('typed: "%s" | auto: "%s"', cap_typed, cap_auto));

%% R5
% The activation panel's auto range is the 1st to 99th percentile of its
% drawn values too (the app's limit fields are 0 0 here, so the projection
% recorded none); the caption says "(auto)"
d_a = getappdata(fig, 'reconstruction_activation');
va = d_a.values(isfinite(d_a.values));
st_c = getappdata(fig, 'reconstruction_confidence');
s_a = st_c(strcmp({st_c.role}, 'projected'));
if ~isempty(s_a) && ~isempty(s_a.all), va = s_a.all(isfinite(s_a.all)); end   % as drawn, before any hiding
want_a = prctile(va, [1 99]);
src_a = getappdata(fig, 'reconstruction_range_source');
rf = getappdata(fig, 'reconstruction_range_full');   % the full range clause of the caption
tip_a = rf.projected;
ends_a = tab.viewer_range_ends(want_a);
results = add(results, 'R5 activation auto: CLim = 1st-99th percentile of the drawn values, caption "(auto)"', ...
    strcmp(src_a.activation, 'auto') && max(abs(ax_a.CLim - want_a)) < 1e-9 && ...
    contains(tip_a, ['colours ' ends_a{1} en ends_a{2}]) && contains(tip_a, 'percentile, auto)') && ...
    any(isfinite(d_a.values) & d_a.values > want_a(2)), ...
    sprintf('source %s, CLim %s, percentiles %s, min-max %s | %s', src_a.activation, mat2str(ax_a.CLim, 4), ...
    mat2str(want_a, 4), mat2str([min(va) max(va)], 4), tip_a));
close(fig, 'force');

%% R6
% Limits recorded at projection (display_limits, 'app') still come before
% auto; typed limits before both
mj = fullfile(run_dir, 'outputs', 'reprojection', 'reprojection_manifest.json');
mtxt = fileread(mj);
mm = jsondecode(mtxt);
mm.display_limits = struct('activation', [22 48], 'cv', []);
fid = fopen(mj, 'w', 'n', 'UTF-8'); fprintf(fid, '%s', jsonencode(mm)); fclose(fid);
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
ax_a = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
src_a = getappdata(fig, 'reconstruction_range_source');
app_ok = strcmp(src_a.activation, 'app') && isequal(ax_a.CLim, [22 48]);
close(fig, 'force');
[r_ok, r_err, vis] = tab.resolve_visualisation_context(run_id);
assert(r_ok, r_err);
vis.activation_limits = [30 40];
[v_ok, v_err, fig] = tab.visualise_artifacts(vis);
assert(v_ok, v_err);
ax_a = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
src_t = getappdata(fig, 'reconstruction_range_source');
typed_ok = strcmp(src_t.activation, 'typed') && isequal(ax_a.CLim, [30 40]);
close(fig, 'force');
fid = fopen(mj, 'w', 'n', 'UTF-8'); fwrite(fid, unicode2native(mtxt, 'UTF-8')); fclose(fid);
results = add(results, 'R6 activation: recorded limits before auto, typed limits before both', app_ok && typed_ok, ...
    sprintf('recorded: %s %d | typed: %s %d', src_a.activation, app_ok, src_t.activation, typed_ok));

%% R7
% The app's own automatic range counts as auto: at
% projection the app's [0, max] is flagged (activation_auto); an older
% record without the flag counts as auto when it is [0, hi] with hi at or
% above the largest projected value; a range cut below it stays a choice
app.max_value_ACT = 47.25;
app_auto = rabbit_rhythm_reproject.app_limits_are_auto(app, [0 47.25]) && ...
    ~rabbit_rhythm_reproject.app_limits_are_auto(app, [10 40]) && ~rabbit_rhythm_reproject.app_limits_are_auto(app, [0 44]);
app.lowerylimit.Value = 0; app.upperylimit.Value = 47.25;
rec_auto = rabbit_rhythm_reproject.app_display_limits(app);
app.upperylimit.Value = 44;
rec_typed = rabbit_rhythm_reproject.app_display_limits(app);
flag_ok = isfield(rec_auto, 'activation_auto') && rec_auto.activation_auto && ~rec_typed.activation_auto && ...
    isequal(rec_auto.activation, [0 47.25]);
mm7 = jsondecode(mtxt);
vmax = max(va);
cases7 = {struct('activation', [22 48], 'cv', [], 'activation_auto', true), 'auto'; ...
    struct('activation', [22 48], 'cv', [], 'activation_auto', false), 'app'; ...
    struct('activation', [0 vmax + 20], 'cv', []), 'auto'; ...
    struct('activation', [0 floor(vmax) - 3], 'cv', []), 'app'};
got7 = cell(1, size(cases7, 1));
ok7 = app_auto && flag_ok;
for k = 1:size(cases7, 1)
    mm7.display_limits = cases7{k, 1};
    fid = fopen(mj, 'w', 'n', 'UTF-8'); fprintf(fid, '%s', jsonencode(mm7)); fclose(fid);
    [v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
    assert(v_ok, v_err);
    ax_a = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected');
    src7 = getappdata(fig, 'reconstruction_range_source');
    got7{k} = src7.activation;
    if strcmp(cases7{k, 2}, 'auto')
        ok7 = ok7 && strcmp(got7{k}, 'auto') && max(abs(ax_a.CLim - want_a)) < 1e-9;
    else
        ok7 = ok7 && strcmp(got7{k}, 'app') && isequal(ax_a.CLim, cases7{k, 1}.activation);
    end
    close(fig, 'force');
end
fid = fopen(mj, 'w', 'n', 'UTF-8'); fwrite(fid, unicode2native(mtxt, 'UTF-8')); fclose(fid);
results = add(results, 'R7 the app''s own [0, max] counts as auto (flag at projection; old records by the rule); a cut range stays', ...
    ok7, sprintf('app_limits_are_auto %d, flag recorded %d | flagged auto/typed, old [0 max+20], old [0 max-3]: %s', ...
    app_auto, flag_ok, strjoin(got7, ', ')));

%% R8
% The CV range by the same rule: the
% app's own automatic CV pair is not recorded (cv_auto); typed limits are; in
% Visualise a flagged automatic pair, or in an older record [0, hi] with hi at
% or above the largest projected speed, gives the panel's auto range; the 2-D
% CV tab shows [0, 99th percentile] (rabbit_cv_map.display_range) and that pair
% counts as the app's own too
cvm = app.processed_data.CV_map;
sp = cvm(:, :, 3);
sp = sp(isfinite(sp) & sp > 0);
d2 = rabbit_cv_map.display_range(cvm);
two_d = abs(d2(1)) < 1e-12 && abs(d2(2) - prctile(sp, 99)) < 1e-12;
% plot_CV_map takes its colour range from that function (the app's code)
code = appdesigner.internal.codegeneration.getAppFileCode(which('analyse_optical_mapping.mlapp'));
uses = contains(code, 'rabbit_cv_map.display_range(app.processed_data.CV_map)');
cv_auto_fn = rabbit_rhythm_reproject.app_cv_limits_are_auto(app, [0 max(cvm(:))]) && ...
    rabbit_rhythm_reproject.app_cv_limits_are_auto(app, d2) && ~rabbit_rhythm_reproject.app_cv_limits_are_auto(app, [0.3 0.9]);
app.lowerylimit_traces.Value = 0; app.upperylimit_traces.Value = max(cvm(:));
rec_a = rabbit_rhythm_reproject.app_display_limits(app);
app.lowerylimit_traces.Value = d2(1); app.upperylimit_traces.Value = d2(2);
rec_p = rabbit_rhythm_reproject.app_display_limits(app);
app.lowerylimit_traces.Value = 0.3; app.upperylimit_traces.Value = 0.9;
rec_t = rabbit_rhythm_reproject.app_display_limits(app);
rec_ok = isempty(rec_a.cv) && rec_a.cv_auto && isempty(rec_p.cv) && rec_p.cv_auto && ...
    isequal(rec_t.cv, [0.3 0.9]) && ~rec_t.cv_auto;
cj = fullfile(run_dir, 'outputs', 'reprojection', 'cv_reprojection_manifest.json');
ctxt = fileread(cj);
cm8 = jsondecode(ctxt);
smax = max(s);
cases8 = {struct('cv', [0.2 0.95], 'cv_auto', true), 'auto'; ...
    struct('cv', [0.2 0.95], 'cv_auto', false), 'app'; ...
    struct('cv', [0 smax + 1]), 'auto'; ...
    struct('cv', [0 0.8 * smax]), 'app'};
got8 = cell(1, size(cases8, 1));
ok8 = two_d && uses && cv_auto_fn && rec_ok;
for k = 1:size(cases8, 1)
    cm8.display_limits = cases8{k, 1};
    fid = fopen(cj, 'w', 'n', 'UTF-8'); fprintf(fid, '%s', jsonencode(cm8)); fclose(fid);
    [v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
    assert(v_ok, v_err);
    ax_c = findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv');
    src8 = getappdata(fig, 'reconstruction_range_source');
    got8{k} = src8.cv;
    if strcmp(cases8{k, 2}, 'auto')
        ok8 = ok8 && strcmp(got8{k}, 'auto') && max(abs(ax_c.CLim - want)) < 1e-9;
    else
        ok8 = ok8 && strcmp(got8{k}, 'app') && max(abs(ax_c.CLim - cases8{k, 1}.cv)) < 1e-12;
    end
    close(fig, 'force');
end
fid = fopen(cj, 'w', 'n', 'UTF-8'); fwrite(fid, unicode2native(ctxt, 'UTF-8')); fclose(fid);
results = add(results, ['R8 CV: the app''s own pair (2-D [0, 99th percentile] or [0, max]) is not recorded and counts ' ...
    'as auto; typed limits recorded and kept; old records by the rule'], ok8, ...
    sprintf('2-D %d (%s) code %d, rule %d, record %d | flagged auto/typed, old [0 max+1], old [0 0.8 max]: %s', ...
    two_d, mat2str(d2, 4), uses, cv_auto_fn, rec_ok, strjoin(got8, ', ')));

%% R9
% the CV map's activation times were cut at the display's
% colour limit; by default nothing is cut, and the
% Activation Map tab's Upper Y limit cuts only with "Leave out activation
% times above the display limit (<x> ms)" ticked on the CV tab
rabbit_cv_map.controls(app);
cut_box = findall(app.GridLayout22, 'Tag', 'CvCutAtLimitCheckBox');
app.upperylimit.Value = 41.5;
[c9, s9] = rabbit_cv_map.activation_cut(app);            % unticked (the default)
cut_box(1).Value = true;
rabbit_cv_map.controls(app);
[c9t, s9t] = rabbit_cv_map.activation_cut(app);          % ticked
box_text = cut_box(1).Text;
cut_box(1).Value = false;
% History names the limit as it is: unticked, the Upper Y
% limit set but not used; ticked, the cut; no limit, "no upper limit set"
h9 = rabbit_cv_map.cut_history_text(app, c9, s9);
h9t = rabbit_cv_map.cut_history_text(app, c9t, s9t);
app.upperylimit.Value = 0;
h9n = rabbit_cv_map.cut_history_text(app, Inf, s9);
app.upperylimit.Value = 41.5;
hist9 = contains(h9, 'the Upper Y limit (41.5 ms) is a display limit and is not used') && ~contains(h9, 'no upper limit set') && ...
    startsWith(h9t, 'Activation times above 41.5 ms left out (') && contains(h9n, 'no upper limit set') && ...
    contains(code, 'act_cut_text = rabbit_cv_map.cut_history_text(app, act_cut, act_cut_source);');
code9 = contains(code, '[act_cut, act_cut_source] = rabbit_cv_map.activation_cut(app);') && ...
    ~contains(code, 'activation_map(activation_map>app.display.image_handle.Parent.CLim(2)) = nan;') && ...
    contains(code, 'cv_settings.activation_cut_ms = act_cut;') && ~contains(code, 'max_value = max(app.processed_data.CV_map(:),[],''omitnan'');');   % plot_CV_map no longer sets max_value_ACT
results = add(results, 'R9 CV input: no cut by default; the Upper Y limit only when ticked; recorded (B4)', ...
    isscalar(cut_box) && isinf(c9) && startsWith(s9, 'none') && c9t == 41.5 && contains(s9t, 'Upper Y limit') && ...
    strcmp(box_text, 'Leave out activation times above the display limit (41.5 ms)') && code9 && hist9, ...
    sprintf('%g (%s) | ticked %g (%s) | "%s" | code %d | %s / %s / %s', c9, s9, c9t, s9t, box_text, code9, h9, h9t, h9n));

%% R10
% Remove local outliers blanks the outlier pixels only (all
% three layers), not every row x column pair of them; repeats until a pass
% removes none; its window stays within one view
base10 = 0.6 + 0.002 * repmat(1:60, 40, 1);          % a smooth ramp: no outliers of its own
cv10 = cat(3, base10 * 0.6, base10 * 0.8, base10);
cv10([1:3, end - 2:end], :, :) = NaN;               % outside the tissue, as on a real map
cv10(:, [1:3, end - 2:end], :) = NaN;
spikes = [10 12; 30 45];                         % two outliers in different rows and columns
for k = 1:2, cv10(spikes(k, 1), spikes(k, 2), :) = 25; end
V10 = [ones(40, 30), 2 * ones(40, 30)];          % two views side by side
[out10, n10, p10] = rabbit_cv_map.remove_local_outliers(cv10, 5, V10);
blank = isnan(out10(:, :, 3)) & ~isnan(cv10(:, :, 3));   % blanked by the removal (not the frame)
pixels_only = blank(10, 12) && blank(30, 45) && ~blank(10, 45) && ~blank(30, 12) && ...
    all(isnan(out10(10, 12, :)), 'all') && nnz(blank) == 2;
% A view whose values sit far from the other's: none blanked at the seam
cv10b = cv10; cv10b(:, 31:end, :) = cv10b(:, 31:end, :) * 4;
[out10b, ~, ~] = rabbit_cv_map.remove_local_outliers(cv10b, 5, V10);
seam_kept = ~any(any(isnan(out10b(5:35, 25:36, 3))));
code10 = (contains(code, 'rabbit_cv_map.remove_local_outliers(') || ...   % through the chosen method,
    contains(code, 'rabbit_cv_map.remove_outliers_chosen(')) && ...          % which calls it by default
    ~contains(code, 'app.processed_data.CV_map(outlier_indices_row,outlier_indices_col,:) = nan;');
results = add(results, 'R10 Remove local outliers: pixels only, all layers, until none, window within a view', ...
    pixels_only && p10 >= 2 && seam_kept && code10, sprintf('blanked %d (passes %d), pixels only %d, seam kept %d, code %d', ...
    n10, p10, pixels_only, seam_kept, code10));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_CV_RANGE RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_cv_range:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
