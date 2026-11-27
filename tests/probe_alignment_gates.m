function probe_alignment_gates
%% Probe: the alignment checks A2-A4 on a synthetic far-camera scene
% Collin Snitchler
% 15.10.2026
% A unit sphere seen by 8 pinhole cameras on a ring 20 units away (about
% 6 mesh diagonals, as far as the rabbit rig's cameras are in its own
% units), with sparse points on the sphere (0.5 px image noise) and, in
% some cases, sparse points off the heart (a shell 1.6 times larger, as
% the bath or the holder would give). Checks rabbit_mesh_alignment:
%   Q1 the aligned mesh with tissue masks PASSes A2, A3 and A4; the earlier
%      rules (cameras within 2 mesh diagonals, bounding-box IoU of all
%      sparse points >= 0.90) would have failed A3
%   Q2 with 200 off-heart sparse points and no masks every point is judged,
%      and A2 gives WARN, not PASS; with the masks the same scene PASSes
%   Q3 a mesh shifted by 10 % of its diagonal FAILs A2
%   Q4 a mesh scaled by 1.2 FAILs A2
%   Q5 a mesh so large that the cameras sit inside its box FAILs A3
%   Q6 the run continues on WARN: ok is true, the warnings name the check,
%      and the alignment JSON verdict is WARN
%   Q8 the A3 summary names the part that decided it, with one decimal:
%      a worst camera at 74.6 % reads "74.6 %" with the camera count and
%      image, never "75 %" next to the 75 % limit; a box-overlap WARN and
%      a camera inside the box are named; a PASS has no such lead
%   Q7 a mesh shrunk by 0.95 FAILs A6 (its outline leaves the tissue
%      outline) although it stays inside the masks; the aligned mesh
%      PASSes A6 (Q1), and without masks A6 is not measured (WARN)
%   Q9 alignment records whose transform says "S1 pinned registration"
%      (older records) or "pinned registration" (newer ones) both read back
%      unchanged through rabbit_reconstruction_tab.report_record, and the
%      record this code writes says "pinned registration"
% Usage: matlab -batch "addpath('<repo>/tests'); probe_alignment_gates" -noFigureWindows

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));
work = tempname;
mkdir(work);
cleanup = onCleanup(@() rmdir(work, 's'));

[V, F] = sphere_mesh(1, 0, 40);
scene_on = make_scene(fullfile(work, 'on'), V, F, 0, 11);        % sparse points on the sphere only
scene_off = make_scene(fullfile(work, 'off'), V, F, 200, 12);    % plus 200 off the heart

fprintf('Q1: aligned mesh, tissue masks: PASS (the earlier A3 rule fails here)\n');
r1 = run_case(scene_on, V, F, true, 'q1');
legacy_a3 = r1.gates.A3.measured.legacy_rule.pass;
Q1 = r1.ok && isempty(r1.warnings) && all(cellfun(@(g) strcmp(r1.gates.(g).verdict, 'PASS'), {'A2', 'A3', 'A4', 'A6'})) && ~legacy_a3;
fprintf('  A2 %s (%.0f %% matched), A3 %s (%.1f-%.1f diagonals), A4 %s; earlier A3 rule pass=%d -> %s\n', r1.gates.A2.verdict, ...
    100 * r1.gates.A2.measured.matched_fraction, r1.gates.A3.verdict, r1.gates.A3.measured.center_dist_diag_min, ...
    r1.gates.A3.measured.center_dist_diag_max, r1.gates.A4.verdict, legacy_a3, tf(Q1));
if Q1, pass = pass + 1; else, fail = fail + 1; end

fprintf('Q2: off-heart sparse points: WARN without masks, PASS with them\n');
r2a = run_case(scene_off, V, F, false, 'q2a');
r2b = run_case(scene_off, V, F, true, 'q2b');
Q2 = strcmp(r2a.gates.A2.verdict, 'WARN') && r2a.ok && strcmp(r2b.gates.A2.verdict, 'PASS') && r2b.ok && ...
    contains(r2a.gates.A1.measured.tissue_points, 'no tissue masks') && contains(r2b.gates.A1.measured.tissue_points, 'inside the tissue masks');
fprintf('  no masks: A2 %s (%.0f %% matched); masks: A2 %s (%.0f %% matched; %s) -> %s\n', r2a.gates.A2.verdict, ...
    100 * r2a.gates.A2.measured.matched_fraction, r2b.gates.A2.verdict, 100 * r2b.gates.A2.measured.matched_fraction, ...
    r2b.gates.A1.measured.tissue_points, tf(Q2));
if Q2, pass = pass + 1; else, fail = fail + 1; end

fprintf('Q3: mesh shifted by 10 %% of its diagonal: A2 FAIL\n');
dg = norm(max(V) - min(V));
r3 = run_case(scene_on, V + 0.10 * dg * [1 0 0], F, true, 'q3');
Q3 = ~r3.ok && strcmp(r3.gates.A2.verdict, 'FAIL') && contains(r3.err, 'projection error');
fprintf('  A2 %s (%.0f %% matched), ok=%d: %s -> %s\n', r3.gates.A2.verdict, 100 * r3.gates.A2.measured.matched_fraction, ...
    r3.ok, r3.err, tf(Q3));
if Q3, pass = pass + 1; else, fail = fail + 1; end

fprintf('Q4: mesh scaled by 1.2: A2 FAIL\n');
r4 = run_case(scene_on, 1.2 * V, F, true, 'q4');
Q4 = ~r4.ok && strcmp(r4.gates.A2.verdict, 'FAIL');
fprintf('  A2 %s (%.0f %% matched) -> %s\n', r4.gates.A2.verdict, 100 * r4.gates.A2.measured.matched_fraction, tf(Q4));
if Q4, pass = pass + 1; else, fail = fail + 1; end

fprintf('Q5: cameras inside the mesh box: A3 FAIL\n');
r5 = run_case(scene_on, 30 * V, F, true, 'q5');
Q5 = ~r5.ok && strcmp(r5.gates.A3.verdict, 'FAIL') && numel(r5.gates.A3.measured.cameras_inside_bbox) == 8;
fprintf('  A3 %s, %d cameras inside -> %s\n', r5.gates.A3.verdict, numel(r5.gates.A3.measured.cameras_inside_bbox), tf(Q5));
if Q5, pass = pass + 1; else, fail = fail + 1; end

fprintf('Q6: a WARN keeps the run going and is written down\n');
aj = jsondecode(fileread(fullfile(scene_off, 'q2a.json')));
Q6 = r2a.ok && isempty(r2a.err) && numel(r2a.warnings) >= 1 && contains(r2a.warnings{1}, 'Alignment check WARN - projection error (A2)') && ...
    strcmp(aj.verdict, 'WARN') && strcmp(aj.gates.A2.verdict, 'WARN');
fprintf('  ok=%d, verdict %s, warning: %s -> %s\n', r2a.ok, aj.verdict, strjoin(r2a.warnings, ' | '), tf(Q6));
if Q6, pass = pass + 1; else, fail = fail + 1; end

fprintf('Q7: mesh shrunk by 0.95: A6 FAIL; aligned A6 PASS; no masks A6 WARN (not measured)\n');
r7 = run_case(scene_on, 0.95 * V, F, true, 'q7');
Q7 = ~r7.ok && strcmp(r7.gates.A6.verdict, 'FAIL') && contains(r7.err, 'mesh outline') && ...
    r7.gates.A6.measured.inside_median > 0.99 && strcmp(r1.gates.A6.verdict, 'PASS') && ...
    strcmp(r2a.gates.A6.verdict, 'WARN') && contains(r2a.gates.A6.measured.summary, 'not measured');
fprintf('  shrunk: A6 %s (%s); aligned: A6 %s (%s); no masks: A6 %s -> %s\n', r7.gates.A6.verdict, ...
    r7.gates.A6.measured.summary, r1.gates.A6.verdict, r1.gates.A6.measured.summary, r2a.gates.A6.verdict, tf(Q7));
if Q7, pass = pass + 1; else, fail = fail + 1; end

%% Q8 the A3 summary names the deciding part with one decimal
L8 = struct('a3_pass_in_frame', 0.75, 'a3_fail_in_frame', 0.5, 'a3_warn_iou', 0.5);
nm = {'v1_f1.tiff', 'v2_f1.tiff', 'v3_f1.tiff'};
s_w = rabbit_mesh_alignment.a3_summary('WARN', [0.746; 0.96; 0.97], false(3, 1), false(3, 1), 0.63, [17; 17; 17], nm, L8);
s_o = rabbit_mesh_alignment.a3_summary('WARN', [0.9; 0.96; 0.97], false(3, 1), false(3, 1), 0.42, [17; 17; 17], nm, L8);
s_f = rabbit_mesh_alignment.a3_summary('FAIL', [0.9; 0.96; 0.97], [true; false; false], false(3, 1), 0.63, [0.2; 17; 17], nm, L8);
s_p = rabbit_mesh_alignment.a3_summary('PASS', [0.9; 0.96; 0.97], false(3, 1), false(3, 1), 0.63, [17; 17; 17], nm, L8);
Q8 = startsWith(s_w, '1 camera(s) see less than 75.0 % of the mesh in frame, the worst 74.6 % (image v1_f1.tiff)') && ...
    contains(s_w, 'mesh in frame 74.6 % (worst camera)') && ~contains(s_w, ' 75 %') && ...
    startsWith(s_o, 'the robust box overlap of mesh and tissue points is 0.42 (WARN below 0.50)') && ...
    startsWith(s_f, '1 camera(s) inside the mesh box (FAIL)') && startsWith(s_p, '3 cameras:');
fprintf('Q8: A3 summaries:\n  WARN: %s\n  box: %s\n  FAIL: %s\n  PASS: %s\n  -> %s\n', s_w, s_o, s_f, s_p, tf(Q8));
if Q8, pass = pass + 1; else, fail = fail + 1; end

fprintf('Q9: records saved with "S1 pinned registration" and with "pinned registration" both read back\n');
tail9 = [': the run consumes the reference sparse model, so the mesh and the sparse model share the ' ...
    'world frame by construction; native COLMAP units preserved; no similarity normalization ' ...
    '(S2/Umeyama 1991 not used); no ICP (A5))'];
words9 = {'identity (S1 pinned registration', 'identity (pinned registration'};
tab9 = rabbit_reconstruction_tab();
Q9 = contains(aj.transform, 'pinned registration');
for k9 = 1:numel(words9)
    rec9 = jsondecode(fileread(fullfile(scene_off, 'q2a.json')));
    rec9.transform = [words9{k9} tail9];
    run9 = fullfile(work, sprintf('run9_%d', k9));
    mkdir(fullfile(run9, 'outputs'));
    fid = fopen(fullfile(run9, 'outputs', 'alignment-gates.json'), 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(rec9));
    fclose(fid);
    a9 = tab9.report_record(run9, struct(), 'alignment', 'alignment-gates.json');
    ok9 = isstruct(a9) && isfield(a9, 'transform') && strcmp(a9.transform, rec9.transform) && ...
        strcmp(a9.verdict, 'WARN') && strcmp(a9.gates.A2.verdict, 'WARN');
    fprintf('  "%s...": read back %d\n', words9{k9}, ok9);
    Q9 = Q9 && ok9;
end
fprintf('  new record: %s -> %s\n', aj.transform, tf(Q9));
if Q9, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_ALIGNMENT_GATES RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_alignment_gates %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_alignment_gates\n');
    error('probe_alignment_gates:Failed', '%d check(s) failed.', fail);
end
end


function r = run_case(scene, V, F, use_masks, tag)
% rabbit_mesh_alignment.run on the scene with the given mesh
mesh = fullfile(scene, [tag '.ply']);
rabbit_mesh_cleanup.write_ply(mesh, V, zeros(size(V)), zeros(size(V), 'uint8'), F);
masks = '';
if use_masks, masks = fullfile(scene, 'masks'); end
r = rabbit_mesh_alignment.run(fullfile(scene, 'fused.ply'), fullfile(scene, 'fused.ply.vis'), ...
    fullfile(scene, 'sparse', 'images.bin'), struct('mesh_ply', mesh, 'mask_root', masks, ...
    'out_json', fullfile(scene, [tag '.json']), 'out_rebuilt', fullfile(scene, [tag '_rebuilt.ply'])));
end


function scene = make_scene(scene, V, F, n_off, seed)
% COLMAP binary model (8 PINHOLE cameras on a ring), a fused cloud on the sphere and one tissue mask per image
rng(seed);
mkdir(fullfile(scene, 'sparse'));
mkdir(fullfile(scene, 'masks'));
f = 4000; w = 1000; h = 1000; nc = 8; dist = 20;
cams = struct('R', {}, 't', {}, 'C', {}, 'name', {});
for k = 1:nc
    a = 2 * pi * (k - 1) / nc;
    C = dist * [cos(a) sin(a) 0.15];
    z = -C / norm(C);
    x = cross([0 0 1], z); x = x / norm(x);
    y = cross(z, x);
    R = [x; y; z];
    cams(k) = struct('R', R, 't', -R * C', 'C', C, 'name', sprintf('cam%d.png', k));
end
% sparse points: 400 on the sphere (0.2 % radial noise), n_off on a 1.6x shell
n_on = 400;
P = randn(n_on, 3); P = P ./ vecnorm(P, 2, 2) .* (1 + 0.002 * randn(n_on, 1));
Q = randn(n_off, 3); Q = 1.6 * Q ./ vecnorm(Q, 2, 2);
X = [P; Q];
obs = cell(nc, 1); track = cell(size(X, 1), 1);
for i = 1:size(X, 1)
    for k = 1:nc
        nrm = X(i, :) / norm(X(i, :));
        if dot(nrm, cams(k).C - X(i, :)) <= 0.3 * norm(cams(k).C - X(i, :)), continue; end % front side only
        xc = cams(k).R * X(i, :)' + cams(k).t;
        uv = [f * xc(1) / xc(3) + w / 2, f * xc(2) / xc(3) + h / 2] + 0.5 * randn(1, 2);
        obs{k}(end + 1, :) = [uv i];
        track{i}(end + 1, :) = [k size(obs{k}, 1) - 1];
    end
end
keep = cellfun(@(t) size(t, 1) >= 2, track);
% cameras.bin (one PINHOLE camera, model id 1)
fid = fopen(fullfile(scene, 'sparse', 'cameras.bin'), 'w');
fwrite(fid, 1, 'uint64'); fwrite(fid, 1, 'int32'); fwrite(fid, 1, 'int32');
fwrite(fid, [w h], 'uint64'); fwrite(fid, [f f w / 2 h / 2], 'double');
fclose(fid);
% images.bin
fid = fopen(fullfile(scene, 'sparse', 'images.bin'), 'w');
fwrite(fid, nc, 'uint64');
for k = 1:nc
    fwrite(fid, k, 'int32'); fwrite(fid, rot2qvec(cams(k).R), 'double'); fwrite(fid, cams(k).t, 'double');
    fwrite(fid, 1, 'int32'); fwrite(fid, [uint8(cams(k).name) 0], 'uint8');
    o = obs{k};
    fwrite(fid, size(o, 1), 'uint64');
    for j = 1:size(o, 1)
        fwrite(fid, o(j, 1:2), 'double');
        pid = int64(o(j, 3)); if ~keep(o(j, 3)), pid = int64(-1); end
        fwrite(fid, pid, 'int64');
    end
end
fclose(fid);
% points3D.bin
fid = fopen(fullfile(scene, 'sparse', 'points3D.bin'), 'w');
fwrite(fid, sum(keep), 'uint64');
for i = find(keep)'
    fwrite(fid, i, 'uint64'); fwrite(fid, X(i, :), 'double'); fwrite(fid, [128 128 128], 'uint8');
    fwrite(fid, 0.5, 'double'); fwrite(fid, size(track{i}, 1), 'uint64');
    fwrite(fid, track{i}', 'int32');
end
fclose(fid);
% fused cloud on the sphere (spacing only matters for the record)
D = randn(20000, 3); D = D ./ vecnorm(D, 2, 2);
rabbit_mesh_cleanup.write_ply(fullfile(scene, 'fused.ply'), D, D, zeros(size(D), 'uint8'), zeros(0, 3));
fid = fopen(fullfile(scene, 'fused.ply.vis'), 'w'); fwrite(fid, 0, 'uint64'); fclose(fid);
% tissue masks: the sphere's silhouette, dilated by 4 px
for k = 1:nc
    xc = V * cams(k).R' + cams(k).t';
    u = f * xc(:, 1) ./ xc(:, 3) + w / 2; v = f * xc(:, 2) ./ xc(:, 3) + h / 2;
    hull = convhull(u, v);
    m = poly2mask(u(hull) + 0.5, v(hull) + 0.5, h, w);
    m = imdilate(m, strel('disk', 4, 0));
    imwrite(m, fullfile(scene, 'masks', [cams(k).name '.png']));
end
end


function q = rot2qvec(R)
% Rotation matrix -> COLMAP quaternion [w x y z] (w >= 0)
t = trace(R);
if t > 0
    s = 2 * sqrt(t + 1);
    q = [s / 4, (R(3, 2) - R(2, 3)) / s, (R(1, 3) - R(3, 1)) / s, (R(2, 1) - R(1, 2)) / s];
elseif R(1, 1) > R(2, 2) && R(1, 1) > R(3, 3)
    s = 2 * sqrt(1 + R(1, 1) - R(2, 2) - R(3, 3));
    q = [(R(3, 2) - R(2, 3)) / s, s / 4, (R(1, 2) + R(2, 1)) / s, (R(1, 3) + R(3, 1)) / s];
elseif R(2, 2) > R(3, 3)
    s = 2 * sqrt(1 + R(2, 2) - R(1, 1) - R(3, 3));
    q = [(R(1, 3) - R(3, 1)) / s, (R(1, 2) + R(2, 1)) / s, s / 4, (R(2, 3) + R(3, 2)) / s];
else
    s = 2 * sqrt(1 + R(3, 3) - R(1, 1) - R(2, 2));
    q = [(R(2, 1) - R(1, 2)) / s, (R(1, 3) + R(3, 1)) / s, (R(2, 3) + R(3, 2)) / s, s / 4];
end
if q(1) < 0, q = -q; end
end


function [V, F] = sphere_mesh(r, z0, n)
% Triangulated sphere of radius r centred on (0, 0, z0), duplicate seam and pole vertices merged
[x, y, z] = sphere(n);
fv = surf2patch(r * x, r * y, r * z + z0, 'triangles');
[V, ~, j] = unique(round(fv.vertices, 12), 'rows');
F = j(fv.faces);
F = F(F(:, 1) ~= F(:, 2) & F(:, 2) ~= F(:, 3) & F(:, 1) ~= F(:, 3), :);
end
