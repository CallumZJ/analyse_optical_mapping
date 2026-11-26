function probe_restore_records
%% Restore records in a converted v2 manifest
% Collin Snitchler
% 13.09.2026
% Converting a v1 manifest gives explicit phase-1 revisions and UNAVAILABLE
% restore records, and the camera record is validated. Uses a temporary v1
% manifest only, no external fixture.
% Check IDs: B2R<n> is check n of this probe; the prefix only groups them.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));
root = tempname;
mkdir(root);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>
run_id = '20260913T010000_01234567';
run_dir = fullfile(root, 'sample.matom', 'reconstruction', 'runs', run_id);
mkdir(run_dir);
write_v1(fullfile(run_dir, 'manifest.json'), run_id, root);

tab = rabbit_reconstruction_tab();
[bytes, report] = tab.convert_v1_to_v2(fullfile(run_dir, 'manifest.json'), run_dir);
m2 = jsondecode(bytes);

fprintf('B2R1: converted v2 carries explicit phase-1 revisions and unavailable restore records\n');
B2R1 = isfield(m2, 'phase1_revision') && strcmp(m2.phase1_revision, '0') && ...
    isfield(m2, 'field_revisions') && strcmp(m2.field_revisions.activation_map, '0') && ...
    strcmp(m2.field_revisions.camera, '0') && ...
    isfield(m2, 'restore') && isfield(m2.restore, 'activation_map') && ...
    strcmp(m2.restore.activation_map.status, 'UNAVAILABLE') && ...
    strcmp(m2.restore.activation_map.reason, 'NO_OM_STACK') && ...
    strcmp(m2.restore.activation_map.detail, 'no_om_stack') && ...
    isfield(m2.restore, 'camera') && strcmp(m2.restore.camera.status, 'UNAVAILABLE') && ...
    strcmp(m2.restore.camera.reason, 'NO_CAMERA_STATE') && ...
    strcmp(m2.restore.camera.detail, 'no_camera_state') && ...
    ~isempty(report.converted_from);
fprintf('  result=%s\n', tf(B2R1));
if B2R1, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R2: camera capture validates shared camera and three role limits\n');
cam = struct('position', [1 2 3], 'target', [0 0 0], 'up', [0 0 1], ...
    'view_angle', 45, 'limits', struct(...
    'fused', struct('x', [-1 1], 'y', [-2 2], 'z', [-3 3]), ...
    'rebuilt', struct('x', [-4 4], 'y', [-5 5], 'z', [-6 6]), ...
    'projected', struct('x', [-7 7], 'y', [-8 8], 'z', [-9 9])));
[cok, cerr, wire] = tab.validate_camera_state(cam);
B2R2 = cok && isempty(cerr) && strcmp(wire.status, 'AVAILABLE') && ...
    strcmp(wire.camera_schema, 'camera-v1') && numel(wire.camera.limits.axes) == 3;
fprintf('  result=%s err=%s\n', tf(B2R2), cerr);
if B2R2, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R3: activation map uses canonical NaN/signed-zero digest and closed provenance fields\n');
map = single([1 NaN; -0 2]);
prov = struct('map_kind', 'activation_time', 'units', 'ms', ...
    'method', struct('name', 'activation_time_pipeline', 'version', 'method-v1', ...
    'parameters_json', method_parameters_json(tab), 'parameters_sha256', repmat('0', 1, 64)), ...
    'time_reference', struct('kind', 'relative_to_first_frame', ...
    'anchor_frame', '1', 'applied_offset_ms', '0000000000000000', 'parent', []), ...
    'recording_identity', struct(), 'geometry', struct(), ...
    'geometry_digest', repmat('0', 1, 64), ...
    'projection_contract', struct(), ...
    'projection_contract_digest', repmat('0', 1, 64), ...
    'target_mesh_digest', repmat('1', 1, 64));
prov.method.parameters_sha256 = tab.restore_domain_digest( ...
    'OM-ACTIVATION-METHOD', 'method-v1', jsondecode(prov.method.parameters_json));
[aok, aerr, awire] = tab.validate_activation_state(map, prov);
B2R3 = aok && isempty(aerr) && strcmp(awire.map_digest, ...
    '57712e409e8978f37fd6f50fdd9cd0cf0c294042acac1cca84c38ae89c6d671b') && ...
    strcmp(awire.map_summary.finite_count, '3') && ...
    strcmp(awire.map_summary.nan_count, '1') && strcmp(awire.projected_output.status, 'UNAVAILABLE');
fprintf('  result=%s err=%s\n', tf(B2R3), aerr);
if B2R3, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R4: unsupported units and all-NaN maps are explicit non-fatal failures\n');
prov_bad = prov; prov_bad.units = 'V';
[bok, berr, ~] = tab.validate_activation_state(map, prov_bad);
all_nan = single([NaN NaN]);
[nok, nerr, ~] = tab.validate_activation_state(all_nan, prov);
B2R4 = ~bok && contains(berr, 'UNSUPPORTED_UNITS') && ~nok && contains(nerr, 'NO_FINITE_VALUES');
fprintf('  result=%s units=%s nan=%s\n', tf(B2R4), berr, nerr);
if B2R4, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R5: camera-only restore uses whole-sidecar CAS and increments only camera revision\n');
[swok, swerr] = tab.write_sidecar_after_commit(run_dir, bytes);
[dhok, before_sha, dherr] = tab.manifest_bytes_sha256(fullfile(run_dir, 'manifest.v2.json'));
[pok, perr, pres] = tab.persist_restore_fields(run_dir, [], wire, before_sha, '0');
active = jsondecode(tab.read_sidecar_bytes(run_dir));
[stale_ok, stale_err, ~] = tab.persist_restore_fields(run_dir, [], wire, before_sha, '0');
B2R5 = swok && isempty(swerr) && dhok && isempty(dherr) && pok && isempty(perr) && ...
    strcmp(pres.status, 'AVAILABLE') && strcmp(active.phase1_revision, '1') && ...
    strcmp(active.field_revisions.activation_map, '0') && strcmp(active.field_revisions.camera, '1') && ...
    strcmp(active.restore.activation_map.status, 'UNAVAILABLE') && ...
    strcmp(active.restore.camera.status, 'AVAILABLE') && ~stale_ok && ...
    contains(stale_err, 'WRITE_CONFLICT');
fprintf('  result=%s first=%s stale=%s\n', tf(B2R5), perr, stale_err);
if B2R5, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R6: activation AVAILABLE wire persists with independent field revision\n');
[sha2_ok, sha2, sha2_err] = tab.manifest_bytes_sha256(fullfile(run_dir, 'manifest.v2.json'));
[before2, before2_ok] = tab.read_manifest_json(fullfile(run_dir, 'manifest.v2.json'));
fprintf('  current-before-activation ok=%s rev=%s sha=%s\n', tf(before2_ok), char(before2.phase1_revision), sha2);
[pok2, perr2, pres2] = tab.persist_restore_fields(run_dir, awire, [], sha2, '1');
[active2, active2_ok] = tab.read_manifest_json(fullfile(run_dir, 'manifest.v2.json'));
B2R6 = sha2_ok && isempty(sha2_err) && pok2 && isempty(perr2) && active2_ok && ...
    strcmp(active2.restore.activation_map.status, 'AVAILABLE') && ...
    strcmp(active2.field_revisions.activation_map, '1') && ...
    strcmp(active2.field_revisions.camera, '1') && strcmp(active2.phase1_revision, '2') && ...
    strcmp(pres2.status, 'AVAILABLE');
fprintf('  result=%s err=%s\n', tf(B2R6), perr2);
if B2R6, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R7: activation mutation invalidates projected output before reprojection\n');
[pmok, pmerr, pending] = tab.mark_activation_mutation_pending(awire);
[sha3_ok, sha3, sha3_err] = tab.manifest_bytes_sha256(fullfile(run_dir, 'manifest.v2.json'));
[pok3, perr3, pres3] = tab.persist_restore_fields(run_dir, pending, [], sha3, '2');
[active3, active3_ok] = tab.read_manifest_json(fullfile(run_dir, 'manifest.v2.json'));
B2R7 = pmok && isempty(pmerr) && sha3_ok && isempty(sha3_err) && pok3 && isempty(perr3) && active3_ok && ...
    strcmp(pending.status, 'MUTATION_PENDING_REPROJECTION') && ...
    strcmp(pending.projected_output.status, 'UNAVAILABLE') && ...
    strcmp(active3.restore.activation_map.status, 'MUTATION_PENDING_REPROJECTION') && ...
    strcmp(active3.field_revisions.activation_map, '2') && strcmp(active3.phase1_revision, '3') && ...
    strcmp(pres3.status, 'MUTATION_PENDING_REPROJECTION');
fprintf('  result=%s err=%s\n', tf(B2R7), perr3);
if B2R7, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R8: activation restore rejects recording-identity mismatch without inference\n');
[compat_ok, compat_err, ~] = tab.validate_activation_compatibility(awire, prov);
bad_prov = prov; bad_prov.recording_identity = struct('source', 'different-recording');
[bad_ok, bad_err, bad_status] = tab.validate_activation_compatibility(awire, bad_prov);
B2R8 = compat_ok && isempty(compat_err) && ~bad_ok && contains(bad_err, 'IDENTITY_MISMATCH') && ...
    strcmp(bad_status.reason, 'IDENTITY_MISMATCH') && strcmp(bad_status.detail, 'recording_identity_mismatch');
fprintf('  result=%s err=%s\n', tf(B2R8), bad_err);
if B2R8, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R9: activation validation builds file identity and preserves the frame map\n');
identity_file = fullfile(root, 'activation.bin');
fid_identity = fopen(identity_file, 'wb');
fwrite(fid_identity, uint8([3 1 4 1 5 9]), 'uint8');
fclose(fid_identity);
prov_file = prov;
prov_file = rmfield(prov_file, 'recording_identity');
prov_file.recording_file = struct('file', identity_file, 'dimensions', [1 2 3], ...
    'frame_map', struct('acquisition_frame', {'1', '2', '3'}, ...
    'source_frame', {'11', '12', '13'}));
[file_ok, file_err, file_wire] = tab.validate_activation_state(single([1 2 3]), prov_file);
B2R9 = file_ok && isempty(file_err) && isfield(file_wire.recording_identity, 'source_type') && ...
    strcmp(file_wire.recording_identity.source_type, 'file') && ...
    numel(file_wire.recording_identity.members.frame_map) == 3 && ...
    isfield(file_wire, 'provenance_digest') && ...
    numel(file_wire.provenance_digest) == 64;
fprintf('  result=%s err=%s\n', tf(B2R9), file_err);
if B2R9, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R10: activation validation rebases workspace identities in acquisition order\n');
workspace_a = fullfile(root, 'workspace_a.bin');
workspace_b = fullfile(root, 'workspace_b.bin');
write_bytes(workspace_a, uint8([1 2 3]));
write_bytes(workspace_b, uint8([4 5 6]));
[wa_ok, wa_err, wa_identity] = tab.build_recording_identity_file( ...
    struct('file', workspace_a), [1 1 2], struct( ...
    'acquisition_frame', {'1', '2'}, 'source_frame', {'21', '22'}));
[wb_ok, wb_err, wb_identity] = tab.build_recording_identity_file( ...
    struct('file', workspace_b), [1 1 2], struct( ...
    'acquisition_frame', {'1', '2'}, 'source_frame', {'31', '32'}));
prov_workspace = prov;
prov_workspace = rmfield(prov_workspace, 'recording_identity');
prov_workspace.recording_workspace = struct('recordings', [wa_identity, wb_identity], ...
    'dimensions', [1 1 4]);
[workspace_ok, workspace_err, workspace_wire] = tab.validate_activation_state( ...
    single([1 2 3 4]), prov_workspace);
B2R10 = wa_ok && wb_ok && isempty(wa_err) && isempty(wb_err) && ...
    workspace_ok && isempty(workspace_err) && ...
    strcmp(workspace_wire.recording_identity.source_type, 'workspace') && ...
    strcmp(workspace_wire.recording_identity.frame_range.values{1}, '1') && ...
    strcmp(workspace_wire.recording_identity.frame_range.values{2}, '4') && ...
    strcmp(workspace_wire.recording_identity.members(2).frame_map(1).acquisition_frame, '3');
fprintf('  result=%s err=%s\n', tf(B2R10), workspace_err);
if B2R10, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R11: restore CAS rejects a malformed projected-output union member\n');
bad_projected = awire;
bad_projected.projected_output.status = 'AVAILABLE';
[sha4_ok, sha4, sha4_err] = tab.manifest_bytes_sha256(fullfile(run_dir, 'manifest.v2.json'));
[bad_persist_ok, bad_persist_err, ~] = tab.persist_restore_fields( ...
    run_dir, bad_projected, [], sha4, '3');
B2R11 = sha4_ok && isempty(sha4_err) && ~bad_persist_ok && ...
    contains(bad_persist_err, 'INVALID_STATE');
fprintf('  result=%s err=%s\n', tf(B2R11), bad_persist_err);
if B2R11, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R12: an ownerless recovery arbiter blocks CAS and is preserved\n');
recovery_lock = fullfile(run_dir, 'manifest.v2.json.recovery.lock');
mkdir(recovery_lock);
[sha5_ok, sha5, sha5_err] = tab.manifest_bytes_sha256(fullfile(run_dir, 'manifest.v2.json'));
[arbiter_ok, arbiter_err, ~] = tab.persist_restore_fields(run_dir, awire, [], sha5, '3');
arbiter_preserved = exist(recovery_lock, 'dir') == 7;
if arbiter_preserved, rmdir(recovery_lock, 's'); end
B2R12 = sha5_ok && isempty(sha5_err) && ~arbiter_ok && ...
    contains(arbiter_err, 'WRITE_CONFLICT') && arbiter_preserved;
fprintf('  result=%s err=%s preserved=%s\n', tf(B2R12), arbiter_err, tf(arbiter_preserved));
if B2R12, pass = pass + 1; else, fail = fail + 1; end

fprintf('B2R13: a foreign lock directory blocks CAS without ownership deletion\n');
foreign_lock = fullfile(run_dir, 'manifest.v2.json.lock');
mkdir(foreign_lock);
[sha6_ok, sha6, sha6_err] = tab.manifest_bytes_sha256(fullfile(run_dir, 'manifest.v2.json'));
[foreign_ok, foreign_err, ~] = tab.persist_restore_fields(run_dir, awire, [], sha6, '3');
foreign_preserved = exist(foreign_lock, 'dir') == 7;
if foreign_preserved, rmdir(foreign_lock, 's'); end
B2R13 = sha6_ok && isempty(sha6_err) && ~foreign_ok && ...
    contains(foreign_err, 'WRITE_CONFLICT') && foreign_preserved;
fprintf('  result=%s err=%s preserved=%s\n', tf(B2R13), foreign_err, tf(foreign_preserved));
if B2R13, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_RESTORE_RECORDS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_restore_records %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_restore_records\n');
end
end

function json = method_parameters_json(tab)
payload = struct('schema', 'method-parameters-v1', 'operation', 'load', ...
    'parent_map_digest', [], 'parent_time_reference', [], ...
    'parameters', struct('kind', 'load', ...
    'source_recording_identity_sha256', repmat('0', 1, 64), ...
    'initial_time_reference', struct('kind', 'relative_to_first_frame', ...
    'anchor_frame', '1', 'applied_offset_ms', '0000000000000000', ...
    'parent', [])));
json = tab.jcs_json(payload);
end

function write_v1(path, run_id, dataset_root)
stage = struct('name', 'image_undistorter', 'status', 'RUNNING', ...
    'command', '', 'settings_resolved', struct(), 'settings_provenance', [], ...
    'validation', struct('exit_code', 0, 'checks', []), 'warnings', [], ...
    'artifacts', [], 'log', 'logs/image_undistorter.log', 'spawned_pids', [], ...
    'licence', '', 'citation_key', '', 'citations', [], ...
    'started_at', '2026-09-13T01:00:00Z', 'finished_at', '', 'elapsed_s', 0);
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = run_id;
m.state_schema_version = 1;
m.recipe_version = 1;
m.tool_versions = struct();
m.tool_provenance = [];
m.dataset = struct('role', 'reconstruction', 'path', dataset_root);
m.inputs = struct('files', []);
m.fov_mapping = struct();
m.image_discovery = struct();
m.stages = stage;
m.deviations = [];
m.resource_checks = [];
m.touchups = [];
m.intensity_filters = [];
m.area_removals = [];
m.smoothings = [];
m.citations = [];
m.result = struct('status', 'CREATED');
fid = fopen(path, 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(m), 'char*1');
fclose(fid);
end

function write_bytes(path, values)
fid = fopen(path, 'wb');
fwrite(fid, values, 'uint8');
fclose(fid);
end

function cleanup_case(root)
if exist(root, 'dir')
    rmdir(root, 's');
end
end
