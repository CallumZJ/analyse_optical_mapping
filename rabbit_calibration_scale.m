classdef rabbit_calibration_scale
    %% The Conduction Velocity tab's pixel size per view (View1-View4), from a rig calibration or by hand
    % Collin Snitchler
    % 24.11.2026
    % Purpose: a calibration recording loaded with the data (Define regions,
    %          Load calibration stack...) can be calibrated right after the
    %          cut, from a question with a Calibrate now... button. The
    %          calibration is made by the Reconstruction tab's own window and
    %          code (rabbit_reconstruction_ui.ReconstructionCalibrateButtonPushed),
    %          so the tab lists and chooses it and it is not run again there.
    %          When it may give mm (PASSED or WARNED), its pixel size of each
    %          view fills the Conduction Velocity tab, after the user has
    %          confirmed the cube edge it rests on. The CV map then uses each
    %          view's own size for the pixels of that view (pixel_map,
    %          rabbit_cv_map).
    %          With a run selected in the Reconstruction tab whose
    %          pixel_size.json comes from the same calibration, the question
    %          also offers "Use the heart-surface sizes of run <id>"
    %          (heart_views); the default stays the size at the cube's depth.
    %
    % Section map (search for the quoted line; line numbers move)
    %   "% ---- The question after the cut ----"
    %   "% ---- From a calibration ----"
    %   "% ---- By hand ----"
    %   "% ---- Keeping it right later ----"
    %   "% ---- Which pixel is in which view ----"
    %   "% ---- The Conduction Velocity tab's fields ----"
    %   "% ---- The state ----"
    %   "% ---- Small helpers ----"
    %
    % Views. View1 to View4 are the regions of the recording frame from left
    % to right (the regions file's view_order, written by rabbit_stack_io
    % since view numbering was fixed left to right). The
    % calibration's cameras tile1-tile4 are its column windows from left to
    % right (rabbit_calibration.tile_windows sorts the ROI columns), so
    % tile k is View k. On the map (the canvas) the regions may sit in
    % another order: canvas region k is the view whose region starts at the
    % rank of app.data.region_bounds(k,2) among the four.
    %
    % What a calibration value is. calibration.json gives, per view,
    % mm_per_px_at_target = depth of the cube's middle / focal length, in
    % pixels of the reconstruction frame (rabbit_pycamset_calibrate.py),
    % the focal length being the recipe's stated value (not changed here).
    % It is the size at the cube, not at the heart surface. A map pixel is
    % that times fov_mapping.scale (optical mapping frame against
    % reconstruction frame) times the binning.
    %
    % State. processed_data.scale_views (1x4, um per pixel of the map as it
    % is binned now) is what the CV map uses; processed_data.scale keeps one
    % value when all four are equal, else NaN. app.data.calibration_scale
    % holds per view the size at binning 1 (base_um_views), where it came
    % from (view_sources: 'calibration <id>', 'typed', 'measured') and the
    % calibration's record, so binning, Undo and a changed calibration are
    % followed or asked about, never applied silently.
    %
    % Single view or four views. The four fields, and a size per view, are
    % only for data with the rabbit panoramic regions: app.data.rabbit_panoramic
    % == 1 (the region dialog's checkbox) with app.data.regions == 4 and the
    % four regions applied (processed_data.region_widths, data.region_bounds),
    % the same test define_regions uses for its rabbit mode. Other data keep
    % today's behaviour: one field, one value for the whole map (Input
    % Scale, Measure length), not changed by binning.
    % Rule: the sizes are kept with the layout they were set for
    % (data.scale_layout, 'single' or 'views'). When regions are applied and
    % the layout differs, the sizes are cleared (back to 1 um/pixel, not
    % set) and the user is told; one value is never spread over four views,
    % nor four views folded into one.
    %
    % The app calls: offer_after_cut (define_regions, after the cut),
    % regions_changed (apply_regions), input_scale (Input Scale), measured
    % (Measure length), binning_changed (Binning, Undo), before_cv_map and
    % pixel_map (CV map). The Reconstruction tab calls show and views.

    properties (Constant)
        SCHEMA = 'rabbit_calibration_scale.v2';
        TAG = 'CalibrationScale';            % the controls made on the Conduction Velocity tab
        TITLE = 'Scale from calibration';
        VIEWS = {'View1', 'View2', 'View3', 'View4'};
    end

    methods (Static)

        % ---- The question after the cut ----

        function offer_after_cut(app)
            %% After the cut: calibrate the rig now from the calibration recording loaded with the data
            % Nothing is asked when no calibration recording was loaded.
            if ~rabbit_calibration_scale.bound(app), return; end
            if ~isfield(app.data, 'calibration_source') || isempty(app.data.calibration_source), return; end
            fig = app.opticalmappingUIFigure;
            [~, nm, ex] = fileparts(char(app.data.calibration_source));
            why = rabbit_calibration_scale.window_ready(app);
            if ~isempty(why)
                uialert(fig, sprintf(['%s%s was loaded as the calibration recording, but the rig cannot be ' ...
                    'calibrated yet: %s You can calibrate later with Calibrate... in the Reconstruction tab (step 2).'], ...
                    nm, ex, why), 'Rig calibration', 'Icon', 'info');
                return;
            end
            id = app.recon.ReconstructionCalibrationDropDown.Value;
            cal_dir = '';
            if ~isempty(id)
                % A calibration of this recording is chosen already (an
                % earlier session, or an earlier cut): it can be used as it is
                cal_dir = fullfile(app.recon.reconstruction_calibration_root(), id);
                use = sprintf('Use %s', id);
                opts = {use, 'Calibrate again...', 'Later'};
                msg = sprintf(['This recording already has a rig calibration, %s (%s), chosen in the ' ...
                    'Reconstruction tab. Use its pixel sizes on the Conduction Velocity tab, or calibrate again from %s%s?'], ...
                    id, rabbit_calibration_scale.status_of(cal_dir), nm, ex);
            else
                use = '';
                opts = {'Calibrate now...', 'Later'};
                msg = sprintf(['%s%s was loaded as the calibration recording. Calibrate the rig now? You type ' ...
                    'the cube edge in the calibration window. The Reconstruction tab then uses this calibration, ' ...
                    'so it is not run again there, and its pixel size of each view can fill in the Conduction ' ...
                    'Velocity tab.'], nm, ex);
            end
            answer = uiconfirm(fig, msg, 'Rig calibration', 'Options', opts, ...
                'DefaultOption', numel(opts), 'CancelOption', numel(opts));
            if ~isempty(use) && strcmp(answer, use)
                rabbit_calibration_scale.fill(app, cal_dir, fig);
            elseif any(strcmp(answer, {'Calibrate now...', 'Calibrate again...'}))
                rabbit_calibration_scale.open_window(app);
            end
        end

        function why = window_ready(app)
            %% '' when the calibration window can be opened, else why not, in plain words
            why = '';
            if ~rabbit_calibration_scale.bound(app)
                why = 'no recording is loaded.';
                return;
            end
            images = strtrim(char(app.recon.ReconstructionImagesField.Value));
            roi = strtrim(char(app.recon.ReconstructionRoiField.Value));
            if isempty(images) || ~isfolder(images)
                why = ['it uses the same four views as the cut reconstruction images, and there are none ' ...
                    '(load the reconstruction stack in Define regions, then cut).'];
            elseif isempty(roi) || exist(roi, 'file') ~= 2
                why = 'the regions file that the cut writes is missing (cut the recordings first).';
            end
        end

        function open_window(app)
            %% The Reconstruction tab's calibration window, filling the pixel sizes when it is done
            app.recon.ReconstructionCalibrateButtonPushed(@(w) rabbit_calibration_scale.after_window(app, w));
        end

        function after_window(app, w)
            %% After a calibration in the window: the pixel sizes, when it may give mm
            % The window shows the verdict itself; a calibration that did not
            % finish changes nothing here.
            if isempty(w) || ~isvalid(w) || ~w.LastOk || isempty(w.LastDir)
                rabbit_calibration_scale.show(app);
                return;
            end
            parent = app.opticalmappingUIFigure;
            if isprop(w, 'Figure') && ~isempty(w.Figure) && isvalid(w.Figure)
                parent = w.Figure;   % the calibration window is modal: ask in front of it
            end
            rabbit_calibration_scale.fill(app, w.LastDir, parent);
        end

        % ---- From a calibration ----

        function ok = fill(app, cal_dir, parent)
            %% Fill the four views' pixel sizes from a calibration, after the cube edge is confirmed
            ok = false;
            if nargin < 3 || isempty(parent), parent = app.opticalmappingUIFigure; end
            if ~strcmp(rabbit_calibration_scale.layout(app), 'views')
                uialert(parent, ['This data has no four views (the rabbit panoramic regions are not set), so a rig ' ...
                    'calibration gives no pixel size for it. Nothing was changed.'], rabbit_calibration_scale.TITLE);
                return;
            end
            [v, why] = rabbit_calibration_scale.scale_from(app, cal_dir);
            if isempty(v)
                uialert(parent, [why ' The pixel sizes on the Conduction Velocity tab were not changed.'], ...
                    rabbit_calibration_scale.TITLE);
                rabbit_calibration_scale.show(app);
                return;
            end
            um = rabbit_calibration_scale.um();
            b = rabbit_calibration_scale.binning_of(app);
            warned = '';
            if strcmp(v.status, 'WARNED')
                warned = ' No second cube recording checked its distances (WARNED).';
            end
            others = '';
            if ~isempty(v.holdout_edges_mm)
                others = sprintf(' The held-out recordings were given %s mm.', ...
                    strjoin(arrayfun(@(x) sprintf('%g', x), v.holdout_edges_mm, 'UniformOutput', false), ', '));
            end
            msg = sprintf(['Calibration %s (%s) gives these sizes of a map pixel (binning %g), at the depth of the ' ...
                'cube''s middle, not at the heart surface: %s %s/pixel.%s\n\nAll its distances rest on the cube edge ' ...
                'typed in the calibration window: %g mm.%s If the cube''s edge is not %g mm, every distance and ' ...
                'conduction velocity will be off by the same factor.\n\nFill in these four values on the Conduction ' ...
                'Velocity tab?'], v.calibration_id, v.status, b, ...
                rabbit_calibration_scale.view_list(v.um_cube_views * b), um, warned, v.edge_mm, others, v.edge_mm);
            yes = sprintf('Yes, the edge is %g mm', v.edge_mm);
            options = {yes, 'No, leave them'};
            % The heart-surface sizes of the run
            % selected in the Reconstruction tab, as an option; the
            % default stays the cube's depth
            [hv, run_id] = rabbit_calibration_scale.heart_views(app, v);
            heart = '';
            if ~isempty(hv)
                heart = sprintf('Use the heart-surface sizes of run %s', run_id);
                options = {yes, heart, 'No, leave them'};
                msg = sprintf(['%s\n\nRun %s measured the pixel on its heart surface with this calibration ' ...
                    '(outputs\\metric\\pixel_size.json): %s %s/pixel. "%s" fills those in instead (the same cube ' ...
                    'edge).'], msg, run_id, rabbit_calibration_scale.view_list(hv * b), um, heart);
            end
            answer = uiconfirm(parent, msg, rabbit_calibration_scale.TITLE, ...
                'Options', options, 'DefaultOption', numel(options), 'CancelOption', numel(options), 'Icon', 'question');
            if ~isempty(heart) && strcmp(answer, heart)
                v.surface_run = run_id;
                src = repmat({sprintf('calibration %s, heart surface of run %s', v.calibration_id, run_id)}, 1, 4);
                rabbit_calibration_scale.apply(app, hv, src, v);
                rabbit_calibration_scale.history(app, sprintf(['Pixel size from calibration %s (%s), cube edge %g mm ' ...
                    '(as typed), on the heart surface of run %s (outputs\\metric\\pixel_size.json), binning %g: %s %s/pixel.'], ...
                    v.calibration_id, v.status, v.edge_mm, run_id, b, rabbit_calibration_scale.view_list(hv * b), um));
                ok = true;
                return;
            end
            if ~strcmp(answer, yes)
                rabbit_calibration_scale.show(app);
                return;
            end
            src = repmat({['calibration ' v.calibration_id]}, 1, 4);
            rabbit_calibration_scale.apply(app, v.um_cube_views, src, v);
            rabbit_calibration_scale.history(app, sprintf(['Pixel size from calibration %s (%s), cube edge %g mm ' ...
                '(as typed), at the depth of the cube''s middle, binning %g: %s %s/pixel.'], v.calibration_id, ...
                v.status, v.edge_mm, b, rabbit_calibration_scale.view_list(v.um_cube_views * b), um));
            ok = true;
        end

        function [v, why] = scale_from(app, cal_dir)
            %% The four views' sizes at binning 1 that a calibration gives; [] and why when it gives none
            v = [];
            why = '';
            [~, id] = fileparts(char(cal_dir));
            [ok, err, c] = rabbit_calibration.read_result(cal_dir);
            if ~ok
                why = sprintf('Calibration %s has no usable result: %s', id, err);
                return;
            end
            try
                verdict = rabbit_calibration.read_json(fullfile(cal_dir, 'verdict.json'));
            catch
                why = sprintf('Calibration %s has no verdict.', id);
                return;
            end
            if ~(isfield(verdict, 'metric_allowed') && islogical(verdict.metric_allowed) && ...
                    isscalar(verdict.metric_allowed) && verdict.metric_allowed)
                why = sprintf('Calibration %s did not pass its checks (%s), so it gives no pixel size.', id, char(verdict.status));
                return;
            end
            cams = c.cameras;
            if ~isfield(cams, 'mm_per_px_at_target') || ~isfield(cams, 'depth_at_target_mm')
                why = sprintf('Calibration %s does not give the pixel size at the cube.', id);
                return;
            end
            % calibration.json's cameras tile1..tile4 are the column windows
            % left to right: View1..View4 (read_result checks the order)
            mm = double([cams.mm_per_px_at_target]);
            depth = double([cams.depth_at_target_mm]);
            if numel(mm) ~= 4 || any(~isfinite(mm)) || any(mm <= 0)
                why = sprintf('Calibration %s gives no usable pixel size at the cube.', id);
                return;
            end
            edge = double(c.target.edge_mm);
            if ~(isscalar(edge) && isfinite(edge) && edge > 0)
                why = sprintf('Calibration %s does not state its cube edge.', id);
                return;
            end
            % One optical mapping pixel spans fov_mapping.scale
            % reconstruction pixels (rabbit_stack_io.map_bounds_across_fov)
            s = [1 1];
            m = [];
            if isfield(app.data, 'reconstruction_fov_mapping'), m = app.data.reconstruction_fov_mapping; end
            if isstruct(m) && isfield(m, 'scale') && isstruct(m.scale)
                s = [double(m.scale.vertical), double(m.scale.horizontal)];
            end
            if abs(s(1) - s(2)) > 1e-9
                why = sprintf(['The optical mapping frames are scaled %g vertically and %g horizontally against the ' ...
                    'reconstruction frames, so a pixel of the map is not square and one size per view cannot be given.'], ...
                    s(1), s(2));
                return;
            end
            try
                sp = rabbit_calibration.read_json(fullfile(cal_dir, 'spec.json'));
                r = sp.recordings;
                if iscell(r), r = rabbit_calibration.same_fields(r); end
                e = double([r(strcmp({r.role}, 'holdout')).edge_mm]);
                held = unique(e(isfinite(e) & abs(e - edge) > 1e-9));
            catch
                held = [];
            end
            src = '';
            if isfield(app.data, 'calibration_source'), src = char(app.data.calibration_source); end
            v = struct('calibration_id', id, 'calibration_dir', char(cal_dir), 'status', char(verdict.status), ...
                'edge_mm', edge, 'holdout_edges_mm', held, 'target_type', char(c.target.type), ...
                'mm_cube_views', mm, 'um_cube_views', 1000 * mm * s(1), 'depth_mm', depth, 'fov_scale', s(1), ...
                'calibration_recording', src, 'result_stamp', rabbit_calibration_scale.stamp(cal_dir), 'surface_run', '', ...
                'made', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
        end

        function [um, run_id] = heart_views(app, v)
            %% The four views' sizes at binning 1 on the heart surface of the selected run; [] when it gives none
            % v: the
            % calibration's sizes (scale_from). The run is the one selected
            % in the Reconstruction tab; its outputs\metric\pixel_size.json
            % must name this calibration and give all four views' tiles. A
            % pixel's size is depth / focal length in both records, so the
            % heart size of view k is the cube's times heart / cube of that
            % view (binning and the frame scale cancel in the ratio, as in
            % heart_clause).
            um = [];
            run_id = '';
            try
                run_dir = app.recon.reconstruction_selected_run_dir();
            catch
                return;
            end
            if isempty(run_dir), return; end
            jf = fullfile(run_dir, 'outputs', 'metric', 'pixel_size.json');
            if exist(jf, 'file') ~= 2, return; end
            try
                p = rabbit_calibration.read_json(jf);
            catch
                return;
            end
            if ~isfield(p, 'calibration_id') || ~strcmp(char(p.calibration_id), v.calibration_id), return; end
            if ~isfield(p, 'views') || ~isstruct(p.views) || ~isfield(p.views, 'tile') || ...
                    ~isfield(p.views, 'median_mm_per_px'), return; end
            if isfield(p, 'om_pixel_same_size') && islogical(p.om_pixel_same_size) && isscalar(p.om_pixel_same_size) ...
                    && p.om_pixel_same_size ~= (abs(v.fov_scale - 1) < 1e-9), return; end
            r = nan(1, 4);
            for k = 1:4
                hit = strcmp({p.views.tile}, rabbit_calibration.TILES{k});
                if nnz(hit) ~= 1, return; end
                h = double(p.views(hit).median_mm_per_px);
                if ~(isscalar(h) && isfinite(h) && h > 0), return; end
                r(k) = h / double(v.mm_cube_views(k));
            end
            um = v.um_cube_views .* r;
            [~, run_id] = fileparts(run_dir);
        end

        % ---- By hand ----

        function input_scale(app)
            %% Input Scale: one value for single-view data (the app's single scale), the four views' window for rabbit data
            if strcmp(rabbit_calibration_scale.layout(app), 'views')
                rabbit_calibration_scale.input_views(app);
                return;
            end
            um = rabbit_calibration_scale.um();
            answer = inputdlg(sprintf('Enter scale in %s/pixel:', um), 'Scale', [1 35], ...
                {num2str(rabbit_calibration_scale.single_value(app), 6)});
            if isempty(answer), return; end
            x = str2double(answer{1});
            if ~(isfinite(x) && x > 0)
                uialert(app.opticalmappingUIFigure, sprintf('"%s" is not a pixel size. Nothing was changed.', answer{1}), ...
                    'Input Scale');
                return;
            end
            rabbit_calibration_scale.set_single(app, x, 'typed');
            rabbit_calibration_scale.history(app, sprintf('Scale: %s %s/pixel (typed).', num2str(x, 4), um));
        end

        function changed = input_views(app)
            %% Input Scale: one window with the four views, each filled with its value now
            % Only the fields the user changes are taken; nothing is set for
            % all four at once.
            changed = [];
            um = rabbit_calibration_scale.um();
            [now_v, src] = rabbit_calibration_scale.views(app);
            prompts = cell(1, 4);
            for k = 1:4
                prompts{k} = sprintf('%s (%s/pixel, now from %s):', rabbit_calibration_scale.VIEWS{k}, um, src{k});
            end
            defaults = arrayfun(@(x) num2str(x, 6), now_v, 'UniformOutput', false);
            answer = inputdlg(prompts, 'Pixel size of each view', [1 50], defaults);
            if isempty(answer), return; end
            new_v = now_v;
            for k = 1:4
                if strcmp(strtrim(answer{k}), defaults{k}), continue; end
                x = str2double(answer{k});
                if ~(isfinite(x) && x > 0)
                    uialert(app.opticalmappingUIFigure, sprintf(['%s: "%s" is not a pixel size. Nothing was ' ...
                        'changed; type a positive number of %s per pixel.'], rabbit_calibration_scale.VIEWS{k}, ...
                        answer{k}, um), 'Input Scale');
                    return;
                end
                new_v(k) = x;
                changed(end + 1) = k; %#ok<AGROW>
            end
            if isempty(changed), return; end
            b = rabbit_calibration_scale.binning_of(app);
            src(changed) = {'typed'};
            rabbit_calibration_scale.apply(app, new_v / b, src, []);
            rabbit_calibration_scale.history(app, sprintf('Pixel size typed in: %s %s/pixel.', ...
                rabbit_calibration_scale.view_list(new_v(changed), changed), um));
        end

        function txt = measured(app, um_per_px, line_cols)
            %% Measure length: the view the line was drawn in gets the size; a line across two views is refused
            % line_cols: the columns of the line's two ends on the map.
            % txt: what was set, for the app's message; '' when refused.
            txt = '';
            if ~(isnumeric(um_per_px) && isscalar(um_per_px) && isfinite(um_per_px) && um_per_px > 0)
                uialert(app.opticalmappingUIFigure, ['The line and the length typed give no pixel size (type a ' ...
                    'positive length in mm, and draw a line longer than a pixel). Nothing was changed.'], 'Measure length');
                return;
            end
            if ~strcmp(rabbit_calibration_scale.layout(app), 'views')
                % Single-view data: one value for the map
                rabbit_calibration_scale.set_single(app, um_per_px, 'measured');
                txt = 'the whole map';
                return;
            end
            [view_of_col, why] = rabbit_calibration_scale.column_views(app);
            if ~isempty(why)
                uialert(app.opticalmappingUIFigure, [why ' The measured length was not used.'], 'Measure length');
                return;
            end
            c = min(max(round(double(line_cols(:))), 1), numel(view_of_col));
            k = unique(view_of_col(min(c):max(c)));
            if numel(k) ~= 1 || k == 0
                uialert(app.opticalmappingUIFigure, ['The line crosses from one view into another. Draw it inside ' ...
                    'one view: each view has its own pixel size. Nothing was changed.'], 'Measure length');
                return;
            end
            [now_v, src] = rabbit_calibration_scale.views(app);
            b = rabbit_calibration_scale.binning_of(app);
            now_v(k) = um_per_px;
            src{k} = 'measured';
            rabbit_calibration_scale.apply(app, now_v / b, src, []);
            txt = rabbit_calibration_scale.VIEWS{k};   % the app's History line names it
        end

        % ---- Keeping it right later ----

        function binning_changed(app)
            %% After Binning or its Undo: every view's size follows the map's pixel
            r = rabbit_calibration_scale.record(app);
            if isempty(r), return; end
            b = rabbit_calibration_scale.binning_of(app);
            if abs(b - r.binning) < 1e-12, return; end
            r.binning = b;
            app.data.calibration_scale = r;
            rabbit_calibration_scale.set_processed(app, r.base_um_views * b);
            rabbit_calibration_scale.history(app, sprintf('Pixel sizes set for binning %g: %s %s/pixel.', b, ...
                rabbit_calibration_scale.view_list(r.base_um_views * b), rabbit_calibration_scale.um()));
            rabbit_calibration_scale.show(app);
        end

        function go = before_cv_map(app)
            %% Before a CV map: sizes from a calibration that may be out of date are asked about
            go = rabbit_calibration_scale.regions_changed(app);
            if ~go, return; end   % cleared and said so: not with 1 um/pixel unasked
            rabbit_calibration_scale.binning_changed(app);
            r = rabbit_calibration_scale.record(app);
            if isempty(r) || isempty(r.calibration), return; end
            uses = startsWith(r.view_sources, 'calibration ');
            if ~any(uses), return; end
            s = r.calibration;
            problem = '';
            if ~isfolder(s.calibration_dir)
                problem = sprintf('its folder, %s, is gone', s.calibration_dir);
            elseif ~isequal(rabbit_calibration_scale.stamp(s.calibration_dir), s.result_stamp)
                problem = 'its result has changed since the sizes were filled in';
            elseif ~any(strcmp(rabbit_calibration_scale.status_of(s.calibration_dir), {'PASSED', 'WARNED'}))
                problem = 'it no longer passes its checks';
            else
                now_src = '';
                if isfield(app.data, 'calibration_source'), now_src = char(app.data.calibration_source); end
                if ~isempty(s.calibration_recording) && ~isempty(now_src) && ...
                        ~rabbit_stack_io.same_file(now_src, s.calibration_recording)
                    [~, nm, ex] = fileparts(now_src);
                    problem = sprintf('another calibration recording, %s%s, is loaded now', nm, ex);
                end
            end
            if isempty(problem), return; end
            answer = uiconfirm(app.opticalmappingUIFigure, sprintf(['The pixel sizes of %s came from calibration ' ...
                '%s, but %s. Make the map with them anyway? Otherwise set them again: Scale from calibration..., ' ...
                'Input Scale or Measure length.'], strjoin(rabbit_calibration_scale.VIEWS(uses), ', '), ...
                s.calibration_id, problem), rabbit_calibration_scale.TITLE, ...
                'Options', {'Use them anyway', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            go = strcmp(answer, 'Use them anyway');
            if go
                rabbit_calibration_scale.history(app, sprintf('Pixel sizes from calibration %s used although %s.', ...
                    s.calibration_id, problem));
            end
        end

        % ---- Which pixel is in which view ----

        function [view_of_col, why] = column_views(app)
            %% The view (1-4) of each column of the map; 0 outside the views
            % Canvas region k (apply_regions places them left to right with
            % processed_data.region_widths) is the view whose region starts
            % at the rank of region_bounds(k,2) in the recording frame. A
            % binned map is mapped back in proportion. A map whose width no
            % longer fits the regions (cropped or turned since) has no views.
            why = '';
            W = app.processed_data.width;
            view_of_col = zeros(1, W);
            ok = isfield(app.data, 'regions') && app.data.regions == 4 && ...
                isfield(app.processed_data, 'region_widths') && numel(app.processed_data.region_widths) == 4 && ...
                isfield(app.data, 'region_bounds') && size(app.data.region_bounds, 1) == 4;
            if ~ok
                why = 'The map has no four regions, so its pixels cannot be given to the four views.';
                return;
            end
            w = double(app.processed_data.region_widths(:)');
            W0 = sum(w);
            b = rabbit_calibration_scale.binning_of(app);
            if abs(W0 / b - W) > 2   % binning rounds each size up: at most a pixel a step
                why = sprintf(['The map is %d pixels wide, but its four regions make %d pixels at binning %g: it was ' ...
                    'cropped or turned after the regions were set, so the app cannot tell which pixels belong to ' ...
                    'which view. Set the regions again.'], W, W0, b);
                return;
            end
            [~, ~, rank] = unique(double(app.data.region_bounds(:, 2)));
            if numel(unique(rank)) ~= 4
                why = 'Two regions start in the same column, so the views cannot be told apart.';
                return;
            end
            edges = cumsum(w);
            u = min(W0, floor(((1:W) - 0.5) * W0 / W) + 1);   % the column at binning 1
            for c = 1:W
                k = find(u(c) <= edges, 1);
                view_of_col(c) = rank(k);
            end
        end

        function [S, V, why] = pixel_map(app)
            %% Per pixel of the map: its size in um (S) and its view (V, 0 = none), for the CV map
            H = app.processed_data.height;
            W = app.processed_data.width;
            if ~strcmp(rabbit_calibration_scale.layout(app), 'views')
                % Single-view data: one size, no views
                S = rabbit_calibration_scale.single_value(app) * ones(H, W);
                V = ones(H, W);
                why = '';
                return;
            end
            v = rabbit_calibration_scale.views(app);
            [view_of_col, why] = rabbit_calibration_scale.column_views(app);
            if isempty(why)
                S = repmat(v(max(view_of_col, 1)), H, 1);
                V = repmat(view_of_col, H, 1);
            elseif all(abs(v - v(1)) <= 1e-12 * v(1))
                % One size everywhere: the single-scale map, without views
                S = v(1) * ones(H, W);
                V = ones(H, W);
                why = '';
            else
                S = [];
                V = [];
            end
        end

        % ---- The Conduction Velocity tab's fields ----

        function show(app)
            %% The four views' sizes, where each came from, and Scale from calibration... (made the first time)
            if ~isprop(app, 'GridLayout22') || isempty(app.GridLayout22) || ~isvalid(app.GridLayout22), return; end
            g = app.GridLayout22;
            T = rabbit_calibration_scale.TAG;
            box = findall(g, 'Tag', [T 'Grid']);
            if isempty(box)
                box = uigridlayout(g, [2 9], 'Tag', [T 'Grid'], 'Padding', [0 0 0 0], 'RowSpacing', 2);
                box.Layout.Row = 4;
                box.Layout.Column = [3 6];
                % The unit names the binning
                % ("um per binned pixel (binning 2)"), on two lines beside
                % both rows, so the first column stays narrow
                box.ColumnWidth = {95, 45, '1x', 45, '1x', 45, '1x', 45, '1x'};
                unit = uilabel(box, 'Text', sprintf('%s/pixel', rabbit_calibration_scale.um()), 'Tag', [T 'Unit'], ...
                    'WordWrap', 'on', 'VerticalAlignment', 'top');
                unit.Layout.Row = [1 2]; unit.Layout.Column = 1;
                % One source label for all four
                % views when they came from one calibration, instead of
                % four truncated copies of its id (shown by show)
                all4 = uilabel(box, 'Text', '', 'FontSize', 10, 'Tag', [T 'SourceAll'], 'Visible', 'off');
                all4.Layout.Row = 2; all4.Layout.Column = [2 9];
                for k = 1:4
                    lb = uilabel(box, 'Text', rabbit_calibration_scale.VIEWS{k}, 'HorizontalAlignment', 'right', ...
                        'Tag', sprintf('%sName%d', T, k));
                    lb.Layout.Row = 1; lb.Layout.Column = 2 * k;
                    f = uieditfield(box, 'numeric', 'Editable', 'off', 'ValueDisplayFormat', '%.4g', ...
                        'Tag', sprintf('%sView%d', T, k));
                    f.Layout.Row = 1; f.Layout.Column = 2 * k + 1;
                    s = uilabel(box, 'Text', '', 'FontSize', 10, 'Tag', sprintf('%sSource%d', T, k));
                    s.Layout.Row = 2; s.Layout.Column = [2 * k, 2 * k + 1];
                end
                btn = uibutton(g, 'push', 'Text', 'Scale from calibration...', 'Tag', [T 'Button'], ...
                    'ButtonPushedFcn', @(~, ~) rabbit_calibration_scale.button_pushed(app));
                btn.Layout.Row = 3;
                btn.Layout.Column = 4;
                lbl = uilabel(g, 'Tag', [T 'Line'], 'WordWrap', 'on', 'Text', '');
                lbl.Layout.Row = 3;   % row 2 beside Time max holds the slowest speed resolved (rabbit_cv_map)
                lbl.Layout.Column = [5 6];
            end
            btn = findall(g, 'Tag', [T 'Button']);
            if rabbit_calibration_scale.bound(app) && strcmp(rabbit_calibration_scale.layout(app), 'views')
                btn.Enable = 'on';
                btn.Tooltip = {['Fill in the pixel size of each view from a rig calibration of this recording: the ' ...
                    'one chosen in the Reconstruction tab (Calibration (gives mm)), else a new one made in the ' ...
                    'calibration window. You confirm the cube edge before anything is filled in.']};
            else
                btn.Enable = 'off';
                btn.Tooltip = {['A rig calibration gives the pixel size of the four views of the rabbit panoramic ' ...
                    'system: load such a recording and set its regions first.']};
            end
            [v, src] = rabbit_calibration_scale.views(app);
            four = strcmp(rabbit_calibration_scale.layout(app), 'views');
            for k = 1:4
                f = findall(g, 'Tag', sprintf('%sView%d', T, k));
                s = findall(g, 'Tag', sprintf('%sSource%d', T, k));
                nm = findall(g, 'Tag', sprintf('%sName%d', T, k));
                on = four || k == 1;
                f.Visible = rabbit_calibration_scale.on_off(on);
                s.Visible = f.Visible;
                nm.Visible = f.Visible;
                if four
                    nm.Text = rabbit_calibration_scale.VIEWS{k};
                else
                    nm.Text = 'Map';
                end
                f.Value = v(k);
                if four
                    f.Tooltip = {sprintf(['%s: %s per pixel of the map as it is binned now. View1 to View4 are the ' ...
                        'regions of the recording frame from left to right; on the map they may sit in another order. ' ...
                        'Change it with Input Scale or Measure length.'], rabbit_calibration_scale.VIEWS{k}, ...
                        rabbit_calibration_scale.um())};
                else
                    f.Tooltip = {sprintf(['%s per pixel, one value for the whole map (this data has no four views). ' ...
                        'Change it with Input Scale or Measure length.'], rabbit_calibration_scale.um())};
                end
                s.Text = src{k};
            end
            % The unit says which pixel, the
            % map's as it is binned now
            unit = findall(g, 'Tag', [T 'Unit']);
            if four
                unit.Text = sprintf('%s per binned pixel (binning %g)', rabbit_calibration_scale.um(), ...
                    rabbit_calibration_scale.binning_of(app));
            else
                unit.Text = sprintf('%s/pixel', rabbit_calibration_scale.um());
            end
            % All four from one calibration ->
            % one label with its full id and verdict; the four per-view
            % labels (text kept) are hidden while it shows
            all4 = findall(g, 'Tag', [T 'SourceAll']);
            all4.Text = rabbit_calibration_scale.one_source(app, src);
            all4.Visible = rabbit_calibration_scale.on_off(four && ~isempty(all4.Text));
            if strcmp(char(all4.Visible), 'on')
                for k = 1:4
                    set(findall(g, 'Tag', sprintf('%sSource%d', T, k)), 'Visible', 'off');
                end
            end
            [txt, tip] = rabbit_calibration_scale.texts(app);
            lbl = findall(g, 'Tag', [T 'Line']);
            lbl.Text = txt;
            lbl.Tooltip = tip;
        end

        function [txt, tip] = texts(app)
            %% The line beside the fields and its tooltip, in plain words
            r = rabbit_calibration_scale.record(app);
            [v, src] = rabbit_calibration_scale.views(app);
            if isempty(r) && all(v == 1)
                txt = sprintf('Pixel size not set: the maps use 1 %s/pixel until it is set.', rabbit_calibration_scale.um());
                tip = {'Set it with Scale from calibration..., Input Scale or Measure length.'};
                return;
            end
            if isempty(r) || isempty(r.calibration) || ~any(startsWith(src, 'calibration '))
                txt = 'Pixel size set by hand (Input Scale or Measure length).';
                tip = {'Scale from calibration... fills it in from a rig calibration instead.'};
                return;
            end
            s = r.calibration;
            % With a run selected in the
            % Reconstruction tab whose pixel_size.json comes from this
            % calibration, how much smaller (or larger) a pixel is on its
            % heart surface; else the plain "not the heart surface"
            [heart, heart_tip] = rabbit_calibration_scale.heart_clause(app, r, src);
            if isfield(s, 'surface_run') && ~isempty(s.surface_run)
                % The heart-surface sizes of a run
                depth_words = sprintf('On the heart surface of run %s.', s.surface_run);
            elseif isempty(heart)
                depth_words = 'At the cube''s depth, not the heart surface.';
            else
                depth_words = sprintf('At the cube''s depth; %s.', heart);
            end
            txt = sprintf('From calibration %s (%s). Cube edge %g mm (as typed). %s', s.calibration_id, s.status, ...
                s.edge_mm, depth_words);
            if ~isempty(rabbit_calibration_scale.one_source(app, src))
                % The id and verdict are in the
                % "All four from calibration" label; not repeated here
                txt = sprintf('Cube edge %g mm (as typed). %s', s.edge_mm, depth_words);
            end
            tip = {sprintf(['The size of a map pixel at the depth of the calibration cube''s middle, %s mm from ' ...
                'the cameras (View1 to View4). The heart surface lies at another depth, so a pixel there is another ' ...
                'size; a reconstruction run measures it on the heart surface (outputs\\metric\\pixel_size.json).'], ...
                strjoin(arrayfun(@(x) sprintf('%.0f', x), s.depth_mm, 'UniformOutput', false), '/')), ...
                sprintf('Binning %g and the frame scale %g against the reconstruction recording are included.', ...
                r.binning, s.fov_scale), ...
                sprintf('The cube edge, %g mm, was typed in the calibration window; every distance rests on it.', s.edge_mm)};
            if ~isempty(heart_tip), tip{end+1} = heart_tip; end   % the heart-surface line, when known
        end

        function [t, tip] = heart_clause(app, r, src)
            %% 'on this run's heart surface about N % smaller' and its tooltip line; '' when it cannot be said
            % The run is the one selected in the
            % Reconstruction tab; its outputs\metric\pixel_size.json must
            % name this calibration and give each view's tile. A pixel's
            % size is depth / focal length in both records, in
            % reconstruction pixels, so binning and the frame scale cancel
            % in the ratio heart / cube of each view.
            t = '';
            tip = '';
            try
                run_dir = app.recon.reconstruction_selected_run_dir();
            catch
                return;
            end
            if isempty(run_dir), return; end
            jf = fullfile(run_dir, 'outputs', 'metric', 'pixel_size.json');
            if exist(jf, 'file') ~= 2, return; end
            try
                p = rabbit_calibration.read_json(jf);
            catch
                return;
            end
            c = r.calibration;
            % Not this calibration's record: nothing to compare
            if ~isfield(p, 'calibration_id') || ~strcmp(char(p.calibration_id), c.calibration_id), return; end
            if ~isfield(p, 'views') || ~isstruct(p.views) || ~isfield(p.views, 'tile') || ...
                    ~isfield(p.views, 'median_mm_per_px') || ~isfield(c, 'mm_cube_views'), return; end
            % The record's OM pixel must be the CV tab's (both at frame scale 1, or both not)
            if isfield(p, 'om_pixel_same_size') && islogical(p.om_pixel_same_size) && isscalar(p.om_pixel_same_size) ...
                    && isfield(c, 'fov_scale') && p.om_pixel_same_size ~= (abs(c.fov_scale - 1) < 1e-9), return; end
            pc = nan(1, 4);   % heart / cube - 1 of View1..View4, in per cent
            for k = 1:4
                % Only the views whose size on the CV tab came from this calibration
                if ~strcmp(src{k}, ['calibration ' c.calibration_id]), continue; end
                hit = strcmp({p.views.tile}, rabbit_calibration.TILES{k});
                if nnz(hit) ~= 1, return; end   % a view missing or twice: the record does not match
                h = double(p.views(hit).median_mm_per_px);
                if ~(isscalar(h) && isfinite(h) && h > 0), return; end
                pc(k) = 100 * (h / double(c.mm_cube_views(k)) - 1);
            end
            have = isfinite(pc);
            if ~any(have), return; end
            x = pc(have);
            names = rabbit_calibration_scale.VIEWS(have);
            % each view signed, with a true minus sign
            per = strjoin(arrayfun(@(n, q) sprintf('%s %s %%', n{1}, rabbit_reconstruction_tab.signed_text(q, 1)), ...
                names, x, 'UniformOutput', false), ', ');
            % One decimal; a range when the views differ
            a = abs(x);
            if all(round(a, 1) == round(a(1), 1))
                amount = sprintf('%.1f %%', a(1));
            else
                amount = sprintf('%.1f%s%.1f %%', min(a), char(8211), max(a));
            end
            [~, run_id] = fileparts(run_dir);
            if all(round(x, 1) == 0)
                t = 'on this run''s heart surface about the same size (within 0.05 %)';
            elseif all(x < 0)
                t = sprintf('on this run''s heart surface about %s smaller', amount);
            elseif all(x > 0)
                t = sprintf('on this run''s heart surface about %s larger', amount);
            else
                t = sprintf('on this run''s heart surface %s', per);   % some smaller, some larger: each view
            end
            tip = sprintf(['Heart surface against the cube, median pixel size per view of run %s ' ...
                '(outputs\\metric\\pixel_size.json, same calibration): %s. Negative: smaller on the heart, which ' ...
                'then lies nearer the cameras than the cube''s middle (size = depth / focal length).'], run_id, per);
        end

        function t = one_source(app, src)
            %% 'All four from calibration <id> (<verdict>)' when the four views all came from it; else ''
            t = '';
            r = rabbit_calibration_scale.record(app);
            if isempty(r) || ~isfield(r, 'calibration') || isempty(r.calibration), return; end
            id = r.calibration.calibration_id;
            if numel(src) == 4 && all(strcmp(src, ['calibration ' id]))
                t = sprintf('All four from calibration %s (%s)', id, r.calibration.status);
            elseif isfield(r.calibration, 'surface_run') && ~isempty(r.calibration.surface_run) && numel(src) == 4 && ...
                    all(strcmp(src, sprintf('calibration %s, heart surface of run %s', id, r.calibration.surface_run)))
                % the heart-surface sizes of a run
                t = sprintf('All four from calibration %s (%s), heart surface of run %s', id, r.calibration.status, ...
                    r.calibration.surface_run);
            end
        end

        function button_pushed(app)
            %% Scale from calibration...: the chosen calibration, else a new one
            fig = app.opticalmappingUIFigure;
            if ~rabbit_calibration_scale.bound(app)
                uialert(fig, 'Load a recording first (File > Load file).', rabbit_calibration_scale.TITLE);
                return;
            end
            id = app.recon.ReconstructionCalibrationDropDown.Value;
            if ~isempty(id)
                rabbit_calibration_scale.fill(app, fullfile(app.recon.reconstruction_calibration_root(), id), fig);
                return;
            end
            why = rabbit_calibration_scale.window_ready(app);
            if ~isempty(why)
                uialert(fig, ['No calibration is chosen in the Reconstruction tab, and a new one cannot be made ' ...
                    'yet: ' why], rabbit_calibration_scale.TITLE);
                return;
            end
            rabbit_calibration_scale.open_window(app);
        end

        % ---- The state ----

        function [v, src] = views(app)
            %% The four views' sizes now (um per pixel of the map) and where each came from
            v = [];
            if strcmp(rabbit_calibration_scale.layout(app), 'views') && isfield(app.processed_data, 'scale_views')
                v = double(app.processed_data.scale_views);
            end
            if ~(isnumeric(v) && numel(v) == 4 && all(isfinite(v)) && all(v > 0))
                % An older workspace, or nothing set yet: the single scale for all four
                s = app.processed_data.scale;
                if ~(isnumeric(s) && isscalar(s) && isfinite(s) && s > 0), s = 1; end
                v = repmat(double(s), 1, 4);
            end
            v = reshape(v, 1, 4);
            src = repmat({'not set'}, 1, 4);
            r = rabbit_calibration_scale.record(app);
            if ~isempty(r)
                src = r.view_sources;
            elseif isfield(app.data, 'scale_single_source') && ~isempty(app.data.scale_single_source)
                src = repmat({app.data.scale_single_source}, 1, 4);
            elseif any(v ~= 1)
                src = repmat({'one scale'}, 1, 4);
            end
        end

        function r = record(app)
            %% app.data.calibration_scale when it still describes the sizes in use; else []
            r = [];
            if ~strcmp(rabbit_calibration_scale.layout(app), 'views'), return; end
            if ~isfield(app.data, 'calibration_scale'), return; end
            c = app.data.calibration_scale;
            if ~isstruct(c) || ~isfield(c, 'schema') || ~strcmp(c.schema, rabbit_calibration_scale.SCHEMA), return; end
            if ~isfield(app.processed_data, 'scale_views'), return; end
            now_v = double(app.processed_data.scale_views);
            want = c.base_um_views * c.binning;
            % Set another way since (a workspace loaded, say): not this record's any more
            if numel(now_v) ~= 4 || any(abs(now_v(:)' - want) > 1e-9 * want), return; end
            r = c;
        end

        function apply(app, base_um_views, sources, cal)
            %% Set the four views' sizes at binning 1 and where each came from
            b = rabbit_calibration_scale.binning_of(app);
            r = rabbit_calibration_scale.record(app);
            if isempty(r)
                r = struct('schema', rabbit_calibration_scale.SCHEMA, 'base_um_views', base_um_views, ...
                    'binning', b, 'view_sources', {sources}, 'calibration', []);
            end
            r.base_um_views = reshape(double(base_um_views), 1, 4);
            r.binning = b;
            r.view_sources = sources;
            if ~isempty(cal)
                r.calibration = cal;
            elseif ~any(startsWith(sources, 'calibration '))
                r.calibration = [];   % no view uses the calibration any more
            end
            app.data.calibration_scale = r;
            app.data.scale_layout = 'views';
            app.data.scale_single_source = '';
            rabbit_calibration_scale.set_processed(app, r.base_um_views * b);
            rabbit_calibration_scale.show(app);
        end

        function set_single(app, um_per_px, how)
            %% Single-view data: one value for the whole map (not changed by binning)
            app.processed_data.scale = um_per_px;
            if isfield(app.processed_data, 'scale_views')
                app.processed_data = rmfield(app.processed_data, 'scale_views');
            end
            app.data.calibration_scale = [];
            app.data.scale_layout = 'single';
            app.data.scale_single_source = char(how);
            rabbit_calibration_scale.show(app);
        end

        function x = single_value(app)
            x = app.processed_data.scale;
            if ~(isnumeric(x) && isscalar(x) && isfinite(x) && x > 0), x = 1; end
        end

        function L = layout(app)
            %% 'views' for data with the rabbit panoramic regions applied, else 'single'
            L = 'single';
            try
                if isfield(app.data, 'rabbit_panoramic') && isequal(double(app.data.rabbit_panoramic), 1) && ...
                        isfield(app.data, 'regions') && app.data.regions == 4 && ...
                        isfield(app.processed_data, 'region_widths') && numel(app.processed_data.region_widths) == 4 && ...
                        isfield(app.data, 'region_bounds') && size(app.data.region_bounds, 1) == 4
                    L = 'views';
                end
            catch
                L = 'single';
            end
        end

        function go = regions_changed(app)
            %% After regions are applied: sizes set for the other layout are cleared, and the user is told
            % go is false when something was cleared.
            go = true;
            now_L = rabbit_calibration_scale.layout(app);
            old = '';
            if isfield(app.data, 'scale_layout'), old = char(app.data.scale_layout); end
            if isempty(old) || strcmp(old, now_L)
                rabbit_calibration_scale.show(app);   % one field or four, for the regions now
                return;
            end
            names = struct('single', 'one value for the whole map', 'views', 'the four views View1 to View4');
            app.processed_data.scale = 1;
            if isfield(app.processed_data, 'scale_views')
                app.processed_data = rmfield(app.processed_data, 'scale_views');
            end
            app.data.calibration_scale = [];
            app.data.scale_single_source = '';
            app.data.scale_layout = '';
            msg = sprintf(['The regions now make %s, but the pixel size was set as %s. It was cleared ' ...
                '(1 %s/pixel, not set) so that it is not carried over the wrong way: set it again with Input ' ...
                'Scale, Measure length or Scale from calibration...'], names.(now_L), names.(old), ...
                rabbit_calibration_scale.um());
            uialert(app.opticalmappingUIFigure, msg, 'Pixel size cleared');
            rabbit_calibration_scale.history(app, ['Pixel size cleared: ' msg]);
            rabbit_calibration_scale.show(app);
            go = false;
        end

        function t = on_off(tf)
            if tf, t = 'on'; else, t = 'off'; end
        end

        function set_processed(app, um_views)
            %% processed_data.scale_views, and processed_data.scale: one value when all four are equal, else NaN
            app.processed_data.scale_views = um_views;
            if all(abs(um_views - um_views(1)) <= 1e-12 * um_views(1))
                app.processed_data.scale = um_views(1);
            else
                app.processed_data.scale = NaN;   % no single value: the CV map uses scale_views
            end
        end

        % ---- Small helpers ----

        function tf = bound(app)
            %% A recording is loaded and the Reconstruction tab has its dataset
            try
                tf = isprop(app, 'recon') && ~isempty(app.recon) && app.recon.reconstruction_has_dataset();
            catch
                tf = false;
            end
        end

        function b = binning_of(app)
            b = 1;
            if isfield(app.processed_data, 'binning') && isnumeric(app.processed_data.binning) && ...
                    isscalar(app.processed_data.binning) && app.processed_data.binning > 0
                b = double(app.processed_data.binning);
            end
        end

        function st = status_of(cal_dir)
            st = 'no verdict';
            try
                v = rabbit_calibration.read_json(fullfile(cal_dir, 'verdict.json'));
                st = char(v.status);
            catch
            end
        end

        function x = stamp(cal_dir)
            %% Size and time of calibration.json, to see a changed result
            x = [];
            d = dir(fullfile(cal_dir, 'calibration.json'));
            if ~isempty(d), x = [d(1).bytes, d(1).datenum]; end
        end

        function t = view_list(values, which)
            %% 'View1 125.4, View2 129.8, ...' (which: the views the values are for; default all four)
            if nargin < 2, which = 1:numel(values); end
            names = rabbit_calibration_scale.VIEWS(which);
            t = strjoin(cellfun(@(n, x) sprintf('%s %s', n, num2str(x, 4)), names(:)', num2cell(values(:)'), ...
                'UniformOutput', false), ', ');
        end

        function t = history_scale(app)
            %% The pixel sizes a CV map was made with, and where each came from, for its History line
            [v, src] = rabbit_calibration_scale.views(app);
            um = rabbit_calibration_scale.um();
            if ~strcmp(rabbit_calibration_scale.layout(app), 'views')
                t = sprintf('Scale: %s %s/pixel (%s).', num2str(v(1), 4), um, src{1});
                return;
            end
            % One source named once, "Pixel size
            % (um/pixel, calibration <id>): View1 250.9, View2 259.6, ..."
            if all(strcmp(src, src{1}))
                t = sprintf('Pixel size (%s/pixel, %s): %s.', um, src{1}, rabbit_calibration_scale.view_list(v));
                return;
            end
            parts = arrayfun(@(k) sprintf('%s %s (%s)', rabbit_calibration_scale.VIEWS{k}, num2str(v(k), 4), src{k}), ...
                1:4, 'UniformOutput', false);
            t = sprintf('Pixel size (%s/pixel): %s.', um, strjoin(parts, ', '));
        end

        function t = um()
            t = [char(956) 'm'];   % micrometre, as the Conduction Velocity tab writes it
        end

        function history(app, line)
            try
                app.history_field.Value{length(app.history_field.Value) + 1, 1} = line;
            catch
                % a test double without a History tab
            end
        end
    end
end
