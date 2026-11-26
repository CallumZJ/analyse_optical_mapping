function probe_restore_gui_safety
%% GUI safety checks for restored runs
% Collin Snitchler
% 12.09.2026
%  U1 restore clears unavailable sparse/images/ROI inputs and gates Run.
%  U2 direct-v2-only provenance is read-only and gates actions.
%  U3 unreadable-v1-sibling provenance is read-only and gates actions.
%  U4 durable status is reconciled from native manifest.v2.json.
%  U5 manual Visualise revalidation rejects a deleted artefact.
%  U6 an empty successful visualiser result updates status (no stale text).
%
% The source and test fixture roots are configured independently so this probe
% does not depend on the caller's current directory or MATLAB path order.
% OM_TEST_RESTORE_GOLDEN_ROOT selects the golden fixture (default tests/fixtures).
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
% The golden run itself is looked for (the tracked fixture folder holds
% only the reprojection oracle); without it a SKIP line is printed
fixture_root = om_restore_fixture_paths('probe_restore_gui_safety');
if isempty(fixture_root), return; end

golden_run = '20260909T110043_d091bb44';
stem = 'subset';
root = fullfile(tempdir, 'om_test_probe_restore_gui_safety');
if exist(root, 'dir'), rmdir(root, 's'); end
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
gdir = fullfile(fixture_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
assert(exist(gdir, 'dir') == 7, 'The golden run fixture is missing.');
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);
mp = fullfile(run_dir, 'manifest.json');

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

fprintf('U1: restore clears unavailable inputs and gates Run\n');
a = analyse_optical_mapping;
a.recon.ReconstructionSparseField.Value = 'stale-sparse';
a.recon.ReconstructionImagesField.Value = 'stale-images';
a.recon.ReconstructionRoiField.Value = 'stale-roi';
a.recon.test_manifest_pick = mp;
a.recon.OpenReconstructionManifestMenuSelected();
U1 = isempty(a.recon.ReconstructionSparseField.Value) && ...
    isempty(a.recon.ReconstructionImagesField.Value) && ...
    isempty(a.recon.ReconstructionRoiField.Value) && ...
    strcmp(a.recon.ReconstructionRunButton.Enable, 'off');
fprintf('  fields-cleared(%s) run-gated(%s) -> %s\n', ...
    tf(isempty(a.recon.ReconstructionSparseField.Value) && isempty(a.recon.ReconstructionImagesField.Value) && isempty(a.recon.ReconstructionRoiField.Value)), ...
    tf(strcmp(a.recon.ReconstructionRunButton.Enable, 'off')), tf(U1));
if U1, pass = pass + 1; else, fail = fail + 1; end

fprintf('U2: direct-v2-only provenance fails closed\n');
v2root = fullfile(tempdir, 'om_test_probe_restore_gui_safety_v2_only');
if exist(v2root, 'dir'), rmdir(v2root, 's'); end
v2run = fullfile(v2root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(v2run));
copyfile(run_dir, v2run);
delete(fullfile(v2run, 'manifest.json'));
b = analyse_optical_mapping;
b.recon.test_manifest_pick = fullfile(v2run, 'manifest.v2.json');
b.recon.OpenReconstructionManifestMenuSelected();
[prov2, err2] = b.recon.reconstruction_validate_manifest_provenance(golden_run);
U2 = ~prov2 && ~isempty(strfind(lower(err2), 'unverified')) && ...
    strcmp(b.recon.ReconstructionVisualiseButton.Enable, 'off') && ...
    strcmp(b.recon.TouchupApplyButton.Enable, 'off');
fprintf('  validator-blocked(%s) visualise-gated(%s) derived-gated(%s) -> %s\n', ...
    tf(~prov2), tf(strcmp(b.recon.ReconstructionVisualiseButton.Enable, 'off')), ...
    tf(strcmp(b.recon.TouchupApplyButton.Enable, 'off')), tf(U2));
if U2, pass = pass + 1; else, fail = fail + 1; end

fprintf('U3: unreadable manifest.json sibling fails closed\n');
badroot = fullfile(tempdir, 'om_test_probe_restore_gui_safety_bad_sibling');
if exist(badroot, 'dir'), rmdir(badroot, 's'); end
badrun = fullfile(badroot, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(badrun));
copyfile(v2run, badrun);
fid = fopen(fullfile(badrun, 'manifest.json'), 'wb');
fwrite(fid, uint8('{ unreadable-json')); fclose(fid);
m3 = jsondecode(fileread(fullfile(badrun, 'manifest.v2.json'))); assert(isfield(m3, 'manifest_schema')); 
c = analyse_optical_mapping;
c.recon.test_manifest_pick = fullfile(badrun, 'manifest.v2.json');
c.recon.OpenReconstructionManifestMenuSelected();
[prov3, err3] = c.recon.reconstruction_validate_manifest_provenance(golden_run);
fprintf('  detail=%s\n', err3);
U3 = ~prov3 && ~isempty(strfind(lower(err3), 'unverified')) && ...
    strcmp(c.recon.ReconstructionReprojectButton.Enable, 'off');
fprintf('  validator-blocked(%s) reprojection-gated(%s) -> %s\n', ...
    tf(~prov3), tf(strcmp(c.recon.ReconstructionReprojectButton.Enable, 'off')), tf(U3));
if U3, pass = pass + 1; else, fail = fail + 1; end

fprintf('U4: durable status reads native manifest.v2.json\n');
status4 = b.recon.reconstruction_manifest_status(golden_run);
U4 = strcmp(status4, 'COMPLETED');
fprintf('  status=%s expected=COMPLETED -> %s\n', status4, tf(U4));
if U4, pass = pass + 1; else, fail = fail + 1; end

fprintf('U5: manual Visualise readiness revalidates artefacts\n');
projected = fullfile(v2run, 'outputs', 'reprojection', 'activation_projected.ply');
projected_copy = [projected '.probe_backup'];
copyfile(projected, projected_copy);
delete(projected);
[ready5, ~] = b.recon.reconstruction_visualise_ready(golden_run);
copyfile(projected_copy, projected);
delete(projected_copy);
U5 = ~ready5;
fprintf('  deleted-projected-ready(%s) -> %s\n', tf(ready5), tf(U5));
if U5, pass = pass + 1; else, fail = fail + 1; end

fprintf('U6: empty successful visualiser clears stale status\n');
a.recon.test_visualise_empty = true;
a.recon.OpenReconstructionManifestMenuSelected();
vst6 = strjoin(a.recon.VisualiseStatusText.Value, ' ');
U6 = ~isempty(strfind(lower(vst6), 'produced no figures'));
fprintf('  status=%s -> %s\n', vst6, tf(U6));
if U6, pass = pass + 1; else, fail = fail + 1; end

close all force;
if exist(root, 'dir'), rmdir(root, 's'); end
if exist(v2root, 'dir'), rmdir(v2root, 's'); end
if exist(badroot, 'dir'), rmdir(badroot, 's'); end
fprintf('PROBE_RESTORE_GUI_SAFETY RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_restore_gui_safety %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_restore_gui_safety\n');
end
end
