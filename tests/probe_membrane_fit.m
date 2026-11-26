function probe_membrane_fit

%% Probe: membrane fit on synthetic clouds
% Collin Snitchler
% 06.10.2026
% Checks rabbit_membrane_fit on an ellipsoid cloud with an open base:
%   P1 the surface is recovered within tolerance of the true ellipsoid
%   P2 the unsupported base is cut open and the rest stays one piece
%   P3 a fixed seed gives the same mesh twice
%   P4 the silhouette cap keeps the mesh inside a smaller silhouette
%   P5 rabbit_mesh_cleanup writes mesh-cleanup.ply and records the method
%      (on a scratch copy of the golden run, when that run is present)
%   P6 face_components keeps one connected surface in one piece
%   P7 the RHYTHM visibility gate M9 (visibility check) sees a sphere in a portrait image
%      when only a few vertices carry the camera visibility
%   P8 the meshing stage finds the silhouette masks in both folder layouts, leaves out a
%      mask that disagrees with the points its camera saw, and drops the cap when most do;
%      a cap turned off by the setting leaves no cameras and keeps the check's counts
%   P9 the reconstruction tab picks the dataset's masks folder only when there is exactly one
%   P10 the membrane gate verdicts: WARN for the rabbit study's values of M4, M7 and M9, FAIL for
%      an inside-out mesh, a mesh that does not follow the cloud or has no data under it, no faces,
%      and too few vertices with a DIRECT camera; PASS within the alpha-shape limits
%   P11 the field band: a mask cut by a field edge 24 px from the image border puts no cap
%      beyond that edge (the membrane keeps the cloud's extent there), while the far side,
%      whose edge lies 61 px from the border, is still held inside the mask; the mask
%      agreement check leaves out the points in the band, so such a mask is used when the edge
%      stays still over 10 frames of its view; with only 5 frames there is no band and the
%      masks disagree (no cap)
%   P12 one open edge (single_open_edge): a strip of points across the open base splits it in
%      two and a patch at the apex has no points; cutting every large unsupported region
%      leaves a hole in both (two boundary loops, the default and 0 alike); with the option the
%      base half beyond the strip is joined to the open edge (the strip cut with it; one boundary
%      loop), while the apex gap, far from the open edge along the surface, is still cut and
%      leaves a hole (two loops; nothing unsupported is spanned)
% P5 needs the golden run: set OM_TEST_REPROJECTION_GOLDEN_ROOT to the folder holding
% subset.matom (P5 is skipped when it is unset).

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));

radii = [0.030 0.025 0.020];     % ellipsoid half-axes (arbitrary world units)
base_level = -0.5 * radii(3);    % no points below this height: the open base
points = ellipsoid_cloud(radii, base_level, 20000, 7);
opts = struct('stage1_iterations', 30, 'stage2_iterations', 15);

fprintf('P1: the ellipsoid is recovered within tolerance\n');
[V, F, rep] = rabbit_membrane_fit(points, [], opts);
err = ellipsoid_distance(V, radii);
mean_radius = mean(radii);
P1 = median(err) < 0.01 * mean_radius && prctile(err, 95) < 0.03 * mean_radius && ...
    rep.quality.cloud_to_mesh.median < 0.01 * mean_radius;
fprintf('  level %d, %d vertices; surface error median %.2f %%, p95 %.2f %% of the mean radius; cloud-to-mesh median %.2f %% -> %s\n', ...
    rep.settings.template_subdivisions, size(V, 1), 100 * median(err) / mean_radius, ...
    100 * prctile(err, 95) / mean_radius, 100 * rep.quality.cloud_to_mesh.median / mean_radius, tf(P1));
if P1, pass = pass + 1; else, fail = fail + 1; end

fprintf('P2: the open base is cut and one piece remains\n');
G = graph_of_faces(F);
lowest = min(V(:, 3));
support = rep.settings.support_mm * rep.settings.world_units_per_mm;   % kept faces lie this close to data
P2 = rep.cut.removed_regions >= 1 && rep.cut.boundary_edges > 0 && ...
    max(conncomp(G)) == 1 && lowest > base_level - support;
fprintf('  removed regions %d, boundary edges %d, pieces %d, lowest vertex %.4f (base %.4f) -> %s\n', ...
    rep.cut.removed_regions, rep.cut.boundary_edges, max(conncomp(G)), lowest, base_level, tf(P2));
if P2, pass = pass + 1; else, fail = fail + 1; end

fprintf('P3: a fixed seed gives the same mesh twice\n');
points_again = ellipsoid_cloud(radii, base_level, 20000, 7);
[V2, F2] = rabbit_membrane_fit(points_again, [], opts);
P3 = isequal(points, points_again) && isequal(F, F2) && max(abs(V(:) - V2(:))) == 0;
fprintf('  same cloud %s, same faces %s, max vertex difference %.3g -> %s\n', ...
    tf(isequal(points, points_again)), tf(isequal(F, F2)), max(abs(V(:) - V2(:))), tf(P3));
if P3, pass = pass + 1; else, fail = fail + 1; end

fprintf('P4: the silhouette cap keeps the mesh inside a smaller silhouette\n');
cam = side_camera(radii, 0.92);
[V4, F4, rep4] = rabbit_membrane_fit(points, cam, opts);
width_free = extent_across(V, cam);
width_cap = extent_across(V4, cam);
% The cap holds the outline on the mask edge (within a few pixels); the original Python fit gives the
% same faces-outside fraction (0.156) and IoU (0.845) on this case
expected_width = 2 * 0.92 * radii(2);
P4 = rep4.quality.faces_outside_max_native_px < 3 && width_cap < width_free && ...
    abs(width_cap - expected_width) < 0.03 * expected_width && ...
    rep4.quality.silhouette_iou_mean > 0.8 && any([rep4.iterations.outside_vertices] > 0);
fprintf('  deepest face outside %.2f px, IoU %.3f, width across the view %.4f (no cap %.4f, mask %.4f) -> %s\n', ...
    rep4.quality.faces_outside_max_native_px, rep4.quality.silhouette_iou_mean, ...
    width_cap, width_free, expected_width, tf(P4));
if P4, pass = pass + 1; else, fail = fail + 1; end

fprintf('P5: the meshing stage writes the membrane mesh and records the method\n');
golden_root = om_test_getenv('OM_TEST_REPROJECTION_GOLDEN_ROOT');
golden = fullfile(golden_root, 'subset.matom', 'reconstruction', 'runs', '20260909T110043_d091bb44');
if isempty(golden_root)
    fprintf('  OM_TEST_REPROJECTION_GOLDEN_ROOT is not set: skipped\n');
elseif ~isfolder(golden)
    fprintf('  golden run not found (%s): skipped\n', golden);
else
    work = fullfile(tempdir, ['probe_membrane_' char(java.util.UUID.randomUUID())]);
    mkdir(fullfile(work, 'outputs'));
    mkdir(fullfile(work, 'sparse'));
    copyfile(fullfile(golden, 'outputs', 'fused-geometric.ply'), fullfile(work, 'outputs'));
    copyfile(fullfile(golden, 'outputs', 'fused-geometric.ply.vis'), fullfile(work, 'outputs'));
    copyfile(fullfile(golden, 'stages', 'image_undistorter', 'dense', 'sparse', '*.bin'), fullfile(work, 'sparse'));
    fused = fullfile(work, 'outputs', 'fused-geometric.ply');
    r = rabbit_mesh_cleanup.run(fused, [fused '.vis'], fullfile(work, 'sparse', 'images.bin'), ...
        struct('membrane', opts));
    gj = jsondecode(fileread(fullfile(work, 'outputs', 'mesh-cleanup-gates.json')));
    m = rabbit_rhythm_reproject.read_ply_mesh(fullfile(work, 'outputs', 'mesh-cleanup.ply'));
    P5 = isfield(gj, 'mesh_method') && strcmp(gj.mesh_method, 'membrane') && ...
        strcmp(gj.cloud_source, 'fused') && size(m.faces, 1) > 0;
    fprintf('  verdict %s (%s), method %s, mesh %d vertices %d faces -> %s\n', gj.verdict, r.err, ...
        gj.mesh_method, size(m.pts, 1), size(m.faces, 1), tf(P5));
    if P5, pass = pass + 1; else, fail = fail + 1; end
    rmdir(work, 's');   % the scratch copy is not kept
end

fprintf('P6: face_components keeps one connected surface in one piece\n');
% Face 2 shares its first vertex with face 1, so a face walk that only
% follows faces with an unlabelled first vertex drops vertex 4 and starts
% a second piece at face 3
F6 = [1 2 3; 1 3 4; 4 5 6];
c6 = rabbit_mesh_cleanup.face_components(F6, 7);
P6 = isequal(c6(1:6)', ones(1, 6)) && c6(7) == 0;
fprintf('  component ids %s (vertex 7 is in no face) -> %s\n', mat2str(c6'), tf(P6));
if P6, pass = pass + 1; else, fail = fail + 1; end

fprintf('P7: the visibility gate sees a sphere in a portrait image\n');
[V7, F7] = sphere_mesh(1.0, 10.0, 80);
N7 = (V7 - [0 0 10]) ./ sqrt(sum((V7 - [0 0 10]) .^ 2, 2));   % outward normals
cameras7 = struct('model', 'SIMPLE_PINHOLE', 'params', [700 80 120], 'width', 160, 'height', 240);
images7 = struct('qvec', [1 0 0 0], 'tvec', [0 0 0], 'camera_id', 1, 'name', 'portrait');
% Only every 20th front-facing vertex carries the camera visibility (as a
% sparse dense cloud would); the sphere spans image rows 50..190, below
% the image width, so a width/height swap would cut it
vis7 = repmat({int32(zeros(1, 0))}, size(V7, 1), 1);
front = find(N7(:, 3) < -0.2);
for i = front(1:20:end)'
    vis7{i} = int32(0);
end
look7 = rabbit_mesh_cleanup.camera_lookns(images7);
[~, m9] = rabbit_mesh_cleanup.direct_visibility_gate(V7, N7, F7, cameras7, images7, vis7, look7);
P7 = m9.n_observations == numel(front(1:20:end)) && m9.aggregate_direct > 0.6;
fprintf('  %d observations, DIRECT fraction %.3f (needs > 0.6) -> %s\n', ...
    m9.n_observations, m9.aggregate_direct, tf(P7));
if P7, pass = pass + 1; else, fail = fail + 1; end

fprintf('P8: the meshing stage finds the masks and leaves out one that disagrees\n');
[cameras8, images8, cloud8, vis8] = mask_scene(radii);
flat = fullfile(tempdir, ['probe_masks_' char(java.util.UUID.randomUUID())]);
nested = fullfile(tempdir, ['probe_masks_' char(java.util.UUID.randomUUID())]);
mkdir(flat);
mkdir(fullfile(nested, 'view1'));
[good, bad] = scene_masks(cameras8(int64(1)), cloud8, radii);
for k = 1:10
    imwrite(uint8(good) * 255, fullfile(flat, sprintf('a%d.tiff.png', k)));             % flat, as rabbit_segmentation_masks writes
    imwrite(uint8(good) * 255, fullfile(nested, 'view1', sprintf('a%d.tiff.png', k)));  % COLMAP layout
end
imwrite(uint8(bad) * 255, fullfile(flat, 'b.tiff.png'));   % too tight: cuts the cloud
% 10 good masks, 1 tight one, 1 image without a mask: the tight mask is left out
[cams_f, rec_f] = rabbit_mesh_cleanup.membrane_cameras(cameras8, images8, flat, cloud8, vis8, 0.97);
[cams_n, ~] = rabbit_mesh_cleanup.membrane_cameras(cameras8, images8, nested, cloud8, vis8, 0.97);
% 2 good masks and the tight one: too many disagree, so no cap at all
[cams_b, rec_b] = rabbit_mesh_cleanup.membrane_cameras(cameras8, images8([1 2 11]), flat, cloud8, vis8, 0.97);
[cams_0, rec_0] = rabbit_mesh_cleanup.membrane_cameras(cameras8, images8, '', cloud8, vis8, 0.97);
[cams_s, rec_s] = rabbit_mesh_cleanup.cap_off_by_setting(cams_f, rec_f);
P8 = isempty(cams_s) && ~rec_s.cap_used && rec_s.cameras_used == 0 && ...
    startsWith(rec_s.note, 'silhouette cap off by setting (10 of the 11 masks') && ...
    ~contains(rec_s.note, 'cap on') && isequaln(rec_s.agreement, rec_f.agreement) && ...
    numel(cams_f) == 10 && all(startsWith({cams_f.name}, 'view1/a')) && rec_f.cap_used && ...
    min(rec_f.agreement(1:10)) >= 0.99 && rec_f.agreement(11) < 0.97 && ...
    any(contains(rec_f.skipped, 'view3/c.tiff: no mask')) && startsWith(rec_f.note, 'silhouette cap on') && ...
    numel(cams_n) == 10 && ...
    isempty(cams_b) && ~rec_b.cap_used && contains(rec_b.note, 'disagree') && ...
    contains(rec_b.note, 'without the silhouette cap') && ...
    isempty(cams_0) && contains(rec_0.note, 'without the silhouette cap');
fprintf(['  flat folder: %d cameras, agreement good %.3f, tight %.3f; COLMAP layout: %d cameras;\n' ...
    '  mostly tight masks: "%s"\n  no folder: "%s" -> %s\n'], numel(cams_f), min(rec_f.agreement(1:10)), ...
    rec_f.agreement(11), numel(cams_n), rec_b.note, rec_0.note, tf(P8));
rmdir(flat, 's');
rmdir(nested, 's');
if P8, pass = pass + 1; else, fail = fail + 1; end

fprintf('P9: the tab uses the dataset''s masks folder only when there is exactly one\n');
root9 = fullfile(tempdir, ['probe_maskroot_' char(java.util.UUID.randomUUID())]);
mkdir(root9);
tab = rabbit_reconstruction_tab();
tab.load_state(root9, 'stem');
none9 = tab.default_mask_root();
mkdir(fullfile(root9, 'masks_reconstruction_a'));
write_text(fullfile(root9, 'masks_reconstruction_a', 'manifest.json'), '{"kind": "colmap_masks"}');
mkdir(fullfile(root9, 'masks_reconstruction_b'));   % no manifest: not a masks folder
one9 = tab.default_mask_root();
mkdir(fullfile(root9, 'masks_reconstruction_c'));
write_text(fullfile(root9, 'masks_reconstruction_c', 'manifest.json'), '{"kind": "colmap_masks"}');
two9 = tab.default_mask_root();
P9 = isempty(none9) && strcmp(one9, fullfile(root9, 'masks_reconstruction_a')) && isempty(two9);
fprintf('  none "%s", one "%s", two "%s" -> %s\n', none9, one9, two9, tf(P9));
rmdir(root9, 's');
if P9, pass = pass + 1; else, fail = fail + 1; end

fprintf('P10: membrane gate verdicts: WARN for a smooth fit of a thick cloud, FAIL for a broken mesh\n');
% Measured values of the rabbit study's membrane meshes (July) give WARN
% for M4, M7 and M9 and an overall pass; each broken case FAILs its gate
g10 = membrane_gates(0.964, 0.989, 0.13, 1.08, 0.992, 0.79, 0.909);
[v10, n10] = rabbit_mesh_cleanup.membrane_verdicts(g10);
warn_ok = strcmp(v10.M4.verdict, 'WARN') && strcmp(v10.M7.verdict, 'WARN') && ...
    strcmp(v10.M9.verdict, 'WARN') && strcmp(v10.M1.verdict, 'PASS') && numel(n10) == 3;
% Inside-out: a sphere whose normals point inwards, seen from outside
[V10, F10] = sphere_mesh(1.0, 0, 40);
N10 = -V10 ./ sqrt(sum(V10 .^ 2, 2));
centres10 = [0 0 6; 6 0 0; -6 0 0; 0 6 0];
cloud10 = V10(1:3:end, :);
vis10 = cell(size(cloud10, 1), 1);
for i = 1:size(cloud10, 1)
    sees = find((centres10 - cloud10(i, :)) * cloud10(i, :)' > 0.2) - 1;   % cameras in front of the point
    vis10{i} = int32(sees(:)');
end
[~, m4_10] = rabbit_mesh_cleanup.membrane_orientation(V10, N10, cloud10, vis10, centres10, 0.05);
g_io = g10;
g_io.M4 = struct('pass', false, 'measured', m4_10);
v_io = rabbit_mesh_cleanup.membrane_verdicts(g_io);
% M7: the mesh does not follow the cloud; surface without data; no faces
v_far = rabbit_mesh_cleanup.membrane_verdicts(membrane_gates(0.995, 0.999, 1.4, 2.0, 0.99, 0.99, 0.99));
v_nodata = rabbit_mesh_cleanup.membrane_verdicts(membrane_gates(0.995, 0.999, 0.1, 0.5, 0.85, 0.99, 0.99));
g_nf = g10;
g_nf.M7 = struct('pass', false, 'measured', struct('reason', 'no faces'));
v_nf = rabbit_mesh_cleanup.membrane_verdicts(g_nf);
% M9: most observed vertices have no DIRECT camera
v_m9 = rabbit_mesh_cleanup.membrane_verdicts(membrane_gates(0.995, 0.999, 0.1, 0.5, 0.99, 0.6, 0.7));
% All within the alpha-shape limits: PASS
v_ok = rabbit_mesh_cleanup.membrane_verdicts(membrane_gates(0.995, 0.999, 0.1, 0.5, 0.99, 0.99, 1.0));
P10 = warn_ok && m4_10.agreement < 0.1 && strcmp(v_io.M4.verdict, 'FAIL') && ...
    strcmp(v_far.M7.verdict, 'FAIL') && strcmp(v_nodata.M7.verdict, 'FAIL') && ...
    strcmp(v_nf.M7.verdict, 'FAIL') && strcmp(v_m9.M9.verdict, 'FAIL') && ...
    strcmp(v_ok.M4.verdict, 'PASS') && strcmp(v_ok.M7.verdict, 'PASS') && strcmp(v_ok.M9.verdict, 'PASS');
fprintf(['  rabbit-like M4/M7/M9 %s/%s/%s; inside-out sphere agreement %.3f -> M4 %s; M7 far %s, ' ...
    'no data %s, no faces %s; M9 few DIRECT vertices %s; within limits %s/%s/%s -> %s\n'], ...
    v10.M4.verdict, v10.M7.verdict, v10.M9.verdict, m4_10.agreement, v_io.M4.verdict, ...
    v_far.M7.verdict, v_nodata.M7.verdict, v_nf.M7.verdict, v_m9.M9.verdict, ...
    v_ok.M4.verdict, v_ok.M7.verdict, v_ok.M9.verdict, tf(P10));
if P10, pass = pass + 1; else, fail = fail + 1; end

fprintf('P11: the field band: no cap beyond a field edge near the border, the cap elsewhere\n');
% The side camera of P4 with the ellipsoid's centre at image column 77: the cloud's left limb
% is at column ~10, the right limb of the 0.92 mask at ~138 (61 px from the border); the mask
% is cut at column 24 (a field edge 24 px from the border), so with the band the left side
% is not limited and without it the cap pulls the membrane to column 24
cam11 = side_camera(radii, 0.92);
f11 = cam11.f(1);
d11 = cam11.t(3);
cam11.c(1) = 77;
[yy11, zz11] = meshgrid(((1:cam11.width) - 0.5 - cam11.c(1)) / f11 * d11, ...
    -((1:cam11.height) - 0.5 - cam11.c(2)) / f11 * d11);
cam11.mask = (yy11 / (0.92 * radii(2))) .^ 2 + (zz11 / (0.92 * radii(3))) .^ 2 <= 1;
cam11.mask(:, 1:24) = false;
cam11.band = [];
cam11b = cam11;
cam11b.band = rabbit_sfm_build.field_band(cam11.mask, 32);
[V11n, ~] = rabbit_membrane_fit(points, cam11, opts);
[V11b, ~, rep11b] = rabbit_membrane_fit(points, cam11b, opts);
s11n = V11n * cam11.R(1, :)';   % image x direction (world y)
s11b = V11b * cam11.R(1, :)';
left_cut = (24 - cam11.c(1)) / f11 * d11;   % the field edge, in world units at the centre's depth
% Agreement: the P8 scene with the principal point moved so the cloud's left limb is at
% column ~10 and the good mask cut at column 24: without the band a few per cent of the points
% the image saw fall outside the mask and it is left out; with the band they are not judged
[cameras11, images11, cloud11, vis11] = mask_scene(radii);
cm11 = cameras11(int64(1));
cm11.params(2) = 90;
cameras11(int64(1)) = cm11;
good11 = scene_masks(cm11, cloud11, radii);
good11(:, 1:24) = false;
% Ten frames of one view with this mask: the field edge stays still over the frames, so it is
% a field edge (rabbit_sfm_build.static_field_bands needs at least 8 frames of a view)
flat11 = fullfile(tempdir, ['probe_masks_' char(java.util.UUID.randomUUID())]);
mkdir(flat11);
images11 = images11(1:10);
for k = 1:10
    images11(k).name = sprintf('p11_view1_frame_%04d.tiff', k);
    imwrite(uint8(good11) * 255, fullfile(flat11, [images11(k).name '.png']));
end
vis11 = repmat({int32(0:9)}, size(cloud11, 1), 1);
[c11n, r11n] = rabbit_mesh_cleanup.membrane_cameras(cameras11, images11, flat11, cloud11, vis11, 0.97);
[c11b, r11b] = rabbit_mesh_cleanup.membrane_cameras(cameras11, images11, flat11, cloud11, vis11, 0.97, 0, 32);
[~, r11s] = rabbit_mesh_cleanup.membrane_cameras(cameras11, images11(1:5), flat11, cloud11, vis11, 0.97, 0, 32);
rmdir(flat11, 's');
tol11 = 0.03 * 0.92 * radii(2);
P11 = min(s11n) > left_cut - 3 * d11 / f11 && min(s11b) < -0.97 * radii(2) && ...
    abs(max(s11b) - 0.92 * radii(2)) < tol11 && abs(max(s11n) - 0.92 * radii(2)) < tol11 && ...
    rep11b.quality.faces_outside_max_native_px < 3 && ...
    isempty(c11n) && r11n.agreement(1) < 0.97 && numel(c11b) == 10 && r11b.agreement(1) >= 0.99 && ...
    ~isempty(c11b(1).band) && contains(r11b.note, 'field band 32 px') && ~r11s.cap_used;
fprintf(['  left extent with band %.4f (cloud %.4f), without %.4f (field edge %.4f); right extent %.4f / %.4f ' ...
    '(mask %.4f); deepest face outside %.2f px; agreement without band %.3f, with band %.3f -> %s\n'], ...
    min(s11b), -radii(2), min(s11n), left_cut, max(s11b), max(s11n), 0.92 * radii(2), ...
    rep11b.quality.faces_outside_max_native_px, r11n.agreement(1), r11b.agreement(1), tf(P11));
if P11, pass = pass + 1; else, fail = fail + 1; end

fprintf('P12: one open edge: a strip across the open base, a gap at the apex\n');
% Points below the base level within 0.001 of the plane y = 0, every 4th: a sparse strip of
% support that splits the open base into two unsupported regions
rng(11);
d12 = randn(60000, 3);
d12 = d12 ./ sqrt(sum(d12 .^ 2, 2));
below12 = d12 .* radii + 0.002 * mean(radii) * randn(60000, 3);
strip12 = below12(below12(:, 3) < base_level & abs(below12(:, 2)) < 0.001, :);
strip12 = strip12(1:4:min(400, size(strip12, 1)), :);
pts_s = [points; strip12];
pts_g = points(sqrt(sum((points - [0 0 radii(3)]) .^ 2, 2)) > 0.009, :);   % no points near the apex
on12 = opts;
on12.single_open_edge = 1;
off12 = opts;
off12.single_open_edge = false;
[Vs0, Fs0, rs0] = rabbit_membrane_fit(pts_s, [], opts);
[Vsf, Fsf, rsf] = rabbit_membrane_fit(pts_s, [], off12);
[Vs1, Fs1, rs1] = rabbit_membrane_fit(pts_s, [], on12);
[Vg0, Fg0, rg0] = rabbit_membrane_fit(pts_g, [], opts);
[Vg1, Fg1, rg1] = rabbit_membrane_fit(pts_g, [], on12);
[~, ms0] = rabbit_mesh_cleanup.boundary_gate(Fs0, Vs0);
[~, ms1] = rabbit_mesh_cleanup.boundary_gate(Fs1, Vs1);
[~, mg0] = rabbit_mesh_cleanup.boundary_gate(Fg0, Vg0);
[~, mg1] = rabbit_mesh_cleanup.boundary_gate(Fg1, Vg1);
oe_s = rs1.cut.single_open_edge;
oe_g = rg1.cut.single_open_edge;
P12 = ms0.n_loops == 2 && ms1.n_loops == 1 && oe_s.joined_regions == 1 && oe_s.hole_regions == 0 && ...
    oe_s.strip_mm2 > 0 && abs(rs1.cut.removed_supported_strip_mm2 - oe_s.strip_mm2) < 1e-12 && ...
    mg0.n_loops == 2 && mg1.n_loops == 2 && oe_g.hole_regions == 1 && ...
    oe_g.joined_regions == 0 && rg1.cut.removed_regions == rg0.cut.removed_regions && ...
    abs(rg1.cut.removed_unsupported_mm2 - rg0.cut.removed_unsupported_mm2) < 1e-12 && ...
    isequal(Fg0, Fg1) && oe_g.regions(1).gap_mm > oe_g.regions(1).limit_mm && ...
    isequal(Fs0, Fsf) && isequal(Vs0, Vsf) && ~isfield(rs0.cut, 'single_open_edge') && ...
    rsf.settings.single_open_edge == 0 && rs0.settings.single_open_edge == 0;
fprintf(['  strip (%d points): loops %d without, %d with (joined %d, strip cut %.2f mm2); apex gap: loops %d ' ...
    'without, %d with (cut as a hole %d, %.2f mm2, gap along the surface %.2f mm > limit %.2f mm); ' ...
    'default = off %s -> %s\n'], ...
    size(strip12, 1), ms0.n_loops, ms1.n_loops, oe_s.joined_regions, oe_s.strip_mm2, mg0.n_loops, mg1.n_loops, ...
    oe_g.hole_regions, oe_g.hole_mm2, oe_g.regions(1).gap_mm, oe_g.regions(1).limit_mm, ...
    tf(isequal(Fs0, Fsf) && isequal(Vs0, Vsf)), tf(P12));
if P12, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MEMBRANE_FIT RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_membrane_fit %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_membrane_fit\n');
end
end


function g = membrane_gates(agree, agree10, med_d, p95_d, v_within, direct, v_direct)
% Gate records as rabbit_mesh_cleanup.run_membrane makes them, with chosen
% M4, M7 (in units of the support distance 0.005) and M9 values; the other
% gates pass
d = 0.005;
g = struct();
for k = [1 2 3 5 6 8 10]
    g.(sprintf('M%d', k)) = struct('pass', true, 'measured', struct());
end
g.M4 = struct('pass', agree >= 0.99, 'measured', struct('agreement', agree, ...
    'agreement_within_10deg_of_grazing', agree10, 'n_observations', 1000));
g.M7 = struct('pass', false, 'measured', struct('reason', '', 'support', d, ...
    'med_cloud_to_surface', med_d * d, 'p95_cloud_to_surface', p95_d * d, ...
    'vertices_within_support', v_within));
g.M9 = struct('pass', direct >= 0.98, 'measured', struct('aggregate_direct', direct, ...
    'cameras_below_95', zeros(1, double(direct < 0.98) * 5), 'n_vertices_observed', 100, ...
    'vertices_with_direct_fraction', v_direct));
end


function [V, F] = sphere_mesh(r, z0, n)
% Triangulated sphere of radius r centred on (0, 0, z0), duplicate seam and pole vertices merged
[X, Y, Z] = sphere(n);
fv = surf2patch(r * X, r * Y, r * Z + z0, 'triangles');
[V, ~, j] = unique(round(fv.vertices, 12), 'rows', 'stable');
F = j(fv.faces);
F = F(F(:, 1) ~= F(:, 2) & F(:, 2) ~= F(:, 3) & F(:, 1) ~= F(:, 3), :);
end


function points = ellipsoid_cloud(radii, base_level, n, seed)
% Points spread over an ellipsoid surface with 0.2 % noise, nothing below the base level
rng(seed);
d = randn(3 * n, 3);
d = d ./ sqrt(sum(d .^ 2, 2));
points = d .* radii;
points = points(points(:, 3) >= base_level, :);
points = points(1:min(n, size(points, 1)), :);
points = points + 0.002 * mean(radii) * randn(size(points));
end


function err = ellipsoid_distance(V, radii)
% Approximate distance to the ellipsoid surface: radial error along the ray from the centre
s = sqrt(sum((V ./ radii) .^ 2, 2));
err = abs(1 - 1 ./ s) .* sqrt(sum(V .^ 2, 2));
end


function G = graph_of_faces(F)
% Faces connected through shared edges
m = size(F, 1);
edges = sort([F(:, [1 2]); F(:, [2 3]); F(:, [3 1])], 2);
owner = repmat((1:m)', 3, 1);
[~, ~, id] = unique(edges, 'rows');
[id, order] = sort(id);
owner = owner(order);
same = id(2:end) == id(1:end-1);
a = owner([same; false]); b = owner([false; same]);
G = graph(sparse(a, b, 1, m, m) + sparse(b, a, 1, m, m));
end


function cam = side_camera(radii, shrink)
% A pinhole camera on the +x axis whose mask is the silhouette of the ellipsoid shrunk by
% the given factor, so the cap must pull the membrane inwards
distance = 20 * max(radii);
cam = struct();
cam.name = 'side';
cam.R = [0 1 0; 0 0 -1; -1 0 0];               % camera looks along -x, image x = world y
cam.t = [0; 0; distance];
cam.width = 200; cam.height = 200;
f = 0.4 * cam.width * distance / max(radii);
cam.f = [f f];
cam.c = [cam.width / 2, cam.height / 2];
cam.scale = 1;
[yy, zz] = meshgrid(((1:cam.width) - 0.5 - cam.c(1)) / f * distance, ...
    -((1:cam.height) - 0.5 - cam.c(2)) / f * distance);
cam.mask = (yy / (shrink * radii(2))) .^ 2 + (zz / (shrink * radii(3))) .^ 2 <= 1;
end


function w = extent_across(V, cam)
% Width of the vertices along the camera's image x direction
axis_x = cam.R(1, :);
s = V * axis_x';
w = max(s) - min(s);
end


function [cameras, images, cloud, vis] = mask_scene(radii)
% An ellipsoid cloud in front of one pinhole camera (identity pose, 200 x 200 px), seen by
% twelve images of that camera (view1/a1..a10, view2/b, view3/c); every point is seen by all
distance = 20 * max(radii);
f = 0.4 * 200 * distance / max(radii);
cameras = containers.Map('KeyType', 'int64', 'ValueType', 'any');
cameras(int64(1)) = struct('model', 'SIMPLE_PINHOLE', 'width', 200, 'height', 200, 'params', [f; 100; 100]);
names = [arrayfun(@(k) sprintf('view1/a%d.tiff', k), 1:10, 'UniformOutput', false), ...
    {'view2/b.tiff', 'view3/c.tiff'}];
images = struct('id', num2cell(1:12), 'qvec', [1 0 0 0], 'tvec', [0 0 distance], 'camera_id', 1, 'name', names);
cloud = ellipsoid_cloud(radii, -Inf, 5000, 3);
vis = repmat({int32(0:11)}, size(cloud, 1), 1);
end


function [good, bad] = scene_masks(cm, cloud, radii)
% Silhouette of the projected cloud, slightly widened (agrees), and the same eroded (too tight)
z = cloud(:, 3) + 20 * max(radii);
col = floor(cm.params(1) * cloud(:, 1) ./ z + cm.params(2)) + 1;
row = floor(cm.params(1) * cloud(:, 2) ./ z + cm.params(3)) + 1;
hit = false(cm.height, cm.width);
hit(sub2ind(size(hit), row, col)) = true;
good = imfill(imdilate(hit, strel('disk', 3)), 'holes');
bad = imerode(good, strel('disk', 12));
end


function write_text(path, txt)
% Write a small UTF-8 text file
fid = fopen(path, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', txt);
fclose(fid);
end
