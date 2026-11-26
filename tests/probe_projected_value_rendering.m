function probe_projected_value_rendering
%% Projected values: signed zero, NaN and infinity
% Collin Snitchler
% 13.09.2026
% Checks validate_projected_output and classify_projected_output.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
tab = rabbit_reconstruction_tab();
d1 = repmat('1', 1, 64);
d2 = repmat('2', 1, 64);

fprintf('R2Z1: finite signed zero is canonicalised to +0 in the projected wire\n');
[ok_zero, err_zero, wire_zero] = tab.validate_projected_output([-0; NaN], d1, d2);
R2Z1 = ok_zero && isempty(err_zero) && ...
    strcmp(wire_zero.values.values{1}, '0000000000000000') && ...
    strcmp(wire_zero.values.values{2}, '7ff8000000000000');
fprintf('  result=%s err=%s\n', tf(R2Z1), err_zero);

fprintf('R2Z2: negative infinity and negative non-canonical NaN are rejected\n');
[ok_wire, err_wire, wire] = tab.validate_projected_output([0; NaN], d1, d2);
assert(ok_wire, err_wire);
wire_inf = wire;
wire_inf.values.values{1} = 'fff0000000000000';
try
    tab.classify_projected_output(wire_inf);
    inf_ok = true; inf_err = '';
catch ME
    inf_ok = false; inf_err = ME.message;
end
wire_nan = wire;
wire_nan.values.values{2} = 'fff8000000000001';
try
    tab.classify_projected_output(wire_nan);
    nan_ok = true; nan_err = '';
catch ME
    nan_ok = false; nan_err = ME.message;
end
R2Z2 = ~inf_ok && contains(inf_err, 'canonical quiet NaN') && ...
    ~nan_ok && contains(nan_err, 'canonical quiet NaN');
fprintf('  inf=%s nan=%s\n', tf(~inf_ok), tf(~nan_ok));

fprintf('R2Z3: renderer statistics use canonical projected_output, not scalar zero\n');
info = struct('pts', [0 0 0; 1 0 0], 'faces', [1 2 1], ...
    'has_faces', true, 'scalar', [0; 0], 'scalar_name', 'activation', ...
    'projected_output', wire);
[stats_ok, stats_err, stats] = tab.visualisation_stats(info);
R2Z3 = stats_ok && isempty(stats_err) && stats.n_assigned == 1 && ...
    stats.n_unassigned == 1 && strcmp(stats.assignment_source, 'projected_output');
fprintf('  result=%s err=%s assigned=%d unassigned=%d\n', ...
    tf(R2Z3), stats_err, stats.n_assigned, stats.n_unassigned);

fprintf('R2Z4: projected output digest uses the normative domain separator and JCS order\n');
expected_digest = '59220f04166fbcf8eeefb2247738de12fbfd037a9aabb113bbf7cb59f98b0834';
R2Z4 = strcmp(wire.output_sha256, expected_digest);
fprintf('  result=%s digest=%s\n', tf(R2Z4), wire.output_sha256);

fprintf('PROBE_PROJECTED_VALUE_RENDERING RESULT: %d passed, %d failed\n', ...
    R2Z1 + R2Z2 + R2Z3 + R2Z4, 4 - R2Z1 - R2Z2 - R2Z3 - R2Z4);
if R2Z1 && R2Z2 && R2Z3 && R2Z4
    fprintf('PROBE_OK probe_projected_value_rendering 4/0\n');
else
    error('PROBE_FAIL probe_projected_value_rendering');
end
end

function out = tf(value)
if value, out = 'T'; else, out = 'F'; end
end
