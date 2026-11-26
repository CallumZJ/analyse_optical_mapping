classdef rabbit_calibration
    %% Metric calibration of the rabbit rig with pyCamSet: spec, checks, scale, pixel size
    % Collin Snitchler
    % 02.11.2026
    % Purpose: everything the Reconstruction tab needs around
    %          rabbit_pycamset_calibrate.py: the calibration's settings, the
    %          tile images it reads, the gates that decide whether its
    %          result may carry a metric claim, the similarity from a sparse
    %          model to the calibrated rig, and the mm per pixel of a mesh.
    %
    % How a run gets its scale. The sparse model stays what it is: built
    % from the heart images at the recipe's focal length, so it is as good
    % as a run without calibration. Each frame of that model holds the four
    % virtual cameras, and so does the calibration, in mm. One similarity
    % between the two sets of camera centres gives the scale, and the
    % centres that do not fit say how far the rig of the recording is from
    % the rig of the calibration (camera moved, mirror knocked). The model
    % is scaled with COLMAP's model_transformer, which scales the rig too,
    % so every later step works in mm. Both rigs must be solved at the same
    % focal length: the camera distance follows the focal length, the
    % magnification does not.
    % Why no calibrated cameras are forced into COLMAP: the tiles are about
    % 400 px of a lens of about 8000 px, so the data leave the focal length
    % open (the calibration's profile shows this) and a calibrated value
    % would change little. Keeping the heart's own rig is what lets the two
    % rigs be compared at all.
    %
    % Tiles are named by position: tile1..tile4 left to right in the camera
    % frame, so ROI rows (view2;view3;view1;view4 at any assignment of
    % tiles) never enter the calibration. tile1 and tile4 are the outer
    % ones, flipped left-right like the sparse model's tiles.
    %
    % Sources: pyCamSet (R. Laven and contributors, development branch);
    % Umeyama 1991 for the similarity; Baker and Nayar 1999 for one virtual
    % pinhole per planar mirror view; COLMAP model_transformer (Schoenberger
    % and Frahm 2016).
    %
    % Section map (search for the quoted line; line numbers move)
    %   Spec and frames ........ "function s = default_spec()"
    %   Frame placement ........ "function [place, err] = placement("
    %   Tiles .................. "function [n_frames, H] = write_tiles("
    %   pyCamSet job and result  "function job = make_job("
    %   Verdict and text ....... "function v = verdict(c)"
    %   Sparse rig vs calibration "function [C, A, frames] = model_rig("
    %   Scaling the model ...... "function [r, tc] = apply_to_model("
    %   Pixel size ............. "function P = pixel_size("
    %   Session and records .... "function [same, txt, unknown] = session_check("

    properties (Constant)
        SPEC_SCHEMA = 'rabbit_calibration.spec.v1';
        RESULT_SCHEMA = 'rabbit_calibration.result.v1';
        VERDICT_SCHEMA = 'rabbit_calibration.verdict.v1';
        METRIC_SCHEMA = 'rabbit_calibration.metric_scale.v1';
        PIXEL_SCHEMA = 'rabbit_calibration.pixel_size.v1';
        TILES = {'tile1', 'tile2', 'tile3', 'tile4'};
        % Gates of a calibration. The reference rabbit recordings gave
        % 0.84-1.13 px per view, 92 % of the points kept, and held-out cubes
        % within 0.3 %. min_view_points is 480, chosen for the rabbit data,
        % not taken from a reference: the 30 mm solve of the reference
        % rabbit Ccube keeps 488 points in view 4 where the same solve at
        % 10 mm keeps 504 (pyCamSet's starting guess depends on the units);
        % the two solves otherwise agree (x3.0002).
        GATE = struct('max_view_rmse_px', 1.5, 'min_kept_fraction', 0.8, ...
            'min_view_points', 480, 'min_view_images', 20, ...
            'max_holdout_error_percent', 1.0, 'min_holdout_frames', 10, ...
            'max_holdout_residual_mm', 0.5, 'max_holdout_rejected_fraction', 0.3);
        % Gates of the comparison of a sparse rig with the calibration. Angle
        % and baselines allow 2.5 deg and 2 %: an earlier rabbit recording
        % gave 2.23 deg and 1.85 %, attributed to view 1's less certain
        % sparse pose.
        RIG_GATE = struct('max_centre_residual_percent', 2.0, ...
            'max_angle_difference_deg', 2.5, 'max_baseline_spread_percent', 2.0, ...
            'max_focal_difference_percent', 0.5);
        TARGET_TYPES = {'PuzzleBoardCube', 'Ccube'};
    end

    methods (Static)

        % =============================================================
        % 1. Settings of a calibration
        % =============================================================

        function s = default_spec()
            %% An empty spec. The target size is left empty on purpose: it sets the scale
            s = struct('schema', rabbit_calibration.SPEC_SCHEMA, ...
                'recordings', struct('path', {}, 'role', {}, 'type', {}, 'n_points', {}, ...
                'edge_mm', {}, 'size_source', {}), ...
                'focal_px', 8000, 'k1', 0, 'lens_centre_frame_px', [], ...
                'pixel_pitch_um', 6.5, 'lens_focal_mm', 50, 'frame_width', [], ...
                'windows', [], 'threads', 6, 'roi_bounds', [], 'size_source', '', ...
                'frame_hw', [], 'roi_hw', [], ...
                'preprocess', rabbit_calibration.default_preprocess());
        end

        function p = default_preprocess()
            %% The pre-processing of Ccube tiles before detection, on by default
            % Sauvola binarisation, window 7 px, k 0 (rabbit_sauvola): on the
            % rabbit ccube1 recordings the only setting tried with which all
            % three calibrated. Only Ccube recordings are binarised; other
            % targets keep pyCamSet's own preparation. [] = no pre-processing.
            p = struct('type', 'sauvola', 'window', 7, 'k', 0, 'targets', {{'Ccube'}});
        end

        function [ok, err] = check_spec(s)
            %% The settings can be run. err says what to change
            ok = false; err = '';
            r = s.recordings;
            if isempty(r)
                err = 'Add at least one calibration recording.'; return;
            end
            if ~any(strcmp({r.role}, 'fit'))
                err = 'Choose which recording the rig is solved from (role fit).'; return;
            end
            for k = 1:numel(r)
                [~, nm, ex] = fileparts(r(k).path);
                nm = [nm ex]; %#ok<AGROW>
                if ~any(strcmp(r(k).role, {'fit', 'holdout'}))
                    err = sprintf('%s: the role must be fit or holdout.', nm); return;
                end
                if exist(r(k).path, 'file') == 0
                    err = sprintf('%s was not found.', r(k).path); return;
                end
                if ~any(strcmp(r(k).type, rabbit_calibration.TARGET_TYPES))
                    err = sprintf('%s: the target must be one of: %s.', nm, ...
                        strjoin(rabbit_calibration.TARGET_TYPES, ', ')); return;
                end
                if ~isnumeric(r(k).n_points) || ~isscalar(r(k).n_points) || ...
                        r(k).n_points < 2 || r(k).n_points ~= round(r(k).n_points)
                    err = sprintf('%s: give the number of squares along a cube edge.', nm); return;
                end
                if ~isnumeric(r(k).edge_mm) || ~isscalar(r(k).edge_mm) || ~isfinite(r(k).edge_mm) || r(k).edge_mm <= 0
                    err = sprintf(['%s: give the cube edge in mm. It sets the scale of everything ' ...
                        'measured later, so there is no default.'], nm); return;
                end
end
            fit = r(strcmp({r.role}, 'fit'));
            if numel(unique(arrayfun(@(q) sprintf('%s|%d|%g', q.type, q.n_points, q.edge_mm), fit, ...
                    'UniformOutput', false))) ~= 1
                err = 'The recordings marked fit must all show the same target.'; return;
            end
            if ~isnumeric(s.focal_px) || ~isscalar(s.focal_px) || ~isfinite(s.focal_px) || s.focal_px <= 0
                err = 'The focal length must be a positive number of pixels.'; return;
            end
            if ~isnumeric(s.pixel_pitch_um) || ~isscalar(s.pixel_pitch_um) || ~(s.pixel_pitch_um > 0)
                err = 'The pixel pitch must be a positive number of micrometres.'; return;
            end
            ok = true;
        end

        function [bounds, err] = tile_bounds(Rr)
            %% The four tiles in the reconstruction frame, from a resolved recipe
            err = '';
            bounds = [];
            v = Rr.resolved.views;
            if iscell(v), v = [v{:}]; end
            if numel(v) ~= 4 || any(arrayfun(@(q) numel(q.bounds) ~= 4, v))
                err = ['The positions of the four views are not known: the reconstruction images have no ' ...
                    'manifest.json and the ROI file does not give all four regions. Cut the reconstruction ' ...
                    'recording in this app, or choose an ROI file saved by the ROI editor with four regions.'];
                return;
            end
            bounds = double(reshape([v.bounds], 4, 4)');
        end

        function [hw, roi_hw, err] = frame_size(Rr, roi_json)
            %% [rows columns] of the reconstruction frame, and of the frame the regions were drawn on
            % The cut manifest of a resolved recipe knows the first. The ROI
            % file's dims are the OM frame when the OM recording is a crop,
            % so they stand in only when no FOV mapping says the two differ.
            err = '';
            p = rabbit_stack_io.load_roi_json(roi_json, [], []);
            roi_hw = [double(p.source_dims.height) double(p.source_dims.width)];
            hw = reshape(double(Rr.resolved.source_dims), 1, []);
            if numel(hw) == 2, return; end
            hw = [];
            if isfield(p, 'fov_mapping') && ~isempty(p.fov_mapping)
                err = ['The size of the reconstruction frames is not known: the cut images have no manifest.json. ' ...
                    'Cut the reconstruction recording in this app first.'];
            else
                hw = roi_hw;
            end
        end

        function hw = recording_size(input)
            %% [rows columns] of a recording's frames, without loading the frames
            if isfolder(input)
                if exist(fullfile(input, 'cut_locations_per_view.json'), 'file') == 2
                    hw = rabbit_calibration.cut_size(input);
                    return;
                end
                d = [dir(fullfile(input, '*.tif')); dir(fullfile(input, '*.tiff'))];
                if isempty(d)
                    error('analyse_om:Calibration:NoFrames', 'There are no TIFF frames in %s.', input);
                end
                info = imfinfo(fullfile(input, d(1).name));
                hw = [info(1).Height info(1).Width];
                return;
            end
            [~, ~, ex] = fileparts(input);
            if any(strcmpi(ex, {'.fits', '.fit'}))
                sz = fitsinfo(input).PrimaryData.Size;
                hw = double(sz(1:2));
            else
                info = imfinfo(input);
                hw = [info(1).Height info(1).Width];
            end
        end

        function hw = cut_size(folder)
            %% [rows columns] of the frames a view1-view4 cut folder was cut from
            % The cut margins can sum one pixel off (a reference rabbit
            % recording's view1: 1575 + 410 + 16 = 2001). The frame is the
            % size most views agree on, and each view may be one pixel off
            % it.
            cuts = rabbit_calibration.read_json(fullfile(folder, 'cut_locations_per_view.json'));
            sizes = zeros(numel(cuts), 2);
            for k = 1:numel(cuts)
                c = cuts(k);
                files = dir(fullfile(folder, c.view, '*.tif*'));
                if isempty(files)
                    error('analyse_om:Calibration:NoFrames', 'There are no TIFF frames in %s.', fullfile(folder, c.view));
                end
                info = imfinfo(fullfile(folder, c.view, files(1).name));
                sizes(k, :) = [c.top + info(1).Height + c.bottom, c.left + info(1).Width + c.right];
            end
            hw = mode(sizes, 1);
            if any(abs(sizes - hw) > 1, 'all')
                error('analyse_om:Calibration:CutSizes', 'A view in %s is more than one pixel off the frame size %dx%d.', ...
                    folder, hw(1), hw(2));
            end
        end

        function [ok, err] = check_frames(spec)
            %% Every recording can be placed in the reconstruction frame
            % The lens centre, tile columns and rays are those of the
            % reconstruction frame. A recording of that size with no
            % position is taken as the same frame. A recording
            % whose frames show another part of the sensor (the camera's
            % area of interest changed) carries frame_offset, the row and
            % column of its top-left pixel in the reconstruction frame
            % (placement); its frames are then put there (write_tiles), and
            % it must show some of every tile. Without a position a
            % recording of another size is refused: its rows and columns
            % would be guessed at.
            ok = false; err = '';
            hw = reshape(double(spec.frame_hw), 1, []);
            roi = reshape(double(spec.roi_hw), 1, []);
            if numel(hw) ~= 2
                err = 'The size of the reconstruction frames is not known. Choose the reconstruction images first.';
                return;
            end
            % The tile bounds are in the reconstruction frame (mapped across
            % any FOV); the OM frame itself may have another size, offset or
            % scale, and check_roi_bounds compares the two.
            b = double(spec.roi_bounds);
            if size(b, 1) ~= 4 || size(b, 2) ~= 4
                err = 'The positions of the four views are not known.';
                return;
            end
            windows = rabbit_calibration.tile_windows(b, hw(2));
            r = spec.recordings;
            for k = 1:numel(r)
                [~, nm, ex] = fileparts(r(k).path);
                nm = [nm ex]; %#ok<AGROW>
                try
                    s = rabbit_calibration.recording_size(r(k).path);
                catch ME
                    err = sprintf('Could not read %s: %s', nm, ME.message);
                    return;
                end
                off = [];
                if isfield(r(k), 'frame_offset'), off = reshape(double(r(k).frame_offset), 1, []); end
                if isempty(off) || isequal(off, [0 0])
                    if isequal(s, hw), continue; end
                    if isempty(off)
                        if isequal(s, roi)
                            err = sprintf(['%s has the %dx%d frames of the OM recording, and the reconstruction frames are ' ...
                                '%dx%d. Its position in the reconstruction frame is not known: add it again so that it ' ...
                                'is measured, or type it in with Position....'], nm, s(1), s(2), hw(1), hw(2));
                        else
                            err = sprintf(['%s has frames of %dx%d and the reconstruction frames are %dx%d. Its ' ...
                                'position in the reconstruction frame is not known: add it again so that it is ' ...
                                'measured, or type it in with Position....'], nm, s(1), s(2), hw(1), hw(2));
                        end
                        return;
                    end
                end
                if numel(off) ~= 2 || any(~isfinite(off)) || any(off ~= round(off))
                    err = sprintf('%s: its position in the reconstruction frame must be two whole numbers.', nm);
                    return;
                end
                if isfolder(r(k).path) && (~isequal(off, [0 0]) || ~isequal(s, hw))
                    err = sprintf(['%s is a cut folder of frames %dx%d; only cut folders of the reconstruction ' ...
                        'frame itself (%dx%d, same position) can be used. Add the recording itself instead.'], ...
                        nm, s(1), s(2), hw(1), hw(2));
                    return;
                end
                % Rows and columns of the reconstruction frame it shows
                rows = [max(1, off(1) + 1), min(hw(1), off(1) + s(1))];
                for q = 1:4
                    c1 = max(windows(q, 1), off(2) + 1);
                    c2 = min(windows(q, 2), off(2) + s(2));
                    if rows(1) > rows(2) || c1 > c2
                        err = sprintf(['%s does not show View%d (columns %d to %d of the reconstruction frame) at ' ...
                            'its position (row %d, column %d), so the target cannot be found there.'], ...
                            nm, q, windows(q, 1), windows(q, 2), off(1) + 1, off(2) + 1);
                        return;
                    end
                end
            end
            ok = true;
        end

        function src = reference_source(images_dir, roi_json)
            %% The reconstruction recording the cut images came from, or ''
            % The cut manifest names it (source); else the ROI file does
            % (reconstruction_path). Used to find where a calibration
            % recording with another frame sits.
            src = '';
            try
                mf = fullfile(images_dir, 'manifest.json');
                if exist(mf, 'file') == 2
                    m = rabbit_calibration.read_json(mf);
                    if isfield(m, 'source') && ~isempty(m.source)
                        src = char(m.source);
                    end
                end
                if isempty(src) && exist(roi_json, 'file') == 2
                    p = rabbit_stack_io.load_roi_json(roi_json, [], []);
                    src = char(p.reconstruction_path);
                end
            catch
                src = '';
            end
            if ~isempty(src) && ~isfolder(src) && exist(src, 'file') ~= 2
                src = '';
            end
        end

        function [place, err] = placement(rec_source, rec_hw, cal_path, roi_json, held)
            %% Where a calibration recording's frames sit in the reconstruction frame, if it can be measured
            % Same camera, not moved: the two frames differ only by the
            % camera's area of interest. Measured on the still pixels of up
            % to 30 frames of each and checked on the odd and the even
            % frames (rabbit_fov_position.measure). A cube recording and
            % the heart recording usually do not look alike enough (no
            % agreement on the reference rabbit data), so the window asks
            % for the position then
            % (rabbit_calibration_dialog.add_row). How much a wrong
            % position matters: a row error of d px moves the lens centre
            % by d px, about d / 8000 rad (0.007 degree per pixel) at the
            % stated focal length; a column error can move the target into
            % another tile's window.
            % Outputs:
            %   place.offset: [row column], 0-based, of the recording's
            %       top-left pixel in the reconstruction frame ([] = not known)
            %   place.source: 'measured', 'same frame' (same size, measured
            %       or not), 'cut folder', or '' (not known: ask)
            %   place.trusted, place.score, place.why: the measurement
            %   place.same_size: the recording has the reconstruction size
            %   place.note: one line for the window and the record
            %   err: why it cannot be used at all ('' when it can)
            %   roi_json (optional): when the measurement is not trusted and
            %       the ROI file lined this same recording up with the
            %       optical mapping recording in the region dialog, the
            %       position follows from the two line-ups there
            %       (offset_from_roi; place.source 'region dialog')
            if nargin < 4, roi_json = ''; end
            %   held (optional): the line-ups the app holds now (struct
            %       calibration_path, calibration_fov_mapping, fov_mapping),
            %       used when the ROI file has none for this recording (a
            %       loaded ROI file keeps the region dialog's typed line-up
            %       in the app only)
            if nargin < 5, held = []; end
            place = struct('offset', [], 'score', NaN, 'note', '', 'source', '', 'trusted', false, ...
                'why', '', 'same_size', false);
            err = '';
            [~, nm, ex] = fileparts(cal_path);
            nm = [nm ex];
            try
                s = rabbit_calibration.recording_size(cal_path);
            catch ME
                err = sprintf('Could not read %s: %s', nm, ME.message);
                return;
            end
            rec_hw = reshape(double(rec_hw), 1, []);
            place.same_size = isequal(s, rec_hw);
            if ~isempty(rec_source)
                txt = rabbit_stack_io.binning_mismatch(rabbit_stack_io.read_binning(rec_source), ...
                    rabbit_stack_io.read_binning(cal_path), 'calibration');
                if ~isempty(txt)
                    err = strrep(txt, 'optical mapping recording', 'reconstruction recording');
                    return;
                end
            end
            if isfolder(cal_path) && exist(fullfile(cal_path, 'cut_locations_per_view.json'), 'file') == 2
                % A view1-view4 cut folder: only the reconstruction frame itself
                if place.same_size
                    place.offset = [0 0];
                    place.source = 'cut folder';
                    place.note = 'the reconstruction frame (cut folder)';
                    try
                        cuts = rabbit_calibration.read_json(fullfile(cal_path, 'cut_locations_per_view.json'));
                        if isfield(cuts, 'placed')
                            place.note = 'placed by the cut from the region dialog''s line-up (not shifted again)';
                        end
                    catch
                    end
                else
                    err = sprintf(['%s is a cut folder of frames %dx%d and the reconstruction frames are %dx%d. ' ...
                        'Add the recording itself, so that its position can be set.'], nm, s(1), s(2), rec_hw(1), rec_hw(2));
                end
                return;
            end
            % The reference must be the recording the reconstruction images
            % were cut from, at their frame size
            if isempty(rec_source)
                place.why = 'the reconstruction recording was not found to compare with';
            else
                try
                    ref = rabbit_fov_position.sample_frames(rec_source);
                    if ~isequal([size(ref, 1) size(ref, 2)], rec_hw)
                        place.why = sprintf(['the reconstruction recording found (%s) has frames of %dx%d, not ' ...
                            'the %dx%d of the reconstruction images'], rec_source, size(ref, 1), size(ref, 2), ...
                            rec_hw(1), rec_hw(2));
                    else
                        est = rabbit_fov_position.measure(rabbit_fov_position.sample_frames(cal_path), ref);
                        place.trusted = est.trusted;
                        place.score = est.ncc;
                        place.why = est.why;
                        if est.trusted
                            place.offset = [est.off est.cols_off];
                            place.source = 'measured';
                        end
                    end
                catch ME
                    place.why = sprintf('frames could not be read to compare: %s', ME.message);
                end
            end
            if isempty(place.source) && (~isempty(roi_json) || ~isempty(held))
                % The region dialog asked this file's shift against the
                % optical mapping image; the calibration window needs it in
                % the reconstruction image. Both line-ups are in the ROI
                % file, so it is worked out rather than typed again (a visiting lab typed the OM shift here and the
                % calibration failed)
                off = [];
                if ~isempty(roi_json), off = rabbit_calibration.offset_from_roi(roi_json, cal_path); end
                if isempty(off) && ~isempty(held), off = rabbit_calibration.offset_from_roi(held, cal_path); end
                if ~isempty(off)
                    place.offset = off;
                    place.source = 'region dialog';
                    % Short, so the Frame position column shows it whole
                    place.note = sprintf('shifted %d px down, %d px right (from the region dialog''s line-ups)', off(1), off(2));
                    return;
                end
            end
            if strcmp(place.source, 'measured')
                if isequal(place.offset, [0 0]) && place.same_size
                    place.source = 'same frame';
                    place.note = sprintf('lines up with the reconstruction recording (checked by the app, score %.2f)', place.score);
                else
                    place.note = sprintf(['lined up by the app: shifted %d px down and %d px right in the ' ...
                        'reconstruction image (score %.2f)'], place.offset(1), place.offset(2), place.score);
                end
            end
        end

        function off = offset_from_roi(roi_json, cal_path)
            %% A calibration recording's top-left in the reconstruction frame, from the ROI file's two line-ups ([] if not there)
            % Both mappings give the optical mapping frame's top-left in the
            % other frame (rows, columns; 0-based). A pixel at p in the
            % optical mapping frame is at p + r in the reconstruction frame
            % and at p + c in the calibration frame, so the calibration's
            % top-left (its 0) is at r - c in the reconstruction frame.
            % Only for the calibration recording the ROI file names.
            off = [];
            if isstruct(roi_json)
                pl = roi_json;          % the line-ups the app holds (placement's held)
            else
                try
                    pl = rabbit_stack_io.load_roi_json(roi_json, [], []);
                catch
                    return;
                end
            end
            if ~isfield(pl, 'fov_mapping') || ~isfield(pl, 'calibration_fov_mapping'), return; end
            if ~isfield(pl, 'calibration_path') || isempty(pl.calibration_path) || ...
                    ~rabbit_stack_io.same_file(pl.calibration_path, cal_path)
                return;
            end
            cm = pl.calibration_fov_mapping;
            rm = pl.fov_mapping;
            ok = @(m) isstruct(m) && isfield(m, 'type') && ~strcmp(m.type, 'scale') && isfield(m, 'om_window_in_rec');
            if ~ok(cm) || ~ok(rm), return; end
            off = [double(rm.om_window_in_rec.off) - double(cm.om_window_in_rec.off), ...
                double(rabbit_cut_tiffs.cols_off_of(rm)) - double(rabbit_cut_tiffs.cols_off_of(cm))];
        end

        function err = check_roi_bounds(bounds, roi_json)
            %% Do the ROI file's regions, mapped across its FOV, match the tile bounds in use?
            % bounds: from tile_bounds, the cut manifest's when there is one.
            % The two are compared by tile column, so the ROI row order does
            % not matter; rounding of the mapping may leave one pixel.
            err = '';
            p = rabbit_stack_io.load_roi_json(roi_json, [], []);
            b = double(p.region_bounds_src(:, 1:4));
            if isfield(p, 'fov_mapping') && ~isempty(p.fov_mapping)
                b = rabbit_stack_io.map_bounds_across_fov(b, p.fov_mapping);
            end
            if size(b, 1) ~= 4
                err = sprintf('The ROI file gives %d regions, not four.', size(b, 1));
                return;
            end
            d = max(abs(sortrows(b, 2) - sortrows(double(bounds), 2)), [], 'all');
            if d > 1
                err = sprintf(['The regions in the ROI file are not the ones these reconstruction images were cut ' ...
                    'with (they differ by up to %d pixels). Choose the ROI file they were cut with, or cut them again.'], d);
            end
        end

        function x = read_json(path)
            %% A project JSON file, read as UTF-8
            x = jsondecode(fileread(path, 'Encoding', 'UTF-8'));
        end

        function w = tile_windows(bounds, width)
            %% Column windows of the four tiles, from the ROI columns
            % Left to right; each window reaches half way to the next tile,
            % so a target moved beyond the heart's box stays in its window.
            % w: 4x2 [first last], 1-based, inclusive.
            [~, o] = sort(bounds(:, 2));
            b = bounds(o, :);
            cut = round((b(1:3, 4) + b(2:4, 2)) / 2);
            w = [[1; cut + 1], [cut; width]];
        end

        function pp = tile_principal_points(windows, centre)
            %% Lens centre in each tile's own pixels (0-based, COLMAP and pyCamSet pixels)
            % The outer tiles are flipped left-right. A value outside the
            % tile is right: the tile is a crop far from the optical axis.
            pp = struct();
            for k = 1:4
                x = centre(1) - (windows(k, 1) - 1);
                if any(k == [1 4])
                    x = (windows(k, 2) - windows(k, 1)) - x;
                end
                pp.(rabbit_calibration.TILES{k}) = [x centre(2)];
            end
        end

        % =============================================================
        % 2. Preparing a calibration folder
        % =============================================================

        function id = next_id(root, stem)
            %% Next free calibration folder name: cal_<stem>, cal_<stem>_01, ...
            % A recording already named cal_... is not named cal_cal_...
            if startsWith(stem, 'cal_'), stem = stem(5:end); end
            id = ['cal_' stem];
            k = 0;
            while exist(fullfile(root, id), 'file') ~= 0
                k = k + 1;
                id = sprintf('cal_%s_%02d', stem, k);
            end
        end

        function [n_frames, H] = write_tiles(input, out_dir, windows, stop, place)
            %% Tile images of one recording: raw rows, outer tiles flipped left-right
            % input: a FITS file, multi-page TIFF or folder of frames
            % through rabbit_stack_io (rows as stored), or a cut folder
            % (view1 to view4 with cut_locations_per_view.json), whose crops
            % are put back into the same windows. stop: @() true to stop
            % between frames (analyse_om:Calibration:Cancelled).
            % place (optional): struct with offset [row column]
            % (0-based, the recording's top-left pixel in the reconstruction
            % frame) and frame_hw (the reconstruction frame). Each frame is
            % then put at that position in a frame of the reconstruction's
            % size, zero where the recording shows nothing, so the tiles,
            % their lens centre and the rays are those of the reconstruction
            % frame (check_frames, placement).
            if nargin < 4 || isempty(stop), stop = @() false; end
            if nargin < 5, place = []; end
            if isfolder(input) && exist(fullfile(input, 'cut_locations_per_view.json'), 'file') == 2
                [n_frames, H] = rabbit_calibration.write_tiles_from_cut(input, out_dir, windows, stop);
                return;
            end
            stk = rabbit_stack_io.load_stack_native(input);
            [h, w, n_frames] = size(stk.stack);
            if isempty(place)
                H = h; W = w; off = [0 0];
                if W ~= windows(4, 2)
                    error('analyse_om:Calibration:Width', ['The calibration frames are %d pixels wide and the regions ' ...
                        'were drawn on frames %d wide. The views would not line up.'], W, windows(4, 2));
                end
            else
                H = place.frame_hw(1); W = place.frame_hw(2); off = reshape(double(place.offset), 1, 2);
            end
            % Rows and columns of the recording that land in the frame
            rs = max(1, 1 - off(1)):min(h, H - off(1));
            cs = max(1, 1 - off(2)):min(w, W - off(2));
            whole = isequal([H W], [h w]) && isequal(off, [0 0]);
            for k = 1:4
                d = fullfile(out_dir, rabbit_calibration.TILES{k});
                if ~isfolder(d), mkdir(d); end
                for f = 1:n_frames
                    rabbit_calibration.stop_check(stop);
                    if whole
                        frame = stk.stack(:, :, f);
                    else
                        frame = zeros(H, W, 'like', stk.stack);
                        frame(rs + off(1), cs + off(2)) = stk.stack(rs, cs, f);
                    end
                    im = frame(:, windows(k, 1):windows(k, 2));
                    if any(k == [1 4]), im = fliplr(im); end
                    imwrite(uint16(im), fullfile(d, sprintf('frame_%04d.tiff', f - 1)), 'tiff', 'Compression', 'none');
                end
            end
        end

        function stop_check(stop)
            %% Leave the tile loops when the user cancelled
            if stop()
                error('analyse_om:Calibration:Cancelled', 'The calibration was cancelled.');
            end
        end

        function [n_frames, H] = write_tiles_from_cut(folder, out_dir, windows, stop)
            %% A cut folder (view1 to view4 with cut_locations_per_view.json) as tiles in the windows above
            % The folder's view names are its display: view1 far right and
            % view4 far left of the mirrored panel, so view1 is the left
            % tile of the frame (tile1), view2 and view3 the middle ones and
            % view4 the right one. Its crops are per-crop stretched to 8
            % bits, which the detector accepts, and already flipped.
            cuts = rabbit_calibration.read_json(fullfile(folder, 'cut_locations_per_view.json'));
            W = windows(4, 2);
            hw = rabbit_calibration.cut_size(folder);
            H = hw(1);    % every tile the same height, though a view's margins may be a pixel off
            n_frames = 0;
            for k = 1:4
                v = sprintf('view%d', k);
                c = cuts(strcmp({cuts.view}, v));
                files = dir(fullfile(folder, v, '*.tiff'));
                files = sort({files.name});
                info = imfinfo(fullfile(folder, v, files{1}));
                % the crop's first column in the (flipped) tile: the cut's
                % left margin counts from the left of the flipped frame
                if any(k == [1 4])
                    src1 = W - c.left - info.Width + 1;
                else
                    src1 = c.left + 1;
                end
                d = fullfile(out_dir, rabbit_calibration.TILES{k});
                if ~isfolder(d), mkdir(d); end
                if k > 1 && numel(files) ~= n_frames
                    error('analyse_om:Calibration:CutFrames', 'The views of %s have different numbers of frames.', folder);
                end
                n_frames = numel(files);
                for f = 1:n_frames
                    rabbit_calibration.stop_check(stop);
                    crop = imread(fullfile(folder, v, files{f}));
                    if any(k == [1 4])
                        x0 = windows(k, 2) - (src1 + info.Width - 1);
                    else
                        x0 = src1 - windows(k, 1);
                    end
                    tw = windows(k, 2) - windows(k, 1) + 1;
                    tile = zeros(H, tw, 'uint16');
                    xs = max(0, x0); xe = min(tw, x0 + info.Width);
                    n_rows = min(info.Height, H - c.top);
                    part = crop(1:n_rows, xs - x0 + 1:xe - x0);
                    if isa(part, 'uint8')
                        part = uint16(part) * 257;   % 8-bit crops to the 16-bit range
                    else
                        part = uint16(part);         % the app's own cut keeps the recording's values
                    end
                    tile(c.top + 1:c.top + n_rows, xs + 1:xe) = part;
                    imwrite(tile, fullfile(d, sprintf('frame_%04d.tiff', f - 1)), 'tiff', 'Compression', 'none');
                end
            end
        end

        function job = make_job(spec, out_dir, tile_root, n_frames, checkout, commit)
            %% The job file rabbit_pycamset_calibrate.py reads
            r = spec.recordings;
            recs = struct('name', {}, 'role', {}, 'n_frames', {}, 'tile_dir', {}, 'target', {});
            for k = 1:numel(r)
                [~, nm] = fileparts(r(k).path);
                if isempty(nm), [~, nm] = fileparts(fileparts(r(k).path)); end
                recs(end+1) = struct('name', nm, 'role', r(k).role, 'n_frames', n_frames(k), ...
                    'tile_dir', fullfile(tile_root, sprintf('rec%02d', k)), ...
                    'target', struct('type', r(k).type, 'n_points', r(k).n_points, 'edge_mm', r(k).edge_mm)); %#ok<AGROW>
            end
            job = struct('output_dir', out_dir, 'pycamset_checkout', checkout, 'pycamset_commit', commit, ...
                'pixel_pitch_um', spec.pixel_pitch_um, ...
                'threads', spec.threads, 'lens', struct('focal_px', spec.focal_px, 'k1', spec.k1, ...
                'source', 'stated, as the sparse model recipe'), ...
                'lens_centre_frame_px', spec.lens_centre_frame_px, ...
                'tile_pp', rabbit_calibration.tile_principal_points(spec.windows, spec.lens_centre_frame_px));
            % Binarise the tiles of the recordings the pre-processing is
            % for; pyCamSet then leaves its own rescale and gamma off for them
            % (on a binary image they change nothing)
            pre = [];
            if isfield(spec, 'preprocess'), pre = spec.preprocess; end
            for k = 1:numel(recs)
                recs(k).preprocessed = rabbit_calibration.preprocess_tiles(recs(k).tile_dir, recs(k).target.type, pre);
            end
            job.preprocess = pre;
            % a cell, so that one recording is still written as a JSON list
            job.recordings = num2cell(recs);
        end

        function done = preprocess_tiles(tile_dir, target_type, pre)
            %% Binarise a recording's tile images in place, when pre is for its target
            % The tiles are this calibration's own copies (write_tiles); the
            % recording is not changed. done: true when they were binarised.
            done = false;
            if isempty(pre) || ~isstruct(pre) || ~strcmp(pre.type, 'sauvola') || ...
                    ~any(strcmp(target_type, cellstr(pre.targets))) || ~isfolder(tile_dir)
                return;
            end
            for t = 1:4
                d = fullfile(tile_dir, rabbit_calibration.TILES{t});
                files = dir(fullfile(d, '*.tif*'));
                for f = 1:numel(files)
                    p = fullfile(d, files(f).name);
                    imwrite(rabbit_sauvola(imread(p), pre.window, pre.k), p, 'tiff', 'Compression', 'none');
                end
            end
            done = true;
        end

        % =============================================================
        % 3. Reading a result and deciding what it may claim
        % =============================================================

        function [ok, err, c] = read_result(dir_path)
            %% calibration.json, checked for shape and finite numbers
            % (its messages name the cameras View1-View4: view_words)
            [ok, err, c] = rabbit_calibration.read_result_checked(dir_path);
            err = rabbit_calibration.view_words(err);
        end

        function t = view_words(t)
            %% The cameras' folder names tile1-tile4 as the app calls them: View1-View4
            t = regexprep(t, '\<tile([1-4])\>', 'View$1');
            % No "tile" in what the user reads; a folder in a
            % path (the tiles folder of a calibration) is left as it is
            t = regexprep(t, '(?<![\\/])\<tiles\>(?![\\/])', 'views');
            t = regexprep(t, '(?<![\\/])\<tile\>(?![\\/])', 'view');
        end

        function [ok, err, c] = read_result_checked(dir_path)
            %% read_result's checks (camera names as in calibration.json)
            ok = false; err = ''; c = [];
            p = fullfile(dir_path, 'calibration.json');
            if exist(p, 'file') ~= 2
                e = fullfile(dir_path, 'calibration_error.txt');
                if exist(e, 'file') == 2
                    err = strtrim(fileread(e, 'Encoding', 'UTF-8'));
                else
                    err = 'The calibration wrote no result.';
                end
                return;
            end
            try
                c = rabbit_calibration.read_json(p);
            catch ME
                err = sprintf('calibration.json cannot be read: %s', ME.message); c = []; return;
            end
            need = {'schema', 'lens', 'target', 'cameras', 'rig', 'residual', 'observations', 'holdout'};
            if ~isstruct(c) || ~isscalar(c) || ~all(isfield(c, need))
                err = 'calibration.json is not a calibration result.'; c = []; return;
            end
            if ~strcmp(c.schema, rabbit_calibration.RESULT_SCHEMA)
                err = sprintf('calibration.json has the format %s, not %s.', c.schema, rabbit_calibration.RESULT_SCHEMA);
                c = []; return;
            end
            cams = c.cameras;
            if iscell(cams), cams = [cams{:}]; end
            if numel(cams) ~= 4 || ~isequal({cams.tile}, reshape(rabbit_calibration.TILES, size({cams.tile})))
                err = 'calibration.json does not hold the four views.'; c = []; return;
            end
            for k = 1:4
                x = [cams(k).centre_mm(:); cams(k).R_world_to_cam(:); cams(k).rmse_px];
                if ~isnumeric(x) || any(~isfinite(x)) || abs(cams(k).det_R - 1) > 1e-6
                    err = sprintf('calibration.json: %s has unusable numbers.', cams(k).tile); c = []; return;
                end
            end
            c.cameras = reshape(cams, 1, []);
            if isempty(c.holdout)
                c.holdout = struct('name', {}, 'frames_used', {}, 'scale_error_percent', {});
            elseif iscell(c.holdout)
                c.holdout = rabbit_calibration.same_fields(c.holdout);
            end
            ok = true;
        end

        function out = same_fields(cells)
            %% Struct array from structs that may lack fields (a check with no frames)
            names = {};
            for k = 1:numel(cells), names = union(names, fieldnames(cells{k})); end
            for k = 1:numel(cells)
                for n = 1:numel(names)
                    if ~isfield(cells{k}, names{n}), cells{k}.(names{n}) = []; end
                end
                cells{k} = orderfields(cells{k}, sort(names));
            end
            out = [cells{:}];
        end

        function v = verdict(c)
            %% PASSED, WARNED or FAILED, and what the calibration may be used for
            % metric_allowed: a run may report mm from it. FAILED never;
            % WARNED only when the sole warning is a held-out check that
            % could not be made, which the record states.
            g = rabbit_calibration.GATE;
            v = struct('schema', rabbit_calibration.VERDICT_SCHEMA, 'status', 'PASSED', ...
                'metric_allowed', true, 'failures', {{}}, 'warnings', {{}});
            function fail(t), v.failures{end+1} = rabbit_calibration.view_words(t); end
            function warn(t), v.warnings{end+1} = rabbit_calibration.view_words(t); end
            for k = 1:4
                q = c.cameras(k);
                if q.rmse_px > g.max_view_rmse_px
                    fail(sprintf('%s: reprojection error %.2f px is above %.2f px.', q.tile, q.rmse_px, g.max_view_rmse_px));
                end
                if q.points < g.min_view_points
                    fail(sprintf('%s: only %d target points (needs %d).', q.tile, q.points, g.min_view_points));
                end
                if q.images < g.min_view_images
                    fail(sprintf('%s: the target was usable in only %d frames (needs %d).', q.tile, q.images, g.min_view_images));
                end
            end
            if c.observations.kept_fraction < g.min_kept_fraction
                fail(sprintf('Only %.0f %% of the target points fit the rig (needs %.0f %%).', ...
                    100 * c.observations.kept_fraction, 100 * g.min_kept_fraction));
            end
            used = 0;
            for k = 1:numel(c.holdout)
                h = c.holdout(k);
                rejected = rabbit_calibration.opt(h, 'frames_rejected', 0);
                seen = rabbit_calibration.opt(h, 'frames_used', 0) + rejected;
                if seen > 0 && rejected / seen > g.max_holdout_rejected_fraction
                    fail(sprintf('%s: %d of %d frames were left out of the distance check (limit %.0f %%).', ...
                        h.name, rejected, seen, 100 * g.max_holdout_rejected_fraction));
                end
                if isempty(h.frames_used) || h.frames_used < g.min_holdout_frames
                    warn(sprintf('%s: too few frames showed target points in two views for a distance check.', h.name));
                    continue;
                end
                used = used + 1;
                if abs(h.scale_error_percent) > g.max_holdout_error_percent
                    fail(sprintf('%s: distances differ by %.2f %% from the stated size of that target (limit %.1f %%).', ...
                        h.name, h.scale_error_percent, g.max_holdout_error_percent));
                end
                if h.residual_mm_median > g.max_holdout_residual_mm
                    fail(sprintf('%s: the target points are %.2f mm from their true shape (limit %.1f mm).', ...
                        h.name, h.residual_mm_median, g.max_holdout_residual_mm));
                end
            end
            if used == 0
                warn(['No held-out recording gave a distance check, so nothing independent of the solve ' ...
                    'confirms the distances.']);
            end
            if ~isempty(v.failures)
                v.status = 'FAILED'; v.metric_allowed = false;
            elseif ~isempty(v.warnings)
                v.status = 'WARNED';
            end
            v.size_note = sprintf(['All distances rest on the stated cube edge of %g mm; the held-out checks ' ...
                'test the rig against that statement, they do not measure the cube.'], c.target.edge_mm);
        end

        function txt = summary_lines(c, v, spec)
            %% Plain text of a calibration for the dialog and the run record
            % spec (optional): the calibration's spec.json, for the nominal
            % lens it names
            if nargin < 3, spec = []; end
            txt = {sprintf('Verdict: %s. %s', v.status, rabbit_calibration.ternary(v.metric_allowed, ...
                'Runs may report mm from this calibration.', 'Runs cannot report mm from this calibration.'))};
            txt{end+1} = sprintf('Target: %s, %d squares, %g mm edge. %s', c.target.type, c.target.n_points, ...
                c.target.edge_mm, v.size_note);
            pre = rabbit_calibration.opt(c, 'preprocess', []);
            % Only when a recording of the targets it is for was used
            used = {};
            try
                tg = c.target; if ~isempty(tg) && isfield(tg, 'type'), used{end + 1} = tg.type; end
                hs = c.holdout; if iscell(hs), hs = [hs{:}]; end
                for q = 1:numel(hs), if isfield(hs(q), 'target') && isfield(hs(q).target, 'type'), used{end + 1} = hs(q).target.type; end, end
            catch
                used = {};
            end
            if isstruct(pre) && strcmp(pre.type, 'sauvola') && ~isempty(used) && ~any(ismember(used, cellstr(pre.targets)))
                txt{end+1} = 'Pre-processing: none (no recording of a target it is for).';
            elseif isstruct(pre) && strcmp(pre.type, 'sauvola')
                txt{end+1} = sprintf(['Pre-processing: Sauvola binarisation (window %d px, k %g) of the %s ' ...
                    'recordings before detection.'], pre.window, pre.k, strjoin(cellstr(pre.targets), ', '));
            else
                txt{end+1} = 'Pre-processing: none.';
            end
            txt{end+1} = sprintf('Reprojection error %.2f px (median %.2f px), %.0f %% of %d points kept.', ...
                c.residual.rmse_px, c.residual.median_px, 100 * c.observations.kept_fraction, c.observations.detected);
            for k = 1:4
                q = c.cameras(k);
                % What is measured and what follows from the stated focal
                % length (um per pixel, as every pixel size)
                txt{end+1} = sprintf(['%s: %.2f px, %d points in %d frames, %.1f %sm/px at the cube (measured); ' ...
                    '%.0f mm away (follows from the stated focal length, not measured).'], ...
                    rabbit_calibration.view_words(q.tile), q.rmse_px, q.points, q.images, 1000 * q.mm_per_px_at_target, ...
                    char(181), q.depth_at_target_mm); %#ok<AGROW>
            end
            for k = 1:numel(c.holdout)
                h = c.holdout(k);
                if isempty(h.frames_used) || h.frames_used == 0
                    txt{end+1} = sprintf('Held out %s: no frames with the target in two views.', h.name); %#ok<AGROW>
                else
                    % the signed value with a true minus sign
                    txt{end+1} = sprintf('Held out %s: distances %s %% +/- %.2f %% (%d frames, %d left out, %.2f mm shape residual).', ...
                        h.name, rabbit_reconstruction_tab.signed_text(h.scale_error_percent, 2), h.scale_se_percent, h.frames_used, ...
                        rabbit_calibration.opt(h, 'frames_rejected', 0), h.residual_mm_median); %#ok<AGROW>
                end
            end
            if isfield(c, 'imported_camset')
                % A camera set made in the pyCamSet GUI: its
                % cameras were checked here, not solved
                txt{end+1} = sprintf(['Cameras from the linked pyCamSet camera set %s, as they are: the app solved ' ...
                    'only the target poses to check them. Focal lengths %s px (each camera its own); a run compares ' ...
                    'them with the sparse model''s.'], c.imported_camset.path, ...
                    strjoin(arrayfun(@(q) sprintf('%.0f', q), [c.cameras.focal_px], 'UniformOutput', false), ', '));
            else
                % The solve's focal length in mm, and the spec's lens
                % named as the nominal one
                pitch = rabbit_calibration.opt(c, 'pixel_pitch_um', 6.5);
                txt{end+1} = sprintf(['Focal length %g px is a stated value, not a result: see the lens profile in ' ...
                    'calibration.json. The solve uses %g px %s %g %sm = %.1f mm.'], c.lens.focal_px, ...
                    c.lens.focal_px, char(215), pitch, char(181), c.lens.focal_px * pitch / 1000);
                if isstruct(spec) && isfield(spec, 'lens_focal_mm') && isnumeric(spec.lens_focal_mm) && ...
                        isscalar(spec.lens_focal_mm)
                    txt{end} = sprintf('%s The spec''s lens_focal_mm %g is the nominal lens.', txt{end}, spec.lens_focal_mm);
                    % Why the stated value is not the nominal lens's: the
                    % sparse build's reason (rabbit_sfm_build)
                    if c.lens.focal_px == 8000
                        txt{end} = sprintf(['%s Nominal %g mm at %g %sm is %.0f px; 8000 px is the sparse build''s ' ...
                            'round value inside an earlier self-calibration of the rig (7740%s8218 px), as a 50 mm lens ' ...
                            'focused at the heart images a little longer than 50 mm.'], txt{end}, spec.lens_focal_mm, ...
                            pitch, char(181), 1000 * spec.lens_focal_mm / pitch, char(8211));
                    end
                end
                % The focal sweep's ends are not an uncertainty interval
                try
                    lo = rabbit_calibration.left_out(c, '');
                    f = lo.focal_length;
                catch
                    f = struct('estimated', false);   % a record without what the sweep needs
                end
                if f.estimated && ~isempty(f.per_view_at_target)
                    fs = rabbit_reconstruction_tab.focal_sweep_words(f.sweep_px, f.rmse_px, ...
                        min([f.per_view_at_target.min_percent]), max([f.per_view_at_target.max_percent]));
                    txt{end+1} = [upper(fs(1)) fs(2:end) '.'];
                end
            end
            txt = [txt, v.failures, v.warnings];
        end

        function c = text_list(x)
            %% 1xN cell of the strings of a JSON list (JSON gives [] for an empty one)
            c = {};
            if ~isempty(x), c = reshape(cellstr(x), 1, []); end
        end

        function txt = saved_lines(dir_path)
            %% What a calibration folder's verdict.json says; {} when it has none
            txt = {};
            p = fullfile(dir_path, 'verdict.json');
            if exist(p, 'file') ~= 2, return; end
            try
                v = rabbit_calibration.read_json(p);
                v.failures = rabbit_calibration.text_list(v.failures);
                v.warnings = rabbit_calibration.text_list(v.warnings);
            catch
                txt = {'verdict.json cannot be read.'};
                return;
            end
            [ok, ~, c] = rabbit_calibration.read_result(dir_path);
            if ok
                % with the spec, for its nominal lens
                spec = [];
                try
                    spec = rabbit_calibration.read_json(fullfile(dir_path, 'spec.json'));
                catch
                    spec = [];
                end
                txt = rabbit_calibration.summary_lines(c, v, spec);
            else
                txt = [{sprintf('Verdict: %s.', v.status)}, v.failures, v.warnings];
            end
            % A failed calibration names the frame positions it used: a
            % wrong one fails the held-out checks without other sign
            if ~strcmp(v.status, 'PASSED')
                try
                    s = rabbit_calibration.read_json(fullfile(dir_path, 'spec.json'));
                    r = s.recordings;
                    if iscell(r), r = rabbit_calibration.same_fields(r); end
                    typed_any = false;
                    for k = 1:numel(r)
                        if isfield(r(k), 'offset_source') && strcmp(r(k).offset_source, 'typed'), typed_any = true; end
                        if isfield(r(k), 'frame_offset') && numel(r(k).frame_offset) == 2
                            txt{end+1} = rabbit_calibration.position_line(r(k)); %#ok<AGROW>
                        end
                    end
                    if typed_any
                        % Say which is the likely cause
                        txt{end+1} = ['A typed position is the most likely cause: this window asks the shift in the ' ...
                            'reconstruction image, the region dialog in the optical mapping image. Check it with Position....'];
                    end
                catch
                end
            end
        end

        function t = position_line(rec)
            %% "Frame position used for <file>: 0 px down, 0 px right in the reconstruction image: <how>. If it is wrong, ..."
            % rec: a spec recording (path, frame_offset, offset_note). One
            % sentence for the calibration window right after Run
            % (run_calibration) and for the saved lines.
            [~, nm, ex] = fileparts(char(rec.path));
            how = '';
            if isfield(rec, 'offset_note') && ~isempty(rec.offset_note), how = [': ' char(rec.offset_note)]; end
            t = sprintf(['Frame position used for %s%s: %d px down, %d px right in the ' ...
                'reconstruction image%s. If it is wrong, correct it with Position... and calibrate again.'], ...
                nm, ex, rec.frame_offset(1), rec.frame_offset(2), how);
        end

        function x = opt(s, name, default)
            if isfield(s, name) && ~isempty(s.(name)), x = s.(name); else, x = default; end
        end

        function t = ternary(tf, a, b)
            if tf, t = a; else, t = b; end
        end

        function L = list(root)
            %% The calibrations in a folder, newest name last
            L = struct('id', {}, 'dir', {}, 'status', {}, 'metric_allowed', {}, 'label', {});
            if ~isfolder(root), return; end
            d = dir(fullfile(root, 'cal_*'));
            d = d([d.isdir]);
            names = sort({d.name});
            for k = 1:numel(names)
                p = fullfile(root, names{k});
                s = 'UNREADABLE'; m = false;
                try
                    v = rabbit_calibration.read_json(fullfile(p, 'verdict.json'));
                    if strcmp(v.schema, rabbit_calibration.VERDICT_SCHEMA) && ...
                            any(strcmp(v.status, {'PASSED', 'WARNED', 'FAILED'}))
                        s = v.status; m = islogical(v.metric_allowed) && isscalar(v.metric_allowed) && v.metric_allowed;
                    end
                catch
                    s = 'UNREADABLE'; m = false;
                end
                L(end+1) = struct('id', names{k}, 'dir', p, 'status', s, 'metric_allowed', m, ...
                    'label', sprintf('%s (%s)', names{k}, s)); %#ok<AGROW>
            end
        end

        % =============================================================
        % 4. The sparse model against the calibrated rig
        % =============================================================

        function [C, A, frames] = model_rig(images, view_prefix)
            %% Camera centres and axes of a sparse model, per frame and tile
            % view_prefix: 1x4 image-name prefixes, in tile order. Frames
            % with all four tiles registered only. C: Nx3x4; A: Nx3x4 is the
            % ray through each camera's principal point, in the world.
            %#ok<*AGROW>
            ids = cell2mat(keys(images));
            tile = zeros(1, numel(ids)); frame = zeros(1, numel(ids));
            for k = 1:numel(ids)
                im = images(ids(k));
                for t = 1:4
                    if startsWith(im.name, view_prefix{t})
                        tile(k) = t;
                        tok = regexp(im.name(numel(view_prefix{t}) + 1:end), '(\d+)', 'tokens', 'once');
                        if ~isempty(tok), frame(k) = str2double(tok{1}); end
                    end
                end
            end
            u = unique(frame(tile > 0));
            C = []; A = []; frames = [];
            for f = u
                sel = find(frame == f & tile > 0);
                if numel(unique(tile(sel))) ~= 4, continue; end
                row_c = zeros(1, 3, 4); row_a = zeros(1, 3, 4);
                for k = sel
                    im = images(ids(k));
                    R = rabbit_calibration.quat_to_rot(im.qvec);
                    row_c(1, :, tile(k)) = -(R' * im.tvec(:))';
                    row_a(1, :, tile(k)) = R(3, :);
                end
                C = cat(1, C, row_c); A = cat(1, A, row_a);
                frames(end+1) = f;
            end
        end

        function R = quat_to_rot(q)
            %% COLMAP quaternion (w x y z) to a rotation matrix
            q = q(:) / norm(q);
            w = q(1); x = q(2); y = q(3); z = q(4);
            R = [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y); ...
                2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x); ...
                2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)];
        end

        function [s, res] = fit_similarity(a, b)
            %% Umeyama (1991): s, R, t minimising |b - (s R a + t)|; res is the Nx3 misfit
            ma = mean(a, 1); mb = mean(b, 1);
            A = a - ma; B = b - mb;
            [U, S, V] = svd(B' * A / size(a, 1));
            D = eye(3);
            if det(U) * det(V) < 0, D(3, 3) = -1; end
            R = U * D * V';
            s = trace(S * D) / mean(sum(A .^ 2, 2));
            res = B - s * (R * A')';
        end

        function m = compare_rig(C, A, c, tile_centre_px)
            %% How the sparse rig agrees with the calibrated one
            % C, A: from model_rig (model units); c: the calibration;
            % tile_centre_px: 4x2 pixel of each model camera's principal
            % point in the calibration's tile (0-based) -- the model's
            % cameras look through the tile centre, the calibration's
            % through the lens centre, so rays are compared at one pixel.
            n = size(C, 1);
            cal = reshape([c.cameras.centre_mm], 3, 4)';
            s = zeros(n, 1); res = zeros(n, 4);
            base = nchoosek(1:4, 2);
            ratio = zeros(n, size(base, 1));
            ang = zeros(n, size(base, 1));
            rays = zeros(4, 3);
            for k = 1:4
                q = c.cameras(k);
                d = [(tile_centre_px(k, :) - q.pp_tile_px(:)') / q.focal_px, 1]';
                r = q.R_world_to_cam' * d;
                rays(k, :) = r' / norm(r);
            end
            for i = 1:n
                M = squeeze(C(i, :, :))';   % 4x3 centres of this frame
                [s(i), e] = rabbit_calibration.fit_similarity(M, cal);
                res(i, :) = sqrt(sum(e .^ 2, 2))';
                for j = 1:size(base, 1)
                    p = base(j, :);
                    ratio(i, j) = norm(cal(p(1), :) - cal(p(2), :)) / norm(M(p(1), :) - M(p(2), :));
                    a1 = squeeze(A(i, :, p(1)))'; a2 = squeeze(A(i, :, p(2)))';
                    ang_model = acosd(max(-1, min(1, a1' * a2)));
                    ang_cal = acosd(max(-1, min(1, rays(p(1), :) * rays(p(2), :)')));
                    ang(i, j) = ang_model - ang_cal;
                end
            end
            mean_base = mean(sqrt(sum((cal(base(:, 1), :) - cal(base(:, 2), :)) .^ 2, 2)));
            rb = median(ratio, 1);
            m = struct('frames', n, 'scale_mm_per_unit', median(s), ...
                'scale_frame_spread_percent', 100 * std(s) / median(s), ...
                'centre_residual_mm', median(res, 1), ...
                'centre_residual_percent', 100 * median(res, 1) / mean_base, ...
                'baseline_ratio_mm_per_unit', rb, ...
                'baseline_spread_percent', 100 * std(rb) / mean(rb), ...
                'angle_difference_deg', median(ang, 1), ...
                'pairs', {arrayfun(@(a, b) sprintf('%d-%d', a, b), base(:, 1)', base(:, 2)', 'UniformOutput', false)});
            m.holdout_term_percent = rabbit_calibration.holdout_term(c);
            % NaN (null in the record) when no held-out check was made
            m.scale_uncertainty_percent = sqrt((m.baseline_spread_percent / sqrt(numel(rb))) ^ 2 + ...
                m.holdout_term_percent ^ 2);
        end

        function e = holdout_term(c)
            %% The held-out part of the scale uncertainty in percent; NaN when no check was made
            % Per check the error and its standard error together, so a
            % lucky near-zero error keeps its spread; the largest check
            % counts. A check with too few frames is no check.
            e = NaN;
            for k = 1:numel(c.holdout)
                h = c.holdout(k);
                if isempty(h.frames_used) || h.frames_used < rabbit_calibration.GATE.min_holdout_frames
                    continue;
                end
                t = hypot(h.scale_error_percent, rabbit_calibration.opt(h, 'scale_se_percent', NaN));
                if isfinite(t), e = max(e, t, 'omitnan'); end
            end
        end

        function t = uncertainty_status(x)
            %% What a scale uncertainty value covers, for the records
            if isnumeric(x) && isscalar(x) && isfinite(x)
                t = 'covers the camera baselines and the held-out distance checks only';
            else
                t = ['not estimated: no held-out recording gave a distance check, so nothing independent ' ...
                    'of the solve tests the scale'];
            end
        end

        function e = focal_effect(c, tile, depth_mm, centre_px)
            %% How mm per pixel moves with the stated focal length, for one tile
            % depth_mm: distance of the surface from that camera at the
            % stated focal length, along the model's axis, which goes through
            % the tile pixel centre_px. Each sweep solve gives the distance to
            % the cube along the calibration's axis, through the lens centre;
            % these differ by about 5.7 degrees on the outer tiles, so the
            % surface is brought onto the calibration's axis first. It then
            % stays at its offset from the cube, which is close to true for
            % these long, narrow views, and not a heart run at that focal
            % length. depth_mm [] means at the cube itself. Empty for an
            % older calibration.
            e = [];
            if ~isfield(c, 'focal_sweep'), return; end
            f = c.focal_sweep.focal_px(:);
            z = c.focal_sweep.depth_mm(:, tile);
            [~, i0] = min(abs(f - c.lens.focal_px));
            if isempty(depth_mm)
                depth_mm = z(i0);
            else
                off = (centre_px(:)' - c.cameras(tile).pp_tile_px(:)') / c.lens.focal_px;
                depth_mm = depth_mm / sqrt(1 + sum(off .^ 2));
            end
            mm = (z - (z(i0) - depth_mm)) ./ f;
            change = 100 * (mm / mm(i0) - 1);
            e = struct('focal_px', f, 'change_percent', change, 'min_percent', min(change), 'max_percent', max(change));
        end

        function s = left_out(c, size_source)
            %% What a scale uncertainty does not include, for the records a later step reads
            s = struct();
            s.cube_size = struct('estimated', false, 'stated_edge_mm', c.target.edge_mm, 'edge_from', size_source, ...
                'note', ['Print and folding tolerance of the cube is unmeasured and is not in the uncertainty. ' ...
                'All distances scale with the stated edge.']);
            f = struct('estimated', isfield(c, 'focal_sweep'), 'stated_focal_px', c.lens.focal_px, ...
                'sweep_px', [], 'rmse_px', [], 'per_view_at_target', [], ...
                'derived', 'not available: this calibration has no focal sweep');
            if f.estimated
                f.sweep_px = c.focal_sweep.focal_px(:)';
                f.rmse_px = c.focal_sweep.rmse_px(:)';
                f.derived = ['The rig was solved again at each focal length with the lens held, and mm per pixel at the ' ...
                    'cube taken as distance / focal length. The focal length is stated, not measured: the reprojection ' ...
                    'error hardly changes across this range.'];
                v = struct('tile', {}, 'min_percent', {}, 'max_percent', {});
                for k = 1:4
                    e = rabbit_calibration.focal_effect(c, k, [], []);
                    v(end+1) = struct('tile', rabbit_calibration.TILES{k}, 'min_percent', e.min_percent, ...
                        'max_percent', e.max_percent);
                end
                f.per_view_at_target = v;
            end
            s.focal_length = f;
        end

        function f = model_focals(images, cameras, view_prefix)
            %% Focal lengths in the model's own cameras, per view prefix
            % What the build ended with, which is not the recipe's prior
            % when the build refined it. Both values of a two-focal camera.
            two = {'PINHOLE', 'OPENCV', 'OPENCV_FISHEYE', 'FULL_OPENCV'};
            f = [];
            ids = cell2mat(keys(images));
            for t = 1:numel(view_prefix)
                seen = [];
                for k = 1:numel(ids)
                    im = images(ids(k));
                    if startsWith(im.name, view_prefix{t}) && ~any(seen == im.camera_id)
                        seen(end+1) = im.camera_id;
                        cm = cameras(im.camera_id);
                        f = [f, reshape(cm.params(1:1 + any(strcmp(cm.model, two))), 1, [])];
                    end
                end
            end
        end

        function [apply, why] = rig_gates(m, model_focal, c)
            %% May this run take its scale from the comparison? why lists every reason not to
            % model_focal: the focal lengths in the model's cameras
            g = rabbit_calibration.RIG_GATE;
            why = {};
            % Each calibrated camera's own focal length (a linked camera set
            % may hold four different ones), and its fy where it
            % has one, against the sparse model's: every model view against
            % the calibration's median, and every calibrated value against
            % the model's median, so one view off on either side is caught
            % without four calibrated cameras being tested against each other
            cf = c.lens.focal_px;
            if isfield(c.cameras, 'focal_px'), cf = [c.cameras.focal_px]; end
            if isfield(c.cameras, 'focal_px_y')
                fy = {c.cameras.focal_px_y};
                fy = [fy{~cellfun(@isempty, fy)}];
                cf = [cf(:)' fy(:)'];
            end
            mf = median(model_focal(:));
            mc = median(cf(:));
            [d1, w1] = max(100 * abs(model_focal(:)' - mc) / mc);
            [d2, w2] = max(100 * abs(mf - cf(:)') ./ cf(:)');
            if max(d1, d2) > g.max_focal_difference_percent
                if d1 >= d2
                    pair = [model_focal(w1), mc];
                else
                    pair = [mf, cf(w2)];
                end
                why{end+1} = sprintf(['The sparse model has a focal length of %g px and the calibration %g px. The ' ...
                    'camera distance follows the focal length, so the two rigs cannot be compared.'], ...
                    pair(1), pair(2));
            end
            if max(m.centre_residual_percent) > g.max_centre_residual_percent
                why{end+1} = sprintf(['A camera of the sparse rig is %.1f %% of the rig''s size from the ' ...
                    'calibrated one (limit %.1f %%): the camera or a mirror may have moved between the ' ...
                    'recording and the calibration.'], max(m.centre_residual_percent), g.max_centre_residual_percent);
            end
            if max(abs(m.angle_difference_deg)) > g.max_angle_difference_deg
                why{end+1} = sprintf(['An angle between two views differs by %.2f degrees from the calibration ' ...
                    '(limit %.1f): the camera or a mirror may have moved.'], ...
                    max(abs(m.angle_difference_deg)), g.max_angle_difference_deg);
            end
            if m.baseline_spread_percent > g.max_baseline_spread_percent
                why{end+1} = sprintf(['The distances between the cameras give scales that differ by %.1f %% ' ...
                    '(limit %.1f %%).'], m.baseline_spread_percent, g.max_baseline_spread_percent);
            end
            apply = isempty(why);
        end

        function [r, tc] = apply_to_model(R, stage_dir, cal_dir, colmap_exe, run_cmd, reader, note)
            %% Compare the built model with the calibration, and scale it to mm if allowed
            % A model that fails a gate stays in model units, and
            % stage_dir/metric_scale.json says why: the run goes on as a run
            % without calibration. COLMAP failing or being cancelled, or the
            % scaled model not reading back, is different: the step stops
            % with the model as it was, and no record is written, because
            % whether the run has mm is then not settled. The model is
            % replaced only after COLMAP wrote the scaled one and it was
            % read back, and the old one goes only when the new one is in
            % place.
            r = struct('ok', true, 'err', '', 'exit_code', 0, 'applied', false, 'commands_run', {{}});
            tc = [];
            [c_ok, c_err, c] = rabbit_calibration.read_result(cal_dir);
            v = rabbit_calibration.read_json(fullfile(cal_dir, 'verdict.json'));
            rec = struct('schema', rabbit_calibration.METRIC_SCHEMA, 'calibration_id', '', 'applied', false, ...
                'units', 'model units', 'reasons', {{}}, 'comparison', struct(), 'scale_mm_per_unit', [], ...
                'scale_uncertainty_percent', [], 'scale_uncertainty_status', '', 'not_included', struct(), ...
                'target_edge_mm', [], 'size_source', '');
            [~, rec.calibration_id] = fileparts(cal_dir);
            out = fullfile(stage_dir, 'metric_scale.json');
            if ~c_ok
                rec.reasons = {sprintf('The calibration cannot be read: %s', c_err)};
                rabbit_sfm_build.write_text(out, jsonencode(rec, 'PrettyPrint', true));
                return;
            end
            rec.target_edge_mm = c.target.edge_mm;
            spec = rabbit_calibration.read_json(fullfile(cal_dir, 'spec.json'));
            rec.size_source = char(rabbit_calibration.opt(spec, 'size_source', ''));
            rec.calibration_id = char(rabbit_calibration.opt(spec, 'calibration_id', rec.calibration_id));
            if ~v.metric_allowed
                rec.reasons = {'The calibration did not pass its checks.'};
                rabbit_sfm_build.write_text(out, jsonencode(rec, 'PrettyPrint', true));
                return;
            end
            model = fullfile(stage_dir, 'model');
            [cameras, images] = reader(model);
            [prefix, tc] = rabbit_calibration.tile_map(R, spec);
            [C, A] = rabbit_calibration.model_rig(images, prefix);
            if size(C, 1) < 3
                rec.reasons = {sprintf('Only %d frames have all four views registered.', size(C, 1))};
                rabbit_sfm_build.write_text(out, jsonencode(rec, 'PrettyPrint', true));
                return;
            end
            m = rabbit_calibration.compare_rig(C, A, c, tc);
            rec.comparison = m;
            rec.scale_uncertainty_percent = m.scale_uncertainty_percent;
            rec.scale_uncertainty_status = rabbit_calibration.uncertainty_status(m.scale_uncertainty_percent);
            rec.not_included = rabbit_calibration.left_out(c, rec.size_source);
            focals = rabbit_calibration.model_focals(images, cameras, prefix);
            rec.comparison.model_focal_px = focals;
            [apply, why] = rabbit_calibration.rig_gates(m, focals, c);
            rec.reasons = why;
            note(sprintf('sparse rig against calibration %s: scale %.5g mm per unit, %.2f %% spread between baselines, largest camera misfit %.2f %%, largest angle difference %.2f degrees', ...
                rec.calibration_id, m.scale_mm_per_unit, m.baseline_spread_percent, ...
                max(m.centre_residual_percent), max(abs(m.angle_difference_deg))));
            if ~apply
                rabbit_sfm_build.write_text(out, jsonencode(rec, 'PrettyPrint', true));
                return;
            end
            sim = fullfile(stage_dir, 'to_mm.sim3.txt');
            rabbit_sfm_build.write_text(sim, sprintf('%.15g 1 0 0 0 0 0 0\n', m.scale_mm_per_unit));
            mm = fullfile(stage_dir, 'model_mm');
            if ~isfolder(mm), mkdir(mm); end
            line = sprintf('"%s" model_transformer --input_path "%s" --output_path "%s" --transform_path "%s"', ...
                colmap_exe, model, mm, sim);
            r.commands_run{end+1} = line;
            [ok, err, code] = run_cmd(line, 300, 'scaling the model to mm (COLMAP model_transformer)');
            if ~ok
                r.ok = false; r.err = err; r.exit_code = code; return;
            end
            [~, images2] = reader(mm);
            C2 = rabbit_calibration.model_rig(images2, prefix);
            ratio = norm(squeeze(C2(1, :, 1)) - squeeze(C2(1, :, 2))) / norm(squeeze(C(1, :, 1)) - squeeze(C(1, :, 2)));
            if abs(ratio / m.scale_mm_per_unit - 1) > 1e-6
                r.ok = false; r.exit_code = 1;
                r.err = sprintf('COLMAP scaled the model by %.6g, not by %.6g.', ratio, m.scale_mm_per_unit);
                return;
            end
            old = fullfile(stage_dir, 'model_units');
            if isfolder(old), rmdir(old, 's'); end
            [moved, m_msg] = movefile(model, old);
            if ~moved
                r.ok = false; r.exit_code = 1;
                r.err = sprintf('Could not set the model aside to replace it: %s', m_msg);
                return;
            end
            [moved, m_msg] = movefile(mm, model);
            if ~moved
                movefile(old, model);
                r.ok = false; r.exit_code = 1;
                r.err = sprintf('Could not put the scaled model in place: %s', m_msg);
                return;
            end
            rec.applied = true;
            rec.units = 'mm';
            rec.scale_mm_per_unit = m.scale_mm_per_unit;
            rabbit_sfm_build.write_text(out, jsonencode(rec, 'PrettyPrint', true));
            [gone, g_msg] = rmdir(old, 's');
            if ~gone, note(sprintf('The model in model units stays in model_units: %s', g_msg)); end
            r.applied = true;
        end

        function [prefix, tc] = tile_map(R, spec)
            %% Image-name prefix per tile and the model's principal point in calibration tile pixels
            % A view's tile comes from its ROI columns, so the ROI row
            % order (old or new view names) does not matter. The recipe's
            % bounds are already in the reconstruction frame's raw rows,
            % and its outer tiles are flipped as the calibration's are.
            V = R.resolved.views;
            if iscell(V), V = [V{:}]; end
            b = reshape([V.bounds], 4, numel(V))';
            [~, o] = sort(b(:, 2));
            w = reshape(spec.windows, [], 2);
            prefix = cell(1, 4); tc = zeros(4, 2);
            for k = 1:4
                q = V(o(k));
                prefix{k} = q.image_prefix;
                x = (q.bounds(2) + q.bounds(4)) / 2 - 0.5 - (w(k, 1) - 1);
                if any(k == [1 4]), x = (w(k, 2) - w(k, 1)) - x; end
                y = (q.bounds(1) + q.bounds(3)) / 2 - 0.5;
                tc(k, :) = [x y];
            end
        end

        % =============================================================
        % 5. Pixel size on the mesh
        % =============================================================

        function P = pixel_size(pts, faces, cams, unit_mm)
            %% mm per pixel of each vertex in each view
            % pts: Vx3 mesh vertices in mm; faces: Fx3; cams: 1xN structs
            % with R, t (world to camera, mm) and f (px); unit_mm: 1.
            % A vertex counts for a view when it faces the camera. The size
            % of a pixel at a surface square on to the camera is depth / f.
            % Where the surface tilts away a pixel covers more surface, but
            % only along the direction of the tilt: across it the size is
            % unchanged. cos_tilt is given separately for that reason.
            V = size(pts, 1);
            N = zeros(V, 3);
            e1 = pts(faces(:, 2), :) - pts(faces(:, 1), :);
            e2 = pts(faces(:, 3), :) - pts(faces(:, 1), :);
            fn = cross(e1, e2, 2);
            for k = 1:3
                for d = 1:3
                    N(:, d) = N(:, d) + accumarray(faces(:, k), fn(:, d), [V 1]);
                end
            end
            N = N ./ max(sqrt(sum(N .^ 2, 2)), eps);
            % outward: away from the middle of the mesh
            mid = mean(pts, 1);
            flip_sign = sum((pts - mid) .* N, 2) < 0;
            if nnz(flip_sign) > V / 2, N = -N; end
            n = numel(cams);
            mmpx = nan(V, n); cosine = nan(V, n);
            P = struct('schema', rabbit_calibration.PIXEL_SCHEMA, 'units', 'mm', 'views', []);
            views = struct('view', {}, 'median_mm_per_px', {}, 'p05_mm_per_px', {}, 'p95_mm_per_px', {}, ...
                'median_depth_mm', {}, 'vertices', {}, 'focal_px', {});
            for k = 1:n
                q = cams(k);
                X = (q.R * pts')' + q.t(:)';
                z = X(:, 3);
                vd = -(pts + (q.R' * q.t(:))') ;
                vd = vd ./ max(sqrt(sum(vd .^ 2, 2)), eps);
                cs = sum(vd .* N, 2);
                vis = z > 0 & cs > 0;
                mmpx(vis, k) = unit_mm * z(vis) / q.f;
                cosine(vis, k) = cs(vis);
                x = mmpx(vis, k);
                if isempty(x), x = nan; end
                views(k) = struct('view', q.name, 'median_mm_per_px', median(x), ...
                    'p05_mm_per_px', prctile(x, 5), 'p95_mm_per_px', prctile(x, 95), ...
                    'median_depth_mm', median(z(vis)), 'vertices', nnz(vis), 'focal_px', q.f);
            end
            P.views = views;
            P.mm_per_px = mmpx;
            P.cos_tilt = cosine;
        end

        function [same, txt] = om_pixel_note(roi_json)
            %% Is an OM pixel the size of a reconstruction pixel?
            same = false;
            txt = 'Whether an OM pixel is this size could not be read from the ROI file.';
            try
                j = rabbit_calibration.read_json(roi_json);
            catch
                return;
            end
            s = [1 1];
            if isfield(j, 'fov_mapping') && isstruct(j.fov_mapping) && isfield(j.fov_mapping, 'scale')
                s = [j.fov_mapping.scale.vertical j.fov_mapping.scale.horizontal];
            end
            same = all(s == 1);
            if same
                txt = 'The OM frames are at scale 1 to the reconstruction frames, so this is also the size of an OM pixel.';
            else
                txt = sprintf(['The OM frames are scaled %g vertically and %g horizontally against the reconstruction ' ...
                    'frames, so this is not the size of an OM pixel.'], s(1), s(2));
            end
        end

        function write_vertex_csv(path, pts, P)
            %% One row per mesh vertex: x y z (mm), then mm/px and cos tilt per view
            fid = fopen(path, 'w', 'n', 'UTF-8');
            if fid < 0, error('analyse_om:Calibration:Write', 'Could not write %s.', path); end
            c = onCleanup(@() fclose(fid));
            n = numel(P.views);
            head = {'x_mm', 'y_mm', 'z_mm'};
            for k = 1:n
                head = [head, {sprintf('mm_per_px_%s', P.views(k).view), sprintf('cos_tilt_%s', P.views(k).view)}];
            end
            fprintf(fid, '%s\n', strjoin(head, ','));
            T = [pts, reshape(permute(cat(3, P.mm_per_px, P.cos_tilt), [1 3 2]), size(pts, 1), [])];
            fprintf(fid, [repmat('%.6g,', 1, size(T, 2) - 1) '%.6g\n'], T');
        end

        function d = recording_dates(r)
            %% The dates a calibration recorded for its recordings ('' for an older record)
            d = repmat({''}, 1, numel(r));
            if ~isfield(r, 'date'), return; end
            for k = 1:numel(r)
                if ischar(r(k).date), d{k} = r(k).date; end
            end
        end

        function [same, txt, unknown] = session_check(cal_paths, om_path, dates)
            %% Same day? FITS headers state when each recording was made
            % same is false only for dates that are known and differ, and
            % txt says which. A date that cannot be found is not evidence of
            % anything: unknown says so, and same stays true for it.
            % dates: as recorded when the calibration was made, which still
            % holds when the drive is gone; the files are read only for an
            % older record.
            if nargin < 3, dates = {}; end
            cal_paths = cellstr(cal_paths);
            b = rabbit_calibration.fits_date(om_path);
            unread = {}; other = {};
            for k = 1:numel(cal_paths)
                [~, nm, ex] = fileparts(cal_paths{k});
                a = '';
                if k <= numel(dates), a = dates{k}; end
                if isempty(a), a = rabbit_calibration.fits_date(cal_paths{k}); end
                if isempty(a)
                    unread{end+1} = [nm ex];
                elseif ~isempty(b) && ~strcmp(a, b)
                    other{end+1} = sprintf('%s (%s)', [nm ex], a);
                end
            end
            parts = {};
            if isempty(b), parts{end+1} = 'The date of this recording is unknown.'; end
            if ~isempty(unread)
                parts{end+1} = sprintf('The date of %s is unknown.', strjoin(unread, ', '));
            end
            unknown = strjoin(parts, ' ');
            same = isempty(other);
            txt = '';
            if ~same
                txt = sprintf('This recording is from %s; not from that day: %s.', b, strjoin(other, ', '));
            end
        end

        function s = run_record(id, sha256, inputs)
            %% What a run's manifest keeps about its calibration
            note = '';
            differs = false;
            if isfield(inputs, 'calibration_date_note') && ischar(inputs.calibration_date_note)
                note = inputs.calibration_date_note;
            end
            if isfield(inputs, 'calibration_date_differs'), differs = isequal(inputs.calibration_date_differs, true); end
            s = struct('id', id, 'sha256', sha256, 'date_note', note, 'date_differs', differs);
        end

        function src = cut_source(folder)
            %% The recording a cut folder came from: its manifest, or beside it by name, or ''
            % This app's cuts say so in manifest.json. Other cut folders hold
            % no record, but a cut_tiffs_<time> sits next to <time>.fits.
            src = '';
            mf = fullfile(folder, 'manifest.json');
            if exist(mf, 'file') == 2
                m = rabbit_calibration.read_json(mf);
                if isfield(m, 'source') && exist(m.source, 'file') == 2, src = m.source; end
                if ~isempty(src), return; end
            end
            [parent, nm] = fileparts(folder);
            t = regexp(nm, '\d\dh-\d\dm-\d\ds', 'match', 'once');
            if ~isempty(t) && exist(fullfile(parent, [t '.fits']), 'file') == 2
                src = fullfile(parent, [t '.fits']);
            end
        end

        function d = fits_date(p)
            %% yyyy-mm-dd of a FITS file's DATE card, '' if it has none
            % For a folder of cut tiles, the date of the recording it was cut
            % from, if that can be found.
            d = '';
            try
                if isfolder(p), p = rabbit_calibration.cut_source(p); end
                [~, ~, ex] = fileparts(p);
                if ~any(strcmpi(ex, {'.fits', '.fit'})), return; end
                info = fitsinfo(p);
                k = find(strcmp(info.PrimaryData.Keywords(:, 1), 'DATE'), 1);
                if ~isempty(k)
                    t = char(info.PrimaryData.Keywords{k, 2});
                    d = t(1:min(10, numel(t)));
                end
            catch
                d = '';
            end
        end
    end
end
