function probe_manifest_open_smoke
%% Smoke test for opening v1 and v2 manifests
% Collin Snitchler
% 12.09.2026
% Runs on scratch copies of the golden run (golden_root) and checks:
%  S1 v1-only open succeeds + sidecar written + v1 bytes untouched
%  S2 re-open is idempotent (sidecar not rewritten)
%  S3 native v2 path opens; active source is the sidecar
%  S4 v1 mismatch -> stale warning, no silent re-convert
%  S5 reserved-name v1 opens as v1, no sidecar
%  S6 determinism of the conversion (two conversions byte-identical)

% Use the repository source in the folder above tests.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
assert(exist('rabbit_reconstruction_tab', 'file') > 0, 'repo backend not found');

addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_open_smoke');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

% ---- fixture: scratch copy of the golden run (manifest + 3 PLYs) ----
root = fullfile(scratch, 'smoke_fixture');
if exist(root, 'dir'), rmdir(root, 's'); end
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);

sha_v1_before = sha256f(fullfile(run_dir, 'manifest.json'));

fprintf('S1: v1-only open succeeds; sidecar written; v1 bytes unchanged\n');
tab = rabbit_reconstruction_tab();
[ok1, err1, info1] = tab.open_manifest(fullfile(run_dir, 'manifest.json'));
flush_sidecar(tab, info1);   % the sidecar is written after the commit
sidecar = fullfile(run_dir, 'manifest.v2.json');
S1 = ok1 && exist(sidecar, 'file') == 2 && strcmp(sha_v1_before, sha256f(fullfile(run_dir, 'manifest.json'))) ...
    && strcmp(info1.run_id, golden_run) && isfield(info1, 'active_manifest_path');
fprintf('  open(%s) sidecar(%s) v1-unchanged(%s) err=%s -> %s\n', tf(ok1), tf(exist(sidecar,'file')==2), ...
    tf(strcmp(sha_v1_before, sha256f(fullfile(run_dir, 'manifest.json')))), err1, tf(S1));
if S1, pass = pass + 1; else, fail = fail + 1; end

fprintf('S2: re-open idempotent (sidecar mtime unchanged)\n');
d2a = dir(sidecar);
pause(1.1);
tab2 = rabbit_reconstruction_tab();
[ok2, err2, info2] = tab2.open_manifest(fullfile(run_dir, 'manifest.json'));
d2b = dir(sidecar);
S2 = ok2 && d2a.datenum == d2b.datenum && strcmp(info2.active_manifest_path, sidecar);
fprintf('  open(%s) mtime-same(%s) active-is-sidecar(%s) err=%s -> %s\n', tf(ok2), ...
    tf(d2a.datenum == d2b.datenum), tf(strcmp(info2.active_manifest_path, sidecar)), err2, tf(S2));
if S2, pass = pass + 1; else, fail = fail + 1; end

fprintf('S3: native v2 path opens; active source = sidecar\n');
tab3 = rabbit_reconstruction_tab();
[ok3, err3, info3] = tab3.open_manifest(sidecar);
S3 = ok3 && strcmp(info3.active_manifest_path, sidecar) && ...
    strcmp(info3.active_manifest_schema, 'cd2.reconstruction.manifest.v2');
fprintf('  open(%s) active(%s) schema(%s) err=%s -> %s\n', tf(ok3), ...
    tf(strcmp(info3.active_manifest_path, sidecar)), info3.active_manifest_schema, err3, tf(S3));
if S3, pass = pass + 1; else, fail = fail + 1; end

fprintf('S4: v1 edited -> stale warning; no silent re-convert\n');
raw = fileread(fullfile(run_dir, 'manifest.json'));
% Keep the v1 result.status within its closed enum; a byte-only edit is
% sufficient to exercise the stale-sidecar resolver branch.
raw2 = [raw ' '];
fid = fopen(fullfile(run_dir, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, raw2, 'char*1'); fclose(fid);
sha_stale_v1 = sha256f(fullfile(run_dir, 'manifest.json'));
d4a = dir(sidecar);
tab4 = rabbit_reconstruction_tab();
[ok4, err4, info4] = tab4.open_manifest(fullfile(run_dir, 'manifest.json'));
d4b = dir(sidecar);
S4 = ok4 && ~isempty(strfind(info4.open_warning, 'out of date')) && d4a.datenum == d4b.datenum ...
    && strcmp(info4.active_manifest_path, fullfile(run_dir, 'manifest.json'));
fprintf('  open(%s) warning(%s) sidecar-unwritten(%s) active-v1(%s) -> %s\n', tf(ok4), ...
    tf(~isempty(strfind(info4.open_warning, 'out of date'))), tf(d4a.datenum == d4b.datenum), ...
    tf(strcmp(info4.active_manifest_path, fullfile(run_dir, 'manifest.json'))), tf(S4));
if S4, pass = pass + 1; else, fail = fail + 1; end

fprintf('S5: reserved-name v1 opens as v1, not converted, no sidecar write\n');
root5 = fullfile(scratch, 'smoke_reserved');
if exist(root5, 'dir'), rmdir(root5, 's'); end
run5 = fullfile(root5, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run5));
copyfile(gdir, run5);
copyfile(fullfile(run_dir, 'manifest.json'), fullfile(run5, 'manifest.json'));
% inject a reserved field name
raw5 = fileread(fullfile(run5, 'manifest.json'));
raw5 = strrep(raw5, '"run_id":', '"converted_at": "x", "run_id":');
fid = fopen(fullfile(run5, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, raw5, 'char*1'); fclose(fid);
tab5 = rabbit_reconstruction_tab();
[ok5, err5, info5] = tab5.open_manifest(fullfile(run5, 'manifest.json'));
S5 = ok5 && ~exist(fullfile(run5, 'manifest.v2.json'), 'file') && ...
    ~isempty(strfind(info5.open_warning, 'not converted')) || ~isempty(strfind(info5.open_warning, 'reserved'));
S5 = ok5 && ~exist(fullfile(run5, 'manifest.v2.json'), 'file') && ~isempty(strfind(lower(info5.open_warning), 'reserved'));
fprintf('  open(%s) warning(%s) no-sidecar(%s) err=%s -> %s\n', tf(ok5), ...
    tf(~isempty(strfind(lower(info5.open_warning), 'reserved'))), ...
    tf(~exist(fullfile(run5, 'manifest.v2.json'), 'file')), err5, tf(S5));
if S5, pass = pass + 1; else, fail = fail + 1; end

fprintf('S6: conversion determinism (two conversions byte-identical)\n');
root6 = fullfile(scratch, 'smoke_det');
if exist(root6, 'dir'), rmdir(root6, 's'); end
run6 = fullfile(root6, [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run6));
copyfile(gdir, run6);
tab6 = rabbit_reconstruction_tab();
[v2a, rep6] = tab6.convert_v1_to_v2(fullfile(run6, 'manifest.json'), run6);
[v2b, ~] = tab6.convert_v1_to_v2(fullfile(run6, 'manifest.json'), run6);
S6 = strcmp(v2a, v2b) && ~isempty(rep6.converted_from);
fprintf('  deterministic(%s) converted_from=%s stamp=%s -> %s\n', tf(strcmp(v2a, v2b)), ...
    rep6.converted_from(1:min(16,numel(rep6.converted_from))), rep6.converted_at, tf(S6));
if S6, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_OPEN_SMOKE RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_open_smoke %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_open_smoke\n');
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

function flush_sidecar(tab, info)
%FLUSH_SIDECAR Write the sidecar as the app does after a successful commit.
%open_manifest is read-only; the sidecar is written only after the app
%state has been committed.
if isstruct(info) && isfield(info, 'sidecar_pending_bytes') && ~isempty(info.sidecar_pending_bytes)
    tab.write_sidecar_after_commit(info.run_dir, info.sidecar_pending_bytes);
end
end
