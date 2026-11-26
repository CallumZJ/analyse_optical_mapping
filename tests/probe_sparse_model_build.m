function probe_sparse_model_build
%% Probe: the "Build sparse model" steps of the Reconstruction tab
% Collin Snitchler
% 14.10.2026
% Builds a tiny cut dataset at run time (4 views x 5 frames of 48x64 uint16
% TIFFs named tiny_view<k>_frame_000f.tiff with a bright "heart" on a dark
% bath, the cut manifest.json and an ROI file) and drives sparse_prep and
% sparse_build with the stand-in COLMAP tests/helpers/fake_colmap/colmap.bat,
% whose mapper "makes" canned text models (a sphere of points seen from a
% ring of cameras; "good" models observe the camera side of the sphere,
% "reversed" ones the far side). No GPU and no real COLMAP are needed.
% Checks:
%   R1  recipe: the study defaults validate and survive a JSON round trip;
%       the frame stride max(1, floor(N/40)) gives 2/3/6/30 for N =
%       100/120/240/1200; shell characters, a principal point other than
%       the tile centre and a wrong schema are refused.
%   R2  preprocessing: nearest-rank stretch limits; the tissue mask keeps
%       the largest region, fills holes and its feature mask is the score
%       mask dilated by the 8 px disk; the separable Gaussian equals
%       imgaussfilt; an outer tile turned 180 is flipud of the original.
%   R3  depth guard: the near-side fraction is ~1 for a good and ~0 for a
%       reversed model; the turn rule (more registered images, then more
%       multi-view points, then 0); the orientation request (auto, per
%       tile, camera upside down); silhouette frames; the silhouette filter.
%   R3b field band: a mask edge within 32 px of the tile border (a mirror's
%       field edge) gives a band out to the border, where the filter
%       abstains, so a point beyond that edge is kept on the other views'
%       votes; a mask edge 40 px from the border gives no band and a point
%       in the clear bath beyond it is still rejected; top and bottom edges
%       likewise; the recipe default is 32 px and a negative value is
%       refused.
%   R3c one open edge: the recipe default mesh.single_open_edge is on and
%       the recipe text says so; a value other than true/false/0/1 is
%       refused; a recipe without the field validates (an old recipe: off).
%   S1  create_run of a built run records manifest.pipeline (built, fused,
%       8 steps without APDe-MVS; 10 with the APDe-MVS cloud) and a
%       read-only inputs/sfm_recipe.json; a supplied run keeps 8 steps.
%   S2  sparse_prep: stride rule on the fixture (frames 1, 3, 5),
%       deterministic tiles (two runs give the same hashes), the outer
%       tiles prepared under turn0 and turn180, inner tiles once, masks,
%       lists, the rig file with the reference view FIRST, 64-hex hashes.
%   S3  the command lines of each phase match the golden lines (ALIKED +
%       LightGlue, 60 inliers, fixed focal, mapper seed); a local model
%       file is passed only when the models folder has it; an option COLMAP
%       does not list and a model sha256 that differs from COLMAP's default
%       fail the tool check.
%   S4  the build (orientation auto): two orientation builds, the turn per
%       outer tile, the guard tries seeds until a model faces the cameras,
%       the rig pass; the model, its registered images and score masks are
%       kept; om_tile_transform.json and run_view_flips give lr / ud; the
%       per-seed values are in the manifest; two models WARN.
%   S5  every seed reversed FAILS with the seeds listed; a view with no
%       registered image FAILS. S5c/S5d: the rig pass keeps a seed only when
%       it registers as many images as the first pass; when none does, the
%       model without the rig is kept and the step WARNS. S5e: an image
%       posed without sparse points (rig) is not counted as registered.
%   S6  the dense steps read the built model (SIMPLE_RADIAL accepted only
%       for the undistortion step).
%   S7  a model changed after it was built is refused on resume.
%   S8  cancel during the build gives CANCELLED; the next attempt keeps the
%       old folder as sparse_build.attempt_* and starts afresh.
%   S13 a retry of image_undistorter (COLMAP 4.2.1 crashes when it runs
%       into a workspace that already holds images) keeps the earlier
%       workspace as image_undistorter.attempt_* (or <dense_dir>.attempt_*
%       for a workspace the caller named) and passes.
%   S9  the legacy golden run keeps its eight steps (needs
%       OM_TEST_RESTORE_GOLDEN_ROOT; skipped without it).
%   S10 validate_sparse_model does not count the cut manifest.json as an
%       unregistered image.
%   S11 manifest.pipeline survives the v1 -> v2 conversion and the frozen-
%       field check of the sidecar.
%   S12 a built run on the fused cloud refuses the APDe-MVS cloud for the
%       mesh; the mesh step of a built run uses the run's score masks, the
%       silhouette filter, the recipe's silhouette frames, field band and
%       one-open-edge cut (0 for a recipe without it; opts override), and
%       the recipe's silhouette cap (off; 1 for a recipe without the setting).
%   K1  a second run of the same recording and boxes takes the turns the
%       first decided (orientation.reuse_turns): one build, no orientation
%       builds, the source recorded.
%   K2  known turns that do not hold (an outer tile unregistered) are kept
%       as work/final_known_turns and the orientation builds run.
%   K3  both outer tiles choose the same turn: that orientation build
%       becomes the final build and only the rig pass runs on it.
%   G1-G3 the step 2 controls of the app (headless; OM_SFM_SKIP_GUI=1 skips).
% Usage: matlab -batch "addpath('<repo>/tests'); probe_sparse_model_build"
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
if strcmp(getenv('OM_APP_HEADLESS'), '1')
    addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
end
pass = 0;
fail = 0;
fake = fullfile(repo_dir, 'tests', 'helpers', 'fake_colmap', 'colmap.bat');
env_names = {'OM_FAKE_COLMAP_MODEL', 'OM_FAKE_COLMAP_EXIT', 'OM_FAKE_COLMAP_FAIL_ON', ...
    'OM_FAKE_COLMAP_SLEEP', 'OM_FAKE_COLMAP_LOG'};
for k = 1:numel(env_names), setenv(env_names{k}, ''); end

root = tempname;
mkdir(root);
cleanup = onCleanup(@() cleanup_root(root)); %#ok<NASGU>

%% Fixture: 4 views x 5 frames, a bright ellipse ("heart") on a dark bath
H = 48; W = 64; n_frames = 5;
bounds = [31 1 78 64; 31 101 78 164; 31 181 78 244; 31 301 78 364];
cut = fullfile(root, 'cut_tiffs_reconstruction_tiny');
mkdir(cut);
src = cell(4, n_frames);
[cc, rr] = meshgrid(1:W, 1:H);
for v = 1:4
    for f = 1:n_frames
        heart = ((cc - 30 - v) / 18) .^ 2 + ((rr - 22 - f) / 12) .^ 2 <= 1;
        im = uint16(100 + 2 * cc + rr + 2000 * heart + 37 * v + 11 * f);
        name = sprintf('tiny_view%d_frame_%04d.tiff', v, f);
        imwrite(im, fullfile(cut, name), 'Compression', 'none');
        src{v, f} = im;
    end
end
cm = struct('version', 1, 'dataset', 'reconstruction', 'source', 'tiny.fits', ...
    'source_dims', struct('height', 100, 'width', 400, 'n_frames', n_frames), ...
    'roi_bounds', struct('schema', 'region_bounds_src', ...
    'coordinates', 'unmirrored source, MATLAB 1-based, inclusive', ...
    'view_order', 'view2; view3; view1; view4', 'bounds', bounds));
write_txt(fullfile(cut, 'manifest.json'), jsonencode(cm));
roi_json = fullfile(root, 'roi.json');
rabbit_stack_io.save_roi_json(roi_json, struct('schema_version', 1, ...
    'region_bounds_src', bounds, 'regions', 4, 'rotation', 3, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', 100, 'width', 400), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, ...
    'view_order', {{'view2', 'view3', 'view1', 'view4'}}));
% The recipe of the probe: the study defaults on CPU, about 2 frames
% (stride floor(5/2) = 2: frames 1, 3, 5)
R = rabbit_sfm_build.defaults('rabbit_4view_v1');
R.images.target_frames = 2;
R.features.use_gpu = false;
R.matching.use_gpu = false;
sel_frames = [1 3 5];
all_names = {};
for v = 1:4
    for f = sel_frames
        all_names{end+1} = sprintf('tiny_view%d_frame_%04d.tiff', v, f); %#ok<AGROW>
    end
end
in_view = @(k) all_names(contains(all_names, sprintf('_view%d_', k)));
% Canned models (sphere of radius 1, cameras on a ring of radius 10)
models = fullfile(root, 'models');
% (a) orientation auto: turn 0 registers no image of view 4, turn 180 none
% of view 1 and needs seed 2; the final first pass needs seed 2; the rig
% pass gives the full model plus a two-image model
write_model(fullfile(models, 'auto', 'orient_turn0', 'pass1_seed1', '0'), all_names(~contains(all_names, '_view4_')), W, H, 'good');
write_model(fullfile(models, 'auto', 'orient_turn180', 'pass1_seed1', '0'), all_names(~contains(all_names, '_view1_')), W, H, 'reversed');
write_model(fullfile(models, 'auto', 'orient_turn180', 'pass1_seed2', '0'), all_names(~contains(all_names, '_view1_')), W, H, 'good');
write_model(fullfile(models, 'auto', 'final', 'pass1_seed1', '0'), all_names, W, H, 'reversed');
write_model(fullfile(models, 'auto', 'final', 'pass1_seed2', '0'), all_names, W, H, 'good');
write_model(fullfile(models, 'auto', 'final', 'rig_seed1', '0'), all_names, W, H, 'good');
write_model(fullfile(models, 'auto', 'final', 'rig_seed1', '1'), all_names(1:2), W, H, 'good');
% (b) every mapper run gives a good full model
write_model(fullfile(models, 'good', '0'), all_names, W, H, 'good');
% (c) every mapper run gives a reversed model
write_model(fullfile(models, 'reversed', '0'), all_names, W, H, 'reversed');
% (d) view 4 never registers
write_model(fullfile(models, 'noview4', '0'), all_names(~contains(all_names, '_view4_')), W, H, 'good');
% (e) the rig pass: seed 1 registers fewer images than the first pass, seed 2 all of them
write_model(fullfile(models, 'rigshort', 'final', 'pass1_seed1', '0'), all_names, W, H, 'good');
write_model(fullfile(models, 'rigshort', 'final', 'rig_seed1', '0'), all_names(1:8), W, H, 'good');
write_model(fullfile(models, 'rigshort', 'final', 'rig_seed2', '0'), all_names, W, H, 'good');
% (f) every rig seed registers fewer images than the first pass
write_model(fullfile(models, 'rigworse', 'final', 'pass1_seed1', '0'), all_names, W, H, 'good');
for s = 1:5
    write_model(fullfile(models, 'rigworse', 'final', sprintf('rig_seed%d', s), '0'), all_names(1:8), W, H, 'good');
end
% (g) every rig seed poses all images, but view 4 without a single observation
write_model(fullfile(models, 'rigposed', 'final', 'pass1_seed1', '0'), all_names, W, H, 'good');
for s = 1:5
    write_model(fullfile(models, 'rigposed', 'final', sprintf('rig_seed%d', s), '0'), all_names, W, H, 'posed_view4');
end
% (h) without the rig: one image of view 4 posed with no observation
write_model(fullfile(models, 'posedone', 'final', 'pass1_seed1', '0'), all_names, W, H, 'posed_one');
% (i) turn 0 registers every view, turn 180 neither outer view: both outer
% tiles choose 0, so the orientation build with turn 0 can be the final one
write_model(fullfile(models, 'same0', 'orient_turn0', 'pass1_seed1', '0'), all_names, W, H, 'good');
write_model(fullfile(models, 'same0', 'orient_turn180', 'pass1_seed1', '0'), ...
    all_names(~contains(all_names, '_view1_') & ~contains(all_names, '_view4_')), W, H, 'good');
write_model(fullfile(models, 'same0', 'final', 'rig_seed1', '0'), all_names, W, H, 'good');

tab = rabbit_reconstruction_tab();
rdir = @(id) fullfile(root, 'tiny.matom', 'reconstruction', 'runs', id);
tab.colmap_exe = fake;
tab.colmap_models_dir = '';
tab.load_state(root, 'tiny');

%% R1 recipe
D = rabbit_sfm_build.defaults();
[d_ok, d_err] = rabbit_sfm_build.validate(D);
D2 = rabbit_sfm_build.normalise(jsondecode(rabbit_sfm_build.to_json(D)));
[d2_ok, d2_err] = rabbit_sfm_build.validate(D2);
strides = arrayfun(@(n) rabbit_sfm_build.frame_stride(n, 40), [100 120 240 1200]);
Ri = D; Ri.commands(2).args(2).value = 'ALIKED_LIGHTGLUE&calc';
[i_ok, i_err] = rabbit_sfm_build.validate(Ri);
Rp = D; Rp.camera.principal_point = 'sensor_offset';
[p_ok, p_err] = rabbit_sfm_build.validate(Rp);
Rs = D; Rs.schema = 1;
[s_ok, s_err] = rabbit_sfm_build.validate(Rs);
record('R1 study recipe: valid, JSON round trip, strides 2/3/6/30, refusals', ...
    d_ok && d2_ok && isempty(rabbit_sfm_build.deviations(D2)) && isequal(strides, [2 3 6 30]) && ...
    strcmp(D.camera.model, 'SIMPLE_RADIAL') && D.camera.focal_prior_px == 8000 && ...
    ~logical(D.camera.refine_focal) && strcmp(D.features.type, 'ALIKED_N32') && ...
    strcmp(D.matching.type, 'ALIKED_LIGHTGLUE') && D.matching.min_num_inliers == 60 && ...
    D.mapper.max_focal_length_ratio == 100 && D.mapper.init_min_tri_angle == 2 && ...
    isequal(D.guard.seeds, 1:5) && D.guard.min_near_side_fraction == 0.6 && D.rig.ref_view == 2 && ...
    ~i_ok && contains(i_err, 'shell') && ~p_ok && contains(p_err, 'HasBogusPrincipalPoint') && ...
    ~s_ok && contains(s_err, 'schema 1'), ...
    sprintf('%s %s | strides %s | %s | %s | %s', d_err, d2_err, mat2str(strides), i_err, p_err, s_err));

%% R2 preprocessing
[lo, hi] = rabbit_sfm_build.stretch_limits(1:1000, [1 99.5]);
u8 = rabbit_sfm_build.stretch_u8([5 10 500 995 2000], lo, hi);
img = uint8(20 * ones(60, 80));
[gx, gy] = meshgrid(1:80, 1:60);
img(((gx - 40) / 20) .^ 2 + ((gy - 30) / 15) .^ 2 <= 1) = 220;   % the tissue
img(28:32, 38:42) = 20;                                         % a hole in it
img(5:7, 5:7) = 230;                                            % a speck away from it
[score, feat] = rabbit_sfm_build.tissue_mask(img, 2, 8);
[dx, dy] = meshgrid(-8:8);
Lg = floor(255 * log1p(double(img)) / log(256) + 0.5);
Bg_ref = floor(imgaussfilt(Lg, 2) + 0.5);
r_g = ceil(2 * 2); g = exp(-((-r_g:r_g) .^ 2) / 8); g = g / sum(g);
Bg = floor(conv2(conv2(padarray(Lg, [r_g r_g], 'replicate'), g, 'valid'), g', 'valid') + 0.5);
t = src{4, 3};
[lr4, ud4] = rabbit_sfm_build.view_transform(true, 180);
[lr1, ud1] = rabbit_sfm_build.view_transform(true, 0);
record('R2 stretch limits, tissue mask (largest region, holes filled, 8 px disk), Gaussian, turn = flipud', ...
    lo == 10 && hi == 995 && isequal(u8, uint8([0 0 127 255 255])) && ...
    score(30, 40) && ~score(6, 6) && ~score(1, 1) && ...
    isequal(feat, imdilate(score, dx .^ 2 + dy .^ 2 <= 64)) && nnz(feat) > nnz(score) && ...
    isequal(Bg, Bg_ref) && ~lr4 && ud4 && lr1 && ~ud1 && ...
    isequal(rabbit_sfm_build.apply_transform(fliplr(t), false, false), fliplr(t)) && ...
    isequal(rot90(fliplr(t), 2), rabbit_sfm_build.apply_transform(t, lr4, ud4)), ...
    sprintf('lo %g hi %g, %d score px, %d feature px', lo, hi, nnz(score), nnz(feat)));

%% R3 guard, turn rule, orientation request, silhouette helpers
mg = fullfile(models, 'good', '0');
mr = fullfile(models, 'reversed', '0');
[~, ig, pg] = tab.read_sparse_model(mg);
[~, ir, pr] = tab.read_sparse_model(mr);
Fg = rabbit_sfm_build.near_side_fraction(ig, pg);
Fr = rabbit_sfm_build.near_side_fraction(ir, pr);
[t1, ~] = rabbit_sfm_build.decide_turn([5 100], [0 90]);
[t2, ~] = rabbit_sfm_build.decide_turn([0 100], [5 90]);
[t3, ~] = rabbit_sfm_build.decide_turn([5 80], [5 90]);
[t4, w4] = rabbit_sfm_build.decide_turn([5 90], [5 90]);
Ro = D;
[q0, s0] = rabbit_sfm_build.orientation_request(Ro);
Ro.orientation.camera_upside_down = 'no';
q1 = rabbit_sfm_build.orientation_request(Ro);
Ro.orientation.camera_upside_down = 'yes';
q2 = rabbit_sfm_build.orientation_request(Ro);
Ro.orientation.camera_upside_down = 'auto';
Ro.orientation.outer_turn = {'auto', '180'};
q3 = rabbit_sfm_build.orientation_request(Ro);
pick = rabbit_sfm_build.silhouette_frames_pick(0:2:98, 4);
cam1 = struct('R', eye(3), 't', [0; 0; 5], 'f', [10 10], 'c', [5 5], 'width', 10, 'height', 10, 'mask', false(10));
cam1.mask(1:5, :) = true;     % top half of the image is tissue
cam2 = cam1; cam2.mask(:) = true;
Xs = [0 -0.5 0; 0 0.5 0; 100 0 0];   % top half, bottom half, outside both images
[k90, n_in, n_hit] = rabbit_sfm_build.silhouette_filter(Xs, [cam1 cam2], 0.9);
k50 = rabbit_sfm_build.silhouette_filter(Xs, [cam1 cam2], 0.5);
record('R3 near-side fraction good ~1 / reversed ~0; turn rule; orientation request; silhouette helpers', ...
    Fg > 0.9 && Fr < 0.1 && t1 == 0 && t2 == 180 && t3 == 180 && t4 == 0 && contains(w4, 'tie') && ...
    all(isnan(q0)) && contains(s0{1}, 'auto') && isequal(q1, [0 180]) && isequal(q2, [180 0]) && ...
    isnan(q3(1)) && q3(2) == 180 && isequal(pick, [0 32 64 98]) && ...
    isequal(k90(:)', [true false false]) && isequal(k50(:)', [true true false]) && ...
    isequal(n_in(:)', [2 2 0]) && isequal(n_hit(:)', [2 1 0]), ...
    sprintf('F good %.3f, reversed %.3f; picks %s', Fg, Fr, mat2str(pick)));

%% R3b field band: abstain beyond a field edge, reject beyond a limb
mb = false(10, 100);
mb(:, 21:60) = true;   % left edge 20 px from the border (field edge), right edge 40 px (limb)
Bb = rabbit_sfm_build.field_band(mb, 32);
cb = struct('R', eye(3), 't', [0; 0; 0], 'f', [1 1], 'c', [0 0], 'width', 100, 'height', 10, ...
    'mask', mb, 'band', Bb);
cfull = cb;
cfull.mask(:) = true;  % a second view that sees every point on tissue
cfull.band = [];
cnob = cb;
cnob.band = [];        % the same view without a band
Xb = [10.5 5.5 1; 70.5 5.5 1; 40.5 5.5 1];   % in the band, in the clear bath beyond the limb, on tissue
[kb, nib, nhb] = rabbit_sfm_build.silhouette_filter(Xb, [cb cfull], 0.9);
k0b = rabbit_sfm_build.silhouette_filter(Xb, [cnob cfull], 0.9);
mt = false(100, 10);
mt(21:60, :) = true;   % the same along the columns: top edge 20 px in, bottom edge 40 px from the border
Bt = rabbit_sfm_build.field_band(mt, 32);
Rb = D;
Rb.mesh.field_band_px = -1;
[b_ok, b_err] = rabbit_sfm_build.validate(Rb);
Rold = rmfield(D.mesh, 'field_band_px');
Ro2 = D;
Ro2.mesh = Rold;
o2_ok = rabbit_sfm_build.validate(Ro2);
record('R3b field band: a point beyond a field edge abstains, beyond a limb 40 px in it is rejected', ...
    isequal(find(Bb(1, :)), 1:20) && all(all(Bb(:, 1:20))) && ~any(any(Bb(:, 21:end))) && ...
    isequal(kb(:)', [true false true]) && isequal(nib(:)', [1 2 2]) && isequal(nhb(:)', [1 1 2]) && ...
    isequal(k0b(:)', [false false true]) && ...
    isequal(find(Bt(:, 1))', 1:20) && ~any(any(Bt(21:end, :))) && ...
    D.mesh.field_band_px == 32 && isequal(rabbit_sfm_build.field_band(mb, 0), false(size(mb))) && ...
    ~b_ok && contains(b_err, 'field_band_px') && o2_ok, ...
    sprintf('keep %s (no band %s), n_in %s; %s', mat2str(kb(:)'), mat2str(k0b(:)'), mat2str(nib(:)'), b_err));

%% R3c one open edge: recipe default, validation, an old recipe, the recipe text
Rs = D;
Rs.mesh.single_open_edge = 2;
[s_ok, s_err] = rabbit_sfm_build.validate(Rs);
Rs.mesh.single_open_edge = 0;
s0_ok = rabbit_sfm_build.validate(Rs);
Rs.mesh = rmfield(D.mesh, 'single_open_edge');
so_ok = rabbit_sfm_build.validate(Rs);
txt_on = strjoin(rabbit_sfm_build.describe(D), newline);
txt_old = strjoin(rabbit_sfm_build.describe(Rs), newline);
record('R3c one open edge: default on, 2 refused, 0 and an old recipe without the field accepted, recipe text', ...
    isequal(D.mesh.single_open_edge, true) && ~s_ok && contains(s_err, 'single_open_edge') && s0_ok && so_ok && ...
    contains(txt_on, 'One open edge: on') && contains(txt_old, 'One open edge: off'), s_err);

%% S1 built run: pipeline, recipe snapshot, steps
rid = 'run_s1_built';
[c_ok, c_err, run_dir] = tab.create_run(rid, struct('image_list', cut, 'roi_json', roi_json, ...
    'sparse_source', 'built', 'sfm_recipe', R));
tab.record_run(rid, 'CREATED');
m = tab.read_manifest(run_dir);
rec_file = fullfile(run_dir, 'inputs', 'sfm_recipe.json');
[~, attr] = fileattrib(rec_file);
order = tab.stage_order_for_run(rid);
proj = tab.reconstruction_stage_projection(rid);
labels = arrayfun(@(s) tab.stage_label(s.name), proj.stages, 'UniformOutput', false);
rid_a = 'run_s1_apd';
[a_ok, a_err] = tab.create_run(rid_a, struct('image_list', cut, 'roi_json', roi_json, ...
    'sparse_source', 'built', 'sfm_recipe', R, 'cloud_source', 'apd'));
tab.record_run(rid_a, 'CREATED');
rid_l = 'run_s1_supplied';
cut_names = {};
for v = 1:4
    for f = 1:n_frames
        cut_names{end+1} = sprintf('tiny_view%d_frame_%04d.tiff', v, f); %#ok<AGROW>
    end
end
write_model(fullfile(root, 'supplied_model'), cut_names, W, H, 'good', 'PINHOLE');
[l_ok, l_err] = tab.create_run(rid_l, struct('sparse_model_dir', fullfile(root, 'supplied_model'), ...
    'image_list', cut, 'roi_json', roi_json));
tab.record_run(rid_l, 'CREATED');
m_l = tab.read_manifest(rdir(rid_l));
proj_l = tab.reconstruction_stage_projection(rid_l);
record('S1 built run: pipeline (fused, 8 steps, no APDe-MVS), read-only recipe; APDe-MVS cloud 10 steps; supplied 8', ...
    c_ok && a_ok && l_ok && isfield(m, 'pipeline') && strcmp(m.pipeline.sparse_source, 'built') && ...
    strcmp(m.pipeline.cloud_source, 'fused') && numel(m.pipeline.stage_order) == 8 && ...
    ~any(contains(m.pipeline.stage_order, 'apde')) && ...
    strcmp(m.pipeline.sfm_recipe.sha256, sha(rec_file)) && ~attr.UserWrite && ...
    numel(order) == 8 && numel(proj.stages) == 8 && numel(tab.stage_order_for_run(rid_a)) == 10 && ...
    strcmp(labels{1}, 'Prepare images for the sparse model') && ...
    strcmp(labels{2}, 'Sparse model (COLMAP structure from motion)') && ...
    strcmp(proj.first_resumable_stage, 'sparse_prep') && ...
    ~isfield(m_l, 'pipeline') && numel(proj_l.stages) == 8 && ...
    strcmp(proj_l.first_resumable_stage, 'image_undistorter'), ...
    sprintf('%s %s %s | order %d, apd %d, legacy %d', c_err, a_err, l_err, numel(order), ...
    numel(tab.stage_order_for_run(rid_a)), numel(proj_l.stages)));
[b_ok, b_err] = tab.create_run('run_s1_both', struct('sparse_model_dir', fullfile(root, 'supplied_model'), ...
    'image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', R));
record('S1b a built run refuses a supplied sparse model folder too', ~b_ok && contains(b_err, 'must not'), b_err);

%% S2 sparse_prep
[p_ok, p_err] = tab.run_stage(rid, 'sparse_prep');
m = tab.read_manifest(run_dir);
st = stage_entry(m, 'sparse_prep');
prep = fullfile(run_dir, 'stages', 'sparse_prep');
Rr = tab.run_sfm_recipe(run_dir);
P = jsondecode(fileread(fullfile(prep, 'prep.json')));
lim = P.stretch_limits;
exp1 = rabbit_sfm_build.equalise(fliplr(rabbit_sfm_build.stretch_u8(src{1, 3}, lim(1, 1), lim(1, 2))), R.preprocess.clahe);
exp4 = rabbit_sfm_build.equalise(flipud(rabbit_sfm_build.stretch_u8(src{4, 5}, lim(4, 1), lim(4, 2))), R.preprocess.clahe);
exp2 = rabbit_sfm_build.equalise(rabbit_sfm_build.stretch_u8(src{2, 3}, lim(2, 1), lim(2, 2)), R.preprocess.clahe);
f1 = imread(fullfile(prep, 'turn0', 'images', 'tiny_view1_frame_0003.tiff'));
f4 = imread(fullfile(prep, 'turn180', 'images', 'tiny_view4_frame_0005.tiff'));
f2 = imread(fullfile(prep, 'turn0', 'images', 'tiny_view2_frame_0003.tiff'));
[sc1, ft1] = rabbit_sfm_build.tissue_mask(rabbit_sfm_build.stretch_u8(src{1, 3}, lim(1, 1), lim(1, 2)), 2, 8);
mk1 = imread(fullfile(prep, 'turn0', 'masks', 'tiny_view1_frame_0003.tiff.png')) > 0;
sm1 = imread(fullfile(prep, 'turn0', 'score_masks', 'tiny_view1_frame_0003.tiff.png')) > 0;
inner180 = rabbit_sfm_build.list_images(fullfile(prep, 'turn180', 'images'));
arts = st.artifacts;
hex_ok = all(cellfun(@(h) ~isempty(regexp(h, '^[0-9a-f]{64}$', 'once')), {arts.sha256})) && ...
    all(startsWith({arts.path}, 'stages/sparse_prep/'));
rig = jsondecode(fileread(fullfile(prep, 'rig_config.json')));
rc = rig(1).cameras;
if ~iscell(rc), rc = num2cell(rc); end   % the reference entry has one more field
rc_prefix = cellfun(@(c) c.image_prefix, rc, 'UniformOutput', false);
list1 = strsplit(strtrim(fileread(fullfile(prep, 'lists', 'view1.txt'))), newline);
% determinism: a second run prepares the same files
rid2 = 'run_s2_again';
tab.create_run(rid2, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', R));
tab.record_run(rid2, 'CREATED');
tab.run_stage(rid2, 'sparse_prep');
st2 = stage_entry(tab.read_manifest(rdir(rid2)), 'sparse_prep');
same = isequal(sort(strcat({arts.path}, {arts.sha256})), sort(strcat({st2.artifacts.path}, {st2.artifacts.sha256})));
c2 = [p_ok, any(strcmp(st.status, {'PASSED', 'WARNED'})), isequal(Rr.resolved.frames, sel_frames), ...
    isequal(Rr.resolved.outer_rows, [1 4]), isequal(f1, exp1), isequal(f4, exp4), isequal(f2, exp2), ...
    isequal(mk1, fliplr(ft1)), isequal(sm1, fliplr(sc1)), ...
    numel(inner180) == 6 && all(contains(inner180, {'_view1_', '_view4_'})), ...
    hex_ok, numel(rc) == 4 && strcmp(rc_prefix{1}, 'tiny_view2_') && isfield(rc{1}, 'ref_sensor'), ...
    isequal(list1, in_view(1)), same, isequal(size(lim), [4 2])];
record('S2 sparse_prep: frames 1,3,5; stretch, flips, turn, CLAHE and masks exact; outer tiles turned too; rig reference first; deterministic', ...
    all(c2), sprintf('%s status %s, %d artifacts, conditions %s', p_err, st.status, numel(arts), mat2str(c2)));
Rq = Rr; Rq.rig.ref_view = 3;
rq = jsondecode(rabbit_sfm_build.rig_config_text(Rq));
rqc = rq(1).cameras;
if ~iscell(rqc), rqc = num2cell(rqc); end
record('S2b rig file lists the reference view first (ref_view 3 -> rows 3, 1, 2, 4)', ...
    isequal(reshape(cellfun(@(c) c.image_prefix, rqc, 'UniformOutput', false), 1, []), ...
    {'tiny_view3_', 'tiny_view1_', 'tiny_view2_', 'tiny_view4_'}) && isfield(rqc{1}, 'ref_sensor'), '');
Rq2 = Rr;   % ROI rows view2;view3;view1;view4 on the tiles 2, 3, 1, 4 from the left
cols_q = [20 30 10 40];
for vq = 1:4, Rq2.resolved.views(vq).bounds(2) = cols_q(vq); end
Rq2.rig.ref_view = 2;
record('S2c ref_view counts tiles from the left: tile 2 is ROI row 1 when the rows are not in column order', ...
    rabbit_sfm_build.ref_roi_row(Rq2) == 1, sprintf('row %d', rabbit_sfm_build.ref_roi_row(Rq2)));

%% S3 command lines per phase (golden), model files, tool check
paths = struct('db', 'C:\r\db.db', 'images', 'C:\r\img', 'masks', 'C:\r\msk', 'rig', 'C:\r\rig.json', ...
    'lists', 'C:\r\lists', 'sparse_out', 'C:\r\out', 'input_model', 'C:\r\p1\0', ...
    'rig_out', 'C:\r\rigcfg', 'models', '');
[cf, tf] = rabbit_sfm_build.commands(Rr, 'features', paths, 'C:\colmap\colmap.exe', []);
[cm3, ~] = rabbit_sfm_build.commands(Rr, 'mapper', paths, 'C:\colmap\colmap.exe', 3);
[cr, ~] = rabbit_sfm_build.commands(Rr, 'rig', paths, 'C:\colmap\colmap.exe', []);
gold1 = ['"C:\colmap\colmap.exe" feature_extractor --database_path "C:\r\db.db" --image_path "C:\r\img" ' ...
    '--image_list_path "C:\r\lists\view1.txt" --ImageReader.mask_path "C:\r\msk" --ImageReader.single_camera 1 ' ...
    '--ImageReader.camera_model SIMPLE_RADIAL --ImageReader.camera_params 8000,32,24,0 ' ...
    '--FeatureExtraction.type ALIKED_N32 --FeatureExtraction.use_gpu 0 --FeatureExtraction.num_threads 6 ' ...
    '--AlikedExtraction.max_num_features 4096 --AlikedExtraction.min_score 0.05 ' ...
    '--log_target stderr --log_color 0 --default_random_seed 0'];
gold5 = ['"C:\colmap\colmap.exe" exhaustive_matcher --database_path "C:\r\db.db" --FeatureMatching.type ALIKED_LIGHTGLUE ' ...
    '--FeatureMatching.use_gpu 0 --FeatureMatching.num_threads 6 --FeatureMatching.guided_matching 0 ' ...
    '--TwoViewGeometry.min_num_inliers 60 --TwoViewGeometry.max_error 4 --TwoViewGeometry.filter_stationary_matches 1 ' ...
    '--TwoViewGeometry.detect_watermark 0 --AlikedMatching.lightglue_min_score 0.1 ' ...
    '--log_target stderr --log_color 0 --default_random_seed 0'];
goldr = ['"C:\colmap\colmap.exe" rig_configurator --database_path "C:\r\db.db" --rig_config_path "C:\r\rig.json" ' ...
    '--input_path "C:\r\p1\0" --output_path "C:\r\rigcfg" --log_target stderr --log_color 0 --default_random_seed 0'];
mp_need = {'--Mapper.random_seed 3', '--Mapper.ba_refine_focal_length 0', '--Mapper.ba_refine_principal_point 0', ...
    '--Mapper.ba_refine_extra_params 0', '--Mapper.max_focal_length_ratio 100', '--Mapper.init_min_tri_angle 2', ...
    '--Mapper.init_min_num_inliers 30', '--Mapper.abs_pose_min_num_inliers 15', '--Mapper.abs_pose_max_error 12', ...
    '--Mapper.filter_max_reproj_error 4', '--Mapper.tri_min_angle 1.5', '--Mapper.filter_min_tri_angle 1.5', ...
    '--Mapper.min_num_matches 15', '--Mapper.init_max_error 4', '--Mapper.num_threads 6', '--output_path "C:\r\out"'};
models_dir = fullfile(root, 'onnx');
mkdir(models_dir);
write_txt(fullfile(models_dir, 'aliked-n32.onnx'), 'not a real model');
pm = paths; pm.models = models_dir;
cf_local = rabbit_sfm_build.commands(Rr, 'features', pm, 'C:\colmap\colmap.exe', []);
record('S3 golden lines: features (4 views + matcher), mapper with the seed, rig; local model only when present', ...
    numel(cf) == 5 && strcmp(cf{1}, gold1) && strcmp(cf{5}, gold5) && isequal(tf, [1800 1800 1800 1800 3600]) && ...
    numel(cm3) == 1 && all(cellfun(@(s) contains(cm3{1}, s), mp_need)) && numel(cr) == 1 && strcmp(cr{1}, goldr) && ...
    ~contains(cf{1}, 'model_path') && contains(cf_local{1}, ['--AlikedExtraction.n32_model_path "' fullfile(models_dir, 'aliked-n32.onnx') '"']) && ...
    ~contains(cf_local{5}, 'lightglue_model_path'), cf{1});
Ru = R; Ru.commands(2).args(end+1) = struct('key', '--FeatureMatching.made_up_option', 'value', '1', 'when', '');
[u_ok, u_res] = tab.preflight('sparse_build', struct('sfm_recipe', Ru));
[g_ok, g_res] = tab.preflight('sparse_build', struct('sfm_recipe', R));
Rh = R; Rh.matching.model_files(1).sha256 = repmat('0', 1, 64);
[h_ok, h_res] = tab.preflight('sparse_build', struct('sfm_recipe', Rh));
tab.colmap_models_dir = models_dir;
[w_ok, w_res] = tab.preflight('sparse_build', struct('sfm_recipe', R));
tab.colmap_models_dir = '';
record('S3b tool check: unknown option fails; COLMAP default model sha256 accepted, a different one refused; a local file with the wrong hash refused', ...
    ~u_ok && contains(u_res(end).message, 'made_up_option') && g_ok && ~h_ok && ...
    contains(h_res(end).message, 'COLMAP''s own default') && ~w_ok && contains(w_res(end).message, 'not the'), ...
    sprintf('%s | %s | %s | %s', u_res(end).message, g_res(end).message, h_res(end).message, w_res(end).message));

%% S4 build with orientation auto: orientation builds, guard, rig
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'auto'));
setenv('OM_FAKE_COLMAP_LOG', fullfile(root, 'fake_calls.log'));
[b4_ok, b4_err] = tab.run_stage(rid, 'sparse_build');
m = tab.read_manifest(run_dir);
st = stage_entry(m, 'sparse_build');
sb = fullfile(run_dir, 'stages', 'sparse_build');
S = jsondecode(fileread(fullfile(sb, 'model_summary.json')));
kept = rabbit_sfm_build.list_images(fullfile(sb, 'images'));
kept_masks = dir(fullfile(sb, 'score_masks', '*.png'));
T = jsondecode(fileread(fullfile(sb, 'om_tile_transform.json')));
calls = strsplit(strtrim(fileread(fullfile(root, 'fake_calls.log'))), newline);
br = st.settings_resolved.build_result;
O = br.summary.orientation;
tr = br.summary.final.trials;
if iscell(tr), tr = [tr{:}]; end
flips = tab.run_view_flips(run_dir);
final_img = imread(fullfile(sb, 'images', 'tiny_view4_frame_0003.tiff'));
prep4 = imread(fullfile(prep, 'turn180', 'images', 'tiny_view4_frame_0003.tiff'));
record('S4 orientation builds pick turn 0 (left) and 180 (right); guard keeps seed 2; rig pass; registered images and score masks kept', ...
    b4_ok && isequal(reshape(O.turns, 1, []), [0 180]) && numel(calls) == 22 && ...
    sum(startsWith(calls, 'mapper')) == 6 && sum(startsWith(calls, 'rig_configurator')) == 1 && ...
    sum(startsWith(calls, 'feature_extractor')) == 12 && ...
    isequal([tr.seed], [1 2 1]) && isequal([tr.accepted], [false true true]) && ...
    tr(1).near_side_fraction < 0.1 && tr(2).near_side_fraction > 0.9 && ...
    S.seed == 1 && S.n_registered == 12 && numel(kept) == 12 && numel(kept_masks) == 12 && ...
    isequal(final_img, prep4) && isequal({T.views.flip_lr}, {true, false, false, false}) && ...
    isequal({T.views.flip_ud}, {false, false, false, true}) && isequal(flips, {'lr', 'none', 'none', 'ud'}) && ...
    iscell(br.commands_run) && numel(br.commands_run) == 22 && ...
    all(cellfun(@(h) ~isempty(regexp(h, '^[0-9a-f]{64}$', 'once')), {st.artifacts.sha256})), ...
    sprintf('%s | turns %s, %d calls, seeds %s', b4_err, mat2str(O.turns), numel(calls), mat2str([tr.seed])));
record('S4b two models in the kept mapper output WARN', ...
    strcmp(st.status, 'WARNED') && any(contains(st.warnings, 'separate models')) && S.n_models == 2, ...
    strjoin(st.warnings, ' | '));

%% K1 known turns from the run of S4: one build
rk1 = 'run_k1_known';
tab.create_run(rk1, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', R));
tab.record_run(rk1, 'CREATED');
tab.run_stage(rk1, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'auto'));
setenv('OM_FAKE_COLMAP_LOG', fullfile(root, 'fake_calls_k1.log'));
[k1_ok, k1_err] = tab.run_stage(rk1, 'sparse_build');
callsk1 = strsplit(strtrim(fileread(fullfile(root, 'fake_calls_k1.log'))), newline);
Ok1 = jsondecode(fileread(fullfile(rdir(rk1), 'stages', 'sparse_build', 'model_summary.json'))).orientation;
wk1 = fullfile(rdir(rk1), 'stages', 'sparse_build', 'work');
record('K1 known turns of an earlier run: one build (4 feature extractions), turns 0/180, source recorded', ...
    k1_ok && isequal(reshape(Ok1.turns, 1, []), [0 180]) && sum(startsWith(callsk1, 'feature_extractor')) == 4 && ...
    ~isfolder(fullfile(wk1, 'orient_turn0')) && ~isfolder(fullfile(wk1, 'orient_turn180')) && ...
    isstruct(Ok1.known) && logical(Ok1.known.held) && strcmp(Ok1.known.source, rid) && ...
    all(contains(Ok1.reasons, 'known from run')), ...
    sprintf('%s | %d calls | %s', k1_err, numel(callsk1), jsonencode(Ok1.known)));
Rn = R; Rn.orientation.reuse_turns = 'no';
rk1b = 'run_k1b_noreuse';
tab.create_run(rk1b, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rn));
tab.record_run(rk1b, 'CREATED');
tab.run_stage(rk1b, 'sparse_prep');
setenv('OM_FAKE_COLMAP_LOG', fullfile(root, 'fake_calls_k1b.log'));
[k1b_ok, ~] = tab.run_stage(rk1b, 'sparse_build');
callsk1b = strsplit(strtrim(fileread(fullfile(root, 'fake_calls_k1b.log'))), newline);
Rold = rmfield(R, 'orientation'); Rold.orientation = rmfield(R.orientation, 'reuse_turns');
[old_ok, old_err] = rabbit_sfm_build.validate(Rold);
Rbad = R; Rbad.orientation.reuse_turns = 'maybe';
[bad_ok, bad_err] = rabbit_sfm_build.validate(Rbad);
record('K1b reuse_turns no: the three builds as before; an old recipe without it is valid and does not reuse; maybe refused', ...
    k1b_ok && sum(startsWith(callsk1b, 'feature_extractor')) == 12 && old_ok && ...
    ~rabbit_sfm_build.reuses_turns(Rold) && ~bad_ok && contains(bad_err, 'reuse_turns'), ...
    sprintf('%d calls | %s | %s', numel(callsk1b), old_err, bad_err));

% A run of other boxes, another tile size, flip or recording is not the same
% cut (turn_key); the ROI file's other fields do not count
Rk = tab.run_sfm_recipe(rdir(rid));
Rb = Rk; Rb.resolved.views(1).bounds(1) = Rb.resolved.views(1).bounds(1) + 1;
Rs = Rk; Rs.resolved.stem = 'another_recording';
Rl = Rk; Rl.resolved.views(4).base_flip_lr = ~Rl.resolved.views(4).base_flip_lr;
kk = rabbit_sfm_build.turn_key(Rk);
record('K1c turn_key: the same cut gives the same key; other boxes, recording or flip another', ...
    strcmp(kk, rabbit_sfm_build.turn_key(tab.run_sfm_recipe(rdir(rk1)))) && ...
    ~strcmp(kk, rabbit_sfm_build.turn_key(Rb)) && ~strcmp(kk, rabbit_sfm_build.turn_key(Rs)) && ...
    ~strcmp(kk, rabbit_sfm_build.turn_key(Rl)), kk);

%% K2 known turns that do not hold: kept aside, orientation builds
rk2 = 'run_k2_fallback';
tab.create_run(rk2, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', R));
tab.record_run(rk2, 'CREATED');
tab.run_stage(rk2, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'noview4'));
setenv('OM_FAKE_COLMAP_LOG', fullfile(root, 'fake_calls_k2.log'));
[~, k2_err] = tab.run_stage(rk2, 'sparse_build');
callsk2 = strsplit(strtrim(fileread(fullfile(root, 'fake_calls_k2.log'))), newline);
wk2 = fullfile(rdir(rk2), 'stages', 'sparse_build', 'work');
bk2 = stage_entry(tab.read_manifest(rdir(rk2)), 'sparse_build').settings_resolved.build_result.summary.orientation;
% 22 calls: the known build (8), both orientation builds (12), then the rig
% pass on the reused turn-0 build (2: view 4 never registers, so both
% outer tiles tie at turn 0)
record('K2 known turns with an unregistered outer tile: kept as final_known_turns, orientation builds run', ...
    isfolder(fullfile(wk2, 'final_known_turns')) && isfolder(fullfile(wk2, 'orient_turn180')) && ...
    sum(startsWith(callsk2, 'feature_extractor')) == 12 && numel(callsk2) == 22 && ...
    isstruct(bk2.known) && ~logical(bk2.known.held) && contains(bk2.known.why_not, 'ROI row 4'), ...
    sprintf('%s | %d calls', k2_err, numel(callsk2)));

%% K3 both outer tiles turned 0: the orientation build becomes the final one
rk3 = 'run_k3_reuse_build';
tab.create_run(rk3, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rn));
tab.record_run(rk3, 'CREATED');
tab.run_stage(rk3, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'same0'));
setenv('OM_FAKE_COLMAP_LOG', fullfile(root, 'fake_calls_k3.log'));
[k3_ok, k3_err] = tab.run_stage(rk3, 'sparse_build');
callsk3 = strsplit(strtrim(fileread(fullfile(root, 'fake_calls_k3.log'))), newline);
wk3 = fullfile(rdir(rk3), 'stages', 'sparse_build', 'work');
Sk3 = jsondecode(fileread(fullfile(rdir(rk3), 'stages', 'sparse_build', 'model_summary.json')));
record('K3 same turn for both outer tiles: orientation build reused as final (8 feature extractions), rig pass on it', ...
    k3_ok && isequal(reshape(Sk3.orientation.turns, 1, []), [0 0]) && strcmp(Sk3.orientation.reused_build, 'orient_turn0') && ...
    sum(startsWith(callsk3, 'feature_extractor')) == 8 && sum(startsWith(callsk3, 'rig_configurator')) == 1 && ...
    ~isfolder(fullfile(wk3, 'orient_turn0')) && isfolder(fullfile(wk3, 'final', 'pass1_seed1')) && ...
    logical(Sk3.final.rig_used), sprintf('%s | %d calls', k3_err, numel(callsk3)));
setenv('OM_FAKE_COLMAP_LOG', '');

%% S5 guard fails on every seed; a view with no image fails
Rf = R; Rf.orientation.camera_upside_down = 'no';   % fixed turns: no orientation builds
rid5 = 'run_s5_reversed';
tab.create_run(rid5, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rf));
tab.record_run(rid5, 'CREATED');
tab.run_stage(rid5, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'reversed'));
setenv('OM_FAKE_COLMAP_LOG', fullfile(root, 'fake_calls5.log'));
[f5_ok, f5_err] = tab.run_stage(rid5, 'sparse_build');
st5 = stage_entry(tab.read_manifest(rdir(rid5)), 'sparse_build');
calls5 = strsplit(strtrim(fileread(fullfile(root, 'fake_calls5.log'))), newline);
record('S5 every seed depth-reversed: FAILED, all five seeds tried and listed, no orientation builds', ...
    ~f5_ok && strcmp(st5.status, 'FAILED') && contains(f5_err, 'None of the seeds') && ...
    contains(f5_err, 'seed 5') && numel(calls5) == 10 && ...
    isfield(st5.settings_resolved, 'build_result'), f5_err);
rid5b = 'run_s5_noview4';
tab.create_run(rid5b, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rf));
tab.record_run(rid5b, 'CREATED');
tab.run_stage(rid5b, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'noview4'));
setenv('OM_FAKE_COLMAP_LOG', '');
[f5b_ok, f5b_err] = tab.run_stage(rid5b, 'sparse_build');
st5b = stage_entry(tab.read_manifest(rdir(rid5b)), 'sparse_build');
record('S5b a view with no registered image FAILS the build', ...
    ~f5b_ok && strcmp(st5b.status, 'FAILED') && contains(f5b_err, 'every_view_registered'), f5b_err);

%% S5c/S5d the rig pass keeps a seed only with as many images as the first pass
% on the July recording one rig run gave 200 images in one
% model and another, same seed, 7 models with 68 in the largest
rid5c = 'run_s5c_rigshort';
tab.create_run(rid5c, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rf));
tab.record_run(rid5c, 'CREATED');
tab.run_stage(rid5c, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'rigshort'));
setenv('OM_FAKE_COLMAP_LOG', '');
[c5_ok, c5_err] = tab.run_stage(rid5c, 'sparse_build');
S5c = jsondecode(fileread(fullfile(rdir(rid5c), 'stages', 'sparse_build', 'model_summary.json')));
t5c = S5c.final.trials; if iscell(t5c), t5c = [t5c{:}]; end
record('S5c a rig seed with fewer images than the first pass is not kept; the next seed is', ...
    c5_ok && isequal({t5c.pass}, {'pass1', 'rig', 'rig'}) && isequal([t5c.seed], [1 1 2]) && ...
    isequal([t5c.accepted], [true false true]) && isequal([t5c.n_images], [12 8 12]) && ...
    S5c.final.rig_used && S5c.n_registered == 12, ...
    sprintf('%s | seeds %s, images %s', c5_err, mat2str([t5c.seed]), mat2str([t5c.n_images])));
rid5d = 'run_s5d_rigworse';
tab.create_run(rid5d, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rf));
tab.record_run(rid5d, 'CREATED');
tab.run_stage(rid5d, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'rigworse'));
[d5_ok, d5_err] = tab.run_stage(rid5d, 'sparse_build');
S5d = jsondecode(fileread(fullfile(rdir(rid5d), 'stages', 'sparse_build', 'model_summary.json')));
st5d = stage_entry(tab.read_manifest(rdir(rid5d)), 'sparse_build');
t5d = S5d.final.trials; if iscell(t5d), t5d = [t5d{:}]; end
record('S5d no rig seed reaches the first pass''s images: the model without the rig is kept, the step WARNS', ...
    d5_ok && numel(t5d) == 6 && ~any([t5d(2:end).accepted]) && ~S5d.final.rig_used && ...
    S5d.n_registered == 12 && strcmp(st5d.status, 'WARNED') && any(contains(st5d.warnings, 'model without the rig')), ...
    sprintf('%s | %s', d5_err, strjoin(st5d.warnings, ' | ')));

% a rig pass on the July recording posed all 50 images of view
% 4 with 1 observation between them (behind the heart); such images are
% not registered, so that rig model has fewer images than the first pass
rid5e = 'run_s5e_rigposed';
tab.create_run(rid5e, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rf));
tab.record_run(rid5e, 'CREATED');
tab.run_stage(rid5e, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'rigposed'));
[e5_ok, e5_err] = tab.run_stage(rid5e, 'sparse_build');
S5e = jsondecode(fileread(fullfile(rdir(rid5e), 'stages', 'sparse_build', 'model_summary.json')));
t5e = S5e.final.trials; if iscell(t5e), t5e = [t5e{:}]; end
mpos = rabbit_sfm_build.largest_model(fullfile(models, 'rigposed', 'final', 'rig_seed1'), @(d) tab.read_sparse_model(d), 15);
record('S5e images posed without sparse points are not registered: the rig model with view 4 posed only is not kept', ...
    e5_ok && all([t5e(2:end).n_images] == 9) && ~any([t5e(2:end).accepted]) && ~S5e.final.rig_used && ...
    S5e.n_registered == 12 && S5e.n_posed_only == 0 && isequal(reshape(S5e.registered_per_view, 1, []), [3 3 3 3]) && ...
    mpos.n_images == 9 && mpos.n_posed_only == 3 && isequal(mpos.per_view, [3 3 3 0]), ...
    sprintf('%s | rig images %s; direct count %d + %d posed only, per view %s', e5_err, mat2str([t5e(2:end).n_images]), ...
    mpos.n_images, mpos.n_posed_only, mat2str(mpos.per_view)));

%% S5f an image posed without sparse points leaves the kept model (COLMAP image_deleter)
rid5f = 'run_s5f_posedone';
Rnr = Rf; Rnr.rig.use = false;
tab.create_run(rid5f, struct('image_list', cut, 'roi_json', roi_json, 'sparse_source', 'built', 'sfm_recipe', Rnr));
tab.record_run(rid5f, 'CREATED');
tab.run_stage(rid5f, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'posedone'));
setenv('OM_FAKE_COLMAP_LOG', fullfile(root, 'fake_calls5f.log'));
[f5_ok, f5_err] = tab.run_stage(rid5f, 'sparse_build');
setenv('OM_FAKE_COLMAP_LOG', '');
sb5f = fullfile(rdir(rid5f), 'stages', 'sparse_build');
S5f = jsondecode(fileread(fullfile(sb5f, 'model_summary.json')));
[~, im5f] = tab.read_sparse_model(fullfile(sb5f, 'model'));
n5f = cellfun(@(k) im5f(k).name, keys(im5f), 'UniformOutput', false);
calls5f = strsplit(strtrim(fileread(fullfile(root, 'fake_calls5f.log'))), newline);
st5f = stage_entry(tab.read_manifest(rdir(rid5f)), 'sparse_build');
record('S5f the image posed without sparse points is removed from the kept model, its file and mask too; the step warns', ...
    f5_ok && im5f.Count == 11 && ~any(strcmp(n5f, 'tiny_view4_frame_0003.tiff')) && ...
    any(startsWith(calls5f, 'image_deleter')) && isequal(cellstr(S5f.posed_only_removed), {'tiny_view4_frame_0003.tiff'}) && ...
    exist(fullfile(sb5f, 'images', 'tiny_view4_frame_0003.tiff'), 'file') == 0 && ...
    exist(fullfile(sb5f, 'score_masks', 'tiny_view4_frame_0003.tiff.png'), 'file') == 0 && ...
    exist(fullfile(sb5f, 'model', 'om_tile_transform.json'), 'file') == 2 && ...
    any(contains(st5f.warnings, 'removed from the model')), ...
    sprintf('%s | %d images kept; deleter called %d; %s', f5_err, im5f.Count, any(startsWith(calls5f, 'image_deleter')), ...
    strjoin(cellstr(st5f.warnings), ' / ')));

%% S6 the dense steps use the built model and its registered images
[cmd_u, ~] = tab.build_stage_command('image_undistorter', run_dir, struct());
[v_ok, v_err] = tab.validate_sparse_model(fullfile(sb, 'model'), fullfile(sb, 'images'), struct('allow_distortion', true));
[v2_ok, v2_err] = tab.validate_sparse_model(fullfile(sb, 'model'), fullfile(sb, 'images'));
[cmd_a, meta_a] = tab.build_stage_command('apde_scene_prep', rdir(rid_a), struct()); %#ok<ASGLU>
record('S6 image_undistorter reads the built model; SIMPLE_RADIAL only with allow_distortion; APDe reads the undistorted model', ...
    contains(cmd_u, fullfile('stages', 'sparse_build', 'model')) && ...
    contains(cmd_u, fullfile('stages', 'sparse_build', 'images')) && v_ok && ~v2_ok && ...
    contains(v2_err, 'SIMPLE_RADIAL') && ...
    strcmp(meta_a.settings_resolved.sparse_dir, fullfile(rdir(rid_a), 'stages', 'image_undistorter', 'dense', 'sparse')), ...
    sprintf('%s | %s', v_err, v2_err));

%% S12 mesh step settings of a built run; APDe cloud refused without APDe steps
[~, meta_m] = tab.build_stage_command('mesh_cleanup', run_dir, struct());
[~, meta_al] = tab.build_stage_command('alignment', run_dir, struct());
[~, meta_al0] = tab.build_stage_command('alignment', run_dir, struct('field_band_px', 0));
[~, meta_m0] = tab.build_stage_command('mesh_cleanup', run_dir, struct('single_open_edge', 0));
[~, meta_mc] = tab.build_stage_command('mesh_cleanup', run_dir, struct('silhouette_cap', 1));
% A recipe written before the setting keeps the cap its check decides
rec_c = fullfile(run_dir, 'inputs', 'sfm_recipe.json');
rec_c_txt = fileread(rec_c);
rec_c_old = jsondecode(rec_c_txt);
rec_c_old.mesh = rmfield(rec_c_old.mesh, 'silhouette_cap');
fileattrib(rec_c, '+w');
write_txt(rec_c, jsonencode(rec_c_old));
[~, meta_mo] = tab.build_stage_command('mesh_cleanup', run_dir, struct());
write_txt(rec_c, rec_c_txt);
[x_ok, x_err] = tab.run_stage(rid, 'mesh_cleanup', struct('cloud_source', 'apd'));
record(['S12 mesh step of a built run: its score masks, filter 0.9, 4 silhouette frames, field band 32, ' ...
    'one open edge, no silhouette cap (opts override; an older recipe keeps the cap); ' ...
    'alignment: same masks and band (opts override); APDe cloud refused'], ...
    strcmp(meta_al.settings_resolved.mask_root, fullfile(sb, 'score_masks')) && ...
    meta_al.settings_resolved.field_band_px == 32 && meta_al0.settings_resolved.field_band_px == 0 && ...
    strcmp(meta_m.settings_resolved.mask_root, fullfile(sb, 'score_masks')) && ...
    meta_m.settings_resolved.silhouette_filter_min_inside == 0.9 && ...
    meta_m.settings_resolved.silhouette_frames == 4 && meta_m.settings_resolved.field_band_px == 32 && ...
    meta_m.settings_resolved.single_open_edge == 1 && meta_m0.settings_resolved.single_open_edge == 0 && ...
    meta_m.settings_resolved.silhouette_cap == 0 && meta_mc.settings_resolved.silhouette_cap == 1 && ...
    meta_mo.settings_resolved.silhouette_cap == 1 && ...
    ~x_ok && contains(x_err, 'no APDe-MVS steps'), x_err);

%% S7 a changed model is refused
cam_file = fullfile(sb, 'model', 'cameras.txt');
txt = fileread(cam_file);
write_txt(cam_file, strrep(txt, 'SIMPLE_RADIAL 64 48 8000', 'SIMPLE_RADIAL 64 48 8001'));
[t_ok, t_err] = tab.run_stage(rid, 'image_undistorter');
record('S7 a model changed after the build is refused', ...
    ~t_ok && contains(t_err, 'changed after it was built'), t_err);

%% S7b a deleted image, a changed score mask or a changed recipe is refused before the later steps
write_txt(cam_file, txt);
[t0_ok, t0_err] = tab.verify_built_inputs(run_dir);
img_k = fullfile(sb, 'images', 'tiny_view2_frame_0003.tiff');
img_bytes = fileread_bytes(img_k);
delete(img_k);
[ta_ok, ta_err] = tab.run_stage(rid, 'image_undistorter');
write_bytes(img_k, img_bytes);
msk_k = fullfile(sb, 'score_masks', 'tiny_view2_frame_0003.tiff.png');
msk_bytes = fileread_bytes(msk_k);
write_bytes(msk_k, [msk_bytes; uint8(0)]);
[tb_ok, tb_err] = tab.run_stage(rid, 'mesh_cleanup');
write_bytes(msk_k, msk_bytes);
rec_k = fullfile(run_dir, 'inputs', 'sfm_recipe.json');
rec_txt = fileread(rec_k);
fileattrib(rec_k, '+w');
write_txt(rec_k, strrep(rec_txt, '"silhouette_frames": 4', '"silhouette_frames": 5'));
[tc_ok, tc_err] = tab.run_stage(rid, 'mesh_cleanup');
write_txt(rec_k, rec_txt);
[td_ok, td_err] = tab.verify_built_inputs(run_dir);
record('S7b a deleted image, a changed score mask and a changed recipe are refused; restored files pass', ...
    t0_ok && ~ta_ok && contains(ta_err, 'is missing') && ~tb_ok && contains(tb_err, 'score_masks') && ...
    ~tc_ok && contains(tc_err, 'sfm_recipe.json') && td_ok, ...
    sprintf('%s | %s | %s | %s | %s', t0_err, ta_err, tb_err, tc_err, td_err));
write_txt(cam_file, strrep(txt, 'SIMPLE_RADIAL 64 48 8000', 'SIMPLE_RADIAL 64 48 8001'));

%% S8 cancel during the build, then a fresh attempt
rid8 = '20261014T120000_0c50ca8c';   % a real run ID form (the v2 check in S11 needs one)
tab.create_run(rid8, struct('image_list', cut, 'roi_json', roi_json, ...
    'sparse_source', 'built', 'sfm_recipe', Rf));
tab.record_run(rid8, 'RUNNING');
tab.run_stage(rid8, 'sparse_prep');
setenv('OM_FAKE_COLMAP_MODEL', fullfile(models, 'good'));
setenv('OM_FAKE_COLMAP_SLEEP', '8');
tmr = timer('StartDelay', 4, 'TimerFcn', @(~, ~) tab.request_cancel(rid8));
start(tmr);
[k_ok, k_err] = tab.run_stage(rid8, 'sparse_build');
stop(tmr); delete(tmr);
setenv('OM_FAKE_COLMAP_SLEEP', '');
run8 = rdir(rid8);
st8 = stage_entry(tab.read_manifest(run8), 'sparse_build');
[r_ok, r_err] = tab.run_stage(rid8, 'sparse_build');
st8b = stage_entry(tab.read_manifest(run8), 'sparse_build');
att = dir(fullfile(run8, 'stages', 'sparse_build.attempt_*'));
record('S8 cancel gives CANCELLED; the next attempt keeps the old folder', ...
    ~k_ok && strcmp(st8.status, 'CANCELLED') && st8.validation.exit_code == 130 && ...
    r_ok && any(strcmp(st8b.status, {'PASSED', 'WARNED'})) && numel(att) == 1 && ...
    isfolder(fullfile(att(1).folder, att(1).name, 'work')), ...
    sprintf('%s | %s | %d attempt folder(s)', k_err, r_err, numel(att)));

%% S13 a retry of the undistortion step starts in an empty workspace
% The stand-in COLMAP fails like COLMAP 4.2.1 (0xC0000409) when it runs
% into a workspace that already holds images
[u1_ok, u1_err] = tab.run_stage(rid8, 'image_undistorter');
[u2_ok, u2_err] = tab.run_stage(rid8, 'image_undistorter');
att_u = dir(fullfile(run8, 'stages', 'image_undistorter.attempt_*'));
st_u = stage_entry(tab.read_manifest(run8), 'image_undistorter');
own_dense = fullfile(run8, 'own_dense');
[u3_ok, u3_err] = tab.run_stage(rid8, 'image_undistorter', struct('dense_dir', own_dense));
[u4_ok, u4_err] = tab.run_stage(rid8, 'image_undistorter', struct('dense_dir', own_dense));
att_own = dir([own_dense '.attempt_*']);
dense8 = fullfile(run8, 'stages', 'image_undistorter', 'dense');
tt_src = fileread(fullfile(run8, 'stages', 'sparse_build', 'om_tile_transform.json'));
A8 = tab.attempt_folders(rid8);
record('S13 a retry of image_undistorter keeps the earlier workspace as image_undistorter.attempt_* and passes', ...
    u1_ok && u2_ok && numel(att_u) == 1 && ...
    strcmp(fileread(fullfile(dense8, 'om_tile_transform.json')), tt_src) && ...
    strcmp(fileread(fullfile(dense8, 'sparse', 'om_tile_transform.json')), tt_src) && ...
    any(strcmp({A8.name}, ['stages/' att_u(1).name])) && all([A8.bytes] > 0) && ...
    isfolder(fullfile(att_u(1).folder, att_u(1).name, 'dense', 'images')) && ...
    any(strcmp(st_u.status, {'PASSED', 'WARNED'})) && ...
    u3_ok && u4_ok && numel(att_own) == 1 && isfolder(fullfile(own_dense, 'images')), ...
    sprintf('%s | %s | %d attempt folder(s) | own: %s | %s | %d', u1_err, u2_err, numel(att_u), ...
    u3_err, u4_err, numel(att_own)));

%% S11 manifest.pipeline survives the v1 -> v2 conversion unchanged
m8 = tab.read_manifest(run8);
[v2bytes, ~] = tab.convert_v1_to_v2(fullfile(run8, 'manifest.json'), run8);
m82 = jsondecode(v2bytes);
[sc_ok, sc_err] = tab.write_manifest_v2_sidecar(run8, v2bytes);
[sv_ok, sv_err] = tab.validate_sidecar_public(run8);
record('S11 pipeline round-trips through the v2 conversion and the frozen-field check', ...
    isfield(m82, 'pipeline') && strcmp(jsonencode(m82.pipeline), jsonencode(m8.pipeline)) && ...
    sc_ok && sv_ok && numel(tab.stage_order_for_run(rid8)) == 8, sprintf('%s %s', sc_err, sv_err));

%% S9 the legacy golden run keeps eight steps
golden_root = om_test_getenv('OM_TEST_RESTORE_GOLDEN_ROOT');
if isempty(golden_root) || ~isfolder(golden_root)
    fprintf('S9 SKIP (set OM_TEST_RESTORE_GOLDEN_ROOT)\n');
else
    groot = fullfile(root, 'golden');
    mkdir(fullfile(groot, 'subset.matom', 'reconstruction', 'runs'));
    gid = '20260909T110043_d091bb44';
    copyfile(fullfile(golden_root, 'subset.matom', 'reconstruction', 'runs', gid), ...
        fullfile(groot, 'subset.matom', 'reconstruction', 'runs', gid));
    gt = rabbit_reconstruction_tab();
    gt.load_state(groot, 'subset');
    gm = gt.read_manifest(fullfile(groot, 'subset.matom', 'reconstruction', 'runs', gid));
    gp = gt.reconstruction_stage_projection(gid);
    record('S9 legacy golden run: no pipeline, eight steps', ...
        ~isfield(gm, 'pipeline') && numel(gt.stage_order_for_run(gid)) == 8 && ...
        numel(gp.stages) == 8, sprintf('first resumable %s', gp.first_resumable_stage));
end

%% S10 manifest.json in the images folder is not an image
[w10_ok, w10_err] = tab.validate_sparse_model(fullfile(root, 'supplied_model'), cut);
record('S10 the cut manifest.json is not counted as an unregistered image', w10_ok, w10_err);

%% G1-G3 the step 2 controls of the app (headless)
if isempty(getenv('OM_SFM_SKIP_GUI'))
    a = analyse_optical_mapping;
    gui_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
    rows0 = numel(a.recon.ReconstructionStageList.Items);
    src0 = a.recon.ReconstructionSparseSourceDropDown.Value;
    a.recon.ReconstructionSparseSourceDropDown.Value = 'built';
    a.recon.reconstruction_sparse_source_changed();
    items = a.recon.ReconstructionStageList.Items;
    % dense cloud "APDe-MVS + COLMAP", then back to "COLMAP"
    a.recon.ReconstructionDenseDropDown.Value = 'both';
    feval(a.recon.ReconstructionDenseDropDown.ValueChangedFcn, a.recon.ReconstructionDenseDropDown, []);
    items_apd = a.recon.ReconstructionStageList.Items;
    a.recon.ReconstructionDenseDropDown.Value = 'colmap';
    feval(a.recon.ReconstructionDenseDropDown.ValueChangedFcn, a.recon.ReconstructionDenseDropDown, []);
    g = a.recon.reconstruction_gate_state();
    record('G1 build mode: 8 listed steps on the fused cloud (10 with APDe-MVS), recipe controls shown, folder hidden', ...
        strcmp(src0, 'built') && rows0 == 8 && numel(items) == 8 && numel(items_apd) == 10 && ...
        contains(items{1}, 'Step 1 of 8: Prepare images for the sparse model') && ...
        contains(items{2}, 'Sparse model (COLMAP structure from motion)') && ...
        ~any(contains(items, 'APDe')) && ...
        strcmp(char(a.recon.ReconstructionSfmRecipeDropDown.Visible), 'on') && ...
        strcmp(char(a.recon.ReconstructionSfmDetailsButton.Visible), 'on') && ...
        strcmp(char(a.recon.ReconstructionSparseField.Visible), 'off'), ...
        sprintf('%d -> %d rows (apd %d); recipe %s, details %s, folder %s; %s | %s', rows0, numel(items), ...
        numel(items_apd), char(a.recon.ReconstructionSfmRecipeDropDown.Visible), char(a.recon.ReconstructionSfmDetailsButton.Visible), ...
        char(a.recon.ReconstructionSparseField.Visible), g.step2_note, g.step3_note));
    a.recon.ReconstructionSparseSourceDropDown.Value = 'supplied';
    a.recon.reconstruction_sparse_source_changed();
    record('G2 back to an existing sparse model: 8 steps and the folder again', ...
        numel(a.recon.ReconstructionStageList.Items) == 8 && ...
        any(contains(a.recon.ReconstructionStageList.Items, 'APDe')) && ...
        strcmp(char(a.recon.ReconstructionSparseField.Visible), 'on'), ...
        sprintf('%d rows, folder %s', numel(a.recon.ReconstructionStageList.Items), char(a.recon.ReconstructionSparseField.Visible)));
    if ~isempty(golden_root) && isfolder(golden_root)
        a.recon.ReconstructionSparseSourceDropDown.Value = 'built';
        a.recon.reconstruction_sparse_source_changed();
        a.recon.test_manifest_pick = fullfile(groot, 'subset.matom', 'reconstruction', 'runs', gid, 'manifest.json');
        a.recon.OpenReconstructionManifestMenuSelected();
        record('G3 opening a run on a supplied model sets step 2 to it', ...
            strcmp(a.recon.ReconstructionSparseSourceDropDown.Value, 'supplied') && ...
            numel(a.recon.ReconstructionStageList.Items) == 8, a.recon.ReconstructionSparseSourceDropDown.Value);
    end
end

fprintf('PROBE_SPARSE_MODEL_BUILD RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0
    error('PROBE_FAIL probe_sparse_model_build');
end

    function record(name, condition, detail)
        if condition
            pass = pass + 1;
            result = 'PASS';
        else
            fail = fail + 1;
            result = 'FAIL';
        end
        fprintf('%s %s %s\n', name, result, detail);
    end
end

function st = stage_entry(m, name)
% The last manifest entry of a stage (empty struct when missing)
st = struct('status', 'MISSING', 'warnings', {{}}, 'artifacts', struct('path', {}, 'sha256', {}));
if ~isstruct(m) || ~isfield(m, 'stages') || isempty(m.stages), return; end
s = m.stages;
if iscell(s), s = [s{:}]; end
i = find(strcmp({s.name}, name), 1, 'last');
if isempty(i), return; end
st = s(i);
if isempty(st.warnings), st.warnings = {}; elseif ~iscell(st.warnings), st.warnings = cellstr(st.warnings); end
if iscell(st.artifacts), st.artifacts = [st.artifacts{:}]; end
end

function write_model(folder, names, w, h, kind, model)
% A COLMAP text model of a sphere (radius 1, 162 points) seen by cameras on
% a ring of radius 10 around it, one camera per view. kind 'good': every
% image observes the points on its own side of the sphere (an opaque body
% seen from outside); 'reversed': the points on the far side (the depth-
% reversed twin); 'posed_view4': as 'good', but the images of view 4 have a
% pose and no observation (as a rig model can pose them); 'posed_one': as
% 'good', but tiny_view4_frame_0003 has no observation. model: camera
% model (default SIMPLE_RADIAL, f 8000).
if nargin < 6, model = 'SIMPLE_RADIAL'; end
mkdir(folder);
n_pts = 162;
k = (0:n_pts - 1)' + 0.5;
phi = acos(1 - 2 * k / n_pts);
th = pi * (1 + sqrt(5)) * k;
X = [cos(th) .* sin(phi), sin(th) .* sin(phi), cos(phi)];
fid = fopen(fullfile(folder, 'cameras.txt'), 'w');
for v = 1:4
    if strcmp(model, 'PINHOLE')
        fprintf(fid, '%d PINHOLE %d %d 8000 8000 %g %g\n', v, w, h, w / 2, h / 2);
    else
        fprintf(fid, '%d SIMPLE_RADIAL %d %d 8000 %g %g 0\n', v, w, h, w / 2, h / 2);
    end
end
fclose(fid);
tracks = cell(n_pts, 1);
fid = fopen(fullfile(folder, 'images.txt'), 'w');
for i = 1:numel(names)
    v = str2double(regexp(names{i}, '_view(\d+)_', 'tokens', 'once'));
    a = 2 * pi * (i - 1) / numel(names);
    C = 10 * [cos(a) 0.3 sin(a)];
    z = -C / norm(C);
    x = cross([0 1 0], z); x = x / norm(x);
    y = cross(z, x);
    Rm = [x; y; z];
    t = -Rm * C';
    q = rot2quat(Rm);
    fprintf(fid, '%d %.12g %.12g %.12g %.12g %.12g %.12g %.12g %d %s\n', i, q, t, v, names{i});
    side = X * C';
    if strcmp(kind, 'reversed'), seen = find(side < 0); else, seen = find(side > 0); end
    if strcmp(kind, 'posed_view4') && v == 4, seen = []; end
    if strcmp(kind, 'posed_one') && strcmp(names{i}, 'tiny_view4_frame_0003.tiff'), seen = []; end
    obs = '';
    for j = 1:numel(seen)
        obs = sprintf('%s %d %d %d', obs, 10, 10, seen(j));
        tracks{seen(j)}(end+1, :) = [i, j - 1];
    end
    fprintf(fid, '%s\n', strtrim(obs));
end
fclose(fid);
fid = fopen(fullfile(folder, 'points3D.txt'), 'w');
for p = 1:n_pts
    if isempty(tracks{p}), continue; end
    tr = sprintf(' %d %d', tracks{p}');
    fprintf(fid, '%d %.12g %.12g %.12g 128 128 128 0.5%s\n', p, X(p, :), tr);
end
fclose(fid);
end

function q = rot2quat(R)
% Rotation matrix -> COLMAP quaternion (w, x, y, z)
w = sqrt(max(0, 1 + trace(R))) / 2;
if w > 1e-6
    q = [w, (R(3, 2) - R(2, 3)) / (4 * w), (R(1, 3) - R(3, 1)) / (4 * w), (R(2, 1) - R(1, 2)) / (4 * w)];
else
    [~, i] = max(diag(R));
    switch i
        case 1
            s = 2 * sqrt(1 + R(1, 1) - R(2, 2) - R(3, 3));
            q = [(R(3, 2) - R(2, 3)) / s, s / 4, (R(1, 2) + R(2, 1)) / s, (R(1, 3) + R(3, 1)) / s];
        case 2
            s = 2 * sqrt(1 + R(2, 2) - R(1, 1) - R(3, 3));
            q = [(R(1, 3) - R(3, 1)) / s, (R(1, 2) + R(2, 1)) / s, s / 4, (R(2, 3) + R(3, 2)) / s];
        otherwise
            s = 2 * sqrt(1 + R(3, 3) - R(1, 1) - R(2, 2));
            q = [(R(2, 1) - R(1, 2)) / s, (R(1, 3) + R(3, 1)) / s, (R(2, 3) + R(3, 2)) / s, s / 4];
    end
end
end

function b = fileread_bytes(path)
fid = fopen(path, 'r');
b = fread(fid, Inf, '*uint8');
fclose(fid);
end

function write_bytes(path, b)
fid = fopen(path, 'w');
fwrite(fid, b, 'uint8');
fclose(fid);
end

function write_txt(path, txt)
fid = fopen(path, 'w', 'n', 'UTF-8');
fwrite(fid, txt, 'char');
fclose(fid);
end

function h = sha(path)
h = rabbit_sfm_build.sha256_file(path);
end

function cleanup_root(root)
% The run snapshots are read-only; make them writable to delete them
try
    fileattrib(fullfile(root, '*'), '+w', '', 's');
catch
end
try
    rmdir(root, 's');
catch
end
end
