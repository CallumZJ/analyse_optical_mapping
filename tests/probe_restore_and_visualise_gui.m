function probe_restore_and_visualise_gui
%% GUI smoke test: restore a run and visualise it automatically
% Collin Snitchler
% 12.09.2026
% Runs the app on a copy of the golden run (golden_root); needs a display.
%  G1 the open callback runs the staged sequence and populates the tab
%  G2 the restore summary is appended (restored vs still required)
%  G3 auto-visualise renders (figure count rises) and the status text says so
%  G4 the injected failure path leaves the session committed with the error
%  G5 the v1 manifest and source PLYs are byte-identical after the flow
%  G6 re-open raises rather than duplicating? (recorded, not asserted)

% Use the repository app and backend.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);

addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_restore_and_visualise_gui');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
root = fullfile(scratch, 'gui_fixture');
if exist(root, 'dir'), rmdir(root, 's'); end
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);
mp = fullfile(run_dir, 'manifest.json');
sha_before = sha256f(mp);
sha_fused = sha256f(fullfile(run_dir, 'outputs', 'fused-geometric.ply'));

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

try
    fig_before = numel(findall(0, 'Type', 'figure'));
catch
    fig_before = 0;
end

fprintf('G1: open callback runs the staged sequence and populates the tab\n');
a = analyse_optical_mapping;
% Inject the file pick through the app's test_manifest_pick property, so no
% uigetfile shim is needed.
a.recon.test_manifest_pick = mp;
a.recon.OpenReconstructionManifestMenuSelected();
G1 = ~isempty(strfind(a.recon.ReconstructionDatasetField.Value, [stem '.matom'])) && ...
    numel(a.recon.ReconstructionRunList.Items) == 1 && ...
    numel(a.recon.ReconstructionStageList.Items) == 8;
fprintf('  dataset(%s) runlist(%d) stagelist(%d) -> %s\n', ...
    tf(~isempty(strfind(a.recon.ReconstructionDatasetField.Value, [stem '.matom']))), ...
    numel(a.recon.ReconstructionRunList.Items), numel(a.recon.ReconstructionStageList.Items), tf(G1));
if G1, pass = pass + 1; else, fail = fail + 1; end

fprintf('G2: restore summary appended (restored vs still required)\n');
txt = strjoin(a.recon.ReconstructionResultsText.Value, ' | ');
G2 = ~isempty(strfind(txt, 'Opened saved run')) && ~isempty(strfind(txt, 'Still required'));
fprintf('  restored(%s) still-required(%s)\n  text=%s\n', ...
    tf(~isempty(strfind(txt, 'Opened saved run'))), tf(~isempty(strfind(txt, 'Still required'))), txt(max(1,end-260):end));
if G2, pass = pass + 1; else, fail = fail + 1; end

fprintf('G3: auto-visualise rendered a figure\n');
drawnow;
figs_after = numel(findall(0, 'Type', 'figure'));
vst = strjoin(a.recon.VisualiseStatusText.Value, ' ');
G3 = figs_after > fig_before && (~isempty(strfind(vst, 'visualised')) || ~isempty(strfind(vst, 'deferred')) || ~isempty(strfind(vst, 'failed')));
fprintf('  figs %d -> %d; status=%s -> %s\n', fig_before, figs_after, vst, tf(G3));
if G3, pass = pass + 1; else, fail = fail + 1; end

fprintf('G4: injected failure leaves the session committed with the error\n');
fig2 = numel(findall(0, 'Type', 'figure'));
a.recon.test_visualise_fails = 'analyse_om:Reconstruction:TestInjected:visualise_artifacts_handle';
a.recon.OpenReconstructionManifestMenuSelected();
vst2 = strjoin(a.recon.VisualiseStatusText.Value, ' ');
G4 = ~isempty(strfind(vst2, 'failed')) && numel(findall(0, 'Type', 'figure')) == fig2 && ...
    numel(a.recon.ReconstructionRunList.Items) == 1;
a.recon.test_visualise_fails = '';
fprintf('  status=%s figures-unchanged(%s) runlist(%d) -> %s\n', vst2, ...
    tf(numel(findall(0, 'Type', 'figure')) == fig2), numel(a.recon.ReconstructionRunList.Items), tf(G4));
if G4, pass = pass + 1; else, fail = fail + 1; end

fprintf('G5: manifest.json + source PLY byte-identical after the whole flow\n');
G5 = strcmp(sha_before, sha256f(mp)) && ...
    strcmp(sha_fused, sha256f(fullfile(run_dir, 'outputs', 'fused-geometric.ply')));
fprintf('  manifest(%s) fused(%s) -> %s\n', tf(strcmp(sha_before, sha256f(mp))), ...
    tf(strcmp(sha_fused, sha256f(fullfile(run_dir, 'outputs', 'fused-geometric.ply')))), tf(G5));
if G5, pass = pass + 1; else, fail = fail + 1; end

fprintf('G6: sidecar written by the open\n');
G6 = exist(fullfile(run_dir, 'manifest.v2.json'), 'file') == 2;
fprintf('  sidecar(%s) -> %s\n', tf(G6), tf(G6));
if G6, pass = pass + 1; else, fail = fail + 1; end

close all force;
fprintf('PROBE_RESTORE_AND_VISUALISE_GUI RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_restore_and_visualise_gui %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_restore_and_visualise_gui\n');
end
end

function h = sha256f(p)
fid = fopen(p, 'rb');
if fid < 0, h = ''; return; end
data = fread(fid, Inf, '*uint8');
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
dg = md.digest(data);
ub = typecast(int8(dg), 'uint8');
h = lower(reshape(dec2hex(ub, 2)', 1, []));
end
