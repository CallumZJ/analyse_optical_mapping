function probe_manifest_ply_payloads
%% Malformed PLY payloads are rejected before the state is committed
% Collin Snitchler
% 12.09.2026
% Opens copies of the golden run with broken PLY files; each open must fail.
% Needs the golden run at golden_root.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_ply_payloads');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
gdir = fullfile(golden_root, 'subset.matom', 'reconstruction', 'runs', golden_run);
pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

fprintf('P1: malformed ASCII vertex payload is rejected\n');
r1 = make_case(gdir, 'bad_ascii');
write_text(fullfile(r1, 'outputs', 'reprojection', 'activation_projected.ply'), sprintf([ ...
    'ply\nformat ascii 1.0\nelement vertex 1\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 0\nproperty list uchar int vertex_indices\n' ...
    'end_header\nnot-a-vertex\n']));
t1 = rabbit_reconstruction_tab();
[ok1, err1] = t1.open_manifest(fullfile(r1, 'manifest.json'));
P1 = ~ok1 && ~isempty(err1);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok1), err1, tf(P1));
if P1, pass = pass + 1; else, fail = fail + 1; end

fprintf('P2: out-of-range ASCII face index is rejected\n');
r2 = make_case(gdir, 'bad_face_index');
write_text(fullfile(r2, 'outputs', 'reprojection', 'activation_projected.ply'), sprintf([ ...
    'ply\nformat ascii 1.0\nelement vertex 1\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 1\nproperty list uchar int vertex_indices\n' ...
    'end_header\n0 0 0\n3 0 0 1\n']));
t2 = rabbit_reconstruction_tab();
[ok2, err2] = t2.open_manifest(fullfile(r2, 'manifest.json'));
P2 = ~ok2 && ~isempty(err2);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok2), err2, tf(P2));
if P2, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_PLY_PAYLOADS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_ply_payloads %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_ply_payloads\n');
end
end

function run_dir = make_case(gdir, tag)
root = fullfile(tempdir, ['c22a_ply_' tag '_' char(java.util.UUID.randomUUID())]);
run_dir = fullfile(root, 'subset.matom', 'reconstruction', 'runs', '20260909T110043_d091bb44');
rundir = run_dir;
mkdir(fileparts(rundir));
copyfile(gdir, rundir);
end

function write_text(path, txt)
fid = fopen(path, 'wb');
assert(fid >= 0, 'could not create scratch PLY');
fwrite(fid, unicode2native(txt, 'UTF-8'), 'uint8');
fclose(fid);
end
