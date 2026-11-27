function probe_camera_view_restore
%% Camera view restore, apply and close
% Collin Snitchler
% 13.09.2026
% Restores, applies and closes the saved camera view on a copy of the golden
% run. Set OM_TEST_REPROJECTION_GOLDEN_ROOT to the golden fixture root.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
golden_root = om_test_getenv('OM_TEST_REPROJECTION_GOLDEN_ROOT');
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
if isempty(golden_root) || ~isfolder(fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run))
    fprintf(['SKIP probe_camera_view_restore: set OM_TEST_REPROJECTION_GOLDEN_ROOT to the folder ' ...
        'holding subset.matom with the golden run %s.\n'], golden_run);
    return;
end
root = fullfile(tempdir, 'om_test_probe_camera_view_restore');
if exist(root, 'dir'), rmdir(root, 's'); end
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);
mp = fullfile(run_dir, 'manifest.json');
tab = rabbit_reconstruction_tab();
[opened, open_err, info] = tab.open_manifest(mp);
if ~opened, error('open_manifest failed: %s', open_err); end
if ~exist(fullfile(run_dir, 'manifest.v2.json'), 'file') && ...
        isfield(info, 'sidecar_pending_bytes') && ~isempty(info.sidecar_pending_bytes)
    [sidecar_ok, sidecar_err] = tab.write_sidecar_after_commit(run_dir, info.sidecar_pending_bytes);
    if ~sidecar_ok, error('sidecar preparation failed: %s', sidecar_err); end
end
tab.load_state(root, stem);
[sha_ok, origin_sha, sha_err] = tab.manifest_bytes_sha256(fullfile(run_dir, 'manifest.v2.json'));
if ~sha_ok, error('manifest digest failed: %s', sha_err); end
[m0, m0ok] = tab.read_manifest_json(fullfile(run_dir, 'manifest.v2.json'));
if ~m0ok, error('v2 decode failed before visualisation'); end
raw = struct('position', [3 4 5], 'target', [0 0 0], 'up', [0 0 1], ...
    'view_angle', 31, 'limits', struct( ...
    'fused', struct('x', [-3 3], 'y', [-4 4], 'z', [-5 5]), ...
    'rebuilt', struct('x', [-2 2], 'y', [-3 3], 'z', [-4 4]), ...
    'projected', struct('x', [-1 1], 'y', [-2 2], 'z', [-3 3])));
[cam_ok, cam_err, camera_wire] = tab.validate_camera_state(raw);
if ~cam_ok, error('camera validation failed: %s', cam_err); end
vis = struct('run_id', info.run_id, 'run_dir', run_dir, ...
    'fused_ply', info.fused_ply, 'rebuilt_ply', info.rebuilt_ply, ...
    'projected_ply', info.projected_ply, 'camera_state', camera_wire, ...
    'camera_origin_sha256', origin_sha, ...
    'camera_origin_revision', char(m0.phase1_revision));
[shown, show_err, fig] = tab.visualise_artifacts(vis);
if ~shown, error('visualise_artifacts failed: %s', show_err); end
status = getappdata(fig, 'reconstruction_camera_restore_status');
axs = getappdata(fig, 'reconstruction_axes_handles');
positions = zeros(3, 3);
for k = 1:3, positions(k, :) = get(axs(k), 'CameraPosition'); end
position_delta = positions - repmat(raw.position, 3, 1);
B2V1 = strcmp(status, 'AVAILABLE') && all(abs(position_delta) < 1e-12, 'all');
fprintf('B2V1: sidecar camera is applied to all three linked axes -> %s status=%s\n', tf(B2V1), status);
fprintf(' expected=[%.6g %.6g %.6g] actual1=[%.6g %.6g %.6g] actual2=[%.6g %.6g %.6g] actual3=[%.6g %.6g %.6g]\n', ...
    raw.position, positions(1,:), positions(2,:), positions(3,:));
if isgraphics(fig), tab.close_visualisation(fig); end
if isgraphics(fig), tab.close_visualisation(fig); end
[m1, m1ok] = tab.read_manifest_json(fullfile(run_dir, 'manifest.v2.json'));
if ~m1ok, error('v2 decode failed after visualisation'); end
B2V2 = isstruct(m1.restore.camera) && strcmp(m1.restore.camera.status, 'AVAILABLE') && ...
    strcmp(char(m1.field_revisions.camera), '1') && strcmp(char(m1.field_revisions.activation_map), '0') && ...
    strcmp(char(m1.phase1_revision), '1');
fprintf('B2V2: close persists camera only and leaves activation revision unchanged -> %s\n', tf(B2V2));

fprintf('PROBE_CAMERA_VIEW_RESTORE RESULT: %d passed, %d failed\n', B2V1 + B2V2, 2 - B2V1 - B2V2);
if ~(B2V1 && B2V2), error('PROBE_FAIL probe_camera_view_restore'); end
fprintf('PROBE_OK probe_camera_view_restore 2/0\n');

end

function out = tf(v)
if v, out = 'T'; else, out = 'F'; end
end
