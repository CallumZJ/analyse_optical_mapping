function probe_sidecar_write_lock
%% Sidecar write is blocked by a recovery lock
% Collin Snitchler
% 13.09.2026
% A recovery lock with no owner must block replacing manifest.v2.json and be
% left in place.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
tab = rabbit_reconstruction_tab();
root = tempname;
mkdir(root);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>
run_dir = fullfile(root, 'run');
mkdir(run_dir);
target = fullfile(run_dir, 'manifest.v2.json');
write_text(target, 'old-sidecar-bytes');
arbiter = fullfile(run_dir, 'manifest.v2.json.recovery.lock');
mkdir(arbiter);
fprintf('S2L1: ownerless recovery arbiter blocks sidecar replacement and is preserved\n');
[ok, err] = tab.write_manifest_v2_sidecar(run_dir, '{"run_id":"test-run"}');
target_preserved = strcmp(fileread(target), 'old-sidecar-bytes');
arbiter_preserved = exist(arbiter, 'dir') == 7;
S2L1 = ~ok && contains(err, 'WRITE_CONFLICT') && target_preserved && arbiter_preserved;
fprintf('  result=%s ok=%s target=%s arbiter=%s err=%s\n', ...
    tf(S2L1), tf(ok), tf(target_preserved), tf(arbiter_preserved), err);
fprintf('PROBE_SIDECAR_WRITE_LOCK RESULT: %d passed, %d failed\n', ...
    S2L1, 1 - S2L1);
if S2L1
    fprintf('PROBE_OK probe_sidecar_write_lock 1/0\n');
else
    error('PROBE_FAIL probe_sidecar_write_lock');
end
end

function write_text(path, text)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0);
fwrite(fid, text, 'char*1');
fclose(fid);
end

function out = tf(value)
if value, out = 'T'; else, out = 'F'; end
end

function cleanup_case(root)
if exist(root, 'dir'), rmdir(root, 's'); end
end
