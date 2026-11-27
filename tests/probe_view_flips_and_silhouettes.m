function probe_view_flips_and_silhouettes
%% Probe: view flips and silhouettes of the rabbit reconstruction
% Collin Snitchler
% 15.10.2026
% Checks, without COLMAP, a GPU or the OM data:
%   R1 the view flips travel with the model: tile_transform_flips finds
%      om_tile_transform.json in the undistorted workspace of a run that
%      built its model (via the run folder), refuses such a run without the
%      file and refuses an unreadable file; a model of a run on an existing
%      model finds the copy in its input snapshot
%   R2 om_camera_views follows run()'s chain: FlipRows, then the view
%      flips with the shift turned round, then the shift (camera pixel
%      (r, c) reads OM view pixel (r + dy, c + dx))
%   R3 a flipped view whose map is not the whole camera frame is refused
%      (analyse_om:Reprojection:FlipNeedsTile)
%   R4 tissue_mask_valid finds a bright disk on a dark ground with
%      missing (NaN) rows
%   R5 mesh_silhouette covers exactly the pixel centres inside the
%      projected faces; silhouette_scores: a mask equal to the silhouette
%      gives IoU 1 and outline share 1, a shrunk silhouette a low outline
%      share
%   R6 a sparse step line with a batch program under a path with ^ is
%      refused with a plain message; a .exe line is written without call
%   R7 the cut's folder check names the cut_tiffs_ folders that already
%      exist in the chosen folder (the cut is then not started)
%   R8 A6 with the field band: silhouette pixels in the band
%      of rabbit_sfm_build.field_band are neither on nor off the tissue
%      (silhouette on tissue 1 with the band, below 1 without; outline
%      share and coverage unchanged); no band with field_band_px 0
%   R9 the cut's refusal names the menu that exists (File > Define
%      regions)
% Usage: matlab -batch "addpath('<repo>/tests'); probe_view_flips_and_silhouettes" -noFigureWindows

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));
work = tempname;
mkdir(work);
cleanup = onCleanup(@() rmdir(work, 's'));

%% R1 the transform travels with the model
run = fullfile(work, 'runs', 'r1');
dense_sparse = fullfile(run, 'stages', 'image_undistorter', 'dense', 'sparse');
mkdir(dense_sparse);
mkdir(fullfile(run, 'stages', 'sparse_build', 'model'));
write_txt(fullfile(run, 'manifest.json'), jsonencode(struct('pipeline', struct('sparse_source', 'built'))));
T = struct('schema', 'rabbit_sfm_build.om_tile_transform.v2', 'views', struct( ...
    'roi_row', {1, 2, 3, 4}, 'flip_lr', {true, false, false, true}, 'flip_ud', {false, false, false, true}));
tt = fullfile(run, 'stages', 'sparse_build', 'om_tile_transform.json');
write_txt(tt, jsonencode(T));
[f1, n1, i1] = rabbit_rhythm_reproject.tile_transform_flips(dense_sparse);
delete(tt);
e_missing = '';
try
    rabbit_rhythm_reproject.tile_transform_flips(dense_sparse);
catch ME
    e_missing = ME.identifier;
end
write_txt(fullfile(dense_sparse, 'om_tile_transform.json'), '{"views": 3');
e_bad = '';
try
    rabbit_rhythm_reproject.tile_transform_flips(dense_sparse);
catch ME
    e_bad = ME.identifier;
end
% a run on an existing model: the copy kept with its input snapshot
run2 = fullfile(work, 'runs', 'r2');
ds2 = fullfile(run2, 'stages', 'image_undistorter', 'dense', 'sparse');
mkdir(ds2);
mkdir(fullfile(run2, 'inputs', 'sparse'));
write_txt(fullfile(run2, 'manifest.json'), jsonencode(struct('pipeline', struct('sparse_source', 'supplied'))));
write_txt(fullfile(run2, 'inputs', 'sparse', 'om_tile_transform.json'), jsonencode(T));
[f2, ~, i2] = rabbit_rhythm_reproject.tile_transform_flips(ds2);
% a model outside any run without a file: no flips, no error
lone = fullfile(work, 'lone');
mkdir(lone);
[f3, ~, i3] = rabbit_rhythm_reproject.tile_transform_flips(lone);
R1 = isequal(f1, {'lr', 'none', 'none', 'lrud'}) && i1.built && strcmp(i1.path, tt) && ~isempty(n1) && ...
    strcmp(e_missing, 'analyse_om:Reprojection:TileTransformMissing') && strcmp(e_bad, 'analyse_om:Reprojection:TileTransform') && ...
    isequal(f2, {'lr', 'none', 'none', 'lrud'}) && ~i2.built && contains(i2.path, fullfile('inputs', 'sparse')) && ...
    isempty(f3) && isempty(i3.path) && isempty(i3.run_dir);
fprintf('R1: built %s (%s); missing -> %s; unreadable -> %s; supplied %s; lone %d -> %s\n', strjoin(f1, ','), ...
    i1.path, e_missing, e_bad, strjoin(f2, ','), numel(f3), tf(R1));
if R1, pass = pass + 1; else, fail = fail + 1; end

%% R2 om_camera_views follows run()'s chain
% A one-view check through split_canvas: build a canvas whose view 1 holds
% a ramp, then compare with the chain applied by hand.
bounds = [1 1 6 6; 1 7 6 12; 1 13 6 18; 1 19 6 24];   % square views (rotation 0 layout)
src = reshape(1:144, 6, 24);
canvas = zeros(6, 24);
start = 1;
for k = 1:4
    x = src(bounds(k, 1):bounds(k, 3), bounds(k, 2):bounds(k, 4));
    switch k
        case 1, tile = rot90(x);
        case 2, tile = fliplr(rot90(fliplr(flipud(x))));
        case 3, tile = fliplr(rot90(fliplr(x)));
        case 4, tile = fliplr(rot90(fliplr(flipud(x))));
    end
    canvas(:, start:start + 5) = tile;
    start = start + 6;
end
views = rabbit_rhythm_reproject.split_canvas(canvas, bounds, 0);
shifts = [1 2; 0 0; 0 0; -1 1];
cam_hw = repmat([6 6], 4, 1);
got = rabbit_rhythm_reproject.om_camera_views(canvas, bounds, 0, true, {'lr', 'none', 'none', 'ud'}, shifts, cam_hw);
% by hand, view 1: flipud (FlipRows), fliplr (lr) with dx -> -1, then
% camera (r, c) = view(r + 2, c - 1)
m1 = fliplr(flipud(views{1}));
e1 = nan(6, 6);
for r = 1:6
    for c = 1:6
        rr = r + 2; cc = c - 1;
        if rr >= 1 && rr <= 6 && cc >= 1 && cc <= 6, e1(r, c) = m1(rr, cc); end
    end
end
% view 4: flipud (FlipRows), flipud (ud) with dy -> -1, then (r - 1, c - 1)
m4 = views{4};
e4 = nan(6, 6);
for r = 1:6
    for c = 1:6
        rr = r - 1; cc = c - 1;
        if rr >= 1 && rr <= 6 && cc >= 1 && cc <= 6, e4(r, c) = m4(rr, cc); end
    end
end
R2 = isequaln(got{1}, e1) && isequaln(got{4}, e4) && isequaln(got{2}, flipud(views{2}));
fprintf('R2: view 1 %s, view 4 %s, view 2 %s -> %s\n', tf(isequaln(got{1}, e1)), tf(isequaln(got{4}, e4)), ...
    tf(isequaln(got{2}, flipud(views{2}))), tf(R2));
if R2, pass = pass + 1; else, fail = fail + 1; end

%% R3 flips need cut-tile cameras
sd = fullfile(work, 'flipwin');
mkdir(sd);
write_model_txt(sd, 40, 30);
mesh = fullfile(sd, 'mesh.ply');
[Vm, Fm] = small_mesh();
rabbit_mesh_cleanup.write_ply(mesh, Vm, zeros(size(Vm)), zeros(size(Vm), 'uint8'), Fm);
json = fullfile(sd, 'roi.json');
b3 = [1 1 20 30; 1 31 20 60; 1 61 20 90; 1 91 20 120];
rabbit_stack_io.save_roi_json(json, struct('schema_version', 1, 'region_bounds_src', b3, 'regions', 4, ...
    'rotation', 3, 'rabbit_panoramic', true, 'source_dims', struct('height', 20, 'width', 120), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, ...
    'view_order', {{'view2', 'view3', 'view1', 'view4'}}));
map = rand(30, 80);   % rotation 3 canvas: views of 20 x 30, cameras of 40 x 30 (a window of the camera frame)
fov = struct('type', 'vertical_crop', 'om_window_in_rec', struct('off', 5, 'cols_off', 0), ...
    'scale', struct('vertical', 1, 'horizontal', 1));
e3 = '';
try
    rabbit_rhythm_reproject.run(map, json, 'ColmapDir', sd, 'MeshFile', mesh, 'FovMapping', fov, ...
        'Shifts', repmat([0 -5], 4, 1), 'ViewFlips', {'ud', 'none', 'none', 'none'}, 'Method', 'reimplementation');
catch ME
    e3 = ME.identifier;
end
R3 = strcmp(e3, 'analyse_om:Reprojection:FlipNeedsTile');
fprintf('R3: flipped window view -> %s -> %s\n', e3, tf(R3));
if R3, pass = pass + 1; else, fail = fail + 1; end

%% R4 tissue_mask_valid
[xx, yy] = meshgrid(1:80, 1:60);
img = 100 + 900 * double((xx - 40) .^ 2 + (yy - 32) .^ 2 <= 15 ^ 2) + 5 * randn(60, 80);
img(1:6, :) = NaN;
m4 = rabbit_rhythm_reproject.tissue_mask_valid(img);
disk = (xx - 40) .^ 2 + (yy - 32) .^ 2 <= 15 ^ 2;
iou4 = nnz(m4 & disk) / nnz(m4 | disk);
R4 = iou4 > 0.9 && ~any(any(m4(1:6, :)));
fprintf('R4: disk IoU %.3f, no mask on missing rows %d -> %s\n', iou4, ~any(any(m4(1:6, :))), tf(R4));
if R4, pass = pass + 1; else, fail = fail + 1; end

%% R5 mesh_silhouette and silhouette_scores
uv = [2 2; 8 2; 2 6; 8 6];           % a 6 x 4 px rectangle in COLMAP pixel coordinates
F5 = [1 2 3; 2 4 3];
S5 = rabbit_mesh_alignment.mesh_silhouette(uv, F5, 10, 12);
want = false(10, 12);
want(3:6, 3:8) = true;                % centres (c - 0.5, r - 0.5) inside [2,8] x [2,6]
big = rabbit_mesh_alignment.mesh_silhouette([10 10; 50 10; 10 40; 50 40], F5, 60, 60);
small = rabbit_mesh_alignment.mesh_silhouette([15 15; 45 15; 15 35; 45 35], F5, 60, 60);
s_same = rabbit_mesh_alignment.silhouette_scores(big, big, 2);
s_small = rabbit_mesh_alignment.silhouette_scores(small, big, 2);
R5 = isequal(S5, want) && abs(s_same.iou - 1) < 1e-12 && abs(s_same.edge - 1) < 1e-12 && ...
    s_small.edge == 0 && abs(s_small.inside - 1) < 1e-12 && s_small.covered < 0.6;
fprintf('R5: rectangle exact %d; same: IoU %.2f edge %.2f; shrunk: edge %.2f inside %.2f covered %.2f -> %s\n', ...
    isequal(S5, want), s_same.iou, s_same.edge, s_small.edge, s_small.inside, s_small.covered, tf(R5));
if R5, pass = pass + 1; else, fail = fail + 1; end

%% R6 ^ in a batch program's path; a .exe without call
tab = rabbit_reconstruction_tab();
sdir = fullfile(work, 'stage');
mkdir(sdir);
log_file = fullfile(sdir, 'stage.log');
[ok6, err6] = tab.spawn_and_wait({sprintf('"%s" help', fullfile(work, 'car^et', 'colmap.bat'))}, log_file, ...
    fullfile(sdir, '.cancel'), fullfile(sdir, '.pid'), 30, 'probe');
cmd_exe = fullfile(getenv('SystemRoot'), 'System32', 'cmd.exe');
[ok7, err7] = tab.spawn_and_wait({sprintf('"%s" /c exit 0', cmd_exe)}, log_file, ...
    fullfile(sdir, '.cancel'), fullfile(sdir, '.pid'), 60, 'probe');
bat = fileread(fullfile(sdir, 'probe.bat'));
R6 = ~ok6 && contains(err6, '^') && ok7 && ~contains(bat, 'call ') && contains(bat, cmd_exe);
fprintf('R6: ^ batch refused (%s); exe without call ok=%d (%s) -> %s\n', err6, ok7, err7, tf(R6));
if R6, pass = pass + 1; else, fail = fail + 1; end

%% R7 the names a cut would use are known before it starts, and a taken one numbers them
croot = fullfile(work, 'cutroot');
mkdir(fullfile(croot, 'cut_tiffs_reconstruction_13h-05m-59s'));
capp = struct('file_info', struct('file', '12h-59m-35s.fits', 'name', '12h-59m-35s.fits', 'path', croot), ...
    'data', struct('reconstruction_path', fullfile(croot, '13h-05m-59s.fits')));
names = rabbit_cut_tiffs.cut_folder_names(capp);
suffix = rabbit_stack_io.next_free_suffix(croot, names);
R7 = isequal(names, {'cut_tiffs_om_12h-59m-35s', 'cut_tiffs_reconstruction_13h-05m-59s'}) && ...
    strcmp(suffix, '_01') && isempty(rabbit_stack_io.next_free_suffix(work, names));
fprintf('R7: %s, number %s -> %s\n', strjoin(names, ', '), suffix, tf(R7));
if R7, pass = pass + 1; else, fail = fail + 1; end

%% R8 A6 leaves the field band out of the silhouette on tissue
mask8 = false(60, 80);
mask8(10:50, 12:60) = true;                       % left edge 11 px from the border: a field edge for 32 px
band8 = rabbit_sfm_build.field_band(mask8, 32);
sil8 = false(60, 80);
sil8(12:48, 4:58) = true;                         % the mesh reaches past the field edge, into the band
s_band = rabbit_mesh_alignment.silhouette_scores(sil8, mask8, 2, band8);
s_none = rabbit_mesh_alignment.silhouette_scores(sil8, mask8, 2);
s_zero = rabbit_mesh_alignment.silhouette_scores(sil8, mask8, 2, rabbit_sfm_build.field_band(mask8, 0));
in_band = nnz(sil8 & band8);
R8 = in_band > 0 && ~any(band8(:) & mask8(:)) && abs(s_band.inside - 1) < 1e-12 && s_none.inside < 0.9 && ...
    abs(s_zero.inside - s_none.inside) < 1e-12 && s_band.edge == s_none.edge && s_band.covered == s_none.covered;
fprintf('R8: %d silhouette px in the band; on tissue %.3f with band, %.3f without, %.3f with band 0; edge %.2f/%.2f -> %s\n', ...
    in_band, s_band.inside, s_none.inside, s_zero.inside, s_band.edge, s_none.edge, tf(R8));
if R8, pass = pass + 1; else, fail = fail + 1; end

%% R9 a repeat cut is not refused any more
src9 = fileread(which('rabbit_cut_tiffs'));
R9 = ~contains(src9, 'was refused') && ~contains(src9, 'Choose another folder');
fprintf('R9: no refusal of a repeat cut in rabbit_cut_tiffs -> %s\n', tf(R9));
if R9, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_VIEW_FLIPS_AND_SILHOUETTES RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_view_flips_and_silhouettes %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_view_flips_and_silhouettes\n');
    error('probe_view_flips_and_silhouettes:Failed', '%d check(s) failed.', fail);
end
end


function write_txt(path, txt)
fid = fopen(path, 'w', 'n', 'UTF-8');
fwrite(fid, txt, 'char');
fclose(fid);
end

function [V, F] = small_mesh()
% a small square of two triangles in front of the cameras of write_model_txt
V = [-0.1 -0.1 0; 0.1 -0.1 0; -0.1 0.1 0; 0.1 0.1 0];
F = [1 2 3; 2 4 3];
end

function write_model_txt(folder, h, w)
% COLMAP text model: four PINHOLE cameras of h x w looking at the origin
% from 10 units, images named view<k>/a.png (the default bindings)
fid = fopen(fullfile(folder, 'cameras.txt'), 'w');
for k = 1:4
    fprintf(fid, '%d PINHOLE %d %d 400 400 %g %g\n', k, w, h, w / 2, h / 2);
end
fclose(fid);
fid = fopen(fullfile(folder, 'images.txt'), 'w');
for k = 1:4
    fprintf(fid, '%d 1 0 0 0 0 0 10 %d view%d/a.png\n\n', k, k, k);
end
fclose(fid);
fid = fopen(fullfile(folder, 'points3D.txt'), 'w');
fclose(fid);
end
