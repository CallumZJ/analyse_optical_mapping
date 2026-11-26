function probe_failed_run_open
%% Probe: a run that stopped before its later steps opens as FAILED, not unreadable
% Collin Snitchler
% 15.10.2026
% The full GUI run on the July data stopped at the alignment check; the run
% had its dense cloud and mesh but no activation_projected.ply, and
% open_manifest refused it as "missing referenced artefacts", so the app
% listed it as UNREADABLE and said it was running in another session.
%   F1 a FAILED run with the cloud and mesh but no projected PLY opens, with
%      status FAILED
%   F2 the same for a CANCELLED run
%   F3 a COMPLETED run without the projected PLY is still refused
%   F4 a FAILED run whose present mesh PLY is malformed is still refused
% Usage: matlab -batch "addpath('<repo>/tests'); probe_failed_run_open" -noFigureWindows
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));
root = tempname(tempdir);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

[ok1, err1, info1] = open_case(root, 'f1', 'FAILED', true);
F1 = ok1 && strcmp(info1.result_status, 'FAILED');
fprintf('F1: FAILED without projected PLY opens: %s (%s)\n', tf(F1), err1);
if F1, pass = pass + 1; else, fail = fail + 1; end

[ok2, err2, info2] = open_case(root, 'f2', 'CANCELLED', true);
F2 = ok2 && strcmp(info2.result_status, 'CANCELLED');
fprintf('F2: CANCELLED without projected PLY opens: %s (%s)\n', tf(F2), err2);
if F2, pass = pass + 1; else, fail = fail + 1; end

[ok3, err3] = open_case(root, 'f3', 'COMPLETED', true);
F3 = ~ok3 && contains(err3, 'activation_projected.ply');
fprintf('F3: COMPLETED without projected PLY is refused: %s (%s)\n', tf(F3), err3);
if F3, pass = pass + 1; else, fail = fail + 1; end

[ok4, err4] = open_case(root, 'f4', 'FAILED', false);
F4 = ~ok4;
fprintf('F4: FAILED with a malformed mesh PLY is refused: %s (%s)\n', tf(F4), err4);
if F4, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_FAILED_RUN_OPEN RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_failed_run_open %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_failed_run_open\n');
    error('probe_failed_run_open:Failed', '%d check(s) failed.', fail);
end
end


function [ok, err, info] = open_case(root, name, status, good_mesh)
% A run folder with the dense cloud and the mesh (no reprojection) and a v1 manifest of the given status
run_id = '20261015T120000_0f0e0d0c';
run_dir = fullfile(root, name, 'case.matom', 'reconstruction', 'runs', run_id);
out_dir = fullfile(run_dir, 'outputs');
mkdir(out_dir);
write_text(fullfile(out_dir, 'fused-geometric.ply'), sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 0\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n']));
mesh = sprintf(['ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n' ...
    'element face 1\nproperty list uchar int vertex_indices\nend_header\n10 0 0\n11 0 0\n10 1 0\n3 0 1 2\n']);
if ~good_mesh, mesh = 'ply\nnot a mesh\n'; end
write_text(fullfile(out_dir, 'mesh-cleanup.ply'), mesh);
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = run_id;
m.dataset = struct('role', 'reconstruction', 'path', fullfile(root, name));
m.inputs = struct('files', []);
m.stages = struct('name', {'mesh_cleanup', 'alignment'}, 'status', {'WARNED', status}, ...
    'started_at', {'2026-10-15T12:00:00', '2026-10-15T12:01:00'}, ...
    'finished_at', {'2026-10-15T12:01:00', '2026-10-15T12:02:00'});
if strcmp(status, 'COMPLETED'), m.stages(2).status = 'PASSED'; end
m.result = struct('status', status);
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m, 'PrettyPrint', true));
tab = rabbit_reconstruction_tab();
[ok, err, info] = tab.open_manifest(fullfile(run_dir, 'manifest.json'));
end


function write_text(path, text)
fid = fopen(path, 'wb');
fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
fclose(fid);
end
