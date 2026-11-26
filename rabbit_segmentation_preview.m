classdef rabbit_segmentation_preview < handle
    %% Reconstruction segmentation preview
    % Collin Snitchler
    % 03.09.2026
    % Sources: segmentationAssist.mlapp (this repository, Callum
    %          Zgierski-Johnston and Teo Puig Walz) for the settings shown.
    % Popup that shows what the current assisted-segmentation settings
    % (threshold and smoothen sliders, confirmed keep-area mask) give on
    % the cut reconstruction images. The only controls are the left/right
    % arrows; close it with the window close button.
    % Available only for the rabbit panoramic system, checked from the
    % saved ROI JSON (rabbit_panoramic true and exactly 4 view bounds), so
    % it works after a MATLAB restart. The reconstruction path comes from
    % the JSON; if it is missing the user is asked for it.
    % Images are read from the cut of this recording that fits the JSON
    % bounds (rabbit_cut_tiffs.find_cut_folder), never the uncut stack. If
    % none fits, a new one is cut with rabbit_cut_tiffs.cut_from_roi.
    % Segmentation uses rabbit_segmentation_core, as the apply step does,
    % with the live slider values. refresh_all is called from the slider
    % callbacks in segmentationAssist.mlapp so the preview updates live.
    % The confirmed keep-area mask (processed_data.keep_area_poly, NaN =
    % excluded) is cropped per view; polygon edits still in progress in
    % segmentationAssist are not used.
    % Inputs:
    %   seg_app: the segmentationAssist app
    %   json_path: saved ROI JSON
    %   main_app: the analyse_optical_mapping app

    properties (Access = public)
        PreviewFigure    matlab.ui.Figure
        ImageAxes        matlab.ui.control.UIAxes
        LeftButton       matlab.ui.control.Button
        RightButton      matlab.ui.control.Button
        TitleLabel       matlab.ui.control.Label
        CounterLabel     matlab.ui.control.Label
        current_index    = 1
        current_mask     = []   % logical keep mask for the shown image
        seg_app          % segmentationAssist app whose LIVE settings are read
        rec_path         % reconstruction stack path (file or folder)
        files = {}       % cut TIFF paths, natural order
        view_of = []     % per-index ROI row (1..4), from the file name's _view<k>
        row_views = 1:4  % the view (View1..View4) of each ROI row, from the JSON's view_order
        keep_crops = {}  % per-view cropped keep mask (logical) or []
    end

    properties (Access = private)
        main_app         % analyse_optical_mapping app (file_info/data)
        json_path        % saved v1 ROI JSON (state survives an app restart)
        bounds           % 4x4 region_bounds_src (view2;view3;view1;view4)
        frames = {}      % lazy cache of decoded frames
        image_handle = []
        boundary_handles = []
    end

    methods (Static)
        function open_from_assist(seg_app, main_app)
            %% Open the preview from the segmentation assist window
            % Picks the saved ROI JSON, builds the popup and shows any
            % failure as an alert on the segmentation assist figure.
            [f, p] = uigetfile({'*.json', 'ROI JSON (*.json)'}, ...
                'Load ROI JSON for the segmentation preview');
            if isequal(f, 0)
                return;
            end
            try
                seg_app.preview_app = rabbit_segmentation_preview( ...
                    seg_app, fullfile(p, f), main_app);
            catch ME
                % clear user-facing message on the window the user came from
                if ~isempty(seg_app) && isprop(seg_app, 'segmentationAssistUIFigure')
                    uialert(seg_app.segmentationAssistUIFigure, ...
                        sprintf('The segmentation preview could not be opened: %s', ME.message), ...
                        'Segmentation preview');
                else
                    rethrow(ME);
                end
            end
        end

        function refresh_all(seg_app)
            %% Redraw every open preview that reads from seg_app
            % Called from the threshold and smoothen slider callbacks in
            % segmentationAssist.mlapp.
            insts = rabbit_segmentation_preview.instance_list;
            for k = 1:numel(insts)
                p = insts{k};
                if isvalid(p) && isequal(p.seg_app, seg_app) ...
                        && ~isempty(p.PreviewFigure) && isvalid(p.PreviewFigure)
                    p.rerender();
                end
            end
        end

        function txt = title_text(fname, row, row_views)
            %% The preview's title: the file name and its view, "<file> (View<n>)"
            % The cut names its images _view<k> with k the ROI row; the
            % view shown is the one the regions file's view_order names for
            % that row (View1 the leftmost region). The file name is shown
            % as it is.
            v = row;
            if numel(row_views) >= row, v = row_views(row); end
            txt = sprintf('%s (View%d)', fname, v);
        end

        function rv = row_views_of(view_order)
            %% The view number of each ROI row from a view_order ({'view2', ...}); [1 2 3 4] if unusable
            rv = 1:4;
            if ischar(view_order), view_order = strtrim(strsplit(view_order, ';')); end
            if ~iscell(view_order) || numel(view_order) ~= 4, return; end
            n = cellfun(@(s) str2double(regexprep(char(s), '^view', '', 'ignorecase')), view_order(:)');
            if all(isfinite(n)) && isequal(sort(n), 1:4), rv = n; end
        end

        function out = instance_list()
            %% Open previews, for refresh_all
            out = rabbit_segmentation_preview.registry();
        end

        function out = register(obj)
            lst = rabbit_segmentation_preview.registry();
            lst{end + 1} = obj; %#ok<AGROW>
            rabbit_segmentation_preview.registry(lst);
            out = obj;
        end

        function out = unregister(obj)
            lst = rabbit_segmentation_preview.registry();
            lst = lst(~cellfun(@(p) isequal(p, obj), lst));
            rabbit_segmentation_preview.registry(lst);
            out = obj;
        end
    end

    methods (Static, Access = private)
        function out = registry(assign)
            %% Persistent list of open previews
            % With no argument returns the valid list; with an argument
            % replaces it (a persistent can only be set in its own
            % function).
            persistent reg
            if isempty(reg)
                reg = {};
            end
            if nargin > 0
                reg = assign;
            end
            reg = reg(cellfun(@(p) isvalid(p), reg));
            out = reg;
        end
    end

    methods (Access = private)
        function v = get_live(obj, field, default_val)
            %% Read a live slider value from seg_app
            % Accepts a UI component with a Value property, a plain number,
            % or a struct with a Value field (headless tests).
            v = default_val;
            s = obj.seg_app;
            if isempty(s)
                return;
            end
            if isobject(s) && isprop(s, field)
                c = s.(field);
            elseif isfield(s, field)   % struct doubles (headless tests)
                c = s.(field);
            else
                return;
            end
            if ~isempty(c)
                if isscalar(c) && (isnumeric(c) || islogical(c))
                    v = double(c);
                elseif isobject(c) && ~isempty(c) && isvalid(c) ...
                        && isprop(c, 'Value') && isscalar(c.Value) ...
                        && (isnumeric(c.Value) || islogical(c.Value))
                    v = double(c.Value);
                elseif isstruct(c) && isscalar(c) && isfield(c, 'Value') ...
                        && isscalar(c.Value) && (isnumeric(c.Value) || islogical(c.Value))
                    v = double(c.Value);
                end
            end
        end
    end

    methods
        function obj = rabbit_segmentation_preview(seg_app, json_path, main_app)
            %% Build the preview popup
            % Throws analyse_om:SegmentationPreview:* errors (shown by the caller) if the
            % JSON, path or image sizes are not usable; nothing is
            % created unless all checks pass.
            if nargin < 2 || isempty(json_path)
                error('analyse_om:SegmentationPreview:NoJSON', ...
                    'A saved ROI JSON is required for the segmentation preview.');
            end
            obj.seg_app = seg_app;
            obj.main_app = main_app;
            obj.json_path = char(json_path);
            if isempty(main_app)
                error('analyse_om:SegmentationPreview:NoApp', ...
                    'The main analysis app handle is required for the preview.');
            end

            % ---- check the saved ROI JSON ----
            H = [];
            W = [];
            if isprop(main_app, 'data')
                if isfield(main_app.data, 'height'), H = main_app.data.height; end
                if isfield(main_app.data, 'width'),  W = main_app.data.width; end
            end
            payload = rabbit_stack_io.load_roi_json(obj.json_path, H, W);
            if ~payload.rabbit_panoramic
                error('analyse_om:SegmentationPreview:NotRabbit', ...
                    ['The segmentation preview is only available for the rabbit ' ...
                    'panoramic system: the saved ROI JSON does not have ' ...
                    'rabbit_panoramic enabled. Re-save the ROIs with the rabbit ' ...
                    'panoramic checkbox selected.']);
            end
            src = payload.region_bounds_src;
            if size(src, 1) ~= 4
                error('analyse_om:SegmentationPreview:BadROIs', ...
                    ['The saved ROI JSON must contain exactly 4 view bounds ' ...
                    '(view order view2;view3;view1;view4) for the preview; got %d.'], ...
                    size(src, 1));
            end
            obj.bounds = double(src);
            if isfield(payload, 'view_order')
                obj.row_views = rabbit_segmentation_preview.row_views_of(payload.view_order);
            end

            % ---- reconstruction path: auto-fill from the JSON; missing -> prompt ----
            rec_path = '';
            if isfield(payload, 'reconstruction_path')
                rec_path = payload.reconstruction_path;
            end
            if isempty(rec_path) || (~isfolder(rec_path) && exist(rec_path, 'file') ~= 2)
                rec_path = obj.prompt_for_path();
            end
            obj.rec_path = char(rec_path);

            % ---- cut reconstruction folder ----
            stem = rabbit_cut_tiffs.source_stem(obj.rec_path);
            cut_dir = rabbit_cut_tiffs.find_cut_folder(obj.main_app, 'reconstruction', stem, obj.bounds);
            if isempty(cut_dir)
                % No cut fits these ROIs: cut with rabbit_cut_tiffs using
                % the JSON bounds, into the next free folder. The cutter
                % reads app.data.reconstruction_path, so set it first, as
                % Load ROI JSON in the editor does.
                if isprop(obj.main_app, 'data') ...
                        && isfield(obj.main_app.data, 'reconstruction_path')
                    obj.main_app.data.reconstruction_path = obj.rec_path;
                end
                try
                    [ok, cut_dir] = rabbit_cut_tiffs.cut_from_roi(obj.main_app, ...
                        obj.json_path, 'reconstruction');
                catch ME
                    error('analyse_om:SegmentationPreview:CutFailed', ...
                        'Could not create the canonical cut reconstruction images: %s', ...
                        ME.message);
                end
                if ~ok
                    error('analyse_om:SegmentationPreview:CutFailed', ...
                        'Could not create the canonical cut reconstruction images (see the cut alert).');
                end
            end

            % ---- list the cut TIFFs and check them against the JSON bounds ----
            obj.load_cut_files(cut_dir);

            % ---- confirmed keep-area mask, cropped per view ----
            obj.load_keep_crops();

            % ---- the popup: arrows and the close button only ----
            obj.build_figure();
            obj.rerender();
            rabbit_segmentation_preview.register(obj);
        end

        function delete(obj)
            rabbit_segmentation_preview.unregister(obj);
            if ~isempty(obj.PreviewFigure) && isvalid(obj.PreviewFigure)
                delete(obj.PreviewFigure);
            end
            if ~isempty(obj.ImageAxes) && isvalid(obj.ImageAxes)
                delete(obj.ImageAxes);
            end
        end

        function frame = current_frame(obj, idx)
            %% Read a cut TIFF on first use and cache it
            if nargin < 2
                idx = obj.current_index;
            end
            if numel(obj.frames) < idx || isempty(obj.frames{idx})
                obj.frames{idx} = imread(obj.files{idx});
            end
            frame = obj.frames{idx};
        end
    end

    methods (Access = private)
        function path = prompt_for_path(obj)
            %% Ask for the reconstruction images
            % Used when the JSON has no usable reconstruction path: an
            % alert, then a file picker, then a folder picker. Cancelling
            % throws analyse_om:SegmentationPreview:NoPath.
            if ~isempty(obj.main_app) && isprop(obj.main_app, 'opticalmappingUIFigure') ...
                    && ~isempty(obj.main_app.opticalmappingUIFigure)
                uialert(obj.main_app.opticalmappingUIFigure, ...
                    ['No reconstruction image path was saved with the ROI JSON ' ...
                    '(or the saved path no longer exists). Please provide the ' ...
                    'reconstruction images of this heart (FITS/TIFF file or a ' ...
                    'folder of 2-D TIFF frames).'], ...
                    'Reconstruction images needed');
            end
            [f, p] = uigetfile({'*.fits', 'FITS files (*.fits)'; ...
                '*.tif; *.tiff', 'Tiff files (*.tif, *.tiff)'; ...
                '*.*', 'All Files (*.*)'}, ...
                'Select reconstruction stack (FITS/TIFF file or folder)');
            if isequal(f, 0)
                d = uigetdir(p, 'Select reconstruction stack folder (2-D TIFF frames)');
                if isequal(d, 0)
                    error('analyse_om:SegmentationPreview:NoPath', ...
                        'No reconstruction image path was provided; the preview cannot be shown.');
                end
                path = d;
            else
                path = fullfile(p, f);
            end
        end

        function load_cut_files(obj, cut_dir)
            %% List the cut TIFFs and check their sizes
            % Natural sort order. Each image must have the crop size of
            % its view's ROI; otherwise the cut is out of date and an
            % error is thrown.
            d = dir(cut_dir);
            isimg = arrayfun(@(e) ~e.isdir && ~isempty(regexpi(e.name, '\.tiff?$')), d);
            names = rabbit_stack_io.natsort_names({d(isimg).name});
            if isempty(names)
                error('analyse_om:SegmentationPreview:NoCutImages', ...
                    'The canonical cut folder contains no TIFF images: %s', cut_dir);
            end
            view_of = zeros(numel(names), 1);
            for k = 1:numel(names)
                toks = regexp(names{k}, '_view([1-4])(?:\.|_|$)', 'tokens', 'once');
                if isempty(toks)
                    error('analyse_om:SegmentationPreview:BadCutName', ...
                        'Cannot determine the view of cut image ''%s'' (expected _view1.._view4).', ...
                        names{k});
                end
                view_of(k) = str2double(toks{1});
            end
            obj.files = cellfun(@(n) fullfile(cut_dir, n), names, 'UniformOutput', false);
            obj.view_of = view_of;
            % Check each image size against the JSON bounds
            for k = 1:numel(obj.files)
                v = obj.view_of(k);
                info = imfinfo(obj.files{k});
                exp_rows = obj.bounds(v, 3) - obj.bounds(v, 1) + 1;
                exp_cols = obj.bounds(v, 4) - obj.bounds(v, 2) + 1;
                if info(1).Height ~= exp_rows || info(1).Width ~= exp_cols
                    error('analyse_om:SegmentationPreview:StaleCut', ...
                        ['The canonical cut reconstruction images do not match the ' ...
                        'saved ROIs (%s is %dx%d but ROI view%d crops %dx%d). The cut ' ...
                        'is stale; re-cut it with the saved ROI JSON (Save ROI JSON ' ...
                        '-> cut flow) or delete %s so the preview can re-cut it.'], ...
                        names{k}, info(1).Height, info(1).Width, v, ...
                        exp_rows, exp_cols, cut_dir);
                end
            end
        end

        function load_keep_crops(obj)
            %% Crop the confirmed keep-area mask per view
            % From processed_data.keep_area_poly (NaN = excluded). If it
            % is missing or all ones, keep_crops stays empty.
            keep = [];
            if isprop(obj.main_app, 'processed_data') ...
                    && isfield(obj.main_app.processed_data, 'keep_area_poly')
                keep = obj.main_app.processed_data.keep_area_poly;
            end
            obj.keep_crops = {};
            if isempty(keep)
                return;
            end
            kd = double(keep);
            if all(kd(:) == 1) || all(~isfinite(kd(:)))
                return;   % all-ones or all-NaN = no effective mask
            end
            for v = 1:4
                r1 = obj.bounds(v, 1); c1 = obj.bounds(v, 2);
                r2 = obj.bounds(v, 3); c2 = obj.bounds(v, 4);
                if r2 > size(keep, 1) || c2 > size(keep, 2)
                    continue;   % keep mask smaller than the source: guard only
                end
                crop = kd(r1:r2, c1:c2);
                if all(~isfinite(crop(:)))
                    obj.keep_crops{v} = [];   % fully excluded view
                else
                    obj.keep_crops{v} = isfinite(crop);
                end
            end
        end

        function build_figure(obj)
            %% Build the popup window
            % Image axes, two arrow buttons and two labels. Closing the
            % window deletes the object, which deletes the figure.
            f = uifigure('Visible', 'off');
            f.Position = [200 200 520 420];
            f.Name = 'Rabbit reconstruction segmentation preview';
            f.CloseRequestFcn = @(s, e) delete(obj);
            ax = uiaxes(f, 'Position', [30 70 460 310], ...
                'XTick', [], 'YTick', [], 'Box', 'on');
            ax.Title.String = '';
            % Save button and right-click menu (om_export): the image with
            % its mask outline as PNG, JPG or PDF (a 300 dpi image), with
            % the window's title line as the picture's title
            om_export.attach(ax, struct('name', @() ['segmentation_preview_' obj.TitleLabel.Text], ...
                'content', 'image', 'title', @() obj.TitleLabel.Text));
            left = uibutton(f, 'push');
            left.Text = '<';
            left.Position = [30 20 60 34];
            left.Tooltip = 'Previous image';
            left.ButtonPushedFcn = @(s, e) obj.navigate(-1);
            right = uibutton(f, 'push');
            right.Text = '>';
            right.Position = [430 20 60 34];
            right.Tooltip = 'Next image';
            right.ButtonPushedFcn = @(s, e) obj.navigate(1);
            title_lbl = uilabel(f);
            title_lbl.Position = [100 388 320 22];
            title_lbl.HorizontalAlignment = 'center';
            title_lbl.FontWeight = 'bold';
            title_lbl.Text = '';
            counter_lbl = uilabel(f);
            counter_lbl.Position = [100 24 320 22];
            counter_lbl.HorizontalAlignment = 'center';
            counter_lbl.Text = '';
            obj.PreviewFigure = f;
            obj.ImageAxes = ax;
            obj.LeftButton = left;
            obj.RightButton = right;
            obj.TitleLabel = title_lbl;
            obj.CounterLabel = counter_lbl;
            f.Visible = 'on';
        end

        function navigate(obj, dir)
            %% Step to the previous or next image (wraps around)
            n = numel(obj.files);
            if n == 0
                return;
            end
            obj.current_index = mod(obj.current_index - 1 + dir, n) + 1;
            obj.rerender();
        end

        function rerender(obj)
            %% Segment the current image and redraw
            % Uses the live slider values and draws the mask boundary
            % over the image.
            if isempty(obj.PreviewFigure) || ~isvalid(obj.PreviewFigure)
                return;
            end
            idx = obj.current_index;
            n = numel(obj.files);
            if n == 0
                return;
            end
            idx = min(max(idx, 1), n);
            obj.current_index = idx;
            frame = obj.current_frame(idx);
            v = obj.view_of(idx);
            keep_crop = [];
            if numel(obj.keep_crops) >= v
                keep_crop = obj.keep_crops{v};
            end
            I0 = rabbit_segmentation_core.prepare_frame(frame, keep_crop);
            thr = obj.get_live('threshold_slider', 0.83);
            sig = obj.get_live('smoothen_slider', 4);
            mask = rabbit_segmentation_core.segment(I0, thr, sig);
            obj.current_mask = mask;
            % Normalise the frame for display
            d = double(frame);
            mx = max(d(:));
            if isempty(mx) || ~isfinite(mx) || mx <= 0
                d = zeros(size(d));
            else
                d = d ./ mx;
            end
            if ~isempty(obj.image_handle) && isvalid(obj.image_handle)
                delete(obj.image_handle);
            end
            obj.image_handle = imshow(d, 'Parent', obj.ImageAxes);
            colormap(obj.ImageAxes, hot(256));
            for h = 1:numel(obj.boundary_handles)
                if isvalid(obj.boundary_handles(h))
                    delete(obj.boundary_handles(h));
                end
            end
            obj.boundary_handles = gobjects(0);
            [B, ~] = bwboundaries(mask, 'noholes');
            hold(obj.ImageAxes, 'on');
            for k = 1:numel(B)
                b = B{k};
                h = plot(obj.ImageAxes, b(:, 2), b(:, 1), 'b', 'LineWidth', 2);
                obj.boundary_handles(end + 1) = h; %#ok<AGROW>
            end
            hold(obj.ImageAxes, 'off');
            [~, fname] = fileparts(obj.files{idx});
            obj.TitleLabel.Text = rabbit_segmentation_preview.title_text(fname, v, obj.row_views);
            obj.CounterLabel.Text = sprintf('%d / %d', idx, n);
            drawnow limitrate
        end
    end
end
