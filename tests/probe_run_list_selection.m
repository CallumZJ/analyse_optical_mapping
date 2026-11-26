function probe_run_list_selection
%% Probe: the selected run stays selected when the run list is refreshed
% Collin Snitchler
% 15.10.2026
% In the full GUI run on the July data, a second run finished, the results
% named it, but the run list (and with it Visualise, Resume and Reproject)
% was back on the first run: the list's line of the selected run changed
% (its status in brackets) and a list box whose value is no longer one of
% its items falls back to the first item.
%   L1 the second of two runs is selected; its status changes; after the
%      list refresh the second run is still selected
%   L2 a refresh with no change keeps the selection too
% Needs OM_APP_HEADLESS=1 (no windows).
% Usage: matlab -batch "addpath('<repo>/tests'); probe_run_list_selection" -noFigureWindows
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));
root = tempname(tempdir);
ids = {'20261015T120000_0a0a0a0a', '20261015T130000_0b0b0b0b'};
rec = fullfile(root, 'case.matom', 'reconstruction');
for k = 1:2
    make_run(fullfile(rec, 'runs', ids{k}), ids{k}, root);
end
state = struct('state_schema_version', 1, 'recipe_version', 1, 'runs', ...
    struct('id', ids, 'status', {'FAILED', 'FAILED'}, 'created_at', {'2026-10-15T12:00:00', '2026-10-15T13:00:00'}));
write_text(fullfile(rec, 'tab-state.json'), jsonencode(state, 'PrettyPrint', true));

app = analyse_optical_mapping();
cleanup = onCleanup(@() close_case(app, root)); %#ok<NASGU>
app.recon.test_manifest_pick = fullfile(rec, 'runs', ids{2}, 'manifest.json');
app.recon.OpenReconstructionManifestMenuSelected();
items = app.recon.ReconstructionRunList.Items;
k2 = find(startsWith(items, ids{2}), 1);
app.recon.ReconstructionRunList.Value = items{k2};
before = app.recon.reconstruction_selected_run_id();

% The second run's status changes on disk (its line in the list changes)
m = jsondecode(fileread(fullfile(rec, 'runs', ids{2}, 'manifest.json')));
m.result.status = 'CANCELLED';
write_text(fullfile(rec, 'runs', ids{2}, 'manifest.json'), jsonencode(m, 'PrettyPrint', true));
app.recon.reconstruction_update_run_list();
after = app.recon.reconstruction_selected_run_id();
L1 = strcmp(before, ids{2}) && strcmp(after, ids{2}) && ...
    any(contains(app.recon.ReconstructionRunList.Items, [ids{2} ' [']));
fprintf('L1: selected %s before, %s after the status change (items: %s) -> %s\n', before, after, ...
    strjoin(app.recon.ReconstructionRunList.Items, ' / '), tf(L1));
if L1, pass = pass + 1; else, fail = fail + 1; end

app.recon.reconstruction_update_run_list();
L2 = strcmp(app.recon.reconstruction_selected_run_id(), ids{2});
fprintf('L2: a refresh without change keeps %s -> %s\n', app.recon.reconstruction_selected_run_id(), tf(L2));
if L2, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_RUN_LIST_SELECTION RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_run_list_selection %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_run_list_selection\n');
    error('probe_run_list_selection:Failed', '%d check(s) failed.', fail);
end
end


function make_run(run_dir, run_id, root)
% A FAILED run with a dense cloud and a mesh (no reprojection), v1 manifest
out_dir = fullfile(run_dir, 'outputs');
mkdir(out_dir);
write_text(fullfile(out_dir, 'fused-geometric.ply'), sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 0\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n']));
write_text(fullfile(out_dir, 'mesh-cleanup.ply'), sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 1\nproperty list uchar int vertex_indices\nend_header\n10 0 0\n11 0 0\n10 1 0\n3 0 1 2\n']));
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = run_id;
m.dataset = struct('role', 'reconstruction', 'path', root);
m.inputs = struct('files', []);
m.stages = struct('name', {'mesh_cleanup', 'alignment'}, 'status', {'WARNED', 'FAILED'}, ...
    'started_at', {'2026-10-15T12:00:00', '2026-10-15T12:01:00'}, ...
    'finished_at', {'2026-10-15T12:01:00', '2026-10-15T12:02:00'});
m.result = struct('status', 'FAILED');
write_text(fullfile(run_dir, 'manifest.json'), jsonencode(m, 'PrettyPrint', true));
end


function write_text(path, text)
fid = fopen(path, 'wb');
fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
fclose(fid);
end


function close_case(app, root)
try, close all force; catch, end
if isvalid(app), delete(app); end
if isfolder(root), rmdir(root, 's'); end
end
