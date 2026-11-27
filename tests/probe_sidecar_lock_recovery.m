function probe_sidecar_lock_recovery
%% Sidecar lock recovery
% Collin Snitchler
% 13.09.2026
% A leftover sidecar lock with no owner is removed only under the recovery
% lock; a live or unknown writer is left alone and the recovery fails closed.
% Check IDs: E5R<n> is check n of this probe; the prefix only groups them.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0;
fail = 0;

fprintf('E5R1: ownerless sidecar lock is removed only under a recovery arbiter\n');
root1 = tempname;
mkdir(root1);
cleanup1 = onCleanup(@() cleanup_case(root1)); %#ok<NASGU>
run1 = fullfile(root1, 'run');
mkdir(run1);
write_text(fullfile(run1, 'manifest.v2.json'), ...
    jsonencode(struct('manifest_schema', 'cd2.reconstruction.manifest.v2')));
lock1 = fullfile(run1, 'manifest.v2.json.lock');
mkdir(lock1);
[ok1, err1, status1] = rabbit_reconstruction_tab().recover_sidecar(run1);
record('E5R1', ok1 && strcmp(status1.status, 'AVAILABLE') && ...
    ~exist(lock1, 'dir') && ~exist(fullfile(run1, ...
    'manifest.v2.json.recovery.lock'), 'dir'), err1);

fprintf('E5R2: indeterminate/live writer is preserved and fails closed\n');
root2 = tempname;
mkdir(root2);
cleanup2 = onCleanup(@() cleanup_case(root2)); %#ok<NASGU>
run2 = fullfile(root2, 'run');
mkdir(run2);
write_text(fullfile(run2, 'manifest.v2.json'), ...
    jsonencode(struct('manifest_schema', 'cd2.reconstruction.manifest.v2')));
write_owner_state(run2, 'LIVE');
lock2 = fullfile(run2, 'manifest.v2.json.lock');
mkdir(lock2);
write_json(fullfile(lock2, 'owner.json'), struct('schema', 'sidecar-lock-v2', ...
    'token', repmat('a', 1, 32), 'registration_token', repmat('a', 1, 32)));
[ok2, err2, ~] = rabbit_reconstruction_tab().recover_sidecar(run2);
record('E5R2', ~ok2 && contains(err2, 'process_death_recovery_required') && ...
    exist(lock2, 'dir') == 7 && exist(fullfile(run2, ...
    'manifest.v2.json.recovery.lock'), 'dir') == 7, err2);

fprintf('E5R3: definitively dead writer is taken over and quiesced\n');
root3 = tempname;
mkdir(root3);
cleanup3 = onCleanup(@() cleanup_case(root3)); %#ok<NASGU>
run3 = fullfile(root3, 'run');
mkdir(run3);
write_text(fullfile(run3, 'manifest.v2.json'), ...
    jsonencode(struct('manifest_schema', 'cd2.reconstruction.manifest.v2')));
write_owner_state(run3, 'DEAD');
lock3 = fullfile(run3, 'manifest.v2.json.lock');
mkdir(lock3);
write_json(fullfile(lock3, 'owner.json'), struct('schema', 'sidecar-lock-v2', ...
    'token', repmat('a', 1, 32), 'registration_token', repmat('a', 1, 32)));
[ok3, err3, status3] = rabbit_reconstruction_tab().recover_sidecar(run3);
record('E5R3', ok3 && strcmp(status3.status, 'AVAILABLE') && isempty(err3) && ...
    ~exist(lock3, 'dir') && ~exist(fullfile(run3, ...
    'manifest.v2.json.recovery.lock'), 'dir'), err3);

fprintf('E5R4: a forged DEAD record for a live process is indeterminate\n');
root4 = tempname;
mkdir(root4);
cleanup4 = onCleanup(@() cleanup_case(root4)); %#ok<NASGU>
run4 = fullfile(root4, 'run');
mkdir(run4);
write_text(fullfile(run4, 'manifest.v2.json'), ...
    jsonencode(struct('manifest_schema', 'cd2.reconstruction.manifest.v2')));
current_pid = sprintf('%.0f', feature('getpid'));
write_owner_state(run4, 'DEAD', current_pid);
lock4 = fullfile(run4, 'manifest.v2.json.lock');
mkdir(lock4);
write_json(fullfile(lock4, 'owner.json'), struct('schema', 'sidecar-lock-v2', ...
    'token', repmat('a', 1, 32), 'registration_token', repmat('a', 1, 32)));
[ok4, err4, ~] = rabbit_reconstruction_tab().recover_sidecar(run4);
record('E5R4', ~ok4 && contains(err4, 'process_death_recovery_required') && ...
    exist(lock4, 'dir') == 7, err4);

fprintf('E5R5: a live matching process instance is preserved fail-closed\n');
root5 = tempname;
mkdir(root5);
cleanup5 = onCleanup(@() cleanup_case(root5)); %#ok<NASGU>
run5 = fullfile(root5, 'run');
mkdir(run5);
write_text(fullfile(run5, 'manifest.v2.json'), ...
    jsonencode(struct('manifest_schema', 'cd2.reconstruction.manifest.v2')));
current_pid = sprintf('%.0f', feature('getpid'));
current_backend = current_backend_instance(current_pid);
write_owner_state(run5, 'LIVE', current_pid, current_backend);
lock5 = fullfile(run5, 'manifest.v2.json.lock');
mkdir(lock5);
write_json(fullfile(lock5, 'owner.json'), struct('schema', 'sidecar-lock-v2', ...
    'token', repmat('a', 1, 32), 'registration_token', repmat('a', 1, 32)));
[ok5, err5, ~] = rabbit_reconstruction_tab().recover_sidecar(run5);
record('E5R5', ~ok5 && contains(err5, 'process_death_recovery_required') && ...
    exist(lock5, 'dir') == 7, err5);

fprintf('PROBE_SIDECAR_LOCK_RECOVERY RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0
    error('PROBE_FAIL probe_sidecar_lock_recovery');
end
fprintf('PROBE_OK probe_sidecar_lock_recovery %d/0\n', pass);

    function record(name, condition, detail)
        if condition
            pass = pass + 1;
            result = 'PASS';
        else
            fail = fail + 1;
            result = 'FAIL';
        end
        fprintf('  %s %s %s\n', name, result, detail);
    end
end

function write_owner_state(run_dir, liveness_state, pid_override, backend_override)
if nargin < 3, pid_override = '99999'; end
if nargin < 4, backend_override = repmat('b', 1, 32); end
token = repmat('a', 1, 32);
backend = backend_override;
owner = struct('schema', 'sidecar-arbiter-v1', 'kind', 'writer', ...
    'token', token, 'backend_instance', backend, 'run_id', '17', 'pid', pid_override);
write_json(fullfile(run_dir, 'manifest.v2.json.recovery.lock', 'owner.json'), owner);
registry = fullfile(run_dir, 'manifest.v2.json.writer-registry');
mkdir(registry);
registry_entry = fullfile(registry, [token '.json']);
write_json(registry_entry, struct( ...
    'schema', 'sidecar-writer-registration-v1', 'token', token, ...
    'backend_instance', backend, 'run_id', '17', 'pid', pid_override, ...
    'state', 'ACTIVE'));
liveness = fullfile(run_dir, 'manifest.v2.json.writer-liveness');
mkdir(liveness);
write_json(fullfile(liveness, [token '.json']), struct( ...
    'schema', 'sidecar-writer-liveness-v1', 'token', token, ...
    'backend_instance', backend, 'run_id', '17', 'pid', pid_override, ...
    'state', liveness_state));
if strcmp(liveness_state, 'DEAD') && exist(registry_entry, 'file')
    delete(registry_entry);
end
end


function backend = current_backend_instance(pid)
if ispc
    proc = System.Diagnostics.Process.GetProcessById(int32(str2double(pid)));
    stamp = char(proc.StartTime.ToUniversalTime().ToString('o'));
elseif isunix && ~ismac
    raw = fileread(fullfile(filesep, 'proc', pid, 'stat'));
    close_paren = find(raw == ')', 1, 'last');
    fields = strsplit(strtrim(raw(close_paren + 1:end)));
    stamp = char(fields{20});
elseif ismac
    [status, output] = system(['ps -o lstart= -p ' pid]);
    assert(status == 0 && ~isempty(strtrim(output)));
    stamp = strtrim(output);
else
    error('E5R5 unsupported platform');
end
bytes = [unicode2native('OM-BACKEND-INSTANCE', 'UTF-8') 0 ...
    unicode2native('backend-instance-v1', 'UTF-8') 0 ...
    unicode2native(pid, 'UTF-8') 0 unicode2native(stamp, 'UTF-8')];
md = java.security.MessageDigest.getInstance('SHA-256');
digest = md.digest(uint8(bytes));
backend = lower(reshape(dec2hex(typecast(int8(digest), 'uint8'), 2)', 1, []));
backend = backend(1:32);
end

function write_json(path, value)
write_text(path, jsonencode(value));
end

function write_text(path, text)
parent = fileparts(path);
if ~exist(parent, 'dir'), mkdir(parent); end
fid = fopen(path, 'wb');
assert(fid >= 0);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
end

function cleanup_case(root)
if exist(root, 'dir'), rmdir(root, 's'); end
end
