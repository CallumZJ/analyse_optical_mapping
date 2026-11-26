function probe_manifest_singleton_collections
%% Single-element v1 collections become valid v2 arrays
% Collin Snitchler
% 12.09.2026
% The converted arrays must still pass the frozen-field validation.
% Needs the golden run at golden_root.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_singleton_collections');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
gdir = fullfile(golden_root, 'subset.matom', 'reconstruction', 'runs', golden_run);
root = fullfile(tempdir, ['c22a_singleton_' char(java.util.UUID.randomUUID())]);
run_dir = fullfile(root, 'subset.matom', 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_dir));
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>
copyfile(gdir, run_dir);
m = jsondecode(fileread(fullfile(gdir, 'manifest.json')));
m.inputs.files = m.inputs.files(1);
m.unicode_note = 'μ';
m.stages = m.stages(1);
if isfield(m, 'deviations') && isstruct(m.deviations) && numel(m.deviations) > 1
    m.deviations = m.deviations(1);
end
write_json(fullfile(run_dir, 'manifest.json'), m);
t1 = rabbit_reconstruction_tab();
[ok1, err1, info1] = t1.open_manifest(fullfile(run_dir, 'manifest.json'));
if ok1 && isfield(info1, 'sidecar_pending_bytes')
    [sw_ok, sw_err] = t1.write_sidecar_after_commit(run_dir, info1.sidecar_pending_bytes);
else
    sw_ok = false; sw_err = err1;
end
t2 = rabbit_reconstruction_tab();
[ok2, err2, info2] = t2.open_manifest(fullfile(run_dir, 'manifest.v2.json'));
raw = '';
if exist(fullfile(run_dir, 'manifest.v2.json'), 'file')
    raw = fileread(fullfile(run_dir, 'manifest.v2.json'));
end
S = struct();
try
    S = jsondecode(raw);
catch
end
shape_ok = isstruct(S) && iscell(S.stages) == false && numel(S.stages) == 1 && ...
    isfield(S, 'inputs') && numel(S.inputs.files) == 1;
result = ok1 && sw_ok && ok2 && strcmp(info2.open_kind, 'VALID_V2') && shape_ok;
fprintf('singleton conversion/open=%s/%s write=%s reopen=%s shape=%s\n', ...
    tf(ok1), tf(ok2), tf(sw_ok), tf(strcmp(info2.open_kind, 'VALID_V2')), tf(shape_ok));
if ~result
    fprintf('  err1=%s sw_err=%s err2=%s kind=%s warn=%s\n', err1, sw_err, err2, info2.open_kind, info2.open_warning);
    fprintf('PROBE_FAIL probe_manifest_singleton_collections\n');
else
    fprintf('PROBE_OK probe_manifest_singleton_collections\n');
end
end

function write_json(path, m)
fid = fopen(path, 'wb');
assert(fid >= 0, 'could not write fixture');
fwrite(fid, unicode2native(jsonencode(m), 'UTF-8'), 'uint8');
fclose(fid);
end

function s = tf(b)
if b, s = 'T'; else, s = 'F'; end
end

function cleanup_case(root)
if exist(root, 'dir'), rmdir(root, 's'); end
end
