function probe_manifest_v2_three_artefacts
%% Load and render three PLY artefacts from a native v2 manifest
% Collin Snitchler
% 12.09.2026
% Generates a minimal v1 provenance anchor, its native-v2 manifest, and
% three distinct valid ASCII PLY artefacts under tempdir. The GUI
% callback must load and render each role separately without changing any of
% the four protected v2/PLY files.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);

root = tempname(tempdir);
run_id = '20260912T120000_01234567';
run_dir = fullfile(root, 'portable.matom', 'reconstruction', 'runs', run_id);
out_dir = fullfile(run_dir, 'outputs');
reproj_dir = fullfile(out_dir, 'reprojection');
mkdir(reproj_dir);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>

fused_path = fullfile(out_dir, 'fused-geometric.ply');
rebuilt_path = fullfile(out_dir, 'alignment-rebuilt-mesh.ply');
projected_path = fullfile(reproj_dir, 'activation_projected.ply');
write_text_utf8(fused_path, point_cloud_ply());
write_text_utf8(rebuilt_path, mesh_ply(false));
write_text_utf8(projected_path, mesh_ply(true));

% A small valid v1 sibling anchors converted_from provenance. Conversion is
% performed by the backend, then written explicitly as UTF-8.
v1 = struct();
v1.manifest_schema = 'cd2.reconstruction.manifest.v1';
v1.run_id = run_id;
v1.dataset = struct('role', 'reconstruction', 'path', root);
v1.inputs = struct('files', []);
v1.stages = struct('name', 'image_undistorter', 'status', 'FAILED', ...
    'started_at', '2026-09-12T12:00:00Z', 'finished_at', '2026-09-12T12:00:01Z');
v1.result = struct('status', 'FAILED');
v1_path = fullfile(run_dir, 'manifest.json');
write_text_utf8(v1_path, jsonencode(v1, 'PrettyPrint', true));
tab = rabbit_reconstruction_tab();
[v2_bytes, ~] = tab.convert_v1_to_v2(v1_path, run_dir);
v2_path = fullfile(run_dir, 'manifest.v2.json');
write_text_utf8(v2_path, v2_bytes);

protected = {v2_path, fused_path, rebuilt_path, projected_path};
before = cellfun(@sha256f, protected, 'UniformOutput', false);

app = analyse_optical_mapping;
app.recon.test_manifest_pick = v2_path;
app.recon.OpenReconstructionManifestMenuSelected();
drawnow;

figs = findall(0, 'Type', 'figure');
vis_fig = [];
for k = 1:numel(figs)
    if endsWith(get(figs(k), 'Name'), ['Reconstruction visualisation - run ' run_id])   % a NOT FOR ANALYSIS prefix first (F13)
        vis_fig = figs(k);
        break;
    end
end

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));
status = strjoin(app.recon.VisualiseStatusText.Value, ' ');
C1 = ~isempty(vis_fig) && ~isempty(strfind(lower(status), 'visualised'));
record('P1 callback opened native-v2 and auto-visualised', C1, tf(C1));

fused_pts = [0 0 0; 1 0 0; 0 1 0];
rebuilt_pts = [10 0 0; 11 0 0; 10 1 0];
C2 = axis_has_scatter(vis_fig, ['Dense cloud ' char(8212) ' COLMAP'], fused_pts);
record('P2 fused-cloud role loaded/rendered separately', C2, tf(C2));
C3 = axis_has_patch(vis_fig, ['Mesh ' char(8212) ' rebuilt by the alignment'], rebuilt_pts);
record('P3 rebuilt-mesh role loaded/rendered separately', C3, tf(C3));
meta = getappdata(vis_fig, 'reconstruction_panel_metadata');
C4 = numel(meta) == 3 && ...
    strcmp(meta(3).render_status, 'NOT_YET_PRODUCED') && ...
    strcmp(meta(3).activation_semantics, 'UNAVAILABLE') && ...
    isempty(findobj(find_axis(vis_fig, 'Projected values'), 'Type', 'patch'));
record('P4 authoritative v2 UNAVAILABLE suppresses unverified projected colours', C4, tf(C4));

after = cellfun(@sha256f, protected, 'UniformOutput', false);
labels = {'manifest.v2.json', 'fused-geometric.ply', ...
    'alignment-rebuilt-mesh.ply', 'activation_projected.ply'};
for k = 1:numel(protected)
    unchanged = strcmp(before{k}, after{k});
    record(['P' num2str(k + 4) ' ' labels{k} ' hash unchanged'], unchanged, ...
        [tf(unchanged) ' ' before{k}]);
end

fprintf('PROBE_MANIFEST_V2_THREE_ARTEFACTS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_v2_three_artefacts %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_v2_three_artefacts\n');
    error('probe_manifest_v2_three_artefacts:failed', '%d checks failed', fail);
end

    function record(name, ok, detail)
        fprintf('%s: %s (%s)\n', name, tf(ok), detail);
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end
end

function ok = axis_has_scatter(fig, wanted_title, expected)
ok = false;
ax = find_axis(fig, wanted_title);
if isempty(ax), return; end
objects = findobj(ax, '-property', 'XData');
for k = 1:numel(objects)
    try
        actual = [objects(k).XData(:), objects(k).YData(:), objects(k).ZData(:)];
        if isequal(actual, expected), ok = true; return; end
    catch
    end
end
end

function ok = axis_has_patch(fig, wanted_title, expected)
ok = false;
ax = find_axis(fig, wanted_title);
if isempty(ax), return; end
objects = findobj(ax, 'Type', 'patch');
for k = 1:numel(objects)
    if isequal(objects(k).Vertices, expected), ok = true; return; end
end
end

function ok = axis_has_activation_colours(fig, wanted_title)
ok = false;
ax = find_axis(fig, wanted_title);
if isempty(ax), return; end
objects = findobj(ax, 'Type', 'patch');
for k = 1:numel(objects)
    colours = objects(k).FaceVertexCData;
    if isnumeric(colours) && isequal(size(colours), [3 3]) && ...
            all(isfinite(colours), 'all') && size(unique(colours, 'rows'), 1) > 1
        ok = true;
        return;
    end
end
end

function ax = find_axis(fig, wanted_title)
ax = [];
if isempty(fig), return; end
axes_handles = findall(fig, 'Type', 'axes');
for k = 1:numel(axes_handles)
    title_text = get(get(axes_handles(k), 'Title'), 'String');
    if iscell(title_text), title_text = strjoin(title_text, ' '); end
    if strcmp(title_text, wanted_title), ax = axes_handles(k); return; end
end
end

function txt = point_cloud_ply
txt = sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 0\nproperty list uchar int vertex_indices\nend_header\n' ...
    '0 0 0\n1 0 0\n0 1 0\n']);
end

function txt = mesh_ply(with_scalar)
if with_scalar
    prop = 'property float activation\n';
    rows = '20 0 0 1\n21 0 0 2\n20 1 0 3\n';
else
    prop = '';
    rows = '10 0 0\n11 0 0\n10 1 0\n';
end
txt = sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' prop ...
    'element face 1\nproperty list uchar int vertex_indices\nend_header\n' ...
    rows '3 0 1 2\n']);
end

function write_text_utf8(path, text)
fid = fopen(path, 'wb');
assert(fid >= 0, 'Could not write UTF-8 fixture: %s', path);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
end

function h = sha256f(path)
fid = fopen(path, 'rb');
assert(fid >= 0, 'Could not hash fixture: %s', path);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = fread(fid, Inf, '*uint8');
md = java.security.MessageDigest.getInstance('SHA-256');
digest = md.digest(data);
bytes = typecast(int8(digest), 'uint8');
h = lower(reshape(dec2hex(bytes, 2)', 1, []));
end

function cleanup_case(root)
try, close all force; catch, end
if exist(root, 'dir'), rmdir(root, 's'); end
end
