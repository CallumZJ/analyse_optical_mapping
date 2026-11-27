function probe_dense_options
%% Probe: the dense cloud choice (COLMAP, or APDe-MVS + COLMAP) and the silhouette fix
% Collin Snitchler
% 24.11.2026
% Checks, without COLMAP, APDe-MVS, a GPU or the OM data:
%   D1 the steps of a new run: built 8 ("COLMAP") or 10 ("APDe-MVS +
%      COLMAP"), existing sparse model 6 or 8; COLMAP's depth maps and
%      fusion in every choice; defaults as before ("COLMAP" for a built
%      run, "APDe-MVS + COLMAP" on an existing sparse model); without a
%      choice the orders are those before 24.11.2026; every step has a
%      plain name
%   D2 runs recorded before 24.11.2026: no pipeline (8 steps), built on
%      the fused cloud (8), built on the APDe-MVS cloud (10) keep their
%      order and map onto their dense clouds; the new 6-step order of an
%      existing sparse model is accepted; orders this app cannot drive
%      (no COLMAP, half a step pair, an unknown step) are refused; a
%      choice other than colmap or both is refused
%   D3 the new user text says View, never "tile"
%   D4 the silhouette fix: the COLMAP points that judge an APDe-MVS mesh
%      (M4, M9, the membrane cameras) are silhouette-filtered: on a
%      synthetic sphere with bath points around it, every bath point
%      leaves the M4 inputs and the tissue points stay, with their .vis
%      rows; without the filter (0) the bath points stay, as before
%   D5 the app (headless): the "Clouds to compute" drop-down defaults per
%      sparse model source, "Cloud used to build the mesh" is a choice
%      only with "APDe-MVS + COLMAP", and the step list follows
%   D6 the labels (formerly "Dense cloud" and "from") and tooltips say
%      what they choose, and the mesh row leaves the label its full text
%      and the drop-down room, at the default and a narrow width
% Usage: matlab -batch "setenv('OM_APP_HEADLESS','1'); addpath('<repo>/tests'); probe_dense_options" -noFigureWindows
%   OM_DENSE_SKIP_GUI=1 leaves out D5.

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
tf = @(b) char(70 + 14 * logical(b));
work = tempname;
mkdir(work);
cleanup = onCleanup(@() rmdir(work, 's'));
T = 'rabbit_reconstruction_tab';
tab = rabbit_reconstruction_tab();
drv = feval([T '.driver_stage_order']);
apde = {'apde_scene_prep', 'apde_run'};
colmap = {'patch_match_stereo', 'stereo_fusion'};

%% D1 the steps of each choice
want = struct('built', struct('colmap', 8, 'both', 10), 'supplied', struct('colmap', 6, 'both', 8));
ok1 = true; txt = {};
for src = {'built', 'supplied'}
    for dn = {'colmap', 'both'}
        o = feval([T '.stage_order_for_source'], src{1}, 'fused', dn{1});
        labels = cellfun(@(s) tab.stage_label(s), o, 'UniformOutput', false);
        ok1 = ok1 && numel(o) == want.(src{1}).(dn{1}) && all(ismember(colmap, o)) && ...
            isequal(all(ismember(apde, o)), strcmp(dn{1}, 'both')) && ~any(ismember(apde, o)) == strcmp(dn{1}, 'colmap') && ...
            isequal(ismember({'sparse_prep', 'sparse_build'}, o), repmat(strcmp(src{1}, 'built'), 1, 2)) && ...
            ~any(strcmp(labels, o));
        txt{end+1} = sprintf('%s/%s %d', src{1}, dn{1}, numel(o)); %#ok<AGROW>
    end
end
def_ok = strcmp(feval([T '.dense_default'], 'built'), 'colmap') && strcmp(feval([T '.dense_default'], 'supplied'), 'both');
same_supplied = isequal(feval([T '.stage_order_for_source'], 'supplied', 'fused', 'both'), drv);
old_ok = numel(feval([T '.stage_order_for_source'], 'built', 'fused')) == 8 && ...
    numel(feval([T '.stage_order_for_source'], 'built', 'apd')) == 10 && ...
    isequal(feval([T '.stage_order_for_source'], 'supplied', 'fused'), drv);
ok1 = ok1 && def_ok && same_supplied && old_ok;
fprintf(['D1 steps: %s; defaults built COLMAP, existing model APDe-MVS + COLMAP %s; existing model with both = the ' ...
    'eight driver steps of today %s; orders without a choice as before %s -> %s\n'], strjoin(txt, ', '), tf(def_ok), ...
    tf(same_supplied), tf(old_ok), tf(ok1));
if ok1, pass = pass + 1; else, fail = fail + 1; end

%% D2 runs recorded before 24.11.2026, and orders that cannot be driven
built_fused = [{'sparse_prep', 'sparse_build'}, drv(~ismember(drv, apde))];
built_apd = [{'sparse_prep', 'sparse_build'}, drv];
cases = {struct('run_id', 'x'), drv, 'both'; ...
    struct('pipeline', struct('sparse_source', 'built', 'cloud_source', 'fused', 'stage_order', {built_fused})), built_fused, 'colmap'; ...
    struct('pipeline', struct('sparse_source', 'built', 'cloud_source', 'apd', 'stage_order', {built_apd})), built_apd, 'both'; ...
    struct('pipeline', struct('sparse_source', 'supplied', 'dense', 'colmap', 'stage_order', {drv(~ismember(drv, apde))})), drv(~ismember(drv, apde)), 'colmap'};
map_ok = true;
for k = 1:size(cases, 1)
    o = tab.stage_order_for_manifest(cases{k, 1});
    map_ok = map_ok && isequal(o, cases{k, 2}) && strcmp(feval([T '.dense_for_order'], o), cases{k, 3});
end
% no COLMAP; half the COLMAP pair; half the APDe-MVS pair; an unknown step
bad = {{'image_undistorter', 'apde_scene_prep', 'apde_run', 'mesh_cleanup', 'alignment', 'reprojection'}, ...
    {'image_undistorter', 'stereo_fusion', 'mesh_cleanup', 'alignment', 'reprojection'}, ...
    {'image_undistorter', 'apde_run', 'patch_match_stereo', 'stereo_fusion', 'mesh_cleanup', 'alignment', 'reprojection'}, ...
    {'image_undistorter', 'apde_visibility', 'patch_match_stereo', 'stereo_fusion', 'mesh_cleanup', 'alignment', 'reprojection'}};
refused = 0;
for k = 1:numel(bad)
    try
        tab.stage_order_for_manifest(struct('pipeline', struct('stage_order', bad(k))));
    catch
        refused = refused + 1;
    end
end
[c_ok, c_err] = tab.create_run('probe_bad_dense', struct('dense', 'apde'));
ok2 = map_ok && refused == numel(bad) && ~c_ok && contains(c_err, 'colmap or both');
fprintf('D2 old runs map onto their clouds %s; %d of %d bad orders refused; choice "apde" refused ("%s") -> %s\n', ...
    tf(map_ok), refused, numel(bad), c_err, tf(ok2));
if ok2, pass = pass + 1; else, fail = fail + 1; end

%% D3 the new user text says View, never "tile"
full = feval([T '.full_stage_order']);
texts = [cellfun(@(s) tab.stage_label(s), full, 'UniformOutput', false), ...
    cellfun(@(s) feval([T '.short_stage_label'], s), full, 'UniformOutput', false)];
H = reconstruction_help_content();
for id = {'stages', 'inputs'}
    k = find(strcmp({H.topics.id}, id{1}), 1);
    if isempty(k), continue; end
    body = H.topics(k).body;
    if ~strcmp(id{1}, 'stages'), body = body(contains(body, {'APDe-MVS', 'Dense cloud', 'dense cloud'})); end
    texts = [texts, body]; %#ok<AGROW>
end
ui = fileread(fullfile(repo_dir, 'rabbit_reconstruction_ui.m'));
blk = regexp(ui, '(obj\.ReconstructionDenseLabel = uilabel.*?obj\.reconstruction_dense_sync\(\);)', 'tokens', 'once');
fns = regexp(ui, '(function reconstruction_dense_sync.*?function reconstruction_cloud_source_changed)', 'tokens', 'once');
strs = regexp([blk{:} fns{:}], '''([^''\n]*)''', 'tokens');
texts = [texts, cellfun(@(c) c{1}, strs, 'UniformOutput', false)];
texts = cellfun(@(t) strrep(char(t), 'om_tile_transform', ''), texts, 'UniformOutput', false);
hits = texts(~cellfun(@isempty, regexpi(texts, '\<tiles?\>', 'once')));
% the tooltip says COLMAP is always needed, for the visibility checks
names_ok = contains(ui, '''COLMAP'', ''APDe-MVS + COLMAP''') && contains(ui, 'COLMAP is always needed, for the visibility checks');
ok3 = isempty(hits) && names_ok && numel(texts) > 30;
fprintf('D3 %d user texts, none says "tile" %s%s; choice names and tooltip %s -> %s\n', numel(texts), tf(isempty(hits)), ...
    strjoin(strcat({' | '}, hits), ''), tf(names_ok), tf(ok3));
if ok3, pass = pass + 1; else, fail = fail + 1; end

%% D4 the silhouette fix drops bath points from the M4 inputs
[sp_dir, mask_dir, ~, P] = sphere_scene(work);
[cameras, images] = rabbit_mesh_cleanup.read_colmap_model(fullfile(sp_dir, 'images.bin'));
fcams = rabbit_mesh_cleanup.filter_cameras(cameras, images, mask_dir, 0);
rng(11);
B = randn(3000, 3);
B = 1.8 * B ./ vecnorm(B, 2, 2);                 % bath and holder: a shell well outside the tissue
X = [P; B];
is_bath = [false(size(P, 1), 1); true(size(B, 1), 1)];
vis = num2cell(int32(1:size(X, 1))');           % each row names its own point, to follow the rows
rgb = zeros(size(X, 1), 3, 'uint8');
[fx, fv, ~, rec] = rabbit_mesh_cleanup.camera_check_points(X, vis, rgb, fcams, 0.9, 16, 3);
rows = double([fv{:}]);
rows_ok = isequal(X(rows, :), fx);
bath_left = sum(is_bath(rows));
tissue_kept = sum(~is_bath(rows)) / sum(~is_bath);
[fx0, ~, ~, rec0] = rabbit_mesh_cleanup.camera_check_points(X, vis, rgb, fcams, 0, 16, 3);
[~, inb] = ismember(B, fx0, 'rows');
ok4 = numel(fcams) == 8 && rows_ok && bath_left == 0 && tissue_kept >= 0.95 && ~isempty(rec) && ...
    rec.n_points_in == size(X, 1) && isempty(rec0) && mean(inb > 0) > 0.9;
fprintf(['D4 silhouette fix: %d masks; bath points left in the M4 inputs %d of %d; tissue points kept %.3f; .vis rows ' ...
    'follow their points %s; without the filter %.0f %% of the bath points stay (as before) -> %s\n'], numel(fcams), ...
    bath_left, size(B, 1), tissue_kept, tf(rows_ok), 100 * mean(inb > 0), tf(ok4));
if ok4, pass = pass + 1; else, fail = fail + 1; end

%% D5 the app
if isempty(getenv('OM_DENSE_SKIP_GUI'))
    app = analyse_optical_mapping();
    close_app = onCleanup(@() delete(app));
    r = app.recon;
    r.ReconstructionSparseSourceDropDown.Value = 'built';
    r.reconstruction_sparse_source_changed();
    built_def = strcmp(r.ReconstructionDenseDropDown.Value, 'colmap') && ...
        strcmp(char(r.ReconstructionCloudSourceDropDown.Enable), 'off') && numel(r.ReconstructionStageList.Items) == 8;
    set_dense(r, 'both');
    both = strcmp(char(r.ReconstructionCloudSourceDropDown.Enable), 'on') && numel(r.ReconstructionStageList.Items) == 10;
    set_dense(r, 'colmap');
    r.ReconstructionSparseSourceDropDown.Value = 'supplied';
    r.reconstruction_sparse_source_changed();
    supplied_def = strcmp(r.ReconstructionDenseDropDown.Value, 'both') && numel(r.ReconstructionStageList.Items) == 8;
    set_dense(r, 'colmap');
    supplied_colmap = numel(r.ReconstructionStageList.Items) == 6 && strcmp(r.ReconstructionCloudSourceDropDown.Value, 'fused');
    r.ReconstructionSparseSourceDropDown.Value = 'built';
    r.reconstruction_sparse_source_changed();
    kept = strcmp(r.ReconstructionDenseDropDown.Value, 'colmap');
    ok5 = built_def && both && supplied_def && supplied_colmap && kept;
    fprintf(['D5 app: built default COLMAP, 8 steps, from off %s; APDe-MVS + COLMAP 10 steps, from on %s; existing ' ...
        'model default APDe-MVS + COLMAP, 8 steps %s; COLMAP 6 steps %s; choice kept per source %s -> %s\n'], ...
        tf(built_def), tf(both), tf(supplied_def), tf(supplied_colmap), tf(kept), tf(ok5));
    if ok5, pass = pass + 1; else, fail = fail + 1; end

    %% D6 labels, tooltips and room in the mesh row
    addpath(fullfile(repo_dir, 'tests', 'helpers'));
    lab_ok = strcmp(r.ReconstructionDenseLabel.Text, 'Clouds to compute') && ...
        strcmp(r.ReconstructionCloudSourceLabel.Text, 'Cloud used to build the mesh') && ...
        isequal(r.ReconstructionDenseDropDown.Items, {'COLMAP', 'APDe-MVS + COLMAP'});
    dense_tip = strjoin(cellstr(r.ReconstructionDenseDropDown.Tooltip), ' ');
    set_dense(r, 'both');
    src_tip_on = strjoin(cellstr(r.ReconstructionCloudSourceDropDown.Tooltip), ' ');
    set_dense(r, 'colmap');
    src_tip_off = strjoin(cellstr(r.ReconstructionCloudSourceDropDown.Tooltip), ' ');
    tip_ok = contains(dense_tip, 'COLMAP is always needed, for the visibility checks') && ...
        all(contains({src_tip_on, src_tip_off}, 'For the next run')) && ...
        all(contains({src_tip_on, src_tip_off}, 'shown in its Results')) && ...
        contains(src_tip_off, '"Clouds to compute"') && ~contains([dense_tip src_tip_off], '"from"');
    fig = app.opticalmappingUIFigure;
    tg = app.TabGroup;
    tg.Visible = 'on';
    tg.SelectedTab = r.ReconstructionTab;
    r.reconstruction_set_accordion(4, false);
    default_size = fig.Position(3:4);
    room_ok = true; room = {};
    for size_k = {default_size, [1000 default_size(2)]}
        fig.Position(3:4) = size_k{1};
        tg.Position = [tg.Position(1), 1, size_k{1}(1) - 2 * tg.Position(1), size_k{1}(2) - 2];
        drawnow;
        pause(1);
        exportapp(fig, [tempname '.png']);   % lays the window out, as it is drawn
        lw = r.ReconstructionCloudSourceLabel.Position(3);
        dw = r.ReconstructionCloudSourceDropDown.Position(3);
        over = ui_control_overlaps(r.ReconstructionCloudSourceLabel.Parent.Parent);   % the next-run panel
        inside = r.ReconstructionRunButton.Parent.Position;   % the Run row stays inside the panel's grid
        g = r.ReconstructionCloudSourceLabel.Parent;
        fits = inside(2) >= 0 && inside(2) + inside(4) <= g.Position(4) + 1;
        % the drop-down needs about 95 px for "APDe-MVS" in full; at the
        % narrow width the label column is set by "Edge weight (RHYTHM
        % 0.55)" (about 150 px) already, so only a usable width is asked there
        dw_min = 95 - 25 * (size_k{1}(1) < default_size(1));
        room_ok = room_ok && lw >= 140 && dw >= dw_min && isempty(over) && fits;
        room{end + 1} = sprintf('%d px wide: label %d px, drop-down %d px, %d overlaps, Run row inside %d', ...
            size_k{1}(1), round(lw), round(dw), numel(over), fits); %#ok<AGROW>
    end
    ok6 = lab_ok && tip_ok && room_ok;
    fprintf('D6 labels %s; tooltips %s; room in the mesh row %s (%s) -> %s\n', tf(lab_ok), tf(tip_ok), tf(room_ok), ...
        strjoin(room, '; '), tf(ok6));
    if ok6, pass = pass + 1; else, fail = fail + 1; end
    clear close_app
else
    fprintf('D5 app part left out (OM_DENSE_SKIP_GUI)\n');
end

% D7: the tab's own messages name the Step 4
% controls by their labels; no "from COLMAP" (the old label) is left
src7 = fileread(which('rabbit_reconstruction_tab'));
ok7 = ~contains(src7, 'Choose "from COLMAP"') && ~contains(src7, 'started with the dense cloud "COLMAP"') && ...
    contains(src7, 'Set "Cloud used to build the mesh" to ') && contains(src7, 'Clouds to compute "APDe-MVS + COLMAP"');
fprintf('D7 messages name the Step 4 labels -> %s\n', tf(ok7));
if ok7, pass = pass + 1; else, fail = fail + 1; end

fprintf('PROBE_DENSE_OPTIONS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_dense_options %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_dense_options\n');
end
end

function set_dense(r, value)
% Choose the dense cloud as a user would
r.ReconstructionDenseDropDown.Value = value;
feval(r.ReconstructionDenseDropDown.ValueChangedFcn, r.ReconstructionDenseDropDown, []);
end

function [sp_dir, mask_dir, cloud, P, cams] = sphere_scene(work)
% Unit sphere (12000 points, APD.ply layout: x y z + blue green red), 8
% PINHOLE cameras on a ring at distance 4 looking at the centre, and each
% image's silhouette as its tissue mask
rng(7);
n = 12000;
P = randn(n, 3);
P = P ./ vecnorm(P, 2, 2);
P = P + 0.002 * randn(n, 3);
sp_dir = fullfile(work, 'sparse');
mask_dir = fullfile(work, 'masks');
mkdir(sp_dir); mkdir(mask_dir);
w = 200; h = 160; f = 180;
fid = fopen(fullfile(sp_dir, 'cameras.bin'), 'w');
fwrite(fid, 1, 'uint64'); fwrite(fid, 1, 'int32'); fwrite(fid, 1, 'int32');
fwrite(fid, [w h], 'uint64'); fwrite(fid, [f f w / 2 h / 2], 'double');
fclose(fid);
nc = 8;
cams = struct('R', {}, 't', {}, 'C', {});
fid = fopen(fullfile(sp_dir, 'images.bin'), 'w');
fwrite(fid, nc, 'uint64');
for k = 1:nc
    a = 2 * pi * (k - 1) / nc;
    Cc = 4 * [cos(a) sin(a) 0.3];
    z = -Cc / norm(Cc); x = cross([0 0 1], z); x = x / norm(x); y = cross(z, x);
    R = [x; y; z];
    t = -R * Cc(:);
    cams(k) = struct('R', R, 't', t, 'C', Cc);
    name = sprintf('s_view%d_frame_0001.tiff', mod(k - 1, 4) + 1);
    fwrite(fid, 10 + k, 'int32'); fwrite(fid, rot2qvec(R), 'double'); fwrite(fid, t, 'double');
    fwrite(fid, 1, 'int32'); fwrite(fid, [uint8(name) 0], 'uint8');
    fwrite(fid, 0, 'uint64');
    % silhouette of the sphere (a little wider): pixels whose ray passes
    % within 1.03 of the centre
    [uu, vv] = meshgrid((0:w - 1) + 0.5, (0:h - 1) + 0.5);
    D = [(uu(:) - w / 2) / f, (vv(:) - h / 2) / f, ones(numel(uu), 1)] * R;   % ray directions, world
    D = D ./ vecnorm(D, 2, 2);
    along = -(Cc * D')';                                                    % ray parameter nearest the centre
    miss = vecnorm(Cc + along .* D, 2, 2);
    m = reshape(miss <= 1.03 & along > 0, h, w);
    imwrite(uint8(255 * m), fullfile(mask_dir, [name '.png']));
end
fclose(fid);
cloud = fullfile(work, 'APD.ply');
fid = fopen(cloud, 'w');
fprintf(fid, 'ply\nformat binary_little_endian 1.0\nelement vertex %d\n', n);
fprintf(fid, 'property float x\nproperty float y\nproperty float z\n');
fprintf(fid, 'property uchar blue\nproperty uchar green\nproperty uchar red\nend_header\n');
rec = zeros(15, n, 'uint8');
xyz = single(P');
rec(1:12, :) = reshape(typecast(xyz(:), 'uint8'), 12, n);
rec(13:15, :) = 128;
fwrite(fid, rec, 'uint8');
fclose(fid);
end

function q = rot2qvec(R)
% Rotation matrix to COLMAP quaternion (w, x, y, z)
tr = trace(R);
if tr > 0
    s = 0.5 / sqrt(tr + 1);
    q = [0.25 / s, (R(3, 2) - R(2, 3)) * s, (R(1, 3) - R(3, 1)) * s, (R(2, 1) - R(1, 2)) * s];
else
    [~, i] = max(diag(R));
    switch i
        case 1
            s = 2 * sqrt(1 + R(1, 1) - R(2, 2) - R(3, 3));
            q = [(R(3, 2) - R(2, 3)) / s, 0.25 * s, (R(1, 2) + R(2, 1)) / s, (R(1, 3) + R(3, 1)) / s];
        case 2
            s = 2 * sqrt(1 + R(2, 2) - R(1, 1) - R(3, 3));
            q = [(R(1, 3) - R(3, 1)) / s, (R(1, 2) + R(2, 1)) / s, 0.25 * s, (R(2, 3) + R(3, 2)) / s];
        otherwise
            s = 2 * sqrt(1 + R(3, 3) - R(1, 1) - R(2, 2));
            q = [(R(2, 1) - R(1, 2)) / s, (R(1, 3) + R(3, 1)) / s, (R(2, 3) + R(3, 2)) / s, 0.25 * s];
    end
end
q = q(:) / norm(q);
end
