function probe_manifest_mixed_time_stamps
%% Conversion picks the latest finished_at across mixed time stamp formats
% Collin Snitchler
% 12.09.2026
% The selection key must not depend on the machine for a mix of finished_at
% values with and without a trailing Z, and the stamp written is the winning raw
% string. No time zone can change the winner because the key is computed from
% the string's own digits. Scratch files are written under base.

% Use the repository source in the folder above tests.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
base = fullfile(tempdir, 'om_test_probe_manifest_mixed_time_stamps');
pass = 0; fail = 0;
tf = @(b) char(70 + 14*logical(b));

if exist(base, 'dir'), rmdir(base, 's'); end
run_dir = fullfile(base, 'subset.matom', 'reconstruction', 'runs', '20260909T110043_d091bb44');
mkdir(run_dir);
% Minimal v1 with a mixed pair: the no-Z value is later in civil time than
% the Z value, so any parse that shifts time zones could flip
% the winner.
v1 = struct();
v1.manifest_schema = 'cd2.reconstruction.manifest.v1';
v1.run_id = '20260909T110043_d091bb44';
v1.result = struct('status', 'FAILED');
v1.stages = struct('name', {'image_undistorter', 'apde_scene_prep'}, ...
    'status', {'FAILED', 'FAILED'}, ...
    'started_at', {'2026-01-01T00:00:00', '2026-01-01T00:00:00'}, ...
    'finished_at', {'2026-01-01T00:30:00', '2026-01-01T00:00:00Z'});
txt = jsonencode(v1, 'PrettyPrint', true);
fid = fopen(fullfile(run_dir, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, txt, 'char*1'); fclose(fid);

tab = rabbit_reconstruction_tab();
[v2a, rep] = tab.convert_v1_to_v2(fullfile(run_dir, 'manifest.json'), run_dir);

fprintf('X1: mixed-grammar selection picks the LATER civil value (no-Z 00:30)\n');
X1 = strcmp(rep.converted_at, '2026-01-01T00:30:00');
fprintf('  stamp=%s -> %s\n', rep.converted_at, tf(X1));
if X1, pass = pass + 1; else, fail = fail + 1; end

fprintf('X2: the emitted stamp is the raw winning string (no zone rewrite)\n');
X2 = strcmp(rep.converted_at, '2026-01-01T00:30:00') && isempty(strfind(rep.converted_at, 'Z'));
fprintf('  no-Z preserved(%s)\n', tf(X2));
if X2, pass = pass + 1; else, fail = fail + 1; end

fprintf('X3: repeated conversion is byte-identical\n');
[v2b, ~] = tab.convert_v1_to_v2(fullfile(run_dir, 'manifest.json'), run_dir);
X3 = strcmp(v2a, v2b);
fprintf('  -> %s\n', tf(X3));
if X3, pass = pass + 1; else, fail = fail + 1; end

fprintf('X4: impossible calendar stamps are IGNORED, never fatal\n');
v1.stages(2).finished_at = '2026-02-30T00:00:00';
txt = jsonencode(v1, 'PrettyPrint', true);
fid = fopen(fullfile(run_dir, 'manifest.json'), 'w', 'n', 'UTF-8');
fwrite(fid, txt, 'char*1'); fclose(fid);
[ok4, err4, rep4] = deal(false, '', struct());
try
    [~, rep4] = tab.convert_v1_to_v2(fullfile(run_dir, 'manifest.json'), run_dir);
    X4 = strcmp(rep4.converted_at, '2026-01-01T00:30:00');
catch ME
    X4 = false; err4 = ME.message;
end
fprintf('  stamp=%s err=%s -> %s\n', rep4.converted_at, err4, tf(X4));
if X4, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_MANIFEST_MIXED_TIME_STAMPS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_manifest_mixed_time_stamps %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_manifest_mixed_time_stamps\n');
end
end
