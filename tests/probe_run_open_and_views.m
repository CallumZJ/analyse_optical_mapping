function probe_run_open_and_views
%% Probe: opening membrane runs, NaN values, camera bindings and the row flip
% Collin Snitchler
% 06.10.2026
% Checks the parts of the run opening and the reprojection set-up that a
% membrane-fit run and real data reach:
%   O1 a finished run with mesh-cleanup.ply and no alignment-rebuilt-mesh.ply
%      opens, and the viewer's mesh panel shows mesh-cleanup.ply
%   O2 the same run with NaN activation values in its projected PLY opens and
%      its activation panel is READY
%   O3 the PLY gate allows NaN in a scalar value and refuses NaN coordinates
%      and malformed values
%   O4 camera bindings: images cut by this app (file names) use the ROI-row
%      numbering, view<k>/ folders decide by the camera sizes, and equal
%      tile sizes under both numberings are refused as ambiguous; camera
%      sizes that fit neither numbering keep the folder names with a warning;
%      a stated numbering is used as stated
%   O5 the OM row-flip shift matches a flip worked out on an array
% O1 and O2 copy the golden run (OM_TEST_RESTORE_GOLDEN_ROOT, the folder holding
% subset.matom) into a temporary folder; they are skipped when it is unset.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_run_open_and_views"

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0; skipped = 0;
tf = @(b) char(70 + 14 * logical(b));
work = fullfile(tempdir, ['probe_open_' char(java.util.UUID.randomUUID())]);
mkdir(work);
cleanup = onCleanup(@() remove_folder(work));

%% O1, O2: a membrane run with NaN activation values
golden_root = om_test_getenv('OM_TEST_RESTORE_GOLDEN_ROOT');
golden_run = '20260909T110043_d091bb44';
gdir = fullfile(golden_root, 'subset.matom', 'reconstruction', 'runs', golden_run);
if isempty(golden_root) || ~isfolder(gdir)
    fprintf('O1, O2: golden run not available (OM_TEST_RESTORE_GOLDEN_ROOT): skipped\n');
    skipped = skipped + 2;
else
    run_dir = fullfile(work, 'ds', 'subset.matom', 'reconstruction', 'runs', golden_run);
    mkdir(fileparts(run_dir));
    copyfile(gdir, run_dir);
    fileattrib(fullfile(run_dir, '*'), '+w', '', 's'); %#ok<FILEATTRIB>
    out = fullfile(run_dir, 'outputs');
    % The meshing stage's mesh replaces the alignment's rebuilt mesh
    copyfile(fullfile(out, 'alignment-rebuilt-mesh.ply'), fullfile(out, 'mesh-cleanup.ply'));
    delete(fullfile(out, 'alignment-rebuilt-mesh.ply'));
    % and its mesh record says membrane fit, as a membrane run's does
    gates_file = fullfile(out, 'mesh-cleanup-gates.json');
    gates_txt = fileread(gates_file);
    gates_txt = regexprep(gates_txt, '^\{', '{\n  "mesh_method": "membrane",', 'once');
    fid = fopen(gates_file, 'w', 'n', 'UTF-8');
    fwrite(fid, gates_txt, 'char');
    fclose(fid);
    fprintf('O1: a membrane run without alignment-rebuilt-mesh.ply opens\n');
    tab = rabbit_reconstruction_tab();
    tab.load_state(fullfile(work, 'ds'), 'subset');
    [ok1, err1, info1] = tab.open_manifest(fullfile(run_dir, 'manifest.json'));
    [~, mesh_name] = fileparts(char(info1.rebuilt_ply));
    [vok, ~, vis] = tab.visualisation_artifacts(golden_run);
    [pok, ~, panels] = tab.visualisation_panel_model(vis);
    mesh_method = tab.viewer_mesh_method(char(info1.rebuilt_ply));
    O1 = ok1 && strcmp(mesh_name, 'mesh-cleanup') && vok && pok && ...
        strcmp(panels(2).render_status, 'READY') && strcmp(mesh_method, 'membrane fit');
    fprintf('  open %s (%s), mesh %s (%s), mesh panel %s -> %s\n', tf(ok1), err1, mesh_name, ...
        mesh_method, panels(2).render_status, tf(O1));
    if O1, pass = pass + 1; else, fail = fail + 1; end

    fprintf('O2: NaN activation values in the projected PLY\n');
    ply = fullfile(out, 'reprojection', 'activation_projected.ply');
    txt = fileread(ply);
    head_end = strfind(txt, 'end_header');
    body = txt(head_end(1):end);
    lines = regexp(body, '\n', 'split');
    n_nan = 0;
    for k = 2:2:min(200, numel(lines))
        % The activation value is the last field; a CR line ending is kept
        new_line = regexprep(lines{k}, '\S+(\r?)$', 'NaN$1', 'once');
        n_nan = n_nan + ~strcmp(new_line, lines{k});
        lines{k} = new_line;
    end
    fid = fopen(ply, 'w', 'n', 'UTF-8');
    fwrite(fid, [txt(1:head_end(1) - 1) strjoin(lines, newline)], 'char');
    fclose(fid);
    tab2 = rabbit_reconstruction_tab();
    tab2.load_state(fullfile(work, 'ds'), 'subset');
    [ok2, err2] = tab2.open_manifest(fullfile(run_dir, 'manifest.json'));
    [~, ~, vis2] = tab2.visualisation_artifacts(golden_run);
    [~, ~, panels2] = tab2.visualisation_panel_model(vis2);
    O2 = n_nan > 0 && ok2 && strcmp(panels2(3).render_status, 'READY');
    fprintf('  %d values set to NaN, open %s (%s), activation panel %s -> %s\n', n_nan, tf(ok2), err2, ...
        panels2(3).render_status, tf(O2));
    if O2, pass = pass + 1; else, fail = fail + 1; end
end

%% O3: the PLY gate
fprintf('O3: NaN only in scalar values\n');
tab3 = rabbit_reconstruction_tab();
head = sprintf(['ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\n' ...
    'property float z\nproperty float activation\nelement face 1\n' ...
    'property list uchar int vertex_indices\nend_header\n']);
cases = { ...
    'scalar NaN', sprintf('0 0 0 NaN\n1 0 0 2\n0 1 0 3\n3 0 1 2\n'), true; ...
    'coordinate NaN', sprintf('NaN 0 0 1\n1 0 0 2\n0 1 0 3\n3 0 1 2\n'), false; ...
    'malformed value', sprintf('0 0 0 abc\n1 0 0 2\n0 1 0 3\n3 0 1 2\n'), false};
O3 = true;
detail = {};
for k = 1:size(cases, 1)
    path = fullfile(work, sprintf('gate_%d.ply', k));
    fid = fopen(path, 'w', 'n', 'UTF-8');
    fwrite(fid, [head cases{k, 2}], 'char');
    fclose(fid);
    gate_ok = tab3.validate_render_ply(path);
    O3 = O3 && gate_ok == cases{k, 3};
    detail{end+1} = sprintf('%s %s', cases{k, 1}, tf(gate_ok)); %#ok<AGROW>
end
% Binary: a NaN activation passes, a NaN coordinate does not
for k = 1:2
    path = fullfile(work, sprintf('gate_bin_%d.ply', k));
    fid = fopen(path, 'w', 'ieee-le');
    fprintf(fid, ['ply\nformat binary_little_endian 1.0\nelement vertex 3\nproperty float x\n' ...
        'property float y\nproperty float z\nproperty float activation\nelement face 1\n' ...
        'property list uchar int vertex_indices\nend_header\n']);
    v = single([0 0 0 NaN; 1 0 0 2; 0 1 0 3]);
    if k == 2, v(1, 1) = NaN; end
    fwrite(fid, v', 'single');
    fwrite(fid, uint8(3), 'uint8');
    fwrite(fid, int32([0 1 2]), 'int32');
    fclose(fid);
    gate_ok = tab3.validate_render_ply(path);
    O3 = O3 && gate_ok == (k == 1);
    detail{end+1} = sprintf('binary %d %s', k, tf(gate_ok)); %#ok<AGROW>
end
fprintf('  %s -> %s\n', strjoin(detail, ', '), tf(O3));
if O3, pass = pass + 1; else, fail = fail + 1; end

%% O4: camera bindings
fprintf('O4: which camera belongs to which view\n');
roi_equal = fullfile(work, 'roi_equal.json');
roi_unequal = fullfile(work, 'roi_unequal.json');
write_roi(roi_equal, [1 1 400 400; 1 401 400 800; 1 801 400 1200; 1 1201 400 1600]);
write_roi(roi_unequal, [1 1 400 428; 1 429 353 780; 1 781 334 1132; 1 1133 359 1424]);
% ROI rows 1-4 have the tile sizes [400 428; 353 352; 334 352; 359 292]
same = [400 400; 400 400; 400 400; 400 400];
unequal = [400 428; 353 352; 334 352; 359 292];
folders = {'view1/view1_0001.tiff', 'view2/view2_0001.tiff', 'view3/view3_0001.tiff', 'view4/view4_0001.tiff'};
cut_names = {'rec_view1_frame_0001.tiff', 'rec_view2_frame_0001.tiff', ...
    'rec_view3_frame_0001.tiff', 'rec_view4_frame_0001.tiff'};
[cams, imgs] = model(folders, same);
[b_amb, e_amb] = tab3.roi_row_bindings(cams, imgs, roi_equal, '');
[cams, imgs] = model(cut_names, same);
[b_cut, e_cut] = tab3.roi_row_bindings(cams, imgs, roi_equal, '');
[cams, imgs] = model(folders, unequal);        % camera k has the size of ROI row k
[b_rows, e_rows] = tab3.roi_row_bindings(cams, imgs, roi_unequal, '');
[cams, imgs] = model(folders, unequal([3 1 2 4], :));   % camera k has the size of view k
[b_def, e_def] = tab3.roi_row_bindings(cams, imgs, roi_unequal, '');
[cams, imgs] = model(folders, unequal / 2);     % no camera has a tile size
[b_none, e_none, n_none] = tab3.roi_row_bindings(cams, imgs, roi_unequal, '');
[b_set, e_set, n_set] = tab3.roi_row_bindings(cams, imgs, roi_unequal, '', 'roi_rows');
% ROI row 1 is the view called view2; under ROI-row numbering it is image 1
O4 = isempty(b_amb) && contains(e_amb, 'Cannot tell') && ...
    isempty(e_cut) && numel(b_cut) == 4 && strcmp(b_cut(1).view_id, 'view2') && b_cut(1).image_id == 1 && ...
    isempty(e_rows) && numel(b_rows) == 4 && b_rows(1).image_id == 1 && b_rows(3).image_id == 3 && ...
    isempty(e_def) && isempty(b_def) && ...
    isempty(b_none) && isempty(e_none) && contains(n_none, 'folder names were used') && ...
    isempty(e_set) && isempty(n_set) && numel(b_set) == 4;
fprintf(['  equal tiles in view folders: refused %s; cut file names: ROI rows %s; sizes of ROI rows: %s; ' ...
    'sizes of views: default %s; no size fits: folder names with a warning %s; numbering stated: ' ...
    'ROI rows %s -> %s\n'], ...
    tf(~isempty(e_amb)), tf(numel(b_cut) == 4), tf(numel(b_rows) == 4), tf(isempty(b_def)), ...
    tf(~isempty(n_none)), tf(numel(b_set) == 4), tf(O4));
if O4, pass = pass + 1; else, fail = fail + 1; end

%% O5: the row-flip shift
fprintf('O5: row shift between a cut tile and its flipped OM view\n');
H = 12;
O5 = true;
for r = [3 9; 5 12; 2 10]'          % tiles whose cut and OM rows overlap
    r1 = r(1); r2 = r(2);
    raw = (1:H)';                       % row numbers of the raw frame
    loaded = flipud(raw);               % the app's FITS frame
    om_view = flipud(loaded(r1:r2));    % the tile cut from it, flipped back
    cut_tile = raw(r1:r2);              % the tile the camera sees
    % For each cut-tile row, the OM-view row that holds the same raw row
    dy_seen = NaN(numel(cut_tile), 1);
    for y = 1:numel(cut_tile)
        i = find(om_view == cut_tile(y));
        if ~isempty(i), dy_seen(y) = i - y; end
    end
    dy_seen = unique(dy_seen(~isnan(dy_seen)));
    if isempty(dy_seen), dy_seen = NaN; end
    O5 = O5 && isscalar(dy_seen) && dy_seen == tab3.om_flip_shift(r1, r2, H);
end
fprintf('  -> %s\n', tf(O5));
if O5, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_RUN_OPEN_AND_VIEWS RESULT: %d passed, %d failed, %d skipped\n', pass, fail, skipped);
if fail == 0
    fprintf('PROBE_OK probe_run_open_and_views %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_run_open_and_views\n');
end
end


function [cameras, images] = model(names, sizes)
% COLMAP maps as read_sparse_model returns them: image k uses camera k of size sizes(k, :)
cameras = containers.Map('KeyType', 'int64', 'ValueType', 'any');
images = containers.Map('KeyType', 'int64', 'ValueType', 'any');
for k = 1:numel(names)
    cameras(int64(k)) = struct('model', 'SIMPLE_PINHOLE', 'height', sizes(k, 1), ...
        'width', sizes(k, 2), 'params', [500; sizes(k, 2) / 2; sizes(k, 1) / 2]);
    images(int64(k)) = struct('name', names{k}, 'camera_id', int64(k));
end
end


function write_roi(path, bounds)
% A rabbit panoramic ROI JSON with the given bounds (rows view2;view3;view1;view4)
rabbit_stack_io.save_roi_json(path, struct('schema_version', 1, ...
    'region_bounds_src', bounds, 'regions', 4, 'rotation', 0, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', max(bounds(:, 3)), ...
    'width', max(bounds(:, 4))), 'coordinate_origin', 'top-left', ...
    'unmirrored_coordinates', true, 'view_order', {{'view2', 'view3', 'view1', 'view4'}}));
end


function remove_folder(folder)
% Remove the probe's temporary folder
if isfolder(folder)
    try
        fileattrib(fullfile(folder, '*'), '+w', '', 's'); %#ok<FILEATTRIB>
    catch
    end
    rmdir(folder, 's');
end
end
