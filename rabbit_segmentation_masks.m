classdef rabbit_segmentation_masks < handle
    %% COLMAP masks from the assisted segmentation
    % Collin Snitchler
    % 04.09.2026
    % Sources: segmentationAssist.mlapp (this repository, Callum
    %          Zgierski-Johnston and Teo Puig Walz); COLMAP mask format
    %          (Schoenberger and Frahm 2016; colmap.github.io).
    % Applies the current assisted-segmentation settings to the cut
    % reconstruction images (from rabbit_cut_tiffs) and writes one COLMAP
    % mask per image into a separate masks folder, for use with
    % --ImageReader.mask_path. The cut TIFFs are never changed.
    % Mask format (checked against COLMAP 02335eb):
    %   - name: the full image filename + '.png' (image.tiff ->
    %     image.tiff.png), in the same relative folder below the mask root;
    %     COLMAP's extension-replacement fallback is not relied on
    %   - single-channel uint8 PNG, 0 = excluded, 255 = foreground
    %   - same size as the image (checked on read-back, never resized)
    %   - an existing masks folder is never replaced: the masks go into
    %     the next free name, masks_reconstruction_<stem>_01 and so on
    % Segmentation uses rabbit_segmentation_core with the live threshold
    % and smoothen values from segmentationAssist, so masks match the
    % preview and the apply step. The confirmed keep area
    % (processed_data.keep_area_poly, NaN = excluded), cropped per view,
    % is applied after the blur so excluded pixels stay 0. Polygon edits
    % still in progress in segmentationAssist are not transferred.
    % Bounds row k is the k-th region (view2;view3;view1;view4); the view
    % of each cut image is read from its _view<k> filename suffix.
    % Inputs:
    %   seg_app: the segmentationAssist app (live slider values)
    %   json_path: saved ROI JSON
    %   main_app: the analyse_optical_mapping app
    % Outputs:
    %   masks in <app.file_info.path>/masks_reconstruction_<stem>/ plus
    %   manifest.json; apply returns a result struct

    properties (Access = public)
        MaskRoot       % the separate masks folder (resolved default or override)
        masks = {}     % written mask paths (COLMAP names), in cut order
        source_files = {} % cut TIFF paths the masks were made from
        view_of = []   % per-mask ROI/bounds row (parsed from the cut filenames)
        threshold = 0.83     % effective threshold (live value or default)
        sigma_gauss = 4      % effective smoothen sigma (live value or default)
        keep_crops = {}  % per-view cropped keep mask (logical) or [];
                         % public so tests can set it, as in the preview
    end

    properties (Access = private)
        main_app       % analyse_optical_mapping app (file_info/data/processed_data)
        seg_app        % segmentationAssist app whose LIVE settings are read
        json_path      % saved v1 ROI JSON (state survives an app restart)
        bounds         % 4x4 region_bounds_src (view2;view3;view1;view4)
        rec_path       % reconstruction stack path (file or folder)
        cut_dir        % cut reconstruction folder (rabbit_cut_tiffs)
        files = {}     % cut TIFF paths, natural order
    end

    methods (Static)
        function open_from_assist(seg_app, main_app)
            %% Entry point from the segmentation assist window
            % Picks the saved ROI JSON, writes the masks (into the next free
            % folder name if the usual one is taken) and reports the
            % folder used.
            [f, p] = uigetfile({'*.json', 'ROI JSON (*.json)'}, ...
                'Load ROI JSON for COLMAP mask generation');
            if isequal(f, 0)
                return;
            end
            try
                m = rabbit_segmentation_masks(seg_app, fullfile(p, f), main_app);
                % Keep a reference on the GUI, as for seg_app.preview_app
                if isobject(seg_app) && isprop(seg_app, 'mask_app')
                    seg_app.mask_app = m;
                end
                res = m.apply();
                if res.ok
                    uialert(seg_app.segmentationAssistUIFigure, ...
                        sprintf('Wrote %d COLMAP masks to:\n%s', ...
                        numel(res.written), res.mask_root), ...
                        'COLMAP masks written');
                else
                    uialert(seg_app.segmentationAssistUIFigure, ...
                        sprintf('The COLMAP masks were not written: %s', res.message), ...
                        'Apply segmentation (COLMAP masks)');
                end
            catch ME
                if ~isempty(seg_app) && isprop(seg_app, 'segmentationAssistUIFigure')
                    uialert(seg_app.segmentationAssistUIFigure, ...
                        sprintf('The COLMAP masks could not be applied: %s', ME.message), ...
                        'Apply segmentation (COLMAP masks)');
                else
                    rethrow(ME);
                end
            end
        end

        function [ok, mask_root, msg] = write_for_run(main_app, roi_json, cut_dir, settings)
            %% Masks for a reconstruction Run from the segmentation's recorded settings
            % The segmentation window's checkbox (Apply these settings to
            % the reconstruction images) records threshold and smoothen
            % (processed_data.reconstruction_segmentation); the keep area
            % is processed_data.keep_area_poly. Writes one mask per cut
            % image of cut_dir (the Run's reconstruction images) into the
            % next free masks_reconstruction_<stem> folder. No pickers.
            %   ok, mask_root: the folder; msg: why not (ok false)
            ok = false; mask_root = ''; msg = '';
            try
                live = struct('threshold_slider', double(settings.threshold), ...
                    'smoothen_slider', double(settings.sigma_gauss));
                m = rabbit_segmentation_masks(live, roi_json, main_app, cut_dir);
                res = m.apply();
                ok = res.ok; mask_root = res.mask_root; msg = res.message;
            catch ME
                msg = ME.message;
            end
        end

        function out = default_mask_root(app, stem)
            %% Default masks folder
            % <root>/masks_reconstruction_<source_stem>, with <root> the
            % loaded optical-mapping folder (app.file_info.path), next to
            % the cut folders and never inside them.
            root = app.file_info.path;
            if isempty(root) || ~isfolder(root)
                root = fileparts(app.file_info.file);
                if isempty(root)
                    root = pwd;
                end
            end
            if isempty(stem)
                stem = 'stack';
            end
            out = fullfile(root, sprintf('masks_reconstruction_%s', stem));
        end

        function alert(app, msg)
            %% Show a message with uialert, or print it when headless
            if ~isempty(app) && isprop(app, 'opticalmappingUIFigure') ...
                    && ~isempty(app.opticalmappingUIFigure)
                uialert(app.opticalmappingUIFigure, msg, 'Apply COLMAP masks failed');
            else
                fprintf('MASK_ALERT: %s\n', msg);
            end
        end

        function cleanup(stage)
            %% Remove a mask folder this run created (best effort)
            if ~isempty(stage) && isfolder(stage)
                rmdir(stage, 's');
            end
        end
    end

    methods
        function obj = rabbit_segmentation_masks(seg_app, json_path, main_app, cut_dir)
            %% Set up mask generation from a saved ROI JSON
            % Checks the JSON (rabbit panoramic, exactly 4 view bounds),
            % gets the reconstruction path (from the JSON, otherwise asks),
            % finds the cut reconstruction folder (cutting it on first
            % use, or when no cut fits the ROIs) and loads the keep-area
            % crops. Writes no masks; apply does.
            % cut_dir (optional): the cut reconstruction images to use, so
            % nothing is asked or cut (write_for_run).
            % Throws analyse_om:Masks:* errors for the caller to show.
            if nargin < 2 || isempty(json_path)
                error('analyse_om:Masks:NoJSON', ...
                    'A saved ROI JSON is required for COLMAP mask generation.');
            end
            obj.seg_app = seg_app;
            obj.main_app = main_app;
            obj.json_path = char(json_path);
            if isempty(main_app)
                error('analyse_om:Masks:NoApp', ...
                    'The main analysis app handle is required for mask generation.');
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
                error('analyse_om:Masks:NotRabbit', ...
                    ['COLMAP mask generation is only available for the rabbit ' ...
                    'panoramic system: the saved ROI JSON does not have ' ...
                    'rabbit_panoramic enabled. Re-save the ROIs with the rabbit ' ...
                    'panoramic checkbox selected.']);
            end
            src = payload.region_bounds_src;
            if size(src, 1) ~= 4
                error('analyse_om:Masks:BadROIs', ...
                    ['The saved ROI JSON must contain exactly 4 view bounds ' ...
                    '(view order view2;view3;view1;view4) for mask generation; got %d.'], ...
                    size(src, 1));
            end
            obj.bounds = double(src);

            if nargin >= 4 && ~isempty(cut_dir)
                obj.cut_dir = char(cut_dir);
                obj.load_cut_files(obj.cut_dir);
                obj.load_keep_crops();
                rec_stem = '';
                if isfield(payload, 'reconstruction_path') && ~isempty(payload.reconstruction_path)
                    rec_stem = rabbit_cut_tiffs.source_stem(payload.reconstruction_path);
                end
                if isempty(rec_stem)
                    [~, rec_stem] = fileparts(obj.cut_dir);
                end
                obj.MaskRoot = rabbit_segmentation_masks.default_mask_root(obj.main_app, rec_stem);
                return;
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
                    error('analyse_om:Masks:CutFailed', ...
                        'Could not create the canonical cut reconstruction images: %s', ...
                        ME.message);
                end
                if ~ok
                    error('analyse_om:Masks:CutFailed', ...
                        'Could not create the canonical cut reconstruction images (see the cut alert).');
                end
            end

            % ---- list the cut TIFFs and check them against the JSON bounds ----
            obj.cut_dir = cut_dir;
            obj.load_cut_files(cut_dir);

            % ---- confirmed keep-area mask, cropped per view ----
            obj.load_keep_crops();

            obj.MaskRoot = rabbit_segmentation_masks.default_mask_root( ...
                obj.main_app, stem);
        end

        function result = apply(obj, varargin)
            %% Write a COLMAP mask for every cut image
            % Uses the live threshold and smoothen values from seg_app, or
            % the defaults (0.83, 4) if they are not available.
            % Inputs (name-value):
            %   'MaskRoot': masks folder override (tests); as the default
            %       folder, it is never replaced: the next free name is used
            %   'Verifier': extra check run on each mask (tests)
            %   'Threshold', 'Sigma': segmentation overrides (tests)
            % Outputs:
            %   result: struct with ok, mask_root, written, sources, views
            %       (bounds row per mask), threshold, sigma_gauss, message,
            %       manifest_path
            p = inputParser;
            p.addParameter('MaskRoot', '', @(x) ischar(x) || isstring(x));
            p.addParameter('Verifier', [], @(x) isa(x, 'function_handle'));
            p.addParameter('Threshold', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
            p.addParameter('Sigma', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
            p.parse(varargin{:});
            if ~isempty(p.Results.MaskRoot)
                mask_root = char(p.Results.MaskRoot);
            else
                mask_root = obj.MaskRoot;
            end
            obj.threshold = obj.get_live('threshold_slider', 0.83);
            obj.sigma_gauss = obj.get_live('smoothen_slider', 4);
            if ~isempty(p.Results.Threshold)
                obj.threshold = double(p.Results.Threshold);
            end
            if ~isempty(p.Results.Sigma)
                obj.sigma_gauss = double(p.Results.Sigma);
            end

            result = struct();
            result.ok = false;
            result.mask_root = mask_root;
            result.written = {};
            result.sources = {};
            result.views = [];
            result.threshold = obj.threshold;
            result.sigma_gauss = obj.sigma_gauss;
            result.message = '';
            result.manifest_path = '';

            % ---- an existing masks folder is never touched ----
            mask_root = rabbit_stack_io.next_free_path(mask_root);
            result.mask_root = mask_root;
            stage = mask_root;

            written = {};
            sources = {};
            views = [];
            try
                mkdir(stage);
                n = numel(obj.files);
                for i = 1:n
                    fpath = obj.files{i};
                    v = obj.view_of(i);
                    frame = imread(fpath);
                    keep = [];
                    if numel(obj.keep_crops) >= v
                        keep = obj.keep_crops{v};
                    end
                    I0 = rabbit_segmentation_core.prepare_frame(frame, keep);
                    mask = rabbit_segmentation_core.segment( ...
                        I0, obj.threshold, obj.sigma_gauss);
                    % Force excluded keep-area pixels to 0 after the blur,
                    % so the smoothing cannot bring them back. An empty
                    % keep crop means nothing is excluded.
                    if ~isempty(keep)
                        mask = mask & keep;
                    end
                    % COLMAP mask name: full image filename + '.png'
                    [~, fname, fext] = fileparts(fpath);
                    out_name = [fname fext '.png'];
                    out_path = fullfile(stage, out_name);
                    imwrite(uint8(mask) * 255, out_path, 'png');
                    written{end + 1} = out_path; %#ok<AGROW>
                    sources{end + 1} = fpath; %#ok<AGROW>
                    views(end + 1) = v; %#ok<AGROW>
                end
            catch ME
                % Remove only what this attempt created; an existing
                % masks folder has not been touched yet
                rabbit_segmentation_masks.cleanup(stage);
                result.message = sprintf( ...
                    'Mask writing failed part-way; no partial outputs were left behind. %s', ...
                    ME.message);
                rabbit_segmentation_masks.alert(obj.main_app, result.message);
                return;
            end

            % ---- read back and check size, bit depth and values ----
            try
                verify = p.Results.Verifier;
                for i = 1:numel(written)
                    info = imfinfo(written{i});
                    src_info = imfinfo(sources{i});
                    if info.Width ~= src_info.Width || info.Height ~= src_info.Height
                        error('analyse_om:Masks:VerifyFailed', ...
                            'Mask %s is %dx%d but its source image is %dx%d.', ...
                            written{i}, info.Height, info.Width, ...
                            src_info.Height, src_info.Width);
                    end
                    if info.BitDepth ~= 8
                        error('analyse_om:Masks:VerifyFailed', ...
                            'Mask %s is %d-bit; the COLMAP contract requires 8-bit uint8.', ...
                            written{i}, info.BitDepth);
                    end
                    vals = unique(imread(written{i}));
                    if ~isempty(setdiff(double(vals), [0 255]))
                        error('analyse_om:Masks:VerifyFailed', ...
                            'Mask %s contains values outside {0, 255}.', written{i});
                    end
                    if ~isempty(verify)
                        verify(written{i});   % test-only failure injection
                    end
                end
            catch ME2
                rabbit_segmentation_masks.cleanup(stage);
                result.message = sprintf( ...
                    'Mask verification failed; no masks were kept. %s', ME2.message);
                rabbit_segmentation_masks.alert(obj.main_app, result.message);
                return;
            end

            % ---- manifest listing source and mask per image ----
            try
                obj.write_manifest( ...
                    stage, written, sources, views);
            catch ME3
                % The masks are valid but the manifest is missing: report
                % it; the masks stay in the folder
                result.message = sprintf( ...
                    'The COLMAP masks were written and verified but the manifest failed (%s); the new masks are preserved in %s.', ...
                    ME3.message, stage);
                rabbit_segmentation_masks.alert(obj.main_app, result.message);
                return;
            end

            obj.MaskRoot = mask_root;
            obj.masks = written;
            obj.source_files = sources;
            obj.view_of = views;
            result.ok = true;
            result.written = written;
            result.sources = sources;
            result.views = views;
            result.manifest_path = fullfile(mask_root, 'manifest.json');
            result.message = sprintf('Wrote %d COLMAP masks to %s.', ...
                numel(written), mask_root);
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

        function path = prompt_for_path(obj)
            %% Ask for the reconstruction images
            % Used when the JSON has no usable reconstruction path: an
            % alert, then a file picker, then a folder picker. Cancelling
            % throws analyse_om:Masks:NoPath.
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
                    error('analyse_om:Masks:NoPath', ...
                        'No reconstruction image path was provided; masks cannot be generated.');
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
                error('analyse_om:Masks:NoCutImages', ...
                    'The canonical cut folder contains no TIFF images: %s', cut_dir);
            end
            view_of = zeros(numel(names), 1);
            for k = 1:numel(names)
                toks = regexp(names{k}, '_view([1-4])(?:\.|_|$)', 'tokens', 'once');
                if isempty(toks)
                    error('analyse_om:Masks:BadCutName', ...
                        'Cannot determine the view of cut image ''%s'' (expected _view1.._view4).', ...
                        names{k});
                end
                view_of(k) = str2double(toks{1});
            end
            obj.files = cellfun(@(n) fullfile(cut_dir, n), names, 'UniformOutput', false);
            obj.view_of = view_of;
            for k = 1:numel(obj.files)
                v = obj.view_of(k);
                info = imfinfo(obj.files{k});
                exp_rows = obj.bounds(v, 3) - obj.bounds(v, 1) + 1;
                exp_cols = obj.bounds(v, 4) - obj.bounds(v, 2) + 1;
                if info(1).Height ~= exp_rows || info(1).Width ~= exp_cols
                    error('analyse_om:Masks:StaleCut', ...
                        ['The canonical cut reconstruction images do not match the ' ...
                        'saved ROIs (%s is %dx%d but ROI view%d crops %dx%d). The cut ' ...
                        'is stale; re-cut it with the saved ROI JSON (Save ROI JSON ' ...
                        '-> cut flow) or delete %s so the mask generator can re-cut it.'], ...
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

        function write_manifest(obj, stage, written, sources, views)
            %% Write manifest.json for the masks
            % Lists every mask with its source and view, plus the
            % segmentation settings and the COLMAP mask format.
            m = struct();
            m.version = 1;
            m.kind = 'colmap_masks';
            m.created_by = 'analyse_optical_mapping (COLMAP mask generator)';
            m.mask_root = stage;
            m.source_cut_dir = obj.cut_dir;
            m.contract = struct( ...
                'mode', 'per-image', ...
                'filename_rule', '<complete image filename>.png (appended, canonical COLMAP form)', ...
                'format', 'single-channel uint8 grayscale PNG', ...
                'values', [0 255], ...
                'excluded_value', 0, ...
                'foreground_value', 255, ...
                'dims_rule', 'exactly equal to the paired image', ...
                'consumed_by', 'COLMAP --ImageReader.mask_path');
            m.settings = struct('threshold', obj.threshold, ...
                'sigma_gauss', obj.sigma_gauss);
            m.keep_area = struct( ...
                'transferred', ~isempty(obj.keep_crops), ...
                'note', 'confirmed keep-area mask (keep_area_poly) cropped per view bounds; all-ones when none confirmed');
            m.view_order = 'view2; view3; view1; view4 (bounds row k -> cut image _view<k>)';
            files = struct('source', cell(1, numel(written)), ...
                'mask', cell(1, numel(written)), ...
                'view', cell(1, numel(written)));
            for i = 1:numel(written)
                files(i).source = sources{i};
                files(i).mask = written{i};
                files(i).view = views(i);
            end
            m.files = files;
            m.count = numel(written);
            try
                txt = jsonencode(m, 'PrettyPrint', true);
            catch
                txt = jsonencode(m);   % plain JSON is equally valid
            end
            f = fopen(fullfile(stage, 'manifest.json'), 'w', 'n', 'UTF-8');
            if f < 0
                error('analyse_om:Masks:ManifestFailed', ...
                    'The manifest could not be written: %s', ...
                    fullfile(stage, 'manifest.json'));
            end
            try
                fprintf(f, '%s\n', txt);
            catch
                % best effort - the masks themselves are verified
            end
            fclose(f);
        end
    end
end
