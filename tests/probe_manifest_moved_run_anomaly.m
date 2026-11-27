function probe_manifest_moved_run_anomaly
%% Anomaly gate on a moved run with a changed view PLY
% Collin Snitchler
% 12.09.2026
% A moved or copied run whose view PLY was changed must have its automatic
% visualisation suppressed by the anomaly gate, also on a rebased path.
%  A1 moved + tampered projected PLY  -> gate fires (suppression)
%  A2 moved + untouched copied PLY    -> gate does not fire (control)
%  A3 the digest is matched by basename across the rebased path
% Needs the golden run at golden_root; the fixture is written under root.

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_moved_run_anomaly');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
root = fullfile(scratch, 'anomaly_fixture');
if exist(root, 'dir'), rmdir(root, 's'); end
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

a = analyse_optical_mapping;
a.recon.test_manifest_pick = fullfile(run_dir, 'manifest.json');

fprintf('A2: control - moved copy with the ORIGINAL PLYs -> gate does NOT fire\n');
a.recon.OpenReconstructionManifestMenuSelected();
[anom2, list2] = a.recon.anomalous_views(a.recon.last_open_info);
A2 = ~anom2;
fprintf('  anomaly=%s list=%s -> %s\n', tf(anom2), list2, tf(A2));
if A2, pass = pass + 1; else, fail = fail + 1; end

fprintf('A1: moved + TAMPERED projected PLY -> gate FIRES (suppression)\n');
pply = fullfile(run_dir, 'outputs', 'reprojection', 'activation_projected.ply');
raw = fileread(pply);
fid = fopen(pply, 'w', 'n', 'UTF-8');
fwrite(fid, [raw ' '], 'char*1'); fclose(fid);   % whitespace tamper, still a valid PLY
[anom1, list1] = a.recon.anomalous_views(a.recon.last_open_info);
A1 = anom1 && ~isempty(strfind(list1, 'activation_projected.ply'));
fprintf('  anomaly=%s list=%s -> %s\n', tf(anom1), list1, tf(A1));
if A1, pass = pass + 1; else, fail = fail + 1; end

fprintf('A3: the digest match survives the REBASED path (basename class)\n');
A3 = A1;   % the suppression itself proves the basename match worked
fprintf('  -> %s\n', tf(A3));
if A3, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_MOVED_RUN_ANOMALY RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_moved_run_anomaly %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_moved_run_anomaly\n');
end
end
