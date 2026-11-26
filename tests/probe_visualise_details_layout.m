function probe_visualise_details_layout
%% Probe: Panel details keeps every panel's axes at half its cell or more, live and saved
% Collin Snitchler
% 25.11.2026
% Round 2 found that with Panel details on the bottom row (activation, OM
% video, CV) shrank to thumbnails, the captions ran into tall narrow
% columns and the activation title overlapped the box above; Save... and
% Save panel... showed the same. The rule (F19, F27): each panel's axes keep
% at least 50 % of their cell's height whatever the caption; longer captions
% are cut with "(more in (i))" and the details box scrolls. Driven through
% Redo projection (map, video and CV, edge weight 0.30 for the long
% captions), headless, on a copy of a completed run.
% At 1500 x 900 and 1920 x 1080, Panel details on:
%   L1  live window: every panel's axes at least 50 % of its cell height
%   L2  live window: each title and caption inside its own cell, clear of
%       every other panel's title, caption and details box
%   L3  saved window (Save...): PNG, JPG and PDF written; the window is
%       saved as it is laid out (exportgraphics of the figure, cropped to
%       what is drawn), so L1/L2 hold for it
%   L4  saved panel (Save panel... route, om_export.save_to): PNG, JPG and
%       PDF written from the axes as drawn (the window's annotations
%       hidden; a copy in a plain figure laid the text out larger, over the
%       colour bar): the axes keep 50 % of the cell height, the title and
%       caption end before the colour bar, and the PNG is as wide as the
%       drawn panel (0.6-1.6 x at 300 dpi)
%   L5  a caption cut to its share ends "(more in (i))"; Panel details off
%       draws the captions as before (no cut)
%   L6  every details box shown opens at its first line (they
%       opened scrolled to the middle): a list at ListboxTop 1
%       with nothing selected
% Panel details off, at both sizes:
%   L7  every panel's axes at least 50 % of its cell height
%   L8  every live caption at most CAPTION_SHORT_LINES (4) lines
%   L9  titles and captions clear of each other and of every panel's
%       scale-bar label ("10 mm")
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_visualise_details_layout" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_visualise_details_layout', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
results = struct('id', {}, 'ok', {}, 'detail', {});
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);

%% The app with the run's dataset, a map, frames and a CV map (as probe_cv_range)
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
app.recon.ReconstructionEdgeWeightField.Value = 0.3;
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
order = getappdata(fig, 'reconstruction_viewer_order');

sizes = [1500 900; 1920 1080];
cut_seen = false;
top_ok = true;
top_why = {};
for z = 1:size(sizes, 1)
    sz = sizes(z, :);
    tag = sprintf('%dx%d', sz);
    fig.Position = [20 20 sz];
    set(pd, 'Value', 1);
    pd.Callback(pd, []);
    tab.viewer_layout(fig, true);
    drawnow;
    [ratios, cap_rects, cell_px] = measure(fig, order);
    boxes = detail_boxes(fig, order);
    %% L1
    results = add(results, ['L1 ' tag ' live: axes >= 50 % of the cell height'], all(ratios >= 0.5 - 1e-3), ...
        sprintf('%s: %s', strjoin(order, '/'), mat2str(ratios, 3)));
    %% L2
    [ok2, why2] = no_collisions(cap_rects, cell_px, boxes);
    results = add(results, ['L2 ' tag ' live: titles and captions in their cells, clear of the others and the boxes'], ok2, why2);
    for t = 1:numel(order)
        ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' order{t}]);
        st = cellstr(ax.Subtitle.String);
        cut_seen = cut_seen || (~isempty(st) && strcmp(st{end}, '(more in (i))'));
        % L6 (R13): each box shown at its top line
        hb = findobj(fig, 'Tag', ['ReconstructionPanelDetailsText_' order{t}]);
        if isscalar(hb) && strcmp(hb.Visible, 'on')
            top_ok = top_ok && strcmp(hb.Style, 'listbox') && hb.ListboxTop == 1 && isempty(hb.Value);
            top_why{end + 1} = sprintf('%s %s top %d', order{t}, hb.Style, hb.ListboxTop); %#ok<AGROW>
        end
    end
    %% L3: Save... as PNG, JPG and PDF
    files = {};
    for e = {'.png', '.jpg', '.pdf'}
        f = fullfile(root, ['window_' tag e{1}]);
        headless_push('uiputfile', f);
        tab.viewer_save_image(fig);
        files{end + 1} = f; %#ok<AGROW>
    end
    [ratios3, cap3] = measure(fig, order);     % the window as it was saved
    im = imread(files{1});
    ok3 = all(cellfun(@(f) fbytes(f) > 1000, files)) && all(ratios3 >= 0.5 - 1e-3) && ...
        no_collisions(cap3, cell_px, boxes) && size(im, 1) > 1000 && size(im, 2) > 1000;
    results = add(results, ['L3 ' tag ' saved window: PNG, JPG, PDF; laid out as L1/L2'], ok3, ...
        sprintf('PNG %dx%d', size(im, 2), size(im, 1)));
    %% L4: Save panel... (om_export.save_to of the panel's axes) and the copied figure
    ok4 = true;
    why4 = {};
    for role = {'projected', 'video', 'cv'}
        ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' role{1}]);
        if isempty(ax), continue; end
        for e = {'.png', '.jpg', '.pdf'}
            f = fullfile(root, sprintf('panel_%s_%s%s', role{1}, tag, e{1}));
            om_export.save_to(ax(1), f);
            keep = getenv('OM_PROBE_KEEP_DIR');                % optional: a folder to keep the pictures in
            if ~isempty(keep) && isfolder(keep), copyfile(f, keep); end
            ok4 = ok4 && fbytes(f) > 1000;
        end
        t = find(strcmp(order, role{1}), 1);
        % The panel is saved from the axes as drawn (om_export.save_figure_part,
        % the window's annotations hidden): its axes against the cell, its
        % text against its colour bar, and the PNG's width against the drawn
        % axes with colour bar and text
        p4 = getpixelposition(ax(1), true);
        r4 = p4(4) / cell_px(t, 4);
        rr4 = text_rect(ax(1));
        cb4 = getpixelposition(ax(1).Colorbar, true);
        clear4 = ~(rr4(1) < cb4(1) + cb4(3) - 2 && cb4(1) < rr4(1) + rr4(3) - 2 && rr4(2) < cb4(2) + cb4(4) - 2 && ...
            cb4(2) < rr4(2) + rr4(4) - 2);
        im4 = imread(fullfile(root, sprintf('panel_%s_%s.png', role{1}, tag)));
        drawn_w = max(cb4(1) + cb4(3) + 40, rr4(1) + rr4(3)) - min(p4(1), rr4(1));   % pixels on screen, with labels
        w_ratio = size(im4, 2) / (drawn_w * 300 / 96);
        ok4 = ok4 && r4 >= 0.5 - 1e-3 && clear4 && w_ratio > 0.6 && w_ratio < 1.6;
        why4{end + 1} = sprintf('%s %.2f, PNG width / drawn %.2f%s', role{1}, r4, w_ratio, repmat(sprintf( ...
            ' (text %s on the colour bar %s)', mat2str(round(rr4)), mat2str(round(cb4))), 1, ~clear4)); %#ok<AGROW>
    end
    results = add(results, ['L4 ' tag ' saved panels: PNG, JPG, PDF; the copied panel keeps 50 % and its text clear'], ok4, ...
        strjoin(why4, ', '));
end

%% L5
set(pd, 'Value', 0);
pd.Callback(pd, []);
drawnow;
none_cut = true;
for t = 1:numel(order)
    ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' order{t}]);
    none_cut = none_cut && ~any(strcmp(cellstr(ax.Subtitle.String), '(more in (i))'));
end
results = add(results, 'L5 a cut caption says "(more in (i))"; Panel details off: no cut', cut_seen && none_cut, ...
    sprintf('cut seen with details on: %d', cut_seen));

%% L6
results = add(results, 'L6 the details boxes open at their first line', top_ok && ~isempty(top_why), strjoin(top_why, ', '));

%% L7-L9: Panel details off (the CV caption
% had grown to about 20 lines, its title ran into the mesh panel's "10 mm"
% scale-bar label and the hearts became thumbnails)
n_short = rabbit_reconstruction_tab.CAPTION_SHORT_LINES;
for z = 1:size(sizes, 1)
    sz = sizes(z, :);
    tag = sprintf('%dx%d', sz);
    fig.Position = [20 20 sz];
    set(pd, 'Value', 0);
    pd.Callback(pd, []);
    tab.viewer_layout(fig, true);
    drawnow;
    [ratios7, rects7, cell7] = measure(fig, order);
    %% L7
    results = add(results, ['L7 ' tag ' details off: axes >= 50 % of the cell height'], all(ratios7(isfinite(ratios7)) >= 0.5 - 1e-3), ...
        sprintf('%s: %s', strjoin(order, '/'), mat2str(ratios7, 3)));
    %% L8
    n8 = zeros(1, numel(order));
    why8 = {};
    for t = 1:numel(order)
        ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' order{t}]);
        if isempty(ax), continue; end
        st = cellstr(ax(1).Subtitle.String);
        n8(t) = numel(st(~cellfun(@isempty, st)));
        why8{end + 1} = sprintf('%s %d', order{t}, n8(t)); %#ok<AGROW>
    end
    results = add(results, sprintf('L8 %s details off: every live caption at most %d lines', tag, n_short), ...
        all(n8 <= n_short), strjoin(why8, ', '));
    %% L9: titles and captions clear of each other and of every scale-bar label
    sl9 = scale_labels(fig, order);
    [ok9, why9] = no_collisions(rects7, cell7, sl9);
    results = add(results, ['L9 ' tag ' details off: titles and captions clear of each other and of the scale-bar labels'], ...
        ok9 && ~isempty(sl9), sprintf('%d scale-bar labels; %s', size(sl9, 1), why9));   % labels found, so the check bites
end

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tg = 'PASS'; else, tg = 'FAIL'; end
    fprintf('%s %s: %s\n', tg, results(k).id, results(k).detail);
end
fprintf('\nPROBE_VISUALISE_DETAILS_LAYOUT RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_visualise_details_layout:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_visualise_details_layout %d/0\n', n_pass);
end


function [ratios, rects, cell_px] = measure(fig, order)
% Axes height / cell height, and the pixel box of each title with its caption
cells = getappdata(fig, 'reconstruction_cells');
fp = getpixelposition(fig);
ratios = nan(1, numel(order));
rects = nan(numel(order), 4);
cell_px = cells .* fp([3 4 3 4]);
for t = 1:numel(order)
    ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' order{t}]);
    if isempty(ax), continue; end
    p = getpixelposition(ax(1));
    ratios(t) = p(4) / cell_px(t, 4);
    rects(t, :) = text_rect(ax(1));
end
end


function r = text_rect(ax)
% The title and caption together, in figure pixels
p = getpixelposition(ax);
r = [Inf Inf -Inf -Inf];
for h = [ax.Title, ax.Subtitle]
    if isempty(h.String) || all(cellfun(@isempty, cellstr(h.String))), continue; end
    u = h.Units; h.Units = 'pixels'; e = h.Extent; h.Units = u;
    r = [min(r(1), p(1) + e(1)), min(r(2), p(2) + e(2)), max(r(3), p(1) + e(1) + e(3)), max(r(4), p(2) + e(2) + e(4))];
end
r = [r(1:2), r(3:4) - r(1:2)];
end


function b = scale_labels(fig, order)
% Every panel's scale-bar label ("10 mm"), in figure pixels
b = zeros(0, 4);
for t = 1:numel(order)
    ax = findobj(fig, 'Type', 'axes', 'Tag', ['panel_' order{t}]);
    if isempty(ax), continue; end
    p = getpixelposition(ax(1));
    for h = reshape(findall(ax(1), 'Tag', 'ReconstructionScaleBarText'), 1, [])
        u = h.Units; h.Units = 'pixels'; e = h.Extent; h.Units = u;
        b(end + 1, :) = [p(1) + e(1), p(2) + e(2), e(3), e(4)]; %#ok<AGROW>
    end
end
end


function b = detail_boxes(fig, order)
b = zeros(0, 4);
for t = 1:numel(order)
    h = findobj(fig, 'Tag', ['ReconstructionPanelDetailsText_' order{t}]);
    if ~isempty(h) && strcmp(get(h(1), 'Visible'), 'on')
        b(end + 1, :) = get(h(1), 'Position'); %#ok<AGROW>
    end
end
end


function [ok, why] = no_collisions(rects, cell_px, boxes)
% Each text box within its cell (2 px slack) and clear of the other text boxes and of every details box
ok = true; why = {};
inter = @(a, b) a(1) < b(1) + b(3) - 1 && b(1) < a(1) + a(3) - 1 && a(2) < b(2) + b(4) - 1 && b(2) < a(2) + a(4) - 1;
for t = 1:size(rects, 1)
    r = rects(t, :);
    if any(~isfinite(r)), continue; end
    c = cell_px(t, :);
    if r(1) < c(1) - 2 || r(2) < c(2) - 2 || r(1) + r(3) > c(1) + c(3) + 2 || r(2) + r(4) > c(2) + c(4) + 2
        ok = false; why{end + 1} = sprintf('panel %d text %s outside its cell %s', t, mat2str(round(r)), mat2str(round(c))); %#ok<AGROW>
    end
    for u = t + 1:size(rects, 1)
        if all(isfinite(rects(u, :))) && inter(r, rects(u, :))
            ok = false; why{end + 1} = sprintf('panels %d and %d text overlap', t, u); %#ok<AGROW>
        end
    end
    for k = 1:size(boxes, 1)
        if inter(r, boxes(k, :))
            ok = false; why{end + 1} = sprintf('panel %d text over details box %d', t, k); %#ok<AGROW>
        end
    end
end
why = strjoin(why, '; ');
if isempty(why), why = 'no collisions'; end
end



function n = fbytes(f)
% The size of a file in bytes, 0 when it is not there
d = dir(f);
n = 0;
if isscalar(d), n = d.bytes; end
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
