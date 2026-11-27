function probe_view_numbering_and_records
%% Probe: view numbering, alignment check names, run records, RHYTHM stand-ins
% Collin Snitchler
% 07.10.2026
% Checks, without COLMAP or a GUI, that:
%   - an unknown view numbering is refused and the message names the
%     View numbering choice of step 2; 'auto' is accepted;
%   - alignment failures name the checks in words, not codes;
%   - the run manifest records the ROI file's FOV mapping when it has one,
%     and otherwise labels the test-data values as reference values;
%   - the run manifest counts the run's own images (views, frames);
%   - the msgbox/waitbar stand-ins written for dataProjection02 stay
%     hidden, keep MATLAB's Tags, and rhythm_cleanup removes only them.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_view_numbering_and_records"
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0;
fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
tab = rabbit_reconstruction_tab();

%% View numbering
[b, e] = tab.roi_row_bindings(containers.Map('KeyType', 'int64', 'ValueType', 'any'), ...
    containers.Map('KeyType', 'int64', 'ValueType', 'any'), '', '', 'rows');
record('P1 unknown view numbering is refused and names the step 2 choice', ...
    isempty(b) && contains(e, 'Unknown view numbering') && contains(e, 'View numbering in step 2'), e);
[~, e_auto] = tab.roi_row_bindings(containers.Map('KeyType', 'int64', 'ValueType', 'any'), ...
    containers.Map('KeyType', 'int64', 'ValueType', 'any'), '', '', 'auto');
record('P2 view numbering auto is accepted', isempty(e_auto), e_auto);

%% Alignment check names
names = rabbit_mesh_alignment.check_names({'A2', 'A4'});
record('P3 alignment checks are named in words', ...
    strcmp(names, 'projection error; silhouette coverage'), names);

%% FOV mapping record
roi_plain = fullfile(root, 'roi_plain.json');
bounds = [1 1 10 10; 1 11 10 20; 1 21 10 30; 1 31 10 40];
roi = struct('schema_version', 1, 'region_bounds_src', bounds, 'regions', 4, 'rotation', 0, ...
    'rabbit_panoramic', true, 'source_dims', struct('height', 10, 'width', 40), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, ...
    'view_order', {{'view2', 'view3', 'view1', 'view4'}});
rabbit_stack_io.save_roi_json(roi_plain, roi);
f_plain = tab.fov_mapping_contract(roi_plain);
% a readable ROI file without a mapping means the same frame
% (the July reference values are kept only for a file that cannot be read)
f_none = tab.fov_mapping_contract(fullfile(root, 'no_such_roi.json'));
record('P4 no FOV mapping in the ROI file: the same frame; no readable file: reference values, labelled', ...
    contains(f_plain.source, 'the frames are the same') && f_plain.om_window_in_rec.off == 0 && ...
    contains(f_none.source, 'reference values') && contains(f_none.source, 'not measured for this run'), ...
    sprintf('%s | %s', f_plain.source, f_none.source));
roi_fov = fullfile(root, 'roi_fov.json');
roi.fov_mapping = rabbit_stack_io.fov_contract();
roi.fov_mapping.om_window_in_rec.off = 150;
rabbit_stack_io.save_roi_json(roi_fov, roi);
f_fov = tab.fov_mapping_contract(roi_fov);
record('P5 the ROI file''s FOV mapping is recorded when present', ...
    contains(f_fov.source, 'ROI file') && f_fov.om_window_in_rec.off == 150, ...
    sprintf('off %g', f_fov.om_window_in_rec.off));

%% Image discovery record
img = fullfile(root, 'images');
mkdir(img);
for v = 1:4
    for fr = [100 120 140]
        fid = fopen(fullfile(img, sprintf('stem_view%d_frame_%04d.tiff', v, fr)), 'w');
        fclose(fid);
    end
end
d = tab.image_discovery_contract(img);
record('P6 the images of the run are counted', ...
    d.total_images == 12 && d.views == 4 && isequal(d.images_per_view(:)', [3 3 3 3]) && ...
    isequal(d.frames(:)', [100 120 140]) && contains(d.source, 'this run'), ...
    sprintf('%d images, frames %s', d.total_images, mat2str(d.frames)));
d0 = tab.image_discovery_contract(fullfile(root, 'none'));
record('P7 no images: reference values, labelled', contains(d0.source, 'reference values'), d0.source);

%% RHYTHM msgbox/waitbar stand-ins and the selective clean-up
work = fullfile(root, 'rhythm_work');
mkdir(work);
rabbit_rhythm_reproject.write_rhythm_stubs(work);
figs0 = findall(0, 'type', 'figure');
here = cd(work);
h1 = msgbox('Projecting....');
h2 = waitbar(0, 'Projection and mapping...');
waitbar(0.5);
in_work = startsWith(which('msgbox'), work) && startsWith(which('waitbar'), work);
hidden = strcmp(get(h1, 'Visible'), 'off') && strcmp(get(h2, 'Visible'), 'off');
tags = strcmp(get(h1, 'Tag'), 'Msgbox_') && strcmp(get(h2, 'Tag'), 'TMWWaitbar');
fraction = getappdata(h2, 'fraction');
other = figure('Visible', 'off', 'Tag', 'probe_keep');
rabbit_rhythm_reproject.rhythm_cleanup(here, figs0, work);
record('P8 stand-ins are hidden, keep the Tags and follow waitbar(x)', ...
    in_work && hidden && tags && fraction == 0.5, ...
    sprintf('in work %d hidden %d tags %d fraction %g', in_work, hidden, tags, fraction));
record('P9 rhythm_cleanup removes only the stand-ins and the folder', ...
    ~isvalid(h1) && ~isvalid(h2) && isvalid(other) && ~isfolder(work) && strcmp(pwd, here) && ...
    ~startsWith(which('msgbox'), work), which('msgbox'));
delete(other);

fprintf('PROBE_VIEW_NUMBERING_AND_RECORDS RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0
    error('PROBE_FAIL probe_view_numbering_and_records');
end
fprintf('PROBE_OK probe_view_numbering_and_records %d/0\n', pass);

    function record(name, condition, detail)
        if condition
            pass = pass + 1;
            result = 'PASS';
        else
            fail = fail + 1;
            result = 'FAIL';
        end
        fprintf('%s %s %s\n', name, result, detail);
    end
end
