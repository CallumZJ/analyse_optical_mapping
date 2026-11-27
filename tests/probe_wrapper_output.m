function probe_wrapper_output
%% Probe: a job wrapper that fails before its command runs says why, in the stage log and the error
% Collin Snitchler
% 20.11.2026
% A user's calibration stopped with "exit code 1" and a stage log holding
% nothing from the job: the wrapper (job_wrapper.ps1) failed before the
% stage's batch file ran, and its own output was lost. Its output now goes
% to <stage>_wrapper.log; on a non-zero exit it is added to the stage log
% and its first lines to the error.
%   W1  a job the wrapper cannot set up (a job object name with a
%       backslash, which Windows refuses): the error and the stage log
%       name the wrapper's reason, the batch file never ran
%   W2  a job that runs: exit 0, no wrapper lines in the stage log
% Usage: matlab -batch "addpath('<repo>/tests'); probe_wrapper_output"
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
tab = rabbit_reconstruction_tab();
cmd_exe = fullfile(getenv('SystemRoot'), 'System32', 'cmd.exe');

% W1: the stage name goes into the job object's name; a backslash there
% makes CreateJobObject fail (ERROR_BAD_PATHNAME), so the wrapper stops
% before it starts the batch file
mkdir(fullfile(root, 'x'));
log1 = fullfile(root, 'w1.log');
[ok1, err1, code1] = tab.spawn_and_wait({sprintf('"%s" /c exit 0', cmd_exe)}, log1, ...
    fullfile(root, 'w1.cancel'), fullfile(root, 'w1.pid'), 60, 'x\y');
txt1 = '';
if exist(log1, 'file') == 2, txt1 = fileread(log1); end
record('W1 the wrapper''s reason is in the error and the stage log', ~ok1 && code1 ~= 0 && ...
    contains(err1, 'The job wrapper said:') && contains(err1, 'CreateJobObject') && ...
    contains(txt1, '[job wrapper]') && ~contains(txt1, 'stage x\y started'), sprintf('%d: %s | log: %s', code1, err1, txt1));

% W2: a job that runs
log2 = fullfile(root, 'w2.log');
[ok2, err2, code2] = tab.spawn_and_wait({sprintf('"%s" /c exit 0', cmd_exe)}, log2, ...
    fullfile(root, 'w2.cancel'), fullfile(root, 'w2.pid'), 60, 'w2');
txt2 = fileread(log2);
record('W2 a job that runs: exit 0, nothing from the wrapper', ok2 && code2 == 0 && isempty(err2) && ...
    contains(txt2, 'stage w2 started') && ~contains(txt2, '[job wrapper]'), sprintf('%d: %s', code2, err2));

fprintf('\nPROBE_WRAPPER_OUTPUT RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function record(name, ok, detail)
        if ok
            fprintf('PASS %s\n', name); pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail); fail = fail + 1;
        end
    end
end
