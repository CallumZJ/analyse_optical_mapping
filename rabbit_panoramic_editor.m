classdef rabbit_panoramic_editor < handle
    %% Rabbit panoramic ROI editor
    % Collin Snitchler
    % 03.09.2026
    % Two-panel ROI editor for the rabbit panoramic system. The
    % top panel holds View2 and View3, the bottom panel shows the image
    % mirrored and holds View1 and View4. Each view has W/H fields; ROIs
    % are clamped to the image with a minimum drag size of 20 px.
    % The first four ROIs are estimated from the image (Otsu foreground and
    % the largest blob in each of four vertical bands). If that fails, the
    % equal-spaced default is used and the status label says so.
    % Inputs:
    %   main_app: the analyse_optical_mapping app
    % Outputs:
    %   main_app.data.region_bounds_src: Nx4 [row1 col1 row2 col2] in
    %       unmirrored source pixels, 1-based, inclusive, rounded; rows
    %       [View2; View3; View1; View4]. The mirror is for display only.
    % "Regions Selected" calls the app's RegionsChosenMenu callback once;
    % cancel or close calls it once with region_bounds_src empty. The call
    % goes through a short timer because define_regions only reaches
    % uiwait after adapt_rabbit_regions returns, and a direct call would
    % hang. The constructor writes the default ROIs straight away because
    % define_regions checks region_bounds_src before uiwait.
    % With a reconstruction stack loaded the panels show the max
    % projection of the whole reconstruction file, cropped by the FOV mapping
    % so that a box covers the pixels the reconstruction cut takes
    % (rabbit_stack_io.mip_in_editor_frame). A line under the panels names
    % the file, or says why it is not shown. Without a stack the panels show
    % the optical mapping max projection. The starting ROIs are
    % always estimated from the optical mapping image.
    % Show chooses what the panels show. "All recordings in
    % colour" (the default once a reconstruction or calibration stack is
    % loaded) puts the calibration in red, the reconstruction in green and
    % the optical mapping recording in blue, each where its cut takes its
    % pixels, so one look shows whether a box holds the heart and the
    % target in every recording. A recording whose frame covers only part
    % of the editor's frame (its camera area of interest was smaller or
    % shifted) is outlined, and the line at the bottom names every box that
    % leaves a recording's frame; Regions Selected asks before keeping such
    % boxes, because that recording cannot be cut there.
    %
    % Section map (search for the quoted line; line numbers move)
    %   UI construction ........ "% UI construction"
    %   ROI interaction ........ "% ROI interaction (move, resize, clamp)"
    %   W/H fields ............. "% W/H fields"
    %   Coordinates ............ "% Coordinate conversion (display <-> unmirrored source)"
    %   ROI JSON ............... "% ROI JSON (schema version 1)"
    %   Confirm / cancel ....... "% Session end: confirm / cancel, single async fire"
    %   Static helpers ......... "methods (Static)"

    properties (SetAccess = private)
        main_app      % handle to the analyse_optical_mapping app
        EditorFigure  % uifigure
        AxesTop       % non-mirrored display (View2, View3)
        AxesBottom    % mirrored display (View1, View4)
        ROIs          % struct: view -> images.roi.Rectangle
        WFields       % struct: view -> uieditfield (numeric)
        HFields       % struct: view -> uieditfield (numeric)
        StatusLabel   % uilabel: ROI estimation source / confidence note
        PreviewLabel  % uilabel: which recording the panels show, and its limits
        ImageTop      % image object of the top panel
        ImageBottom   % image object of the bottom panel
        ImageH        % source image rows
        ImageW        % source image cols
        MIP           % HxW optical mapping max projection (ROI estimate, fallback display)
        CalibrationMIP % HxW calibration MIP for the combined display (NaN outside its frame)
        CalibrationCover % HxW logical: where the calibration frame has pixels
        ReconstructionCover % HxW logical: where the reconstruction frame has pixels
        ShowDropdown  % uidropdown: what the panels show
        ShowMode = '' % key of the chosen view ('' = the default)
        CoverageLabel % uilabel: boxes that leave a recording's frame
        OutlineLines = gobjects(0) % outlines of partly covering frames
        CalibrationNote = '' % why the calibration stack is not combined
        PreviewNote = '' % what the panels show now
        ReconstructionShown = false % true while the panels show the reconstruction
        ReconstructionProblem = '' % why a stack named by a ROI JSON could not be loaded
        fire_timer    % one-shot timer used for the async RegionsChosen fire
        fired = false % true once the RegionsChosen callback was fired
        syncing = false % guards programmatic field refreshes
    end

    properties (Constant)
        MIN_DRAG_SIZE = 20   % smallest ROI side when dragged (px)
    end

    methods
        function obj = rabbit_panoramic_editor(main_app)
            %% Build the two-panel editing UI
            obj.main_app = main_app;
            obj.fired = false;

            % Source image size (the display MIP is the max over frames)
            if ~isempty(main_app.data.image_stack)
                obj.ImageH = size(main_app.data.image_stack, 1);
                obj.ImageW = size(main_app.data.image_stack, 2);
            else
                obj.ImageH = [];
                obj.ImageW = [];
            end
            if ~isempty(main_app.data.height) && ~isempty(main_app.data.width)
                obj.ImageH = main_app.data.height;
                obj.ImageW = main_app.data.width;
            end
            if isempty(obj.ImageH) || isempty(obj.ImageW)
                % No image context - treat as cancelled.
                main_app.data.region_bounds_src = [];
                obj.schedule_fire_once();
                return;
            end

            obj.place_calibration();

            obj.build_ui();
            obj.init_default_rois();

            % define_regions checks region_bounds_src as soon as the
            % constructor returns
            obj.write_src_bounds();
        end

        function place_calibration(obj)
            %% The calibration MIP in the editor's frame (display only), with its covered pixels
            % From the calibration mapping on app.data, so after Load ROI
            % JSON changes the mapping the picture follows. A calibration stack that cannot be placed is left
            % out and the line under the panels says so.
            obj.CalibrationMIP = [];
            obj.CalibrationCover = [];
            obj.CalibrationNote = '';
            d = obj.main_app.data;
            if isfield(d, 'calibration_mip') && ~isempty(d.calibration_mip)
                mapping = [];
                if isfield(d, 'calibration_fov_mapping')
                    mapping = d.calibration_fov_mapping;
                end
                [obj.CalibrationMIP, why_not, obj.CalibrationCover] = rabbit_stack_io.mip_in_editor_frame( ...
                    d.calibration_mip, obj.ImageH, obj.ImageW, mapping);
                if isempty(obj.CalibrationMIP)
                    obj.CalibrationNote = sprintf('The calibration stack is not combined here: %s.', why_not);
                end
            end
        end

        % -------------------------------------------------------------
        % UI construction
        % -------------------------------------------------------------
        function build_ui(obj)
            % OM_APP_HEADLESS=1 (scripts and tests): built but not shown,
            % as the main app
            obj.EditorFigure = uifigure( ...
                'Visible', ~strcmp(getenv('OM_APP_HEADLESS'), '1'), ...
                'Name', 'Rabbit panoramic ROI editor', ...
                'Position', [80 80 1100 800], ...
                'CloseRequestFcn', @(s,e) obj.cancel_edit());

            root = uigridlayout(obj.EditorFigure, [8 1]);
            root.RowHeight = {'1x', '1x', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit'};
            root.Padding = [8 8 8 8];
            root.RowSpacing = 6;

            obj.AxesTop = uiaxes(root);
            title(obj.AxesTop, 'View2 + View3 (non-mirrored)');
            obj.AxesTop.XTick = []; obj.AxesTop.YTick = [];

            obj.AxesBottom = uiaxes(root);
            title(obj.AxesBottom, 'View1 + View4 (mirrored, display only)');
            obj.AxesBottom.XTick = []; obj.AxesBottom.YTick = [];

            % per-view W/H fields: one group per view, horizontal
            fields_row = uigridlayout(root, [1 4]);
            fields_row.ColumnWidth = {'1x','1x','1x','1x'};
            views = {'view1','view2','view3','view4'};
            obj.WFields = struct(); obj.HFields = struct();
            for k = 1:4
                v = views{k};
                grp = uigridlayout(fields_row, [1 5]);
                grp.ColumnWidth = {45, 16, 52, 16, 52};   % fits a 1280 px screen
                uilabel(grp, 'Text', v);
                uilabel(grp, 'Text', 'W');
                obj.WFields.(v) = uieditfield(grp, 'numeric', 'Value', 0, ...
                    'ValueChangedFcn', @(s,e) obj.apply_dim_edit(v));
                uilabel(grp, 'Text', 'H');
                obj.HFields.(v) = uieditfield(grp, 'numeric', 'Value', 0, ...
                    'ValueChangedFcn', @(s,e) obj.apply_dim_edit(v));
            end

            % Buttons, including ROI JSON save and load
            btn_row = uigridlayout(root, [1 4]);
            btn_row.ColumnWidth = {'1x','1x','1x','1x'};
            uibutton(btn_row, 'push', 'Text', 'Save ROI JSON...', ...
                'ButtonPushedFcn', @(s,e) obj.save_roi_json());
            uibutton(btn_row, 'push', 'Text', 'Load ROI JSON...', ...
                'ButtonPushedFcn', @(s,e) obj.load_roi_json());
            uibutton(btn_row, 'push', 'Text', 'Regions Selected', ...
                'ButtonPushedFcn', @(s,e) obj.confirm_edit());
            uibutton(btn_row, 'push', 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(s,e) obj.cancel_edit());

            % What the panels show (update_panels fills the items)
            show_row = uigridlayout(root, [1 2]);
            show_row.ColumnWidth = {50, '1x'};
            show_row.Padding = [0 0 0 0];
            uilabel(show_row, 'Text', 'Show:');
            obj.ShowDropdown = uidropdown(show_row, 'Items', {'Optical mapping recording'}, ...
                'ItemsData', {'om'}, 'ValueChangedFcn', @(s,e) obj.choose_show(s.Value));

            % Note on how the ROIs were estimated (read-only)
            obj.StatusLabel = uilabel(root, 'Text', '', ...
                'HorizontalAlignment', 'left', ...
                'WordWrap', 'on');

            % Which recording the panels show, and what that means for the
            % cuts (read-only)
            obj.PreviewLabel = uilabel(root, 'Text', '', ...
                'HorizontalAlignment', 'left', ...
                'WordWrap', 'on');

            % Boxes that leave the frame of a loaded recording (read-only)
            obj.CoverageLabel = uilabel(root, 'Text', '', ...
                'HorizontalAlignment', 'left', ...
                'WordWrap', 'on');
        end

        function init_default_rois(obj)
            % Place the four ROIs from the image content, or fall back to
            % the equal-spaced default if the estimate fails.
            % Draw the panels first so the ROIs sit on top.
            obj.update_panels();
            obj.ROIs = struct();

            W = obj.ImageW; H = obj.ImageH;
            [bounds, note] = obj.estimate_roi_bounds();
            if isempty(bounds)
                % Fallback: squares of
                % side 0.8*ImageH (clamped to [20, min(W,H)]) centred at
                % the four panoramic positions
                roi_size = floor(0.8 * H);
                roi_size = max(obj.MIN_DRAG_SIZE, min([roi_size, W, H]));
                views = {'view4','view2','view3','view1'};
                centers = struct( ...
                    'view4', [W*1/8, H*0.5], ...  % far left on the mirrored panel
                    'view2', [W*3/8, H*0.5], ...  % mid-left on the normal panel
                    'view3', [W*5/8, H*0.5], ...  % mid-right on the normal panel
                    'view1', [W*7/8, H*0.5]);     % far right on the mirrored panel
                for k = 1:4
                    v = views{k};
                    x = centers.(v)(1) - roi_size/2;
                    y = centers.(v)(2) - roi_size/2;
                    x = max(0, min(x, W - roi_size));
                    y = max(0, min(y, H - roi_size));
                    pos = [x y roi_size roi_size];
                    if strcmp(v, 'view2') || strcmp(v, 'view3')
                        ax = obj.AxesTop;
                    else
                        ax = obj.AxesBottom;
                    end
                    obj.ROIs.(v) = obj.create_roi(ax, v, pos);
                end
            else
                % Estimated bounds are in view2;view3;view1;view4 order;
                % convert each to display coordinates on its panel
                views = {'view2', 'view3', 'view1', 'view4'};
                for k = 1:4
                    v = views{k};
                    pos = obj.src_to_display(v, bounds(k, :));
                    if strcmp(v, 'view2') || strcmp(v, 'view3')
                        ax = obj.AxesTop;
                    else
                        ax = obj.AxesBottom;
                    end
                    obj.ROIs.(v) = obj.create_roi(ax, v, pos);
                end
            end

            obj.refresh_dim_fields();
            if ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                obj.StatusLabel.Text = note;
            end
        end

        function [bounds, note] = estimate_roi_bounds(obj)
            %% Estimate the four view ROIs from the image
            % The panoramic frame shows the four views side by side, so
            % the frame is split into four vertical bands and the largest
            % foreground blob in each band is taken.
            % Outputs:
            %   bounds: 4x4 [row1 col1 row2 col2] in unmirrored source
            %       pixels, 1-based, inclusive, rows view2;view3;view1;view4;
            %       empty if the estimate is not trusted
            %   note: status text for the editor
            W = obj.ImageW; H = obj.ImageH;
            if isempty(obj.MIP) || isempty(W) || isempty(H) || W < 4 || H < 4
                note = 'ROI estimate: no image content - using the equal-spaced default (adjust the ROIs).';
                bounds = [];
                return;
            end
            fg = rabbit_panoramic_editor.foreground_mask(obj.MIP);
            if ~any(fg(:))
                note = 'ROI estimate: no foreground found - using the equal-spaced default (adjust the ROIs).';
                bounds = [];
                return;
            end
            % Four vertical bands with whole-pixel edges; the last band
            % takes any remainder so the bands tile the frame
            edges = round(linspace(1, W + 1, 5));
            edges(5) = W + 1;
            bounds = zeros(4, 4);
            ok = true(4, 1);
            for k = 1:4
                c1 = edges(k); c2 = edges(k + 1) - 1;
                band = fg(:, c1:c2);
                [r1, c1b, r2, c2b] = rabbit_panoramic_editor.largest_blob(band);
                if isempty(r1)
                    ok(k) = false;
                    continue;
                end
                bounds(k, :) = [r1, c1 + c1b - 1, r2, c1 + c2b - 1];
            end
            if ~all(ok)
                note = 'ROI estimate: partial content evidence - using the equal-spaced default (adjust the ROIs).';
                bounds = [];
                return;
            end
            % Each blob must cover at least 5% of the frame and be at
            % least 10 px tall and wide
            areas = (bounds(:, 3) - bounds(:, 1) + 1) .* (bounds(:, 4) - bounds(:, 2) + 1);
            frame_area = H * W;
            if any(areas < 0.05 * frame_area) || any(bounds(:, 3) - bounds(:, 1) + 1 < 10) ...
                    || any(bounds(:, 4) - bounds(:, 2) + 1 < 10)
                note = 'ROI estimate: low confidence - using the equal-spaced default (adjust the ROIs).';
                bounds = [];
                return;
            end
            % Neighbouring views must leave a gap of at least 2 px at the
            % band edge (one blob spanning the frame touches every edge)
            GAP = 2;
            for k = 1:3
                if bounds(k, 4) >= edges(k + 1) - GAP || ...
                        bounds(k + 1, 2) <= edges(k + 1) + GAP
                    note = 'ROI estimate: views not distinct - using the equal-spaced default (adjust the ROIs).';
                    bounds = [];
                    return;
                end
            end
            % The bands run left to right over view1, view2, view3, view4,
            % the same places as the equal-spaced default; on the mirrored
            % panel view4 then sits far left and view1 far right. Store
            % them in ROI row order, view2;view3;view1;view4
            bounds = bounds([2 3 1 4], :);
            note = sprintf( ...
                'ROI estimate: content-based (Otsu foreground, largest blob per view band). Adjust the ROIs if needed; the estimate is not an equal split.');
        end

        function r = create_roi(obj, ax, view, pos)
            %% Draw one ROI rectangle in its view colour
            % Clamping is done in on_roi_moved, as images.roi.Rectangle
            % has no Limits/MinimumSize in R2026a.
            colors = struct( ...
                'view1', [1.00 0.31 0.31], ...
                'view2', [0.31 0.78 0.31], ...
                'view3', [0.31 0.55 1.00], ...
                'view4', [1.00 0.82 0.31]);
            r = drawrectangle(ax, 'Position', pos, ...
                'Color', colors.(view), ...
                'LineWidth', 2, ...
                'FaceAlpha', 0.15, ...
                'Label', view, 'LabelVisible', 'on', ...
                'Deletable', false);
            addlistener(r, 'ROIMoved', @(s,e) obj.on_roi_moved(view));
        end

        function update_panels(obj)
            % Render the two views (display-only normalisation): the view
            % chosen under Show, by default all loaded recordings in colour
            % once a reconstruction or calibration stack is loaded, else the
            % optical mapping max projection.
            if isempty(obj.MIP)
                obj.MIP = max(single(obj.main_app.data.image_stack), [], 3);
            end
            [rec, name, frames, obj.ReconstructionCover] = obj.reconstruction_preview();
            obj.ReconstructionShown = ~isempty(rec);
            obj.PreviewNote = '';   % set below, for the view shown
            cal = obj.CalibrationMIP;
            % The views on offer, and the default one
            keys = {'om'};
            labels = {'Optical mapping recording'};
            if ~isempty(rec) || ~isempty(cal)
                keys = [{'colour'} keys];
                labels = [{'All recordings in colour (red calibration, green reconstruction, blue optical mapping)'} labels];
            end
            if ~isempty(rec)
                keys{end + 1} = 'reconstruction';
                labels{end + 1} = ['Reconstruction recording ' name];
            end
            if ~isempty(cal)
                keys{end + 1} = 'calibration';
                labels{end + 1} = 'Calibration recording';
                keys{end + 1} = 'combined';
                labels{end + 1} = 'Brightest of the calibration and the reconstruction (or optical mapping)';
            end
            mode = obj.ShowMode;
            if ~any(strcmp(keys, mode))
                mode = keys{1};
            end
            if ~isempty(obj.ShowDropdown) && isvalid(obj.ShowDropdown)
                obj.ShowDropdown.Items = labels;
                obj.ShowDropdown.ItemsData = keys;
                obj.ShowDropdown.Value = mode;
            end
            obj.PreviewNote = obj.preview_note(name, frames, mode);
            grey = true;
            switch mode
                case 'colour'
                    % Each recording normalised on its own pixels; a
                    % recording not loaded, or outside its frame, is dark.
                    % The optical mapping recording is shown in the row
                    % order stored in its file, like the others, so the
                    % three line up where the camera saw the same thing (a
                    % FITS recording is upside down elsewhere in the app;
                    % its cut takes the rows the app shows, see the note)
                    z = zeros(obj.ImageH, obj.ImageW);
                    om_stored = obj.MIP;
                    if obj.om_is_fits(), om_stored = flip(om_stored, 1); end
                    ch = {z, z, rabbit_stack_io.normalize_mip(om_stored)};
                    if ~isempty(cal), ch{1} = rabbit_stack_io.normalize_mip(cal); end
                    if ~isempty(rec), ch{2} = rabbit_stack_io.normalize_mip(rec); end
                    mtop = cat(3, ch{:});
                    grey = false;
                    source = 'red calibration, green reconstruction, blue optical mapping (rows as stored)';
                case 'reconstruction'
                    mtop = rec;
                    source = ['reconstruction ' name];
                case 'calibration'
                    mtop = cal;
                    source = 'calibration';
                case 'combined'
                    % Normalise each MIP to [0,1], then take the
                    % element-wise max (NaN -> 0); display only
                    if isempty(rec)
                        mtop = rabbit_stack_io.combined_display(obj.MIP, cal);
                        source = 'optical mapping + calibration';
                    else
                        mtop = rabbit_stack_io.combined_display(rec, cal);
                        source = ['reconstruction ' name ' + calibration'];
                    end
                otherwise
                    mtop = obj.MIP;
                    source = 'optical mapping';
            end
            mbot = flip(mtop, 2);
            if isempty(obj.ImageTop) || ~isvalid(obj.ImageTop)
                obj.ImageTop = imshow(mtop, [], 'Parent', obj.AxesTop);
                obj.ImageBottom = imshow(mbot, [], 'Parent', obj.AxesBottom);
                axis(obj.AxesTop, 'image'); axis(obj.AxesBottom, 'image');
            else
                % imshow would clear the axes and with them the ROIs
                obj.ImageTop.CData = mtop;
                obj.ImageBottom.CData = mbot;
            end
            if grey
                % A grey view after the colour one: scaled through the grey
                % colour map, between the image's own limits
                obj.ImageTop.CDataMapping = 'scaled';
                obj.ImageBottom.CDataMapping = 'scaled';
                colormap(obj.AxesTop, gray(256));
                colormap(obj.AxesBottom, gray(256));
                lims = [min(mtop(:)) max(mtop(:))];
                if isfinite(lims(1)) && isfinite(lims(2)) && lims(2) > lims(1)
                    obj.AxesTop.CLim = double(lims);
                    obj.AxesBottom.CLim = double(lims);
                end
            end
            title(obj.AxesTop, sprintf('View2 + View3 (non-mirrored): %s', source), 'Interpreter', 'none');
            title(obj.AxesBottom, sprintf('View1 + View4 (mirrored, display only): %s', source), 'Interpreter', 'none');
            obj.draw_outlines(rec, cal);
            obj.refresh_preview_label();
        end

        function choose_show(obj, mode)
            %% Show another view of the recordings
            obj.ShowMode = mode;
            obj.update_panels();
        end

        function draw_outlines(obj, rec, cal)
            %% Dashed outline of a loaded frame that covers only part of the editor's frame
            % White, dashed for the reconstruction and dotted for the
            % calibration (the boxes use the channel colours); mirrored on
            % the bottom panel like the image.
            delete(obj.OutlineLines(isgraphics(obj.OutlineLines)));
            obj.OutlineLines = gobjects(0);
            items = {rec, obj.ReconstructionCover, '--'; cal, obj.CalibrationCover, ':'};
            for k = 1:2
                cover = items{k, 2};
                if isempty(items{k, 1}) || isempty(cover) || all(cover(:)) || ~any(cover(:))
                    continue;
                end
                rows = find(any(cover, 2));
                cols = find(any(cover, 1));
                x = [cols(1) cols(end) cols(end) cols(1) cols(1)] + [-0.5 0.5 0.5 -0.5 -0.5];
                y = [rows(1) rows(1) rows(end) rows(end) rows(1)] + [-0.5 -0.5 0.5 0.5 -0.5];
                axes_both = [obj.AxesTop obj.AxesBottom];
                for a = 1:2
                    ax = axes_both(a);
                    xx = x;
                    if a == 2, xx = obj.ImageW + 1 - x; end
                    hold(ax, 'on');
                    obj.OutlineLines(end + 1) = plot(ax, xx, y, items{k, 3}, 'Color', [1 1 1], 'LineWidth', 1.5, ...
                        'HitTest', 'off', 'PickableParts', 'none');
                    hold(ax, 'off');
                end
            end
        end

        function [ok, txt] = check_boxes(obj)
            %% Do all boxes lie inside every loaded recording's frame?
            % The cut of each recording takes the boxes mapped into its
            % frame (rabbit_stack_io.boxes_outside); a box outside cannot
            % be cut there. txt names them, or says that all fit.
            ok = true;
            txt = '';
            if ~isstruct(obj.ROIs) || ~all(isfield(obj.ROIs, {'view1', 'view2', 'view3', 'view4'}))
                return;
            end
            bounds = obj.current_src();
            names = {'view2', 'view3', 'view1', 'view4'};   % the rows of current_src, as the boxes are labelled
            d = obj.main_app.data;
            parts = {};
            checked = {};
            if obj.ReconstructionShown
                mapping = [];
                if isfield(d, 'reconstruction_fov_mapping'), mapping = d.reconstruction_fov_mapping; end
                [out, t] = rabbit_stack_io.boxes_outside(bounds, mapping, size(d.reconstruction_mip), 'reconstruction', names);
                checked{end + 1} = 'reconstruction';
                if any(out), parts{end + 1} = t; end
            end
            if ~isempty(obj.CalibrationMIP)
                mapping = [];
                if isfield(d, 'calibration_fov_mapping'), mapping = d.calibration_fov_mapping; end
                [out, t] = rabbit_stack_io.boxes_outside(bounds, mapping, size(d.calibration_mip), 'calibration', names);
                checked{end + 1} = 'calibration';
                if any(out), parts{end + 1} = t; end
            end
            if isempty(checked)
                return;
            end
            ok = isempty(parts);
            if ok
                txt = sprintf('Every box lies inside the %s frames.', strjoin(checked, ' and '));
            else
                txt = [strjoin(parts, ' ') ' Those boxes cannot be cut from that recording: move or shrink them ' ...
                    'inside its outline.'];
            end
        end

        function refresh_coverage_label(obj)
            %% Show the box check, in red when a box leaves a frame
            if isempty(obj.CoverageLabel) || ~isvalid(obj.CoverageLabel)
                return;
            end
            [ok, txt] = obj.check_boxes();
            obj.CoverageLabel.Text = txt;
            if ok
                obj.CoverageLabel.FontColor = [0 0 0];
            else
                obj.CoverageLabel.FontColor = [0.8 0 0];
            end
        end

        function [img, name, frames, cover] = reconstruction_preview(obj)
            %% The reconstruction max projection in the editor's frame
            % Empty when no stack is loaded or it cannot be placed; the
            % reason then goes into ReconstructionProblem. A projection
            % belongs to the file it was made from: after Load ROI JSON names
            % another file the old one is not shown.
            img = [];
            name = '';
            frames = [];
            cover = [];
            d = obj.main_app.data;
            path = '';
            if isfield(d, 'reconstruction_path')
                path = char(d.reconstruction_path);
            end
            if ~isempty(path)
                [~, stem, ext] = fileparts(path);
                name = [stem ext];
            end
            if ~isfield(d, 'reconstruction_mip') || isempty(d.reconstruction_mip)
                return;
            end
            if isfield(d, 'reconstruction_mip_source') && (isempty(path) || ...
                    ~rabbit_stack_io.same_file(d.reconstruction_mip_source, path))
                return;
            end
            if isfield(d, 'reconstruction_mip_frames')
                frames = d.reconstruction_mip_frames;
            end
            mapping = [];
            if isfield(d, 'reconstruction_fov_mapping')
                mapping = d.reconstruction_fov_mapping;
            end
            [img, why_not, cover] = rabbit_stack_io.mip_in_editor_frame( ...
                d.reconstruction_mip, obj.ImageH, obj.ImageW, mapping);
            if isempty(img)
                obj.ReconstructionProblem = sprintf('%s is not shown: %s', name, why_not);
            else
                obj.ReconstructionProblem = '';
            end
        end

        function note = preview_note(obj, name, frames, mode)
            %% One plain sentence on what the panels show
            if nargin < 4, mode = ''; end
            if obj.ReconstructionShown && strcmp(mode, 'om')
                note = sprintf(['Preview: the optical mapping recording (the reconstruction file %s is loaded: ' ...
                    'choose it under Show).'], name);
            elseif obj.ReconstructionShown && strcmp(mode, 'calibration')
                note = 'Preview: the calibration recording, where its cut takes its pixels.';
            elseif obj.ReconstructionShown
                if isempty(frames)
                    count = 'all frames';
                else
                    count = sprintf('all %d frames', frames);
                end
                note = sprintf(['Preview: maximum intensity of %s of the reconstruction file %s. ' ...
                    'A box shows the pixels the reconstruction cut takes.'], count, name);
            elseif ~isempty(obj.ReconstructionProblem)
                note = sprintf('Preview: optical mapping recording. The reconstruction file %s', ...
                    obj.ReconstructionProblem);
                if ~strcmp(note(end), '.'), note = [note '.']; end
            else
                note = 'Preview: optical mapping recording (no reconstruction file loaded).';
            end
            if ~isempty(obj.CalibrationNote)
                note = [note ' ' obj.CalibrationNote];
            end
        end

        function refresh_preview_label(obj)
            %% Show the preview note, with the row-flip note for the boxes
            if isempty(obj.PreviewLabel) || ~isvalid(obj.PreviewLabel)
                return;
            end
            txt = obj.PreviewNote;
            flip_note = obj.om_flip_note();
            if ~isempty(flip_note)
                txt = [txt ' ' flip_note];
            end
            obj.PreviewLabel.Text = txt;
            obj.refresh_coverage_label();
        end

        function note = om_flip_note(obj)
            %% How far the optical mapping cut differs from the box shown
            % The app shows FITS recordings upside down and the
            % reconstruction cut keeps the stored rows. Both cuts use the
            % same row numbers, so a box that is not centred vertically
            % covers a different part of the camera image in each: rows r1
            % to r2 here are stored rows H+1-r2 to H+1-r1 of the optical
            % mapping file, r1 + r2 - H - 1 rows away.
            note = '';
            if ~obj.ReconstructionShown || ~obj.om_is_fits() || ~isstruct(obj.ROIs)
                return;
            end
            views = {'view1', 'view2', 'view3', 'view4'};
            parts = {};
            for k = 1:4
                v = views{k};
                if ~isfield(obj.ROIs, v) || ~isvalid(obj.ROIs.(v))
                    return;
                end
                b = obj.display_to_src(v, obj.ROIs.(v).Position);
                parts{end + 1} = sprintf('%s %d', v, abs(b(1) + b(3) - obj.ImageH - 1)); %#ok<AGROW>
            end
            note = sprintf(['The optical mapping cut does not take this same part of the camera image: ' ...
                'the app shows FITS recordings upside down, so a box covers the same camera rows in both ' ...
                'recordings only when it is centred vertically. Rows off centre: %s. Check the views on ' ...
                'the optical mapping image too; heart inside a box here can fall outside its optical ' ...
                'mapping cut.'], strjoin(parts, ', '));
        end

        function tf = om_is_fits(obj)
            %% True when the loaded optical mapping recording is a FITS file
            tf = false;
            try
                [~, ~, ext] = fileparts(obj.main_app.file_info.file);
                tf = strcmpi(ext, '.fits');
            catch
                tf = false;   % test doubles without file_info
            end
        end

        % -------------------------------------------------------------
        % ROI interaction (move, resize, clamp)
        % -------------------------------------------------------------
        function on_roi_moved(obj, view)
            % called on every ROIMoved: clamp to image bounds + min size,
            % then keep the W/H fields in sync.
            r = obj.ROIs.(view);
            if ~isvalid(r)
                return;
            end
            % Only write back when the clamp actually changed something:
            % writing Position inside a ROIMoved callback would otherwise
            % re-fire the event and recurse.
            newp = obj.clamp_position(r.Position);
            if ~isequal(newp, r.Position)
                r.Position = newp;
            end
            obj.refresh_dim_fields();
        end

        function p = clamp_position(obj, pos)
            %% Clamp a rectangle to the image
            % Enforces the minimum size; display coordinates, with the
            % image edges at 0.5 and W+0.5.
            W = obj.ImageW; H = obj.ImageH;
            minw = obj.MIN_DRAG_SIZE; minh = obj.MIN_DRAG_SIZE;
            p = pos;
            if p(3) < minw, p(3) = minw; end
            if p(4) < minh, p(4) = minh; end
            if p(1) < 0.5, p(1) = 0.5; end
            if p(2) < 0.5, p(2) = 0.5; end
            if p(1) + p(3) > W + 0.5, p(3) = W + 0.5 - p(1); end
            if p(2) + p(4) > H + 0.5, p(4) = H + 0.5 - p(2); end
            % ensure the position stays valid after right/bottom clamping
            if p(3) < minw, p(3) = minw; end
            if p(4) < minh, p(4) = minh; end
            p(1) = max(0.5, min(p(1), W + 0.5 - p(3)));
            p(2) = max(0.5, min(p(2), H + 0.5 - p(4)));
        end

        % -------------------------------------------------------------
        % W/H fields
        % -------------------------------------------------------------
        function refresh_dim_fields(obj)
            % Sync the W/H fields from the current ROI rectangles
            % (rounded sizes).
            if obj.syncing
                return;
            end
            views = {'view1','view2','view3','view4'};
            for k = 1:4
                v = views{k};
                if ~isfield(obj.ROIs, v) || ~isvalid(obj.ROIs.(v))
                    continue;
                end
                p = obj.ROIs.(v).Position;
                obj.syncing = true;
                obj.WFields.(v).Value = round(p(3));
                obj.HFields.(v).Value = round(p(4));
                obj.syncing = false;
            end
            obj.refresh_preview_label();
        end

        function apply_dim_edit(obj, view)
            % Apply the edited W/H to the ROI, anchoring the DISPLAYED
            % top-left corner and clamping to the image bounds; minimum
            % size 1.
            if obj.syncing || ~isfield(obj.ROIs, view) || ~isvalid(obj.ROIs.(view))
                return;
            end
            r = obj.ROIs.(view);
            p = r.Position;
            x = round(p(1));   % anchor left (display)
            y = round(p(2));   % anchor top  (display)
            w = obj.WFields.(view).Value;
            h = obj.HFields.(view).Value;
            w = max(1, round(w));
            h = max(1, round(h));
            max_w = max(1, obj.ImageW - x);
            max_h = max(1, obj.ImageH - y);
            w = min(w, max_w);
            h = min(h, max_h);
            newp = [x y w h];
            if ~isequal(newp, r.Position)
                r.Position = newp;
            end
            obj.refresh_dim_fields();
        end

        % -------------------------------------------------------------
        % Coordinate conversion (display <-> unmirrored source)
        % -------------------------------------------------------------
        function src = display_to_src(obj, view, pos)
            %% Display rectangle to unmirrored source bounds
            % Returns [row1 col1 row2 col2], 1-based, inclusive, rounded.
            x = pos(1); y = pos(2); w = pos(3); h = pos(4);
            col1 = round(x + 0.5);
            col2 = round(x + w - 0.5);
            row1 = round(y + 0.5);
            row2 = round(y + h - 0.5);
            if strcmp(view, 'view1') || strcmp(view, 'view4')
                % bottom panel: display is fliplr(source)
                scol1 = obj.ImageW - col2 + 1;
                scol2 = obj.ImageW - col1 + 1;
            else
                scol1 = col1; scol2 = col2;
            end
            src = [row1 scol1 row2 scol2];
        end

        function pos = src_to_display(obj, view, src)
            %% Inverse of display_to_src (rectangle edges at 0.5 offsets)
            row1 = src(1); scol1 = src(2); row2 = src(3); scol2 = src(4);
            if strcmp(view, 'view1') || strcmp(view, 'view4')
                col1 = obj.ImageW - scol2 + 1;
                col2 = obj.ImageW - scol1 + 1;
            else
                col1 = scol1; col2 = scol2;
            end
            pos = [col1 - 0.5, row1 - 0.5, col2 - col1 + 1, row2 - row1 + 1];
        end

        function M = current_src(obj)
            %% The ROIs as unmirrored source bounds, rows [View2; View3; View1; View4]
            M = zeros(4, 4);
            M(1, :) = obj.display_to_src('view2', obj.ROIs.view2.Position);
            M(2, :) = obj.display_to_src('view3', obj.ROIs.view3.Position);
            M(3, :) = obj.display_to_src('view1', obj.ROIs.view1.Position);
            M(4, :) = obj.display_to_src('view4', obj.ROIs.view4.Position);
        end

        function write_src_bounds(obj)
            %% Store the ROIs in app.data.region_bounds_src
            % Nx4 unmirrored source bounds [row1 col1 row2 col2], 1-based,
            % inclusive, rounded; rows [View2; View3; View1; View4].
            obj.main_app.data.region_bounds_src = obj.current_src();
        end

        % -------------------------------------------------------------
        % ROI JSON (schema version 1)
        % -------------------------------------------------------------
        function save_roi_json(obj)
            %% Save the ROIs as a version 1 ROI JSON
            % Extends cut_locations_per_view.json with the
            % unmirrored source bounds, coordinate origin, source size,
            % checkbox state, reconstruction path and FOV mappings.
            obj.write_src_bounds();
            src = obj.main_app.data.region_bounds_src;
            if isempty(src)
                return;
            end
            payload = struct();
            payload.schema_version = 1;
            payload.region_bounds_src = src;
            payload.regions = 4;
            payload.rotation = 3;
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'rotation')
                payload.rotation = obj.main_app.data.rotation;
            end
            payload.rabbit_panoramic = true;
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'rabbit_panoramic')
                payload.rabbit_panoramic = (obj.main_app.data.rabbit_panoramic == 1);
            end
            payload.source_dims = struct('height', obj.ImageH, 'width', obj.ImageW);
            payload.coordinate_origin = 'top-left';
            payload.unmirrored_coordinates = true;
            payload.reconstruction_path = '';
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'reconstruction_path')
                payload.reconstruction_path = obj.main_app.data.reconstruction_path;
            end
            % Stationary-camera FOV mappings, so the cut and reprojection
            % can map the bounds into a larger calibration or
            % reconstruction frame. Empty means the FOVs are the same.
            payload.fov_mapping = [];
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'reconstruction_fov_mapping') ...
                    && ~isempty(obj.main_app.data.reconstruction_fov_mapping)
                payload.fov_mapping = obj.main_app.data.reconstruction_fov_mapping;
            end
            payload.calibration_fov_mapping = [];
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'calibration_fov_mapping') ...
                    && ~isempty(obj.main_app.data.calibration_fov_mapping)
                payload.calibration_fov_mapping = obj.main_app.data.calibration_fov_mapping;
            end
            payload.calibration_path = '';
            if ~isempty(payload.calibration_fov_mapping) && isfield(obj.main_app.data, 'calibration_source')
                payload.calibration_path = char(obj.main_app.data.calibration_source);
            end
            payload.view_order = {'view2', 'view3', 'view1', 'view4'};
            % The dialog opens at the recording with the next free name, so
            % saving again does not replace the ROI file of an earlier cut
            default_name = 'cut_locations_per_view';
            start = '';
            try
                start = char(obj.main_app.file_info.path);
            catch
                start = '';   % test doubles without file_info
            end
            if ~isempty(start) && isfolder(start)
                default_name = rabbit_stack_io.next_free_path(fullfile(start, default_name), '.json');
            else
                default_name = [default_name '.json'];
            end
            [f, p] = uiputfile({'*.json', 'ROI JSON (*.json)'}, ...
                'Save ROI JSON', default_name);
            if isequal(f, 0)
                return;
            end
            try
                rabbit_stack_io.save_roi_json(fullfile(p, f), payload);
            catch ME
                uialert(obj.EditorFigure, ['Could not save ROI JSON: ', ME.message], ...
                    'Save ROI JSON failed');
            end
        end

        function load_roi_json(obj)
            %% Load a ROI JSON and restore the four ROIs
            % Accepts version 1 or a legacy cut list (converted
            % with defaults). Also restores the reconstruction path and
            % FOV mappings. Malformed files are rejected with a message.
            [f, p] = uigetfile({'*.json', 'ROI JSON (*.json)'}, 'Load ROI JSON');
            if isequal(f, 0)
                return;
            end
            try
                payload = rabbit_stack_io.load_roi_json(fullfile(p, f), obj.ImageH, obj.ImageW);
            catch ME
                uialert(obj.EditorFigure, ['Could not load ROI JSON: ', ME.message], ...
                    'Load ROI JSON failed');
                return;
            end
            src = payload.region_bounds_src;
            if size(src, 1) ~= 4
                uialert(obj.EditorFigure, ...
                    'ROI JSON must contain exactly 4 view bounds to restore the panoramic ROIs.', ...
                    'Load ROI JSON failed');
                return;
            end
            views = {'view2', 'view3', 'view1', 'view4'};
            for k = 1:4
                v = views{k};
                if isfield(obj.ROIs, v) && isvalid(obj.ROIs.(v))
                    obj.ROIs.(v).Position = obj.src_to_display(v, src(k, :));
                end
            end
            obj.refresh_dim_fields();
            % The reconstruction recording loaded before, to say when the
            % file names another one
            was_rec = '';
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'reconstruction_path')
                was_rec = char(obj.main_app.data.reconstruction_path);
                obj.main_app.data.reconstruction_path = payload.reconstruction_path;
            end
            % What the file changes is said, not done silently: the line starts afresh for this file
            [~, jn, je] = fileparts(fullfile(p, f));
            notes = {sprintf('Boxes from %s%s: to reproduce its cuts, leave them where they are.', jn, je)};
            named_rec = char(payload.reconstruction_path);
            if ~isempty(was_rec) && ~isempty(named_rec) && ~rabbit_stack_io.same_file(was_rec, named_rec)
                notes{end + 1} = sprintf(['The file names the reconstruction recording %s, not %s loaded before; the ' ...
                    'cuts now use the one the file names. Load the reconstruction stack again to use the other.'], ...
                    named_rec, was_rec);
            end
            old_rec = rabbit_panoramic_editor.offsets_of(obj.main_app.data, 'reconstruction_fov_mapping');
            % Restore the stationary-camera FOV mappings so a re-cut uses
            % the same mapping as when the JSON was saved
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'reconstruction_fov_mapping')
                if isfield(payload, 'fov_mapping')
                    obj.main_app.data.reconstruction_fov_mapping = payload.fov_mapping;
                else
                    obj.main_app.data.reconstruction_fov_mapping = [];
                end
            end
            % A calibration alignment reused from the reconstruction
            % recording follows the reconstruction alignment the file sets
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'calibration_fov_mapping')
                cm = obj.main_app.data.calibration_fov_mapping;
                if isstruct(cm) && isfield(cm, 'follows') && strcmp(cm.follows, 'reconstruction') && ...
                        isstruct(payload.fov_mapping)
                    nm = payload.fov_mapping;
                    nm.follows = 'reconstruction';
                    nm.position_source = 'assumed';
                    nm.provenance = ['taken from the reconstruction recording (same frame size): ' nm.provenance];
                    obj.main_app.data.calibration_fov_mapping = nm;
                    payload.calibration_fov_mapping = nm;
                    payload.calibration_path = char(obj.main_app.data.calibration_source);
                end
            end
            % The calibration mapping belongs to one calibration recording.
            % It replaces the position of the calibration
            % stack loaded now only when the file names that same stack; a
            % file without the name (an older file) sets it only when no
            % calibration stack is loaded. The picture follows.
            cal_note = '';
            if isprop(obj.main_app, 'data') && isfield(obj.main_app.data, 'calibration_fov_mapping')
                d = obj.main_app.data;
                loaded = '';
                if isfield(d, 'calibration_source'), loaded = char(d.calibration_source); end
                named = '';
                if isfield(payload, 'calibration_path'), named = payload.calibration_path; end
                if isempty(loaded) || (~isempty(named) && rabbit_stack_io.same_file(named, loaded))
                    obj.main_app.data.calibration_fov_mapping = payload.calibration_fov_mapping;
                elseif ~isempty(payload.calibration_fov_mapping)
                    cal_note = sprintf(['The ROI file''s calibration position belongs to %s, not to the calibration ' ...
                        'stack loaded now, so the loaded stack keeps the position found when it was loaded.'], ...
                        rabbit_panoramic_editor.or_unknown(named));
                end
            end
            obj.place_calibration();
            obj.show_reconstruction_of_json(payload.reconstruction_path);
            d = obj.main_app.data;
            new_rec = rabbit_panoramic_editor.offsets_of(d, 'reconstruction_fov_mapping');
            if isfield(d, 'reconstruction_loaded') && d.reconstruction_loaded && ~isequal(old_rec, new_rec)
                notes{end + 1} = sprintf(['The file moved the reconstruction recording''s alignment from %d px down, %d px ' ...
                    'right to %d px down, %d px right.'], old_rec(1), old_rec(2), new_rec(1), new_rec(2));
            end
            if ~isempty(cal_note), notes{end + 1} = cal_note; end
            % A calibration of the reconstruction's size lined up elsewhere
            cm = [];
            if isfield(d, 'calibration_fov_mapping'), cm = d.calibration_fov_mapping; end
            if isfield(d, 'calibration_mip') && ~isempty(d.calibration_mip) && isfield(d, 'reconstruction_mip') && ...
                    isequal(size(d.calibration_mip), size(d.reconstruction_mip)) && ...
                    ~(isstruct(cm) && isfield(cm, 'follows'))
                co = rabbit_panoramic_editor.offsets_of(d, 'calibration_fov_mapping');
                if any(abs(co - new_rec) > 1)
                    notes{end + 1} = sprintf(['The calibration recording has the reconstruction recording''s size but is ' ...
                        'lined up %d px down and %d px right of it: if both were recorded with the same area of ' ...
                        'interest, one of the two is wrong. Check the colour view.'], co(1) - new_rec(1), co(2) - new_rec(2));
                end
            end
            if ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                obj.StatusLabel.Text = strjoin(notes, ' ');
            end
            obj.note_old_view_labels(src);
            scaled = {};
            if ~isempty(payload.fov_mapping) && ~strcmp(payload.fov_mapping.type, 'crop'), scaled{end + 1} = 'reconstruction'; end
            if ~isempty(payload.calibration_fov_mapping) && ~strcmp(payload.calibration_fov_mapping.type, 'crop')
                scaled{end + 1} = 'calibration';
            end
            if ~isempty(scaled) && ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                obj.StatusLabel.Text = strtrim([obj.StatusLabel.Text sprintf([' The ROI file scales the %s frames ' ...
                    'against the optical mapping frames, a guess from the frame sizes alone (as in older ROI files); check ' ...
                    'the colour view, or load that stack again so that its position is measured.'], strjoin(scaled, ' and '))]);
            end
        end

        function note_old_view_labels(obj, src)
            %% Say so when a loaded ROI file has the older view names
            % Older ROI files name the tiles view2, view3, view1, view4
            % from left to right. Such a file is kept as saved: its boxes
            % and cuts are right and only the names of the views differ.
            [~, left_to_right] = sort(src(:, 2));
            if isequal(left_to_right(:)', [1 2 3 4]) && ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                obj.StatusLabel.Text = strtrim([obj.StatusLabel.Text ' This ROI file names the views view2, view3, ' ...
                    'view1, view4 from left to right, as older versions of the app did; only the names differ from ' ...
                    'what the editor would give now.']);
            end
        end

        function show_reconstruction_of_json(obj, path)
            %% Show the reconstruction file a loaded ROI JSON names
            % The JSON holds the path, not the max projection, so it is
            % made here, one frame at a time. A file that cannot be read is
            % not shown and the line under the panels says why.
            obj.ReconstructionProblem = '';
            path = char(path);
            d = obj.main_app.data;
            if ~isempty(path)
                [~, stem, ext] = fileparts(path);
                name = [stem ext];
                have = isfield(d, 'reconstruction_mip') && ~isempty(d.reconstruction_mip) && ...
                    isfield(d, 'reconstruction_mip_source') && ...
                    rabbit_stack_io.same_file(d.reconstruction_mip_source, path);
                if ~isfolder(path) && ~isfile(path)
                    obj.ReconstructionProblem = sprintf('%s named in the ROI file is not shown: the file was not found', name);
                elseif ~have
                    busy = uiprogressdlg(obj.EditorFigure, 'Title', 'Reconstruction preview', ...
                        'Message', sprintf('Making the maximum intensity of %s...', name), ...
                        'Indeterminate', 'on');
                    close_busy = onCleanup(@() close(busy));
                    try
                        stack = rabbit_stack_io.load_stack_preview(path);
                        obj.main_app.data.reconstruction_mip = stack.mip;
                        obj.main_app.data.reconstruction_mip_source = path;
                        obj.main_app.data.reconstruction_mip_frames = stack.n_frames;
                        if isfield(d, 'reconstruction_loaded')
                            obj.main_app.data.reconstruction_loaded = true;
                        end
                    catch ME
                        obj.ReconstructionProblem = sprintf('%s named in the ROI file is not shown: %s', ...
                            name, ME.message);
                    end
                    clear close_busy;
                end
            end
            obj.update_panels();
        end

        % -------------------------------------------------------------
        % Session end: confirm / cancel, single async fire
        % -------------------------------------------------------------
        function confirm_edit(obj)
            % "Regions Selected": store the final bounds and fire the real
            % RegionsChosenMenu callback exactly once (async).
            if obj.fired
                return;
            end
            % A box outside a loaded recording's frame cannot be cut from
            % that recording: ask before keeping it
            [ok, txt] = obj.check_boxes();
            if ~ok
                answer = uiconfirm(obj.EditorFigure, txt, 'Boxes outside a recording', ...
                    'Options', {'Go back to the boxes', 'Keep them'}, 'DefaultOption', 1, ...
                    'CancelOption', 1, 'Icon', 'warning');
                if ~strcmp(answer, 'Keep them')
                    return;
                end
            end
            obj.write_src_bounds();
            obj.fired = true;
            obj.schedule_fire_once();
        end

        function cancel_edit(obj)
            % Cancel/close: fire once with region_bounds_src empty (the app
            % treats empty src as cancel and returns without applying).
            if obj.fired
                % already fired - just close the figure
                if isvalid(obj.EditorFigure)
                    delete(obj.EditorFigure);
                end
                return;
            end
            obj.main_app.data.region_bounds_src = [];
            obj.fired = true;
            obj.schedule_fire_once();
            if isvalid(obj.EditorFigure)
                delete(obj.EditorFigure);
            end
        end

        function schedule_fire_once(obj)
            %% Schedule the RegionsChosen callback on a timer
            % define_regions reaches uiwait only after
            % adapt_rabbit_regions returns, so the callback cannot be
            % called directly from the constructor.
            if ~isempty(obj.fire_timer) && isvalid(obj.fire_timer)
                return;
            end
            obj.fire_timer = timer('StartDelay', 0.08, ...
                'TimerFcn', @(s,e) obj.fire_regions_chosen());
            start(obj.fire_timer);
        end

        function fire_regions_chosen(obj)
            %% Run the app's 'regions selected' callback
            if ~isvalid(obj)
                return;
            end
            % isvalid needs a handle; test fakes may not be the real app
            if isa(obj.main_app, 'handle') && isvalid(obj.main_app) && ...
                    isprop(obj.main_app, 'RegionsChosenMenu')
                feval(obj.main_app.RegionsChosenMenu.MenuSelectedFcn, obj.main_app, []);
            end
            if ~isempty(obj.fire_timer) && isvalid(obj.fire_timer)
                stop(obj.fire_timer);
                delete(obj.fire_timer);
            end
            if isvalid(obj.EditorFigure)
                delete(obj.EditorFigure);
            end
        end

        function delete(obj)
            %% Delete the timer and the editor figure
            if ~isempty(obj.fire_timer) && isvalid(obj.fire_timer)
                stop(obj.fire_timer);
                delete(obj.fire_timer);
            end
            if ~isempty(obj.EditorFigure) && isvalid(obj.EditorFigure)
                delete(obj.EditorFigure);
            end
        end
    end

    methods (Static)
        function o = offsets_of(d, field)
            %% [down right] of an alignment on app.data, [0 0] when there is none
            o = [0 0];
            if isfield(d, field) && isstruct(d.(field))
                o = [d.(field).om_window_in_rec.off, rabbit_cut_tiffs.cols_off_of(d.(field))];
            end
        end

        function t = or_unknown(path)
            %% A file's name, or a plain word when the ROI file names none
            if isempty(path)
                t = 'a calibration recording the file does not name';
            else
                [~, n, e] = fileparts(path);
                t = [n e];
            end
        end

        function fg = foreground_mask(mip)
            %% Otsu foreground mask of a display MIP
            % NaN/Inf count as background. A flat or all-NaN image gives
            % an all-false mask. Used only for the ROI estimate.
            if isempty(mip)
                fg = false(0, 0);
                return;
            end
            d = double(mip);
            fin = d(isfinite(d));
            if isempty(fin)
                fg = false(size(d));
                return;
            end
            mn = min(fin); mx = max(fin);
            if ~isfinite(mx - mn) || mx - mn <= 0
                fg = false(size(d));
                return;
            end
            d = (d - mn) ./ (mx - mn);
            d(~isfinite(d)) = 0;
            % Otsu threshold (base MATLAB, no toolbox dependency).
            counts = histcounts(d(:), 0:1/256:1);
            total = sum(counts);
            if total == 0
                fg = false(size(d));
                return;
            end
            wB = cumsum(counts) / total;
            wF = 1 - wB;
            muB = cumsum((0:255) .* counts) ./ max(cumsum(counts), 1);
            muT = sum((0:255) .* counts) / total;
            varB = wB .* wF .* (muB - muT) .^ 2;
            varB(wB == 0 | wF == 0) = 0;
            [~, t] = max(varB);
            thr = t / 256;
            fg = d > thr;
        end

        function [r1, c1, r2, c2] = largest_blob(band)
            %% Bounding box of the largest 8-connected blob in a mask
            % Band-local, 1-based, inclusive. Empty if there is no
            % foreground.
            if ~any(band(:))
                r1 = []; c1 = []; r2 = []; c2 = [];
                return;
            end
            L = bwlabel(band, 8);
            if isempty(L)
                r1 = []; c1 = []; r2 = []; c2 = [];
                return;
            end
            idx = L(L > 0);
            areas = accumarray(idx, 1);
            [~, bi] = max(areas);
            [rr, cc] = find(L == bi);
            r1 = min(rr); r2 = max(rr);
            c1 = min(cc); c2 = max(cc);
        end
    end
end
