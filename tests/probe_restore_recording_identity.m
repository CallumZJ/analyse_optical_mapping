function probe_restore_recording_identity
%% Recording identity and COLMAP pose checks
% Collin Snitchler
% 13.09.2026
% A renamed copy of a recording must get the same identity; the COLMAP pose
% records must follow the view bindings and the default view names.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
root = tempname;
mkdir(root);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>
source_a = fullfile(root, 'recording-a.bin');
source_b = fullfile(root, 'renamed-recording.bin');
write_bytes(source_a, uint8([1 2 3 4 5 6]));
copyfile(source_a, source_b);
frame_map = struct('acquisition_frame', {'3', '4'}, 'source_frame', {'1', '2'});
file_info = struct('file', source_a, 'path', root, 'name', 'recording-a.bin', 'type', '.bin');
tab = rabbit_reconstruction_tab();
[ok_a, err_a, id_a, digest_a] = tab.build_recording_identity_file(file_info, [2 3 2], frame_map);
assert(ok_a, err_a);
assert(strcmp(id_a.frame_range.values{1}, '3') && strcmp(id_a.frame_range.values{2}, '4'));
assert(strcmp(id_a.members.frame_map(1).acquisition_frame, '3'));
file_info.file = source_b;
[ok_b, err_b, id_b, digest_b] = tab.build_recording_identity_file(file_info, [2 3 2], frame_map);
assert(ok_b, err_b);
assert(strcmp(digest_a, digest_b));
assert(strcmp(jsonencode(id_a), jsonencode(id_b)));

workspace_input = [id_a id_b];
[ok_w, err_w, id_w, ~] = tab.build_recording_identity_workspace(workspace_input, [2 3 4]);
assert(ok_w, err_w);
wm = id_w.members;
assert(strcmp(wm(1).frame_map(1).acquisition_frame, '1'));
assert(strcmp(wm(1).frame_map(2).acquisition_frame, '2'));
assert(strcmp(wm(2).frame_map(1).acquisition_frame, '3'));
assert(strcmp(wm(2).frame_map(2).acquisition_frame, '4'));
assert(strcmp(id_w.frame_range.values{1}, '1') && strcmp(id_w.frame_range.values{2}, '4'));

cameras = containers.Map('KeyType', 'int64', 'ValueType', 'any');
cameras(int64(7)) = struct('model', 'PINHOLE', 'width', uint64(640), 'height', uint64(480), 'params', [500 500 320 240]);
images = containers.Map('KeyType', 'int64', 'ValueType', 'any');
for k = 1:4
    images(int64(k)) = struct('qvec', [1 0 0 0], 'tvec', [k 0 0], ...
        'camera_id', int64(7), 'name', sprintf('exact/view%d frame.png', k));
end
bindings = struct('view_id', {'view2', 'view3', 'view1', 'view4'}, ...
    'image_id', num2cell(int64(1:4)), 'camera_id', num2cell(int64(repmat(7, 1, 4))));
[ok_p, err_p, pose] = tab.build_colmap_pose_wire(cameras, images, bindings);
assert(ok_p, err_p);
assert(strcmp(pose.records(1).view_id, 'view2'));
assert(strcmp(pose.records(1).image_name, 'exact/view1 frame.png'));
assert(strcmp(pose.records(1).camera_id, '7'));
assert(strcmp(pose.camera_artifacts(1).model, 'PINHOLE'));
assert(strcmp(pose.records(1).qvec.values{1}, '3ff0000000000000'));
[ok_r, err_r, resolved] = tab.resolve_colmap_pose_wire(cameras, images, bindings);
assert(ok_r, err_r);
assert(strcmp(resolved.records(4).view_id, 'view4'));
images_default = containers.Map('KeyType', 'int64', 'ValueType', 'any');
for k = 1:4
    images_default(int64(k)) = struct('qvec', [1 0 0 0], 'tvec', [k 0 0], ...
        'camera_id', int64(7), 'name', sprintf('view%d/view%d_0080.tiff', k, k));
end
[ok_d, err_d, default_wire] = tab.resolve_colmap_pose_wire(cameras, images_default, []);
assert(ok_d, err_d);
assert(strcmp(default_wire.records(1).image_name, 'view2/view2_0080.tiff'));
assert(strcmp(default_wire.records(3).image_name, 'view1/view1_0080.tiff'));
% cut images (_view<k>_frame_) are ROI rows; the
% default bindings bound _view1_ to the view called view1, where ROI row 1
% is the view called view2. They now refuse, naming the regions file.
images_cut = containers.Map('KeyType', 'int64', 'ValueType', 'any');
for k = 1:4
    images_cut(int64(k)) = struct('qvec', [1 0 0 0], 'tvec', [k 0 0], ...
        'camera_id', int64(7), 'name', sprintf('13h-05m-59s_view%d_frame_0001.tiff', k));
end
[ok_c, err_c] = tab.resolve_colmap_pose_wire(cameras, images_cut, []);
assert(~ok_c && contains(err_c, 'Cut images are named by region row') && contains(err_c, 'Set View numbering'), 'R9: cut images bound by view name: %s', err_c);
fprintf('PROBE_OK probe_restore_recording_identity 2/0\n');
end

function write_bytes(path, bytes)
fid = fopen(path, 'wb');
assert(fid >= 0);
fwrite(fid, bytes, 'uint8');
fclose(fid);
end

function cleanup_case(root)
if exist(root, 'dir'), rmdir(root, 's'); end
end
