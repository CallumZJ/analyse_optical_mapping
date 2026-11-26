classdef rabbit_mesh_alignment
    %% Check that the cleaned mesh lines up with the COLMAP sparse model
    % Collin Snitchler
    % 09.09.2026
    % Sources: COLMAP (Schoenberger and Frahm 2016); silhouette test after
    %          the visual hull (Laurentini 1994, IEEE PAMI 16(2):150-162).
    % Measures the alignment gates A1-A6 between the mesh from
    % rabbit_mesh_cleanup and the COLMAP sparse model and tissue masks. It
    % only checks: nothing is moved, and ICP is not used.
    %
    % Method (each check gives PASS, WARN or FAIL; WARN keeps the run
    % going with the values in the step's warnings, FAIL stops it):
    %   A1 (projection check): project mesh vertices through the COLMAP
    %       camera model (the cameras of the undistorted frames, as used
    %       by rabbit_rhythm_reproject) and compare against the sparse
    %       model. No refinement, no transform.
    %   Tissue points: the sparse points that lie inside the tissue
    %       silhouettes (the masks the mesh step used; same rule as its
    %       silhouette filter: inside in >= 90 % of the images they land
    %       in). Without masks every sparse point is used. Sparse points on
    %       the bath or the holder are not on the heart, so the mesh is
    %       not expected to cover them.
    %   A2 (projection error): for each tissue point the closest point on
    %       the mesh surface (not the nearest vertex). Its distance is
    %       measured in image pixels of the cameras that observe the point
    %       (distance x focal / depth, median over the observations), so
    %       the rule does not depend on the model's units or the cloud
    %       spacing. Points within 5 px are matched (the recipe drops
    %       sparse points whose reprojection error exceeds 4 px). For the
    %       matched points the surface point is projected into each
    %       observing camera and compared with the observation; the
    %       sparse model's own reprojection error of the same observations
    %       is the reference. PASS: >= 75 % of the tissue points matched,
    %       median error <= own median + 0.5 px and 95th percentile <= own
    %       95th percentile + 1.5 px. FAIL: < 40 % matched. WARN between.
    %   A3 (camera geometry): no camera centre inside the mesh bounding
    %       box (FAIL), the mesh in front of every camera (FAIL), and the
    %       projected mesh inside each image: PASS when every camera sees
    %       >= 75 % of the mesh vertices inside its frame, FAIL when the
    %       median camera sees < 50 %, WARN between. The overlap of the
    %       robust bounding boxes (5th-95th percentiles) of the tissue
    %       points and the mesh vertices gives WARN below 0.5 (never FAIL).
    %       The camera distance is recorded in mesh diagonals but not
    %       limited: it is set by the lens and working distance (rabbit
    %       rig 16-21 diagonals, 50 mm lens at 0.6-0.9 m).
    %   A4 (silhouette coverage): per view, the share of the tissue
    %       points' 2D observations inside the projected mesh silhouette
    %       (point-in-triangle test). PASS: median view >= 95 % and every
    %       view >= 75 %; FAIL: median view < 75 %; WARN between.
    %   A5 (registration policy): ICP (Besl & McKay 1992) is not used.
    %       There is no second cloud to register to, and a registration
    %       would hide a world-frame error.
    %   A6 (mesh outline): the mesh is drawn into every image that has a
    %       tissue mask (mesh_silhouette) and its outline compared with
    %       the mask's outline (silhouette_scores): the share of the mesh
    %       outline within 5 px of the mask outline (median over the
    %       images) and the share of the mesh silhouette on the tissue. A
    %       mesh that is too small, shifted or mirrored moves its outline
    %       off the tissue outline; a mesh that only stops short of part of
    %       the heart keeps the rest of its outline on it. PASS: outline
    %       share >= 50 % and silhouette on tissue >= 97 % (98 % with a
    %       field band); FAIL: outline share < 40 %; WARN between. Without
    %       masks A6 is not measured (WARN). With the mesh step's field
    %       band (opts.field_band_px, the run recipe's mesh.field_band_px,
    %       at most 64 px; rabbit_sfm_build.static_field_bands: only mask
    %       edges near the border that stay still over the frames of a
    %       view) the silhouette pixels in the band count neither on nor
    %       off the tissue, as in the mesh step, where the band does not
    %       limit the mesh.
    %
    % Where the limits come from (chosen for the rabbit data, not taken
    % from a reference; a parameter study on four rabbit recordings plus a
    % tab run on the reference rabbit data, membrane meshes, tissue masks):
    % matched 62-83 % of the tissue points (reference rabbit data
    % 62-63 %: WARN), median
    % error 0.28-0.33 px above the model's own (1.05-1.94 px against own
    % 0.74-1.65 px), mesh in frame >= 85 % for every camera, box overlap
    % 0.76-0.87, A4 median view 96-99 % and worst view 80-93 %. The same
    % meshes moved on purpose: shifted by 5 % of their diagonal 19-46 %
    % matched, mirrored 15-31 %, scaled by 1.05 25-38 %, by 1.2 0-2 %
    % (FAIL except one 5 % shift at 46 %, WARN); shrunk by 0.95 36-58 %
    % (WARN, one FAIL), so a small scale error is not always caught by A2.
    % A6 (the same four recordings and two runs on the reference rabbit
    % data, membrane meshes, score masks): outline share 0.58-0.65 as built;
    % shrunk by 0.95 0.03-0.25 and by 0.97 0.12-0.38, shifted by 5 % of
    % the diagonal 0.16-0.31, mirrored 0.16-0.24 (all FAIL); scaled by 1.05
    % 0.64-0.74 (A6 PASS; A2 FAILs it), shifted by 2 % 0.30-0.64, rotated
    % 5 degrees about the rotation axis 0.50-0.63 (not reliably caught).
    % Silhouette on tissue 0.998-1.000 as built (the membrane is held
    % inside the masks), 0.96-0.98 scaled by 1.05. With the mesh step's
    % field band (32 px) the mesh may reach
    % past a mask edge near the image border into the band: outline share
    % 0.56-0.77, A4 median view 99-100 % and worst view 89-93 % on the same
    % four recordings and the reference rabbit data. Counting band pixels
    % as off the tissue gives silhouette on tissue 0.980-1.000 (0.980 on
    % the reference rabbit data, 0.981 on another recording, close to the
    % 0.97 limit); A6 leaves the band out (the run's mesh.field_band_px),
    % which gives 0.997-1.000 on the same meshes, with the same outline
    % share and verdicts. A band over every border edge also covers heart
    % outlines near the border, so a mesh scaled by 1.03 or shifted by 2 %
    % passes; so the band is at still edges only. With it (two walks, the
    % four recordings and a run on the reference rabbit data): as built
    % outline share 0.60-0.71, on tissue 0.990-1.000 (0.971-1.000 with the
    % band counted as off); shrunk by 0.97 0.14-0.40 (FAIL); shifted by 2 %
    % 0.32-0.55 (FAIL or WARN, except one shift on one recording, 0.55 on
    % 0.980: PASS); scaled by 1.03 on tissue 0.971-0.972 on the reference
    % rabbit meshes (WARN with the 0.98 limit) but 0.985-0.994 on three
    % other recordings, whose silhouette cap holds the mesh inside the
    % masks (PASS: not caught); by 1.05 0.949-0.981 (WARN; one recording
    % PASS). The 0.98 limit with the band keeps a margin of 0.010 to the
    % as-built reference rabbit meshes; without the band the limit stays
    % 0.97, so recipes without a band keep their verdicts.
    % The legacy limits (A2 median <= 2.0 px and
    % p95 <= 5.0 px on pairs within 3 cloud spacings of a vertex, set
    % against a mouse model with 0.591 px own error; A3 cameras within 2
    % mesh diagonals and bounding-box IoU >= 0.90 over all sparse points;
    % A4 every view >= 95 % of all observations) fail every rabbit model
    % although its mesh lines up; their values stay in the record
    % (legacy_rule).
    %
    % Units/scale: native COLMAP units are kept and the transform is
    % identity. The mesh is built from the same COLMAP model as the
    % sparse points, so both share the world frame; no similarity
    % normalisation is applied (Umeyama 1991 is not used).
    %
    % Mesh source: the mesh from rabbit_mesh_cleanup
    % (outputs/mesh-cleanup.ply) when present. If mesh cleanup failed
    % (no candidate passed M4-M8, normal orientation to boundary and
    % holes), the best candidate's trimmed shell is rebuilt from the
    % M9 (visibility check) candidate in mesh-cleanup-gates.json (same
    % alpha, same outlier mask, same orientation and trim), so the
    % A gates can still be measured and kept on disk. The rebuilt shell
    % is written to outputs/alignment-rebuilt-mesh.ply.
    %
    % Citations: COLMAP (Schoenberger & Frahm 2016, camera model);
    % RHYTHM (Gloschat et al. 2018, PMID 29440763) and Laughner et al.
    % 2012 (PMID 22821993) for the projection. ICP (Besl & McKay 1992)
    % is not used.
    %
    % Usage:
    %   r = rabbit_mesh_alignment.run(fused_ply, vis_ply, images_bin, opts)
    %   r.ok, r.err, r.gates (struct), r.artifacts (path/sha256),
    %   r.out_json
    %
    % opts fields (all optional):
    %   mesh_ply     mesh-cleanup PLY (default: <fused dir>/mesh-cleanup.ply)
    %   gates_json   mesh-cleanup gates JSON for the rebuild (default:
    %                <fused dir>/mesh-cleanup-gates.json)
    %   out_json     alignment gates JSON (default: <fused dir>/alignment-gates.json)
    %   out_rebuilt  rebuilt shell PLY (default: <fused dir>/alignment-rebuilt-mesh.ply)
    %   k_nn         nearest-neighbour k for the rebuild (default 16)
    %   z_thresh     outlier z threshold for the rebuild (default 3.0)
    %   a3_bbox_expand  A3 bbox expansion (default 0.01)
    %
    %   mask_root    tissue silhouette masks (as for the mesh step; '' = none)
    %   silhouette_min_inside  tissue point rule (default 0.9)
    %   a2_match_px, a2_pass_matched, a2_fail_matched, a2_excess_median_px,
    %   a2_excess_p95_px, a3_pass_in_frame, a3_fail_in_frame, a3_warn_iou,
    %   a4_pass_median, a4_pass_min, a4_fail_median: the limits above
    %
    % On failure: a FAIL returns ok=false with the failed check and
    % measured values; the alignment JSON (and the rebuilt shell on the
    % rebuild path) are still written so the failed outputs are kept.
    % WARN returns ok=true with r.warnings. No silent retry, no silent
    % rescale.
    %
    % Gate codes A1-A6: plain names in check_names (end of the file).
    %
    % Section map (search for the quoted line; line numbers move)
    %   Run (all checks) ....... "function r = run("
    %   Mesh source ............ "= load_mesh("
    %   Sparse model ........... "= read_sparse_full("
    %   A2 ..................... "= gate_a2("
    %   A3 ..................... "= gate_a3("
    %   A4 ..................... "= gate_a4("
    %   A6 ..................... "= gate_a6("
    %   Projection ............. "function uv = project_point("
    %   Silhouettes ............ "function S = mesh_silhouette("
    %   Check names ............ "function txt = check_names("

    properties (Constant)
        A3_BBOX_EXPAND = 0.01;     % A3: camera inside the mesh box (+1 %)
        A2_MATCH_PX = 5.0;         % A2: tissue point within 5 px of the surface
        A2_PASS_MATCHED = 0.75;    % A2 PASS: share of tissue points matched
        A2_FAIL_MATCHED = 0.40;    % A2 FAIL below
        A2_EXCESS_MEDIAN_PX = 0.5; % A2 PASS: median error above the model's own
        A2_EXCESS_P95_PX = 1.5;    % A2 PASS: 95th percentile above the model's own
        A3_PASS_IN_FRAME = 0.75;   % A3 PASS: every camera sees this share of the mesh in frame
        A3_FAIL_IN_FRAME = 0.50;   % A3 FAIL: median camera below
        A3_WARN_IOU = 0.50;        % A3 WARN: robust box overlap below
        A4_PASS_MEDIAN = 0.95;     % A4 PASS: median view coverage
        A4_PASS_MIN = 0.75;        % A4 PASS: every view coverage
        A4_FAIL_MEDIAN = 0.75;     % A4 FAIL: median view below
        A6_EDGE_PX = 5;            % A6: mesh outline pixel on the tissue outline within this distance
        A6_PASS_EDGE = 0.50;       % A6 PASS: median image share of the mesh outline on the tissue outline
        A6_FAIL_EDGE = 0.40;       % A6 FAIL below
        A6_PASS_INSIDE = 0.97;     % A6 PASS: median image share of the mesh silhouette on the tissue
        A6_PASS_INSIDE_BAND = 0.98;  % the same with a field band (band pixels abstain)
        SILHOUETTE_MIN_INSIDE = 0.9; % tissue point rule (mesh step's silhouette filter)
        % Earlier limits, measured and kept in the record only (legacy_rule)
        LEGACY_A2_MEDIAN_PX = 2.0;
        LEGACY_A2_P95_PX = 5.0;
        LEGACY_MATCH_DIST_MULT = 3.0;
        LEGACY_A3_MAX_DIAG = 2.0;
        LEGACY_A3_IOU = 0.90;
        LEGACY_A4_MIN_COVERAGE = 0.95;
    end

    methods (Static)

        function r = run(fused_ply, vis_ply, images_bin, opts)
            %RUN Measure the alignment gates A1-A5 (no transform).
            if nargin < 4, opts = struct(); end
            r = struct();
            r.ok = false;
            r.err = '';
            r.gates = struct();
            r.warnings = {};
            r.artifacts = struct('path', {}, 'sha256', {});
            r.out_json = '';

            % ---- inputs ----
            if ~exist(fused_ply, 'file')
                r.err = sprintf('The dense cloud is missing: %s', fused_ply);
                return;
            end
            if ~exist(vis_ply, 'file')
                r.err = sprintf('The camera visibility file is missing: %s (needed to rebuild the mesh)', vis_ply);
                return;
            end
            if ~exist(images_bin, 'file')
                r.err = sprintf('The camera poses (images.bin) are missing: %s', images_bin);
                return;
            end
            out_dir = fileparts(fused_ply);
            mesh_ply = rabbit_mesh_alignment.opt_str(opts, 'mesh_ply', fullfile(out_dir, 'mesh-cleanup.ply'));
            gates_json = rabbit_mesh_alignment.opt_str(opts, 'gates_json', fullfile(out_dir, 'mesh-cleanup-gates.json'));
            out_json = rabbit_mesh_alignment.opt_str(opts, 'out_json', fullfile(out_dir, 'alignment-gates.json'));
            out_rebuilt = rabbit_mesh_alignment.opt_str(opts, 'out_rebuilt', fullfile(out_dir, 'alignment-rebuilt-mesh.ply'));
            k_nn = rabbit_mesh_alignment.opt_num(opts, 'k_nn', 16);
            z_thresh = rabbit_mesh_alignment.opt_num(opts, 'z_thresh', 3.0);
            a3_exp = rabbit_mesh_alignment.opt_num(opts, 'a3_bbox_expand', rabbit_mesh_alignment.A3_BBOX_EXPAND);
            mask_root = rabbit_mesh_alignment.opt_str(opts, 'mask_root', '');
            L = struct( ...
                'silhouette_min_inside', rabbit_mesh_alignment.opt_num(opts, 'silhouette_min_inside', rabbit_mesh_alignment.SILHOUETTE_MIN_INSIDE), ...
                'a2_match_px', rabbit_mesh_alignment.opt_num(opts, 'a2_match_px', rabbit_mesh_alignment.A2_MATCH_PX), ...
                'a2_pass_matched', rabbit_mesh_alignment.opt_num(opts, 'a2_pass_matched', rabbit_mesh_alignment.A2_PASS_MATCHED), ...
                'a2_fail_matched', rabbit_mesh_alignment.opt_num(opts, 'a2_fail_matched', rabbit_mesh_alignment.A2_FAIL_MATCHED), ...
                'a2_excess_median_px', rabbit_mesh_alignment.opt_num(opts, 'a2_excess_median_px', rabbit_mesh_alignment.A2_EXCESS_MEDIAN_PX), ...
                'a2_excess_p95_px', rabbit_mesh_alignment.opt_num(opts, 'a2_excess_p95_px', rabbit_mesh_alignment.A2_EXCESS_P95_PX), ...
                'a3_bbox_expand', a3_exp, ...
                'a3_pass_in_frame', rabbit_mesh_alignment.opt_num(opts, 'a3_pass_in_frame', rabbit_mesh_alignment.A3_PASS_IN_FRAME), ...
                'a3_fail_in_frame', rabbit_mesh_alignment.opt_num(opts, 'a3_fail_in_frame', rabbit_mesh_alignment.A3_FAIL_IN_FRAME), ...
                'a3_warn_iou', rabbit_mesh_alignment.opt_num(opts, 'a3_warn_iou', rabbit_mesh_alignment.A3_WARN_IOU), ...
                'a4_pass_median', rabbit_mesh_alignment.opt_num(opts, 'a4_pass_median', rabbit_mesh_alignment.A4_PASS_MEDIAN), ...
                'a4_pass_min', rabbit_mesh_alignment.opt_num(opts, 'a4_pass_min', rabbit_mesh_alignment.A4_PASS_MIN), ...
                'a4_fail_median', rabbit_mesh_alignment.opt_num(opts, 'a4_fail_median', rabbit_mesh_alignment.A4_FAIL_MEDIAN), ...
                'a6_edge_px', rabbit_mesh_alignment.opt_num(opts, 'a6_edge_px', rabbit_mesh_alignment.A6_EDGE_PX), ...
                'a6_pass_edge', rabbit_mesh_alignment.opt_num(opts, 'a6_pass_edge', rabbit_mesh_alignment.A6_PASS_EDGE), ...
                'a6_fail_edge', rabbit_mesh_alignment.opt_num(opts, 'a6_fail_edge', rabbit_mesh_alignment.A6_FAIL_EDGE), ...
                'a6_pass_inside', [], ...
                'field_band_px', rabbit_mesh_alignment.opt_num(opts, 'field_band_px', 0));
            % With a field band the band pixels abstain, which raises the share on the tissue
            % by about 0.01 on the reference rabbit data: the PASS limit is 0.98 then
            inside_default = rabbit_mesh_alignment.A6_PASS_INSIDE;
            if L.field_band_px > 0, inside_default = rabbit_mesh_alignment.A6_PASS_INSIDE_BAND; end
            L.a6_pass_inside = rabbit_mesh_alignment.opt_num(opts, 'a6_pass_inside', inside_default);
            r.out_json = out_json;
            try
                rabbit_mesh_cleanup.check_band_px(L.field_band_px);
            catch err
                r.err = err.message;
                return;
            end

            % ---- load the mesh (mesh-cleanup output, or the rebuild) ----
            [mxyz, mfaces, msrc, mrebuilt] = rabbit_mesh_alignment.load_mesh( ...
                fused_ply, vis_ply, images_bin, mesh_ply, gates_json, ...
                out_rebuilt, k_nn, z_thresh);
            if isempty(mxyz)
                r.err = msrc;
                return;
            end
            if isempty(mfaces)
                r.err = 'The mesh has no faces, so the silhouette coverage cannot be measured.';
                return;
            end

            % ---- read the sparse model (cameras + images with 2D
            % observations + points3D) ----
            [cameras, images, points3d, s_ok, s_err] = rabbit_mesh_alignment.read_sparse_full(images_bin);
            if ~s_ok
                r.err = s_err;
                return;
            end
            nviews = numel(images);
            if nviews == 0
                r.err = 'The sparse model has no images.';
                return;
            end

            % ---- s50 (median point spacing) on the source fused cloud ----
            [fxyz, ~, ~, fnv] = rabbit_mesh_cleanup.read_ply_27(fused_ply);
            if fnv == 0
                r.err = 'The dense cloud has no points.';
                return;
            end
            [s50, ~] = rabbit_mesh_cleanup.spacing_stats(fxyz, k_nn);

            % ---- A1: verify-only policy record ----
            r.gates.A1 = struct('pass', true, 'measured', struct( ...
                'policy', 'verify only: the mesh is checked against the cameras, never moved', ...
                'camera_model', 'COLMAP standard camera model (exact for pinhole cameras)', ...
                'mesh_source', msrc, ...
                'n_sparse_points', points3d.Count, ...
                'n_mesh_vertices', size(mxyz, 1), ...
                'n_mesh_faces', size(mfaces, 1), ...
                'n_views', nviews));

            % ---- tissue points: sparse points inside the tissue
            % silhouettes (the mesh step's masks and filter rule) ----
            S = rabbit_mesh_alignment.sparse_arrays(points3d);
            tissue = rabbit_mesh_alignment.tissue_points(S.xyz, images_bin, mask_root, L.silhouette_min_inside);
            r.gates.A1.measured.tissue_points = tissue.note;

            % ---- A2: projection error of the closest surface points ----
            [a2_v, a2_meas] = rabbit_mesh_alignment.gate_a2(mxyz, mfaces, cameras, images, S, tissue.keep, L);
            a2_meas.legacy_rule = rabbit_mesh_alignment.legacy_a2(mxyz, s50, cameras, images, points3d);
            r.gates.A2 = struct('pass', ~strcmp(a2_v, 'FAIL'), 'verdict', a2_v, 'measured', a2_meas, ...
                'criterion', sprintf(['tissue points within %.1f px of the surface: PASS >= %.0f %% matched, median error <= own + %.1f px, ' ...
                'p95 <= own p95 + %.1f px; FAIL < %.0f %% matched'], L.a2_match_px, 100 * L.a2_pass_matched, ...
                L.a2_excess_median_px, L.a2_excess_p95_px, 100 * L.a2_fail_matched));

            % ---- A3: camera geometry ----
            [a3_v, a3_meas] = rabbit_mesh_alignment.gate_a3(mxyz, cameras, images, points3d, S.xyz(tissue.keep, :), L);
            r.gates.A3 = struct('pass', ~strcmp(a3_v, 'FAIL'), 'verdict', a3_v, 'measured', a3_meas, ...
                'criterion', sprintf(['FAIL: a camera inside the mesh box (+%.0f %%) or behind the mesh, or the median camera ' ...
                'sees < %.0f %% of the mesh in frame; PASS: every camera >= %.0f %%; WARN: between, or robust box overlap < %.2f'], ...
                100 * L.a3_bbox_expand, 100 * L.a3_fail_in_frame, 100 * L.a3_pass_in_frame, L.a3_warn_iou));

            % ---- A4: per-view silhouette coverage ----
            [a4_v, a4_meas] = rabbit_mesh_alignment.gate_a4(mxyz, mfaces, cameras, images, S.ids(tissue.keep), L);
            r.gates.A4 = struct('pass', ~strcmp(a4_v, 'FAIL'), 'verdict', a4_v, 'measured', a4_meas, ...
                'criterion', sprintf(['tissue observations inside the projected mesh: PASS median view >= %.0f %% and every view ' ...
                '>= %.0f %%; FAIL median view < %.0f %%'], 100 * L.a4_pass_median, 100 * L.a4_pass_min, 100 * L.a4_fail_median));

            % ---- A6: the mesh outline against the tissue masks ----
            [a6_v, a6_meas] = rabbit_mesh_alignment.gate_a6(mxyz, mfaces, images_bin, mask_root, L);
            r.gates.A6 = struct('pass', ~strcmp(a6_v, 'FAIL'), 'verdict', a6_v, 'measured', a6_meas, ...
                'criterion', sprintf(['mesh outline within %g px of the tissue outline: PASS median image >= %.0f %% and ' ...
                'mesh silhouette on tissue >= %.0f %% (field band of %g px left out); FAIL < %.0f %%; not measured ' ...
                'without masks (WARN)'], L.a6_edge_px, 100 * L.a6_pass_edge, 100 * L.a6_pass_inside, L.field_band_px, ...
                100 * L.a6_fail_edge));

            % ---- A5: ICP policy ----
            r.gates.A5 = struct('pass', true, 'measured', struct( ...
                'icp_used', false, ...
                'policy', 'ICP not used (Besl and McKay 1992, IEEE TPAMI 14(2):239-256): there is no second cloud to register, and a registration would hide a world-frame error'));
            r.gates.A1.verdict = 'PASS';
            r.gates.A5.verdict = 'PASS';

            % ---- final verdict: FAIL stops the run, WARN is said in the
            % step's warnings and the run goes on ----
            gate_names = {'A1', 'A2', 'A3', 'A4', 'A5', 'A6'};
            verdicts = cellfun(@(g) r.gates.(g).verdict, gate_names, 'UniformOutput', false);
            failed = gate_names(strcmp(verdicts, 'FAIL'));
            warned = gate_names(strcmp(verdicts, 'WARN'));
            all_pass = isempty(failed);
            r.ok = all_pass;
            for k = 1:numel(warned)
                r.warnings{end+1} = sprintf(['Alignment check WARN - %s (%s): the mesh lines up, but this ' ...
                    'check is below its ideal value. Measured: %s. The mesh is used and the run continues; see ' ...
                    'Help, Limitations.'], rabbit_mesh_alignment.check_names(warned(k)), warned{k}, ...
                    r.gates.(warned{k}).measured.summary);
            end
            if ~all_pass
                r.err = sprintf('These alignment checks failed: %s. The run stops here for review; details are in the alignment JSON.', ...
                    rabbit_mesh_alignment.check_names(failed));
            end

            % ---- write the alignment JSON ----
            aj = struct();
            aj.stage = 'alignment';
            aj.input = struct('fused_ply', fused_ply, ...
                'fused_sha256', rabbit_mesh_cleanup.sha256_file(fused_ply), ...
                'images_bin', images_bin, ...
                'mesh_source', msrc);
            if ~isempty(mrebuilt)
                aj.input.rebuilt_mesh = out_rebuilt;
                aj.input.rebuilt_sha256 = rabbit_mesh_cleanup.sha256_file(out_rebuilt);
            end
            aj.transform = 'identity (pinned registration: the run consumes the reference sparse model, so the mesh and the sparse model share the world frame by construction; native COLMAP units preserved; no similarity normalization (S2/Umeyama 1991 not used); no ICP (A5))';
            aj.parameters = L;
            aj.parameters.k_nn = k_nn;
            aj.parameters.z_thresh = z_thresh;
            aj.parameters.mask_root = mask_root;
            aj.gates = r.gates;
            aj.verdict = 'PASS';
            if ~isempty(warned), aj.verdict = 'WARN'; end
            if ~all_pass, aj.verdict = 'FAIL'; end
            if ~all_pass
                aj.blocked_for = 'review of the failed checks';
            end
            aj.citations = {'colmap-sfm (Schoenberger & Frahm 2016, CVPR - COLMAP camera model)', ...
                'rhythm (Gloschat et al. 2018, Sci Rep 8:2921, PMID 29440763 - projection model)', ...
                'laughner (Laughner et al. 2012, AJP-Heart 303(7):H753-65, PMID 22821993 - software lineage)'};
            aj.icp_citation = 'Besl and McKay 1992, IEEE TPAMI 14(2):239-256 - not used';
            fid = fopen(out_json, 'w', 'n', 'UTF-8');
            if fid > 0
                fprintf(fid, '%s', jsonencode(aj, 'PrettyPrint', true));
                fclose(fid);
            end
            r.artifacts(end+1) = struct('path', out_json, 'sha256', rabbit_mesh_cleanup.sha256_file(out_json));
            r.artifacts(end+1) = struct('path', fused_ply, 'sha256', rabbit_mesh_cleanup.sha256_file(fused_ply));
            if ~isempty(mrebuilt)
                r.artifacts(end+1) = struct('path', out_rebuilt, 'sha256', rabbit_mesh_cleanup.sha256_file(out_rebuilt));
            end
        end

        % =============================================================
        % Mesh loading: the mesh-cleanup mesh when present, else the
        % rebuild of the best-available candidate from the gates JSON.
        % =============================================================

        function [xyz, faces, src, rebuilt] = load_mesh(fused_ply, vis_ply, images_bin, mesh_ply, gates_json, out_rebuilt, k_nn, z_thresh)
            xyz = []; faces = []; src = ''; rebuilt = '';
            if ~isempty(mesh_ply) && exist(mesh_ply, 'file')
                m = rabbit_rhythm_reproject.read_ply_mesh(mesh_ply);
                xyz = m.pts;
                faces = m.faces;
                src = mesh_ply;
                return;
            end
            % Rebuild: best candidate from the mesh-cleanup gates JSON
            % (the M9 candidate; deterministic).
            if isempty(gates_json) || exist(gates_json, 'file') ~= 2
                src = sprintf('There is no mesh at %s and no mesh check record (mesh-cleanup-gates.json) to rebuild one from.', mesh_ply);
                return;
            end
            try
                gj = jsondecode(fileread(gates_json));
            catch
                src = sprintf('The mesh check record could not be read: %s', gates_json);
                return;
            end
            if ~isfield(gj, 'gates') || ~isfield(gj.gates, 'M9') || ...
                    ~isfield(gj.gates.M9, 'candidate') || ~isfield(gj.gates.M9.candidate, 'alpha')
                src = 'The mesh check record (mesh-cleanup-gates.json) names no candidate mesh to rebuild.';
                return;
            end
            cand = gj.gates.M9.candidate;
            [xyz0, nrm0, rgb0, nv] = rabbit_mesh_cleanup.read_ply_27(fused_ply);
            if nv == 0
                src = 'The dense cloud has no points, so no mesh can be rebuilt.';
                return;
            end
            [keep, ~] = rabbit_mesh_cleanup.outlier_mask(xyz0, k_nn, z_thresh);
            work = xyz0(keep, :);
            nrm_w = nrm0(keep, :);
            rgb_w = rgb0(keep, :);
            [faces0, comps, ~] = rabbit_mesh_cleanup.alpha_surface(work, cand.alpha);
            if isempty(faces0)
                src = sprintf('Rebuilding the mesh gave no surface (alpha radius %.6f).', cand.alpha);
                return;
            end
            [vis, vok, verr] = rabbit_mesh_cleanup.read_vis(vis_ply);
            if ~vok
                src = verr;
                return;
            end
            [cameras, images, cok, cerr] = rabbit_mesh_cleanup.read_colmap_model(images_bin);
            if ~cok
                src = cerr;
                return;
            end
            centers = rabbit_mesh_cleanup.camera_centres(images);
            lookns = rabbit_mesh_cleanup.camera_lookns(images);
            [nrm_o, ~] = rabbit_mesh_cleanup.orient_normals(work, nrm_w, vis(keep), centers, comps, k_nn);
            [faces_v, ~] = rabbit_mesh_cleanup.trim_visible_shell(work, nrm_o, faces0, vis(keep), lookns);
            if isempty(faces_v)
                src = sprintf('Rebuilding the mesh left no surface that the cameras see (alpha radius %.6f).', cand.alpha);
                return;
            end
            faces = rabbit_mesh_cleanup.orient_faces(work, nrm_o, faces_v);
            xyz = work;
            % Write the rebuilt shell so the measured geometry is kept on disk.
            rabbit_mesh_cleanup.write_ply(out_rebuilt, work, nrm_o, rgb_w, faces);
            rebuilt = out_rebuilt;
            src = sprintf('mesh rebuilt from the best candidate in mesh-cleanup-gates.json (alpha_mult %d, alpha %.6f, %d faces)', ...
                cand.alpha_mult, cand.alpha, cand.n_faces);
        end

        % =============================================================
        % Sparse model reader: cameras.bin + images.bin (with 2D
        % observations) + points3D.bin (standard COLMAP binary layout,
        % the same as the reconstruction tab's readers).
        % =============================================================

        function [cameras, images, points3d, ok, err] = read_sparse_full(images_bin)
            cameras = containers.Map('KeyType', 'int64', 'ValueType', 'any');
            images = struct('id', {}, 'qvec', {}, 'tvec', {}, 'camera_id', {}, ...
                'name', {}, 'points2D_xy', {}, 'point3D_ids', {});
            points3d = containers.Map('KeyType', 'int64', 'ValueType', 'any');
            ok = false;
            err = '';
            cam_bin = fullfile(fileparts(images_bin), 'cameras.bin');
            pts_bin = fullfile(fileparts(images_bin), 'points3D.bin');
            if ~exist(cam_bin, 'file')
                err = sprintf('cameras.bin missing next to %s', images_bin);
                return;
            end
            if ~exist(pts_bin, 'file')
                err = sprintf('points3D.bin missing next to %s', images_bin);
                return;
            end
            % cameras.bin
            fid = fopen(cam_bin, 'rb');
            if fid < 0, err = 'cannot open cameras.bin'; return; end
            n = fread(fid, 1, 'uint64');
            for k = 1:n
                cid = int64(fread(fid, 1, 'int32'));
                model_id = fread(fid, 1, 'int32');
                wh = fread(fid, 2, 'uint64');
                npar = rabbit_mesh_cleanup.camera_num_params(model_id);
                params = fread(fid, npar, 'double');
                cameras(cid) = struct('model', rabbit_mesh_cleanup.camera_model_name(model_id), ...
                    'width', wh(1), 'height', wh(2), 'params', params);
            end
            fclose(fid);
            % images.bin (with 2D observations; 24-byte records:
            % double x, double y, int64 point3D_id)
            fid = fopen(images_bin, 'rb');
            if fid < 0, err = 'cannot open images.bin'; return; end
            n = fread(fid, 1, 'uint64');
            for k = 1:n
                im_id = int64(fread(fid, 1, 'int32'));
                qvec = fread(fid, 4, 'double');
                tvec = fread(fid, 3, 'double');
                cam_id = int64(fread(fid, 1, 'int32'));
                name = '';
                while true
                    c = fread(fid, 1, 'uint8');
                    if isempty(c) || c == 0, break; end
                    name = [name char(c)]; %#ok<AGROW>
                end
                np = fread(fid, 1, 'uint64');
                pts = zeros(3, 0);
                pids = zeros(1, 0);
                if np > 0
                    pts = fread(fid, [3 np], 'double');
                    pids = int64(typecast(pts(3, :), 'int64'));
                end
                images(end+1) = struct('id', im_id, 'qvec', qvec, 'tvec', tvec, ...
                    'camera_id', cam_id, 'name', name, ...
                    'points2D_xy', pts(1:2, :), 'point3D_ids', pids); %#ok<AGROW>
            end
            fclose(fid);
            % points3D.bin
            fid = fopen(pts_bin, 'rb');
            if fid < 0, err = 'cannot open points3D.bin'; return; end
            n = fread(fid, 1, 'uint64');
            for k = 1:n
                pid = int64(fread(fid, 1, 'uint64'));
                xyz = fread(fid, 3, 'double');
                rgb = fread(fid, 3, 'uint8');
                fread(fid, 1, 'double'); % error
                tl = fread(fid, 1, 'uint64');
                tr = fread(fid, [2 tl], 'int32');
                points3d(pid) = struct('xyz', xyz, 'rgb', rgb, ...
                    'image_ids', int64(tr(1, :)), 'point2D_idxs', int64(tr(2, :)));
            end
            fclose(fid);
            ok = true;
        end

        % =============================================================
        % Tissue points: the sparse points inside the tissue silhouettes.
        % =============================================================

        function S = sparse_arrays(points3d)
            % points3D map -> arrays (ids, xyz, observing image ids and
            % 0-based 2D indices), in the map's key order
            ks = keys(points3d);
            n = numel(ks);
            S = struct('ids', zeros(n, 1, 'int64'), 'xyz', zeros(n, 3));
            S.img = cell(n, 1);
            S.p2 = cell(n, 1);
            for k = 1:n
                p = points3d(ks{k});
                S.ids(k) = ks{k};
                S.xyz(k, :) = p.xyz(:)';
                S.img{k} = p.image_ids;
                S.p2{k} = p.point2D_idxs;
            end
        end

        function t = tissue_points(xyz, images_bin, mask_root, min_inside)
            % Sparse points inside the tissue masks in >= min_inside of the
            % images they land in (rabbit_sfm_build.silhouette_filter, the
            % rule of the mesh step's silhouette filter). Without usable
            % masks, or with fewer than 20 points kept, every point is used
            % and the note says so.
            n = size(xyz, 1);
            t = struct('keep', true(n, 1), 'note', '');
            if isempty(mask_root) || ~isfolder(mask_root)
                t.note = sprintf('all %d sparse points (no tissue masks)', n);
                return;
            end
            [cams0, imgs0] = rabbit_mesh_cleanup.read_colmap_model(images_bin);
            fc = rabbit_mesh_cleanup.filter_cameras(cams0, imgs0, mask_root);
            if isempty(fc)
                t.note = sprintf('all %d sparse points (no mask in %s fits a pinhole camera of the model)', n, mask_root);
                return;
            end
            keep = rabbit_sfm_build.silhouette_filter(xyz, fc, min_inside);
            if sum(keep) < 20
                t.note = sprintf('all %d sparse points (only %d inside the tissue masks)', n, sum(keep));
                return;
            end
            t.keep = keep;
            t.note = sprintf(['%d of %d sparse points inside the tissue masks of %d images (%s; inside in >= %.0f %% ' ...
                'of the images they land in)'], sum(keep), n, numel(fc), mask_root, 100 * min_inside);
        end

        % =============================================================
        % A2: projection error of the closest surface points.
        % =============================================================

        function [verdict, meas] = gate_a2(V, F, cameras, images, S, keep, L)
            im_by_id = containers.Map('KeyType', 'int64', 'ValueType', 'double');
            for i = 1:numel(images)
                im_by_id(int64(images(i).id)) = i;
            end
            idx = find(keep);
            Q = rabbit_mesh_alignment.closest_on_mesh(S.xyz(idx, :), V, F);
            % Per observation: the model's own error (the sparse point),
            % the surface error (its closest surface point) and the
            % point-surface distance in pixels of that camera (distance x
            % focal / depth)
            nobs = sum(cellfun(@numel, S.img(idx)));
            e_own = nan(nobs, 1); e_srf = e_own; d_px = e_own; owner = zeros(nobs, 1);
            o = 0;
            for j = 1:numel(idx)
                i = idx(j);
                dist = norm(S.xyz(i, :) - Q(j, :));
                for k = 1:numel(S.img{i})
                    if ~isKey(im_by_id, int64(S.img{i}(k))), continue; end
                    im = images(im_by_id(int64(S.img{i}(k))));
                    cam = cameras(im.camera_id);
                    obs = im.points2D_xy(:, S.p2{i}(k) + 1); % COLMAP point2D_idx is 0-based
                    u0 = rabbit_mesh_alignment.project_point(S.xyz(i, :), im, cam);
                    u1 = rabbit_mesh_alignment.project_point(Q(j, :), im, cam);
                    R = rabbit_mesh_cleanup.qvec2rot(im.qvec);
                    z = R(3, :) * S.xyz(i, :)' + im.tvec(3);
                    if any(isnan(u0)) || any(isnan(u1)) || z <= 0, continue; end
                    o = o + 1;
                    e_own(o) = norm(u0 - obs);
                    e_srf(o) = norm(u1 - obs);
                    d_px(o) = dist * cam.params(1) / z;   % the first parameter is the focal length (fx) in every COLMAP model
                    owner(o) = j;
                end
            end
            e_own = e_own(1:o); e_srf = e_srf(1:o); d_px = d_px(1:o); owner = owner(1:o);
            meas = struct('n_tissue_points', numel(idx), 'n_observations', o);
            if o == 0
                verdict = 'FAIL';
                meas.summary = 'no tissue point has an observation that projects';
                return;
            end
            pt_px = accumarray(owner, d_px, [numel(idx) 1], @median, NaN);
            seen = ~isnan(pt_px);
            m_pt = seen & pt_px <= L.a2_match_px;
            frac = sum(m_pt) / max(sum(seen), 1);
            mo = m_pt(owner);
            meas.distance_px = struct('median', median(pt_px(seen)), 'p95', prctile(pt_px(seen), 95));
            meas.matched_fraction = frac;
            meas.n_matched = sum(m_pt);
            meas.median_px = NaN; meas.p95_px = NaN; meas.own_median_px = NaN; meas.own_p95_px = NaN;
            if any(mo)
                meas.median_px = median(e_srf(mo)); meas.p95_px = prctile(e_srf(mo), 95);
                meas.own_median_px = median(e_own(mo)); meas.own_p95_px = prctile(e_own(mo), 95);
            end
            meas.excess_median_px = meas.median_px - meas.own_median_px;
            meas.excess_p95_px = meas.p95_px - meas.own_p95_px;
            if frac < L.a2_fail_matched || ~any(mo)
                verdict = 'FAIL';
            elseif frac >= L.a2_pass_matched && meas.excess_median_px <= L.a2_excess_median_px && ...
                    meas.excess_p95_px <= L.a2_excess_p95_px
                verdict = 'PASS';
            else
                verdict = 'WARN';
            end
            meas.summary = sprintf(['%.0f %% of %d tissue points within %.1f px of the surface (PASS >= %.0f %%, FAIL < %.0f %%); ' ...
                'matched error median %.2f px / p95 %.2f px against the model''s own %.2f / %.2f px'], ...
                100 * frac, numel(idx), L.a2_match_px, 100 * L.a2_pass_matched, 100 * L.a2_fail_matched, ...
                meas.median_px, meas.p95_px, meas.own_median_px, meas.own_p95_px);
        end

        function meas = legacy_a2(mxyz, s50, cameras, images, points3d)
            % The earlier A2 measure, kept in the record only: the nearest
            % mesh vertex of every sparse point within 3 cloud spacings
            % (s50); median <= 2.0 px and p95 <= 5.0 px
            md_mult = rabbit_mesh_alignment.LEGACY_MATCH_DIST_MULT;
            sp_xyz = zeros(points3d.Count, 3);
            pids = keys(points3d);
            for k = 1:numel(pids)
                sp_xyz(k, :) = points3d(pids{k}).xyz;
            end
            [vi, d] = knnsearch(mxyz, sp_xyz, 'K', 1);
            matched = d <= md_mult * s50;
            im_by_id = containers.Map('KeyType', 'int64', 'ValueType', 'any');
            for i = 1:numel(images)
                im_by_id(int64(images(i).id)) = i;
            end
            errs = [];
            for k = find(matched)'
                p = points3d(pids{k});
                v = mxyz(vi(k), :);
                for o = 1:numel(p.image_ids)
                    if ~isKey(im_by_id, int64(p.image_ids(o))), continue; end
                    im = images(im_by_id(int64(p.image_ids(o))));
                    uv = rabbit_mesh_alignment.project_point(v, im, cameras(im.camera_id));
                    if any(isnan(uv)), continue; end
                    errs(end+1) = norm(uv - im.points2D_xy(:, p.point2D_idxs(o) + 1)); %#ok<AGROW>
                end
            end
            if isempty(errs), errs = NaN; end
            meas = struct('matched_fraction', mean(matched), 'median_px', median(errs), 'p95_px', prctile(errs, 95), ...
                'match_distance', md_mult * s50, 'fused_s50', s50, ...
                'pass', median(errs) <= rabbit_mesh_alignment.LEGACY_A2_MEDIAN_PX && ...
                prctile(errs, 95) <= rabbit_mesh_alignment.LEGACY_A2_P95_PX, ...
                'rule', 'nearest vertex within 3 s50; median <= 2.0 px AND p95 <= 5.0 px (mouse reference 0.591 px)');
        end

        function [Q, D] = closest_on_mesh(P, V, F)
            % Closest surface point of the mesh to every row of P: exact
            % over the faces around the 8 nearest vertices (closest-point
            % region tests, Ericson 2005, Real-Time Collision Detection,
            % section 5.1.5)
            nv = size(V, 1);
            [sv, order] = sort(F(:));
            owner = mod(order - 1, size(F, 1)) + 1;          % face of each (vertex, face) incidence
            counts = accumarray(sv, 1, [nv 1]);
            starts = cumsum(counts) - counts;
            slot = (1:numel(sv))' - starts(sv);
            incident = zeros(nv, max(counts));
            incident(sub2ind(size(incident), sv, slot)) = owner;
            k = min(8, nv);
            Q = zeros(size(P)); D = inf(size(P, 1), 1);
            chunk = 5000;
            for b = 1:chunk:size(P, 1)
                rows = b:min(b + chunk - 1, size(P, 1));
                near = knnsearch(V, P(rows, :), 'K', k);
                cand = reshape(incident(near', :)', [], numel(rows))'; % candidate faces per point
                [rr, cc] = find(cand > 0);
                f = cand(sub2ind(size(cand), rr, cc));
                [q, d] = rabbit_mesh_alignment.point_triangle(P(rows(rr), :), V(F(f, 1), :), V(F(f, 2), :), V(F(f, 3), :));
                [dmin, pick] = rabbit_mesh_alignment.group_min(rr, d, numel(rows));
                D(rows) = dmin;
                Q(rows, :) = q(pick, :);
            end
        end

        function [dmin, pick] = group_min(g, d, n)
            % Smallest d per group g (1..n, every group present) and the row that has it
            [~, ord] = sortrows([g(:) d(:)]);
            gs = g(ord);
            first = [true; diff(gs(:)) > 0];
            pick = zeros(n, 1);
            pick(gs(first)) = ord(first);
            dmin = inf(n, 1);
            dmin(gs(first)) = d(ord(first));
        end

        function [q, d] = point_triangle(p, a, b, c)
            % Closest points q on the triangles (a, b, c) to the points p (rows)
            ab = b - a; ac = c - a; ap = p - a;
            d1 = sum(ab .* ap, 2); d2 = sum(ac .* ap, 2);
            bp = p - b; d3 = sum(ab .* bp, 2); d4 = sum(ac .* bp, 2);
            cp = p - c; d5 = sum(ab .* cp, 2); d6 = sum(ac .* cp, 2);
            va = d3 .* d6 - d5 .* d4; vb = d5 .* d2 - d1 .* d6; vc = d1 .* d4 - d3 .* d2;
            denom = va + vb + vc;
            q = a + ab .* (vb ./ denom) + ac .* (vc ./ denom);   % inside the face
            s = va <= 0 & d4 - d3 >= 0 & d5 - d6 >= 0;           % edge bc
            w = (d4 - d3) ./ ((d4 - d3) + (d5 - d6));
            q(s, :) = b(s, :) + (c(s, :) - b(s, :)) .* w(s);
            s = vb <= 0 & d2 >= 0 & d6 <= 0;                     % edge ac
            q(s, :) = a(s, :) + ac(s, :) .* (d2(s) ./ (d2(s) - d6(s)));
            s = d6 >= 0 & d5 <= d6;                              % vertex c
            q(s, :) = c(s, :);
            s = vc <= 0 & d1 >= 0 & d3 <= 0;                     % edge ab
            q(s, :) = a(s, :) + ab(s, :) .* (d1(s) ./ (d1(s) - d3(s)));
            s = d3 >= 0 & d4 <= d3;                              % vertex b
            q(s, :) = b(s, :);
            s = d1 <= 0 & d2 <= 0;                               % vertex a
            q(s, :) = a(s, :);
            d = sqrt(sum((p - q) .^ 2, 2));
            d(~isfinite(d)) = inf;
        end

        % =============================================================
        % A3: camera geometry.
        % =============================================================

        function [verdict, meas] = gate_a3(mxyz, cameras, images, points3d, tissue_xyz, L)
            centers = rabbit_mesh_cleanup.camera_centres(images);
            bbox = [min(mxyz, [], 1); max(mxyz, [], 1)]; % 2x3
            ext = bbox(2, :) - bbox(1, :);
            bbox_e = [bbox(1, :) - L.a3_bbox_expand * ext; bbox(2, :) + L.a3_bbox_expand * ext];
            centroid = mean(bbox, 1);
            diagl = norm(ext);
            nc = numel(images);
            inside = false(nc, 1); behind = false(nc, 1); in_frame = zeros(nc, 1);
            for c = 1:nc
                inside(c) = all(centers(c, :) >= bbox_e(1, :) - 1e-12) && ...
                    all(centers(c, :) <= bbox_e(2, :) + 1e-12);
                im = images(c);
                cam = cameras(im.camera_id);
                R = rabbit_mesh_cleanup.qvec2rot(im.qvec);
                behind(c) = R(3, :) * centroid(:) + im.tvec(3) <= 0;
                uv = rabbit_mesh_alignment.project_points(mxyz, im, cam);
                in_frame(c) = mean(all(isfinite(uv), 2) & uv(:, 1) >= 0 & uv(:, 2) >= 0 & ...
                    uv(:, 1) <= double(cam.width) & uv(:, 2) <= double(cam.height));
            end
            dist = sqrt(sum((centers - centroid).^2, 2)) / max(diagl, 1e-12);
            % Robust box overlap: 5th-95th percentiles of the tissue points
            % and of the mesh vertices (one stray sparse point does not
            % decide it)
            iou = NaN;
            if size(tissue_xyz, 1) >= 20
                iou = rabbit_mesh_alignment.bbox_iou([prctile(mxyz, 5); prctile(mxyz, 95)], ...
                    [prctile(tissue_xyz, 5); prctile(tissue_xyz, 95)]);
            end
            med_in = median(in_frame);
            if any(inside) || any(behind) || med_in < L.a3_fail_in_frame
                verdict = 'FAIL';
            elseif min(in_frame) >= L.a3_pass_in_frame && ~(iou < L.a3_warn_iou)
                verdict = 'PASS';
            else
                verdict = 'WARN';
            end
            % The earlier rule, kept in the record only
            sp_xyz = zeros(points3d.Count, 3);
            pids = keys(points3d);
            for k = 1:numel(pids)
                sp_xyz(k, :) = points3d(pids{k}).xyz;
            end
            raw_iou = rabbit_mesh_alignment.bbox_iou(bbox, [min(sp_xyz, [], 1); max(sp_xyz, [], 1)]);
            ids = [images.id];
            meas = struct('n_cameras', nc, ...
                'cameras_inside_bbox', ids(inside), ...
                'cameras_behind_mesh', ids(behind), ...
                'mesh_in_frame_min', min(in_frame), 'mesh_in_frame_median', med_in, ...
                'cameras_below_pass_in_frame', ids(in_frame < L.a3_pass_in_frame), ...
                'center_dist_diag_min', min(dist), 'center_dist_diag_max', max(dist), ...
                'robust_box_overlap', iou, ...
                'mesh_bbox', bbox, ...
                'legacy_rule', struct('cameras_beyond_2x_diag', sum(dist > rabbit_mesh_alignment.LEGACY_A3_MAX_DIAG), ...
                'sparse_mesh_bbox_iou', raw_iou, ...
                'pass', ~any(inside) && ~any(dist > rabbit_mesh_alignment.LEGACY_A3_MAX_DIAG) && ...
                raw_iou >= rabbit_mesh_alignment.LEGACY_A3_IOU, ...
                'rule', 'centres within 2 mesh diagonals of the centroid; bounding-box IoU of all sparse points >= 0.90'));
            meas.summary = rabbit_mesh_alignment.a3_summary(verdict, in_frame, inside, behind, iou, dist, ...
                {images.name}, L);
        end

        function txt = a3_summary(verdict, in_frame, inside, behind, iou, dist, names, L)
            % A3 summary for the step warnings. It starts with the part
            % that decided a FAIL or WARN and gives one decimal, so a
            % worst camera at 74.6 % is not shown as "75 %" next to
            % "PASS >= 75 %". in_frame,
            % inside, behind and dist hold one value per camera; names
            % the image names in the same order.
            nc = numel(in_frame);
            med_in = median(in_frame);
            [~, worst] = min(in_frame);
            n_low = sum(in_frame < L.a3_pass_in_frame);
            why = {};
            if any(inside)
                why{end + 1} = sprintf('%d camera(s) inside the mesh box (FAIL)', sum(inside));
            end
            if any(behind)
                why{end + 1} = sprintf('%d camera(s) behind the mesh (FAIL)', sum(behind));
            end
            if med_in < L.a3_fail_in_frame
                why{end + 1} = sprintf('the median camera sees only %.1f %% of the mesh in frame (FAIL below %.1f %%)', ...
                    100 * med_in, 100 * L.a3_fail_in_frame);
            end
            if strcmp(verdict, 'WARN') && n_low > 0
                why{end + 1} = sprintf(['%d camera(s) see less than %.1f %% of the mesh in frame, the worst %.1f %% ' ...
                    '(image %s); PASS needs every camera at %.1f %% or more'], n_low, 100 * L.a3_pass_in_frame, ...
                    100 * in_frame(worst), char(string(names{worst})), 100 * L.a3_pass_in_frame);
            end
            if strcmp(verdict, 'WARN') && iou < L.a3_warn_iou
                why{end + 1} = sprintf('the robust box overlap of mesh and tissue points is %.2f (WARN below %.2f)', ...
                    iou, L.a3_warn_iou);
            end
            if isempty(why)
                lead = '';
            else
                lead = [strjoin(why, '; ') '. '];
            end
            txt = sprintf(['%s%d cameras: %d inside the mesh box, %d behind the mesh; mesh in frame %.1f %% (worst ' ...
                'camera) / %.1f %% (median), PASS when every camera >= %.1f %%; robust box overlap %.2f (WARN < %.2f); ' ...
                'cameras %.1f-%.1f mesh diagonals away (not limited)'], lead, nc, sum(inside), sum(behind), ...
                100 * min(in_frame), 100 * med_in, 100 * L.a3_pass_in_frame, iou, L.a3_warn_iou, min(dist), max(dist));
        end

        function iou = bbox_iou(b1, b2)
            %BBox IoU for axis-aligned boxes b = [minx miny minz; maxx maxy maxz].
            lo = max(b1(1, :), b2(1, :));
            hi = min(b1(2, :), b2(2, :));
            inter = prod(max(0, hi - lo));
            v1 = prod(b1(2, :) - b1(1, :));
            v2 = prod(b2(2, :) - b2(1, :));
            iou = inter / (v1 + v2 - inter + eps);
        end

        % =============================================================
        % A4: per-view silhouette coverage (point-in-triangle on the
        % projected mesh) of the tissue points' observations.
        % =============================================================

        function [verdict, meas] = gate_a4(mxyz, mfaces, cameras, images, tissue_ids, L)
            nviews = numel(images);
            per = struct();
            cov_t = nan(nviews, 1);
            cov_all = nan(nviews, 1);
            for i = 1:nviews
                im = images(i);
                cam = cameras(im.camera_id);
                tracked = im.point3D_ids ~= -1;
                if ~any(tracked)
                    per.(sprintf('img%d', im.id)) = struct('n_observations', 0, ...
                        'inside', 0, 'coverage', NaN, 'note', 'no tracked observations');
                    continue;
                end
                % Project all mesh vertices through this camera
                V = rabbit_mesh_alignment.project_points(mxyz, im, cam);
                okv = all(isfinite(V), 2);
                F = mfaces(okv(mfaces(:, 1)) & okv(mfaces(:, 2)) & okv(mfaces(:, 3)), :);
                obs = im.points2D_xy(:, tracked);
                inside = false(size(obs, 2), 1);
                if ~isempty(F)
                    inside = rabbit_mesh_alignment.in_triangles(obs', V, F);
                end
                cov_all(i) = mean(inside);
                is_t = ismember(im.point3D_ids(tracked), tissue_ids);
                ins_t = inside(is_t(:));
                if ~isempty(ins_t), cov_t(i) = mean(ins_t); end
                per.(sprintf('img%d', im.id)) = struct('n_observations', numel(ins_t), ...
                    'inside', sum(ins_t), 'coverage', cov_t(i), 'coverage_all_points', cov_all(i));
            end
            c = cov_t(~isnan(cov_t));
            if isempty(c)
                verdict = 'FAIL';
                meas = struct('per_view', per, 'n_views_with_observations', 0, ...
                    'summary', 'no view has a tissue observation');
                return;
            end
            med = median(c);
            if med < L.a4_fail_median
                verdict = 'FAIL';
            elseif med >= L.a4_pass_median && min(c) >= L.a4_pass_min
                verdict = 'PASS';
            else
                verdict = 'WARN';
            end
            ids = [images.id];
            cl = cov_all(~isnan(cov_all));
            meas = struct('per_view', per, 'n_views_with_observations', numel(c), ...
                'coverage_median', med, 'coverage_min', min(c), ...
                'views_below_pass_min', ids(cov_t < L.a4_pass_min), ...
                'legacy_rule', struct('coverage_min', min(cl), 'coverage_median', median(cl), ...
                'views_below_95', sum(cl < rabbit_mesh_alignment.LEGACY_A4_MIN_COVERAGE), ...
                'pass', all(cl >= rabbit_mesh_alignment.LEGACY_A4_MIN_COVERAGE), ...
                'rule', 'every view >= 95 % of all sparse observations'));
            meas.summary = sprintf(['tissue observations inside the projected mesh: median view %.0f %%, worst view %.0f %% ' ...
                '(PASS median >= %.0f %% and every view >= %.0f %%, FAIL median < %.0f %%)'], 100 * med, 100 * min(c), ...
                100 * L.a4_pass_median, 100 * L.a4_pass_min, 100 * L.a4_fail_median);
        end

        function [verdict, meas] = gate_a6(mxyz, mfaces, images_bin, mask_root, L)
            % A6: the mesh drawn into every image with a tissue mask
            % (filter_cameras: pinhole cameras with a mask of their size)
            if isempty(mask_root) || ~isfolder(mask_root)
                verdict = 'WARN';
                meas = struct('n_images', 0, 'summary', ['not measured: there are no tissue masks, so a mesh ' ...
                    'that is too small or shifted is not caught by its outline']);
                return;
            end
            [cams0, imgs0] = rabbit_mesh_cleanup.read_colmap_model(images_bin);
            % With the band, each camera carries its mask's field band: the
            % still field edges over its view's frames, as in the mesh step
            [fc, band_rec] = rabbit_mesh_cleanup.filter_cameras(cams0, imgs0, mask_root, L.field_band_px);
            if isempty(fc)
                verdict = 'WARN';
                meas = struct('n_images', 0, 'summary', sprintf(['not measured: no mask in %s fits a pinhole ' ...
                    'camera of the model'], mask_root));
                return;
            end
            n = numel(fc);
            edge = nan(n, 1);
            inside = nan(n, 1);
            covered = nan(n, 1);
            iou = nan(n, 1);
            for i = 1:n
                Xc = mxyz * fc(i).R' + fc(i).t(:)';
                z = Xc(:, 3);
                uv = [fc(i).f(1) * Xc(:, 1) ./ z + fc(i).c(1), fc(i).f(2) * Xc(:, 2) ./ z + fc(i).c(2)];
                uv(z <= 0, :) = NaN;
                sil = rabbit_mesh_alignment.mesh_silhouette(uv, mfaces, fc(i).height, fc(i).width);
                s = rabbit_mesh_alignment.silhouette_scores(sil, fc(i).mask, L.a6_edge_px, fc(i).band);
                edge(i) = s.edge;
                inside(i) = s.inside;
                covered(i) = s.covered;
                iou(i) = s.iou;
            end
            e = median(edge, 'omitnan');
            ins = median(inside, 'omitnan');
            if ~isfinite(e) || e < L.a6_fail_edge
                verdict = 'FAIL';
            elseif e >= L.a6_pass_edge && ins >= L.a6_pass_inside
                verdict = 'PASS';
            else
                verdict = 'WARN';
            end
            meas = struct('n_images', n, 'edge_share_median', e, 'edge_share_p10', prctile(edge, 10), ...
                'inside_median', ins, 'covered_median', median(covered, 'omitnan'), ...
                'iou_median', median(iou, 'omitnan'), 'mask_root', mask_root, 'field_band_px', L.field_band_px);
            if L.field_band_px > 0
                meas.field_band_sides = rabbit_mesh_cleanup.band_sides_text(band_rec);
                band_txt = sprintf([' (the field band left out: mask edges within %g px of the image border ' ...
                    'that stay still over the frames)'], L.field_band_px);
            else
                band_txt = '';
            end
            meas.summary = sprintf(['%.0f %% of the mesh outline lies within %g px of the tissue outline (median of %d ' ...
                'images; PASS >= %.0f %%, FAIL < %.0f %%); %.1f %% of the mesh silhouette is on the tissue%s; the mesh ' ...
                'covers %.0f %% of the tissue'], 100 * e, L.a6_edge_px, n, 100 * L.a6_pass_edge, 100 * L.a6_fail_edge, ...
                100 * ins, band_txt, 100 * meas.covered_median);
        end

        function inside = in_triangles(P, V, F)
            %IN_TRIANGLES Point-in-triangle (barycentric sign test) for
            %   P (Mx2), V (Nx2), F (Kx3, 1-based). A point on an edge or
            %   vertex counts as inside (>= 0 signs).
            M = size(P, 1);
            K = size(F, 1);
            inside = false(M, 1);
            for k = 1:K
                a = V(F(k, 1), :);
                b = V(F(k, 2), :);
                c = V(F(k, 3), :);
                d1 = rabbit_mesh_alignment.cross2(b - a, P - a);
                d2 = rabbit_mesh_alignment.cross2(c - b, P - b);
                d3 = rabbit_mesh_alignment.cross2(a - c, P - c);
                has_neg = (d1 < 0) | (d2 < 0) | (d3 < 0);
                has_pos = (d1 > 0) | (d2 > 0) | (d3 > 0);
                inside = inside | ~(has_neg & has_pos);
            end
        end

        function c = cross2(u, v)
            c = u(:, 1) .* v(:, 2) - u(:, 2) .* v(:, 1);
        end

        % =============================================================
        % Camera model: COLMAP standard world->camera projection
        % (X_cam = R*X + tvec; intrinsics + distortion per model).
        % Pinhole models are exact (the RHYTHM camera conversion in
        % rabbit_rhythm_reproject reproduces COLMAP pinhole pixels to
        % ~3e-14 px).
        % =============================================================

        function uv = project_point(p, im, cam)
            R = rabbit_mesh_cleanup.qvec2rot(im.qvec);
            Xc = R * p(:) + im.tvec(:);
            x = Xc(1); y = Xc(2); z = Xc(3);
            if z <= 0
                uv = [NaN; NaN];
                return;
            end
            prm = cam.params;
            switch cam.model
                case 'SIMPLE_PINHOLE'
                    f = prm(1); cx = prm(2); cy = prm(3);
                    u = f * x / z + cx; v = f * y / z + cy;
                case 'PINHOLE'
                    fx = prm(1); fy = prm(2); cx = prm(3); cy = prm(4);
                    u = fx * x / z + cx; v = fy * y / z + cy;
                case 'SIMPLE_RADIAL'
                    f = prm(1); cx = prm(2); cy = prm(3); k = prm(4);
                    xn = x / z; yn = y / z; r2 = xn^2 + yn^2;
                    fac = 1 + k * r2;
                    u = f * fac * xn + cx; v = f * fac * yn + cy;
                case 'RADIAL'
                    f = prm(1); cx = prm(2); cy = prm(3); k1 = prm(4); k2 = prm(5);
                    xn = x / z; yn = y / z; r2 = xn^2 + yn^2;
                    fac = 1 + k1 * r2 + k2 * r2^2;
                    u = f * fac * xn + cx; v = f * fac * yn + cy;
                case 'OPENCV'
                    fx = prm(1); fy = prm(2); cx = prm(3); cy = prm(4);
                    k1 = prm(5); k2 = prm(6); p1 = prm(7); p2 = prm(8);
                    xn = x / z; yn = y / z; r2 = xn^2 + yn^2;
                    xd = xn * (1 + k1 * r2 + k2 * r2^2) + 2 * p1 * xn * yn + p2 * (r2 + 2 * xn^2);
                    yd = yn * (1 + k1 * r2 + k2 * r2^2) + p1 * (r2 + 2 * yn^2) + 2 * p2 * xn * yn;
                    u = fx * xd + cx; v = fy * yd + cy;
                case 'OPENCV_FISHEYE'
                    fx = prm(1); fy = prm(2); cx = prm(3); cy = prm(4);
                    k1 = prm(5); k2 = prm(6); k3 = prm(7); k4 = prm(8);
                    xn = x / z; yn = y / z; r = sqrt(xn^2 + yn^2);
                    th = atan(r);
                    thd = th * (1 + k1 * th^2 + k2 * th^4 + k3 * th^6 + k4 * th^8);
                    if r < 1e-12, fac = 1; else, fac = thd / r; end
                    u = fx * fac * xn + cx; v = fy * fac * yn + cy;
                case 'FULL_OPENCV'
                    fx = prm(1); fy = prm(2); cx = prm(3); cy = prm(4);
                    k1 = prm(5); k2 = prm(6); p1 = prm(7); p2 = prm(8); k3 = prm(9); k4 = prm(10);
                    xn = x / z; yn = y / z; r2 = xn^2 + yn^2; r4 = r2^2; r6 = r4 * r2;
                    xd = xn * (1 + k1 * r2 + k2 * r4 + k3 * r6) + 2 * p1 * xn * yn + p2 * (r2 + 2 * xn^2);
                    yd = yn * (1 + k1 * r2 + k2 * r4 + k3 * r6) + p1 * (r2 + 2 * yn^2) + 2 * p2 * xn * yn;
                    u = fx * xd + cx; v = fy * yd + cy;
                case 'FOV'
                    fx = prm(1); fy = prm(2); cx = prm(3); cy = prm(4); w = prm(5);
                    xn = x / z; yn = y / z; r = sqrt(xn^2 + yn^2);
                    if abs(w) < 1e-12 || r < 1e-12
                        fac = 1;
                    else
                        fac = atan(2 * r * tan(w / 2)) / (r * w);
                    end
                    u = fx * fac * xn + cx; v = fy * fac * yn + cy;
                case 'SIMPLE_RADIAL_FISHEYE'
                    f = prm(1); cx = prm(2); cy = prm(3); k = prm(4);
                    xn = x / z; yn = y / z; r = sqrt(xn^2 + yn^2); th = atan(r);
                    thd = th * (1 + k * th^2);
                    if r < 1e-12, fac = 1; else, fac = thd / r; end
                    u = f * fac * xn + cx; v = f * fac * yn + cy;
                case 'RADIAL_FISHEYE'
                    f = prm(1); cx = prm(2); cy = prm(3); k1 = prm(4); k2 = prm(5);
                    xn = x / z; yn = y / z; r = sqrt(xn^2 + yn^2); th = atan(r);
                    thd = th * (1 + k1 * th^2 + k2 * th^4);
                    if r < 1e-12, fac = 1; else, fac = thd / r; end
                    u = f * fac * xn + cx; v = f * fac * yn + cy;
                case 'THIN_PRISM_FISHEYE'
                    fx = prm(1); fy = prm(2); cx = prm(3); cy = prm(4);
                    k1 = prm(5); k2 = prm(6); p1 = prm(7); p2 = prm(8); k3 = prm(9); k4 = prm(10);
                    s1 = prm(11); s2 = prm(12);
                    xn = x / z; yn = y / z; r = sqrt(xn^2 + yn^2); th = atan(r);
                    thd = th * (1 + k1 * th^2 + k2 * th^4 + k3 * th^6 + k4 * th^8);
                    if r < 1e-12, fac = 1; else, fac = thd / r; end
                    xd = fac * xn + s1 * r^2 + s2 * r^4;
                    yd = fac * yn;
                    u = fx * xd + cx; v = fy * yd + cy;
                otherwise
                    error('analyse_om:Reconstruction:Alignment', 'Unsupported camera model ''%s''.', cam.model);
            end
            uv = [u; v];
        end

        function uv = project_points(P, im, cam)
            % project_point for many points (rows of P): vectorised for the
            % pinhole models (the undistorted model is pinhole), one call
            % per point for the others; NaN behind the camera
            R = rabbit_mesh_cleanup.qvec2rot(im.qvec);
            Xc = P * R' + im.tvec(:)';
            z = Xc(:, 3);
            prm = cam.params;
            switch cam.model
                case 'SIMPLE_PINHOLE'
                    uv = [prm(1) * Xc(:, 1) ./ z + prm(2), prm(1) * Xc(:, 2) ./ z + prm(3)];
                case 'PINHOLE'
                    uv = [prm(1) * Xc(:, 1) ./ z + prm(3), prm(2) * Xc(:, 2) ./ z + prm(4)];
                otherwise
                    uv = zeros(size(P, 1), 2);
                    for k = 1:size(P, 1)
                        uv(k, :) = rabbit_mesh_alignment.project_point(P(k, :), im, cam)';
                    end
            end
            uv(z <= 0, :) = NaN;
        end

        % =============================================================
        % Mesh silhouettes against the tissue masks (A6).
        % =============================================================

        function S = mesh_silhouette(uv, F, h, w)
            %MESH_SILHOUETTE Pixels of an h x w image covered by the projected mesh
            %   uv: N x 2 COLMAP pixel coordinates of the vertices (NaN
            %   behind the camera); F: K x 3 faces (1-based). Pixel (r, c)
            %   is covered when its centre, (c - 0.5, r - 0.5) in COLMAP
            %   coordinates (pixel k covering [k-1, k)), lies in a projected
            %   face (edges and corners count). Faces with a vertex behind
            %   the camera are left out.
            S = false(h, w);
            okv = all(isfinite(uv), 2);
            F = F(okv(F(:, 1)) & okv(F(:, 2)) & okv(F(:, 3)), :);
            if isempty(F), return; end
            Ax = uv(F(:, 1), 1); Ay = uv(F(:, 1), 2);
            Bx = uv(F(:, 2), 1); By = uv(F(:, 2), 2);
            Cx = uv(F(:, 3), 1); Cy = uv(F(:, 3), 2);
            % Pixel-centre range of each face's bounding box
            c0 = max(1, ceil(min([Ax Bx Cx], [], 2) + 0.5));
            c1 = min(w, floor(max([Ax Bx Cx], [], 2) + 0.5));
            r0 = max(1, ceil(min([Ay By Cy], [], 2) + 0.5));
            r1 = min(h, floor(max([Ay By Cy], [], 2) + 0.5));
            use = c1 >= c0 & r1 >= r0;
            nc = c1 - c0 + 1;
            nr = r1 - r0 + 1;
            % Faces of a fine mesh cover a few pixels: test them together
            % on a small grid of candidate centres; larger faces one by one
            small = use & nc <= 6 & nr <= 6;
            idx = find(small);
            if ~isempty(idx)
                [dx, dy] = meshgrid(0:5, 0:5);
                dx = dx(:)'; dy = dy(:)';
                cc = c0(idx) + dx;   % faces x 36 candidate columns
                rr = r0(idx) + dy;
                valid = dx <= nc(idx) - 1 & dy <= nr(idx) - 1;
                in = valid & rabbit_mesh_alignment.centre_in_face(cc - 0.5, rr - 0.5, ...
                    Ax(idx), Ay(idx), Bx(idx), By(idx), Cx(idx), Cy(idx));
                S(sub2ind([h w], rr(in), cc(in))) = true;
            end
            for k = find(use & ~small)'
                [cc, rr] = meshgrid(c0(k):c1(k), r0(k):r1(k));
                in = rabbit_mesh_alignment.centre_in_face(cc(:) - 0.5, rr(:) - 0.5, ...
                    Ax(k), Ay(k), Bx(k), By(k), Cx(k), Cy(k));
                S(sub2ind([h w], rr(in), cc(in))) = true;
            end
        end

        function in = centre_in_face(px, py, ax, ay, bx, by, cx, cy)
            % Sign test of the three edges (both orientations of the face)
            d1 = (bx - ax) .* (py - ay) - (by - ay) .* (px - ax);
            d2 = (cx - bx) .* (py - by) - (cy - by) .* (px - bx);
            d3 = (ax - cx) .* (py - cy) - (ay - cy) .* (px - cx);
            in = ~((d1 < 0 | d2 < 0 | d3 < 0) & (d1 > 0 | d2 > 0 | d3 > 0));
        end

        function s = silhouette_scores(sil, mask, edge_px, band)
            %SILHOUETTE_SCORES How well a mesh silhouette fits a tissue mask
            %   iou       |S and M| / |S or M|
            %   inside    |S and M| / |S| (share of the silhouette on tissue);
            %             with a field band B (optional, same size, see
            %             rabbit_sfm_build.field_band) |S and M| / |S not B|:
            %             silhouette pixels in the band are neither on nor
            %             off the tissue
            %   covered   |S and M| / |M| (share of the tissue under the mesh)
            %   edge      share of the silhouette's outline (pixels not on
            %             the image border) within edge_px of the mask's
            %             outline. A mesh that is too small, too large,
            %             shifted or mirrored moves its outline off the
            %             mask's; a mesh that only stops short of part of
            %             the tissue keeps the rest of its outline on it.
            s = struct('iou', NaN, 'inside', NaN, 'covered', NaN, 'edge', NaN);
            if nargin < 4 || isempty(band), band = false(size(sil)); end
            ns = nnz(sil);
            nm = nnz(mask);
            if ns == 0 || nm == 0, return; end
            both = nnz(sil & mask);
            s.iou = both / nnz(sil | mask);
            n_judged = nnz(sil & ~band);   % the band pixels abstain (mask and band are disjoint)
            if n_judged > 0, s.inside = both / n_judged; end
            s.covered = both / nm;
            ps = bwperim(sil, 8);
            ps([1 end], :) = false;
            ps(:, [1 end]) = false;
            if any(ps(:))
                d = bwdist(bwperim(mask, 8));
                s.edge = mean(d(ps) <= edge_px);
            end
        end

        % =============================================================
        % Helpers.
        % =============================================================

        function v = opt_str(opts, field, default)
            if isfield(opts, field) && ~isempty(opts.(field))
                v = opts.(field);
            else
                v = default;
            end
        end

        function v = opt_num(opts, field, default)
            if isfield(opts, field) && ~isempty(opts.(field))
                v = opts.(field);
            else
                v = default;
            end
        end

        function txt = check_names(codes)
            % Plain names of the alignment checks, for messages the user reads
            names = struct('A1', 'projection set-up', 'A2', 'projection error', ...
                'A3', 'camera geometry', 'A4', 'silhouette coverage', ...
                'A5', 'no registration step', 'A6', 'mesh outline');
            parts = cell(1, numel(codes));
            for k = 1:numel(codes)
                if isfield(names, codes{k})
                    parts{k} = names.(codes{k});
                else
                    parts{k} = codes{k};
                end
            end
            txt = strjoin(parts, '; ');
        end
    end
end
