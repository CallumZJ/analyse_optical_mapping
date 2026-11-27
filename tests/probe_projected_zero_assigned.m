function probe_projected_zero_assigned
%% Projected values of zero count as assigned
% Collin Snitchler
% 13.09.2026
% A projected value of 0 is a valid assigned value; only NaN is unassigned.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
tab = rabbit_reconstruction_tab();
values = [0; NaN; 2];
[ok, err, record] = tab.validate_projected_output(values, repmat('1', 1, 64), repmat('2', 1, 64));
assert(ok, err);
assert(strcmp(record.status, 'AVAILABLE'));
[assigned, counts] = tab.classify_projected_output(record);
assert(isequal(assigned, [true; false; true]));
assert(counts.assigned == 2 && counts.unassigned == 1);
fprintf('PROBE_OK probe_projected_zero_assigned 1/0\n');
end
