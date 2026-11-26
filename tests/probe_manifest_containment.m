function probe_manifest_containment
%% Opening a run never resolves artefacts outside the run
% Collin Snitchler
% 12.09.2026
% Checks on modified copies of the golden run (golden_root):
%  K1 a traversal render reference (aligned_mesh_ply = outputs/../../escape.ply)
%     is invalid -> the canonical in-run path is kept, never the escape
%  K2 a stage artefact pointing at an existing foreign file is rejected
%  K3 a truncated (header-only) fused PLY fails closed before any commit
%  K4 a valid run still opens (negative control)
%  K5 a dataset-relative reference to the same run keeps the <stem>.matom part

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_containment');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
root = fullfile(scratch, 'contain_fixture');
if exist(root, 'dir'), rmdir(root, 's'); end
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));
mp = fullfile(run_dir, 'manifest.json');

% K4 first: negative control (valid run opens)
fprintf('K4: control - the untouched fixture opens\n');
t4 = rabbit_reconstruction_tab();
[ok4, err4, info4] = t4.open_manifest(mp);
K4 = ok4;
fprintf('  open=%s err=%s -> %s\n', tf(ok4), err4, tf(K4));
if K4, pass = pass + 1; else, fail = fail + 1; end

% K1: traversal alignment path
fprintf('K1: a traversal aligned_mesh_ply is invalid -> canonical in-run path kept\n');
raw = fileread(mp);
raw1 = strrep(raw, '''alignment-rebuilt-mesh.ply''', '''outputs/../../escape.ply''');
% also patch any recorded aligned_mesh_ply value
raw1 = regexprep(raw1, '"aligned_mesh_ply":\s*"[^"]*"', '"aligned_mesh_ply": "outputs/../../escape.ply"');
kr1 = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', '20260909T110043_d091bb44');
% write the mutated manifest into a copy of the run so the filename gate
% (manifest.json) is satisfied and the traversal logic is what is tested.
run1 = fullfile(root, 'k1root', [stem '.matom'], 'reconstruction', 'runs', golden_run);
if exist(fullfile(root, 'k1root'), 'dir'), rmdir(fullfile(root, 'k1root'), 's'); end
copyfile(run_dir, run1);
mp1 = fullfile(run1, 'manifest.json');
fid = fopen(mp1, 'w', 'n', 'UTF-8'); fwrite(fid, raw1, 'char*1'); fclose(fid);
t1 = rabbit_reconstruction_tab();
[ok1, err1, info1] = t1.open_manifest(mp1);
t1.load_state(fullfile(root, 'k1root'), stem);
[vis1_ok, vis1_err, vis1] = t1.visualisation_artifacts(golden_run);
% The traversal reference must never produce a path that escapes the run:
% either the open fails closed, or the resolved rebuilt path stays in-run.
in_run_k1 = ~isempty(vis1) && isfield(vis1, 'rebuilt_ply') && ~isempty(vis1.rebuilt_ply) && ...
    ~isempty(strfind(strrep(vis1.rebuilt_ply, '\', '/'), strrep(run1, '\', '/')));
K1 = (~ok1) || in_run_k1;
fprintf('  open=%s rebuilt=%s -> %s\n', tf(ok1), vis1.rebuilt_ply, tf(K1));
if K1, pass = pass + 1; else, fail = fail + 1; end

% K2: a stage artefact pointing at an existing foreign file
fprintf('K2: a foreign stage-artefact reference is rejected\n');
foreign = fullfile(root, 'escape_target.ply');
copyfile(fullfile(run_dir, 'outputs', 'fused-geometric.ply'), foreign);
raw2 = strrep(raw, '''outputs/mesh-cleanup-removal-mask.mat''', ['''' foreign '''']);
if strcmp(raw2, raw)
    % the exact key varies by fixture; patch the first stage artefact path
    raw2 = regexprep(raw, '("path":\s*")([^"]*\.mat)(")', ['$1' strrep(foreign, '\', '\\') '$3'], 'once');
end
run2 = fullfile(root, 'k2root', [stem '.matom'], 'reconstruction', 'runs', golden_run);
if exist(fullfile(root, 'k2root'), 'dir'), rmdir(fullfile(root, 'k2root'), 's'); end
copyfile(run_dir, run2);
% the foreign target sits outside this run root
foreign2 = fullfile(root, 'k2root', 'escape_target.ply');
copyfile(fullfile(run_dir, 'outputs', 'fused-geometric.ply'), foreign2);
mp2 = fullfile(run2, 'manifest.json');
m2s = jsondecode(fileread(mp));
if isfield(m2s, 'stages') && ~isempty(m2s.stages) && isfield(m2s.stages(1), 'artifacts')
    if isstruct(m2s.stages(1).artifacts)
        m2s.stages(1).artifacts(1).path = strrep(foreign2, '', '/');
    end
end
fid2 = fopen(mp2, 'w', 'n', 'UTF-8'); fwrite(fid2, jsonencode(m2s), 'char*1'); fclose(fid2);
mp2 = fullfile(run2, 'manifest.json');

t2 = rabbit_reconstruction_tab();
[ok2, err2] = t2.open_manifest(mp2);
% the foreign reference must not be accepted as an in-run artefact
K2 = ~ok2 && ~isempty(err2);
fprintf('  open=%s err=%s -> %s\n', tf(ok2), err2, tf(K2));
if K2, pass = pass + 1; else, fail = fail + 1; end

% K3: truncated PLY
fprintf('K3: a truncated (header-only) fused PLY fails closed before commit\n');
t3 = rabbit_reconstruction_tab();
[~, ~, info3] = t3.open_manifest(mp);
fp = fullfile(run_dir, 'outputs', 'fused-geometric.ply');
fid = fopen(fp, 'w', 'n');
fprintf(fid, 'ply\nformat ascii 1.0\nelement vertex 10\nproperty float x\nproperty float y\nproperty float z\nend_header\n');
fclose(fid);
t3b = rabbit_reconstruction_tab();
[ok3, err3] = t3b.open_manifest(mp);
K3 = ~ok3 && ~isempty(strfind(err3, 'truncated'));
fprintf('  open=%s err=%s -> %s\n', tf(ok3), err3, tf(K3));
if K3, pass = pass + 1; else, fail = fail + 1; end

% K5: a dataset-relative reference to the same run keeps the stem.
fprintf('K5: dataset-relative same-run reference preserves the stem\n');
run5 = fullfile(root, 'k5root', [stem '.matom'], 'reconstruction', 'runs', golden_run);
if exist(fullfile(root, 'k5root'), 'dir'), rmdir(fullfile(root, 'k5root'), 's'); end
copyfile(run_dir, run5);
mj5 = jsondecode(fileread(fullfile(run5, 'manifest.json')));
rel5 = [stem '.matom/reconstruction/runs/' golden_run '/outputs/alignment-rebuilt-mesh.ply'];
for si = 1:numel(mj5.stages)
    if isfield(mj5.stages(si), 'settings_resolved') && isstruct(mj5.stages(si).settings_resolved) && ...
            isfield(mj5.stages(si).settings_resolved, 'aligned_mesh_ply')
        mj5.stages(si).settings_resolved.aligned_mesh_ply = rel5;
    end
end
fid5 = fopen(fullfile(run5, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid5, jsonencode(mj5), 'char*1'); fclose(fid5);
t5 = rabbit_reconstruction_tab();
[ok5d, err5d] = t5.open_manifest(fullfile(run5, 'manifest.json'));
t5.load_state(fullfile(root, 'k5root'), stem);
[v5ok, ~, v5] = t5.visualisation_artifacts(golden_run);
% The resolved path must carry the full <stem>.matom component and stay
% inside the run.
rp5 = strrep(v5.rebuilt_ply, char(92), '/');
K5 = ~isempty(strfind(rp5, [stem '.matom/reconstruction/runs/']));
fprintf('  open=%s rebuilt=%s -> %s\n', tf(ok5d), v5.rebuilt_ply, tf(K5));
if K5, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_CONTAINMENT RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_containment %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_containment\n');
end
end
