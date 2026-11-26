function probe_manifest_v1_malformed
%% v1 manifests with malformed records fail closed
% Collin Snitchler
% 12.09.2026
%Malformed result.status and malformed inputs.files records must be rejected
%before restore registration or sidecar preparation.
% Needs the golden run at golden_root.

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'tests', 'helpers'));
[golden_root, scratch] = om_restore_fixture_paths('probe_manifest_v1_malformed');
if isempty(golden_root), return; end
golden_run = '20260909T110043_d091bb44';
stem = 'subset';
gdir = fullfile(golden_root, [stem '.matom'], 'reconstruction', 'runs', golden_run);
base = fullfile(scratch, 'v1-gate');
if exist(base, 'dir'), rmdir(base, 's'); end
pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

fprintf('V1a: malformed input snapshot digest fails before conversion\n');
run_input = fullfile(base, 'bad-input', 'elsewhere', [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_input));
copyfile(gdir, run_input);
mp = fullfile(run_input, 'manifest.json');
m = jsondecode(fileread(mp));
m.inputs.files(1).sha256 = 'not-a-digest';
write_json_utf8(mp, jsonencode(m));
tab = rabbit_reconstruction_tab();
[ok_input, err_input, ~] = tab.open_manifest(mp);
V1a = ~ok_input && ~isempty(strfind(err_input, 'inputs.files')) && ...
    exist(fullfile(run_input, 'manifest.v2.json'), 'file') == 0;
fprintf('  fails(%s) names-inputs(%s) no-sidecar(%s)\n', tf(~ok_input), ...
    tf(~isempty(strfind(err_input, 'inputs.files'))), tf(exist(fullfile(run_input, 'manifest.v2.json'), 'file') == 0));
if V1a, pass = pass + 1; else, fail = fail + 1; end

fprintf('V1b: unknown result status fails before restore\n');
run_status = fullfile(base, 'bad-status', 'elsewhere', [stem '.matom'], 'reconstruction', 'runs', golden_run);
mkdir(fileparts(run_status));
copyfile(gdir, run_status);
mp2 = fullfile(run_status, 'manifest.json');
m2 = jsondecode(fileread(mp2));
m2.result.status = 'BOGUS';
write_json_utf8(mp2, jsonencode(m2));
tab2 = rabbit_reconstruction_tab();
[ok_status, err_status, ~] = tab2.open_manifest(mp2);
V1b = ~ok_status && ~isempty(strfind(err_status, 'result.status')) && ...
    exist(fullfile(run_status, 'manifest.v2.json'), 'file') == 0;
fprintf('  fails(%s) names-status(%s) no-sidecar(%s)\n', tf(~ok_status), ...
    tf(~isempty(strfind(err_status, 'result.status'))), tf(exist(fullfile(run_status, 'manifest.v2.json'), 'file') == 0));
if V1b, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_V1_MALFORMED RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_v1_malformed %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_v1_malformed\n');
end
end

function write_json_utf8(path, text)
fid = fopen(path, 'w', 'n', 'UTF-8');
if fid < 0, error('could not open %s', path); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, text, 'char*1');
end
