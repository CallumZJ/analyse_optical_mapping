classdef rabbit_rhythm_reproject < handle
    %% RHYTHM reprojection of optical mapping data onto a 3D heart mesh
    % Collin Snitchler
    % 04.09.2026
    % Projects per-view optical mapping data (a single activation map, and
    % optionally the OM frame stack as a time series) onto a mesh
    % reconstructed with COLMAP, using the RHYTHM 2.0 projection code.
    %
    % Inputs are standard COLMAP outputs (cameras.bin/txt, images.bin/txt)
    % and a PLY mesh, plus the activation canvas made by
    % analyse_optical_mapping (app.processed_data.activation_map, ms,
    % NaN = no data) and the saved ROI JSON (rabbit_stack_io) that pins
    % the canvas geometry. This class does all coordinate and format
    % conversion; nothing else in the GUI calls the RHYTHM code directly.
    %
    % Attribution (MIT notice and required citations):
    %   RHYTHM: An Open Source Imaging Toolkit for Cardiac Panoramic
    %   Optical Mapping. Gloschat C et al. Sci Rep 2018;8:2921.
    %   doi:10.1038/s41598-018-21333-w. PMID 29440763.
    %   Software lineage: Laughner JI et al. Am J Physiol Heart Circ
    %   Physiol 2012;303(7):H753-65. PMID 22821993.
    %   Vendored upstream: github.com/optocardiography/RHYTHM-2.0 at
    %   dc4818acfc9bcd393785d77920a7e77de80c6400 (MIT, Efimov Lab GWU),
    %   see third_party/RHYTHM/NOTICE.md.
    %
    % Projection method (default, Method 'auto' or 'rhythm'):
    %   The vendored ORIENT_files/dataProjection02.m is called itself,
    %   unmodified, exactly as RHYTHM's ORIENT2 calls it. Its inputs are
    %   built to be RHYTHM-native:
    %     - Each view is resampled to the 100x100 grid that
    %       dataProjection02 assumes (sub2ind([100 100],...)); RHYTHM 2.0
    %       mapped 100x100 CMOS data (configc 'brainvision_ultimaL').
    %       The resampling is an exact area average (each 100x100 pixel
    %       is the area-weighted mean of the source pixels it covers), so
    %       a 400x400 view becomes 4x4 binning. Source pixels with no data
    %       (NaN) are left out of the average; a 100x100 pixel is in the
    %       view mask (bgMask) when at least half its area has data.
    %     - The binning is folded exactly into the RHYTHM camera
    %       parameters: the COLMAP camera is converted to the
    %       'brainvision_ultimaL' parametrisation (10 px/mm sensor) with
    %       focal length, aspect ratio, principal point and Heikkila
    %       distortion terms rescaled, and the remaining pixel offset goes
    %       into RHYTHM's own per-view shift. pred() then lands directly
    %       on the 100x100 grid.
    %     - Xshift/Yshift, from which dataProjection02 draws each view's
    %       silhouette, are projected points on the mesh faces spaced at
    %       most half a 100x100 pixel apart (the mesh vertices and face
    %       centroids when the mesh is that dense, as RHYTHM's meshes
    %       were; ORIENT2 passes the vertices).
    %     - cmosData{view} carries a data-coverage frame first, then the
    %       activation map, then any OM frames. Projected values are
    %       divided by the projected coverage, which gives the area mean
    %       of the valid source pixels under each face (NaN pixels are
    %       ignored rather than zeroing the face).
    %     - dataProjection02 is run in a temporary folder (it writes a
    %       .cdf header to the current folder), and the msgbox/waitbar it
    %       opens are closed afterwards, also on error.
    %   Kept as fallback (Method 'reimplementation', or chosen by 'auto'
    %   when a view is smaller than 100 px, so would need upsampling
    %   rather than binning, or when dataProjection02 itself fails, e.g.
    %   a collinear projected triangle in convex_intersect, or two views
    %   tying exactly in both edge weight and normal angle, which its
    %   view choice (line 156) cannot resolve): a MATLAB
    %   transcription of the same algorithm (project_views) at native
    %   view resolution, calling the vendored pred, imdist, configc,
    %   checkpoly, convex_intersect, line_intersect, conefilt and
    %   smoothregionbdr. It differs from dataProjection02 in that it does
    %   not bin to 100x100 (so the 16 px cone edge filter acts on a finer
    %   grid) and it builds the view mask from face centroids rather than
    %   mesh vertices. The fallback projects the activation map only, not
    %   the frame stack.
    %
    % Canvas un-mapping (view1/view4 mirror handling):
    %   The activation map lives on the 4-view canvas built by
    %   apply_regions in analyse_optical_mapping from unmirrored source
    %   crops (region_bounds_src, Nx4 [row1 col1 row2 col2], 1-based,
    %   inclusive; row order view2;view3;view1;view4). regions_chosen
    %   first orders the regions by first column; with four regions,
    %   rotation 3 then swaps the last two and rotation 1 takes them in
    %   the order 4 3 1 2. Per canvas slot s (left to right):
    %       s==1: canvas_tile = rot90(src)
    %       s==2: canvas_tile = fliplr(rot90(fliplr(flipud(src))))
    %       s==3: canvas_tile = fliplr(rot90(fliplr(src)))
    %       s==4: canvas_tile = fliplr(rot90(fliplr(flipud(src))))
    %   Tiles are stacked left to right, vertically centred. Rotation 1/3
    %   use the WxH layout (height = max source width, width = sum of
    %   source heights; rotation 3 is the app default) and are checked
    %   against the app's assembly. Rotation 0/2 are read as an HxW layout
    %   (height = max source height, width = sum of source widths), which
    %   only holds for square views. split_canvas() applies the inverse
    %   per tile, so the per-view maps are in the same orientation as the
    %   cut reconstruction images the COLMAP cameras see.
    %
    % OM row flip (FITS recordings):
    %   analyse_optical_mapping loads a FITS recording as flip(fitsread, 1),
    %   so the OM canvas is upside down relative to the raw sensor rows.
    %   The reconstruction cut (rabbit_cut_tiffs via rabbit_stack_io) keeps
    %   the raw rows, so the cameras image the raw orientation (on the
    %   reference rabbit data the OM frame matches the reconstruction
    %   window with NCC 0.52 as loaded and 0.97 after a row flip). With
    %   FlipRows each per-view map is flipped back; the row offset this
    %   leaves between the flipped OM view and the cut tile (the cut crops
    %   the app-frame rows, the flip mirrors them about the OM frame) is
    %   passed in Shifts by the caller: for a cut tile of OM rows r1..r2 in
    %   an OM frame of height H, dy = r1 + r2 - H - 1.
    %
    % View flips (runs that build their own sparse model):
    %   The Reconstruction tab can flip mirrored views (left-right and/or
    %   up-down, per ROI row) before COLMAP sees them, so those cameras
    %   image the flipped tile. ViewFlips flips each per-view map and frame
    %   the same way after the canvas split (and after FlipRows), and
    %   negates that view's shift along the flipped axis: a camera pixel u
    %   of a left-right flipped tile of width w is tile column w+1-u, so
    %   with the flipped map the lookup u+dx must become u-dx. Only views
    %   whose map is the cut tile itself can be flipped. A model built by
    %   the tab has om_tile_transform.json next to its model folder;
    %   run_from_app reads it and applies the flips.
    %
    % Camera convention (COLMAP -> RHYTHM):
    %   SIMPLE_PINHOLE/PINHOLE: par = [Asp=1, f_mm, cx, cy, 0 0 0 0] with
    %   f_mm = f_px * 0.024 and the configc entry 'andor_ixon_6mm'
    %   (41.667 px/mm), so pred reproduces the COLMAP pinhole projection
    %   exactly at the native resolution. OPENCV-type distortion maps
    %   k1, k2, p1, p2 onto imdist's Heikkila model (exact for zero
    %   coefficients, an approximation otherwise). The world-to-camera
    %   rotation R is decomposed into RHYTHM's omega/psi/kappa with
    %   R = Rz(kappa)*Ry(psi)*Rx(omega). Translations and mesh points are
    %   scaled to mm with UnitScale (the projection is unchanged by a
    %   common scale; it only sets the RHYTHM unit).
    %
    % Conduction velocity direction:
    %   With Quantity 'cv_speed' and CvComponents, each assigned face also
    %   gets a unit direction in the surface (cv_direction.mat): each
    %   view's CV vector, turned with its tile on the way from the canvas,
    %   is lifted onto the face's plane through that view's camera at the
    %   face centroid, and the views are combined with the speed's
    %   weights (cv_face_directions).
    %
    % Usage:
    %   r = rabbit_rhythm_reproject.run(map, json_path, ...
    %       'ColmapDir', folder, 'MeshFile', mesh.ply, ...)
    %   r = rabbit_rhythm_reproject.run(map, json_path, ..., ...
    %       'Frames', stack, 'Fps', fps)     % also project the video
    %   rabbit_rhythm_reproject.run_from_app(app)   % GUI button callback
    %
    % The vendored RHYTHM files are never modified.
    %
    % Section map (search for the quoted line; line numbers move)
    %   Entry points .............. "% 1. Entry points"
    %   Frame choice and checks ... "% 1b. Which frame's cameras project the OM views, and checks"
    %   Canvas split .............. "% 2. Canvas <-> per-view source maps"
    %   COLMAP readers ............ "% 3. COLMAP readers (standard COLMAP model formats only)"
    %   PLY reader ................ "% 4. PLY mesh reader (COLMAP/APDe-MVS PLY, text or binary)"
    %   Mesh topology ............. "% 5. Mesh topology"
    %   Projection ................ "% 6. The projection: vendored RHYTHM dataProjection02"
    %   Fallback projection ....... "% 6a. FALLBACK: MATLAB transcription of dataProjection02"
    %   Exports ................... "% 7. Exports"

    properties (Access = public, Constant)
        VIEW_ORDER = {'view2', 'view3', 'view1', 'view4'}; % ROI row order
        RHYTHM_CAMERA = 'andor_ixon_6mm'; % configc entry, native resolution
        RHYTHM_MAP_CAMERA = 'brainvision_ultimaL'; % configc entry, 100x100 RHYTHM grid
        RHYTHM_GRID = 100;      % dataProjection02 camera size (sub2ind([100 100]))
        PIXEL_PITCH_MM = 0.024; % Nx=128 px over Sx=3.072 mm (configc)
        MIN_ANGLE_DIRECT = 95;  % dataProjection02 minangleDIRECT
        MIN_EDGE_DIRECT = 0.9;  % dataProjection02 minedgeDIRECT
        MIN_EDGE_EDGE = 0.55;   % dataProjection02 minedgeEDGE (default of the setting)
        EDGE_RATIONALE = 'edge-on rim faces, e.g. the apex, are seen by no camera directly';
        EDGE_FILT_VAL = 16;     % dataProjection02 edgefiltval
        % A view gives a face no CV direction when the face is seen so
        % nearly edge-on that the image squashes one surface direction to
        % less than this fraction of the other (about 87 degrees of tilt)
        CV_LIFT_MIN_RATIO = 0.05;
        % The surface speed is left out (NaN) where the tilt correction is
        % above this factor (chosen for the rabbit data, not taken from a
        % reference); the image-plane speed is kept
        SURFACE_MAX_CORRECTION = 1.5;
        % The frame check's mesh_outside_om warns above this share
        MESH_OUTSIDE_WARN = 0.10;
        % The per-view activation consistency warns when the IQR of a
        % view's directly seen faces is above this times its 2-D IQR
        ACTIVATION_IQR_RATIO_WARN = 1.5;
        % A view's camera-image outline match below this counts towards
        % "geometry suspect" (display only; the frame check's own WARN
        % limit is frame_check_limits' 0.85)
        GEOMETRY_CAMERA_MATCH_SUSPECT = 0.75;
        % Confidence class of a projected face, best to worst (saved in
        % <stem>_confidence.mat next to each projection). Separate from
        % the projected values: there RHYTHM's 0 still means unassigned.
        CLASS_NAMES = {'DIRECT', 'OVERLAP', 'EDGE', 'LOW_CONFIDENCE', 'UNASSIGNED'};
    end

    methods (Static)

        % =============================================================
        % 1. Entry points
        % =============================================================

        function result = run(map, json_path, varargin)
            %RUN Project an OM activation canvas map (and optionally the
            %OM frame stack) onto a reconstruction from standard COLMAP
            %outputs.
            %   map       HxW numeric activation canvas (ms; NaN missing)
            %   json_path saved v1 ROI JSON (rabbit_stack_io schema)
            %   Name-Value options:
            %     ColmapDir    folder with cameras.bin/txt and
            %                  images.bin/txt
            %     MeshFile     .ply mesh (COLMAP/APDe-MVS PLY accepted)
            %     ViewCameras  1x4 cell of COLMAP image names, one per ROI
            %                  row; default: for ROI row k the first image
            %                  (sorted by name) named 'view<k>/...' or
            %                  '..._view<k>...', else a cam<k>/camera_<k>
            %                  prefix (positional; recorded as
            %                  view_camera_per_roi_row)
            %     UnitScale    COLMAP units -> mm scale (default 1000)
            %     Shifts       4x2 pixel shifts [dx dy] per view (default
            %                  zeros). When the maps are a vertical crop
            %                  of the reconstruction frame, Shifts(:,2) =
            %                  -offset per view.
            %     FovMapping   struct describing the OM window in the
            %                  reconstruction frame (recorded in the
            %                  manifest; its scale is applied)
            %     Frames       HxWxT OM frame stack on the same canvas as
            %                  map (e.g. app.processed_data.image_stack{n});
            %                  projected as a per-face time series
            %     Fps          frame rate of Frames (default 1)
            %     FlipRows     true, or 1x4 logical per view: turn each per-view
            %                  map (and frame) upside down after the canvas is
            %                  split, before projection (default false). Used
            %                  for FITS recordings, which the app loads row-
            %                  flipped while the reconstruction cut is not
            %                  (see OM row flip in the class header)
            %     ViewFlips    1x4 cell per ROI row: 'none' (default), 'lr',
            %                  'ud' or 'lrud'; flips each per-view map and
            %                  frame like the tab flipped the SfM images
            %                  (see View flips in the class header)
            %     Method       'auto' (default), 'rhythm' or
            %                  'reimplementation' (see the class header)
            %     Quantity     'activation' (default) or 'cv_speed': the
            %                  map is the conduction velocity speed (m/s,
            %                  the Conduction Velocity tab's CV_map(:,:,3));
            %                  the files are then cv_projected.cdf/.ply and
            %                  cv_reprojection_manifest.json, and no frames
            %                  are projected
            %     CvComponents with Quantity 'cv_speed': the CV vectors,
            %                  rows x cols x 2 on the same canvas (CV_map(:,:,1)
            %                  the row, CV_map(:,:,2) the column component).
            %                  Each face then also gets a 3D unit direction
            %                  in the surface, saved as cv_direction.mat
            %                  (see cv_face_directions); the speed files are
            %                  the same as without it
            %     DisplayLimits struct with fields activation and cv, each
            %                  [lo hi] or []: the colour ranges the maps were
            %                  shown with in the app (app_display_limits),
            %                  recorded in the manifest as display_limits so
            %                  Visualise starts with them; colour only, no
            %                  value is left out
            %     CvActivationSpread with Quantity 'cv_speed': struct with views
            %                  (View1-View4, or '' for one map) and iqr_ms,
            %                  the activation IQR (25-75 %) of each view of the
            %                  map the CV step used (rabbit_cv_map.
            %                  simultaneous_check); recorded in the CV
            %                  manifest as activation_spread
            %     CvPixelUm    with Quantity 'cv_speed' and CvComponents: um
            %                  per pixel of the canvas, as the CV map used it
            %                  (rabbit_calibration_scale.pixel_map); each face
            %                  then also gets the tilt-corrected surface
            %                  speed (lift_speed), saved as speed_surface in
            %                  cv_direction.mat; [] (default) none
            %     CvActivationCut with Quantity 'cv_speed': struct with map
            %                  (the activation canvas the CV map was made
            %                  from, before its cut) and cut_ms (the cut the
            %                  CV map was made with: the CV tab's "Leave out
            %                  activation times above the display limit"
            %                  ticked). Faces whose projected activation is
            %                  above cut_ms then get no CV, recorded in the CV
            %                  manifest as activation_cut. [] (default) or a
            %                  cut that is not finite: nothing is left out
            %     PacingCycleMs the recording's pacing cycle in ms, or []
            %                  (Step 2's Pacing cycle; check_pacing_cycle):
            %                  recorded in the manifest as pacing_cycle_ms
            %                  when given
            %     ActivationZero the activation map's method and zero
            %                  (rabbit_activation_zero record, or []):
            %                  recorded in the manifest as activation_zero,
            %                  so the label can say what 0 is
            %     RecordingRhythm the recording's rhythm marker
            %                  (rabbit_recording_rhythm.record), or []:
            %                  recorded in the manifest as recording_rhythm
            %                  when given; nothing computed depends on it
            %     MinEdgeEdge  minimum edge weight of an EDGE face
            %                  (dataProjection02 minedgeEDGE; default 0.55,
            %                  0.1-0.9). Not 0.55: dataProjection02 runs
            %                  from a copy whose only change is that value,
            %                  and the result records it as a deviation
            %     OutDir       export folder (default: no file exports)
            %     ExportCdf    write activation_projected.cdf (default
            %                  true when OutDir given)
            %     ExportPly    write activation_projected.ply (default
            %                  true when OutDir given)
            %   result fields: dataProj (nFaces x 1 ms; 0 = unassigned),
            %   mask (assigned faces), viewi (nFaces x nViews+1), series
            %   (nFaces x T, NaN = unassigned, when Frames given), method,
            %   per-view maps, mesh, cameras, view_cameras, shifts, stats,
            %   export paths, manifest_path.
            p = struct();
            p.ColmapDir = ''; p.MeshFile = ''; p.ViewCameras = [];
            p.UnitScale = 1000; p.Shifts = []; p.FovMapping = [];
            p.Frames = []; p.Fps = 1; p.Method = 'auto'; p.FlipRows = false;
            p.ViewFlips = {}; p.FrameCheck = [];
            p.MinEdgeEdge = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            p.Quantity = 'activation';
            p.CvComponents = [];
            p.DisplayLimits = [];
            p.PacingCycleMs = [];
            p.RecordingRhythm = [];
            p.CvActivationSpread = [];
            p.CvPixelUm = [];
            p.CvSettings = [];
            p.CvActivationCut = [];
            p.ActivationZero = [];
            p.OutDir = ''; p.ExportCdf = true; p.ExportPly = true;
            for i = 1:2:numel(varargin)
                if ischar(varargin{i}) || isstring(varargin{i})
                    p.(char(varargin{i})) = varargin{i+1};
                end
            end
            min_edge_edge = rabbit_rhythm_reproject.check_min_edge_edge(p.MinEdgeEdge);
            quantity = lower(char(p.Quantity));
            if ~any(strcmp(quantity, {'activation', 'cv_speed'}))
                error('analyse_om:Reprojection:BadQuantity', 'Quantity must be ''activation'' or ''cv_speed''.');
            end
            if strcmp(quantity, 'cv_speed')
                p.Frames = [];
            end
            % The CV direction is projected only with the speed and only
            % from vectors on the canvas of the speed
            want_dir = strcmp(quantity, 'cv_speed') && ~isempty(p.CvComponents);
            if want_dir && (size(p.CvComponents, 1) ~= size(map, 1) || ...
                    size(p.CvComponents, 2) ~= size(map, 2) || size(p.CvComponents, 3) ~= 2)
                error('analyse_om:Reprojection:BadCvComponents', ...
                    'CvComponents must be %dx%dx2 (row and column components on the canvas of the speed).', ...
                    size(map, 1), size(map, 2));
            end
            method = lower(char(p.Method));
            if ~any(strcmp(method, {'auto', 'rhythm', 'reimplementation'}))
                error('analyse_om:Reprojection:BadMethod', ...
                    'Method must be ''auto'', ''rhythm'' or ''reimplementation''.');
            end
            if ~isempty(p.Frames) && (size(p.Frames, 1) ~= size(map, 1) || ...
                    size(p.Frames, 2) ~= size(map, 2))
                error('analyse_om:Reprojection:FramesMismatch', ...
                    ['The frame stack is %dx%d but the activation map is %dx%d; ' ...
                    'both must be on the same canvas.'], size(p.Frames, 1), ...
                    size(p.Frames, 2), size(map, 1), size(map, 2));
            end

            if isempty(p.ColmapDir) || ~isfolder(p.ColmapDir)
                error('analyse_om:Reprojection:NoColmapDir', ...
                    'ColmapDir is required (COLMAP model folder).');
            end
            % A UnitScale given by the caller wins; otherwise a model the
            % calibration scaled to mm says so
            named = varargin(1:2:end);
            if ~any(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(x, 'UnitScale'), named))
                p.UnitScale = rabbit_rhythm_reproject.unit_scale_for_model(p.ColmapDir, p.UnitScale);
            end
            if isempty(p.MeshFile) || ~exist(p.MeshFile, 'file')
                error('analyse_om:Reprojection:NoMesh', ...
                    'MeshFile is required (.ply reconstruction mesh).');
            end
            % The vendored RHYTHM primitives live next to this adapter
            % (third_party/RHYTHM under the repo root); make sure they
            % are on the MATLAB path regardless of how the GUI or a
            % headless script was launched (idempotent, no user config).
            rabbit_rhythm_reproject.ensure_rhythm_path();

            % --- canvas geometry from the saved ROI JSON ---
            payload = rabbit_stack_io.load_roi_json(json_path, [], []);
            if ~isfield(payload, 'rabbit_panoramic') || ~payload.rabbit_panoramic
                error('analyse_om:Reprojection:NotRabbit', ...
                    ['RHYTHM reprojection needs the rabbit panoramic system: ' ...
                    'the saved ROI JSON has rabbit_panoramic=false.']);
            end
            bounds = payload.region_bounds_src;
            if size(bounds, 1) ~= 4
                error('analyse_om:Reprojection:BadROIs', ...
                    ['Exactly 4 view bounds (view2;view3;view1;view4) are ' ...
                    'required; got %d.'], size(bounds, 1));
            end
            rotation = 0;
            if isfield(payload, 'rotation'), rotation = payload.rotation; end
            % Rotations 0-3 are supported: 0/2 use the HxW canvas
            % layout, 1/3 the transposed WxH layout (rotation 3 is the
            % app default). Only the slot geometry differs.

            % --- split the canvas into per-view source-orientation maps ---
            [views, view_names, canvas, om_bin] = rabbit_rhythm_reproject.split_canvas( ...
                map, bounds, rotation);
            bin_note = '';
            if om_bin > 1
                bin_note = sprintf(['The activation map was made after %dx%d binning: each of its pixels is ' ...
                    'projected over its %dx%d block of the regions.'], om_bin, om_bin, om_bin, om_bin);
            end
            result.om_binning = om_bin;
            % Optional row flip per view (FlipRows): the OM canvas is upside
            % down relative to the reconstruction images (see the class
            % header), so each per-view map is turned the right way up
            % before it meets the cameras.
            flip_rows = logical(p.FlipRows(:)');
            if isscalar(flip_rows), flip_rows = repmat(flip_rows, 1, numel(views)); end
            if numel(flip_rows) ~= numel(views)
                error('analyse_om:Reprojection:BadFlipRows', ...
                    'FlipRows must be true/false or one value per view (%d).', numel(views));
            end
            for k = 1:numel(views)
                if flip_rows(k), views{k} = flipud(views{k}); end
            end
            result.flip_rows = flip_rows;
            % View flips (see the class header): flip the map like the
            % SfM image of that view, and turn the shift round
            view_flips = repmat({'none'}, 1, numel(views));
            if ~isempty(p.ViewFlips)
                if ~iscell(p.ViewFlips) || numel(p.ViewFlips) ~= numel(views) || ...
                        ~all(ismember(p.ViewFlips, {'none', 'lr', 'ud', 'lrud'}))
                    error('analyse_om:Reprojection:BadViewFlips', ...
                        'ViewFlips must be one of none/lr/ud/lrud per view (%d).', numel(views));
                end
                view_flips = reshape(p.ViewFlips, 1, []);
            end
            flip_lr = contains(view_flips, 'lr');
            flip_ud = contains(view_flips, 'ud');
            if any(flip_lr | flip_ud)
                if isempty(p.Shifts)
                    p.Shifts = zeros(numel(views), 2);
                end
                for k = 1:numel(views)
                    if flip_lr(k)
                        views{k} = fliplr(views{k});
                        p.Shifts(k, 1) = -p.Shifts(k, 1);
                    end
                    if flip_ud(k)
                        views{k} = flipud(views{k});
                        p.Shifts(k, 2) = -p.Shifts(k, 2);
                    end
                end
            end
            result.view_flips = view_flips;
            result.canvas = canvas;
            result.views = views;
            result.view_names = view_names;
            result.bounds = bounds;
            result.rotation = rotation;
            % The CV vectors of each view, in the axes of its map (the
            % same split and flips as the map above)
            cv_views = {};
            cv_axes = [];
            if want_dir
                [cv_views, cv_axes] = rabbit_rhythm_reproject.cv_view_components( ...
                    p.CvComponents, bounds, rotation, flip_rows, view_flips);
            end
            % Each view's pixel size as the CV map used it (the median over
            % the view's part of CvPixelUm), for the tilt-corrected surface
            % speed, in mm per pixel of the frame
            % the projection's Jacobian is in: a binned map is projected
            % over its om_bin x om_bin blocks, so that is the unbinned pixel
            % (CvPixelUm / om_bin)
            cv_pixel_mm = [];
            if want_dir && ~isempty(p.CvPixelUm) && isequal(size(p.CvPixelUm), size(map))
                pv = rabbit_rhythm_reproject.split_canvas(double(p.CvPixelUm), bounds, rotation);
                cv_pixel_mm = nan(1, numel(pv));
                for k = 1:numel(pv)
                    u = pv{k}(isfinite(pv{k}) & pv{k} > 0);
                    if ~isempty(u), cv_pixel_mm(k) = median(u) / 1000 / om_bin; end
                end
                if ~all(isfinite(cv_pixel_mm)), cv_pixel_mm = []; end
            end

            % --- read COLMAP cameras + per-view poses ---
            cam = rabbit_rhythm_reproject.read_colmap_cameras(p.ColmapDir);
            imgs = rabbit_rhythm_reproject.read_colmap_images(p.ColmapDir);
            [view_cam, view_names_used] = ...
                rabbit_rhythm_reproject.resolve_view_cameras(imgs, p.ViewCameras);
            result.cameras = cam;
            result.images = imgs;
            result.view_cameras = view_cam;
            result.view_names_used = view_names_used;

            % --- the maps and the cameras must share one image frame ---
            % The cameras are the undistorted-workspace cameras, which
            % image the undistorted frames 1:1, so each per-view map must
            % be either the full camera frame or, when a FovMapping is
            % given, the OM window inside it: the full camera width and
            % rows off_k..off_k+round(nr*sv) (off_k the per-view or common
            % row offset, sv/sh the OM-to-reconstruction pixel scale). A
            % mismatch means the wrong cameras.bin or the wrong map.
            fov_off = 0;
            fov_off_c = 0;
            fov_sv = 1;
            fov_sh = 1;
            per_view = [];
            if ~isempty(p.FovMapping) && isfield(p.FovMapping, 'om_window_in_rec')
                o = p.FovMapping.om_window_in_rec;
                if isfield(o, 'off'), fov_off = o.off; end
                if isfield(o, 'cols_off'), fov_off_c = o.cols_off; end
                if isfield(o, 'per_view_offsets'), per_view = o.per_view_offsets; end
            end
            if ~isempty(p.FovMapping) && isfield(p.FovMapping, 'scale')
                s = p.FovMapping.scale;
                if isfield(s, 'vertical'), fov_sv = s.vertical; end
                if isfield(s, 'horizontal'), fov_sh = s.horizontal; end
            end
            full_frame = false(1, numel(views));
            for k = 1:numel(views)
                vc = view_cam{k};
                cm = [];
                for c = 1:numel(cam)
                    if cam(c).id == vc.camera_id, cm = cam(c); break; end
                end
                if isempty(cm)
                    error('analyse_om:Reprojection:CameraMissing', ...
                        'Camera %d for image ''%s'' not in cameras file.', ...
                        vc.camera_id, vc.name);
                end
                [nr, nc] = size(views{k});
                if nr == cm.height && nc == cm.width
                    % The map is the full camera frame; a FovMapping, if
                    % present, is provenance only and its scale is not
                    % applied to this view.
                    full_frame(k) = true;
                    continue;
                end
                if isempty(p.FovMapping)
                    % Without a FovMapping the map must be the full
                    % camera frame.
                    error('analyse_om:Reprojection:FrameMismatch', ...
                        ['View %d (%s) activation map is %dx%d but camera %d ' ...
                        '(%s) images %dx%d. The activation maps and the ' ...
                        'cameras must be in the same image frame: use the ' ...
                        'undistorted-workspace cameras.bin that images the ' ...
                        'frames the maps were taken from.'], ...
                        k, view_names{k}, nr, nc, cm.id, cm.model, ...
                        cm.height, cm.width);
                else
                    % The map is the OM window of the camera frame: its
                    % reconstruction-frame size is round(nr*sv) x
                    % round(nc*sh) at row off_k. The window is a pure
                    % vertical crop, so the scaled width must equal the
                    % camera width and the window must fit vertically.
                    off_k = fov_off;
                    if ~isempty(per_view) && numel(per_view) >= k
                        off_k = per_view(k);
                    end
                    win_h = round(nr * fov_sv);
                    win_w = round(nc * fov_sh);
                    if off_k < 0 || fov_off_c < 0 || ...
                            win_w ~= cm.width || ...
                            off_k + win_h > cm.height
                        error('analyse_om:Reprojection:FrameMismatch', ...
                            ['View %d (%s) activation map is %dx%d but camera %d ' ...
                            '(%s) images %dx%d. The map must be the full camera ' ...
                            'frame or the OM window (rows off..off+height, ' ...
                            'off=%d, scale %.4g x %.4g) of the undistorted-' ...
                            'workspace camera frame.'], ...
                            k, view_names{k}, nr, nc, cm.id, cm.model, ...
                            cm.height, cm.width, off_k, fov_sv, fov_sh);
                    end
                end
            end

            % A flipped view's shift is negated above, which is exact only
            % when its map is the camera frame itself (the cut tile): for a
            % map that is a window of a larger camera frame the flipped
            % lookup would also need the size difference. Built runs always
            % have cut-tile cameras, so the other case is refused.
            bad_flip = find((flip_lr | flip_ud) & ~full_frame, 1);
            if ~isempty(bad_flip)
                error('analyse_om:Reprojection:FlipNeedsTile', ...
                    ['View %d (%s) is flipped (%s), but its map is not the whole camera frame. ' ...
                    'Flipped views are only supported when the cameras image the cut views themselves ' ...
                    '(a model built by the Reconstruction tab).'], bad_flip, view_names{bad_flip}, ...
                    view_flips{bad_flip});
            end

            % --- read the PLY mesh ---
            mesh = rabbit_rhythm_reproject.read_ply_mesh(p.MeshFile);
            if isempty(mesh.pts) || isempty(mesh.faces)
                error('analyse_om:Reprojection:BadMesh', ...
                    'PLY mesh has no vertices or no triangle faces.');
            end
            result.mesh = mesh;               % as read (COLMAP/APDe-MVS units)
            % UnitScale converts both the camera translations and the
            % mesh points into the RHYTHM millimetre projection space
            % (the vendored pred.m works in mm; reconstructions are
            % typically metre-based -> UnitScale 1000). The exported PLY
            % and result.mesh keep the ORIGINAL units.
            mesh.pts = mesh.pts .* p.UnitScale;
            result.mesh_pts_mm = mesh.pts;

            % --- mesh topology (cells/centroids/normals/neighbours) ---
            [cells, centroids, norms, neighs, neighnum] = ...
                rabbit_rhythm_reproject.build_mesh_topology(mesh.pts, mesh.faces);
            result.cells = cells;
            result.centroids = centroids;
            result.norms = norms;
            result.neighs = neighs;
            result.neighnum = neighnum;

            % --- project ---
            % Per-view scales from the FovMapping (the OM map is the
            % camera-frame window scaled down by 1/sv, 1/sh).
            scales = ones(4, 2);
            if ~isempty(p.FovMapping) && isfield(p.FovMapping, 'scale')
                s = p.FovMapping.scale;
                if isfield(s, 'vertical'), scales(:, 1) = s.vertical; end
                if isfield(s, 'horizontal'), scales(:, 2) = s.horizontal; end
            end
            scales(full_frame, :) = 1;
            use_rhythm = ~strcmp(method, 'reimplementation');
            method_note = '';
            if strcmp(method, 'auto')
                small = false;
                for k = 1:numel(views)
                    small = small || min(size(views{k})) < rabbit_rhythm_reproject.RHYTHM_GRID;
                end
                if small
                    use_rhythm = false;
                    method_note = sprintf(['A view is smaller than %d px, so it would ' ...
                        'be upsampled rather than binned for dataProjection02; ' ...
                        'the native-resolution reimplementation was used.'], ...
                        rabbit_rhythm_reproject.RHYTHM_GRID);
                end
            end
            % Per-view frame stacks, split from the canvas one frame at a
            % time so the full canvas stack is never copied. Each frame is
            % binned to the 100x100 RHYTHM grid straight away (the same
            % area average as the map), so a long recording costs 100x100
            % per view and frame rather than the full view size.
            % A pixel counts only if it is finite in the map and in every
            % frame: one mask per view, so the coverage that divides the
            % binned values is the same for the map and for every frame,
            % and a NaN pixel in some frames cannot pull those frames
            % towards 0. The mask costs one pass over the frames and one
            % logical image, not a second copy of the stack. The map
            % alone (and the reimplementation fallback) keeps its own
            % finite pixels. A frame with no finite pixel where the map
            % has data (e.g. a dropped frame) is left out of the mask, so
            % it cannot blank the map, and its series column is NaN. When
            % the mask still removes more than 5 % of the map's pixels,
            % method_note and a warning say so.
            frame_views = [];
            views_map_only = views;
            empty_frames = [];
            if ~isempty(p.Frames) && use_rhythm
                grid = rabbit_rhythm_reproject.RHYTHM_GRID;
                n_t = size(p.Frames, 3);
                frames_ok = true(size(p.Frames, 1), size(p.Frames, 2));
                map_ok = isfinite(map);
                empty_frames = false(1, n_t);
                for t = 1:n_t
                    fin = isfinite(p.Frames(:, :, t));
                    if ~any(fin(map_ok))
                        empty_frames(t) = true;
                        continue;
                    end
                    frames_ok = frames_ok & fin;
                end
                ok_views = rabbit_rhythm_reproject.split_canvas( ...
                    double(frames_ok), bounds, rotation);
                frame_views = cell(numel(views), 1);
                Ay = cell(numel(views), 1);
                Ax = cell(numel(views), 1);
                valid = cell(numel(views), 1);
                n_map = 0;
                n_kept = 0;
                for k = 1:numel(views)
                    ok_k = ok_views{k};
                    if flip_rows(k), ok_k = flipud(ok_k); end
                    if flip_lr(k), ok_k = fliplr(ok_k); end
                    if flip_ud(k), ok_k = flipud(ok_k); end
                    valid{k} = isfinite(views{k}) & ok_k > 0.5;
                    n_map = n_map + nnz(isfinite(views{k}));
                    n_kept = n_kept + nnz(valid{k});
                    views{k}(~valid{k}) = NaN;
                    frame_views{k} = zeros(grid, grid, n_t);
                    Ay{k} = rabbit_rhythm_reproject.area_matrix(size(views{k}, 1), grid);
                    Ax{k} = rabbit_rhythm_reproject.area_matrix(size(views{k}, 2), grid);
                end
                for t = 1:n_t
                    fv = rabbit_rhythm_reproject.split_canvas( ...
                        double(p.Frames(:, :, t)), bounds, rotation);
                    for k = 1:numel(views)
                        f = fv{k};
                        if flip_rows(k), f = flipud(f); end
                        if flip_lr(k), f = fliplr(f); end
                        if flip_ud(k), f = flipud(f); end
                        f(~valid{k} | ~isfinite(f)) = 0;
                        frame_views{k}(:, :, t) = Ay{k} * f * Ax{k}';
                    end
                end
                if any(empty_frames)
                    method_note = sprintf(['%d of %d OM frames have no data on the map ' ...
                        '(frames %s); they are NaN in the projected video.'], ...
                        nnz(empty_frames), n_t, mat2str(find(empty_frames)));
                end
                if n_map > 0 && (n_map - n_kept) / n_map > 0.05
                    mask_note = sprintf(['%.1f %% of the activation map''s pixels are left out ' ...
                        'because they have no data in some OM frame ("Map and video" keeps only ' ...
                        'pixels valid in every frame).'], 100 * (n_map - n_kept) / n_map);
                    method_note = strtrim([method_note ' ' mask_note]);
                end
                if ~isempty(method_note)
                    warning('analyse_om:Reprojection:FrameMask', '%s', method_note);
                end
            end
            series = [];
            % For the CV direction, dataProjection02 also projects three
            % frames per view (cv_direction_frames): that view's component
            % coverage and its two components, zero in the other views. The
            % speed (the map) is projected exactly as without them.
            dir_series = [];
            ledge_fb = [];
            kernels_fb = {};
            if want_dir && use_rhythm
                frame_views = rabbit_rhythm_reproject.cv_direction_frames(views, cv_views);
            end
            if use_rhythm
                try
                    out = rabbit_rhythm_reproject.project_views_rhythm( ...
                        views, cam, view_cam, cells, centroids, norms, ...
                        neighs, neighnum, p.UnitScale, p.Shifts, mesh.pts, ...
                        scales, frame_views, p.Fps, min_edge_edge);
                    dataProj = out.dataProj;
                    viewi = out.viewi;
                    mask = out.mask;
                    series = out.series;
                    if want_dir
                        % Those frames are not an OM video
                        dir_series = series;
                        series = [];
                    end
                    if ~isempty(series) && any(empty_frames)
                        series(:, empty_frames) = NaN;
                    end
                    result.textProj = out.textProj;
                    result.rhythm = rmfield(out, {'dataProj', 'viewi', 'mask', 'series'});
                    result.method = 'rhythm';
                catch ME
                    if strcmp(method, 'rhythm'), rethrow(ME); end
                    use_rhythm = false;
                    method_note = sprintf(['dataProjection02 could not complete (%s); ' ...
                        'the native-resolution reimplementation was used.'], ME.message);
                end
            end
            if ~use_rhythm
                views = views_map_only;
                [dataProj, viewi, mask, ledge_fb, kernels_fb] = rabbit_rhythm_reproject.project_views( ...
                    views, cam, view_cam, cells, centroids, norms, ...
                    neighs, neighnum, p.UnitScale, p.Shifts, mesh.pts, scales, min_edge_edge);
                % A face is assigned when it has a view and a value: faces
                % with a view but no valid source data are 0 too. This is
                % dataProjection02's own convention (its output holds 0 for
                % an unassigned face), so a genuine activation time of
                % exactly 0 ms is dropped as unassigned on this path. The
                % dataProjection02 path keeps it (it uses the coverage).
                mask = mask & isfinite(dataProj) & dataProj ~= 0;
                result.method = 'reimplementation';
                if ~isempty(p.Frames)
                    method_note = strtrim([method_note ' The frame stack was not ' ...
                        'projected (the reimplementation maps the activation map only).']);
                end
                if ~isempty(method_note)
                    warning('analyse_om:Reprojection:Fallback', '%s', method_note);
                end
            end
            % With a cut asked for, faces whose projected activation is
            % above it get no CV (unassigned, as faces without data);
            % without one (the default) nothing is left out
            if strcmp(quantity, 'cv_speed') && ~isempty(p.CvActivationCut)
                [mask, dataProj, cut_rec] = rabbit_rhythm_reproject.cv_activation_cut_faces( ...
                    p.CvActivationCut, size(map), mask, dataProj, result.method, bounds, rotation, ...
                    flip_rows, flip_lr, flip_ud, cam, view_cam, cells, centroids, norms, neighs, ...
                    neighnum, p.UnitScale, p.Shifts, mesh.pts, scales, p.Fps, min_edge_edge);
                if ~isempty(cut_rec), result.cv_activation_cut = cut_rec; end
            end
            % A changed edge threshold is said and kept as a deviation
            result.quantity = quantity;
            if ~isempty(p.DisplayLimits)
                result.display_limits = rabbit_rhythm_reproject.check_display_limits(p.DisplayLimits);
            end
            result.pacing_cycle_ms = rabbit_rhythm_reproject.check_pacing_cycle(p.PacingCycleMs);
            if isstruct(p.RecordingRhythm) && isfield(p.RecordingRhythm, 'state')
                result.recording_rhythm = p.RecordingRhythm;
            end
            % What time 0 of the activation map is
            if strcmp(quantity, 'activation')
                result.activation_zero = rabbit_activation_zero.check(p.ActivationZero);
            end
            if strcmp(quantity, 'cv_speed') && isstruct(p.CvActivationSpread)
                result.cv_activation_spread = p.CvActivationSpread;
            end
            % The CV map's settings, under the names the captions read
            % (rabbit_cv_map.record_fields)
            if strcmp(quantity, 'cv_speed') && isstruct(p.CvSettings)
                result.cv_settings = p.CvSettings;
            end
            result.min_edge_edge = min_edge_edge;
            result.deviations = struct('parameter', {}, 'old', {}, 'new', {}, 'rationale', {});
            edge_note = '';
            if min_edge_edge ~= rabbit_rhythm_reproject.MIN_EDGE_EDGE
                edge_note = sprintf(['Edge threshold %.2f (RHYTHM %.2f): faces no camera sees directly ' ...
                    'take the views whose edge weight is at least %.2f.'], min_edge_edge, ...
                    rabbit_rhythm_reproject.MIN_EDGE_EDGE, min_edge_edge);
                result.deviations(1).parameter = 'minedgeEDGE';
                result.deviations(1).old = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
                result.deviations(1).new = min_edge_edge;
                result.deviations(1).rationale = rabbit_rhythm_reproject.EDGE_RATIONALE;
            end
            result.method_note = strtrim([bin_note ' ' edge_note ' ' method_note]);
            % Confidence class of each face. Class 4 (low confidence) is an
            % EDGE face that is
            % assigned only because the edge threshold is below RHYTHM's
            % 0.55: the faces this projection has as EDGE but a projection
            % at 0.55 does not. That projection is made here, map only.
            low = false(numel(mask), 1);
            if min_edge_edge < rabbit_rhythm_reproject.MIN_EDGE_EDGE && ~isempty(viewi)
                nv_c = size(viewi, 2) - 1;
                edge_now = viewi(:, end) == nv_c + 2 & logical(mask(:));
                if any(edge_now)
                    if strcmp(result.method, 'rhythm')
                        out55 = rabbit_rhythm_reproject.project_views_rhythm( ...
                            views, cam, view_cam, cells, centroids, norms, ...
                            neighs, neighnum, p.UnitScale, p.Shifts, mesh.pts, ...
                            scales, [], p.Fps, rabbit_rhythm_reproject.MIN_EDGE_EDGE);
                        viewi55 = out55.viewi;
                    else
                        [~, viewi55] = rabbit_rhythm_reproject.project_views( ...
                            views, cam, view_cam, cells, centroids, norms, ...
                            neighs, neighnum, p.UnitScale, p.Shifts, mesh.pts, scales, ...
                            rabbit_rhythm_reproject.MIN_EDGE_EDGE);
                    end
                    low = edge_now & viewi55(:, end) ~= nv_c + 2;
                end
            end
            result.face_class = rabbit_rhythm_reproject.face_confidence(viewi, mask, low);
            result.confidence = rabbit_rhythm_reproject.confidence_record(result.face_class, min_edge_edge);
            % Display only: does each view's projection reproduce its
            % 2-D map? The IQR of the faces it sees
            % directly against the IQR of its map
            if strcmp(quantity, 'activation')
                result.activation_consistency = rabbit_rhythm_reproject.activation_consistency( ...
                    views_map_only, dataProj, viewi, mask, rabbit_rhythm_reproject.row_views_of(payload));
            end
            result.dataProj = dataProj;   % nFaces x 1 activation ms (0 = unassigned)
            result.viewi = viewi;         % nFaces x (nViews+1) RHYTHM convention
            result.mask = mask;           % nFaces x 1 assigned faces
            result.series = series;       % nFaces x T (NaN = unassigned), or []
            result.fps = p.Fps;
            result.pts_mm = mesh.pts;     % mm-space vertices (export/tests)
            result.shifts = p.Shifts;     % per-view pixel shifts applied
            result.fov_mapping = p.FovMapping; % recorded in the manifest
            result.frame_check = p.FrameCheck; % om_frame_check record (manifest)
            if want_dir
                % A 3D unit direction in the surface per assigned face
                [result.cv_dir, result.cv_direction, result.cv_n_views, result.cv_view_weights, surf_f] = ...
                    rabbit_rhythm_reproject.cv_face_directions( ...
                    result.method, dir_series, ledge_fb, kernels_fb, viewi, mask, cv_views, ...
                    cam, view_cam, centroids, norms, cells, mesh.pts, p.UnitScale, p.Shifts, scales, cv_pixel_mm);
                result.cv_direction.canvas_from_view = cv_axes;
                % The tilt-corrected surface speed next to the image-plane
                % one: each assigned face's
                % projected speed times its factor (lift_speed, 1/|A'g|)
                result.cv_speed_surface = [];
                if ~isempty(cv_pixel_mm)
                    sp = double(dataProj(:));
                    sp(~logical(mask(:)) | ~(sp > 0)) = NaN;
                    result.cv_speed_surface = sp .* surf_f;
                    % No surface speed where the tilt correction is above
                    % SURFACE_MAX_CORRECTION (steep faces, where it rests
                    % most on the pose); the image-plane speed (sp, the
                    % projected map) is kept
                    steep = isfinite(sp) & surf_f(:) > rabbit_rhythm_reproject.SURFACE_MAX_CORRECTION;
                    result.cv_speed_surface(steep) = NaN;
                    result.cv_direction.surface_speed = rabbit_rhythm_reproject.surface_speed_record( ...
                        sp, result.cv_speed_surface, cv_pixel_mm, om_bin, nnz(steep));
                end
            end
            if use_rhythm
                n_assigned = nnz(mask);
            else
                n_assigned = nnz(~isnan(dataProj) & dataProj ~= 0);
            end
            % Assigned faces per view (RHYTHM viewi: columns 1..nViews say
            % which views a face took data from; the last column is the
            % view of a DIRECT face, nViews+1 OVERLAP, nViews+2 EDGE). A
            % face averaged over several views counts for each of them.
            nv = numel(views);
            per_view = zeros(1, nv);
            kinds = zeros(1, 3);
            if ~isempty(viewi) && size(viewi, 2) == nv + 1
                if use_rhythm
                    got = mask(:);
                else
                    got = ~isnan(dataProj) & dataProj ~= 0;
                end
                per_view = sum(viewi(got, 1:nv) > 0, 1);
                last = viewi(got, end);
                kinds = [nnz(last >= 1 & last <= nv), nnz(last == nv + 1), nnz(last == nv + 2)];
            end
            result.stats = struct( ...
                'nFaces', size(dataProj, 1), ...
                'nAssigned', n_assigned, ...
                'nAssignedPerView', per_view, ...
                'nDirectOverlapEdge', kinds, ...
                'nViews', numel(views), ...
                'nFrames', size(series, 2), ...
                'colmapDir', p.ColmapDir, 'meshFile', p.MeshFile);

            % --- exports ---
            if ~isempty(p.OutDir)
                if ~isfolder(p.OutDir), mkdir(p.OutDir); end
                % File names and the PLY property of the quantity
                if strcmp(quantity, 'cv_speed')
                    stem = 'cv'; prop = 'cv_speed'; tag = 'om_cv_speed';
                    manifest_name = 'cv_reprojection_manifest.json';
                else
                    stem = 'activation'; prop = 'activation'; tag = 'om_activation';
                    manifest_name = 'reprojection_manifest.json';
                end
                if p.ExportCdf
                    result.cdf_path = rabbit_rhythm_reproject.write_cdf( ...
                        fullfile(p.OutDir, [stem '_projected.cdf']), ...
                        dataProj, tag);
                end
                if p.ExportPly
                    result.ply_path = rabbit_rhythm_reproject.write_projected_ply( ...
                        fullfile(p.OutDir, [stem '_projected.ply']), ...
                        result.mesh, dataProj, mask, prop);
                end
                % The confidence classes (the video uses the map's faces,
                % so it shares activation_confidence.mat)
                face_class = result.face_class; %#ok<NASGU>
                class_names = rabbit_rhythm_reproject.CLASS_NAMES; %#ok<NASGU>
                % The views each face took its value from (faces x views,
                % ROI order, 1 = used) and the views' names, for the
                % per-face CSV
                face_views = zeros(numel(mask), numel(views), 'uint8');
                if ~isempty(viewi) && size(viewi, 2) == numel(views) + 1
                    face_views = uint8(viewi(:, 1:numel(views)) > 0 & logical(mask(:)));
                end
                view_names = result.view_names; %#ok<NASGU>
                conf_path = fullfile(p.OutDir, [stem '_confidence.mat']);
                save(conf_path, 'face_class', 'class_names', 'face_views', 'view_names');
                [~, cn, ce] = fileparts(conf_path);
                result.confidence.file = [cn ce];
                if want_dir
                    % The direction and the speed it goes with, per face
                    direction = result.cv_dir; %#ok<NASGU>
                    speed = dataProj(:);
                    speed(~mask(:)) = NaN; %#ok<NASGU>
                    n_views = result.cv_n_views; %#ok<NASGU>
                    view_weights = single(result.cv_view_weights); %#ok<NASGU>
                    note = result.cv_direction.summary; %#ok<NASGU>
                    vars = {'direction', 'speed', 'n_views', 'view_weights', 'note'};
                    if isfield(result, 'cv_speed_surface') && ~isempty(result.cv_speed_surface)
                        % next to speed (image plane), per face, m/s
                        speed_surface = result.cv_speed_surface; %#ok<NASGU>
                        vars{end + 1} = 'speed_surface';
                    end
                    save(fullfile(p.OutDir, 'cv_direction.mat'), vars{:});
                    result.cv_direction.file = 'cv_direction.mat';
                    result.cv_direction_path = fullfile(p.OutDir, 'cv_direction.mat');
                end
                if ~isempty(series)
                    result.video_path = rabbit_rhythm_reproject.write_video_mat( ...
                        fullfile(p.OutDir, 'om_video_projected.mat'), ...
                        result.mesh, series, mask, p.Fps, result.method);
                end
                result.manifest_path = fullfile(p.OutDir, manifest_name);
                rabbit_rhythm_reproject.write_manifest(result.manifest_path, result);
            end
        end

        function result = run_from_app(app)
            %RUN_FROM_APP GUI entry point. Asks for the saved ROI JSON,
            %the COLMAP model folder, the mesh and an output folder, then
            %projects the current activation map and, if the user wants
            %it, the current OM frame stack as a video on the mesh.
            %The button that calls this lives in analyse_optical_mapping.
            result = [];
            fig = app.opticalmappingUIFigure;
            if isempty(app.processed_data.activation_map)
                uialert(fig, 'Generate an activation map first (Activation Map tab).', ...
                    'RHYTHM reprojection');
                return;
            end
            [f, pth] = uigetfile(fullfile(app.file_info.path, '*.json'), ...
                'Load ROI file (rabbit panoramic JSON)');
            if isequal(f, 0), return; end
            json_path = fullfile(pth, f);
            cdir = uigetdir(app.file_info.path, 'COLMAP model folder (cameras/images)');
            if isequal(cdir, 0), return; end
            % Start next to the COLMAP model, where a run keeps its mesh
            [mf, mp] = uigetfile(fullfile(fileparts(cdir), '*.ply'), 'Reconstruction mesh (PLY)');
            if isequal(mf, 0), return; end
            outdir = uigetdir(app.file_info.path, 'Reprojection output folder');
            if isequal(outdir, 0), return; end
            % Doing this again must not replace an earlier projection
            outdir = rabbit_rhythm_reproject.free_output_folder(outdir);
            % The OM frame stack on the same canvas as the activation map
            % (the current normalisation) can be projected as a video.
            map = app.processed_data.activation_map;
            frames = [];
            fps = 1;
            try
                stack = app.processed_data.image_stack{app.display.normalisation};
            catch
                stack = [];
            end
            if isempty(stack)
                video_note = 'No OM frames are loaded.';
            elseif ndims(stack) ~= 3 || size(stack, 1) ~= size(map, 1) || ...
                    size(stack, 2) ~= size(map, 2)
                video_note = sprintf(['The OM frames (%s) are not the same ' ...
                    'size as the activation map (%s).'], mat2str(size(stack)), ...
                    mat2str(size(map)));
            else
                video_note = '';
            end
            if isempty(video_note)
                % In front of the main window, not hidden behind it after
                % the file selectors
                if strcmp(get(fig, 'Visible'), 'on'), figure(fig); end
                choice = uiconfirm(fig, sprintf(['Also project the OM video ' ...
                    '(%d frames) onto the mesh? This takes longer than the ' ...
                    'activation map alone, and with the video the map keeps only ' ...
                    'the pixels that have data in every frame.'], size(stack, 3)), ...
                    'RHYTHM reprojection', 'Options', ...
                    {'Map and video', 'Map only', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 3);
            else
                choice = uiconfirm(fig, ['The OM video cannot be projected. ' ...
                    video_note ' Only the activation map will be projected.'], ...
                    'RHYTHM reprojection', 'Options', {'Map only', 'Cancel'}, ...
                    'DefaultOption', 1, 'CancelOption', 2);
            end
            if strcmp(choice, 'Cancel')
                return;
            end
            if strcmp(choice, 'Map and video')
                frames = stack;
                fps = app.data.fps;
            end
            % A model built by the Reconstruction tab may image flipped
            % views; its om_tile_transform.json (in or next to the model
            % folder, or in the run it belongs to) says which, and the same
            % flips are applied here. A model of a run that built its
            % sparse model without the file is refused; a model of cut
            % images without it is projected unflipped only when the user
            % says so.
            try
                [view_flips, flip_note, flip_info] = rabbit_rhythm_reproject.tile_transform_flips(cdir);
            catch ME
                uialert(fig, ME.message, 'RHYTHM reprojection');
                return;
            end
            if isempty(flip_info.path) && rabbit_rhythm_reproject.cut_named_model(cdir)
                choice = uiconfirm(fig, ['This model''s images are named like the cut images of the ' ...
                    'Reconstruction tab, but there is no om_tile_transform.json with it. If the model was ' ...
                    'built by the tab ("Build sparse model"), its outer views are flipped and would be ' ...
                    'projected mirrored: copy om_tile_transform.json from stages/sparse_build of its run into ' ...
                    'the model folder first. Project the views unflipped?'], 'RHYTHM reprojection', ...
                    'Options', {'Project unflipped', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, 'Project unflipped'), return; end
            end
            % FITS recordings are loaded upside down; the cut tiles are not
            % (OM row flip in the class header). Same rule as the tab.
            [flip_rows, shifts] = rabbit_rhythm_reproject.app_row_flip(app, json_path);
            progress = uiprogressdlg(fig, 'Title', 'RHYTHM reprojection', ...
                'Message', 'Choosing the frame of the cameras...', ...
                'Indeterminate', 'on');
            [run_dir_m, ~] = rabbit_rhythm_reproject.enclosing_run(cdir);
            mask_dir = '';
            if ~isempty(run_dir_m) && isfolder(fullfile(run_dir_m, 'stages', 'sparse_build', 'score_masks'))
                mask_dir = fullfile(run_dir_m, 'stages', 'sparse_build', 'score_masks');
            end
            try
                chk = rabbit_rhythm_reproject.om_frame_check( ...
                    rabbit_rhythm_reproject.om_image_from_app(app), json_path, cdir, fullfile(mp, mf), ...
                    'FlipRows', flip_rows, 'ViewFlips', view_flips, 'Shifts', shifts, ...
                    'MaskDir', mask_dir, 'ImagesDir', fullfile(fileparts(cdir), 'images'), ...
                    'Frame', rabbit_rhythm_reproject.app_pose_frame(app));
            catch ME
                close(progress);
                uialert(fig, sprintf('The frame of the cameras could not be chosen: %s', ME.message), ...
                    'RHYTHM reprojection');
                return;
            end
            if strcmp(chk.verdict, 'FAIL')
                close(progress);
                choice = uiconfirm(fig, sprintf(['Projection check failed: %s The OM views and the ' ...
                    'reconstruction views do not show the heart in the same position (or a view is ' ...
                    'mirrored). Project anyway?'], chk.summary), 'RHYTHM reprojection', ...
                    'Options', {'Project anyway', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, 'Project anyway'), return; end
                progress = uiprogressdlg(fig, 'Title', 'RHYTHM reprojection', ...
                    'Indeterminate', 'on');
            end
            progress.Message = 'Projecting the OM data onto the mesh...';
            try
                result = rabbit_rhythm_reproject.run(map, json_path, ...
                    'ColmapDir', cdir, 'MeshFile', fullfile(mp, mf), ...
                    'Frames', frames, 'Fps', fps, 'OutDir', outdir, ...
                    'ViewFlips', view_flips, 'FlipRows', flip_rows, 'Shifts', shifts, ...
                    'ViewCameras', chk.view_cameras, 'FrameCheck', chk, ...
                    'DisplayLimits', rabbit_rhythm_reproject.app_display_limits(app), ...
                    'ActivationZero', rabbit_activation_zero.of(app), ...
                    'MinEdgeEdge', rabbit_rhythm_reproject.app_min_edge_edge(app));
                % The conduction velocity speed, when the Conduction
                % Velocity tab has a map on this canvas
                cv_msg = '';
                [cv_speed, cv_why] = rabbit_rhythm_reproject.app_cv_speed(app, map);
                if ~isempty(cv_speed)
                    try
                        cv_res = rabbit_rhythm_reproject.run(cv_speed, json_path, ...
                            'ColmapDir', cdir, 'MeshFile', fullfile(mp, mf), ...
                            'Quantity', 'cv_speed', 'OutDir', outdir, ...
                            'CvComponents', double(app.processed_data.CV_map(:, :, 1:2)), ...
                            'ViewFlips', view_flips, 'FlipRows', flip_rows, 'Shifts', shifts, ...
                            'ViewCameras', chk.view_cameras, 'FrameCheck', chk, ...
                            'DisplayLimits', rabbit_rhythm_reproject.app_display_limits(app), ...
                            'CvActivationSpread', rabbit_rhythm_reproject.app_cv_spread(app), ...
                            'CvPixelUm', rabbit_rhythm_reproject.app_cv_pixel_um(app), ...
                            'CvSettings', rabbit_cv_map.record_fields(app.processed_data.CV_settings), ...
                            'CvActivationCut', rabbit_rhythm_reproject.app_cv_cut(app, map), ...
                            'MinEdgeEdge', rabbit_rhythm_reproject.app_min_edge_edge(app));
                        cv_msg = sprintf('Conduction velocity: %d of %d faces assigned.', ...
                            cv_res.stats.nAssigned, cv_res.stats.nFaces);
                    catch ME_cv
                        cv_msg = sprintf('Conduction velocity not projected: %s', ME_cv.message);
                    end
                elseif ~isempty(cv_why)
                    cv_msg = ['Conduction velocity not projected: ' cv_why];
                end
                close(progress);
                msg = sprintf('%d of %d mesh faces assigned.', ...
                    result.stats.nAssigned, result.stats.nFaces);
                if ~isempty(cv_msg)
                    msg = sprintf('%s\n%s', msg, cv_msg);
                end
                if ~isempty(chk.summary)
                    msg = sprintf('%s\n%s', msg, chk.summary);
                end
                if result.stats.nFrames > 0
                    msg = sprintf('%s\nVideo: %d frames.', msg, result.stats.nFrames);
                end
                if ~isempty(result.method_note)
                    msg = sprintf('%s\n%s', msg, result.method_note);
                end
                if ~isempty(flip_note)
                    msg = sprintf('%s\n%s', msg, flip_note);
                end
                % These files are not part of a reconstruction run, so the
                % run's Visualise window does not show them
                uialert(fig, sprintf(['%s\nSaved to: %s\nThese files belong to no reconstruction run: the ' ...
                    'Visualise window of a run does not show them. Open them from this folder.'], msg, outdir), ...
                    'RHYTHM reprojection', 'Icon', 'success');
            catch ME
                close(progress);
                uialert(fig, sprintf('RHYTHM reprojection failed: %s', ME.message), ...
                    'RHYTHM reprojection');
            end
        end

        function out = free_output_folder(folder)
            %FREE_OUTPUT_FOLDER Folder for a projection that replaces nothing
            %   A new folder 'reprojection' inside the chosen one, numbered
            %   when it is taken (reprojection_01, _02 ...), so each
            %   projection has a folder of its own and nothing lands next to
            %   the recordings. The folder used is
            %   shown when the projection is done.
            out = rabbit_stack_io.next_free_path(fullfile(char(folder), 'reprojection'));
        end

        function [flips, note, info] = tile_transform_flips(colmap_dir)
            %TILE_TRANSFORM_FLIPS View flips of a model whose tiles the tab flipped
            %   A model built by the Reconstruction tab images flipped outer
            %   tiles; om_tile_transform.json says how. The tab writes it
            %   into stages/sparse_build, the model folder and the
            %   undistorted workspace (dense/ and dense/sparse), and a run
            %   that uses such a model as an existing sparse model keeps it
            %   with its input snapshot. When colmap_dir lies inside a run
            %   folder, the file that run uses (run_transform_path) is taken
            %   first; else colmap_dir, then its parent.
            %   flips: {} when there is no file (no flips); note: what was
            %   applied, for the user; info.path: the file used ('' none),
            %   info.run_dir: the run folder colmap_dir lies in ('' none),
            %   info.built: true when that run built its sparse model.
            %   Errors (projecting without the flips would mirror views):
            %   analyse_om:Reprojection:TileTransform when the file cannot be read, and
            %   analyse_om:Reprojection:TileTransformMissing when colmap_dir lies in a
            %   run that built its sparse model but no file is found.
            flips = {};
            note = '';
            info = struct('path', '', 'run_dir', '', 'built', false);
            [run_dir, built] = rabbit_rhythm_reproject.enclosing_run(colmap_dir);
            info.run_dir = run_dir;
            info.built = built;
            % Inside a run, the run's own file comes first: it is the one
            % the run recorded with its sha256 (verify_built_inputs), while
            % the copies in the workspace are not hashed. A loose copy that
            % differs from it is named in note.
            loose = {fullfile(colmap_dir, 'om_tile_transform.json'), ...
                fullfile(fileparts(colmap_dir), 'om_tile_transform.json')};
            pinned = '';
            if ~isempty(run_dir)
                pinned = rabbit_rhythm_reproject.run_transform_path(run_dir);
            end
            cands = [{pinned}, loose];
            hit = '';
            for c = 1:numel(cands)
                if ~isempty(cands{c}) && exist(cands{c}, 'file') == 2
                    hit = cands{c};
                    break;
                end
            end
            differ = {};
            if ~isempty(hit) && strcmp(hit, pinned)
                for c = 1:numel(loose)
                    if exist(loose{c}, 'file') == 2 && ~isequal(rabbit_rhythm_reproject.file_bytes(loose{c}), ...
                            rabbit_rhythm_reproject.file_bytes(pinned))
                        differ{end+1} = loose{c}; %#ok<AGROW>
                    end
                end
            end
            if isempty(hit)
                if built
                    error('analyse_om:Reprojection:TileTransformMissing', ...
                        ['%s belongs to a run that built its sparse model (%s), so its outer views are ' ...
                        'flipped, but om_tile_transform.json is missing (looked in the model folder, its ' ...
                        'parent and stages/sparse_build of the run). Without it the outer views would be ' ...
                        'projected mirrored. Restore the file from the run, or build the model again.'], ...
                        colmap_dir, run_dir);
                end
                return;
            end
            flips = rabbit_rhythm_reproject.read_tile_transform(hit);
            info.path = hit;
            if any(~strcmp(flips, 'none'))
                note = sprintf(['The cameras of this model see some views flipped (%s, per ' ...
                    'ROI row, from %s); the activation map and frames of those views ' ...
                    'were flipped the same way.'], strjoin(flips, ', '), hit);
            end
            if ~isempty(differ)
                note = strtrim(sprintf(['%s The copy %s differs from the run''s own file and was not ' ...
                    'used.'], note, strjoin(differ, ' and ')));
            end
        end

        function b = file_bytes(path)
            %FILE_BYTES The bytes of a file ([] when it cannot be read)
            b = [];
            fid = fopen(path, 'rb');
            if fid < 0, return; end
            b = fread(fid, Inf, '*uint8');
            fclose(fid);
        end

        function tf = cut_named_model(colmap_dir)
            %CUT_NAMED_MODEL True when the model's images carry the cut names (..._view<k>_frame_<n>)
            tf = false;
            try
                imgs = rabbit_rhythm_reproject.read_colmap_images(colmap_dir);
                tf = ~isempty(imgs) && all(~cellfun(@isempty, regexp({imgs.name}, '_view[1-4]_frame_\d+', 'once')));
            catch
                tf = false;
            end
        end

        function [flip_rows, shifts] = app_row_flip(app, json_path)
            %APP_ROW_FLIP OM row flip and cut-tile shifts for the loaded recording
            % The tab's rule (rabbit_reconstruction_tab.om_row_flip and the
            % cut-tile shift r1 + r2 - H - 1): FITS recordings are loaded
            % upside down. The decision is the app's own when it has one,
            % else the ROI JSON's om_rows_flipped, else the file type.
            flip_rows = false;
            try
                flip_rows = logical(app.recon.reconstruction_om_rows_flipped());
            catch
                try
                    raw = jsondecode(fileread(json_path));
                    if isfield(raw, 'om_rows_flipped')
                        flip_rows = logical(raw.om_rows_flipped);
                    else
                        [~, ~, ext] = fileparts(app.file_info.file);
                        flip_rows = strcmpi(ext, '.fits');
                    end
                catch
                    flip_rows = false;
                end
            end
            shifts = zeros(4, 2);
            if ~flip_rows, return; end
            payload = rabbit_stack_io.load_roi_json(json_path, [], []);
            b = double(payload.region_bounds_src);
            H = double(payload.source_dims.height);
            for k = 1:4
                shifts(k, 2) = b(k, 1) + b(k, 3) - H - 1;
            end
        end

        function f = app_pose_frame(app)
            %APP_POSE_FRAME The tab's "OM pose frame" setting ([] = automatic)
            % A frame number typed in the drop-down, else [] (automatic, or
            % an app without the control).
            f = [];
            try
                v = app.recon.ReconstructionOmPoseFrameDropDown.Value;
            catch
                return;
            end
            v = str2double(v);
            if isfinite(v) && v > 0 && v == round(v)
                f = v;
            end
        end

        function img = om_image_from_app(app)
            %OM_IMAGE_FROM_APP OM image on the activation map's canvas, tissue bright
            % The tissue outline of the OM views is taken from it
            % (om_frame_check). The outline is geometry, so the image is
            % the first loaded frame as the regions cut it, before any
            % processing (app.first_processed_frame): processing changes
            % values only, and Assisted area segmentation sets everything
            % outside its polygons to NaN, which would leave the outline
            % rule to split the heart itself (the projection check then
            % fails on the reference rabbit data). Mirror and Rotate move
            % the pixels after the cut, so
            % with either in the history, or a frame of another size, the
            % image is the mean of the unnormalised stack (image_stack{1};
            % turned back when Invert data is on), with pixels outside the
            % kept area set to the darkest kept value. [] when there is none.
            img = [];
            try
                stack = app.processed_data.image_stack{1};
                if isempty(stack) || ndims(stack) < 2, return; end
                raw = [];
                if isprop(app, 'first_processed_frame')
                    raw = app.first_processed_frame;
                end
                hist = '';
                if isfield(app.history, 'current'), hist = char(app.history.current); end
                moved = contains(hist, 'mirrored', 'IgnoreCase', true) || contains(hist, 'Rotate');
                if ~isempty(raw) && ~moved && isequal(size(raw, 1, 2), size(stack, 1, 2)) && ...
                        all(isfinite(raw(:)))
                    img = double(raw);
                    return;
                end
                img = mean(double(stack), 3, 'omitnan');
                if isfield(app.display, 'inversion') && logical(app.display.inversion)
                    img = max(img(:)) - img;
                end
                fin = isfinite(img);
                if any(fin(:)) && ~all(fin(:))
                    img(~fin) = min(img(fin));
                end
            catch
                img = [];
            end
        end

        function [flips, T] = read_tile_transform(path)
            %READ_TILE_TRANSFORM Flip codes per ROI row from om_tile_transform.json
            % Errors (analyse_om:Reprojection:TileTransform) when the file is unreadable
            % or does not hold four views with flip_lr and flip_ud.
            try
                T = jsondecode(fileread(path));
                v = T.views;
                if iscell(v), v = [v{:}]; end
                if numel(v) ~= 4 || ~isfield(v, 'flip_lr') || ~isfield(v, 'flip_ud')
                    error('analyse_om:Reprojection:TileTransform', 'it does not list four views with flip_lr and flip_ud');
                end
                flips = rabbit_sfm_build.view_flips(v);
                T.views = v;
            catch ME
                error('analyse_om:Reprojection:TileTransform', ...
                    ['Could not read the view flips in %s (%s). Without them the outer views of a model ' ...
                    'built by the Reconstruction tab would be projected mirrored; restore the file from ' ...
                    'the run.'], path, ME.message);
            end
        end

        function p = run_transform_path(run_dir)
            %RUN_TRANSFORM_PATH The om_tile_transform.json a run's cameras go with
            % A run that built its sparse model: stages/sparse_build. A run
            % on an existing sparse model: the copy in its input snapshot
            % (inputs/sparse, or inputs/om_tile_transform.json when the
            % file came from the model's run folder). '' when none exists.
            [~, built] = rabbit_rhythm_reproject.enclosing_run(run_dir);
            if built
                p = fullfile(run_dir, 'stages', 'sparse_build', 'om_tile_transform.json');
                return;
            end
            p = '';
            cands = {fullfile(run_dir, 'inputs', 'sparse', 'om_tile_transform.json'), ...
                fullfile(run_dir, 'inputs', 'om_tile_transform.json')};
            for c = 1:numel(cands)
                if exist(cands{c}, 'file') == 2
                    p = cands{c};
                    return;
                end
            end
        end

        function [run_dir, built] = enclosing_run(folder)
            %ENCLOSING_RUN The Reconstruction run folder that holds folder
            % A run folder has manifest.json and a stages folder; folder
            % may be the run folder itself or lie up to five levels below
            % it. built: its manifest says the run built its sparse model
            % (pipeline.sparse_source 'built').
            run_dir = '';
            built = false;
            d = char(folder);
            for up = 0:5
                if isempty(d), break; end
                if exist(fullfile(d, 'manifest.json'), 'file') == 2 && isfolder(fullfile(d, 'stages'))
                    run_dir = d;
                    try
                        m = jsondecode(fileread(fullfile(d, 'manifest.json')));
                        built = isfield(m, 'pipeline') && isstruct(m.pipeline) && ...
                            isfield(m.pipeline, 'sparse_source') && strcmp(m.pipeline.sparse_source, 'built');
                    catch
                        % an unreadable manifest: the stages folder decides
                        built = isfolder(fullfile(d, 'stages', 'sparse_build'));
                    end
                    return;
                end
                parent = fileparts(d);
                if strcmp(parent, d), break; end
                d = parent;
            end
        end

        % =============================================================
        % 1b. Which frame's cameras project the OM views, and checks
        % =============================================================

        function L = frame_check_limits()
            %FRAME_CHECK_LIMITS Limits of om_frame_check (see its header)
            L = struct('pose_iou_fail', 0.70, 'pose_iou_warn', 0.85, 'covered_warn', 0.80, ...
                'min_points', 15, 'ambiguity_margin', 0.05, 'ambiguity_deg', 10);
        end

        function views = om_camera_views(img, bounds, rotation, flip_rows, view_flips, shifts, cam_hw)
            %OM_CAMERA_VIEWS An OM canvas image per view, in the camera frame
            % The same chain as run(): split_canvas, FlipRows, ViewFlips
            % (with the shift turned round on the flipped axis) and the
            % per-view shift [dx dy] (camera pixel (r, c) reads OM view
            % pixel (r + dy, c + dx)). cam_hw: 4 x 2 camera sizes. Pixels
            % without an OM pixel are NaN.
            v = rabbit_rhythm_reproject.split_canvas(double(img), bounds, rotation);
            flip_rows = logical(flip_rows(:)');
            if isscalar(flip_rows), flip_rows = repmat(flip_rows, 1, 4); end
            if isempty(view_flips), view_flips = repmat({'none'}, 1, 4); end
            if isempty(shifts), shifts = zeros(4, 2); end
            views = cell(1, 4);
            for k = 1:4
                m = v{k};
                dx = shifts(k, 1);
                dy = shifts(k, 2);
                if flip_rows(k), m = flipud(m); end
                if contains(view_flips{k}, 'lr'), m = fliplr(m); dx = -dx; end
                if contains(view_flips{k}, 'ud'), m = flipud(m); dy = -dy; end
                h = cam_hw(k, 1);
                w = cam_hw(k, 2);
                out = nan(h, w);
                r = (1:h) + dy;
                c = (1:w) + dx;
                okr = r >= 1 & r <= size(m, 1);
                okc = c >= 1 & c <= size(m, 2);
                out(okr, okc) = m(r(okr), c(okc));
                views{k} = out;
            end
        end

        function M = tissue_mask_valid(img)
            %TISSUE_MASK_VALID Tissue silhouette of an image with missing (NaN) pixels
            % The SfM recipe's mask rule (rabbit_sfm_build.tissue_mask:
            % stretch between the 1st and 99.5th percentiles, log, Gaussian
            % of sigma 2 px, Otsu 1979, largest 8-connected region, holes
            % filled) with the percentiles and Otsu's threshold taken over
            % the pixels that have data only.
            img = double(img);
            fin = isfinite(img);
            M = false(size(img));
            if nnz(fin) < 16, return; end
            [lo, hi] = rabbit_sfm_build.stretch_limits(img(fin), [1 99.5]);
            x = min(max((img - lo) / max(hi - lo, 1e-9), 0), 1);
            x(~fin) = 0;
            I = floor(255 * x + 0.5);
            L = floor(255 * log1p(I) / log(256) + 0.5);
            r = 4;
            g = exp(-((-r:r) .^ 2) / 8);
            g = g / sum(g);
            B = conv2(padarray(L, [r r], 'replicate'), g, 'valid');
            B = floor(conv2(B, g', 'valid') + 0.5);
            h = accumarray(min(max(B(fin), 0), 255) + 1, 1, [256 1])';
            p = h / sum(h);
            w0 = cumsum(p);
            mu = cumsum(p .* (0:255));
            sb = (mu(end) * w0 - mu) .^ 2 ./ (w0 .* (1 - w0));
            sb(~isfinite(sb)) = -1;
            [~, k] = max(sb(1:255));
            M = B > (k - 1) & fin;
            if any(M(:))
                M = bwareafilt(M, 1, 8);
                M = imfill(M, 'holes') & fin;
            end
        end

        function chk = om_frame_check(om_image, json_path, colmap_dir, mesh_file, varargin)
            %OM_FRAME_CHECK Choose the frame whose cameras project the OM views, and check it
            % The OM recording shows the heart in one orientation; the
            % reconstruction recording turns it. Each ROI row's camera must
            % be the one of the frame in which the reconstruction views
            % show the heart as the OM views do, and the four cameras must
            % come from the same frame.
            % Candidates: frames whose four views are all registered with
            % at least L.min_points sparse points (images named
            % ..._view<k>_frame_<n>... or <n>_view<k>..., k = ROI row).
            % For each candidate frame and view, in the camera frame (the
            % run's flips and shifts, om_camera_views):
            %   pose IoU  overlap (intersection over union) of the OM
            %             view's tissue outline with the tissue outline of
            %             that frame's image (its score mask when MaskDir
            %             has one, else tissue_mask_valid of the image in
            %             ImagesDir);
            %   mesh IoU  overlap of the OM tissue outline with the mesh
            %             silhouette seen by that camera;
            %   covered   share of the OM tissue outline under the mesh
            %             silhouette (how much of the heart the OM camera
            %             sees gets a surface to land on).
            % Choice: frames are scored by the
            % mean pose IoU over the four views (frames lacking a camera
            % outline are left out; the mean mesh IoU only when no frame
            % has one). Among the frames with every view at or above
            % L.pose_iou_fail, the frames within L.ambiguity_margin of the
            % best mean form the margin group, and the earliest of them is
            % chosen (see the comment at the choice for why). Frames of
            % the group more than L.ambiguity_deg turned away from the
            % chosen one (the turn comes from the camera poses) are named
            % in the summary and make the verdict WARN: the outline match
            % cannot tell those positions apart (on the reference rabbit
            % data, frames 13-21 degrees from frame 1 score within 0.05 of
            % it). Frame (name-
            % value; the tab's "OM pose frame") sets the frame by hand.
            % Verdict: FAIL when a view's score at the chosen frame is
            % below L.pose_iou_fail (also on the mesh IoU), WARN below
            % L.pose_iou_warn, when a view's covered share is below
            % L.covered_warn, when the frame is ambiguous or only the mesh
            % outline could be compared, else PASS. PASS therefore means
            % "within about L.ambiguity_deg of the best-matching frame",
            % not "the OM pose". Without an OM image the first candidate
            % frame is used and the verdict is NOT CHECKED.
            % A wrong frame, a mirrored or missing view flip or a wrong
            % view order move the OM outline off the camera's and lower
            % the pose IoU; a wrong FOV offset of 10-20 rows lowers it
            % only a little (WARN at most on the reference rabbit data),
            % and a wrong flip of
            % one view can stay above L.pose_iou_warn (ROI row 4 without
            % its ud flip: 0.88).
            % Name-value: FlipRows, ViewFlips, Shifts (as given to run),
            % MaskDir, ImagesDir, Limits (frame_check_limits fields),
            % Frame (a frame number, or [] for automatic), ExcludeFrames
            % (frames left out of the candidates; for checks).
            % chk fields: checked, verdict, summary, note, frames (the
            % candidates), frame (chosen), chosen_by ('automatic' or
            % 'manual'), requested_frame, basis ('pose' or 'mesh'),
            % best_score_frame, ambiguous_frames and ambiguous_turn_deg,
            % best_turn_deg (the chosen frame's turn from the best match),
            % view_cameras (1x4 image names), per_view (struct array:
            % roi_row, image, pose_iou, mesh_iou, covered, om_tissue_px),
            % per_frame (frame, mean_pose_iou, min_pose_iou, mean_mesh_iou,
            % turn_deg_from_chosen, compared), limits, mask_source.
            p = struct('FlipRows', false, 'ViewFlips', {{}}, 'Shifts', zeros(4, 2), ...
                'MaskDir', '', 'ImagesDir', '', 'Limits', [], 'Frame', [], 'ExcludeFrames', []);
            for i = 1:2:numel(varargin)
                p.(char(varargin{i})) = varargin{i + 1};
            end
            L = rabbit_rhythm_reproject.frame_check_limits();
            if isstruct(p.Limits)
                f = fieldnames(p.Limits);
                for i = 1:numel(f), L.(f{i}) = p.Limits.(f{i}); end
            end
            chk = struct('checked', false, 'verdict', 'NOT CHECKED', 'summary', '', 'note', '', ...
                'frames', [], 'frame', NaN, 'view_cameras', {{}}, 'per_view', [], 'per_frame', [], ...
                'limits', L, 'mask_source', '', 'chosen_by', 'automatic', 'requested_frame', [], ...
                'basis', '', 'best_score_frame', NaN, 'ambiguous_frames', [], 'ambiguous_turn_deg', [], ...
                'best_turn_deg', [], 'view_camera_per_roi_row', [], 'mesh_outside_om', [], 'mesh_outside_warning', '', ...
                'mesh_outside_om_order', '', 'roi_row_view', []);
            % --- registered images per ROI row and frame ---
            images_bin = fullfile(colmap_dir, 'images.bin');
            if exist(images_bin, 'file') ~= 2
                chk.note = sprintf('No images.bin in %s, so the frame could not be chosen.', colmap_dir);
                chk.summary = chk.note;
                return;
            end
            [cameras, images, ~, s_ok, s_err] = rabbit_mesh_alignment.read_sparse_full(images_bin);
            if ~s_ok
                chk.note = s_err;
                chk.summary = s_err;
                return;
            end
            n = numel(images);
            row = zeros(1, n);
            fr = nan(1, n);
            nobs = zeros(1, n);
            for i = 1:n
                t = regexp(images(i).name, '_view([1-4])_frame_(\d+)', 'tokens', 'once');
                if isempty(t)
                    t = regexp(images(i).name, '(?:^|[\\/])(\d+)_view([1-4])\.', 'tokens', 'once');
                    if ~isempty(t), t = t([2 1]); end
                end
                if isempty(t), continue; end
                row(i) = str2double(t{1});
                fr(i) = str2double(t{2});
                nobs(i) = nnz(images(i).point3D_ids ~= -1);
            end
            if ~any(row)
                chk.note = ['The images are not named by ROI row and frame (..._view<k>_frame_<n>), so the ' ...
                    'frame could not be chosen; the first image of each view by name is used.'];
                chk.summary = chk.note;
                return;
            end
            ok_img = row > 0 & nobs >= L.min_points;
            if ~isempty(p.ExcludeFrames)
                ok_img = ok_img & ~ismember(fr, p.ExcludeFrames);
            end
            frames = unique(fr(ok_img));
            common = [];
            for f = frames
                if all(arrayfun(@(k) any(ok_img & row == k & fr == f), 1:4))
                    common(end+1) = f; %#ok<AGROW>
                end
            end
            chk.frames = common;
            if isempty(common)
                chk.verdict = 'FAIL';
                chk.note = sprintf(['No frame has all four views registered with at least %d sparse points, so ' ...
                    'the four cameras cannot come from one heart position.'], L.min_points);
                chk.summary = chk.note;
                return;
            end
            pick = @(k, f) find(ok_img & row == k & fr == f, 1);
            cam_hw = zeros(4, 2);
            for k = 1:4
                cm = cameras(images(pick(k, common(1))).camera_id);
                cam_hw(k, :) = double([cm.height cm.width]);
            end
            if isempty(om_image)
                chk.frame = common(1);
                chk.view_cameras = arrayfun(@(k) images(pick(k, common(1))).name, 1:4, 'UniformOutput', false);
                chk.view_camera_per_roi_row = rabbit_rhythm_reproject.camera_per_roi_row(chk.view_cameras);
                chk.note = sprintf(['No OM image was given, so the frame (%d, the first with all four views ' ...
                    'registered) could not be checked against the OM recording.'], common(1));
                chk.summary = chk.note;
                return;
            end
            % --- OM tissue outline per view, in the camera frame ---
            payload = rabbit_stack_io.load_roi_json(json_path, [], []);
            rotation = 0;
            if isfield(payload, 'rotation'), rotation = payload.rotation; end
            omv = rabbit_rhythm_reproject.om_camera_views(om_image, payload.region_bounds_src, rotation, ...
                p.FlipRows, p.ViewFlips, p.Shifts, cam_hw);
            om_mask = cellfun(@rabbit_rhythm_reproject.tissue_mask_valid, omv, 'UniformOutput', false);
            valid = cellfun(@isfinite, omv, 'UniformOutput', false);
            mesh = rabbit_rhythm_reproject.read_ply_mesh(mesh_file);
            % --- scores per candidate frame and view ---
            nf = numel(common);
            pose = nan(nf, 4);
            miou = nan(nf, 4);
            cov = nan(nf, 4);
            outside = nan(nf, 4);   % mesh outside the OM outline
            src = {};
            iou = @(a, b, v) nnz(a & b & v) / max(1, nnz((a | b) & v));
            for j = 1:nf
                for k = 1:4
                    im = images(pick(k, common(j)));
                    cm = cameras(im.camera_id);
                    % the camera image's tissue outline
                    cmask = [];
                    mf = '';
                    if ~isempty(p.MaskDir), mf = rabbit_mesh_cleanup.mask_file_for(p.MaskDir, im.name); end
                    if ~isempty(mf)
                        cmask = imread(mf);
                        cmask = cmask(:, :, 1) > 0;
                        src{end+1} = 'score masks'; %#ok<AGROW>
                    elseif ~isempty(p.ImagesDir) && exist(fullfile(p.ImagesDir, im.name), 'file') == 2
                        im_px = imread(fullfile(p.ImagesDir, im.name));
                        cmask = rabbit_rhythm_reproject.tissue_mask_valid(im_px(:, :, 1));
                        src{end+1} = 'camera images'; %#ok<AGROW>
                    end
                    if ~isempty(cmask) && isequal(size(cmask), cam_hw(k, :))
                        pose(j, k) = iou(cmask, om_mask{k}, valid{k});
                    end
                    % the mesh silhouette of this camera
                    if any(strcmp(cm.model, {'PINHOLE', 'SIMPLE_PINHOLE'}))
                        uv = rabbit_mesh_alignment.project_points(mesh.pts, im, cm);
                        sil = rabbit_mesh_alignment.mesh_silhouette(uv, mesh.faces, cam_hw(k, 1), cam_hw(k, 2));
                        miou(j, k) = iou(sil, om_mask{k}, valid{k});
                        cov(j, k) = nnz(sil & om_mask{k}) / max(1, nnz(om_mask{k}));
                        % Share of the mesh silhouette
                        % (where the OM view has pixels) outside the OM tissue
                        % outline: pose or scale mismatch, not missing mesh
                        outside(j, k) = nnz(sil & ~om_mask{k} & valid{k}) / max(1, nnz(sil & valid{k}));
                    end
                end
            end
            chk.checked = true;
            chk.mask_source = strjoin(unique(src), ' and ');
            % --- turn between the candidate frames, from the camera poses ---
            % The cameras stand still and the heart turns, so in the
            % model's world frame each view's camera turns by the heart's
            % turn: the angle of R_f * R_g' for the same view, the median
            % over the four views (they agree to about 0.1 degrees on the
            % reference rabbit data).
            Rc = cell(nf, 4);
            for j = 1:nf
                for k = 1:4
                    Rc{j, k} = rabbit_mesh_cleanup.qvec2rot(images(pick(k, common(j))).qvec);
                end
            end
            turn = zeros(nf, nf);
            for a = 1:nf
                for b = a + 1:nf
                    ang = zeros(1, 4);
                    for k = 1:4
                        Rr = Rc{a, k} * Rc{b, k}';
                        ang(k) = acosd(min(1, max(-1, (trace(Rr) - 1) / 2)));
                    end
                    turn(a, b) = median(ang);
                    turn(b, a) = turn(a, b);
                end
            end
            % --- which frames can be compared ---
            % A frame is scored by the pose IoU when all four of its camera
            % images have a tissue outline; frames without one are left out
            % of the choice (and named). Only when no frame has them is the
            % mesh IoU used, and then a view below the FAIL limit still
            % stops the step.
            pose_ok = all(isfinite(pose), 2);
            mesh_ok = all(isfinite(miou), 2);
            if any(pose_ok)
                basis = 'pose';
                S = pose;
                usable = pose_ok;
            else
                basis = 'mesh';
                S = miou;
                usable = mesh_ok;
            end
            score = mean(S, 2);
            score(~usable) = -Inf;
            smin = min(S, [], 2);
            smin(~usable) = -Inf;
            % --- the choice ---
            % Automatic: among the frames whose every view is at or above
            % the FAIL limit, the best mean score; then, of the frames
            % within L.ambiguity_margin of that score, the earliest frame.
            % The outline match does not resolve the heart's turn better
            % than about +-20 degrees (on the reference rabbit data, frames
            % 13-21 degrees from frame 1 score within 0.05 of it), so the
            % ranking inside that margin carries no information; the
            % earliest frame is the deterministic tie-break. Rationale
            % (an assumption, not a measurement): the OM recording is made
            % before the rotation recording (the reference rabbit data's lab
            % notes: OM 12:59, rotation 13:04), so the start of the rotation
            % is the
            % position closest in time to the OM pose. Frames of the
            % margin group more than L.ambiguity_deg away from the chosen
            % one make the verdict WARN and are named.
            % Manual (Frame given): that frame, judged on its own scores.
            eligible = usable & smin >= L.pose_iou_fail;
            requested = p.Frame;
            if isempty(requested) || ~isnumeric(requested) || ~isscalar(requested) || ...
                    ~isfinite(requested) || requested <= 0
                requested = [];
            end
            [~, best_any] = max(score);
            best_score = best_any;
            group = false(nf, 1);
            if ~isempty(requested)
                chosen = find(common == requested, 1);
                chk.chosen_by = 'manual';
                chk.requested_frame = requested;
                if isempty(chosen)
                    chk.verdict = 'FAIL';
                    chk.note = sprintf(['OM pose frame %d was set by hand, but it is not one of the frames whose ' ...
                        'four views are all registered with at least %d sparse points (%s).'], requested, ...
                        L.min_points, rabbit_rhythm_reproject.list_num(common, '%d', 1));
                    chk.summary = chk.note;
                    return;
                end
            elseif any(eligible)
                sc = score;
                sc(~eligible) = -Inf;
                [~, best_score] = max(sc);
                group = eligible & score >= score(best_score) - L.ambiguity_margin;
                chosen = find(group, 1, 'first');
            else
                chosen = best_any;
            end
            best = chosen;
            far = group & turn(:, best) > L.ambiguity_deg;
            far(best) = false;
            chk.basis = basis;
            chk.best_score_frame = common(best_score);
            chk.ambiguous_frames = reshape(common(far), 1, []);
            chk.ambiguous_turn_deg = reshape(turn(far, best), 1, []);
            % The chosen frame's turn from the best-matching frame ("frame 3,
            % 5.5 deg away"); 0 when they are one
            chk.best_turn_deg = turn(best_score, best);
            chk.frame = common(best);
            chk.view_cameras = arrayfun(@(k) images(pick(k, common(best))).name, 1:4, 'UniformOutput', false);
            chk.view_camera_per_roi_row = rabbit_rhythm_reproject.camera_per_roi_row(chk.view_cameras);
            chk.per_frame = struct('frame', num2cell(common(:)), 'mean_pose_iou', num2cell(mean(pose, 2)), ...
                'min_pose_iou', num2cell(min(pose, [], 2)), 'mean_mesh_iou', num2cell(mean(miou, 2)), ...
                'turn_deg_from_chosen', num2cell(turn(:, best)), 'compared', num2cell(usable));
            chk.per_view = struct('roi_row', num2cell(1:4), 'image', chk.view_cameras, ...
                'pose_iou', num2cell(pose(best, :)), 'mesh_iou', num2cell(miou(best, :)), ...
                'covered', num2cell(cov(best, :)), ...
                'mesh_outside_om', num2cell(outside(best, :)), ...
                'om_tissue_px', num2cell(cellfun(@nnz, om_mask)));
            % --- verdict ---
            sb = S(best, :);
            pb = pose(best, :);
            cb = cov(best, :);
            if ~usable(best) || any(sb < L.pose_iou_fail)
                chk.verdict = 'FAIL';
            elseif strcmp(basis, 'mesh') || any(pb < L.pose_iou_warn) || any(cb < L.covered_warn) || any(far)
                chk.verdict = 'WARN';
            else
                chk.verdict = 'PASS';
            end
            if strcmp(chk.chosen_by, 'manual')
                how = sprintf('Frame %d set by hand (OM pose frame) for the cameras', chk.frame);
            elseif chk.frame ~= chk.best_score_frame
                how = sprintf(['Frame %d chosen for the cameras: the earliest frame within %.2f of the best ' ...
                    'match (frame %d)'], chk.frame, L.ambiguity_margin, chk.best_score_frame);
            else
                how = sprintf('Frame %d chosen for the cameras', chk.frame);
            end
            % The values are per ROI row; the summary lists them View1 to
            % View4 (View1 the leftmost region), through the regions
            % file's view_order (ROI row k is the view it names k-th)
            rv = 1:4;
            if isfield(payload, 'view_order') && numel(payload.view_order) == 4
                n = cellfun(@(v) str2double(regexprep(char(v), '^view', '', 'ignorecase')), cellstr(payload.view_order));
                if all(isfinite(n)) && isequal(sort(n(:)'), 1:4), rv = n(:)'; end
            end
            sb_v = sb; sb_v(rv) = sb;
            cb_v = cb; cb_v(rv) = cb;
            % The mesh outside the OM outline and its warning above
            % MESH_OUTSIDE_WARN (the text View1 to View4). Kept in ROI-row
            % order, as its siblings
            % (pose_iou, mesh_iou, om_covered, per_view), with the view of
            % each ROI row (roi_row_view); the manifests' top-level
            % mesh_outside_om is the View1-to-View4 copy (write_manifest)
            ob_v = outside(best, :); ob_v(rv) = outside(best, :);
            chk.mesh_outside_om = outside(best, :);
            chk.mesh_outside_om_order = 'roi_row';
            chk.roi_row_view = rv;
            chk.mesh_outside_warning = rabbit_rhythm_reproject.mesh_outside_text(ob_v);
            chk.summary = sprintf(['%s (%d frames had all four views registered). ' ...
                'Match of the heart outline in the OM views with the reconstruction views of that frame, View1 ' ...
                'to View4 (1 = identical): %s (below %.2f the views may not show the same heart position; below %.2f ' ...
                'the step stops). Share of the heart in each OM view that the mesh covers, View1 to View4: %s.'], ...
                how, nf, rabbit_rhythm_reproject.outline_match_list(sb_v, [L.pose_iou_warn L.pose_iou_fail]), ...
                L.pose_iou_warn, L.pose_iou_fail, rabbit_rhythm_reproject.list_num(cb_v, '%.0f %%', 100));
            if any(far)
                parts = arrayfun(@(f, a) sprintf('%d (%.0f deg)', f, a), chk.ambiguous_frames, ...
                    chk.ambiguous_turn_deg, 'UniformOutput', false);
                chk.summary = sprintf(['%s Frames %s match within %.2f as well, but the heart is turned by up to ' ...
                    '%.0f degrees there: the outline match cannot tell these positions apart, so the OM pose is ' ...
                    'known only to within about %.0f degrees. Set "OM pose frame" to a frame number if another ' ...
                    'frame is known to show the OM position.'], chk.summary, strjoin(parts, ', '), ...
                    L.ambiguity_margin, max(chk.ambiguous_turn_deg), max(chk.ambiguous_turn_deg));
            end
            if strcmp(basis, 'mesh')
                chk.summary = [chk.summary ' The camera images had no tissue outline to compare, so only ' ...
                    'the mesh outline was compared (FAIL below the same limit; at best WARN).'];
            elseif ~all(usable)
                chk.summary = sprintf(['%s Frames %s were not compared: a camera image or its tissue outline ' ...
                    'was missing.'], chk.summary, rabbit_rhythm_reproject.list_num(common(~usable), '%d', 1));
            end
        end

        function s = outline_match_list(x, limits)
            %% Outline matches, comma-separated: two decimals, three within 0.01 of a limit
            % A value such as 0.795 against a limit of 0.80 would print as
            % 0.80 and read as on the limit; within 0.01 of one it is given
            % to three decimals ('n/a' for NaN).
            parts = cell(1, numel(x));
            for i = 1:numel(x)
                if ~isfinite(x(i))
                    parts{i} = 'n/a';
                elseif any(abs(x(i) - limits) <= 0.01)
                    parts{i} = sprintf('%.3f', x(i));
                else
                    parts{i} = sprintf('%.2f', x(i));
                end
            end
            s = strjoin(parts, ', ');
        end

        function fo = mesh_outside_by_view(fc)
            %% A frame check's mesh outside the OM outline, View1 to View4
            % fc.mesh_outside_om is in ROI-row order when
            % fc.mesh_outside_om_order is 'roi_row' (fc.roi_row_view: the
            % view of each ROI row); an older record without that field is
            % already View1 to View4.
            fo = double(fc.mesh_outside_om(:)');
            if isfield(fc, 'mesh_outside_om_order') && strcmp(char(fc.mesh_outside_om_order), 'roi_row') && ...
                    isfield(fc, 'roi_row_view') && isequal(sort(double(fc.roi_row_view(:)')), 1:numel(fo))
                by_view = fo;
                by_view(double(fc.roi_row_view(:)')) = fo;   % ROI row k is View roi_row_view(k)
                fo = by_view;
            end
        end

        function t = mesh_outside_text(v)
            %% 'mesh outside the OM outline V1 7 % · V2 12 % ... (warn > 10 %; mesh larger than the OM outline: ...)' when a view is above MESH_OUTSIDE_WARN; else ''
            % v: the share of each view's mesh silhouette outside its OM
            % tissue outline, View1 to View4
            t = '';
            v = double(v(:)');
            if ~any(v > rabbit_rhythm_reproject.MESH_OUTSIDE_WARN), return; end
            parts = cell(1, numel(v));
            for k = 1:numel(v)
                if isfinite(v(k))
                    % non-breaking spaces keep "V4 26 %" whole when a row wraps
                    parts{k} = sprintf('V%d%s%.0f%s%%', k, char(160), 100 * v(k), char(160));
                else
                    parts{k} = sprintf('V%d%sn/a', k, char(160));
                end
            end
            % The limit, and the causes without
            % asserting pose or scale
            t = sprintf(['mesh outside the OM outline %s (warn > %.0f %%; mesh larger than the OM outline: pose, ' ...
                'scale or the OM tissue outline; not missing mesh)'], strjoin(parts, [' ' char(183) ' ']), ...
                100 * rabbit_rhythm_reproject.MESH_OUTSIDE_WARN);
        end

        function r = view_geometry_suspect(result)
            %% The views whose geometry is suspect: two or more of three per-view checks fire; [] without any check
            % Display only. View1 to View4:
            %   camera-image outline match below GEOMETRY_CAMERA_MATCH_SUSPECT
            %     (frame_check.pose_iou, ROI-row order, put in View order by
            %     roi_row_view; left out of a record without it)
            %   mesh outside the OM outline above MESH_OUTSIDE_WARN
            %     (mesh_outside_by_view)
            %   directly seen faces spread more than
            %     ACTIVATION_IQR_RATIO_WARN times the view's 2-D map
            %     (activation_consistency.ratio; activation records only)
            % warnings and next: one ready text each per suspect view.
            r = [];
            names = {'View1', 'View2', 'View3', 'View4'};
            cam = nan(1, 4); outs = nan(1, 4); ratio = nan(1, 4);
            fc = [];
            if isfield(result, 'frame_check') && isstruct(result.frame_check), fc = result.frame_check; end
            if isstruct(fc) && isfield(fc, 'mesh_outside_om') && numel(fc.mesh_outside_om) == 4
                outs = rabbit_rhythm_reproject.mesh_outside_by_view(fc);
            end
            if isstruct(fc) && isfield(fc, 'pose_iou') && numel(fc.pose_iou) == 4 && isfield(fc, 'roi_row_view') && ...
                    isequal(sort(double(fc.roi_row_view(:)')), 1:4)
                cam(double(fc.roi_row_view(:)')) = double(fc.pose_iou(:)');   % ROI row k is View roi_row_view(k)
            end
            if isfield(result, 'activation_consistency') && isstruct(result.activation_consistency) && ...
                    isfield(result.activation_consistency, 'ratio') && numel(result.activation_consistency.ratio) == 4
                ratio = double(result.activation_consistency.ratio(:)');      % already View1 to View4
            end
            if all(isnan([cam outs ratio])), return; end
            f_cam = cam < rabbit_rhythm_reproject.GEOMETRY_CAMERA_MATCH_SUSPECT;
            f_out = outs > rabbit_rhythm_reproject.MESH_OUTSIDE_WARN;
            f_act = ratio > rabbit_rhythm_reproject.ACTIVATION_IQR_RATIO_WARN;
            n = double(f_cam) + double(f_out) + double(f_act);
            suspect = n >= 2;
            flags = cell(1, 4);
            warnings = {};
            next = {};
            for k = 1:4
                f = {};
                parts = {};
                if f_cam(k)
                    f{end + 1} = 'camera_image_match'; %#ok<AGROW>
                    parts{end + 1} = sprintf('camera-image match %.2f', cam(k)); %#ok<AGROW>
                end
                if f_out(k)
                    f{end + 1} = 'mesh_outside'; %#ok<AGROW>
                    parts{end + 1} = sprintf('mesh outside its outline %d %%', round(100 * outs(k))); %#ok<AGROW>
                end
                if f_act(k)
                    f{end + 1} = 'activation_spread'; %#ok<AGROW>
                    parts{end + 1} = sprintf('directly seen faces spread %.1f%s its 2-D map', ratio(k), char(215)); %#ok<AGROW>
                end
                flags{k} = f;
                if suspect(k)
                    warnings{end + 1} = sprintf('WARN %s  geometry suspect: %s.', names{k}, strjoin(parts, ', ')); %#ok<AGROW>
                    next{end + 1} = sprintf('Next: treat %s''s 3-D values as unreliable; use its 2-D map.', names{k}); %#ok<AGROW>
                end
            end
            r = struct('views', {names}, 'camera_image_match', cam, 'mesh_outside', outs, ...
                'activation_iqr_ratio', ratio, 'flags', {flags}, 'n_flags', n, 'suspect', suspect, ...
                'suspect_views', {names(suspect)}, 'warnings', {warnings}, 'next', {next}, ...
                'limits', struct('camera_image_match_below', rabbit_rhythm_reproject.GEOMETRY_CAMERA_MATCH_SUSPECT, ...
                'mesh_outside_above', rabbit_rhythm_reproject.MESH_OUTSIDE_WARN, ...
                'activation_iqr_ratio_above', rabbit_rhythm_reproject.ACTIVATION_IQR_RATIO_WARN, 'min_flags', 2), ...
                'basis', ['a view is geometry suspect when two or more of its checks fire: camera-image outline ' ...
                'match below 0.75, mesh outside the OM outline above 10 %, directly seen faces spreading more ' ...
                'than 1.5x its 2-D map (activation records only); display only']);
        end

        function s = list_num(x, fmt, scale)
            %LIST_NUM Comma-separated numbers ('n/a' for NaN)
            parts = cell(1, numel(x));
            for i = 1:numel(x)
                if isfinite(x(i))
                    parts{i} = sprintf(fmt, scale * x(i));
                else
                    parts{i} = 'n/a';
                end
            end
            s = strjoin(parts, ', ');
        end

        % =============================================================
        % 2. Canvas <-> per-view source maps
        % =============================================================

        function [map, n] = unbin_canvas(map, H, W)
            %% A map made after N x N binning, back on the H x W canvas of the regions
            % Binning (imresize by 1/N) gives ceil(H/N) x ceil(W/N); binned
            % pixel (i, j) covers canvas rows (i-1)N+1..iN and columns
            % (j-1)N+1..jN, so each is put over that block (NaN stays NaN).
            % n: the factor (1 = the canvas size already, or no factor fits).
            n = 1;
            [h, w] = size(map, [1 2]);
            if h == H && w == W, return; end
            for f = 2:16
                if h == ceil(H / f) && w == ceil(W / f)
                    n = f;
                    r = min(ceil((1:H) / f), h);
                    c = min(ceil((1:W) / f), w);
                    map = map(r, c, :);
                    return;
                end
            end
        end

        function [views, view_names, canvas, om_bin] = split_canvas(map, bounds, rotation)
            %SPLIT_CANVAS Inverse of apply_regions' 4-view assembly.
            %   map     HxW activation canvas (ms; NaN missing)
            %   bounds  Nx4 region_bounds_src [r1 c1 r2 c2] (order
            %           view2;view3;view1;view4), optional cols 5/6 =
            %           [height width]
            %   rotation 0-3 (rabbit editor layout). 1/3 = the WxH
            %           layout (max source width x sum source heights),
            %           the app's default (rotation 3) and the layout of
            %           the reference rabbit data (non-square); checked
            %           against the app's assembly. 0/2 = HxW slots (max
            %           source height x sum source widths), which only
            %           holds for square views.
            %   views   4x1 cell of per-view maps in SOURCE orientation
            %           (same orientation as the cut images the COLMAP
            %           cameras see)
            %   om_bin  1, or N when the map was made after N x N binning
            %           (Processing tab, Binning): it is then
            %           ceil(H/N) x ceil(W/N), and each of its pixels is
            %           put over its N x N block of the regions' canvas
            %           before the split (unbin_canvas)
            if nargin < 3 || isempty(rotation), rotation = 0; end
            om_bin = 1;
            if ~any(rotation == [0 1 2 3])
                error('analyse_om:Reprojection:BadRotation', ...
                    'split_canvas supports rotation 0-3 (got %d).', rotation);
            end
            bounds = double(bounds);
            n = size(bounds, 1);
            hh = bounds(:, 3) - bounds(:, 1) + 1;
            ww = bounds(:, 4) - bounds(:, 2) + 1;
            if size(bounds, 2) >= 6
                hh = bounds(:, 5); ww = bounds(:, 6);
            end
            % Canvas slot of each ROI row, as regions_chosen orders the
            % regions before apply_regions: by first column, then for four
            % regions rotation 3 swaps the last two and rotation 1 takes
            % them in the order 4 3 1 2. The tile transform belongs to the
            % slot, the region to the ROI row.
            [~, slot_rows] = sort(bounds(:, 2));
            if n == 4 && rotation == 3
                slot_rows = slot_rows([1 2 4 3]);
            elseif n == 4 && rotation == 1
                slot_rows = slot_rows([4 3 1 2]);
            end
            if any(rotation == [0 2])
                % HxW canvas: height = max source height, width = sum
                % source widths; each tile slot is hh(k) x ww(k).
                H = max(hh); W = sum(ww);
                [map, om_bin] = rabbit_rhythm_reproject.unbin_canvas(map, H, W);
                if size(map, 1) ~= H || size(map, 2) ~= W
                    error('analyse_om:Reprojection:CanvasMismatch', ...
                        ['Activation canvas is %dx%d but the ROI JSON pins a ' ...
                        '%dx%d canvas. Generate the map with these regions.'], ...
                        size(map, 1), size(map, 2), H, W);
                end
                views = cell(n, 1);
                view_names = cell(n, 1);
                start = 1;
                for s = 1:n
                    k = slot_rows(s);
                    th = hh(k); tw = ww(k);
                    crows = 1 + floor((H - th) / 2) : floor((H - th) / 2) + th;
                    ccols = start : start + tw - 1;
                    tile = map(crows, ccols);
                    switch s
                        case 1 % slot 1: tile = rot90(src)
                            src = rot90(tile, -1);
                        case 2 % slot 2: tile = fliplr(rot90(fliplr(flipud(src))))
                            src = flipud(fliplr(rot90(fliplr(tile), -1)));
                        case 3 % slot 3: tile = fliplr(rot90(fliplr(src)))
                            src = fliplr(rot90(fliplr(tile), -1));
                        case 4 % slot 4: tile = fliplr(rot90(fliplr(flipud(src))))
                            src = flipud(fliplr(rot90(fliplr(tile), -1)));
                        otherwise % defensive: never reached (gate enforces 4)
                            src = tile;
                    end
                    views{k} = src;
                    view_names{k} = rabbit_rhythm_reproject.VIEW_ORDER{k};
                    start = start + tw;
                end
            else
                % Transposed WxH canvas (rotation 1/3): height = max
                % source width, width = sum source heights; each tile
                % slot is ww(k) x hh(k) (the rot90'd source). The
                % per-view transforms are the same as rotation 0/2
                % (verified in apply_regions - only the slot geometry
                % differs).
                H = max(ww); W = sum(hh);
                [map, om_bin] = rabbit_rhythm_reproject.unbin_canvas(map, H, W);
                if size(map, 1) ~= H || size(map, 2) ~= W
                    error('analyse_om:Reprojection:CanvasMismatch', ...
                        ['Activation canvas is %dx%d but the ROI JSON pins a ' ...
                        '%dx%d canvas (rotation %d). Generate the map with ' ...
                        'these regions.'], ...
                        size(map, 1), size(map, 2), H, W, rotation);
                end
                views = cell(n, 1);
                view_names = cell(n, 1);
                start = 1;
                for s = 1:n
                    k = slot_rows(s);
                    th = hh(k); tw = ww(k);
                    % WxH slot: tw rows, th cols
                    crows = 1 + floor((H - tw) / 2) : floor((H - tw) / 2) + tw;
                    ccols = start : start + th - 1;
                    tile = map(crows, ccols);
                    switch s
                        case 1 % slot 1: tile = rot90(src)
                            src = rot90(tile, -1);
                        case 2 % slot 2: tile = fliplr(rot90(fliplr(flipud(src))))
                            src = flipud(fliplr(rot90(fliplr(tile), -1)));
                        case 3 % slot 3: tile = fliplr(rot90(fliplr(src)))
                            src = fliplr(rot90(fliplr(tile), -1));
                        case 4 % slot 4: tile = fliplr(rot90(fliplr(flipud(src))))
                            src = flipud(fliplr(rot90(fliplr(tile), -1)));
                        otherwise % defensive: never reached (gate enforces 4)
                            src = tile;
                    end
                    views{k} = src;
                    view_names{k} = rabbit_rhythm_reproject.VIEW_ORDER{k};
                    start = start + th;
                end
            end
            canvas = map;
        end

        % =============================================================
        % 3. COLMAP readers (standard COLMAP model formats only)
        % =============================================================

        function cam = read_colmap_cameras(folder)
            %READ_COLMAP_CAMERAS cameras.bin (first choice) or
            %cameras.txt. Returns struct array with fields: id, model
            %(name string), width, height, params (double vector).
            b = fullfile(folder, 'cameras.bin');
            t = fullfile(folder, 'cameras.txt');
            if exist(b, 'file')
                cam = rabbit_rhythm_reproject.read_cameras_bin(b);
            elseif exist(t, 'file')
                cam = rabbit_rhythm_reproject.read_cameras_txt(t);
            else
                error('analyse_om:Reprojection:NoCameras', ...
                    'No cameras.bin or cameras.txt in %s.', folder);
            end
        end

        function cam = read_cameras_bin(path)
            %READ_CAMERAS_BIN COLMAP cameras.bin (standard binary layout,
            %as in COLMAP's reconstruction_io_binary.cc; older and current
            %COLMAP versions write the same bytes for cameras/images):
            %   uint64 count, then per camera:
            %     uint32 camera_id, int32 model_id,
            %     uint64 width, uint64 height,
            %     nParams doubles (model-dependent).
            % There is no ascii '<N>' header; the count is the raw uint64.
            fid = fopen(path, 'rb', 'ieee-le');
            if fid < 0
                error('analyse_om:Reprojection:CannotOpen', 'Cannot open %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            n = fread(fid, 1, 'uint64');
            if isempty(n) || n < 1
                error('analyse_om:Reprojection:BadCameras', ...
                    'No camera records could be read from %s.', path);
            end
            % COLMAP model-id -> name/params layout
            model = { 'SIMPLE_PINHOLE', 'PINHOLE', 'SIMPLE_RADIAL', ...
                'RADIAL', 'OPENCV', 'OPENCV_FISHEYE', 'FULL_OPENCV', ...
                'FOV', 'SIMPLE_RADIAL_FISHEYE', 'RADIAL_FISHEYE', ...
                'THIN_PRISM_FISHEYE' };
            npar = [3 4 4 5 8 8 12 5 4 5 12];
            cam = struct('id', {}, 'model', {}, 'width', {}, ...
                'height', {}, 'params', {});
            k = 0;
            while k < n
                cid = fread(fid, 1, 'uint32');
                if isempty(cid), break; end
                mid = fread(fid, 1, 'int32');
                w = fread(fid, 1, 'uint64');
                h = fread(fid, 1, 'uint64');
                if isempty(mid) || isempty(w) || isempty(h), break; end
                npar_i = npar(mid + 1);
                prm = fread(fid, npar_i, 'double');
                if numel(prm) < npar_i, break; end
                k = k + 1;
                cam(k).id = cid;
                cam(k).model = model{mid + 1};
                cam(k).width = w;
                cam(k).height = h;
                cam(k).params = prm(:)';
            end
            if k == 0
                error('analyse_om:Reprojection:BadCameras', ...
                    'No camera records could be read from %s.', path);
            end
        end

        function cam = read_cameras_txt(path)
            fid = fopen(path, 'rt');
            if fid < 0
                error('analyse_om:Reprojection:CannotOpen', 'Cannot open %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            cam = struct('id', {}, 'model', {}, 'width', {}, ...
                'height', {}, 'params', {});
            k = 0;
            while ~feof(fid)
                ln = fgetl(fid);
                if isequal(ln, -1), break; end
                line = strtrim(ln);
                if isempty(line) || line(1) == '#', continue; end
                C = textscan(line, '%u %s %u %u %[^\n]', 1);
                if isempty(C{1}) || isempty(C{2}), continue; end
                k = k + 1;
                cam(k).id = C{1};
                cam(k).model = C{2}{1};
                cam(k).width = C{3};
                cam(k).height = C{4};
                if numel(C) >= 5 && ~isempty(C{5})
                    rest = strtrim(C{5}{1});
                    cam(k).params = sscanf(rest, '%f')';
                else
                    cam(k).params = [];
                end
            end
            if k == 0
                error('analyse_om:Reprojection:BadCameras', ...
                    'No camera records could be read from %s.', path);
            end
        end

        function imgs = read_colmap_images(folder)
            %READ_COLMAP_IMAGES images.bin (first choice) or
            %images.txt. Returns struct array with fields: id, qvec
            %[qw qx qy qz], tvec [tx ty tz], camera_id, name.
            b = fullfile(folder, 'images.bin');
            t = fullfile(folder, 'images.txt');
            if exist(b, 'file')
                imgs = rabbit_rhythm_reproject.read_images_bin(b);
            elseif exist(t, 'file')
                imgs = rabbit_rhythm_reproject.read_images_txt(t);
            else
                error('analyse_om:Reprojection:NoImages', ...
                    'No images.bin or images.txt in %s.', folder);
            end
        end

        function imgs = read_images_bin(path)
            %READ_IMAGES_BIN COLMAP images.bin (standard binary layout,
            %as in COLMAP's reconstruction_io_binary.cc):
            %   uint64 count, then per image:
            %     uint32 image_id, 4 doubles (qw qx qy qz),
            %     3 doubles (tx ty tz), uint32 camera_id,
            %     nul-terminated name, uint64 num_points2D,
            %     then per point: double x, double y,
            %     uint64 point3D_id (skipped - not needed here).
            % Older and current COLMAP versions write the same bytes here
            % (rigs/frames are separate files).
            fid = fopen(path, 'rb', 'ieee-le');
            if fid < 0
                error('analyse_om:Reprojection:CannotOpen', 'Cannot open %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            n = fread(fid, 1, 'uint64');
            if isempty(n) || n < 1
                error('analyse_om:Reprojection:BadImages', ...
                    'No image records could be read from %s.', path);
            end
            imgs = struct('id', {}, 'qvec', {}, 'tvec', {}, ...
                'camera_id', {}, 'name', {});
            k = 0;
            while k < n
                iid = fread(fid, 1, 'uint32');
                if isempty(iid), break; end
                q = fread(fid, 4, 'double');
                t = fread(fid, 3, 'double');
                cid = fread(fid, 1, 'uint32');
                nm = '';
                b = fread(fid, 1, 'uint8');
                while ~isempty(b) && b ~= 0
                    nm = [nm char(b)]; %#ok<AGROW>
                    b = fread(fid, 1, 'uint8');
                end
                npts = fread(fid, 1, 'uint64');
                if ~isempty(npts) && npts > 0
                    fseek(fid, npts * (8 + 8 + 8), 'cof'); % x y point3D_id
                end
                if numel(q) < 4, break; end
                k = k + 1;
                imgs(k).id = iid;
                imgs(k).qvec = q(:)';
                imgs(k).tvec = t(:)';
                imgs(k).camera_id = cid;
                imgs(k).name = nm;
            end
            if k == 0
                error('analyse_om:Reprojection:BadImages', ...
                    'No image records could be read from %s.', path);
            end
        end

        function imgs = read_images_txt(path)
            fid = fopen(path, 'rt');
            if fid < 0
                error('analyse_om:Reprojection:CannotOpen', 'Cannot open %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            imgs = struct('id', {}, 'qvec', {}, 'tvec', {}, ...
                'camera_id', {}, 'name', {});
            k = 0;
            while ~feof(fid)
                ln = fgetl(fid);
                if isequal(ln, -1), break; end
                line = strtrim(ln);
                if isempty(line)
                    % blank line: skip possible trailing points block
                    if ~feof(fid)
                        ln = fgetl(fid);
                        if isequal(ln, -1), break; end
                        line = strtrim(ln);
                    end
                end
                if isempty(line) || line(1) == '#', continue; end
                C = textscan(line, '%u %f %f %f %f %f %f %f %u %s', 1);
                if isempty(C{1}) || numel(C) < 10 || isempty(C{10}), continue; end
                k = k + 1;
                imgs(k).id = C{1};
                imgs(k).qvec = [C{2} C{3} C{4} C{5}];
                imgs(k).tvec = [C{6} C{7} C{8}];
                imgs(k).camera_id = C{9};
                imgs(k).name = C{10}{1};
                % consume the points lines until the next blank line
                while ~feof(fid)
                    pos = ftell(fid);
                    l2 = fgetl(fid);
                    if isequal(l2, -1), break; end
                    l2 = strtrim(l2);
                    if isempty(l2), break; end
                    if l2(1) == '#', continue; end
                    % points lines are 'X Y Z R G B' (7 tokens); a header
                    % row ('ID QW QX QY QZ TX TY TZ CAMERA NAME') has 10
                    % tokens - rewind and let the outer loop parse it
                    if numel(strsplit(l2)) >= 10
                        fseek(fid, pos, 'bof');
                        break;
                    end
                end
            end
            if k == 0
                error('analyse_om:Reprojection:BadImages', ...
                    'No image records could be read from %s.', path);
            end
        end

        function [view_cam, names_used] = resolve_view_cameras(imgs, override)
            %RESOLVE_VIEW_CAMERAS Map each of the four ROI views to a
            %COLMAP image record. With override (1x4 cell of image
            %names, one per ROI row) the names are matched literally.
            %Without override, ROI row k takes the first image by name
            %that is named 'view<k>/...' or contains '_view<k>' (the
            %cut names its tiles by ROI row: bounds row k -> _view<k>,
            %as om_frame_check reads them); failing that, a
            %cam<k>/camera_<k> prefix.
            %The reading is positional, not VIEW_ORDER{k} (row 1 ->
            %_view2): the data (the cut, the frame check's outline
            %matches) back the positional one, and the frame check reads
            %the names the same way.
            if ~isempty(override)
                if numel(override) ~= 4
                    error('analyse_om:Reprojection:BadViewCameras', ...
                        'ViewCameras must have exactly 4 names.');
                end
                view_cam = cell(4, 1);
                names_used = cell(4, 1);
                for k = 1:4
                    nm = char(override{k});
                    hit = [];
                    for i = 1:numel(imgs)
                        if strcmp(imgs(i).name, nm), hit = i; break; end
                    end
                    if isempty(hit)
                        error('analyse_om:Reprojection:ViewCameraMissing', ...
                            'COLMAP image ''%s'' (view %d) not found.', nm, k);
                    end
                    view_cam{k} = imgs(hit);
                    names_used{k} = imgs(hit).name;
                end
                return;
            end
            view_cam = cell(4, 1);
            names_used = cell(4, 1);
            [names, order] = sort({imgs.name});
            for k = 1:4
                n = k;   % positional: ROI row k is _view<k>
                hit = [];
                ns = num2str(n);
                pats = {['(^|[/\\])view' ns '[_/]'], ['_view' ns '(\D|$)'], ...
                    ['(^|[/\\])cam' ns '(\D|$)'], ['(^|[/\\])camera_' ns '(\D|$)']};
                for q = 1:numel(pats)
                    for i = 1:numel(names)
                        if ~isempty(regexp(names{i}, pats{q}, 'once'))
                            hit = order(i); break;
                        end
                    end
                    if ~isempty(hit), break; end
                end
                if isempty(hit)
                    error('analyse_om:Reprojection:ViewCameraMissing', ...
                        ['No COLMAP image found for ROI row %d (need a name like ' ...
                        '''view%d/...'', ''..._view%d...'' or a cam%d/camera_%d ' ...
                        'prefix). Pass ViewCameras explicitly.'], ...
                        k, n, n, n, n);
                end
                view_cam{k} = imgs(hit);
                names_used{k} = imgs(hit).name;
            end
        end

        function rv = row_views_of(payload)
            %% The view number (View1 = leftmost region) of each ROI row, from the regions file's view_order; 1:4 if unusable
            rv = 1:4;
            if isstruct(payload) && isfield(payload, 'view_order') && numel(payload.view_order) == 4
                n = cellfun(@(v) str2double(regexprep(char(v), '^view', '', 'ignorecase')), cellstr(payload.view_order));
                if all(isfinite(n)) && isequal(sort(n(:)'), 1:4), rv = n(:)'; end
            end
        end

        function r = activation_consistency(views, dataProj, viewi, mask, row_views)
            %% Per view: the IQR of the activation on the faces it sees directly against the IQR of its 2-D map
            % Display only. views: each
            % ROI row's map as projected (ms); dataProj, viewi, mask: the
            % projection (viewi's last column: the ROI row of a DIRECT
            % face); row_views: the view number of each ROI row. A view
            % warns when its directly seen faces spread more than
            % ACTIVATION_IQR_RATIO_WARN times its map's IQR: its projection
            % does not reproduce its map. per_view is in ROI order;
            % warnings are View1 to View4, ready to print ('' none).
            lim = rabbit_rhythm_reproject.ACTIVATION_IQR_RATIO_WARN;
            nv = numel(views);
            % The 2-D map's IQR twice, as projected
            % (unsmoothed: the ratio's basis) and after the 3 x 3 median the
            % CV step applies (rabbit_cv_map.median3), which the CV tab's
            % near-simultaneous check reads; display only
            per = struct('roi_row', {}, 'view', {}, 'n_direct_faces', {}, 'iqr_direct_faces_ms', {}, ...
                'n_map_px', {}, 'iqr_map_ms', {}, 'iqr_map_smoothed_ms', {}, 'ratio', {}, 'warn', {});
            iqr_of = @(x) diff(prctile(double(x), [25 75]));
            direct = [];
            if ~isempty(viewi) && size(viewi, 2) == nv + 1, direct = viewi(:, end); end
            for k = 1:nv
                v = views{k}(isfinite(views{k}));
                if isempty(direct)
                    f = [];
                else
                    f = dataProj(logical(mask(:)) & direct == k & isfinite(dataProj(:)));
                end
                i2 = NaN; i3 = NaN; i2s = NaN;
                if numel(v) >= 4, i2 = iqr_of(v); end
                if numel(v) >= 4
                    m3 = rabbit_cv_map.median3(double(views{k}), double(isfinite(views{k})));   % one view: no seam
                    m3 = m3(isfinite(m3));
                    if numel(m3) >= 4, i2s = iqr_of(m3); end
                end
                if numel(f) >= 4, i3 = iqr_of(f); end
                ratio = i3 / i2;
                if ~(i2 > 0), ratio = NaN; end
                per(k) = struct('roi_row', k, 'view', sprintf('View%d', row_views(k)), 'n_direct_faces', numel(f), ...
                    'iqr_direct_faces_ms', i3, 'n_map_px', numel(v), 'iqr_map_ms', i2, 'iqr_map_smoothed_ms', i2s, 'ratio', ratio, ...
                    'warn', ratio > lim); %#ok<AGROW>
            end
            % The record in View1 to View4 order: views, iqr_3d_direct_ms,
            % iqr_2d_ms, ratio, warn, basis; per_view keeps the ROI-row
            % detail
            [~, order] = sort(row_views(1:nv));
            p = per(order);
            warnings = {};
            for k = 1:numel(p)
                if p(k).warn
                    % both 2-D IQRs named
                    warnings{end + 1} = sprintf(['WARN Activation  %s: directly seen faces spread %d ms (IQR) ' ...
                        'against %d ms in its 2-D map as projected (unsmoothed; %s ms after the CV step''s 3%s3 ' ...
                        'median); this view''s projection does not reproduce its map'], ...
                        p(k).view, round(p(k).iqr_direct_faces_ms), round(p(k).iqr_map_ms), ...
                        rabbit_rhythm_reproject.ms_or_dash(p(k).iqr_map_smoothed_ms), char(215)); %#ok<AGROW>
                end
            end
            r = struct('views', {{p.view}}, 'iqr_3d_direct_ms', [p.iqr_direct_faces_ms], ...
                'iqr_2d_ms', [p.iqr_map_ms], 'iqr_2d_smoothed_ms', [p.iqr_map_smoothed_ms], ...
                'smoothed_basis', ['IQR (25-75 %) of that view''s 2-D map pixels after the CV step''s 3 x 3 median ' ...
                '(NaN ignored, within the tissue and the view); the ratio and its warning use the map as projected'], ...
                'ratio', [p.ratio], 'warn', [p.warn], ...
                'basis', ['IQR (25-75 %) of the projected activation on the faces each view sees directly ' ...
                '(DIRECT) against the IQR of that view''s 2-D map pixels; warn when the ratio is above 1.5'], ...
                'limit_ratio', lim, 'n_direct_faces', [p.n_direct_faces], 'n_map_px', [p.n_map_px], ...
                'per_view', per, 'warnings', {warnings});
        end

        function t = ms_or_dash(x)
            %% A time in whole ms, or '-' when there is none
            if isscalar(x) && isfinite(x), t = sprintf('%d', round(x)); else, t = '-'; end
        end

        function r = camera_per_roi_row(names)
            %% The record of which camera image each ROI row used (view_camera_per_roi_row)
            % names: 4 image names, ROI row 1 to 4. roi_view_in_name is
            % the k of '_view<k>' (or 'view<k>/') in the name, NaN when
            % the name has none; with the positional convention it equals
            % roi_row.
            names = cellstr(names);
            k_in = nan(1, numel(names));
            for k = 1:numel(names)
                t = regexp(names{k}, '(?:_view|(?:^|[\\/])view)([1-4])(?:\D|$)', 'tokens', 'once');
                if ~isempty(t), k_in(k) = str2double(t{1}); end
            end
            r = struct('roi_row', num2cell(1:numel(names)), 'image', names(:)', ...
                'roi_view_in_name', num2cell(k_in));
            r = struct('per_row', r, 'convention', ['positional: ROI row k (row k of region_bounds_src) takes ' ...
                'the image named ..._view<k>... (the cut names its tiles by ROI row), in the frame check and ' ...
                'the default choice alike']);
        end

        % =============================================================
        % 4. PLY mesh reader (COLMAP/APDe-MVS PLY, text or binary)
        % =============================================================

        function s = unit_scale_for_model(colmap_dir, default)
            %% UnitScale of a COLMAP model: 1 when its record says it is in mm
            % The record sits next to the undistorted cameras
            % (dense/sparse/metric_scale.json), or one folder up from a
            % built model (sparse_build/metric_scale.json). No record:
            % default. A record that cannot be read is an error: guessing
            % would put a mm model out by 1000.
            s = default;
            colmap_dir = regexprep(char(colmap_dir), '[\\/]+$', '');
            where = {fullfile(colmap_dir, 'metric_scale.json'), ...
                fullfile(fileparts(colmap_dir), 'metric_scale.json')};
            for k = 1:2
                if exist(where{k}, 'file') ~= 2, continue; end
                try
                    q = jsondecode(fileread(where{k}, 'Encoding', 'UTF-8'));
                catch ME
                    error('analyse_om:Reprojection:BadMetricRecord', '%s cannot be read: %s', where{k}, ME.message);
                end
                if ~isstruct(q) || ~isscalar(q) || ~isfield(q, 'applied') || ~islogical(q.applied) || ~isscalar(q.applied)
                    error('analyse_om:Reprojection:BadMetricRecord', '%s is not a scale record.', where{k});
                end
                if q.applied, s = 1; end
                return;
            end
        end

        function mesh = read_ply_mesh(path)
            %READ_PLY_MESH Read a PLY mesh. Supports ascii and
            %binary_little_endian, element vertex/face; other elements
            %are skipped. Returns struct: pts (Vx3), faces (Fx3,
            %triangles, 1-based), has_faces (logical).
            fid = fopen(path, 'rb');
            if fid < 0
                error('analyse_om:Reprojection:CannotOpen', 'Cannot open %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            magic = fgetl(fid);
            if ~strcmpi(strtrim(magic), 'ply')
                error('analyse_om:Reprojection:BadPly', '%s is not a PLY file.', path);
            end
            fmt = ''; nv = 0; nf = 0;
            vtypes = {}; % vertex property types in declaration order
            cur_elem = '';
            while true
                ln = fgetl(fid);
                if isequal(ln, -1)
                    error('analyse_om:Reprojection:BadPly', 'PLY header not terminated.');
                end
                line = strtrim(ln);
                if strcmpi(line, 'end_header'), break; end
                tok = strsplit(line);
                if isempty(tok{1}), continue; end
                switch lower(tok{1})
                    case 'format'
                        if numel(tok) < 2, continue; end
                        fmt = lower(tok{2});
                    case 'element'
                        if numel(tok) < 3, continue; end
                        cur_elem = lower(tok{2});
                        switch cur_elem
                            case 'vertex', nv = str2double(tok{3});
                            case 'face', nf = str2double(tok{3});
                        end
                    case 'property'
                        if strcmp(cur_elem, 'vertex') && numel(tok) >= 3
                            vtypes{end + 1} = lower(tok{2}); %#ok<AGROW>
                        end
                end
            end
            if ~strcmp(fmt, 'ascii') && ~strcmp(fmt, 'binary_little_endian')
                error('analyse_om:Reprojection:BadPly', ...
                    'Unsupported PLY format ''%s'' (ascii or binary_little_endian).', fmt);
            end
            if nv == 0, error('analyse_om:Reprojection:BadPly', 'PLY has no vertices.'); end
            binary = strcmp(fmt, 'binary_little_endian');
            if binary
                vstart = ftell(fid);
                % vertex precision from the header: double if any of the
                % first three scalar properties is declared double,
                % otherwise float (COLMAP/APDe-MVS PLYs use float;
                % some exporters write doubles)
                prec = 'float32';
                nscal = min(3, numel(vtypes));
                for i = 1:nscal
                    if strcmp(vtypes{i}, 'double') || strcmp(vtypes{i}, 'float64')
                        prec = 'float64';
                        break;
                    end
                end
                % Full vertex record size (all declared scalar
                % properties). The fused COLMAP PLY carries 6 float32
                % (x,y,z,nx,ny,nz) + 3 uchar (r,g,b) = 27 bytes/vertex;
                % reading only 3*nv floats would misalign every record
                % after the first.
                rec = 0;
                for t = 1:numel(vtypes)
                    s = rabbit_rhythm_reproject.ply_scalar_size(vtypes{t});
                    if s <= 0
                        error('analyse_om:Reprojection:BadPly', ...
                            'Unsupported vertex property type ''%s'' (list properties on vertices are not supported).', ...
                            vtypes{t});
                    end
                    rec = rec + s;
                end
                fseek(fid, vstart, 'bof');
                raw = fread(fid, rec * nv, '*uint8');
                if numel(raw) < rec * nv
                    error('analyse_om:Reprojection:BadPly', ...
                        'PLY vertex data truncated (declared %d, record %d bytes).', ...
                        nv, rec);
                end
                raw = reshape(raw, rec, nv)';
                % xyz = the first three scalar properties.
                if strcmp(prec, 'float64')
                    xyz_raw = raw(:, 1:24);
                    pts = double(typecast(reshape(xyz_raw', 24 * nv, 1), 'double'));
                else
                    xyz_raw = raw(:, 1:12);
                    pts = double(typecast(reshape(xyz_raw', 12 * nv, 1), 'single'));
                end
                pts = reshape(pts, 3, nv)';
                faces = zeros(0, 3);
                if nf > 0
                    for f = 1:nf
                        cnt = fread(fid, 1, 'uint8');
                        if isempty(cnt), break; end
                        idx = fread(fid, double(cnt), 'uint32')';
                        if cnt == 3
                            faces(end + 1, :) = double(idx) + 1; %#ok<AGROW>
                        end
                        if feof(fid), break; end
                    end
                end
            else
                pts = zeros(nv, 3);
                for v = 1:nv
                    ln = fgetl(fid);
                    if isequal(ln, -1)
                        error('analyse_om:Reprojection:BadPly', 'Unexpected EOF in vertex data.');
                    end
                    C = sscanf(strtrim(ln), '%f');
                    pts(v, :) = C(1:3)';
                end
                faces = zeros(0, 3);
                for f = 1:nf
                    ln = fgetl(fid);
                    if isequal(ln, -1), break; end
                    C = sscanf(strtrim(ln), '%d');
                    if numel(C) >= 4 && C(1) == 3
                        faces(end + 1, :) = C(2:4)' + 1; %#ok<AGROW>
                    end
                end
            end
            mesh = struct('pts', double(pts), 'faces', double(faces), ...
                'path', path, 'n_vertices', nv, 'n_faces', size(faces, 1));
        end

        % =============================================================
        % 5. Mesh topology
        % =============================================================

        function [cells, centroids, norms, neighs, neighnum] = ...
                build_mesh_topology(pts, faces)
            %BUILD_MESH_TOPOLOGY From PLY vertices/faces build the RHYTHM
            %dataProjection02 inputs: cells (Fx3 1-based vertex indices),
            %centroids (Fx3), norms (Fx3 outward unit normals),
            %neighs/neighnum (per-face neighbour lists via edge hashing).
            cells = double(faces);
            c1 = pts(faces(:, 1), :);
            c2 = pts(faces(:, 2), :);
            c3 = pts(faces(:, 3), :);
            centroids = (c1 + c2 + c3) / 3;
            norms = cross(c2 - c1, c3 - c1, 2);
            ln = sqrt(sum(norms .* norms, 2));
            ln(ln == 0) = 1; % degenerate faces keep zero normal
            norms = norms ./ ln;
            % outward orientation: normals point away from the centroid
            % of the whole mesh (COLMAP PLY faces are consistently
            % oriented; this normalises sign for robustness)
            centre = mean(pts, 1);
            flip = sum((centroids - centre) .* norms, 2) < 0;
            norms(flip, :) = -norms(flip, :);
            % face adjacency via directed edge -> face map
            edgeMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            F = size(faces, 1);
            for f = 1:F
                for e = 1:3
                    a = faces(f, e);
                    b = faces(f, mod(e, 3) + 1);
                    key = sprintf('%d_%d', min(a, b), max(a, b));
                    if isKey(edgeMap, key)
                        edgeMap(key) = [edgeMap(key) f];
                    else
                        edgeMap(key) = f;
                    end
                end
            end
            neighs = cell(F, 1);
            neighnum = zeros(F, 1);
            for f = 1:F
                nb = [];
                for e = 1:3
                    a = faces(f, e);
                    b = faces(f, mod(e, 3) + 1);
                    key = sprintf('%d_%d', min(a, b), max(a, b));
                    vals = edgeMap(key);
                    for v = vals
                        if v ~= f
                            nb(end + 1) = v; %#ok<AGROW>
                        end
                    end
                end
                nb = unique(nb);
                neighs{f} = nb;
                neighnum(f) = numel(nb);
            end
        end

        % =============================================================
        % 6. The projection: vendored RHYTHM dataProjection02
        % =============================================================

        function out = project_views_rhythm(views, cam, view_cam, cells, ...
                centroids, norms, neighs, neighnum, unit_scale, shifts, pts, ...
                scales, frame_views, fps, min_edge_edge) %#ok<INUSD> (used inside evalc)
            %% Project per-view OM data with RHYTHM's dataProjection02
            % Calls the vendored, unmodified dataProjection02 with
            % RHYTHM-native inputs (four 100x100 views, see the class
            % header). Inputs as project_views, plus:
            %   frame_views  [] or 4x1 cell of per-view frame stacks
            %                (rows x cols x T, same views as the maps)
            %   fps          frame rate written into RHYTHM's .cdf header
            %   min_edge_edge  minedgeEDGE (default 0.55): another value runs
            %                a copy of dataProjection02 in the temporary
            %                folder whose only change is that line
            % Output struct:
            %   dataProj  nFaces x 1 activation (0 = unassigned)
            %   mask      nFaces x 1 assigned faces (some valid data)
            %   viewi     nFaces x 5 RHYTHM view assignment
            %   series    nFaces x T frame values ([] without frames;
            %             NaN = unassigned)
            %   textProj  nFaces x 1 RHYTHM texture (background image)
            %   masks, geommasks  100x100x4 RHYTHM view masks
            %   bins      per-view binning record (source size, factors)
            %   coverage  per view: surface points inside the 100x100 grid
            %             (0 = the view sees none of the mesh)
            %   n_points  number of surface points passed as Xshift/Yshift
            %   log       console text printed by dataProjection02
            grid = rabbit_rhythm_reproject.RHYTHM_GRID;
            nviews = numel(views);
            if nviews ~= 4
                error('analyse_om:Reprojection:NotFourViews', ...
                    'dataProjection02 maps exactly four views (got %d).', nviews);
            end
            [shifts_, scales_] = rabbit_rhythm_reproject.check_shifts_scales( ...
                nviews, shifts, scales);
            cam_name = rabbit_rhythm_reproject.RHYTHM_MAP_CAMERA;
            has_frames = ~isempty(frame_views);
            if isempty(fps), fps = 1; end %#ok<NASGU> (used inside evalc)

            % ---- cameras: COLMAP -> RHYTHM, binned to the 100x100 grid ----
            Parmap = zeros(8, nviews);
            Posmap = zeros(6, nviews);
            looknmap = zeros(nviews, 3);
            shift = zeros(nviews, 2);
            bins = struct('source_size', {}, 'source_px_per_rhythm_px', {});
            for i = 1:nviews
                cm = rabbit_rhythm_reproject.find_camera(cam, view_cam{i});
                [par, pos, lookn] = rabbit_rhythm_reproject.colmap_to_rhythm( ...
                    cm, view_cam{i}.qvec, view_cam{i}.tvec, unit_scale);
                [nr, nc] = size(views{i});
                [Parmap(:, i), shift(i, :)] = rabbit_rhythm_reproject.bin_camera( ...
                    par, nr, nc, shifts_(i, :), scales_(i, :));
                Posmap(:, i) = pos;
                looknmap(i, :) = lookn;
                bins(i).source_size = [nr nc];
                bins(i).source_px_per_rhythm_px = [nr nc] / grid;
            end

            % ---- projected surface points (ORIENT2's Xshift/Yshift) ----
            % dataProjection02 rounds these points to pixels and hole-fills
            % the result to get each view's silhouette. ORIENT2 passes the
            % mesh vertices, which for RHYTHM's dense meshes cover every
            % pixel; for a coarser mesh the rounded vertices leave gaps and
            % the silhouette stays a scatter of points. The faces are
            % therefore sampled on a barycentric grid fine enough that
            % neighbouring samples are at most half a 100x100 pixel apart
            % in every view (just the vertices and face centroids when the
            % mesh is dense).
            % Only faces are sampled: a PLY may also carry the point
            % cloud, whose stray points would enlarge the silhouette.
            used = unique(cells(:));
            Xv = zeros(size(pts, 1), nviews);
            Yv = zeros(size(pts, 1), nviews);
            for i = 1:nviews
                [Xv(used, i), Yv(used, i)] = pred(pts(used, :), Parmap(:, i), ...
                    Posmap(:, i), cam_name);
            end
            % Only a view whose frame the face's projection touches counts:
            % samples outside every frame cannot change a silhouette, and
            % a camera close to the mesh (a poor pose) would otherwise ask
            % for millions of samples of faces far off its frame. A face
            % that crosses a frame is split at most 2*grid times.
            edge_px = zeros(size(cells, 1), 1);
            for i = 1:nviews
                Xf = reshape(Xv(cells, i) + shift(i, 1), [], 3);
                Yf = reshape(Yv(cells, i) + shift(i, 2), [], 3);
                touches = max(Xf, [], 2) >= 0 & min(Xf, [], 2) <= grid + 1 & ...
                    max(Yf, [], 2) >= 0 & min(Yf, [], 2) <= grid + 1;
                e_i = zeros(size(cells, 1), 1);
                for e = 1:3
                    b = mod(e, 3) + 1;
                    e_i = max(e_i, hypot(Xf(:, e) - Xf(:, b), Yf(:, e) - Yf(:, b)));
                end
                e_i(~touches) = 0;
                edge_px = max(edge_px, e_i);
            end
            n_sub = min(max(1, ceil(edge_px / 0.5)), 2 * grid);
            levels = unique(n_sub(n_sub > 1))';
            parts = cell(numel(levels) + 1, 1);
            parts{1} = [pts(used, :); centroids];
            for L = 1:numel(levels)
                n = levels(L);
                [bi, bj] = meshgrid(0:n, 0:n);
                keep = bi + bj <= n;
                w = [bi(keep), bj(keep)] / n;   % barycentric weights of V1, V2
                f = find(n_sub == n);
                V1 = pts(cells(f, 1), :);
                V2 = pts(cells(f, 2), :);
                V3 = pts(cells(f, 3), :);
                nf = numel(f);
                P = zeros(nf * size(w, 1), 3);
                for q = 1:size(w, 1)
                    P((q - 1) * nf + (1:nf), :) = w(q, 1) * V1 + w(q, 2) * V2 + ...
                        (1 - w(q, 1) - w(q, 2)) * V3;
                end
                parts{L + 1} = P;
            end
            samples = vertcat(parts{:});
            Xshift = cell(1, nviews);
            Yshift = cell(1, nviews);
            coverage = zeros(1, nviews);
            for i = 1:nviews
                [X, Y] = pred(samples, Parmap(:, i), Posmap(:, i), cam_name);
                Xshift{i} = X + shift(i, 1);
                Yshift{i} = Y + shift(i, 2);
                x = round(Xshift{i}); y = round(Yshift{i});
                coverage(i) = nnz(x >= 1 & x <= grid & y >= 1 & y <= grid);
            end
            if all(coverage == 0)
                error('analyse_om:Reprojection:ViewSeesNothing', ...
                    ['The mesh does not project inside any view; check the ' ...
                    'cameras, the shifts and the mesh.']);
            end
            % dataProjection02's out-of-frame filter (lines 61-84) fails
            % when no point of a view is inside its frame. Such a view gets
            % one placeholder point at pixel (1,1). It cannot change any
            % face: the points include every face centroid, so no centroid
            % is inside that view, and dataProjection02 only builds edge
            % weights and pixel kernels for faces whose centroid is.
            for i = find(coverage == 0)
                Xshift{i}(end + 1) = 1;
                Yshift{i}(end + 1) = 1;
            end

            % ---- 100x100 views: coverage frame, map, then OM frames ----
            cmosData = cell(1, nviews);
            bgMask = cell(1, nviews);
            bg = cell(1, nviews);
            for i = 1:nviews
                valid = isfinite(views{i});
                [S, W] = rabbit_rhythm_reproject.bin_view(views{i}, valid, grid);
                if has_frames
                    F = frame_views{i};
                    F(~isfinite(F)) = 0;
                    if size(F, 1) == grid && size(F, 2) == grid && ...
                            ~isequal(size(views{i}), [grid grid])
                        % Already binned to the grid by run()
                        SF = F;
                    else
                        SF = rabbit_rhythm_reproject.bin_view(F, valid, grid);
                    end
                    cmosData{i} = cat(3, W, S, SF);
                    tex = mean(SF, 3);
                else
                    cmosData{i} = cat(3, W, S);
                    tex = S;
                end
                bgMask{i} = double(W >= 0.5);
                bg{i} = zeros(grid);
                bg{i}(W > 0) = tex(W > 0) ./ W(W > 0);
            end
            geommasks = zeros(grid, grid, nviews);

            % ---- run dataProjection02 in a temporary folder ----
            % It writes '<filename(1:2)>_d.cdf' to the current folder and
            % opens a msgbox and a waitbar; both are undone on exit. Small
            % msgbox.m and waitbar.m stand-ins written into the temporary
            % folder shadow MATLAB's own while it is the current folder, so
            % those two never appear on screen.
            work = tempname;
            mkdir(work);
            rabbit_rhythm_reproject.write_rhythm_stubs(work);
            if nargin < 15 || isempty(min_edge_edge)
                min_edge_edge = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            end
            edge_copy = min_edge_edge ~= rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            if edge_copy
                % Written before the temporary folder becomes current, so
                % that which() still finds the vendored file
                rabbit_rhythm_reproject.write_edge_copy(work, min_edge_edge);
            end
            clear('dataProjection02');
            figs0 = findall(0, 'type', 'figure');
            % The app may be found only because its folder is the current
            % folder (MATLAB started with -sd there). Leaving that folder
            % would lose this class and the app's other files, so the
            % folder is on the path while the temporary one is current
            own = fileparts(mfilename('fullpath'));
            own_added = ~any(strcmpi(strsplit(path, pathsep), own));
            if own_added, addpath(own, '-end'); end
            here = cd(work);
            restore = onCleanup(@() rabbit_rhythm_reproject.rhythm_cleanup( ...
                here, figs0, work, own, own_added));
            dataProj = []; textProj = []; viewi = []; masks = [];
            rhythm_log = evalc(['[dataProj, textProj, viewi, geommasks, masks] = ' ...
                'dataProjection02(Xshift, Yshift, shift, norms, centroids, ' ...
                'cells, pts, neighs, neighnum, Parmap, Posmap, cam_name, ' ...
                'bgMask, bg, geommasks, grid, grid, looknmap, cmosData, ' ...
                'fps, work, ''om_projection'');']);

            % ---- values = projected data / projected coverage ----
            cover = dataProj(:, 1);
            assigned = viewi(:, end) > 0 & isfinite(cover) & cover > 1e-9;
            vals = dataProj(:, 2:end) ./ cover;
            vals(~assigned, :) = NaN;
            out.dataProj = vals(:, 1);
            out.dataProj(~isfinite(out.dataProj)) = 0;
            out.mask = assigned;
            out.viewi = viewi;
            if has_frames
                out.series = vals(:, 2:end);
            else
                out.series = [];
            end
            out.textProj = textProj;
            out.coverage_proj = cover;
            out.masks = masks;
            out.geommasks = geommasks;
            out.bins = bins;
            out.coverage = coverage;
            out.n_points = size(samples, 1);
            out.Parmap = Parmap;
            out.Posmap = Posmap;
            out.shift = shift;
            out.camera = cam_name;
            out.log = rhythm_log;
            out.edge_copy = edge_copy;
            clear('dataProjection02');
        end

        function [speed, why] = app_cv_speed(app, map)
            %% The Conduction Velocity tab's speed map, when it can be projected
            % CV_map is rows x cols x 3 (row and column components, speed;
            % m/s) on the canvas of the activation map. [] and why not
            % otherwise ('' when there is no CV map at all).
            speed = [];
            why = '';
            try
                cv = app.processed_data.CV_map;
            catch
                cv = [];
            end
            if isempty(cv)
                return;
            end
            % Not one made from an earlier activation map
            why = rabbit_cv_map.stale(app);
            if ~isempty(why), return; end
            if ndims(cv) ~= 3 || size(cv, 3) < 3
                why = 'the CV map is not rows x columns x 3.';
                return;
            end
            if size(cv, 1) ~= size(map, 1) || size(cv, 2) ~= size(map, 2)
                why = sprintf(['the CV map (%dx%d) is not the size of the activation map (%dx%d); ' ...
                    'make it again from this map.'], size(cv, 1), size(cv, 2), size(map, 1), size(map, 2));
                return;
            end
            s = double(cv(:, :, 3));
            s(~isfinite(s)) = NaN;
            if ~any(isfinite(s(:)) & s(:) > 0)
                why = 'the CV map has no values (make it in the Conduction Velocity tab).';
                return;
            end
            speed = s;
        end

        function c = app_cv_cut(app, map)
            %% The CV map's activation cut (CV_settings.activation_cut_ms) with the map, for CvActivationCut; [] without one
            % None unless the CV map was made with
            % "Leave out activation times above the display limit" ticked
            c = [];
            try
                s = app.processed_data.CV_settings;
                if isstruct(s) && isfield(s, 'activation_cut_ms')
                    v = double(s.activation_cut_ms);
                    if isscalar(v) && isfinite(v), c = struct('map', map, 'cut_ms', v); end
                end
            catch
            end
        end

        function S = app_cv_pixel_um(app)
            %% Each pixel's size (um) as the app's CV map was made with it (rabbit_cv_map.pixel_um_map), [] if none
            % For the tilt-corrected surface speed; the sizes kept with the
            % CV map
            S = rabbit_cv_map.pixel_um_map(app);
        end

        function a = app_cv_spread(app)
            %% Each view's activation spread the app's CV map was made from (processed_data.CV_activation_spread), [] if none
            a = [];
            try
                if isfield(app.processed_data, 'CV_activation_spread') && isstruct(app.processed_data.CV_activation_spread)
                    a = app.processed_data.CV_activation_spread;
                end
            catch
                a = [];
            end
        end

        function [comp, M] = cv_view_components(cv_rc, bounds, rotation, flip_rows, view_flips)
            %% The canvas CV vectors as vectors in each view's map
            % cv_rc: rows x cols x 2 on the canvas of the activation map;
            % layer 1 is the row (down) and layer 2 the column (right)
            % component, as the Conduction Velocity tab stores and draws
            % them (its quiver takes CV_map(:,:,2) across, CV_map(:,:,1)
            % down). Each layer goes down the same chain as the map in run()
            % (split_canvas, FlipRows, ViewFlips). The tiles are turned and
            % mirrored on the way, so the components are mixed and change
            % sign too: an image of each canvas pixel's own row and column,
            % sent down the same chain, gives per view the 2 x 2 matrix M
            % with [d_row; d_col] on the canvas = M * [d_x; d_y] in the view
            % map (x right, y down). M only turns and mirrors, so the view
            % vector is M' * [v_row; v_col].
            % comp: 4x1 cell, rows x cols x 2 per view, layer 1 the x
            % (column) and layer 2 the y (row) component in the view's map
            % pixels, NaN where the canvas has none. M: 2 x 2 x 4.
            [h, w, ~] = size(cv_rc);
            [C, R] = meshgrid(1:w, 1:h);
            rv = rabbit_rhythm_reproject.cv_split_flip(R, bounds, rotation, flip_rows, view_flips);
            cvw = rabbit_rhythm_reproject.cv_split_flip(C, bounds, rotation, flip_rows, view_flips);
            vr = rabbit_rhythm_reproject.cv_split_flip(double(cv_rc(:, :, 1)), bounds, rotation, flip_rows, view_flips);
            vc = rabbit_rhythm_reproject.cv_split_flip(double(cv_rc(:, :, 2)), bounds, rotation, flip_rows, view_flips);
            nv = numel(rv);
            comp = cell(nv, 1);
            M = zeros(2, 2, nv);
            for k = 1:nv
                [nr, nc] = size(rv{k});
                [X, Y] = meshgrid(1:nc, 1:nr);
                % Least squares, so a binned canvas (each pixel over an
                % N x N block) gives the same turn, scaled by 1/N
                B = [X(:) Y(:) ones(nr * nc, 1)] \ [rv{k}(:) cvw{k}(:)];
                Mk = B(1:2, :)';
                Mk = round(Mk / max(abs(Mk(:))));
                if nnz(Mk) ~= 2 || abs(det(Mk)) ~= 1
                    error('analyse_om:Reprojection:CvAxes', ...
                        'The canvas axes of view %d could not be followed through the split (%s).', ...
                        k, mat2str(B(1:2, :)', 3));
                end
                M(:, :, k) = Mk;
                Mi = Mk';
                comp{k} = cat(3, Mi(1, 1) * vr{k} + Mi(1, 2) * vc{k}, ...
                    Mi(2, 1) * vr{k} + Mi(2, 2) * vc{k});
            end
        end

        function views = cv_split_flip(img, bounds, rotation, flip_rows, view_flips)
            %% A canvas image per view, split and flipped as the map in run()
            % flip_rows: 1 x 4 logical (FlipRows); view_flips: 1 x 4 cell
            % of 'none', 'lr', 'ud' or 'lrud' (ViewFlips). Same order as
            % run(): split_canvas, then the row flip, then left-right, then
            % up-down.
            views = rabbit_rhythm_reproject.split_canvas(img, bounds, rotation);
            flip_rows = logical(flip_rows(:)');
            if isscalar(flip_rows), flip_rows = repmat(flip_rows, 1, numel(views)); end
            if isempty(view_flips), view_flips = repmat({'none'}, 1, numel(views)); end
            for k = 1:numel(views)
                if flip_rows(k), views{k} = flipud(views{k}); end
                if contains(view_flips{k}, 'lr'), views{k} = fliplr(views{k}); end
                if contains(view_flips{k}, 'ud'), views{k} = flipud(views{k}); end
            end
        end

        function frames = cv_direction_frames(views, cv_views)
            %% Per-view frames that make dataProjection02 give the CV direction's inputs
            % Three frames per view k (frames 3k-2..3k of every view): the
            % fraction of each 100x100 pixel with a CV vector, and the two
            % components times that fraction (exact area sums, as the map
            % is binned), in view k only and zero in the others. Averaged
            % over a face by dataProjection02 like the speed, a face gets
            % from frame 3k-2 the weight view k has in the speed (its edge
            % weight times its data coverage, over the face's total) and
            % from frames 3k-1 and 3k divided by 3k-2 the mean vector of
            % view k over the face. A pixel counts when the speed and both
            % components are finite there (in the app's CV maps the
            % components are finite wherever the speed is).
            grid = rabbit_rhythm_reproject.RHYTHM_GRID;
            nv = numel(views);
            frames = cell(nv, 1);
            for k = 1:nv
                frames{k} = zeros(grid, grid, 3 * nv);
                c = cv_views{k};
                ok = isfinite(views{k}) & all(isfinite(c), 3);
                Ay = rabbit_rhythm_reproject.area_matrix(size(ok, 1), grid);
                Ax = rabbit_rhythm_reproject.area_matrix(size(ok, 2), grid);
                cx = c(:, :, 1);
                cy = c(:, :, 2);
                cx(~ok) = 0;
                cy(~ok) = 0;
                frames{k}(:, :, 3 * k - 2) = Ay * double(ok) * Ax';
                frames{k}(:, :, 3 * k - 1) = Ay * cx * Ax';
                frames{k}(:, :, 3 * k) = Ay * cy * Ax';
            end
        end

        function [D, rec, n_used, w_used, F] = cv_face_directions(method, dir_series, ledge, kernels, viewi, mask, ...
                cv_views, cam, view_cam, centroids, norms, cells, pts, unit_scale, shifts, scales, pixel_mm)
            %% A 3D unit CV direction in the surface for each assigned face
            % For each view a face takes its speed from, that view's mean CV
            % vector over the face (in the view's map pixels,
            % cv_view_components) is lifted onto the face: the direction in
            % the face's plane whose image at the face centroid is that
            % vector (lift_direction, with the projection's Jacobian at the
            % centroid through the same camera, shift and scale as the
            % values). The views of an OVERLAP or EDGE face are combined as
            % the weighted mean of their unit directions, with the weights
            % of the speed:
            %   rhythm            dataProjection02's own (cv_direction_frames
            %                     gives each view's mean vector and weight
            %                     from the same averaging as the speed)
            %   reimplementation  project_views' edge weights and pixel
            %                     kernels (ledge, kernels)
            % D: nFaces x 3, NaN where none; rec: the manifest record;
            % n_used: nFaces x 1, the views that gave a direction; w_used:
            % nFaces x nViews, their weights (summing to 1 per face).
            % pixel_mm (optional): 1 x nViews, mm
            % per map pixel of each view as the CV map used it; then F:
            % nFaces x 1, the factor from the image-plane speed to the
            % tilt-corrected surface speed (lift_speed: 1/|A'g|), the
            % weighted mean of the views' factors with the direction's
            % weights; NaN where none (all NaN without pixel_mm).
            if nargin < 17, pixel_mm = []; end
            nF = size(centroids, 1);
            nv = numel(cv_views);
            vx = nan(nF, nv);
            vy = nan(nF, nv);
            w = zeros(nF, nv);
            last = viewi(:, end);
            if strcmp(method, 'rhythm')
                for k = 1:nv
                    q = dir_series(:, 3 * k - 2 : 3 * k);
                    ok = all(isfinite(q), 2) & q(:, 1) > 0;
                    vx(ok, k) = q(ok, 2) ./ q(ok, 1);
                    vy(ok, k) = q(ok, 3) ./ q(ok, 1);
                    w(ok, k) = q(ok, 1);
                end
                weights = ['dataProjection02''s own: three extra frames per view (that view''s CV coverage and ' ...
                    'its two components, zero in the other views) are projected with the speed, so each face ' ...
                    'gets each view''s area-mean vector over its pixel kernel and the weight the view has in ' ...
                    'the speed (edge weight times data coverage; DIRECT faces one view) from the same averaging'];
            else
                for f = find(last(:)' > 0)
                    if last(f) <= nv
                        g = last(f);
                    else
                        g = find(viewi(f, 1:nv));
                    end
                    for k = g
                        [ax_, okx] = rabbit_rhythm_reproject.kernel_mean(cv_views{k}(:, :, 1), kernels(f, k, :));
                        [ay_, oky] = rabbit_rhythm_reproject.kernel_mean(cv_views{k}(:, :, 2), kernels(f, k, :));
                        if ~(okx && oky && isfinite(ax_) && isfinite(ay_)), continue; end
                        vx(f, k) = ax_;
                        vy(f, k) = ay_;
                        if last(f) <= nv
                            w(f, k) = 1;
                        else
                            w(f, k) = ledge(f, k);
                        end
                    end
                end
                weights = ['the transcription''s (project_views): each view''s area-mean vector over the ' ...
                    'face''s pixel kernel, weighted by its edge weight for OVERLAP and EDGE faces, as the speed'];
            end
            w(~logical(mask(:)), :) = 0;

            % Lift each view's vector onto the faces it covers
            [shifts_, scales_] = rabbit_rhythm_reproject.check_shifts_scales(nv, shifts, scales);
            e = vecnorm(pts(cells(:, 1), :) - pts(cells(:, 2), :), 2, 2);
            h = 1e-3 * median(e(e > 0));
            if isempty(h) || ~isfinite(h), h = 1e-3; end
            acc = zeros(nF, 3);
            n_used = zeros(nF, 1);
            w_used = zeros(nF, nv);
            n_edge_on = 0;
            have_px = isnumeric(pixel_mm) && numel(pixel_mm) == nv && all(isfinite(pixel_mm(:)) & pixel_mm(:) > 0);
            f_acc = zeros(nF, 1);
            f_w = zeros(nF, 1);
            for k = 1:nv
                f = find(w(:, k) > 0 & isfinite(vx(:, k)) & isfinite(vy(:, k)) & hypot(vx(:, k), vy(:, k)) > 0);
                if isempty(f), continue; end
                cm = rabbit_rhythm_reproject.find_camera(cam, view_cam{k});
                [par, pos] = rabbit_rhythm_reproject.colmap_to_rhythm(cm, view_cam{k}.qvec, ...
                    view_cam{k}.tvec, unit_scale);
                [Jx, Jy] = rabbit_rhythm_reproject.projection_jacobian(centroids(f, :), par, pos, ...
                    shifts_(k, :), scales_(k, :), h);
                d = rabbit_rhythm_reproject.lift_direction(Jx, Jy, norms(f, :), [vx(f, k) vy(f, k)]);
                ok = all(isfinite(d), 2);
                n_edge_on = n_edge_on + nnz(~ok);
                acc(f(ok), :) = acc(f(ok), :) + w(f(ok), k) .* d(ok, :);
                n_used(f(ok)) = n_used(f(ok)) + 1;
                w_used(f(ok), k) = w(f(ok), k);
                if have_px
                    % The same Jacobian and vector: the surface speed's factor
                    [~, fk] = rabbit_rhythm_reproject.lift_speed(Jx, Jy, norms(f, :), [vx(f, k) vy(f, k)], pixel_mm(k));
                    okf = isfinite(fk);
                    f_acc(f(okf)) = f_acc(f(okf)) + w(f(okf), k) .* fk(okf);
                    f_w(f(okf)) = f_w(f(okf)) + w(f(okf), k);
                end
            end
            F = nan(nF, 1);
            F(f_w > 0) = f_acc(f_w > 0) ./ f_w(f_w > 0);
            len = vecnorm(acc, 2, 2);
            D = acc ./ len;
            none = n_used == 0 | ~(len > 1e-9);
            D(none, :) = NaN;
            w_used = w_used ./ sum(w_used, 2);
            w_used(none, :) = 0;
            n_dir = nnz(all(isfinite(D), 2));

            rec = struct();
            rec.quantity = 'conduction velocity direction';
            rec.file = '';
            rec.variables = ['direction: faces x 3 unit vectors in the mesh''s frame (NaN = none); speed: faces x 1 ' ...
                'the projected speed (m/s, NaN = none); n_views: faces x 1 views that gave the direction; ' ...
                'view_weights: faces x 4 their weights (ROI order, summing to 1)'];
            rec.n_faces = nF;
            rec.n_assigned = nnz(mask);
            rec.n_with_direction = n_dir;
            rec.components = ['CV_map(:,:,1) the row (down) and CV_map(:,:,2) the column (right) component on the ' ...
                'canvas, as the Conduction Velocity tab draws its arrows; turned and mirrored with each view''s ' ...
                'tile (canvas_from_view: [d_row; d_col] = M * [d_x; d_y], ROI order)'];
            rec.lifting = ['per view, the face''s mean vector v (view map pixels; along the image gradient of the ' ...
                'activation time) at its centroid c, pulled back onto the face''s plane as a gradient: d = A''*v ' ...
                'in a basis of the plane, A = J*[t1 t2], J the 2 x 3 Jacobian of the projection (pred with the ' ...
                'COLMAP camera, distortion, shift and scale, central differences) at c; then normalised ' ...
                '(the transpose since 25.11.2026; the inverse before)'];
            rec.weights = weights;
            rec.combination = 'the weighted mean of the views'' unit directions, normalised';
            rec.approximations = { ...
                ['First order: the vector at the face centroid is lifted with the projection''s local Jacobian, ' ...
                'so the direction is that of the face''s plane, not of the curved surface under it.'], ...
                ['The CV vector is taken as the activation-time gradient direction in the OM map''s pixels (the app makes it with one ' ...
                'pixel scale for rows and columns), so a different row and column scale of the OM window ' ...
                'turns it with the pixels.'], ...
                ['The direction is in the surface (corrected for tilt). The speed file stays the in-plane speed ' ...
                'of each view (not corrected for tilt); the tilt-corrected surface speed is stored next to it ' ...
                '(speed_surface, when the pixel sizes were given).'], ...
                sprintf(['A view gives no direction where the face is seen nearly edge-on (one surface direction ' ...
                'shrunk below %.2f of the other in the image): %d view-face pairs.'], ...
                rabbit_rhythm_reproject.CV_LIFT_MIN_RATIO, n_edge_on), ...
                'Views that disagree are averaged as unit vectors; a face whose views cancel has no direction.'};
            rec.summary = sprintf(['CV direction lifted onto the surface (approximate) for %d of %d assigned ' ...
                'faces (%s); weights: %s.'], n_dir, nnz(mask), method, weights);
        end

        function [mask, dataProj, rec] = cv_activation_cut_faces(cut, canvas_hw, mask, dataProj, method, ...
                bounds, rotation, flip_rows, flip_lr, flip_ud, cam, view_cam, cells, centroids, norms, ...
                neighs, neighnum, unit_scale, shifts, pts, scales, fps, min_edge_edge)
            %% Faces whose projected activation is above the CV map's cut: no CV
            % cut: struct('map', the activation canvas the CV map was made
            % from, 'cut_ms', its cut). The activation map is projected
            % map only, as the speed was (same split, flips, cameras,
            % shifts, scales, edge weight and method); an assigned face
            % whose activation is above cut_ms is made unassigned in the
            % speed (mask false, value 0, dataProjection02's convention).
            % rec: what was done, [] when no cut applies (none asked for,
            % not finite, or a map of another size), so nothing changes.
            rec = [];
            if ~isstruct(cut) || ~all(isfield(cut, {'map', 'cut_ms'})), return; end
            cut_ms = double(cut.cut_ms);
            act = double(cut.map);
            if ~(isscalar(cut_ms) && isfinite(cut_ms)) || ~isequal(size(act), canvas_hw), return; end
            % the activation map's views, split and flipped as the speed's
            act_views = rabbit_rhythm_reproject.split_canvas(act, bounds, rotation);
            for k = 1:numel(act_views)
                if flip_rows(k), act_views{k} = flipud(act_views{k}); end
                if flip_lr(k), act_views{k} = fliplr(act_views{k}); end
                if flip_ud(k), act_views{k} = flipud(act_views{k}); end
            end
            if strcmp(method, 'rhythm')
                out = rabbit_rhythm_reproject.project_views_rhythm(act_views, cam, view_cam, cells, ...
                    centroids, norms, neighs, neighnum, unit_scale, shifts, pts, scales, [], fps, min_edge_edge);
                act_proj = out.dataProj;
                act_ok = logical(out.mask);
            else
                [act_proj, ~, act_ok] = rabbit_rhythm_reproject.project_views(act_views, cam, view_cam, ...
                    cells, centroids, norms, neighs, neighnum, unit_scale, shifts, pts, scales, min_edge_edge);
                act_ok = act_ok & isfinite(act_proj) & act_proj ~= 0;   % the same rule as the speed's
            end
            beyond = act_ok(:) & double(act_proj(:)) > cut_ms & logical(mask(:));
            mask(beyond) = false;
            dataProj(beyond) = 0;
            rec = struct('cut_ms', cut_ms, 'n_faces_left_out', nnz(beyond), ...
                'basis', ['faces whose projected activation (the activation map the CV map was made from, ' ...
                'projected as the speed) is above the cut get no CV']);
        end

        function r = surface_speed_record(speed, surface, pixel_mm, om_bin, n_steep)
            %% The manifest record of the tilt-corrected surface speed (cv_direction.surface_speed)
            % speed, surface: faces x 1 (m/s, NaN = none); medians over
            % the faces that have both. om_bin: the CV map's binning (its
            % pixel is om_bin unbinned OM pixels). n_steep: the faces
            % whose surface speed was left out, correction above
            % SURFACE_MAX_CORRECTION; steep_text names them for the
            % caption and the Results row.
            if nargin < 4 || isempty(om_bin), om_bin = 1; end
            if nargin < 5 || isempty(n_steep), n_steep = 0; end
            both = isfinite(speed) & isfinite(surface);
            if om_bin > 1
                px_is = sprintf(['mm per unbinned OM pixel (the CV map''s binned pixel / %g), the frame of the ' ...
                    'Jacobian'], om_bin);
            else
                px_is = 'mm per unbinned OM pixel (the CV map''s pixel, not binned), the frame of the Jacobian';
            end
            steep_text = '';
            if n_steep > 0
                % the count with thousands commas, as the app prints counts
                steep_text = sprintf('surface speed left out on %s steep faces (correction > %s%s)', ...
                    regexprep(sprintf('%d', round(n_steep)), '(\d)(?=(\d{3})+$)', '$1,'), ...
                    num2str(rabbit_rhythm_reproject.SURFACE_MAX_CORRECTION), char(215));
            end
            r = struct('variable', 'speed_surface (cv_direction.mat): faces x 1, m/s, NaN = none', ...
                'formula', ['per view, s = 1/|A''*g| with g = v_px/|v_px|^2 the image gradient of the activation ' ...
                'time (ms per map pixel; v_px the face''s mean CV vector in map pixels per ms) and A the ' ...
                'projection''s Jacobian on the face''s plane, as for the direction; the face''s projected ' ...
                'image-plane speed times the weighted mean over its views of s/|v|'], ...
                'pixel_mm', pixel_mm(:)', ...
                'pixel_mm_is', px_is, ...
                'n_faces', nnz(both), ...
                'correction_cap', rabbit_rhythm_reproject.SURFACE_MAX_CORRECTION, ...
                'steep_faces_left_out', n_steep, 'steep_text', steep_text, ...
                'median_image_plane', NaN, 'median_surface', NaN, ...
                'note', ['speed on the surface, corrected for its tilt and depth against each view (first ' ...
                'order, at the face''s plane); the image-plane speed stays the default']);
            if any(both)
                r.median_image_plane = median(speed(both));
                r.median_surface = median(surface(both));
            end
        end

        function [Jx, Jy] = projection_jacobian(xyz, par, pos, shift, scale, h)
            %% Gradients of a point's map pixel x and y with respect to the point
            % The same projection as the values (rhythm_pred: pred, the
            % per-view shift and scale), by central differences with step h
            % (mm). Jx, Jy: N x 3.
            rabbit_rhythm_reproject.ensure_rhythm_path();
            n = size(xyz, 1);
            Jx = zeros(n, 3);
            Jy = zeros(n, 3);
            for a = 1:3
                e = zeros(1, 3);
                e(a) = h;
                [xp, yp] = rabbit_rhythm_reproject.rhythm_pred(xyz + e, par, pos, shift, scale);
                [xm, ym] = rabbit_rhythm_reproject.rhythm_pred(xyz - e, par, pos, shift, scale);
                Jx(:, a) = (xp(:) - xm(:)) / (2 * h);
                Jy(:, a) = (yp(:) - ym(:)) / (2 * h);
            end
        end

        function d = lift_direction(Jx, Jy, n, v)
            %% The direction in a plane whose image is a given image vector
            % Jx, Jy: N x 3 gradients of the image x and y at a point of the
            % plane (projection_jacobian); n: N x 3 plane normals; v: N x 2
            % image CV vectors [vx vy]. With t1, t2 a basis of the plane, A =
            % [Jx; Jy] * [t1 t2] maps a plane direction to the image. The
            % image CV vector of the Bayly fit lies along the gradient of
            % the activation time in the image, and a gradient pulls back
            % onto the plane with the transpose: the activation time on the
            % plane is T(A p), so its gradient there is A' * g. The wave
            % runs along that gradient: d = [t1 t2] * (A' * v), normalised.
            % (A \ v would treat the vector as a displacement: on a plane
            % tilted 60 degrees a wave at 45 degrees would come out at 76;
            % probe_cv_direction_lift checks this.)
            % NaN where the plane is seen nearly edge-on (smaller singular
            % value of A below CV_LIFT_MIN_RATIO of the larger), as the
            % image vector then hardly fixes it.
            N = size(n, 1);
            n = n ./ vecnorm(n, 2, 2);
            a = repmat([1 0 0], N, 1);
            near_x = abs(n(:, 1)) > 0.9;
            a(near_x, :) = repmat([0 1 0], nnz(near_x), 1);
            t1 = cross(n, a, 2);
            t1 = t1 ./ vecnorm(t1, 2, 2);
            t2 = cross(n, t1, 2);
            A11 = sum(Jx .* t1, 2);
            A12 = sum(Jx .* t2, 2);
            A21 = sum(Jy .* t1, 2);
            A22 = sum(Jy .* t2, 2);
            dt = A11 .* A22 - A12 .* A21;
            % Singular values from the Frobenius norm and the determinant
            fro2 = A11 .^ 2 + A12 .^ 2 + A21 .^ 2 + A22 .^ 2;
            root = sqrt(max(fro2 .^ 2 - 4 * dt .^ 2, 0));
            s_max = sqrt((fro2 + root) / 2);
            s_min = sqrt(max(fro2 - root, 0) / 2);
            a1 = A11 .* v(:, 1) + A21 .* v(:, 2);   % A' * v, first plane coordinate
            a2 = A12 .* v(:, 1) + A22 .* v(:, 2);   % and second
            d = a1 .* t1 + a2 .* t2;
            d = d ./ vecnorm(d, 2, 2);
            bad = ~(s_min >= rabbit_rhythm_reproject.CV_LIFT_MIN_RATIO * s_max) | ~all(isfinite(d), 2);
            d(bad, :) = NaN;
        end

        function [s, f] = lift_speed(Jx, Jy, n, v, pixel_mm)
            %% The speed on a plane of a wave whose image CV vector is given: 1/|A'g| (tilt-corrected)
            % Jx, Jy, n as
            % for lift_direction (the same Jacobian, A = [Jx; Jy] * [t1
            % t2], image map pixels per mm on the plane); v: N x 2 image CV
            % vectors [vx vy] in mm/ms as the CV tab gives them (each view's
            % pixel size, pixel_mm: N x 1 or scalar, mm per map pixel, at
            % the calibration cube's depth). The image gradient of the
            % activation time is g = v_px / |v_px|^2 (ms per map pixel,
            % v_px = v / pixel_mm, the Bayly vector along the gradient);
            % on the plane the gradient is A' * g (ms per mm), so the
            % speed there is s = 1 / |A' * g| (mm/ms = m/s). f = s / |v|,
            % the factor from the image-plane speed to it: 1 on a plane
            % facing the camera at the cube's depth. NaN where the plane is
            % seen nearly edge-on (as lift_direction).
            N = size(n, 1);
            n = n ./ vecnorm(n, 2, 2);
            a = repmat([1 0 0], N, 1);
            near_x = abs(n(:, 1)) > 0.9;
            a(near_x, :) = repmat([0 1 0], nnz(near_x), 1);
            t1 = cross(n, a, 2);
            t1 = t1 ./ vecnorm(t1, 2, 2);
            t2 = cross(n, t1, 2);
            A11 = sum(Jx .* t1, 2);
            A12 = sum(Jx .* t2, 2);
            A21 = sum(Jy .* t1, 2);
            A22 = sum(Jy .* t2, 2);
            dt = A11 .* A22 - A12 .* A21;
            fro2 = A11 .^ 2 + A12 .^ 2 + A21 .^ 2 + A22 .^ 2;
            root = sqrt(max(fro2 .^ 2 - 4 * dt .^ 2, 0));
            s_max = sqrt((fro2 + root) / 2);
            s_min = sqrt(max(fro2 - root, 0) / 2);
            vp = v ./ pixel_mm;                                % map pixels per ms
            g = vp ./ sum(vp .^ 2, 2);                         % ms per map pixel
            b1 = A11 .* g(:, 1) + A21 .* g(:, 2);              % A' * g, ms per mm on the plane
            b2 = A12 .* g(:, 1) + A22 .* g(:, 2);
            s = 1 ./ hypot(b1, b2);
            f = s ./ vecnorm(v, 2, 2);
            bad = ~(s_min >= rabbit_rhythm_reproject.CV_LIFT_MIN_RATIO * s_max) | ~isfinite(s) | ~isfinite(f);
            s(bad) = NaN;
            f(bad) = NaN;
        end

        function lim = check_display_limits(s)
            %% Display limits as struct('activation', [lo hi] or [], 'cv', [lo hi] or [])
            % A range that is not two finite numbers with lo < hi is [] (auto)
            % activation_auto (kept when given, true or false): the
            % activation range is the app's own automatic one (app_
            % display_limits), so Visualise takes its own auto range
            lim = struct('activation', [], 'cv', []);
            if ~isstruct(s), return; end
            for f = {'activation', 'cv'}
                if isfield(s, f{1})
                    v = s.(f{1});
                    if isnumeric(v) && numel(v) == 2 && all(isfinite(v(:))) && v(2) > v(1)
                        lim.(f{1}) = double(v(:))';
                    end
                end
            end
            for f = {'activation_auto', 'cv_auto'}
                if isfield(s, f{1}) && isscalar(s.(f{1})) && (islogical(s.(f{1})) || isnumeric(s.(f{1})))
                    lim.(f{1}) = logical(s.(f{1}));
                end
            end
        end

        function v = check_pacing_cycle(v)
            %% A pacing cycle in ms: [] or blank for none, else a positive finite number
            % Text is read as a number; 0, a negative number or text that
            % is not a number is refused (analyse_om:Reprojection:
            % BadPacingCycle) with a message that says what to type
            if isempty(v) || ((ischar(v) || isstring(v)) && strlength(strtrim(string(v))) == 0)
                v = [];
                return;
            end
            raw = v;
            if ischar(v) || isstring(v), v = str2double(strtrim(char(v))); end
            if ~isnumeric(v) || ~isscalar(v) || ~isreal(v) || ~isfinite(v) || v <= 0
                error('analyse_om:Reprojection:BadPacingCycle', ['The pacing cycle must be a positive number ' ...
                    'of ms (2 Hz = 500 ms), or blank when it is not known; got %s.'], ...
                    strtrim(evalc('disp(raw)')));
            end
            v = double(v);
        end

        function auto = app_limits_are_auto(app, lo_hi)
            %% True when [lo hi] is the range the app sets itself after drawing a map
            % Generate map shows a map with the colour range [0, max] and
            % copies it into Lower and Upper Y limit, max being the map's
            % maximum as the app takes it: max_value_ACT or max_value_APD,
            % the map's own maximum, or that rounded up to the next 10 (the
            % map types' choices in analyse_optical_mapping). A range typed
            % into the fields is any other pair; one typed to exactly such a
            % pair cannot be told apart and counts as the app's.
            auto = false;
            if ~isnumeric(lo_hi) || numel(lo_hi) ~= 2 || lo_hi(1) ~= 0, return; end
            cand = [];
            for f = {'max_value_ACT', 'max_value_APD'}
                try
                    v = double(app.(f{1}));
                    if isscalar(v) && isfinite(v), cand(end + 1) = v; end %#ok<AGROW>
                catch
                end
            end
            try
                mx = double(max(app.processed_data.activation_map(:), [], 'omitnan'));
                if isscalar(mx) && isfinite(mx), cand = [cand, mx, 10 * ceil(mx / 10)]; end
            catch
            end
            auto = any(abs(lo_hi(2) - cand) <= 1e-9 * max(1, abs(cand)));
        end

        function auto = app_cv_limits_are_auto(app, lo_hi)
            %% True when [lo hi] is the CV range the app sets itself after drawing a CV map
            % The Conduction Velocity tab draws a CV map with [0, its 99th
            % percentile of the speeds] (rabbit_cv_map.display_range) and
            % copies it into its Lower and Upper limit; [0, the map's
            % maximum] (all three layers, as plot_CV_map takes it, or the
            % speeds alone), the range of older CV maps, counts as automatic
            % too. Any other pair was typed; one typed to exactly such a
            % pair cannot be told apart and counts as the app's.
            auto = false;
            if ~isnumeric(lo_hi) || numel(lo_hi) ~= 2 || lo_hi(1) ~= 0, return; end
            cand = [];
            try
                cv = double(app.processed_data.CV_map);
                s = cv(:, :, 3);
                cand = [max(cv(:), [], 'omitnan'), max(s(:), [], 'omitnan')];
                r = rabbit_cv_map.display_range(cv);
                cand(end + 1) = r(2);
            catch
            end
            cand = cand(isfinite(cand));
            auto = any(abs(lo_hi(2) - cand) <= 1e-9 * max(1, abs(cand)));
        end

        function lim = app_display_limits(app)
            %% The colour ranges the app shows its maps with
            % Activation: the Activation Map tab's Lower and Upper Y limit
            % (lowerylimit, upperylimit; ms). Conduction velocity: the
            % Conduction Velocity tab's Lower and Upper Y limit
            % (lowerylimit_traces, upperylimit_traces; m/s). That tab shows
            % either its CV map or an activation map made from the traces
            % in the same axes and sets the same two fields for both, so
            % they are taken as CV limits only when there is a CV map and
            % the range overlaps its speeds without going above twice the
            % largest one (an activation range in ms would). [] = auto.
            % activation_auto records whether the activation range is the
            % app's own automatic one (app_limits_are_auto): then Visualise
            % uses its own auto range instead
            lim = struct('activation', [], 'cv', []);
            try
                lim.activation = [app.lowerylimit.Value, app.upperylimit.Value];
                lim.activation_auto = rabbit_rhythm_reproject.app_limits_are_auto(app, lim.activation);
            catch
            end
            try
                cv = app.processed_data.CV_map;
                lo_hi = [app.lowerylimit_traces.Value, app.upperylimit_traces.Value];
                s = double(cv(:, :, 3));
                s = s(isfinite(s) & s > 0);
                if ~isempty(s) && lo_hi(2) > lo_hi(1) && lo_hi(1) < max(s) && lo_hi(2) <= 2 * max(s)
                    % The app's own automatic CV pair is not recorded, so
                    % Visualise takes its own auto range; typed limits are
                    lim.cv_auto = rabbit_rhythm_reproject.app_cv_limits_are_auto(app, lo_hi);
                    if ~lim.cv_auto, lim.cv = lo_hi; end
                end
            catch
            end
            lim = rabbit_rhythm_reproject.check_display_limits(lim);
        end

        function v = app_min_edge_edge(app)
            %% The Reconstruction tab's edge setting, else RHYTHM's 0.55
            v = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            try
                if isprop(app.recon, 'ReconstructionEdgeWeightField') && ~isempty(app.recon.ReconstructionEdgeWeightField)
                    v = rabbit_rhythm_reproject.check_min_edge_edge(app.recon.ReconstructionEdgeWeightField.Value);
                end
            catch
                v = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            end
        end

        function v = check_min_edge_edge(v)
            %% The edge faces' minimum edge weight: a number from 0.1 to 0.9
            if ischar(v) || isstring(v), v = str2double(v); end
            if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v < 0.1 || v > 0.9
                error('analyse_om:Reprojection:BadMinEdge', ...
                    ['The minimum edge weight of edge faces must be a number from 0.1 to 0.9 ' ...
                    '(RHYTHM: %.2f).'], rabbit_rhythm_reproject.MIN_EDGE_EDGE);
            end
            v = double(v);
        end

        function write_edge_copy(work, v)
            %% dataProjection02 with minedgeEDGE = v, in the temporary folder
            % The vendored file is read, never changed; its line 49 must be
            % exactly RHYTHM's, or the projection stops rather than run a
            % file that differs in more than that value.
            src = which('dataProjection02');
            if isempty(src)
                error('analyse_om:Reprojection:VendorMissing', 'The vendored dataProjection02.m is not on the path.');
            end
            txt = fileread(src);
            old = sprintf('minedgeEDGE=%.2f;', rabbit_rhythm_reproject.MIN_EDGE_EDGE);
            at = strfind(txt, old);
            if numel(at) ~= 1
                error('analyse_om:Reprojection:EdgeLine', ['%s does not hold "%s" exactly once, so the edge ' ...
                    'threshold cannot be set without changing more of it.'], src, old);
            end
            txt = [txt(1:at - 1) sprintf('minedgeEDGE=%.17g;', v) txt(at + numel(old):end)];
            fid = fopen(fullfile(work, 'dataProjection02.m'), 'w', 'n', 'UTF-8');
            if fid < 0
                error('analyse_om:Reprojection:CannotWrite', 'Cannot write the copy of dataProjection02 in %s.', work);
            end
            fprintf(fid, '%s', txt);
            fclose(fid);
        end

        function [par_b, shift_b] = bin_camera(par, nr, nc, shift, scale)
            %% Fold the 100x100 resampling into a RHYTHM camera
            % par    8x1 RHYTHM parameters for RHYTHM_CAMERA (native px)
            % nr,nc  source view size; shift [dx dy]; scale [sv sh]
            % A native camera pixel X maps to the OM map pixel
            % (X - 0.5 + dx)/sh + 0.5 (pixel centres line up at any scale)
            % and then to the 100x100 pixel
            % (X - 0.5 + dx)*100/(nc*sh) + 0.5, i.e. X*ax + offset.
            % The linear factor goes into the 'brainvision_ultimaL'
            % parameters (focal length from the vertical factor, aspect
            % ratio from the ratio of the two, principal point scaled, and
            % the Heikkila distortion terms rescaled so the distortion is
            % unchanged in normalised sensor units); the offset becomes
            % RHYTHM's per-view shift.
            grid = rabbit_rhythm_reproject.RHYTHM_GRID;
            src = configc(rabbit_rhythm_reproject.RHYTHM_CAMERA);
            dst = configc(rabbit_rhythm_reproject.RHYTHM_MAP_CAMERA);
            ax = grid / (nc * scale(2));
            ay = grid / (nr * scale(1));
            f_px = par(2) * src(2) / src(4);         % focal length, native px
            f_b = ay * f_px * dst(4) / dst(2);       % focal length, mm on the 100x100 sensor
            s = f_b / par(2);                        % normalised-coordinate ratio
            par_b = zeros(8, 1);
            par_b(1) = par(1) * (ax / ay) * (src(1) / src(3)) / (dst(1) / dst(3)) ...
                * (dst(2) / dst(4)) / (src(2) / src(4));
            par_b(2) = f_b;
            par_b(3) = ax * par(3);
            par_b(4) = ay * par(4);
            par_b(5) = par(5) / s^2;
            par_b(6) = par(6) / s^4;
            par_b(7) = par(7) / s;
            par_b(8) = par(8) / s;
            shift_b = [ax * (shift(1) - 0.5) + 0.5, ...
                ay * (shift(2) - 0.5) + 0.5];
        end

        function [S, W] = bin_view(v, valid, grid)
            %% Exact area resampling of a view to grid x grid
            % v      rows x cols (x T) data; valid rows x cols logical
            % S      grid x grid (x T): area mean with invalid pixels as 0
            % W      grid x grid: fraction of each output pixel with data
            % S ./ W is the area mean of the valid source pixels.
            [nr, nc, nt] = size(v);
            Ay = rabbit_rhythm_reproject.area_matrix(nr, grid);
            Ax = rabbit_rhythm_reproject.area_matrix(nc, grid);
            W = Ay * double(valid) * Ax';
            S = zeros(grid, grid, nt);
            for t = 1:nt
                d = v(:, :, t);
                d(~valid) = 0;
                S(:, :, t) = Ay * d * Ax';
            end
        end

        function A = area_matrix(n, grid)
            %% Overlap of grid output pixels with n source pixels
            % A(i, r) = fraction of output pixel i covered by source pixel
            % r (rows sum to 1). Source pixel r spans [r-1, r]; output
            % pixel i spans [(i-1), i] * n / grid.
            A = zeros(grid, n);
            step = n / grid;
            for i = 1:grid
                lo = (i - 1) * step;
                hi = i * step;
                r = floor(lo) + 1 : ceil(hi);
                ov = min(hi, r) - max(lo, r - 1);
                A(i, r) = max(ov, 0) / step;
            end
        end

        function rhythm_cleanup(here, figs0, work, own, own_added)
            %% Undo dataProjection02's side effects
            % Restores the current folder, closes only the figures it
            % opened (its msgbox, tagged 'Msgbox_...', and its waitbar,
            % tagged 'TMWWaitbar') and removes its temporary folder.
            % Any other figure opened meanwhile is left alone.
            cd(here);
            % Forget the msgbox/waitbar stand-ins of the temporary folder
            clear('msgbox', 'waitbar');
            figs = findall(0, 'type', 'figure');
            extra = figs(~ismember(figs, figs0));
            if ~isempty(extra)
                tags = get(extra, {'Tag'});
                ours = startsWith(tags, 'Msgbox_') | strcmp(tags, 'TMWWaitbar');
                delete(extra(ours));
            end
            if isfolder(work), rmdir(work, 's'); end
            % The path as it was (the folder is current again)
            if nargin >= 5 && own_added, rmpath(own); end
        end

        function write_rhythm_stubs(work)
            %% Hidden msgbox/waitbar stand-ins for dataProjection02
            % dataProjection02 calls h = msgbox('Projecting....'),
            % delete(h), h = waitbar(0, '...'), waitbar(x) and close(h).
            % MATLAB's own msgbox and waitbar always show their window.
            % These two files go only into the temporary folder that is
            % the current folder while dataProjection02 runs, so they
            % shadow MATLAB's own there and nowhere else. They keep the
            % real Tags ('Msgbox_' + title and 'TMWWaitbar'), so
            % rhythm_cleanup finds them as it finds the real ones, and are
            % never shown.
            msgbox_src = { ...
                'function h = msgbox(varargin)'
                '% Hidden stand-in for MATLAB''s msgbox while RHYTHM''s dataProjection02'
                '% runs (written by rabbit_rhythm_reproject.write_rhythm_stubs).'
                'txt = '''';'
                'name = '''';'
                'if nargin >= 1, txt = varargin{1}; end'
                'if nargin >= 2, name = char(varargin{2}); end'
                'h = figure(''Visible'', ''off'', ''Tag'', [''Msgbox_'' name], ''Name'', name, ...'
                '    ''NumberTitle'', ''off'', ''IntegerHandle'', ''off'', ...'
                '    ''HandleVisibility'', ''callback'', ''UserData'', txt);'
                'end'};
            waitbar_src = { ...
                'function h = waitbar(x, varargin)'
                '% Hidden stand-in for MATLAB''s waitbar while RHYTHM''s dataProjection02'
                '% runs (written by rabbit_rhythm_reproject.write_rhythm_stubs).'
                '% waitbar(x, message) makes a new one, waitbar(x, h) and'
                '% waitbar(x, h, message) update h, and waitbar(x) updates the newest.'
                'h = [];'
                'if nargin >= 2 && ~isempty(varargin{1}) && ~ischar(varargin{1}) && ...'
                '        ~isstring(varargin{1}) && all(ishghandle(varargin{1}))'
                '    h = varargin{1};'
                'elseif nargin == 1'
                '    open = findall(0, ''Type'', ''figure'', ''Tag'', ''TMWWaitbar'');'
                '    if ~isempty(open), h = open(1); end'
                'end'
                'if isempty(h)'
                '    msg = '''';'
                '    if nargin >= 2 && (ischar(varargin{1}) || isstring(varargin{1}))'
                '        msg = char(varargin{1});'
                '    end'
                '    h = figure(''Visible'', ''off'', ''Tag'', ''TMWWaitbar'', ''Name'', '''', ...'
                '        ''NumberTitle'', ''off'', ''IntegerHandle'', ''off'', ...'
                '        ''HandleVisibility'', ''callback'');'
                '    setappdata(h, ''message'', msg);'
                'end'
                'setappdata(h, ''fraction'', x);'
                'if nargin >= 3, setappdata(h, ''message'', char(varargin{2})); end'
                'if nargout == 0, clear h; end'
                'end'};
            files = {'msgbox.m', msgbox_src; 'waitbar.m', waitbar_src};
            for k = 1:size(files, 1)
                fid = fopen(fullfile(work, files{k, 1}), 'w', 'n', 'UTF-8');
                if fid < 0
                    error('analyse_om:Reprojection:StubWrite', 'Could not write %s in %s.', ...
                        files{k, 1}, work);
                end
                fprintf(fid, '%s\n', files{k, 2}{:});
                fclose(fid);
            end
            % Make sure MATLAB sees the new files in that folder
            rehash;
        end

        function cm = find_camera(cam, vc)
            %% COLMAP camera record of one image record
            cm = [];
            for c = 1:numel(cam)
                if cam(c).id == vc.camera_id, cm = cam(c); break; end
            end
            if isempty(cm)
                error('analyse_om:Reprojection:CameraMissing', ...
                    'Camera %d for image ''%s'' not in cameras file.', ...
                    vc.camera_id, vc.name);
            end
        end

        function [shifts_, scales_] = check_shifts_scales(nviews, shifts, scales)
            %% Validate the per-view shifts [dx dy] and scales [sv sh]
            shifts_ = zeros(nviews, 2);
            if ~isempty(shifts)
                if isequal(size(shifts), [nviews 2])
                    shifts_ = double(shifts);
                else
                    error('analyse_om:Reprojection:BadShifts', 'Shifts must be nViews x 2 [dx dy].');
                end
            end
            scales_ = ones(nviews, 2);
            if ~isempty(scales)
                if isequal(size(scales), [nviews 2])
                    scales_ = double(scales);
                else
                    error('analyse_om:Reprojection:BadScales', 'Scales must be nViews x 2 [sv sh].');
                end
            end
        end

        % =============================================================
        % 6a. FALLBACK: MATLAB transcription of dataProjection02
        % =============================================================

        function [dataProj, viewi, mask, ledge, txtkernel] = project_views(views, cam, view_cam, ...
                cells, centroids, norms, neighs, neighnum, unit_scale, shifts, pts, scales, min_edge_edge)
            %PROJECT_VIEWS Fallback: a MATLAB transcription of RHYTHM's
            %dataProjection02 at native view resolution, calling the
            %vendored primitives (see the class header for how it
            %differs from calling dataProjection02 itself). Returns:
            %   dataProj nFaces x 1 activation values (ms; 0 = unassigned
            %            or no valid source data - dataProjection02 rule)
            %   viewi    nFaces x (nViews+1): columns k = DIRECT-membership
            %            of view k; last column = assigned view (1..4,
            %            nViews+1 = OVERLAP, nViews+2 = EDGE)
            %   mask     nFaces x 1 assigned-at-least-once logical
            %   pts      the mesh VERTEX points (mm) - the pixel kernels
            %            are built from the projected triangle VERTICES
            %            (dataProjection02 lines 245-259), exactly as
            %            upstream
            %   scales   optional nViews x 2 [sv sh] per-view scale: the
            %            OM map is the camera-frame window scaled down by
            %            1/sv (rows) and 1/sh (columns), so projected
            %            coordinates are divided by the scale after the
            %            shift. Default ones.
            %   min_edge_edge  optional minimum edge weight of an EDGE face
            %            (dataProjection02 minedgeEDGE; default 0.55)
            %   ledge    nFaces x nViews edge weights (the OVERLAP/EDGE
            %            weights) and txtkernel nFaces x nViews x 2 pixel
            %            kernels, for the CV direction (cv_face_directions)
            if nargin < 13 || isempty(min_edge_edge)
                min_edge_edge = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            end
            nviews = numel(views);
            if nviews < 1
                error('analyse_om:Reprojection:NoViews', 'No per-view maps.');
            end
            shifts_ = zeros(nviews, 2);
            if ~isempty(shifts)
                if isequal(size(shifts), [4 2]) || isequal(size(shifts), [nviews 2])
                    shifts_ = double(shifts);
                else
                    error('analyse_om:Reprojection:BadShifts', ...
                        'Shifts must be nViews x 2 [dx dy].');
                end
            end
            scales_ = ones(nviews, 2);
            if nargin >= 12 && ~isempty(scales)
                if isequal(size(scales), [4 2]) || isequal(size(scales), [nviews 2])
                    scales_ = double(scales);
                else
                    error('analyse_om:Reprojection:BadScales', ...
                        'Scales must be nViews x 2 [sv sh].');
                end
            end

            % ---- per-view camera parameters (COLMAP -> RHYTHM) ----
            par = zeros(8, nviews);
            pos = zeros(6, nviews);
            lookn = zeros(nviews, 3);
            for i = 1:nviews
                vc = view_cam{i};
                cm = [];
                for c = 1:numel(cam)
                    if cam(c).id == vc.camera_id, cm = cam(c); break; end
                end
                if isempty(cm)
                    error('analyse_om:Reprojection:CameraMissing', ...
                        'Camera %d for image ''%s'' not in cameras file.', ...
                        vc.camera_id, vc.name);
                end
                [par(:, i), pos(:, i), lookn(i, :)] = ...
                    rabbit_rhythm_reproject.colmap_to_rhythm( ...
                    cm, vc.qvec, vc.tvec, unit_scale);
            end

            % ---- project face centroids into every view ----
            nF = size(centroids, 1);
            % dataProjection02: langle = acos(norms * lookn') in degrees
            langle = zeros(nF, nviews);
            for i = 1:nviews
                g = norms * lookn(i, :)';
                g = max(-1, min(1, g));
                langle(:, i) = acos(g) * 180 / pi;
            end

            % ---- per-view projected centroid positions ----
            Xall = zeros(nF, nviews);
            Yall = zeros(nF, nviews);
            for i = 1:nviews
                [Xall(:, i), Yall(:, i)] = rabbit_rhythm_reproject.rhythm_pred( ...
                    centroids, par(:, i), pos(:, i), shifts_(i, :), scales_(i, :));
            end

            % ---- per-view masks (valid data + in-bounds projection) ----
            masks = cell(nviews, 1);
            for i = 1:nviews
                v = views{i};
                [nr, nc] = size(v);
                geom = zeros(nr, nc);
                x = round(Xall(:, i)); y = round(Yall(:, i));
                ok = x >= 1 & x <= nc & y >= 1 & y <= nr;
                ix = sub2ind([nr nc], y(ok), x(ok));
                geom(unique(ix)) = 1;
                geom = imfill(geom, 'holes');
                masks{i} = (~isnan(v)) .* geom; % bgMask = valid data
            end

            % ---- edge weights (dataProjection02 lines 117-158) ----
            ledge = zeros(nF, nviews);
            for i = 1:nviews
                gg = find(langle(:, i) > 90); % front face
                [Xigg, Yigg] = rabbit_rhythm_reproject.rhythm_pred( ...
                    centroids(gg, :), par(:, i), pos(:, i), shifts_(i, :), scales_(i, :));
                out = Xigg < 1 | Xigg > size(views{i}, 2) | ...
                    Yigg < 1 | Yigg > size(views{i}, 1);
                Xigg(out) = []; Yigg(out) = []; gg(out) = [];
                if isempty(gg), continue; end
                conesilh = conefilt(masks{i}, rabbit_rhythm_reproject.EDGE_FILT_VAL, 1);
                ledge(gg, i) = interp2(conesilh, Xigg, Yigg);
            end
            ledge(isnan(ledge)) = 0;

            % ---- per-face DIRECT assignment basis (lines 160-216) ----
            viewi = zeros(nF, nviews + 1);
            for i = 1:nviews
                gg = find(langle(:, i) >= rabbit_rhythm_reproject.MIN_ANGLE_DIRECT ...
                    & ledge(:, i) >= rabbit_rhythm_reproject.MIN_EDGE_DIRECT);
                if ~isempty(gg)
                    viewi(gg, i) = 1;
                    s = smoothregionbdr(viewi(:, i), neighnum, neighs);
                    viewi(:, i) = s;
                end
            end
            for i = 1:nF
                g = find(viewi(i, 1:nviews));
                if ~isempty(g)
                    if isscalar(g)
                        viewi(i, nviews + 1) = g;
                    else
                        viewi(i, nviews + 1) = nviews + 1; % OVERLAP
                    end
                else
                    g = find(langle(i, 1:nviews) >= 90 & ...
                        ledge(i, 1:nviews) >= min_edge_edge);
                    if ~isempty(g)
                        viewi(i, nviews + 1) = nviews + 2; % EDGE
                        viewi(i, g) = 1;
                    end
                end
            end

            % ---- pixel kernels (lines 224-315) ----
            txtkernel = cell(nF, nviews, 2);
            for i = 1:nviews
                [nr, nc] = size(views{i});
                gg = find(viewi(:, i));
                if isempty(gg), continue; end
                [Xc, Yc] = rabbit_rhythm_reproject.rhythm_pred( ...
                    centroids(gg, :), par(:, i), pos(:, i), shifts_(i, :), scales_(i, :));
                out = Xc < 1 | Xc > nc | Yc < 1 | Yc > nr;
                gg(out) = [];   % keep only faces whose centroid is in-view
                if isempty(gg), continue; end
                V1 = pts(cells(gg, 1), :);
                V2 = pts(cells(gg, 2), :);
                V3 = pts(cells(gg, 3), :);
                [XV1, YV1] = rabbit_rhythm_reproject.rhythm_pred( ...
                    V1, par(:, i), pos(:, i), shifts_(i, :), scales_(i, :));
                [XV2, YV2] = rabbit_rhythm_reproject.rhythm_pred( ...
                    V2, par(:, i), pos(:, i), shifts_(i, :), scales_(i, :));
                [XV3, YV3] = rabbit_rhythm_reproject.rhythm_pred( ...
                    V3, par(:, i), pos(:, i), shifts_(i, :), scales_(i, :));
                for j = 1:numel(gg)
                    VXmax = ceil(max([XV1(j) XV2(j) XV3(j)]) - 0.5) + 0.5;
                    VXmin = floor(min([XV1(j) XV2(j) XV3(j)]) + 0.5) - 0.5;
                    VYmax = ceil(max([YV1(j) YV2(j) YV3(j)]) - 0.5) + 0.5;
                    VYmin = floor(min([YV1(j) YV2(j) YV3(j)]) + 0.5) - 0.5;
                    VXmax = min(VXmax, nc + 0.5);
                    VXmin = max(VXmin, 0.5);
                    VYmax = min(VYmax, nr + 0.5);
                    VYmin = max(VYmin, 0.5);
                    [pvX, pvY] = meshgrid(VXmin:1:VXmax, VYmin:1:VYmax);
                    intarea = zeros(size(pvX, 1) - 1, size(pvX, 2) - 1);
                    Q = [XV1(j), YV1(j); XV2(j), YV2(j); XV3(j), YV3(j)];
                    try
                        Q = checkpoly(Q * 100) / 100;
                    catch
                        % collinear triangle - the kernel stays empty
                    end
                    if isempty(Q), continue; end
                    for pn = 1:size(pvX, 1) - 1
                        for pm = 1:size(pvY, 2) - 1
                            P = [pvX(pn, pm + 1) pvY(pn, pm + 1);
                                pvX(pn + 1, pm + 1) pvY(pn + 1, pm + 1);
                                pvX(pn + 1, pm) pvY(pn + 1, pm);
                                pvX(pn, pm) pvY(pn, pm)];
                            % Degenerate-geometry guard: with a dense mesh
                            % a tiny projected triangle can share only
                            % collinear points with a pixel square and the
                            % vendored convex_intersect's internal convhull
                            % throws 'points may be collinear'. This is the
                            % same degenerate class upstream swallows with
                            % its checkpoly try/catch (dataProjection02
                            % lines 286-290); zero area is the correct
                            % contribution. The vendored file is not
                            % modified.
                            try
                                [~, ~, intarea(pn, pm)] = convex_intersect(P, Q);
                            catch
                                intarea(pn, pm) = 0;
                            end
                        end
                    end
                    txtkernel{gg(j), i, 1} = sub2ind([nr nc], ...
                        pvY(1:end - 1, 1:end - 1) + 0.5, ...
                        pvX(1:end - 1, 1:end - 1) + 0.5);
                    txtkernel{gg(j), i, 2} = intarea;
                end
            end

            % ---- assign data (lines 344-433) ----
            dataProj = zeros(nF, 1);
            for i = 1:nF
                v = viewi(i, nviews + 1);
                if v == 0
                    dataProj(i) = 0; % unassigned (dataProjection02 NaN->0)
                    continue;
                end
                if v <= nviews % DIRECT
                    [val, ok] = rabbit_rhythm_reproject.kernel_mean( ...
                        views{v}, txtkernel(i, v, :));
                    if ~ok, val = 0; end
                    dataProj(i) = val;
                else % OVERLAP or EDGE
                    g = find(viewi(i, 1:nviews));
                    num = 0; den = 0; valid = false;
                    for gg_ = g
                        [val, ok] = rabbit_rhythm_reproject.kernel_mean( ...
                            views{gg_}, txtkernel(i, gg_, :));
                        if ok
                            w = ledge(i, gg_);
                            num = num + val * w;
                            den = den + w;
                            valid = true;
                        end
                    end
                    if valid && den > 0
                        dataProj(i) = num / den;
                    else
                        dataProj(i) = 0;
                    end
                end
            end
            % ---- final rule (dataProjection02 lines 409-417): every
            % NaN-valued face is forced to 0 before saving - the
            % unassigned and the missing-source-data faces are both 0 ----
            dataProj(isnan(dataProj)) = 0;
            mask = viewi(:, nviews + 1) ~= 0;
        end

        function [val, ok] = kernel_mean(v, kernel_cell)
            %KERNEL_MEAN Area-weighted mean of the activation map over
            %the face's pixel kernel (dataProjection02 lines 366-367).
            %Returns ok=false when the kernel is empty or all weights
            %are zero. NaN pixels inside the kernel are ignored
            %(missing-data policy; a kernel with no valid pixels fails).
            idx = kernel_cell{1};
            wt = kernel_cell{2};
            ok = ~isempty(idx) && sum(wt(:)) > 0;
            if ~ok
                val = NaN;
                return;
            end
            pix = v(idx);
            w = wt;
            valid = ~isnan(pix);
            if ~any(valid)
                val = NaN; % no valid source data under this face
                return;
            end
            val = sum(pix(valid) .* w(valid)) / sum(w(valid));
        end

        function [Xi, Yi] = rhythm_pred(xyz, par, pos, shift, scale)
            %RHYTHM_PRED Vendored pred.m + imdist.m with the adapter's
            %COLMAP-derived parameters, plus the pixel shift [dx dy] and
            %the scale [sv sh]. The OM map is the camera-frame window
            %scaled down, so the shifted coordinates are divided by the
            %horizontal scale (columns, X) and the vertical scale (rows,
            %Y) to land in the OM map's pixel grid. The scaling is about
            %pixel edges, (X - 0.5)/s + 0.5, so pixel centres line up at
            %any scale.
            [Xi, Yi] = pred(xyz, par, pos, rabbit_rhythm_reproject.RHYTHM_CAMERA);
            if nargin >= 4 && ~isempty(shift)
                Xi = Xi + shift(1);
                Yi = Yi + shift(2);
            end
            if nargin >= 5 && ~isempty(scale)
                Xi = (Xi - 0.5) ./ scale(2) + 0.5;
                Yi = (Yi - 0.5) ./ scale(1) + 0.5;
            end
        end

        function [par, pos, lookn] = colmap_to_rhythm(cm, qvec, tvec, unit_scale)
            %COLMAP_TO_RHYTHM Convert one COLMAP camera/image record to
            %the RHYTHM parametrisation (par 8x1, pos 6x1, lookn 1x3).
            %   COLMAP intrinsic layouts (model-specific):
            %     SIMPLE_PINHOLE   [f, cx, cy]
            %     PINHOLE          [fx, fy, cx, cy]
            %     SIMPLE_RADIAL    [f, cx, cy, k]
            %     RADIAL           [f, cx, cy, k1, k2]
            %     OPENCV           [fx, fy, cx, cy, k1, k2, p1, p2]
            %     FULL_OPENCV      [fx, fy, cx, cy, k1, k2, p1, p2, k3..k6]
            %   RHYTHM par = [Asp, f_mm, Cpx, Cpy, Rad1, Rad2, Tan1, Tan2]
            %   with f_mm = fx * PIXEL_PITCH_MM and Cpx/Cpy = the COLMAP
            %   principal point in pixels plus 0.5 (pred adds Cpx to the
            %   pixel-scaled projection). COLMAP pixel coordinates are
            %   0-based with pixel k centred at k + 0.5; RHYTHM and MATLAB
            %   index pixel j centred at j, so u_matlab = u_colmap + 0.5.
            %   Pinhole models then reproduce the COLMAP projection exactly
            %   when fx == fy.
            p = cm.params;
            k = numel(p);
            f = p(1);
            model = cm.model;
            switch model
                case 'SIMPLE_PINHOLE'
                    cx = p(2); cy = p(3);
                    par = [1, f * rabbit_rhythm_reproject.PIXEL_PITCH_MM, ...
                        cx + 0.5, cy + 0.5, 0, 0, 0, 0];
                case 'PINHOLE'
                    cx = p(3); cy = p(4);
                    if abs(p(2) - f) / f > 1e-6
                        warning('analyse_om:Reprojection:AnisotropicPixel', ...
                            'PINHOLE camera has fx~=fy (%.4f vs %.4f); RHYTHM pred uses fx.', ...
                            f, p(2));
                    end
                    par = [1, f * rabbit_rhythm_reproject.PIXEL_PITCH_MM, ...
                        cx + 0.5, cy + 0.5, 0, 0, 0, 0];
                otherwise
                    % SIMPLE_RADIAL / RADIAL / OPENCV / FULL_OPENCV:
                    % Heikkila-model approximation - Rad1=k1, Rad2=k2,
                    % Tan1=p1, Tan2=p2 map onto imdist.m's model (exact
                    % when all coefficients are 0; the Heikkila radial
                    % polynomial Q-denominator differs from COLMAP's
                    % plain polynomial for non-zero coefficients - a
                    % documented approximation, identical to RHYTHM's
                    % own model).
                    if strcmp(model, 'SIMPLE_RADIAL')
                        cx = p(2); cy = p(3);
                        k1 = p(4); k2 = 0; p1 = 0; p2 = 0;
                    elseif strcmp(model, 'RADIAL')
                        cx = p(2); cy = p(3);
                        k1 = p(4); k2 = p(5); p1 = 0; p2 = 0;
                    else % OPENCV / FULL_OPENCV
                        cx = p(3); cy = p(4);
                        if abs(p(2) - f) / f > 1e-6
                            warning('analyse_om:Reprojection:AnisotropicPixel', ...
                                '%s camera has fx~=fy (%.4f vs %.4f); RHYTHM pred uses fx.', ...
                                model, f, p(2));
                        end
                        k1 = p(5); k2 = p(6);
                        if k >= 8, p1 = p(7); p2 = p(8); else, p1 = 0; p2 = 0; end
                    end
                    par = [1, f * rabbit_rhythm_reproject.PIXEL_PITCH_MM, ...
                        cx + 0.5, cy + 0.5, k1, k2, p1, p2];
            end
            % rotation: COLMAP qvec (qw qx qy qz) -> R (world->camera).
            % The vendored pred.m assembles (verify column-by-column
            % against Rz(kappa)Ry(psi)Rx(omega)) a matrix whose columns
            % are the ROWS of RzRyRx - i.e. Rc = (RzRyRx)' - and computes
            % pc = X*Rc + t, so the effective world->camera rotation is
            % Rc' = Rz(kappa)Ry(psi)Rx(omega). For the COLMAP convention
            % pc = R*X + t we therefore need RzRyRx == R and recover the
            % Euler angles from R directly:
            %   R(3,1) = -sin(psi)     -> psi
            %   R(2,1)/R(1,1) = tan(k) -> kappa
            %   R(3,2)/R(3,3) = tan(w) -> omega
            qw = qvec(1); qx = qvec(2); qy = qvec(3); qz = qvec(4);
            R = [1 - 2 * (qy^2 + qz^2), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw);
                2 * (qx * qy + qz * qw), 1 - 2 * (qx^2 + qz^2), 2 * (qy * qz - qx * qw);
                2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx^2 + qy^2)];
            cp = sqrt(R(1,1)^2 + R(2,1)^2);
            if cp > 1e-10
                psi = asin(max(-1, min(1, -R(3,1))));
                kappa = atan2(R(2,1), R(1,1));
                omega = atan2(R(3,2), R(3,3));
            else
                % gimbal lock: |R(3,1)| = 1 -> psi = +/-90 deg, kappa free
                sgn = -R(3,1); % +1 -> psi = +90 deg
                psi = sgn * pi / 2;
                kappa = 0;
                if sgn > 0   % R = Rz(0)*Ry(90)*Rx(w): R(1,2)=sin(w), R(1,3)=cos(w)
                    omega = atan2(R(1,2), R(1,3));
                else         % R = Rz(0)*Ry(-90)*Rx(w): R(1,2)=-sin(w), R(1,3)=-cos(w)
                    omega = atan2(-R(1,2), -R(1,3));
                end
            end
            t = tvec(:) * unit_scale; % -> mm
            pos = [t; omega * 180 / pi; psi * 180 / pi; kappa * 180 / pi];
            % camera view direction in world = R' * [0;0;1]
            look = R' * [0; 0; 1];
            lookn = look(:)' / norm(look);
        end

        % =============================================================
        % 7. Exports
        % =============================================================

        function cdf_path = write_cdf(path, dataProj, varargin)
            %WRITE_CDF RHYTHM-format texture .cdf (dataProjection02
            %header layout, exactly 8 header lines): header_lines=8,
            %nchannels, delta-t, n_samples, word_size=4, event, date,
            %data_source, then float32 data. A static activation map is
            %written as a single sample (n_samples = 1). The mesh path
            %is recorded in the manifest only (extra header lines would
            %shift the vendored reader's data offset).
            source = 'om-activation';
            if numel(varargin) >= 1 && ~isempty(varargin{1})
                source = varargin{1};
            end
            fid = fopen(path, 'wb');
            if fid < 0
                error('analyse_om:Reprojection:CannotWrite', 'Cannot write %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid, 'header_lines=8\n');
            fprintf(fid, 'nchannels=%d\n', numel(dataProj));
            fprintf(fid, 'delta-t=1.000000\n');
            fprintf(fid, 'n_samples=%d\n', 1);
            fprintf(fid, 'word_size=4\n');
            fprintf(fid, 'event=0\n');
            fprintf(fid, 'date=%s\n', datestr(now, 'yyyy-mm-dd'));
            fprintf(fid, 'data_source=%s\n', source);
            fwrite(fid, single(dataProj(:)), 'float32');
            cdf_path = path;
        end

        function cls = face_confidence(viewi, mask, low)
            %% Confidence class of each face from RHYTHM's viewi
            % viewi: nFaces x (nViews+1), last column 1..nViews = DIRECT
            % view, nViews+1 = OVERLAP, nViews+2 = EDGE; mask: assigned
            % faces; low: EDGE faces of low confidence. Classes as
            % CLASS_NAMES: 1 DIRECT, 2 OVERLAP, 3 EDGE, 4 low confidence,
            % 5 unassigned (also a face with a view but no value).
            n = numel(mask);
            cls = repmat(uint8(5), n, 1);
            if isempty(viewi) || size(viewi, 1) ~= n
                return;
            end
            nv = size(viewi, 2) - 1;
            last = viewi(:, end);
            got = logical(mask(:));
            cls(got & last >= 1 & last <= nv) = 1;
            cls(got & last == nv + 1) = 2;
            cls(got & last == nv + 2) = 3;
            cls(got & last == nv + 2 & logical(low(:))) = 4;
        end

        function rec = confidence_record(cls, min_edge_edge)
            %% The manifest's record of the confidence classes
            defs = { ...
                'seen directly by one view (RHYTHM DIRECT: angle >= 95 deg, edge weight >= 0.9)', ...
                'seen by several views and averaged (RHYTHM OVERLAP)', ...
                sprintf('no view sees it directly; an edge view with edge weight >= %.2f (RHYTHM EDGE)', ...
                    rabbit_rhythm_reproject.MIN_EDGE_EDGE), ...
                sprintf(['low confidence: an EDGE face assigned only because the edge threshold was ' ...
                    'lowered below %.2f (edge weight below %.2f). Another projector may also put here ' ...
                    'faces seen by only one view past its angle limit.'], ...
                    rabbit_rhythm_reproject.MIN_EDGE_EDGE, rabbit_rhythm_reproject.MIN_EDGE_EDGE), ...
                'unassigned (no view, or no value)'};
            classes = struct('value', num2cell(1:5), 'name', rabbit_rhythm_reproject.CLASS_NAMES, ...
                'definition', defs);
            counts = arrayfun(@(k) nnz(cls == k), 1:5);
            rec = struct('classes', classes, 'counts', counts, 'min_edge_edge', min_edge_edge, ...
                'file', '', ...
                'note', ['These classes are separate from the projected values: in dataProj and the ' ...
                    '.cdf, 0 still means unassigned (RHYTHM''s convention). The OM video uses the ' ...
                    'activation map''s faces and classes.']);
        end

        function ply_path = write_projected_ply(path, mesh, dataProj, mask, prop)
            %WRITE_PROJECTED_PLY PLY copy of the input mesh with the
            %projected activation values attached as per-vertex
            %'activation' floats: the mean of the ASSIGNED faces around
            %each vertex. A vertex with no assigned face gets NaN (no
            %value), so unassigned faces are never averaged in as 0.
            %   mask  assigned faces (default: finite, non-zero dataProj,
            %         the convention of dataProj where 0 = unassigned)
            if nargin < 4 || isempty(mask)
                mask = isfinite(dataProj) & dataProj ~= 0;
            end
            % prop: the vertex property's name (default 'activation';
            % 'cv_speed' for the conduction velocity)
            if nargin < 5 || isempty(prop)
                prop = 'activation';
            end
            F = size(mesh.faces, 1);
            nV = size(mesh.pts, 1);
            assigned = logical(mask(:)) & isfinite(dataProj(:));
            % Vertex x face incidence of the assigned faces only
            fa = find(assigned);
            inc = sparse(reshape(mesh.faces(fa, :), [], 1), repmat(fa, 3, 1), 1, nV, F);
            vals = zeros(F, 1);
            vals(fa) = dataProj(fa);
            cnt = full(sum(inc, 2));
            vint = full(inc * vals) ./ cnt;
            vint(cnt == 0) = NaN;
            fid = fopen(path, 'wt');
            if fid < 0
                error('analyse_om:Reprojection:CannotWrite', 'Cannot write %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid, 'ply\nformat ascii 1.0\n');
            fprintf(fid, 'element vertex %d\n', size(mesh.pts, 1));
            fprintf(fid, 'property float x\nproperty float y\nproperty float z\n');
            fprintf(fid, 'property float %s\n', prop);
            fprintf(fid, 'element face %d\n', F);
            fprintf(fid, 'property list uchar int vertex_indices\n');
            fprintf(fid, 'end_header\n');
            fprintf(fid, '%.6f %.6f %.6f %.4f\n', ...
                [mesh.pts, vint]');
            fprintf(fid, '3 %d %d %d\n', ...
                (mesh.faces - 1)');
            ply_path = path;
        end

        function mat_path = write_video_mat(path, mesh, series, mask, fps, method)
            %% Save the projected OM video for the mesh viewer
            % face_series    nFaces x T single (NaN = unassigned)
            % vertex_series  nVertices x T single: mean of the assigned
            %                faces around each vertex (NaN if none)
            % faces (1-based), vertices (mesh units), assigned, fps, method
            nV = size(mesh.pts, 1);
            nF = size(mesh.faces, 1);
            inc = sparse(mesh.faces(:), repmat((1:nF)', 3, 1), 1, nV, nF);
            s0 = series;
            s0(~mask, :) = 0;
            s0(~isfinite(s0)) = 0;
            cnt = inc * double(mask(:));
            vertex_series = single(full(inc * s0) ./ cnt);
            vertex_series(cnt == 0, :) = NaN;
            face_series = single(series);
            faces = mesh.faces;
            vertices = mesh.pts;
            assigned = logical(mask(:));
            time_s = (0:size(series, 2) - 1) / fps;
            if numel(face_series) + numel(vertex_series) > 3e8
                save(path, 'face_series', 'vertex_series', 'faces', 'vertices', ...
                    'assigned', 'fps', 'time_s', 'method', '-v7.3');
            else
                save(path, 'face_series', 'vertex_series', 'faces', 'vertices', ...
                    'assigned', 'fps', 'time_s', 'method');
            end
            mat_path = path;
        end

        function write_manifest(path, result)
            %WRITE_MANIFEST JSON record of the reprojection run (inputs,
            %settings, stats, outputs, citations). Written with
            %jsonencode (R2016b+).
            m = struct();
            m.schema = 'rabbit_rhythm_reproject.manifest.v1';
            if isfield(result, 'quantity') && strcmp(result.quantity, 'cv_speed')
                % Written only for the conduction velocity; the
                % activation record has none of these fields
                m.quantity = 'conduction velocity speed';
                m.units = 'm/s (mm/ms)';
                m.note = ['The speed of the Conduction Velocity tab (CV_map(:,:,3)) as measured in each OM ' ...
                    'view''s image plane, not corrected for the tilt of the surface; the direction is not ' ...
                    'projected (the in-plane vectors of four views do not make one surface direction).'];
                if isfield(result, 'cv_direction')
                    m.note = ['The speed of the Conduction Velocity tab (CV_map(:,:,3)) as measured in each OM ' ...
                        'view''s image plane, not corrected for the tilt of the surface. The direction ' ...
                        '(CV_map(:,:,1:2)) is lifted from each view''s image plane onto the surface ' ...
                        '(approximate; see cv_direction).'];
                end
            end
            m.created_by = 'analyse_optical_mapping (RHYTHM reprojection)';
            m.created = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            m.views = rabbit_rhythm_reproject.VIEW_ORDER;
            m.view_cameras = result.view_names_used; % 4 strings (the
            % view<->camera assignment in ROI order); not wrapped in an
            % extra cell - jsonencode of {cell} would emit a 1-element
            % array
            % The camera image of each ROI row, and
            % the one convention both the frame check and the default
            % choice use
            m.view_camera_per_roi_row = rabbit_rhythm_reproject.camera_per_roi_row(result.view_names_used);
            m.rotation = result.rotation;
            m.colmap_dir = result.stats.colmapDir;
            m.mesh_file = result.stats.meshFile;
            m.n_faces = result.stats.nFaces;
            m.n_assigned = result.stats.nAssigned;
            % Coverage: faces with a projected value, in total and per view
            % (ROI order); 0 in the .cdf/.ply means no value, not 0 ms
            m.coverage = struct('n_faces', result.stats.nFaces, ...
                'n_assigned', result.stats.nAssigned, ...
                'n_assigned_per_view', result.stats.nAssignedPerView, ...
                'n_direct_overlap_edge', result.stats.nDirectOverlapEdge, ...
                'fraction', result.stats.nAssigned / max(1, result.stats.nFaces));
            if isfield(result, 'flip_rows')
                m.flip_rows = result.flip_rows; % per view, ROI order
            end
            m.n_views = result.stats.nViews;
            m.unassigned_value = 0; % dataProjection02 NaN->0 rule
            % Projection method; for RHYTHM, the 100x100 binning per view.
            if isfield(result, 'method')
                m.method = result.method;
                m.method_note = result.method_note;
            end
            if isfield(result, 'rhythm')
                fn = 'dataProjection02 (vendored, unmodified)';
                if isfield(result.rhythm, 'edge_copy') && result.rhythm.edge_copy
                    fn = sprintf(['dataProjection02 (vendored; run from a copy whose only change is ' ...
                        'minedgeEDGE = %.2f instead of %.2f)'], result.min_edge_edge, ...
                        rabbit_rhythm_reproject.MIN_EDGE_EDGE);
                end
                m.rhythm = struct('function', fn, ...
                    'grid', [rabbit_rhythm_reproject.RHYTHM_GRID rabbit_rhythm_reproject.RHYTHM_GRID], ...
                    'camera', result.rhythm.camera, ...
                    'binning', 'exact area average, NaN pixels excluded', ...
                    'source_sizes', reshape([result.rhythm.bins.source_size], 2, [])', ...
                    'surface_points', result.rhythm.n_points, ...
                    'points_in_view', result.rhythm.coverage);
            end
            if isfield(result, 'min_edge_edge')
                % RHYTHM's two edge thresholds; EDGE is a setting
                m.edge_thresholds = struct('min_edge_direct', rabbit_rhythm_reproject.MIN_EDGE_DIRECT, ...
                    'min_edge_edge', result.min_edge_edge, ...
                    'rhythm_min_edge_edge', rabbit_rhythm_reproject.MIN_EDGE_EDGE);
                m.deviations = result.deviations;
            end
            if isfield(result, 'video_path')
                m.video = result.video_path;
                m.n_frames = result.stats.nFrames;
                m.fps = result.fps;
            end
            % The maps and the cameras share the undistorted-workspace
            % image frame (checked in run); a vertical OM crop of that
            % frame is applied as per-view pixel shifts.
            m.camera_frame = 'undistorted-workspace';
            m.original_to_undistorted = 'identity for the undistorted workspace';
            if isfield(result, 'shifts') && ~isempty(result.shifts)
                m.shifts = result.shifts; % 4x2 [dx dy] per view (ROI order)
            end
            if isfield(result, 'fov_mapping') && ~isempty(result.fov_mapping)
                m.fov_mapping = result.fov_mapping;
            end
            if isfield(result, 'view_flips')
                m.view_flips = result.view_flips; % per view, ROI order
            end
            if isfield(result, 'frame_check') && ~isempty(result.frame_check)
                m.frame_check = result.frame_check; % pose frame and its checks
            end
            m.citations = { ...
                'Gloschat C et al. Sci Rep 2018;8:2921 (PMID 29440763)', ...
                'Laughner JI et al. Am J Physiol Heart Circ Physiol 2012;303(7):H753-65 (PMID 22821993)'};
            if isfield(result, 'confidence') && ~isempty(result.confidence)
                m.confidence_classes = result.confidence;
            end
            if isfield(result, 'cv_direction')
                m.cv_direction = result.cv_direction; % method and approximations
            end
            % Each view's directly seen faces
            % against its 2-D map (activation only; display only)
            if isfield(result, 'activation_consistency') && isstruct(result.activation_consistency)
                m.activation_consistency = result.activation_consistency;
            end
            if isfield(result, 'display_limits')
                % The colour ranges of the app, for Visualise (the CV
                % manifest keeps the CV one)
                if isfield(result, 'quantity') && strcmp(result.quantity, 'cv_speed')
                    m.display_limits = struct('cv', result.display_limits.cv);
                    if isfield(result.display_limits, 'cv_auto')
                        m.display_limits.cv_auto = result.display_limits.cv_auto;
                    end
                else
                    m.display_limits = result.display_limits;
                end
            end
            % Each view's activation spread of the map the CV step used
            % (the near-simultaneous warning reads it)
            if isfield(result, 'cv_activation_spread') && isstruct(result.cv_activation_spread)
                a = result.cv_activation_spread;
                % each view's limit as the check made it
                lim = rabbit_reconstruction_tab.SIMULTANEOUS_IQR_MS;
                if isfield(a, 'warn_below_ms') && ~isempty(a.warn_below_ms), lim = double(a.warn_below_ms(:)'); end
                basis = 'IQR (25-75 %) of the activation times of each view of the map the CV step used';
                if isfield(a, 'basis') && ~isempty(a.basis), basis = char(a.basis); end
                m.activation_spread = struct('views', {cellstr(a.views)}, 'iqr_ms', double(a.iqr_ms(:)'), ...
                    'warn_below_ms', lim, 'basis', basis);
            end
            % The CV map's settings (cv_smoothing_3x3, cv_time_max_ms,
            % cv_distance_max_mm), when given; otherwise the record has no
            % such fields
            if isfield(result, 'cv_settings') && isstruct(result.cv_settings)
                for f = fieldnames(result.cv_settings)'
                    m.(f{1}) = result.cv_settings.(f{1});
                end
            end
            % The pacing cycle given for this projection (Step 2), if any
            if isfield(result, 'pacing_cycle_ms') && ~isempty(result.pacing_cycle_ms)
                m.pacing_cycle_ms = result.pacing_cycle_ms;
            end
            % The recording's rhythm marker (File > Recording rhythm), if given
            if isfield(result, 'recording_rhythm') && isstruct(result.recording_rhythm)
                m.recording_rhythm = result.recording_rhythm;
            end
            % The activation map's method and zero (rabbit_activation_zero);
            % null when the app did not record them
            if isfield(result, 'activation_zero')
                m.activation_zero = result.activation_zero;
            end
            % The faces left out at the CV map's activation cut (only when a
            % cut was asked for)
            if isfield(result, 'cv_activation_cut') && isstruct(result.cv_activation_cut)
                m.activation_cut = result.cv_activation_cut;
            end
            % The steep faces whose surface speed was left out, under
            % surface_speed
            if isfield(result, 'cv_direction') && isfield(result.cv_direction, 'surface_speed')
                ss = result.cv_direction.surface_speed;
                m.surface_speed = struct('steep_faces_left_out', ss.steep_faces_left_out, ...
                    'correction_cap', ss.correction_cap, 'basis', sprintf(['faces whose tilt correction ' ...
                    '(surface / image-plane speed) is above %sx'], num2str(ss.correction_cap)), ...
                    'text', ss.steep_text);
            end
            % The mesh outside the OM outline per
            % view, from the frame check (activation and CV records alike)
            if isfield(result, 'frame_check') && isstruct(result.frame_check) && ...
                    isfield(result.frame_check, 'mesh_outside_om') && numel(result.frame_check.mesh_outside_om) == 4
                fo = rabbit_rhythm_reproject.mesh_outside_by_view(result.frame_check);
                m.mesh_outside_om = struct('views', {{'View1', 'View2', 'View3', 'View4'}}, 'fraction', fo, ...
                    'warn', fo > rabbit_rhythm_reproject.MESH_OUTSIDE_WARN, ...
                    'basis', 'share of the projected mesh silhouette outside the OM tissue outline', ...
                    'text', rabbit_rhythm_reproject.mesh_outside_text(fo));
            end
            % A view where two or more of the
            % per-view checks fire, as one record with ready text
            g = rabbit_rhythm_reproject.view_geometry_suspect(result);
            if isstruct(g), m.view_geometry_suspect = g; end
            if isfield(result, 'cdf_path'), m.cdf = result.cdf_path; end
            if isfield(result, 'ply_path'), m.ply = result.ply_path; end
            fid = fopen(path, 'wt', 'n', 'UTF-8');
            if fid < 0
                error('analyse_om:Reprojection:CannotWrite', 'Cannot write %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', jsonencode(m));
        end
    end

    methods (Static, Access = private)
        % (helpers that should not be called from the GUI)

        function ensure_rhythm_path()
            %ENSURE_RHYTHM_PATH Idempotently add the vendored RHYTHM
            %directories (third_party/RHYTHM/Source Code/MATLAB/...,
            %relative to this adapter's own location) to the MATLAB path
            %so the projection primitives are always resolvable without
            %user configuration. Guarded by an exist() check on the
            %entry function (pred), not by persistent state, so path
            %manipulation by the caller is always re-detected.
            if exist('pred', 'file') == 2 && exist('conefilt', 'file') == 2
                return;
            end
            self = fileparts(mfilename('fullpath'));
            common = fullfile(self, 'third_party', 'RHYTHM', ...
                'Source Code', 'MATLAB', 'Common_files');
            orient = fullfile(self, 'third_party', 'RHYTHM', ...
                'Source Code', 'MATLAB', 'ORIENT_files');
            if ~isfolder(common) || ~isfolder(orient)
                error('analyse_om:Reprojection:VendorMissing', ...
                    ['Vendored RHYTHM sources not found under %s. ' ...
                    'Restore the third_party/RHYTHM folder from the repository.'], ...
                    fullfile(self, 'third_party', 'RHYTHM'));
            end
            addpath(common, orient, '-begin');
        end

        function n = ply_scalar_size(type)
            %PLY_SCALAR_SIZE Byte width of a PLY scalar type; 0/-1 for
            %types we cannot skip (lists, doubles handled separately).
            switch lower(type)
                case {'char', 'int8'}, n = 1;
                case {'uchar', 'uint8'}, n = 1;
                case {'short', 'int16'}, n = 2;
                case {'ushort', 'uint16'}, n = 2;
                case {'int', 'int32'}, n = 4;
                case {'uint', 'uint32'}, n = 4;
                case {'float', 'float32'}, n = 4;
                case {'double', 'float64'}, n = 8;
                otherwise, n = -1; % list or unknown
            end
        end
    end
end
