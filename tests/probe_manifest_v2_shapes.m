function probe_manifest_v2_shapes
%% Strict JSON collection shapes in v2 manifests
% Collin Snitchler
% 12.09.2026
% Check IDs: V2S<n> is check n of this probe (V2S0 the valid control); the
% prefix only groups them.
%Each malformed case is v2-only so the sibling-independent validator is
%exercised before any restore state can be committed. The valid control uses
%JSON arrays for every list-valued field; malformed cases replace one array
%with an object or scalar collection.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

fprintf('V2S0: valid v2-only collection shapes open\n');
[ok0, err0] = run_case('valid', @(m) m);
V2S0 = ok0;
fprintf('  open=%s err=%s -> %s\n', tf(ok0), err0, tf(V2S0));
if V2S0, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S1: empty roles must remain a JSON array, not an object\n');
[ok1, err1] = run_case('roles_object', @(m) set_roles_object(m));
V2S1 = ~ok1 && ~isempty(err1);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok1), err1, tf(V2S1));
if V2S1, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S2: snapshot must be an array of records\n');
[ok2, err2] = run_case('snapshot_object', @(m) set_snapshot_object(m));
V2S2 = ~ok2 && ~isempty(err2);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok2), err2, tf(V2S2));
if V2S2, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S3: derived_chain must be an array of records\n');
[ok3, err3] = run_case('chain_object', @(m) set_chain_object(m));
V2S3 = ~ok3 && ~isempty(err3);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok3), err3, tf(V2S3));
if V2S3, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S4: stages must be an array, even for one stage\n');
[ok4, err4] = run_case('stages_object', @(m) set_stages_object(m));
V2S4 = ~ok4 && ~isempty(err4);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok4), err4, tf(V2S4));
if V2S4, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S5: nested stage collections must be arrays\n');
[ok5, err5] = run_case('nested_object', @(m) set_nested_object(m));
V2S5 = ~ok5 && ~isempty(err5);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok5), err5, tf(V2S5));
if V2S5, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S6: derived-operation collections must be arrays\n');
[ok6, err6] = run_case('operation_object', @(m) set_operation_object(m));
V2S6 = ~ok6 && ~isempty(err6);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok6), err6, tf(V2S6));
if V2S6, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S7: nested artifact elements must carry path and digest\n');
[ok7, err7] = run_case('artifact_empty_record', @(m) set_artifact_empty_record(m));
V2S7 = ~ok7 && ~isempty(err7);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok7), err7, tf(V2S7));
if V2S7, pass = pass + 1; else, fail = fail + 1; end

fprintf('V2S8: character-form stage artefacts are malformed\n');
[ok8, err8] = run_case('artifact_character_path', @(m) set_artifact_character_path(m));
V2S8 = ~ok8 && ~isempty(err8);
fprintf('  rejects=%s err=%s -> %s\n', tf(~ok8), err8, tf(V2S8));
if V2S8, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_V2_SHAPES RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_v2_shapes %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_v2_shapes\n');
end
end

function m = base_manifest(root)
run_id = '20260912T120000_01234567';
stage = struct('name', 'image_undistorter', 'status', 'RUNNING', ...
    'started_at', '2026-09-12T12:00:00Z', 'finished_at', '');
ri = struct();
ri.snapshot = {struct('path', 'inputs/a.bin', ...
    'sha256', repmat('a', 1, 64), 'size', 1)};
ri.roles = [];
ri.original_locations_recorded = false;
r = struct();
r.inputs = ri;
r.selected_run = run_id;
r.derived_chain = {};
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v2';
m.run_id = run_id;
m.converted_from = repmat('a', 1, 64);
m.converted_at = '2026-09-12T12:00:00Z';
m.converted_at_basis = m.converted_at;
m.restore = r;
m.dataset = struct('role', 'reconstruction', 'path', root);
m.inputs = struct('files', []);
m.stages = {stage};
m.result = struct('status', 'CREATED');
end

function [ok, err] = run_case(name, mutate)
root = tempname;
mkdir(root);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>
run_id = '20260912T120000_01234567';
run_dir = fullfile(root, 'subset.matom', 'reconstruction', 'runs', run_id);
mkdir(run_dir);
m = mutate(base_manifest(root));
p = fullfile(run_dir, 'manifest.v2.json');
fid = fopen(p, 'wb');
if fid < 0
    ok = false; err = 'could not create fixture'; return;
end
fwrite(fid, jsonencode(m), 'char*1');
fclose(fid);
tab = rabbit_reconstruction_tab();
[ok, err] = tab.open_manifest(p);
end

function m = set_roles_object(m)
m.restore.inputs.roles = struct();
end

function m = set_snapshot_object(m)
m.restore.inputs.snapshot = struct('path', 'inputs/a.bin', ...
    'sha256', repmat('a', 1, 64), 'size', 1);
end

function m = set_chain_object(m)
m.restore.derived_chain = struct('kind', 'touchups', 'id', 'x', ...
    'output_ply', '', 'source_ply', '', 'created_at', '');
end

function m = set_stages_object(m)
m.stages = m.stages{1};
end

function m = set_nested_object(m)
st = m.stages{1};
st.validation = struct('checks', struct('name', 'ok', 'ok', true));
st.warnings = struct('message', 'warning');
m.stages = {st};
end

function m = set_operation_object(m)
m.touchups = {struct('id', 'x', 'operations', struct('name', 'bad'))};
end

function m = set_artifact_empty_record(m)
st = m.stages{1};
st.artifacts = {struct()};
m.stages = {st};
end

function m = set_artifact_character_path(m)
st = m.stages{1};
st.artifacts = 'outputs/not-a-record.ply';
m.stages = {st};
end

function cleanup_case(root)
if exist(root, 'dir')
    rmdir(root, 's');
end
end
