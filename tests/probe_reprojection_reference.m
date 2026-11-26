function probe_reprojection_reference
%% Reprojection against a pinned oracle
% Collin Snitchler
% 13.09.2026
% The large reconstruction fixture is external and selected only through
% OM_TEST_REPROJECTION_GOLDEN_ROOT. The repository stores only small oracle
% metadata; this probe generates its deterministic mesh/ROI in temp space.
% Check IDs: E6R<n> is check n of this probe; the prefix only groups them.
% Oracle updates of 06.10.2026:
%   1. output_ply_sha256 and output_ply_bytes: the projected PLY gives a
%      vertex with no assigned face NaN instead of averaging unassigned
%      faces in as 0.
%   2. data_proj, viewi, assignment mask, CDF payload, projected_output and
%      the PLY hash: COLMAP pixel coordinates are now shifted by +0.5 to
%      RHYTHM's 1-based pixel centres (half-pixel fix). Counts are
%      unchanged; probe_rhythm_pure P6 and P12 check the values against
%      an expectation worked out without the adapter.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
oracle_path = fullfile(repo_dir, 'tests', 'fixtures', 'reprojection_reference', 'oracle.json');
assert(exist(oracle_path, 'file') == 2, 'The reprojection oracle (tests/fixtures/reprojection_reference/oracle.json) is missing.');
o = jsondecode(read_utf8(oracle_path));
assert(strcmp(o.schema, 'reprojection-reference-oracle-v1'));
fixture_root = om_test_getenv(char(o.fixture_root_env));
if isempty(fixture_root) || exist(relative_join(fixture_root, o.external.run_relative), 'dir') ~= 7
    fprintf('SKIP probe_reprojection_reference: set %s to the measured external fixture root (with %s).\n', ...
        o.fixture_root_env, o.external.run_relative);
    return;
end
external_run = relative_join(fixture_root, o.external.run_relative);
external_roi = relative_join(external_run, o.oracle.external_roi_path);
external_mesh = relative_join(external_run, o.oracle.external_mesh_path);
assert(exist(external_run, 'dir') == 7 && exist(external_roi, 'file') == 2 && ...
    exist(external_mesh, 'file') == 2, 'E6 fixture path is missing.');

pass = 0;
fail = 0;
record('E6R1 descriptor is schema-pinned and path-portable', ...
    ~isempty(o.source_commit) && strcmp(o.fixture_root_env, ...
    'OM_TEST_REPROJECTION_GOLDEN_ROOT') && ~has_absolute_path(o.external.run_relative) && ...
    ~has_absolute_path(o.oracle.external_roi_path) && ...
    ~has_absolute_path(o.oracle.external_mesh_path), char(o.source_commit));

% Hash every external reference before any operation. The fixture is never
% copied or written by this probe.
external_specs = o.external.files;
external_paths = cell(1, numel(external_specs));
before = cell(1, numel(external_specs));
external_ok = true;
for k = 1:numel(external_specs)
    external_paths{k} = relative_join(external_run, external_specs(k).path);
    [file_ok, file_hash, file_bytes] = file_digest(external_paths{k});
    before{k} = file_hash;
    external_ok = external_ok && file_ok && file_bytes == external_specs(k).bytes && ...
        strcmp(file_hash, external_specs(k).sha256);
end
record('E6R2 external input and protected-artifact hashes match', external_ok, ...
    sprintf('%d role-labelled files', numel(external_specs)));

% Read-only load checks cover the v1 manifest, all three external PLY roles,
% and the binary CDF payload without changing any fixture bytes.
read_ok = false;
try
    manifest = jsondecode(read_utf8(external_paths{1})); %#ok<NASGU>
    fused = rabbit_rhythm_reproject.read_ply_mesh(external_paths{6}); %#ok<NASGU>
    rebuilt = rabbit_rhythm_reproject.read_ply_mesh(external_paths{7}); %#ok<NASGU>
    projected_legacy = rabbit_rhythm_reproject.read_ply_mesh(external_paths{8}); %#ok<NASGU>
    cdf_bytes = read_bytes(external_paths{9});
    read_ok = isstruct(manifest) && ~isempty(fused.pts) && ~isempty(rebuilt.pts) && ...
        ~isempty(projected_legacy.pts) && numel(cdf_bytes) > 0;
catch
    read_ok = false;
end
record('E6R3 external artefacts load read-only by role', read_ok, 'manifest/3 PLY/CDF');

% Build the deterministic plane and ROI in the OS temp directory. No mesh,
% image, ROI, or other fixture bytes are copied into the repository.
[local_mesh, local_roi, map, generated] = make_generated_inputs( ...
    external_run, o.oracle);
input_cleanup = onCleanup(@() cleanup_files({local_mesh, local_roi})); %#ok<NASGU>
map_spec = o.oracle.map;
map_dims = map_spec.dimensions;
if ischar(map_dims), map_dims = {map_dims}; end
map_ok = strcmp(map_spec.class, 'double') && strcmp(map_spec.order, 'column-major') && ...
    size(map, 1) == str2double(map_dims{1}) && size(map, 2) == str2double(map_dims{2}) && ...
    strcmp(hash_array(map, 'float64'), map_spec.sha256) && ...
    strcmp(generated.mesh_sha256, o.oracle.generated_mesh.mesh_sha256) && ...
    strcmp(generated.roi_sha256, o.oracle.generated_roi.roi_sha256);
record('E6R4 generated oracle inputs are pinned without repository fixture bytes', ...
    map_ok, sprintf('mesh=%s roi=%s', generated.mesh_sha256, generated.roi_sha256));

views = cellstr(o.oracle.view_cameras);
out_dir = tempname;
cleanup = onCleanup(@() cleanup_output(out_dir)); %#ok<NASGU>
% The pinned oracle arrays were recorded with the native-resolution
% reimplementation, so that method is selected explicitly; the default
% (RHYTHM dataProjection02 on 100x100 views) is covered by
% probe_rhythm_pure.
r = rabbit_rhythm_reproject.run(map, local_roi, ...
    'ColmapDir', fullfile(external_run, 'inputs', 'sparse'), ...
    'MeshFile', local_mesh, 'ViewCameras', views, 'UnitScale', 1000, ...
    'Shifts', zeros(4, 2), 'Method', 'reimplementation', 'OutDir', out_dir, ...
    'ExportCdf', true, 'ExportPly', true);

stats = o.baseline.stats;
run_ok = r.stats.nFaces == stats.face_count && ...
    r.stats.nAssigned == stats.assigned_count && nnz(r.mask) > 0 && ...
    nnz(r.dataProj == 0) == stats.legacy_unassigned_scalar_count;
record('E6R5 live product produces non-degenerate assigned geometry', run_ok, ...
    sprintf('faces=%d assigned=%d legacy_zero=%d', r.stats.nFaces, ...
    nnz(r.mask), nnz(r.dataProj == 0)));

array_ok = strcmp(hash_array(r.mesh.pts, 'float64'), o.baseline.vertex_array.sha256) && ...
    strcmp(hash_array(r.mesh.faces, 'uint64_one_based'), o.baseline.face_array.sha256) && ...
    strcmp(hash_array(r.dataProj, 'float64'), o.baseline.data_proj_double.sha256) && ...
    strcmp(hash_array(r.dataProj, 'float32'), o.baseline.data_proj_float32.sha256) && ...
    strcmp(hash_array(r.viewi, 'uint64'), o.baseline.viewi.sha256) && ...
    strcmp(hash_array(uint8(r.mask), 'uint8'), o.baseline.assignment_mask.sha256);
record('E6R6 exact ordered topology/scalar/mask arrays match', array_ok, ...
    'little-endian canonical array hashes');

% Do not pass the legacy zero sentinel to the phase-1 wire. The assignment
% mask is an independent product output; only unassigned faces become NaN.
projected_values = double(r.dataProj(:));
projected_values(~r.mask(:)) = NaN;
tab = rabbit_reconstruction_tab();
[po_ok, po_err, projected] = tab.validate_projected_output( ...
    projected_values, generated.mesh_sha256, o.oracle.projection_contract_digest);
if po_ok
    [assigned, counts] = tab.classify_projected_output(projected);
else
    assigned = false(0, 1);
    counts = struct('assigned', 0, 'unassigned', 0);
end
projected_ok = po_ok && isempty(po_err) && strcmp(projected.status, ...
    o.baseline.projected_output.status) && ...
    strcmp(projected.face_order, o.baseline.projected_output.face_order) && ...
    strcmp(projected.face_indexing, o.baseline.projected_output.face_indexing) && ...
    strcmp(projected.validity, o.baseline.projected_output.validity) && ...
    strcmp(projected.output_sha256, o.baseline.projected_output.output_sha256) && ...
    strcmp(projected.target_mesh_digest, o.baseline.projected_output.target_mesh_digest) && ...
    strcmp(projected.projection_contract_digest, ...
    o.baseline.projected_output.projection_contract_digest) && ...
    counts.assigned == o.baseline.projected_output.assigned_count && ...
    counts.unassigned == o.baseline.projected_output.unassigned_count && ...
    counts.assigned == nnz(r.mask) && counts.unassigned > 0 && ...
    nnz(r.dataProj == 0) == counts.unassigned;
record('E6R7 phase-1 projected_output preserves assignment/zero distinction', ...
    projected_ok, sprintf('finite=%d canonical-NaN=%d legacy-zero=%d', ...
    counts.assigned, counts.unassigned, nnz(r.dataProj == 0)));

cdf_actual = read_bytes(r.cdf_path);
nl = find(cdf_actual == uint8(10));
cdf_ok = numel(nl) >= 8 && strcmp(sha256_bytes(cdf_actual(nl(8) + 1:end)), ...
    o.baseline.cdf_payload_sha256);
[ply_ok, ply_hash, ply_bytes] = file_digest(r.ply_path);
output_ok = cdf_ok && ply_ok && ply_bytes == o.baseline.output_ply_bytes && ...
    strcmp(ply_hash, o.baseline.output_ply_sha256);
record('E6R8 exact projected output payload and PLY match', output_ok, ...
    sprintf('cdf=%s ply=%s', o.baseline.cdf_payload_sha256, ply_hash));

% Re-check every external byte after the oracle run, including manifest.json
% and all three PLYs. Any write or mutation fails the battery.
after_ok = true;
for k = 1:numel(external_specs)
    [file_ok, file_hash, file_bytes] = file_digest(external_paths{k});
    after_ok = after_ok && file_ok && file_bytes == external_specs(k).bytes && ...
        strcmp(file_hash, before{k}) && strcmp(file_hash, external_specs(k).sha256);
end
record('E6R9 external manifest/PLY artefacts remain byte-identical', after_ok, ...
    sprintf('%d before/after hashes', numel(external_specs)));

records_path = getenv('E6_RECORDS_PATH');
if isempty(records_path)
    records_path = fullfile(tempdir, 'om_test_probe_reprojection_reference_records.json');
end
records = struct('schema', 'reprojection-reference-records-v1', ...
    'oracle_path', oracle_path, 'output_ply', r.ply_path, ...
    'output_cdf', r.cdf_path, 'vertex_array_sha256', hash_array(r.mesh.pts, 'float64'), ...
    'face_array_sha256', hash_array(r.mesh.faces, 'uint64_one_based'), ...
    'data_proj_double_sha256', hash_array(r.dataProj, 'float64'), ...
    'data_proj_float32_sha256', hash_array(r.dataProj, 'float32'), ...
    'viewi_sha256', hash_array(r.viewi, 'uint64'), ...
    'assignment_mask_sha256', hash_array(uint8(r.mask), 'uint8'), ...
    'projected_output_sha256', projected.output_sha256, ...
    'projected_assigned_count', counts.assigned, ...
    'projected_unassigned_count', counts.unassigned, ...
    'projected_finite_count', counts.assigned, ...
    'projected_canonical_nan_count', counts.unassigned, ...
    'projected_canonical_nan_bits', o.baseline.projected_output.canonical_nan_bits, ...
    'finite_zero_is_assigned', o.baseline.projected_output.finite_zero_is_assigned, ...
    'legacy_zero_count', nnz(r.dataProj == 0), ...
    'external_unchanged', after_ok);
write_json(records_path, records);
fprintf('E6_RECORDS path=%s\n', records_path);

fprintf('PROBE_REPROJECTION_REFERENCE RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0
    error('PROBE_FAIL probe_reprojection_reference');
end
fprintf('PROBE_OK probe_reprojection_reference %d/0\n', pass);

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

function [mesh_path, roi_path, map, generated] = make_generated_inputs(external_run, oracle)
% Generate only deterministic, non-sensitive test inputs under tempdir.
tab = rabbit_reconstruction_tab();
camdir = fullfile(external_run, 'inputs', 'sparse');
[cameras, images, ~] = tab.read_sparse_model(camdir);
image_name = char(oracle.generated_mesh.camera_image);
keys = images.keys;
image_id = [];
for k = 1:numel(keys)
    if strcmp(images(keys{k}).name, image_name)
        image_id = keys{k};
        break;
    end
end
assert(~isempty(image_id), 'Pinned oracle camera image is absent: %s', image_name);
view = images(image_id);
q = view.qvec(:);
qw = q(1); qx = q(2); qy = q(3); qz = q(4);
R = [1-2*(qy^2+qz^2), 2*(qx*qy-qz*qw), 2*(qx*qz+qy*qw); ...
    2*(qx*qy+qz*qw), 1-2*(qx^2+qz^2), 2*(qy*qz-qx*qw); ...
    2*(qx*qz-qy*qw), 2*(qy*qz+qx*qw), 1-2*(qx^2+qy^2)];
centre = R' * ([0; 0; oracle.generated_mesh.plane_depth_m] - view.tvec(:));
u = R' * [1; 0; 0];
v = R' * [0; 1; 0];
n = oracle.generated_mesh.grid_side;
half = oracle.generated_mesh.half_extent_m;
pts = zeros(n * n + 1, 3);
for row = 1:n
    for col = 1:n
        pts((row - 1) * n + col, :) = (centre + ...
            ((col - 1) / (n - 1) * 2 - 1) * half * u + ...
            ((row - 1) / (n - 1) * 2 - 1) * half * v)';
    end
end
faces = zeros((n - 1) * (n - 1) * 2, 3);
f = 0;
for row = 1:n-1
    for col = 1:n-1
        a = (row - 1) * n + col; b = a + 1;
        d = row * n + col; e = d + 1;
        f = f + 1; faces(f, :) = [a d b];
        f = f + 1; faces(f, :) = [b d e];
    end
end
% Preserve the established topology-orientation anchor, but do not persist it.
pts(end, :) = (centre + oracle.generated_mesh.anchor_offset_m * ...
    (R' * [0; 0; 1]))';
mesh_path = [tempname, '.ply'];
write_ply(mesh_path, pts, faces);

bounds = double(oracle.generated_roi.bounds);
dims = oracle.generated_roi.source_dims;
payload = struct('schema_version', 1, 'region_bounds_src', bounds, ...
    'regions', size(bounds, 1), 'rotation', oracle.generated_roi.rotation, ...
    'rabbit_panoramic', true, 'source_dims', dims, ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, ...
    'view_order', {{'view2', 'view3', 'view1', 'view4'}});
roi_path = [tempname, '.json'];
write_json_no_newline(roi_path, payload);
roi = rabbit_stack_io.load_roi_json(roi_path, [], []);
tile_values = double(oracle.map.tile_values_ms(:)');
map = NaN(roi.source_dims.height, roi.source_dims.width);
widths = roi.region_bounds_src(:, 4) - roi.region_bounds_src(:, 2) + 1;
start_col = 1;
for k = 1:numel(widths)
    map(:, start_col:start_col + widths(k) - 1) = tile_values(k);
    start_col = start_col + widths(k);
end
[~, generated.mesh_sha256, generated.mesh_bytes] = file_digest(mesh_path);
[~, generated.roi_sha256, generated.roi_bytes] = file_digest(roi_path);
end

function write_ply(path, pts, faces)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Cannot write %s.', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, ['ply\nformat ascii 1.0\nelement vertex %d\nproperty float x\n' ...
    'property float y\nproperty float z\nelement face %d\n' ...
    'property list uchar int vertex_indices\nend_header\n'], ...
    size(pts, 1), size(faces, 1));
for k = 1:size(pts, 1), fprintf(fid, '%.17g %.17g %.17g\n', pts(k, :)); end
for k = 1:size(faces, 1), fprintf(fid, '3 %d %d %d\n', faces(k, :) - 1); end
end

function write_json_no_newline(path, value)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Cannot write %s.', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value), 'char*1');
end

function cleanup_files(paths)
for k = 1:numel(paths)
    if exist(paths{k}, 'file'), delete(paths{k}); end
end
end

function out = relative_join(base, relative)
parts = strsplit(char(relative), '/');
out = base;
for k = 1:numel(parts)
    if ~isempty(parts{k}), out = fullfile(out, parts{k}); end
end
end

function tf = has_absolute_path(value)
value = char(value);
tf = ~isempty(regexp(value, '^[A-Za-z]:[\\/]', 'once')) || ...
    ~isempty(regexp(value, '^[/\\]', 'once'));
end

function [ok, h, bytes] = file_digest(path)
ok = false;
h = '';
bytes = -1;
try
    fid = fopen(path, 'rb');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    data = fread(fid, Inf, '*uint8');
    bytes = numel(data);
    h = sha256_bytes(data);
    ok = true;
catch
    ok = false;
end
end

function text = read_utf8(path)
fid = fopen(path, 'r', 'n', 'UTF-8');
assert(fid >= 0, 'Cannot read UTF-8 text file: %s.', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fread(fid, Inf, '*char')';
end

function bytes = read_bytes(path)
fid = fopen(path, 'rb');
assert(fid >= 0, 'Cannot read %s.', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8');
end

function h = sha256_file(path)
[ok, h, ~] = file_digest(path);
assert(ok, 'Cannot hash %s.', path);
end

function h = hash_array(values, encoding)
switch encoding
    case {'float64', 'float64_little_endian'}
        bytes = le_bytes(double(values(:)));
    case 'float32'
        bytes = le_bytes(single(values(:)));
    case {'uint64', 'uint64_one_based'}
        bytes = le_bytes(uint64(values(:)));
    case 'uint8'
        bytes = uint8(values(:));
    otherwise
        error('Unknown E6 array encoding: %s', encoding);
end
h = sha256_bytes(bytes);
end

function out = le_bytes(values)
[~, ~, endian] = computer;
if strcmp(endian, 'B'), values = swapbytes(values); end
out = typecast(values(:), 'uint8');
end

function h = sha256_bytes(bytes)
md = java.security.MessageDigest.getInstance('SHA-256');
digest = md.digest(uint8(bytes));
bytes = typecast(int8(digest), 'uint8');
h = lower(reshape(dec2hex(bytes, 2)', 1, []));
end

function write_json(path, value)
parent = fileparts(path);
if ~isempty(parent) && ~isfolder(parent), mkdir(parent); end
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Cannot write %s.', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(value));
end

function cleanup_output(path)
if exist(path, 'dir'), rmdir(path, 's'); end
end
