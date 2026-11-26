classdef om_export
    %% Save a data visual as PNG, JPG or PDF, and a graph's data as CSV
    % Collin Snitchler
    % 23.11.2026
    % Shared by the apps of this repository. attach(ax, spec) gives a data
    % axes two routes to the same handler (save_dialog): a save button on
    % the axes toolbar and a right-click menu ("Save as PNG / JPG / PDF..."
    % and, for graphs and maps, "Save data as CSV..."). The format is taken
    % from the file name's extension (or the file type picked in the dialog).
    % Pictures: exportgraphics at 300 dpi, with the axes' title, colour bar
    % and legend. PDF: vector content for 2D graphs, an embedded 300 dpi
    % image for image maps and 3D panels (spec.content), because a vector
    % PDF of an image or of a mesh with many faces is large and slow. An
    % image PDF is the PNG picture on a page of its own size, so the page
    % is cropped as the PNG is.
    % CSV: exactly the plotted data. Graphs get one header row of names with
    % units (e.g. time_s, roi1_signal_au), NaN as an empty cell; maps are
    % the plain matrix with no header, NaN as the text NaN (readmatrix
    % drops empty rows and columns at a map's edge). Numbers are written
    % with as few digits as read back to the same double.
    % A CSV writer with nothing to write raises om_export:Empty; the user
    % is then told that there is nothing to save yet, before any file
    % dialog (csv_empty runs the writer as a dry run first).
    % PDF in the file dialog: "PDF (vector)" or "PDF (image, 300 dpi)", as
    % spec.content. The toolbar button's tooltip names CSV only where the
    % visual has a CSV.
    % Headless (OM_APP_HEADLESS=1, scripts and tests): report prints the
    % message instead of showing a dialog.
    % spec fields (all optional):
    %   name      default file name (no extension) for pictures, or @() name
    %   csv_name  default file name for the CSV, or @() name
    %   folder    default folder, or @() folder
    %   csv       @(path) writes the CSV (no CSV item without it)
    %   render    @(path, content) writes the picture itself (instead of
    %             exporting the axes, e.g. the main view's rebuilt figure)
    %   targets   @() the axes to save together (overlaid axes)
    %   title     @() a title put on the axes while the picture is saved
    %             (for a window whose title is a label outside the axes)
    %   content   'vector' (default) or 'image', for PDF
    %   toolbar   'default' for an axes that shows MATLAB's default
    %             toolbar: the same buttons as MATLAB shows for what is
    %             drawn, plus the save button; 'save' for an axes whose
    %             toolbar was hidden: the save button only (so MATLAB's
    %             own export button does not appear where it was not);
    %             'none': no toolbar (the caller gives a button of its own)
    %   menu_text the right-click item for pictures
    %   footer    @() a line (or lines) of text put under a saved picture
    %   prepare   @() a value kept while a picture is saved (e.g. an
    %             onCleanup that puts the window back afterwards)
    %   after     @(path) called when the file dialog closes: the saved
    %             file, or '' when nothing was saved
    % Usage:
    %   om_export.attach(ax, struct('name', 'apd_trace', 'csv', @(p) ...));
    %   om_export.save_to(ax, 'trace.pdf');   % no dialog (scripts, tests)

    properties (Constant)
        TOOLTIP = 'Save as PNG, JPG or PDF...'
        CSV_TOOLTIP = 'Save as PNG, JPG or PDF, or the data as CSV...'
        BUTTON_TAG = 'om_export_save'
    end

    methods (Static)
        function attach(ax, spec)
            %% Give a data axes its save button, right-click menu and spec
            % Safe to call again on the same axes: the spec is replaced and
            % the button and menu are only added when missing.
            if nargin < 2 || isempty(spec)
                spec = struct();
            end
            if isempty(ax) || ~isgraphics(ax)
                return;
            end
            spec = om_export.defaults(spec);
            setappdata(ax, 'om_export', spec);
            om_export.add_button(ax, spec.toolbar, ~isempty(spec.csv));
            om_export.add_menu(ax, ~isempty(spec.csv), spec.menu_text);
            % Objects drawn later (imshow, plot) get the same right-click
            % menu: a right-click on them does not reach the axes' menu
            om_export.claim_children(ax);
            if ~isappdata(ax, 'om_export_listener')
                try
                    lis = addlistener(ax, 'ChildAdded', @(src, ~) om_export.refresh(src));
                    setappdata(ax, 'om_export_listener', lis);
                catch
                    % no ChildAdded event: the children are claimed when
                    % the menu is next attached
                end
            end
        end

        function ok = has_button(ax)
            %% True when the axes toolbar has the save button
            ok = false;
            try
                tb = ax.Toolbar;
                ok = ~isempty(tb) && isvalid(tb) && ~isempty(findobj(tb.Children, 'Tag', om_export.BUTTON_TAG));
            catch
                % no axes toolbar
            end
        end

        function [path, err] = save_dialog(ax, what)
            %% Ask for a file name, then save; what = 'image', 'csv' or 'any'
            % The toolbar button calls this with 'any', the right-click
            % items with 'image' and 'csv'. A CSV with nothing to write is
            % found before the dialog (csv_empty), and the user is told so
            % at once, without being asked for a file name.
            path = ''; err = '';
            spec = om_export.spec_of(ax);
            if isempty(spec)
                return;
            end
            if nargin < 2
                what = 'any';
            end
            if strcmp(what, 'csv') && ~isempty(spec.csv)
                err = om_export.csv_empty(spec);
                if ~isempty(err)
                    om_export.report(ax, err, 'Nothing to save yet', 'info');
                    return;
                end
            end
            pdf = 'PDF (vector) (*.pdf)';
            if strcmp(spec.content, 'image'), pdf = 'PDF (image, 300 dpi) (*.pdf)'; end
            images = {'*.png', 'PNG image (*.png)'; '*.jpg', 'JPEG image (*.jpg)'; '*.pdf', pdf};
            csv = {'*.csv', 'CSV data (*.csv)'};
            switch what
                case 'csv'
                    filters = csv;
                case 'image'
                    filters = images;
                otherwise
                    filters = images;
                    if ~isempty(spec.csv)
                        filters = [images; csv];
                    end
            end
            if strcmp(what, 'csv')
                stem = om_export.value(spec.csv_name);
            else
                stem = om_export.value(spec.name);
            end
            folder = om_export.value(spec.folder);
            suggestion = [om_export.safe_name(stem) filters{1, 1}(2:end)];
            if ~isempty(folder) && isfolder(folder)
                suggestion = fullfile(folder, suggestion);
            end
            [f, p, idx] = uiputfile(filters, 'Save', suggestion);
            if isequal(f, 0)
                om_export.after_dialog(spec, '');
                return;
            end
            path = fullfile(p, f);
            [~, ~, e] = fileparts(path);
            if isempty(e) && idx >= 1 && idx <= size(filters, 1)
                path = [path filters{idx, 1}(2:end)];   % the file type picked in the dialog
            end
            saved = path;
            try
                om_export.save_to(ax, path);
            catch ME
                saved = '';
                err = ME.message;
                if strcmp(ME.identifier, 'om_export:Empty')
                    om_export.report(ax, err, 'Nothing to save yet', 'info');
                else
                    om_export.report(ax, sprintf('Could not save %s: %s', path, err), 'Save', 'error');
                end
            end
            om_export.after_dialog(spec, saved);
        end

        function save_to(ax, path)
            %% Save the visual of ax to path; the extension gives the format
            spec = om_export.spec_of(ax);
            if isempty(spec)
                error('om_export:NoSpec', 'This axes has nothing to save.');
            end
            [~, ~, e] = fileparts(path);
            switch lower(e)
                case '.csv'
                    if isempty(spec.csv)
                        error('om_export:NoData', 'This visual has no data to save as CSV.');
                    end
                    spec.csv(path);
                case {'.png', '.jpg', '.jpeg', '.pdf'}
                    if ~isempty(spec.render)
                        spec.render(path, spec.content);
                    else
                        prepared = []; %#ok<NASGU>
                        if ~isempty(spec.prepare), prepared = spec.prepare(); end %#ok<NASGU>
                        if isempty(spec.targets)
                            targets = ax;
                        else
                            targets = spec.targets();
                        end
                        footer = {};
                        if ~isempty(spec.footer)
                            try
                                footer = cellstr(spec.footer());
                            catch ME
                                % the picture is saved without it
                                warning('om_export:Footer', 'No footer line: %s', ME.message);
                            end
                        end
                        restore = om_export.temporary_title(ax, spec.title); %#ok<NASGU>
                        om_export.save_figure_part(targets, path, spec.content, footer);
                    end
                otherwise
                    if isempty(spec.csv)
                        error('om_export:Format', 'Save as .png, .jpg or .pdf (not "%s").', e);
                    end
                    error('om_export:Format', 'Save as .png, .jpg, .pdf or .csv (not "%s").', e);
            end
        end

        function save_figure_part(target, path, content, footer)
            %% exportgraphics of one axes, several overlaid axes or a figure
            % Pictures at 300 dpi. PDF: content 'vector' (2D graphs) or
            % 'image' (a 300 dpi picture in the PDF: image maps, 3D panels).
            % footer (optional): text lines put under the picture, left
            % aligned, as a strip of their own (append_footer); a vector
            % PDF gets none.
            if nargin < 3 || isempty(content)
                content = 'vector';
            end
            if nargin < 4 || isempty(footer)
                footer = {};
            end
            footer = cellstr(footer);
            [~, ~, e] = fileparts(path);
            if strcmpi(e, '.pdf') && strcmp(content, 'image')
                % The PNG picture (cropped to what is drawn) on a page of
                % its size: exportgraphics does not crop an image PDF, so
                % a panel was a speck on a page the size of the helper
                % figure
                png = [tempname '.png'];
                remove = onCleanup(@() delete_if_there(png)); %#ok<NASGU>
                om_export.save_figure_part(target, png, 'image', footer);
                om_export.png_to_pdf(png, path);
                return;
            end
            opts = {'Resolution', 300};
            if strcmpi(e, '.pdf')
                if strcmp(content, 'vector')
                    opts = {'ContentType', 'vector'};
                else
                    opts = {'ContentType', 'image', 'Resolution', 300};
                end
            end
            target = target(isgraphics(target));
            if isempty(target)
                error('om_export:Nothing', 'Nothing is shown to save.');
            end
            % A figure, or one axes in a window without annotations, is
            % saved as it is. One axes in a window with annotations (a
            % window title or note, as Visualise has) is copied first:
            % exportgraphics of the axes also takes in the annotations,
            % which span the whole window, so the picture would be mostly
            % empty space
            if ~any(strcmpi(e, {'.png', '.jpg', '.jpeg'})), footer = {}; end
            if isscalar(target) && (isa(target, 'matlab.ui.Figure') || ...
                    ~isa(target, 'matlab.graphics.axis.Axes') || ~om_export.has_annotations(target))
                exportgraphics(target, path, opts{:});
                om_export.append_footer(path, footer);
                return;
            end
            % One axes of a window with annotations: the axes as drawn on
            % screen, with the window's annotations hidden while it is
            % saved (a copy in a plain figure lays its text out larger,
            % so a Visualise panel's caption would run under its colour
            % bar in the saved picture)
            if isscalar(target) && isa(target, 'matlab.graphics.axis.Axes')
                panes = findall(ancestor(target, 'figure'), 'Type', 'annotationpane');
                was = get(panes, {'Visible'});
                set(panes, 'Visible', 'off');
                put_back = onCleanup(@() set(panes, {'Visible'}, was));
                exportgraphics(target, path, opts{:});
                clear put_back
                om_export.append_footer(path, footer);
                return;
            end
            % Axes copied into a hidden figure at the same places, with
            % their legends and colour bars, saved as one picture
            % The hidden figure is the window's size plus room on every
            % side, and the copies keep their places, so titles, captions
            % and labels that reach outside the axes (or past the window's
            % edge) are not cut off; exportgraphics crops the picture to
            % what is drawn
            src = ancestor(target(1), 'figure');
            pos = zeros(numel(target), 4);
            for k = 1:numel(target)
                pos(k, :) = getpixelposition(target(k), true);
            end
            src_px = getpixelposition(src);
            % The colour bars and legends where they are on screen, next
            % to their axes: left to place themselves by the copy, a
            % colour bar sat over the captions (Visualise, Panel details)
            side = cell(numel(target), 1);
            for k = 1:numel(target)
                side{k} = om_export.side_offsets(target(k));
            end
            room = 400;   % pixels around the window's area: text may reach past its edge
            tmp = figure('Visible', 'off', 'Units', 'pixels', 'Color', src.Color, ...
                'Position', [50 50 src_px(3:4) + 2 * room]);
            cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
            for k = 1:numel(target)
                a = target(k);
                objs = a;
                if isprop(a, 'Legend') && ~isempty(a.Legend) && isgraphics(a.Legend)
                    objs = [a.Legend, objs]; %#ok<AGROW>
                end
                if isprop(a, 'Colorbar') && ~isempty(a.Colorbar) && isgraphics(a.Colorbar)
                    objs = [a.Colorbar, objs]; %#ok<AGROW>
                end
                c = copyobj(objs, tmp);
                ca = c(end);   % the copied axes (copyobj keeps the order)
                ca.Units = 'pixels';
                ca.Position = [pos(k, 1:2) + room, pos(k, 3:4)];
                for j = 1:numel(c) - 1
                    off = side{k}.(lower(c(j).Type));
                    if ~isempty(off)
                        c(j).Units = 'pixels';
                        c(j).Position = [pos(k, 1:2) + room + off(1:2), off(3:4)];
                    end
                end
            end
            exportgraphics(tmp, path, opts{:});
            om_export.append_footer(path, footer);
        end


        function append_footer(path, lines)
            %% Text lines added under a saved PNG or JPG, as a strip of its own
            % The lines are drawn at 7 pt and 300 dpi in a hidden figure,
            % saved, and put under the picture, left aligned; the narrower
            % of the two is padded with white. Below everything drawn, so
            % the footer never covers the picture.
            lines = cellstr(lines);
            if ~isfile(path) || isempty(lines) || all(cellfun(@isempty, lines)), return; end
            img = imread(path);
            % Lines wrapped at spaces to the picture's width (about 0.55 of
            % the 7 pt font's size a character)
            w_px = max(400, size(img, 2) * 96 / 300);
            n_max = max(40, floor(w_px / (0.55 * 7 * 96 / 72)));
            % "left<TAB>right" lines are two
            % columns (footer_columns); left lines go in one text block at
            % the left edge, right lines in one from the middle, so the
            % columns line up whatever the font
            % A first line "NOT FOR ANALYSIS ..." is
            % drawn in red over its own rows (blank at the top of every column)
            red = {};
            if startsWith(lines{1}, 'NOT FOR ANALYSIS')
                red = om_export.wrap_words(lines{1}, n_max);
                red = reshape(cellstr(red), 1, []);
                lines = lines(2:end);
            end
            % A line with n tabs is a row of n + 1
            % columns, each block in its own column (footer_grid)
            cols = om_export.footer_grid(lines, n_max);
            for j = 1:numel(cols), cols{j} = [repmat({''}, 1, numel(red)), reshape(cols{j}, 1, [])]; end
            left = cols{1};
            lines = left;
            % An empty line is drawn as a space, so every line keeps its height
            for j = 1:numel(cols), cols{j}(cellfun(@isempty, cols{j})) = {' '}; end
            left = cols{1};
            f = figure('Visible', 'off', 'Units', 'pixels', 'Color', 'w', 'Tag', 'om_export_footer', ...
                'DeleteFcn', '', 'Position', [50 50 w_px 12 * numel(lines) + 8]);
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            a = axes(f, 'Units', 'normalized', 'Position', [0 0 1 1], 'Visible', 'off');
            text(a, 0.005, 0.95, left, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
                'HorizontalAlignment', 'left', 'Interpreter', 'none', 'FontSize', 7, 'Color', [0.2 0.2 0.2], ...
                'Tag', 'om_export_footer_left');
            if ~isempty(red)   % the verdict in red, on the rows kept blank for it
                text(a, 0.005, 0.95, red, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
                    'HorizontalAlignment', 'left', 'Interpreter', 'none', 'FontSize', 7, 'Color', [0.8 0 0], ...
                    'FontWeight', 'bold', 'Tag', 'om_export_footer_verdict');
            end
            % The other columns, each from its share of the width (as
            % many as the row has panels; slots no run uses are empty and
            % not drawn)
            for j = 2:numel(cols)
                if all(strcmp(cols{j}, ' ') | strcmp(cols{j}, '')), continue; end
                tag = sprintf('om_export_footer_col%d', j);
                if numel(cols) == 2, tag = 'om_export_footer_right'; end
                text(a, 0.005 + (j - 1) / numel(cols), 0.95, cols{j}, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
                    'HorizontalAlignment', 'left', 'Interpreter', 'none', 'FontSize', 7, 'Color', [0.2 0.2 0.2], ...
                    'Tag', tag);
            end
            strip_png = [tempname '.png'];
            remove = onCleanup(@() delete_if_there(strip_png)); %#ok<NASGU>
            exportgraphics(f, strip_png, 'Resolution', 300);
            strip = imread(strip_png);
            if size(img, 3) == 1, img = repmat(img, 1, 1, 3); end
            strip = cast(strip, 'like', img);
            gap = 24;   % pixels between the picture and the footer at 300 dpi
            w = max(size(img, 2), size(strip, 2));
            white = intmax(class(img));
            out = repmat(white, size(img, 1) + gap + size(strip, 1), w, 3);
            out(1:size(img, 1), 1:size(img, 2), :) = img;
            out(size(img, 1) + gap + (1:size(strip, 1)), 1:size(strip, 2), :) = strip;
            imwrite(out, path);
        end

        function [left, right] = footer_columns(lines, n_max)
            %% A footer's lines, wrapped, as a left and a right column of the same length
            % A line "left<TAB>right" is a row of
            % two columns. A run of such lines is split into its left and
            % right column, each wrapped at spaces to half of n_max
            % characters, its trailing empty lines (padding) dropped, and
            % the shorter padded with '' to the longer, so the next run
            % starts under both. Other lines are wrapped to n_max and span
            % the width (right '').
            lines = cellstr(lines);
            left = {};
            right = {};
            k = 1;
            while k <= numel(lines)
                if ~contains(lines{k}, char(9))
                    w = om_export.wrap_words(lines{k}, n_max);
                    left = [left, w]; %#ok<AGROW>
                    right = [right, repmat({''}, 1, numel(w))]; %#ok<AGROW>
                    k = k + 1;
                    continue;
                end
                L = {}; R = {};
                while k <= numel(lines) && contains(lines{k}, char(9))
                    t = strfind(lines{k}, char(9));
                    L{end + 1} = lines{k}(1:t(1) - 1); %#ok<AGROW>
                    R{end + 1} = lines{k}(t(1) + 1:end); %#ok<AGROW>
                    k = k + 1;
                end
                half = max(20, floor(n_max / 2) - 2);   % a gap between the columns
                wl = {}; wr = {};
                for j = 1:numel(L), wl = [wl, om_export.wrap_words(L{j}, half)]; end %#ok<AGROW>
                for j = 1:numel(R), wr = [wr, om_export.wrap_words(R{j}, half)]; end %#ok<AGROW>
                while ~isempty(wl) && isempty(strtrim(wl{end})), wl(end) = []; end
                while ~isempty(wr) && isempty(strtrim(wr{end})), wr(end) = []; end
                n = max(numel(wl), numel(wr));
                wl(end + 1:n) = {''}; wr(end + 1:n) = {''};
                left = [left, wl]; %#ok<AGROW>
                right = [right, wr]; %#ok<AGROW>
            end
        end

        function cols = footer_grid(lines, n_max)
            %% A footer's lines, wrapped, as columns of the same length
            % A line with tabs is a row of columns, one more than its tabs.
            % A run of such lines (the same number of columns) is split
            % into its columns, each wrapped at spaces to its share of
            % n_max characters, trailing empty lines dropped and the shorter
            % padded with ''. Other lines span the width (the other columns
            % ''). cols: 1 x n cell of equal-length cell rows, one per
            % slot of the width; n is the least common multiple of the
            % runs' column counts, so each run keeps its own shares (a row
            % of three panels under a row of four: thirds under quarters).
            % Slots no run uses stay ''.
            lines = cellstr(lines);
            n_all = 1;
            for k = 1:numel(lines), n_all = lcm(n_all, 1 + numel(strfind(lines{k}, char(9)))); end
            cols = repmat({{}}, 1, n_all);
            k = 1;
            while k <= numel(lines)
                n = 1 + numel(strfind(lines{k}, char(9)));
                if n == 1
                    w = om_export.wrap_words(lines{k}, n_max);
                    cols{1} = [cols{1}, w];
                    for j = 2:n_all, cols{j} = [cols{j}, repmat({''}, 1, numel(w))]; end
                    k = k + 1;
                    continue;
                end
                parts = repmat({{}}, 1, n);
                while k <= numel(lines) && 1 + numel(strfind(lines{k}, char(9))) == n
                    f = strsplit(lines{k}, char(9), 'CollapseDelimiters', false);
                    for j = 1:n, parts{j}{end + 1} = f{j}; end
                    k = k + 1;
                end
                width = max(20, floor(n_max / n) - 2);   % a gap between the columns
                wrapped = cell(1, n);
                for j = 1:n
                    wj = {};
                    for i = 1:numel(parts{j}), wj = [wj, om_export.wrap_words(parts{j}{i}, width)]; end %#ok<AGROW>
                    while ~isempty(wj) && isempty(strtrim(wj{end})), wj(end) = []; end
                    wrapped{j} = wj;
                end
                m = max(cellfun(@numel, wrapped));
                % Column j of a run of n goes to the slot where its share of
                % the width starts
                for j = 1:n_all, cols{j} = [cols{j}, repmat({''}, 1, m)]; end
                base = numel(cols{1}) - m;
                for j = 1:n
                    c = 1 + (j - 1) * n_all / n;
                    w = wrapped{j};
                    cols{c}(base + (1:numel(w))) = w;
                end
            end
        end

        function out = wrap_words(line, n_max)
            %% One line wrapped at spaces to at most n_max characters a line (a longer word stays whole)
            words = strsplit(line, ' ');
            out = {};
            cur = '';
            for j = 1:numel(words)
                if isempty(cur), cur = words{j};
                elseif numel(cur) + 1 + numel(words{j}) <= n_max, cur = [cur ' ' words{j}]; %#ok<AGROW>
                else, out{end + 1} = cur; cur = words{j}; %#ok<AGROW>
                end
            end
            out{end + 1} = cur;
        end

        function png_to_pdf(png, path)
            %% A PNG picture as a PDF page of the same size, at 300 dpi
            img = imread(png);
            px = [size(img, 2), size(img, 1)] * 96 / 300;   % the page in screen pixels at 300 dpi
            f = figure('Visible', 'off', 'Units', 'pixels', 'Position', [50 50 px], 'Color', 'w', ...
                'Tag', 'om_export_pdf_page');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            a = axes(f, 'Units', 'normalized', 'Position', [0 0 1 1]);
            image(a, img);
            axis(a, 'off');
            a.XLim = [0.5, size(img, 2) + 0.5];
            a.YLim = [0.5, size(img, 1) + 0.5];
            exportgraphics(f, path, 'ContentType', 'image', 'Resolution', 300);
        end

        function report(ax, msg, title, icon)
            %% Tell the user: a failed save, nothing to save yet, a note
            % uialert in the window of ax. OM_APP_HEADLESS=1 (scripts and
            % tests): no dialog on screen; the message is printed (in a
            % hidden window, uialert is the tests' headless stand-in)
            if nargin < 3, title = 'Save'; end
            if nargin < 4, icon = 'error'; end
            % A message that starts with its title ("Nothing to save yet:
            % no histogram is shown.", as om_export:Empty says it) gives
            % the title once: printed as it is, shown without it under
            % the title
            lead = [title ': '];
            if startsWith(msg, lead)
                printed = msg;
                msg = strtrim(msg(numel(lead) + 1:end));
                if ~isempty(msg), msg(1) = upper(msg(1)); end
            else
                printed = sprintf('%s: %s', title, msg);
            end
            fig = ancestor(ax, 'figure');
            if strcmp(getenv('OM_APP_HEADLESS'), '1') && (isempty(fig) || strcmp(fig.Visible, 'on'))
                fprintf('%s\n', printed);
                return;
            end
            try
                if matlab.ui.internal.isUIFigure(fig)
                    uialert(fig, msg, title, 'Icon', icon);
                elseif strcmp(icon, 'error')
                    errordlg(msg, title);
                else
                    msgbox(msg, title, 'help');
                end
            catch
                warning('om_export:SaveFailed', '%s', msg);
            end
        end

        function tf = has_annotations(ax)
            %% True when the window of ax has annotations (text boxes, arrows)
            fig = ancestor(ax, 'figure');
            tf = ~isempty(fig) && ~isempty(findall(fig, 'Type', 'annotationpane'));
        end

        function write_table(path, header, cols)
            %% CSV with one header row; columns may differ in length
            % cols: cell array of vectors, one per header name. Missing
            % rows and NaN are empty cells. A column of text (string array
            % or cell array of char) is written as it is: its
            % entries must hold no comma or quote; '' is an empty cell.
            om_export.dry_stop();
            n = max([0, cellfun(@numel, cols)]);
            cells = strings(n, numel(cols));
            for k = 1:numel(cols)
                v = cols{k};
                if isstring(v) || iscellstr(v)
                    cells(1:numel(v), k) = string(v(:));
                else
                    cells(1:numel(v), k) = om_export.num_text(v);
                end
            end
            body = join(cells, ',', 2);
            om_export.write_lines(path, [string(strjoin(header, ',')); body]);
        end

        function write_matrix(path, M)
            %% A map as a plain CSV matrix: no header, NaN as the text NaN
            % Reads straight back with readmatrix at the map's size (empty
            % cells at its edges would be trimmed), as Save image's CSV
            % (writematrix) did before.
            om_export.dry_stop();
            M = double(M);
            txt = om_export.num_text(M(:));
            txt(isnan(M(:))) = "NaN";
            cells = reshape(txt, size(M, 1), size(M, 2));
            om_export.write_lines(path, join(cells, ',', 2));
        end

        function write_series(path, series)
            %% CSV of plotted lines: x column(s), then each series' values
            % series: struct array with fields h (line or errorbar), x and
            % y (column names with units) and err (column name for an
            % errorbar's error, or ''). A series whose XData equals the
            % previous series' shares its x column.
            om_export.dry_stop();
            header = {}; cols = {};
            last_x = [];
            for k = 1:numel(series)
                s = series(k);
                x = double(s.h.XData(:));
                y = double(s.h.YData(:));
                if k == 1 || ~isequaln(x, last_x)
                    header{end + 1} = s.x; %#ok<AGROW>
                    cols{end + 1} = x; %#ok<AGROW>
                    last_x = x;
                end
                header{end + 1} = s.y; %#ok<AGROW>
                cols{end + 1} = y; %#ok<AGROW>
                if isfield(s, 'err') && ~isempty(s.err) && isprop(s.h, 'YPositiveDelta')
                    up = double(s.h.YPositiveDelta(:));
                    down = double(s.h.YNegativeDelta(:));
                    if isequaln(up, down)
                        header{end + 1} = s.err; %#ok<AGROW>
                        cols{end + 1} = up; %#ok<AGROW>
                    else
                        header = [header, {[s.err '_plus'], [s.err '_minus']}]; %#ok<AGROW>
                        cols = [cols, {up, down}]; %#ok<AGROW>
                    end
                end
            end
            om_export.write_table(path, header, cols);
        end

        function write_long(path, header, ids, handles)
            %% CSV in long format: id, x, y per plotted point
            % header: three names, e.g. {'beat', 'time_ms', 'signal_au'};
            % ids(k) is written on every row of handles(k).
            om_export.dry_stop();
            id_col = []; x_col = []; y_col = [];
            for k = 1:numel(handles)
                x = double(handles(k).XData(:));
                id_col = [id_col; repmat(ids(k), numel(x), 1)]; %#ok<AGROW>
                x_col = [x_col; x]; %#ok<AGROW>
                y_col = [y_col; double(handles(k).YData(:))]; %#ok<AGROW>
            end
            om_export.write_table(path, header, {id_col, x_col, y_col});
        end

        function write_histogram(path, h, quantity)
            %% CSV of a histogram: bin edges and values
            % quantity names the binned values with their unit, e.g.
            % 'activation_ms' -> bin_lower_activation_ms, bin_upper_..., count.
            % h: a histogram, or a struct with its BinEdges, Values and
            % Normalization (bins worked out for the export)
            if isempty(h) || (~isstruct(h) && ~isgraphics(h(1)))
                error('om_export:Empty', 'Nothing to save yet: no histogram is shown.');
            end
            om_export.dry_stop();
            h = h(1);
            edges = double(h.BinEdges(:));
            norm = char(h.Normalization);
            om_export.write_table(path, {['bin_lower_' quantity], ['bin_upper_' quantity], norm}, ...
                {edges(1:end - 1), edges(2:end), double(h.Values(:))});
        end

        function txt = num_text(v)
            %% Numbers as text that reads back to the same double; NaN -> ""
            v = double(v(:));
            txt = strings(numel(v), 1);
            idx = find(~isnan(v));
            if isempty(idx)
                return;
            end
            s = string(compose('%.15g', v(idx)));
            redo = str2double(s) ~= v(idx);   % 15 digits are not always enough
            s(redo) = string(compose('%.17g', v(idx(redo))));
            txt(idx) = s;
        end

        function msg = csv_empty(spec)
            %% The "nothing to save yet" message of a CSV with nothing to write, else ''
            % The spec's CSV writer runs as a dry run: the om_export
            % writers stop before writing anything (dry_stop), so only
            % its own om_export:Empty check can end it. Any other outcome
            % leaves the save to the file dialog.
            msg = '';
            setappdata(groot, 'om_export_dry_run', true);
            reset = onCleanup(@() setappdata(groot, 'om_export_dry_run', false)); %#ok<NASGU>
            try
                spec.csv(fullfile(tempdir, 'om_export_dry_run.csv'));
            catch ME
                if strcmp(ME.identifier, 'om_export:Empty')
                    msg = ME.message;
                end
            end
        end

        function name = safe_name(name)
            %% A file name without characters that file systems refuse
            name = regexprep(char(name), '[\\/:*?"<>|%\s]+', '_');
            if isempty(name)
                name = 'figure';
            end
        end
    end

    methods (Static, Access = private)
        function spec = defaults(spec)
            %% Fill the spec's missing fields
            d = struct('name', 'figure', 'csv_name', '', 'folder', '', 'csv', [], 'render', [], ...
                'targets', [], 'title', [], 'content', 'vector', 'toolbar', 'default', ...
                'menu_text', 'Save as PNG / JPG / PDF...', 'footer', [], 'prepare', [], 'after', []);
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(spec, f{k})
                    spec.(f{k}) = d.(f{k});
                end
            end
            if isempty(spec.csv_name)
                spec.csv_name = spec.name;
            end
        end

        function spec = spec_of(ax)
            %% The spec stored on the axes, or [] when there is none
            spec = [];
            if ~isempty(ax) && isgraphics(ax) && isappdata(ax, 'om_export')
                spec = getappdata(ax, 'om_export');
            end
        end

        function v = value(x)
            %% A spec value that may be given as a function
            if isa(x, 'function_handle')
                v = x();
            else
                v = x;
            end
            v = char(v);
        end

        function dry_stop()
            %% In a dry run (csv_empty), stop before anything is written
            if isequal(getappdata(groot, 'om_export_dry_run'), true)
                error('om_export:DryRun', 'Dry run: there is data to write.');
            end
        end

        function after_dialog(spec, path)
            %% spec.after with the saved file ('' when nothing was saved)
            if isempty(spec.after), return; end
            try
                spec.after(path);
            catch
                % a note after the save must not turn it into a failure
            end
        end

        function add_button(ax, mode, has_csv)
            %% The save button on the axes toolbar (made again if missing)
            % MATLAB's default toolbar cannot take extra buttons, so a new
            % one is made: MATLAB's default buttons plus save, or save
            % alone. Of its default buttons MATLAB shows those that fit
            % what is drawn: rotate only on a 3D view, brush only when
            % there is data to brush (no brush on an image). A toolbar
            % made with axtoolbar(ax, 'default') before the drawing, as
            % here, keeps them as they were then, so after each drawing
            % they are shown or hidden by the same rule
            % (show_default_buttons; probe_export_visuals compares it
            % with MATLAB's own choice). Mode 'none': no toolbar at all.
            if nargin < 3, has_csv = false; end
            if strcmp(mode, 'none')
                try
                    ax.Toolbar.Visible = 'off';
                catch
                    % no axes toolbar in this MATLAB release
                end
                return;
            end
            if om_export.has_button(ax)
                if strcmp(mode, 'default')
                    om_export.show_default_buttons(ax);
                end
                return;
            end
            try
                if strcmp(mode, 'save')
                    tb = axtoolbar(ax, {});
                else
                    tb = axtoolbar(ax, 'default');
                end
                tip = om_export.TOOLTIP;
                if has_csv, tip = om_export.CSV_TOOLTIP; end
                axtoolbarbtn(tb, 'push', 'Tag', om_export.BUTTON_TAG, 'Icon', om_export.icon(), ...
                    'Tooltip', tip, 'ButtonPushedFcn', @(~, ~) om_export.save_dialog(ax, 'any'));
                tb.Visible = 'on';
                if strcmp(mode, 'default')
                    om_export.show_default_buttons(ax);
                end
            catch
                % no axes toolbar in this MATLAB release: the right-click
                % menu is the route
            end
        end

        function show_default_buttons(ax)
            %% Rotate, brush and data tips shown as MATLAB's default toolbar shows them
            % rotate: a 3D view; brush: lines, scatter, surfaces, bars,
            % stairs, stems, areas or error bars drawn; data tips:
            % anything drawn
            types = {};
            if ~isempty(ax.Children)
                types = get(ax.Children, {'Type'});
            end
            brushable = any(ismember(types, {'line', 'scatter', 'surface', 'bar', 'stair', 'stem', 'area', 'errorbar'}));
            is3d = ~isequal(round(ax.View), [0 90]);
            tb = ax.Toolbar;
            onoff = {'off', 'on'};
            for k = 1:numel(tb.Children)
                switch tb.Children(k).Tag
                    case 'rotate', tb.Children(k).Visible = onoff{1 + is3d};
                    case 'brush', tb.Children(k).Visible = onoff{1 + brushable};
                    case 'datacursor', tb.Children(k).Visible = onoff{1 + ~isempty(types)};
                end
            end
        end

        function add_menu(ax, has_csv, text)
            %% The right-click items on the axes' menu (made if it has none)
            fig = ancestor(ax, 'figure');
            cm = ax.ContextMenu;
            if isempty(cm) || ~isgraphics(cm)
                cm = uicontextmenu(fig);
                ax.ContextMenu = cm;
            end
            others = ~isempty(cm.Children) && isempty(findobj(cm, '-regexp', 'Tag', '^om_export'));
            if isempty(findobj(cm, 'Tag', 'om_export_image'))
                m = uimenu(cm, 'Text', text, 'Tag', 'om_export_image', ...
                    'MenuSelectedFcn', @(~, ~) om_export.save_dialog(ax, 'image'));
                if others
                    m.Separator = 'on';
                end
            end
            csv_item = findobj(cm, 'Tag', 'om_export_csv');
            if has_csv && isempty(csv_item)
                uimenu(cm, 'Text', 'Save data as CSV...', 'Tag', 'om_export_csv', ...
                    'MenuSelectedFcn', @(~, ~) om_export.save_dialog(ax, 'csv'));
            elseif ~has_csv && ~isempty(csv_item)
                delete(csv_item);
            end
        end

        function refresh(ax)
            %% After something was drawn: button, menu and children again
            % imshow and plot on axes that are not held reset the axes'
            % properties, which can take the toolbar and the menu away.
            spec = om_export.spec_of(ax);
            if isempty(spec)
                return;
            end
            om_export.add_button(ax, spec.toolbar, ~isempty(spec.csv));
            om_export.add_menu(ax, ~isempty(spec.csv), spec.menu_text);
            om_export.claim_children(ax);
        end

        function claim_children(ax)
            %% The axes' menu on drawn objects that have none of their own
            % ROI objects (images.roi) keep theirs.
            if ~isgraphics(ax) || isempty(ax.ContextMenu)
                return;
            end
            kids = ax.Children;
            for k = 1:numel(kids)
                c = kids(k);
                if startsWith(class(c), 'matlab.graphics.') && isprop(c, 'ContextMenu') && isempty(c.ContextMenu)
                    c.ContextMenu = ax.ContextMenu;
                end
            end
        end

        function restore = temporary_title(ax, title_fn)
            %% Put spec.title on the axes until restore is cleared
            restore = [];
            if isempty(title_fn)
                return;
            end
            old = ax.Title.String;
            ax.Title.String = title_fn();
            restore = onCleanup(@() set(ax.Title, 'String', old));
        end

        function off = side_offsets(ax)
            %% Colour bar and legend of ax: [x y w h] in pixels, x y from the axes' corner
            off = struct('colorbar', [], 'legend', []);
            if ~isa(ax, 'matlab.graphics.axis.Axes')
                return;
            end
            a = getpixelposition(ax);
            parts = {'Colorbar', 'colorbar'; 'Legend', 'legend'};
            for k = 1:2
                h = ax.(parts{k, 1});
                if ~isempty(h) && isgraphics(h)
                    try
                        p = getpixelposition(h);
                        off.(parts{k, 2}) = [p(1:2) - a(1:2), p(3:4)];
                    catch
                        % left where exportgraphics puts it
                    end
                end
            end
        end

        function img = icon()
            %% A 16 x 16 floppy disk for the toolbar button
            img = repmat(reshape([0.20 0.33 0.55], 1, 1, 3), 16, 16);   % the disk
            img(2:6, 5:12, :) = 0.85;                                     % the shutter
            img(3:5, 10:11, :) = 0.20;                                    % its window
            img(9:15, 3:14, :) = 1;                                       % the label
            img(11, 5:12, :) = 0.6; img(13, 5:12, :) = 0.6;               % lines on the label
        end

        function write_lines(path, lines)
            %% Write text lines as UTF-8
            fid = fopen(path, 'w', 'n', 'UTF-8');
            if fid < 0
                error('om_export:Open', 'Cannot write %s.', path);
            end
            closer = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', lines);
        end
    end
end


function delete_if_there(path)
% A temporary file, if one was made
if isfile(path)
    delete(path);
end
end
