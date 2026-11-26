function probe_ply_bulk_checks
%% Probe: the render PLY check and the visualisation load read in bulk, with the same verdicts
% Collin Snitchler
% 20.11.2026
% Opening a finished run took 7-14 min: each of its PLY files was checked value by value about a dozen
% times. The check now reads each element in one go and falls back to the
% record loops for anything it cannot pass, and results are kept per file
% content (rabbit_memo).
%   B1  a valid binary PLY (NaN in the projected value) passes.
%   B2-B7  a non-finite coordinate, an infinite value, a face index out of
%       range, a quad face, a truncated file and trailing bytes fail with
%       the record loops' messages (record numbers included).
%   B8  trailing whitespace passes.
%   B9  the cached verdict follows the content: the same file again gives
%       the same verdict, the file changed gives the new one.
%   L1  the visualisation load gives the faces of a triangle-only file in
%       one read; L2 a file with a quad face is read by the loop, which
%       refuses it (only triangles are shown), as before.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_ply_bulk_checks"
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
rabbit_memo('clear');
tab = rabbit_reconstruction_tab();

V = [0 0 0; 1 0 0; 0 1 0; 1 1 0; 0 0 1];          % five vertices
S = [1; NaN; 3; 4; 5];                             % a projected value with no data at vertex 2
F = [0 1 2; 1 3 2; 0 2 4];                         % three triangles, 0-based

%% B1 valid
f1 = fullfile(root, 'valid.ply');
write_ply(f1, V, S, F, struct());
[ok, err] = tab.validate_render_ply(f1);
record('B1 a valid binary PLY with NaN in its value passes', ok, err);

%% B2-B7 faults, each with the record loops' message
cases = {
    'B2 a non-finite coordinate', struct('vertex_inf', [2 1]), 'vertex record 2'
    'B3 an infinite value', struct('scalar_inf', 3), 'vertex record 3'
    'B4 a face index out of range', struct('face_index', [2 2 9]), 'out-of-range face index in record 2'
    'B5 a quad face', struct('quad', 1), 'non-triangular face in record 1'
    'B6 a truncated file', struct('cut', 5), 'record 3'
    'B7 trailing bytes', struct('trailing', uint8('abc')), 'non-whitespace payload'};
for k = 1:size(cases, 1)
    fk = fullfile(root, sprintf('bad%d.ply', k));
    write_ply(fk, V, S, F, cases{k, 2});
    [ok, err] = tab.validate_render_ply(fk);
    record(sprintf('%s fails: "%s"', cases{k, 1}, cases{k, 3}), ~ok && contains(err, cases{k, 3}), err);
end

%% B8 trailing whitespace
f8 = fullfile(root, 'trailing_ws.ply');
write_ply(f8, V, S, F, struct('trailing', uint8([10 13 32 9])));
[ok, err] = tab.validate_render_ply(f8);
record('B8 trailing whitespace passes', ok, err);

%% B9 the cached verdict follows the content
[ok_a, ~] = tab.validate_render_ply(f1);
write_ply(f1, V, S, F, struct('face_index', [3 1 7]));     % same path, now broken
[ok_b, err_b] = tab.validate_render_ply(f1);
record('B9 same file again: same verdict; changed file: checked again', ok_a && ~ok_b && ...
    contains(err_b, 'out-of-range face index in record 3'), err_b);

%% L1 / L2 the visualisation load
fl1 = fullfile(root, 'load_tri.ply');
write_ply(fl1, V, S, F, struct());
[ok1, err1, info1] = tab.load_visualisation_ply(fl1);
record('L1 triangle-only file: faces read in one go, 1-based', ok1 && isequal(info1.faces, F + 1) && ...
    isequal(info1.pts, V), err1);
fl2 = fullfile(root, 'load_quad.ply');
write_ply(fl2, V, S, F, struct('quad', 2));
[ok2, err2] = tab.load_visualisation_ply(fl2);
record('L2 a quad face: the loop reads it and refuses the file, as before', ~ok2 && ...
    contains(err2, 'face data is truncated or unsupported'), err2);

fprintf('\nPROBE_PLY_BULK_CHECKS RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function record(name, ok, detail)
        if ok
            fprintf('PASS %s\n', name);
            pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail);
            fail = fail + 1;
        end
    end
end

function write_ply(path, V, S, F, opt)
% A binary little-endian PLY: float x y z activation; uchar count and int
% indices per face. opt changes it: vertex_inf [vertex axis], scalar_inf
% vertex, face_index [face slot value], quad face (adds a fourth index),
% cut (bytes removed from the end), trailing (bytes added at the end).
if isfield(opt, 'vertex_inf'), V(opt.vertex_inf(1), opt.vertex_inf(2)) = Inf; end
if isfield(opt, 'scalar_inf'), S(opt.scalar_inf) = Inf; end
if isfield(opt, 'face_index'), F(opt.face_index(1), opt.face_index(2)) = opt.face_index(3); end
head = sprintf(['ply\nformat binary_little_endian 1.0\nelement vertex %d\nproperty float x\nproperty float y\n' ...
    'property float z\nproperty float activation\nelement face %d\nproperty list uchar int vertex_indices\nend_header\n'], ...
    size(V, 1), size(F, 1));
body = uint8([]);
for k = 1:size(V, 1)
    body = [body, typecast(single([V(k, :), S(k)]), 'uint8')]; %#ok<AGROW>
end
for k = 1:size(F, 1)
    idx = int32(F(k, :));
    if isfield(opt, 'quad') && opt.quad == k
        idx = [idx, int32(0)]; %#ok<AGROW>
    end
    body = [body, uint8(numel(idx)), typecast(idx, 'uint8')]; %#ok<AGROW>
end
if isfield(opt, 'cut'), body = body(1:end - opt.cut); end
if isfield(opt, 'trailing'), body = [body, opt.trailing]; end
fid = fopen(path, 'w');
fwrite(fid, uint8(head), 'uint8');
fwrite(fid, body, 'uint8');
fclose(fid);
end
