function probe_manifest_moved_run
%% Moved or copied runs resolve their own artefacts
% Collin Snitchler
% 12.09.2026
% A moved or copied run must resolve its own artefacts by rebasing the paths,
% not the original files. The golden manifest records absolute paths into the
% original staging tree; the fixture is a full copy at a different root. A
% second copy carries only the three view PLYs, so a missing stage output must
% fail closed rather than fall back to the original file.
% Needs the golden run at golden_root; copies are written under base.

% Use the repository source in the folder above tests.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_moved_run');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
base = fullfile(scratch, 'moved');
pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

if exist(base, 'dir'), rmdir(base, 's'); end
run_dir = fullfile(base, 'elsewhere', [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);

fprintf('M1: open_manifest resolves the three views INSIDE the moved copy\n');
tab = rabbit_reconstruction_tab();
[ok, err, info] = tab.open_manifest(fullfile(run_dir, 'manifest.json'));
in_run = @(p) ~isempty(strfind(strrep(p, '\', '/'), strrep(run_dir, '\', '/')));
M1 = ok && in_run(info.fused_ply) && in_run(info.rebuilt_ply) && in_run(info.projected_ply);
fprintf('  open(%s) fused-in(%s) rebuilt-in(%s) projected-in(%s)\n', tf(ok), ...
    tf(in_run(info.fused_ply)), tf(in_run(info.rebuilt_ply)), tf(in_run(info.projected_ply)));
fprintf('    fused=%s\n    rebuilt=%s\n    projected=%s\n', info.fused_ply, info.rebuilt_ply, info.projected_ply);
if M1, pass = pass + 1; else, fail = fail + 1; end

fprintf('M2: visualisation_artifacts resolves the same rebased paths\n');
tab.load_state(fullfile(base, 'elsewhere'), stem);
[ok2, err2, vis] = tab.visualisation_artifacts(golden_run);
M2 = ok2 && in_run(vis.fused_ply) && in_run(vis.rebuilt_ply) && in_run(vis.projected_ply);
fprintf('  ok(%s) all-in(%s) err=%s\n', tf(ok2), ...
    tf(ok2 && in_run(vis.fused_ply) && in_run(vis.rebuilt_ply) && in_run(vis.projected_ply)), err2);
if M2, pass = pass + 1; else, fail = fail + 1; end

fprintf('M3: the archive ORIGINAL is never the resolved rebuilt path\n');
orig_rebuilt = fullfile(gdir, 'outputs', 'alignment-rebuilt-mesh.ply');
M3 = isstruct(vis) && isfield(vis, 'rebuilt_ply') && ~strcmp(strrep(vis.rebuilt_ply, '\', '/'), strrep(orig_rebuilt, '\', '/'));
fprintf('  resolved!=original(%s)\n', tf(M3));
if M3, pass = pass + 1; else, fail = fail + 1; end

fprintf('M4: the resolved rebuilt file exists (rebasing finds the copy)\n');
M4 = isstruct(vis) && isfield(vis, 'rebuilt_ply') && exist(vis.rebuilt_ply, 'file') == 2;
fprintf('  exists(%s)\n', tf(M4));
if M4, pass = pass + 1; else, fail = fail + 1; end

fprintf('M5: moved copy with an absent stage output fails closed\n');
missing_base = fullfile(base, 'missing-stage');
if exist(missing_base, 'dir'), rmdir(missing_base, 's'); end
missing_run = fullfile(missing_base, 'elsewhere', [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fullfile(missing_run, 'outputs', 'reprojection'));
copyfile(fullfile(gdir, 'manifest.json'), fullfile(missing_run, 'manifest.json'));
copyfile(fullfile(gdir, 'outputs', 'fused-geometric.ply'), fullfile(missing_run, 'outputs', 'fused-geometric.ply'));
copyfile(fullfile(gdir, 'outputs', 'alignment-rebuilt-mesh.ply'), fullfile(missing_run, 'outputs', 'alignment-rebuilt-mesh.ply'));
copyfile(fullfile(gdir, 'outputs', 'reprojection', 'activation_projected.ply'), fullfile(missing_run, 'outputs', 'reprojection', 'activation_projected.ply'));
tab_missing = rabbit_reconstruction_tab();
[ok_missing, err_missing, ~] = tab_missing.open_manifest(fullfile(missing_run, 'manifest.json'));
M5 = ~ok_missing && ~isempty(strfind(err_missing, 'missing referenced artefacts')) && ...
    isempty(strfind(err_missing, 'manifest.v2.json'));
fprintf('  fails(%s) names-missing(%s) no-sidecar-error(%s)\n', tf(~ok_missing), ...
    tf(~isempty(strfind(err_missing, 'missing referenced artefacts'))), tf(isempty(strfind(err_missing, 'manifest.v2.json'))));
if M5, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_MOVED_RUN RESULT: %d passed, %d failed\n', pass, fail);

if fail == 0
    fprintf('PROBE_OK probe_manifest_moved_run %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_moved_run\n');
end
end

function flush_sidecar(tab, info)
%FLUSH_SIDECAR Write the sidecar as the app does after a successful commit.
%open_manifest is read-only; the sidecar is written only after the app
%state has been committed.
if isstruct(info) && isfield(info, 'sidecar_pending_bytes') && ~isempty(info.sidecar_pending_bytes)
    tab.write_sidecar_after_commit(info.run_dir, info.sidecar_pending_bytes);
end
end
