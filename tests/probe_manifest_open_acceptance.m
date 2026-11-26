function probe_manifest_open_acceptance
%% Acceptance checks for opening and converting reconstruction manifests
% Collin Snitchler
% 12.09.2026
% Checks on scratch copies of the golden run: C2 the v1 to v2 conversion is
% deterministic (also for a CREATED run without stage time stamps), C4 a stale
% sidecar, C5 a failed sidecar write and its retry, C6 native and v2-only
% manifests, C7 a missing artefact, C12 reserved field names and C13 invalid or
% corrupt v2 sidecars. Needs the golden run at golden_root; copies go under base.

% Use the repository source in the folder above tests.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_open_acceptance');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
base = fullfile(scratch, 'acc');

pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

% ============ C2: determinism ============
fprintf('C2: determinism (two scratch copies -> byte-identical v2)\n');
r1 = mkfix(base, 'det1', gdir, stem, golden_run, 'COMPLETED');
r2d = mkfix(base, 'det2', gdir, stem, golden_run, 'COMPLETED');
t1 = rabbit_reconstruction_tab(); t2 = rabbit_reconstruction_tab();
[v2a, ~] = t1.convert_v1_to_v2(fullfile(r1, 'manifest.json'), r1);
[v2b, ~] = t2.convert_v1_to_v2(fullfile(r2d, 'manifest.json'), r2d);
C2a = strcmp(v2a, v2b);
fprintf('  two-location identical: %s\n', tf(C2a));
if C2a, pass = pass + 1; else, fail = fail + 1; end

fprintf('C2b: zero-stamp CREATED case is CONTENT-DERIVED (R1 P1-1)\n');
r3 = mkfix(base, 'det3', gdir, stem, golden_run, 'CREATED');
% Clear every finished_at so the conversion has to fall back to the
% content-derived time stamp.
mp3 = fullfile(r3, 'manifest.json');
mj3 = jsondecode(fileread(mp3));
for si = 1:numel(mj3.stages)
    mj3.stages(si).finished_at = '';
end
fid3 = fopen(mp3, 'w', 'n', 'UTF-8');
fwrite(fid3, jsonencode(mj3), 'char*1'); fclose(fid3);
t3 = rabbit_reconstruction_tab();
[v2c, rep3] = t3.convert_v1_to_v2(fullfile(r3, 'manifest.json'), r3);
[v2d, rep3b] = t3.convert_v1_to_v2(fullfile(r3, 'manifest.json'), r3);
C2b = strcmp(v2c, v2d) && strcmp(rep3.converted_at, rep3b.converted_at) && ...
    strcmp(rep3.basis_source, 'run_id') && ...
    ~isempty(regexp(rep3.converted_at, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', 'once'));
fprintf('  deterministic(%s) stamp=%s basis=%s -> %s\n', tf(strcmp(v2c, v2d)), ...
    rep3.converted_at, rep3.basis_source, tf(C2b));
if C2b, pass = pass + 1; else, fail = fail + 1; end

% ============ C4: mismatch ============
fprintf('C4: stale sidecar (v1 edited) -> STALE warning (row 6), no re-convert\n');
r4 = mkfix(base, 'mm', gdir, stem, golden_run, 'COMPLETED');
t4 = rabbit_reconstruction_tab();
[ok4, ~, info4] = t4.open_manifest(fullfile(r4, 'manifest.json'));
flush_sidecar(t4, info4);
sc4 = fullfile(r4, 'manifest.v2.json');
d4a = dir(sc4);
raw = fileread(fullfile(r4, 'manifest.json'));
fid = fopen(fullfile(r4, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, [raw ' '], 'char*1'); fclose(fid);
t4b = rabbit_reconstruction_tab();
[ok4b, err4b, info4b] = t4b.open_manifest(fullfile(r4, 'manifest.json'));
d4b = dir(sc4);
C4 = ok4 && ok4b && strcmp(info4b.open_kind, 'STALE_V2') && ...
    ~isempty(strfind(info4b.open_warning, 'out of date')) && d4a.datenum == d4b.datenum;
fprintf('  kind=%s warning=%s sidecar-unwritten=%s -> %s\n', info4b.open_kind, ...
    tf(~isempty(strfind(info4b.open_warning, 'out of date'))), tf(d4a.datenum == d4b.datenum), tf(C4));
if C4, pass = pass + 1; else, fail = fail + 1; end

% ============ C6: native v2 + v2-only + write block ============
fprintf('C6: native v2 opens; v2-only folder; write block on v2-only\n');
r6 = mkfix(base, 'natv2', gdir, stem, golden_run, 'COMPLETED');
t6 = rabbit_reconstruction_tab();
[~, ~, info6p] = t6.open_manifest(fullfile(r6, 'manifest.json'));
flush_sidecar(t6, info6p);   % the sidecar is only written after the commit
v2f = fullfile(r6, 'manifest.v2.json');
t6b = rabbit_reconstruction_tab();
[ok6, err6, info6] = t6b.open_manifest(v2f);
C6a = ok6 && strcmp(info6.active_manifest_schema, 'cd2.reconstruction.manifest.v2');
% v2-only: remove the v1
r6only = mkfix(base, 'v2only', gdir, stem, golden_run, 'COMPLETED');
t6c = rabbit_reconstruction_tab();
[~, ~, info6q] = t6c.open_manifest(fullfile(r6only, 'manifest.json'));
flush_sidecar(t6c, info6q);   % write the v2 sidecar for the v2-only case
copyfile(fullfile(r6only, 'manifest.v2.json'), fullfile(r6only, 'mv2.tmp'));
delete(fullfile(r6only, 'manifest.json'));
movefile(fullfile(r6only, 'mv2.tmp'), fullfile(r6only, 'manifest.v2.json'), 'f');
t6d = rabbit_reconstruction_tab();
[ok6b, err6b, info6d] = t6d.open_manifest(fullfile(r6only, 'manifest.v2.json'));
C6b = ok6b && strcmp(info6d.open_kind, 'V2_ONLY');
% write block
[wb_ok, wb_err] = t6d.write_active_manifest(r6only, @(m) m);
C6c = ~wb_ok && ~isempty(strfind(wb_err, 'no sibling v1'));
fprintf('  native(%s) v2-only(%s) write-block(%s) -> %s\n', tf(C6a), tf(C6b), tf(C6c), ...
    tf(C6a && C6b && C6c));
if C6a && C6b && C6c, pass = pass + 1; else, fail = fail + 1; end

% ============ C7: missing artefact -> fail closed ============
fprintf('C7: missing artefact fails closed pre-restore\n');
r7 = mkfix(base, 'missing', gdir, stem, golden_run, 'COMPLETED');
t7 = rabbit_reconstruction_tab();
[ok7a] = t7.open_manifest(fullfile(r7, 'manifest.json')); % first open writes sidecar
delete(fullfile(r7, 'outputs', 'fused-geometric.ply'));
t7b = rabbit_reconstruction_tab();
[ok7, err7, ~] = t7b.open_manifest(fullfile(r7, 'manifest.json'));
C7 = ok7a && ~ok7 && ~isempty(strfind(err7, 'missing referenced artefacts'));
fprintf('  fails=%s names=%s -> %s\n', tf(~ok7), tf(~isempty(strfind(err7, 'missing referenced artefacts'))), tf(C7));
if C7, pass = pass + 1; else, fail = fail + 1; end

% ============ C12: reserved names ============
fprintf('C12: reserved-name v1 opens as v1, not converted\n');
r12 = mkfix(base, 'reserved', gdir, stem, golden_run, 'COMPLETED');
raw12 = fileread(fullfile(r12, 'manifest.json'));
raw12 = strrep(raw12, '"run_id":', '"converted_at": "x", "run_id":');
fid = fopen(fullfile(r12, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, raw12, 'char*1'); fclose(fid);
t12 = rabbit_reconstruction_tab();
[ok12, err12, info12] = t12.open_manifest(fullfile(r12, 'manifest.json'));
C12 = ok12 && ~exist(fullfile(r12, 'manifest.v2.json'), 'file') && ...
    strcmp(info12.open_kind, 'RESERVED_V1');
fprintf('  kind=%s no-sidecar=%s -> %s\n', info12.open_kind, ...
    tf(~exist(fullfile(r12, 'manifest.v2.json'), 'file')), tf(C12));
if C12, pass = pass + 1; else, fail = fail + 1; end

% ============ C13: invalid / corrupt v2 ============
fprintf('C13a: semantic-INVALID v2 (bad converted_from) -> v1 fallback + warning\n');
r13 = mkfix(base, 'invalidv2', gdir, stem, golden_run, 'COMPLETED');
t13 = rabbit_reconstruction_tab();
[~, ~, info13p] = t13.open_manifest(fullfile(r13, 'manifest.json'));
flush_sidecar(t13, info13p);   % write the sidecar before changing it
sc13 = fileread(fullfile(r13, 'manifest.v2.json'));
sc13 = strrep(sc13, ['"converted_from": "' char(repmat('0',1,0))], '"converted_from": "');
% flip the first hex char of converted_from
i_cf = strfind(sc13, '"converted_from": "');
if ~isempty(i_cf)
    i_hex = i_cf(1) + numel('"converted_from": "');
    c0 = sc13(i_hex);
    sc13(i_hex) = char(double(c0) + 1);
end
fid = fopen(fullfile(r13, 'manifest.v2.json'), 'w', 'n', 'UTF-8');
fwrite(fid, sc13, 'char*1'); fclose(fid);
t13b = rabbit_reconstruction_tab();
[ok13, err13, info13] = t13b.open_manifest(fullfile(r13, 'manifest.json'));
C13a = ok13 && strcmp(info13.open_kind, 'STALE_V2') && ~isempty(strfind(info13.open_warning, 'out of date'));
fprintf('  kind=%s -> %s\n', info13.open_kind, tf(C13a));
if C13a, pass = pass + 1; else, fail = fail + 1; end

fprintf('C13b: corrupt v2 + readable sibling -> v1 fallback; v2-only -> fail closed\n');
r13b = mkfix(base, 'corruptv2', gdir, stem, golden_run, 'COMPLETED');
t13c = rabbit_reconstruction_tab();
t13c.open_manifest(fullfile(r13b, 'manifest.json'));
fid = fopen(fullfile(r13b, 'manifest.v2.json'), 'w', 'n', 'UTF-8');
fwrite(fid, '{"manifest_schema": "cd2.', 'char*1'); fclose(fid);
t13d = rabbit_reconstruction_tab();
[ok13b, err13b, info13b] = t13d.open_manifest(fullfile(r13b, 'manifest.json'));
C13b = ok13b && strcmp(info13b.open_kind, 'V2_CORRUPT');
% v2-only corrupt
r13c = mkfix(base, 'corruptonly', gdir, stem, golden_run, 'COMPLETED');
t13e = rabbit_reconstruction_tab();
t13e.open_manifest(fullfile(r13c, 'manifest.json'));
delete(fullfile(r13c, 'manifest.json'));
fid = fopen(fullfile(r13c, 'manifest.v2.json'), 'w', 'n', 'UTF-8');
fwrite(fid, '{"manifest_schema": "cd2.', 'char*1'); fclose(fid);
t13f = rabbit_reconstruction_tab();
[ok13c, err13c, ~] = t13f.open_manifest(fullfile(r13c, 'manifest.v2.json'));
C13c = ~ok13c && ~isempty(strfind(err13c, 'corrupt'));
fprintf('  sibling-fallback(%s) v2-only-fail-closed(%s) -> %s\n', tf(C13b), tf(C13c), tf(C13b && C13c));
if C13b && C13c, pass = pass + 1; else, fail = fail + 1; end

% ============ C5: write-fail + close/reopen retry ============
fprintf('C5: sidecar write failure -> session restored; next open retries (R1-F6)\n');
r5 = mkfix(base, 'wf', gdir, stem, golden_run, 'COMPLETED');
t5 = tab_failure_doubles('fail_on', {'write_manifest_v2_sidecar'});
[ok5, err5, info5] = t5.open_manifest(fullfile(r5, 'manifest.json'));
% open_manifest is read-only: it prepares the sidecar bytes but writes nothing,
% so the write failure shows up when the sidecar is written after the commit.
C5a = ok5 && ~isempty(info5.sidecar_pending_bytes) && ...
    isempty(strfind(info5.active_manifest_path, 'manifest.v2.json')) && ...
    exist(fullfile(r5, 'manifest.v2.json'), 'file') == 0;
[sw5_ok, sw5_err] = t5.write_sidecar_after_commit(info5.run_dir, info5.sidecar_pending_bytes);
C5a = C5a && ~sw5_ok && ~isempty(sw5_err);
fprintf('  open-ok=%s pending=%s write-fails=%s no-sidecar=%s\n', tf(ok5), ...
    tf(~isempty(info5.sidecar_pending_bytes)), tf(~sw5_ok), ...
    tf(exist(fullfile(r5, 'manifest.v2.json'), 'file') == 0));
% injection removed: the next open and post-commit write create the sidecar
t5b = rabbit_reconstruction_tab();
[ok5b, err5b, info5b] = t5b.open_manifest(fullfile(r5, 'manifest.json'));
flush_sidecar(t5b, info5b);
C5b = ok5b && exist(fullfile(r5, 'manifest.v2.json'), 'file') == 2;
fprintf('  retry-wrote-sidecar=%s -> %s\n', tf(C5b), tf(C5a && C5b));
if C5a && C5b, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_OPEN_ACCEPTANCE RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_open_acceptance %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_open_acceptance\n');
end
end

function run_dir = mkfix(base, name, gdir, stem, golden_run, status)
run_dir = fullfile(base, name, [stem '.matom'], 'reconstruction', 'runs', golden_run);
if exist(fullfile(base, name), 'dir'), rmdir(fullfile(base, name), 's'); end
mkdir(fileparts(run_dir));
copyfile(gdir, run_dir);
if ~strcmp(status, 'COMPLETED')
    raw = fileread(fullfile(run_dir, 'manifest.json'));
    raw = strrep(raw, '"status": "COMPLETED"', ['"status": "' status '"']);
    fid = fopen(fullfile(run_dir, 'manifest.json'), 'w', 'n', 'UTF-8');
    fwrite(fid, raw, 'char*1'); fclose(fid);
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
