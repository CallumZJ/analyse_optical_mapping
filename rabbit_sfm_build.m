classdef rabbit_sfm_build
    %% Build the sparse model (COLMAP structure from motion) for a run
    % Collin Snitchler
    % 14.10.2026
    % The "Build sparse model" steps of the Reconstruction tab: choose and
    % prepare the cut reconstruction images, run the COLMAP commands of an
    % SfM recipe, check the result and keep the model. The tab
    % (rabbit_reconstruction_tab) runs the steps and records them.
    %
    % The default recipe (rabbit_4view_v1) is the result of a rabbit SfM
    % parameter study (COLMAP 4.2.1 on the four reference rabbit rotation
    % recordings: one main recording, an SFOV and an LFOV recording and one
    % of the old rig; all images of every recording registered in one
    % model with it). The study is not published; its result is this
    % recipe. Its parts, and why each is needed:
    %   Frames     about 40 frames evenly spread over the recording:
    %              stride = max(1, floor(N/40)). This gives the study's
    %              strides 2, 3, 6 and 30 for N = 100, 120, 240 and 1200
    %              frames.
    %   Tiles      per view, a linear stretch between the nearest-rank 1st
    %              and 99.5th percentiles of all pixels of that view over
    %              all chosen frames (the same limits for every frame), to
    %              uint8; then CLAHE (Zuiderveld 1994) with MATLAB
    %              adapthisteq, 8x8 tiles, ClipLimit 1/255, 256 bins,
    %              uniform. ClipLimit 1/255 is the MATLAB equivalent of
    %              OpenCV clipLimit 2.0: MATLAB clips at n/256 + c(n - n/256)
    %              counts, OpenCV at 2n/256, so c = 1/255 (adapthisteq and
    %              OpenCV createCLAHE documentation). Without CLAHE ALIKED
    %              finds about 60 keypoints per tile and no model forms.
    %   Masks      tissue silhouette per image, for --ImageReader.mask_path:
    %              Otsu's threshold (Otsu 1979) on the log of the stretched
    %              tile, smoothed with a Gaussian of sigma 2 px; largest
    %              8-connected region, holes filled, dilated by a disk of
    %              8 px. The undilated silhouette (score mask) is kept for
    %              the mesh step.
    %   Mirrors    each planar mirror reverses the handedness of the image
    %              (a mirror view is a virtual camera with the same
    %              intrinsics, Gluckman & Nayar 2001), so a view seen
    %              through an odd number of mirrors is a reflection of
    %              those seen through an even number, and
    %              ALIKED + LightGlue match neither mirrored nor upside-down
    %              views. The two outer tiles (left-most and right-most in
    %              the frame) are always flipped left-right; each of them
    %              may also need a 180 degree turn (fliplr then rot90(.,2),
    %              which is flipud). The turn is found by building the model
    %              once with both outer tiles turned 0 and once turned 180
    %              and keeping, per outer tile, the turn under which more of
    %              its images registered (the study: the other turn
    %              registered none, on all four recordings). The recipe can
    %              fix the turn per outer tile or with one switch for the
    %              whole camera (orientation.camera_upside_down).
    %   Cameras    one SIMPLE_RADIAL camera per view; focal length fixed at
    %              8000 px, a round value inside the old rig's
    %              self-calibration (7740-8218 px) and 2-5 % below the
    %              thin-lens estimate (a 50 mm lens at 0.6-0.9 m images at
    %              52.9-54.5 mm = 8140-8390 px of 6.5 um; under the
    %              near-affine projection of this rig a focal error mainly
    %              becomes a depth scale; refining the focal length
    %              ran away to 1477-20598 px because, with the heart about
    %              0.02 of the distance across, focal length and depth
    %              cannot be told apart); principal point at the tile
    %              centre and the radial term fixed at 0. COLMAP 4.2.1
    %              treats a camera whose principal point lies outside the
    %              image as bogus (src/colmap/sensor/models.h,
    %              HasBogusPrincipalPoint), so the true optical axis of a
    %              cropped tile (Hartley & Zisserman 2004, sec. 6.1) cannot
    %              be used; for f = 8000 px the tile centre is a 1.5-5.8
    %              degree virtual turn of each view (tile centres 207-811 px
    %              from the frame centre, which is itself not the measured
    %              optical axis) that the pose absorbs to first order (the
    %              residual is below about 0.6 px at the tile edges).
    %              COLMAP 4.2.1 image_undistorter keeps these cameras as
    %              they are (no distortion to remove: it copies the images
    %              "already undistorted"); the tab then writes the exactly
    %              equivalent PINHOLE cameras (f, f, cx, cy) of the same
    %              size for the dense steps, the mesh and the reprojection
    %              (rabbit_reconstruction_tab.pinhole_undistorted_cameras).
    %   Features   ALIKED_N32 (Zhao et al. 2023), at most 4096 keypoints,
    %              min_score 0.05; matching ALIKED_LIGHTGLUE (Lindenberger,
    %              Sarlin & Pollefeys 2023), exhaustive, at least 60 inliers
    %              per pair (15 lets random cross-view pairs through; the
    %              true ones have 100-230), stationary matches filtered.
    %   Mapper     COLMAP incremental mapper (Schoenberger & Frahm 2016) with
    %              max_focal_length_ratio 100 (8000 px over a ~400 px tile
    %              is ~20, above the default 10: HasBogusFocalLength),
    %              init_min_tri_angle 2, init_min_num_inliers 30,
    %              abs_pose_min_num_inliers 15 and the other values in
    %              defaults().
    %   Depth guard  under near-affine projection a model and its depth-
    %              reversed (Necker) twin fit the images equally well
    %              (Koenderink & van Doorn 1991; Tomasi & Kanade 1992;
    %              Szeliski & Kang 1997). For each image, the fraction of
    %              its observed points nearer the camera than the per-axis
    %              median of the cloud; the mean over the images must be at
    %              least 0.6 (seen: correct 0.88-0.99, reversed
    %              0.002-0.12). Seeds 1 to 5 are tried in order and the
    %              first model that passes is kept; when none passes the
    %              step fails rather than keep a reversed model.
    %   Rig        COLMAP rig support (doc/rigs.rst, "Unknown rig sensor
    %              poses"): a first mapper pass without the rig,
    %              rig_configurator --input_path <that model> derives the
    %              sensor poses, then the mapper runs again with the rig.
    %              The reference sensor must be the first camera of the rig
    %              file: COLMAP 4.2.1 rig_configurator --input_path exits
    %              with 0xC0000409 and no message otherwise (found by the
    %              study). With the rig every image registers (main
    %              recording 200 vs 196-199, SFOV 160 vs 143).
    %   Mesh       a fused point is kept when it projects inside the score
    %              mask in at least 90 % of the registered images it lands
    %              in (rabbit_mesh_cleanup; recipe field mesh). The membrane
    %              fit has no silhouette cap (mesh.silhouette_cap, off): on
    %              the main recording the cap's own check switched it on by
    %              chance, and the capped mesh lost about 13 % of the
    %              surface the cloud supports. The 4 evenly spaced frames x 4 views stay
    %              the frames of the per-view mask check. Field band
    %              (mesh.field_band_px, 32 px, at most 64): a mask edge
    %              within 32 px of the tile border that stays still over
    %              the view's frames (sd at most 5 px) is taken as the edge
    %              of the mirror's field of view, not as the heart's
    %              outline; the pixels between it and the border do not
    %              judge a point (the filter, the silhouette cap, the cap's
    %              agreement check and A6 ignore them; static_field_bands).
    %              A heart limb near the border moves with the heart and
    %              keeps judging. Why: on the main recording, view 4's left
    %              mask edge is the mirror's field edge (static over the
    %              frames, sd 3.4 px, about 20 px from the tile border) with
    %              tissue continuing past it, and without the band the
    %              filter and the cap cut the mesh there.
    %              One open edge (mesh.single_open_edge, on): a second large
    %              unsupported region closer to the open edge (along the
    %              surface) than its own size is cut together with it, so a
    %              narrow strip of support leaves no hole; a region further
    %              away is cut and shows as a hole in M8; nothing
    %              unsupported is spanned (rabbit_membrane_fit). Why: on one
    %              run of the main recording the points the band keeps
    %              formed a narrow strip across the open base, and cutting
    %              both parts left a hole (M8 FAIL).
    %   The study's tests of the alternatives (SIFT, global_mapper, the
    %   GLOMAP-style global mapper of Pan et al. 2024, LoMa of Nordstroem
    %   et al. 2026, other inlier counts, a refined focal length) are listed
    %   in its report; none is part of this recipe.
    %
    % Recipe:
    %   A recipe is data: one struct, made by defaults(name) and checked by
    %   validate(). Changing the default recipe is a change to defaults()
    %   only. Its commands field is a list of COLMAP command templates, one
    %   per phase:
    %     features    feature_extractor (once per view) and the matcher,
    %                 run once per build;
    %     mapper      the mapper without the rig (repeated per seed);
    %     rig         rig_configurator (when rig.use);
    %     rig_mapper  the mapper with the rig (when rig.use, per seed).
    %   Each command is a subcommand, a list of --option value pairs and a
    %   time limit. Values may be tokens:
    %     path tokens  {DB} {IMAGES} {MASKS} {RIG} {VIEW_LIST} {SPARSE_OUT}
    %                  {INPUT_MODEL} {RIG_OUT}, replaced by quoted absolute
    %                  paths of the build;
    %     call tokens  {VIEW} {VIEW_CAMERA} (per-view commands) and
    %                  {MAPPER_SEED} (the seed being tried);
    %     field tokens {threads} {camera.model} ..., any recipe field,
    %                  written as text (logical as 1/0).
    %   A command or option runs only when its 'when' holds: '' (always),
    %   'a.b' (field true), '!a.b' (field false), 'a.b=TEXT' (equal) or
    %   'a.b~TEXT' (starts with). commands() always adds --log_target
    %   stderr, --log_color 0 and --default_random_seed, and refuses values
    %   with the characters % " & | ^ < > (they would reach the batch shell).
    %   Model files (ONNX): a model file named in the recipe is taken from
    %   the COLMAP models folder (step 3) when it is there, after its sha256
    %   is checked against the recipe; otherwise the option is left out and
    %   COLMAP uses its own default (a URL;name;sha256 triple: COLMAP
    %   downloads the file on first use, which needs network access, into
    %   its cache folder <home>/.cache/colmap and checks the sha256); the
    %   tab's tool check makes sure that default carries the sha256 the
    %   recipe pins, and the run records the cached file and its sha256
    %   (cached_model; rabbit_reconstruction_tab.sfm_model_sources).
    %
    % Images and cameras:
    %   The cut tiles <stem>_view<k>_frame_NNNN.tiff keep their names
    %   (view k = ROI row k, rows view2;view3;view1;view4 in the region
    %   editor's names), so the later steps find their views by name.
    %   Each view is one COLMAP camera (feature_extractor once per view
    %   with --ImageReader.single_camera 1 and an image list).
    %
    % Steps:
    %   resolve(R, ctx)    cut tiles, frames, outer tiles, cameras -> the
    %                      resolved recipe (inputs/sfm_recipe.json)
    %   prepare(Rr, ...)   stages/sparse_prep: per turn (0 and 180) the
    %                      prepared tiles, feature masks and score masks,
    %                      the image lists, rig_config.json and prep.json
    %   build(Rr, ...)     stages/sparse_build: the orientation builds,
    %                      the final build with the depth guard and the
    %                      rig, the chosen model and its registered images
    %                      and score masks, model_summary.json and
    %                      om_tile_transform.json
    %
    % Citations: COLMAP SfM (Schoenberger & Frahm 2016, CVPR) and MVS
    % (Schoenberger et al. 2016, ECCV); COLMAP rig documentation
    % (doc/rigs.rst of COLMAP 4.2.1) and source (src/colmap/sensor/models.h,
    % src/colmap/controllers/incremental_pipeline.cc); ALIKED (Zhao et al.
    % 2023, IEEE TIM 72, doi:10.1109/TIM.2023.3271000; BSD-3-Clause);
    % LightGlue (Lindenberger, Sarlin & Pollefeys 2023, ICCV; Apache-2.0);
    % CLAHE (Zuiderveld 1994, Graphics Gems IV); Otsu 1979 (IEEE Trans. SMC
    % 9(1):62-66); the depth-reversal ambiguity (Koenderink & van Doorn
    % 1991, JOSA A 8(2):377-385; Tomasi & Kanade 1992, IJCV 9(2):137-154;
    % Szeliski & Kang 1997, IEEE PAMI 19(5):506-512); Gluckman & Nayar
    % 2001 (mirror virtual cameras); Hartley & Zisserman 2004 (principal
    % point of a crop); the visual hull (Laurentini 1994, IEEE PAMI
    % 16(2):150-162) for the silhouette filter; SIFT (Lowe 2004) and GLOMAP (Pan et al. 2024) when
    % a custom recipe uses them.
    %
    % Section map (search for the quoted line; line numbers move)
    %   "% 1. Recipes"
    %   "% 2. Resolve: tiles, frames, outer tiles, cameras"
    %   "% 3. Orientation of the outer tiles"
    %   "% 4. Prepare the images (stage sparse_prep)"
    %   "% 5. Commands"
    %   "% 6. Build the model (stage sparse_build)"
    %   "% 7. Silhouette filter of the fused cloud (used by the mesh step)"
    %   "% 8. Small helpers"

    properties (Constant)
        SCHEMA = 2;            % recipe schema (independent of the tab's recipe_version)
        MAX_THREADS = 6;       % CPU threads per COLMAP command (reproducibility)
        PATH_TOKENS = {'DB', 'IMAGES', 'MASKS', 'RIG', 'VIEW_LIST', 'SPARSE_OUT', ...
            'INPUT_MODEL', 'RIG_OUT'};
        SUBCOMMANDS = {'feature_extractor', 'exhaustive_matcher', 'sequential_matcher', ...
            'vocab_tree_matcher', 'spatial_matcher', 'transitive_matcher', ...
            'rig_configurator', 'mapper', 'global_mapper', 'bundle_adjuster'};
        PHASES = {'features', 'mapper', 'rig', 'rig_mapper'};
        VIEW_NAMES = {'view2', 'view3', 'view1', 'view4'}; % region editor names of ROI rows 1-4
        % mesh.field_band_px upper limit: the field edges found lie 7-28 px
        % from the tile border (the four reference recordings and runs of
        % the main one); a wider band would abstain over the heart's own
        % outline and A6 would pass a too-large mesh with it
        MAX_FIELD_BAND_PX = 64;
    end

    methods (Static)

        % =============================================================
        % 1. Recipes
        % =============================================================

        function names = recipe_names()
            %% Names defaults() knows
            names = {'rabbit_4view_v1'};
        end

        function R = defaults(name)
            %% A named recipe
            % The only place the default values live.
            if nargin < 1 || isempty(name), name = 'rabbit_4view_v1'; end
            switch name
                case 'rabbit_4view_v1'
                    R = struct();
                    R.name = 'rabbit_4view_v1';
                    R.schema = rabbit_sfm_build.SCHEMA;
                    R.status = 'study';
                    R.note = ['Rabbit SfM study recipe (14.10.2026): ALIKED + LightGlue on stretched, ' ...
                        'CLAHE-equalised views with tissue masks; outer views flipped and turned as the ' ...
                        'images need; fixed 8000 px focal length; depth-reversal guard over seeds 1-5; ' ...
                        'four-view rig in a second mapper pass.'];
                    R.threads = 6;
                    % --default_random_seed of every COLMAP command (COLMAP's
                    % own default is 0)
                    R.random_seed = 0;
                    % Frames: frame_step [] = max(1, floor(N/target_frames));
                    % a number fixes the step; frames lists them outright
                    R.images = struct('target_frames', 40, 'frame_step', [], 'frames', [], 'views', 4);
                    R.preprocess = struct( ...
                        'intensity', 'stretch_clahe', ...  % none | stretch | stretch_clahe
                        'percentiles', [1 99.5], ...
                        'clahe', struct('num_tiles', [8 8], 'clip_limit', 1/255, ...
                        'nbins', 256, 'distribution', 'uniform'));
                    % Outer tiles: flipped left-right; turn 'auto' | '0' |
                    % '180' per outer tile (left, right); camera_upside_down
                    % 'auto' | 'no' | 'yes' sets both at once ('no': left 0,
                    % right 180, the pattern of the main and the old-rig
                    % recordings; 'yes': left 180, right 0, the pattern of
                    % the SFOV and LFOV recordings). A per-tile value wins
                    % over the switch.
                    % reuse_turns 'yes': a tile left to auto takes the turn
                    % an earlier finished run of the same recording, boxes
                    % and flips decided (turn_key), and the build runs once; it falls back
                    % to the orientation builds when that build fails the
                    % depth guard or an outer tile registers fewer than half
                    % of its images (known_turns, build). 'no', or missing
                    % (older recipes): always the two builds.
                    R.orientation = struct('outer_flip_lr', true, ...
                        'outer_turn', {{'auto', 'auto'}}, 'camera_upside_down', 'auto', 'reuse_turns', 'yes');
                    R.masks = struct('use', true, 'source', 'log_otsu', 'gauss_sigma', 2, 'dilate_px', 8);
                    R.camera = struct( ...
                        'model', 'SIMPLE_RADIAL', ...
                        'focal_prior_px', 8000, ...
                        'focal_source', ['8000 px: a round value inside the old rig self-calibration (7740-8218 px), ' ...
                        '2-5 % below the thin-lens estimate for 50 mm (Navitar DO-5095) at 0.6-0.9 m on 6.5 um ' ...
                        'pixels (Andor Zyla 5.5): 8140-8390 px'], ...
                        'principal_point', 'tile_centre', ...
                        'extra_params', '0', ...
                        'refine_focal', false, 'refine_pp', false, 'refine_extra', false);
                    % Rig: ref_view counts tiles from the left in the frame
                    % (2 = the second tile, the study's reference), whatever
                    % the ROI row of that tile
                    R.rig = struct('use', true, 'ref_view', 2, 'refine_sensor_from_rig', true);
                    R.features = struct('type', 'ALIKED_N32', 'max_num_features', 4096, ...
                        'min_score', 0.05, 'use_gpu', true, ...
                        'model_files', struct('option', '--AlikedExtraction.n32_model_path', ...
                        'file', 'aliked-n32.onnx', ...
                        'sha256', 'a077728a02d2de1a775c66df6de8cfeb7c6b51ca57572c64c680131c988c8b3c'));
                    R.matching = struct('type', 'ALIKED_LIGHTGLUE', 'guided', false, 'use_gpu', true, ...
                        'min_num_inliers', 60, 'max_error', 4, 'filter_stationary_matches', true, ...
                        'detect_watermark', false, 'lightglue_min_score', 0.1, ...
                        'model_files', struct('option', '--AlikedMatching.lightglue_model_path', ...
                        'file', 'aliked-lightglue.onnx', ...
                        'sha256', 'b9a5de7204648b18a8cf5dcac819f9d30de1a5961ef03756803c8b86c2dceb8d'));
                    R.mapper = struct('max_focal_length_ratio', 100, 'init_min_tri_angle', 2, ...
                        'init_min_num_inliers', 30, 'init_max_error', 4, 'tri_min_angle', 1.5, ...
                        'filter_min_tri_angle', 1.5, 'min_num_matches', 15, ...
                        'abs_pose_min_num_inliers', 15, 'abs_pose_max_error', 12, ...
                        'filter_max_reproj_error', 4);
                    R.guard = struct('use', true, 'seeds', [1 2 3 4 5], 'min_near_side_fraction', 0.6);
                    % field_band_px: a mask edge this close to the tile
                    % border that stays still over the view's frames is a
                    % field edge (static_field_bands; at most
                    % MAX_FIELD_BAND_PX). 32 px: on the main recording
                    % view 4's field edge lies about 20 px from the border
                    % (sd 3.4 px over the frames); with 32 px the per-view
                    % median mask coverage of its mesh rose from
                    % 69-90 % to 89-95 % and the mesh stays within 0.8 %
                    % of mask + band. 0 = off,
                    % which recipes written before this setting mean.
                    % single_open_edge: a large unsupported region near the
                    % open edge is cut together with it, so a strip of
                    % support leaves no hole (rabbit_membrane_fit); one
                    % run of the main recording had a hole without it.
                    % false = every large unsupported region is cut on its
                    % own, which recipes written before this setting mean.
                    % silhouette_cap: hold the membrane inside the masks
                    % that pass the agreement check. Off: a cap-on
                    % mesh lost about 13 % of the surface its cloud
                    % supports and whether the cap went on depended on GPU
                    % matching. true = the check decides,
                    % which recipes written before this setting mean.
                    R.mesh = struct('silhouette_filter_min_inside', 0.9, 'silhouette_frames', 4, ...
                        'field_band_px', 32, 'single_open_edge', true, 'silhouette_cap', false);
                    R.acceptance = struct( ...
                        'fail_registered_fraction', 0.3, ...
                        'warn_registered_fraction', 0.8, ...
                        'warn_min_images_per_view', 3, ...
                        'warn_mean_reproj_px', 2.0, ...
                        'warn_focal_change_frac', 0.25, ...
                        'tolerances', struct('n_registered_abs', 2, ...
                            'mean_reproj_px_abs', 0.2, 'n_points_rel', 0.1));
                    R.commands = rabbit_sfm_build.default_commands();
                otherwise
                    error('analyse_om:SparseModel:UnknownRecipe', 'There is no recipe called ''%s''.', name);
            end
        end

        function C = default_commands()
            %% The command templates of rabbit_4view_v1 (one per phase)
            % The options and values are those of the study's final runs
            % (the study's results.jsonl, tags F_jul, F_sfov, F_lfov, F_old).
            a = @(k, v, w) struct('key', k, 'value', v, 'when', w);
            fx = [a('--database_path', '{DB}', ''), ...
                a('--image_path', '{IMAGES}', ''), ...
                a('--image_list_path', '{VIEW_LIST}', ''), ...
                a('--ImageReader.mask_path', '{MASKS}', 'masks.use'), ...
                a('--ImageReader.single_camera', '1', ''), ...
                a('--ImageReader.camera_model', '{camera.model}', ''), ...
                a('--ImageReader.camera_params', '{VIEW_CAMERA}', ''), ...
                a('--FeatureExtraction.type', '{features.type}', ''), ...
                a('--FeatureExtraction.use_gpu', '{features.use_gpu}', ''), ...
                a('--FeatureExtraction.num_threads', '{threads}', ''), ...
                a('--AlikedExtraction.max_num_features', '{features.max_num_features}', 'features.type~ALIKED'), ...
                a('--AlikedExtraction.min_score', '{features.min_score}', 'features.type~ALIKED'), ...
                a('--SiftExtraction.max_num_features', '{features.max_num_features}', 'features.type=SIFT')];
            mt = [a('--database_path', '{DB}', ''), ...
                a('--FeatureMatching.type', '{matching.type}', ''), ...
                a('--FeatureMatching.use_gpu', '{matching.use_gpu}', ''), ...
                a('--FeatureMatching.num_threads', '{threads}', ''), ...
                a('--FeatureMatching.guided_matching', '{matching.guided}', ''), ...
                a('--TwoViewGeometry.min_num_inliers', '{matching.min_num_inliers}', ''), ...
                a('--TwoViewGeometry.max_error', '{matching.max_error}', ''), ...
                a('--TwoViewGeometry.filter_stationary_matches', '{matching.filter_stationary_matches}', ''), ...
                a('--TwoViewGeometry.detect_watermark', '{matching.detect_watermark}', ''), ...
                a('--AlikedMatching.lightglue_min_score', '{matching.lightglue_min_score}', 'matching.type=ALIKED_LIGHTGLUE')];
            mp = [a('--database_path', '{DB}', ''), ...
                a('--image_path', '{IMAGES}', ''), ...
                a('--output_path', '{SPARSE_OUT}', ''), ...
                a('--Mapper.num_threads', '{threads}', ''), ...
                a('--Mapper.random_seed', '{MAPPER_SEED}', ''), ...
                a('--Mapper.ba_refine_focal_length', '{camera.refine_focal}', ''), ...
                a('--Mapper.ba_refine_principal_point', '{camera.refine_pp}', ''), ...
                a('--Mapper.ba_refine_extra_params', '{camera.refine_extra}', ''), ...
                a('--Mapper.init_min_tri_angle', '{mapper.init_min_tri_angle}', ''), ...
                a('--Mapper.tri_min_angle', '{mapper.tri_min_angle}', ''), ...
                a('--Mapper.filter_min_tri_angle', '{mapper.filter_min_tri_angle}', ''), ...
                a('--Mapper.min_num_matches', '{mapper.min_num_matches}', ''), ...
                a('--Mapper.abs_pose_min_num_inliers', '{mapper.abs_pose_min_num_inliers}', ''), ...
                a('--Mapper.max_focal_length_ratio', '{mapper.max_focal_length_ratio}', ''), ...
                a('--Mapper.init_min_num_inliers', '{mapper.init_min_num_inliers}', ''), ...
                a('--Mapper.init_max_error', '{mapper.init_max_error}', ''), ...
                a('--Mapper.abs_pose_max_error', '{mapper.abs_pose_max_error}', ''), ...
                a('--Mapper.filter_max_reproj_error', '{mapper.filter_max_reproj_error}', ''), ...
                a('--Mapper.ba_refine_sensor_from_rig', '{rig.refine_sensor_from_rig}', '')];
            rc = [a('--database_path', '{DB}', ''), ...
                a('--rig_config_path', '{RIG}', ''), ...
                a('--input_path', '{INPUT_MODEL}', ''), ...
                a('--output_path', '{RIG_OUT}', '')];
            c = @(ph, sub, fe, w, t, lbl, args) struct('phase', ph, 'subcommand', sub, 'foreach', fe, ...
                'when', w, 'timeout_s', t, 'label', lbl, 'args', args);
            C = [c('features', 'feature_extractor', 'view', '', 1800, 'Find features (view {VIEW})', fx), ...
                c('features', 'exhaustive_matcher', '', '', 3600, 'Match features between all image pairs', mt), ...
                c('mapper', 'mapper', '', '', 3600, 'Register the images without the rig (seed {MAPPER_SEED})', mp), ...
                c('rig', 'rig_configurator', '', 'rig.use', 600, 'Set up the four-view rig from the first model', rc), ...
                c('rig_mapper', 'mapper', '', 'rig.use', 3600, 'Register the images with the rig (seed {MAPPER_SEED})', mp)];
        end

        function R = normalise(R)
            %% Shapes after jsondecode
            % jsondecode gives column vectors, [] for empty struct arrays
            % and cell arrays for lists of unlike objects; turn them back
            % into the shapes defaults() makes.
            if ~isstruct(R), return; end
            if isfield(R, 'preprocess')
                if isfield(R.preprocess, 'percentiles')
                    R.preprocess.percentiles = reshape(R.preprocess.percentiles, 1, []);
                end
                if isfield(R.preprocess, 'clahe') && isstruct(R.preprocess.clahe) && ...
                        isfield(R.preprocess.clahe, 'num_tiles')
                    R.preprocess.clahe.num_tiles = reshape(R.preprocess.clahe.num_tiles, 1, []);
                end
            end
            if isfield(R, 'images')
                for f = {'frames', 'frame_step'}
                    if isfield(R.images, f{1}), R.images.(f{1}) = reshape(R.images.(f{1}), 1, []); end
                end
            end
            if isfield(R, 'orientation') && isfield(R.orientation, 'outer_turn')
                t = R.orientation.outer_turn;
                if ischar(t) || isstring(t), t = cellstr(t); end
                if isnumeric(t), t = arrayfun(@(x) sprintf('%d', x), t, 'UniformOutput', false); end
                R.orientation.outer_turn = reshape(cellfun(@char, t, 'UniformOutput', false), 1, []);
            end
            if isfield(R, 'guard') && isfield(R.guard, 'seeds')
                R.guard.seeds = reshape(R.guard.seeds, 1, []);
            end
            for s = {'features', 'matching'}
                if isfield(R, s{1}) && isfield(R.(s{1}), 'model_files')
                    mf = R.(s{1}).model_files;
                    if isempty(mf)
                        mf = struct('option', {}, 'file', {}, 'sha256', {});
                    elseif iscell(mf)
                        mf = [mf{:}];
                    end
                    R.(s{1}).model_files = reshape(mf, 1, []);
                end
            end
            if isfield(R, 'commands')
                C = R.commands;
                if iscell(C), C = rabbit_sfm_build.cell_to_struct(C); end
                C = reshape(C, 1, []);
                for k = 1:numel(C)
                    if isfield(C(k), 'args')
                        A = C(k).args;
                        if isempty(A)
                            A = struct('key', {}, 'value', {}, 'when', {});
                        elseif iscell(A)
                            A = rabbit_sfm_build.cell_to_struct(A);
                        end
                        C(k).args = reshape(A, 1, []);
                    end
                end
                R.commands = C;
            end
        end

        function [ok, err] = validate(R)
            %% Check a recipe before it is used
            % Returns ok=false and a plain message for the first problem; a
            % field that is missing deeper in the recipe, or a value of the
            % wrong kind, is reported the same way (never a MATLAB error).
            try
                [ok, err] = rabbit_sfm_build.validate_fields(R);
            catch ME
                ok = false;
                err = sprintf(['The recipe is missing a field or has a value of the wrong kind (%s). Start ' ...
                    'from the default recipe (Details... > Save copy as JSON...) and make the changes again.'], ...
                    ME.message);
            end
        end

        function [ok, err] = validate_fields(R)
            %% validate() without the error guard
            ok = false; err = '';
            if ~isstruct(R) || ~isscalar(R)
                err = 'The recipe is not a single JSON object.'; return;
            end
            if ~isfield(R, 'schema') || ~isnumeric(R.schema) || ~isscalar(R.schema) || R.schema ~= rabbit_sfm_build.SCHEMA
                s = '(none)';
                if isfield(R, 'schema'), s = mat2str(R.schema); end
                err = sprintf(['The recipe has schema %s; this app reads schema %d. Start from the ' ...
                    'default recipe (Details... > Save copy as JSON...) and make the changes again.'], ...
                    s, rabbit_sfm_build.SCHEMA); return;
            end
            need = {'name', 'threads', 'random_seed', 'images', 'preprocess', 'orientation', ...
                'masks', 'camera', 'rig', 'features', 'matching', 'mapper', 'guard', 'mesh', ...
                'acceptance', 'commands'};
            for k = 1:numel(need)
                if ~isfield(R, need{k})
                    err = sprintf('The recipe has no ''%s'' field.', need{k}); return;
                end
            end
            if ~ischar(R.name) || isempty(regexp(R.name, '^[A-Za-z0-9_.-]+$', 'once'))
                err = 'The recipe name may only use letters, digits, _ . and -.'; return;
            end
            if ~rabbit_sfm_build.is_whole(R.threads) || R.threads < 1 || R.threads > rabbit_sfm_build.MAX_THREADS
                err = sprintf('threads must be a whole number from 1 to %d.', rabbit_sfm_build.MAX_THREADS); return;
            end
            if ~rabbit_sfm_build.is_whole(R.random_seed) || R.random_seed < 0
                err = 'random_seed must be a whole number of 0 or more.'; return;
            end
            I = R.images;
            if ~isempty(I.frame_step) && (~rabbit_sfm_build.is_whole(I.frame_step) || I.frame_step < 1)
                err = 'images.frame_step must be empty (automatic) or a whole number of 1 or more.'; return;
            end
            if ~rabbit_sfm_build.is_whole(I.target_frames) || I.target_frames < 2
                err = 'images.target_frames must be a whole number of 2 or more.'; return;
            end
            if ~isempty(I.frames) && (~isnumeric(I.frames) || any(~arrayfun(@rabbit_sfm_build.is_whole, I.frames)) || ...
                    any(I.frames < 1) || numel(unique(I.frames)) ~= numel(I.frames))
                err = ['images.frames must be empty (frame_step or target_frames decide) or a list of different ' ...
                    'whole frame numbers of 1 or more (it then replaces frame_step and target_frames).']; return;
            end
            if ~any(strcmp(R.preprocess.intensity, {'none', 'stretch', 'stretch_clahe'}))
                err = 'preprocess.intensity must be none, stretch or stretch_clahe.'; return;
            end
            p = R.preprocess.percentiles;
            if ~isnumeric(p) || numel(p) ~= 2 || p(1) < 0 || p(2) > 100 || p(1) >= p(2)
                err = 'preprocess.percentiles must be two increasing numbers between 0 and 100.'; return;
            end
            t = R.orientation.outer_turn;
            if ~iscell(t) || numel(t) ~= 2 || ~all(ismember(t, {'auto', '0', '180'}))
                err = 'orientation.outer_turn must hold two values, each auto, 0 or 180 (left and right outer view).'; return;
            end
            if ~any(strcmp(R.orientation.camera_upside_down, {'auto', 'no', 'yes'}))
                err = 'orientation.camera_upside_down must be auto, no or yes.'; return;
            end
            if isfield(R.orientation, 'reuse_turns') && ~any(strcmp(R.orientation.reuse_turns, {'yes', 'no'}))
                err = 'orientation.reuse_turns must be yes or no.'; return;
            end
            if logical(R.masks.use) && ~any(strcmp(R.masks.source, {'log_otsu', 'folder'}))
                err = 'masks.source must be log_otsu or folder.'; return;
            end
            if ~rabbit_sfm_build.is_whole(R.masks.dilate_px) || R.masks.dilate_px < 0
                err = 'masks.dilate_px must be a whole number of 0 or more (pixels).'; return;
            end
            if ~isnumeric(R.masks.gauss_sigma) || ~isscalar(R.masks.gauss_sigma) || R.masks.gauss_sigma <= 0
                err = 'masks.gauss_sigma must be a positive number (pixels).'; return;
            end
            if ~any(strcmp(R.camera.model, {'SIMPLE_PINHOLE', 'PINHOLE', 'SIMPLE_RADIAL', 'RADIAL'}))
                err = ['camera.model must be SIMPLE_PINHOLE, PINHOLE, SIMPLE_RADIAL or RADIAL (models ' ...
                    'image_undistorter turns into the pinhole cameras the dense steps need).']; return;
            end
            if ~strcmp(R.camera.principal_point, 'tile_centre')
                err = ['camera.principal_point must be tile_centre: COLMAP 4.2.1 rejects a camera whose ' ...
                    'principal point lies outside the image (HasBogusPrincipalPoint), which the true ' ...
                    'optical axis of most views does.']; return;
            end
            if ~isnumeric(R.camera.focal_prior_px) || ~isscalar(R.camera.focal_prior_px) || R.camera.focal_prior_px <= 0
                err = 'camera.focal_prior_px must be a positive number.'; return;
            end
            if ~ischar(R.camera.extra_params) || isempty(regexp(R.camera.extra_params, '^(-?[0-9.eE+-]+)?(,-?[0-9.eE+-]+)*$', 'once'))
                err = 'camera.extra_params must be numbers separated by commas (e.g. 0).'; return;
            end
            rv = R.rig.ref_view;
            if ~isnumeric(rv) || ~isscalar(rv) || ~any(rv == 1:4)
                err = 'rig.ref_view must be 1, 2, 3 or 4.'; return;
            end
            G = R.guard;
            if ~isnumeric(G.seeds) || isempty(G.seeds) || any(G.seeds ~= round(G.seeds)) || any(G.seeds < 0)
                err = 'guard.seeds must be a list of whole numbers of 0 or more.'; return;
            end
            if numel(unique(G.seeds)) ~= numel(G.seeds)
                err = 'guard.seeds lists a seed more than once; each seed gives the same model every time.'; return;
            end
            if ~isnumeric(G.min_near_side_fraction) || G.min_near_side_fraction <= 0 || G.min_near_side_fraction >= 1
                err = 'guard.min_near_side_fraction must lie between 0 and 1.'; return;
            end
            q = R.mesh.silhouette_filter_min_inside;
            if ~isnumeric(q) || ~isscalar(q) || q < 0 || q > 1
                err = 'mesh.silhouette_filter_min_inside must lie between 0 (off) and 1.'; return;
            end
            if ~rabbit_sfm_build.is_whole(R.mesh.silhouette_frames) || R.mesh.silhouette_frames < 0
                err = 'mesh.silhouette_frames must be a whole number (0 = all registered frames).'; return;
            end
            if isfield(R.mesh, 'field_band_px') && ...
                    (~rabbit_sfm_build.is_whole(R.mesh.field_band_px) || R.mesh.field_band_px < 0 || ...
                    R.mesh.field_band_px > rabbit_sfm_build.MAX_FIELD_BAND_PX)
                err = sprintf(['mesh.field_band_px must be a whole number of pixels from 0 (no field band) ' ...
                    'to %d.'], rabbit_sfm_build.MAX_FIELD_BAND_PX); return;
            end
            if isfield(R.mesh, 'single_open_edge') && (~isscalar(R.mesh.single_open_edge) || ...
                    ~(islogical(R.mesh.single_open_edge) || isnumeric(R.mesh.single_open_edge)) || ...
                    ~any(double(R.mesh.single_open_edge) == [0 1]))
                err = 'mesh.single_open_edge must be true or false.'; return;
            end
            if isfield(R.mesh, 'silhouette_cap') && (~isscalar(R.mesh.silhouette_cap) || ...
                    ~(islogical(R.mesh.silhouette_cap) || isnumeric(R.mesh.silhouette_cap)) || ...
                    ~any(double(R.mesh.silhouette_cap) == [0 1]))
                err = 'mesh.silhouette_cap must be true or false.'; return;
            end
            for s = {'features', 'matching'}
                mf = R.(s{1}).model_files;
                for k = 1:numel(mf)
                    if contains(mf(k).file, '://')
                        err = sprintf(['%s model file %s is a web address. Name the file (as COLMAP''s default ' ...
                            'names it); the app uses it from the COLMAP models folder, else COLMAP''s own ' ...
                            'checked download.'], s{1}, mf(k).file); return;
                    end
                    if isempty(regexp(mf(k).option, '^--[A-Za-z]+\.[A-Za-z0-9_]+_path$', 'once'))
                        err = sprintf('%s model option ''%s'' is not a COLMAP model path option.', s{1}, mf(k).option); return;
                    end
                    if isempty(regexp(mf(k).sha256, '^[0-9a-f]{64}$', 'once'))
                        err = sprintf('%s model file %s has no sha256 (64 hex characters).', s{1}, mf(k).file); return;
                    end
                    if ~isempty(regexp(mf(k).file, '[\\/%"&|^<>]', 'once'))
                        err = sprintf('%s model file ''%s'' must be a plain file name inside the models folder.', s{1}, mf(k).file); return;
                    end
                end
            end
            C = R.commands;
            if ~isstruct(C) || isempty(C) || ~isfield(C, 'phase')
                err = 'The recipe has no commands (each with a phase).'; return;
            end
            for k = 1:numel(C)
                if ~any(strcmp(C(k).phase, rabbit_sfm_build.PHASES))
                    err = sprintf('Command %d: phase must be features, mapper, rig or rig_mapper.', k); return;
                end
                if ~any(strcmp(C(k).subcommand, rabbit_sfm_build.SUBCOMMANDS))
                    err = sprintf('Command %d: ''%s'' is not a COLMAP command this step runs.', k, C(k).subcommand); return;
                end
                if ~any(strcmp(C(k).foreach, {'', 'view'}))
                    err = sprintf('Command %d: foreach must be empty or ''view''.', k); return;
                end
                if ~isnumeric(C(k).timeout_s) || C(k).timeout_s <= 0
                    err = sprintf('Command %d: timeout_s must be a positive number.', k); return;
                end
                A = C(k).args;
                for j = 1:numel(A)
                    if isempty(regexp(A(j).key, '^--[A-Za-z_][A-Za-z0-9_.]*$', 'once'))
                        err = sprintf('Command %d: ''%s'' is not a --option name.', k, A(j).key); return;
                    end
                    if any(strcmp(A(j).key, {'--log_target', '--log_color', '--default_random_seed', '--project_path'}))
                        err = sprintf('Command %d: %s is set by the app, not by the recipe.', k, A(j).key); return;
                    end
                    if ~ischar(A(j).value) && ~isstring(A(j).value)
                        err = sprintf('Command %d, %s: the value must be text.', k, A(j).key); return;
                    end
                    if ~isempty(regexp(char(A(j).value), '[%"&|^<>]', 'once'))
                        err = sprintf('Command %d, %s: the value contains a character the shell would read (%% " & | ^ < >).', k, A(j).key); return;
                    end
                    if ~isempty(regexp(char(A(j).value), '\s', 'once'))
                        err = sprintf('Command %d, %s: the value contains a space; use a path token instead.', k, A(j).key); return;
                    end
                end
            end
            ph = {C.phase};
            if ~any(strcmp(ph, 'features')) || nnz(strcmp(ph, 'mapper')) ~= 1
                err = 'The recipe needs feature commands and exactly one mapper command.'; return;
            end
            if logical(R.rig.use) && (nnz(strcmp(ph, 'rig')) ~= 1 || nnz(strcmp(ph, 'rig_mapper')) ~= 1)
                err = 'A recipe with the rig needs one rig_configurator (rig) and one rig_mapper command.'; return;
            end
            ok = true;
        end

        function d = deviations(R)
            %% Fields of R that differ from defaults(R.name)
            % One record per differing leaf (commands compared as a whole).
            d = struct('parameter', {}, 'old', {}, 'new', {});
            try
                D = rabbit_sfm_build.defaults(R.name);
            catch
                d(end+1) = struct('parameter', 'name', 'old', 'rabbit_4view_v1', 'new', R.name);
                return;
            end
            d = rabbit_sfm_build.diff_struct(D, R, '', d);
        end

        function lines = describe(R)
            %% Plain-text summary of a recipe (the Details... window)
            lines = {sprintf('Recipe: %s (%s)', R.name, R.status), R.note, ''};
            if isempty(R.images.frame_step)
                fr = sprintf('every max(1, floor(N/%d))-th frame of the N cut frames (about %d frames)', ...
                    R.images.target_frames, R.images.target_frames);
            else
                fr = sprintf('every %d. frame', R.images.frame_step);
            end
            if ~isempty(R.images.frames), fr = sprintf('frames %s', mat2str(R.images.frames)); end
            lines{end+1} = ['Frames: ' fr];
            lines{end+1} = sprintf(['Views: %s (percentiles %g / %g per view over all chosen frames; CLAHE %dx%d ' ...
                'views, clip limit %.6g)'], R.preprocess.intensity, R.preprocess.percentiles(1), ...
                R.preprocess.percentiles(2), R.preprocess.clahe.num_tiles(1), R.preprocess.clahe.num_tiles(2), ...
                R.preprocess.clahe.clip_limit);
            lines{end+1} = sprintf(['Outer views: flipped left-right %s; turn left %s, right %s; camera upside ' ...
                'down: %s (auto = build both turns and keep the one that registers); turns of an earlier run ' ...
                'of the same recording and boxes reused: %s'], ...
                rabbit_sfm_build.yes_no(R.orientation.outer_flip_lr), R.orientation.outer_turn{1}, ...
                R.orientation.outer_turn{2}, R.orientation.camera_upside_down, ...
                rabbit_sfm_build.pick(rabbit_sfm_build.reuses_turns(R), 'yes', 'no'));
            if logical(R.masks.use)
                if strcmp(R.masks.source, 'folder')
                    lines{end+1} = 'Masks: given per image (inputs/masks; from the assisted area segmentation when its checkbox was ticked)';
                else
                    lines{end+1} = sprintf('Masks: the run''s own tissue masks (%s, Gaussian sigma %g px, dilated %d px for the features)', ...
                        R.masks.source, R.masks.gauss_sigma, R.masks.dilate_px);
                end
            else
                lines{end+1} = 'Masks: off';
            end
            lines{end+1} = sprintf('Camera: %s per view, focal length %.0f px fixed (%s), principal point: %s', ...
                R.camera.model, R.camera.focal_prior_px, R.camera.focal_source, ...
                strrep(R.camera.principal_point, '_', ' '));
            lines{end+1} = sprintf(['Features: %s (%d keypoints); matching: %s, at least %d inliers; rig: %s ' ...
                '(reference: View%d from the left); threads: %d'], R.features.type, R.features.max_num_features, ...
                R.matching.type, R.matching.min_num_inliers, rabbit_sfm_build.yes_no(R.rig.use), ...
                R.rig.ref_view, R.threads);
            lines{end+1} = sprintf('Depth guard: %s, seeds %s, near-side fraction at least %g', ...
                rabbit_sfm_build.yes_no(R.guard.use), mat2str(R.guard.seeds), R.guard.min_near_side_fraction);
            cap = true;
            if isfield(R.mesh, 'silhouette_cap'), cap = logical(R.mesh.silhouette_cap); end
            if cap
                cap_text = 'when their masks pass the agreement check, they also cap the membrane fit';
            else
                cap_text = 'they check the masks; no silhouette cap on the membrane fit';
            end
            lines{end+1} = sprintf(['Mesh: keep fused points inside the tissue silhouette in at least %g %% of ' ...
                'the images they land in; %d silhouette frames x 4 views: %s'], ...
                100 * R.mesh.silhouette_filter_min_inside, R.mesh.silhouette_frames, cap_text);
            band = 0;
            if isfield(R.mesh, 'field_band_px'), band = R.mesh.field_band_px; end
            if band > 0
                lines{end+1} = sprintf(['Field band: %d px (a mask edge within %d px of the view border that ' ...
                    'stays still over the view''s frames is the mirror''s field edge; the pixels beyond it ' ...
                    'neither keep nor reject a point, do not limit the mesh and are left out of A6)'], band, band);
            else
                lines{end+1} = 'Field band: off';
            end
            one_edge = false;
            if isfield(R.mesh, 'single_open_edge'), one_edge = logical(R.mesh.single_open_edge); end
            if one_edge
                lines{end+1} = ['One open edge: on (a second unsupported region near the open edge, along ' ...
                    'the surface, is cut together with it, so a strip of support leaves no hole; one further ' ...
                    'away is cut on its own and shows as a hole in M8)'];
            else
                lines{end+1} = 'One open edge: off (every large unsupported region is cut)';
            end
            lines{end+1} = '';
            lines{end+1} = 'COLMAP commands per build ({...} are filled in for each run):';
            for k = 1:numel(R.commands)
                c = R.commands(k);
                w = '';
                if ~isempty(c.when), w = sprintf(' (only when %s)', c.when); end
                each = '';
                if strcmp(c.foreach, 'view'), each = ' (once per view)'; end
                args = arrayfun(@(x) sprintf('%s %s', x.key, x.value), c.args, 'UniformOutput', false);
                lines{end+1} = sprintf('%d. [%s] %s%s%s: colmap %s %s', k, c.phase, c.label, each, w, ...
                    c.subcommand, strjoin(args, ' ')); %#ok<AGROW>
            end
        end

        % =============================================================
        % 2. Resolve: tiles, frames, outer tiles, cameras
        % =============================================================

        function [ok, err, Rr] = resolve(R, ctx)
            %% Resolve a recipe against the run's cut images
            %   ctx.images_dir  the cut folder (with the cut manifest.json)
            %   ctx.roi_json    the ROI file (fallback for the tile bounds)
            % Returns the recipe with a 'resolved' block: frames, the outer
            % tiles and per view the tile, base flip, camera and images.
            ok = false; err = ''; Rr = R;
            [v_ok, v_err] = rabbit_sfm_build.validate(R);
            if ~v_ok, err = v_err; return; end
            if ~isfield(ctx, 'images_dir') || ~isfolder(ctx.images_dir)
                err = 'The reconstruction images folder is missing.'; return;
            end
            % --- the cut images: <stem>_view<k>_frame_NNNN.tiff ---
            d = dir(ctx.images_dir);
            names = {d(~[d.isdir]).name};
            names = names(~cellfun(@isempty, regexpi(names, '\.(tiff?|png|jpe?g)$', 'once')));
            tok = regexp(names, '^(.*)_view(\d+)_frame_(\d+)\.tiff?$', 'tokens', 'once');
            bad = cellfun(@isempty, tok);
            if isempty(names) || all(bad)
                err = ['The reconstruction images are not cut views named <name>_view<k>_frame_NNNN.tiff. ' ...
                    'Cut the reconstruction recording with the four regions first.'];
                return;
            end
            if any(bad)
                err = sprintf('%d image(s) in %s do not follow <name>_view<k>_frame_NNNN.tiff, e.g. %s.', ...
                    nnz(bad), ctx.images_dir, names{find(bad, 1)}); return;
            end
            stems = cellfun(@(t) t{1}, tok, 'UniformOutput', false);
            if numel(unique(stems)) ~= 1
                err = 'The images come from more than one recording; keep one recording per run.'; return;
            end
            stem = stems{1};
            view_of = cellfun(@(t) str2double(t{2}), tok);
            frame_of = cellfun(@(t) str2double(t{3}), tok);
            if ~isequal(unique(view_of), 1:4)
                err = sprintf('The images must have views 1 to 4; found %s.', mat2str(unique(view_of))); return;
            end
            % --- tile bounds: the cut manifest, else the ROI file ---
            [bounds, src_dims, b_source] = rabbit_sfm_build.tile_bounds(ctx);
            % --- frames: in every view; the list, a fixed step, or the
            % study's rule stride = max(1, floor(N/target_frames)) ---
            common = 1:max(frame_of);
            for v = 1:4
                common = intersect(common, frame_of(view_of == v));
            end
            if isempty(common)
                err = 'No frame number has an image in all four views.'; return;
            end
            if ~isempty(R.images.frames)
                frames = intersect(R.images.frames, common);
                missing = setdiff(R.images.frames, common);
                if ~isempty(missing)
                    err = sprintf('Frames %s of the recipe are not cut in all four views.', mat2str(missing)); return;
                end
                stride = NaN;
                frame_rule = 'frames listed in the recipe';
            else
                if isempty(R.images.frame_step)
                    stride = rabbit_sfm_build.frame_stride(numel(common), R.images.target_frames);
                    frame_rule = sprintf('stride max(1, floor(N/%d)) = %d for N = %d frames', ...
                        R.images.target_frames, stride, numel(common));
                else
                    stride = R.images.frame_step;
                    frame_rule = sprintf('fixed step %d', stride);
                end
                frames = common(1:stride:end);
            end
            % --- outer tiles: left-most and right-most in the frame ---
            if size(bounds, 1) >= 4
                [~, left] = min(bounds(1:4, 2));
                [~, right] = max(bounds(1:4, 4));
                outer_source = 'view columns in the reconstruction frame';
            else
                left = 1; right = 4;
                outer_source = 'ROI rows 1 and 4 (no view bounds found)';
            end
            if left == right
                err = 'The left-most and right-most views are the same; the regions look wrong.'; return;
            end
            % --- per-view cameras ---
            f0 = R.camera.focal_prior_px;
            views = struct('roi_row', {}, 'view_name', {}, 'image_prefix', {}, 'tile_hw', {}, ...
                'bounds', {}, 'outer', {}, 'base_flip_lr', {}, 'cx', {}, 'cy', {}, 'pp_source', {}, ...
                'camera_params', {}, 'images', {});
            for v = 1:4
                sel = find(view_of == v & ismember(frame_of, frames));
                [~, order] = sort(frame_of(sel));
                img_names = names(sel(order));
                info = imfinfo(fullfile(ctx.images_dir, img_names{1}));
                hw = [info(1).Height info(1).Width];
                b = [];
                if size(bounds, 1) >= v, b = bounds(v, :); end
                if ~isempty(b) && ~isequal(hw, [b(3) - b(1) + 1, b(4) - b(2) + 1])
                    err = sprintf(['View %d images are %dx%d pixels but the cut regions say %dx%d. ' ...
                        'The images and the regions do not belong together.'], v, hw(1), hw(2), ...
                        b(3) - b(1) + 1, b(4) - b(2) + 1);
                    return;
                end
                outer = any(v == [left right]);
                % COLMAP pixel centres sit at +0.5, so the image centre is
                % (w/2, h/2); flips and turns keep it there
                cx = hw(2) / 2; cy = hw(1) / 2;
                views(end+1) = struct('roi_row', v, ...
                    'view_name', rabbit_sfm_build.VIEW_NAMES{v}, ...
                    'image_prefix', sprintf('%s_view%d_', stem, v), ...
                    'tile_hw', hw, 'bounds', b, 'outer', outer, ...
                    'base_flip_lr', outer && logical(R.orientation.outer_flip_lr), ...
                    'cx', cx, 'cy', cy, ...
                    'pp_source', 'view centre (COLMAP refuses a principal point outside the image, see the class header)', ...
                    'camera_params', rabbit_sfm_build.camera_params(R, f0, cx, cy), ...
                    'images', {img_names}); %#ok<AGROW>
            end
            Rr.resolved = struct('stem', stem, 'frames', frames, 'n_frames_cut', numel(common), ...
                'stride', stride, 'frame_rule', frame_rule, ...
                'n_images', 4 * numel(frames), 'outer_rows', [left right], 'outer_source', outer_source, ...
                'views', views, 'bounds_source', b_source, 'source_dims', src_dims, ...
                'focal_prior_px', f0, 'focal_source', R.camera.focal_source);
            ok = true;
        end

        function s = frame_stride(n, target)
            %% The study's frame step: max(1, floor(N/target))
            % With target 40: N = 100, 120, 240, 1200 give 2, 3, 6, 30,
            % the strides of the study's four recordings.
            s = max(1, floor(n / target));
        end

        function cp = camera_params(R, f, cx, cy)
            %% --ImageReader.camera_params text for one view
            n = @rabbit_sfm_build.num;
            switch R.camera.model
                case 'SIMPLE_PINHOLE'
                    cp = sprintf('%s,%s,%s', n(f), n(cx), n(cy));
                case 'PINHOLE'
                    cp = sprintf('%s,%s,%s,%s', n(f), n(f), n(cx), n(cy));
                otherwise
                    % SIMPLE_RADIAL / RADIAL: f, cx, cy, then the radial terms
                    cp = sprintf('%s,%s,%s,%s', n(f), n(cx), n(cy), R.camera.extra_params);
            end
        end

        function [bounds, src_dims, source] = tile_bounds(ctx)
            %% Tile bounds in the reconstruction frame
            % The cut manifest's roi_bounds (already mapped across the FOV
            % when the cut was made), else the ROI file's region bounds
            % mapped with its fov_mapping.
            bounds = []; src_dims = []; source = 'none';
            mf = fullfile(ctx.images_dir, 'manifest.json');
            if exist(mf, 'file') == 2
                try
                    m = jsondecode(fileread(mf));
                    bounds = double(m.roi_bounds.bounds);
                    src_dims = [double(m.source_dims.height) double(m.source_dims.width)];
                    source = 'cut manifest.json (roi_bounds, source_dims)';
                    return;
                catch
                    bounds = []; src_dims = [];
                end
            end
            if isfield(ctx, 'roi_json') && exist(ctx.roi_json, 'file') == 2
                try
                    p = rabbit_stack_io.load_roi_json(ctx.roi_json, [], []);
                    bounds = double(p.region_bounds_src(:, 1:4));
                    source = 'ROI file region_bounds_src';
                    if isfield(p, 'fov_mapping') && ~isempty(p.fov_mapping)
                        bounds = rabbit_stack_io.map_bounds_across_fov(bounds, p.fov_mapping);
                        source = 'ROI file region_bounds_src mapped with its fov_mapping';
                    end
                catch
                    bounds = [];
                end
            end
        end

        % =============================================================
        % 3. Orientation of the outer tiles
        % =============================================================

        function [turns, source] = orientation_request(R)
            %% Requested turn (0 / 180, NaN = find out) of the left and right outer tile
            % A per-tile value wins over camera_upside_down; 'auto' for
            % both leaves the turn to the two orientation builds.
            turns = [NaN NaN];
            src = {'', ''};
            sw = R.orientation.camera_upside_down;
            for j = 1:2
                t = R.orientation.outer_turn{j};
                if ~strcmp(t, 'auto')
                    turns(j) = str2double(t);
                    src{j} = 'recipe (per view)';
                elseif strcmp(sw, 'no')
                    % the main and old-rig recordings' pattern: left 0, right 180
                    turns(j) = 180 * (j == 2);
                    src{j} = 'recipe (camera_upside_down = no)';
                elseif strcmp(sw, 'yes')
                    % the SFOV and LFOV recordings' pattern: the frame turned by 180 degrees
                    turns(j) = 180 * (j == 1);
                    src{j} = 'recipe (camera_upside_down = yes)';
                else
                    src{j} = 'orientation builds (auto)';
                end
            end
            source = src;
        end

        function [lr, ud] = view_transform(base_lr, turn)
            %% Final flips of a tile: the base left-right flip, then a turn
            % A 180 degree turn is fliplr + flipud, so lr+180 = flipud
            % (pixel for pixel).
            t180 = (turn == 180);
            lr = xor(logical(base_lr), t180);
            ud = t180;
        end

        function im = apply_transform(im, lr, ud)
            %% Mirror a tile left-right and/or up-down
            if lr, im = fliplr(im); end
            if ud, im = flipud(im); end
        end

        function tf = reuses_turns(R)
            %% orientation.reuse_turns is yes (missing, in older recipes: no)
            tf = isfield(R, 'orientation') && isfield(R.orientation, 'reuse_turns') && ...
                strcmp(R.orientation.reuse_turns, 'yes');
        end

        function key = turn_key(R)
            %% What an outer tile's turn depends on: the recording, the boxes, the flips
            % The turn is a property of the rig and of how the tiles are
            % cut, not of the frames or the feature settings, so two runs
            % of the same recording with the same boxes and flips need the
            % same turns.
            v = R.resolved.views;
            if iscell(v), v = [v{:}]; end
            parts = cell(1, numel(v));
            for k = 1:numel(v)
                parts{k} = sprintf('%d:%s:%s:%d', v(k).roi_row, mat2str(reshape(double(v(k).bounds), 1, [])), ...
                    mat2str(reshape(double(v(k).tile_hw), 1, [])), logical(v(k).base_flip_lr));
            end
            key = sprintf('%s|%s|%d|%s', char(R.resolved.stem), mat2str(reshape(double(R.resolved.outer_rows), 1, [])), ...
                logical(R.orientation.outer_flip_lr), strjoin(parts, ';'));
        end

        function known = known_turns(run_dir, R, reader_R)
            %% The outer-tile turns an earlier finished run of the same recording and boxes decided
            % run_dir: this run; its siblings in the same runs folder are
            % searched, newest first. A sibling counts when its sparse
            % build kept a model and its turn_key is the same (the
            % recording, each tile's box in the reconstruction frame, its
            % size and flip, the outer rows). The ROI file itself is not
            % compared: it also holds things a turn does not depend on,
            % such as the calibration stack's path. reader_R: @(dir)
            % -> the sibling's recipe (the tab's run_sfm_recipe).
            % known: [] or struct turns (left, right), source (run id),
            % how (how that run had its turns).
            known = [];
            key = rabbit_sfm_build.turn_key(R);
            [runs_dir, me] = fileparts(run_dir);
            d = dir(runs_dir);
            d = d([d.isdir] & ~startsWith({d.name}, '.') & ~strcmp({d.name}, me));
            [~, order] = sort({d.name});
            for k = fliplr(order)
                other = fullfile(runs_dir, d(k).name);
                sf = fullfile(other, 'stages', 'sparse_build', 'model_summary.json');
                if exist(sf, 'file') ~= 2, continue; end
                try
                    S = jsondecode(fileread(sf));
                    if ~isfield(S, 'chosen') || isempty(S.chosen) || ~isfield(S, 'orientation'), continue; end
                    Ro = reader_R(other);
                    if isempty(Ro) || ~strcmp(rabbit_sfm_build.turn_key(Ro), key), continue; end
                    tu = reshape(double(S.orientation.turns), 1, []);
                    if numel(tu) ~= 2 || ~all(ismember(tu, [0 180])), continue; end
                    how = 'orientation builds';
                    if isfield(S.orientation, 'known') && isstruct(S.orientation.known) && ...
                            isfield(S.orientation.known, 'source')
                        how = sprintf('reused from run %s', S.orientation.known.source);
                    end
                    known = struct('turns', tu, 'source', d(k).name, 'how', how);
                    return;
                catch
                    % an unreadable record is passed over
                end
            end
        end

        function [ok, why] = known_turns_hold(Rr, P)
            %% A build with known turns stands: depth guard passed, each outer tile half registered
            ok = false; why = '';
            if ~P.accepted
                why = 'no seed passed the depth guard'; return;
            end
            v = Rr.resolved.views;
            if iscell(v), v = [v{:}]; end
            for row = reshape(Rr.resolved.outer_rows, 1, [])
                n = numel(v([v.roi_row] == row).images);
                got = P.registered_per_view(row);
                if got < 0.5 * n
                    why = sprintf('the outer view of ROI row %d registered %d of %d images', row, got, n); return;
                end
            end
            ok = true;
        end

        function [turn, why] = decide_turn(a, b)
            %% Turn of one outer tile from its two orientation builds
            % a, b: [registered images of the tile, points seen in >= 2
            % views] of the build with turn 0 and turn 180. More registered
            % images wins; then more multi-view points; then turn 0.
            if a(1) ~= b(1)
                if a(1) > b(1), turn = 0; else, turn = 180; end
                why = sprintf('registered %d (turn 0) vs %d (turn 180) images', a(1), b(1));
            elseif a(2) ~= b(2)
                if a(2) > b(2), turn = 0; else, turn = 180; end
                why = sprintf('tie on registered images (%d); %d vs %d points seen in two or more views', ...
                    a(1), a(2), b(2));
            else
                turn = 0;
                why = sprintf('full tie (%d images, %d points); turn 0 kept', a(1), a(2));
            end
        end

        % =============================================================
        % 4. Prepare the images (stage sparse_prep)
        % =============================================================

        function [lo, hi] = stretch_limits(vals, pct)
            %% Nearest-rank percentiles: sorted value at ceil(p/100*n)
            % The same rule in any language (no interpolation), so the
            % limits are exact.
            v = sort(double(vals(:)));
            n = numel(v);
            k = @(p) min(max(ceil(p / 100 * n), 1), n);
            lo = v(k(pct(1)));
            hi = v(k(pct(2)));
        end

        function u8 = stretch_u8(im, lo, hi)
            %% Linear stretch to [0,1], clipped, to uint8 (x*255 rounded half up)
            x = min(max((double(im) - lo) / max(hi - lo, 1e-9), 0), 1);
            u8 = uint8(floor(x * 255 + 0.5));
        end

        function [score, feat] = tissue_mask(u8, sigma, dilate_px)
            %% Tissue silhouette of a stretched uint8 tile
            % 1. L = round(255 log(1 + I) / log 256); 2. a separable
            % Gaussian of sigma 2 px (9 taps, replicate border; the same as
            % imgaussfilt(L, 2)), rounded; 3. Otsu's threshold (Otsu 1979)
            % on its 256-bin histogram, foreground = above it; 4. the
            % largest 8-connected region; 5. holes filled. score is that
            % silhouette; feat is it dilated by a disk of dilate_px
            % (x^2 + y^2 <= r^2), the mask the features may use.
            L = floor(255 * log1p(double(u8)) / log(256) + 0.5);
            r = ceil(2 * sigma);                       % 4 for sigma 2: 9 taps
            g = exp(-((-r:r) .^ 2) / (2 * sigma ^ 2));
            g = g / sum(g);
            B = conv2(padarray(L, [r r], 'replicate'), g, 'valid');   % rows
            B = conv2(B, g', 'valid');                                % columns
            B = floor(B + 0.5);
            h = accumarray(min(max(B(:), 0), 255) + 1, 1, [256 1])';
            p = h / sum(h);
            w0 = cumsum(p);
            mu = cumsum(p .* (0:255));
            sb = (mu(end) * w0 - mu) .^ 2 ./ (w0 .* (1 - w0));      % between-class variance
            sb(~isfinite(sb)) = -1;
            [~, k] = max(sb(1:255));                                 % first maximum
            M = B > (k - 1);
            if any(M(:))
                M = bwareafilt(M, 1, 8);
                M = imfill(M, 'holes');
            end
            score = M;
            if dilate_px > 0
                [xx, yy] = meshgrid(-dilate_px:dilate_px);
                feat = imdilate(M, xx .^ 2 + yy .^ 2 <= dilate_px ^ 2);
            else
                feat = M;
            end
        end

        function out = equalise(u8, cfg)
            %% CLAHE (Zuiderveld 1994) with MATLAB adapthisteq
            out = adapthisteq(u8, 'NumTiles', cfg.num_tiles, 'ClipLimit', cfg.clip_limit, ...
                'NBins', cfg.nbins, 'Distribution', cfg.distribution);
        end

        function r = prepare(Rr, in_dir, out_dir, mask_dir)
            %% Write the SfM tiles, masks, lists and the rig file
            % in_dir: the run's inputs/images (the cut tiles, camera counts
            % as uint16); out_dir: stages/sparse_prep; mask_dir: per-image
            % masks for masks.source 'folder' ('' = none). For each view:
            % stretch limits over all its chosen frames, then per image
            % the stretched tile, its tissue masks (before any flip; the
            % mask steps are symmetric, so a flip commutes with them), the
            % flips of each turn (inner tiles: none; outer tiles: turn 0
            % and turn 180), CLAHE on the flipped tile (CLAHE does not
            % commute with flips). Written as turn<t>/images/<name>
            % (uint8 TIFF), turn<t>/masks/<name>.png (feature mask, COLMAP
            % layout) and turn<t>/score_masks/<name>.png; inner tiles only
            % under turn0. Returns r.ok, r.err, r.checks, r.warnings,
            % r.prep (what prep.json holds).
            if nargin < 4, mask_dir = ''; end
            r = struct('ok', false, 'err', '', 'checks', struct('name', {}, 'result', {}), ...
                'warnings', {{}}, 'prep', struct());
            V = Rr.resolved.views;
            P = Rr.preprocess;
            use_masks = logical(Rr.masks.use);
            list_out = fullfile(out_dir, 'lists');
            turns_of = @(v) unique([0, 180 * V(v).outer]);   % inner tiles: turn 0 only
            sub = {'images'};
            if use_masks, sub = [sub, {'masks', 'score_masks'}]; end
            dirs = {list_out};
            for t = [0 180]
                for s = sub
                    dirs{end+1} = fullfile(out_dir, sprintf('turn%d', t), s{1}); %#ok<AGROW>
                end
            end
            for k = 1:numel(dirs)
                if ~isfolder(dirs{k})
                    [s_ok, m] = mkdir(dirs{k});
                    if ~s_ok, r.err = sprintf('Could not create %s: %s', dirs{k}, m); return; end
                end
            end
            limits = nan(4, 2);
            n_masks = 0; n_missing = 0; n_written = 0;
            png_time = datetime(2000, 1, 1, 'TimeZone', 'UTC');
            for v = 1:4
                names = V(v).images;
                rabbit_sfm_build.write_text(fullfile(list_out, sprintf('view%d.txt', v)), ...
                    sprintf('%s\n', names{:}));
                % All chosen frames of the view (the limits are shared)
                stack = cell(1, numel(names));
                for i = 1:numel(names)
                    im = imread(fullfile(in_dir, names{i}));
                    if size(im, 3) > 1, im = im(:, :, 1); end
                    if ~isequal(size(im), V(v).tile_hw)
                        r.err = sprintf('%s is %dx%d, not the %dx%d of its view.', names{i}, ...
                            size(im, 1), size(im, 2), V(v).tile_hw(1), V(v).tile_hw(2));
                        return;
                    end
                    stack{i} = im;
                end
                if ~strcmp(P.intensity, 'none')
                    vals = cellfun(@(x) double(x(:)), stack, 'UniformOutput', false);
                    [lo, hi] = rabbit_sfm_build.stretch_limits(vertcat(vals{:}), P.percentiles);
                    limits(v, :) = [lo hi];
                end
                for i = 1:numel(names)
                    im = stack{i};
                    if strcmp(P.intensity, 'none')
                        u8 = im;
                    else
                        u8 = rabbit_sfm_build.stretch_u8(im, limits(v, 1), limits(v, 2));
                    end
                    score = []; feat = [];
                    if use_masks
                        if strcmp(Rr.masks.source, 'log_otsu')
                            if ~isa(u8, 'uint8')
                                r.err = 'Tissue masks need stretched views (preprocess.intensity stretch or stretch_clahe).';
                                return;
                            end
                            [score, feat] = rabbit_sfm_build.tissue_mask(u8, Rr.masks.gauss_sigma, Rr.masks.dilate_px);
                        else
                            mp = rabbit_sfm_build.find_mask(mask_dir, names{i});
                            if isempty(mp)
                                n_missing = n_missing + 1;
                            else
                                mk = imread(mp);
                                if size(mk, 3) > 1, mk = mk(:, :, 1); end
                                score = mk > 0;
                                feat = score;
                            end
                        end
                    end
                    for t = turns_of(v)
                        [lr, ud] = rabbit_sfm_build.view_transform(V(v).base_flip_lr, t);
                        img = rabbit_sfm_build.apply_transform(u8, lr, ud);
                        if strcmp(P.intensity, 'stretch_clahe')
                            img = rabbit_sfm_build.equalise(img, P.clahe);
                        end
                        td = fullfile(out_dir, sprintf('turn%d', t));
                        imwrite(img, fullfile(td, 'images', names{i}), 'Compression', 'none');
                        n_written = n_written + 1;
                        if ~isempty(score)
                            % COLMAP: <mask_path>/<image name>.png, 0 = ignore.
                            % A fixed PNG time stamp, so the file bytes (and
                            % the recorded sha256) depend only on the pixels
                            imwrite(uint8(255 * rabbit_sfm_build.apply_transform(feat, lr, ud)), ...
                                fullfile(td, 'masks', [names{i} '.png']), 'ImageModTime', png_time);
                            imwrite(uint8(255 * rabbit_sfm_build.apply_transform(score, lr, ud)), ...
                                fullfile(td, 'score_masks', [names{i} '.png']), 'ImageModTime', png_time);
                            n_masks = n_masks + 1;
                        end
                    end
                end
            end
            % rig_config.json: one rig of the four views, unknown poses
            % (derived from the first model by rig_configurator); the
            % reference sensor is listed FIRST (COLMAP 4.2.1 crashes with
            % 0xC0000409 otherwise, see the class header)
            rabbit_sfm_build.write_text(fullfile(out_dir, 'rig_config.json'), ...
                rabbit_sfm_build.rig_config_text(Rr));
            % prep.json: what was done, for the run record
            S = struct();
            S.schema = 'rabbit_sfm_build.prep.v2';
            S.recipe = Rr.name;
            S.frames = Rr.resolved.frames;
            S.frame_rule = Rr.resolved.frame_rule;
            S.n_images = Rr.resolved.n_images;
            S.intensity = P.intensity;
            S.percentiles = P.percentiles;
            S.stretch_limits = limits;
            S.clahe = P.clahe;
            S.outer_rows = Rr.resolved.outer_rows;
            S.focal_prior_px = Rr.resolved.focal_prior_px;
            S.focal_source = Rr.resolved.focal_source;
            S.bounds_source = Rr.resolved.bounds_source;
            S.views = rmfield(V, 'images');
            S.masks = struct('use', use_masks, 'source', Rr.masks.source, 'gauss_sigma', Rr.masks.gauss_sigma, ...
                'dilate_px', Rr.masks.dilate_px, 'written', n_masks, 'missing', n_missing);
            rabbit_sfm_build.write_text(fullfile(out_dir, 'prep.json'), jsonencode(S, 'PrettyPrint', true));
            r.prep = S;
            % Checks: every image under turn0, the outer ones under turn180 too
            n_expect = Rr.resolved.n_images + numel(Rr.resolved.frames) * nnz([V.outer]);
            r.checks(end+1) = struct('name', 'images_written', 'result', n_written == n_expect);
            r.checks(end+1) = struct('name', 'rig_config', 'result', exist(fullfile(out_dir, 'rig_config.json'), 'file') == 2);
            if use_masks && n_missing > 0
                r.warnings{end+1} = sprintf('%d of %d images have no mask; COLMAP uses the whole image for those.', ...
                    n_missing, Rr.resolved.n_images);
            end
            r.ok = all([r.checks.result]);
            if ~r.ok
                bad = r.checks(find(~[r.checks.result], 1));
                r.err = sprintf('check ''%s'' failed', bad.name);
            end
        end

        function row = ref_roi_row(Rr)
            %% ROI row of the rig's reference tile (ref_view counts from the left)
            row = Rr.rig.ref_view;
            V = Rr.resolved.views;
            if all(arrayfun(@(v) numel(v.bounds) == 4, V))  % no bounds: ROI rows it is
                [~, left_to_right] = sort(arrayfun(@(v) v.bounds(2), V));
                row = left_to_right(row);
            end
        end

        function txt = rig_config_text(Rr)
            %% rig_config.json: the reference view first, then the others in ROI-row order
            ref = rabbit_sfm_build.ref_roi_row(Rr);
            order = [ref, setdiff(1:4, ref)];
            cams = cell(1, 4);
            for k = 1:4
                c = struct('image_prefix', Rr.resolved.views(order(k)).image_prefix);
                if order(k) == ref, c.ref_sensor = true; end
                cams{k} = c;
            end
            txt = jsonencode({struct('cameras', {cams})}, 'PrettyPrint', true);
        end

        function p = find_mask(mask_dir, name)
            %% The mask of an image: <name>.png or <stem>.png in mask_dir
            p = '';
            if isempty(mask_dir) || ~isfolder(mask_dir), return; end
            [~, stem] = fileparts(name);
            cands = {[name '.png'], [stem '.png'], [stem '.tif'], [stem '.tiff']};
            for k = 1:numel(cands)
                if exist(fullfile(mask_dir, cands{k}), 'file') == 2
                    p = fullfile(mask_dir, cands{k});
                    return;
                end
            end
        end

        % =============================================================
        % 5. Commands
        % =============================================================

        function [cmds, timeouts, steps] = commands(Rr, phase, paths, colmap_exe, seed)
            %% COLMAP command lines of one phase of a resolved recipe
            %   paths: struct with db, images, masks, lists (folder of
            %       view<k>.txt), rig, sparse_out, input_model, rig_out,
            %       models (the COLMAP models folder, '' = none); fields a
            %       phase does not use may be ''
            %   seed: the mapper seed ({MAPPER_SEED}; [] for other phases)
            % Returns the command lines (cellstr, in order), their time
            % limits (s) and steps (subcommand, label, line, keys).
            if nargin < 5, seed = []; end
            [v_ok, v_err] = rabbit_sfm_build.validate(Rr);
            if ~v_ok
                error('analyse_om:SparseModel:BadRecipe', '%s', v_err);
            end
            if ~isfield(Rr, 'resolved')
                error('analyse_om:SparseModel:NotResolved', 'The recipe has not been resolved against the images.');
            end
            rabbit_sfm_build.check_path(colmap_exe, 'colmap.exe');
            ptok = struct('DB', paths.db, 'IMAGES', paths.images, 'MASKS', paths.masks, ...
                'RIG', paths.rig, 'VIEW_LIST', '', 'SPARSE_OUT', paths.sparse_out, ...
                'INPUT_MODEL', paths.input_model, 'RIG_OUT', paths.rig_out);
            cmds = {}; timeouts = [];
            steps = struct('subcommand', {}, 'label', {}, 'line', {}, 'keys', {}, 'timeout_s', {});
            C = Rr.commands;
            for k = 1:numel(C)
                if ~strcmp(C(k).phase, phase) || ~rabbit_sfm_build.when_holds(Rr, C(k).when), continue; end
                if strcmp(C(k).foreach, 'view'), reps = 1:4; else, reps = 0; end
                for v = reps
                    if v > 0
                        ptok.VIEW_LIST = fullfile(paths.lists, sprintf('view%d.txt', v));
                    end
                    parts = {sprintf('"%s"', colmap_exe), C(k).subcommand};
                    keys = {};
                    for j = 1:numel(C(k).args)
                        A = C(k).args(j);
                        if ~rabbit_sfm_build.when_holds(Rr, A.when), continue; end
                        val = rabbit_sfm_build.expand(Rr, char(A.value), ptok, v, seed);
                        parts{end+1} = sprintf('%s %s', A.key, val); %#ok<AGROW>
                        keys{end+1} = A.key; %#ok<AGROW>
                    end
                    % Model files (ONNX): the local copy when the models
                    % folder has it, else COLMAP's own (checked) default
                    mf = rabbit_sfm_build.model_files_of(Rr, C(k).subcommand);
                    for j = 1:numel(mf)
                        p = rabbit_sfm_build.local_model(paths.models, mf(j).file);
                        if ~isempty(p)
                            rabbit_sfm_build.check_path(p, mf(j).option);
                            parts{end+1} = sprintf('%s "%s"', mf(j).option, p); %#ok<AGROW>
                            keys{end+1} = mf(j).option; %#ok<AGROW>
                        end
                    end
                    % Always: log to stderr (the stage log), no colour
                    % codes, the recipe's seed
                    parts{end+1} = '--log_target stderr'; %#ok<AGROW>
                    parts{end+1} = '--log_color 0'; %#ok<AGROW>
                    parts{end+1} = sprintf('--default_random_seed %d', Rr.random_seed); %#ok<AGROW>
                    keys = [keys, {'--log_target', '--log_color', '--default_random_seed'}]; %#ok<AGROW>
                    line = strjoin(parts, ' ');
                    lbl = strrep(C(k).label, '{VIEW}', sprintf('%d', v));
                    if ~isempty(seed), lbl = strrep(lbl, '{MAPPER_SEED}', sprintf('%d', seed)); end
                    cmds{end+1} = line; %#ok<AGROW>
                    timeouts(end+1) = C(k).timeout_s; %#ok<AGROW>
                    steps(end+1) = struct('subcommand', C(k).subcommand, 'label', lbl, ...
                        'line', line, 'keys', {keys}, 'timeout_s', C(k).timeout_s); %#ok<AGROW>
                end
            end
        end

        function mf = model_files_of(Rr, subcommand)
            %% The model files (ONNX) a subcommand of the recipe can take
            if strcmp(subcommand, 'feature_extractor')
                mf = Rr.features.model_files;
            elseif contains(subcommand, 'matcher')
                mf = Rr.matching.model_files;
            else
                mf = struct('option', {}, 'file', {}, 'sha256', {});
            end
        end

        function p = cached_model(file, sha256)
            %% COLMAP's cached copy of a default model file, or ''
            % COLMAP keeps a file it downloaded as
            % <home>/.cache/colmap/<sha256>-<file name> (seen with COLMAP
            % 4.2.1 on Windows).
            p = '';
            home = char(java.lang.System.getProperty('user.home'));
            q = fullfile(home, '.cache', 'colmap', sprintf('%s-%s', sha256, file));
            if exist(q, 'file') == 2, p = q; end
        end

        function p = local_model(models_dir, file)
            %% A model file in the COLMAP models folder, or ''
            p = '';
            if isempty(models_dir), return; end
            q = fullfile(models_dir, file);
            if exist(q, 'file') == 2, p = q; end
        end

        function used = commands_used(Rr)
            %% Subcommands and the --options each one uses (for the help checks)
            % Struct array: subcommand, keys (cellstr, unique), with the
            % model options and the options the app always adds.
            used = struct('subcommand', {}, 'keys', {});
            C = Rr.commands;
            for k = 1:numel(C)
                if ~rabbit_sfm_build.when_holds(Rr, C(k).when), continue; end
                keys = {};
                for j = 1:numel(C(k).args)
                    if rabbit_sfm_build.when_holds(Rr, C(k).args(j).when)
                        keys{end+1} = C(k).args(j).key; %#ok<AGROW>
                    end
                end
                mf = rabbit_sfm_build.model_files_of(Rr, C(k).subcommand);
                keys = [keys, {mf.option}, {'--log_target', '--log_color', '--default_random_seed'}]; %#ok<AGROW>
                i = find(strcmp({used.subcommand}, C(k).subcommand), 1);
                if isempty(i)
                    used(end+1) = struct('subcommand', C(k).subcommand, 'keys', {unique(keys, 'stable')}); %#ok<AGROW>
                else
                    used(i).keys = unique([used(i).keys, keys], 'stable');
                end
            end
        end

        function [lines, labels] = plan(Rr, paths, colmap_exe)
            %% The command lines of one build with the first seed (for the record)
            % The orientation builds repeat the features and mapper
            % phases; the depth guard repeats the mapper phases with the
            % next seeds; the record keeps the lines actually run.
            lines = {}; labels = {};
            s1 = Rr.guard.seeds(1);
            for ph = rabbit_sfm_build.PHASES
                [c, ~, st] = rabbit_sfm_build.commands(Rr, ph{1}, paths, colmap_exe, s1);
                lines = [lines, c]; %#ok<AGROW>
                labels = [labels, {st.label}]; %#ok<AGROW>
            end
        end

        function tf = uses_gpu(Rr)
            %% True when a step of the recipe asks COLMAP for the GPU
            tf = (logical(Rr.features.use_gpu) || logical(Rr.matching.use_gpu));
        end

        function keys = citation_keys(R)
            %% Citation keys of the methods a recipe uses
            keys = {'colmap-sfm'};
            switch upper(R.features.type)
                case 'SIFT', keys{end+1} = 'sift';
                case {'ALIKED_N16ROT', 'ALIKED_N32'}, keys{end+1} = 'aliked';
            end
            if contains(upper(R.matching.type), 'LIGHTGLUE'), keys{end+1} = 'lightglue'; end
            if any(strcmp({R.commands.subcommand}, 'global_mapper')), keys{end+1} = 'colmap-glomap'; end
            if any(strcmp({R.commands.subcommand}, 'vocab_tree_matcher')), keys{end+1} = 'colmap-vocabtree'; end
            if logical(R.rig.use), keys{end+1} = 'colmap-rigs'; end
            if logical(R.guard.use), keys = [keys, {'koenderink-vandoorn', 'tomasi-kanade', 'szeliski-kang'}]; end
            keys = unique(keys, 'stable');
        end

        function keys = prep_citation_keys(R)
            %% Citation keys of the image preparation of a recipe
            keys = {'sfm-prep', 'gluckman-nayar', 'hartley-zisserman'};
            if strcmp(R.preprocess.intensity, 'stretch_clahe'), keys{end+1} = 'clahe'; end
            if logical(R.masks.use) && strcmp(R.masks.source, 'log_otsu'), keys{end+1} = 'otsu'; end
        end

        % =============================================================
        % 6. Build the model (stage sparse_build)
        % =============================================================

        function r = build(Rr, stage_dir, prep_dir, colmap_exe, models_dir, run_cmd, reader, note, known)
            %% Orientation builds, the final build, the guard, the chosen model
            %   run_cmd: @(line, timeout_s, label) -> [ok, err, exit_code];
            %       runs one COLMAP command line (the tab: one wrapped job
            %       with cancel and time limit, logged to the stage log)
            %   reader: @(dir) -> [cameras, images, points3d] maps (the
            %       tab's read_sparse_model)
            %   note: @(text) adds a line to the stage log
            %   known (optional): [] or known_turns(...) of an earlier run;
            %       used only for tiles left to auto. The build then runs
            %       once; when it does not hold (known_turns_hold) it is
            %       kept as work/final_known_turns and the orientation
            %       builds run as without it.
            % Writes work/ (orient_turn0, orient_turn180, final), then
            % model/, images/ and score_masks/ (registered images only),
            % model_summary.json and om_tile_transform.json. Returns r.ok,
            % r.err, r.exit_code (130 = cancelled), r.summary and
            % r.commands_run (every line, in order).
            if nargin < 8 || isempty(note), note = @(t) []; end
            if nargin < 9, known = []; end
            r = struct('ok', false, 'err', '', 'exit_code', 0, 'summary', struct(), 'commands_run', {{}});
            work = fullfile(stage_dir, 'work');
            if ~isfolder(work), mkdir(work); end
            ctx = struct('Rr', Rr, 'prep_dir', prep_dir, 'colmap_exe', colmap_exe, ...
                'models_dir', models_dir, 'run_cmd', run_cmd, 'reader', reader, 'note', note);
            outer = Rr.resolved.outer_rows;
            [req, req_src] = rabbit_sfm_build.orientation_request(Rr);
            O = struct('outer_rows', outer, 'requested', {req_src}, 'candidates', [], ...
                'turns', req, 'reasons', {{'', ''}}, 'known', [], 'reused_build', []);
            use_rig = logical(Rr.rig.use);
            P = [];
            % --- 0. turns an earlier run of the same recording and boxes decided ---
            if any(isnan(req)) && ~isempty(known)
                t = req;
                t(isnan(req)) = known.turns(isnan(req));
                note(sprintf(['known turns: run %s (%s) decided left %d, right %d for this recording and these ' ...
                    'boxes; one build with them'], known.source, known.how, known.turns(1), known.turns(2)));
                [Pk, r] = rabbit_sfm_build.run_pass_set(ctx, r, t, fullfile(work, 'final'), use_rig);
                if ~isempty(r.err), r.summary = struct('orientation', O); return; end
                [hold_ok, why] = rabbit_sfm_build.known_turns_hold(Rr, Pk);
                O.known = struct('turns', known.turns, 'source', known.source, 'how', known.how, ...
                    'held', hold_ok, 'why_not', why);
                O.known.trials = Pk.trials;
                if hold_ok
                    for j = find(isnan(req))
                        O.reasons{j} = sprintf('known from run %s', known.source);
                    end
                    O.turns = t;
                    P = Pk;
                else
                    note(sprintf('known turns do not hold (%s): kept as work/final_known_turns; orientation builds', why));
                    movefile(fullfile(work, 'final'), fullfile(work, 'final_known_turns'));
                end
            end
            % --- 1. the orientation builds (only for tiles left to auto) ---
            Pc = {};
            if any(isnan(req)) && isempty(P)
                cand = struct('turn', {}, 'registered_per_view', {}, 'multi_view_points', {}, ...
                    'accepted', {}, 'trials', {});
                for c = [0 180]
                    t = req;
                    t(isnan(t)) = c;
                    note(sprintf('orientation build: both outer views turned %d (views left to auto)', c));
                    [P, r] = rabbit_sfm_build.run_pass_set(ctx, r, t, ...
                        fullfile(work, sprintf('orient_turn%d', c)), false);
                    if ~isempty(r.err), r.summary = struct('orientation', O); return; end
                    cand(end+1) = struct('turn', c, 'registered_per_view', P.registered_per_view, ...
                        'multi_view_points', P.multi_view_points, 'accepted', P.accepted, ...
                        'trials', P.trials); %#ok<AGROW>
                    Pc{end+1} = P; %#ok<AGROW>
                end
                P = [];
                for j = find(isnan(req))
                    v = outer(j);
                    [O.turns(j), O.reasons{j}] = rabbit_sfm_build.decide_turn( ...
                        [cand(1).registered_per_view(v), cand(1).multi_view_points], ...
                        [cand(2).registered_per_view(v), cand(2).multi_view_points]);
                    note(sprintf('outer view ROI row %d: turn %d (%s)', v, O.turns(j), O.reasons{j}));
                end
                O.candidates = cand;
            end
            % --- 2. the final build with the chosen turns ---
            % An orientation build with exactly these turns has the same
            % tiles, features and first pass as the final build would: it
            % becomes the final build and only the rig pass is run on it
            % (both outer tiles chose the same turn)
            if isempty(P)
                for k = 1:numel(Pc)
                    if isequal(Pc{k}.turns, O.turns) && Pc{k}.accepted && isfield(Pc{k}, 'pass1') && ~isempty(Pc{k}.pass1)
                        src = fullfile(work, sprintf('orient_turn%d', O.candidates(k).turn));
                        note(sprintf('final build: the orientation build with both outer views turned %d is reused; rig pass only', ...
                            O.candidates(k).turn));
                        movefile(src, fullfile(work, 'final'));
                        start = rabbit_sfm_build.rebased(Pc{k}, src, fullfile(work, 'final'));
                        O.reused_build = sprintf('orient_turn%d', O.candidates(k).turn);
                        [P, r] = rabbit_sfm_build.run_pass_set(ctx, r, O.turns, fullfile(work, 'final'), use_rig, start);
                        break;
                    end
                end
            end
            if isempty(P)
                note(sprintf('final build: left outer view turned %d, right %d', O.turns(1), O.turns(2)));
                [P, r] = rabbit_sfm_build.run_pass_set(ctx, r, O.turns, fullfile(work, 'final'), use_rig);
            end
            S = struct();
            S.schema = 'rabbit_sfm_build.model_summary.v2';
            S.orientation = O;
            if ~isempty(r.err)
                if isstruct(P), S.final = rmfield(P, intersect({'pass1'}, fieldnames(P))); end
                r.summary = S;
                return;
            end
            S.final = rmfield(P, intersect({'model_dir', 'pass1'}, fieldnames(P)));
            if ~P.accepted
                r.err = rabbit_sfm_build.guard_failure_text(Rr, P);
                S.n_models = 0; S.chosen = '';
                r.summary = S;
                rabbit_sfm_build.write_text(fullfile(stage_dir, 'model_summary.json'), jsonencode(S, 'PrettyPrint', true));
                return;
            end
            % --- 3. images the rig posed without sparse points of their own ---
            [P, r] = rabbit_sfm_build.drop_posed_only(ctx, r, P, fullfile(work, 'final'));
            if ~isempty(r.err)
                r.summary = S;
                return;
            end
            % --- 4. keep the model, its registered images and score masks ---
            [S, err] = rabbit_sfm_build.keep_model(Rr, P, stage_dir, fullfile(work, 'final'), reader, S);
            if ~isempty(err)
                r.err = err;
                r.summary = S;
                return;
            end
            rabbit_sfm_build.write_text(fullfile(stage_dir, 'model_summary.json'), jsonencode(S, 'PrettyPrint', true));
            rabbit_sfm_build.write_tile_transform(Rr, O.turns, fullfile(stage_dir, 'om_tile_transform.json'));
            % The flips travel with the model: a copy in the model folder,
            % for anyone who takes the folder as an existing sparse model or
            % projects with its cameras
            copyfile(fullfile(stage_dir, 'om_tile_transform.json'), ...
                fullfile(stage_dir, 'model', 'om_tile_transform.json'), 'f');
            r.summary = S;
            r.ok = true;
        end

        function [P, r] = drop_posed_only(ctx, r, P, bdir)
            %% Remove the images the rig posed without sparse points of their own
            % An image with fewer than min_points_per_image sparse points
            % (n_posed_only) has a pose only through the rig; on the main
            % reference recording such images sat behind the heart. They would enter
            % the depth maps, the fusion, the mesh's silhouette filter, the
            % alignment checks and the choice of the projection cameras,
            % so they leave the model: COLMAP image_deleter writes the
            % model without them to <bdir>/anchored. In a rig model it
            % removes the whole frame of such an image (the frame's other
            % images too); the removed names are recorded
            % (P.removed_images) and the step log says so. Removing
            % observations can leave a point with fewer than two images,
            % which COLMAP drops, so another image can fall below the
            % minimum: the check repeats on the new model (at most 5
            % passes; <bdir>/anchored_2, ...) until every image has its
            % own points.
            P.removed_images = {};
            P.posed_only_images = {};
            P.chosen_dir = P.model_dir;
            P.deleter_passes = 0;
            [~, imgs, pts] = ctx.reader(P.model_dir);
            min_obs = rabbit_sfm_build.min_points_per_image(ctx.Rr);
            ik0 = cell2mat(keys(imgs));
            all_names = arrayfun(@(i) imgs(i).name, ik0, 'UniformOutput', false);
            model = P.model_dir;
            max_passes = 5;
            while true
                ik = cell2mat(keys(imgs));
                a = rabbit_sfm_build.anchored(imgs, min_obs);
                if all(a), break; end
                names = cell(1, nnz(~a));
                bad = find(~a);
                for k = 1:numel(bad)
                    names{k} = imgs(ik(bad(k))).name;
                end
                if P.deleter_passes >= max_passes
                    ctx.note(sprintf(['After %d removals, %d image(s) still have fewer than %d sparse points ' ...
                        'of their own; they stay in the model: %s'], max_passes, numel(names), min_obs, ...
                        strjoin(names, ', ')));
                    break;
                end
                pass = P.deleter_passes + 1;
                if pass == 1
                    list = fullfile(bdir, 'posed_only_images.txt');
                    out = fullfile(bdir, 'anchored');
                    ctx.note(sprintf(['%d image(s) have a pose from the rig but fewer than %d sparse points of ' ...
                        'their own; they leave the model (with the rest of their frame): %s'], numel(names), ...
                        min_obs, strjoin(names, ', ')));
                else
                    list = fullfile(bdir, sprintf('posed_only_images_%d.txt', pass));
                    out = fullfile(bdir, sprintf('anchored_%d', pass));
                    ctx.note(sprintf(['After the removal, %d more image(s) have fewer than %d sparse points of ' ...
                        'their own (their points lost the removed images); they leave the model too: %s'], ...
                        numel(names), min_obs, strjoin(names, ', ')));
                end
                if ~isfolder(out), mkdir(out); end
                rabbit_sfm_build.write_text(list, sprintf('%s\n', names{:}));
                rabbit_sfm_build.check_path(list, 'the image list');
                rabbit_sfm_build.check_path(out, 'the model folder');
                line = sprintf(['"%s" image_deleter --input_path "%s" --output_path "%s" --image_names_path "%s" ' ...
                    '--log_target stderr --log_color 0'], ctx.colmap_exe, model, out, list);
                r = rabbit_sfm_build.run_one(ctx, r, line, 600, 'remove the images without sparse points (image_deleter)');
                if ~isempty(r.err), return; end
                [~, imgs, pts] = ctx.reader(out);
                P.posed_only_images = [P.posed_only_images, names];
                P.deleter_passes = pass;
                model = out;
            end
            if P.deleter_passes == 0, return; end
            n2 = cell2mat(keys(imgs));
            kept = arrayfun(@(i) imgs(i).name, n2, 'UniformOutput', false);
            P.removed_images = setdiff(all_names, kept);
            P.model_dir = model;
            [P.registered_per_view, P.multi_view_points] = rabbit_sfm_build.view_counts(imgs, pts, min_obs);
        end

        function [P, r] = run_pass_set(ctx, r, turns, bdir, use_rig, start)
            %% One build: tiles of the given turns, features, guarded mapper, rig
            % start (optional): the P of an earlier build of the same turns
            % now in bdir (rebased); its tiles, features and first pass are
            % kept and only the rig pass runs
            Rr = ctx.Rr;
            P = struct('turns', turns, 'rig', use_rig, 'rig_used', false, 'registered_per_view', zeros(1, 4), ...
                'multi_view_points', 0, 'accepted', false, 'trials', struct('pass', {}, 'seed', {}, ...
                'near_side_fraction', {}, 'n_models', {}, 'n_images', {}, 'n_points', {}, 'accepted', {}), ...
                'model_dir', '', 'pass1', []);
            paths = struct('db', fullfile(bdir, 'database.db'), 'images', fullfile(bdir, 'images'), ...
                'masks', fullfile(bdir, 'masks'), 'lists', fullfile(ctx.prep_dir, 'lists'), ...
                'rig', fullfile(ctx.prep_dir, 'rig_config.json'), 'sparse_out', '', ...
                'input_model', '', 'rig_out', '', 'models', ctx.models_dir);
            if nargin >= 6 && ~isempty(start)
                acc = start.pass1;
                P.trials = start.trials;
                P.accepted = true;
            else
                % Tiles of this build: per view from the turn folder it needs
                [ok, err] = rabbit_sfm_build.assemble(Rr, ctx.prep_dir, bdir, turns);
                if ~ok, r.err = err; return; end
                % Features and matches
                [lines, touts, steps] = rabbit_sfm_build.commands(Rr, 'features', paths, ctx.colmap_exe, []);
                for k = 1:numel(lines)
                    r = rabbit_sfm_build.run_one(ctx, r, lines{k}, touts(k), steps(k).label);
                    if ~isempty(r.err), return; end
                end
                % Mapper without the rig, seeds in order, depth guard
                [acc, trials, r] = rabbit_sfm_build.guarded_mapper(ctx, r, 'mapper', paths, bdir, 'pass1');
                P.trials = trials;
                if ~isempty(r.err), return; end
                if ~isempty(acc)
                    P.accepted = true;
                end
            end
            P.pass1 = acc;
            if use_rig && P.accepted
                % rig_configurator --input_path <accepted first model>
                paths.input_model = acc.model_dir;
                paths.rig_out = fullfile(bdir, 'rig_configured');
                if ~isfolder(paths.rig_out), mkdir(paths.rig_out); end
                [lines, touts, steps] = rabbit_sfm_build.commands(Rr, 'rig', paths, ctx.colmap_exe, []);
                for k = 1:numel(lines)
                    r = rabbit_sfm_build.run_one(ctx, r, lines{k}, touts(k), steps(k).label);
                    if ~isempty(r.err), return; end
                end
                % Mapper with the rig, the same seeds and guard. The rig
                % pass is there to add the images the first pass missed
                % (rabbit SfM study: 200 vs 196-199 of 200), so a seed is
                % kept only when its model has at least as many images as
                % the first pass. On the reference rabbit recording one rig run gave
                % 200 images in one model and another, same seed, split
                % into 7 models with 68 in the largest (GPU matching is not
                % bit-reproducible). When no seed gets there, the first
                % pass's model is kept and the step warns.
                acc1 = acc;
                [acc, trials, r] = rabbit_sfm_build.guarded_mapper(ctx, r, 'rig_mapper', paths, bdir, 'rig', acc1.n_images);
                P.trials = [P.trials, trials];
                if ~isempty(r.err), return; end
                if isempty(acc)
                    ctx.note(sprintf(['rig pass: no seed gave a model that passed the depth guard with %d ' ...
                        'images or more (best %d); the model without the rig is kept'], acc1.n_images, ...
                        max([0, trials.n_images])));
                    acc = acc1;
                else
                    P.rig_used = ~isempty(acc);
                end
                P.accepted = ~isempty(acc);
            end
            if isempty(acc)
                % No seed passed: the counts of the trial nearest to passing
                % (the orientation decision still uses them; a final build
                % fails)
                acc = rabbit_sfm_build.best_trial_model(ctx, P.trials, bdir);
            end
            if ~isempty(acc)
                P.registered_per_view = acc.per_view;
                P.multi_view_points = acc.multi_view_points;
                P.model_dir = acc.model_dir;
            end
        end

        function P = rebased(P, old, new)
            %% The model folders of a build moved from old to new
            if isfield(P, 'model_dir') && startsWith(P.model_dir, old)
                P.model_dir = [new P.model_dir(numel(old) + 1:end)];
            end
            if isfield(P, 'pass1') && isstruct(P.pass1) && startsWith(P.pass1.model_dir, old)
                P.pass1.model_dir = [new P.pass1.model_dir(numel(old) + 1:end)];
            end
        end

        function r = run_one(ctx, r, line, timeout_s, label)
            %% Run one command line through the tab; a failure stops the build
            r.commands_run{end+1} = line;
            [ok, err, code] = ctx.run_cmd(line, timeout_s, label);
            if ~ok
                r.exit_code = code;
                if isempty(err), err = sprintf('%s failed (exit code %d).', label, code); end
                r.err = err;
            end
        end

        function [acc, trials, r] = guarded_mapper(ctx, r, phase, paths, bdir, tag, min_images)
            %% The mapper over the guard seeds; the first model that passes is kept
            % min_images (optional): a model with fewer registered images
            % is not kept either (the rig pass, see run_pass_set)
            if nargin < 7, min_images = 0; end
            Rr = ctx.Rr;
            G = Rr.guard;
            acc = [];
            trials = struct('pass', {}, 'seed', {}, 'near_side_fraction', {}, 'n_models', {}, ...
                'n_images', {}, 'n_points', {}, 'accepted', {});
            seeds = G.seeds;
            if ~logical(G.use), seeds = seeds(1); end
            for s = seeds
                out = fullfile(bdir, sprintf('%s_seed%d', tag, s));
                if ~isfolder(out), mkdir(out); end
                paths.sparse_out = out;
                [lines, touts, steps] = rabbit_sfm_build.commands(Rr, phase, paths, ctx.colmap_exe, s);
                for k = 1:numel(lines)
                    r = rabbit_sfm_build.run_one(ctx, r, lines{k}, touts(k), steps(k).label);
                    if ~isempty(r.err), return; end
                end
                m = rabbit_sfm_build.largest_model(out, ctx.reader, rabbit_sfm_build.min_points_per_image(Rr));
                tr = struct('pass', tag, 'seed', s, 'near_side_fraction', NaN, 'n_models', m.n_models, ...
                    'n_images', m.n_images, 'n_points', m.n_points, 'accepted', false);
                if m.n_models > 0
                    tr.near_side_fraction = m.near_side_fraction;
                    % The study compared the value rounded to 3 decimals
                    tr.accepted = ~logical(G.use) || ...
                        (isfinite(m.near_side_fraction) && round(m.near_side_fraction, 3) >= G.min_near_side_fraction);
                end
                few = m.n_models > 0 && m.n_images < min_images;
                tr.accepted = tr.accepted && ~few;
                trials(end+1) = tr; %#ok<AGROW>
                why = '';
                if few, why = sprintf(' (fewer than the %d images of the first pass)', min_images); end
                ctx.note(sprintf('%s seed %d: %d model(s), %d images, %d points, near-side fraction %.3f -> %s%s', ...
                    tag, s, m.n_models, m.n_images, m.n_points, tr.near_side_fraction, ...
                    rabbit_sfm_build.pick(tr.accepted, 'kept', 'not kept'), why));
                if tr.accepted
                    acc = m;
                    return;
                end
            end
        end

        function acc = best_trial_model(ctx, trials, bdir)
            %% The model of the trial with the highest near-side fraction ([] if none)
            acc = [];
            if isempty(trials), return; end
            f = [trials.near_side_fraction];
            f(~isfinite(f)) = -Inf;
            [fm, i] = max(f);
            if ~isfinite(fm), return; end
            acc = rabbit_sfm_build.largest_model(fullfile(bdir, sprintf('%s_seed%d', trials(i).pass, trials(i).seed)), ...
                ctx.reader, rabbit_sfm_build.min_points_per_image(ctx.Rr));
        end

        function n = min_points_per_image(Rr)
            %% Sparse points an image needs to count as registered
            % The mapper's own minimum for posing an image from its own
            % points (abs_pose_min_num_inliers, 15 in the study recipe). A
            % rig model can pose every image of a frame once one sensor is
            % posed; on the reference rabbit recording one rig pass posed all 50
            % images of view 4 with 1 observation between them, behind
            % the heart. Such images are counted apart (n_posed_only).
            n = 15;
            if isstruct(Rr) && isfield(Rr, 'mapper') && isfield(Rr.mapper, 'abs_pose_min_num_inliers')
                n = double(Rr.mapper.abs_pose_min_num_inliers);
            end
        end

        function a = anchored(imgs, min_obs)
            %% Per image (in key order): at least min_obs observations of sparse points
            ik = cell2mat(keys(imgs));
            a = false(1, numel(ik));
            for k = 1:numel(ik)
                a(k) = nnz(imgs(ik(k)).point3D_ids ~= -1) >= min_obs;
            end
        end

        function m = largest_model(sp, reader, min_obs)
            %% The model with most registered images (then most points) in a mapper output
            % An image counts as registered when it observes at least
            % min_obs sparse points (min_points_per_image; 0 counts every
            % posed image)
            if nargin < 3, min_obs = 0; end
            m = struct('n_models', 0, 'model_dir', '', 'n_images', 0, 'n_posed_only', 0, 'n_points', 0, ...
                'near_side_fraction', NaN, 'per_view', zeros(1, 4), 'multi_view_points', 0, ...
                'models', struct('dir', {}, 'n_images', {}, 'n_posed_only', {}, 'n_points', {}));
            d = dir(sp);
            d = d([d.isdir] & ~startsWith({d.name}, '.'));
            data = {};
            for k = 1:numel(d)
                md = fullfile(sp, d(k).name);
                if exist(fullfile(md, 'images.bin'), 'file') ~= 2 && exist(fullfile(md, 'images.txt'), 'file') ~= 2
                    continue;
                end
                [cams, imgs, pts] = reader(md);
                na = nnz(rabbit_sfm_build.anchored(imgs, min_obs));
                m.models(end+1) = struct('dir', d(k).name, 'n_images', na, ...
                    'n_posed_only', double(imgs.Count) - na, 'n_points', double(pts.Count));
                data{end+1} = {cams, imgs, pts, md}; %#ok<AGROW>
            end
            m.n_models = numel(m.models);
            if m.n_models == 0, return; end
            [~, order] = sortrows([[m.models.n_images]' [m.models.n_points]'], [-1 -2]);
            b = order(1);
            imgs = data{b}{2}; pts = data{b}{3};
            m.model_dir = data{b}{4};
            m.n_images = m.models(b).n_images;
            m.n_posed_only = m.models(b).n_posed_only;
            m.n_points = double(pts.Count);
            m.near_side_fraction = rabbit_sfm_build.near_side_fraction(imgs, pts);
            [m.per_view, m.multi_view_points] = rabbit_sfm_build.view_counts(imgs, pts, min_obs);
        end

        function F = near_side_fraction(imgs, pts)
            %% Depth-reversal guard: mean over images of the near-side fraction
            % c = per-axis median of all 3D points; for image i with pose
            % (R_i, t_i), z_c = (R_i c + t_i)_z and, for each observation
            % of a 3D point X_j, z_j = (R_i X_j + t_i)_z; f_i = fraction of
            % observations with z_j < z_c. F = mean of f_i over the images
            % with observations (an opaque body seen from outside gives
            % ~1, its depth-reversed twin ~0). NaN with fewer than 10
            % points. Same definition as the study (harness.py
            % near_side_fraction).
            F = NaN;
            if pts.Count < 10, return; end
            pk = cell2mat(keys(pts));
            X = zeros(numel(pk), 3);
            for k = 1:numel(pk)
                X(k, :) = reshape(pts(pk(k)).xyz, 1, 3);
            end
            row_of = containers.Map(num2cell(int64(pk)), num2cell(1:numel(pk)));
            c = median(X, 1);
            ik = cell2mat(keys(imgs));
            f = nan(1, numel(ik));
            for k = 1:numel(ik)
                im = imgs(ik(k));
                ids = im.point3D_ids(im.point3D_ids ~= -1);
                ids = ids(isKey(row_of, num2cell(int64(ids))));
                if isempty(ids), continue; end
                rows = cellfun(@(x) row_of(x), num2cell(int64(ids)));
                Rm = rabbit_sfm_build.qvec2rot(im.qvec);
                t = im.tvec(:);
                zc = Rm(3, :) * c(:) + t(3);
                z = X(rows, :) * Rm(3, :)' + t(3);
                f(k) = mean(z < zc);
            end
            f = f(isfinite(f));
            if ~isempty(f), F = mean(f); end
        end

        function [per_view, n_multi] = view_counts(imgs, pts, min_obs)
            %% Registered images per ROI row and points seen in two or more views
            % (an image counts with at least min_obs sparse points)
            if nargin < 3, min_obs = 0; end
            per_view = zeros(1, 4);
            ik = cell2mat(keys(imgs));
            anc = rabbit_sfm_build.anchored(imgs, min_obs);
            view_of = containers.Map('KeyType', 'int64', 'ValueType', 'double');
            for k = 1:numel(ik)
                t = regexp(imgs(ik(k)).name, '_view(\d+)_frame_\d+', 'tokens', 'once');
                v = 0;
                if ~isempty(t), v = str2double(t{1}); end
                view_of(int64(ik(k))) = v;
                if v >= 1 && v <= 4 && anc(k), per_view(v) = per_view(v) + 1; end
            end
            n_multi = 0;
            pk = keys(pts);
            for k = 1:numel(pk)
                ii = pts(pk{k}).image_ids;
                vv = zeros(1, numel(ii));
                for j = 1:numel(ii)
                    if isKey(view_of, int64(ii(j))), vv(j) = view_of(int64(ii(j))); end
                end
                vv = vv(vv > 0);
                if numel(unique(vv)) >= 2, n_multi = n_multi + 1; end
            end
        end

        function [ok, err] = assemble(Rr, prep_dir, bdir, turns)
            %% The tiles of one build: each view from turn0, outer tiles from their turn
            ok = false; err = '';
            subs = {'images'};
            if logical(Rr.masks.use), subs = [subs, {'masks', 'score_masks'}]; end
            for s = subs
                d = fullfile(bdir, s{1});
                if ~isfolder(d), mkdir(d); end
            end
            V = Rr.resolved.views;
            outer = Rr.resolved.outer_rows;
            for v = 1:4
                t = 0;
                j = find(outer == v, 1);
                if ~isempty(j), t = turns(j); end
                src = fullfile(prep_dir, sprintf('turn%d', t));
                for i = 1:numel(V(v).images)
                    nm = V(v).images{i};
                    pairs = {fullfile(src, 'images', nm), fullfile(bdir, 'images', nm)};
                    if logical(Rr.masks.use)
                        pairs(end+1, :) = {fullfile(src, 'masks', [nm '.png']), fullfile(bdir, 'masks', [nm '.png'])}; %#ok<AGROW>
                        pairs(end+1, :) = {fullfile(src, 'score_masks', [nm '.png']), fullfile(bdir, 'score_masks', [nm '.png'])}; %#ok<AGROW>
                    end
                    for p = 1:size(pairs, 1)
                        if exist(pairs{p, 1}, 'file') ~= 2
                            if p == 1
                                err = sprintf('The prepared view %s is missing. Run the preparation step again.', pairs{p, 1});
                                return;
                            end
                            continue;   % a missing mask: the image is used whole
                        end
                        [c_ok, c_msg] = copyfile(pairs{p, 1}, pairs{p, 2}, 'f');
                        if ~c_ok
                            err = sprintf('Could not copy %s: %s', pairs{p, 1}, c_msg);
                            return;
                        end
                    end
                end
            end
            ok = true;
        end

        function txt = guard_failure_text(Rr, P)
            %% Plain message when no seed gave a model facing the cameras
            f = arrayfun(@(t) sprintf('seed %d (%s): %s', t.seed, t.pass, ...
                rabbit_sfm_build.pick(isfinite(t.near_side_fraction), sprintf('%.3f', t.near_side_fraction), 'no model')), ...
                P.trials, 'UniformOutput', false);
            txt = sprintf(['None of the seeds %s gave a model whose observed points lie on the camera side ' ...
                '(near-side fraction at least %g): %s. The model would be depth-reversed (its mirror ' ...
                'twin), so the step stops. Check the views and masks, or add seeds in a custom recipe.'], ...
                mat2str(Rr.guard.seeds), Rr.guard.min_near_side_fraction, strjoin(f, '; '));
        end

        function [S, err] = keep_model(Rr, P, stage_dir, bdir, reader, S)
            %% Copy the chosen model, its registered images and score masks; fill the summary
            err = '';
            src = P.model_dir;
            [cams, imgs, pts] = reader(src);
            model_dir = fullfile(stage_dir, 'model');
            img_dir = fullfile(stage_dir, 'images');
            sm_dir = fullfile(stage_dir, 'score_masks');
            for p = {model_dir, img_dir}
                if ~isfolder(p{1}), mkdir(p{1}); end
            end
            f = dir(src);
            f = f(~[f.isdir]);
            for k = 1:numel(f)
                copyfile(fullfile(src, f(k).name), fullfile(model_dir, f(k).name), 'f');
            end
            ids = cell2mat(keys(imgs));
            names = cell(1, numel(ids));
            cam_of_view = zeros(1, 4);
            for k = 1:numel(ids)
                im = imgs(ids(k));
                names{k} = im.name;
                copyfile(fullfile(bdir, 'images', im.name), fullfile(img_dir, im.name), 'f');
                ms = fullfile(bdir, 'score_masks', [im.name '.png']);
                if exist(ms, 'file') == 2
                    if ~isfolder(sm_dir), mkdir(sm_dir); end
                    copyfile(ms, fullfile(sm_dir, [im.name '.png']), 'f');
                end
                t = regexp(im.name, '_view(\d+)_frame_\d+', 'tokens', 'once');
                if ~isempty(t)
                    v = str2double(t{1});
                    if v >= 1 && v <= 4, cam_of_view(v) = double(im.camera_id); end
                end
            end
            cam_ids = cell2mat(keys(cams));
            cam_rec = struct('id', {}, 'model', {}, 'width', {}, 'height', {}, 'params', {}, 'focal_change_frac', {});
            for k = 1:numel(cam_ids)
                c = cams(cam_ids(k));
                fch = abs(c.params(1) - Rr.resolved.focal_prior_px) / Rr.resolved.focal_prior_px;
                cam_rec(end+1) = struct('id', double(cam_ids(k)), 'model', c.model, ...
                    'width', double(c.width), 'height', double(c.height), ...
                    'params', reshape(c.params, 1, []), 'focal_change_frac', fch); %#ok<AGROW>
            end
            errs = zeros(1, pts.Count);
            pk = keys(pts);
            tl = zeros(1, pts.Count);
            for k = 1:numel(pk)
                errs(k) = pts(pk{k}).error;
                tl(k) = numel(pts(pk{k}).image_ids);
            end
            chosen = src;
            if isfield(P, 'chosen_dir') && ~isempty(P.chosen_dir), chosen = P.chosen_dir; end
            [~, mdir] = fileparts(chosen);
            min_obs = rabbit_sfm_build.min_points_per_image(Rr);
            m = rabbit_sfm_build.largest_model(fileparts(chosen), reader, min_obs);
            n_anc = nnz(rabbit_sfm_build.anchored(imgs, min_obs));
            S.n_models = m.n_models;
            S.models = m.models;
            S.chosen = mdir;
            S.chosen_from = strrep(strrep(chosen, [stage_dir filesep], ''), char(92), '/');
            % images the rig posed without sparse points, and their frames,
            % left out of the model (drop_posed_only)
            S.posed_only_removed = {};
            S.images_removed = {};
            if isfield(P, 'posed_only_images'), S.posed_only_removed = P.posed_only_images; end
            if isfield(P, 'removed_images'), S.images_removed = P.removed_images; end
            if isfield(P, 'deleter_passes'), S.posed_only_passes = P.deleter_passes; end
            S.n_selected = Rr.resolved.n_images;
            % registered = posed and seen in >= min_obs sparse points; the
            % others keep their pose in the model (n_posed_only)
            S.min_points_per_image = min_obs;
            S.n_registered = n_anc;
            S.n_posed_only = numel(ids) - n_anc;
            S.registered_fraction = n_anc / max(1, Rr.resolved.n_images);
            S.registered_per_view = P.registered_per_view;
            S.camera_of_view = cam_of_view;
            S.n_points = double(pts.Count);
            S.multi_view_points = P.multi_view_points;
            S.mean_track_length = NaN;
            S.mean_reproj_px = NaN;
            if ~isempty(errs)
                S.mean_reproj_px = mean(errs);
                S.mean_track_length = mean(tl);
            end
            acc = P.trials([P.trials.accepted]);
            S.near_side_fraction = acc(end).near_side_fraction;
            S.seed = acc(end).seed;
            S.cameras = cam_rec;
            S.focal_prior_px = Rr.resolved.focal_prior_px;
            S.registered_images = sort(names);
            S.score_masks = isfolder(sm_dir);
        end

        function write_tile_transform(Rr, turns, path)
            %% om_tile_transform.json: how the SfM tiles differ from the cut tiles
            % The final flips per ROI row (the base flip and the turn the
            % build chose). The tab's reprojection flips the activation map
            % and the OM frames of each view the same way; anyone
            % projecting OM data with these cameras by hand must too.
            V = Rr.resolved.views;
            outer = Rr.resolved.outer_rows;
            T = struct();
            T.schema = 'rabbit_sfm_build.om_tile_transform.v2';
            T.note = ['The cameras of this model image the cut views flipped as listed (a 180 degree ' ...
                'turn of a left-right flipped view is an up-down flip). Flip the activation map and the OM ' ...
                'frames of each view the same way before projecting with these cameras; the Reconstruction ' ...
                'tab does this itself.'];
            views = struct('roi_row', {}, 'view_name', {}, 'image_prefix', {}, 'tile_hw', {}, ...
                'outer', {}, 'base_flip_lr', {}, 'turn', {}, 'flip_lr', {}, 'flip_ud', {});
            for v = 1:4
                t = 0;
                j = find(outer == v, 1);
                if ~isempty(j), t = turns(j); end
                [lr, ud] = rabbit_sfm_build.view_transform(V(v).base_flip_lr, t);
                views(end+1) = struct('roi_row', V(v).roi_row, 'view_name', V(v).view_name, ...
                    'image_prefix', V(v).image_prefix, 'tile_hw', V(v).tile_hw, 'outer', V(v).outer, ...
                    'base_flip_lr', V(v).base_flip_lr, 'turn', t, 'flip_lr', lr, 'flip_ud', ud); %#ok<AGROW>
            end
            T.views = views;
            rabbit_sfm_build.write_text(path, jsonencode(T, 'PrettyPrint', true));
        end

        function flips = view_flips(views)
            %% Flip codes per ROI row ('none' | 'lr' | 'ud' | 'lrud')
            % views: struct array with flip_lr / flip_ud (the
            % om_tile_transform.json views).
            if iscell(views), views = [views{:}]; end
            flips = cell(1, numel(views));
            for k = 1:numel(views)
                c = '';
                if logical(views(k).flip_lr), c = [c 'lr']; end %#ok<AGROW>
                if logical(views(k).flip_ud), c = [c 'ud']; end %#ok<AGROW>
                if isempty(c), c = 'none'; end
                flips{k} = c;
            end
        end

        % =============================================================
        % 7. Silhouette filter of the fused cloud (used by the mesh step)
        % =============================================================

        function [keep, n_in, n_hit] = silhouette_filter(X, cams, min_inside)
            %% Keep points inside the tissue mask in >= min_inside of the images they land in
            % X: N x 3 points; cams: struct array with R (3x3), t (3x1),
            % f [fx fy], c [cx cy], width, height, mask (logical, height x
            % width). A point lands in an image when it lies in front of
            % the camera and projects to 0 <= u < width-1, 0 <= v <
            % height-1 (COLMAP pixel coordinates, pixel k covering
            % [k-1, k)); it is inside when the mask is set at
            % (floor(v)+1, floor(u)+1). A point that lands in no image is
            % dropped. Same rule as the study (carve.py), including its
            % u < width-1, v < height-1: a point in the last pixel column
            % or row does not count as landing (kept for parity with the
            % study, whose limits were measured with it). The rule is the
            % silhouette (visual hull) constraint of shape from silhouettes
            % (Laurentini 1994, IEEE PAMI 16(2):150-162), with a tolerance
            % for imperfect masks.
            % A camera with a non-empty field 'band' (logical, the size of
            % the mask; field_band) abstains for the points that land in
            % it: they count neither as inside nor as landing there.
            N = size(X, 1);
            n_in = zeros(N, 1);
            n_hit = zeros(N, 1);
            has_band = isfield(cams, 'band');
            for i = 1:numel(cams)
                Xc = X * cams(i).R' + reshape(cams(i).t, 1, 3);
                z = Xc(:, 3);
                u = cams(i).f(1) * Xc(:, 1) ./ z + cams(i).c(1);
                v = cams(i).f(2) * Xc(:, 2) ./ z + cams(i).c(2);
                ok = z > 0 & u >= 0 & v >= 0 & u < cams(i).width - 1 & v < cams(i).height - 1;
                idx = find(ok);
                lin = sub2ind(size(cams(i).mask), floor(v(idx)) + 1, floor(u(idx)) + 1);
                if has_band && ~isempty(cams(i).band)
                    vote = ~cams(i).band(lin);   % points in the field band abstain
                    idx = idx(vote);
                    lin = lin(vote);
                end
                n_in(idx) = n_in(idx) + 1;
                n_hit(idx) = n_hit(idx) + double(cams(i).mask(lin));
            end
            keep = n_hit >= min_inside * max(n_in, 1);
        end

        function band = field_band(mask, k_px)
            %% The field band of a tissue mask: outside pixels between a field edge and the tile border
            % Per image row, the mask's left edge is taken as a field edge
            % (the edge of the mirror's field of view, not the heart's
            % outline) when it lies within k_px of the left tile border
            % (its first mask pixel is at most k_px pixels in); the band is
            % then the pixels of that row left of it. The same for the
            % right edge, and per column for the top and bottom edges.
            % Rows or columns without mask pixels have no band; k_px = 0
            % gives no band.
            % Why: on the reference rabbit recording, view 4's left mask
            % edge is the mirror's field edge (static over the frames,
            % sd 3.4 px, about 20 px from the tile border, a soft ~110 px
            % ramp) with dim tissue continuing past it; the other views'
            % accepted points run 13 px past it. This rule looks
            % at one mask only, so a heart limb within k_px of the border
            % gets a band too (on one run, 4 of 7 banded sides were
            % limbs). The pipeline therefore uses
            % static_field_bands, which keeps only the edges that stay
            % still over a view's frames.
            mask = logical(mask);
            [h, w] = size(mask);
            band = false(h, w);
            if k_px <= 0 || ~any(mask(:)), return; end
            rows_on = any(mask, 2);              % h x 1
            [~, first_c] = max(mask, [], 2);     % first mask column per row
            [~, last_rc] = max(fliplr(mask), [], 2);
            last_c = w - last_rc + 1;            % last mask column per row
            cols = 1:w;
            band = band | ((rows_on & first_c - 1 <= k_px) & cols < first_c);
            band = band | ((rows_on & w - last_c <= k_px) & cols > last_c);
            cols_on = any(mask, 1);              % 1 x w
            [~, first_r] = max(mask, [], 1);     % first mask row per column
            [~, last_rr] = max(flipud(mask), [], 1);
            last_r = h - last_rr + 1;            % last mask row per column
            rows = (1:h)';
            band = band | ((cols_on & first_r - 1 <= k_px) & rows < first_r);
            band = band | ((cols_on & h - last_r <= k_px) & rows > last_r);
        end

        function [bands, rec] = static_field_bands(names, masks, k_px)
            %% Field bands from the mask edges that stay still over a view's frames
            % names: cell of image names (<...>_view<V>_frame_<N>...);
            % masks: cell of logical tissue masks, same order. bands: cell,
            % same order, each the image's field band (logical, the size of
            % its mask; no pixel set = no band). rec: one entry per view:
            % the frames, and per border side the image rows (left, right)
            % or columns (top, bottom) taken as a field edge (still) and
            % the ones near the border that move with the heart.
            % The rule: per view (images of one view, same mask size, at
            % least 8 frames), per border side and image line, the mask
            % edge's distance from the border is followed over the frames.
            % A line is a candidate when its edge lies within k_px of the
            % border in at least 3 frames and 10 % of the frames; adjacent
            % candidate lines form a run (at least 5 lines). Per line, the
            % sd of that distance over those frames; a line's stillness is
            % the larger of the median sd over its 21 neighbouring lines
            % and the median sd over its whole run. The run's median keeps
            % the ends of a limb's run out (where the limb only touches
            % the border band in a few frames at its turning point its sd
            % is small, as at one run's view 1 top), the local median keeps a
            % moving part of an otherwise still run out. A line whose
            % stillness is at most 5 px is a field edge: the edge of the
            % mirror's field of view, which does not move when the heart
            % turns. In each
            % frame its band is then the outside pixels between the edge
            % and the border, when the edge lies within k_px of the border
            % and at most 10 px further in than its median position (a
            % frame where the tissue stops short of the field edge shows
            % the heart's own outline there, which keeps judging).
            % A heart limb near the border moves with the heart and gets
            % no band.
            % Why 5 px: over the four reference recordings and runs of
            % the main one the field edges (still in the
            % mean mask over the frames) have a median sd per side of
            % 0.0-4.8 px, the heart limbs near the border 6.1-12.9 px
            % (one run: field edges 2.0-3.7 px, limbs 7.9-11.1 px).
            % Needs the frames of a turning heart: a view with fewer than
            % 8 frames gets no band (recorded). A static object that is
            % not a field edge (e.g. a bright panel next to the heart) is
            % still and is banded too.
            % k_px = 0 gives no band.
            sd_limit = 5;          % px: a field edge's sd over the frames is at most this
            back_tol = 10;         % px: a frame's edge further in than this from the median is the heart's
            min_frames = 8;        % frames of a view needed to tell still from moving
            window = 21;           % lines: the local stillness is the median over this many candidate lines
            min_run = 5;           % lines: shorter runs of candidate lines are noise
            n = numel(masks);
            bands = cell(1, n);
            for i = 1:n
                bands{i} = false(size(masks{i}));
            end
            rec = struct('view', {}, 'frames', {}, 'size', {}, 'note', {}, 'sides', {});
            if k_px <= 0 || n == 0, return; end
            tok = regexp(names, '_view(\d+)_frame_(\d+)', 'tokens', 'once');
            view = nan(1, n);
            for i = 1:n
                if ~isempty(tok{i}), view(i) = str2double(tok{i}{1}); end
            end
            if any(isnan(view))
                rec(end+1) = struct('view', NaN, 'frames', nnz(isnan(view)), 'size', [], 'note', ...
                    'image names without _view<V>_frame_<N>: no field band for them', 'sides', []);
            end
            side_names = {'left', 'right', 'top', 'bottom'};
            for v = unique(view(~isnan(view)))
                idx = find(view == v);
                sz = cell2mat(cellfun(@size, masks(idx)', 'UniformOutput', false));
                [usz, ~, which] = unique(sz, 'rows');
                [~, common] = max(accumarray(which, 1));
                idx = idx(which == common);              % the images of the view's usual size
                entry = struct('view', v, 'frames', numel(idx), 'size', usz(common, :), 'note', '', ...
                    'sides', struct('side', {}, 'still_lines', {}, 'segments', {}, 'edge_px', {}, ...
                    'sd_px', {}, 'moving_lines', {}, 'moving_sd_px', {}));
                if numel(idx) < min_frames
                    entry.note = sprintf(['%d frames, fewer than %d: a still field edge cannot be told from ' ...
                        'the heart''s moving outline, so no field band'], numel(idx), min_frames);
                    rec(end+1) = entry; %#ok<AGROW>
                    continue;
                end
                M = cat(3, masks{idx});
                B = false(size(M));
                for s = 1:4
                    switch s                         % lines x depth from the border x frames
                        case 1, A = M;
                        case 2, A = flip(M, 2);
                        case 3, A = permute(M, [2 1 3]);
                        case 4, A = flip(permute(M, [2 1 3]), 2);
                    end
                    [nl, depth, nf] = size(A);
                    on = reshape(any(A, 2), nl, nf);
                    [~, first] = max(A, [], 2);
                    d = reshape(first, nl, nf) - 1;         % edge distance from the border (px)
                    near = on & d <= k_px;
                    dn = d;
                    dn(~near) = NaN;
                    nb = sum(near, 2);
                    sd = std(dn, 0, 2, 'omitnan');
                    sd(nb < 3) = NaN;
                    pos = median(dn, 2, 'omitnan');
                    cand = nb >= max(3, ceil(0.1 * nf));
                    still_sd = nan(nl, 1);
                    edges = diff([0; cand; 0]);
                    starts = find(edges == 1);
                    stops = find(edges == -1) - 1;
                    for q = 1:numel(starts)
                        run = starts(q):stops(q);
                        if numel(run) < min_run, continue; end
                        % the larger of the run's median and the local median
                        still_sd(run) = max(movmedian(sd(run), window, 'omitnan', 'Endpoints', 'shrink'), ...
                            median(sd(run), 'omitnan'));
                    end
                    still = cand & still_sd <= sd_limit;
                    use = still & near & d <= pos + back_tol;   % lines x frames with a band
                    BA = reshape(use, nl, 1, nf) & ((1:depth) <= reshape(d, nl, 1, nf));
                    switch s
                        case 1, B = B | BA;
                        case 2, B = B | flip(BA, 2);
                        case 3, B = B | permute(BA, [2 1 3]);
                        case 4, B = B | permute(flip(BA, 2), [2 1 3]);
                    end
                    e2 = diff([0; still; 0]);
                    seg = [find(e2 == 1) find(e2 == -1) - 1];
                    moving = cand & ~still;
                    entry.sides(end+1) = struct('side', side_names{s}, 'still_lines', nnz(still), ...
                        'segments', seg, 'edge_px', median(pos(still)), 'sd_px', median(sd(still), 'omitnan'), ...
                        'moving_lines', nnz(moving), 'moving_sd_px', median(sd(moving), 'omitnan'));
                end
                for j = 1:numel(idx)
                    bands{idx(j)} = B(:, :, j) & ~M(:, :, j);
                end
                rec(end+1) = entry; %#ok<AGROW>
            end
        end

        function idx = silhouette_frames_pick(frame_numbers, n)
            %% n evenly spaced frames of a sorted list (the study's rule)
            % frames(fix(linspace(0, numel-1, n)) + 1), as numpy's
            % linspace(...).astype(int); n = 0 keeps all.
            frame_numbers = unique(frame_numbers);
            if n <= 0 || n >= numel(frame_numbers)
                idx = frame_numbers;
                return;
            end
            idx = frame_numbers(fix(linspace(0, numel(frame_numbers) - 1, n)) + 1);
        end

        % =============================================================
        % 8. Small helpers
        % =============================================================

        function txt = to_json(R)
            %% Pretty JSON of a recipe
            txt = jsonencode(R, 'PrettyPrint', true);
        end

        function [R, err] = from_json_file(path)
            %% Read and check a recipe JSON file
            err = '';
            try
                R = rabbit_sfm_build.normalise(jsondecode(fileread(path)));
            catch ME
                R = [];
                err = sprintf('Could not read the recipe %s: %s', path, ME.message);
                return;
            end
            [ok, verr] = rabbit_sfm_build.validate(R);
            if ~ok, err = verr; end
        end

        function h = sha256_text(txt)
            %% sha256 (lowercase hex) of UTF-8 text
            md = java.security.MessageDigest.getInstance('SHA-256');
            b = md.digest(uint8(unicode2native(char(txt), 'UTF-8')));
            h = lower(reshape(dec2hex(typecast(int8(b), 'uint8'), 2)', 1, []));
        end

        function h = sha256_file(path)
            %% sha256 (lowercase hex) of a file
            fid = fopen(path, 'rb');
            if fid < 0, h = ''; return; end
            data = fread(fid, Inf, '*uint8');
            fclose(fid);
            md = java.security.MessageDigest.getInstance('SHA-256');
            if isempty(data)
                b = md.digest();   % an empty file (Java refuses an empty array)
            else
                b = md.digest(data);
            end
            h = lower(reshape(dec2hex(typecast(int8(b), 'uint8'), 2)', 1, []));
        end

        function a = artifact_tree(root, base)
            %% One {path, sha256} record per file under root (sorted)
            % With base, paths are relative to it with / separators (run
            % folders can move; the tab rebases relative paths).
            if nargin < 2, base = ''; end
            a = struct('path', {}, 'sha256', {});
            files = rabbit_sfm_build.walk(root);
            files = sort(files);
            for k = 1:numel(files)
                p = files{k};
                if ~isempty(base) && startsWith(p, [base filesep])
                    p = strrep(p(numel(base) + 2:end), char(92), '/');
                end
                a(end+1) = struct('path', p, 'sha256', rabbit_sfm_build.sha256_file(files{k})); %#ok<AGROW>
            end
        end

        function files = walk(root)
            %% All files under root (recursive, no hidden entries)
            files = {};
            if ~isfolder(root), return; end
            d = dir(root);
            for k = 1:numel(d)
                if d(k).name(1) == '.', continue; end
                p = fullfile(root, d(k).name);
                if d(k).isdir
                    files = [files, rabbit_sfm_build.walk(p)]; %#ok<AGROW>
                else
                    files{end+1} = p; %#ok<AGROW>
                end
            end
        end

        function names = list_images(folder)
            %% Image files directly in folder (TIFF, PNG, JPEG)
            names = {};
            if ~isfolder(folder), return; end
            d = dir(folder);
            names = {d(~[d.isdir]).name};
            names = names(~cellfun(@isempty, regexpi(names, '\.(tiff?|png|jpe?g)$', 'once')));
        end

        function write_text(path, txt)
            %% Write UTF-8 text (errors if the file cannot be opened)
            fid = fopen(path, 'w', 'n', 'UTF-8');
            if fid < 0
                error('analyse_om:SparseModel:Write', 'Could not write %s.', path);
            end
            fwrite(fid, txt, 'char');
            fclose(fid);
        end

        function s = num(x)
            %% A number as short exact-enough text
            s = sprintf('%.10g', x);
        end

        function R = qvec2rot(q)
            %% COLMAP quaternion (w, x, y, z) -> rotation matrix
            w = q(1); x = q(2); y = q(3); z = q(4);
            R = [1 - 2*y^2 - 2*z^2, 2*x*y - 2*w*z, 2*x*z + 2*w*y; ...
                2*x*y + 2*w*z, 1 - 2*x^2 - 2*z^2, 2*y*z - 2*w*x; ...
                2*x*z - 2*w*y, 2*y*z + 2*w*x, 1 - 2*x^2 - 2*y^2];
        end
    end

    methods (Static, Access = private)

        function tf = is_whole(x)
            %% A single whole number
            tf = isnumeric(x) && isscalar(x) && isfinite(x) && x == round(x);
        end

        function s = yes_no(tf)
            %% 'on' / 'off' for a switch
            if logical(tf), s = 'on'; else, s = 'off'; end
        end

        function v = pick(tf, a, b)
            %% a when tf, else b
            if tf, v = a; else, v = b; end
        end

        function tf = when_holds(R, w)
            %% Evaluate a 'when' switch: '' | 'a.b' | '!a.b' | 'a.b=TEXT' | 'a.b~TEXT'
            w = strtrim(char(w));
            if isempty(w), tf = true; return; end
            neg = startsWith(w, '!');
            if neg, w = w(2:end); end
            eq = strfind(w, '=');
            pre = strfind(w, '~');
            if ~isempty(eq)
                val = rabbit_sfm_build.field_text(R, w(1:eq(1) - 1));
                tf = strcmpi(val, w(eq(1) + 1:end));
            elseif ~isempty(pre)
                val = rabbit_sfm_build.field_text(R, w(1:pre(1) - 1));
                tf = startsWith(val, w(pre(1) + 1:end), 'IgnoreCase', true);
            else
                v = rabbit_sfm_build.get_field(R, w);
                tf = ~isempty(v) && all(logical(v(:)));
            end
            if neg, tf = ~tf; end
        end

        function v = get_field(R, path)
            %% Recipe field by dotted path (error when absent)
            parts = strsplit(path, '.');
            v = R;
            for k = 1:numel(parts)
                if ~isstruct(v) || ~isfield(v, parts{k})
                    error('analyse_om:SparseModel:Token', 'The recipe has no field ''%s''.', path);
                end
                v = v.(parts{k});
            end
        end

        function s = field_text(R, path)
            %% A recipe field as command-line text
            v = rabbit_sfm_build.get_field(R, path);
            if islogical(v)
                s = sprintf('%d', v);
            elseif isnumeric(v) && isscalar(v)
                s = rabbit_sfm_build.num(v);
            elseif ischar(v) || isstring(v)
                s = char(v);
            else
                error('analyse_om:SparseModel:Token', 'Recipe field ''%s'' is not a single value.', path);
            end
        end

        function val = expand(R, val, ptok, v, seed)
            %% Replace the tokens of one option value
            toks = regexp(val, '\{([A-Za-z0-9_.]+)\}', 'tokens');
            for k = 1:numel(toks)
                t = toks{k}{1};
                if any(strcmp(t, rabbit_sfm_build.PATH_TOKENS))
                    p = ptok.(t);
                    if isempty(p)
                        error('analyse_om:SparseModel:Token', 'Path token {%s} has no value here.', t);
                    end
                    rabbit_sfm_build.check_path(p, t);
                    rep = sprintf('"%s"', p);
                elseif strcmp(t, 'VIEW')
                    rep = sprintf('%d', v);
                elseif strcmp(t, 'VIEW_CAMERA')
                    if v < 1, error('analyse_om:SparseModel:Token', '{VIEW_CAMERA} needs a per-view command.'); end
                    rep = R.resolved.views(v).camera_params;
                elseif strcmp(t, 'MAPPER_SEED')
                    if isempty(seed), error('analyse_om:SparseModel:Token', '{MAPPER_SEED} needs a mapper seed.'); end
                    rep = sprintf('%d', seed);
                else
                    rep = rabbit_sfm_build.field_text(R, t);
                    if ~isempty(regexp(rep, '[%"&|^<>\s]', 'once'))
                        error('analyse_om:SparseModel:Token', 'Recipe field ''%s'' contains a character the shell would read.', t);
                    end
                end
                val = strrep(val, ['{' t '}'], rep);
            end
        end

        function check_path(p, what)
            %% Refuse paths the batch file could not quote safely
            if ~isempty(regexp(p, '[%"]', 'once'))
                error('analyse_om:SparseModel:Path', 'The path for %s contains %% or ", which a batch file cannot quote: %s', what, p);
            end
        end

        function s = cell_to_struct(c)
            %% Cell of like-shaped structs -> struct array
            s = c{1};
            for k = 2:numel(c)
                s(k) = orderfields(c{k}, s(1));
            end
        end

        function d = diff_struct(A, B, prefix, d)
            %% Leaf differences between two recipe structs
            fa = fieldnames(A); fb = fieldnames(B);
            all_f = unique([fa; fb], 'stable');
            for k = 1:numel(all_f)
                f = all_f{k};
                p = f;
                if ~isempty(prefix), p = [prefix '.' f]; end
                if any(strcmp(f, {'resolved', 'status', 'note'})), continue; end
                if ~isfield(A, f)
                    d(end+1) = struct('parameter', p, 'old', '', 'new', jsonencode(B.(f))); %#ok<AGROW>
                elseif ~isfield(B, f)
                    d(end+1) = struct('parameter', p, 'old', jsonencode(A.(f)), 'new', ''); %#ok<AGROW>
                elseif isstruct(A.(f)) && isscalar(A.(f)) && isstruct(B.(f)) && isscalar(B.(f))
                    d = rabbit_sfm_build.diff_struct(A.(f), B.(f), p, d);
                elseif ~strcmp(jsonencode(A.(f)), jsonencode(B.(f)))
                    d(end+1) = struct('parameter', p, 'old', jsonencode(A.(f)), 'new', jsonencode(B.(f))); %#ok<AGROW>
                end
            end
        end
    end
end
