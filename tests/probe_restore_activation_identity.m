function probe_restore_activation_identity
%% Activation map, recording identity and provenance checks
% Collin Snitchler
% 13.09.2026
% Runs the pinned test vectors and the provenance cases (recording identity,
% geometry and projection records, time-reference changes). The generated
% records are written to E3_RECORDS_PATH when it is set.
% Check IDs: E3R<n> are the records and vectors, E3M<n> the eligibility and
% perturbation matrices; the prefixes only group them.
%The fixture is generated below and removed on completion; no external
%recording or extraction tree is consumed.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
tab = rabbit_reconstruction_tab();
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>

fprintf('E3R1: independent consumer parses the pinned vector records\n');
[v_ok, v_err, vectors] = normative_vectors(repo_dir);
record('E3R1', v_ok && isempty(v_err) && isfield(vectors, 'K1') && ...
    isfield(vectors, 'M1'), v_err);

fprintf('E3R2: all map predicates and canonical M1-M4 outcomes\n');
[m1_ok, m1_err, m1] = tab.validate_activation_map(single([1 NaN; -0 2]));
[m2_ok, m2_err, m2] = tab.validate_activation_map([0 -0 NaN]);
[m3_ok, m3_err, ~] = tab.validate_activation_map(single([Inf; -Inf]));
[m4_ok, m4_err, ~] = tab.validate_activation_map([NaN NaN]);
[m_bad_shape, ~, ~] = tab.validate_activation_map(ones(2, 1, 2));
record('E3R2', m1_ok && m2_ok && strcmp(m1.digest, vectors.M1.sha256) && ...
    strcmp(m2.digest, vectors.M2.sha256) && ~m3_ok && contains(m3_err, 'NO_FINITE') && ...
    ~m4_ok && contains(m4_err, 'NO_FINITE') && ~m_bad_shape, ...
    sprintf('%s | %s | %s', m1_err, m2_err, m4_err));

fprintf('E3R3: file identity is content based and relocation safe\n');
file_a = fullfile(root, 'recording-a.bin');
file_b = fullfile(root, 'renamed-recording.bin');
write_bytes(file_a, uint8([1 2 3 4 5 6]));
copyfile(file_a, file_b);
frame_map = struct('acquisition_frame', {'3', '4'}, 'source_frame', {'1', '2'});
fi = struct('file', file_a, 'path', root, 'name', 'recording-a.bin', 'type', '.bin');
[id_ok_a, id_err_a, identity_a, digest_a] = tab.build_recording_identity_file(fi, [2 3 2], frame_map);
fi.file = file_b;
[id_ok_b, id_err_b, identity_b, digest_b] = tab.build_recording_identity_file(fi, [2 3 2], frame_map);
write_bytes(file_b, uint8([1 2 3 4 5 7]));
[id_ok_c, ~, ~, digest_c] = tab.build_recording_identity_file(fi, [2 3 2], frame_map);
record('E3R3', id_ok_a && id_ok_b && isempty(id_err_a) && isempty(id_err_b) && ...
    strcmp(digest_a, digest_b) && isequal(identity_a, identity_b) && ...
    id_ok_c && ~strcmp(digest_a, digest_c), sprintf('%s | %s', id_err_a, id_err_b));

fprintf('E3R4: ordered stack identity retains duplicate bytes\n');
sm = repmat(struct('bytes', uint8([]), 'frame_map', struct()), 1, 3);
sm(1).bytes = uint8([9 8]); sm(1).frame_map = struct('acquisition_frame', {'1'}, 'source_frame', {'1'});
sm(2).bytes = uint8([9 8]); sm(2).frame_map = struct('acquisition_frame', {'2'}, 'source_frame', {'1'});
sm(3).bytes = uint8([7 6]); sm(3).frame_map = struct('acquisition_frame', {'3'}, 'source_frame', {'1'});
[stack_ok, stack_err, stack_id, stack_digest] = tab.build_recording_identity_stack(sm, [2 3 3]);
record('E3R4', stack_ok && isempty(stack_err) && numel(stack_id.members) == 3 && ...
    strcmp(stack_id.members(1).bytes_sha256, stack_id.members(2).bytes_sha256) && ...
    strcmp(stack_id.members(1).ordinal, '1') && strcmp(stack_id.members(2).ordinal, '2') && ...
    numel(stack_digest) == 64, stack_err);

fprintf('E3R5: workspace rebases a non-one-starting local range inclusively\n');
fi.file = file_a; write_bytes(file_a, uint8([1 2 3 4 5 6]));
[~, ~, id1, ~] = tab.build_recording_identity_file(fi, [2 3 2], ...
    struct('acquisition_frame', {'3', '4'}, 'source_frame', {'1', '2'}));
[~, ~, id2, ~] = tab.build_recording_identity_file(fi, [2 3 2], ...
    struct('acquisition_frame', {'7', '8'}, 'source_frame', {'1', '2'}));
[ws_ok, ws_err, ws_id, ws_digest] = tab.build_recording_identity_workspace([id1 id2], [2 3 4]);
record('E3R5', ws_ok && isempty(ws_err) && strcmp(ws_id.members(1).frame_map(1).acquisition_frame, '1') && ...
    strcmp(ws_id.members(1).frame_map(2).acquisition_frame, '2') && ...
    strcmp(ws_id.members(2).frame_map(1).acquisition_frame, '3') && ...
    strcmp(ws_id.members(2).frame_map(2).acquisition_frame, '4') && ...
    strcmp(ws_id.frame_range.values{2}, '4') && numel(ws_digest) == 64, ws_err);

fprintf('E3R6: strict geometry/projection perturbations are independently bound\n');
[g_ok, g_err, geometry, geometry_digest] = local_geometry_fixture(tab, vectors);
[p_ok, p_err, projection, projection_digest] = local_projection_fixture(tab, vectors);
[g_valid, g_valid_err] = tab.validate_geometry_record(geometry, geometry_digest);
[p_valid, p_valid_err] = tab.validate_projection_contract(projection, projection_digest);
geometry_bad = geometry; geometry_bad.rotation.values{1} = '3ff0000000000000';
projection_bad = projection; projection_bad.pose_inputs.records(1).image_name = 'changed-image';
[g_bad_ok, ~] = tab.validate_geometry_record(geometry_bad, geometry_digest);
[p_bad_ok, ~] = tab.validate_projection_contract(projection_bad, projection_digest);
record('E3R6', g_ok && p_ok && g_valid && p_valid && ~g_bad_ok && ~p_bad_ok && ...
    isempty(g_err) && isempty(p_err) && isempty(g_valid_err) && isempty(p_valid_err), ...
    sprintf('%s | %s', g_err, p_err));

fprintf('E3R7: every root time-reference and mutation transition is closed\n');
refs = {'absolute_acquisition_start', 'relative_to_first_frame', ...
    'relative_to_stimulus', 'relative_to_reference_frame', ...
    'relative_to_earliest_activation'};
ref_ok = true;
for k = 1:numel(refs)
    [rok, ~] = tab.validate_time_reference(root_time_reference(refs{k}));
    ref_ok = ref_ok && rok;
end
prov = phase2_provenance(tab, identity_a, geometry, geometry_digest, projection, projection_digest, digest_a);
[load_ok, load_err, state0] = tab.mutate_activation_state('load', [], struct('map', single([2 NaN; 4 6]), 'provenance', prov));
[filter_ok, filter_err, state1] = tab.mutate_activation_state('spatial_filter', state0, struct('kernel', [1 -0; 2 3]));
[zero_ok, zero_err, state2] = tab.mutate_activation_state('manual_zero', state1, ...
    struct('reference_coordinate', struct('kind', 'first_frame', 'anchor_frame', '1'), 'offset_ms', 1));
[zero2_ok, zero2_err, state3] = tab.mutate_activation_state('manual_zero', state2, ...
    struct('reference_coordinate', struct('kind', 'first_frame', 'anchor_frame', '1'), 'offset_ms', 2));
[undo_ok, undo_err, state4] = tab.mutate_activation_state('undo', state3, struct());
record('E3R7', ref_ok && load_ok && filter_ok && zero_ok && zero2_ok && undo_ok && ...
    strcmp(state1.activation_map.status, 'MUTATION_PENDING_REPROJECTION') && ...
    strcmp(state2.activation_provenance.time_reference.kind, 'relative_to_manual_zero') && ...
    strcmp(state3.activation_provenance.time_reference.parent.kind, 'relative_to_manual_zero') && ...
    ~isempty(state4.activation_provenance.method.parameters_json), ...
    sprintf('%s | %s | %s', load_err, filter_err, [zero_err zero2_err undo_err]));

fprintf('E3R8: stale or missing provenance is rejected without state mutation\n');
missing = rmfield(prov, 'recording_identity');
[missing_ok, missing_err] = tab.validate_activation_provenance(single([1 2; 3 4]), missing);
stale = prov; stale.geometry_digest = repmat('0', 1, 64);
[stale_ok, stale_err] = tab.validate_activation_provenance(single([1 2; 3 4]), stale);
record('E3R8', ~missing_ok && contains(missing_err, 'NOT_RECORDED') && ...
    ~stale_ok && contains(stale_err, 'GEOMETRY'), [missing_err ' | ' stale_err]);

fprintf('E3R9: MATLAB generated records are serialised for independent comparison\n');
records_path = getenv('E3_RECORDS_PATH');
if isempty(records_path)
    records_path = getenv('E3_RECORDS_PATH');
if isempty(records_path)
    records_path = getenv('E3_RECORDS_PATH');
if isempty(records_path)
    records_path = getenv('E3_RECORDS_PATH');
if isempty(records_path)
    records_path = getenv('E3_RECORDS_PATH');
if isempty(records_path)
    records_path = getenv('E3_RECORDS_PATH');
if isempty(records_path)
    records_path = fullfile(root, 'e3-generated-records.json');
else
    records_path = char(records_path);
end
else
    records_path = char(records_path);
end
else
    records_path = char(records_path);
end
else
    records_path = char(records_path);
end
else
    records_path = char(records_path);
end
else
    records_path = char(records_path);
end
record_payload = struct('geometry', geometry, 'geometry_digest', geometry_digest, ...
    'projection', projection, 'projection_digest', projection_digest, ...
    'identity', identity_a, 'identity_digest', digest_a, ...
    'map_m1_digest', vectors.M1.sha256, 'map_m2_digest', vectors.M2.sha256, ...
    'kernel_digest', vectors.K1.sha256);
write_json(records_path, record_payload);
record('E3R9', exist(records_path, 'file') == 2, records_path);

fprintf('E3M1: eligibility rejects non-activation map kinds, non-ms units, and unknown time reference\n');
bad_kind = prov; bad_kind.map_kind = 'repolarisation';
[bad_kind_ok, bad_kind_err] = tab.validate_activation_provenance(single([1 2; 3 4]), bad_kind);
bad_units = prov; bad_units.units = 'mV';
[bad_units_ok, bad_units_err] = tab.validate_activation_provenance(single([1 2; 3 4]), bad_units);
bad_time = prov; bad_time.time_reference = struct('kind', 'unknown');
[bad_time_ok, bad_time_err] = tab.validate_activation_provenance(single([1 2; 3 4]), bad_time);
record('E3M1', ~bad_kind_ok && contains(bad_kind_err, 'MAP_KIND') && ...
    ~bad_units_ok && contains(bad_units_err, 'UNSUPPORTED_UNITS') && ...
    ~bad_time_ok && contains(bad_time_err, 'TIME_REFERENCE'), ...
    [bad_kind_err ' | ' bad_units_err ' | ' bad_time_err]);

fprintf('E3M2: every finite top-level geometry field rejects an independent perturbation\n');
geometry_fields = {'contract_version', 'region_bounds_src', 'rotation', ...
    'view_order', 'per_view_inverse_transforms', 'fov', 'binning', ...
    'cropping', 'canvas_shape', 'matrix_convention'};
geometry_matrix_ok = true;
for k = 1:numel(geometry_fields)
    field = geometry_fields{k};
    altered = geometry;
    if strcmp(field, 'contract_version')
        altered.(field) = 'geometry-invalid';
    else
        altered.(field) = [];
    end
    [altered_ok, altered_err] = tab.validate_geometry_record(altered, geometry_digest);
    rejected = ~altered_ok;
    geometry_matrix_ok = geometry_matrix_ok && rejected;
    fprintf('  E3M2 geometry.%s reject=%d detail=%s\n', field, rejected, altered_err);
end
record('E3M2', geometry_matrix_ok, sprintf('%d fields', numel(geometry_fields)));

fprintf('E3M3: every finite top-level projection field rejects an independent perturbation\n');
projection_fields = {'contract_version', 'algorithm', 'view_bindings', ...
    'unit_scale', 'shifts', 'scales', 'fov_mapping', 'target_mesh', ...
    'pose_inputs'};
projection_matrix_ok = true;
for k = 1:numel(projection_fields)
    field = projection_fields{k};
    altered = projection;
    if strcmp(field, 'contract_version')
        altered.(field) = 'projection-invalid';
    else
        altered.(field) = [];
    end
    [altered_ok, altered_err] = tab.validate_projection_contract(altered, projection_digest);
    rejected = ~altered_ok;
    projection_matrix_ok = projection_matrix_ok && rejected;
    fprintf('  E3M3 projection.%s reject=%d detail=%s\n', field, rejected, altered_err);
end
record('E3M3', projection_matrix_ok, sprintf('%d fields', numel(projection_fields)));

fprintf('E3M4: generated lineage is closed and independently digestable\n');
lineage = identity_a.lineage;
lineage_json = jsondecode(lineage.json);
lineage_fields_ok = obj_exact_fields(lineage, {'encoding', 'json', 'sha256'}) && ...
    strcmp(char(lineage.encoding), 'jcs-utf8-v1') && ...
    obj_exact_fields(lineage_json, {'schema', 'source_type', 'frame_basis', ...
    'members', 'processing_parents'}) && ...
    strcmp(char(lineage_json.schema), 'lineage-v1') && ...
    strcmp(char(lineage_json.source_type), 'file') && ...
    strcmp(char(lineage_json.frame_basis), 'one_based_acquisition_frame') && ...
    numel(lineage_json.members) == 1 && isempty(lineage_json.processing_parents) && ...
    strcmp(char(lineage.sha256), tab.restore_domain_digest( ...
    'OM-RECORDING-LINEAGE', 'lineage-v1', lineage_json));
record('E3M4', lineage_fields_ok, 'file lineage schema/member/parent/digest');

fprintf('PROBE_RESTORE_ACTIVATION_IDENTITY RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0, error('PROBE_FAIL probe_restore_activation_identity'); end
fprintf('PROBE_OK probe_restore_activation_identity %d/0\n', pass);

    function record(name, condition, detail)
        if condition, pass = pass + 1; result = 'PASS'; else, fail = fail + 1; result = 'FAIL'; end
        fprintf('  %s %s %s\n', name, result, detail);
    end
end

function tf = obj_exact_fields(value, required)
tf = isstruct(value) && isequal(sort(fieldnames(value)), sort(required(:)));
end

function [ok, err, vectors] = normative_vectors(repo_dir)
ok = false; err = ''; vectors = struct();
try
% The pinned vectors: the activation digest's test vectors (tests/fixtures/restore_vectors.md)
text = fileread(fullfile(repo_dir, 'tests', 'fixtures', 'restore_vectors.md'));
for key = {'M1', 'M2'}
    token = key{1};
    hit = regexp(text, [token ' is [\s\S]*?exact input bytes are ([0-9a-f]+) and its SHA-256 is ([0-9a-f]{64})'], 'tokens', 'once');
    if isempty(hit), error('missing %s vector', token); end
    vectors.(token) = struct('input_hex', hit{1}, 'sha256', hit{2});
end
for key = {'K1', 'G1', 'MP1', 'L1', 'P1'}
    token = key{1};
    json_hit = line_value(text, [token '.json=']);
    if isempty(json_hit), json_hit = {''}; end
    hex_hit = line_value(text, [token '.input_hex=']);
    sha_hit = line_value(text, [token '.sha256=']);
    if ~isempty(hex_hit)
        hex_match = regexp(hex_hit{1}, '[0-9a-f]{32,}', 'match', 'once');
        if ~isempty(hex_match), hex_hit = {hex_match}; end
    end
    if ~isempty(sha_hit)
        sha_match = regexp(sha_hit{1}, '[0-9a-f]{64}', 'match', 'once');
        if ~isempty(sha_match), sha_hit = {sha_match}; end
    end
    if isempty(json_hit) || isempty(hex_hit) || isempty(sha_hit), error('missing %s vector', token); end
    vectors.(token) = struct('json', json_hit{1}, 'input_hex', hex_hit{1}, 'sha256', sha_hit{1});
end
vectors.M3 = struct('status', 'REJECT', 'reason', 'INFINITY');
vectors.M4 = struct('status', 'REJECT', 'reason', 'NO_FINITE_VALUES');
ok = true;
catch ME
err = ME.message;
end
end

function out = line_value(text, marker)
out = {};
starts = strfind(text, marker);
valid = [];
for k = 1:numel(starts)
    if starts(k) == 1 || isempty(regexp(text(starts(k)-1), '[A-Za-z0-9]', 'once'))
        valid(end+1) = starts(k); %#ok<AGROW>
    end
end
if isempty(valid), return; end
start = valid(1) + numel(marker);
finish = strfind(text(start:end), sprintf('\n'));
if isempty(finish), finish = numel(text) - start + 2; else, finish = finish(1); end
value = strtrim(text(start:start + finish - 2));
if numel(value) >= 2 && value(1) == '"' && value(end) == '"'
    value = value(2:end-1);
end
out = {strtrim(value)};
end

function [ok, err, record, digest] = local_geometry_fixture(tab, vectors)
ok = false; err = ''; record = struct(); digest = '';
try
record = jsondecode(vectors.G1.json);
digest = tab.restore_domain_digest('OM-ACTIVATION-GEOMETRY', 'geometry-v1', record);
ok = strcmp(digest, vectors.G1.sha256);
if ~ok, err = 'G1 digest mismatch'; end
catch ME
err = ME.message;
end
end

function [ok, err, record, digest] = local_projection_fixture(tab, vectors)
ok = false; err = ''; record = struct(); digest = '';
try
record = jsondecode(vectors.P1.json);
digest = tab.restore_domain_digest('OM-PROJECTION-CONTRACT', 'projection-v1', record);
ok = strcmp(digest, vectors.P1.sha256);
if ~ok, err = 'P1 digest mismatch'; end
catch ME
err = ME.message;
end
end

function out = phase2_provenance(tab, identity, geometry, geometry_digest, projection, projection_digest, identity_digest)
method = struct('name', 'activation_time_pipeline', 'version', 'method-v1', ...
    'parameters_json', '', 'parameters_sha256', '');
params = struct('schema', 'method-parameters-v1', 'operation', 'load', ...
    'parent_map_digest', [], 'parent_time_reference', [], ...
    'parameters', struct('kind', 'load', ...
    'source_recording_identity_sha256', identity_digest, ...
    'initial_time_reference', root_time_reference('relative_to_first_frame')));
method.parameters_json = tab.jcs_json(params);
method.parameters_sha256 = tab.restore_domain_digest('OM-ACTIVATION-METHOD', 'method-v1', params);
out = struct('map_kind', 'activation_time', 'units', 'ms', 'method', method, ...
    'time_reference', root_time_reference('relative_to_first_frame'), ...
    'recording_identity', identity, 'geometry', geometry, ...
    'geometry_digest', geometry_digest, 'projection_contract', projection, ...
    'projection_contract_digest', projection_digest, ...
    'target_mesh_digest', projection.target_mesh.vertices_sha256);
end

function out = root_time_reference(kind)
switch kind
    case 'absolute_acquisition_start', anchor = '0';
    case 'relative_to_first_frame', anchor = '1';
    case 'relative_to_stimulus', anchor = '2';
    case 'relative_to_reference_frame', anchor = '3';
    case 'relative_to_earliest_activation', anchor = '0';
    otherwise, error('unknown root time reference');
end
out = struct('kind', kind, 'anchor_frame', anchor, ...
    'applied_offset_ms', '0000000000000000', 'parent', []);
end

function write_bytes(path, bytes)
fid = fopen(path, 'wb'); assert(fid >= 0); fwrite(fid, bytes, 'uint8'); fclose(fid);
end

function write_json(path, value)
fid = fopen(path, 'wb'); assert(fid >= 0); fwrite(fid, unicode2native(jsonencode(value), 'UTF-8'), 'uint8'); fclose(fid);
end

function cleanup_case(root)
if exist(root, 'dir'), rmdir(root, 's'); end
end
