function probe_fov_measure
%% Probe: measured position of the optical mapping window in a larger frame
% Collin Snitchler
% 14.10.2026
% Checks, without a GUI, that:
%   - measure_fov_offset finds a known row and column offset in synthetic
%     frames, and gives NaN for a flat image;
%   - propose_fov_mapping uses the measured offset (not the July 2026
%     value), drops the July per-view offsets, keeps the uniform-scale case
%     and, without images, keeps the old defaults;
%   - a frame that is upside down (as the app shows FITS recordings) only
%     matches after it is flipped back;
%   - the cut writes whole-number optical-mapping frames as uint16 and
%     leaves the reconstruction policy as it was.
% With OM_FOV_PROBE_SMALL and OM_FOV_PROBE_LARGE (two FITS files from the
% same camera, the first with fewer rows) it also measures the real pair
% and prints the result.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_fov_measure" -noFigureWindows
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0;
fail = 0;

% Synthetic camera frame: smooth background plus structure, so the match
% has a single clear peak
rng(7);
big = conv2(rand(300, 260), ones(7) / 49, 'same') + linspace(0, 0.3, 260);
small = big(41:140, 11:210);   % rows 41-140, columns 11-210 -> offset 40, 10
est = rabbit_stack_io.measure_fov_offset(small, big);
[pass, fail] = check(pass, fail, 'finds-offset', est.off == 40 && est.cols_off == 10 && est.ncc > 0.999, ...
    sprintf('off %d cols_off %d ncc %.4f', est.off, est.cols_off, est.ncc));
est = rabbit_stack_io.measure_fov_offset(zeros(100, 200), big);
[pass, fail] = check(pass, fail, 'flat-image-nan', isnan(est.ncc), '');
up = rabbit_stack_io.measure_fov_offset(flip(small, 1), big);
back = rabbit_stack_io.measure_fov_offset(flip(flip(small, 1), 1), big);
[pass, fail] = check(pass, fail, 'flip-matters', up.ncc < 0.9 && back.off == 40 && back.ncc > 0.999, ...
    sprintf('upside down ncc %.3f, flipped back off %d', up.ncc, back.off));

m = rabbit_stack_io.propose_fov_mapping(100, 200, 300, 260, 'reconstruction', small, big);
[pass, fail] = check(pass, fail, 'proposal-measured', strcmp(m.type, 'crop') && m.om_window_in_rec.off == 40 && ...
    m.om_window_in_rec.cols_off == 10 && ~isfield(m.om_window_in_rec, 'per_view_offsets') && ...
    contains(m.provenance, 'measured'), m.provenance);
v = rabbit_stack_io.validate_fov_mapping(m);
mb = rabbit_stack_io.map_bounds_across_fov([1 1 100 200], v);
[pass, fail] = check(pass, fail, 'proposal-maps-bounds', isequal(mb, [41 11 140 210]), mat2str(mb));
m = rabbit_stack_io.propose_fov_mapping(400, 2000, 800, 2000, 'reconstruction');
[pass, fail] = check(pass, fail, 'no-images-keeps-default', m.om_window_in_rec.off == 192, '');
m = rabbit_stack_io.propose_fov_mapping(100, 200, 200, 400, 'reconstruction', small, big);
% no scale is guessed from the size ratio any more (another
% binning is refused from the FITS header); the frame is placed as a crop
[pass, fail] = check(pass, fail, 'no-scale-guessed', strcmp(m.type, 'crop') && m.scale.vertical == 1, m.type);

% Cut policy: whole-number doubles (fitsread output) stay camera counts
% for the optical mapping and reconstruction copies, not for calibration
counts = double(randi([0 4095], 20, 30));
[pass, fail] = check(pass, fail, 'om-counts-uint16', ...
    strcmp(rabbit_cut_tiffs.class_policy(counts, 'om'), 'whole_number_uint16') && ...
    strcmp(rabbit_cut_tiffs.class_policy(counts, 'reconstruction'), 'whole_number_uint16') && ...
    strcmp(rabbit_cut_tiffs.class_policy(counts, 'calibration'), 'normalized_uint8') && ...
    strcmp(rabbit_cut_tiffs.class_policy(counts + 0.5, 'om'), 'normalized_uint8') && ...
    strcmp(rabbit_cut_tiffs.class_policy(uint16(counts), 'om'), 'uint16'), '');
tmp = [tempname '.tiff'];
rabbit_cut_tiffs.write_crop(counts, tmp, 'whole_number_uint16');
back = imread(tmp);
delete(tmp);
[pass, fail] = check(pass, fail, 'om-counts-exact', isa(back, 'uint16') && isequal(double(back), counts), class(back));

% Real pair (optional)
a = getenv('OM_FOV_PROBE_SMALL');
b = getenv('OM_FOV_PROBE_LARGE');
if ~isempty(a) && ~isempty(b)
    ia = fitsinfo(a).PrimaryData.Size;
    ib = fitsinfo(b).PrimaryData.Size;
    fa = fitsread(a, 'PixelRegion', {[1 ia(1)], [1 ia(2)], [1 1]});
    fb = fitsread(b, 'PixelRegion', {[1 ib(1)], [1 ib(2)], [1 1]});
    rel = rabbit_stack_io.classify_fov_relation(ia(1), ia(2), ib(1), ib(2));
    m = rabbit_stack_io.propose_fov_mapping(ia(1), ia(2), ib(1), ib(2), 'reconstruction', fa, fb);
    fprintf('real pair %dx%d in %dx%d: %s, %s\n', ia(1), ia(2), ib(1), ib(2), rel, m.provenance);
    [pass, fail] = check(pass, fail, 'real-pair-fits', strcmp(rel, 'crop') && ...
        m.om_window_in_rec.off + ia(1) <= ib(1) && m.om_window_in_rec.cols_off + ia(2) <= ib(2), ...
        sprintf('off %d', m.om_window_in_rec.off));
end

fprintf('probe_fov_measure: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('probe_fov_measure:Failed', '%d check(s) failed.', fail);
end
end

function [pass, fail] = check(pass, fail, id, ok, detail)
if ok
    pass = pass + 1;
    fprintf('PASS %s %s\n', id, detail);
else
    fail = fail + 1;
    fprintf('FAIL %s %s\n', id, detail);
end
end
