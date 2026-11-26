classdef rabbit_mesh_cleanup
    %% Turn the fused COLMAP cloud into a cleaned mesh for RHYTHM
    % Collin Snitchler
    % 09.09.2026
    % Builds a RHYTHM-compatible mesh from the dense cloud and measures
    % the mesh gates M1-M10 on it: M1 (finite coordinates), M2 (outlier
    % removal), M3 (unit normals), M4 (normal orientation), M5 (connected
    % components), M6 (degenerate faces), M7 (surface deviation), M8
    % (boundary and holes), M9 (visibility check), M10 (point spacing).
    % Normals are oriented by COLMAP camera visibility. The target is an
    % open epicardial shell (M8). Native COLMAP units are kept: no
    % transform is applied and the output PLY has the input units.
    %
    % Citations: alpha shapes (Edelsbrunner & Muecke 1994), outlier
    % removal (Rusu et al. 2008), RHYTHM (Gloschat et al. 2018, PMID
    % 29440763) and Laughner et al. 2012 (PMID 22821993) for the DIRECT
    % visibility rule of M9.
    %
    % Usage:
    %   r = rabbit_mesh_cleanup.run(fused_ply, vis_ply, images_bin, opts)
    %   r.ok, r.err, r.gates (struct), r.warnings (cell), r.artifacts
    %   (struct array path/sha256), r.out_ply, r.gates_json, r.silhouette
    %   (membrane fit: whether the silhouette cap was used, and why not)
    %
    % opts fields (all optional):
    %   out_ply      output mesh PLY (default: <fused dir>/mesh-cleanup.ply)
    %   out_gates    gates JSON (default: <fused dir>/mesh-cleanup-gates.json)
    %   out_mask     removal mask .mat (default: <fused dir>/mesh-cleanup-removal-mask.mat):
    %                keep (the outlier step's mask over the cloud it judged);
    %                for the membrane fit also silhouette_keep (the silhouette
    %                filter's mask over the dense cloud) and keep_in_fused
    %                (both together, over the dense cloud)
    %   k_nn         nearest-neighbour k (default 16)
    %   z_thresh     outlier z threshold (default 3.0)
    %   alpha_mults  alpha multipliers around s50 (default [2 4 8])
    %   sample_n     fixed-sample size for M7 (default 5000)
    %   seed         RNG seed for deterministic sampling (default 42)
    %   mesh_method  'membrane' (default): smooth membrane fit to the dense
    %                cloud (rabbit_membrane_fit, a port of the author's Python
    %                membrane fit); 'alpha': the alpha-complex sweep below
    %   cloud_source 'fused' (default): the COLMAP fused cloud; 'apd': the
    %                APDe-MVS cloud APD.ply (membrane method only)
    %   apd_ply      APD.ply path (default: <run>/stages/apde_scene_prep/
    %                scene/APD/APD.ply, <run> = the folder above outputs)
    %   mask_root    folder of per-image silhouette masks:
    %                <mask_root>/<image name>.png (COLMAP layout) or
    %                <mask_root>/<file name>.png (the flat folder written by
    %                rabbit_segmentation_masks); empty = no silhouette cap
    %   membrane     struct of membrane-fit settings (see rabbit_membrane_fit)
    %   silhouette_filter_min_inside  (membrane method) before the gates,
    %                keep a cloud point only when it projects inside the
    %                mask in at least this fraction of the images it lands
    %                in (rabbit_sfm_build.silhouette_filter; the rabbit SfM
    %                study used 0.9 with the tissue silhouettes of the
    %                sparse model step); 0 (default) = no filter
    %   silhouette_frames  (membrane method) silhouette cameras of only this
    %                many evenly spaced frames (all views of each), as the
    %                study did (4 frames x 4 views); 0 (default) = all
    %                images with a mask
    %   silhouette_cap  (membrane method) 1 (default): the masks that pass
    %                the agreement check hold the membrane inside them; 0:
    %                no cap, the check is still run and recorded
    %   field_band_px  (membrane method) width of the field band in pixels
    %                (rabbit_sfm_build.field_band): where a mask edge lies
    %                within this distance of the image border, the pixels
    %                between it and the border neither keep nor reject a
    %                point in the silhouette filter, do not limit the
    %                membrane (no silhouette cap there) and are left out of
    %                the cap's mask agreement check; 0 (default) = no band
    %   single_open_edge  (membrane method) 1: a second large unsupported
    %                region that lies closer to the open edge, along the
    %                surface, than its own size is cut together with it, so
    %                a strip of support leaves no hole (rabbit_membrane_fit,
    %                single_open_edge); a region further away is cut on its
    %                own and shows as a hole (M8); 0 (default) = every large
    %                unsupported region is cut on its own
    %
    % The method that ran is recorded in the gates JSON (mesh_method,
    % cloud_source). Both methods write the same outputs.
    %
    % On failure: any gate miss returns ok=false with the failed gate and
    % measured values; the output mesh and gates JSON are still written
    % so the failed outputs are kept. No silent retry, no silent rescale.
    %
    % Gate codes M1-M10: plain names for user messages in check_names.
    %
    % Section map (search for the quoted line; line numbers move)
    %   Alpha-shape method ..... "function r = run(fused_ply"
    %   Membrane method ........ "function r = run_membrane("
    %   Silhouette cameras ..... "= membrane_cameras("
    %   Membrane gates ......... "= membrane_verdicts("
    %   M4 fixture ............. "= mesh_normal_fixture("
    %   PLY read / write ....... "= read_ply_27("
    %   Alpha-shape gates ...... "= alpha_surface("
    %   RHYTHM visibility (M9) . "= direct_visibility_gate("
    %   Check names ............ "function txt = check_names("
    %   COLMAP model ........... "= read_colmap_model("

    properties (Constant)
        MIN_ANGLE_DIRECT = 95;  % RHYTHM dataProjection02 minangleDIRECT
        MIN_EDGE_DIRECT = 0.9;  % RHYTHM dataProjection02 minedgeDIRECT
        EDGE_FILT_VAL = 16;     % RHYTHM dataProjection02 edgefiltval
        MIN_M4_WITHIN_10DEG = 0.98;  % membrane M4 FAIL limit (membrane_verdicts)
        MIN_VERTEX_DIRECT = 0.75;    % membrane M9 FAIL limit (membrane_verdicts)
        MIN_VIEW_SILHOUETTE_IOU = 0.6;  % view_silhouette_check: a view's masks fit the mesh below this
    end

    methods (Static)

        function r = run(fused_ply, vis_ply, images_bin, opts)
            %RUN Build the mesh and measure the gates M1-M10.
            if nargin < 4, opts = struct(); end
            r = struct();
            r.ok = false;
            r.err = '';
            r.gates = struct();
            r.warnings = {};
            r.silhouette = [];
            r.silhouette_filter = [];
            r.artifacts = struct('path', {}, 'sha256', {});
            r.out_ply = '';
            r.gates_json = '';

            % ---- inputs ----
            if ~exist(fused_ply, 'file')
                r.err = sprintf('The dense cloud is missing: %s', fused_ply);
                return;
            end
            if ~exist(vis_ply, 'file')
                r.err = sprintf('The camera visibility file is missing: %s. Run stereo fusion again to write it.', vis_ply);
                return;
            end
            if ~exist(images_bin, 'file')
                r.err = sprintf('The camera poses (images.bin) are missing: %s. Run the undistortion step again.', images_bin);
                return;
            end
            k_nn = rabbit_mesh_cleanup.opt_num(opts, 'k_nn', 16);
            z_thresh = rabbit_mesh_cleanup.opt_num(opts, 'z_thresh', 3.0);
            alpha_mults = rabbit_mesh_cleanup.opt_num(opts, 'alpha_mults', []);
            sample_n = rabbit_mesh_cleanup.opt_num(opts, 'sample_n', 5000);
            seed = rabbit_mesh_cleanup.opt_num(opts, 'seed', 42);
            out_dir = fileparts(fused_ply);
            out_ply = rabbit_mesh_cleanup.opt_str(opts, 'out_ply', fullfile(out_dir, 'mesh-cleanup.ply'));
            out_gates = rabbit_mesh_cleanup.opt_str(opts, 'out_gates', fullfile(out_dir, 'mesh-cleanup-gates.json'));
            out_mask = rabbit_mesh_cleanup.opt_str(opts, 'out_mask', fullfile(out_dir, 'mesh-cleanup-removal-mask.mat'));
            r.out_ply = out_ply;
            mesh_method = lower(char(rabbit_mesh_cleanup.opt_str(opts, 'mesh_method', 'membrane')));
            cloud_source = lower(char(rabbit_mesh_cleanup.opt_str(opts, 'cloud_source', 'fused')));
            r.mesh_method = mesh_method;
            r.cloud_source = cloud_source;
            if ~any(strcmp(mesh_method, {'membrane', 'alpha'}))
                r.err = sprintf('Unknown mesh method ''%s'' (membrane or alpha).', mesh_method);
                return;
            end
            if ~any(strcmp(cloud_source, {'fused', 'apd'}))
                r.err = sprintf('Unknown cloud source ''%s'' (fused or apd).', cloud_source);
                return;
            end
            if strcmp(mesh_method, 'alpha') && strcmp(cloud_source, 'apd')
                r.err = 'The alpha-shape mesh needs the COLMAP dense cloud (it uses which cameras saw each point); choose the COLMAP cloud.';
                return;
            end

            % ---- M4 fixture: must PASS before any real-data mesh ----
            [fx_ok, fx_msg] = rabbit_mesh_cleanup.mesh_normal_fixture();
            if ~fx_ok
                r.err = sprintf('The built-in check of the normal orientation failed: %s', fx_msg);
                return;
            end

            % ---- membrane fit (default method) ----
            if strcmp(mesh_method, 'membrane')
                r = rabbit_mesh_cleanup.run_membrane(r, fused_ply, vis_ply, images_bin, opts, ...
                    out_ply, out_gates, out_mask, k_nn, z_thresh, sample_n, seed);
                return;
            end

            % ---- read the fused cloud (byte-aligned 27-byte records) ----
            [xyz, nrm, rgb, nv] = rabbit_mesh_cleanup.read_ply_27(fused_ply);
            if nv == 0
                r.err = 'The dense cloud has no points.';
                return;
            end

            % ---- M1: finite coordinates (0 NaN/Inf; no silent drops) ----
            finite_ok = all(isfinite(xyz(:))) && all(isfinite(nrm(:)));
            n_nonfinite = sum(~isfinite(xyz(:))) + sum(~isfinite(nrm(:)));
            r.gates.M1 = struct('pass', finite_ok, ...
                'measured', struct('n_vertices', nv, 'n_nonfinite', n_nonfinite));
            if ~finite_ok
                r.err = sprintf('The dense cloud has %d coordinates that are not numbers; nothing was dropped silently.', n_nonfinite);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, []);
                return;
            end

            % ---- M2: statistical outlier removal (k=16, z>3.0) ----
            [keep, m2_stats] = rabbit_mesh_cleanup.outlier_mask(xyz, k_nn, z_thresh);
            retention = sum(keep) / numel(keep);
            m2_pass = retention >= 0.90 && retention <= 1.00;
            r.gates.M2 = struct('pass', m2_pass, 'measured', struct( ...
                'n_source', numel(keep), 'n_outliers', sum(~keep), ...
                'retention', retention, 'k', k_nn, 'z', z_thresh, ...
                'mean_nn_mean', m2_stats.m, 'mean_nn_std', m2_stats.s, ...
                'threshold', m2_stats.thresh));
            if ~m2_pass
                r.err = sprintf('The outlier filter would keep only %.1f %% of the dense cloud (at least 90 %% expected).', 100 * retention);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, keep);
                return;
            end
            work = xyz(keep, :);
            nrm_w = nrm(keep, :);
            rgb_w = rgb(keep, :);

            % ---- M10: spacing ratios (source vs work, k=16 16th-NN) ----
            [s50, s95] = rabbit_mesh_cleanup.spacing_stats(xyz, k_nn);
            [s50w, s95w] = rabbit_mesh_cleanup.spacing_stats(work, k_nn);
            m10_pass = (s50w / s50) >= 0.80 && (s50w / s50) <= 1.25 && (s95w / s95) <= 1.50;
            r.gates.M10 = struct('pass', m10_pass, 'measured', struct( ...
                's50', s50, 's95', s95, 's50_work', s50w, 's95_work', s95w, ...
                's50_ratio', s50w / s50, 's95_ratio', s95w / s95, 'k', k_nn));
            if ~m10_pass
                r.err = sprintf('Removing outliers changed the point spacing too much (median ratio %.2f, 95th percentile ratio %.2f).', s50w / s50, s95w / s95);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, keep);
                return;
            end

            % ---- M3: normals unit-length (>= 99% in [0.99, 1.01]) ----
            nlen = sqrt(sum(nrm_w .* nrm_w, 2));
            unit_frac = mean(nlen >= 0.99 & nlen <= 1.01);
            m3_pass = unit_frac >= 0.99;
            r.gates.M3 = struct('pass', m3_pass, 'measured', struct( ...
                'unit_fraction', unit_frac, 'n_normals', size(nrm_w, 1)));
            if ~m3_pass
                r.err = sprintf('Only %.1f %% of the cloud normals have unit length (at least 99 %% expected).', 100 * unit_frac);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, keep);
                return;
            end

            % ---- visibility association (.vis + camera centres) ----
            [vis, vis_ok, vis_err] = rabbit_mesh_cleanup.read_vis(vis_ply);
            if ~vis_ok
                r.err = vis_err;
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, keep);
                return;
            end
            [cameras, images, cam_ok, cam_err] = rabbit_mesh_cleanup.read_colmap_model(images_bin);
            if ~cam_ok
                r.err = cam_err;
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, keep);
                return;
            end
            centers = rabbit_mesh_cleanup.camera_centres(images);
            lookns = rabbit_mesh_cleanup.camera_lookns(images);

            % ---- alpha-shape surface sweep ----
            % The closed alpha shape is trimmed to the camera-visible
            % shell (M8: the target is an open epicardial shell; the
            % unsupported back side of a closed surface is invented
            % geometry). The first candidate whose trimmed shell passes
            % M4-M8 is kept, and M9 is measured on it.
            % Alpha scale: on a thin shell the Delaunay tetrahedra have
            % circumradii at the shell scale (median ~654*s50 on the
            % rabbit cloud), so spacing-scale alphas give an empty
            % complex. alpha is therefore prctile(R, p) of the
            % tetrahedron circumradii R for p in the sweep set.
            % alpha_mults (old spacing-scale multipliers) is accepted but
            % ignored when alpha_percentiles is given.
            alpha_percentiles = rabbit_mesh_cleanup.opt_num(opts, 'alpha_percentiles', [50 60 70 80 90 95]);
            DT0 = delaunayTriangulation(work);
            T0 = DT0.ConnectivityList;
            nt0 = size(T0, 1);
            R0 = zeros(nt0, 1);
            for t = 1:nt0
                p1 = work(T0(t, 1), :); p2 = work(T0(t, 2), :);
                p3 = work(T0(t, 3), :); p4 = work(T0(t, 4), :);
                A = 2 * [p2 - p1; p3 - p1; p4 - p1];
                b = [p2 * p2' - p1 * p1'; p3 * p3' - p1 * p1'; p4 * p4' - p1 * p1'];
                c = A \ b;
                R0(t) = norm(c - p1);
            end
            r_gates = struct('n_tetrahedra', nt0, 'R_median', median(R0), ...
                'R_p95', prctile(R0, 95), 'R_min', min(R0), 'R_max', max(R0));
            best = [];
            sweep = struct('alpha_mult', {}, 'alpha', {}, 'faces', {}, ...
                'n_faces', {}, 'n_regions', {}, 'nrm_o', {}, ...
                'm4', {}, 'm5', {}, 'm6', {}, 'm7', {}, 'm8', {});
            for a = 1:numel(alpha_percentiles)
                p = alpha_percentiles(a);
                alpha = prctile(R0, p);
                [faces, comps, shp_stats] = rabbit_mesh_cleanup.alpha_surface(work, alpha);
                if isempty(faces)
                    sweep(a) = struct('alpha_mult', p, 'alpha', alpha, 'faces', [], ...
                        'n_faces', 0, 'n_regions', shp_stats.n_regions, 'nrm_o', [], ...
                        'm4', struct('pass', false, 'measured', struct('reason', 'no surface')), ...
                        'm5', struct('pass', false, 'measured', struct('reason', 'no surface')), ...
                        'm6', struct('pass', false, 'measured', struct('reason', 'no surface')), ...
                        'm7', struct('pass', false, 'measured', struct('reason', 'no surface')), ...
                        'm8', struct('pass', false, 'measured', struct('reason', 'no surface')));
                    continue;
                end
                % M4: orient normals per surface region (visibility).
                [nrm_o, orient_stats] = rabbit_mesh_cleanup.orient_normals( ...
                    work, nrm_w, vis(keep), centers, comps, k_nn);
                m4_pass = orient_stats.agreement >= 0.99;
                m4 = struct('pass', m4_pass, 'measured', struct( ...
                    'agreement', orient_stats.agreement, 'n_regions', orient_stats.n_regions, ...
                    'positive_fraction', orient_stats.positive_fraction));
                % M5: connected components (one primary; strays < 1%).
                [m5_pass, m5_meas, faces5, ~] = rabbit_mesh_cleanup.component_gate(faces, comps, work);
                m5 = struct('pass', m5_pass, 'measured', m5_meas);
                % M6: degenerate faces (zero-area <= 0.1%; duplicates removed).
                [m6_pass, m6_meas, faces6] = rabbit_mesh_cleanup.degenerate_gate(faces5, work);
                m6 = struct('pass', m6_pass, 'measured', m6_meas);
                % Trim to the camera-visible shell (M8 open-shell target):
                % keep faces whose oriented normal is within 95 deg of at
                % least one camera that imaged the face's vertices.
                [faces_v, ~] = rabbit_mesh_cleanup.trim_visible_shell( ...
                    work, nrm_o, faces6, vis(keep), lookns);
                % M8: boundary edges + holes on the TRIMMED shell.
                [m8_pass, m8_meas] = rabbit_mesh_cleanup.boundary_gate(faces_v, work);
                m8 = struct('pass', m8_pass, 'measured', m8_meas);
                % M7: bidirectional deviation on fixed samples (trimmed shell).
                [m7_pass, m7_meas] = rabbit_mesh_cleanup.deviation_gate(work, faces_v, s50, sample_n, seed);
                m7 = struct('pass', m7_pass, 'measured', m7_meas);
                sweep(a) = struct('alpha_mult', p, 'alpha', alpha, 'faces', faces_v, ...
                    'n_faces', size(faces_v, 1), 'n_regions', shp_stats.n_regions, 'nrm_o', nrm_o, ...
                    'm4', m4, 'm5', m5, 'm6', m6, 'm7', m7, 'm8', m8);
                if m4_pass && m5_pass && m6_pass && m7_pass && m8_pass
                    best = sweep(a);
                    break;
                end
            end
            r.gates.sweep = sweep;
            r.gates.alpha_scale = r_gates;
            if isempty(best)
                % No candidate passed M4-M8: still measure M9 (RHYTHM
                % DIRECT, direct_visibility_gate) on the best candidate's
                % trimmed shell so the failure record has an M9 value.
                % Best = most M4-M8 gates passed; ties go to the lowest
                % M7 p95 cloud->mesh deviation.
                b9 = rabbit_mesh_cleanup.best_candidate(sweep);
                if ~isempty(b9)
                    [m9_pass, m9_meas] = rabbit_mesh_cleanup.direct_visibility_gate( ...
                        work, b9.nrm_o, b9.faces, cameras, images, vis(keep), lookns);
                    r.gates.M9 = struct('pass', m9_pass, 'measured', m9_meas, ...
                        'criterion', 'langle >= 95 AND ledge >= 0.9 (RHYTHM dataProjection02; Gloschat 2018 PMID 29440763; Laughner 2012 PMID 22821993)', ...
                        'candidate', struct('alpha_mult', b9.alpha_mult, 'alpha', b9.alpha, 'n_faces', b9.n_faces));
                end
                r.err = sprintf(['Alpha shape: none of the %d tried surfaces passed the surface checks; ' ...
                    'the closest one is described in mesh-cleanup-gates.json and no mesh was written.'], numel(sweep));
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, keep);
                return;
            end
            r.gates.M4 = best.m4;
            r.gates.M5 = best.m5;
            r.gates.M6 = best.m6;
            r.gates.M7 = best.m7;
            r.gates.M8 = best.m8;
            r.gates.alpha = struct('alpha_mult', best.alpha_mult, 'alpha', best.alpha, ...
                'n_faces', best.n_faces, 'n_regions', best.n_regions);

            % ---- M9: RHYTHM DIRECT visibility (langle >= 95 and ledge >= 0.9) ----
            faces_final = best.faces;
            nrm_o = best.nrm_o;
            [m9_pass, m9_meas] = rabbit_mesh_cleanup.direct_visibility_gate( ...
                work, nrm_o, faces_final, cameras, images, vis(keep), lookns);
            r.gates.M9 = struct('pass', m9_pass, 'measured', m9_meas);

            % ---- final verdict ----
            gate_names = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'M10'};
            all_pass = true;
            for g = 1:numel(gate_names)
                if ~r.gates.(gate_names{g}).pass, all_pass = false; end
            end
            r.ok = all_pass;
            if ~all_pass
                failed = gate_names(~arrayfun(@(g) r.gates.(g).pass, gate_names));
                r.err = sprintf(['Alpha shape: the mesh was written for review, but these checks failed: %s. ' ...
                    'Details are in mesh-cleanup-gates.json.'], rabbit_mesh_cleanup.check_names(failed));
            end

            % ---- write the output mesh (RHYTHM-compatible PLY) ----
            % Face winding: orient each face so its normal agrees with the
            % oriented vertex normals (self-consistent outward mesh).
            faces_final = rabbit_mesh_cleanup.orient_faces(work, nrm_o, faces_final);
            rabbit_mesh_cleanup.write_ply(out_ply, work, nrm_o, rgb_w, faces_final);
            % Removal mask (M2 provenance).
            save(out_mask, 'keep');
            % Gates JSON (all measured values, for review).
            gates_json = struct();
            gates_json.stage = 'mesh_cleanup';
            gates_json.mesh_method = 'alpha';
            gates_json.cloud_source = 'fused';
            gates_json.input = fused_ply;
            gates_json.input_sha256 = rabbit_mesh_cleanup.sha256_file(fused_ply);
            gates_json.output = out_ply;
            gates_json.transform = 'identity (the COLMAP model''s own units kept: mm when the run''s sparse model was scaled from a calibration, else COLMAP''s arbitrary unit; no conditioning transform applied)';   % review 3 round 2, B12
            gates_json.parameters = struct('k_nn', k_nn, 'z_thresh', z_thresh, ...
                'alpha_mults', alpha_mults, 'sample_n', sample_n, 'seed', seed);
            gates_json.gates = r.gates;
            gates_json.verdict = 'PASS';
            if ~all_pass, gates_json.verdict = 'FAIL'; end
            if ~all_pass
                gates_json.blocked_for = 'review of the failed checks';
            end
            fid = fopen(out_gates, 'w', 'n', 'UTF-8');
            if fid > 0
                fprintf(fid, '%s', jsonencode(gates_json, 'PrettyPrint', true));
                fclose(fid);
            end
            r.gates_json = out_gates;
            r.artifacts(end+1) = struct('path', out_ply, 'sha256', rabbit_mesh_cleanup.sha256_file(out_ply));
            r.artifacts(end+1) = struct('path', out_gates, 'sha256', rabbit_mesh_cleanup.sha256_file(out_gates));
            r.artifacts(end+1) = struct('path', out_mask, 'sha256', rabbit_mesh_cleanup.sha256_file(out_mask));
            r.artifacts(end+1) = struct('path', fused_ply, 'sha256', rabbit_mesh_cleanup.sha256_file(fused_ply));
        end

        % =============================================================
        % Membrane method: smooth membrane fit (rabbit_membrane_fit) under
        % the same gates. The fit's own normals are outward by
        % construction; M4 checks them against the camera visibility of
        % the fused cloud, and M9 uses that visibility transferred to the
        % mesh vertices (nearest fused point within the support distance).
        % =============================================================

        function r = run_membrane(r, fused_ply, vis_ply, images_bin, opts, out_ply, out_gates, out_mask, k_nn, z_thresh, sample_n, seed)
            cloud_source = r.cloud_source;
            run_dir = fileparts(fileparts(fused_ply));
            apd_ply = rabbit_mesh_cleanup.opt_str(opts, 'apd_ply', ...
                fullfile(run_dir, 'stages', 'apde_scene_prep', 'scene', 'APD', 'APD.ply'));
            mask_root = rabbit_mesh_cleanup.opt_str(opts, 'mask_root', '');
            membrane_opts = rabbit_mesh_cleanup.opt_str(opts, 'membrane', struct());
            % single_open_edge: the membrane cut leaves one open edge and no
            % hole (rabbit_membrane_fit, step 3)
            single_edge = rabbit_mesh_cleanup.opt_num(opts, 'single_open_edge', 0);
            if single_edge
                membrane_opts.single_open_edge = 1;
            end
            cloud_ply = fused_ply;
            if strcmp(cloud_source, 'apd')
                cloud_ply = apd_ply;
                if ~exist(cloud_ply, 'file')
                    r.err = sprintf('The APDe-MVS cloud is missing: %s. Run APDe-MVS first, or mesh the COLMAP cloud.', cloud_ply);
                    return;
                end
            end

            % ---- the dense cloud to fit ----
            [xyz, nrm, rgb, nv] = rabbit_mesh_cleanup.read_ply_27(cloud_ply);
            if nv == 0
                r.err = sprintf('The dense cloud %s has no points.', cloud_ply);
                return;
            end
            has_normals = any(nrm(:) ~= 0);

            % ---- M1: finite coordinates ----
            n_nonfinite = sum(~isfinite(xyz(:))) + sum(~isfinite(nrm(:)));
            r.gates.M1 = struct('pass', n_nonfinite == 0, ...
                'measured', struct('n_vertices', nv, 'n_nonfinite', n_nonfinite));
            if n_nonfinite > 0
                r.err = sprintf('The dense cloud has %d coordinates that are not numbers; nothing was dropped silently.', n_nonfinite);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, []);
                return;
            end

            % ---- silhouette filter (optional, before the gates) ----
            % Points outside the tissue silhouette in more than 1 - q of
            % the images they land in are dropped; the gates below then
            % measure the filtered cloud (the rabbit SfM study filtered the
            % fused cloud the same way before its membrane fit)
            sil_q = rabbit_mesh_cleanup.opt_num(opts, 'silhouette_filter_min_inside', 0);
            band_px = rabbit_mesh_cleanup.opt_num(opts, 'field_band_px', 0);
            try
                rabbit_mesh_cleanup.check_band_px(band_px);
            catch err
                r.err = err.message;
                return;
            end
            sil_keep = true(nv, 1);
            fcams = [];
            band_rec = [];
            if sil_q > 0
                [cams0, imgs0, ok0, err0] = rabbit_mesh_cleanup.read_colmap_model(images_bin);
                if ~ok0
                    r.err = err0;
                    return;
                end
                [fcams, band_rec] = rabbit_mesh_cleanup.filter_cameras(cams0, imgs0, mask_root, band_px);
                if isempty(fcams)
                    r.err = sprintf(['The silhouette filter needs a mask for the images, but none of the %d ' ...
                        'images has one in %s.'], numel(imgs0), mask_root);
                    return;
                end
                sil_keep = rabbit_sfm_build.silhouette_filter(xyz, fcams, sil_q);
                r.silhouette_filter = struct('min_inside', sil_q, 'mask_root', mask_root, ...
                    'images_with_mask', numel(fcams), 'images', numel(imgs0), ...
                    'n_points_in', nv, 'n_kept', nnz(sil_keep), 'n_removed', nnz(~sil_keep), ...
                    'field_band_px', band_px, ...
                    'note', sprintf(['silhouette filter: %d of %d points kept (inside the tissue mask in at ' ...
                    'least %.0f %% of the images they land in; %d images with a mask; %s)'], ...
                    nnz(sil_keep), nv, 100 * sil_q, numel(fcams), rabbit_mesh_cleanup.band_text(band_px)));
                if band_px > 0
                    % Which sides of which views have a still field edge
                    r.silhouette_filter.field_band = band_rec;
                    r.silhouette_filter.field_band_sides = rabbit_mesh_cleanup.band_sides_text(band_rec);
                end
                if ~any(sil_keep)
                    r.err = 'The silhouette filter left no point of the dense cloud; the masks do not fit the cameras.';
                    return;
                end
                xyz = xyz(sil_keep, :);
                nrm = nrm(sil_keep, :);
                rgb = rgb(sil_keep, :);
                nv = size(xyz, 1);
            end

            % ---- M2: statistical outlier removal ----
            [keep, m2_stats] = rabbit_mesh_cleanup.outlier_mask(xyz, k_nn, z_thresh);
            retention = sum(keep) / numel(keep);
            m2_pass = retention >= 0.90 && retention <= 1.00;
            r.gates.M2 = struct('pass', m2_pass, 'measured', struct( ...
                'n_source', numel(keep), 'n_outliers', sum(~keep), ...
                'retention', retention, 'k', k_nn, 'z', z_thresh, ...
                'mean_nn_mean', m2_stats.m, 'mean_nn_std', m2_stats.s, ...
                'threshold', m2_stats.thresh));
            if ~m2_pass
                r.err = sprintf('The outlier filter would keep only %.1f %% of the dense cloud (at least 90 %% expected).', 100 * retention);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, keep);
                return;
            end
            work = xyz(keep, :);

            % ---- M10: spacing ratios ----
            [s50, s95] = rabbit_mesh_cleanup.spacing_stats(xyz, k_nn);
            [s50w, s95w] = rabbit_mesh_cleanup.spacing_stats(work, k_nn);
            m10_pass = (s50w / s50) >= 0.80 && (s50w / s50) <= 1.25 && (s95w / s95) <= 1.50;
            r.gates.M10 = struct('pass', m10_pass, 'measured', struct( ...
                's50', s50, 's95', s95, 's50_work', s50w, 's95_work', s95w, ...
                's50_ratio', s50w / s50, 's95_ratio', s95w / s95, 'k', k_nn));
            if ~m10_pass
                r.err = sprintf('Removing outliers changed the point spacing too much (median ratio %.2f, 95th percentile ratio %.2f).', s50w / s50, s95w / s95);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, keep);
                return;
            end

            % ---- cameras, visibility of the fused cloud ----
            [vis, vis_ok, vis_err] = rabbit_mesh_cleanup.read_vis(vis_ply);
            if ~vis_ok
                r.err = vis_err;
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, keep);
                return;
            end
            if strcmp(cloud_source, 'fused') && sil_q > 0
                vis = vis(sil_keep);   % the .vis rows of the points the filter kept
            end
            [cameras, images, cam_ok, cam_err] = rabbit_mesh_cleanup.read_colmap_model(images_bin);
            if ~cam_ok
                r.err = cam_err;
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, keep);
                return;
            end
            centers = rabbit_mesh_cleanup.camera_centres(images);
            lookns = rabbit_mesh_cleanup.camera_lookns(images);
            if strcmp(cloud_source, 'fused')
                fxyz = work;
                fvis = vis(keep);
                frgb = rgb(keep, :);
            else
                [fxyz0, ~, frgb0] = rabbit_mesh_cleanup.read_ply_27(fused_ply);
                if numel(vis) ~= size(fxyz0, 1)
                    r.err = sprintf('The visibility file %s has %d rows; the COLMAP cloud has %d points.', ...
                        vis_ply, numel(vis), size(fxyz0, 1));
                    r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, keep);
                    return;
                end
                [fxyz, fvis, frgb, fsil_rec] = rabbit_mesh_cleanup.camera_check_points(fxyz0, vis, frgb0, ...
                    fcams, sil_q, k_nn, z_thresh);
                if ~isempty(fsil_rec)
                    r.silhouette_filter.camera_check_points = fsil_rec;
                    r.silhouette_filter.note = sprintf('%s; COLMAP points for the camera checks: %d of %d kept', ...
                        r.silhouette_filter.note, fsil_rec.n_kept, fsil_rec.n_points_in);
                end
            end
            min_agree = rabbit_mesh_cleanup.opt_num(opts, 'mask_min_agreement', 0.97);
            bands = [];
            if band_px > 0 && ~isempty(fcams)
                bands = rabbit_mesh_cleanup.band_map(fcams);   % the filter's bands (all frames of a view)
            end
            [cams, silhouette] = rabbit_mesh_cleanup.membrane_cameras(cameras, images, mask_root, ...
                fxyz, fvis, min_agree, rabbit_mesh_cleanup.opt_num(opts, 'silhouette_frames', 0), band_px, bands);
            % The masks are still checked, so the record shows how they
            % agreed; a cap turned off on purpose is not a warning
            sil_cap = rabbit_mesh_cleanup.opt_num(opts, 'silhouette_cap', 1) ~= 0;
            if ~sil_cap
                [cams, silhouette] = rabbit_mesh_cleanup.cap_off_by_setting(cams, silhouette);
            end
            r.silhouette = silhouette;
            if sil_cap && ~silhouette.cap_used
                r.warnings{end+1} = ['Silhouette cap off: ' silhouette.note '.'];
            end

            % ---- the membrane fit ----
            try
                [V, faces, rep] = rabbit_membrane_fit(work, cams, membrane_opts);
            catch err
                r.err = sprintf('Membrane fit: the fit stopped with an error: %s', err.message);
                r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, keep);
                return;
            end
            % ---- per view: does the mask fit the mesh at all? ----
            % A view whose masks hold much more than the heart (one view of a large-field recording:
            % a still bright panel above it, silhouette IoU 0.39-0.47) can
            % neither cap the mesh nor judge it, and the mask checks pass
            % there by construction. Such a view
            % is named in a warning; when it is in the silhouette cap, its
            % cameras leave the cap and the membrane is fitted again.
            check_cams = cams;
            if isempty(check_cams) && ~isempty(fcams)
                check_cams = fcams(rabbit_mesh_cleanup.in_frames({fcams.name}, silhouette.frames));
            end
            vcheck = rabbit_mesh_cleanup.view_silhouette_check(V, faces, check_cams, ...
                rabbit_mesh_cleanup.MIN_VIEW_SILHOUETTE_IOU);
            vcheck.refitted = false;
            if ~isempty(vcheck.low_views) && silhouette.cap_used
                keep_cam = ~ismember(vcheck.view_of, vcheck.low_views);
                cams = cams(keep_cam);
                silhouette.cameras_used = numel(cams);
                silhouette.cap_used = ~isempty(cams);
                silhouette.note = sprintf('%s; the cameras of view %s left the cap (their masks do not fit the mesh)', ...
                    silhouette.note, strjoin(arrayfun(@(v) sprintf('%g', v), vcheck.low_views, 'UniformOutput', false), ', '));
                r.silhouette = silhouette;
                try
                    [V, faces, rep] = rabbit_membrane_fit(work, cams, membrane_opts);
                catch err
                    r.err = sprintf('Membrane fit: the fit without view %s stopped with an error: %s', ...
                        mat2str(vcheck.low_views), err.message);
                    r = rabbit_mesh_cleanup.finish_fail(r, out_ply, out_gates, out_mask, cloud_ply, xyz, nrm, rgb, keep);
                    return;
                end
                vcheck.refitted = true;
            end
            if ~isempty(vcheck.low_views)
                r.warnings{end+1} = vcheck.warning;
            end
            % ---- the share of the mesh that only the field band lets pass ----
            % Faces whose centre passes the silhouette rule only because the
            % band pixels abstain (counted as outside, it would fail):
            % surface no silhouette of those views checks
            band_only = struct('share', 0, 'area_ref_mm2', 0, 'faces', 0, 'rule', 'no field band');
            if band_px > 0 && ~isempty(fcams)
                band_only = rabbit_mesh_cleanup.band_only_share(V, faces, fcams, sil_q, ...
                    rep.settings.world_units_per_mm);
            end
            nrm_m = rep.normals;
            support = rep.settings.support_mm * rep.settings.world_units_per_mm;
            if isfield(rep.cut, 'single_open_edge')
                oe = rep.cut.single_open_edge;
                if oe.joined_regions > 0
                    r.warnings{end+1} = sprintf(['Membrane fit: %d unsupported region(s) of %.1f reference mm2 ' ...
                        'lay closer to the open edge (along the surface) than their own size and were cut ' ...
                        'with it, with the strip of supported surface between them (%.2f reference mm2), so ' ...
                        'the strip leaves no hole.'], oe.joined_regions, oe.joined_mm2, oe.strip_mm2);
                end
                if oe.hole_regions > 0
                    r.warnings{end+1} = sprintf(['Membrane fit: %d unsupported region(s) (%.1f reference mm2 ' ...
                        'with no cloud point within the support distance) lie too far from the open edge to ' ...
                        'be part of it; they were cut and leave a hole in the mesh (see holes, M8).'], ...
                        oe.hole_regions, oe.hole_mm2);
                end
            end

            % ---- M3: unit-length normals (of the output mesh) ----
            nlen = sqrt(sum(nrm_m .* nrm_m, 2));
            unit_frac = mean(nlen >= 0.99 & nlen <= 1.01);
            % The membrane's vertex normals are normalised face normals, so
            % this check cannot fail here; it is kept for the gate set
            r.gates.M3 = struct('pass', unit_frac >= 0.99, 'measured', struct( ...
                'unit_fraction', unit_frac, 'n_normals', size(nrm_m, 1), ...
                'on', 'output mesh vertex normals', 'input_cloud_has_normals', has_normals, ...
                'note', 'unit length by construction: the vertex normals are computed from the mesh faces'));

            % ---- M4: mesh normals against the camera visibility ----
            [m4_pass, m4_meas] = rabbit_mesh_cleanup.membrane_orientation(V, nrm_m, fxyz, fvis, centers, support);
            r.gates.M4 = struct('pass', m4_pass, 'measured', m4_meas);

            % ---- M5, M6: components and degenerate faces ----
            % Vertex components through the mesh edges (0 = vertex in no face)
            comps = rabbit_mesh_cleanup.face_components(faces, size(V, 1));
            [m5_pass, m5_meas, faces5, ~] = rabbit_mesh_cleanup.component_gate(faces, comps, V);
            r.gates.M5 = struct('pass', m5_pass, 'measured', m5_meas);
            [m6_pass, m6_meas, faces6] = rabbit_mesh_cleanup.degenerate_gate(faces5, V);
            r.gates.M6 = struct('pass', m6_pass, 'measured', m6_meas);

            % ---- M7: distances to the surface, M8: boundary ----
            % The face-centre sample measure of the alpha shape is kept in
            % the record (centre_samples); the verdict uses the distances
            % to the surface (membrane_surface_distances, membrane_verdicts)
            m7_meas = rabbit_mesh_cleanup.membrane_surface_distances(work, V, faces6, s50, support);
            [m7c_pass, m7_meas.centre_samples] = rabbit_mesh_cleanup.membrane_deviation_gate(work, V, faces6, s50, sample_n, seed);
            m7_meas.centre_samples.alpha_shape_rule_pass = m7c_pass;
            r.gates.M7 = struct('pass', false, 'measured', m7_meas);
            [m8_pass, m8_meas] = rabbit_mesh_cleanup.boundary_gate(faces6, V);
            r.gates.M8 = struct('pass', m8_pass, 'measured', m8_meas);

            % ---- M9: RHYTHM DIRECT visibility on the mesh vertices ----
            [near_p, near_d] = knnsearch(fxyz, V);
            vis_m = cell(size(V, 1), 1);
            for i = 1:size(V, 1)
                if near_d(i) <= support
                    vis_m{i} = fvis{near_p(i)};
                else
                    vis_m{i} = int32(zeros(1, 0));
                end
            end
            [m9_pass, m9_meas] = rabbit_mesh_cleanup.direct_visibility_gate( ...
                V, nrm_m, faces6, cameras, images, vis_m, lookns);
            m9_meas.visibility_source = 'fused-cloud .vis of the nearest point within the support distance';
            r.gates.M9 = struct('pass', m9_pass, 'measured', m9_meas);

            % ---- verdict: PASS / WARN / FAIL per gate (membrane_verdicts) ----
            % A WARN gate lets the run continue with the mesh and is said
            % plainly in the step's warnings and in the gates JSON; a FAIL
            % gate stops the run for review
            [r.gates, gate_notes] = rabbit_mesh_cleanup.membrane_verdicts(r.gates);
            gate_names = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'M10'};
            verdicts = cellfun(@(g) r.gates.(g).verdict, gate_names, 'UniformOutput', false);
            failed = strcmp(verdicts, 'FAIL');
            warned = strcmp(verdicts, 'WARN');
            r.ok = ~any(failed);
            for k = find(warned)
                note = gate_notes(strcmp({gate_notes.code}, gate_names{k}));
                r.warnings{end+1} = sprintf(['Mesh check WARN - %s (%s): the mesh is usable, but this check ' ...
                    'is below its ideal value. Measured: %s. The mesh was kept and the run continues; see ' ...
                    'Help, Limitations.'], rabbit_mesh_cleanup.check_names(gate_names(k)), ...
                    gate_names{k}, note(1).text);
            end
            if ~r.ok
                r.err = sprintf(['Membrane fit: the mesh was written for review, but these checks failed: %s. ' ...
                    'Details are in mesh-cleanup-gates.json.'], rabbit_mesh_cleanup.check_names(gate_names(failed)));
            end

            % ---- outputs: mesh, removal mask, gates JSON ----
            rgb_m = frgb(near_p, :);
            rabbit_mesh_cleanup.write_ply(out_ply, V, nrm_m, rgb_m, faces6);
            % keep indexes the silhouette-filtered cloud; the masks over the
            % dense cloud itself are saved beside it
            silhouette_keep = sil_keep; %#ok<NASGU>
            keep_in_fused = false(numel(sil_keep), 1);
            keep_in_fused(sil_keep) = keep;
            save(out_mask, 'keep', 'silhouette_keep', 'keep_in_fused');
            rep = rmfield(rep, 'normals');
            rep.silhouette = silhouette;
            rep.silhouette_filter = r.silhouette_filter;
            gates_json = struct();
            gates_json.stage = 'mesh_cleanup';
            gates_json.mesh_method = 'membrane';
            gates_json.cloud_source = cloud_source;
            gates_json.input = cloud_ply;
            gates_json.input_sha256 = rabbit_mesh_cleanup.sha256_file(cloud_ply);
            gates_json.visibility_input = fused_ply;
            gates_json.output = out_ply;
            gates_json.transform = 'identity (the COLMAP model''s own units kept: mm when the run''s sparse model was scaled from a calibration, else COLMAP''s arbitrary unit; no conditioning transform applied)';   % review 3 round 2, B12
            gates_json.parameters = struct('k_nn', k_nn, 'z_thresh', z_thresh, ...
                'sample_n', sample_n, 'seed', seed, 'mask_root', mask_root, ...
                'silhouette_filter_min_inside', sil_q, ...
                'silhouette_frames', rabbit_mesh_cleanup.opt_num(opts, 'silhouette_frames', 0), ...
                'silhouette_cap', double(sil_cap), ...
                'field_band_px', band_px, 'single_open_edge', single_edge);
            if band_px > 0
                % Where the band acts (still field edges per view and side) and
                % how much of the mesh rests on it
                gates_json.field_band = struct('field_band_px', band_px, ...
                    'sides', rabbit_mesh_cleanup.band_sides_text(band_rec), 'views', band_rec, ...
                    'band_only_mesh', band_only);
            end
            gates_json.view_silhouette = vcheck;
            gates_json.membrane = rep;
            gates_json.gates = r.gates;
            gates_json.gate_notes = gate_notes;
            gates_json.verdict = 'PASS';
            if any(warned), gates_json.verdict = 'WARN'; end
            if ~r.ok, gates_json.verdict = 'FAIL'; end
            fid = fopen(out_gates, 'w', 'n', 'UTF-8');
            if fid > 0
                fprintf(fid, '%s', jsonencode(gates_json, 'PrettyPrint', true));
                fclose(fid);
            end
            r.gates_json = out_gates;
            r.membrane = rep;
            r.view_silhouette = vcheck;
            r.band_only_mesh = band_only;
            r.artifacts(end+1) = struct('path', out_ply, 'sha256', rabbit_mesh_cleanup.sha256_file(out_ply));
            r.artifacts(end+1) = struct('path', out_gates, 'sha256', rabbit_mesh_cleanup.sha256_file(out_gates));
            r.artifacts(end+1) = struct('path', out_mask, 'sha256', rabbit_mesh_cleanup.sha256_file(out_mask));
            r.artifacts(end+1) = struct('path', cloud_ply, 'sha256', rabbit_mesh_cleanup.sha256_file(cloud_ply));
        end

        function [cams, band_rec] = filter_cameras(cameras, images, mask_root, band_px)
            %FILTER_CAMERAS Pinhole cameras with their mask, for the
            %silhouette filter: every image with a pinhole camera and a
            %mask of its size in mask_root (mask_file_for). band_px > 0:
            %each camera also carries its mask's field band, found from
            %the mask edges that stay still over the frames of its view
            %(rabbit_sfm_build.static_field_bands over all these masks;
            %band_rec says which sides are banded per view), where the
            %filter abstains; otherwise band is empty.
            if nargin < 4 || isempty(band_px), band_px = 0; end
            band_rec = [];
            cams = struct('name', {}, 'R', {}, 't', {}, 'f', {}, 'c', {}, ...
                'width', {}, 'height', {}, 'mask', {}, 'band', {});
            if isempty(mask_root) || ~isfolder(mask_root), return; end
            rabbit_mesh_cleanup.check_band_px(band_px);
            for i = 1:numel(images)
                cm = cameras(images(i).camera_id);
                switch cm.model
                    case 'SIMPLE_PINHOLE'
                        f = [cm.params(1) cm.params(1)]; c = cm.params(2:3)';
                    case 'PINHOLE'
                        f = cm.params(1:2)'; c = cm.params(3:4)';
                    otherwise
                        continue;
                end
                mask_file = rabbit_mesh_cleanup.mask_file_for(mask_root, images(i).name);
                if isempty(mask_file), continue; end
                mask = imread(mask_file);
                if size(mask, 3) > 1, mask = mask(:, :, 1); end
                if size(mask, 1) ~= cm.height || size(mask, 2) ~= cm.width, continue; end
                cams(end+1) = struct('name', images(i).name, 'R', rabbit_mesh_cleanup.qvec2rot(images(i).qvec), ...
                    't', images(i).tvec(:), 'f', f, 'c', c, 'width', double(cm.width), ...
                    'height', double(cm.height), 'mask', mask > 0, 'band', []); %#ok<AGROW>
            end
            if band_px > 0 && ~isempty(cams)
                [bands, band_rec] = rabbit_sfm_build.static_field_bands({cams.name}, {cams.mask}, band_px);
                for i = 1:numel(cams)
                    if any(bands{i}(:)), cams(i).band = bands{i}; end
                end
            end
        end

        function check_band_px(band_px)
            %CHECK_BAND_PX The field band width: a whole number from 0 to
            %rabbit_sfm_build.MAX_FIELD_BAND_PX (a wider band would
            %abstain over the heart's outline)
            if ~isnumeric(band_px) || ~isscalar(band_px) || band_px < 0 || band_px ~= round(band_px) || ...
                    band_px > rabbit_sfm_build.MAX_FIELD_BAND_PX
                error('rabbit_mesh_cleanup:FieldBand', ['The field band must be a whole number of pixels ' ...
                    'from 0 to %d; got %g.'], rabbit_sfm_build.MAX_FIELD_BAND_PX, double(band_px(1)));
            end
        end

        function [cams, record] = membrane_cameras(cameras, images, mask_root, cloud, vis, min_agree, n_frames, band_px, bands)
            %MEMBRANE_CAMERAS Silhouette cameras for the membrane fit: the
            %COLMAP poses with one mask per image. The mask of image
            %<name> is <mask_root>/<name>.png (COLMAP's own layout, with
            %the image's subfolder), else <mask_root>/<file name>.png (the
            %flat folder rabbit_segmentation_masks writes). The cameras
            %are the undistorted ones; the sparse input must already be
            %pinhole, so undistortion leaves the image frame unchanged and
            %a mask of the input image fits it (the size is checked).
            %Images without a mask, with a mask of another size or with a
            %non-pinhole camera are left out; no masks at all = no
            %silhouette cap.
            %The cap holds the mesh inside every mask, so a mask that is
            %too tight or shifted would cut real surface off. A mask is
            %only used when at least min_agree (default 0.97) of the cloud
            %points its image saw (the .vis file) project inside it, and
            %the image saw at least 20 points; other masks are left out
            %with the measured agreement in the record. When fewer than 90 %
            %of the masks that could be checked agree, the mask set as a
            %whole does not fit the cameras and the cap is not used.
            %n_frames > 0: only the images of n evenly spaced frames (by
            %the frame number of the cut names, ..._frame_NNNN; all views
            %of each frame) are candidates, as in the rabbit SfM study
            %(4 frames x 4 views; rabbit_sfm_build.silhouette_frames_pick).
            %band_px > 0: each mask's field band is left out of the
            %agreement (points landing in it are not counted) and travels
            %with the camera, so the membrane fit puts no cap there. The
            %bands are those of filter_cameras (still edges over all the
            %frames of a view, not only the candidates); bands, a
            %containers.Map from image name to band, passes them in,
            %otherwise they are found here.
            if nargin < 4, cloud = []; end
            if nargin < 5, vis = {}; end
            if nargin < 6 || isempty(min_agree), min_agree = 0.97; end
            if nargin < 7 || isempty(n_frames), n_frames = 0; end
            if nargin < 8 || isempty(band_px), band_px = 0; end
            if nargin < 9, bands = []; end
            if band_px > 0 && isempty(bands) && ~isempty(mask_root) && isfolder(mask_root)
                fc = rabbit_mesh_cleanup.filter_cameras(cameras, images, mask_root, band_px);
                bands = rabbit_mesh_cleanup.band_map(fc);
            end
            cams = struct('name', {}, 'R', {}, 't', {}, 'f', {}, 'c', {}, ...
                'width', {}, 'height', {}, 'mask', {}, 'scale', {}, 'band', {});
            record = struct('mask_root', mask_root, 'images', numel(images), ...
                'cameras_used', 0, 'skipped', {{}}, 'cap_used', false, 'note', '', ...
                'min_agreement', min_agree, 'agreement', [], 'frames', [], 'field_band_px', band_px);
            % Candidate images: all, or those of n evenly spaced frames
            candidate = true(numel(images), 1);
            if n_frames > 0 && ~isempty(images)
                tok = regexp({images.name}, '_frame_(\d+)', 'tokens', 'once');
                if all(~cellfun(@isempty, tok))
                    fr = cellfun(@(t) str2double(t{1}), tok);
                    pick = rabbit_sfm_build.silhouette_frames_pick(fr, n_frames);
                    candidate = ismember(fr(:), pick(:));
                    record.frames = pick;
                end
            end
            if isempty(mask_root)
                record.note = 'no silhouette masks found: fitted without the silhouette cap';
                return;
            end
            if ~isfolder(mask_root)
                record.note = sprintf('the masks folder %s does not exist: fitted without the silhouette cap', mask_root);
                return;
            end
            % Points seen by each image (.vis holds 0-based image positions)
            counts = cellfun(@numel, vis(:));
            point_of = repelem((1:numel(vis))', counts);
            image_of = zeros(sum(counts), 1);
            if ~isempty(image_of)
                image_of = double(cell2mat(cellfun(@(x) x(:), vis(:), 'UniformOutput', false))) + 1;
            end
            valid = image_of >= 1 & image_of <= numel(images);
            seen_by = accumarray(image_of(valid), point_of(valid), [numel(images) 1], @(x) {x});
            agreement = nan(numel(images), 1);
            n_disagree = 0;
            n_checked = 0;
            for i = 1:numel(images)
                if ~candidate(i), continue; end
                cm = cameras(images(i).camera_id);
                mask_file = rabbit_mesh_cleanup.mask_file_for(mask_root, images(i).name);
                if isempty(mask_file)
                    record.skipped{end+1} = sprintf('%s: no mask', images(i).name);
                    continue;
                end
                switch cm.model
                    case 'SIMPLE_PINHOLE'
                        f = [cm.params(1) cm.params(1)];
                        c = cm.params(2:3)';
                    case 'PINHOLE'
                        f = cm.params(1:2)';
                        c = cm.params(3:4)';
                    otherwise
                        record.skipped{end+1} = sprintf('%s: camera model %s (needs an undistorted pinhole camera)', images(i).name, cm.model);
                        continue;
                end
                mask = imread(mask_file);
                if size(mask, 3) > 1, mask = mask(:, :, 1); end
                if size(mask, 1) ~= cm.height || size(mask, 2) ~= cm.width
                    record.skipped{end+1} = sprintf('%s: mask %dx%d, image %dx%d', images(i).name, ...
                        size(mask, 2), size(mask, 1), cm.width, cm.height);
                    continue;
                end
                if ~any(mask(:))
                    record.skipped{end+1} = sprintf('%s: empty mask', images(i).name);
                    continue;
                end
                R = rabbit_mesh_cleanup.qvec2rot(images(i).qvec);
                % Agreement of the mask with the points this image saw
                % (COLMAP pixel convention: pixel k covers u in [k-1, k))
                seen = seen_by{i};
                if numel(seen) < 20
                    record.skipped{end+1} = sprintf('%s: the image saw %d points, too few to check its mask', ...
                        images(i).name, numel(seen));
                    continue;
                end
                Xc = cloud(seen, :) * R' + images(i).tvec(:)';
                col = floor(f(1) * Xc(:, 1) ./ Xc(:, 3) + c(1)) + 1;
                row = floor(f(2) * Xc(:, 2) ./ Xc(:, 3) + c(2)) + 1;
                inside = Xc(:, 3) > 0 & col >= 1 & col <= cm.width & row >= 1 & row <= cm.height;
                lands = inside;
                inside(inside) = mask(sub2ind(size(mask), row(inside), col(inside))) > 0;
                band = [];
                judged = true(size(inside));
                if band_px > 0 && ~isempty(bands) && isKey(bands, images(i).name)
                    % Points landing in the field band are not judged
                    band = bands(images(i).name);
                    judged(lands) = ~band(sub2ind(size(mask), row(lands), col(lands)));
                end
                if nnz(judged) < 20
                    record.skipped{end+1} = sprintf(['%s: only %d of the points the image saw lie outside ' ...
                        'its field band, too few to check its mask'], images(i).name, nnz(judged));
                    continue;
                end
                agreement(i) = mean(inside(judged));
                n_checked = n_checked + 1;
                if agreement(i) < min_agree
                    n_disagree = n_disagree + 1;
                    record.skipped{end+1} = sprintf('%s: only %.1f %% of the points the image saw lie inside its mask', ...
                        images(i).name, 100 * agreement(i));
                    continue;
                end
                cams(end+1) = struct('name', images(i).name, ...
                    'R', R, 't', images(i).tvec(:), ...
                    'f', f, 'c', c, 'width', double(cm.width), 'height', double(cm.height), ...
                    'mask', mask > 0, 'scale', 1, 'band', band); %#ok<AGROW>
            end
            record.agreement = agreement;
            if n_checked > 0 && n_disagree > 0.1 * n_checked
                % The mask set does not fit the cameras: no cap at all
                cams = cams([]);
                record.cameras_used = 0;
                record.cap_used = false;
                record.note = sprintf(['the masks in %s disagree with the cameras: only %d of the %d ' ...
                    'masks that could be checked hold at least %.0f %% of the points their image saw ' ...
                    '(90 %% of them must): fitted without the silhouette cap'], ...
                    mask_root, n_checked - n_disagree, n_checked, 100 * min_agree);
                return;
            end
            record.cameras_used = numel(cams);
            record.cap_used = ~isempty(cams);
            if isempty(cams)
                record.note = sprintf('none of the %d images has a usable mask in %s', numel(images), mask_root);
                if n_disagree > 0
                    record.note = sprintf(['%s (the masks of %d images disagree with the cameras: fewer ' ...
                        'than %.0f %% of the points the image saw lie inside its mask)'], ...
                        record.note, n_disagree, 100 * min_agree);
                end
                record.note = [record.note ': fitted without the silhouette cap'];
            else
                record.note = sprintf('silhouette cap on: %d of %d images have a mask that agrees with the cameras', ...
                    numel(cams), numel(images));
                if band_px > 0
                    record.note = sprintf('%s (%s)', record.note, rabbit_mesh_cleanup.band_text(band_px));
                end
            end
        end

        function [cams, record] = cap_off_by_setting(cams, record)
            %CAP_OFF_BY_SETTING No silhouette cameras for the membrane fit,
            %whatever the mask check decided; the record keeps its counts
            cams = cams([]);
            record.cameras_used = 0;
            record.cap_used = false;
            record.note = sprintf(['silhouette cap off by setting (%d of the %d masks that could be ' ...
                'checked hold at least %.0f %% of the points their image saw)'], ...
                nnz(record.agreement >= record.min_agreement), nnz(~isnan(record.agreement)), ...
                100 * record.min_agreement);
        end

        function txt = band_text(band_px)
            %BAND_TEXT Plain words for the field band setting
            if band_px > 0
                txt = sprintf(['field band %d px: where a mask edge lies within %d px of the image border and ' ...
                    'stays still over the view''s frames (a field edge), the pixels beyond it do not judge a ' ...
                    'point'], band_px, band_px);
            else
                txt = 'no field band';
            end
        end

        function m = band_map(cams)
            %BAND_MAP Image name -> field band of the cameras that have one
            m = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(cams)
                if ~isempty(cams(i).band), m(cams(i).name) = cams(i).band; end
            end
        end

        function txt = band_sides_text(band_rec)
            %BAND_SIDES_TEXT Which border sides of which views have a field
            %edge (static_field_bands record), in plain words
            parts = {};
            for k = 1:numel(band_rec)
                e = band_rec(k);
                if ~isempty(e.note)
                    parts{end+1} = sprintf('view %g: %s', e.view, e.note); %#ok<AGROW>
                    continue;
                end
                sides = {};
                for s = 1:numel(e.sides)
                    if e.sides(s).still_lines > 0
                        sides{end+1} = sprintf('%s (%d lines, edge %.0f px from the border, sd %.1f px)', ...
                            e.sides(s).side, e.sides(s).still_lines, e.sides(s).edge_px, e.sides(s).sd_px); %#ok<AGROW>
                    end
                end
                if isempty(sides), sides = {'none'}; end
                parts{end+1} = sprintf('view %g: %s', e.view, strjoin(sides, ', ')); %#ok<AGROW>
            end
            txt = strjoin(parts, '; ');
        end

        function in = in_frames(names, frames)
            %IN_FRAMES Images (by the frame number of the cut names,
            %..._frame_NNNN) of the given frames; all when frames is empty
            in = true(1, numel(names));
            if isempty(frames), return; end
            tok = regexp(names, '_frame_(\d+)', 'tokens', 'once');
            for i = 1:numel(names)
                in(i) = ~isempty(tok{i}) && ismember(str2double(tok{i}{1}), frames);
            end
        end

        function chk = view_silhouette_check(V, F, cams, min_iou)
            %VIEW_SILHOUETTE_CHECK Per view, how well the masks fit the mesh
            %   Per camera the IoU of the mesh silhouette with its mask,
            %   field band pixels left out (as the fit's own check); per
            %   view (_view<V>_ of the name) the median. A view is low when
            %   its median is below min_iou and at least two views were
            %   measured. view_of: the view of each camera (NaN unknown).
            n = numel(cams);
            iou = nan(n, 1);
            view_of = nan(n, 1);
            for i = 1:n
                tok = regexp(cams(i).name, '_view(\d+)_frame_', 'tokens', 'once');
                if ~isempty(tok), view_of(i) = str2double(tok{1}); end
                Xc = V * cams(i).R' + cams(i).t(:)';
                z = Xc(:, 3);
                uv = [cams(i).f(1) * Xc(:, 1) ./ z + cams(i).c(1), cams(i).f(2) * Xc(:, 2) ./ z + cams(i).c(2)];
                uv(z <= 0, :) = NaN;
                sil = rabbit_mesh_alignment.mesh_silhouette(uv, F, cams(i).height, cams(i).width);
                m = logical(cams(i).mask);
                judged = true(size(m));
                if isfield(cams, 'band') && ~isempty(cams(i).band), judged = ~logical(cams(i).band); end
                iou(i) = nnz(sil & m) / max(nnz((sil | m) & judged), 1);
            end
            views = unique(view_of(~isnan(view_of)))';
            med = arrayfun(@(v) median(iou(view_of == v)), views);
            cnt = arrayfun(@(v) nnz(view_of == v), views);
            low = false(size(views));
            if numel(views) >= 2, low = med < min_iou; end
            chk = struct('min_iou', min_iou, 'images', n, 'views', views, 'iou_median', med, ...
                'n_images', cnt, 'low_views', views(low), 'view_of', view_of', 'iou', iou', 'warning', '', ...
                'rule', ['per view, the median IoU of the mesh silhouette with the tissue mask (field band ' ...
                'left out) over the silhouette cameras, or over the silhouette frames when the cap is off']);
            if any(low)
                others = med(~low);
                chk.warning = sprintf(['Silhouette check WARN: the masks of view %s fit the mesh poorly ' ...
                    '(median silhouette IoU %s; the other views %.2f-%.2f; limit %.2f). Such a mask holds much ' ...
                    'more than the heart (e.g. a bright object beside it) or misses part of it, so in that ' ...
                    'view the silhouette filter and the mask checks (silhouette A4, outline A6) cannot see surface the mask ' ...
                    'wrongly includes. Its cameras are not used to cap the mesh; check the masks of that view.'], ...
                    strjoin(arrayfun(@(v) sprintf('%g', v), views(low), 'UniformOutput', false), ', '), ...
                    strjoin(arrayfun(@(x) sprintf('%.2f', x), med(low), 'UniformOutput', false), ', '), ...
                    min([others NaN]), max([others NaN]), min_iou);
            end
        end

        function s = band_only_share(V, F, fcams, q, unit)
            %BAND_ONLY_SHARE Mesh area that passes the silhouette rule only
            %because the field band abstains: the face centres judged with
            %the band (filter_cameras) and with band pixels counted as
            %outside the mask; area share and reference mm2 (unit = world
            %units per reference mm)
            c = (V(F(:, 1), :) + V(F(:, 2), :) + V(F(:, 3), :)) / 3;
            a = 0.5 * sqrt(sum(cross(V(F(:, 2), :) - V(F(:, 1), :), V(F(:, 3), :) - V(F(:, 1), :), 2) .^ 2, 2));
            keep_band = rabbit_sfm_build.silhouette_filter(c, fcams, q);
            no_band = fcams;
            [no_band.band] = deal([]);
            keep_plain = rabbit_sfm_build.silhouette_filter(c, no_band, q);
            only = keep_band & ~keep_plain;
            s = struct('share', sum(a(only)) / max(sum(a), eps), 'area_ref_mm2', sum(a(only)) / unit ^ 2, ...
                'faces', nnz(only), 'rule', sprintf(['mesh faces whose centre lies inside the mask in at least ' ...
                '%.0f %% of the images it lands in only because the field band pixels abstain'], 100 * q));
        end

        function mask_file = mask_file_for(mask_root, image_name)
            %MASK_FILE_FOR The mask of one image, or '' when there is none:
            %<mask_root>/<image name>.png, else <mask_root>/<file name>.png
            mask_file = fullfile(mask_root, [image_name '.png']);
            if exist(mask_file, 'file') == 2
                return;
            end
            [~, name, ext] = fileparts(image_name);
            mask_file = fullfile(mask_root, [name ext '.png']);
            if exist(mask_file, 'file') ~= 2
                mask_file = '';
            end
        end

        function [fxyz, fvis, frgb, rec] = camera_check_points(fxyz, fvis, frgb, fcams, sil_q, k_nn, z_thresh)
            %CAMERA_CHECK_POINTS The COLMAP points (and .vis rows) that judge
            %a mesh made from another cloud (the APDe-MVS cloud): the same
            %silhouette filter as the cloud (fcams, sil_q; skipped when
            %sil_q is 0 or there are no masks), then the outlier filter.
            %Outlier filtering alone leaves bath and holder points near the
            %mesh to judge it (19 % of the M4 observations on the reference
            %rabbit data, M4 FAIL 92.3 / 91.4 %; 96.8 / 96.5 % with this
            %filter). rec: n_points_in, n_kept ([] when
            %not filtered).
            rec = [];
            if sil_q > 0 && ~isempty(fcams)
                in = rabbit_sfm_build.silhouette_filter(fxyz, fcams, sil_q);
                rec = struct('n_points_in', numel(in), 'n_kept', nnz(in));
                fxyz = fxyz(in, :);
                fvis = fvis(in);
                frgb = frgb(in, :);
            end
            [fkeep, ~] = rabbit_mesh_cleanup.outlier_mask(fxyz, k_nn, z_thresh);
            fxyz = fxyz(fkeep, :);
            fvis = fvis(fkeep);
            frgb = frgb(fkeep, :);
        end

        function [pass, meas] = membrane_orientation(V, nrm, cloud, vis, centers, support)
            %MEMBRANE_ORIENTATION Fraction of the fused-cloud observations
            %(point, camera that saw it) whose camera lies on the outer side
            %of the mesh normal at the point's nearest vertex; points
            %farther than the support distance from the mesh are not used.
            [idx, d] = knnsearch(V, cloud);
            pos = 0; near_grazing = 0; tot = 0;
            for i = find(d <= support)'
                for j = 1:numel(vis{i})
                    v = centers(vis{i}(j) + 1, :) - cloud(i, :);
                    cosine = dot(nrm(idx(i), :), v) / max(norm(v), 1e-300);
                    tot = tot + 1;
                    if cosine > 0
                        pos = pos + 1;
                    elseif cosine > -sind(10)
                        near_grazing = near_grazing + 1;
                    end
                end
            end
            agreement = pos / max(tot, 1);
            pass = tot > 0 && agreement >= 0.99;
            meas = struct('agreement', agreement, 'n_observations', tot, ...
                'n_points_used', sum(d <= support), 'support', support, ...
                'agreement_within_10deg_of_grazing', (pos + near_grazing) / max(tot, 1));
        end

        function [pass, meas] = membrane_deviation_gate(cloud, V, faces, s50, sample_n, seed)
            %MEMBRANE_DEVIATION_GATE M7 for a mesh whose vertices are not
            %the cloud points: the same samples and criterion as
            %deviation_gate (median <= 1.5*s50, p95 <= 4*s50, both ways).
            if isempty(faces)
                pass = false;
                meas = struct('reason', 'no faces');
                return;
            end
            rng(seed);
            n = size(cloud, 1);
            ns = min(sample_n, n);
            cloud_s = cloud(randsample(n, ns), :);
            centroids = (V(faces(:, 1), :) + V(faces(:, 2), :) + V(faces(:, 3), :)) / 3;
            nf = size(centroids, 1);
            nfs = min(sample_n, nf);
            mesh_s = centroids(randsample(nf, nfs), :);
            [~, d_cm] = knnsearch(mesh_s, cloud_s, 'K', 1);
            [~, d_mc] = knnsearch(cloud_s, mesh_s, 'K', 1);
            med_cm = median(d_cm); p95_cm = prctile(d_cm, 95);
            med_mc = median(d_mc); p95_mc = prctile(d_mc, 95);
            pass = med_cm <= 1.5 * s50 && p95_cm <= 4 * s50 && ...
                med_mc <= 1.5 * s50 && p95_mc <= 4 * s50;
            meas = struct('s50', s50, 'cloud_sample', ns, 'mesh_sample', nfs, ...
                'med_cloud_to_mesh', med_cm, 'p95_cloud_to_mesh', p95_cm, ...
                'med_mesh_to_cloud', med_mc, 'p95_mesh_to_cloud', p95_mc, ...
                'gate_med', 1.5 * s50, 'gate_p95', 4 * s50);
        end

        function meas = membrane_surface_distances(cloud, V, faces, s50, support)
            %MEMBRANE_SURFACE_DISTANCES M7 of the membrane fit: distances
            %to the surface itself, not to sampled face centres. The
            %centre-sample distance of membrane_deviation_gate (5000 random
            %face centres) is mostly the spacing of those samples: half the
            %square root of the mesh area per sample is 0.0012-0.0015 model
            %units on the four rabbit recordings, as large as its own
            %median limit (1.5 s50 = 0.0015-0.0019), so it measures the
            %sampling, not the fit. Here every face carries a fixed
            %barycentric grid of points (no random numbers; spacing about
            %a quarter of s50 or finer) and
            %  cloud -> surface  every cloud point to its nearest surface point
            %  vertex -> cloud   every mesh vertex to its nearest cloud point
            %are measured against the fit's support distance (support_mm in
            %model units: the fit counts a point as data for the surface
            %within it, and cuts surface that has no data within it).
            meas = struct('reason', '');
            if isempty(faces)
                meas.reason = 'no faces';
                return;
            end
            edge = median(sqrt(sum((V(faces(:, 1), :) - V(faces(:, 2), :)) .^ 2, 2)));
            n = min(16, max(4, ceil(4 * edge / max(s50, eps))));   % grid steps per edge
            [a, b] = meshgrid(0:n, 0:n);
            keep = a + b <= n;
            a = a(keep) / n; b = b(keep) / n;                      % barycentric weights of the grid
            P1 = V(faces(:, 1), :); P2 = V(faces(:, 2), :); P3 = V(faces(:, 3), :);
            nf = size(faces, 1);
            S = zeros(nf * numel(a), 3);
            for k = 1:numel(a)
                S((k - 1) * nf + (1:nf), :) = P1 + a(k) * (P2 - P1) + b(k) * (P3 - P1);
            end
            [~, d_cs] = knnsearch(S, cloud);
            [~, d_vc] = knnsearch(cloud, V);
            meas = struct('support', support, 's50', s50, ...
                'surface_samples', size(S, 1), 'sample_spacing', edge / n, ...
                'cloud_points', size(cloud, 1), 'mesh_vertices', size(V, 1), ...
                'med_cloud_to_surface', median(d_cs), 'p95_cloud_to_surface', prctile(d_cs, 95), ...
                'cloud_within_support', mean(d_cs <= support), ...
                'med_vertex_to_cloud', median(d_vc), 'p95_vertex_to_cloud', prctile(d_vc, 95), ...
                'vertices_within_support', mean(d_vc <= support), 'reason', '');
        end

        function [gates, notes] = membrane_verdicts(gates)
            %MEMBRANE_VERDICTS PASS / WARN / FAIL of the membrane fit's gates
            % The M1-M10 limits were set for the alpha-shape mesh, whose
            % vertices are the cloud points; the membrane fit takes them
            % over. A
            % membrane is a smooth surface through a cloud that has a
            % thickness, so three of them measure the cloud rather than a
            % broken mesh. On the four rabbit recordings of the SfM study
            % (its recipe, the tab's mesh step) every membrane
            % mesh missed M4 and M9, and three of four missed M7, while
            % fitting the tissue silhouettes:
            %   M4  96.4-98.1 % of the camera observations lie on the outer
            %       side of the surface (99 % needed), but 98.9-99.5 % do
            %       within 10 degrees of grazing: the misses are cameras
            %       that saw a noisy point almost edge-on. An inside-out
            %       mesh turns this round (about 2-4 % on the outer side).
            %       FAIL below MIN_M4_WITHIN_10DEG within 10 degrees (part
            %       of the mesh faces away from its cameras), WARN below 99 %.
            %   M7  surface distances (membrane_surface_distances) instead
            %       of face-centre samples, in units of the fit's support
            %       distance d. FAIL when the median cloud point is farther
            %       than d from the surface (the mesh does not follow the
            %       cloud) or fewer than 90 % of the vertices have a cloud
            %       point within d (surface without data); PASS when the
            %       median is within d/2, 95 % of the cloud within d and
            %       98 % of the vertices within d; WARN between. Measured:
            %       median 0.12-0.14 d, p95 0.51-1.08 d, 99.0-99.5 % of the
            %       vertices (the alpha-shape centre-sample rule fails on
            %       three of the four, by 1-27 % of its limit).
            %   M9  RHYTHM DIRECT views (Gloschat et al. 2018; Laughner et
            %       al. 2012): a membrane vertex takes the camera list of
            %       the nearest dense point, so the cameras that saw that
            %       point near grazing or near the outline count against
            %       it; 79-91 % of the observations are DIRECT (98 %
            %       needed; 3-9 % miss on the angle, 6-13 % on the outline
            %       weight). RHYTHM colours a vertex from its DIRECT views,
            %       so what reprojection needs is that the observed
            %       vertices have one: 90.9-93.5 % do. FAIL when fewer than
            %       MIN_VERTEX_DIRECT (75 %: well below the four recordings,
            %       well above an inside-out or misplaced mesh, near 0) do,
            %       WARN when the alpha-shape rule is missed otherwise.
            % The other gates (M1-M3, M5, M6, M8, M10) keep their limits
            % and FAIL when missed. pass keeps the alpha-shape rule (M7: the
            % PASS rule above); verdict is what the run acts on.
            notes = struct('code', {}, 'verdict', {}, 'text', {});
            names = fieldnames(gates);
            for k = 1:numel(names)
                g = gates.(names{k});
                if g.pass
                    g.verdict = 'PASS';
                else
                    g.verdict = 'FAIL';
                end
                gates.(names{k}) = g;
            end
            % ---- M4: orientation ----
            m = gates.M4.measured;
            if ~gates.M4.pass && m.n_observations > 0 && ...
                    m.agreement_within_10deg_of_grazing >= rabbit_mesh_cleanup.MIN_M4_WITHIN_10DEG
                gates.M4.verdict = 'WARN';
            end
            gates.M4.rule = sprintf(['membrane: PASS when >= 99 %% of the observations have their camera on ' ...
                'the outer side; FAIL when < %.0f %% do within 10 degrees of grazing; WARN between'], ...
                100 * rabbit_mesh_cleanup.MIN_M4_WITHIN_10DEG);
            notes = rabbit_mesh_cleanup.add_note(notes, 'M4', gates.M4.verdict, sprintf(['%.1f %% of the camera observations lie ' ...
                'on the outer side of the surface (99 %% for PASS); %.1f %% do within 10 degrees of grazing ' ...
                '(%.0f %% needed)'], 100 * m.agreement, 100 * m.agreement_within_10deg_of_grazing, ...
                100 * rabbit_mesh_cleanup.MIN_M4_WITHIN_10DEG));
            % ---- M7: surface distances ----
            m = gates.M7.measured;
            gates.M7.rule = ['membrane: distances to the surface in units of the fit''s support distance d; ' ...
                'PASS median <= d/2, p95 <= d and >= 98 % of the vertices within d; FAIL median > d or ' ...
                '< 90 % of the vertices within d; WARN between'];
            if ~isempty(m.reason)
                gates.M7.pass = false;
                gates.M7.verdict = 'FAIL';
                notes = rabbit_mesh_cleanup.add_note(notes, 'M7', 'FAIL', m.reason);
            else
                d = m.support;
                gates.M7.pass = m.med_cloud_to_surface <= 0.5 * d && m.p95_cloud_to_surface <= d && ...
                    m.vertices_within_support >= 0.98;
                if gates.M7.pass
                    gates.M7.verdict = 'PASS';
                elseif m.med_cloud_to_surface > d || m.vertices_within_support < 0.90
                    gates.M7.verdict = 'FAIL';
                else
                    gates.M7.verdict = 'WARN';
                end
                % The note names the PASS conditions the mesh missed, and
                % what each count is over
                missed = {};
                if m.med_cloud_to_surface > 0.5 * d, missed{end + 1} = 'median above d/2'; end
                if m.p95_cloud_to_surface > d, missed{end + 1} = '95th percentile above d'; end
                if m.vertices_within_support < 0.98, missed{end + 1} = 'below 98 % of the vertices within d'; end
                miss_txt = '';
                if ~isempty(missed), miss_txt = sprintf('; missed for PASS: %s', strjoin(missed, ', ')); end
                n_cloud = '';
                n_vert = '';
                if isfield(m, 'cloud_points'), n_cloud = sprintf(' (%d cloud points)', m.cloud_points); end
                if isfield(m, 'mesh_vertices'), n_vert = sprintf(' %d', m.mesh_vertices); end
                notes = rabbit_mesh_cleanup.add_note(notes, 'M7', gates.M7.verdict, sprintf(['cloud to surface%s: ' ...
                    'median %.2f d, 95th percentile %.2f d, d = support distance %.3g in the mesh''s units ' ...
                    '(PASS: d/2 and d; FAIL: median above d); %.1f %% of the%s vertices have a cloud point ' ...
                    'within d (PASS: 98 %%; FAIL: below 90 %%)%s'], n_cloud, m.med_cloud_to_surface / d, ...
                    m.p95_cloud_to_surface / d, d, 100 * m.vertices_within_support, n_vert, miss_txt));
            end
            % ---- M9: RHYTHM DIRECT views ----
            m = gates.M9.measured;
            if ~gates.M9.pass && isfield(m, 'vertices_with_direct_fraction') && m.n_vertices_observed > 0 && ...
                    m.vertices_with_direct_fraction >= rabbit_mesh_cleanup.MIN_VERTEX_DIRECT
                gates.M9.verdict = 'WARN';
            end
            gates.M9.rule = sprintf(['membrane: PASS as for the alpha shape (>= 98 %% DIRECT, every camera ' ...
                '>= 95 %%); FAIL when < %.0f %% of the observed vertices have a DIRECT camera; WARN between'], ...
                100 * rabbit_mesh_cleanup.MIN_VERTEX_DIRECT);
            if isfield(m, 'vertices_with_direct_fraction')
                notes = rabbit_mesh_cleanup.add_note(notes, 'M9', gates.M9.verdict, sprintf(['%.1f %% of the camera observations ' ...
                    'are DIRECT for RHYTHM (98 %% for PASS; %d cameras below 95 %%); %.1f %% of the observed ' ...
                    'vertices have a DIRECT camera (%.0f %% needed)'], 100 * m.aggregate_direct, ...
                    numel(m.cameras_below_95), 100 * m.vertices_with_direct_fraction, ...
                    100 * rabbit_mesh_cleanup.MIN_VERTEX_DIRECT));
            end
        end

        function notes = add_note(notes, code, verdict, text)
            %ADD_NOTE One gate note (membrane_verdicts)
            notes(end+1) = struct('code', code, 'verdict', verdict, 'text', text);
        end

        % =============================================================
        % M4 fixture: deliberately reversed normals must be corrected to
        % >= 99% agreement (deterministic, fixed seed).
        % =============================================================

        function [ok, msg] = mesh_normal_fixture()
            % Realistic visibility: camera j sees point i only when the
            % point's outward normal points toward the camera (the
            % camera-facing hemisphere) - the same structure as the real
            % .vis association (a camera images only the surface it
            % faces). The visibility score is only reliable on
            % observations that are actually visible.
            rng(42);
            n = 2000;
            p = randn(n, 3);
            p = p ./ sqrt(sum(p .* p, 2));   % unit sphere
            nrm = p;                          % outward normals
            % 4 exterior cameras (tetrahedral coverage).
            C = [3 0 0; 0 3 0; 0 0 3; -2 -2 -2];
            C = C ./ sqrt(sum(C .* C, 2)) * 3;
            vis = cell(n, 1);
            for i = 1:n
                vis{i} = int32(find(dot(repmat(p(i, :), 4, 1), C - repmat(p(i, :), 4, 1), 2) > 0) - 1);
            end
            % 100% reversal variant.
            nrm_r = -nrm;
            [~, st] = rabbit_mesh_cleanup.orient_normals(p, nrm_r, vis, C, ones(n, 1), 16);
            ok100 = st.agreement >= 0.99;
            % 5% random subset reversal variant.
            nrm_r5 = nrm;
            rng(42);
            flip5 = rand(n, 1) < 0.05;
            nrm_r5(flip5, :) = -nrm_r5(flip5, :);
            [~, st5] = rabbit_mesh_cleanup.orient_normals(p, nrm_r5, vis, C, ones(n, 1), 16);
            ok5 = st5.agreement >= 0.99;
            ok = ok100 && ok5;
            msg = sprintf('100%% reversal agreement %.4f; 5%% reversal agreement %.4f', st.agreement, st5.agreement);
        end

        % =============================================================
        % PLY I/O (byte-aligned; the COLMAP fused layout is 6 float32 +
        % 3 uchar = 27 bytes/vertex; the output layout is what the
        % rabbit_rhythm_reproject PLY reader expects: float32 xyz + extra
        % scalar properties + face list uint8 count + uint32 indices).
        % =============================================================

        function [xyz, nrm, rgb, nv] = read_ply_27(path)
            fid = fopen(path, 'rb');
            if fid < 0, error('analyse_om:Reconstruction:MeshCleanup', 'Cannot open %s', path); end
            cleanup = onCleanup(@() fclose(fid));
            nv = 0; vtypes = {}; cur = '';
            while true
                ln = fgetl(fid);
                if ~ischar(ln), error('analyse_om:Reconstruction:MeshCleanup', 'Unterminated PLY header in %s', path); end
                if strncmp(strtrim(ln), 'end_header', 10), break; end
                tok = strsplit(strtrim(ln));
                if numel(tok) < 2, continue; end
                switch lower(tok{1})
                    case 'element'
                        cur = lower(tok{2});
                        if numel(tok) >= 3
                            if strcmp(cur, 'vertex'), nv = str2double(tok{3}); end
                        end
                    case 'property'
                        if strcmp(cur, 'vertex') && numel(tok) >= 3
                            vtypes{end+1} = lower(tok{2}); %#ok<AGROW>
                        end
                end
            end
            if nv == 0, error('analyse_om:Reconstruction:MeshCleanup', 'No vertex element in %s', path); end
            % Record layout: first 3 properties must be float x/y/z.
            if numel(vtypes) < 3 || ~all(strcmp(vtypes(1:3), {'float', 'float', 'float'}))
                error('analyse_om:Reconstruction:MeshCleanup', 'Unsupported vertex layout in %s (x/y/z must be float32).', path);
            end
            rec = 0;
            for t = 1:numel(vtypes)
                rec = rec + rabbit_mesh_cleanup.scalar_size(vtypes{t});
            end
            raw = fread(fid, nv * rec, '*uint8');
            if numel(raw) < nv * rec
                error('analyse_om:Reconstruction:MeshCleanup', 'Vertex data truncated in %s (declared %d, record %d bytes).', path, nv, rec);
            end
            raw = reshape(raw, rec, nv)';
            xyz = rabbit_mesh_cleanup.vec3(raw, 1, vtypes);
            nrm = zeros(nv, 3);
            if numel(vtypes) >= 6 && all(strcmp(vtypes(4:6), {'float', 'float', 'float'}))
                nrm = rabbit_mesh_cleanup.vec3(raw, 4, vtypes);
            end
            rgb = zeros(nv, 3, 'uint8');
            if numel(vtypes) >= 9 && all(strcmp(vtypes(7:9), {'uchar', 'uchar', 'uchar'}))
                rgb = raw(:, 25:27);
            end
        end

        function write_ply(path, xyz, nrm, rgb, faces)
            fid = fopen(path, 'wb');
            if fid < 0, error('analyse_om:Reconstruction:MeshCleanup', 'Cannot write %s', path); end
            cleanup = onCleanup(@() fclose(fid));
            nv = size(xyz, 1);
            nf = size(faces, 1);
            fprintf(fid, 'ply\n');
            fprintf(fid, 'format binary_little_endian 1.0\n');
            fprintf(fid, 'element vertex %d\n', nv);
            fprintf(fid, 'property float x\nproperty float y\nproperty float z\n');
            fprintf(fid, 'property float nx\nproperty float ny\nproperty float nz\n');
            fprintf(fid, 'property uchar red\nproperty uchar green\nproperty uchar blue\n');
            fprintf(fid, 'element face %d\n', nf);
            fprintf(fid, 'property list uchar int vertex_indices\n');
            fprintf(fid, 'end_header\n');
            rec = zeros(nv, 27, 'uint8');
            xyzv = single(xyz');
            nrmv = single(nrm');
            rec(:, 1:12) = reshape(typecast(xyzv(:), 'uint8'), 12, nv)';
            rec(:, 13:24) = reshape(typecast(nrmv(:), 'uint8'), 12, nv)';
            rec(:, 25:27) = uint8(rgb);
            fwrite(fid, rec', 'uint8');
            if nf > 0
                % PLY face-list format: per face, one uchar count then
                % the uint32 indices (interleaved - the reader reads
                % cnt then cnt indices per face).
                for f = 1:nf
                    fwrite(fid, uint8(3), 'uint8');
                    fwrite(fid, uint32(faces(f, :) - 1), 'uint32');
                end
            end
        end

        % =============================================================
        % M2 outlier removal (Rusu et al. 2008; k=16 mean-NN, z > 3.0).
        % =============================================================

        function [keep, stats] = outlier_mask(xyz, k, z)
            n = size(xyz, 1);
            kk = min(k + 1, n);
            [~, d] = knnsearch(xyz, xyz, 'K', kk);
            mean_nn = mean(d(:, 2:end), 2);
            m = mean(mean_nn);
            s = std(mean_nn);
            if s < eps
                s = 1;
            end
            thresh = m + z * s;
            keep = mean_nn <= thresh;
            stats = struct('m', m, 's', s, 'thresh', thresh);
        end

        % =============================================================
        % Spacing stats (k-th NN distance, as used by M10).
        % =============================================================

        function [s50, s95] = spacing_stats(xyz, k)
            n = size(xyz, 1);
            kk = min(k + 1, n);
            [~, d] = knnsearch(xyz, xyz, 'K', kk);
            dk = d(:, end);
            s50 = median(dk);
            s95 = prctile(dk, 95);
        end

        % =============================================================
        % M4 orientation: per-surface-region sign by camera visibility
        % with local continuity propagation.
        % =============================================================

        function [nrm_o, stats] = orient_normals(xyz, nrm, vis, centers, comps, k)
            n = size(xyz, 1);
            nrm_o = nrm;
            % k-NN adjacency for continuity propagation.
            kk = min(k, n - 1);
            [idx, ~] = knnsearch(xyz, xyz, 'K', kk + 1);
            idx = idx(:, 2:end);
            n_regions = max(comps);
            for reg = 1:n_regions
                members = find(comps == reg);
                if isempty(members), continue; end
                % Seed: the member with the highest |visibility score|.
                sc = zeros(numel(members), 1);
                for mi = 1:numel(members)
                    i = members(mi);
                    s = 0; c = 0;
                    for j = 1:numel(vis{i})
                        v = centers(vis{i}(j) + 1, :) - xyz(i, :);
                        nv = norm(v);
                        if nv < 1e-12, continue; end
                        s = s + dot(nrm_o(i, :), v) / nv;
                        c = c + 1;
                    end
                    if c > 0, sc(mi) = s / c; end
                end
                [~, si] = max(abs(sc));
                seed = members(si);
                % BFS propagation: flip a neighbour when its normal
                % disagrees with the parent (local continuity).
                visited = false(n, 1);
                visited(seed) = true;
                queue = seed;
                while ~isempty(queue)
                    cur = queue(1);
                    queue(1) = [];
                    for j = 1:size(idx, 2)
                        nb = idx(cur, j);
                        if visited(nb) || comps(nb) ~= reg, continue; end
                        visited(nb) = true;
                        if dot(nrm_o(nb, :), nrm_o(cur, :)) < 0
                            nrm_o(nb, :) = -nrm_o(nb, :);
                        end
                        queue(end+1) = nb; %#ok<AGROW>
                    end
                end
                % Region aggregate: recompute the visibility score with the
                % FINAL normals; flip the whole region if negative.
                agg = 0; c = 0;
                for mi = 1:numel(members)
                    i = members(mi);
                    for j = 1:numel(vis{i})
                        v = centers(vis{i}(j) + 1, :) - xyz(i, :);
                        nv = norm(v);
                        if nv < 1e-12, continue; end
                        agg = agg + dot(nrm_o(i, :), v) / nv;
                        c = c + 1;
                    end
                end
                if c > 0 && agg < 0
                    nrm_o(members, :) = -nrm_o(members, :);
                end
            end
            % Agreement with the camera-visibility convention.
            pos = 0; tot = 0;
            for i = 1:n
                for j = 1:numel(vis{i})
                    v = centers(vis{i}(j) + 1, :) - xyz(i, :);
                    nv = norm(v);
                    if nv < 1e-12, continue; end
                    tot = tot + 1;
                    if dot(nrm_o(i, :), v) / nv > 0, pos = pos + 1; end
                end
            end
            stats = struct('agreement', pos / max(tot, 1), ...
                'positive_fraction', pos / max(tot, 1), 'n_regions', n_regions);
        end

        % =============================================================
        % alphaShape surface (Edelsbrunner & Muecke 1994).
        % =============================================================

        function [faces, comps, stats] = alpha_surface(xyz, alpha)
            %ALPHA_SURFACE Alpha-complex surface (Edelsbrunner & Muecke
            %1994), implemented directly on the Delaunay triangulation.
            %
            % MATLAB's alphaShape (checked in R2026a) does not honour the
            % alpha radius on general-position point sets: boundaryFacets
            % returns faces with circumradii 5-20x the requested alpha.
            % The alpha complex below honours it by construction: keep
            % tetrahedra with circumradius <= alpha; boundary faces are
            % faces shared by exactly one kept tetrahedron.
            n = size(xyz, 1);
            if n < 4
                faces = zeros(0, 3);
                comps = ones(n, 1);
                stats = struct('n_regions', 0, 'n_faces', 0, 'volume', 0);
                return;
            end
            DT = delaunayTriangulation(xyz);
            T = DT.ConnectivityList;
            nt = size(T, 1);
            % Circumradius per tetrahedron: solve for the circumcenter.
            R = zeros(nt, 1);
            for t = 1:nt
                p1 = xyz(T(t, 1), :); p2 = xyz(T(t, 2), :);
                p3 = xyz(T(t, 3), :); p4 = xyz(T(t, 4), :);
                A = 2 * [p2 - p1; p3 - p1; p4 - p1];
                b = [p2 * p2' - p1 * p1'; p3 * p3' - p1 * p1'; p4 * p4' - p1 * p1'];
                c = A \ b;
                R(t) = norm(c - p1);
            end
            keep = R <= alpha;
            n_keep = sum(keep);
            if n_keep == 0
                faces = zeros(0, 3);
                comps = ones(n, 1);
                stats = struct('n_regions', 0, 'n_faces', 0, 'volume', 0, ...
                    'n_tetrahedra', nt, 'n_kept', 0, 'alpha', alpha);
                return;
            end
            % Boundary faces: faces of kept tetrahedra shared by exactly
            % one kept tetrahedron.
            faceMap = containers.Map('KeyType', 'char', 'ValueType', 'int32');
            for t = 1:nt
                if ~keep(t), continue; end
                for f = 1:4
                    v = T(t, setdiff(1:4, f));
                    key = sprintf('%d_%d_%d', min(v), median(v), max(v));
                    if isKey(faceMap, key)
                        faceMap(key) = faceMap(key) + 1;
                    else
                        faceMap(key) = int32(1);
                    end
                end
            end
            keys_ = keys(faceMap);
            faces = zeros(0, 3);
            for k = 1:numel(keys_)
                if faceMap(keys_{k}) == 1
                    tok = strsplit(keys_{k}, '_');
                    faces(end+1, :) = [str2double(tok{1}) str2double(tok{2}) str2double(tok{3})]; %#ok<AGROW>
                end
            end
            comps = ones(n, 1);
            if ~isempty(faces)
                comps = rabbit_mesh_cleanup.face_components(faces, n);
            end
            stats = struct('n_regions', numel(unique(comps(comps > 0))), ...
                'n_faces', size(faces, 1), 'volume', 0, ...
                'n_tetrahedra', nt, 'n_kept', n_keep, 'alpha', alpha);
        end

        function comps = face_components(faces, n)
            % Connected components of the surface: vertices joined by the
            % face edges; per-vertex component id 1..k (0 = vertex not in
            % any face). An earlier face-walk version only queued a
            % neighbouring face when its first vertex was still unlabelled,
            % so one connected surface could be split into several pieces.
            comps = zeros(n, 1);
            if isempty(faces), return; end
            ev = [faces(:, [1 2]); faces(:, [2 3]); faces(:, [3 1])];
            A = sparse(ev(:, 1), ev(:, 2), 1, n, n);
            vc = conncomp(graph(A + A'))';
            in_face = false(n, 1);
            in_face(faces(:)) = true;
            % Renumber the components that hold faces as 1..k
            [~, ~, comps(in_face)] = unique(vc(in_face), 'stable');
        end

        function [faces_v, n_trimmed] = trim_visible_shell(xyz, nrm, faces, vis, lookns)
            %TRIM_VISIBLE_SHELL Keep faces whose oriented normal is
            %within 95 deg of at least one camera that imaged the face's
            %vertices (M8 open-shell target: the unsupported back side
            %of a closed alpha shape is invented geometry and is removed;
            %the M9 RHYTHM DIRECT check uses the same 95-deg threshold,
            %MIN_ANGLE_DIRECT).
            F = size(faces, 1);
            if F == 0
                faces_v = faces;
                n_trimmed = 0;
                return;
            end
            keepf = false(F, 1);
            cos95 = cosd(95);
            for f = 1:F
                a = faces(f, 1); b = faces(f, 2); c = faces(f, 3);
                fn = cross(xyz(b, :) - xyz(a, :), xyz(c, :) - xyz(a, :));
                ln = norm(fn);
                if ln < 1e-12, continue; end
                fn = fn / ln;
                % Face normal agrees with the oriented vertex normals.
                vn = (nrm(a, :) + nrm(b, :) + nrm(c, :)) / 3;
                if dot(fn, vn) < 0, fn = -fn; end
                % Cameras that imaged any of the face's vertices.
                cams = unique([vis{a}(:)', vis{b}(:)', vis{c}(:)']) + 1;
                for j = 1:numel(cams)
                    if dot(fn, lookns(cams(j), :)) <= cos95
                        keepf(f) = true;
                        break;
                    end
                end
            end
            faces_v = faces(keepf, :);
            n_trimmed = F - sum(keepf);
        end

        % =============================================================
        % M5: connected components (one primary; strays < 1% of primary
        % area removed with mask recorded).
        % =============================================================

        function [pass, meas, faces_out, comps_out] = component_gate(faces, comps, xyz)
            F = size(faces, 1);
            if F == 0
                pass = false;
                meas = struct('n_components', 0, 'reason', 'no faces');
                faces_out = faces;
                comps_out = comps;
                return;
            end
            fcomp = comps(faces(:, 1));
            areas = rabbit_mesh_cleanup.face_areas(faces, xyz);
            ucomp = unique(fcomp);
            tot = zeros(numel(ucomp), 1);
            for c = 1:numel(ucomp)
                tot(c) = sum(areas(fcomp == ucomp(c)));
            end
            [~, pi_] = max(tot);
            primary = ucomp(pi_);
            stray_frac = 1 - tot(pi_) / sum(tot);
            pass = stray_frac < 0.01;
            meas = struct('n_components', numel(ucomp), 'primary', primary, ...
                'stray_fraction', stray_frac, 'primary_area', tot(pi_), 'total_area', sum(tot));
            keepf = fcomp == primary;
            faces_out = faces(keepf, :);
            comps_out = comps;
            comps_out(comps ~= primary) = 0;
        end

        function areas = face_areas(faces, xyz)
            F = size(faces, 1);
            areas = zeros(F, 1);
            for f = 1:F
                a = faces(f, 1); b = faces(f, 2); c = faces(f, 3);
                cr = cross(xyz(b, :) - xyz(a, :), xyz(c, :) - xyz(a, :));
                areas(f) = 0.5 * norm(cr);
            end
        end

        % =============================================================
        % M6: degenerate faces (zero-area <= 0.1%; duplicate-index faces
        % removed with count recorded).
        % =============================================================

        function [pass, meas, faces_out] = degenerate_gate(faces, xyz)
            F = size(faces, 1);
            faces_out = faces;
            if F == 0
                pass = false;
                meas = struct('n_faces', 0, 'reason', 'no faces');
                return;
            end
            dup = faces(:, 1) == faces(:, 2) | faces(:, 2) == faces(:, 3) | faces(:, 1) == faces(:, 3);
            n_dup = sum(dup);
            faces_out = faces(~dup, :);
            p1 = xyz(faces_out(:, 1), :);
            p2 = xyz(faces_out(:, 2), :);
            p3 = xyz(faces_out(:, 3), :);
            cr = cross(p2 - p1, p3 - p1, 2);
            zarea = sqrt(sum(cr .* cr, 2)) < 1e-12;
            n_zero = sum(zarea);
            rate = n_zero / max(size(faces_out, 1), 1);
            pass = rate <= 0.001;
            meas = struct('n_faces', F, 'n_duplicate_index', n_dup, ...
                'n_zero_area', n_zero, 'zero_area_rate', rate, ...
                'n_faces_after', size(faces_out, 1));
            faces_out = faces_out(~zarea, :);
        end

        % =============================================================
        % M8: boundary edges + holes (open shell; holes with perimeter
        % <= 5% of total boundary perimeter acceptable; NO hole-filling).
        % =============================================================

        function [pass, meas] = boundary_gate(faces, xyz)
            F = size(faces, 1);
            if F == 0
                pass = false;
                meas = struct('n_boundary_edges', 0, 'reason', 'no faces');
                return;
            end
            edgeMap = containers.Map('KeyType', 'char', 'ValueType', 'int32');
            for f = 1:F
                for e = 1:3
                    a = faces(f, e);
                    b = faces(f, mod(e, 3) + 1);
                    key = sprintf('%d_%d', min(a, b), max(a, b));
                    if isKey(edgeMap, key)
                        edgeMap(key) = edgeMap(key) + 1;
                    else
                        edgeMap(key) = int32(1);
                    end
                end
            end
            keys_ = keys(edgeMap);
            bkeys = {};
            for k = 1:numel(keys_)
                if edgeMap(keys_{k}) == 1
                    bkeys{end+1} = keys_{k}; %#ok<AGROW>
                end
            end
            n_boundary = numel(bkeys);
            if n_boundary == 0
                % Watertight (closed) surface. M8 accepts a closed surface
                % only if it does not alter reprojection: the caller
                % re-checks M7/M9 on the chosen candidate and sets M8 to
                % FAIL if either fails (the closure then invented
                % unsupported surface).
                pass = true;
                meas = struct('n_boundary_edges', 0, 'n_loops', 0, ...
                    'watertight', true, ...
                    'note', 'closed surface; acceptable only if mesh fit (M7) and direct views (M9) pass');
                return;
            end
            loops = rabbit_mesh_cleanup.trace_loops(bkeys);
            n_loops = numel(loops);
            % Loop perimeters in native units.
            perims = zeros(n_loops, 1);
            for l = 1:n_loops
                lp = loops{l};
                for e = 1:numel(lp)
                    a = lp(e);
                    b = lp(mod(e, numel(lp)) + 1);
                    perims(l) = perims(l) + norm(xyz(a, :) - xyz(b, :));
                end
            end
            [~, li] = max(perims);
            rim = li;
            hole_frac = 1 - perims(rim) / sum(perims);
            pass = hole_frac <= 0.05;
            meas = struct('n_boundary_edges', n_boundary, 'n_loops', n_loops, ...
                'watertight', false, ...
                'rim_loop', rim, 'rim_perimeter', perims(rim), ...
                'total_boundary_perimeter', sum(perims), ...
                'hole_fraction_by_perimeter', hole_frac, ...
                'loop_perimeters', perims, 'loop_edge_counts', cellfun(@numel, loops));
        end

        function loops = trace_loops(bkeys)
            % Trace boundary edges into loops (each boundary edge appears
            % in exactly one loop; edges are undirected).
            loops = {};
            used = false(1, numel(bkeys));
            for k = 1:numel(bkeys)
                if used(k), continue; end
                loop = [];
                cur = bkeys{k};
                used(k) = true;
                while true
                    tok = strsplit(cur, '_');
                    a = str2double(tok{1}); b = str2double(tok{2});
                    loop(end+1) = a; %#ok<AGROW>
                    nxt = '';
                    for j = 1:numel(bkeys)
                        if used(j), continue; end
                        tok2 = strsplit(bkeys{j}, '_');
                        a2 = str2double(tok2{1}); b2 = str2double(tok2{2});
                        if a2 == b || b2 == b
                            nxt = bkeys{j};
                            used(j) = true;
                            if a2 == b, cur = sprintf('%d_%d', b, b2);
                            else, cur = sprintf('%d_%d', b, a2); end
                            break;
                        end
                    end
                    if isempty(nxt), break; end
                end
                loops{end+1} = loop; %#ok<AGROW>
            end
        end

        % =============================================================
        % M7: bidirectional deviation on fixed samples (median <= 1.5*s50,
        % p95 <= 4*s50, both directions).
        % =============================================================

        function [pass, meas] = deviation_gate(work, faces, s50, sample_n, seed)
            n = size(work, 1);
            F = size(faces, 1);
            if F == 0
                pass = false;
                meas = struct('reason', 'no faces');
                return;
            end
            rng(seed);
            ns = min(sample_n, n);
            cloud_s = work(randsample(n, ns), :);
            centroids = (work(faces(:, 1), :) + work(faces(:, 2), :) + work(faces(:, 3), :)) / 3;
            nf = size(centroids, 1);
            nfs = min(sample_n, nf);
            mesh_s = centroids(randsample(nf, nfs), :);
            [~, d_cm] = knnsearch(mesh_s, cloud_s, 'K', 1);
            [~, d_mc] = knnsearch(cloud_s, mesh_s, 'K', 1);
            med_cm = median(d_cm); p95_cm = prctile(d_cm, 95);
            med_mc = median(d_mc); p95_mc = prctile(d_mc, 95);
            pass = med_cm <= 1.5 * s50 && p95_cm <= 4 * s50 && ...
                med_mc <= 1.5 * s50 && p95_mc <= 4 * s50;
            meas = struct('s50', s50, 'cloud_sample', ns, 'mesh_sample', nfs, ...
                'med_cloud_to_mesh', med_cm, 'p95_cloud_to_mesh', p95_cm, ...
                'med_mesh_to_cloud', med_mc, 'p95_mesh_to_cloud', p95_mc, ...
                'gate_med', 1.5 * s50, 'gate_p95', 4 * s50);
        end

        % =============================================================
        % M9: RHYTHM DIRECT visibility gate (langle >= 95 deg and
        % ledge >= 0.9; the dataProjection02 constants). Per-vertex, using
        % the .vis association and the COLMAP camera model (SIMPLE_PINHOLE
        % exact; the RHYTHM camera conversion reproduces COLMAP pinhole
        % pixels to ~3e-14 px).
        % =============================================================

        function [pass, meas] = direct_visibility_gate(xyz, nrm, faces, cameras, images, vis, lookns)
            n = size(xyz, 1);
            nviews = numel(images);
            par = zeros(3, nviews);
            dims = zeros(nviews, 2);
            for i = 1:nviews
                cm = cameras(images(i).camera_id);
                if strcmp(cm.model, 'SIMPLE_PINHOLE')
                    par(:, i) = cm.params(1:3)';
                else
                    par(1, i) = cm.params(1);
                    par(2, i) = cm.params(3);
                    par(3, i) = cm.params(4);
                end
                % Image size as [rows cols] = [height width], the order
                % sub2ind and the bounds checks below expect
                dims(i, :) = [cm.height cm.width];
            end
            % langle per (vertex, seeing camera).
            langle = cell(n, 1);
            for i = 1:n
                langle{i} = zeros(1, numel(vis{i}));
                for j = 1:numel(vis{i})
                    c = vis{i}(j) + 1;
                    g = dot(nrm(i, :), lookns(c, :));
                    g = max(-1, min(1, g));
                    langle{i}(j) = acos(g) * 180 / pi;
                end
            end
            % ledge per (vertex, seeing camera): cone-filtered edge weight
            % of the view's silhouette (RHYTHM conefilt, replicated inline;
            % EDGE_FILT_VAL = 16). Only front faces (langle > 90). As in
            % dataProjection02 the silhouette is the whole projected mesh,
            % hole-filled; building it from only the vertices that see the
            % camera left a scatter of dots, so ledge stayed near 0.1.
            ledge = cell(n, 1);
            for i = 1:n
                ledge{i} = zeros(1, numel(vis{i}));
            end
            for c = 1:nviews
                % Vertices that see camera c.
                sees = find(cellfun(@(v) any(v + 1 == c), vis));
                if isempty(sees), continue; end
                X = zeros(numel(sees), 1); Y = zeros(numel(sees), 1);
                ok = false(numel(sees), 1);
                for si = 1:numel(sees)
                    i = sees(si);
                    pc = rabbit_mesh_cleanup.project_pinhole(xyz(i, :), images(c), par(:, c));
                    if pc(3) > 0
                        X(si) = pc(1); Y(si) = pc(2);
                        ok(si) = X(si) >= 1 && X(si) <= dims(c, 2) && Y(si) >= 1 && Y(si) <= dims(c, 1);
                    end
                end
                if isempty(faces)
                    geom = zeros(dims(c, 1), dims(c, 2));
                    ix = sub2ind(dims(c, :), round(Y(ok)), round(X(ok)));
                    geom(unique(ix)) = 1;
                    geom = imfill(geom, 'holes');
                else
                    geom = rabbit_mesh_cleanup.view_silhouette(xyz, faces, images(c), par(:, c), dims(c, :));
                end
                conesilh = rabbit_mesh_cleanup.conefilt(geom, rabbit_mesh_cleanup.EDGE_FILT_VAL, 1);
                for si = 1:numel(sees)
                    i = sees(si);
                    if ~ok(si), continue; end
                    j = find(vis{i} + 1 == c, 1);
                    if langle{i}(j) <= 90, continue; end
                    ledge{i}(j) = interp2(conesilh, X(si), Y(si));
                end
            end
            % DIRECT membership.
            pos = 0; tot = 0; per_cam = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            n_angle = 0; n_edge = 0;          % observations that miss on the angle / on the edge weight
            v_seen = 0; v_direct = 0;         % vertices with any observation / with a DIRECT one
            for i = 1:n
                any_direct = false;
                for j = 1:numel(vis{i})
                    c = vis{i}(j) + 1;
                    tot = tot + 1;
                    lv = ledge{i}(j);
                    if isnan(lv), lv = 0; end
                    angle_ok = langle{i}(j) >= rabbit_mesh_cleanup.MIN_ANGLE_DIRECT;
                    direct = angle_ok && lv >= rabbit_mesh_cleanup.MIN_EDGE_DIRECT;
                    n_angle = n_angle + double(~angle_ok);
                    n_edge = n_edge + double(angle_ok && ~direct);
                    any_direct = any_direct || direct;
                    if direct, pos = pos + 1; end
                    if isKey(per_cam, int32(c))
                        v = per_cam(int32(c));
                        v(1) = v(1) + double(direct);
                        v(2) = v(2) + 1;
                        per_cam(int32(c)) = v;
                    else
                        per_cam(int32(c)) = [double(direct) 1];
                    end
                end
                if ~isempty(vis{i})
                    v_seen = v_seen + 1;
                    v_direct = v_direct + double(any_direct);
                end
            end
            agg = pos / max(tot, 1);
            cids = keys(per_cam);
            below = [];
            per = struct();
            for k = 1:numel(cids)
                v = per_cam(cids{k});
                frac = v(1) / max(v(2), 1);
                per.(sprintf('img%d', cids{k})) = struct('direct', v(1), 'total', v(2), 'fraction', frac);
                if frac < 0.95, below(end+1) = cids{k}; end
            end
            pass = agg >= 0.98 && isempty(below);
            % Also recorded (not part of the pass rule): why observations
            % are not DIRECT, and how many observed vertices have at least
            % one DIRECT camera (the vertices RHYTHM can colour)
            meas = struct('aggregate_direct', agg, 'n_observations', tot, ...
                'cameras_below_95', below, 'per_camera', per, ...
                'not_direct_angle_fraction', n_angle / max(tot, 1), ...
                'not_direct_edge_fraction', n_edge / max(tot, 1), ...
                'n_vertices_observed', v_seen, 'vertices_with_direct', v_direct, ...
                'vertices_with_direct_fraction', v_direct / max(v_seen, 1));
        end

        function geom = view_silhouette(xyz, faces, im, par, dims)
            % Silhouette of the mesh in one view (dims = [rows cols]): the
            % faces are sampled on a barycentric grid fine enough that
            % neighbouring samples land at most half a pixel apart, the
            % samples are rounded to pixels and the result is hole-filled
            % (the same sampling rabbit_rhythm_reproject uses for the
            % dataProjection02 silhouettes).
            R = rabbit_mesh_cleanup.qvec2rot(im.qvec);
            f = par(1); cx = par(2); cy = par(3);
            Xc = xyz * R' + im.tvec(:)';
            u = f * Xc(:, 1) ./ Xc(:, 3) + cx;
            v = f * Xc(:, 2) ./ Xc(:, 3) + cy;
            % Longest projected edge of each face, in pixels
            edge_px = zeros(size(faces, 1), 1);
            for e = 1:3
                a = faces(:, e);
                b = faces(:, mod(e, 3) + 1);
                edge_px = max(edge_px, hypot(u(a) - u(b), v(a) - v(b)));
            end
            n_sub = max(1, ceil(edge_px / 0.5));
            n_sub(~isfinite(n_sub)) = 1;
            n_sub = min(n_sub, 64);    % a face seen almost edge-on from behind the camera
            used = unique(faces(:));
            parts = {xyz(used, :)};
            for n = unique(n_sub(n_sub > 1))'
                [bi, bj] = meshgrid(0:n, 0:n);
                keep = bi + bj <= n;
                w = [bi(keep), bj(keep)] / n;
                fi = find(n_sub == n);
                V1 = xyz(faces(fi, 1), :); V2 = xyz(faces(fi, 2), :); V3 = xyz(faces(fi, 3), :);
                P = zeros(numel(fi) * size(w, 1), 3);
                for q = 1:size(w, 1)
                    P((q - 1) * numel(fi) + (1:numel(fi)), :) = w(q, 1) * V1 + w(q, 2) * V2 + ...
                        (1 - w(q, 1) - w(q, 2)) * V3;
                end
                parts{end + 1} = P; %#ok<AGROW>
            end
            P = vertcat(parts{:});
            Pc = P * R' + im.tvec(:)';
            x = round(f * Pc(:, 1) ./ Pc(:, 3) + cx);
            y = round(f * Pc(:, 2) ./ Pc(:, 3) + cy);
            ok = Pc(:, 3) > 0 & x >= 1 & x <= dims(2) & y >= 1 & y <= dims(1);
            geom = zeros(dims(1), dims(2));
            geom(unique(sub2ind(dims, y(ok), x(ok)))) = 1;
            geom = imfill(geom, 'holes');
        end

        function txt = check_names(codes)
            % Plain names of the mesh checks, for messages the user reads
            names = struct('M1', 'coordinates are numbers', 'M2', 'outlier removal keeps the cloud', ...
                'M3', 'normals have unit length', 'M4', 'normals face the cameras', ...
                'M5', 'the surface is one piece', 'M6', 'no degenerate faces', ...
                'M7', 'the mesh follows the cloud', 'M8', 'the open edge is clean', ...
                'M9', 'the cameras see the surface directly (RHYTHM)', 'M10', 'point spacing is kept');
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

        function b = best_candidate(sweep)
            %BEST_CANDIDATE Pick the sweep candidate closest to passing
            %   M4-M8 for the FAIL-path M9 measurement: most gates
            %   passed, tie-break by lowest M7 p95 cloud->mesh deviation.
            %   Returns [] when the sweep is empty or no candidate has a
            %   surface (all M4-M8 measured 'no surface').
            b = [];
            best_score = -1;
            best_p95 = inf;
            for a = 1:numel(sweep)
                if ~isfield(sweep(a), 'm4') || ~isfield(sweep(a), 'm7')
                    continue;
                end
                if isfield(sweep(a).m4.measured, 'reason')
                    continue; % no surface
                end
                score = double(sweep(a).m4.pass) + double(sweep(a).m5.pass) + ...
                    double(sweep(a).m6.pass) + double(sweep(a).m7.pass) + ...
                    double(sweep(a).m8.pass);
                p95 = inf;
                if isfield(sweep(a).m7.measured, 'p95_cloud_to_mesh')
                    p95 = sweep(a).m7.measured.p95_cloud_to_mesh;
                end
                if score > best_score || (score == best_score && p95 < best_p95)
                    best_score = score;
                    best_p95 = p95;
                    b = sweep(a);
                end
            end
        end

        function pc = project_pinhole(p, im, par)
            % COLMAP world->camera: X_cam = R*X + t; u = f*x/z + cx.
            R = rabbit_mesh_cleanup.qvec2rot(im.qvec);
            Xc = R * p(:) + im.tvec(:);
            f = par(1); cx = par(2); cy = par(3);
            pc = [f * Xc(1) / Xc(3) + cx; f * Xc(2) / Xc(3) + cy; Xc(3)];
        end

        function R = qvec2rot(q)
            w = q(1); x = q(2); y = q(3); z = q(4);
            R = [1 - 2 * (y^2 + z^2), 2 * (x * y - z * w), 2 * (x * z + y * w);
                2 * (x * y + z * w), 1 - 2 * (x^2 + z^2), 2 * (y * z - x * w);
                2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x^2 + y^2)];
        end

        function out = conefilt(data, width, slope)
            %CONEFILT Replicates the vendored RHYTHM conefilt.m (ORIENT
            %files, dataProjection02 edgefiltval 16): a cone kernel
            %convolved with the mask ('same').
            kernel = zeros(width, width);
            for i = 0:width - 1
                for j = 0:width - 1
                    kernel(i + 1, j + 1) = floor((width - 1) * slope / 2 + 1 - slope * sqrt((i - (width - 1) / 2)^2 + (j - (width - 1) / 2)^2));
                    if kernel(i + 1, j + 1) < 0, kernel(i + 1, j + 1) = 0; end
                end
            end
            kernel = kernel .* (1 / sum(sum(kernel)));
            out = conv2(data, kernel, 'same');
        end

        % =============================================================
        % Face winding: orient faces so their normals agree with the
        % oriented vertex normals (self-consistent outward mesh).
        % =============================================================

        function faces = orient_faces(xyz, nrm, faces)
            F = size(faces, 1);
            for f = 1:F
                a = faces(f, 1); b = faces(f, 2); c = faces(f, 3);
                fn = cross(xyz(b, :) - xyz(a, :), xyz(c, :) - xyz(a, :));
                ln = norm(fn);
                if ln < 1e-12, continue; end
                fn = fn / ln;
                vn = (nrm(a, :) + nrm(b, :) + nrm(c, :)) / 3;
                if dot(fn, vn) < 0
                    faces(f, 2:3) = faces(f, [3 2]);
                end
            end
        end

        % =============================================================
        % COLMAP model readers (poses only; the mesh cleanup needs camera
        % centres + look directions for the visibility gates).
        % =============================================================

        function [cameras, images, ok, err] = read_colmap_model(images_bin)
            cameras = containers.Map('KeyType', 'int64', 'ValueType', 'any');
            images = struct('id', {}, 'qvec', {}, 'tvec', {}, 'camera_id', {}, 'name', {});
            ok = false;
            err = '';
            cam_bin = fullfile(fileparts(images_bin), 'cameras.bin');
            if ~exist(cam_bin, 'file')
                err = sprintf('cameras.bin missing next to %s', images_bin);
                return;
            end
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
                if np > 0
                    fread(fid, [3 np], 'double');
                end
                images(end+1) = struct('id', im_id, 'qvec', qvec, 'tvec', tvec, ...
                    'camera_id', cam_id, 'name', name); %#ok<AGROW>
            end
            fclose(fid);
            ok = true;
        end

        function n = camera_num_params(model_id)
            table_ = {0 3; 1 4; 2 4; 3 5; 4 8; 5 8; 6 12; 7 5; 8 4; 9 5; 10 12};
            n = 0;
            for k = 1:size(table_, 1)
                if table_{k, 1} == model_id, n = table_{k, 2}; return; end
            end
        end

        function name = camera_model_name(model_id)
            names = {'SIMPLE_PINHOLE', 'PINHOLE', 'SIMPLE_RADIAL', 'RADIAL', 'OPENCV', ...
                'OPENCV_FISHEYE', 'FULL_OPENCV', 'FOV', 'SIMPLE_RADIAL_FISHEYE', ...
                'RADIAL_FISHEYE', 'THIN_PRISM_FISHEYE'};
            if model_id >= 0 && model_id < numel(names)
                name = names{model_id + 1};
            else
                name = 'UNKNOWN';
            end
        end

        function centers = camera_centres(images)
            n = numel(images);
            centers = zeros(n, 3);
            for i = 1:n
                R = rabbit_mesh_cleanup.qvec2rot(images(i).qvec);
                centers(i, :) = (-R' * images(i).tvec(:))';
            end
        end

        function lookns = camera_lookns(images)
            n = numel(images);
            lookns = zeros(n, 3);
            for i = 1:n
                R = rabbit_mesh_cleanup.qvec2rot(images(i).qvec);
                lookns(i, :) = (R' * [0; 0; 1])';
            end
        end

        % =============================================================
        % .vis reader (COLMAP fused-geometric.ply.vis): uint64 count,
        % then per vertex uint32 n_images + n_images x int32 image ids
        % (0-based into images.bin order).
        % =============================================================

        function [vis, ok, err] = read_vis(path)
            vis = {};
            ok = false;
            err = '';
            fid = fopen(path, 'rb');
            if fid < 0, err = sprintf('cannot open %s', path); return; end
            cleanup = onCleanup(@() fclose(fid));
            n = fread(fid, 1, 'uint64');
            if isempty(n), err = 'empty .vis'; return; end
            for i = 1:n
                ni = fread(fid, 1, 'uint32');
                if isempty(ni), err = 'truncated .vis'; return; end
                ids = fread(fid, ni, 'int32');
                if numel(ids) < ni, err = 'truncated .vis ids'; return; end
                vis{i} = int32(ids(:)'); %#ok<AGROW>
            end
            ok = true;
        end

        % =============================================================
        % Helpers.
        % =============================================================

        function v = vec3(raw, off, vtypes)
            % Read 3 float32 columns starting at property index off.
            n = size(raw, 1);
            v = zeros(n, 3);
            for c = 0:2
                col = off + c;
                if col > numel(vtypes), break; end
                if strcmp(vtypes{col}, 'float') || strcmp(vtypes{col}, 'float32')
                    v(:, c + 1) = double(typecast(reshape(raw(:, (col - 1) * 4 + 1:col * 4)', 4 * n, 1), 'single'));
                elseif strcmp(vtypes{col}, 'double') || strcmp(vtypes{col}, 'float64')
                    v(:, c + 1) = typecast(reshape(raw(:, (col - 1) * 8 + 1:col * 8)', 8 * n, 1), 'double');
                end
            end
        end

        function s = scalar_size(type)
            switch lower(type)
                case {'char', 'int8', 'uchar', 'uint8'}, s = 1;
                case {'short', 'int16', 'ushort', 'uint16'}, s = 2;
                case {'int', 'int32', 'uint', 'uint32', 'float', 'float32'}, s = 4;
                case {'double', 'float64'}, s = 8;
                otherwise, s = 0;
            end
        end

        function h = sha256_file(path)
            fid = fopen(path, 'rb');
            if fid < 0
                d = dir(path);
                h = sprintf('size-%d', d.bytes);
                return;
            end
            data = fread(fid, Inf, '*uint8');
            fclose(fid);
            md = java.security.MessageDigest.getInstance('SHA-256');
            digest = md.digest(data);
            db = int8(digest);
            ub = typecast(db, 'uint8');
            h = lower(reshape(dec2hex(ub, 2)', 1, []));
        end

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

        function r = finish_fail(r, out_ply, out_gates, out_mask, fused_ply, xyz, nrm, rgb, keep)
            % Write the failed outputs (keep them, never retry silently)
            % and record the input file.
            r.artifacts(end+1) = struct('path', fused_ply, 'sha256', rabbit_mesh_cleanup.sha256_file(fused_ply));
            if ~isempty(keep)
                save(out_mask, 'keep');
                r.artifacts(end+1) = struct('path', out_mask, 'sha256', rabbit_mesh_cleanup.sha256_file(out_mask));
            end
            % The method comes first, so a reader of the top of the file
            % (the viewer's mesh label) finds it
            method = ''; source = '';
            if isfield(r, 'mesh_method')
                method = r.mesh_method;
                source = r.cloud_source;
            end
            record = struct('stage', 'mesh_cleanup', 'mesh_method', method, ...
                'cloud_source', source, ...
                'input', fused_ply, 'verdict', 'FAIL', 'error', r.err, ...
                'gates', r.gates);
            fid = fopen(out_gates, 'w', 'n', 'UTF-8');
            if fid > 0
                fprintf(fid, '%s', jsonencode(record, 'PrettyPrint', true));
                fclose(fid);
            end
            r.gates_json = out_gates;
            r.artifacts(end+1) = struct('path', out_gates, 'sha256', rabbit_mesh_cleanup.sha256_file(out_gates));
        end
    end
end
