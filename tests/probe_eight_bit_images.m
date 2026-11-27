function probe_eight_bit_images
%% Probe: 8-bit copies of 16-bit images for the COLMAP dense steps
% Collin Snitchler
% 15.10.2026
% COLMAP 4.2.1 reduces 16-bit samples to 8 bits (in effect the high byte), so the undistortion
% step of a run with a supplied sparse model gets 8-bit copies of 16-bit
% cut tiles (rabbit_reconstruction_tab.eight_bit_images). Builds a tiny
% folder at run time (2 views x 3 frames of 16-bit TIFFs using only the
% values 35-3252, like the July tiles, in a subfolder and at the top level).
% Checks:
%   E1  every image gets an 8-bit copy under the same relative name
%   E2  the stretch is per view: nearest-rank 1st and 99.5th percentiles of
%       the view's pixels, the copy equals stretch_u8 with those limits
%   E3  the copies use the full 8-bit range (the high byte alone would
%       leave at most 13 grey levels)
%   E4  a folder of 8-bit images is used as it is (no copies)
%   E5  the note names the class, the folder and the limits per view
%   E6  images in view subfolders (COLMAP layout) are stretched per subfolder
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
tab = rabbit_reconstruction_tab();
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

src = fullfile(root, 'cut');
mkdir(fullfile(src, 'sub'));
rng(3, 'twister');
names = {};
for v = 1:2
    for f = 1:3
        im = uint16(35 + round((3252 - 35) * rand(40, 50) .^ v));
        if f == 1
            rel = fullfile('sub', sprintf('tiny_view%d_frame_%04d.tiff', v, f));
        else
            rel = sprintf('tiny_view%d_frame_%04d.tiff', v, f);
        end
        imwrite(im, fullfile(src, rel));
        names{end+1} = rel; %#ok<AGROW>
    end
end
out = fullfile(root, 'images_8bit');
[ok, err, out_dir, note] = tab.eight_bit_images(src, out);

all_there = ok && strcmp(out_dir, out);
for k = 1:numel(names)
    all_there = all_there && exist(fullfile(out, names{k}), 'file') == 2 && ...
        isa(imread(fullfile(out, names{k})), 'uint8');
end
record('E1', all_there, sprintf('%s | %d images', err, numel(names)));

limits_ok = true;
full_range = true;
for v = 1:2
    in_v = names(contains(names, sprintf('_view%d_', v)));
    vals = cellfun(@(n) reshape(imread(fullfile(src, n)), [], 1), in_v, 'UniformOutput', false);
    [lo, hi] = rabbit_sfm_build.stretch_limits(vertcat(vals{:}), [1 99.5]);
    for k = 1:numel(in_v)
        a = imread(fullfile(out, in_v{k}));
        limits_ok = limits_ok && isequal(a, rabbit_sfm_build.stretch_u8(imread(fullfile(src, in_v{k})), lo, hi));
        full_range = full_range && numel(unique(a)) > 200;
    end
end
record('E2', limits_ok, 'copies equal stretch_u8 with the per-view limits');
record('E3', full_range, 'more than 200 grey levels per copy');

[ok8, ~, out8, note8] = tab.eight_bit_images(out, fullfile(root, 'again'));
record('E4', ok8 && strcmp(out8, out) && isempty(note8) && ~isfolder(fullfile(root, 'again')), out8);

record('E5', contains(note, 'uint16') && contains(note, out) && contains(note, 'view 1') && ...
    contains(note, 'view 2'), note);

% COLMAP layout: view<k>/<name> without the _view<k>_ part
src6 = fullfile(root, 'colmap_layout');
mkdir(fullfile(src6, 'view1')); mkdir(fullfile(src6, 'view2'));
imwrite(uint16(35 + round(1000 * rand(30, 30))), fullfile(src6, 'view1', '0000.tiff'));
imwrite(uint16(2000 + round(1000 * rand(30, 30))), fullfile(src6, 'view2', '0000.tiff'));
[ok6, ~, out6, note6] = tab.eight_bit_images(src6, fullfile(root, 'colmap_layout_8bit'));
a6 = imread(fullfile(out6, 'view2', '0000.tiff'));
record('E6', ok6 && isa(a6, 'uint8') && numel(unique(a6)) > 200 && contains(note6, 'view1 ') && ...
    contains(note6, 'view2 '), note6);

fprintf('PROBE_EIGHT_BIT_IMAGES RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0, error('PROBE_FAIL probe_eight_bit_images'); end
fprintf('PROBE_OK probe_eight_bit_images %d/0\n', pass);

    function record(name, condition, detail)
        if condition, pass = pass + 1; result = 'PASS'; else, fail = fail + 1; result = 'FAIL'; end
        fprintf('  %s %s %s\n', name, result, detail);
    end
end
