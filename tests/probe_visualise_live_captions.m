function probe_visualise_live_captions
%% Probe: Visualise captions counted live from what is drawn
% Collin Snitchler
% 23.11.2026
% The Visualise window's captions and controls (final_proposal B1, B2): line 1 says what a
% panel shows, line 2 its caveats, every number counted from what is drawn.
% Driven through the app's Reproject run button, headless, on a copy of a
% completed run, with typed colour ranges so that some faces are outside.
%   L1  0.55: no class-4 faces; the low-confidence checkbox is ticked and
%       disabled; no edge weight warning in the captions
%   L2  0.30: the checkbox starts unticked and the class-4 fills are hidden
%       (the drawn values are those without class 4); the captions say
%       "WARN edge weight 0.30 (RHYTHM default 0.55): N low-confidence
%       faces hidden"
%   L3  ticking and unticking recounts: activation coverage, CV median and
%       video vertices match a recount from the projection's files, and
%       the activation coverage changes
%   L4  out-of-range values: own colours (activation white above, black
%       below; CV the same); the caption's count of faces
%       drawn with them matches a recount, and follows a newly typed range;
%       the range is drawn short, the (i) tooltip has it in full
%   L5  Panel details adds the full captions (with the file) and the whole
%       orientation note; unticked, the short captions come back
%   L6  the header is one line, Interpreter none, with the run id
%   L7  no overlaps between the controls, panels (with their labels and
%       captions), colour bars and header at the default size and at
%       1050 px wide, and with Panel details; the video slider fills its
%       panel; no hint line. Axes text too: the panels show
%       no rulers (tick labels), and each title and caption is checked
%       against its own scale bar text, axis labels and colour bar
%   L8  range ends with the same decimals (50.7-147.5, 0.00-1.18, 25-45);
%       Panel details gives the CV median over the faces shown
%   L9  the activation caption gives both shares,
%       "N % of mesh faces shown (M % with low-confidence fills)", and the
%       other way round with the fills on; the CV median is "over shown
%       faces"; the (i) tooltips of the activation and CV panels count
%       their edge faces and low-confidence faces, and the faces that are
%       low-confidence in one panel only, from the confidence files
%   L10 the data panels (activation, video, CV) are matte (no specular
%       highlight: white is an out-of-range colour); the plain mesh keeps
%       its light and highlight; no "Reproject run" (the button's old name)
%       in the window's texts or in the code's texts
%   L11 activation range back on auto: the 1st to 99th
%       percentile of the drawn values, as the CV panel; "(auto)" in the
%       full caption; the faces beyond it drawn and counted as outside
%   L12 the activation caption says "WARN spread N ms (5-95 %) > 80 ms" in
%       line 2 when the 5-95 % spread of the vertex values the panel draws
%       now is above 80 ms, following the low-confidence checkbox; none at
%       80 ms or below. The caution case needs OM_TEST_SPREAD_DS (a dataset copy
%       whose projection spreads more than 80 ms), else PROBE_SKIP
%   L13 "Faces per view" and the frame check's summary list View1 to View4
%       through the regions file's view_order; no lowercase view1..view4
%       label outside a file name in the window's texts and tooltips
%   the CV caption reads "median 0.70 m/s (IQR
%       0.52-0.94), image plane" (F10; L3, L8, L9); the activation range
%       names each side as "N faces (x %) later than <hi> ms, white" (F19;
%       L4); the (i) tooltips give the activation's median per face class
%       and the CV medians and median by view (L9)
%   L16 one caveat a line, no mid-phrase wraps, the video in
%       faces, the other panel's differing low-confidence count named
%   L14 the rhythm is the projection's own record, in Results,
%       the activation and CV captions and the saved footers alike (Paced,
%       Sinus rhythm; the CV record has it too); an older record without it
%       "Not stated"; a record that cannot be read "could not be read"
% Panel details are in a box under each panel since 24.11.2026: the
% helper caption() reads the caption and, when shown, that box.
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_visualise_live_captions" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_visualise_live_captions', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
out_dir = fullfile(run_dir, 'outputs', 'reprojection');
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset, a map, frames and a CV map (as probe_confidence_classes)
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
map = 20 + 30 * rand(size(om_image));
frames = repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, []);
rng(11, 'twister');
speed = 0.2 + 0.8 * rand(size(map));
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
g = tab.viewer_glyphs();

%% L1
app.recon.ReconstructionEdgeWeightField.Value = 0.55;
redo(app);
fig = open_vis(tab, run_id);
cb = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
caps = all_captions(fig);
l1 = isscalar(cb) && strcmp(cb.Enable, 'off') && cb.Value == 1 && ~contains(caps, 'WARN edge') && ...
    ~any(read_class(fullfile(out_dir, 'activation_confidence.mat')) == 4);
results = add(results, 'L1 0.55: checkbox ticked and disabled, no edge weight warning', l1, ...
    sprintf('enable %s value %g | %s', cb_field(cb, 'Enable'), cb_value(cb), caps));
close(fig, 'force');

%% L2
app.recon.ReconstructionEdgeWeightField.Value = 0.30;
redo(app);
cls = read_class(fullfile(out_dir, 'activation_confidence.mat'));
cv_cls = read_class(fullfile(out_dir, 'cv_confidence.mat'));
act_f = read_cdf_values(fullfile(out_dir, 'activation_projected.cdf'));
cv_f = read_cdf_values(fullfile(out_dir, 'cv_projected.cdf'));
n4 = nnz(cls == 4);
fig = open_vis(tab, run_id);
cb = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
st = getappdata(fig, 'reconstruction_confidence');
d = getappdata(fig, 'reconstruction_activation');
s_act = st(strcmp({st.role}, 'projected'));
cap_a = caption(fig, 'projected');
% in meaning first, the setting after
warn = sprintf('WARN %s steep-angle rim faces hidden (low confidence; edge weight 0.30, RHYTHM default 0.55)', tab.format_count(n4));
l2 = n4 > 0 && isscalar(cb) && strcmp(cb.Enable, 'on') && cb.Value == 0 && ~isempty(s_act) && ...
    isequaln(d.values, s_act.hidden) && contains(cap_a, warn) && contains(caption(fig, 'video'), 'edge weight 0.30') && ...
    contains(caption(fig, 'cv'), sprintf('WARN %s steep-angle rim faces hidden (low confidence; edge weight 0.30, RHYTHM default 0.55)', ...
    tab.format_count(nnz(cv_cls == 4))));
results = add(results, 'L2 0.30: unticked by default, class-4 fills hidden, captions say so', l2, ...
    sprintf('class 4: %d | %s', n4, cap_a));

%% L3
[want_a, want_c, want_v] = recount(tab, fig, act_f, cls, cv_f, cv_cls, false);
hidden_ok = contains(caption(fig, 'projected'), want_a) && contains(caption(fig, 'cv'), want_c) && ...
    contains(caption(fig, 'video'), want_v);
cap_hidden = caption(fig, 'projected');
cb.Value = 1; cb.Callback(cb, []);
[want_a2, want_c2, want_v2] = recount(tab, fig, act_f, cls, cv_f, cv_cls, true);
shown_ok = contains(caption(fig, 'projected'), want_a2) && contains(caption(fig, 'cv'), want_c2) && ...
    contains(caption(fig, 'video'), want_v2) && contains(caption(fig, 'projected'), 'steep-angle rim faces shown');
cap_shown = caption(fig, 'projected');
cb.Value = 0; cb.Callback(cb, []);
back = strcmp(caption(fig, 'projected'), cap_hidden);
results = add(results, 'L3 toggling recounts coverage, CV median and video vertices from what is drawn', ...
    hidden_ok && shown_ok && back && ~strcmp(want_a, want_a2), ...
    sprintf('hidden "%s" / "%s" / "%s" -> shown "%s" / "%s" / "%s" | back %d | %s || %s', want_a, want_c, want_v, ...
    want_a2, want_c2, want_v2, back, cap_hidden, cap_shown));

%% L9
keep_all = cls >= 1 & cls <= 4;
p_all = tab.viewer_percent(100 * nnz(keep_all) / numel(keep_all));
p_hid = tab.viewer_percent(100 * nnz(keep_all & cls ~= 4) / numel(keep_all));
cap_off = caption(fig, 'projected');
cb.Value = 1; cb.Callback(cb, []);
cap_on = caption(fig, 'projected');
cb.Value = 0; cb.Callback(cb, []);
both_ok = contains(cap_off, sprintf('%s of mesh faces shown (%s with low-confidence fills)', p_hid, p_all)) && ...
    contains(cap_on, sprintf('%s of mesh faces shown (%s without low-confidence fills)', p_all, p_hid)) && ...
    contains(caption(fig, 'cv'), 'm/s (IQR ') && contains(caption(fig, 'cv'), 'image plane');
tip_a = info_tip(fig, 'projected');
tip_c = info_tip(fig, 'cv');
% the activation (i) gives each class's median,
% "Median activation by face class: DIRECT 103 · ... ms."; the CV (i) the
% medians in use and the median by view (F10)
cls_parts = {};
cls_names = {'DIRECT', 'OVERLAP', 'EDGE', 'low-conf'};
for c4 = 1:4
    vc = act_f(cls == c4 & isfinite(act_f));
    if ~isempty(vc), cls_parts{end + 1} = sprintf('%s %.0f', cls_names{c4}, median(vc)); end %#ok<AGROW>
end
med_ok = contains(tip_a, ['Median activation by face class: ' strjoin(cls_parts, g.dot) ' ms.']) && ...
    contains(tip_c, 'CV medians: ') && contains(tip_c, 'vertices with a value (every face with a CV value; the Results row)') && ...
    contains(tip_c, sprintf('%s m/s over the %s faces shown (the caption)', ...
    tab.viewer_number(median(cv_f(isfinite(cv_f) & cv_f > 0 & cv_cls <= 3))), ...
    tab.format_count(nnz(isfinite(cv_f) & cv_f > 0 & cv_cls <= 3)))) && ...
    (exist(fullfile(fileparts(cv_path_of(fig)), 'cv_direction.mat'), 'file') ~= 2 || ...
    ~isempty(regexp(tip_c, 'CV median by view \(each face counted for the view that gave most of its value\): V1 \d\.\d\d', 'once')));
want_a = sprintf('%s edge faces in all; %s of them are below 0.55 (low-confidence).', ...
    tab.format_count(nnz(cls == 3 | cls == 4)), tab.format_count(n4));
want_c = sprintf('%s edge faces in all; %s of them are below 0.55 (low-confidence).', ...
    tab.format_count(nnz(cv_cls == 3 | cv_cls == 4)), tab.format_count(nnz(cv_cls == 4)));
only_a = nnz(cls == 4 & cv_cls ~= 4);
only_c = nnz(cv_cls == 4 & cls ~= 4);
why_ok = (only_a == 0 && only_c == 0) || ...
    (contains(tip_a, sprintf('%s faces are low-confidence here only, %s in the CV panel only', ...
    tab.format_count(only_a), tab.format_count(only_c))) && ...
    contains(tip_c, sprintf('%s faces are low-confidence here only, %s in the activation panel only', ...
    tab.format_count(only_c), tab.format_count(only_a))));
results = add(results, 'L9 activation shares both ways, CV median over shown faces, (i) edge and low-confidence counts', ...
    both_ok && contains(tip_a, want_a) && contains(tip_c, want_c) && why_ok && med_ok, ...   % med_ok:
    sprintf('%s || %s || %s || %s', cap_off, cap_on, tip_a, tip_c));

%% L16
% each caveat on its own line (no drawn line holds
% the edge weight warning and the rhythm both); a wrapped line breaks after a
% phrase, not inside "(5-95 %) > 80 ms" or "(RHYTHM default 0.55)"; the video
% counts faces; differing low-confidence counts are named in the caption
sub_p = cellstr(findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected').Subtitle.String);
sub_c = cellstr(findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv').Subtitle.String);
one_each = ~any(contains(sub_p, 'edge weight 0.30') & contains(sub_p, 'Rhythm:')) && ...
    ~any(contains(sub_c, 'edge weight 0.30') & contains(sub_c, 'Rhythm:'));
no_mid = ~any(endsWith([sub_p(:); sub_c(:)], {'(RHYTHM', '(5', ['(5' char(8211) '95'], '>'}));
video_faces = contains(caption(fig, 'video'), 'of mesh faces shown (') && contains(caption(fig, 'video'), ' have data') && ...
    ~contains(caption(fig, 'video'), 'of vertices');
n4c = nnz(cv_cls == 4);
named = n4c == n4 || contains(caption(fig, 'cv'), sprintf('(activation panel %s; see (i))', tab.format_count(n4)));
results = add(results, 'L16 one caveat a line, no mid-phrase wraps, video in faces, other low-confidence count named (F19)', ...
    one_each && no_mid && video_faces && named, sprintf('%s || %s', strjoin(sub_p, ' / '), strjoin(sub_c, ' / ')));

%% L10
patch_of =@(role) findobj(findobj(fig, 'Type', 'axes', 'Tag', ['panel_' role]), 'Type', 'patch');
spec_ok = true;
for role = {'projected', 'video', 'cv'}
    h = patch_of(role{1});
    spec_ok = spec_ok && ~isempty(h) && all([h.SpecularStrength] == 0);
end
hm = patch_of('rebuilt');
mesh_ok = ~isempty(hm) && all([hm.SpecularStrength] > 0) && ...
    ~isempty(findobj(findobj(fig, 'Type', 'axes', 'Tag', 'panel_rebuilt'), 'Type', 'light'));
texts = [get(findall(fig, 'Type', 'text'), {'String'}); get(findobj(fig, 'Type', 'uicontrol'), {'TooltipString'})];
texts = cellfun(@(s) strjoin(cellstr(s), ' '), texts, 'UniformOutput', false);
src = splitlines(fileread(which('rabbit_reconstruction_tab')));
code = src(~startsWith(strtrim(src), '%'));
old_name = any(contains(texts, 'Reproject run')) || any(contains(code, {'Reproject run', 'then Reproject.', 'Reproject once'}));
results = add(results, 'L10 data panels matte, the plain mesh lit; no "Reproject run" left', ...
    spec_ok && mesh_ok && ~old_name, sprintf('matte %d, mesh %d, old name %d', spec_ok, mesh_ok, old_name));

%% L4
fa = findobj(fig, 'Tag', 'ReconstructionActivationLimits');
fc = findobj(fig, 'Tag', 'ReconstructionCvLimits');
fa.String = '25 45'; fa.Callback(fa, []);
fc.String = '0.3 0.9'; fc.Callback(fc, []);
[l4a, det_a] = out_of_range(tab, fig, 'projected', [25 45], ' ms');
[l4c, det_c] = out_of_range(tab, fig, 'cv', [0.3 0.9], ' m/s');
fa.String = '30 40'; fa.Callback(fa, []);
[l4b, det_b] = out_of_range(tab, fig, 'projected', [30 40], ' ms');
% what white is and how to colour it, and the range's
% source; W2: the 2-D maps' near-simultaneous words for the activation caption
cap4 = caption(fig, 'projected');
lim4 = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected').CLim;
% the example is the 5th-95th percentile of the faces
% shown, "or clear it for auto"
w4 = ~isempty(regexp(cap4, 'white = later than the colour range; type a wider Range \(e\.g\. -?\d+ -?\d+\) or clear it for auto', 'once'));
w2 = strcmp(rabbit_reconstruction_tab.simultaneous_2d_words(struct('views', {{'View1', 'View2', 'View3', 'View4'}}, ...
    'iqr_ms', [4.8 5.2 4.2 4.9])), sprintf(['2-D maps: middle half of each view within 4%s5 ms; the 3-D spread comes ' ...
    'from scattered late faces, also on directly seen faces; check the activation (i), median time by face ' ...
    'class'], char(8211))) && ...   % R12
    isempty(rabbit_reconstruction_tab.simultaneous_2d_words(struct('views', {{'View1'}}, 'iqr_ms', 12))) && ...
    ... % each view's recorded limit, as the CV alert: View2 (12 < 13 ms) only
    strcmp(rabbit_reconstruction_tab.simultaneous_2d_words(struct('views', {{'View1', 'View2', 'View3', 'View4'}}, ...
    'iqr_ms', [18.7 12 14.3 22.3], 'warn_below_ms', [15 13 13 20])), ['2-D maps: middle half of View2 within 12 ms; ' ...
    'the 3-D spread comes from scattered late faces, also on directly seen faces; check the activation (i), ' ...
    'median time by face class']) && ...   % R12
    isempty(rabbit_reconstruction_tab.simultaneous_2d_words(struct('views', {{'View1', 'View2'}}, ...
    'iqr_ms', [4.8 5.2], 'warn_below_ms', [3.4 4.0]))) && ...
    strcmp(tab.viewer_range_how('app', 'projected'), 'recorded with the projection, Activation Map tab limits');
results = add(results, 'L4 out-of-range faces: own colours, counted, following the typed range; white explained (W4, W2)', ...
    l4a && l4c && l4b && w4 && w2, strjoin({det_a, det_c, det_b, cap4}, ' | '));

%% L11
% Back to auto: the 1st to 99th percentile of the values drawn (before the
% low-confidence fills were hidden, as the CV panel), "(auto)" in the full
% caption, and the faces beyond counted as outside
fa.String = 'auto'; fa.Callback(fa, []);
va = s_act.all(isfinite(s_act.all));
want_auto = prctile(va(:)', [1 99]);
[l11, det11] = out_of_range(tab, fig, 'projected', want_auto, ' ms');
rf11 = getappdata(fig, 'reconstruction_range_full');   % the full range clause of the caption
tip11 = rf11.projected;
ends11 = tab.viewer_range_ends(want_auto);
l11 = l11 && contains(tip11, sprintf('colours %s%s%s ms (1st%s99th percentile, auto)', ends11{1}, char(8211), ends11{2}, char(8211)));
fa.String = '30 40'; fa.Callback(fa, []);
results = add(results, 'L11 activation auto: 1st-99th percentile, "(auto)", faces beyond counted outside', l11, ...
    sprintf('%s | %s', det11, tip11));

%% L8
% Both ends of a range with the same decimals, from the span; Panel details
% gives the CV median over the faces shown, as the caption does
e1 = tab.viewer_range_ends([50.66 147.47]);
e2 = tab.viewer_range_ends([0 1.183]);
e3 = tab.viewer_range_ends([25 45]);
pd = findobj(fig, 'Tag', 'ReconstructionPanelDetails');
ck = isfinite(cv_f) & cv_f > 0 & cv_cls <= 4 & cv_cls ~= 4;
med = tab.viewer_number(median(cv_f(ck)));
pd.Value = 1; pd.Callback(pd, []);
cv_full = caption(fig, 'cv');
pd.Value = 0; pd.Callback(pd, []);
l8 = isequal(e1, {'50.7', '147.5'}) && isequal(e2, {'0.00', '1.18'}) && isequal(e3, {'25', '45'}) && ...
    contains(cv_full, sprintf('median %.2f m/s (IQR ', median(cv_f(ck)))) && ...   % the caption's form
    contains(cv_full, 'faces shown), image plane') && ~contains(cv_full, 'Range ') && ...   % the colour range line, no "Range"
    contains(cv_full, 'come from the 2-D CV maps') && ~contains(cv_full, [char(215) '3 median']) && ...   % no smoothing recorded here: none said
    contains(cv_full, sprintf('colours %s', strjoin(tab.viewer_range_ends(findobj(fig, 'Type', 'axes', 'Tag', 'panel_cv').CLim), char(8211)))) && ...
    ~contains(cv_full, 'over vertices');
results = add(results, 'L8 range ends with the same decimals; Panel details CV median per face, as the caption', l8, ...
    sprintf('%s | %s | %s | median %s | %s', strjoin(e1, '-'), strjoin(e2, '-'), strjoin(e3, '-'), med, cv_full));

%% L5
pd = findobj(fig, 'Tag', 'ReconstructionPanelDetails');
note = findall(fig, 'Tag', 'ReconstructionOrientationNote');
short = caption(fig, 'projected');
n_short = numel(cellstr(findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected').Subtitle.String));
pd.Value = 1; pd.Callback(pd, []);
full = strrep(caption(fig, 'projected'), ' (more in (i))', '');   % a cut caption goes on in the box
note_full = char(note.String);
n_full = numel(cellstr(findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected').Subtitle.String)) + ...
    numel(cellstr(findobj(fig, 'Tag', 'ReconstructionPanelDetailsText_projected').String));
pd.Value = 0; pd.Callback(pd, []);
% The short caption's key line comes first (with Panel
% details off the caption keeps its key number and warning tags only)
sub5 = cellstr(findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected').Subtitle.String);
short_head = sub5{1};
l5 = isscalar(pd) && n_full > n_short && startsWith(full, short_head) && contains(full, '(typed)') && ...
    contains(full, 'File: outputs\reprojection\activation_projected.ply') && contains(full, 'Coverage:') && ...
    ~contains(note_full, 'Atria up, from the') && ~contains(note_full, ['.' char(183)]) && ...   % no repeat of the title, no ". ·"
    strcmp(caption(fig, 'projected'), short) && isempty(char(note.String));
results = add(results, 'L5 Panel details draws the full captions and note; unticked, the short ones', l5, ...
    sprintf('%d -> %d lines | note "%s"', n_short, n_full, note_full));

%% L6
h = findall(fig, 'Tag', 'ReconstructionHeader');
hs = char(h.String);
l6 = isscalar(h) && strcmp(h.Interpreter, 'none') && ~contains(hs, newline) && ...
    startsWith(hs, ['Run ' run_id g.dot]) && contains(hs, 'atria up');
results = add(results, 'L6 header: one line, Interpreter none, run id as it is', l6, hs);

%% L7
% No overlaps at the default size and at a narrow width; the slider spans
% the OM video panel's cell less the Play button
[bad1, n1] = overlaps(fig);
sl_ok1 = slider_fills(fig);
% With Panel details the full captions have room too
pd.Value = 1; pd.Callback(pd, []);
bad_pd = overlaps(fig);
pd.Value = 0; pd.Callback(pd, []);
bad1 = [bad1, strcat({'details: '}, bad_pd)];
pos = get(fig, 'Position');
set(fig, 'Position', [pos(1) pos(2) 1050 pos(4)]);
drawnow;
if isa(fig.SizeChangedFcn, 'function_handle')
    % As the window manager does after a resize (headless figures may not)
    fig.SizeChangedFcn(fig, []);
end
[bad2, n2] = overlaps(fig);
sl_ok2 = slider_fills(fig);
results = add(results, 'L7 no overlaps between controls, panels and colour bars; slider = panel width', ...
    isempty(bad1) && isempty(bad2) && sl_ok1 && sl_ok2 && isempty(findall(fig, 'Tag', 'ReconstructionNavigationHint')), ...
    sprintf('default: %d objects, overlaps [%s], slider %d | 1050 px: %d objects, overlaps [%s], slider %d', ...
    n1, strjoin(bad1, '; '), sl_ok1, n2, strjoin(bad2, '; '), sl_ok2));
close(fig, 'force');

%% L17
% The per-view WARNs of Results (activation consistency, mesh outside)
% in the activation and CV captions, in full (Panel details, saved
% pictures) and as one short tag each with Panel details off (<= 4 lines);
% Helpers: the tags, the saved words, the CV outside colours,
% the one Arrows line, the speed floor
mj17 = fullfile(out_dir, 'reprojection_manifest.json');
t17 = fileread(mj17);
pm17 = jsondecode(t17);
pm17.activation_consistency = struct('views', {{'View1'; 'View2'; 'View3'; 'View4'}}, 'iqr_3d_direct_ms', [20; 21; 22; 74], ...
    'iqr_2d_ms', [18; 19; 20; 22], 'ratio', [1.1; 1.1; 1.1; 3.3], 'warn', [false; false; false; true], 'basis', 'probe');
pm17.mesh_outside_om = struct('views', {{'View1'; 'View2'; 'View3'; 'View4'}}, 'fraction', [0.07; 0.12; 0.13; 0.26], ...
    'warn', [false; true; true; true], 'basis', 'probe');
fid17 = fopen(mj17, 'w', 'n', 'UTF-8'); fwrite(fid17, jsonencode(pm17), 'char'); fclose(fid17);
fig = open_vis(tab, run_id);
full_a = strjoin(tab.viewer_caption(fig, 'projected'), ' | ');
full_c = strjoin(tab.viewer_caption(fig, 'cv'), ' | ');
want_d = sprintf('WARN View4 spread 3.3%s its 2-D map: directly seen faces spread 74 ms (IQR) against 22 ms', char(215));
ok17 = contains(full_a, want_d) && contains(full_a, 'WARN mesh outside the OM outline: ') && ...
    contains(full_c, want_d) && contains(full_c, 'WARN mesh outside the OM outline: ');
% Panel details off: the live caption keeps at most 4 lines, the tags are short
sub = findobj(fig, 'Type', 'axes', 'Tag', 'panel_projected').Subtitle;
n_sub = numel(cellstr(sub.String));
ok17 = ok17 && n_sub <= rabbit_reconstruction_tab.CAPTION_SHORT_LINES;
close(fig, 'force');
fid17 = fopen(mj17, 'w', 'n', 'UTF-8'); fwrite(fid17, t17, 'char'); fclose(fid17);
x = char(215);
ok17 = ok17 && strcmp(rabbit_reconstruction_tab.warning_tag([want_d ' as projected (unsmoothed) (warn > 1.5' x ')']), ...
    ['WARN View4 spread 3.3' x ' its 2-D map']) && ...
    strcmp(rabbit_reconstruction_tab.warning_tag('WARN mesh outside the OM outline: V1 7 % (warn > 10 %; not missing mesh)'), ...
    'WARN mesh outside the OM outline') && ...
    strcmp(rabbit_reconstruction_tab.warning_tag('WARN 8.7 % of faces shown > 1.5 m/s, max 25 m/s: outliers present'), ...
    'WARN outliers: 8.7 % > 1.5 m/s') && ...
    strcmp(rabbit_reconstruction_tab.warning_tag(['WARN 3,820 steep-angle rim faces hidden (low confidence; edge ' ...
    'weight 0.30, RHYTHM default 0.55) (CV panel 4,088; see (i))']), 'WARN 3,820 steep-angle rim faces hidden');
[out17, names17] = tab.viewer_out_colours('cv');
sv17 = tab.viewer_saved_lines({'WARN 3 faces hidden (activation panel 4; see (i))', 'Rhythm: Paced', 'a (more in (i))'});
ok17 = ok17 && isequal(out17, [0 0 0; 1 1 1]) && isequal(names17, {'black', 'white'}) && ...   % the CV outside colours
    isequal(sv17, {'WARN 3 faces hidden (activation panel 4)', 'a'}) && ...   % S10
    strcmp(tab.viewer_arrows_line(), sprintf(['Arrows: direction lifted onto the surface (approximate); length ' ...
    '0.4%s1 %s spacing; every arrow within the colour range'], char(8211), x)) && ...   % S10
    strcmp(rabbit_reconstruction_tab.cv_floor_words(3, 10), ['speeds below 0.3 m/s (distance max 3 mm / time max ' ...
    '10 ms) are not resolved; slow (transverse) conduction is not measured, so the median reads high']);   % T2
results = add(results, 'L17 per-view WARNs in the captions, short tags with details off; the outside colours and arrow words', ...
    ok17, sprintf('%d lines | %s || %s', n_sub, full_a, full_c));

%% L12
% The activation caption's spread caution: "WARN spread
% N ms (5-95 %) > 80 ms" in line 2 when the 5-95 % spread of the vertex
% values the panel draws now is above SPREAD_WARN_MS; it follows the
% low-confidence checkbox. Here (a small spread) no caution either way;
% with OM_TEST_SPREAD_DS (a dataset copy whose projection spreads more) the caution
% with the drawn values' numbers, before and after ticking the checkbox
lim12 = rabbit_reconstruction_tab.SPREAD_WARN_MS;
fig = open_vis(tab, run_id);
[c_off, s_off] = spread_caption(tab, fig, lim12);
cb = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
cb.Value = 1; cb.Callback(cb, []);
[c_on, s_on] = spread_caption(tab, fig, lim12);
close(fig, 'force');
ok12 = c_off && c_on && s_off <= lim12 && s_on <= lim12;
det12 = sprintf('this run: %.1f ms hidden, %.1f ms shown, no caution', s_off, s_on);
h2_root = '';
if ~isempty(getenv('OM_TEST_SPREAD_DS'))
    % Only read: the shared copy itself, no copy of its own
    [h2_root, h2_clean] = om_redo_copy('probe_visualise_live_captions', 'OM_TEST_SPREAD_DS', stem, run_id, 'read'); %#ok<ASGLU>
end
if ~isempty(h2_root)
    tab2 = rabbit_reconstruction_tab();
    [ok2, err2] = tab2.load_state(h2_root, stem);
    assert(ok2, err2);
    [v_ok, v_err, fig] = tab2.visualise_artifacts(run_id);
    assert(v_ok, v_err);
    cb = findobj(fig, 'Tag', 'ReconstructionLowConfidence');
    start_off = isscalar(cb) && cb.Value == 0;
    [w_off, s2_off] = spread_caption(tab2, fig, lim12);
    cb.Value = 1; cb.Callback(cb, []);
    [w_on, s2_on] = spread_caption(tab2, fig, lim12);
    close(fig, 'force');
    ok12 = ok12 && start_off && w_off && w_on && s2_off > lim12 && s2_on > lim12 && abs(s2_on - s2_off) > 0.5;
    det12 = sprintf('%s | OM_TEST_SPREAD_DS: opens unticked %d, %.1f ms hidden, %.1f ms shown', det12, start_off, s2_off, s2_on);
else
    fprintf('PROBE_SKIP L12 caution case: OM_TEST_SPREAD_DS not set\n');
end
results = add(results, 'L12 activation caption: WARN spread (5-95 %) > 80 ms from the drawn values, following the checkbox', ...
    ok12, det12);

%% L13
% Visualise per-view labels: "Faces per view" lists View1 to
% View4 through the regions file (the record has ROI rows), the frame
% check's summary too, and no lowercase view label shows outside a file
% name in the captions, details, tooltips or header
roi = jsondecode(fileread(fullfile(run_dir, 'inputs', 'roi.json')));
row_view = cellfun(@(v) str2double(regexprep(v, '^view', '')), cellstr(roi.view_order))';
pm = jsondecode(fileread(fullfile(out_dir, 'reprojection_manifest.json')));
n_v = zeros(1, 4); n_v(row_view) = pm.coverage.n_assigned_per_view(:)';
want13 = ['Faces per view: ' strjoin(arrayfun(@(k) sprintf('View%d %s', k, tab.format_count(n_v(k))), 1:4, ...
    'UniformOutput', false), ', ')];
fig = open_vis(tab, run_id);
pd = findobj(fig, 'Tag', 'ReconstructionPanelDetails');
pd.Value = 1; pd.Callback(pd, []);
full13 = caption(fig, 'projected');
texts13 = [get(findall(fig, 'Type', 'text'), {'String'}); get(findobj(fig, 'Type', 'uicontrol'), {'TooltipString'}); ...
    get(findobj(fig, 'Type', 'uicontrol'), {'String'}); get(findall(fig, 'Type', 'textboxshape'), {'String'})];
pd.Value = 0; pd.Callback(pd, []);
hits13 = lowercase_view_labels([texts13(:)', {full13}]);
close(fig, 'force');
m13 = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
fc13 = m13.result.reprojection.frame_check;
iou_v = zeros(1, 4); iou_v(row_view) = fc13.pose_iou(:)';
% a match within 0.01 of a limit is printed to 3 decimals
L13 = rabbit_rhythm_reproject.frame_check_limits();
want_s = ['View1 to View4 (1 = identical): ' rabbit_rhythm_reproject.outline_match_list(iou_v, [L13.pose_iou_warn L13.pose_iou_fail])];
sum_ok = contains(char(fc13.summary), want_s);
results = add(results, ['L13 Visualise: Faces per view and the frame check summary View1 to View4 by the regions ' ...
    'file; no lowercase view labels'], contains(full13, want13) && sum_ok && isempty(hits13) && ~isequal(row_view, 1:4), ...
    sprintf('want "%s" | summary %d "%s" | hits %s', want13, sum_ok, want_s, strjoin(hits13, ' || ')));

%% L14
% The rhythm in Visualise is the projection's own record.
% Projected marked Paced, 500 ms, then Sinus rhythm: every
% caption and saved footer that names a rhythm says so. The same record
% with recording_rhythm and the cycle taken out (a projection made before
% the marker, in its record and the run manifest): "Not stated". The window
% is opened as the Visualise button opens it, so its first captions are
% drawn before it knows its run folder (which gave "Not stated" before).
ok14 = true;
det14 = {};
marks = {{'Paced', 500}, {'Sinus rhythm'}};
wants = {'Rhythm: Paced, 500 ms cycle, pacing site not known (as stated)', 'Rhythm: Sinus rhythm (as stated)'};
for k = 1:2
    app.set_recording_rhythm(marks{k}{:});
    redo(app);
    % The CV projection records the marker too
    cvm14 = jsondecode(fileread(fullfile(out_dir, 'cv_reprojection_manifest.json')));
    cv_rec = isfield(cvm14, 'recording_rhythm') && ...
        strcmp(['Rhythm: ' rabbit_recording_rhythm.words(rabbit_recording_rhythm.from_record(cvm14.recording_rhythm))], wants{k});
    [o, d] = rhythm_everywhere(tab, run_id, wants{k});
    ok14 = ok14 && o && cv_rec;
    det14{end + 1} = sprintf('CV record %d, %s', cv_rec, d); %#ok<AGROW>
end
pm14 = jsondecode(fileread(fullfile(out_dir, 'reprojection_manifest.json')));
pm14 = rmfield(pm14, intersect(fieldnames(pm14), {'recording_rhythm', 'pacing_cycle_ms'}));
write_text(fullfile(out_dir, 'reprojection_manifest.json'), jsonencode(pm14, 'PrettyPrint', true));
m14 = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
m14.result.reprojection = rmfield(m14.result.reprojection, ...
    intersect(fieldnames(m14.result.reprojection), {'recording_rhythm', 'pacing_cycle_ms'}));
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m14, 'PrettyPrint', true));
cvm14 = jsondecode(fileread(fullfile(out_dir, 'cv_reprojection_manifest.json')));   % the CV record has its own marker
cvm14 = rmfield(cvm14, intersect(fieldnames(cvm14), {'recording_rhythm'}));
write_text(fullfile(out_dir, 'cv_reprojection_manifest.json'), jsonencode(cvm14, 'PrettyPrint', true));
[o, d] = rhythm_everywhere(tab, run_id, 'Rhythm: Not stated');
ok14 = ok14 && o;
det14{end + 1} = d;
% A record that cannot be read says so, never "Not stated"
write_text(fullfile(out_dir, 'reprojection_manifest.json'), '{"recording_rhythm": ');
write_text(fullfile(out_dir, 'cv_reprojection_manifest.json'), '{"recording_rhythm": ');
[o, d] = rhythm_everywhere(tab, run_id, 'Rhythm: could not be read');
ok14 = ok14 && o;
det14{end + 1} = d;
results = add(results, ['L14 rhythm from the projection''s record: Paced and Sinus rhythm in Results and in every ' ...
    'caption and footer that names one; an older record without it "Not stated"; an unreadable one "could not be read"'], ...
    ok14, strjoin(det14, ' || '));

%% L15
% a projection kept in outputs/reprojection_NN by Redo
% projection names its own files in its records (cdf, ply, video), not
% outputs/reprojection's
ok15 = true;
det15 = {};
kept = dir(fullfile(run_dir, 'outputs', 'reprojection_*'));
for k = 1:numel(kept)
    for name = {'reprojection_manifest.json', 'cv_reprojection_manifest.json'}
        mj = fullfile(kept(k).folder, kept(k).name, name{1});
        if exist(mj, 'file') ~= 2, continue; end
        try
            m15 = jsondecode(fileread(mj));
        catch
            continue;   % L14 left an unreadable record in the folder it then archived
        end
        for f = {'cdf', 'ply', 'video'}
            if ~isfield(m15, f{1}) || isempty(m15.(f{1})), continue; end
            here = strcmp(fileparts(strrep(char(m15.(f{1})), '\', '/')), strrep(fullfile(kept(k).folder, kept(k).name), '\', '/'));
            ok15 = ok15 && here;
            det15{end + 1} = sprintf('%s/%s %s %d', kept(k).name, name{1}, f{1}, here); %#ok<AGROW>
        end
    end
end
ok15 = ok15 && numel(det15) >= 4;
results = add(results, 'L15 a kept projection''s records name the files in its own folder', ok15, strjoin(det15, ', '));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_VISUALISE_LIVE_CAPTIONS RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_visualise_live_captions:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
end


function [a, c, v] = recount(tab, fig, ~, cls, cv_f, cv_cls, show_low)
% The caption numbers counted again from the projection's files and the drawn video
g = tab.viewer_glyphs();
keep = cls >= 1 & cls <= 4;
if ~show_low, keep = keep & cls ~= 4; end
a = sprintf('%s of mesh faces shown', tab.viewer_percent(100 * nnz(keep) / numel(keep)));
ck = isfinite(cv_f) & cv_f > 0 & cv_cls <= 4;
if ~show_low, ck = ck & cv_cls ~= 4; end
% the CV caption gives the median and IQR of the faces
% shown, "median 0.70 m/s (IQR 0.52-0.94), image plane" (F10); the video
% counts faces whose three vertices have data (F19)
q = prctile(cv_f(ck), [25 50 75]);
c = sprintf('median %.2f m/s (IQR %.2f%s%.2f, faces shown), image plane', q(2), q(1), char(8211), q(3));
vd = getappdata(fig, 'reconstruction_video');
has_v = any(isfinite(vd.series), 2);
fv = vd.handle.Faces;
% the drawn share is the share shown, "88 % of mesh
% faces shown (94 % have data; ...)"
v = sprintf('%s%s of mesh faces shown (', g.dot, tab.viewer_percent(100 * nnz(all(has_v(fv), 2)) / size(fv, 1)));
end


function [ok, detail] = out_of_range(tab, fig, role, lim, suffix)
% Colours of the vertices outside lim, and the caption's count of the faces
% drawn with them (a face with a vertex outside shows its colour)
key = 'reconstruction_activation';
if strcmp(role, 'cv'), key = 'reconstruction_cv'; end
d = getappdata(fig, key);
[out, ~] = tab.viewer_out_colours(role);
col = d.handle.FaceVertexCData;
hi = isfinite(d.values) & d.values > lim(2);
lo = isfinite(d.values) & d.values < lim(1);
inside = isfinite(d.values) & ~hi & ~lo;
own = all(ismember(col(hi, :), out(2, :), 'rows')) && all(ismember(col(lo, :), out(1, :), 'rows')) && ...
    ~any(ismember(col(inside, :), out, 'rows'));
f = d.handle.Faces;
n_hi = nnz(any(hi(f), 2));
n_lo = nnz(any(lo(f), 2));
n_out = nnz(any(hi(f) | lo(f), 2));
if strcmp(role, 'cv')
    % the CV panel counts the faces shown by their own
    % values (cv_projected.cdf), the basis of its colour range
    fdd = getappdata(fig, 'reconstruction_face_data');
    fv_ = double(fdd.cv.values(:));
    use = tab.viewer_faces_shown(fig, fdd.cv) & isfinite(fv_) & fv_ > 0;
    n_hi = nnz(use & fv_ > lim(2));
    n_lo = nnz(use & fv_ < lim(1));
    n_out = n_hi + n_lo;
end
want = tab.viewer_outside_text(n_hi, n_lo, 'faces', role, n_out);
% The short caption draws the range and the count with one colour word
% each ("colours 25-45 ms: N outside (white/black)"); the (i) tooltip and
% Panel details have the full clause
ends = tab.viewer_range_ends(lim);
want_short = sprintf('colours %s%s%s%s: %s', ends{1}, char(8211), ends{2}, suffix, ...
    tab.viewer_outside_text(n_hi, n_lo, 'faces', role, n_out, true));
if strcmp(role, 'projected')
    % the activation names each side as faces,
    % their share of the faces drawn and the time, short and full alike,
    % "17,615 faces (29 %) later than 147.5 ms, white"
    % counted on the faces shown by their own values
    % (the caption's line 1 basis), as the CV panel; it was the faces with a
    % vertex value, which also took faces next to assigned ones
    fdd = getappdata(fig, 'reconstruction_face_data');
    fa_ = double(fdd.projected.values(:));
    if isfield(d, 'offset'), fa_ = fa_ - d.offset; end
    use_a = tab.viewer_faces_shown(fig, fdd.projected) & isfinite(fa_);
    n_hi = nnz(use_a & fa_ > lim(2));
    n_lo = nnz(use_a & fa_ < lim(1));
    n_drawn = nnz(use_a);
    [~, names] = tab.viewer_out_colours(role);
    sides = {};
    % the basis named; "<n> of <N> faces shown"
    if n_hi > 0
        sides{end + 1} = sprintf('%s of %s faces shown (%s) later than %s ms, %s', tab.format_count(n_hi), ...
            tab.format_count(n_drawn), tab.viewer_percent(100 * n_hi / n_drawn), ends{2}, names{2});
    end
    if n_lo > 0
        sides{end + 1} = sprintf('%s of %s faces shown (%s) earlier than %s ms, %s', tab.format_count(n_lo), ...
            tab.format_count(n_drawn), tab.viewer_percent(100 * n_lo / n_drawn), ends{1}, names{1});
    end
    want = strjoin(sides, '; ');
    want_short = sprintf('colours %s%s%s%s: %s', ends{1}, char(8211), ends{2}, suffix, want);
end
if strcmp(role, 'cv') && n_out > 0
    % the faces, their share of the faces shown and
    % what each colour means, short and full alike
    [~, names] = tab.viewer_out_colours(role);
    share = tab.viewer_percent(100 * n_out / nnz(use));
    if n_hi > 0 && n_lo > 0
        want = sprintf('%s faces (%s) outside: %s = faster, %s = slower', tab.format_count(n_out), share, names{2}, names{1});
    elseif n_hi > 0
        want = sprintf('%s faces (%s) above: %s = faster', tab.format_count(n_out), share, names{2});
    else
        want = sprintf('%s faces (%s) below: %s = slower', tab.format_count(n_out), share, names{1});
    end
    want_short = sprintf('colours %s%s%s%s: %s', ends{1}, char(8211), ends{2}, suffix, want);
end
drawn = caption(fig, role);
tip = info_tip(fig, role);
pd = findobj(fig, 'Tag', 'ReconstructionPanelDetails');
pd.Value = 1; pd.Callback(pd, []);
cap_full = caption(fig, role);
pd.Value = 0; pd.Callback(pd, []);
ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' role]);
% With Panel details off the live caption no longer draws the range: it is
% in (i) with the faces outside it (the short
% caption); the drawn caption keeps no "colours" line
drawn_sub = strjoin(cellstr(ax.Subtitle.String), ' ');
ok = own && any(hi | lo) && ~isempty(want) && ~contains(drawn_sub, 'colours ') && contains(drawn, want) && ...
    contains(tip, want) && contains(cap_full, want) && isequal(ax.CLim, lim);
detail = sprintf('%s: vertices %d above %d below, own colours %d, caption wants "%s", tooltip "%s"', role, ...
    nnz(hi), nnz(lo), own, want_short, want);
end


function [bad, n] = overlaps(fig)
% Pairs of visible objects whose rectangles (figure pixels) overlap: the
% uicontrols; each panel's box (Position widened by TightInset, which is
% zero in a figure without a window, hence the labels' own extents); its title,
% caption and visible axis labels (their text extents); the colour bars
% with their tick labels (a margin to the right); the header lines. An
% object is not checked against its own panel, a panel box not against
% another panel box (3-D boxes are larger than what they draw).
fp = getpixelposition(fig);
rects = zeros(0, 4);
names = {};
kinds = {};
owner = {};
for h = findobj(fig, 'Type', 'uicontrol', 'Visible', 'on')'
    rects(end + 1, :) = getpixelposition(h); %#ok<AGROW>
    names{end + 1} = ['uicontrol ' char(h.Tag) ' "' first_string(h) '"']; %#ok<AGROW>
    kinds{end + 1} = 'ui'; owner{end + 1} = ''; %#ok<AGROW>
end
bad = {};
for ax = findobj(fig, 'Type', 'axes')'
    p = getpixelposition(ax);
    u = ax.Units; ax.Units = 'pixels'; ti = ax.TightInset; ax.Units = u;
    rects(end + 1, :) = [p(1) - ti(1), p(2) - ti(2), p(3) + ti(1) + ti(3), p(4) + ti(2) + ti(4)]; %#ok<AGROW>
    names{end + 1} = ['axes ' ax.Tag]; kinds{end + 1} = 'ax'; owner{end + 1} = ax.Tag; %#ok<AGROW>
    % Axes text: a panel shows no rulers, whose tick labels
    % have no extent to measure and ran into the titles; its title and
    % caption are checked against its own axis labels, scale bar text and
    % colour bar ('ttl' against 'lab', 'sb' and 'cb')
    if strcmp(char(ax.Visible), 'on') && startsWith(ax.Tag, 'panel_')
        bad{end + 1} = sprintf('axes %s shows its rulers (tick labels)', ax.Tag); %#ok<AGROW>
    end
    labs = {ax.Title, ax.Subtitle, ax.XLabel, ax.YLabel, ax.ZLabel};
    on = strcmp(char(ax.Visible), 'on');
    vis = {'on', 'on', char(ax.XAxis.Visible), char(ax.YAxis.Visible), char(ax.ZAxis.Visible)};
    for k = 1:numel(labs)
        if ~strcmp(vis{k}, 'on') || (k > 2 && ~on) || isempty(labs{k}.String), continue; end
        u = labs{k}.Units; labs{k}.Units = 'pixels'; e = labs{k}.Extent; labs{k}.Units = u;
        rects(end + 1, :) = [p(1) + e(1), p(2) + e(2), e(3), e(4)]; %#ok<AGROW>
        kind = 'lab';
        if k <= 2, kind = 'ttl'; end
        names{end + 1} = sprintf('label %d of %s', k, ax.Tag); kinds{end + 1} = kind; owner{end + 1} = ax.Tag; %#ok<AGROW>
    end
    for h = findall(ax, 'Tag', 'ReconstructionScaleBarText')'
        u = h.Units; h.Units = 'pixels'; e = h.Extent; h.Units = u;
        rects(end + 1, :) = [p(1) + e(1), p(2) + e(2), e(3), e(4)]; %#ok<AGROW>
        names{end + 1} = ['scale bar of ' ax.Tag]; kinds{end + 1} = 'sb'; owner{end + 1} = ax.Tag; %#ok<AGROW>
    end
    cb = ax.Colorbar;
    if ~isempty(cb) && isgraphics(cb)
        q = cb.Position .* [fp(3) fp(4) fp(3) fp(4)];
        rects(end + 1, :) = [q(1), q(2) - 8, q(3) + 50, q(4) + 16]; %#ok<AGROW>
        names{end + 1} = ['colorbar ' ax.Tag]; kinds{end + 1} = 'cb'; owner{end + 1} = ax.Tag; %#ok<AGROW>
    end
end
for h = findall(fig, 'Type', 'textboxshape')'
    if isempty(char(strjoin(cellstr(h.String), ''))), continue; end
    u = h.Units; h.Units = 'pixels'; rects(end + 1, :) = h.Position; h.Units = u; %#ok<AGROW>
    names{end + 1} = ['annotation ' h.Tag]; kinds{end + 1} = 'an'; owner{end + 1} = ''; %#ok<AGROW>
end
n = size(rects, 1);
for i = 1:n
    for j = i + 1:n
        if strcmp(kinds{i}, 'ax') && strcmp(kinds{j}, 'ax'), continue; end
        % A panel's own parts: only its title and caption against its axis
        % labels, scale bar text and colour bar, and its axis labels
        % against its colour bar
        pair = {kinds{i}, kinds{j}};
        if ~isempty(owner{i}) && strcmp(owner{i}, owner{j}) && ...
                ~((any(strcmp(pair, 'ttl')) && any(ismember(pair, {'lab', 'sb', 'cb'}))) || ...
                (any(strcmp(pair, 'lab')) && any(strcmp(pair, 'cb')))), continue; end
        if any(strcmp(pair, 'ax')) && any(ismember(pair, {'lab', 'ttl', 'sb'})), continue; end
        if any(strcmp({kinds{i}, kinds{j}}, 'ax')) && any(strcmp({kinds{i}, kinds{j}}, {'cb'})), continue; end
        a = rects(i, :); b = rects(j, :);
        ox = min(a(1) + a(3), b(1) + b(3)) - max(a(1), b(1));
        oy = min(a(2) + a(4), b(2) + b(4)) - max(a(2), b(2));
        if ox > 1 && oy > 1
            bad{end + 1} = sprintf('%s %s x %s %s', names{i}, mat2str(round(a)), names{j}, mat2str(round(b))); %#ok<AGROW>
        end
    end
end
end


function ok = slider_fills(fig)
% The slider runs from the Play button to the right end of the video row
pl = findobj(fig, 'Tag', 'ReconstructionVideoPlay');
sl = findobj(fig, 'Tag', 'ReconstructionVideoSlider');
ax = findobj(fig, 'Type', 'axes', 'Tag', 'panel_video');
ok = false;
if ~isscalar(pl) || ~isscalar(sl) || ~isscalar(ax), return; end
p = getpixelposition(pl); s = getpixelposition(sl);
cells = getappdata(fig, 'reconstruction_cells');
fp = getpixelposition(fig);
c = cells(strcmp(getappdata(fig, 'reconstruction_viewer_order'), 'video'), :) .* [fp(3) fp(4) fp(3) fp(4)];
ok = s(1) > p(1) + p(3) && abs((s(1) + s(3)) - (c(1) + c(3) - 6)) < 3 && s(3) > 0.6 * c(3);
end


function s = first_string(h)
% A control's text, or its menu's chosen item
s = h.String;
% a list with nothing selected (the Panel details boxes)
% gives its first line
v = h.Value;
if isempty(v), v = 1; end
if iscell(s), s = s{min(numel(s), max(1, v(1)))}; end
s = char(s);
end


function fig = open_vis(tab, run_id)
% Visualise the run with typed colour ranges
[r_ok, r_err, vis] = tab.resolve_visualisation_context(run_id);
assert(r_ok, r_err);
vis.activation_limits = [25 45];
vis.cv_limits = [0.3 0.9];
[v_ok, v_err, fig] = tab.visualise_artifacts(vis);
assert(v_ok, v_err);
end


function p = cv_path_of(fig)
% The file the CV panel shows (cv_direction.mat is beside it)
panels = getappdata(fig, 'reconstruction_viewer_panels');
k = find(strcmp({panels.role_id}, 'cv'), 1);
p = '';
if ~isempty(k), p = char(panels(k).source_path); end
end


function txt = info_tip(fig, role)
% A panel's (i) tooltip
txt = char(get(findobj(fig, 'Tag', ['ReconstructionPanelInfo_' role]), 'TooltipString'));
end


function txt = caption(fig, role)
% A panel's caption as one line, with its Panel details box when shown;
% with Panel details off, with its (i) tooltip's lines too: the live caption
% keeps only its key number and warning tags, the rest is in (i)
ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' role]);
txt = strjoin(cellstr(ax.Subtitle.String), ' ');
box = findobj(fig, 'Tag', ['ReconstructionPanelDetailsText_' role]);
if isscalar(box) && strcmp(box.Visible, 'on')
    txt = [txt ' ' strjoin(cellstr(box.String), ' ')];
end
pd = findobj(fig, 'Tag', 'ReconstructionPanelDetails');
if isscalar(pd) && pd.Value == 0
    txt = [txt ' ' regexprep(info_tip(fig, role), '\s+', ' ')];
end
end


function txt = all_captions(fig)
% Every panel's caption
ax = findobj(fig, 'Type', 'axes');
txt = strjoin(arrayfun(@(a) strjoin(cellstr(a.Subtitle.String), ' '), ax, 'UniformOutput', false), ' | ');
end


function redo(app)
% Reproject run on the selected COMPLETED run: Redo projection, map and video
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();
end


function [ok, s] = spread_caption(tab, fig, lim)
% L12: the 5-95 % spread of the activation panel's drawn vertex values and
% whether line 2 of its caption says the caution exactly when it is above lim
d = getappdata(fig, 'reconstruction_activation');
v = d.values(isfinite(d.values(:, 1)), 1);
q = prctile(v, [5 95]);
s = q(2) - q(1);
lines = tab.viewer_caption(fig, 'projected');   % line 1, line 2 (the caveats), the range, unwrapped
% in the Results row's words
want = sprintf('WARN over the whole heart, 5%s95 %% activate within %d ms (limit %d ms); scattered late faces, see the per-view activation check', ...
    char(8211), round(s), lim);
if s > lim
    % each caveat on its own line, after line 1
    ok = numel(lines) >= 2 && any(contains(lines(2:end), want)) && ~contains(lines{1}, 'WARN over the whole heart');
else
    ok = ~any(contains(lines, 'WARN over the whole heart'));
end
end


function [ok, detail] = rhythm_everywhere(tab, run_id, want)
% L14: the activation and CV captions (unwrapped, as drawn under Panel
% details) and the window's, activation's and CV panel's saved footers name
% the rhythm want, and no other rhythm
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
c = onCleanup(@() close(fig, 'force'));
texts = {strjoin(tab.viewer_caption(fig, 'projected'), ' | '), strjoin(tab.viewer_caption(fig, 'cv'), ' | '), ...
    char(strjoin(cellstr(tab.viewer_export_footer(fig, '')), ' | ')), ...
    char(strjoin(cellstr(tab.viewer_export_footer(fig, 'projected')), ' | ')), ...
    char(strjoin(cellstr(tab.viewer_export_footer(fig, 'cv')), ' | '))};
% Results: the same words
rep = tab.run_report(run_id);
texts{end + 1} = ['Rhythm: ' rep.rhythm];
named = cellfun(@(t) numel(strfind(t, 'Rhythm: ')), texts);
right = cellfun(@(t) numel(strfind(t, want)), texts);
% The footers and Results always name it; a caption whose panel cannot show
% its values (an unreadable record) may leave it out, never another one
ok = all(named(3:end) >= 1) && isequal(named, right) && (all(named(1:2) >= 1) || contains(want, 'could not be read'));
detail = sprintf('"%s": named %s, as wanted %s', want, mat2str(named), mat2str(right));
if ~ok, detail = [detail ' | ' strjoin(texts, ' || ')]; end
end


function write_text(p, txt)
fid = fopen(p, 'w', 'n', 'UTF-8');
fwrite(fid, unicode2native(txt, 'UTF-8'));
fclose(fid);
end


function c = read_class(p)
c = [];
if isfile(p)
    w = load(p, 'face_class');
    c = double(w.face_class(:));
end
end


function v = read_cdf_values(p)
% The projected values of a .cdf (float32 after its 8 header lines)
fid = fopen(p, 'rb');
c = onCleanup(@() fclose(fid));
for k = 1:8, fgetl(fid); end
v = double(fread(fid, Inf, 'float32'));
end


function s = cb_field(cb, name)
s = '';
if isscalar(cb), s = char(cb.(name)); end
end


function v = cb_value(cb)
v = NaN;
if isscalar(cb), v = cb.Value; end
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
