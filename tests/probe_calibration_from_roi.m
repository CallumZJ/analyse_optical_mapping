function probe_calibration_from_roi
%% Probe: a calibration recording lined up in the region dialog is placed from that line-up
% Collin Snitchler
% 20.11.2026
% On-screen the region dialog asks a calibration
% recording's shift against the optical mapping image, the calibration
% window against the reconstruction image. A visiting lab typed the first
% number in the second place and the calibration failed. The ROI file holds
% both line-ups, so rabbit_calibration.offset_from_roi works the position
% out: reconstruction offset minus calibration offset.
%   C1  OM 42 rows into the reconstruction frame, 92 rows into the
%       calibration frame (the visiting-lab copies): the calibration starts
%       at -50 rows, 0 columns; columns work the same way.
%   C2  only for the calibration recording the ROI file names: another
%       file gives [].
%   C3  an ROI file without a calibration line-up, or a scale mapping,
%       gives [].
% Usage: matlab -batch "addpath('<repo>/tests'); probe_calibration_from_roi"
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

cal = fullfile(root, 'cube.tif');                            % the calibration recording the ROI file names
other = fullfile(root, 'other_cube.tif');                    % a recording it does not name
fclose(fopen(cal, 'w')); fclose(fopen(other, 'w'));          % same_file needs them to exist
base = struct('schema_version', 1, 'region_bounds_src', [1 1 10 10; 1 11 10 10; 1 21 10 10; 1 31 10 10], ...
    'regions', 4, 'rotation', 3, 'rabbit_panoramic', true, ...
    'source_dims', struct('height', 400, 'width', 2000), 'coordinate_origin', 'top-left', ...
    'unmirrored_coordinates', true, 'reconstruction_path', '', ...
    'view_order', {{'view2', 'view3', 'view1', 'view4'}});
rec = mapping(42, 0);                                        % OM 42 rows down in the reconstruction frame
roi1 = write_roi(fullfile(root, 'roi1.json'), base, rec, mapping(92, 0), cal);
roi2 = write_roi(fullfile(root, 'roi2.json'), base, mapping(42, 7), mapping(92, 3), cal);
roi3 = write_roi(fullfile(root, 'roi3.json'), base, rec, [], '');

o1 = rabbit_calibration.offset_from_roi(roi1, cal);
o2 = rabbit_calibration.offset_from_roi(roi2, cal);
record('C1 rows: 42 - 92 = -50; columns: 7 - 3 = 4', isequal(o1, [-50 0]) && isequal(o2, [-50 4]), ...
    sprintf('%s, %s', mat2str(o1), mat2str(o2)));
record('C2 another calibration recording: no position', isempty(rabbit_calibration.offset_from_roi(roi1, other)), '');
record('C3 no calibration line-up in the ROI file: no position', isempty(rabbit_calibration.offset_from_roi(roi3, cal)), '');

fprintf('\nPROBE_CALIBRATION_FROM_ROI RESULT: %d passed, %d failed\n', pass, fail);
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

function m = mapping(off, cols_off)
% An offset mapping: the optical mapping frame's top-left in the other frame
m = struct('type', 'crop', 'camera_stationary', true, ...
    'om_window_in_rec', struct('off', off, 'cols_off', cols_off, 'rows', sprintf('%d:%d', off, off + 400), ...
    'cols', sprintf('%d:%d', cols_off, cols_off + 2000)), ...
    'scale', struct('vertical', 1, 'horizontal', 1), 'provenance', 'probe');
end

function p = write_roi(p, base, rec, calm, cal_path)
% An ROI file with the reconstruction and calibration line-ups
s = base;
s.fov_mapping = rec;
if ~isempty(calm)
    s.calibration_fov_mapping = calm;
    s.calibration_path = cal_path;
end
fid = fopen(p, 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(s), 'char');
fclose(fid);
end
