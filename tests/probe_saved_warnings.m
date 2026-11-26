function probe_saved_warnings
%% Probe: saved Visualise pictures carry every warning of the live window
% Collin Snitchler
% 25.11.2026
% Round 3 found that a saved window or panel left out warnings the live
% window shows (the activation-spread WARN, the paced outlier warning), cut
% a WARN line with "(more in (i))" (a file has no (i)), drew NOT FOR
% ANALYSIS twice in the saved window and stated a colour range up to three
% times. Driven through the app's Redo projection, headless, on a copy of a
% completed run marked Paced, with an activation map that spreads more than
% 80 ms, a CV map with outliers and an edge weight of 0.30 (rim faces
% hidden), so the captions have WARN lines.
% With Panel details off and on, for the whole window and each data panel:
%   S1  every warning line of the live caption and details box (lines with
%       WARN, "outliers present" or "Caution") is in the saved text, word
%       for word (the footer, and the picture's captions as drawn while it
%       is saved; whitespace ignored, as the picture wraps lines)
%   S2  "(more in (i))" is in no saved text
%   S3  the colour range is stated once: in the footer's last line, not in
%       the picture's captions or the footer's caption blocks
%   S4  NOT FOR ANALYSIS (when the run is under the defect rule) is once in
%       the saved window: in its footer, not in header line 2 while saving;
%       header line 2 has it again afterwards
%   S5  Save... and Save panel... write their PNGs, and the live captions
%       are drawn back as before
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_saved_warnings" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_saved_warnings', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app: paced, a wide-spread map, a CV map with outliers, edge weight 0.30
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
rng(7, 'twister');
% A ramp across the frame, 20 to 220 ms: faces average their pixels, so a
% spread must be in space, not noise, to reach the 5-95 % spread warning (80 ms)
map = 20 + 200 * repmat(linspace(0, 1, size(om_image, 2)), size(om_image, 1), 1) + rand(size(om_image));
frames = repmat(om_image, 1, 1, 6) .* reshape(linspace(0.9, 1.1, 6), 1, 1, []);
rng(11, 'twister');
speed = 0.2 + 0.8 * rand(size(map));
speed(:, 1:round(0.25 * size(map, 2))) = 3;      % a quarter of the frame above 1.5 m/s: the paced outlier warning
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
rabbit_recording_rhythm.mark(app, rabbit_recording_rhythm.make('paced', 500), 'quiet');
app.recon.ReconstructionEdgeWeightField.Value = 0.30;
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map and video');
app.recon.ReconstructionReprojectButtonPushed();
[v_ok, v_err, fig] = tab.visualise_artifacts(run_id);
assert(v_ok, v_err);
fig_cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
pd = findobj(fig, 'Tag', 'ReconstructionPanelDetails');
assert(isscalar(pd), 'No Panel details checkbox.');
note = findall(fig, 'Tag', 'ReconstructionOrientationNote');
nfa = getappdata(fig, 'reconstruction_not_for_analysis');
roles = intersect({'projected', 'video', 'cv'}, getappdata(fig, 'reconstruction_viewer_order'), 'stable');
squash = @(t) regexprep(strjoin(cellstr(t), ' '), '\s+', '');   % whitespace ignored (the picture wraps)
is_warn = @(c) contains(c, 'WARN') | contains(c, 'outliers present') | contains(c, 'Caution');

for on = [0 1]
    set(pd, 'Value', on);
    pd.Callback(pd, []);
    drawnow;
    mode = sprintf('details %d', on);
    live_sub = struct();
    warns = {};
    for r = roles
        lines = tab.viewer_caption(fig, r{1});                  % unwrapped: line 1, caveats, range
        if on, lines = [lines, tab.viewer_detail_lines(fig, r{1})]; end %#ok<AGROW>
        warns = [warns, lines(is_warn(lines))]; %#ok<AGROW>
        ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' r{1}]);
        live_sub.(r{1}) = cellstr(ax.Subtitle.String);
    end
    warns = unique(warns, 'stable');
    live_note = char(note.String);
    %% Whole window, as Save... draws it
    prep = tab.viewer_export_prepare(fig, 'window');
    foot = tab.viewer_export_footer(fig, '');
    subs = {};
    for r = roles
        ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' r{1}]);
        subs = [subs, cellstr(ax.Subtitle.String)']; %#ok<AGROW>
    end
    save_note = char(note.String);
    clear prep
    foot_cells = strsplit(strjoin(foot, char(9)), char(9));
    saved_text = squash([foot_cells, subs]);
    missing = warns(~cellfun(@(w) contains(saved_text, squash(w)), warns));
    results = add(results, ['S1 ' mode ' window: every warning line in the saved text'], ...
        ~isempty(warns) && isempty(missing), sprintf('%d warning lines; missing: %s', numel(warns), strjoin(missing, ' | ')));
    results = add(results, ['S2 ' mode ' window: no "(more in (i))" in the saved text'], ...
        ~any(contains([foot_cells, subs], '(more in (i))')), '');
    range_in_caps = any(~cellfun(@isempty, regexp(subs, '^colours \S*\d', 'once')));
    range_in_blocks = any(~cellfun(@isempty, regexp(strtrim(foot_cells(1:end - 1)), '^(colours|Colours|Colour range)\s', 'once')));
    results = add(results, ['S3 ' mode ' window: the colour range only in the footer''s last line'], ...
        ~range_in_caps && ~range_in_blocks && contains(foot{end}, 'colours '), foot{end});
    if ischar(nfa) && ~isempty(nfa)
        results = add(results, ['S4 ' mode ' window: NOT FOR ANALYSIS once, in the footer'], ...
            ~contains(save_note, 'NOT FOR ANALYSIS') && numel(strfind(strjoin(foot, ' '), 'NOT FOR ANALYSIS')) == 1 && ...
            contains(char(note.String), 'NOT FOR ANALYSIS'), sprintf('while saving "%s"; after "%s"', save_note, char(note.String)));
    else
        fprintf('PROBE_SKIP S4 %s: this run is not under the defect rule\n', mode);
    end
    %% Each data panel, as Save panel... draws it
    for r = roles
        ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' r{1}]);
        lines = tab.viewer_caption(fig, r{1});
        if on, lines = [lines, tab.viewer_detail_lines(fig, r{1})]; end %#ok<AGROW>
        pw = unique(lines(is_warn(lines)), 'stable');
        prep = tab.viewer_export_prepare(fig, 'panel');
        pf = tab.viewer_export_footer(fig, r{1});
        ps = cellstr(ax.Subtitle.String)';
        clear prep
        pt = squash([pf, ps]);
        pmiss = pw(~cellfun(@(w) contains(pt, squash(w)), pw));
        results = add(results, ['S1 ' mode ' panel ' r{1} ': every warning line in the saved text'], isempty(pmiss), ...
            sprintf('%d warning lines; missing: %s', numel(pw), strjoin(pmiss, ' | ')));
        results = add(results, ['S2/S3 ' mode ' panel ' r{1} ': no "(more in (i))"; the range once, in the last line'], ...
            ~any(contains([pf, ps], '(more in (i))')) && ...
            ~any(~cellfun(@isempty, regexp(ps, '^colours \S*\d', 'once'))) && ...
            ~any(~cellfun(@isempty, regexp(strtrim(pf(1:end - 1)), '^(colours|Colours|Colour range)\s', 'once'))), pf{end});
    end
    %% S5: the files, and the live window drawn back
    f = fullfile(root, sprintf('window_%d.png', on));
    headless_push('uiputfile', f);
    tab.viewer_save_image(fig);
    ok5 = exist(f, 'file') == 2;
    why5 = {};
    for r = roles
        ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' r{1}]);
        fp = fullfile(root, sprintf('panel_%s_%d.png', r{1}, on));
        om_export.save_to(ax(1), fp);
        now5 = cellstr(ax.Subtitle.String);
        same5 = isequal(now5, live_sub.(r{1}));
        ok5 = ok5 && exist(fp, 'file') == 2 && same5;
        if ~same5
            why5{end + 1} = sprintf('%s: "%s" -> "%s"', r{1}, strjoin(live_sub.(r{1}), ' / '), strjoin(now5, ' / ')); %#ok<AGROW>
        end
    end
    results = add(results, ['S5 ' mode ': PNGs written; the live captions and header back as before'], ...
        ok5 && strcmp(char(note.String), live_note), sprintf('note "%s" -> "%s"; %s', live_note, char(note.String), ...
        strjoin(why5, ' | ')));
end

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_SAVED_WARNINGS RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_saved_warnings:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_saved_warnings %d/0\n', n_pass);
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
