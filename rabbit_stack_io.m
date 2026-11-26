classdef rabbit_stack_io
    %% Rabbit stack and ROI JSON input/output
    % Collin Snitchler
    % 03.09.2026
    % Sources: natural filename order as natsortfiles (Stephen Cobeldick,
    %          MATLAB File Exchange) gives it, without needing it.
    % Loads calibration and reconstruction stacks, computes MIPs and the
    % combined display, and reads and writes the ROI JSON.
    % Inputs:
    %   a folder of 2-D TIFF frames (natural filename order), a multi-page
    %   TIFF (page order), or a FITS file (2-D or 3-D, read with
    %   fitsinfo/fitsread as in the main file selector). Single-channel
    %   only. Source files are never modified.
    % Display: MIP is the max over frames. For the combined display each
    % MIP is normalised to [0,1] and the two are combined by element-wise
    % max (NaN -> 0). This never changes saved data or crop coordinates.
    % ROI JSON, schema_version 1 (extends
    % cut_locations_per_view.json):
    %   required:
    %     schema_version = 1
    %     region_bounds_src = Nx4 [row1 col1 row2 col2], unmirrored source
    %         pixels, 1-based, inclusive
    %     regions = number of regions (4)
    %     rotation = atrial-side rotation code
    %     rabbit_panoramic = checkbox state (logical)
    %     source_dims = struct {height, width}
    %     coordinate_origin = 'top-left'
    %     unmirrored_coordinates = true
    %   optional (defaults on load):
    %     reconstruction_path = ''
    %     view_order = {'view2','view3','view1','view4'}
    %     fov_mapping = [] or a stationary-camera FOV mapping struct: type
    %         'crop'/'scale', camera_stationary, om_window_in_rec {off,
    %         rows, cols, per_view_offsets}, scale {vertical, horizontal};
    %         empty means the frames have the same FOV
    %     calibration_fov_mapping = [] or the same struct for calibration
    % Legacy cut lists (array of {view, top, right, bottom, left},
    % 0-based display-space cut margins) are converted to unmirrored
    % source bounds using the current image size.
    % Errors are thrown with identifiers 'analyse_om:Recordings:*' (the
    % region file: 'analyse_om:Regions:*') for the GUI to show with uialert.
    %
    % Section map (search for the quoted line; line numbers move)
    %   Loading stacks ......... "function out = load_stack(input)"
    %   Another frame in the
    %   editor's frame ......... "function [img, why_not, cover] = mip_in_editor_frame"
    %   Binning, free names .... "function bins = read_binning(path)"
    %   Frames and MIPs ........ "function stack = load_frames_folder(folder)"
    %   FOV mapping ............ "function m = fov_contract()"
    %   FOV offset search ...... "function est = measure_fov_offset"
    %   ROI JSON ............... "function save_roi_json(path, payload)"
    %   Validation (private) ... "function out = validate_payload(in)"

    methods (Static)

        function out = load_stack(input)
            %% Load a stack as single
            % From a folder of 2-D TIFF frames, a multi-page TIFF or a
            % FITS file. Returns a struct with stack (HxWxN single), mip
            % (HxW single), height, width, n_frames and source.
            if ~ischar(input) && ~isstring(input)
                error('analyse_om:Recordings:BadInput', ...
                    'Input must be a file or folder path.');
            end
            input = char(input);
            if ~isfolder(input) && ~exist(input, 'file')
                error('analyse_om:Recordings:NotFound', ...
                    'Path does not exist: %s', input);
            end
            if isfolder(input)
                stack = rabbit_stack_io.load_frames_folder(input);
            else
                [~, ~, ext] = fileparts(input);
                switch lower(ext)
                    case '.fits'
                        stack = rabbit_stack_io.load_fits(input);
                    case {'.tif', '.tiff'}
                        stack = rabbit_stack_io.load_tiff_file(input);
                    otherwise
                        error('analyse_om:Recordings:UnsupportedType', ...
                            'Unsupported stack file type ''%s'' (supported: .fits, .tif, .tiff).', ext);
                end
            end
            out = struct();
            out.stack = single(stack);
            out.mip = single(rabbit_stack_io.compute_mip(stack));
            out.height = size(stack, 1);
            out.width = size(stack, 2);
            out.n_frames = size(stack, 3);
            out.source = input;
        end

        function out = load_stack_native(input)
            %% Load a stack in its own numeric class
            % As load_stack, but uint16 TIFFs stay uint16 and FITS data
            % stay as fitsread returns them. Used by rabbit_cut_tiffs so
            % the cut TIFFs keep the source bit depth.
            if ~ischar(input) && ~isstring(input)
                error('analyse_om:Recordings:BadInput', ...
                    'Input must be a file or folder path.');
            end
            input = char(input);
            if ~isfolder(input) && ~exist(input, 'file')
                error('analyse_om:Recordings:NotFound', ...
                    'Path does not exist: %s', input);
            end
            if isfolder(input)
                stack = rabbit_stack_io.load_frames_folder(input);
            else
                [~, ~, ext] = fileparts(input);
                switch lower(ext)
                    case '.fits'
                        stack = rabbit_stack_io.load_fits(input);
                    case {'.tif', '.tiff'}
                        stack = rabbit_stack_io.load_tiff_file(input);
                    otherwise
                        error('analyse_om:Recordings:UnsupportedType', ...
                            'Unsupported stack file type ''%s'' (supported: .fits, .tif, .tiff).', ext);
                end
            end
            out = struct();
            out.stack = stack;   % class kept as loaded
            if isfloat(stack)
                out.mip = max(stack, [], 3, 'omitnan');
            else
                out.mip = max(stack, [], 3);   % integer classes have no NaN
            end
            out.height = size(stack, 1);
            out.width = size(stack, 2);
            out.n_frames = size(stack, 3);
            out.source = input;
        end

        function out = load_stack_preview(input)
            %% Load the first frame and the max projection, one frame at a time
            % For the region dialog and the ROI editor, which need the max
            % projection of the whole recording but not the frames: a 3 GB
            % recording stays on disk instead of being read into memory.
            % Takes the same inputs and makes the same checks as load_stack.
            % Returns the fields of load_stack with stack holding frame 1
            % only (n_frames still counts all frames).
            if ~ischar(input) && ~isstring(input)
                error('analyse_om:Recordings:BadInput', ...
                    'Input must be a file or folder path.');
            end
            input = char(input);
            if ~isfolder(input) && ~exist(input, 'file')
                error('analyse_om:Recordings:NotFound', ...
                    'Path does not exist: %s', input);
            end
            first = [];
            mip = [];
            if isfolder(input)
                img_names = rabbit_stack_io.frame_names(input);
                n = numel(img_names);
                for k = 1:n
                    p = fullfile(input, img_names{k});
                    fr = rabbit_stack_io.read_folder_frame(p, first);
                    if isempty(first), first = fr; end
                    mip = rabbit_stack_io.add_to_mip(mip, fr);
                end
            else
                [~, ~, ext] = fileparts(input);
                switch lower(ext)
                    case '.fits'
                        info = fitsinfo(input);
                        sz = info.PrimaryData.Size;
                        if numel(sz) > 3
                            error('analyse_om:Recordings:MultiChannel', ...
                                'FITS stack must be 2-D or 3-D (single-channel); got %d dimensions %s - rejected.', ...
                                numel(sz), mat2str(sz));
                        end
                        if numel(sz) == 2
                            n = 1;
                            first = fitsread(input);
                            mip = single(first);
                        else
                            n = sz(3);
                            % A hundred frames at a time, which keeps the
                            % many small reads of a long recording down
                            for k = 1:100:n
                                last = min(k + 99, n);
                                block = fitsread(input, 'primary', 'PixelRegion', ...
                                    {[1 sz(1)], [1 sz(2)], [k last]});
                                if isempty(first), first = block(:, :, 1); end
                                mip = rabbit_stack_io.add_to_mip(mip, max(single(block), [], 3, 'omitnan'));
                            end
                        end
                    case {'.tif', '.tiff'}
                        info = imfinfo(input);
                        n = numel(info);
                        for k = 1:n
                            if info(k).SamplesPerPixel ~= 1
                                error('analyse_om:Recordings:MultiChannel', ...
                                    'Multi-channel TIFF rejected (single-channel only): page %d of %s', k, input);
                            end
                        end
                        for k = 1:n
                            fr = imread(input, k);
                            if ndims(fr) ~= 2
                                error('analyse_om:Recordings:Not2D', ...
                                    'TIFF page is not 2-D: page %d of %s', k, input);
                            end
                            if isempty(first), first = fr; end
                            mip = rabbit_stack_io.add_to_mip(mip, fr);
                        end
                    otherwise
                        error('analyse_om:Recordings:UnsupportedType', ...
                            'Unsupported stack file type ''%s'' (supported: .fits, .tif, .tiff).', ext);
                end
            end
            out = struct();
            out.stack = single(first);
            out.mip = single(mip);
            out.height = size(first, 1);
            out.width = size(first, 2);
            out.n_frames = n;
            out.source = input;
        end

        function fr = first_frame(input)
            %% Frame 1 of a recording, rows as stored, without reading the rest
            % A FITS file, a multi-page TIFF or a folder of TIFF frames.
            input = char(input);
            if isfolder(input)
                names = rabbit_stack_io.frame_names(input);
                if isempty(names)
                    error('analyse_om:Recordings:NoFrames', 'There are no TIFF frames in %s.', input);
                end
                fr = rabbit_stack_io.read_folder_frame(fullfile(input, names{1}), []);
                return;
            end
            [~, ~, ext] = fileparts(input);
            if any(strcmpi(ext, {'.fits', '.fit'}))
                sz = fitsinfo(input).PrimaryData.Size;
                if numel(sz) == 2
                    fr = fitsread(input);
                else
                    fr = fitsread(input, 'primary', 'PixelRegion', {[1 sz(1)], [1 sz(2)], [1 1]});
                end
            else
                fr = imread(input, 1);
            end
        end

        function mip = add_to_mip(mip, frame)
            %% Update a running max projection with one more frame
            if isempty(mip)
                mip = single(frame);
            else
                mip = max(mip, single(frame), 'omitnan');
            end
        end

        function [img, why_not, cover] = mip_in_editor_frame(mip, H, W, mapping)
            %% Show another frame's max projection in the ROI editor's frame
            % The ROI editor works in the optical-mapping frame (H x W). The
            % cut takes rows bounds + offset of the other frame in the order
            % they are stored, so this takes the same window, in the same
            % row order: a box on the result covers the pixels the cut of
            % that frame takes. Uses map_bounds_across_fov, as the cut does,
            % one pixel at a time; with a scale mapping each editor pixel
            % shows the max of the block of pixels it stands for.
            % The other frame may be smaller than the
            % optical-mapping frame or cover only part of it (the camera's
            % area of interest changed between recordings). Editor pixels
            % outside it are NaN and false in cover; a box there cannot be
            % cut from that recording.
            % Inputs:
            %   mip: max projection as the stack loader returns it
            %   H, W: size of the optical-mapping frame
            %   mapping: FOV mapping struct, or [] (same frame)
            % Outputs:
            %   img: H x W image (single), NaN outside the other frame;
            %       empty if it cannot be shown
            %   why_not: plain reason when img is empty
            %   cover: H x W logical, true where the other frame has pixels
            img = [];
            why_not = '';
            cover = [];
            h = size(mip, 1);
            w = size(mip, 2);
            if isempty(mapping) || ~isstruct(mapping)
                if h == H && w == W
                    img = mip;   % same frame: the cut uses the bounds unchanged
                    cover = true(H, W);
                    return;
                end
                why_not = sprintf(['its frames are %d x %d pixels, the optical mapping frames %d x %d, ' ...
                    'and no position of one inside the other was recorded'], h, w, H, W);
                return;
            end
            ri = (1:H)';
            ci = (1:W)';
            rb = rabbit_stack_io.map_bounds_across_fov([ri ones(H, 1) ri ones(H, 1)], mapping);
            cb = rabbit_stack_io.map_bounds_across_fov([ones(W, 1) ci ones(W, 1) ci], mapping);
            r1 = rb(:, 1); r2 = rb(:, 3);
            c1 = cb(:, 2); c2 = cb(:, 4);
            % An editor row (column) is covered when its whole block lies
            % inside the other frame
            row_in = r1 >= 1 & r2 <= h & r1 <= r2;
            col_in = c1 >= 1 & c2 <= w & c1 <= c2;
            if ~any(row_in) || ~any(col_in)
                why_not = sprintf(['the recorded position (rows %d to %d, columns %d to %d) lies outside ' ...
                    'its %d x %d frames'], r1(1), r2(end), c1(1), c2(end), h, w);
                return;
            end
            cover = row_in & col_in';
            img = nan(H, W, 'single');
            if all(r1 == r2) && all(c1 == c2)
                img(row_in, col_in) = single(mip(r1(row_in), c1(col_in)));   % a plain crop
                return;
            end
            by_row = nan(H, w, 'single');
            for k = find(row_in)'
                by_row(k, :) = max(single(mip(r1(k):r2(k), :)), [], 1, 'omitnan');
            end
            for k = find(col_in)'
                img(row_in, k) = max(by_row(row_in, c1(k):c2(k)), [], 2, 'omitnan');
            end
        end

        function [outside, text] = boxes_outside(bounds, mapping, hw, which, names)
            %% Which ROIs leave another recording's frame
            % bounds: Nx4 [r1 c1 r2 c2] in the optical-mapping frame, as the
            % editor writes them; mapping: that recording's FOV mapping, or
            % [] (same frame); hw: [rows columns] of its frames; which: its
            % name for the text; names (optional): the box names in row
            % order, as the editor labels them (default ROI 1, ROI 2, ...).
            % The cut of that recording takes the mapped bounds, so a box
            % that leaves its frame cannot be cut there.
            % Outputs: outside, Nx1 logical; text, one plain sentence naming
            % the rows (ROI order) or '' when every box fits.
            if isempty(mapping) || ~isstruct(mapping)
                mb = double(bounds(:, 1:4));
            else
                mb = rabbit_stack_io.map_bounds_across_fov(double(bounds(:, 1:4)), mapping);
            end
            outside = mb(:, 1) < 1 | mb(:, 2) < 1 | mb(:, 3) > hw(1) | mb(:, 4) > hw(2);
            if nargin < 5 || isempty(names)
                names = arrayfun(@(q) sprintf('ROI %d', q), 1:size(mb, 1), 'UniformOutput', false);
            end
            text = '';
            if any(outside)
                k = find(outside);
                parts = arrayfun(@(q) sprintf('%s (it would need rows %d to %d and columns %d to %d of frames that have rows 1 to %d and columns 1 to %d)', ...
                    names{q}, mb(q, 1), mb(q, 3), mb(q, 2), mb(q, 4), hw(1), hw(2)), k, 'UniformOutput', false);
                verb = 'leaves';
                if numel(k) > 1, verb = 'leave'; end
                text = sprintf('%s %s the frames of the %s recording: %s.', ...
                    rabbit_stack_io.count_words(numel(k), 'box', 'boxes'), verb, which, strjoin(parts, '; '));
            end
        end

        function t = count_words(n, one, many)
            %% "1 box", "3 boxes"
            if n == 1, t = sprintf('%d %s', n, one); else, t = sprintf('%d %s', n, many); end
        end

        function bins = read_binning(path)
            %% Pixel binning [vertical horizontal] a recording was made with
            % Andor Solis writes VBIN and HBIN into every FITS header (the
            % reference rabbit recordings: 1 and 1). Other files, or a FITS file
            % without them, give [NaN NaN]: not known.
            bins = [NaN NaN];
            try
                [~, ~, ext] = fileparts(char(path));
                if ~any(strcmpi(ext, {'.fits', '.fit'})), return; end
                kw = fitsinfo(char(path)).PrimaryData.Keywords;
                names = upper(strtrim(kw(:, 1)));
                v = kw(strcmp(names, 'VBIN'), 2);
                h = kw(strcmp(names, 'HBIN'), 2);
                if ~isempty(v) && isnumeric(v{1}), bins(1) = double(v{1}); end
                if ~isempty(h) && isnumeric(h{1}), bins(2) = double(h{1}); end
            catch
                bins = [NaN NaN];
            end
        end

        function txt = binning_mismatch(om_bins, other_bins, which)
            %% '' when the binnings agree or are not both known, else why the stack cannot be used
            txt = '';
            if all(isfinite(om_bins)) && all(isfinite(other_bins)) && ~isequal(om_bins, other_bins)
                txt = sprintf(['The %s recording was made with %d x %d pixel binning (vertical x horizontal) ' ...
                    'and the optical mapping recording with %d x %d. The cut, the reconstruction and the ' ...
                    'reprojection all need one camera pixel to be the same size in both, so record the %s ' ...
                    'stack with the same binning.'], which, other_bins(1), other_bins(2), om_bins(1), om_bins(2), which);
            end
        end

        function suffix = next_free_suffix(folder, bases, ext)
            %% First number that makes all these names free in a folder
            % As when a file is pasted into a folder that already has one
            % of that name: '' if every name is free, else '_01', '_02' and
            % so on (more digits after _99), the first number free for all
            % of them, so names made together keep the same number. A gap
            % is used. A file and a folder both count as taken, and the
            % file system decides what is the same name (case on Windows).
            % Nothing is created.
            % Inputs:
            %   folder: where the names would go
            %   bases: name, or cell array of names, without ext
            %   ext: extension with its dot, or '' (optional)
            if nargin < 3
                ext = '';
            end
            bases = cellstr(bases);
            n = 0;
            suffix = '';
            while true
                taken = false;
                for k = 1:numel(bases)
                    p = fullfile(folder, [bases{k} suffix ext]);
                    if isfolder(p) || isfile(p)
                        taken = true;
                        break;
                    end
                end
                if ~taken
                    return;
                end
                n = n + 1;
                suffix = sprintf('_%02d', n);
            end
        end

        function p = next_free_path(path, ext)
            %% The path itself if free, else the next free numbered path
            % path has no extension; ext is added after the number.
            if nargin < 2
                ext = '';
            end
            path = char(path);
            while numel(path) > 1 && any(path(end) == '/\')
                path(end) = [];
            end
            [folder, name, tail] = fileparts(path);
            base = [name tail];   % a dot inside a name is part of the name
            p = fullfile(folder, [base rabbit_stack_io.next_free_suffix(folder, base, ext) ext]);
        end

        function stack = load_frames_folder(folder)
            %% Load a folder of 2-D TIFF frames
            % Natural filename order; single-channel; all frames the same
            % size.
            img_names = rabbit_stack_io.frame_names(folder);
            frames = cell(numel(img_names), 1);
            first = [];
            for k = 1:numel(img_names)
                p = fullfile(folder, img_names{k});
                fr = rabbit_stack_io.read_folder_frame(p, first);
                if isempty(first), first = fr; end
                frames{k} = fr;
            end
            stack = cat(3, frames{:});
        end

        function img_names = frame_names(folder)
            %% TIFF names of a frames folder, in natural order
            % A folder without TIFFs or with other files is rejected.
            d = dir(folder);
            names = {d.name};
            keep = cellfun(@(n) ~strcmp(n, '.') && ~strcmp(n, '..'), names);
            names = names(keep);
            isimg = cellfun(@(n) ~isempty(regexpi(n, '\.tiff?$')), names);
            other = names(~isimg);
            if ~any(isimg)
                error('analyse_om:Recordings:NoFrames', ...
                    'Folder contains no TIFF frames: %s', folder);
            end
            if ~isempty(other)
                shown = other(1:min(5, numel(other)));
                error('analyse_om:Recordings:NonTiffFiles', ...
                    'Folder contains non-TIFF files (only 2-D TIFF frames are accepted): %s', ...
                    strjoin(shown, ', '));
            end
            img_names = rabbit_stack_io.natsort_names(names(isimg));
        end

        function fr = read_folder_frame(p, first)
            %% Read and check one frame of a frames folder
            % first: the folder's first frame ([] for the first one).
            info = imfinfo(p);
            if numel(info) > 1
                error('analyse_om:Recordings:MultiPageInFolder', ...
                    'Frame file is multi-page; expected 2-D frames in a folder: %s', p);
            end
            if info(1).SamplesPerPixel ~= 1
                error('analyse_om:Recordings:MultiChannel', ...
                    'Multi-channel frame rejected (single-channel only): %s', p);
            end
            fr = imread(p);
            if ndims(fr) ~= 2
                error('analyse_om:Recordings:Not2D', ...
                    'Frame is not 2-D: %s', p);
            end
            if ~isempty(first) && (size(fr, 1) ~= size(first, 1) || size(fr, 2) ~= size(first, 2))
                error('analyse_om:Recordings:FrameDims', ...
                    'Frame 2-D dimensions differ from the first frame (%dx%d): %s', ...
                    size(first, 1), size(first, 2), p);
            end
        end

        function stack = load_tiff_file(file)
            %% Load a single- or multi-page TIFF in page order
            info = imfinfo(file);
            for k = 1:numel(info)
                if info(k).SamplesPerPixel ~= 1
                    error('analyse_om:Recordings:MultiChannel', ...
                        'Multi-channel TIFF rejected (single-channel only): page %d of %s', k, file);
                end
            end
            frames = cell(numel(info), 1);
            for k = 1:numel(info)
                fr = imread(file, k);
                if ndims(fr) ~= 2
                    error('analyse_om:Recordings:Not2D', ...
                        'TIFF page is not 2-D: page %d of %s', k, file);
                end
                frames{k} = fr;
            end
            stack = cat(3, frames{:});
        end

        function stack = load_fits(file)
            %% Load a FITS stack with fitsinfo and fitsread
            % 2-D gives one frame, 3-D a stack; more dimensions are
            % rejected.
            info = fitsinfo(file);
            sz = info.PrimaryData.Size;
            if numel(sz) == 2
                stack = fitsread(file);   % single-frame stack (2-D page)
            elseif numel(sz) == 3
                stack = fitsread(file);
            else
                error('analyse_om:Recordings:MultiChannel', ...
                    'FITS stack must be 2-D or 3-D (single-channel); got %d dimensions %s - rejected.', ...
                    numel(sz), mat2str(sz));
            end
        end

        function mip = compute_mip(stack)
            %% Max-intensity projection over frames
            if ndims(stack) == 3
                mip = max(stack, [], 3, 'omitnan');
            else
                mip = stack;
            end
        end

        function d = normalize_mip(mip)
            %% Normalise a MIP to [0,1] for display
            % Min-max over finite values; NaN/Inf -> 0. A flat or all-NaN
            % input gives zeros. Display only.
            d = double(mip);
            if isempty(d)
                return;
            end
            fin = d(isfinite(d));
            if isempty(fin)
                d = zeros(size(d));
                return;
            end
            mn = min(fin);
            mx = max(fin);
            rng = mx - mn;
            if ~isfinite(rng) || rng <= 0
                d = zeros(size(d));
                return;
            end
            d = (d - mn) ./ rng;
            d(~isfinite(d)) = 0;   % NaN -> 0 for display
        end

        function c = combined_display(mip_a, mip_b)
            %% Combine two MIPs for display
            % Normalises each to [0,1] and takes the element-wise max.
            % Both must be the same size.
            a = rabbit_stack_io.normalize_mip(mip_a);
            b = rabbit_stack_io.normalize_mip(mip_b);
            if ~isequal(size(a), size(b))
                error('analyse_om:Recordings:DimsMismatch', ...
                    'Combined display requires equal 2-D dimensions (got %dx%d and %dx%d).', ...
                    size(a, 1), size(a, 2), size(b, 1), size(b, 2));
            end
            c = max(a, b);
        end

        function m = fov_contract()
            %% Measured stationary-camera FOV mapping
            % Position of the optical-mapping window in the
            % reconstruction frame, measured with
            % tools/fov_mapping_fixture.py: the optical-mapping FOV is a
            % vertical crop of the reconstruction FOV (scale 1.0, no
            % column offset), row offset 192 on reconstruction frame 0
            % (NCC 0.9754). Saved as fov_mapping in the ROI JSON and used
            % by the cut and the reprojection.
            m = struct();
            m.type = 'crop';
            m.camera_stationary = true;
            m.om_window_in_rec = struct('off', 192, 'cols_off', 0, ...
                'rows', 'off:off+400', 'cols', '0:2000', ...
                'per_view_offsets', [190 199 199 188]);
            m.scale = struct('vertical', 1.0, 'horizontal', 1.0);
            m.provenance = ['vertical crop measured on the July 2026 rabbit test data ' ...
                '(off=192, frame 0, ncc 0.9754)'];
        end

        function tf = same_file(a, b)
            %% True when two paths name the same file or folder
            % Compared as absolute, normalised paths (java.io.File
            % getCanonicalPath resolves '.', '..' and, where the file
            % exists, links); without case on Windows, whose file names
            % ignore case. The region dialog uses it to refuse the loaded
            % optical mapping recording as a calibration or reconstruction
            % stack.
            tf = false;
            if isempty(a) || isempty(b), return; end
            try
                ca = char(java.io.File(char(a)).getCanonicalPath());
                cb = char(java.io.File(char(b)).getCanonicalPath());
            catch
                ca = char(a);
                cb = char(b);
            end
            if ispc
                tf = strcmpi(ca, cb);
            else
                tf = strcmp(ca, cb);
            end
        end

        function rel = classify_fov_relation(om_h, om_w, other_h, other_w)
            %% Compare the optical-mapping frame size with another stack
            % Returns:
            %   'same': identical size (its position is still measured:
            %       the camera's area of interest may have moved)
            %   'crop': the other frame is at least as large in both
            %       directions, so the optical-mapping frame can be a
            %       window of it
            %   'smaller': the other frame is smaller in at least one
            %       direction (allowed; the ROIs must then stay inside
            %       the part both frames show)
            if other_h == om_h && other_w == om_w
                rel = 'same';
            elseif other_h >= om_h && other_w >= om_w
                rel = 'crop';
            else
                rel = 'smaller';
            end
        end

        function m = offset_mapping(off, cols_off, provenance)
            %% A stationary-camera mapping that only shifts the frame
            % off, cols_off: 0-based row and column of the optical-mapping
            % frame's top-left pixel in the other frame, in the row order
            % stored in the files; negative when the optical-mapping frame
            % starts above (left of) the other frame.
            m = struct();
            m.type = 'crop';
            m.camera_stationary = true;
            m.om_window_in_rec = struct('off', off, 'cols_off', cols_off, ...
                'rows', sprintf('%d:%d', off, off), 'cols', sprintf('%d:%d', cols_off, cols_off));
            m.scale = struct('vertical', 1.0, 'horizontal', 1.0);
            m.provenance = provenance;
        end

        function m = propose_fov_mapping(om_h, om_w, other_h, other_w, which, om_img, other_img)
            %% Measure where the optical-mapping frame sits in another frame
            % With om_img and other_img (one frame of each, in the same
            % row order) the position is measured with measure_fov_offset
            % (any relative size and position; the per-view offsets of
            % fov_contract are not carried over). Without the images the
            % reconstruction falls back to the offset measured on the
            % reference rabbit data (fov_contract, 192) and the
            % calibration to the top-left window (offset 0), with a note.
            % The pixels are taken to be the same size: a recording with
            % another binning is refused by the caller (binning_mismatch),
            % so no scale is guessed from the size ratio.
            m = rabbit_stack_io.fov_contract();
            if strcmp(which, 'calibration')
                m.om_window_in_rec.off = 0;
                m.om_window_in_rec.rows = '0:om_h-1 (assumed top-left)';
                m.provenance = ['assumed top-left window (offset 0); ' ...
                    'NOT fixture-verified - verify the OM window ' ...
                    'position before cutting'];
            end
            if nargin < 7 || isempty(om_img) || isempty(other_img)
                return;
            end
            est = rabbit_stack_io.measure_fov_offset(om_img, other_img);
            if ~isfinite(est.ncc)
                return;   % nothing to match (flat image): keep the defaults
            end
            m = rabbit_stack_io.offset_mapping(est.off, est.cols_off, sprintf(['measured when the %s ' ...
                'stack was loaded: frame 1 matches the optical-mapping frame at row offset %d, column ' ...
                'offset %d (normalised cross-correlation %.3f; offsets in the row order stored in the ' ...
                'files)'], which, est.off, est.cols_off, est.ncc));
            m.om_window_in_rec.rows = sprintf('%d:%d', est.off, est.off + om_h);
            m.om_window_in_rec.cols = sprintf('%d:%d', est.cols_off, est.cols_off + om_w);
            m.match_score = est.ncc;
            m.overlap = rabbit_stack_io.overlap_text(om_h, om_w, other_h, other_w, est.off, est.cols_off);
        end

        function txt = overlap_text(om_h, om_w, other_h, other_w, off, cols_off)
            %% Which part of the optical-mapping frame the other frame shows, in plain words
            r1 = max(1, 1 - off); r2 = min(om_h, other_h - off);
            c1 = max(1, 1 - cols_off); c2 = min(om_w, other_w - cols_off);
            if r1 == 1 && r2 == om_h && c1 == 1 && c2 == om_w
                txt = 'the whole optical mapping frame lies inside it';
            elseif r1 > r2 || c1 > c2
                txt = 'no part of the optical mapping frame lies inside it';
            else
                txt = sprintf(['only rows %d to %d and columns %d to %d of the optical mapping frame lie ' ...
                    'inside it, so every ROI must stay within them'], r1, r2, c1, c2);
            end
        end

        function est = measure_fov_offset(om_img, other_img, om_mask, other_mask)
            %% Find where the optical-mapping frame sits in another frame
            % Same camera, same pixel size: the background (rig, mirrors)
            % matches even when the heart moved. Both frames must be in the
            % same row order: the app shows FITS recordings upside down
            % (flip(fitsread, 1)), so the caller flips an app frame back
            % before comparing it with a stack read by this class.
            % The frames may have any sizes and may only partly
            % overlap (the camera's area of interest changed between the
            % recordings). The match is the masked normalised
            % cross-correlation of Padfield (2012, IEEE Trans. Image
            % Process. 21(5):2706-2718): the correlation over the pixels
            % both frames share, at every whole-pixel shift where the
            % frames share at least a quarter of the smaller one. It equals
            % normxcorr2 (Lewis 1995) where one frame lies wholly inside
            % the other. To keep the memory small the search runs on 4 x 4
            % block means first, then at full resolution within 6 px of
            % the best shift. om_mask, other_mask (optional, logical, the
            % frames' sizes): only these pixels count, e.g. the pixels that
            % stay still through a recording (rabbit_fov_position.still),
            % so that a heart in another pose does not pull the match.
            % Outputs:
            %   est.off, est.cols_off: 0-based row and column of the
            %       optical-mapping frame's top-left pixel in the other
            %       frame; negative when it starts above or left of it
            %   est.ncc: correlation at that position (1 = identical);
            %       NaN if either image is flat or the frames are too small
            %       to compare (under 16 px)
            %   est.overlap: share of the optical-mapping frame inside the
            %       other frame at that position
            %   est.edge: true when the best shift lies on the edge of the
            %       refinement window (the coarse search may have missed)
            est = struct('off', 0, 'cols_off', 0, 'ncc', NaN, 'overlap', NaN, 'edge', false, ...
                'method', 'masked normalised cross-correlation (Padfield 2012)');
            a = double(om_img(:, :, 1));
            b = double(other_img(:, :, 1));
            if nargin < 3 || isempty(om_mask), om_mask = true(size(a)); end
            if nargin < 4 || isempty(other_mask), other_mask = true(size(b)); end
            ma = logical(om_mask) & isfinite(a);
            mb = logical(other_mask) & isfinite(b);
            a(~ma) = 0;
            b(~mb) = 0;
            if min([size(a) size(b)]) < 16 || nnz(ma) < 256 || nnz(mb) < 256 || ...
                    max(a(ma)) == min(a(ma)) || max(b(mb)) == min(b(mb))
                return;
            end
            min_share = 0.25 * min(numel(a), numel(b));   % frames overlap by at least this many pixels
            min_used = 0.25 * min(nnz(ma), nnz(mb));      % and share at least this many counted pixels
            % Coarse search on 4 x 4 block means of the counted pixels
            f = 4;
            na = rabbit_stack_io.block_mean(double(ma), f);
            nb = rabbit_stack_io.block_mean(double(mb), f);
            ac = rabbit_stack_io.block_mean(a, f) ./ max(na, eps);
            bc = rabbit_stack_io.block_mean(b, f) ./ max(nb, eps);
            [ncc_c, ov_c] = rabbit_stack_io.masked_ncc(ac, bc, na > 0.5, nb > 0.5);
            frames_c = rabbit_stack_io.masked_ncc_overlap(size(ac), size(bc));
            ncc_c(frames_c * f * f < min_share | ov_c * f * f < min_used) = -Inf;
            [~, i] = max(ncc_c(:));
            [ri, ki] = ind2sub(size(ncc_c), i);
            r0 = (ri - size(ac, 1)) * f;   % 0-based shift of a in b, in full pixels
            k0 = (ki - size(ac, 2)) * f;
            % Full-resolution refinement around the coarse shift
            best = -Inf;
            R = 6;
            for dr = -R:R
                for dk = -R:R
                    [v, n, nf] = rabbit_stack_io.ncc_at(a, b, r0 + dr, k0 + dk, ma, mb);
                    if nf >= min_share && n >= min_used && v > best + 1e-12
                        best = v;
                        est.off = r0 + dr;
                        est.cols_off = k0 + dk;
                        est.overlap = nf / numel(a);
                        est.edge = abs(dr) == R || abs(dk) == R;
                    end
                end
            end
            if isfinite(best), est.ncc = best; end
        end

        function c = block_mean(x, f)
            %% Mean of each f x f block (the last partial blocks dropped)
            h = floor(size(x, 1) / f) * f;
            w = floor(size(x, 2) / f) * f;
            x = x(1:h, 1:w);
            c = squeeze(mean(mean(reshape(x, f, h / f, f, w / f), 1), 3));
            c = reshape(c, h / f, w / f);
        end

        function overlap = masked_ncc_overlap(sa, sb)
            %% Pixels two whole frames of sizes sa and sb share at every shift (same layout as masked_ncc)
            % Shift index i shares min(i, size a, size b, size a + size b - i) rows (and so for columns)
            rows = min([(1:sa(1) + sb(1) - 1)', repmat(sa(1), sa(1) + sb(1) - 1, 1), ...
                repmat(sb(1), sa(1) + sb(1) - 1, 1), (sa(1) + sb(1) - 1:-1:1)'], [], 2);
            cols = min([(1:sa(2) + sb(2) - 1)', repmat(sa(2), sa(2) + sb(2) - 1, 1), ...
                repmat(sb(2), sa(2) + sb(2) - 1, 1), (sa(2) + sb(2) - 1:-1:1)'], [], 2);
            overlap = rows * cols';
        end

        function [ncc, overlap] = masked_ncc(a, b, ma, mb)
            %% Normalised cross-correlation over the shared counted pixels, at every shift (Padfield 2012)
            % Element (i, j) is the shift of a's top-left pixel to row
            % i - size(a, 1), column j - size(a, 2) of b (0-based). The
            % sums over the overlap come from linear convolutions by FFT.
            % ma, mb (optional): the pixels that count.
            if nargin < 3 || isempty(ma), ma = true(size(a)); end
            if nargin < 4 || isempty(mb), mb = true(size(b)); end
            ma = double(ma); mb = double(mb);
            a = (a - sum(a(:) .* ma(:)) / max(sum(ma(:)), 1)) .* ma;
            b = (b - sum(b(:) .* mb(:)) / max(sum(mb(:)), 1)) .* mb;
            sz = size(a) + size(b) - 1;
            Fa = @(x) fft2(rot90(x, 2), sz(1), sz(2));
            Fb = @(x) fft2(x, sz(1), sz(2));
            cc = @(p, q) real(ifft2(p .* q));
            Ama = Fa(ma); Aa = Fa(a); Aa2 = Fa(a .^ 2);
            Bmb = Fb(mb); Bb = Fb(b); Bb2 = Fb(b .^ 2);
            overlap = round(cc(Bmb, Ama));
            n = max(overlap, 1);
            sa = cc(Bmb, Aa); sb = cc(Bb, Ama);
            num = cc(Bb, Aa) - sa .* sb ./ n;
            den = sqrt(max(cc(Bmb, Aa2) - sa .^ 2 ./ n, 0) .* max(cc(Bb2, Ama) - sb .^ 2 ./ n, 0));
            ncc = num ./ den;
            ncc(~isfinite(ncc) | den < 1e-9 * max(den(:)) | overlap < 1) = -Inf;
        end

        function [v, n, nf] = ncc_at(a, b, off, cols_off, ma, mb)
            %% Correlation over the shared counted pixels at one shift; n counted pixels, nf frame pixels shared
            r1 = max(1, 1 - off); r2 = min(size(a, 1), size(b, 1) - off);
            c1 = max(1, 1 - cols_off); c2 = min(size(a, 2), size(b, 2) - cols_off);
            v = -Inf; n = 0; nf = 0;
            if r1 > r2 || c1 > c2, return; end
            p = a(r1:r2, c1:c2);
            q = b(r1 + off:r2 + off, c1 + cols_off:c2 + cols_off);
            nf = numel(p);
            if nargin >= 6
                m = ma(r1:r2, c1:c2) & mb(r1 + off:r2 + off, c1 + cols_off:c2 + cols_off);
                p = p(m); q = q(m);
            end
            n = numel(p);
            if n < 2, return; end
            p = p(:) - mean(p(:));
            q = q(:) - mean(q(:));
            d = sqrt(sum(p .^ 2) * sum(q .^ 2));
            if d > 0, v = sum(p .* q) / d; end
        end

        function mb = map_bounds_across_fov(bounds, mapping)
            %% Map ROI bounds into the calibration or reconstruction frame
            % bounds are Nx4 [r1 c1 r2 c2], 1-based, inclusive, in the
            % optical-mapping frame:
            %   rec_r = (om_r - 1) * sv + 1 + off_r
            %   rec_c = (om_c - 1) * sh + 1 + off_c
            % off is the 0-based row/column offset of the window, sv/sh
            % the vertical/horizontal scale. Rounded to whole pixels.
            m = rabbit_stack_io.validate_fov_mapping(mapping);
            sv = m.scale.vertical;
            sh = m.scale.horizontal;
            off_r = m.om_window_in_rec.off;
            off_c = 0;
            if isfield(m.om_window_in_rec, 'cols_off')
                off_c = m.om_window_in_rec.cols_off;
            end
            mb = zeros(size(bounds));
            mb(:, 1) = round((bounds(:, 1) - 1) * sv + 1 + off_r);
            mb(:, 3) = round(bounds(:, 3) * sv + off_r);
            mb(:, 2) = round((bounds(:, 2) - 1) * sh + 1 + off_c);
            mb(:, 4) = round(bounds(:, 4) * sh + off_c);
        end

        function m = validate_fov_mapping(in)
            %% Check a fov_mapping struct and return a clean copy
            % Optional fields get defaults; camera_stationary must be
            % true. Errors use analyse_om:Regions:MalformedJSON, as the ROI JSON
            % check does.
            if ~isstruct(in) || ~isscalar(in)
                error('analyse_om:Regions:MalformedJSON', ...
                    'fov_mapping must be a scalar struct.');
            end
            if ~isfield(in, 'type') || ~ischar(in.type) || ...
                    ~any(strcmp(in.type, {'crop', 'scale', 'crop_scale'}))
                error('analyse_om:Regions:MalformedJSON', ...
                    'fov_mapping.type must be ''crop'', ''scale'' or ''crop_scale''.');
            end
            cs = true;
            if isfield(in, 'camera_stationary')
                cs = in.camera_stationary;
                if ~(islogical(cs) && isscalar(cs)) && ~(isnumeric(cs) && isscalar(cs))
                    error('analyse_om:Regions:MalformedJSON', ...
                        'fov_mapping.camera_stationary must be a logical.');
                end
            end
            if ~cs
                error('analyse_om:Regions:MalformedJSON', ...
                    'fov_mapping.camera_stationary must be true (stationary-camera contract).');
            end
            ow = struct('off', 0, 'cols_off', 0);
            if isfield(in, 'om_window_in_rec')
                o = in.om_window_in_rec;
                if ~isstruct(o) || ~isscalar(o)
                    error('analyse_om:Regions:MalformedJSON', ...
                        'fov_mapping.om_window_in_rec must be a struct.');
                end
                % Negative offsets are allowed, for an
                % optical-mapping frame that starts above or left of the
                % other frame (the other frame smaller, or shifted)
                if isfield(o, 'off')
                    if ~isnumeric(o.off) || ~isscalar(o.off) || ...
                            ~isfinite(o.off) || o.off ~= round(o.off)
                        error('analyse_om:Regions:MalformedJSON', ...
                            'fov_mapping.om_window_in_rec.off must be a whole number.');
                    end
                    ow.off = double(o.off);
                end
                if isfield(o, 'cols_off')
                    if ~isnumeric(o.cols_off) || ~isscalar(o.cols_off) || ...
                            ~isfinite(o.cols_off) || o.cols_off ~= round(o.cols_off)
                        error('analyse_om:Regions:MalformedJSON', ...
                            'fov_mapping.om_window_in_rec.cols_off must be a whole number.');
                    end
                    ow.cols_off = double(o.cols_off);
                end
                for f = {'rows', 'cols'}
                    if isfield(o, f{1})
                        if ~ischar(o.(f{1})) && ~isstring(o.(f{1}))
                            error('analyse_om:Regions:MalformedJSON', ...
                                'fov_mapping.om_window_in_rec.%s must be a string.', f{1});
                        end
                        ow.(f{1}) = char(o.(f{1}));
                    end
                end
                if isfield(o, 'per_view_offsets')
                    pv = o.per_view_offsets;
                    if ~isnumeric(pv) || numel(pv) ~= 4 || ...
                            any(~isfinite(pv(:))) || any(pv(:) < 0)
                        error('analyse_om:Regions:MalformedJSON', ...
                            'fov_mapping.om_window_in_rec.per_view_offsets must be 4 non-negative scalars.');
                    end
                    ow.per_view_offsets = double(pv(:)');
                end
            end
            sc = struct('vertical', 1.0, 'horizontal', 1.0);
            if isfield(in, 'scale')
                s = in.scale;
                if ~isstruct(s) || ~isscalar(s)
                    error('analyse_om:Regions:MalformedJSON', ...
                        'fov_mapping.scale must be a struct.');
                end
                for f = {'vertical', 'horizontal'}
                    if isfield(s, f{1})
                        if ~isnumeric(s.(f{1})) || ~isscalar(s.(f{1})) || ...
                                ~isfinite(s.(f{1})) || s.(f{1}) <= 0
                            error('analyse_om:Regions:MalformedJSON', ...
                                'fov_mapping.scale.%s must be a positive scalar.', f{1});
                        end
                        sc.(f{1}) = double(s.(f{1}));
                    end
                end
            end
            m = struct();
            m.type = in.type;
            m.camera_stationary = true;
            m.om_window_in_rec = ow;
            m.scale = sc;
            m.provenance = '';
            if isfield(in, 'provenance')
                if ~ischar(in.provenance) && ~isstring(in.provenance)
                    error('analyse_om:Regions:MalformedJSON', ...
                        'fov_mapping.provenance must be a string.');
                end
                m.provenance = char(in.provenance);
            end
            % How the position was found, kept for the records
            % (rabbit_fov_position.mapping); NaN = no score
            if isfield(in, 'position_source') && ~isempty(in.position_source)
                if ~any(strcmp(char(in.position_source), {'measured', 'typed', 'assumed'}))
                    error('analyse_om:Regions:MalformedJSON', ...
                        'fov_mapping.position_source must be measured, typed or assumed.');
                end
                m.position_source = char(in.position_source);
            end
            % The recording whose alignment this one reuses
            if isfield(in, 'follows') && ~isempty(in.follows)
                if ~any(strcmp(char(in.follows), {'reconstruction', 'calibration'}))
                    error('analyse_om:Regions:MalformedJSON', 'fov_mapping.follows must be reconstruction or calibration.');
                end
                m.follows = char(in.follows);
            end
            if isfield(in, 'match_score')
                s = in.match_score;
                if isempty(s), s = NaN; end
                if ~isnumeric(s) || ~isscalar(s)
                    error('analyse_om:Regions:MalformedJSON', 'fov_mapping.match_score must be a number.');
                end
                m.match_score = double(s);
            end
        end

        function save_roi_json(path, payload)
            %% Write a version 1 ROI JSON
            % The payload is checked with the same rules as load_roi_json
            % before writing.
            if ~isstruct(payload) || ~isscalar(payload)
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON payload must be a scalar struct.');
            end
            rabbit_stack_io.validate_payload(payload);
            txt = jsonencode(payload);
            try
                txt = jsonencode(payload, 'PrettyPrint', true);
            catch
                % R2023b+ only; plain compact JSON is equally valid.
            end
            f = fopen(path, 'w', 'n', 'UTF-8');
            if f < 0
                error('analyse_om:Regions:WriteFailed', ...
                    'Could not open ROI JSON for writing: %s', path);
            end
            try
                fprintf(f, '%s\n', txt);
            catch ME
                fclose(f);
                rethrow(ME);
            end
            fclose(f);
        end

        function out = load_roi_json(path, img_h, img_w)
            %% Load a ROI JSON
            % A version 1 file is checked and its defaults filled; a
            % legacy cut list is converted using the current image
            % size (img_h, img_w). Throws analyse_om:Regions:MalformedJSON
            % otherwise.
            if nargin < 2
                img_h = [];
            end
            if nargin < 3
                img_w = [];
            end
            if ~exist(path, 'file')
                error('analyse_om:Recordings:NotFound', ...
                    'ROI JSON file not found: %s', path);
            end
            try
                dec = jsondecode(fileread(path));
            catch ME
                error('analyse_om:Regions:MalformedJSON', ...
                    'Malformed ROI JSON (%s): %s', path, ME.message);
            end
            if isstruct(dec) && ~isscalar(dec) && all(isfield(dec, 'view'))
                out = rabbit_stack_io.legacy_to_payload(dec, path, img_h, img_w);
                return;
            end
            if ~isstruct(dec) || ~isscalar(dec)
                error('analyse_om:Regions:MalformedJSON', ...
                    'Malformed ROI JSON: expected a JSON object (v1) or the legacy cut list: %s', path);
            end
            out = rabbit_stack_io.validate_payload(dec);
        end

        function names = natsort_names(names)
            %% Natural filename order (frame10 after frame2)
            % Numbers are zero-padded to 12 digits before sorting, so
            % numbers up to 10^12 sort correctly. Does not need
            % natsortfiles.
            if isempty(names)
                return;
            end
            names = cellstr(names);
            keys = cell(numel(names), 1);
            for k = 1:numel(names)
                toks = regexp(names{k}, '\d+|\D+', 'match');
                p = '';
                for j = 1:numel(toks)
                    if ~isempty(regexp(toks{j}, '^\d+$', 'once'))
                        p = [p sprintf('%012d', str2double(toks{j}))]; %#ok<AGROW>
                    else
                        p = [p toks{j}]; %#ok<AGROW>
                    end
                end
                keys{k} = p;
            end
            [~, idx] = sort(keys);
            names = names(idx);
        end

    end

    methods (Static, Access = private)

        function out = validate_payload(in)
            %% Check a version 1 payload and fill the optional defaults
            % Missing or wrongly typed required fields throw
            % analyse_om:Regions:MalformedJSON.
            req = {'schema_version', 'region_bounds_src', ...
                'regions', 'rotation', 'rabbit_panoramic', ...
                'source_dims', 'coordinate_origin', 'unmirrored_coordinates'};
            missing = req(~isfield(in, req));
            if ~isempty(missing)
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON missing required field(s): %s', strjoin(missing, ', '));
            end
            if ~isnumeric(in.schema_version) || ~isscalar(in.schema_version) ...
                    || in.schema_version ~= 1
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON schema_version must be 1 (got missing or unsupported value).');
            end
            src = in.region_bounds_src;
            if ~isnumeric(src)
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON region_bounds_src must be an Nx4 numeric array (N>=1, finite).');
            end
            % jsonencode writes a 1x4 row as a flat array, which
            % jsondecode reads back as 4x1. Turn that single ROI back into
            % 1x4; other column lengths stay invalid.
            if size(src, 1) == 4 && size(src, 2) == 1
                src = src.';
            end
            if size(src, 2) ~= 4 || size(src, 1) < 1 ...
                    || any(~isfinite(src(:)))
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON region_bounds_src must be an Nx4 numeric array (N>=1, finite).');
            end
            if ~isnumeric(in.regions) || ~isscalar(in.regions) || in.regions < 1
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON regions must be a positive scalar number.');
            end
            if ~isnumeric(in.rotation) || ~isscalar(in.rotation)
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON rotation must be a scalar number.');
            end
            rp = in.rabbit_panoramic;
            if ~(islogical(rp) && isscalar(rp)) && ~(isnumeric(rp) && isscalar(rp))
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON rabbit_panoramic must be a logical (checkbox state).');
            end
            sd = in.source_dims;
            if ~isstruct(sd) || ~isscalar(sd) || ~isfield(sd, 'height') ...
                    || ~isfield(sd, 'width') || ~isnumeric(sd.height) ...
                    || ~isnumeric(sd.width) || ~isscalar(sd.height) ...
                    || ~isscalar(sd.width) || sd.height < 1 || sd.width < 1
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON source_dims must be {height, width} positive scalars.');
            end
            if ~ischar(in.coordinate_origin) || ~strcmp(in.coordinate_origin, 'top-left')
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON coordinate_origin must be ''top-left'' (pinned schema literal).');
            end
            uc = in.unmirrored_coordinates;
            if ~(islogical(uc) && isscalar(uc)) && ~(isnumeric(uc) && isscalar(uc))
                error('analyse_om:Regions:MalformedJSON', ...
                    'ROI JSON unmirrored_coordinates must be a logical.');
            end

            out = struct();
            out.schema_version = 1;
            out.region_bounds_src = double(src);
            out.regions = double(in.regions);
            out.rotation = double(in.rotation);
            out.rabbit_panoramic = logical(rp);
            out.source_dims = struct('height', double(sd.height), ...
                'width', double(sd.width));
            out.coordinate_origin = char(in.coordinate_origin);
            out.unmirrored_coordinates = logical(uc);
            out.reconstruction_path = '';
            if isfield(in, 'reconstruction_path')
                if ~ischar(in.reconstruction_path) && ~isstring(in.reconstruction_path)
                    error('analyse_om:Regions:MalformedJSON', ...
                        'ROI JSON reconstruction_path must be a string.');
                end
                out.reconstruction_path = char(in.reconstruction_path);
            end
            out.view_order = {'view2', 'view3', 'view1', 'view4'};
            if isfield(in, 'view_order')
                vo = in.view_order;
                if ~iscellstr(vo) && ~isstring(vo)
                    error('analyse_om:Regions:MalformedJSON', ...
                        'ROI JSON view_order must be an array of view names.');
                end
                vo = cellstr(vo);
                if numel(vo) ~= 4 || numel(unique(vo)) ~= 4
                    error('analyse_om:Regions:MalformedJSON', ...
                        'ROI JSON view_order must contain exactly 4 distinct view names.');
                end
                out.view_order = vo;
            end
            % Optional stationary-camera FOV mapping; empty means the
            % same FOV, so older files load unchanged
            out.fov_mapping = [];
            if isfield(in, 'fov_mapping') && ~isempty(in.fov_mapping)
                out.fov_mapping = rabbit_stack_io.validate_fov_mapping(in.fov_mapping);
            end
            % Separate mapping for the calibration cut (fov_mapping is
            % for the reconstruction)
            out.calibration_fov_mapping = [];
            if isfield(in, 'calibration_fov_mapping') && ~isempty(in.calibration_fov_mapping)
                out.calibration_fov_mapping = rabbit_stack_io.validate_fov_mapping(in.calibration_fov_mapping);
            end
            % The calibration recording calibration_fov_mapping belongs to
            % ('' = not recorded, as in older files)
            out.calibration_path = '';
            if isfield(in, 'calibration_path') && ~isempty(in.calibration_path)
                if ~ischar(in.calibration_path) && ~isstring(in.calibration_path)
                    error('analyse_om:Regions:MalformedJSON', 'ROI JSON calibration_path must be a string.');
                end
                out.calibration_path = char(in.calibration_path);
            end
        end

        function out = legacy_to_payload(dec, path, img_h, img_w)
            %% Convert a legacy cut list to a version 1 payload
            % The list holds {view, top, right, bottom, left}, 0-based
            % display-space margins, so the current image size is needed.
            if isempty(img_h) || isempty(img_w)
                error('analyse_om:Regions:MalformedJSON', ...
                    'Legacy ROI JSON requires the current image dimensions for conversion: %s', path);
            end
            H = img_h; W = img_w;
            by_view = containers.Map();
            for k = 1:numel(dec)
                e = dec(k);
                flds = {'top', 'right', 'bottom', 'left'};
                if ~isfield(e, 'view')
                    error('analyse_om:Regions:MalformedJSON', ...
                        'Legacy ROI JSON entry missing ''view'': %s', path);
                end
                for j = 1:4
                    f = flds{j};
                    if ~isfield(e, f) || ~isnumeric(e.(f)) || ~isscalar(e.(f)) ...
                            || ~isfinite(e.(f))
                        error('analyse_om:Regions:MalformedJSON', ...
                            'Legacy ROI JSON entry ''%s'' missing numeric ''%s'': %s', ...
                            e.view, f, path);
                    end
                end
                v = lower(strtrim(char(e.view)));
                by_view(v) = [round(e.top) round(e.right) round(e.bottom) round(e.left)];
            end
            views = {'view1', 'view2', 'view3', 'view4'};
            miss = views(~cellfun(@(v) by_view.isKey(v), views));
            if ~isempty(miss)
                error('analyse_om:Regions:MalformedJSON', ...
                    'Legacy ROI JSON missing entries for: %s (%s)', ...
                    strjoin(miss, ', '), path);
            end
            src = zeros(4, 4);
            order = {'view2', 'view3', 'view1', 'view4'};
            for k = 1:4
                v = order{k};
                cut = by_view(v);
                top = cut(1); right = cut(2); bot = cut(3); left = cut(4);
                if strcmp(v, 'view2') || strcmp(v, 'view3')
                    % non-mirrored: cuts are display = source space
                    src(k, :) = [top + 1, left + 1, H - bot, W - right];
                else
                    % mirrored display: source columns invert through W
                    src(k, :) = [top + 1, right + 1, H - bot, W - left];
                end
            end
            src(:, 1) = min(max(src(:, 1), 1), H);
            src(:, 2) = min(max(src(:, 2), 1), W);
            src(:, 3) = min(max(src(:, 3), 1), H);
            src(:, 4) = min(max(src(:, 4), 1), W);
            src(:, 1:2) = min(src(:, 1:2), src(:, 3:4));
            src(:, 3:4) = max(src(:, 1:2), src(:, 3:4));
            out = struct();
            out.schema_version = 1;
            out.region_bounds_src = src;
            out.regions = 4;
            out.rotation = 3;
            out.rabbit_panoramic = true;   % a cut list is always the rabbit system
            out.source_dims = struct('height', H, 'width', W);
            out.coordinate_origin = 'top-left';
            out.unmirrored_coordinates = true;
            out.reconstruction_path = '';
            out.view_order = {'view2', 'view3', 'view1', 'view4'};
            out.fov_mapping = [];   % legacy files carry no mapping
            out.calibration_fov_mapping = [];
            out.calibration_path = '';
        end

    end
end
