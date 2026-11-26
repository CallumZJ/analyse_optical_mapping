classdef rabbit_cut_tiffs
    %% Cut TIFF copies of the rabbit datasets by region
    % Collin Snitchler
    % 03.09.2026
    % After the regions are selected (rabbit mode, end of define_regions),
    % prompt_cut asks whether to write TIFF copies, and cut_inline cuts the
    % optical-mapping images, the calibration images (if loaded) and the
    % reconstruction images (if a path was set) with the same ROI geometry.
    % cut_from_roi re-cuts any dataset later from a saved ROI JSON.
    % Inputs:
    %   app: the analyse_optical_mapping app
    %   bounds: region_bounds_src, Nx4 [row1 col1 row2 col2] in unmirrored
    %       source pixels, 1-based, inclusive; rows [View2; View3; View1; View4]
    % Outputs:
    %   TIFFs in <folder>/cut_tiffs_<dataset>_<source_stem>/ (numbered _01,
    %   _02 ... when that name is taken), <folder> chosen by the user when
    %   cutting (default: the optical-mapping folder),
    %   named <stem>_view<k>_frame_%04d.tiff (multi-frame source) or
    %   <frame_stem>_view<k>.tiff (folder of 2-D TIFFs), plus manifest.json
    %   listing each output with its source, frame, view, bounds and
    %   bit-depth policy. Methods return logical success flags; errors are
    %   shown with uialert.
    % An existing folder is never written to or replaced: the cut goes into
    % the next free name. The folders of one cut share their number, and
    % app.data.cut_folders_made records the folders made, so that later steps
    % use those and not a guessed name. Files from a failed attempt are
    % deleted.
    % Bit depth: uint8 and uint16 crops are written unchanged; other classes
    % are min-max normalised to [0,1] and written as uint8 (imwrite rejects
    % single TIFF data and auto-scales double). NaN/Inf become 0.
    % Optical-mapping crops that are whole numbers in the uint16 range
    % (FITS camera counts, which fitsread returns as double) are written as
    % uint16, not normalised frame by frame, which would lose the intensity
    % changes between frames. The reconstruction copies keep their camera
    % counts the same way: the "Build sparse model" step stretches each view
    % over all its frames (rabbit_sfm_build), which needs the counts; a
    % per-frame min-max normalisation could not be undone.
    % A repeat cut is allowed; it goes into the next free number (above).
    %
    % Section map (search for the quoted line; line numbers move)
    %   The question ........... "function answer = prompt_cut"
    %   Cut now ................ "function ok = cut_inline"
    %   Progress ............... "function progress_open"
    %   Per dataset ............ "function ok = cut_om"
    %   Re-cut from a ROI file . "function [ok, out_root] = cut_from_roi"
    %   Writing the cut ........ "function [ok, out_root] = cut_stack"
    %   Finding a cut .......... "function cut_dir = find_cut_folder"
    %   Files and manifest ..... "function write_crop"
    %   Output folder .......... "function ok = choose_output_folder"

    methods (Static)

        function answer = prompt_cut(app, has_calibration, has_reconstruction)
            %% Ask whether to create TIFF copies now
            % Returns 'Yes' or 'No'. Without an optical-mapping source
            % there is nothing to cut, so the prompt is skipped ('No').
            if ~isfield(app.data, 'rabbit_panoramic') || app.data.rabbit_panoramic ~= 1
                answer = 'No';
                return;
            end
            if isempty(app.file_info.file)
                answer = 'No';
                return;
            end
            if nargin < 3
                has_reconstruction = false;
            end
            parts = {'the optical-mapping heart images'};
            if has_calibration
                parts{end+1} = 'the calibration images'; %#ok<AGROW>
            end
            if has_reconstruction
                parts{end+1} = 'the reconstruction images'; %#ok<AGROW>
            end
            msg = ['Create TIFF copies of ' strjoin(parts, ' and ') ...
                ', cut according to the regions?'];
            % In front of the other windows, Yes by default: the next steps
            % need the copies
            try
                % only a window on show is raised: raising a hidden one
                % (scripts, tests) would show it
                if strcmp(char(app.opticalmappingUIFigure.Visible), 'on'), figure(app.opticalmappingUIFigure); end
            catch
                % a test double without a window
            end
            answer = uiconfirm(app.opticalmappingUIFigure, msg, 'Cut TIFF copies', ...
                'Options', {'Yes', 'No'}, 'DefaultOption', 1, 'CancelOption', 2);
            if ~strcmp(answer, 'Yes')
                answer = 'No';
            end
        end

        function ok = cut_inline(app)
            %% Cut all loaded datasets with the current ROIs
            % Cuts the optical-mapping images, the calibration images (if
            % loaded) and the reconstruction images (if a path was set).
            % Asks first for the folder to write into; each dataset goes
            % into its own cut_tiffs_* folder there, all with the same
            % number if the names are taken, and the user is told which
            % folders were made. One failure does not stop the others.
            % Returns true only if every cut succeeded; false with nothing
            % written if no folder was chosen.
            [bounds, src_dims] = rabbit_cut_tiffs.current_bounds(app);
            if isempty(bounds)
                ok = true;
                return;   % no regions - nothing to cut
            end
            if ~rabbit_cut_tiffs.choose_output_folder(app)
                ok = false;
                return;   % cancelled - nothing written
            end
            % The folders of this cut replace those of any earlier cut
            app.data.cut_folders_made = struct();
            app.data.cut_roi_json = '';
            app.data.cut_output_suffix = rabbit_stack_io.next_free_suffix( ...
                app.data.cut_output_root, rabbit_cut_tiffs.cut_folder_names(app));
            has_cal = isfield(app.data, 'calibration_source') ...
                && ~isempty(app.data.calibration_source);
            has_rec = isfield(app.data, 'reconstruction_path') ...
                && ~isempty(app.data.reconstruction_path);
            % One progress dialog for the whole cut, on the app's window,
            % so the app cannot be clicked until the cut is done; it closes
            % on success, on Cancel and on errors
            rabbit_cut_tiffs.progress_open(app, 1 + has_cal + has_rec);
            closer = onCleanup(@() rabbit_cut_tiffs.progress_close(app)); %#ok<NASGU>
            ok = rabbit_cut_tiffs.cut_om(app, bounds, src_dims);
            rabbit_cut_tiffs.progress_next(app);
            if has_cal && ~rabbit_cut_tiffs.progress_cancelled(app)
                ok_cal = rabbit_cut_tiffs.cut_calibration(app, bounds, src_dims);
                ok = ok && ok_cal;
                rabbit_cut_tiffs.progress_next(app);
            end
            if has_rec && ~rabbit_cut_tiffs.progress_cancelled(app)
                ok_rec = rabbit_cut_tiffs.cut_reconstruction(app, bounds, src_dims);
                ok = ok && ok_rec;
                rabbit_cut_tiffs.progress_next(app);
            end
            app.data.cut_output_suffix = '';
            cancelled = rabbit_cut_tiffs.progress_cancelled(app);
            if ~cancelled
                % The regions file of this cut, for the Reconstruction tab
                % (filled in after the cut, not chosen)
                rabbit_cut_tiffs.progress(app, 'Writing the regions file...', []);
                app.data.cut_roi_json = rabbit_cut_tiffs.write_roi_file(app, src_dims);
            end
            rabbit_cut_tiffs.progress_close(app);   % the alerts come after the dialog
            if cancelled
                ok = false;
                made = rabbit_cut_tiffs.made_folders(app);
                msg = 'The cut was cancelled. The folder being written was removed.';
                if ~isempty(made)
                    msg = sprintf('%s These were finished before Cancel and are kept:\n%s', msg, strjoin(made, newline));
                end
                rabbit_cut_tiffs.alert(app, msg);
                return;
            end
            rabbit_cut_tiffs.report_folders(app);
        end

        function progress_open(app, n_phases)
            %% The cut's progress dialog (headless: the stand-in records it)
            app.data.cut_progress = struct('dlg', [], 'phase', 0, 'n_phases', max(1, n_phases), 'cancelled', false);
            if isprop(app, 'opticalmappingUIFigure') && ~isempty(app.opticalmappingUIFigure) && ...
                    isvalid(app.opticalmappingUIFigure)
                app.data.cut_progress.dlg = uiprogressdlg(app.opticalmappingUIFigure, 'Title', 'Cutting TIFF copies', ...
                    'Message', 'Starting the cut...', 'Value', 0, 'Cancelable', 'on', 'CancelText', 'Cancel');
            end
        end

        function progress(app, msg, frac)
            %% Message and how far the current phase is (0-1, [] = keep the bar)
            if ~isfield(app.data, 'cut_progress'), return; end
            P = app.data.cut_progress;
            d = P.dlg;
            if isempty(d) || ~isvalid(d), return; end
            d.Message = msg;
            if ~isempty(frac)
                d.Value = min(1, (P.phase + min(max(frac, 0), 1)) / P.n_phases);
            end
            drawnow limitrate;   % shows the dialog and takes a Cancel click
        end

        function progress_next(app)
            %% The next dataset of the cut
            if isfield(app.data, 'cut_progress')
                app.data.cut_progress.phase = app.data.cut_progress.phase + 1;
            end
        end

        function tf = progress_cancelled(app)
            %% Cancel was pressed in the cut's dialog
            tf = false;
            if ~isfield(app.data, 'cut_progress'), return; end
            P = app.data.cut_progress;
            tf = P.cancelled || (~isempty(P.dlg) && isvalid(P.dlg) && P.dlg.CancelRequested);
            app.data.cut_progress.cancelled = tf;
        end

        function progress_close(app)
            %% Close the cut's dialog (safe to call twice)
            if ~isfield(app.data, 'cut_progress'), return; end
            d = app.data.cut_progress.dlg;
            if ~isempty(d) && isvalid(d), close(d); end
            app.data.cut_progress.dlg = [];
        end

        function made = made_folders(app)
            %% The folders this cut finished
            made = {};
            if isfield(app.data, 'cut_folders_made')
                fields = fieldnames(app.data.cut_folders_made);
                for k = 1:numel(fields)
                    made{end+1} = app.data.cut_folders_made.(fields{k}).path; %#ok<AGROW>
                end
            end
        end

        function path = write_roi_file(app, src_dims)
            %% The regions as an ROI file next to the cut folders ('' if not written)
            % The same content as the ROI editor's Save ROI JSON: the
            % unmirrored source bounds, the source size, the reconstruction
            % path and the region dialog's line-ups. Named
            % regions_<recording>.json, the next free name, so an earlier
            % cut's file is never replaced.
            path = '';
            try
                d = app.data;
                payload = struct();
                payload.schema_version = 1;
                payload.region_bounds_src = double(d.region_bounds_src);
                payload.regions = 4;
                payload.rotation = 3;
                if isfield(d, 'rotation') && ~isempty(d.rotation), payload.rotation = d.rotation; end
                payload.rabbit_panoramic = true;
                if isfield(d, 'rabbit_panoramic') && ~isempty(d.rabbit_panoramic)
                    payload.rabbit_panoramic = (d.rabbit_panoramic == 1);
                end
                payload.source_dims = struct('height', src_dims(1), 'width', src_dims(2));
                payload.coordinate_origin = 'top-left';
                payload.unmirrored_coordinates = true;
                payload.reconstruction_path = '';
                if isfield(d, 'reconstruction_path'), payload.reconstruction_path = char(d.reconstruction_path); end
                payload.fov_mapping = [];
                if isfield(d, 'reconstruction_fov_mapping') && ~isempty(d.reconstruction_fov_mapping)
                    payload.fov_mapping = d.reconstruction_fov_mapping;
                end
                payload.calibration_fov_mapping = [];
                if isfield(d, 'calibration_fov_mapping') && ~isempty(d.calibration_fov_mapping)
                    payload.calibration_fov_mapping = d.calibration_fov_mapping;
                end
                payload.calibration_path = '';
                if ~isempty(payload.calibration_fov_mapping) && isfield(d, 'calibration_source')
                    payload.calibration_path = char(d.calibration_source);
                end
                % the calibration cut folder (view1..view4), which the
                % calibration window lists; calibration_path stays the
                % recording, which a re-cut and the line-ups refer to
                payload.calibration_cut_folder = '';
                if isfield(d, 'cut_folders_made') && isfield(d.cut_folders_made, 'calibration')
                    payload.calibration_cut_folder = d.cut_folders_made.calibration.path;
                end
                payload.view_order = {'view2', 'view3', 'view1', 'view4'};
                [~, stem] = fileparts(char(app.file_info.name));
                if isempty(stem), stem = 'recording'; end
                path = rabbit_stack_io.next_free_path(fullfile(d.cut_output_root, ['regions_' stem]), '.json');
                rabbit_stack_io.save_roi_json(path, payload);
            catch ME
                path = '';
                rabbit_cut_tiffs.alert(app, sprintf(['The regions file for the Reconstruction tab could not be ' ...
                    'written: %s Save it from the region editor (Save ROI JSON...) instead.'], ME.message));
            end
        end

        function ok = cut_om(app, bounds, src_dims)
            %% Cut the in-memory optical-mapping images
            % Uses the same array the ROIs were drawn on, so the geometry
            % matches for every source format without re-reading.
            stk = app.data.image_stack;
            if isempty(stk)
                rabbit_cut_tiffs.alert(app, ...
                    'The optical-mapping images are not loaded; nothing to cut.');
                ok = false;
                return;
            end
            [H, W, n] = rabbit_cut_tiffs.stack_planes(stk);
            [~, stem] = fileparts(app.file_info.file);
            if isempty(stem)
                [~, stem] = fileparts(app.file_info.name);
            end
            ok = rabbit_cut_tiffs.cut_stack(app, 'om', stk, H, W, n, ...
                stem, fullfile(app.file_info.path, app.file_info.file), ...
                bounds, src_dims);
        end

        function ok = cut_calibration(app, bounds, src_dims)
            %% Re-load the calibration images and cut them
            % Loads FITS/TIFF through rabbit_stack_io and cuts with the
            % same ROI geometry. The load dialogs already check the size,
            % so the size check here is a backstop. A larger calibration
            % frame is allowed only when a stationary-camera FOV mapping
            % was recorded at import (app.data.calibration_fov_mapping);
            % the bounds are then mapped into that frame. Otherwise the cut
            % is refused rather than resized.
            src = app.data.calibration_source;
            rabbit_cut_tiffs.progress(app, 'Reading the calibration images...', 0);
            try
                stk = rabbit_stack_io.load_stack_native(src);
            catch ME
                rabbit_cut_tiffs.alert(app, ...
                    sprintf('Could not load the calibration images for cutting: %s', ...
                    ME.message));
                ok = false;
                return;
            end
            H = app.data.height;
            W = app.data.width;
            if isempty(H), H = size(app.data.calibration_mip, 1); end
            if isempty(W), W = size(app.data.calibration_mip, 2); end
            if isempty(H) || isempty(W)
                [H, W, ~] = rabbit_cut_tiffs.stack_planes(stk.stack);
            end
            % A recorded mapping is applied whatever the frame sizes:
            % frames of the same size may show another part of the
            % sensor, and the load dialog records a mapping only then
            fov = [];
            if isfield(app.data, 'calibration_fov_mapping')
                fov = app.data.calibration_fov_mapping;
            end
            if ~isempty(fov) && isstruct(fov)
                bounds = rabbit_stack_io.map_bounds_across_fov(bounds, fov);
            elseif stk.height ~= H || stk.width ~= W
                rabbit_cut_tiffs.alert(app, ...
                    sprintf(['The calibration images are %dx%d but the ROIs were defined on ' ...
                    '%dx%d images. The FOVs differ and no stationary-camera FOV mapping ' ...
                    'was recorded at import; refusing to cut with mismatched geometry.'], ...
                    stk.height, stk.width, H, W));
                ok = false;
                return;
            end
            [~, stem] = fileparts(src);
            [ok, out_root] = rabbit_cut_tiffs.cut_stack(app, 'calibration', stk.stack, ...
                stk.height, stk.width, stk.n_frames, stem, src, bounds, src_dims, ...
                [], '', fov);
            if ok
                % Where each view sits in the reconstruction frame, for the
                % calibration (rabbit_calibration.write_tiles_from_cut)
                try
                    rabbit_cut_tiffs.write_cut_locations(app, out_root, src_dims);
                catch ME
                    rabbit_cut_tiffs.alert(app, sprintf(['The calibration copies are in %s, but where each view ' ...
                        'sits could not be written (%s). Add the recording itself in the calibration window.'], ...
                        out_root, ME.message));
                end
            end
        end

        function write_cut_locations(app, out_root, src_dims)
            %% cut_locations_per_view.json of a calibration cut folder
            % The views are named by their place in the frame, as
            % rabbit_calibration.write_tiles_from_cut reads
            % them: view1 the leftmost region of the (unmirrored) frame,
            % view4 the rightmost; the regions file's rows are another
            % order (view2;view3;view1;view4). The margins are those of the
            % same region in the reconstruction frame, so the calibration
            % tiles land where the reconstruction's do: the region dialog's
            % line-ups are applied here, once (top, bottom: rows above and
            % below; left, right: columns, counted from the left of the
            % flipped frame for view1 and view4, whose crops are flipped).
            rb = double(app.data.region_bounds_src);
            hw = src_dims;
            if isfield(app.data, 'reconstruction_fov_mapping') && ~isempty(app.data.reconstruction_fov_mapping) && ...
                    isstruct(app.data.reconstruction_fov_mapping)
                rb = rabbit_stack_io.map_bounds_across_fov(rb, app.data.reconstruction_fov_mapping);
            end
            if isfield(app.data, 'reconstruction_path') && ~isempty(app.data.reconstruction_path)
                hw = rabbit_calibration.recording_size(app.data.reconstruction_path);
            end
            H = hw(1); W = hw(2);
            [~, order] = sort(rb(:, 2));   % left to right
            cuts = struct('view', {}, 'top', {}, 'bottom', {}, 'left', {}, 'right', {}, 'roi_row', {}, 'placed', {});
            for p = 1:4
                k = order(p);
                if any(p == [1 4])
                    l = W - rb(k, 4); r = rb(k, 2) - 1;
                else
                    l = rb(k, 2) - 1; r = W - rb(k, 4);
                end
                cuts(p) = struct('view', sprintf('view%d', p), 'top', rb(k, 1) - 1, 'bottom', H - rb(k, 3), ...
                    'left', l, 'right', r, 'roi_row', k, ...
                    'placed', 'in the reconstruction frame from the region dialog''s line-up');
            end
            rabbit_sfm_build.write_text(fullfile(out_root, 'cut_locations_per_view.json'), jsonencode(cuts, 'PrettyPrint', true));
        end

        function ok = cut_reconstruction(app, bounds, src_dims)
            %% Re-load the reconstruction images and cut them
            % app.data.reconstruction_path is a folder of 2-D TIFFs, a
            % multi-page TIFF or a FITS file. Same size checks as the
            % calibration cut. A larger frame is allowed only when a
            % stationary-camera FOV mapping was recorded at import
            % (app.data.reconstruction_fov_mapping, the vertical crop);
            % otherwise the cut is refused rather than resized.
            src = app.data.reconstruction_path;
            rabbit_cut_tiffs.progress(app, 'Reading the reconstruction images...', 0);
            try
                stk = rabbit_stack_io.load_stack_native(src);
            catch ME
                rabbit_cut_tiffs.alert(app, ...
                    sprintf('Could not load the reconstruction images for cutting: %s', ...
                    ME.message));
                ok = false;
                return;
            end
            H = app.data.height;
            W = app.data.width;
            if isempty(H), H = size(app.data.calibration_mip, 1); end
            if isempty(W), W = size(app.data.calibration_mip, 2); end
            if isempty(H), H = size(app.data.reconstruction_mip, 1); end
            if isempty(W), W = size(app.data.reconstruction_mip, 2); end
            if isempty(H) || isempty(W)
                [H, W, ~] = rabbit_cut_tiffs.stack_planes(stk.stack);
            end
            % A recorded mapping is applied whatever the frame sizes:
            % frames of the same size may show another part of the
            % sensor, and the load dialog records a mapping only then
            fov = [];
            if isfield(app.data, 'reconstruction_fov_mapping')
                fov = app.data.reconstruction_fov_mapping;
            end
            if ~isempty(fov) && isstruct(fov)
                bounds = rabbit_stack_io.map_bounds_across_fov(bounds, fov);
            elseif stk.height ~= H || stk.width ~= W
                rabbit_cut_tiffs.alert(app, ...
                    sprintf(['The reconstruction images are %dx%d but the ROIs were defined on ' ...
                    '%dx%d images. The FOVs differ and no stationary-camera FOV mapping ' ...
                    'was recorded at import; refusing to cut with mismatched geometry.'], ...
                    stk.height, stk.width, H, W));
                ok = false;
                return;
            end
            if isfolder(src)
                stem = rabbit_cut_tiffs.source_stem(src);
            else
                [~, stem] = fileparts(src);
            end
            ok = rabbit_cut_tiffs.cut_stack(app, 'reconstruction', stk.stack, ...
                stk.height, stk.width, stk.n_frames, stem, src, bounds, src_dims, ...
                [], '', fov);
        end

        function [ok, out_root] = cut_from_roi(app, json_path, dataset, varargin)
            %% Re-cut a dataset from a saved ROI JSON
            % The JSON's region_bounds_src is used as saved (a legacy
            % cut list is converted with the current image size).
            % The dataset must have the JSON's source_dims, or a saved FOV
            % mapping; a mismatch is refused rather than resampled, so
            % every dataset gets the same crop per view.
            % Inputs:
            %   app: app handle (a test double with app.data and
            %       file_info works headless)
            %   json_path: saved ROI JSON (v1 or legacy, see
            %       rabbit_stack_io.load_roi_json)
            %   dataset: 'om' (app.data.image_stack), 'calibration'
            %       (app.data.calibration_source) or 'reconstruction'
            %       (app.data.reconstruction_path)
            %   'OutputRoot': output folder override (tests only)
            %   'Writer': write function override (tests only)
            % Outputs:
            %   ok: true when the dataset was cut into a new folder
            %   out_root: the folder made (the next free name if the usual
            %       one is taken); empty when nothing was cut
            p = inputParser;
            p.addRequired('app');
            p.addRequired('json_path', @(x) ischar(x) || isstring(x));
            p.addRequired('dataset', @(x) ischar(x) || isstring(x));
            p.addParameter('OutputRoot', '', @(x) ischar(x) || isstring(x));
            p.addParameter('Writer', [], @(x) isa(x, 'function_handle'));
            p.KeepUnmatched = false;
            p.parse(app, json_path, dataset, varargin{:});
            out_root = '';
            dataset = lower(char(p.Results.dataset));
            valid = {'om', 'calibration', 'reconstruction'};
            if ~any(strcmp(dataset, valid))
                error('analyse_om:CutTiffs:BadDataset', ...
                    'Unknown dataset ''%s'' (expected om, calibration or reconstruction).', dataset);
            end
            H = p.Results.app.data.height;
            W = p.Results.app.data.width;
            if isempty(H), H = 0; end
            if isempty(W), W = 0; end
            roi = rabbit_stack_io.load_roi_json(p.Results.json_path, H, W);
            bounds = double(roi.region_bounds_src);
            if isempty(bounds)
                rabbit_cut_tiffs.alert(p.Results.app, ...
                    'The saved ROI JSON contains no region bounds; nothing to cut.');
                ok = false;
                return;
            end
            src_dims = [double(roi.source_dims.height) double(roi.source_dims.width)];
            [stk, stem, source_path] = rabbit_cut_tiffs.dataset_stack( ...
                p.Results.app, dataset);
            if isempty(stk)
                ok = false;
                return;
            end
            % The mapping of this dataset (the calibration has its own,
            % calibration_fov_mapping, not the reconstruction's), applied
            % whenever one is saved: frames of
            % the same size may show another part of the sensor
            fov = [];
            if strcmp(dataset, 'reconstruction') && isfield(roi, 'fov_mapping') && ~isempty(roi.fov_mapping)
                fov = roi.fov_mapping;
            elseif strcmp(dataset, 'calibration') && isfield(roi, 'calibration_fov_mapping') && ...
                    ~isempty(roi.calibration_fov_mapping)
                % Only for the calibration recording it was found for; a
                % file saved before it named one keeps the earlier rule
                % (a same-size calibration is cut unshifted)
                named = '';
                if isfield(roi, 'calibration_path'), named = roi.calibration_path; end
                if ~isempty(named) && rabbit_stack_io.same_file(named, source_path)
                    fov = roi.calibration_fov_mapping;
                elseif stk.height ~= src_dims(1) || stk.width ~= src_dims(2)
                    rabbit_cut_tiffs.alert(p.Results.app, ...
                        sprintf(['The calibration images are %dx%d and the ROIs were drawn on %dx%d images, but the ' ...
                        'saved JSON''s calibration position is not for this recording (%s). Load the calibration ' ...
                        'stack under Define regions so that its position is set, then save the ROI JSON again.'], ...
                        stk.height, stk.width, src_dims(1), src_dims(2), char(source_path)));
                    ok = false;
                    return;
                end
            end
            if ~isempty(fov) && isstruct(fov)
                bounds = rabbit_stack_io.map_bounds_across_fov(bounds, fov);
            elseif stk.height ~= src_dims(1) || stk.width ~= src_dims(2)
                rabbit_cut_tiffs.alert(p.Results.app, ...
                    sprintf(['The %s images are %dx%d but the ROIs in the saved JSON were ' ...
                    'defined on a %dx%d source. The FOVs differ and the JSON carries no ' ...
                    'stationary-camera FOV mapping for them; refusing to cut with mismatched geometry.'], ...
                    dataset, stk.height, stk.width, src_dims(1), src_dims(2)));
                ok = false;
                return;
            end
            if isempty(p.Results.Writer)
                writer = @(c, o, pol) rabbit_cut_tiffs.write_crop(c, o, pol);
            else
                writer = p.Results.Writer;
            end
            [ok, out_root] = rabbit_cut_tiffs.cut_stack(p.Results.app, dataset, stk.stack, ...
                stk.height, stk.width, stk.n_frames, stem, source_path, ...
                bounds, src_dims, writer, p.Results.OutputRoot, fov);
        end

        function [stk, stem, source_path] = dataset_stack(app, dataset)
            %% Get a dataset's stack for re-cutting
            % 'om' comes from memory; 'calibration' and 'reconstruction'
            % are re-loaded from their saved paths with
            % rabbit_stack_io.load_stack_native (bit depth kept). Returns
            % an empty stack, stem and path if the dataset is not
            % available (the user has already been alerted).
            if strcmp(dataset, 'om')
                s = app.data.image_stack;
                if isempty(s)
                    rabbit_cut_tiffs.alert(app, ...
                        'The optical-mapping images are not loaded; nothing to cut.');
                    stk = []; stem = ''; source_path = '';
                    return;
                end
                [H, W, n] = rabbit_cut_tiffs.stack_planes(s);
                stk = struct('stack', s, 'height', H, 'width', W, 'n_frames', n);
                [~, stem] = fileparts(app.file_info.file);
                if isempty(stem)
                    [~, stem] = fileparts(app.file_info.name);
                end
                source_path = fullfile(app.file_info.path, app.file_info.file);
                return;
            end
            if strcmp(dataset, 'calibration')
                fld = 'calibration_source';
            else
                fld = 'reconstruction_path';
            end
            if ~isfield(app.data, fld) || isempty(app.data.(fld))
                rabbit_cut_tiffs.alert(app, ...
                    sprintf('The %s images are not loaded (no saved source path); nothing to cut.', dataset));
                stk = []; stem = ''; source_path = '';
                return;
            end
            src = app.data.(fld);
            try
                loaded = rabbit_stack_io.load_stack_native(src);
            catch ME
                rabbit_cut_tiffs.alert(app, ...
                    sprintf('Could not load the %s images for cutting: %s', ...
                    dataset, ME.message));
                stk = []; stem = ''; source_path = '';
                return;
            end
            stk = loaded;
            if isfolder(src)
                stem = rabbit_cut_tiffs.source_stem(src);
            else
                [~, stem] = fileparts(src);
            end
            source_path = src;
        end

        function stem = source_stem(src)
            %% Output folder stem for a source path
            % The basename, after stripping a trailing separator (fileparts
            % returns an empty name for 'folder/'). Falls back to 'stack'.
            if isfolder(src)
                s = char(src);
                while ~isempty(s) && (s(end) == filesep || s(end) == '/')
                    s(end) = []; %#ok<AGROW>
                end
                [~, stem] = fileparts(s);
            else
                [~, stem] = fileparts(src);
            end
            if isempty(stem)
                stem = 'stack';
            end
        end

        function [ok, out_root] = cut_stack(app, dataset, planes, H, W, n, stem, source_path, bounds, src_dims, writer, out_root_override, fov_mapping)
            %% Crop every frame per ROI and write the TIFFs
            % Writes into a new per-dataset output folder, the next free
            % name if the usual one is taken, removes partial output on
            % failure, then writes the manifest.
            % Optional inputs:
            %   writer: @(cropped, out_path, policy), replaces write_crop
            %       (used by the tests to force a failure)
            %   out_root_override: output folder override (tests only)
            %   fov_mapping: stationary-camera FOV mapping already applied
            %       to the bounds (default []); recorded in the manifest
            if nargin < 11
                writer = @(c, o, p) rabbit_cut_tiffs.write_crop(c, o, p);
            end
            if isempty(writer)
                writer = @(c, o, p) rabbit_cut_tiffs.write_crop(c, o, p);
            end
            if nargin < 12
                out_root_override = '';
            end
            if nargin < 13
                fov_mapping = [];
            end
            ok = false;
            if ~isempty(out_root_override)
                out_root = char(out_root_override);
            else
                out_root = rabbit_cut_tiffs.output_root(app, dataset, stem);
                % The number shared by the folders of this cut (cut_inline)
                if isfield(app.data, 'cut_output_suffix')
                    out_root = [out_root app.data.cut_output_suffix];
                end
            end
            % An existing folder is never touched: use the next free name
            out_root = rabbit_stack_io.next_free_path(out_root);
            % The editor writes 1-based inclusive bounds inside the image;
            % anything outside means mismatched geometry, so refuse rather
            % than clamp.
            for k = 1:size(bounds, 1)
                if any(bounds(k, :) < 1) || bounds(k, 1) > H || bounds(k, 3) > H ...
                        || bounds(k, 2) > W || bounds(k, 4) > W ...
                        || bounds(k, 1) > bounds(k, 3) || bounds(k, 2) > bounds(k, 4)
                    rabbit_cut_tiffs.alert(app, ...
                        sprintf(['Refusing to cut the %s images: ROI %d lies outside the ' ...
                        '%dx%d image (bounds %d %d %d %d there). The ROIs were defined on the ' ...
                        'optical-mapping image and must fit the source; when the camera''s area ' ...
                        'of interest differed, keep every box inside the part both recordings ' ...
                        'show (the ROI editor outlines it).'], ...
                        dataset, k, H, W, bounds(k, 1), bounds(k, 2), bounds(k, 3), bounds(k, 4)));
                    out_root = '';
                    return;
                end
            end

            written = {};
            created_dirs = {};
            words = struct('om', 'optical mapping', 'calibration', 'calibration', 'reconstruction', 'reconstruction');
            n_views = size(bounds, 1);
            % The calibration cut: one folder per view, named
            % by its place in the frame (view1 leftmost ... view4
            % rightmost), the outer two flipped left-right, as the calibration's
            % tiles are (write_cut_locations)
            as_views = strcmp(dataset, 'calibration') && n_views == 4;
            place_of = 1:n_views;
            if as_views
                [~, order] = sort(bounds(:, 2));
                place_of(order) = 1:4;
            end
            try
                mkdir(out_root);
                created_dirs{end+1} = out_root; %#ok<AGROW>
                if as_views
                    for q = 1:4
                        mkdir(fullfile(out_root, sprintf('view%d', q)));
                        created_dirs{end+1} = fullfile(out_root, sprintf('view%d', q)); %#ok<AGROW>
                    end
                end
                for k = 1:size(bounds, 1)
                    % ROI k: rows bounds(k,1):bounds(k,3), cols
                    % bounds(k,2):bounds(k,4) (Nx4 unmirrored source
                    % bounds, 1-based inclusive; validated above)
                    rows = bounds(k, 1):bounds(k, 3);
                    cols = bounds(k, 2):bounds(k, 4);
                    for f = 1:n
                        if f == 1 || mod(f, 10) == 0 || f == n
                            % every 10 frames: the message, the bar
                            % (reading counts as the first 10 % of a
                            % dataset) and Cancel
                            rabbit_cut_tiffs.progress(app, sprintf('Writing the %s copies: view %d of %d, frame %d of %d', ...
                                words.(dataset), k, n_views, f, n), 0.1 + 0.9 * ((k - 1) * n + f) / (n_views * n));
                            if rabbit_cut_tiffs.progress_cancelled(app)
                                error('analyse_om:CutTiffs:Cancelled', 'The cut was cancelled.');
                            end
                        end
                        frame = planes(:, :, f);
                        cropped = frame(rows, cols);
                        policy = rabbit_cut_tiffs.class_policy(cropped, dataset);
                        out_name = rabbit_cut_tiffs.frame_output_name( ...
                            dataset, stem, source_path, k, f);
                        out_path = fullfile(out_root, out_name);
                        if as_views   % named by its place, as its folder
                            if any(place_of(k) == [1 4]), cropped = fliplr(cropped); end
                            out_name = rabbit_cut_tiffs.frame_output_name(dataset, stem, source_path, place_of(k), f);
                            out_path = fullfile(out_root, sprintf('view%d', place_of(k)), out_name);
                        end
                        writer(cropped, out_path, policy);
                        written{end+1} = struct('source', source_path, ... %#ok<AGROW>
                            'frame', f, 'view', k, 'output', out_path, ...
                            'policy', policy);
                    end
                end
            catch ME
                % Remove only what this attempt wrote, then its folders if
                % empty (dir('*') lists '.' and '..', so filter them out)
                for w = 1:numel(written)
                    if exist(written{w}.output, 'file')
                        delete(written{w}.output);
                    end
                end
                for d = numel(created_dirs):-1:1
                    if isfolder(created_dirs{d})
                        e = dir(fullfile(created_dirs{d}, '*'));
                        e = e(arrayfun(@(x) ~strcmp(x.name, '.') ...
                            && ~strcmp(x.name, '..'), e));
                        if isempty(e)
                            rmdir(created_dirs{d});
                        end
                    end
                end
                if ~strcmp(ME.identifier, 'analyse_om:CutTiffs:Cancelled')   % Cancel: cut_inline says so
                    rabbit_cut_tiffs.alert(app, ...
                        sprintf('Cutting the %s images failed part-way; no partial output was left behind. %s', ...
                        dataset, ME.message));
                end
                out_root = '';
                return;
            end

            rabbit_cut_tiffs.write_manifest(app, out_root, dataset, source_path, ...
                bounds, src_dims, struct('height', H, 'width', W, 'n_frames', n), written, fov_mapping);
            % Later steps look the folder up here, not by its usual name
            app.data.cut_folders_made.(dataset) = struct('stem', stem, 'path', out_root);
            ok = true;
        end

        function report_folders(app)
            %% Tell the user which folders the cut made
            made = {};
            if isfield(app.data, 'cut_folders_made')
                fields = fieldnames(app.data.cut_folders_made);
                for k = 1:numel(fields)
                    made{end+1} = app.data.cut_folders_made.(fields{k}).path; %#ok<AGROW>
                end
            end
            if isempty(made)
                return;
            end
            msg = sprintf('The TIFF copies are in:\n%s', strjoin(made, newline));
            if isfield(app.data, 'cut_roi_json') && ~isempty(app.data.cut_roi_json)
                msg = sprintf(['%s\n\nThe regions file (Reconstruction tab, step 2) is %s. Step 2 is filled in ' ...
                    'with it and the reconstruction images.'], msg, app.data.cut_roi_json);
            end
            if ~isempty(app) && isprop(app, 'opticalmappingUIFigure') ...
                    && ~isempty(app.opticalmappingUIFigure)
                uialert(app.opticalmappingUIFigure, msg, 'TIFF copies made', 'Icon', 'success');
            else
                fprintf('CUT_DONE: %s\n', msg);
            end
        end

        function cut_dir = find_cut_folder(app, dataset, stem, bounds)
            %% Find the cut of this recording that fits these ROIs
            % The folder made in this session comes first (see
            % app.data.cut_folders_made), then the folders of this
            % recording by name, newest number first. A folder fits when
            % its first image of every view has the size of that view's
            % ROI. Empty when none fits.
            % Inputs:
            %   bounds: Nx4 ROI bounds of the cut; rows are the views
            cut_dir = '';
            tried = {};
            if isfield(app.data, 'cut_folders_made') && isfield(app.data.cut_folders_made, dataset) ...
                    && strcmp(app.data.cut_folders_made.(dataset).stem, stem)
                tried{end+1} = app.data.cut_folders_made.(dataset).path;
            end
            base = rabbit_cut_tiffs.output_root(app, dataset, stem);
            [root, name, tail] = fileparts(base);
            name = [name tail];
            d = dir(root);
            d = d([d.isdir]);
            pattern = ['^' regexptranslate('escape', name) '(_(\d{2,}))?$'];
            numbers = [];
            found = {};
            for k = 1:numel(d)
                if ~isempty(regexp(d(k).name, pattern, 'once'))
                    found{end+1} = fullfile(root, d(k).name); %#ok<AGROW>
                    % the digits after 'name_'; the unnumbered folder is 0
                    numbers(end+1) = max([0 str2double(d(k).name(numel(name) + 2:end))]); %#ok<AGROW>
                end
            end
            [~, order] = sort(numbers, 'descend');
            tried = [tried, found(order)];
            % A folder cut at another frame position (its
            % manifest's fov_mapping) does not fit either
            field = [dataset '_fov_mapping'];
            current = [];
            if isfield(app.data, field), current = app.data.(field); end
            for k = 1:numel(tried)
                if rabbit_cut_tiffs.folder_fits(tried{k}, bounds) && ...
                        rabbit_cut_tiffs.same_position(tried{k}, current)
                    cut_dir = tried{k};
                    return;
                end
            end
        end

        function ok = same_position(folder, mapping)
            %% True when a cut folder was cut at this frame position (or records none to compare)
            ok = true;
            mf = fullfile(folder, 'manifest.json');
            if exist(mf, 'file') ~= 2, return; end
            try
                m = jsondecode(fileread(mf, 'Encoding', 'UTF-8'));
            catch
                return;
            end
            offs = @(x) [x.om_window_in_rec.off, rabbit_cut_tiffs.cols_off_of(x)];
            had = isfield(m, 'fov_mapping') && ~isempty(m.fov_mapping);
            has = ~isempty(mapping) && isstruct(mapping);
            if had && has
                ok = isequal(offs(m.fov_mapping), offs(rabbit_stack_io.validate_fov_mapping(mapping)));
            elseif had || has
                % one of the two shifted, the other not: shifted by zero is the same
                if had, ok = isequal(offs(m.fov_mapping), [0 0]); else, ok = isequal(offs(rabbit_stack_io.validate_fov_mapping(mapping)), [0 0]); end
            end
        end

        function c = cols_off_of(m)
            %% The column offset of a mapping (0 when it has none)
            c = 0;
            if isfield(m.om_window_in_rec, 'cols_off'), c = m.om_window_in_rec.cols_off; end
        end

        function ok = folder_fits(folder, bounds)
            %% True when a cut folder has images of these ROI sizes
            ok = false;
            if ~isfolder(folder)
                return;
            end
            d = dir(folder);
            names = {d(~[d.isdir]).name};
            for v = 1:size(bounds, 1)
                hit = find(~cellfun(@isempty, regexp(names, ...
                    sprintf('_view%d(\\.|_).*tiff?$', v), 'once')), 1);
                if isempty(hit)
                    return;
                end
                info = imfinfo(fullfile(folder, names{hit}));
                if info(1).Height ~= bounds(v, 3) - bounds(v, 1) + 1 || ...
                        info(1).Width ~= bounds(v, 4) - bounds(v, 2) + 1
                    return;
                end
            end
            ok = true;
        end

        function [H, W, n] = stack_planes(stk)
            %% Height, width and frame count of a 2-D, 3-D or 4-D stack
            % For a 4-D stack the frame count is the 4th dimension.
            if ndims(stk) == 2
                H = size(stk, 1); W = size(stk, 2); n = 1;
            elseif ndims(stk) == 3
                H = size(stk, 1); W = size(stk, 2); n = size(stk, 3);
            elseif ndims(stk) == 4
                H = size(stk, 1); W = size(stk, 2); n = size(stk, 4);
            else
                error('analyse_om:CutTiffs:BadStack', ...
                    'Cannot cut a %d-dimensional stack (2-D, 3-D or 4-D expected).', ndims(stk));
            end
        end

        function out_name = frame_output_name(dataset, stem, source_path, k, f)
            %% Output filename that keeps the source basename
            %   multi-frame source: <stem>_view<k>_frame_%04d.tiff
            %   folder of 2-D TIFFs: <frame_stem>_view<k>.tiff, with the
            %       frames in natural sort order as the loader reads them
            % Only calibration and reconstruction can be folders; om is
            % always cut from memory.
            if isfolder(source_path)
                d = dir(source_path);
                keep = arrayfun(@(e) ~e.isdir && ~isempty(regexpi(e.name, '\.tiff?$')), d);
                nms = rabbit_stack_io.natsort_names({d(keep).name});
                if f <= numel(nms)
                    [~, frame_stem] = fileparts(nms{f});
                    out_name = sprintf('%s_view%d.tiff', frame_stem, k);
                    return;
                end
            end
            out_name = sprintf('%s_view%d_frame_%04d.tiff', stem, k, f);
        end

        function policy = class_policy(cropped, dataset)
            %% Bit-depth policy for a crop
            % uint8/uint16 unchanged; for the optical-mapping and the
            % reconstruction images, single/double holding only whole
            % numbers from 0 to 65535 (camera counts) written as uint16, so
            % the intensity changes over time are kept (the sparse model
            % step stretches the reconstruction counts itself); everything
            % else min-max normalised to [0,1] and written as uint8 (the
            % calibration copies stay 8-bit).
            if nargin < 2
                dataset = '';
            end
            c = class(cropped);
            if strcmp(c, 'uint8') || strcmp(c, 'uint16')
                policy = c;
            elseif any(strcmp(dataset, {'om', 'reconstruction'})) && isfloat(cropped) && ~isempty(cropped) && all(isfinite(cropped(:))) ...
                    && all(cropped(:) >= 0) && all(cropped(:) <= 65535) ...
                    && all(cropped(:) == round(cropped(:)))
                policy = 'whole_number_uint16';
            else
                policy = 'normalized_uint8';
            end
        end

        function write_crop(cropped, out_path, policy)
            %% Write one crop as an uncompressed TIFF using the policy
            if strcmp(policy, 'uint8') || strcmp(policy, 'uint16')
                imwrite(cropped, out_path, 'Compression', 'none');
                return;
            end
            if strcmp(policy, 'whole_number_uint16')
                % exact: the values are whole numbers inside the uint16 range
                imwrite(uint16(cropped), out_path, 'Compression', 'none');
                return;
            end
            d = double(cropped);
            fin = d(isfinite(d));
            if isempty(fin)
                d = zeros(size(d));
            else
                mn = min(fin);
                mx = max(fin);
                rng = mx - mn;
                if ~isfinite(rng) || rng <= 0
                    d = zeros(size(d));
                else
                    d = (d - mn) ./ rng;
                end
            end
            d(~isfinite(d)) = 0;   % NaN/Inf -> 0 (no TIFF representation)
            imwrite(uint8(round(d .* 255)), out_path, 'Compression', 'none');
        end

        function write_manifest(app, out_root, dataset, source_path, bounds, src_dims, stk, written, fov_mapping)
            %% Write manifest.json for a cut
            % Lists every written file with its source, frame and view,
            % plus the ROI bounds, source size and bit-depth policy. If a
            % stationary-camera FOV mapping was applied, it is recorded
            % with the size of the frame the bounds were drawn on.
            if nargin < 9
                fov_mapping = [];
            end
            m = struct();
            m.version = 1;
            m.dataset = dataset;
            m.source = source_path;
            m.source_dims = struct('height', stk.height, 'width', stk.width, ...
                'n_frames', stk.n_frames);
            m.roi_bounds = struct('schema', 'region_bounds_src', ...
                'coordinates', 'unmirrored source, MATLAB 1-based, inclusive', ...
                'view_order', 'view2; view3; view1; view4', ...
                'bounds', bounds);
            if ~isempty(fov_mapping) && isstruct(fov_mapping)
                m.fov_mapping = rabbit_stack_io.validate_fov_mapping(fov_mapping);
                if ~isempty(src_dims)
                    m.bounds_defined_on = struct('height', src_dims(1), ...
                        'width', src_dims(2));
                end
            end
            if ~isempty(src_dims)
                m.defined_on_dims = struct('height', src_dims(1), 'width', src_dims(2));
            else
                m.defined_on_dims = [];
            end
            files = struct('source', cell(1, numel(written)), ...
                'frame', cell(1, numel(written)), ...
                'view', cell(1, numel(written)), ...
                'output', cell(1, numel(written)), ...
                'policy', cell(1, numel(written)));
            for w = 1:numel(written)
                files(w).source = written{w}.source;
                files(w).frame = written{w}.frame;
                files(w).view = written{w}.view;
                files(w).output = written{w}.output;
                files(w).policy = written{w}.policy;
            end
            m.files = files;
            m.policy_note = ['uint8/uint16 verbatim; optical-mapping and reconstruction single/double whole numbers 0-65535 written as ' ...
                'uint16 (whole_number_uint16); other numeric classes min-max normalised to [0,1] and written as uint8; NaN/Inf -> 0'];
            m.created_by = 'analyse_optical_mapping (TIFF cut engine)';
            try
                txt = jsonencode(m, 'PrettyPrint', true);
            catch
                txt = jsonencode(m);   % plain JSON is equally valid
            end
            f = fopen(fullfile(out_root, 'manifest.json'), 'w', 'n', 'UTF-8');
            if f < 0
                % The cut succeeded but the manifest is missing, so tell
                % the user
                rabbit_cut_tiffs.alert(app, ...
                    sprintf('The %s images were cut but the manifest could not be written: %s', ...
                    dataset, fullfile(out_root, 'manifest.json')));
                return;
            end
            try
                fprintf(f, '%s\n', txt);
            catch
                % best effort - the cut itself succeeded
            end
            fclose(f);
        end

        function ok = choose_output_folder(app)
            %% Ask where to write the TIFF copies
            % Opens a folder dialog at the optical-mapping folder (or the
            % folder chosen before for this recording). The choice is kept
            % in app.data.cut_output_root, so later re-cuts and the
            % segmentation tools find the copies; it is cleared when another
            % recording is loaded. Returns false if the dialog was
            % cancelled. A folder that already holds copies of these
            % recordings is fine: the new cut gets the next free number.
            start = app.file_info.path;
            if isfield(app.data, 'cut_output_root') && ~isempty(app.data.cut_output_root)
                start = app.data.cut_output_root;
            end
            folder = uigetdir(start, ...
                'Choose the folder for the TIFF copies (a cut_tiffs_... folder is made inside it)');
            if isequal(folder, 0) || isempty(folder)
                ok = false;
                return;
            end
            app.data.cut_output_root = char(folder);
            ok = true;
        end

        function names = cut_folder_names(app)
            %% The cut_tiffs_<dataset>_<stem> names this cut would use, before numbering
            names = {};
            stems = {};
            [~, s] = fileparts(app.file_info.file);
            if isempty(s) && isfield(app.file_info, 'name'), [~, s] = fileparts(app.file_info.name); end
            if ~isempty(s), stems(end+1, :) = {'om', s}; end
            if isfield(app.data, 'calibration_source') && ~isempty(app.data.calibration_source)
                stems(end+1, :) = {'calibration', rabbit_cut_tiffs.source_stem(app.data.calibration_source)};
            end
            if isfield(app.data, 'reconstruction_path') && ~isempty(app.data.reconstruction_path)
                stems(end+1, :) = {'reconstruction', rabbit_cut_tiffs.source_stem(app.data.reconstruction_path)};
            end
            for k = 1:size(stems, 1)
                names{end+1} = sprintf('cut_tiffs_%s_%s', stems{k, 1}, stems{k, 2}); %#ok<AGROW>
            end
        end

        function out_root = output_root(app, dataset, stem)
            %% Usual per-dataset output folder, before any number
            % <root>/cut_tiffs_<dataset>_<source_stem>, with <root> the
            % folder chosen for this recording's cut
            % (app.data.cut_output_root, see choose_output_folder), else
            % the loaded optical-mapping folder (app.file_info.path). The
            % stem keeps two sources in the same folder apart.
            root = '';
            if isfield(app.data, 'cut_output_root') && ~isempty(app.data.cut_output_root) ...
                    && isfolder(app.data.cut_output_root)
                root = app.data.cut_output_root;
            end
            if isempty(root)
                root = app.file_info.path;
            end
            if isempty(root) || ~isfolder(root)
                root = fileparts(app.file_info.file);
                if isempty(root)
                    root = pwd;
                end
            end
            if isempty(stem)
                stem = 'stack';
            end
            out_root = fullfile(root, sprintf('cut_tiffs_%s_%s', dataset, stem));
        end

        function [bounds, src_dims] = current_bounds(app)
            %% ROI bounds to cut with
            % The unmirrored source bounds from the editor (Nx4, rows
            % [View2; View3; View1; View4]). Empty if no regions exist.
            bounds = [];
            src_dims = [];
            if ~isfield(app.data, 'region_bounds_src')
                return;
            end
            b = app.data.region_bounds_src;
            if isempty(b) || size(b, 2) ~= 4
                return;
            end
            bounds = double(b);
            if ~isempty(app.data.height) && ~isempty(app.data.width)
                src_dims = [app.data.height app.data.width];
            end
        end

        function alert(app, msg)
            %% Show a message with uialert, or print it when headless
            if ~isempty(app) && isprop(app, 'opticalmappingUIFigure') ...
                    && ~isempty(app.opticalmappingUIFigure)
                uialert(app.opticalmappingUIFigure, msg, 'Cut TIFF copies failed');
            else
                fprintf('CUT_ALERT: %s\n', msg);
            end
        end

    end
end
