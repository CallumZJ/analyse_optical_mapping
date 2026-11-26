function probe_manifest_partial_runs
%% Partial runs open, completed partial runs fail closed
% Collin Snitchler
% 12.09.2026
% CREATED and RUNNING runs open with the three-PLY check skipped; a COMPLETED
% run with a missing PLY still fails closed. Needs the golden run at golden_root.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_partial_runs');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

make_fixture = @(name, status) local_make(fullfile(scratch, name), gdir, stem, golden_run, status);

% --- CASE 1: RUNNING, no PLYs at all (mid-pipeline crash) ---
root1 = make_fixture('partial_running', 'RUNNING');
tab1 = rabbit_reconstruction_tab();
[ok1, err1, info1] = tab1.open_manifest(fullfile(root1, [stem '.matom'], 'reconstruction', 'runs', golden_run, 'manifest.json'));
flush_sidecar(tab1, info1);
C1 = ok1 && info1.partial_exempt && strcmp(info1.result_status, 'RUNNING');
fprintf('C1 RUNNING partial opens: ok=%s exempt=%s err=%s -> %s\n', tf(ok1), ...
    tf(ok1 && info1.partial_exempt), err1, tf(C1));
if C1, pass = pass + 1; else, fail = fail + 1; end

% --- CASE 2: CREATED, empty stages, no PLYs ---
root2 = make_fixture('partial_created', 'CREATED');
tab2 = rabbit_reconstruction_tab();
[ok2, err2, info2] = tab2.open_manifest(fullfile(root2, [stem '.matom'], 'reconstruction', 'runs', golden_run, 'manifest.json'));
C2 = ok2 && info2.partial_exempt && strcmp(info2.result_status, 'CREATED');
fprintf('C2 CREATED partial opens: ok=%s exempt=%s err=%s -> %s\n', tf(ok2), ...
    tf(ok2 && info2.partial_exempt), err2, tf(C2));
if C2, pass = pass + 1; else, fail = fail + 1; end

% --- CASE 3: COMPLETED with a missing PLY -> fail closed ---
root3 = make_fixture('partial_completed', 'COMPLETED');
tab3 = rabbit_reconstruction_tab();
[ok3, err3, ~] = tab3.open_manifest(fullfile(root3, [stem '.matom'], 'reconstruction', 'runs', golden_run, 'manifest.json'));
C3 = ~ok3 && ~isempty(strfind(err3, 'missing referenced artefacts'));
fprintf('C3 COMPLETED partial fails closed: ok=%s names-artefacts=%s -> %s\n', tf(~ok3), ...
    tf(~isempty(strfind(err3, 'missing referenced artefacts'))), tf(C3));
if C3, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_PARTIAL_RUNS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_partial_runs %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_partial_runs\n');
end
end

function root = local_make(root, gdir, stem, golden_run, status)
if exist(root, 'dir'), rmdir(root, 's'); end
run = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run));
copyfile(gdir, run);
delete(fullfile(run, 'outputs', 'fused-geometric.ply'));
delete(fullfile(run, 'outputs', 'alignment-rebuilt-mesh.ply'));
delete(fullfile(run, 'outputs', 'reprojection', 'activation_projected.ply'));
raw = fileread(fullfile(run, 'manifest.json'));
raw = strrep(raw, '"status": "COMPLETED"', ['"status": "' status '"']);
if any(strcmp(status, {'CREATED', 'RUNNING'}))
    % empty stages: replace the stages array with []
    i1 = strfind(raw, '"stages": [');
    if ~isempty(i1)
        % find the matching close: scan brackets
        i2 = i1(1) + numel('"stages": ');
        depth = 0; j = i2;
        while j <= numel(raw)
            if raw(j) == '[', depth = depth + 1;
            elseif raw(j) == ']'
                depth = depth - 1;
                if depth == 0, break; end
            end
            j = j + 1;
        end
        raw = [raw(1:i2-1) '[]' raw(j+1:end)];
    end
end
fid = fopen(fullfile(run, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, raw, 'char*1'); fclose(fid);
end

function flush_sidecar(tab, info)
%FLUSH_SIDECAR Write the sidecar as the app does after a successful commit.
%open_manifest is read-only; the sidecar is written only after the app
%state has been committed.
if isstruct(info) && isfield(info, 'sidecar_pending_bytes') && ~isempty(info.sidecar_pending_bytes)
    tab.write_sidecar_after_commit(info.run_dir, info.sidecar_pending_bytes);
end
end
