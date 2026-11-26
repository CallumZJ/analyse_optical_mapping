function probe_reprojection_inputs
%% Reprojection stage input checks
% Collin Snitchler
% 13.09.2026
% A malformed COLMAP view binding must fail before the adapter runs; valid
% bindings must pass on to the next manifest check.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
root = tempname;
mkdir(root);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>
model = fullfile(root, 'model');
mkdir(model);
write_text(fullfile(model, 'cameras.txt'), [ ...
    '# Camera list with one line of data per camera' newline ...
    '1 SIMPLE_PINHOLE 640 480 500 320 240' newline]);
image_lines = ['# Image list with two lines of data per image' newline];
for k = 1:4
    image_lines = [image_lines sprintf('%d 1 0 0 0 0 0 0 1 view%d/view%d_0080.tiff', ...
        k, k, k) newline newline];
end
write_text(fullfile(model, 'images.txt'), image_lines);
write_text(fullfile(model, 'points3D.txt'), ...
    ['# 3D point list with one line of data per point' newline]);
run_dir = fullfile(root, 'run');
mkdir(run_dir);
tab = rabbit_reconstruction_tab();
[~, meta] = tab.build_stage_command('reprojection', run_dir, struct());

fprintf('P2P1: malformed explicit binding fails before the adapter is invoked\n');
bad_opts = struct('cameras_bin', fullfile(model, 'cameras.txt'), ...
    'colmap_view_bindings', struct('view_id', 'not-a-fixed-view'));
[bad_ok, bad_err, ~] = tab.run_matlab_stage('reprojection', run_dir, bad_opts, meta);
P2P1 = ~bad_ok && contains(bad_err, 'PROJECTION_CONTRACT_MISMATCH');
fprintf('  result=%s err=%s\n', tf(P2P1), bad_err);

fprintf('P2P2: valid production pose wire advances to the next manifest gate\n');
[cameras, images, ~] = tab.read_sparse_model(model); %#ok<ASGLU>
[bindings_ok, bindings_err, bindings] = tab.default_colmap_bindings(images);
assert(bindings_ok, bindings_err);
good_opts = struct('cameras_bin', fullfile(model, 'cameras.txt'), ...
    'colmap_view_bindings', bindings);
[good_ok, good_err, ~] = tab.run_matlab_stage('reprojection', run_dir, good_opts, meta);
P2P2 = ~good_ok && contains(good_err, 'Saved ROI JSON missing');
fprintf('  result=%s err=%s\n', tf(P2P2), good_err);

fprintf('PROBE_REPROJECTION_INPUTS RESULT: %d passed, %d failed\n', ...
    P2P1 + P2P2, 2 - P2P1 - P2P2);
if P2P1 && P2P2
    fprintf('PROBE_OK probe_reprojection_inputs 2/0\n');
else
    error('PROBE_FAIL probe_reprojection_inputs');
end
end

function write_text(path, text)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0);
fwrite(fid, char(text), 'char*1');
fclose(fid);
end

function out = tf(value)
if value, out = 'T'; else, out = 'F'; end
end

function cleanup_case(root)
if exist(root, 'dir'), rmdir(root, 's'); end
end
