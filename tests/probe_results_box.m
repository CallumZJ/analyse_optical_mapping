function probe_results_box
%% Probe: the Reconstruction tab's verdict, Results rows, Steps warnings and layout
% Collin Snitchler
% 23.11.2026
% The Results box says the verdict first and one row per finding, every
% number read from the run's record; the defect rule (mesh fit M7
% warned AND a view's mesh coverage below 80 %) is read from the check
% records, never from a step's WARN status. Headless, on a copy of a
% real run.
%   R1  real run: verdict line, rows of at most 78 characters, the
%       coverage, faces, alignment (A2) and mesh (M4, M9) values are the
%       record's
%   R2  the verdict rule: M7 warned and a view below 80 % -> DO NOT USE;
%       (F13): the headline in plain words, and Visualise's title and saved
%       footers start with NOT FOR ANALYSIS
%       FOR ANALYSIS (once in each footer, Panel
%       details on or off, in red; the live header's line 2 starts with it
%       in red); M7 warned alone, or a view below 80 % alone -> not
%       with a near-simultaneous CV record, the
%       Next line says not to report CV from this recording
%   R3  the Steps box with the log hidden still shows the selected step's
%       warnings, one line each, with their values and limits
%   R4  opening the run selects the first step that warned
%   R5  Redo projection: a COMPLETED run whose steps passed with warnings
%       can be redone; the messages for a run that cannot say that
%       warnings are allowed
%   R6  the Step 4 header and the journey strip give the verdict in the
%       same words as the Results headline
%   R7  no two visible controls overlap in any container of the tab, at
%       the default window size and at a narrow width, log shown or not
%   R8  Help still says what results_expected states (July coverage
%       85-95 %, A2 expected to warn); tex_escape escapes run ids
%   R9  a frame check with several ambiguous frames: one pose line with the
%       largest turn and every frame that fits, the one used marked, on
%       one line
%   R10 Results wording from the record: the Sparse
%       row is tagged WARN (its step warned) with the build's own limit
%       (min_points_per_image) and the frame it removed; M9 says "pass";
%       A2 gives the matched error against the model's own (median, p95);
%       the A2 limit says what earlier runs show, as Help; the Next line
%       names the largest turn of the pose; "The defect rule" (Help >
%       Limitations and checks); no "expected on this rig", no "Guide's"
%   R11 Details: the projection check in labelled lines (Camera frame,
%       Outline match, Mesh coverage, Pose uncertainty, Next step), with
%       the record's values, "view" (not "ROI row"), degrees as the
%       degree sign; the scale in 3 significant figures, no "+/-"
%   R12 Steps: tiles 6 and 7 of a run with APDe-MVS say "for the
%       visibility check"; a finished run selected opens Step 4, makes
%       Visualise the one blue button and does not ask for the tools
%       (needed only to run or resume); the settings sit in their "Settings for the
%       next Run, Resume or Redo projection" panel
%   R13 Step 2's calibration tooltip says what (PASSED) and (WARNED) mean,
%       as the calibration record states it; the edge weight tooltip
%       makes no claim that low values make little difference
%   R14 the step log marks the lines of earlier attempts; with the log
%       shown the warnings box is as high as its lines (96-240 px)
%   R15 the activation spread caution: Results'
%       spread equals the 5-95 % percentiles of the values the Visualise
%       panel draws as it opens; a WARN Activation row (live numbers,
%       wrapped at 78, not a warned step) when it is above 80 ms, with or
%       without a pacing cycle, the cycle named when recorded; none at
%       80 ms or below. The warning case needs OM_TEST_SPREAD_DS (a dataset copy
%       whose projection spreads more than 80 ms), else PROBE_SKIP
%   R18 activation nearly simultaneous: a WARN CV row,
%       wrapped at 78, with the words of the CV tab and History (in
%       plain words, the views named when not all are hit), when
%       the CV projection's record has a view whose activation IQR is below
%       10 ms; none at 10 ms or above, none without the record
%       with a CV row, the two are one WARN CV row
%       ("not a conduction velocity: ... Apparent speed median ..."), the
%       CV row's IQR and settings its second line, no plain CV row
%       the row hits the views the CV alert hits, with
%       each view's recorded limit (its size / 3 mm/ms), not a fixed 10 ms
%   R22 a CV row, "median 0.70 m/s (IQR 0.52-0.94), N vertices;
%       image-plane speed (...); Bayly 3 mm, 3x3 median, 9.8 ms; pixel size
%       from calibration <id>", "apparent" under Sinus rhythm, before the
%       WARN CV row (PROBE_SKIP without a CV projection)
%   R23 a Projected row (recording file name, projection
%       time); WARN Recording before it when another recording is loaded,
%       or the same one marked with another rhythm
%   R30 printing the per-view projection records: a synthetic
%       projection record with the fields gives the pacing site, the cycle
%       mismatch WARN, the per-view consistency WARN, the mesh-outside WARN
%       and the steep faces; without the fields nothing is printed
%   R31 one WARN View<k> "geometry suspect" row when
%       two or more of a view's checks fire (activation consistency, mesh outside, camera-image
%       match < 0.75), with its Next words
%   R32 the log window's pose words are the Results
%       pose row's; S12: the Results rows in the fixed order
%   R24 marked Paced, CV values more than 5 %
%       above 1.5 m/s or any above 5 m/s give a WARN CV outlier row; not
%       for Sinus rhythm or Not stated (a synthetic CV projection on the
%       run copy's mesh when the copy has none)
%   R16 per-view labels (Results, Steps, Details, defect rule) follow the
%       regions file's view_order: the value labelled View v is that of
%       the ROI row named view v (View1 = the leftmost region)
%   R17 no lowercase view label (view1..view4) outside a file name or path
%       in the tab's texts, Results, Steps, Details, the defect line, Help
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder and:
%   OM_REDO_DS    folder holding a copy of <stem>.matom with a COMPLETED run
%                 (not the original: the probe copies it once more, under
%                 tempdir, and works on that copy only)
%   OM_REDO_STEM  dataset stem (the .matom name without .matom)
%   OM_REDO_RUN   run id of the COMPLETED run
% Usage: matlab -batch "addpath('<repo>/tests'); probe_results_box" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
results = struct('id', {}, 'ok', {}, 'detail', {});

[root, cleanup] = om_redo_copy('probe_results_box', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
m_text = fileread(fullfile(run_dir, 'manifest.json'));
m = jsondecode(m_text);
gates = jsondecode(fileread(fullfile(run_dir, 'outputs', 'mesh-cleanup-gates.json')));
align = jsondecode(fileread(fullfile(run_dir, 'outputs', 'alignment-gates.json')));
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(root, stem);
assert(ok, err);

%% R1
lines = tab.results_box_lines(run_id, true);
r = tab.run_report(run_id);
fc = m.result.reprojection.frame_check;
% ROI row k is the view the regions file names in view_order{k} (view1 =
% the leftmost region); the per-view values are listed View1 to View4
roi = jsondecode(fileread(fullfile(run_dir, 'inputs', 'roi.json')));
row_view = cellfun(@(v) str2double(regexprep(v, '^view', '')), cellstr(roi.view_order))';
cov_v = nan(1, 4); cov_v(row_view) = fc.om_covered(:)';
iou_v = nan(1, 4); iou_v(row_view) = fc.pose_iou(:)';
cov = arrayfun(@(k) sprintf('%.0f %%', 100 * cov_v(k)), 1:4, 'UniformOutput', false);   % in view order
faces = sprintf('%s of %s mesh faces', tab.format_count(m.result.reprojection.n_assigned), ...
    tab.format_count(m.result.reprojection.n_faces));
a2 = sprintf('%.0f %% of tissue points', 100 * align.gates.A2.measured.matched_fraction);
% each set named, the tissue points with their count
if isfield(align.gates.A2.measured, 'n_tissue_points')
    a2 = sprintf('%.0f %% of the %s tissue points lie within', 100 * align.gates.A2.measured.matched_fraction, ...
        tab.format_count(align.gates.A2.measured.n_tissue_points));
end
% each mesh check names what it counts
m4 = sprintf('M4 normals: %.1f %% of %s camera observations', 100 * gates.gates.M4.measured.agreement, ...
    tab.format_count(gates.gates.M4.measured.n_observations));
cov_label = 'share of the heart in each OM view covered by the mesh';
txt = strjoin(lines, newline);
n_warned = sum(strcmp({m.stages.status}, 'WARNED'));
head_ok = startsWith(lines{1}, sprintf('USABLE, WITH CAUTIONS %s %d steps warned', char(8212), n_warned)) && ...
    endsWith(lines{1}, ['run ' run_id]);
results = add(results, 'R1 real run: verdict line, rows <= 78 characters, values from the record', ...
    head_ok && max(cellfun(@numel, lines)) <= 78 && contains(txt, cov_label) && has_by_view(txt, '', 100 * cov_v, '%.0f %%') && ...
    ~contains(txt, 'mesh coverage by view') && contains(regexprep(txt, '\s+', ' '), m4) && contains(txt, faces) && contains(regexprep(txt, '\s+', ' '), a2) && contains(txt, 'earlier runs usually') && ...
    contains(txt, 'Output files present and unchanged'), ...
    sprintf('longest %d; %s', max(cellfun(@numel, lines)), strjoin(lines, ' | ')));

%% R2
cases = {'WARN', 0.76, true; 'WARN', 0.81, false; 'PASS', 0.76, false; 'PASS', 0.81, false};
got = false(1, size(cases, 1));
words = cell(1, size(cases, 1));
for k = 1:size(cases, 1)
    g2 = gates;
    g2.gates.M7.verdict = cases{k, 1};
    write_json(fullfile(run_dir, 'outputs', 'mesh-cleanup-gates.json'), g2);
    write_text(fullfile(run_dir, 'manifest.json'), regexprep(m_text, '"om_covered":\s*\[[^\]]*\]', ...
        sprintf('"om_covered": [0.86, 0.90, %.2f, 0.97]', cases{k, 2})));
    rk = tab.run_report(run_id);
    lk = tab.results_box_lines(run_id, true);
    parts = [strcmp(rk.verdict, 'DO_NOT_USE'), startsWith(lk{1}, 'NOT FOR ANALYSIS (defect rule, Help > Limitations and checks)'), ...   % one term
        contains(strjoin(lk, ' '), sprintf('View%d covers %.0f %%', row_view(3), 100 * cases{k, 2})) || ...
        contains(strjoin(lk, ' '), sprintf('%.0f %% of the heart in View%d', 100 * cases{k, 2}, row_view(3))), ...   % Q1
        max(cellfun(@numel, lk)) <= 78, ...
        tab.run_not_for_analysis(run_id) == cases{k, 3}];   % the Runs list's label
    if cases{k, 3}
        % the headline in plain words; Visualise's title and
        % every saved footer start with NOT FOR ANALYSIS
        joined = strjoin(strtrim(lk), ' ');
        % one sentence naming the rule, coverage first
        % and M7 last; the rule's repeat line only in Details; the DO NOT
        % USE Next line first
        % one builder, "NOT FOR ANALYSIS (defect rule, Help >
        % Limitations and checks): the mesh covers only 76 % of the heart in
        % View1 (rule: 80 %), and the mesh fit warned (M7)." for Results,
        % Step 4, Visualise, footers and Why?; no pose in it; the Next lines
        % directly under it (before Status)
        want_h = sprintf(['NOT FOR ANALYSIS (defect rule, Help > Limitations and checks): the mesh covers only %.0f %% of the ' ...
            'heart in View%d (rule: 80 %%), and the mesh fit warned (M7).'], 100 * cases{k, 2}, row_view(3));
        k_status = find(startsWith(lk, 'Status '), 1);
        k_next = find(startsWith(lk, 'Next'), 1);
        parts(end + 1) = startsWith(joined, want_h) && strcmp(rk.headline, want_h) && strcmp(rk.verdict_words, want_h) && ...
            ~contains(rk.headline, 'OM pose') && ~contains(joined, 'defect rule applies') && ...
            contains(joined, rabbit_reconstruction_tab.DO_NOT_USE_NEXT) && ...
            ~isempty(k_next) && ~isempty(k_status) && k_next < k_status && ~contains(joined, 'DO NOT USE');   % one term
        % with the near-simultaneous rule firing
        % (sinus), the Next line sends activation to the 2-D tab and CV to
        % a paced recording
        cv_path2 = fullfile(run_dir, 'outputs', 'reprojection', 'cv_reprojection_manifest.json');
        had_cv2 = exist(cv_path2, 'file') == 2;
        if had_cv2, cv_text2 = fileread(cv_path2); end
        write_json(cv_path2, struct('schema', 'rabbit_rhythm_reproject.manifest.v1', ...
            'activation_spread', struct('views', {{'View1', 'View2', 'View3', 'View4'}}, 'iqr_ms', [4.8 5.2 4.2 4.9], ...
            'warn_below_ms', [7.4 9.5 8.1 8.0], 'basis', 'probe')));
        rk4 = tab.run_report(run_id);
        if had_cv2, write_text(cv_path2, cv_text2); else, delete(cv_path2); end
        parts(end + 1) = contains(rk4.next, rabbit_reconstruction_tab.DO_NOT_USE_NEXT(true)) && ...
            endsWith(rabbit_reconstruction_tab.DO_NOT_USE_NEXT(true), ['Until then, report activation from the 2-D ' ...
            'Activation Map tab. Do not report CV from this recording (near-simultaneous activation); use a paced recording.']) && ...
            ~contains(rk4.next, 'report activation and CV');
        [v_ok, ~, vf] = tab.visualise_artifacts(run_id);
        if v_ok
            foot = tab.viewer_export_footer(vf, 'cv');
            % coverage, then pose, then M7, as the Results headline
            % Q1: the window title and the footers start with the one sentence
            parts(end + 1) = startsWith(vf.Name, want_h) && startsWith(foot{1}, want_h) && ...
                startsWith(strjoin(tab.viewer_export_footer(vf, ''), ' '), want_h);
            % once in each saved footer, with Panel
            % details on (the caption block first) and off
            pd = findobj(vf, 'Tag', 'ReconstructionPanelDetails');
            once = @(f) numel(strfind(strjoin(f, ' '), 'NOT FOR ANALYSIS')) == 1 && startsWith(f{1}, 'NOT FOR ANALYSIS (');
            once_off = once(foot) && once(tab.viewer_export_footer(vf, ''));
            once_on = false;
            if isscalar(pd)
                set(pd, 'Value', 1);
                if ~isempty(pd.Callback), pd.Callback(pd, []); end
                once_on = once(tab.viewer_export_footer(vf, 'cv')) && once(tab.viewer_export_footer(vf, '')) && ...
                    numel(tab.viewer_export_footer(vf, 'cv')) > 1;
                set(pd, 'Value', 0);
                if ~isempty(pd.Callback), pd.Callback(pd, []); end
            end
            parts(end + 1) = once_off && once_on;
            % the live header's line 2 starts with it,
            % in red, and a saved footer draws it in red
            note = findall(vf, 'Tag', 'ReconstructionOrientationNote');
            red_png = [tempname '.png'];
            imwrite(255 * ones(60, 400, 3, 'uint8'), red_png);
            om_export.append_footer(red_png, foot);
            im = double(imread(red_png));
            delete(red_png);
            n_red = nnz(im(:, :, 1) > 150 & im(:, :, 2) < 90 & im(:, :, 3) < 90);
            parts(end + 1) = isscalar(note) && startsWith(char(note.String), 'NOT FOR ANALYSIS (') && ...
                isequal(note.Color, [0.8 0 0]) && n_red > 50;
            % Q1: "wider end on top" on header line 1 (with Panel details off
            % too), not on line 2
            hd = findall(vf, 'Tag', 'ReconstructionHeader');
            ori = getappdata(vf, 'reconstruction_view_orientation');
            if isstruct(ori) && strcmp(ori.source, 'cameras') && ~isempty(ori.wider_end_up)
                parts(end + 1) = contains(char(hd.String), 'wider end on top: ') && ~contains(char(note.String), 'Wider end');
            end
            close(vf, 'force');
        else
            parts(end + 1) = false;
        end
    end
    got(k) = all(parts);
    words{k} = sprintf('M7 %s, ROI row 3 (view %d) %.2f: %s %s (%s)', cases{k, 1}, row_view(3), cases{k, 2}, ...
        rk.verdict, mat2str(parts), ...
        rk.defect.line);
end
% Back to the run as recorded
write_json(fullfile(run_dir, 'outputs', 'mesh-cleanup-gates.json'), gates);
write_text(fullfile(run_dir, 'manifest.json'), m_text);
results = add(results, 'R2 DO NOT USE only for M7 warned and a view below 80 %', isequal(got, [cases{:, 3}]), ...
    strjoin(words, ' | '));

%% R3, R4, R6
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root, stem);
recording = rabbit_reconstruction_tab.recording_stem(root, stem);
app.file_info.path = root;
app.file_info.name = [recording '.fits'];
app.file_info.type = '.fits';
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
app.recon.ReconstructionRunListValueChanged();
first_warned = m.stages(find(strcmp({m.stages.status}, 'WARNED'), 1)).name;
sel = app.recon.ReconstructionStageList.Value;
results = add(results, 'R4 opening the run selects the first step that warned', strcmp(sel, first_warned), ...
    sprintf('selected %s, first warned %s', sel, first_warned));
% Each warned step, log hidden: its warning lines are shown with values and limits
stages = app.recon.ReconstructionStageList.ItemsData;
ok3 = ~app.recon.ReconstructionShowLogCheckBox.Value && strcmp(char(app.recon.ReconstructionLogViewer.Visible), 'off') && ...
    strcmp(char(app.recon.StepWarningsText.Visible), 'on');
shown = {};
for st = {'alignment', 'mesh_cleanup', 'reprojection'}
    k = find(strcmp(stages, st{1}), 1);
    b = findall(app.recon.StageRowsGrid, 'Type', 'uibutton');
    b = b(arrayfun(@(x) x.Layout.Row, b) == k);
    feval(b.ButtonPushedFcn, b, []);
    w = app.recon.StepWarningsText.Value;
    shown{end + 1} = strjoin(w, ' / '); %#ok<AGROW>
    ok3 = ok3 && numel(w) >= 2 && startsWith(w{2}, 'WARN');
end
% (M4's limit as "pass >= 99 %", the coverage label)
ok3 = ok3 && contains(shown{1}, a2) && contains(shown{1}, 'earlier runs usually') && ...
    contains(shown{2}, m4) && contains(shown{2}, sprintf('pass %s 99 %%', char(8805))) && ...
    contains(shown{3}, cov_label) && has_by_view(shown{3}, '', 100 * cov_v, '%.0f %%') && ...
    contains(shown{3}, 'warn < 80 %');
results = add(results, 'R3 log hidden: the selected step''s warnings with values and limits', ok3, strjoin(shown, ' || '));
% R6: the Step 4 header and the strip in the verdict's words
hdr = app.recon.StepHeader4.Text;
strip = app.recon.JourneyStripLabel.Text;
results = add(results, 'R6 Step 4 header and strip give the verdict in the Results words', ...
    contains(lower(r.headline), 'usable, with cautions') && ...
    contains(hdr, r.verdict_words) && contains(strip, '4 Run: usable, with cautions') && ...
    startsWith(strip, ['Run ' run_id ' | 1 Data: ']) && ...
    startsWith(app.recon.ReconstructionResultsText.Value{1}, r.headline), sprintf('%s | %s | %s', hdr, strip, r.verdict_words));
% under the defect rule the Step 4 tooltip says the
% verdict sentence once (the header text), not again as the rule's line
g6 = gates;
g6.gates.M7.verdict = 'WARN';
write_json(fullfile(run_dir, 'outputs', 'mesh-cleanup-gates.json'), g6);
write_text(fullfile(run_dir, 'manifest.json'), regexprep(m_text, '"om_covered":\s*\[[^\]]*\]', ...
    '"om_covered": [0.86, 0.90, 0.76, 0.97]'));
app.recon.reconstruction_update_journey();
tt6 = strjoin(cellstr(app.recon.StepHeader4.Tooltip), ' ');
hd6 = app.recon.StepHeader4.Text;
write_json(fullfile(run_dir, 'outputs', 'mesh-cleanup-gates.json'), gates);
write_text(fullfile(run_dir, 'manifest.json'), m_text);
app.recon.reconstruction_update_journey();
results = add(results, 'R6b Step 4 tooltip under the defect rule: the verdict sentence once (Q1)', ...
    contains(hd6, 'NOT FOR ANALYSIS (') && numel(strfind(tt6, 'NOT FOR ANALYSIS (')) == 1, tt6);

%% R5
[can, why] = tab.can_redo_reprojection(run_id);
write_text(fullfile(run_dir, 'manifest.json'), regexprep(m_text, ...
    '("name":\s*"stereo_fusion",\s*"status":\s*)"PASSED"', '$1"FAILED"', 'once'));
[can5, why5] = tab.can_redo_reprojection(run_id);
app.recon.reconstruction_update_enablement();
g5 = app.recon.reconstruction_gate_state();
write_text(fullfile(run_dir, 'manifest.json'), m_text);
results = add(results, 'R5 Redo projection allows WARN steps and says so when refused', ...
    can && n_warned > 0 && ~can5 && contains(why5, 'passed with warnings') && ...
    contains(g5.reproject_tip, 'passed with warnings') && ...
    strcmp(app.recon.ReconstructionReprojectButton.Text, 'Redo projection...'), ...
    sprintf('%d %s | %d %s | %s', can, why, can5, why5, g5.reproject_tip));

%% R7
app.recon.reconstruction_update_enablement();
app.recon.ReconstructionRunListValueChanged();
fig = app.opticalmappingUIFigure;
tg = app.TabGroup;
tg.Visible = 'on';
tg.SelectedTab = app.recon.ReconstructionTab;
app.recon.reconstruction_set_accordion(4, false);
default_size = fig.Position(3:4);
detail = {};
ok7 = true;
for size_k = {default_size, [1000 default_size(2)]}
    for show_log = [false true]
        app.recon.ReconstructionShowLogCheckBox.Value = show_log;
        app.recon.reconstruction_show_log();
        fig.Position(3:4) = size_k{1};
        tg.Position = [tg.Position(1), 1, size_k{1}(1) - 2 * tg.Position(1), size_k{1}(2) - 2];
        drawnow;
        pause(1);
        exportapp(fig, [tempname '.png']);   % lays the window out, as it is drawn
        rep = ui_control_overlaps(app.recon.ReconstructionTab);
        laid_out = app.recon.ReconstructionRunButton.Position(3) > 40;
        ok7 = ok7 && isempty(rep) && laid_out;
        names = arrayfun(@(e) sprintf('%s: %s x %s', e.container, e.a, e.b), rep, 'UniformOutput', false);
        detail{end + 1} = sprintf('%dx%d log %d: %d overlaps %s', size_k{1}, show_log, numel(rep), ...
            strjoin(names, '; ')); %#ok<AGROW>
    end
end
results = add(results, 'R7 no overlapping controls at the default and a narrow width', ok7, strjoin(detail, ' | '));

%% R8
cat = reconstruction_help_content();
lim = strjoin(cat.topics(strcmp({cat.topics.id}, 'limitations-and-resources')).body, ' ');
E = rabbit_reconstruction_tab.results_expected();
results = add(results, 'R8 Help states the July values; run ids are tex-escaped', ...
    contains(lim, sprintf('%d%s%d %% per OM view', E.coverage_usual(1), char(8211), E.coverage_usual(2))) && ...
    contains(lim, sprintf('(A2) WARN (%d-%d %%)', E.a2_usual)) && ...
    strcmp(rabbit_reconstruction_tab.tex_escape('20261120T120627_6d6798db'), '20261120T120627\_6d6798db'), ...
    rabbit_reconstruction_tab.tex_escape(run_id));

%% R9
% Two frames that fit as well as the chosen one, each with its own turn:
% one value (the largest turn) and the frame list, never a recycled format
write_text(fullfile(run_dir, 'manifest.json'), regexprep(regexprep(m_text, ...
    '"ambiguous_frames":\s*[^,\r\n]*', '"ambiguous_frames": [37, 67]'), ...
    '"ambiguous_turn_deg":\s*[^,\r\n]*', '"ambiguous_turn_deg": [18.4, 13.1]'));
l9 = tab.results_box_lines(run_id, true);
write_text(fullfile(run_dir, 'manifest.json'), m_text);
t9 = strjoin(l9, ' ');
used = fc.frame(1);
% "OM pose: frame 1 used (earliest within 0.05 of the
% best match, frame 3); frames 37 (18°) and 67 (13°) fit as well" (each
% frame with its turn, joined to it by a non-breaking space)
want9 = sprintf('OM pose: frame %d used', used);
% "frames 37 and 67 fit as well but are turned 18° and
% 13° from frame 1"
want9b = sprintf('frames 37 and 67 fit as well but are turned 18%s and 13%s from frame %d', char(176), char(176), used);
% for a run in mm, the turn as distances on the
% heart, deg2rad(turn) x the median and 95th percentile of the projected
% mesh's vertex distances from its centroid, under the pose row and in Next
mesh9 = rabbit_rhythm_reproject.read_ply_mesh(fullfile(run_dir, 'outputs', 'mesh-cleanup.ply'));
rad9 = sqrt(sum((double(mesh9.pts) - mean(double(mesh9.pts), 1)) .^ 2, 2));
mm9 = deg2rad(18.4) * [median(rad9), prctile(rad9, 95)];
pos9 = sprintf('on the heart by about %s mm (up to %s mm)', fmt_mm(mm9(1)), fmt_mm(mm9(2)));
in_mm9 = strcmp(tab.run_units(run_dir), 'mm');
flat9 = regexprep(strrep(t9, char(160), ' '), '\s+', ' ');
mm_ok9 = ~in_mm9 || (contains(flat9, sprintf('directions uncertain by up to 18%s; positions %s', char(176), pos9)) && ...
    contains(flat9, sprintf('treat directions as uncertain by up to 18%s, and positions %s.', char(176), pos9)));
results = add(results, 'R9 several ambiguous frames: the largest turn and the frame list, once; in mm on the heart (F15)', ...
    contains(flat9, want9) && contains(flat9, want9b) && numel(strfind(t9, 'OM pose:')) == 1 && ...
    ~contains(t9, 'e+0') && in_mm9 && mm_ok9 && max(cellfun(@numel, l9)) <= 78, ...
    sprintf('mm %d (median %.2f mm, p95 %.2f mm): %s', in_mm9, mm9, t9));

%% R10
lines = tab.results_box_lines(run_id, true);
txt = strjoin(lines, newline);
summ = jsondecode(fileread(fullfile(run_dir, 'stages', 'sparse_build', 'model_summary.json')));
sp = m.stages(strcmp({m.stages.name}, 'sparse_build'));
n_rm = numel(cellstr(summ.posed_only_removed));
n_all = numel(cellstr(summ.images_removed));
sparse_row = lines(contains(lines, 'Sparse'));
sparse_ok = numel(sparse_row) == 1 && startsWith(sparse_row{1}, 'WARN') == strcmp(sp(end).status, 'WARNED') && ...
    contains(strjoin(lines, ' '), sprintf('< %d points', summ.min_points_per_image)) && ...
    contains(strjoin(lines, ' '), sprintf('(%d images)', n_all)) && n_rm >= 1;
a2m = align.gates.A2.measured;
a2_err = sprintf('error median %.2f px (model %.2f), p95 %.2f px (%.2f)', a2m.median_px, a2m.own_median_px, ...
    a2m.p95_px, a2m.own_p95_px);
E = rabbit_reconstruction_tab.results_expected();
flat = regexprep(txt, '\s+', ' ');
fc_turn = max(double(fc.ambiguous_turn_deg(:)));
% (M9 names its denominator, the limit below it)
ok10 = sparse_ok && contains(flat, 'M9 direct views') && ...
    ~isempty(regexp(flat, ['M9 direct views: [\d.]+ % of [\d,]+ camera observations are seen face-on enough to colour it \(DIRECT\) pass ' ...   % Q8
    char(8805) ' [\d.]+ %'], 'once')) && ...
    contains(flat, a2_err) && contains(flat, sprintf('earlier runs usually %d%s%d %%', E.a2_usual(1), char(8211), E.a2_usual(2))) && ...
    contains(flat, sprintf('earlier runs usually %d%s%d %%', E.coverage_usual(1), char(8211), E.coverage_usual(2))) && ...
    contains(flat, 'type it in "OM pose frame" (Step 2) and press Redo projection') && ...
    contains(flat, sprintf('uncertain by up to %.0f%s', fc_turn, char(176))) && ~contains(flat, 'load the recording') && ...
    contains(flat, 'The defect rule') && ~contains(flat, 'replication guide') && ~contains(flat, 'Guide''s') && ...
    ~contains(flat, 'expected on this rig') && ~contains(flat, 'July data') && max(cellfun(@numel, lines)) <= 78;
results = add(results, 'R10 Results: Sparse WARN with its limit, M9 pass, A2 errors, earlier runs, Next, defect rule', ...
    ok10, strjoin(lines, ' | '));

%% R11
det = app.recon.reconstruction_results_details(run_id);
dt = strjoin(det, newline);
labels = {'Camera frame:', 'Camera-image outline match', 'Mesh coverage', 'Pose uncertainty:', 'Next step:'};
% Details prints an outline match within 0.01 of a limit to 3 decimals, as
% Results
iou_txt = arrayfun(@(k) sprintf(['View%d ' iou_fmt(iou_v(k))], k, iou_v(k)), 1:4, 'UniformOutput', false);
cov_txt = arrayfun(@(k) sprintf('View%d %.0f %%', k, 100 * cov_v(k)), 1:4, 'UniformOutput', false);
ms = jsondecode(fileread(fullfile(run_dir, 'stages', 'sparse_build', 'metric_scale.json')));
ok11 = all(cellfun(@(c) contains(dt, c), labels)) && contains(dt, strjoin(iou_txt, ', ')) && ...
    contains(dt, strjoin(cov_txt, ', ')) && contains(dt, sprintf('Camera frame: %d,', fc.frame)) && ...
    ~contains(dt, 'ROI row') && ~contains(dt, ' deg') && ~contains(dt, '>=') && ~contains(dt, '+/-') && ...
    contains(dt, sprintf('scale %.3g mm per reconstruction unit (COLMAP''s arbitrary unit)', ms.scale_mm_per_unit));
results = add(results, 'R11 Details: labelled projection lines, view order, degree sign, 3 significant figures', ok11, ...
    strjoin(det, ' | '));

%% R12
stages = app.recon.ReconstructionStageList.ItemsData;
items = app.recon.ReconstructionStageList.Items;
apd = any(strcmp(stages, 'apde_run'));
k6 = find(strcmp(stages, 'patch_match_stereo'), 1);
k7 = find(strcmp(stages, 'stereo_fusion'), 1);
tiles_ok = ~apd || (contains(items{k6}, 'Depth maps (COLMAP, for the visibility check)') && ...
    contains(items{k7}, 'Dense cloud (COLMAP fusion, for the visibility check)'));
app.recon.reconstruction_set_accordion(0, false);
app.recon.ReconstructionRunListValueChanged();
run_btn = app.recon.ReconstructionRunButton;
vis_btn = app.recon.ReconstructionVisualiseButton;
blue = app.recon.primary_colour();
next_panel = findall(app.recon.ReconstructionTab, 'Tag', 'ReconstructionNextRunPanel');
ok12 = tiles_ok && app.recon.reconstruction_step_open() == 4 && ~isequal(run_btn.BackgroundColor, blue) && ...
    isequal(vis_btn.BackgroundColor, blue) && ~contains(app.recon.StepHeader3.Text, 'press Check tools') && ...
    ~contains(app.recon.StepHeader3.Text, 'set the COLMAP path') && ~contains(app.recon.StepHeader3.Text, 'set all four') && ...
    isscalar(next_panel) && strcmp(next_panel.Title, 'Settings for the next Run, Resume or Redo projection') && ...
    isequal(ancestor(run_btn, 'uipanel'), next_panel) && isequal(ancestor(app.recon.ReconstructionEdgeWeightField, 'uipanel'), next_panel);
results = add(results, 'R12 APDe tiles name the visibility check; a finished run opens Step 4, Visualise the one primary button', ...
    ok12, sprintf('apd %d: %s / %s | step %d | run %s | tools "%s"', apd, items{k6}, items{k7}, ...
    app.recon.reconstruction_step_open(), mat2str(run_btn.BackgroundColor), app.recon.StepHeader3.Text));

%% R13
cal_tip = strjoin(cellstr(app.recon.ReconstructionCalibrationDropDown.Tooltip), ' ');
edge_tip = strjoin(cellstr(app.recon.ReconstructionEdgeWeightField.Tooltip), ' ');
results = add(results, 'R13 calibration tooltip explains (PASSED) and (WARNED); edge weight tooltip without the 0.5 claim', ...
    contains(cal_tip, '(PASSED)') && contains(cal_tip, '(WARNED)') && contains(cal_tip, 'held-out') && ...
    ~contains(cal_tip, 'that passed its checks') && ~contains(edge_tip, 'little difference'), [cal_tip ' || ' edge_tip]);
% the calibration drop-down's items are short
% ("...14h-12m-15s_03 (WARNED)"), from the time stamp on, the id as data;
% the Step 2 path fields give the full path in the tooltip
app.recon.reconstruction_refresh_calibrations();
dd14 = app.recon.ReconstructionCalibrationDropDown;
L14 = tab.calibration_list();
L14 = L14([L14.metric_allowed]);
short_ok = numel(dd14.Items) == numel(L14) + 1;
% shorter still, "..._03 (WARNED)", when no two read the same
tiny14 = cellfun(@(s) regexp(s, '_\d+(\s.*)?$', 'match', 'once'), {L14.label}, 'UniformOutput', false);
use_tiny = numel(unique(tiny14)) == numel(tiny14) && ~any(cellfun(@isempty, tiny14));
for k = 1:numel(L14)
    tk = regexp(L14(k).label, '\d+h-\d+m-\d+s\S*.*$', 'match', 'once');
    if use_tiny, tk = tiny14{k}; end
    short_ok = short_ok && strcmp(dd14.ItemsData{k + 1}, L14(k).id) && ...
        (isempty(tk) || strcmp(dd14.Items{k + 1}, [char(8230) tk]));
end
app.recon.reconstruction_update_enablement();
img_tip = cellstr(app.recon.ReconstructionImagesField.Tooltip);
v14 = strtrim(app.recon.ReconstructionImagesField.Value);
path_ok = isempty(v14) || strcmp(img_tip{end}, ['Full path: ' rabbit_reconstruction_tab.display_path(v14)]);
results = add(results, 'R14 short calibration names in the drop-down; Step 2 path fields'' full path in the tooltip', ...
    short_ok && path_ok, sprintf('%s || %s', strjoin(dd14.Items, ' | '), strjoin(img_tip, ' / ')));

%% R14
log_in = {'Activity - run x', 'Log: logs/reprojection.log', '-- Existing log tail (last 200 lines; file unchanged) --', ...
    '[2026-11-20T13:09:08] stage reprojection FAILED: The frame could not be chosen', ...
    '[2026-11-20T13:30:00] started again', '[2026-11-20T13:30:53] stage reprojection WARNED'};
log_out = app.recon.reconstruction_mark_earlier_attempts(log_in, 'reprojection');
mark_ok = startsWith(log_out{4}, 'earlier attempt (failed): [2026-11-20T13:09:08] stage reprojection FAILED') && ...
    isequal(log_out([1:3 5:6]), log_in([1:3 5:6]));
app.recon.ReconstructionShowLogCheckBox.Value = true;
k = find(strcmp(stages, 'reprojection'), 1);
b = findall(app.recon.StageRowsGrid, 'Type', 'uibutton');
b = b(arrayfun(@(x) x.Layout.Row, b) == k);
feval(b.ButtonPushedFcn, b, []);
h_w = app.recon.GridLayoutR2.RowHeight{3};
n_w = numel(app.recon.StepWarningsText.Value);
app.recon.ReconstructionShowLogCheckBox.Value = false;
app.recon.reconstruction_show_log();
results = add(results, 'R14 earlier attempts marked in the step log; the warnings box keeps its lines with the log shown', ...
    mark_ok && isnumeric(h_w) && h_w >= min(240, 16 * n_w + 12) && h_w <= 240, ...
    sprintf('%s | box %s px for %d lines', strjoin(log_out, ' / '), num2str(h_w), n_w));

%% R16
% Every per-view label goes through the run's row-to-view mapping: the
% value labelled view v is the value of the ROI row the regions file names
% view v (Results coverage and outline match, Steps, Details, defect rule)
lines16 = tab.results_box_lines(run_id, true);
flat16 = regexprep(strjoin(lines16, ' '), '\s+', ' ');
% (the coverage label, the values on their own line)
res_ok = contains(flat16, cov_label) && has_by_view(flat16, '', 100 * cov_v, '%.0f %%') && ...
    (all(fc.pose_iou >= 0.85) || has_by_view(flat16, 'outline match ', iou_v, 'iou'));   % 3 decimals near a limit
det16 = strjoin(app.recon.reconstruction_results_details(run_id), newline);
det_ok = contains(det16, ['Camera-image outline match (1 = identical): ' strjoin(iou_txt, ', ')]) && ...
    contains(det16, ['Mesh coverage (share of the heart in each OM view): ' strjoin(cov_txt, ', ')]);
r16 = tab.run_report(run_id);
def_ok = isequal(r16.defect.cover, cov_v) && isequal(r16.defect.low_views, find(cov_v < r16.defect.limit));
steps16 = tab.step_warning_lines(run_id, 'reprojection');
step_ok = any(cellfun(@(t) has_by_view(t, '', 100 * cov_v, '%.0f %%'), steps16));
map_ok = ~isequal(row_view, 1:4);   % not the identity here, so the check can tell
results = add(results, 'R16 per-view labels follow the run''s ROI row to view mapping (View1 = leftmost region)', ...
    res_ok && det_ok && def_ok && step_ok && map_ok, sprintf('rows -> views %s; results %d details %d defect %d steps %d | %s', ...
    mat2str(row_view), res_ok, det_ok, def_ok, step_ok, strjoin(steps16, ' / ')));

%% R17
% No lowercase view label (view1..view4) outside a file name or path in
% what the tab shows: Results, Steps, Details, the tab's labels, items and
% tooltips, the Why? text and Help
shown17 = [lines16, steps16, {det16}, {r16.defect.line}];
for c = findall(app.recon.ReconstructionTab)'
    for f = {'Text', 'Tooltip', 'Items', 'Value', 'Title', 'Placeholder'}
        if isprop(c, f{1})
            v = c.(f{1});
            if ischar(v) || isstring(v) || iscell(v), shown17{end + 1} = v; end %#ok<AGROW>
        end
    end
end
hc = reconstruction_help_content();
for k = 1:numel(hc.topics)
    shown17{end + 1} = hc.topics(k).body; %#ok<AGROW>
    if isfield(hc.topics, 'title'), shown17{end + 1} = hc.topics(k).title; end %#ok<AGROW>
end
hits17 = lowercase_view_labels(shown17);
results = add(results, 'R17 no lowercase view1..view4 label in the tab''s texts, Results, Details or Help', ...
    isempty(hits17), strjoin(hits17, ' || '));

%% R15
% The activation spread caution: a WARN Activation row
% when the 5-95 % spread of the values the Visualise activation panel
% draws as it opens is above SPREAD_WARN_MS (80 ms), with or without a
% pacing cycle; a recorded cycle is named in the row. The Results spread
% is checked against the panel's own drawn values (the same basis), on
% this run's real projection; with OM_TEST_SPREAD_DS (a copy of a dataset whose
% projection spreads more than 80 ms) the warning case too.
lim15 = rabbit_reconstruction_tab.SPREAD_WARN_MS;
[ok15, det15] = spread_case(tab, run_id, run_dir, lim15, 'this run');
h2_root = '';
if ~isempty(getenv('OM_TEST_SPREAD_DS'))
    % A copy: spread_case writes a cycle into the projection's record (and puts it back)
    [h2_root, h2_clean] = om_redo_copy('probe_results_box', 'OM_TEST_SPREAD_DS', stem, run_id); %#ok<ASGLU>
end
if ~isempty(h2_root)
    tab2 = rabbit_reconstruction_tab();
    [ok2, err2] = tab2.load_state(h2_root, stem);
    assert(ok2, err2);
    h2_run = fullfile(h2_root, [stem '.matom'], 'reconstruction', 'runs', run_id);
    [okw, detw] = spread_case(tab2, run_id, h2_run, lim15, 'OM_TEST_SPREAD_DS');
    ok15 = ok15 && okw;
    det15 = [det15 ' || ' detw];
else
    fprintf('PROBE_SKIP R15 warning case: OM_TEST_SPREAD_DS not set\n');
end
results = add(results, ['R15 activation spread: the panel''s drawn values (opening state); WARN above 80 ms ' ...
    'with or without a cycle, the cycle named when recorded; wording, wrap, not a step'], ok15, det15);

%% R18
% The near-simultaneous activation warning from the CV projection's record
cv_path = fullfile(run_dir, 'outputs', 'reprojection', 'cv_reprojection_manifest.json');
had_cv = exist(cv_path, 'file') == 2;
if had_cv, cv_text = fileread(cv_path); end
% in plain words, the views named when not all are
% hit, the ms range over the hit views' IQRs
want18 = sprintf(['WARN CV  In View2 and View3, most of each view activates at almost the same moment (middle ' ...
    'half of pixels within 5%s6 ms, under 10 ms). Speeds from such small time differences are not true ' ...
    'conduction velocities %s typical of sinus rhythm. Do not report them as CV; use a paced recording.'], ...
    char(8211), char(8212));
cvm = struct('schema', 'rabbit_rhythm_reproject.manifest.v1', 'quantity', 'conduction velocity speed', ...
    'activation_spread', struct('views', {{'View1', 'View2', 'View3', 'View4'}}, 'iqr_ms', [18.7 5.2 6.4 22.3], ...
    'warn_below_ms', 10, 'basis', 'probe'));
write_json(cv_path, cvm);
l18 = tab.results_box_lines(run_id, true);
row18 = joined_row(l18, 'WARN CV');
% with a CV row, one WARN CV row says it is not a
% conduction velocity, with the CV row's median; the rest of the CV row is
% its second line, and no plain CV row is left
med18 = median(tab.report_cv_values(run_dir));
plain18 = any(startsWith(l18, '     CV '));
if isfinite(med18)
    want18 = sprintf(['WARN CV  not a conduction velocity in View2, View3: most of each of these views activates at ' ...
        'almost the same moment (the middle half of pixels within 5%s6 ms, under 10 ms). Speed median %.2f m/s over ' ...
        'all views; do not report it as CV for View2, View3. Use a paced recording. IQR '], char(8211), med18);
    cvm.activation_spread.iqr_ms = [4.8 5.2 4.2 4.9];
    write_json(cv_path, cvm);
    all18 = joined_row(tab.results_box_lines(run_id, true), 'WARN CV');
    want18_all = sprintf(['WARN CV  not a conduction velocity: most of each view activates at almost the same moment ' ...
        '(within each view, the middle half of pixels within 4%s5 ms, under 10 ms). Apparent speed median %.2f m/s; ' ...
        'do not report it as CV. Use a paced recording. IQR '], char(8211), med18);
    row18_ok = startsWith(row18, want18) && startsWith(all18, want18_all) && ~plain18;
else
    row18_ok = strcmp(row18, want18);
end
% The merged row's words on their own, without a CV projection in the copy
u18a = rabbit_reconstruction_tab.simultaneous_cv_row(struct('activation_spread', struct('views', ...
    {{'View1', 'View2', 'View3', 'View4'}}, 'iqr_ms', [4.8 5.2 4.2 4.9])), 1.79);
u18b = rabbit_reconstruction_tab.simultaneous_cv_row(struct('activation_spread', struct('views', ...
    {{'View1', 'View2', 'View3', 'View4'}}, 'iqr_ms', [18.7 5.2 6.4 22.3])), 0.7);
u18c = rabbit_reconstruction_tab.simultaneous_cv_row(struct('activation_spread', struct('views', ...
    {{'View1', 'View2', 'View3', 'View4'}}, 'iqr_ms', [18.7 10 14.3 22.3])), 0.7);
row18_ok = row18_ok && strcmp(u18a, sprintf(['not a conduction velocity: most of each view activates at almost the ' ...
    'same moment (within each view, the middle half of pixels within 4%s5 ms, under 10 ms). Apparent speed median ' ...
    '1.79 m/s; do not report it as CV. Use a paced recording.'], char(8211))) && ...
    startsWith(u18b, 'not a conduction velocity in View2, View3: ') && isempty(u18c);
% with each view's limit recorded (its size / 3 mm/ms), the
% row hits the views the CV alert hits, not those below a fixed 10 ms: here
% the alert names View2 and View3 only (the fixed rule would take all four),
% and View2 at 12 ms under its 13 ms limit (the fixed rule would take none)
rec18d = struct('activation_spread', struct('views', {{'View1', 'View2', 'View3', 'View4'}}, ...
    'iqr_ms', [4.8 5.2 4.2 4.9], 'warn_below_ms', [3.4 5.5 4.6 4.0]));
rec18e = struct('activation_spread', struct('views', {{'View1', 'View2', 'View3', 'View4'}}, ...
    'iqr_ms', [18.7 12 14.3 22.3], 'warn_below_ms', [15 13 13 20]));
u18d = rabbit_reconstruction_tab.simultaneous_cv_row(rec18d, 1.79);
u18e = rabbit_reconstruction_tab.simultaneous_cv_row(rec18e, 0.7);
% in plain words, "a real wave at 1.5 m/s would take ..."
u18f = rabbit_reconstruction_tab.simultaneous_cv_row(struct('activation_spread', struct('views', ...
    {{'View1', 'View2', 'View3', 'View4'}}, 'iqr_ms', [4.2 4.6 5.1 4.4], 'warn_below_ms', [9.6 8.8 9.3 7.5])), 1.79);
row18_ok = row18_ok && strcmp(u18f, sprintf(['not a conduction velocity: in each view, the middle half of the ' ...
    'pixels activate within 4%s5 ms; a real wave at 1.5 m/s would take 7.5%s9.6 ms. Apparent speed median ' ...
    '1.79 m/s; do not report it as CV. Use a paced recording.'], char(8211), char(8211)));
row18_ok = row18_ok && strcmp(u18d, sprintf(['not a conduction velocity in View2, View3: in each of these views, ' ...
    'the middle half of the pixels activate within 4%s5 ms; a real wave at 1.5 m/s would take 4.6%s5.5 ms. ' ...
    'Speed median 1.79 m/s over all views; do not report it as CV for View2, View3. ' ...
    'Use a paced recording.'], char(8211), char(8211))) && ...
    startsWith(rabbit_reconstruction_tab.simultaneous_from_record(rec18d), 'In View2 and View3, ') && ...
    startsWith(u18e, 'not a conduction velocity in View2: ') && ...
    startsWith(rabbit_reconstruction_tab.simultaneous_from_record(rec18e), 'Most of View2 activates');
if isfinite(med18)
    % the same through the Results box: one WARN CV row, for View2 and View3
    cvm.activation_spread.iqr_ms = [4.8 5.2 4.2 4.9];
    cvm.activation_spread.warn_below_ms = [3.4 5.5 4.6 4.0];
    write_json(cv_path, cvm);
    l18d = tab.results_box_lines(run_id, true);
    row18_ok = row18_ok && startsWith(joined_row(l18d, 'WARN CV'), 'WARN CV  not a conduction velocity in View2, View3: ');
    cvm.activation_spread.warn_below_ms = 10;
end
cvm.activation_spread.iqr_ms = [18.7 10 14.3 22.3];
write_json(cv_path, cvm);
none18 = joined_row(tab.results_box_lines(run_id, true), 'WARN CV');
if had_cv, write_text(cv_path, cv_text); else, delete(cv_path); end
none18b = joined_row(tab.results_box_lines(run_id, true), 'WARN CV');
results = add(results, 'R18 near-simultaneous activation: a WARN CV row for an IQR below 10 ms, wrapped at 78; none at 10 ms or above', ...
    row18_ok && max(cellfun(@numel, l18)) <= 78 && isempty(none18) && (had_cv || isempty(none18b)), ...
    sprintf('%s || %s', row18, none18));

%% R19
% the cloud the mesh was built from is what the mesh step
% recorded (its check record's cloud_source, else its settings), not the run's
% start choice (pipeline.cloud_source); Results names it in a Mesh row
gates_path = fullfile(run_dir, 'outputs', 'mesh-cleanup-gates.json');
g_text = fileread(gates_path);
g19 = jsondecode(g_text);
used = char(g19.cloud_source);
other = 'apd';
if strcmp(used, 'apd'), other = 'fused'; end
m19 = m;
m19.pipeline.cloud_source = other;
words19 = struct('fused', 'built from the COLMAP dense cloud', 'apd', 'built from the APDe-MVS dense cloud');
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m19));
a19 = tab.cloud_source_for_manifest(m19);
row19 = strjoin(tab.results_box_lines(run_id, true), ' | ');
% Without the check record's field: the step's recorded settings
g19b = rmfield(g19, 'cloud_source');
write_json(gates_path, g19b);
k19 = find(strcmp({m19.stages.name}, 'mesh_cleanup'), 1, 'last');
m19.stages(k19).settings_resolved.cloud_source = other;
b19 = tab.cloud_source_for_manifest(m19);
write_text(gates_path, g_text);
write_text(fullfile(run_dir, 'manifest.json'), m_text);
results = add(results, ['R19 mesh input: the check record''s cloud, then the step''s settings, not the run''s ' ...
    'start choice; Results says it'], strcmp(a19, used) && strcmp(b19, other) && contains(row19, words19.(used)), ...
    sprintf('recorded %s, start choice %s: %s; settings only: %s | "%s"', used, other, a19, b19, row19));

%% R20
% one Mesh row per check that did not pass, each
% naming its denominator; M7 names the condition that missed, d in mm for a
% run in mm. The record's M7 is made to miss only on its 95th percentile
% (1.09 d), as in the 2181c1c2 run.
g20 = gates;
mm7 = g20.gates.M7.measured;
d20 = double(mm7.support);
g20.gates.M7.verdict = 'WARN';
g20.gates.M7.measured.med_cloud_to_surface = 0.14 * d20;
g20.gates.M7.measured.p95_cloud_to_surface = 1.09 * d20;
g20.gates.M7.measured.vertices_within_support = 0.988;
write_json(gates_path, g20);
l20 = tab.results_box_lines(run_id, true);
s20 = tab.step_warning_lines(run_id, 'mesh_cleanup');
write_text(gates_path, g_text);
flat20 = regexprep(strjoin(l20, ' '), '\s+', ' ');
unit20 = ' model units';
if strcmp(tab.run_units(run_dir), 'mm'), unit20 = ' mm'; end
% the distances themselves, in mm, and the condition missed
want20 = sprintf('M7 mesh fit: cloud to surface median %.2f%s, p95 %.2f%s over %s cloud points (pass: p95 %s d = %.2f%s)', ...
    0.14 * d20, unit20, 1.09 * d20, unit20, tab.format_count(mm7.cloud_points), char(8804), d20, unit20);
mesh_rows = l20(startsWith(l20, 'WARN Mesh'));
ok20 = numel(mesh_rows) == 3 && startsWith(mesh_rows{1}, 'WARN Mesh        M4 normals:') && ...
    startsWith(mesh_rows{2}, 'WARN Mesh        M7 mesh fit:') && startsWith(mesh_rows{3}, 'WARN Mesh        M9 direct views:') && ...
    contains(flat20, want20) && contains(flat20, sprintf('d = support distance %.3g%s', d20, unit20)) && ...
    ~contains(extractBefore(flat20, 'd = support distance'), 'half of') && ...   % the missed condition only; the fail rule is on its own line
    ~contains(flat20, 'mesh vertices have a cloud point') && ...
    contains(flat20, sprintf('%s observed vertices have a DIRECT camera', tab.format_count(gates.gates.M9.measured.n_vertices_observed))) && ...
    numel(s20) == 3 && startsWith(s20{2}, ['WARN Mesh: ' want20]) && max(cellfun(@numel, l20)) <= 78 && strcmp(unit20, ' mm');   % B12: with its label
results = add(results, 'R20 mesh checks: one row each with its denominator; M7 names the missed condition, d in mm (F14)', ...
    ok20, sprintf('%s || steps: %s', strjoin(l20, ' | '), strjoin(s20, ' / ')));

%% R21
% the Scale row says what the scale rests on and
% what was measured, from the run's scale record; no combined figure
ms21 = jsondecode(fileread(fullfile(run_dir, 'stages', 'sparse_build', 'metric_scale.json')));
l21 = tab.results_box_lines(run_id, true);
k21 = find(startsWith(l21, '     Scale'), 1);
row21 = '';
if ~isempty(k21)
    k21e = k21;
    while k21e < numel(l21) && startsWith(l21{k21e + 1}, repmat(' ', 1, 19)), k21e = k21e + 1; end
    row21 = regexprep(strjoin(strtrim(l21(k21:k21e)), ' '), '\s+', ' ');
end
pv21 = ms21.not_included.focal_length.per_view_at_target;
if iscell(pv21), pv21 = [pv21{:}]; end
% the sweep is not an uncertainty interval
rm21 = [];
if isfield(ms21.not_included.focal_length, 'rmse_px'), rm21 = ms21.not_included.focal_length.rmse_px; end
% the rig comparison in words, from the record's own numbers
c21 = ms21.comparison;
rig21 = sprintf('COLMAP and calibration rigs agree: baselines SD %.2f %%', c21.baseline_spread_percent);
if isfield(c21, 'baseline_ratio_mm_per_unit') && numel(c21.baseline_ratio_mm_per_unit) > 1
    r21 = c21.baseline_ratio_mm_per_unit;
    rig21 = sprintf('%s (range %.2f %%)', rig21, 100 * (max(r21) - min(r21)) / mean(r21));
end
if isfield(c21, 'centre_residual_mm') && ~isempty(c21.centre_residual_mm)
    rig21 = sprintf('%s, camera centres within %.1f%s%.1f mm', rig21, min(c21.centre_residual_mm), char(8211), ...
        max(c21.centre_residual_mm));
end
if isfield(c21, 'model_focal_px') && isscalar(unique(c21.model_focal_px))
    rig21 = sprintf('%s; both use the stated %g px, so this does not test the focal length', rig21, unique(c21.model_focal_px));
end
want21 = sprintf('%s; %s', ...
    rig21, rabbit_reconstruction_tab.focal_sweep_words( ...
    ms21.not_included.focal_length.sweep_px, rm21, min([pv21.min_percent]), max([pv21.max_percent])));
rests21 = sprintf('scale rests on the stated %g mm cube; no held-out check', ms21.target_edge_mm);
ok21 = ~isempty(row21) && contains(row21, want21) && contains(row21, 'the cube''s own size tolerance is not measured') && ...
    ~contains(row21, '3.3 %') && ...
    (~isempty(ms21.scale_uncertainty_percent) || contains(row21, rests21)) && ...
    contains(regexprep(strjoin(app.recon.reconstruction_results_details(run_id), ' '), '\s+', ' '), want21) && ...   % Details (Q3: starts with a capital already)
    contains(tab.viewer_header_units(run_dir, 'mm'), 'rests on the stated') && max(cellfun(@numel, l21)) <= 78;
results = add(results, 'R21 Scale: rests on the stated cube; measured parts from the scale record (F16)', ok21, row21);

%% R22
% a CV row from the CV projection's record:
% median and IQR over the vertices with a value (per vertex the mean of its
% faces with a speed), the kind of speed, how the map was made and where the
% pixel size came from; "apparent" under Sinus rhythm; next to the WARN CV row
rp_dir = fullfile(run_dir, 'outputs', 'reprojection');
if exist(fullfile(rp_dir, 'cv_projected.cdf'), 'file') == 2
    fv22 = read_cdf_values(fullfile(rp_dir, 'cv_projected.cdf'));
    mesh22 = rabbit_rhythm_reproject.read_ply_mesh(fullfile(rp_dir, 'cv_projected.ply'));
    use22 = isfinite(fv22) & fv22 > 0;
    f22 = mesh22.faces(use22, :);
    s22 = accumarray(f22(:), repmat(fv22(use22), 3, 1), [size(mesh22.pts, 1) 1]);
    c22 = accumarray(f22(:), 1, [size(mesh22.pts, 1) 1]);
    vv22 = s22(c22 > 0) ./ c22(c22 > 0);
    q22 = prctile(vv22, [25 50 75]);
    want22 = sprintf('median %.2f m/s (IQR %.2f%s%.2f, %s vertices); image-plane speed (not corrected for surface tilt)', ...
        q22(2), q22(1), char(8211), q22(3), tab.format_count(numel(vv22)));
    l22 = tab.results_box_lines(run_id, true);
    flat22 = regexprep(strjoin(strtrim(l22), ' '), '\s+', ' ');
    prm22 = struct();
    if isfield(m.result.reprojection, 'cv') && isfield(m.result.reprojection.cv, 'parameters')
        prm22 = m.result.reprojection.cv.parameters;
    end
    how_ok = true;
    % "Bayly fit: 3 mm window, 3×3 median, time max 10 ms"
    if isfield(prm22, 'time_max'), how_ok = how_ok && contains(flat22, sprintf('time max %s ms', ...
            regexprep(sprintf('%.1f', prm22.time_max), '\.0$', ''))); end
    if isfield(prm22, 'method') && startsWith(char(prm22.method), 'Bayly') && isfield(prm22, 'distance_max')
        how_ok = how_ok && contains(flat22, sprintf('Bayly fit: %g mm window', prm22.distance_max));
    end
    if isfield(prm22, 'pixel_scale_sources') && ~isempty(prm22.pixel_scale_sources)
        src22 = unique(cellstr(prm22.pixel_scale_sources), 'stable');
        % a calibration at the cube is named by its
        % number, at the cube's depth, with the heart's smaller pixels
        want_src22 = ['from ' src22{1}];
        id22 = regexp(src22{1}, '^calibration (\S+)$', 'tokens', 'once');
        if isscalar(src22) && ~isempty(id22)
            want_src22 = sprintf('pixel size from calibration %s at the cube''s depth', ...
                regexp(id22{1}, '_\d+$', 'match', 'once'));
        end
        how_ok = how_ok && contains(flat22, want_src22);
    end
    % Sinus rhythm: the speed is called apparent
    pm_path22 = fullfile(rp_dir, 'reprojection_manifest.json');
    pm_text22 = fileread(pm_path22);
    pm22 = jsondecode(pm_text22);
    pm22.recording_rhythm = rabbit_recording_rhythm.record(rabbit_recording_rhythm.make('sinus'));
    write_json(pm_path22, pm22);
    sinus22 = regexprep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), '\s+', ' ');
    write_text(pm_path22, pm_text22);
    k_cv = find(startsWith(l22, '     CV '), 1);
    k_warn = find(startsWith(l22, 'WARN CV'), 1);
    ok22 = contains(flat22, ['CV ' want22]) && how_ok && max(cellfun(@numel, l22)) <= 78 && ...
        contains(sinus22, 'vertices); apparent image-plane speed (not corrected for surface tilt)') && ...
        ~isempty(k_cv) && (isempty(k_warn) || k_warn > k_cv);   % k_warn: the WARN CV row comes right after it
    % the range of the per-view medians on the DIRECT
    % faces, image plane (and surface when recorded), recounted here
    conf22 = load(fullfile(rp_dir, 'cv_confidence.mat'));
    img22 = [];
    for k = 1:size(conf22.face_views, 2)
        a22 = fv22(conf22.face_class(:) == 1 & logical(conf22.face_views(:, k)) & isfinite(fv22) & fv22 > 0);
        if ~isempty(a22), img22(end + 1) = median(a22); end %#ok<AGROW>
    end
    q6_ok = numel(img22) < 2 || contains(flat22, sprintf('by view (directly seen faces): image plane %.2f%s%.2f', ...
        min(img22), char(8211), max(img22))) && contains(flat22, 'm/s; quote the range');
    % when the near-simultaneous rule fires, the
    % by-view range is "apparent" and is not to be quoted (its row says
    % not to report it as CV)
    if numel(img22) >= 2 && exist(cv_path, 'file') == 2
        cv_text22 = fileread(cv_path);
        cvm22 = jsondecode(cv_text22);
        cvm22.activation_spread = struct('views', {{'View1', 'View2', 'View3', 'View4'}}, ...
            'iqr_ms', [4.8 5.2 4.2 4.9], 'warn_below_ms', 10, 'basis', 'probe');
        write_json(cv_path, cvm22);
        sim22 = regexprep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), '\s+', ' ');
        write_text(cv_path, cv_text22);
        q6_ok = q6_ok && contains(sim22, sprintf('by view (directly seen faces), apparent: image plane %.2f%s%.2f', ...
            min(img22), char(8211), max(img22))) && ~contains(sim22, 'quote the range');
    end
    ok22 = ok22 && q6_ok;
    results = add(results, 'R22 CV row: median, IQR, vertices, image plane, Bayly settings, pixel size; apparent under Sinus (F10); by-view range (Q6), apparent and unquoted when near-simultaneous (R4/Q6)', ...
        ok22, sprintf('%s || sinus: %s', joined_row(l22, '     CV'), want22));
else
    fprintf('PROBE_SKIP R22: the run copy has no CV projection\n');
end

%% R23
% a Projected row names the recording projected
% (SOURCE_RECORDING.json, else the run manifest's result.reprojection.
% source_recording, the file name only) and the projection's time; with
% another recording loaded, or the same one marked with another rhythm, a WARN
% Recording row before it; without the app's recording, no comparison
sr_path = fullfile(rp_dir, 'SOURCE_RECORDING.json');
had_sr = exist(sr_path, 'file') == 2;
if had_sr, sr_text = fileread(sr_path); end
pm23 = jsondecode(fileread(fullfile(rp_dir, 'reprojection_manifest.json')));
when23 = regexprep(char(pm23.created), '^(\d{4}-\d\d-\d\d[ T]\d\d:\d\d).*$', '$1');
when23 = strrep(when23, 'T', ' ');
write_json(sr_path, struct('source_recording', ['some' filesep 'folder' filesep '12h-57m-53s.fits']));
l23 = tab.results_box_lines(run_id, true);
other23 = tab.results_box_lines(run_id, true, struct('name', '12h-59m-35s.fits', 'rhythm', []));
same23 = tab.results_box_lines(run_id, true, struct('name', '12h-57m-53s', 'rhythm', []));
want23 = ['     Projected   12h-57m-53s.fits, ' when23];
warn23 = ['WARN Recording  the projection is of another recording than the one loaded; numbers below are ' ...
    'the projection''s'];
% A rhythm other than the projection's (when both are marked)
rep23 = tab.run_report(run_id);
rr23 = rep23.rhythm_record;
rh_ok = true;
if any(strcmp(rr23.state, {'sinus', 'paced'}))
    alt = rabbit_recording_rhythm.make('sinus');
    if strcmp(rr23.state, 'sinus'), alt = rabbit_recording_rhythm.make('paced', 400); end
    rh23 = joined_row(tab.results_box_lines(run_id, true, struct('name', '12h-57m-53s.fits', 'rhythm', alt)), 'WARN Recording');
    rh_ok = startsWith(rh23, ['WARN Recording  the loaded recording is marked ' rabbit_recording_rhythm.words(alt)]);
end
% From the run manifest when there is no SOURCE_RECORDING.json
delete(sr_path);
m23 = m;
m23.result.reprojection.source_recording = '12h-57m-53s.fits';
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m23));
from_m = tab.results_box_lines(run_id, true);
write_text(fullfile(run_dir, 'manifest.json'), m_text);
if had_sr, write_text(sr_path, sr_text); end
k_p = find(startsWith(l23, '     Projected'), 1);
k_f = find(startsWith(l23, {'WARN', '     Faces'}), 1);       % the first finding row
k_ow = find(startsWith(other23, 'WARN Recording'), 1);
k_op = find(startsWith(other23, '     Projected'), 1);
ok23 = any(strcmp(l23, want23)) && isempty(joined_row(l23, 'WARN Recording')) && ...
    strcmp(joined_row(other23, 'WARN Recording'), warn23) && ...
    ~isempty(k_ow) && ~isempty(k_op) && k_ow < k_op && ...
    isempty(joined_row(same23, 'WARN Recording')) && rh_ok && any(strcmp(from_m, want23)) && ...
    ~isempty(k_p) && (isempty(k_f) || k_p < k_f) && ...
    max(cellfun(@numel, [l23, other23])) <= 78;
% another recording loaded is said on line 1, above the
% verdict; not for the same recording, nor for another rhythm alone
ok23 = ok23 && strcmp(other23{1}, 'THESE RESULTS ARE FOR 12h-57m-53s.fits, NOT THE LOADED 12h-59m-35s.fits.') && ...
    ~startsWith(same23{1}, 'THESE RESULTS') && ~startsWith(l23{1}, 'THESE RESULTS');
results = add(results, 'R23 Projected row and WARN Recording for another loaded recording or rhythm (F11)', ok23, ...
    sprintf('%s || %s', strjoin(l23(max(1, k_p - 1):min(numel(l23), k_p + 1)), ' | '), joined_row(other23, 'WARN Recording')));

%% R24
% A recording marked Paced
% whose CV values (per vertex, as the CV row) are more than 5 % above 1.5 m/s,
% or any above 5 m/s, gets the row "WARN CV  <x> % of values > 1.5 m/s, max
% <y> m/s: outliers present; ..."; Sinus rhythm and Not stated do not. When
% the run copy has no CV projection, one is made for this check from the
% activation projection's mesh (cv_projected.ply) and synthetic speeds
% (cv_projected.cdf), and removed afterwards.
made24 = exist(fullfile(rp_dir, 'cv_projected.cdf'), 'file') ~= 2;
if made24
    mesh24 = rabbit_rhythm_reproject.read_ply_mesh(fullfile(rp_dir, 'activation_projected.ply'));
    nf24 = size(mesh24.faces, 1);
    rng(24, 'twister');
    fv24 = 0.5 + 0.4 * rand(nf24, 1);                      % 0.5-0.9 m/s
    fv24(1:round(0.03 * nf24)) = 100;                      % wild fits: 3 % of the faces above 5 m/s (more than 1 % warns)
    copyfile(fullfile(rp_dir, 'activation_projected.ply'), fullfile(rp_dir, 'cv_projected.ply'));
    rabbit_rhythm_reproject.write_cdf(fullfile(rp_dir, 'cv_projected.cdf'), fv24, 'om_cv_speed');
end
fv24 = read_cdf_values(fullfile(rp_dir, 'cv_projected.cdf'));
mesh24 = rabbit_rhythm_reproject.read_ply_mesh(fullfile(rp_dir, 'cv_projected.ply'));
use24 = isfinite(fv24) & fv24 > 0;
f24 = mesh24.faces(use24, :);
s24 = accumarray(f24(:), repmat(fv24(use24), 3, 1), [size(mesh24.pts, 1) 1]);
c24 = accumarray(f24(:), 1, [size(mesh24.pts, 1) 1]);
vv24 = s24(c24 > 0) ./ c24(c24 > 0);
pm_path24 = fullfile(rp_dir, 'reprojection_manifest.json');
pm_text24 = fileread(pm_path24);
rows24 = struct();
for st = {'paced', 'sinus', 'not_stated'}
    pm24 = jsondecode(pm_text24);
    pm24.recording_rhythm = rabbit_recording_rhythm.record(rabbit_recording_rhythm.make(st{1}, 500 * strcmp(st{1}, 'paced')));
    if strcmp(st{1}, 'not_stated'), pm24 = rmfield(pm24, 'recording_rhythm'); end
    write_json(pm_path24, pm24);
    rows24.(st{1}) = tab.results_box_lines(run_id, true);
end
write_text(pm_path24, pm_text24);
if made24
    delete(fullfile(rp_dir, 'cv_projected.cdf'));
    delete(fullfile(rp_dir, 'cv_projected.ply'));
end
share24 = 100 * mean(vv24 > 1.5);
% its basis; the rule (more than 5 % above 1.5 m/s or more
% than 1 % above 5 m/s) and its words
want24 = sprintf(['WARN CV  %.1f %% of projected vertices > 1.5 m/s, 99th percentile %.1f m/s, max %.1f m/s: ' ...
    'outliers present; quote the median and IQR, and look at the red patches on the 2-D CV map (white faces on the ' ...
    '3-D CV panel) before removing anything (Remove local outliers with "median %s 3 MAD, edges too" can reach edges)'], share24, ...
    prctile(vv24(vv24 > 0), 99), max(vv24), char(177));
got24 = regexprep(strjoin(strtrim(rows24.paced), ' '), '\s+', ' ');
% under a paced CV row the Report line says what to
% report, and the outlier row points to it
want24 = strrep(want24, 'quote the median and IQR', 'report as in the Report line');
report24 = ~isempty(regexp(got24, 'Report: (image plane|surface speed) median [\d.]+ m/s \(IQR ', 'once')) && ...
    contains(got24, 'from this box') && ~contains(strjoin(rows24.sinus, ' '), 'Report:');
ok24 = (share24 > 5 || 100 * mean(vv24 > 5) > 1) && contains(got24, regexprep(want24, '\s+', ' ')) && ...
    ~contains(strjoin(rows24.sinus, ' '), 'outliers present') && ~contains(strjoin(rows24.not_stated, ' '), 'outliers present') && ...
    max(cellfun(@numel, rows24.paced)) <= 78 && report24;
results = add(results, 'R24 paced CV outliers: a WARN CV row; none for Sinus rhythm or Not stated', ok24, ...
    sprintf('%s (synthetic CV: %d)', want24, made24));

%% R26
% the WARN Recording check compares the recording's full
% path, not its display name, whenever both paths are known: the record's
% (SOURCE_RECORDING.json with a folder, else the run manifest's
% source_recording_path) and the loaded file's (file_info.path + its name)
had_sr26 = exist(sr_path, 'file') == 2;
if had_sr26, sr_text26 = fileread(sr_path); end
P26 = fullfile(root, 'rec_a', '12h-57m-53s.fits');
Q26 = fullfile(root, 'rec_b', '12h-57m-53s.fits');
write_json(sr_path, struct('source_recording', P26));
warn26 = @(ld) ~isempty(joined_row(tab.results_box_lines(run_id, true, ld), 'WARN Recording'));
c1 = ~warn26(struct('name', '12h-57m-53s.fits', 'rhythm', [], 'path', P26));                   % same file
c2 = warn26(struct('name', '12h-57m-53s.fits', 'rhythm', [], 'path', Q26));                    % same name, other folder
c3 = warn26(struct('name', '12h-57m-53s.fits', 'rhythm', [], 'path', fullfile(root, 'rec_a', '12h-59m-35s.fits')));   % relabelled name over another file
c4 = ~warn26(struct('name', '12h-59m-35s.fits', 'rhythm', [], 'path', P26));                   % another name, the same file
c5 = ~warn26(struct('name', '12h-57m-53s.fits', 'rhythm', [], 'path', strrep(upper(P26), '\', '/'))) || ~ispc;   % case and separators
% The run manifest's path when there is no record beside the files
delete(sr_path);
m26 = m;
m26.result.reprojection.source_recording = '12h-57m-53s.fits';
m26.result.reprojection.source_recording_path = P26;
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m26));
c6 = ~warn26(struct('name', '12h-59m-35s.fits', 'rhythm', [], 'path', P26)) && ...
    warn26(struct('name', '12h-57m-53s.fits', 'rhythm', [], 'path', Q26));
write_text(fullfile(run_dir, 'manifest.json'), m_text);
if had_sr26, write_text(sr_path, sr_text26); end
% The app gives the loaded file's full path, and records it with a projection
ld26 = app.recon.reconstruction_loaded_recording();
c7 = isfield(ld26, 'path') && strcmp(ld26.path, fullfile(app.file_info.path, ld26.name)) && ...
    strcmp(app.recon.reconstruction_source_recording_path(), ld26.path);
ok26 = c1 && c2 && c3 && c4 && c5 && c6 && c7;
results = add(results, 'R26 WARN Recording by full path, not the display name', ok26, ...
    sprintf('same %d, other folder %d, relabelled %d, renamed same file %d, case/sep %d, manifest path %d, app path %d', ...
    c1, c2, c3, c4, c5, c6, c7));

%% R25
% W7 the mesh outline match as its own row,
% the other one named "camera-image", both in Details; W10 Rhythm directly
% under Projected; W11 Details gives the pose as distances on the heart, as
% Results; B12 Details names what the clean-completion check covers, and
% each step line has its row's label
write_text(fullfile(run_dir, 'manifest.json'), regexprep(regexprep(m_text, ...
    '"ambiguous_frames":\s*[^,\r\n]*', '"ambiguous_frames": [37, 67]'), ...
    '"ambiguous_turn_deg":\s*[^,\r\n]*', '"ambiguous_turn_deg": [18.4, 13.1]'));
l25 = tab.results_box_lines(run_id, true);
d25 = strjoin(app.recon.reconstruction_results_details(run_id), ' ');
st25 = tab.step_warning_lines(run_id, 'reprojection');
r25 = tab.run_report(run_id);
write_text(fullfile(run_dir, 'manifest.json'), m_text);
flat25 = regexprep(strjoin(l25, ' '), '\s+', ' ');
ok25 = true;
det25 = {};
if isfield(fc, 'mesh_iou') && ~isempty(fc.mesh_iou)
    miou_v = nan(1, 4); miou_v(row_view) = fc.mesh_iou(:)';
    ok25 = ok25 && has_by_view(flat25, 'mesh outline match ', miou_v, 'iou') && ...   % 3 decimals near a limit
        contains(d25, ['Mesh outline match (OM outline against the mesh; 1 = identical): ' strjoin(arrayfun(@(k) ...
        sprintf(['View%d ' iou_fmt(miou_v(k))], k, miou_v(k)), 1:4, 'UniformOutput', false), ', ')]);   % 3 decimals in Details too
    det25{end + 1} = sprintf('mesh iou %s', mat2str(miou_v, 3));
end
if any(iou_v < 0.85), ok25 = ok25 && contains(flat25, 'camera-image outline match '); end
kp = find(startsWith(l25, '     Projected'), 1);
kr = find(startsWith(l25, '     Rhythm'), 1);
if ~isempty(kp) && ~isempty(kr)
    kp_end = kp;
    while kp_end < numel(l25) && startsWith(l25{kp_end + 1}, repmat(' ', 1, 19)), kp_end = kp_end + 1; end
    ok25 = ok25 && kr == kp_end + 1;
    det25{end + 1} = sprintf('Projected row %d, Rhythm row %d', kp, kr);
end
[~, mm25] = tab.pose_position_words(run_dir, m, 18.4);
if ~isempty(mm25), ok25 = ok25 && contains(d25, sprintf('Positions %s.', mm25)); end
ok25 = ok25 && ~contains(d25, 'the three files the viewer shows') && ...
    all(cellfun(@(t) ~isempty(regexp(t, '^(WARN |FAIL )?[A-Z][A-Za-z]*: ', 'once')), st25));
ok25 = ok25 && (~r25.defect.applies || ~contains(flat25, 'defect rule applies'));
results = add(results, 'R25 mesh outline match row and Details; Rhythm under Projected; Details pose in mm, check scope, step labels', ...
    ok25, sprintf('%s | %s | pose "%s" | steps: %s', strjoin(det25, '; '), d25(1:min(end, 300)), mm25, strjoin(st25, ' / ')));

%% R27
% shares round half up (30.5 -> 31 %), never 0 or 100 for a part
p27 = {tab.viewer_percent(30.5), tab.viewer_percent(30.49), tab.viewer_percent(100 * 17615 / 57143), ...
    tab.viewer_percent(0.4), tab.viewer_percent(99.6), tab.viewer_percent(2.5)};
ok27 = isequal(p27, {'31 %', '30 %', '31 %', '<1 %', '>99 %', '3 %'});
results = add(results, 'R27 shares in whole percent, half up', ok27, strjoin(p27, ', '));

%% R28
% "(3x3 median)" only when the CV
% projection's record says cv_smoothing_3x3 is true; nothing on smoothing
% when it is false or the field is absent (an older record)
w_on = rabbit_reconstruction_tab.CV_SOURCE_WORDS(struct('parameters', struct('cv_smoothing_3x3', true, ...
    'cv_time_max_ms', 9.8, 'cv_distance_max_mm', 3)));
w_off = rabbit_reconstruction_tab.CV_SOURCE_WORDS(struct('parameters', struct('cv_smoothing_3x3', false)));
w_old = rabbit_reconstruction_tab.CV_SOURCE_WORDS(struct('schema', 'old record'));
w_none = rabbit_reconstruction_tab.CV_SOURCE_WORDS();
% the CV projection writes the field at its top level
w_top = rabbit_reconstruction_tab.CV_SOURCE_WORDS(struct('cv_smoothing_3x3', true, 'cv_time_max_ms', 9.8));
ok28 = contains(w_on, sprintf('2-D CV maps (3%s3 median), not from', char(215))) && strcmp(w_top, w_on) && ...
    ~contains(w_off, 'median') && ~contains(w_old, 'median') && strcmp(w_off, w_old) && strcmp(w_old, w_none) && ...
    contains(w_old, '2-D CV maps, not from the 3-D activation shown');
results = add(results, 'R28 CV source words: 3x3 median only when the record says so', ok28, ...
    sprintf('%s | %s', w_on, w_old));

%% R29
% displayed paths in backslashes,
% cut from the left with "...\" (whole folder names, the file name kept);
% only path-like words change in text built from records; Results and the
% Steps lines carry no forward-slash run path
ell = char(8230);
p29a = rabbit_reconstruction_tab.display_path('outputs/reprojection_01');
p29b = rabbit_reconstruction_tab.display_path('X:/data/a dataset/a day/a_stem.matom/reconstruction/runs/x/outputs/reprojection', 40);
p29c = rabbit_reconstruction_tab.display_paths_in('kept in outputs/reprojection_05; 0.70 m/s, 1 / 2, see stages/sparse_build/metric_scale.json.');
l29 = [tab.results_box_lines(run_id, true), tab.step_warning_lines(run_id, 'reprojection')];
ok29 = strcmp(p29a, 'outputs\reprojection_01') && startsWith(p29b, [ell '\']) && endsWith(p29b, '\outputs\reprojection') && ...
    numel(p29b) <= 40 && strcmp(p29c, 'kept in outputs\reprojection_05; 0.70 m/s, 1 / 2, see stages\sparse_build\metric_scale.json.') && ...
    isempty(regexp(strjoin(l29, ' '), '\<(outputs|stages|inputs)/', 'once'));
results = add(results, 'R29 displayed paths: backslashes, cut from the left, only path words', ok29, ...
    sprintf('%s | %s | %s', p29a, p29b, p29c));

%% R30
% Printing the per-view projection records: a
% synthetic projection record with the fields prints them; one without them
% prints nothing (older runs)
pm_path30 = fullfile(rp_dir, 'reprojection_manifest.json');
cv_path30 = fullfile(rp_dir, 'cv_reprojection_manifest.json');
pm_text30 = fileread(pm_path30);
had_cv30 = exist(cv_path30, 'file') == 2;
if had_cv30, cv_text30 = fileread(cv_path30); end
base30 = regexprep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), '\s+', ' ');
pm30 = jsondecode(pm_text30);
pm30.recording_rhythm = struct('state', 'paced', 'pacing_cycle_ms', 500, 'stated_as', 'ms', 'source', 'File menu', ...
    'marked_at', '2026-11-25 22:00:00', 'pacing_site', 'RV epicardium', 'detected_interval_ms', 560, ...
    'cycle_mismatch_pct', 12, 'cycle_mismatch_warn', true);
pm30.activation_consistency = struct('views', {{'View1'; 'View2'; 'View3'; 'View4'}}, 'iqr_3d_direct_ms', [20; 21; 22; 69], ...
    'iqr_2d_ms', [18; 19; 20; 14], 'ratio', [1.1; 1.1; 1.1; 4.9], 'warn', [false; false; false; true], 'basis', 'probe');
pm30.mesh_outside_om = struct('views', {{'View1'; 'View2'; 'View3'; 'View4'}}, 'fraction', [0.07; 0.12; 0.13; 0.26], ...
    'warn', [false; true; true; true], 'basis', 'share of the projected mesh silhouette outside the OM tissue outline');
write_json(pm_path30, pm30);
cvm30 = struct('schema', 'rabbit_rhythm_reproject.manifest.v1');
if had_cv30, cvm30 = jsondecode(cv_text30); end
cvm30.surface_speed = struct('steep_faces_left_out', 1234, 'correction_cap', 1.5, ...
    'basis', 'faces whose tilt correction (surface / image-plane speed) is above 1.5x');
write_json(cv_path30, cvm30);
with30 = regexprep(strrep(strjoin(strtrim(tab.results_box_lines(run_id, true)), ' '), char(160), ' '), '\s+', ' ');
% View4 has the activation consistency warning and 26 % outside; with its
% camera-image match below 0.75 too (the run's own), one WARN View4 row names
% each check that fired, with the Next words
g30 = tab.geometry_suspect(run_dir, m);
g4 = g30([g30.view] == 4);
s8_ok = isscalar(g4) && contains(g4.text, 'mesh outside its outline 26') && ...
    contains(g4.text, sprintf('directly seen faces spread 4.9%s its 2-D map', char(215))) && ...
    endsWith(g4.text, 'Next: treat View4''s 3-D values as unreliable; use its 2-D map.') && ...
    contains(with30, 'WARN View4 geometry suspect: ') && ...
    contains(g4.text, 'camera-image match') == (iou_v(4) < rabbit_reconstruction_tab.GEOMETRY_SUSPECT_IOU) && ...
    ~any([g30.view] == 1);   % View1: one check at most
% the view_geometry_suspect record comes first when there
pm30.view_geometry_suspect = struct('suspect_views', {{'View2'}}, 'warnings', ...
    {{'WARN View2  geometry suspect: ready.'}}, 'next', {{'Next: ready next.'}});
write_json(pm_path30, pm30);
g30r = tab.geometry_suspect(run_dir, m);
s8_ok = s8_ok && isscalar(g30r) && g30r.view == 2 && strcmp(g30r.text, 'geometry suspect: ready. Next: ready next.');
write_text(pm_path30, pm_text30);
if had_cv30, write_text(cv_path30, cv_text30); else, delete(cv_path30); end
nb = ' ';
% merge of lanes A and B: the site is in the Rhythm words, and the cycle WARN is
% rabbit_recording_rhythm.cycle_warning's (one wording; read back from the record)
want30 = {'Paced, 500 ms cycle, pacing site RV epicardium (as stated; Average beats found 560 ms, 12 % different)', ...
    'WARN Rhythm stated cycle 500 ms, detected 560 ms (beat interval from Average beats): 12 % different (more than 10 %)', ...
    ... % S2 names the map (the smoothed IQR, when the CV record has it, follows), S7 the limits
    'WARN Activation View4: directly seen faces spread 69 ms (IQR) against 14 ms in its 2-D map as projected (unsmoothed', ...
    sprintf('this view''s projection does not reproduce its map (warn > 1.5%s)', char(215)), ...
    sprintf(['WARN Projection mesh outside the OM outline V1%s7 %% %s V2%s12 %% %s V3%s13 %% %s V4%s26 %% ' ...
    '(warn > 10 %%; mesh larger than the OM outline: pose, scale or the OM tissue outline; not missing mesh)'], ...
    nb, char(183), nb, char(183), nb, char(183), nb)};
ok30 = all(cellfun(@(w) contains(with30, w), want30)) && ~contains(with30, 'View1: directly seen') && ...
    numel(strfind(with30, 'pacing site')) == 1;   % said once
% the steep faces only where the run has a surface speed (the CV row)
if ~isempty(tab.report_cv_values(run_dir, 'surface'))
    ok30 = ok30 && contains(with30, sprintf('surface speed left out on 1,234 steep faces (correction > 1.5%s)', char(215)));
end
none30 = ~contains(base30, 'pacing site') && ~contains(base30, 'detected beat interval') && ...
    ~contains(base30, 'does not reproduce its map') && ~contains(base30, 'mesh outside the OM outline') && ...
    ~contains(base30, 'steep faces');
% the helpers on their own, without the fields: nothing
unit30 = isempty(rabbit_reconstruction_tab.h3_steep_words(struct('schema', 'x'))) && ...
    isempty(tab.h3_consistency_words(struct('schema', 'x'))) && isempty(tab.h3_outside_words(struct('schema', 'x'))) && ...
    isempty(tab.h3_cycle_words(struct('state', 'paced', 'pacing_cycle_ms', 500))) && ...
    isequal(tab.near_limit_formats([0.855 0.80 0.705 0.71], struct('pose_iou_warn', 0.85, 'pose_iou_fail', 0.70)), ...
    {'%.3f', '%.2f', '%.3f', '%.2f'});
% texts already in the record are printed when recorded, without their WARN lead
unit30 = unit30 && strcmp(tab.h3_outside_words(struct('mesh_outside_om', struct('fraction', [0.2 0.05], ...
    'warn', [true false], 'text', 'WARN Projection  ready outside'))), 'ready outside') && ...
    isequal(tab.h3_consistency_words(struct('activation_consistency', struct('warnings', ...
    {{'WARN Activation  View4: ready'}}))), {sprintf('View4: ready (warn > 1.5%s)', char(215))}) && ...   % its limit added
    strcmp(rabbit_reconstruction_tab.h3_steep_words(struct('surface_speed', struct('steep_faces_left_out', 3, ...
    'text', 'ready steep'))), 'ready steep');
% an older recorded text gets thousands commas and its
% "26 %" joined; a view list keeps a value and its % together
nb30 = char(160);
unit30 = unit30 && strcmp(rabbit_reconstruction_tab.h3_steep_words(struct('surface_speed', struct( ...
    'steep_faces_left_out', 7508, 'text', sprintf('surface speed left out on 7508 steep faces (correction > 1.5%s)', ...
    char(215))))), sprintf('surface speed left out on 7,508 steep faces (correction > 1.5%s)', char(215))) && ...
    contains(tab.h3_outside_words(struct('mesh_outside_om', struct('fraction', [0.07 0.26], 'warn', [false true], ...
    'text', sprintf('WARN Projection  mesh outside the OM outline V1 7 %% %s V2 26 %% (pose)', char(183))))), ...
    ['V1' nb30 '7' nb30 '% ' char(183) ' V2' nb30 '26' nb30 '%']) && ...
    contains(tab.by_view('', [77 81], '%.0f %%', char(183)), ['77' nb30 '%']);
% both 2-D IQRs named, the CV step's from its record;
% an older ready text gets the words put in
ac31 = struct('views', {{'View1', 'View2', 'View3', 'View4'}}, 'iqr_3d_direct_ms', [13 17 33 74], ...
    'iqr_2d_ms', [19 20 33 22], 'warn', [false false false true]);
cv31 = struct('cv_smoothing_3x3', true, 'activation_spread', struct('views', {{'View1', 'View2', 'View3', 'View4'}}, ...
    'iqr_ms', [16 18 25 14.3]));
want31 = sprintf(['View4: directly seen faces spread 74 ms (IQR) against 22 ms in its 2-D map as projected ' ...
    '(unsmoothed; 14 ms after the CV step''s 3%s3 median); this view''s projection does not reproduce its map ' ...
    '(warn > 1.5%s)'], char(215), char(215));
ac31r = ac31;
ac31r.warnings = {['WARN Activation  View4: directly seen faces spread 74 ms (IQR) against 22 ms in its 2-D map; ' ...
    'this view''s projection does not reproduce its map']};
unit30 = unit30 && isequal(tab.h3_consistency_words(struct('activation_consistency', ac31), cv31), {want31}) && ...
    isequal(tab.h3_consistency_words(struct('activation_consistency', ac31r), cv31), {want31}) && ...
    isequal(tab.h3_consistency_words(struct('activation_consistency', ac31)), ...
    {strrep(want31, sprintf('; 14 ms after the CV step''s 3%s3 median', char(215)), '')});
% the record's own iqr_2d_smoothed_ms, without the CV record
ac31s = ac31;
ac31s.iqr_2d_smoothed_ms = [15 17 24 14.3];
unit30 = unit30 && isequal(tab.h3_consistency_words(struct('activation_consistency', ac31s)), {want31});
% the Rhythm row says whether the cycle was checked
pr31 = struct('state', 'paced');
st31 = 'Paced, 500 ms cycle, pacing site not known (as stated)';
unit30 = unit30 && strcmp(tab.rhythm_check_words(st31, pr31, struct('detected_interval_ms', [])), ...
    [st31 '; beat interval not checked (Average beats not run on this recording in this session)']) && ...
    strcmp(tab.rhythm_check_words(st31, pr31, struct('detected_interval_ms', 499.67, 'cycle_mismatch_warn', false)), ...
    'Paced, 500 ms cycle, pacing site not known (as stated; Average beats found 500 ms, agrees)') && ...
    strcmp(tab.rhythm_check_words(st31, pr31, struct('state', 'paced')), st31) && ...
    strcmp(tab.rhythm_check_words(st31, pr31, struct('detected_interval_ms', [], 'rhythm_row_text', 'ready row')), ...
    'ready row') && ...   % a rhythm_row_text already in the record
    strcmp(tab.rhythm_check_words('Sinus rhythm (as stated)', struct('state', 'sinus'), ...
    struct('detected_interval_ms', [])), 'Sinus rhythm (as stated)');
% and no Results line begins with a lone % (a wrapped "24 / %")
unit30 = unit30 && ~any(startsWith(strtrim(tab.results_box_lines(run_id, true)), '%'));
results = add(results, 'R30 H3 printing: pacing site, cycle mismatch, per-view consistency, mesh outside, steep faces; nothing without the fields', ...
    ok30 && none30 && unit30, with30);
results = add(results, 'R31 one WARN View<k> geometry-suspect row when two or more per-view checks fire', ...
    s8_ok, strjoin({g30.text}, ' | '));

%% R32
% the log window's projection-check warning gives the
% pose in the Results words (pose_row_words); S12: the rows in the fixed order
w32 = ['Projection check WARN - the projection was made; read the numbers. Frame 1 chosen for the cameras: the ' ...
    'earliest frame within 0.05 of the best match (frame 3) (49 frames had all four views registered). Match of ' ...
    'the heart outline ... below 0.70 the step stops). Frames 37 (18 deg), 67 (13 deg) match within 0.05 as well, ' ...
    'but the heart is turned by up to 18 degrees there: the outline match cannot tell these positions apart, so ' ...
    'the OM pose is known only to within about 18 degrees. Set "OM pose frame" to a frame number if another frame ' ...
    'is known to show the OM position. The OM image differs.'];
m32 = struct('result', struct('reprojection', struct('frame_check', struct('frame', 1, 'chosen_by', 'automatic', ...
    'best_score_frame', 3, 'summary', 'the earliest frame within 0.05 of the best match', ...
    'ambiguous_frames', [37 67], 'ambiguous_turn_deg', [18.2 13.1]))));
a32 = tab.activity_pose_words(w32, '', m32);
ok32 = startsWith(a32, ['Projection check WARN - the projection was made; read the numbers. OM pose: frame 1 used ' ...
    '(earliest within 0.05 of the best match, frame 3); frames 37 and 67 fit as well but are turned 18' char(176) ...
    ' and 13' char(176) ' from frame 1. Match of the heart outline']) && ~contains(a32, 'chosen for the cameras') && ...
    ~contains(a32, 'Set "OM pose frame"') && endsWith(a32, 'The OM image differs.') && ...
    strcmp(tab.activity_pose_words('Edge threshold 0.30', '', m32), 'Edge threshold 0.30');
% the fixed order: Projected, Rhythm, then Projection before Coverage before
% Activation before CV before Alignment before Mesh before Sparse
lab32 = regexp(tab.results_box_lines(run_id, true), '^(WARN|    ) (\S+)', 'tokens', 'once');
lab32 = lab32(~cellfun(@isempty, lab32));
lab32 = cellfun(@(c) c{2}, lab32, 'UniformOutput', false);
order32 = {'Projected', 'Rhythm', 'Projection', 'Coverage', 'Activation', 'CV', 'Alignment', 'Mesh', 'Sparse', 'Faces', 'Scale'};
pos32 = cellfun(@(c) find(strcmp(order32, c), 1), lab32, 'UniformOutput', false);
pos32 = [pos32{:}];
ok32 = ok32 && issorted(pos32);
results = add(results, 'R32 log window pose in the Results words; the fixed row order', ok32, ...
    sprintf('%s || %s', a32, strjoin(lab32, ' ')));

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_RESULTS_BOX RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_results_box:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_results_box %d/0\n', n_pass);
end


function [ok, detail] = spread_case(tab, run_id, run_dir, lim, name)
% R15: Results' spread against the Visualise panel's drawn values as it
% opens (same values, same basis), then the row with no cycle and with a
% 500 ms cycle recorded in the projection's record
[vals, hid] = tab.report_activation_values(run_dir);
s_res = tab.activation_spread(vals);
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
d = getappdata(fig, 'reconstruction_activation');
dv = d.values(isfinite(d.values(:, 1)), 1);
q = prctile(dv, [5 95]);
s_pan = q(2) - q(1);
cap = strjoin(tab.viewer_caption(fig, 'projected'), ' / ');
close(fig, 'force');
% the panel's face values come from the run record, Results' from the .cdf (float32):
% the same values to about 1e-5 ms
same = ~isempty(s_res) && abs(s_res - s_pan) < 0.01 && numel(vals) == numel(dv);
en = char(8211);
warn = s_pan > lim;
pm_path = fullfile(run_dir, 'outputs', 'reprojection', 'reprojection_manifest.json');
pm_text = fileread(pm_path);
l0 = tab.results_box_lines(run_id, true);
row0 = joined_row(l0, 'WARN Activation');
pm = jsondecode(pm_text);
pm.cycle_length_ms = 500;
write_json(pm_path, pm);
l1 = tab.results_box_lines(run_id, true);
row1 = joined_row(l1, 'WARN Activation');
write_text(pm_path, pm_text);
% which spread, in words
% the basis named, "the <n> vertices on faces shown
% (low-confidence fills hidden)", the parenthesis when class-4 faces are hidden
basis = sprintf('the %s vertices on faces shown', tab.format_count(numel(dv)));
if hid, basis = [basis ' (low-confidence fills hidden)']; end
want0 = sprintf(['WARN Activation  over the whole heart, 5 %% to 95 %% of %s activate within %d ms (limit %d ms); ' ...
    'scattered late faces, also on directly seen faces; check the activation (i), median time by face class'], ...
    basis, round(s_pan), lim);   % R12: no cause claimed
want1 = strrep(want0, sprintf('(limit %d ms);', lim), sprintf('(limit %d ms); cycle 500 ms;', lim));
m = jsondecode(fileread(fullfile(run_dir, 'manifest.json')));
n_warned = sum(strcmp({m.stages.status}, 'WARNED'));
r15 = tab.run_report(run_id);   % the row is not a warned step: the count and the headline stay
head_ok = numel(r15.warned) == n_warned && strcmp(l1{1}, l0{1});
k1 = find(startsWith(l1, 'WARN Activation'), 1);   % the row goes on onto an indented line
wrapped = isempty(k1) || (k1 < numel(l1) && startsWith(l1{k1 + 1}, repmat(' ', 1, 19)));
if warn
    ok = same && strcmp(row0, want0) && strcmp(row1, want1) && max(cellfun(@numel, [l0, l1])) <= 78 && ...
        head_ok && wrapped && contains(cap, sprintf('WARN over the whole heart, 5%s95 %% activate within %d ms (limit %d ms)', en, round(s_pan), lim));
else
    ok = same && isempty(row0) && isempty(row1) && ~contains(cap, 'WARN over the whole heart') && head_ok;
end
detail = sprintf(['%s: Results %.2f ms over %d vertices, panel %.2f ms over %d (5th %.1f, 95th %.1f); ' ...
    'diff %.2g ms; warn %d same %d head %d wrapped %d width %d | "%s" | with 500 ms: "%s" | caption "%s"'], name, s_res, numel(vals), ...
    s_pan, numel(dv), q(1), q(2), s_res - s_pan, warn, same, head_ok, wrapped, max(cellfun(@numel, [l0, l1])), row0, row1, cap);
fprintf('R15 %s spread: Results %.2f ms, panel %.2f ms (5th %.1f, 95th %.1f ms over %d vertices)\n', name, s_res, ...
    s_pan, q(1), q(2), numel(dv));
end


function txt = joined_row(lines, head)
% A Results row with its indented continuation lines, as one line ('' if none)
txt = '';
k0 = find(startsWith(lines, head), 1);
if isempty(k0), return; end
k1 = k0;
while k1 < numel(lines) && startsWith(lines{k1 + 1}, repmat(' ', 1, 19)), k1 = k1 + 1; end
rest = strtrim(extractAfter(strjoin(strtrim(lines(k0:k1)), ' '), head));
txt = [head '  ' rest];
end


function ok = has_by_view(txt, head, vals, fmt)
% txt has head then the values View1 to View4 ("View1 x Â· View2 y ...", or
% the short "V1 x Â· V2 y ..." when the long form does not fit its row)
sep = [' ' char(183) ' '];
ok = false;
% Results prints an outline match within 0.01
% of a limit (0.85, 0.70) to 3 decimals; fmt 'iou' asks for that rule
fk = repmat({fmt}, 1, numel(vals));
if strcmp(fmt, 'iou')
    fk = repmat({'%.2f'}, 1, numel(vals));
    fk(min(abs(vals(:) - 0.85), abs(vals(:) - 0.70))' < 0.01) = {'%.3f'};
end
for name = {'View', 'V'}
    want = [head strjoin(arrayfun(@(k) sprintf([name{1} '%d ' fk{k}], k, vals(k)), 1:numel(vals), ...
        'UniformOutput', false), sep)];
    ok = ok || contains(regexprep(txt, '\s+', ' '), want);
end
end


function f = iou_fmt(v)
% An outline match's format: 3 decimals within 0.01 of a limit (0.85, 0.70)
f = '%.2f';
if min(abs(v - 0.85), abs(v - 0.70)) < 0.01, f = '%.3f'; end
end

function v = read_cdf_values(p)
% The projected values of a .cdf (float32 after its 8 header lines)
fid = fopen(p, 'rb');
c = onCleanup(@() fclose(fid));
for k = 1:8, fgetl(fid); end
v = double(fread(fid, Inf, 'float32'));
end


function s = fmt_mm(v)
% A distance in mm as Results gives it: whole mm from 2 mm
if v >= 2, s = sprintf('%.0f', v); else, s = sprintf('%.1f', v); end
end


function write_json(path, x)
fid = fopen(path, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(x));
fclose(fid);
end


function write_text(path, txt)
fid = fopen(path, 'w', 'n', 'UTF-8');
fwrite(fid, unicode2native(txt, 'UTF-8'));
fclose(fid);
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
