function probe_run_id_unique
%% Probe: run IDs are unique across MATLAB sessions
% Collin Snitchler
% 15.10.2026
% The run ID suffix came from randi on the global random generator, which
% MATLAB starts from the same seed in every session, so every fresh start
% gave the same suffix. Checks:
%   U1  the ID has the format the run parsers expect (yyyymmddTHHMMSS_8hex)
%   U2  the global random generator state is unchanged by new_run_id
%   U3  two IDs made after the same generator reset (a fresh session)
%       have different suffixes
%   U4  100 IDs in a row have 100 different suffixes
%   U5  run_suffix gives 8 lower-case hex digits
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
tab = rabbit_reconstruction_tab();
pass = 0; fail = 0;
pattern = '^\d{8}T\d{6}_[0-9a-f]{8}$';   % the regex of the run parsers

id = tab.new_run_id();
record('U1', ~isempty(regexp(id, pattern, 'once')), id);

rng(12345, 'twister');
s0 = rng;
tab.new_run_id();
s1 = rng;
record('U2', isequal(s0, s1), 'rng state before and after new_run_id');

rng('default'); a = tab.new_run_id();
rng('default'); b = tab.new_run_id();
record('U3', ~strcmp(a(end-7:end), b(end-7:end)), sprintf('%s vs %s', a, b));

ids = cell(100, 1);
for k = 1:100
    ids{k} = tab.new_run_id();
end
suffixes = cellfun(@(x) x(end-7:end), ids, 'UniformOutput', false);
record('U4', numel(unique(suffixes)) == 100, sprintf('%d unique of 100', numel(unique(suffixes))));

h = rabbit_reconstruction_tab.run_suffix();
record('U5', ischar(h) && ~isempty(regexp(h, '^[0-9a-f]{8}$', 'once')), h);

fprintf('PROBE_RUN_ID_UNIQUE RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0, error('PROBE_FAIL probe_run_id_unique'); end
fprintf('PROBE_OK probe_run_id_unique %d/0\n', pass);

    function record(name, condition, detail)
        if condition, pass = pass + 1; result = 'PASS'; else, fail = fail + 1; result = 'FAIL'; end
        fprintf('  %s %s %s\n', name, result, detail);
    end
end
